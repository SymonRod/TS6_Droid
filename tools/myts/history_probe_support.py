"""Bounded research helpers, not production chat or a native Go import oracle.

Importing this module performs no network/account/profile access. Live callers
must obtain authorization separately. Diagnostics must never print input data.
"""

import json
import os
import secrets
import stat
from pathlib import Path

from chat_session_vectors import unwrap


class ProbeError(ValueError):
    """Only fixed, non-secret error messages may be used."""


def object_value(value):
    if not isinstance(value, dict):
        raise ProbeError("expected object")
    return value


def array_value(value, maximum=128):
    if not isinstance(value, list) or len(value) > maximum:
        raise ProbeError("invalid array or count bound")
    return value


def text(value, maximum=1024):
    if not isinstance(value, str) or not value or len(value) > maximum:
        raise ProbeError("invalid text or length bound")
    return value


def strict_json(data, maximum=2 * 1024 * 1024):
    if len(data) > maximum:
        raise ProbeError("JSON byte bound")

    def pairs(entries):
        result = {}
        for key, value in entries:
            if key in result:
                raise ProbeError("duplicate JSON key")
            result[key] = value
        return result

    def constant(_):
        raise ProbeError("nonfinite JSON number")

    try:
        return json.loads(data, object_pairs_hook=pairs, parse_constant=constant)
    except (ValueError, RecursionError, UnicodeError):
        raise ProbeError("invalid JSON") from None


def encrypted_event(room_id, value):
    value = object_value(value)
    if value.get("type") != "m.room.encrypted":
        return None
    content = object_value(value.get("content"))
    if content.get("algorithm") != "m.megolm.v1.aes-sha2":
        return None
    return {
        "room_id": text(room_id),
        "event_id": text(value.get("event_id")),
        "sender": text(value.get("sender")),
        "content": {
            "algorithm": content["algorithm"],
            "session_id": text(content.get("session_id")),
            "sender_key": text(content.get("sender_key")),
            "ciphertext": text(content.get("ciphertext"), 262144),
        },
    }


def event_shape_summary(events):
    """Only allowlisted protocol labels; never arbitrary types/values or bodies."""
    allowed = {"m.room.message", "m.room.encrypted", "m.room.member", "m.room.create",
               "m.room.encryption", "m.room.name", "m.room.topic", "m.room.avatar",
               "m.room.history_visibility", "m.room.power_levels", "m.room.join_rules",
               "m.room.redaction", "m.reaction", "m.room.guest_access"}
    types = {}
    fields = {key: 0 for key in ("algorithm", "ciphertext", "session_id", "sender_key", "body", "msgtype")}
    summary = {"types": types, "content_fields": fields, "megolm_algorithm": 0,
               "text_message_shape": 0, "events": len(events)}
    for value in events:
        value = object_value(value)
        kind = value.get("type")
        label = kind if isinstance(kind, str) and kind in allowed else "other"
        types[label] = types.get(label, 0) + 1
        content = object_value(value.get("content", {}))
        for field in fields:
            fields[field] += field in content
        summary["megolm_algorithm"] += content.get("algorithm") == "m.megolm.v1.aes-sha2"
        summary["text_message_shape"] += (kind == "m.room.message"
            and content.get("msgtype") in ("m.text", "m.notice", "m.emote")
            and isinstance(content.get("body"), str))
    return summary


def sync_summary(reply):
    """Return aggregate diagnostics plus private event/room data separately."""
    reply = object_value(reply)
    text(reply.get("next_batch"), 65536)
    rooms = object_value(reply.get("rooms", {}))
    summary = {"next_batch_present": True, "encrypted_events": 0,
               "timeline_events": 0, "limited_timelines": 0,
               "global_account_events": 0, "direct_mapping_present": False,
               "direct_rooms": 0, "to_device_events": 0}
    events, known_rooms, direct_rooms, timeline_values, state_values = [], {}, set(), [], []
    for membership in ("join", "invite", "leave", "knock"):
        group = object_value(rooms.get(membership, {}))
        if len(group) > 32:
            raise ProbeError("room count bound")
        summary[membership] = len(group)
        for room_id, raw in group.items():
            text(room_id)
            raw = object_value(raw)
            known_rooms[room_id] = membership
            timeline = object_value(raw.get("timeline", {}))
            chunk = array_value(timeline.get("events", []), 100)
            timeline_values.extend(chunk)
            state_values.extend(array_value(object_value(raw.get("state", {})).get("events", []), 256))
            summary["timeline_events"] += len(chunk)
            summary["limited_timelines"] += timeline.get("limited") is True
            for value in chunk:
                event = encrypted_event(room_id, value)
                if event:
                    events.append(event)
    account_data = object_value(reply.get("account_data", {}))
    global_events = array_value(account_data.get("events", []))
    summary["global_account_events"] = len(global_events)
    for value in global_events:
        value = object_value(value)
        if value.get("type") == "m.direct":
            summary["direct_mapping_present"] = True
            mapping = object_value(value.get("content"))
            if len(mapping) > 128:
                raise ProbeError("direct map bound")
            for user, mapped in mapping.items():
                text(user)
                direct_rooms.update(text(room) for room in array_value(mapped, 32))
    summary["direct_rooms"] = len(direct_rooms)
    summary["encrypted_events"] = len(events)
    summary["timeline_shapes"] = event_shape_summary(timeline_values)
    summary["state_shapes"] = event_shape_summary(state_values)
    summary["to_device_events"] = len(array_value(
        object_value(reply.get("to_device", {})).get("events", [])))
    return summary, events, known_rooms, direct_rooms


def decrypt_cloud_event(encoded, account_key, event, olm, observe=None, *, expected_user_id=None):
    """Single-event receive-only check; no key generation, persistence or trust claim.

    Explicitly scoped own type-1 backups may have all three identity strings
    empty. Do not manufacture verified metadata from the event in that case.
    Room/session/actual libolm ID/index/signature/inner-room checks still apply.
    """
    plain = object_value(strict_json(unwrap(text(encoded, 262144).encode("ascii"),
                                           account_key), 196608))
    room, session_id = event["room_id"], event["content"]["session_id"]
    if observe is not None:
        observe("cloud_validation_shape", {
            "envelope_digest_checked": True,
            "version_string_one": plain.get("version") == "1",
            "room_matches": plain.get("room_id") == room,
            "session_matches": plain.get("group_session_id") == session_id,
            "algorithm_matches": plain.get("algorithm") == "m.megolm.v1.aes-sha2",
            "known_export_type": type(plain.get("type")) is int and plain["type"] in (1, 2, 3),
            "chain_index_u32": type(plain.get("chain_index")) is int and 0 <= plain["chain_index"] <= 0xffffffff,
            "sender_matches": plain.get("sender") == event["sender"],
            "curve_matches": plain.get("c25519") == event["content"]["sender_key"],
            "sender_empty": plain.get("sender") == "",
            "curve_empty": plain.get("c25519") == "",
            "signing_key_present": isinstance(plain.get("ed25519"), str) and bool(plain["ed25519"]),
        })
    if (plain.get("version") != "1" or plain.get("room_id") != room
            or plain.get("group_session_id") != session_id
            or plain.get("algorithm") != "m.megolm.v1.aes-sha2"):
        raise ProbeError("cloud format or association mismatch")
    kind, chain = plain.get("type"), plain.get("chain_index")
    if type(kind) is not int or kind not in (1, 2, 3):
        raise ProbeError("cloud discriminator")
    if type(chain) is not int or not 0 <= chain <= 0xffffffff:
        raise ProbeError("cloud chain index")
    if kind in (1, 2) and chain != 0:
        raise ProbeError("unexpected sharing metadata index")
    own_outbound_empty = (kind == 1 and expected_user_id is not None
        and text(expected_user_id) == event["sender"]
        and all(plain.get(field) == "" for field in ("sender", "c25519", "ed25519")))
    if observe is not None:
        observe("cloud_session_parameters", {"export_type": kind, "json_chain_index": chain,
            "event_sender_is_own": expected_user_id is not None and event["sender"] == expected_user_id,
            "empty_own_outbound_metadata": own_outbound_empty})
    if not own_outbound_empty:
        if (text(plain.get("sender")) != event["sender"]
                or text(plain.get("c25519")) != event["content"]["sender_key"]):
            raise ProbeError("cloud sender association mismatch")
        text(plain.get("ed25519"))  # Claimed key only, NOT verified identity.
    key = text(plain.get("group_session_key"), 4096).encode("ascii")
    with olm.inbound(key, exported=kind == 3) as receive:
        if receive.session_id() != session_id:
            raise ProbeError("actual Megolm session mismatch")
        first_index = receive.first_index()
        if kind == 3 and chain != first_index:
            raise ProbeError("exported index metadata mismatch")
        decoded, index = receive.decrypt(event["content"]["ciphertext"].encode("ascii"))
        message = object_value(strict_json(decoded, 262144))
        if message.get("room_id") != room:
            raise ProbeError("inner room mismatch")
        text(message.get("type"))
        object_value(message.get("content"))
        if index < first_index:
            raise ProbeError("decrypted index precedes imported session")
    return {"decrypted": True, "export_type": kind, "first_known_index": first_index,
            "message_index": index, "json_chain_index": chain,
            "inner_room_matches": True,
            "room_message": message["type"] == "m.room.message",
            "sender_metadata_matched": not own_outbound_empty,
            "metadata_policy": "empty_own_outbound" if own_outbound_empty else "matched",
            "verified_sender_identity": False}


class PrivateState:
    """Owner-only research login record; never contains account/Megolm keys.

    Not an OS vault or encrypted at rest. The containing directory is 0700 and
    files are 0600. Records are needed to avoid losing the next device/token.
    """

    def __init__(self, directory):
        self.directory = Path(directory)
        info = self.directory.lstat()
        if (not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid()
                or stat.S_IMODE(info.st_mode) != 0o700):
            raise ProbeError("unsafe research state directory")

    @classmethod
    def create(cls, parent):
        parent = Path(parent)
        parent.mkdir(mode=0o700, exist_ok=True)
        cls(parent)  # Fail closed on symlinks, wrong owner or broad permissions.
        directory = parent / secrets.token_hex(16)
        directory.mkdir(mode=0o700)
        return cls(directory)

    def write(self, value):
        temporary = self.directory / (".state-" + secrets.token_hex(16))
        descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL
                             | os.O_NOFOLLOW, 0o600)
        try:
            with os.fdopen(descriptor, "w") as output:
                json.dump(value, output, separators=(",", ":"))
                output.flush()
                os.fsync(output.fileno())
            os.replace(temporary, self.directory / "state.json")
            descriptor = os.open(self.directory, os.O_RDONLY | os.O_DIRECTORY)
            try:
                os.fsync(descriptor)
            finally:
                os.close(descriptor)
        finally:
            if temporary.exists():
                temporary.unlink()

    def read(self):
        descriptor = os.open(self.directory / "state.json", os.O_RDONLY | os.O_NOFOLLOW)
        with os.fdopen(descriptor, "rb") as source:
            info = os.fstat(source.fileno())
            if (not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid()
                    or stat.S_IMODE(info.st_mode) != 0o600):
                raise ProbeError("unsafe research state file")
            return object_value(strict_json(source.read(65537), 65536))


def capture_login(state, record, status, response):
    """Persist useful response fields BEFORE identity/status validation can fail."""
    response = object_value(response)
    invalid = False
    for name in ("access_token", "device_id", "user_id", "refresh_token"):
        if name in response:
            value = response[name]
            if isinstance(value, str) and 0 < len(value) <= 8192:
                record[name] = value
            else:
                invalid = True
    record["login_http"] = status
    record["phase"] = "login_response_received"
    state.write(record)
    if (invalid or status != 200 or not record.get("access_token") or not record.get("device_id")
            or record.get("user_id") != record["expected_user_id"]):
        raise ProbeError("login response validation failed; record retained")


def password_delete_auth(challenge, user_id, password):
    """Only a single advertised password UIA stage; no guessed fallback flows."""
    challenge = object_value(challenge)
    flows = array_value(challenge.get("flows", []), 16)
    if not any(object_value(flow).get("stages") == ["m.login.password"] for flow in flows):
        return None
    return {"type": "m.login.password", "session": text(challenge.get("session"), 4096),
            "identifier": {"type": "m.id.user", "user": text(user_id)},
            "password": text(password, 65536)}
