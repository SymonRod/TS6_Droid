"""Offline checks with ephemeral OS-random keys; no account or network access."""
import ctypes as c
import json
import unittest

from research_olm import ResearchOlm, Object, canonical, room_key_content
from megolm_synthetic import Session


class ResearchOlmTests(unittest.TestCase):
    def setUp(self):
        self.olm = ResearchOlm()

    def test_random_accounts_and_group_sessions_are_distinct(self):
        with self.olm.account() as a, self.olm.account() as b:
            self.assertNotEqual(a.identities(), b.identities())
        with self.olm.outbound() as a, self.olm.outbound() as b:
            self.assertNotEqual(a.session_id(), b.session_id())

    def test_direct_room_key_has_teamspeak_numeric_chain_index(self):
        with self.olm.outbound() as group:
            for index in range(3):
                group.encrypt(b'synthetic')
            actual = self.olm.lib.olm_outbound_group_session_message_index(group.ptr)
            value = room_key_content('!synthetic', group.session_id(), group.sharing_key().decode(), actual)
            self.assertEqual(value['chain_index'], 3)
            with self.olm.inbound(value['session_key'].encode()) as receive:
                self.assertEqual(receive.first_index(), 3)
            for invalid in (True, '3', -1, 0x100000000, None):
                with self.subTest(invalid=invalid), self.assertRaises(ValueError):
                    room_key_content('!synthetic', group.session_id(), value['session_key'], invalid)

    def test_signature_verification_and_tampering(self):
        with self.olm.account() as a:
            value = a.sign({'key': 'synthetic'}, '@a:example.invalid', 'A')
            self.olm.verify(value, '@a:example.invalid', 'A', a.identities()['ed25519'])
            value['key'] = 'changed'
            with self.assertRaises(ValueError):
                self.olm.verify(value, '@a:example.invalid', 'A', a.identities()['ed25519'])

    def test_encrypted_account_pickle_roundtrip_and_wrong_key(self):
        with self.olm.account() as a:
            value = self.olm.pickle(a, bytes(range(32)))
            with self.olm.account(value, bytes(range(32))) as b:
                self.assertEqual(a.identities(), b.identities())
            with self.assertRaises(ValueError):
                self.olm.account(value, bytes(32))

    def test_real_olm_key_delivery_then_megolm_nonzero_indices(self):
        lib = self.olm.lib
        with self.olm.account() as sender, self.olm.account() as recipient:
            n = lib.olm_account_generate_one_time_keys_random_length(recipient.ptr, 1)
            # Test entropy only for this recipient OTK; sender/session use OS randomness.
            recipient.check(lib.olm_account_generate_one_time_keys(
                recipient.ptr, 1, c.create_string_buffer(bytes(n)), n))
            otk = next(iter(json.loads(recipient.output('olm_account_one_time_keys'))['curve25519'].values()))
            with self.olm.pair(sender, recipient.identities()['curve25519'], otk) as pair:
                with self.olm.outbound() as group:
                    value = {'session_id': group.session_id(), 'session_key': group.sharing_key().decode()}
                    encrypted = self.olm.encrypt_pair(pair, value)
                    body = encrypted['body'].encode()
                    curve = sender.identities()['curve25519'].encode()
                    with Object(self.olm, 'session') as receive:
                        receive.check(lib.olm_create_inbound_session_from(receive.ptr, recipient.ptr,
                            c.create_string_buffer(curve), len(curve), c.create_string_buffer(body), len(body)))
                        size = receive.check(lib.olm_decrypt_max_plaintext_length(receive.ptr,
                            encrypted['type'], c.create_string_buffer(body), len(body)))
                        out = c.create_string_buffer(size)
                        length = receive.check(lib.olm_decrypt(receive.ptr, encrypted['type'],
                            c.create_string_buffer(body), len(body), out, size))
                        delivered = json.loads(out.raw[:length])
                    self.assertEqual(delivered, value)
                    with self.olm.inbound(delivered['session_key'].encode()) as inbound:
                        for index in range(3):
                            plain = canonical({'body': 'synthetic', 'index': index})
                            decoded, actual = inbound.decrypt(group.encrypt(plain))
                            self.assertEqual((decoded, actual), (plain, index))

    def test_group_pickle_preserves_advanced_ratchet(self):
        with self.olm.outbound() as group:
            sharing = group.sharing_key()
            group.encrypt(b'first')
            value = self.olm.pickle(group, bytes(range(32)))
            with Session(self.olm, 'outbound') as restored:
                self.olm.unpickle(restored, value, bytes(range(32)))
                self.assertEqual(group.session_id(), restored.session_id())
                with self.olm.inbound(sharing) as incoming:
                    self.assertEqual(incoming.decrypt(restored.encrypt(b'second')), (b'second', 1))


if __name__ == '__main__':
    unittest.main()
