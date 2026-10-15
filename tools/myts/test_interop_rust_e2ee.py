"""Cross-check of the Rust encrypted-send engine (`tslib-myts`) against the pinned libolm.

The peer is a libolm account; everything the Rust engine produces (device keys, signed
one-time and fallback keys, the Olm key share, the Megolm room event) is verified with
libolm only, and the signed keys libolm produced are accepted and claimed by Rust.
Offline and synthetic: the Rust side is the `e2ee_interop` example, which has a fake
server inside it and never touches the network. No accounts, profiles or secrets.

Run from the repository root, without network:
    unshare -Urn captures/myts/.venv/bin/python -I -m unittest discover \
        -s tools/myts -p 'test_interop_rust_e2ee.py'
"""
import ctypes as c
import json
import os
import re
import secrets
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from research_olm import Object, ResearchOlm

RUST_REPO = Path(__file__).resolve().parents[3] / 'ts6-lib'
DOMAIN = 'example.invalid'
PEER_USER = '@libolm:' + DOMAIN
PEER_DEVICE = 'LIBOLMDEV'
ROOM = '!interop:' + DOMAIN
ALGORITHMS = ['m.olm.v1.curve25519-aes-sha2', 'm.megolm.v1.aes-sha2']


def one_time_key(olm, account):
    """One libolm one-time key: (key id without prefix, curve25519 key)."""
    lib = olm.lib
    n = lib.olm_account_generate_one_time_keys_random_length(account.ptr, 1)
    account.check(lib.olm_account_generate_one_time_keys(
        account.ptr, 1, c.create_string_buffer(secrets.token_bytes(n)), n))
    keys = json.loads(account.output('olm_account_one_time_keys'))['curve25519']
    return next(iter(keys.items()))


def decrypt_prekey(olm, account, sender_curve, message):
    """What a libolm client does with an Olm key share: new inbound session, decrypt."""
    lib = olm.lib
    kind, body = message['type'], message['body'].encode()
    sender = sender_curve.encode()
    with Object(olm, 'session') as session:
        session.check(lib.olm_create_inbound_session_from(
            session.ptr, account.ptr, c.create_string_buffer(sender), len(sender),
            c.create_string_buffer(body), len(body)))
        size = session.check(lib.olm_decrypt_max_plaintext_length(
            session.ptr, kind, c.create_string_buffer(body), len(body)))
        out = c.create_string_buffer(size)
        length = session.check(lib.olm_decrypt(
            session.ptr, kind, c.create_string_buffer(body), len(body), out, size))
        return out.raw[:length].decode('utf-8')


def tamper(signature):
    """A different but still well-formed base64 signature."""
    return ('A' if signature[0] != 'A' else 'B') + signature[1:]


class RustInterop(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if shutil.which('cargo') is None:
            raise unittest.SkipTest('cargo not found: Rust interop checks not run')
        if not (RUST_REPO / 'Cargo.toml').is_file():
            raise unittest.SkipTest('ts6-lib checkout not found at ' + str(RUST_REPO))
        cls.olm = ResearchOlm()

    def run_rust(self, texts, *, tamper_otk=False):
        """Plays the sends in Rust against a libolm peer; returns (peer account, output)."""
        olm = self.olm
        account = olm.account()
        self.addCleanup(account.close)
        otk_id, otk = one_time_key(olm, account)
        ids = account.identities()
        device_keys = account.sign({
            'user_id': PEER_USER, 'device_id': PEER_DEVICE, 'algorithms': ALGORITHMS,
            'keys': {'curve25519:' + PEER_DEVICE: ids['curve25519'],
                     'ed25519:' + PEER_DEVICE: ids['ed25519']},
        }, PEER_USER, PEER_DEVICE)
        otk_object = account.sign({'key': otk}, PEER_USER, PEER_DEVICE)
        if tamper_otk:
            sigs = otk_object['signatures'][PEER_USER]
            sigs['ed25519:' + PEER_DEVICE] = tamper(sigs['ed25519:' + PEER_DEVICE])
        with tempfile.TemporaryDirectory() as tmp:
            source, target = Path(tmp, 'in.json'), Path(tmp, 'out.json')
            source.write_text(json.dumps({
                'domain': DOMAIN, 'username': 'rusty', 'room': ROOM,
                'peer_user': PEER_USER, 'peer_device': PEER_DEVICE,
                'peer_device_keys': device_keys, 'peer_otk_id': otk_id,
                'peer_otk': otk_object, 'texts': texts,
            }))
            done = subprocess.run(
                ['cargo', 'run', '--offline', '--quiet', '-p', 'tslib-myts',
                 '--example', 'e2ee_interop', '--', str(source), str(target)],
                cwd=RUST_REPO, capture_output=True, text=True, timeout=900,
                env={**os.environ, 'CARGO_NET_OFFLINE': 'true'})
            if done.returncode != 0:
                self.fail('e2ee_interop failed (not skipped):\n' + done.stderr[-4000:])
            return account, json.loads(target.read_text())

    def test_rust_output_is_accepted_by_libolm(self):
        olm, text = self.olm, 'hello from rust ✓'
        account, out = self.run_rust([text])
        user = out['our_user']
        self.assertEqual(out['actions'], [
            'keys_upload', 'keys_query', 'keys_claim', 'share_keys', 'send_encrypted'])
        self.assertEqual(out['outcomes'][-1]['action'], 'done')

        # Our device keys, one-time keys and fallback key, verified by libolm.
        device_keys = out['upload']['device_keys']
        device = device_keys['device_id']
        ed = device_keys['keys']['ed25519:' + device]
        curve = device_keys['keys']['curve25519:' + device]
        self.assertEqual(device_keys['user_id'], user)
        self.assertEqual(device_keys['algorithms'], ALGORITHMS)
        self.assertEqual(sorted(device_keys['keys']),
                         ['curve25519:' + device, 'ed25519:' + device])
        olm.verify(device_keys, user, device, ed)
        one_time = out['upload']['one_time_keys']
        self.assertEqual(len(one_time), 50)
        for key_id, signed in one_time.items():
            self.assertTrue(key_id.startswith('signed_curve25519:'))
            self.assertEqual(sorted(signed), ['key', 'signatures'])
            olm.verify(signed, user, device, ed)
        fallback = out['upload']['fallback_keys']
        self.assertEqual(len(fallback), 1)
        for key_id, signed in fallback.items():
            self.assertTrue(key_id.startswith('signed_curve25519:'))
            self.assertIs(signed['fallback'], True)
            olm.verify(signed, user, device, ed)

        # The claim Rust made for libolm's device, and the key share that came out of it.
        self.assertEqual(out['claims'], [
            {'one_time_keys': {PEER_USER: {PEER_DEVICE: 'signed_curve25519'}},
             'timeout': out['claims'][0]['timeout']}])
        self.assertEqual(len(out['to_device']), 1)
        share = out['to_device'][0]['body']
        self.assertEqual(list(share), ['messages'])
        self.assertEqual(list(share['messages']), [PEER_USER])
        self.assertEqual(list(share['messages'][PEER_USER]), [PEER_DEVICE])
        wrapper = share['messages'][PEER_USER][PEER_DEVICE]
        self.assertEqual(sorted(wrapper), [
            'algorithm', 'ciphertext', 'device_id', 'sender_key', 'session_id'])
        self.assertEqual(wrapper['algorithm'], ALGORITHMS[0])
        self.assertEqual(wrapper['sender_key'], curve)
        self.assertEqual(wrapper['device_id'], device)
        peer_curve = account.identities()['curve25519']
        self.assertEqual(list(wrapper['ciphertext']), [peer_curve])
        message = wrapper['ciphertext'][peer_curve]
        self.assertEqual(sorted(message), ['body', 'type'])
        self.assertIs(type(message['type']), int)
        self.assertEqual(message['type'], 0, 'first message of a session is a pre-key message')
        print('olm body padded base64:', message['body'].endswith('='))

        # libolm opens it (this also proves the claimed key was libolm's own one-time key).
        plain = decrypt_prekey(olm, account, curve, message)
        self.assertRegex(plain, r'"chain_index":\s*\d+[,}]')
        payload = json.loads(plain)
        self.assertEqual(sorted(payload), [
            'content', 'keys', 'recipient', 'recipient_keys', 'sender', 'sender_device', 'type'])
        self.assertEqual(payload['type'], 'm.room_key')
        self.assertEqual(payload['sender'], user)
        self.assertEqual(payload['sender_device'], device)
        self.assertEqual(payload['keys'], {'ed25519': ed})
        self.assertEqual(payload['recipient'], PEER_USER)
        self.assertEqual(payload['recipient_keys'],
                         {'ed25519': account.identities()['ed25519']})
        content = payload['content']
        self.assertEqual(sorted(content), [
            'algorithm', 'chain_index', 'room_id', 'session_id', 'session_key'])
        self.assertEqual(content['algorithm'], ALGORITHMS[1])
        self.assertEqual(content['room_id'], ROOM)
        self.assertIs(type(content['chain_index']), int)
        self.assertEqual(content['chain_index'], 0)
        self.assertEqual(wrapper['session_id'], content['session_id'])

        # libolm builds the Megolm session from the shared key and reads the room event.
        event = out['events'][0]['body']
        self.assertEqual(sorted(event), [
            'algorithm', 'ciphertext', 'device_id', 'sender_key', 'session_id'])
        self.assertEqual(event['algorithm'], ALGORITHMS[1])
        self.assertEqual(event['sender_key'], curve)
        self.assertEqual(event['device_id'], device)
        self.assertEqual(event['session_id'], content['session_id'])
        with olm.inbound(content['session_key'].encode()) as inbound:
            self.assertEqual(inbound.session_id(), content['session_id'])
            self.assertEqual(inbound.first_index(), content['chain_index'])
            decoded, index = inbound.decrypt(event['ciphertext'].encode())
        self.assertEqual(index, 0)
        inner = json.loads(decoded)
        self.assertEqual(sorted(inner), ['content', 'room_id', 'type'])
        self.assertEqual(inner['room_id'], ROOM)
        self.assertEqual(inner['type'], 'm.room.message')
        self.assertEqual(inner['content'], {'msgtype': 'm.text', 'body': text})

    def test_second_message_continues_the_same_megolm_session(self):
        olm = self.olm
        account, out = self.run_rust(['first', 'second'])
        self.assertEqual(out['actions'], [
            'keys_upload', 'keys_query', 'keys_claim', 'share_keys', 'send_encrypted',
            'send_encrypted'])
        self.assertEqual(len(out['to_device']), 1, 'the key is shared once')
        self.assertEqual(len(out['events']), 2)
        device_keys = out['upload']['device_keys']
        device = device_keys['device_id']
        message = out['to_device'][0]['body']['messages'][PEER_USER][PEER_DEVICE]
        message = message['ciphertext'][account.identities()['curve25519']]
        key = json.loads(decrypt_prekey(
            olm, account, device_keys['keys']['curve25519:' + device], message))['content']
        with olm.inbound(key['session_key'].encode()) as inbound:
            for expected, event in enumerate(out['events']):
                self.assertEqual(event['body']['session_id'], key['session_id'])
                decoded, index = inbound.decrypt(event['body']['ciphertext'].encode())
                self.assertEqual(index, expected)
                self.assertEqual(json.loads(decoded)['content']['body'],
                                 ['first', 'second'][expected])

    def test_a_tampered_one_time_key_signature_gets_no_share(self):
        account, out = self.run_rust(['must not be sent'], tamper_otk=True)
        self.assertEqual(out['actions'], ['keys_upload', 'keys_query', 'keys_claim'])
        self.assertEqual(len(out['claims']), 1, 'the claim itself was made')
        self.assertEqual(out['to_device'], [], 'no key share without a valid one-time key')
        self.assertEqual(out['events'], [], 'nothing is sent without a recipient')
        last = out['outcomes'][-1]
        self.assertEqual((last['action'], last['code']), ('fail', 'no_recipients'))


if __name__ == '__main__':
    unittest.main()
