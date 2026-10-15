"""Synthetic-only tests for the live probe's validation and private state."""

import base64
import json
import os
import stat
import tempfile
import unittest
from pathlib import Path

from chat_session_vectors import ACCOUNT_KEY, wrap
from history_probe_support import (PrivateState, ProbeError, capture_login,
                                   decrypt_cloud_event, encrypted_event, event_shape_summary,
                                   password_delete_auth, strict_json, sync_summary)
from megolm_synthetic import Olm, OlmError, ROOM, cloud_plaintext, event


class HistoryProbeTests(unittest.TestCase):
    def test_json_rejects_duplicate_nonfinite_and_oversized(self):
        for value in (b'{"type":1,"type":3}', b'{"a":NaN}', b'not json'):
            with self.subTest(value=value), self.assertRaises(ProbeError):
                strict_json(value)
        with self.assertRaises(ProbeError):
            strict_json(b'"large"', 3)

    def test_sync_distinguishes_memberships_and_direct_mapping(self):
        summary, events, rooms, direct = sync_summary({"next_batch": "synthetic",
            "rooms": {"join": {ROOM: {"timeline": {"events": []}}},
                      "invite": {"!invite:example.invalid": {}}},
            "account_data": {"events": [{"type": "m.direct", "content": {
                "@synthetic:example.invalid": [ROOM]}}]}})
        self.assertEqual((summary["join"], summary["invite"], summary["leave"]), (1, 1, 0))
        self.assertTrue(summary["direct_mapping_present"])
        self.assertEqual(direct, {ROOM})
        self.assertEqual(events, [])
        self.assertEqual(rooms[ROOM], "join")

    def test_sync_room_bounds_and_shape(self):
        for rooms in ({"join": []}, {"join": {str(i): {} for i in range(33)}}):
            with self.assertRaises(ProbeError):
                sync_summary({"next_batch": "synthetic", "rooms": rooms})

    def test_encrypted_event_requires_associations(self):
        self.assertIsNone(encrypted_event(ROOM, {"type": "m.room.message"}))
        with self.assertRaises(ProbeError):
            encrypted_event(ROOM, {"type": "m.room.encrypted", "content": {
                "algorithm": "m.megolm.v1.aes-sha2"}})

    def test_shapes_never_print_arbitrary_event_types_or_messages(self):
        summary = event_shape_summary([{"type": "synthetic-sensitive-value", "content": {
            "body": "synthetic-sensitive-body", "untrusted-field": "synthetic-sensitive-value"}},
            {"type": "m.room.message", "content": {"msgtype": "m.text", "body": "synthetic-sensitive-body"}}])
        self.assertEqual(summary["types"], {"other": 1, "m.room.message": 1})
        self.assertEqual(summary["text_message_shape"], 1)
        serialized = json.dumps(summary)
        for forbidden in ("synthetic-sensitive-value", "synthetic-sensitive-body", "untrusted-field"):
            self.assertNotIn(forbidden, serialized)

    def test_private_record_and_incomplete_login_survive(self):
        with tempfile.TemporaryDirectory() as directory:
            state = PrivateState.create(Path(directory) / "research")
            record = {"expected_user_id": "@synthetic:example.invalid", "phase": "intent"}
            state.write(record)
            with self.assertRaises(ProbeError):
                capture_login(state, record, 200, {"access_token": "synthetic-only-token"})
            self.assertEqual(state.read()["access_token"], "synthetic-only-token")
            self.assertEqual(stat.S_IMODE(state.directory.stat().st_mode), 0o700)
            self.assertEqual(stat.S_IMODE((state.directory / "state.json").stat().st_mode), 0o600)

    def test_wrong_account_is_retained_but_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            state = PrivateState.create(Path(directory) / "research")
            record = {"expected_user_id": "@expected:example.invalid"}
            with self.assertRaises(ProbeError):
                capture_login(state, record, 200, {"user_id": "@other:example.invalid",
                    "device_id": "SYNTHETIC", "access_token": "synthetic-only-token"})
            self.assertEqual(state.read()["device_id"], "SYNTHETIC")

    def test_malformed_device_field_does_not_lose_token(self):
        with tempfile.TemporaryDirectory() as directory:
            state = PrivateState.create(Path(directory) / "research")
            record = {"expected_user_id": "@synthetic:example.invalid"}
            with self.assertRaises(ProbeError):
                capture_login(state, record, 200, {"access_token": "synthetic-only-token",
                    "device_id": None, "user_id": "@synthetic:example.invalid"})
            self.assertEqual(state.read()["access_token"], "synthetic-only-token")

    def test_unsafe_directory_and_symlink_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            unsafe = Path(directory) / "unsafe"
            unsafe.mkdir(mode=0o755)
            with self.assertRaises(ProbeError):
                PrivateState(unsafe)
            link = Path(directory) / "link"
            link.symlink_to(directory)
            with self.assertRaises(ProbeError):
                PrivateState(link)

    def test_unsafe_state_file_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            state = PrivateState.create(Path(directory) / "research")
            state.write({"synthetic": True})
            os.chmod(state.directory / "state.json", 0o644)
            with self.assertRaises(ProbeError):
                state.read()

    def test_uia_only_advertised_single_password_flow(self):
        self.assertIsNone(password_delete_auth({"flows": [{"stages": ["m.login.sso"]}]},
                                               "@s:example.invalid", "synthetic"))
        auth = password_delete_auth({"session": "synthetic-session", "flows": [
            {"stages": ["m.login.password"]}]}, "@s:example.invalid", "synthetic")
        self.assertEqual(auth["type"], "m.login.password")
        self.assertEqual(auth["session"], "synthetic-session")


class HistoryRecoveryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.olm = Olm()

    def fixture(self, kind=1, first=0):
        with self.olm.outbound() as sender:
            for index in range(first):
                sender.encrypt(event(index))
            key, sid = sender.sharing_key(), sender.session_id()
            message = sender.encrypt(event(first))
        if kind == 3:
            with self.olm.inbound(key) as receive:
                key = receive.export(first)
        plain = json.loads(cloud_plaintext(sid, key, kind, first if kind == 3 else 0))
        encrypted = encrypted_event(ROOM, {"event_id": "$synthetic-event",
            "sender": "@synthetic:example.invalid", "type": "m.room.encrypted", "content": {
                "algorithm": "m.megolm.v1.aes-sha2", "sender_key": plain["c25519"],
                "session_id": sid, "ciphertext": message.decode()}})
        return plain, encrypted

    def recover(self, plain, encrypted):
        return decrypt_cloud_event(wrap(json.dumps(plain).encode()).decode(),
                                   ACCOUNT_KEY, encrypted, self.olm)

    def test_all_types_decrypt_without_sender_trust_claim(self):
        for kind in (1, 2, 3):
            with self.subTest(kind=kind):
                result = self.recover(*self.fixture(kind))
                self.assertTrue(result["decrypted"])
                self.assertFalse(result["verified_sender_identity"])
                self.assertEqual(result["message_index"], 0)

    def test_actual_nonzero_sharing_index_is_observed(self):
        result = self.recover(*self.fixture(first=2))
        self.assertEqual(result["json_chain_index"], 0)
        self.assertEqual(result["first_known_index"], 2)
        self.assertEqual(result["message_index"], 2)

    def test_cloud_observer_contains_only_fixed_boolean_metadata(self):
        plain, encrypted = self.fixture()
        observed = []
        decrypt_cloud_event(wrap(json.dumps(plain).encode()).decode(), ACCOUNT_KEY,
                            encrypted, self.olm,
                            observe=lambda label, values: observed.append((label, values)))
        self.assertEqual(observed[0][0], "cloud_validation_shape")
        self.assertTrue(all(type(value) is bool for value in observed[0][1].values()))
        for forbidden in (plain["group_session_key"], plain["sender"], encrypted["content"]["ciphertext"]):
            self.assertNotIn(forbidden, json.dumps(observed))

    def test_explicit_own_outbound_empty_metadata_can_decrypt_without_trust(self):
        plain, encrypted = self.fixture(kind=1)
        own = encrypted["sender"]
        for field in ("sender", "c25519", "ed25519"):
            plain[field] = ""
        with self.assertRaises(ProbeError):
            self.recover(plain, encrypted)  # Default remains strict.
        result = decrypt_cloud_event(wrap(json.dumps(plain).encode()).decode(), ACCOUNT_KEY,
                                     encrypted, self.olm, expected_user_id=own)
        self.assertTrue(result["decrypted"])
        self.assertFalse(result["sender_metadata_matched"])
        self.assertFalse(result["verified_sender_identity"])
        self.assertEqual(result["metadata_policy"], "empty_own_outbound")

    def test_empty_metadata_exception_is_not_for_inbound_or_other_user(self):
        for kind in (1, 2, 3):
            plain, encrypted = self.fixture(kind=kind)
            for field in ("sender", "c25519", "ed25519"):
                plain[field] = ""
            own = "@other:example.invalid" if kind == 1 else encrypted["sender"]
            with self.subTest(kind=kind), self.assertRaises(ProbeError):
                decrypt_cloud_event(wrap(json.dumps(plain).encode()).decode(), ACCOUNT_KEY,
                                    encrypted, self.olm, expected_user_id=own)

    def test_empty_metadata_exception_rejects_missing_partial_and_null_fields(self):
        plain, encrypted = self.fixture()
        for field in ("sender", "c25519", "ed25519"):
            plain[field] = ""
        for field in ("sender", "c25519", "ed25519"):
            for value in (None, "synthetic-mismatch", 0):
                invalid = dict(plain, **{field: value})
                with self.subTest(field=field, value=value), self.assertRaises(ProbeError):
                    decrypt_cloud_event(wrap(json.dumps(invalid).encode()).decode(), ACCOUNT_KEY,
                                        encrypted, self.olm, expected_user_id=encrypted["sender"])
            invalid = dict(plain)
            del invalid[field]
            with self.assertRaises(ProbeError):
                decrypt_cloud_event(wrap(json.dumps(invalid).encode()).decode(), ACCOUNT_KEY,
                                    encrypted, self.olm, expected_user_id=encrypted["sender"])

    def test_empty_metadata_exception_still_checks_actual_session_and_room(self):
        plain, encrypted = self.fixture()
        for field in ("sender", "c25519", "ed25519"):
            plain[field] = ""
        plain["group_session_id"] = encrypted["content"]["session_id"] = "synthetic-wrong-session"
        with self.assertRaises(ProbeError):
            decrypt_cloud_event(wrap(json.dumps(plain).encode()).decode(), ACCOUNT_KEY,
                                encrypted, self.olm, expected_user_id=encrypted["sender"])

    def test_empty_metadata_exception_still_checks_signature_and_inner_room(self):
        for scenario in ("signature", "inner_room"):
            plain, encrypted = self.fixture()
            for field in ("sender", "c25519", "ed25519"):
                plain[field] = ""
            if scenario == "signature":
                ciphertext = encrypted["content"]["ciphertext"].encode()
                raw = bytearray(base64.b64decode(ciphertext + b"=" * (-len(ciphertext) % 4)))
                raw[-1] ^= 1
                encrypted["content"]["ciphertext"] = base64.b64encode(raw).rstrip(b"=").decode()
            else:
                with self.olm.outbound() as sender:
                    encrypted["content"]["ciphertext"] = sender.encrypt(json.dumps({
                        "room_id": "!wrong:example.invalid", "type": "m.room.message",
                        "content": {"body": "Synthetic only"}}).encode()).decode()
            with self.subTest(scenario=scenario), self.assertRaises((ProbeError, OlmError)):
                decrypt_cloud_event(wrap(json.dumps(plain).encode()).decode(), ACCOUNT_KEY,
                                    encrypted, self.olm, expected_user_id=encrypted["sender"])

    def test_exported_metadata_index_mismatch_rejected(self):
        plain, encrypted = self.fixture(kind=3, first=2)
        plain["chain_index"] = 0
        with self.assertRaises(ProbeError):
            self.recover(plain, encrypted)

    def test_outer_associations_types_and_sender_fail_closed(self):
        original, encrypted = self.fixture()
        for field, value in (("room_id", "!other:example.invalid"),
                             ("group_session_id", "wrong"), ("sender", "wrong"),
                             ("c25519", "wrong"), ("version", 1),
                             ("algorithm", "wrong"), ("type", True),
                             ("chain_index", True), ("chain_index", -1)):
            with self.subTest(field=field, value=value), self.assertRaises(ProbeError):
                self.recover(dict(original, **{field: value}), encrypted)

    def test_key_actual_session_mismatch_rejected(self):
        plain, encrypted = self.fixture()
        plain["group_session_id"] = encrypted["content"]["session_id"] = "synthetic-wrong-session"
        with self.assertRaises(ProbeError):
            self.recover(plain, encrypted)

    def test_exported_key_in_sharing_mode_rejected(self):
        plain, encrypted = self.fixture()
        with self.olm.outbound() as sender:
            sender.encrypt(event(0))
            key = sender.sharing_key()
        with self.olm.inbound(key) as receive:
            exported = receive.export(1)
        plain["group_session_key"] = exported.decode()
        with self.assertRaises(OlmError):
            self.recover(plain, encrypted)  # Export is invalid in type-1 init mode.

    def test_wrong_inner_room_rejected(self):
        plain, encrypted = self.fixture()
        with self.olm.outbound() as sender:
            encrypted["content"]["ciphertext"] = sender.encrypt(json.dumps({
                "room_id": "!wrong:example.invalid", "type": "m.room.message",
                "content": {"body": "Synthetic only"}}).encode()).decode()
        with self.assertRaises(ProbeError):
            self.recover(plain, encrypted)


if __name__ == "__main__":
    unittest.main()
