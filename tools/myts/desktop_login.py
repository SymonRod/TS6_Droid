#!/usr/bin/env python3
"""Drive one explicitly authorized, isolated desktop login over localhost CDP.

Reads credentials from .env in memory; prints only result codes and lengths.
The desktop client must already be running with a research profile and a
loopback remote-debugging port. --probe attaches the build-pinned gdb probe
before logout/login, then waits for it to detach. Requires python-dotenv,
requests and websocket-client (plus gdb for --probe).
"""

import argparse
import json
import os
from pathlib import Path
import signal
import subprocess
import time

from dotenv import dotenv_values
import requests
import websocket


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pid", required=True, type=int)
    parser.add_argument("--port", type=int, default=9223)
    parser.add_argument("--out", required=True, type=Path)
    parser.add_argument("--probe", action="store_true")
    parser.add_argument("--first-login", action="store_true", help="skip logout on a fresh profile")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    out = args.out.resolve()
    assert out.is_relative_to(root / "captures"), "output must be in captures/"
    env = Path("/proc/%d/environ" % args.pid).read_bytes().split(b"\0")
    assert any(item.startswith(("XDG_CONFIG_HOME=" + str(root / "captures") + "/").encode()) for item in env), "not a research profile"
    assert Path("/proc/%d/exe" % args.pid).resolve() == (root / "../teamspeak-client/TeamSpeak").resolve(), "unexpected process binary"
    credentials = dotenv_values(root / ".env")
    assert credentials.get("USERNAME") and credentials.get("PASSWORD"), "missing credentials"
    out.mkdir(mode=0o700, parents=True, exist_ok=True)
    assert not (out / "metadata.log").exists(), "use a fresh probe output directory"
    probe = None
    log = None
    try:
        if args.probe:
            log = (out / "gdb.log").open("wb")
            probe_env = os.environ | {"MYTS_PID": str(args.pid), "MYTS_OUT": str(out)}
            probe = subprocess.Popen(
                ["gdb", "-batch", "-nx", "-x", str(root / "tools/myts/gdb_login_probe.py")],
                env=probe_env, stdout=log, stderr=log,
            )
            deadline = time.monotonic() + 15
            while not ((out / "metadata.log").exists() and "attached targeted probe" in (out / "metadata.log").read_text()):
                if probe.poll() is not None or time.monotonic() > deadline:
                    raise RuntimeError("probe did not attach; see local gdb.log")
                time.sleep(0.1)
        pages = requests.get("http://127.0.0.1:%d/json" % args.port, timeout=5).json()
        page = next(p for p in pages if p.get("url", "").startswith("tsui://"))
        # Do not follow a remote debugging URL to a non-loopback host.
        assert page["webSocketDebuggerUrl"].startswith("ws://127.0.0.1:%d/" % args.port)
        ws = websocket.create_connection(page["webSocketDebuggerUrl"], suppress_origin=True, timeout=60)
        try:
            def evaluate(identifier, expression):
                ws.send(json.dumps({"id": identifier, "method": "Runtime.evaluate", "params": {
                    "expression": expression, "awaitPromise": True, "returnByValue": True,
                }}))
                while True:
                    reply = json.loads(ws.recv())
                    if reply.get("id") == identifier:
                        result = reply.get("result", {})
                        if "exceptionDetails" in result or "error" in reply:
                            raise RuntimeError("bridge call failed (details suppressed)")
                        return result["result"].get("value")
            if not args.first_login:
                print("Isolated logout:", evaluate(1, "new Promise(resolve=>tsclient_internal.logoutAccount(code=>resolve({code})))"))
            expression = (
                "new Promise(resolve=>tsclient_internal.loginAccount("
                + json.dumps(credentials["USERNAME"]) + "," + json.dumps(credentials["PASSWORD"])
                + ',"",code=>resolve({code})))'
            )
            print("Isolated login:", evaluate(2, expression))
            print("Account password metadata:", evaluate(3,
                'new Promise(resolve=>tsclient_internal.getAccountHashedPassword(v=>resolve({length:typeof v==="string"?v.length:-1})))'))
        finally:
            ws.close()
        if probe:
            probe.send_signal(signal.SIGINT)
            probe.wait(timeout=10)
            print("Probe detached; exit code:", probe.returncode)
            log.flush()
            debugger_log = (out / "gdb.log").read_text(errors="replace")
            if probe.returncode or "Python Exception" in debugger_log or "Traceback (most recent call last)" in debugger_log:
                raise RuntimeError("probe failed; inspect local gdb.log (details suppressed)")
    finally:
        if probe and probe.poll() is None:
            # This is our debugger, never the desktop process or another gdb.
            probe.terminate()
            probe.wait(timeout=10)
        if log:
            log.close()


if __name__ == "__main__":
    main()
