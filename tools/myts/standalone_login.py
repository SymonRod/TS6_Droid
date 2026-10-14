#!/usr/bin/env python3
"""One explicitly authorized login, no retries or sync; secrets stay in captures/.

Requires run39's extracted descriptors and the disposable research venv.
Creates one session and then deletes only that session. Never prints secrets.
"""

import argparse
import os
from pathlib import Path

from dotenv import dotenv_values
from google.protobuf import any_pb2, descriptor_pb2, descriptor_pool, message_factory
import requests

from password import login_password


def classes(directory):
    pool = descriptor_pool.Default()  # any_pb2 registers the well-known Any dependency.
    descriptors = {}
    for path in directory.rglob("*.descriptor.bin"):
        desc = descriptor_pb2.FileDescriptorProto.FromString(path.read_bytes())
        descriptors[desc.name] = desc

    def add(name):
        try:
            pool.FindFileByName(name)
            return
        except KeyError:
            pass
        desc = descriptors[name]
        for dependency in desc.dependency:
            add(dependency)
        pool.Add(desc)

    add("myteamspeak_common.proto")
    return {name: message_factory.GetMessageClass(pool.FindMessageTypeByName(
        "com.teamspeak.myteamspeak.proto." + name))
        for name in ("LoginData", "LoginSession", "Session", "LoginStatus")}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--authorize-login", action="store_true")
    args = parser.parse_args()
    assert args.authorize_login, "explicit authorization required"
    root = Path(__file__).resolve().parents[2]
    out = args.out.resolve()
    assert out.is_relative_to(root / "captures"), "output must be in captures/"
    out.mkdir(mode=0o700, parents=True, exist_ok=False)
    os.chmod(out, 0o700)
    messages = classes(root / "captures/myts/build-7eb9fdb8")
    credentials = dotenv_values(root / ".env")
    email, password = credentials["USERNAME"], credentials["PASSWORD"]
    encoded = login_password(email, password)
    assert encoded.encode() == (root / "captures/myts/run40/probe-derivation-fixed/002-derive-login-result.bin").read_bytes(), "desktop comparison failed"

    def rpc(method, message):
        body = bytes([len(method)]) + method.encode("ascii") + message.SerializeToString()
        (out / (method + "-request.bin")).write_bytes(body)
        os.chmod(out / (method + "-request.bin"), 0o600)
        # requests does not retry by default. No redirects or account mutations.
        response = requests.post("https://clientapi.myteamspeak.com/authentication", data=body,
            headers={"Content-Type": "application/ts3cloud", "User-Agent": "cpp-httplib/0.11.1"},
            timeout=(15, 30), allow_redirects=False)
        (out / (method + "-reply.bin")).write_bytes(response.content)
        os.chmod(out / (method + "-reply.bin"), 0o600)
        print(method, "HTTP", response.status_code, "reply bytes", len(response.content))
        assert response.status_code == 200, "HTTP failure (no retry)"
        return response.content

    request = messages["LoginData"](email=email, password=encoded, sync_version=1,
                                    device_name="TS6 Droid research run40")
    reply = messages["LoginSession"].FromString(rpc("login", request))
    metadata = {"error": reply.error, "fields": [f.name for f, _ in reply.ListFields()],
                "key_bytes": len(reply.key), "session_chars": len(reply.session),
                "uuid_chars": len(reply.uuid), "purge_present": reply.purge != 0,
                "renewal_token_chars": len(reply.alternative_login_info.renewal_token),
                "otp_renewal_token_chars": len(reply.alternative_login_info.otp_renewal_token),
                "device_id_chars": len(reply.alternative_login_info.device_id)}
    print("LoginSession metadata:", metadata)
    (out / "metadata.txt").write_text(repr(metadata) + "\n")
    assert reply.error == 200 and reply.session, "login failed (no retry)"
    status = messages["LoginStatus"].FromString(rpc("deleteSession", messages["Session"](session=reply.session)))
    print("Own standalone session cleanup error:", status.error)
    assert status.error == 204, "standalone session cleanup not confirmed"


if __name__ == "__main__":
    main()
