"""Writes the synthetic libolm peer used by the Flutter encrypted-send tests.

The peer is a fake contact with two devices. For each device the fixture holds what a
real client publishes: libolm-signed `device_keys`, signed one-time keys and a signed
fallback key (the shape a homeserver hands out when one-time keys run out). A third
account signs a second, different `device_keys` for the first device ID, which is how
the tests present "a known device came back with other keys".

Everything is synthetic: random keys from the pinned libolm, a made-up user and device
IDs, no account, no network and no secret (private keys are never written).

Regenerate with (repository root):
    unshare -Urn captures/myts/.venv/bin/python -I tools/myts/generate_e2ee_peer_fixture.py \
        flutter/test/fixtures/e2ee_peer.json
"""
import ctypes as c
import json
import secrets
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from research_olm import ResearchOlm  # noqa: E402

PEER_USER = '@friend:example.invalid'
ALGORITHMS = ['m.olm.v1.curve25519-aes-sha2', 'm.megolm.v1.aes-sha2']
ONE_TIME_KEYS = 8


def generate(olm, account, count):
    """`count` fresh one-time keys: {key id without prefix: curve25519 key}."""
    lib = olm.lib
    n = lib.olm_account_generate_one_time_keys_random_length(account.ptr, count)
    account.check(lib.olm_account_generate_one_time_keys(
        account.ptr, count, c.create_string_buffer(secrets.token_bytes(n)), n))
    return json.loads(account.output('olm_account_one_time_keys'))['curve25519']


def device(olm, device_id):
    account = olm.account()
    try:
        ids = account.identities()
        keys = generate(olm, account, ONE_TIME_KEYS + 1)
        items = list(keys.items())
        fallback_id, fallback_key = items.pop()
        return {
            'device_keys': account.sign({
                'user_id': PEER_USER,
                'device_id': device_id,
                'algorithms': ALGORITHMS,
                'keys': {
                    'curve25519:' + device_id: ids['curve25519'],
                    'ed25519:' + device_id: ids['ed25519'],
                },
            }, PEER_USER, device_id),
            'one_time_keys': {
                'signed_curve25519:' + key_id: account.sign(
                    {'key': key}, PEER_USER, device_id)
                for key_id, key in items
            },
            'fallback_key': {
                'signed_curve25519:' + fallback_id: account.sign(
                    {'key': fallback_key, 'fallback': True}, PEER_USER, device_id),
            },
        }
    finally:
        account.close()


def main(target):
    olm = ResearchOlm()
    fixture = {
        'comment': 'Synthetic libolm peer for flutter tests; regenerate with '
                   'tools/myts/generate_e2ee_peer_fixture.py. No real account.',
        'peer_user': PEER_USER,
        'devices': {
            'FRIENDDEV': device(olm, 'FRIENDDEV'),
            'FRIENDDEV2': device(olm, 'FRIENDDEV2'),
        },
        # Same device ID, different identity keys (signed by a different account).
        'changed': {'FRIENDDEV': device(olm, 'FRIENDDEV')['device_keys']},
    }
    Path(target).write_text(json.dumps(fixture, indent=2, sort_keys=True) + '\n')


if __name__ == '__main__':
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
