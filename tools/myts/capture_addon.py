"""mitmproxy addon: dump myTeamSpeak cloud API calls for offline decoding.

    MYTS_RUN=run3 mitmdump -s tools/myts/capture_addon.py \
        -w captures/myts/run3.mitm

Every request to *.myteamspeak.com / *.teamspeak.com is written to
captures/myts/<run>-<seq>-<host>-<path>.{req,resp}.bin and summarized in
captures/myts/<run>.log. For application/ts3cloud bodies the log also
names the RPC (framing: u8 length + method name + protobuf, see
docs/myteamspeak-sync-protocol.md §0). Decode with tools/myts/analyze.py.

Everything written here carries tokens and credentials: captures/ is
git-ignored and must stay that way.
"""

import os
import re
from pathlib import Path

from mitmproxy import http

OUT = Path(os.environ.get("MYTS_OUT", "captures/myts"))
RUN = os.environ.get("MYTS_RUN", "run")
HOSTS = ("myteamspeak.com", "teamspeak.com")


def rpc_method(body: bytes) -> str | None:
    if not body:
        return None
    n = body[0]
    name = body[1:1 + n]
    if len(name) == n and re.fullmatch(rb"[A-Za-z_][A-Za-z0-9_]*", name):
        return name.decode()
    return None


class Dump:
    def __init__(self):
        OUT.mkdir(parents=True, exist_ok=True)
        self.seq = 0
        self.log = open(OUT / f"{RUN}.log", "a", buffering=1)

    def response(self, flow: http.HTTPFlow):
        req, resp = flow.request, flow.response
        if not req.pretty_host.endswith(HOSTS):
            return
        self.seq += 1
        path = req.path.split("?")[0].strip("/").replace("/", "_") or "root"
        stem = OUT / f"{RUN}-{self.seq:03d}-{req.method}-{req.pretty_host}-{path}"
        body = req.raw_content or b""
        Path(f"{stem}.req.bin").write_bytes(body)
        Path(f"{stem}.resp.bin").write_bytes(resp.raw_content or b"")
        ctype = req.headers.get("content-type", "?")
        method = rpc_method(body) if "ts3cloud" in ctype else None
        self.log.write(
            f"seq={self.seq} {req.method} {req.pretty_url} ctype={ctype}"
            f" rpc={method or '-'} req={len(body)}B"
            f" resp={resp.status_code}/{len(resp.raw_content or b'')}B"
            f" ua={req.headers.get('user-agent', '-')}\n")

    def error(self, flow: http.HTTPFlow):
        if flow.request.pretty_host.endswith(HOSTS):
            self.log.write(f"ERROR {flow.request.pretty_url}: {flow.error}\n")

    def tls_failed_client(self, data):
        # A client that pins or rejects our CA shows up here, not in response().
        self.log.write(f"TLS-FAIL client={data.context.client.peername}"
                       f" sni={data.context.client.sni}: {data.conn.error}\n")


addons = [Dump()]
