"""Narrow libolm adapter for explicitly authorized disposable-account research.

Not a production Matrix client. No network, profiles or secret diagnostics.
Uses the pinned desktop libolm and OS randomness, never synthetic entropy.
Encrypted pickles require a caller-provided secret key; no key is persisted here.
"""
import ctypes as c
import json
import secrets

from megolm_synthetic import Olm, Session, ERROR


def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True,
                      separators=(',', ':'), allow_nan=False).encode('utf-8')


def room_key_content(room, session_id, sharing_key, chain_index):
    """TeamSpeak requires a numeric chain_index even on direct m.room_key events.

    This is an additional native-client requirement, not a universal Matrix
    requirement. The actual libolm sharing key may start later than index zero.
    """
    if (type(chain_index) is not int or not 0 <= chain_index <= 0xffffffff
            or any(not isinstance(v, str) or not v or len(v) > 4096
                   for v in (room, session_id, sharing_key))):
        raise ValueError('invalid room-key metadata')
    return {'algorithm': 'm.megolm.v1.aes-sha2', 'room_id': room,
            'session_id': session_id, 'session_key': sharing_key,
            'chain_index': chain_index}


class ResearchOlm(Olm):
    def __init__(self):
        super().__init__()
        p, s = c.c_void_p, c.c_size_t
        for kind in ('account', 'session', 'utility'):
            self.bind('olm_' + kind + '_size', s, [])
            self.bind('olm_' + kind, p, [p])
            self.bind('olm_clear_' + kind, s, [p])
        self.bind('olm_create_account_random_length', s, [p])
        self.bind('olm_create_account', s, [p, p, s])
        self.bind('olm_outbound_group_session_message_index', c.c_uint32, [p])
        self.bind('olm_account_identity_keys_length', s, [p])
        self.bind('olm_account_identity_keys', s, [p, p, s])
        self.bind('olm_account_signature_length', s, [p])
        self.bind('olm_account_sign', s, [p, p, s, p, s])
        self.bind('olm_ed25519_verify', s, [p, p, s, p, s, p, s])
        self.bind('olm_create_outbound_session_random_length', s, [p])
        self.bind('olm_create_outbound_session', s, [p, p, p, s, p, s, p, s])
        self.bind('olm_create_inbound_session_from', s, [p, p, p, s, p, s])
        self.bind('olm_encrypt_message_type', s, [p])
        self.bind('olm_encrypt_random_length', s, [p])
        self.bind('olm_encrypt_message_length', s, [p, s])
        self.bind('olm_encrypt', s, [p, p, s, p, s, p, s])
        self.bind('olm_decrypt_max_plaintext_length', s, [p, s, p, s])
        self.bind('olm_decrypt', s, [p, s, p, s, p, s])
        self.bind('olm_account_generate_one_time_keys_random_length', s, [p, s])
        self.bind('olm_account_generate_one_time_keys', s, [p, s, p, s])
        self.bind('olm_account_one_time_keys_length', s, [p])
        self.bind('olm_account_one_time_keys', s, [p, p, s])
        for kind in ('account', 'session', 'outbound_group_session'):
            self.bind('olm_pickle_' + kind + '_length', s, [p])
            self.bind('olm_pickle_' + kind, s, [p, p, s, p, s])
            self.bind('olm_unpickle_' + kind, s, [p, p, s, p, s])

    def outbound(self):
        session = Session(self, 'outbound')
        try:
            n = self.lib.olm_init_outbound_group_session_random_length(session.ptr)
            session.check(self.lib.olm_init_outbound_group_session(
                session.ptr, c.create_string_buffer(secrets.token_bytes(n)), n))
            return session
        except Exception:
            session.close()
            raise

    def account(self, pickle=None, key=None):
        account = Object(self, 'account')
        try:
            if pickle is None:
                n = self.lib.olm_create_account_random_length(account.ptr)
                account.check(self.lib.olm_create_account(
                    account.ptr, c.create_string_buffer(secrets.token_bytes(n)), n))
            else:
                self.unpickle(account, pickle, key)
            return account
        except Exception:
            account.close()
            raise

    def pickle(self, obj, key):
        if not isinstance(key, bytes) or len(key) != 32:
            raise ValueError('invalid pickle secret')
        stem = 'olm_pickle_' + getattr(obj, 'kind', 'outbound_group_session')
        n = getattr(self.lib, stem + '_length')(obj.ptr)
        out = c.create_string_buffer(n)
        length = obj.check(getattr(self.lib, stem)(obj.ptr,
            c.create_string_buffer(key), len(key), out, n))
        return out.raw[:length].decode('ascii')

    def unpickle(self, obj, value, key):
        if not isinstance(key, bytes) or len(key) != 32 or not 0 < len(value) < 65536:
            raise ValueError('invalid pickle input')
        data = value.encode('ascii')
        obj.check(getattr(self.lib, 'olm_unpickle_' + getattr(obj, 'kind', 'outbound_group_session'))(obj.ptr,
            c.create_string_buffer(key), len(key), c.create_string_buffer(data), len(data)))

    def verify(self, value, user, device, signing_key):
        signature = value.get('signatures', {}).get(user, {}).get('ed25519:' + device)
        if not isinstance(signature, str) or len(signature) > 256:
            raise ValueError('missing signature')
        payload = canonical({k: v for k, v in value.items() if k not in ('unsigned', 'signatures')})
        public, signature = signing_key.encode('ascii'), signature.encode('ascii')
        with Object(self, 'utility') as utility:
            utility.check(self.lib.olm_ed25519_verify(utility.ptr,
                c.create_string_buffer(public), len(public), c.create_string_buffer(payload), len(payload),
                c.create_string_buffer(signature), len(signature)))

    def pair(self, account, curve, one_time):
        session = Object(self, 'session')
        try:
            curve, one_time = curve.encode('ascii'), one_time.encode('ascii')
            n = self.lib.olm_create_outbound_session_random_length(session.ptr)
            session.check(self.lib.olm_create_outbound_session(session.ptr, account.ptr,
                c.create_string_buffer(curve), len(curve), c.create_string_buffer(one_time), len(one_time),
                c.create_string_buffer(secrets.token_bytes(n)), n))
            return session
        except Exception:
            session.close()
            raise

    def encrypt_pair(self, session, value):
        data = canonical(value)
        kind = session.check(self.lib.olm_encrypt_message_type(session.ptr))
        n = self.lib.olm_encrypt_random_length(session.ptr)
        size = self.lib.olm_encrypt_message_length(session.ptr, len(data))
        out = c.create_string_buffer(size)
        length = session.check(self.lib.olm_encrypt(session.ptr,
            c.create_string_buffer(data), len(data), c.create_string_buffer(secrets.token_bytes(n)), n,
            out, size))
        return {'type': kind, 'body': out.raw[:length].decode('ascii')}


class Object:
    def __init__(self, olm, kind):
        self.olm, self.kind = olm, kind
        self.memory = c.create_string_buffer(getattr(olm.lib, 'olm_' + kind + '_size')())
        self.ptr = getattr(olm.lib, 'olm_' + kind)(self.memory)

    def check(self, result):
        if result == ERROR:
            raise ValueError('libolm operation failed')
        return result

    def output(self, stem):
        n = getattr(self.olm.lib, stem + '_length')(self.ptr)
        out = c.create_string_buffer(n)
        length = self.check(getattr(self.olm.lib, stem)(self.ptr, out, n))
        return out.raw[:length]

    def identities(self):
        return json.loads(self.output('olm_account_identity_keys'))

    def sign(self, value, user, device):
        data = canonical({k: v for k, v in value.items() if k not in ('unsigned', 'signatures')})
        n = self.olm.lib.olm_account_signature_length(self.ptr)
        out = c.create_string_buffer(n)
        length = self.check(self.olm.lib.olm_account_sign(
            self.ptr, c.create_string_buffer(data), len(data), out, n))
        return {**value, 'signatures': {user: {'ed25519:' + device: out.raw[:length].decode('ascii')}}}

    def close(self):
        if self.ptr:
            getattr(self.olm.lib, 'olm_clear_' + self.kind)(self.ptr)
            self.ptr = None

    def __enter__(self):
        return self

    def __exit__(self, *_):
        self.close()
