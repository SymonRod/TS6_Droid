"""Real libolm keys/messages, but synthetic JSON dispatch (not native Go import)."""

import base64
import json
import unittest

from chat_session_vectors import unwrap, wrap
from megolm_synthetic import Olm, OlmError, cloud_plaintext, event


class MegolmSyntheticTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # This optional native suite fails closed if the supplied binary is absent
        # or changed. It must not silently fall back to another installed libolm.
        cls.olm = Olm()

    def test_synthetic_cloud_roundtrip_decrypts_messages_for_all_types(self):
        with self.olm.outbound() as sender:
            sharing_key, sid = sender.sharing_key(), sender.session_id()
            messages = [sender.encrypt(event(i)) for i in range(4)]
        with self.olm.inbound(sharing_key) as receiver:
            exported = receiver.export(0)
        for kind, key in ((1, sharing_key), (2, sharing_key), (3, exported)):
            with self.subTest(kind=kind):
                # Tests the envelope and libolm path; JSON dispatch here is OUR
                # reconstruction, not a native TeamSpeak importer oracle.
                restored = json.loads(unwrap(wrap(cloud_plaintext(sid, key, kind))))
                with self.olm.inbound(restored["group_session_key"].encode(),
                                      exported=restored["type"] == 3) as fresh:
                    self.assertEqual(fresh.session_id(), sid)
                    self.assertEqual(fresh.first_index(), 0)
                    for i, message in enumerate(messages):
                        self.assertEqual(fresh.decrypt(message), (event(i), i))

    def test_sharing_and_exported_key_formats_are_not_interchangeable(self):
        with self.olm.outbound() as sender:
            sharing_key = sender.sharing_key()
        with self.olm.inbound(sharing_key) as receiver:
            exported = receiver.export(0)
        for key, expected_length, expected_version in ((sharing_key, 229, 2), (exported, 165, 1)):
            decoded = base64.b64decode(key + b"=" * (-len(key) % 4), validate=True)
            self.assertEqual(len(decoded), expected_length)
            self.assertEqual(decoded[0], expected_version)
        with self.assertRaises(OlmError):
            self.olm.inbound(sharing_key, exported=True)
        with self.assertRaises(OlmError):
            self.olm.inbound(exported)

    def test_nonzero_export_cannot_decrypt_earlier_messages(self):
        with self.olm.outbound() as sender:
            sharing_key = sender.sharing_key()
            messages = [sender.encrypt(event(i)) for i in range(4)]
        with self.olm.inbound(sharing_key) as receiver:
            exported = receiver.export(2)
        with self.olm.inbound(exported, exported=True) as fresh:
            self.assertEqual(fresh.first_index(), 2)
            for i in (0, 1):
                with self.subTest(index=i), self.assertRaisesRegex(OlmError, "UNKNOWN_MESSAGE_INDEX"):
                    fresh.decrypt(messages[i])
            for i in (2, 3):
                self.assertEqual(fresh.decrypt(messages[i]), (event(i), i))

    def test_sharing_key_can_also_begin_at_nonzero_index(self):
        with self.olm.outbound() as sender:
            earlier = sender.encrypt(event(0))
            later_key = sender.sharing_key()
            later = sender.encrypt(event(1))
        with self.olm.inbound(later_key) as fresh:
            self.assertEqual(fresh.first_index(), 1)
            with self.assertRaisesRegex(OlmError, "UNKNOWN_MESSAGE_INDEX"):
                fresh.decrypt(earlier)
            self.assertEqual(fresh.decrypt(later), (event(1), 1))

    def test_libolm_verification_is_not_device_trust(self):
        with self.olm.outbound() as sender:
            sharing_key = sender.sharing_key()
            message = sender.encrypt(event(0))
        with self.olm.inbound(sharing_key) as receiver:
            self.assertTrue(receiver.verified())
            exported = receiver.export(0)
        with self.olm.inbound(exported, exported=True) as fresh:
            self.assertFalse(fresh.verified())
            self.assertEqual(fresh.decrypt(message), (event(0), 0))
            self.assertTrue(fresh.verified())

    def test_libolm_alone_does_not_prevent_replay(self):
        with self.olm.outbound() as sender:
            key = sender.sharing_key()
            message = sender.encrypt(event(0))
        with self.olm.inbound(key) as fresh:
            self.assertEqual(fresh.decrypt(message), fresh.decrypt(message))

    def test_tampered_ciphertext_rejected(self):
        with self.olm.outbound() as sender:
            key = sender.sharing_key()
            message = sender.encrypt(event(0))
        raw = bytearray(base64.b64decode(message + b"=" * (-len(message) % 4)))
        raw[-1] ^= 1
        with self.olm.inbound(key) as fresh:
            with self.assertRaises(OlmError):
                fresh.decrypt(base64.b64encode(raw).rstrip(b"="))


if __name__ == "__main__":
    unittest.main()
