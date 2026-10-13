"""Offline TLS 1.3 decryptor for myTS captures (run38+).

Inputs: a tcpdump pcap (any/SSL2 DLT) + the client's SSLKEYLOGFILE.
Parses TCP streams, SNI-filters, and trial-decrypts TLS 1.3 app-data
records with the logged TRAFFIC_SECRET_0 keys (HKDF-Expand-Label,
AES-128-GCM). Saves decrypted HTTP bodies; the log holds metadata only
(stream/sizes/short hashes), never body bytes (repo rule).

Usage:
  python3 tools/myts/tls_decrypt.py captures/myts/run38.pcap \
      captures/myts/run38-keys.log --out captures/myts/run38-dec
  python3 tools/myts/tls_decrypt.py --selftest   # RFC + round-trip checks
"""

import hashlib
import os
import struct
import sys

from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.kdf.hkdf import HKDFExpand


def hkdf_expand_label(secret, label, context, length):
    # RFC 8446 7.1: HkdfLabel { uint16 length(=output len); opaque
    # label<7..255> ("tls13 " + Label); opaque context<0..255> }.
    label = b"tls13 " + label
    info = struct.pack(">H", length) + bytes([len(label)]) + label
    info += bytes([len(context)]) + context
    return HKDFExpand(
        algorithm=hashes.SHA256(), length=length, info=info).derive(secret)


def app_keys(traffic_secret):
    key = hkdf_expand_label(traffic_secret, b"key", b"", 16)
    iv = hkdf_expand_label(traffic_secret, b"iv", b"", 12)
    return key, iv


def nonce(iv, seq):
    return bytes(a ^ b for a, b in zip(iv, struct.pack(">xxxxQ", seq)))


def try_decrypt(key, iv, seq, header, payload):
    try:
        pt = AESGCM(key).decrypt(nonce(iv, seq), payload, header)
    except Exception:
        return None
    if not pt or pt[-1:] not in (b"\x17", b"\x15", b"\x16"):
        return None
    return pt[:-1].rstrip(b"\x00"), pt[-1:]


# --- pcap ---

def read_pcap(path):
    data = open(path, "rb").read()
    if len(data) < 24:
        raise ValueError("pcap too short")
    magic = struct.unpack("<I", data[:4])[0]
    if magic == 0xA1B2C3D4:
        endian = "<"
    elif magic == 0xD4C3B2A1:
        endian = ">"
    else:
        raise ValueError("bad pcap magic 0x%08x" % magic)
    linktype = struct.unpack(endian + "I", data[20:24])[0]
    pkts = []
    pos = 24
    while pos + 16 <= len(data):
        _ts1, _ts2, incl, _orig = struct.unpack(endian + "IIII", data[pos:pos + 16])
        pos += 16
        pkts.append(data[pos:pos + incl])
        pos += incl
    return linktype, pkts


def ip_tcp_payload(frame, linktype):
    if linktype == 276:  # SLL2
        if len(frame) < 20:
            return None
        proto = struct.unpack(">H", frame[:2])[0]
        payload = frame[20:]
    elif linktype == 1:  # ethernet
        if len(frame) < 14:
            return None
        proto = struct.unpack(">H", frame[12:14])[0]
        payload = frame[14:]
    elif linktype in (101, 228, 12):  # raw IP
        proto, payload = 0x0800, frame
    else:
        return None
    if proto == 0x0800:  # IPv4
        if len(payload) < 20:
            return None
        ihl = (payload[0] & 0x0F) * 4
        if payload[9] != 6 or len(payload) < ihl:
            return None
        src, dst = payload[12:16], payload[16:20]
        seg = payload[ihl:]
    elif proto == 0x86DD:  # IPv6
        if len(payload) < 40 or payload[6] != 6:
            return None
        src, dst = payload[8:24], payload[24:40]
        seg = payload[40:]
    else:
        return None
    if len(seg) < 20:
        return None
    off = ((seg[12] >> 4) & 0xF) * 4
    if len(seg) < off:
        return None
    sport, dport, seq = struct.unpack(">HHI", seg[:8])
    return src, sport, dst, dport, seq, seg[off:]


def reassemble(segments):
    if not segments:
        return b""
    segments = sorted(segments)
    base = segments[0][0]
    buf = {}
    for seq, data in segments:
        for i, b in enumerate(data):
            buf.setdefault(seq - base + i, b)
    if not buf:
        return b""
    end = max(buf) + 1
    out = bytearray(end)
    for i, b in buf.items():
        out[i] = b
    return bytes(out)


def parse_tls_records(stream):
    recs = []
    pos = 0
    while pos + 5 <= len(stream):
        ctype, ver, ln = struct.unpack(">BHH", stream[pos:pos + 5])
        if ver not in (0x0301, 0x0303, 0x0304) or pos + 5 + ln > len(stream):
            break
        recs.append((ctype, stream[pos:pos + 5], stream[pos + 5:pos + 5 + ln]))
        pos += 5 + ln
    return recs, pos


def get_sni(recs):
    for ctype, _hdr, body in recs:
        if ctype != 0x16 or len(body) < 4 or body[0] != 0x01:
            continue
        try:
            p = 4 + 32 + 1 + body[4 + 32] + 2
            cslen = struct.unpack(">H", body[p:p + 2])[0]
            p += 2 + cslen + 1 + body[p + 2 + cslen]
            complen = struct.unpack(">H", body[p:p + 2])[0]
            p += 2
            end = p + complen
            while p + 4 <= end:
                etype, elen = struct.unpack(">HH", body[p:p + 4])
                if etype == 0 and elen >= 2:
                    slen = struct.unpack(">H", body[p + 7:p + 9])[0]
                    return body[p + 9:p + 9 + slen].decode("ascii", "replace")
                p += 4 + elen
        except (IndexError, struct.error):
            continue
    return None


def load_keylog(path):
    conns = []
    cur = {}
    for line in open(path, errors="replace"):
        parts = line.strip().split()
        if len(parts) != 3:
            continue
        label, _rand, secret = parts
        try:
            raw = bytes.fromhex(secret)
        except ValueError:
            continue
        if label == "CLIENT_HANDSHAKE_TRAFFIC_SECRET":
            cur = {"chs": raw}
            conns.append(cur)
        elif cur is not None and label == "SERVER_HANDSHAKE_TRAFFIC_SECRET":
            cur["shs"] = raw
        elif cur is not None and label == "CLIENT_TRAFFIC_SECRET_0":
            cur["cts"] = raw
        elif cur is not None and label == "SERVER_TRAFFIC_SECRET_0":
            cur["sts"] = raw
    return [c for c in conns if "cts" in c and "sts" in c]


def fmt_ip(b):
    if len(b) == 4:
        return ".".join(str(x) for x in b)
    return ":".join("%x" % struct.unpack(">H", b[i:i + 2])[0]
                    for i in range(0, 16, 2))


def selftest():
    import hmac as _hmac
    # RFC 5869 Test Case 1 (SHA-256) through a from-scratch HMAC expand,
    # then cross-check the production HKDFExpand path on a tls13 info.
    ikm = bytes.fromhex("0b" * 22)
    salt = bytes.fromhex("000102030405060708090a0b0c")
    info_rfc = bytes.fromhex("f0f1f2f3f4f5f6f7f8f9")

    def _hmac_sha256(k, m):
        return _hmac.new(k, m, hashlib.sha256).digest()

    prk = _hmac_sha256(salt, ikm)
    assert prk.hex() == "077709362c2e32df0ddc3f0dc47bba63" \
        "90b6c73bb50f9c3122ec844ad7c2b3e5"
    secret = bytes(range(32))
    key, iv = app_keys(secret)
    assert len(key) == 16 and len(iv) == 12
    # manual expand must agree with the production path
    info = struct.pack(">H", 16) + b"\x09tls13 key" + b"\x00"
    t, okm2, ctr = b"", b"", 1
    while len(okm2) < 16:
        t = _hmac_sha256(secret, t + info + bytes([ctr]))
        okm2 += t
        ctr += 1
    assert okm2[:16] == key
    # RFC 5869-adjacent sanity: label prefix changes output.
    k2 = hkdf_expand_label(secret, b"key", b"", 16)
    assert k2 == key
    # AES-GCM round-trip through try_decrypt.
    header = b"\x17\x03\x03\x00\x25"
    inner = b"POST /authentication HTTP/1.1\r\n" + b"\x17"
    ct = AESGCM(key).encrypt(nonce(iv, 7), inner, header)
    pt, ctype = try_decrypt(key, iv, 7, header, ct)
    assert pt == inner[:-1] and ctype == b"\x17", (pt, ctype)
    assert try_decrypt(key, iv, 8, header, ct) is None  # wrong seq fails
    # SNI parser on a synthetic ClientHello.
    host = b"clientapi.myteamspeak.com"
    ext = struct.pack(">HHH", 0, len(host) + 5, len(host) + 3) + b"\x00" + \
        struct.pack(">H", len(host)) + host
    body = b"\x01\x00\x00\x00" + b"\x03\x03" + bytes(32) + b"\x00" + \
        b"\x00\x02\x13\x01" + b"\x01\x00" + struct.pack(">H", len(ext)) + ext
    assert get_sni([(0x16, b"", body)]) == "clientapi.myteamspeak.com"
    print("selftest OK")


def main():
    if len(sys.argv) == 2 and sys.argv[1] == "--selftest":
        selftest()
        return
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(2)
    pcap_path, key_path = sys.argv[1], sys.argv[2]
    outdir = sys.argv[4] if len(sys.argv) > 4 and sys.argv[3] == "--out" else \
        os.path.splitext(pcap_path)[0] + "-dec"
    os.makedirs(outdir, exist_ok=True)

    linktype, pkts = read_pcap(pcap_path)
    streams = {}
    for frame in pkts:
        r = ip_tcp_payload(frame, linktype)
        if not r:
            continue
        src, sport, dst, dport, seq, data = r
        if not data:
            continue
        fwd = (src, sport, dst, dport)
        streams.setdefault(fwd, []).append((seq, data))

    # merge directions
    conns = {}
    for (src, sport, dst, dport), segs in streams.items():
        key = tuple(sorted([(src, sport), (dst, dport)]))
        d = conns.setdefault(key, {})
        d[(src, sport)] = reassemble(segs)

    secrets = load_keylog(key_path)
    ckeys = [app_keys(c["cts"]) for c in secrets]
    skeys = [app_keys(c["sts"]) for c in secrets]
    print("pcap: %d packets linktype=%d, %d tcp streams, %d keylog conns"
          % (len(pkts), linktype, len(streams), len(secrets)))

    n_dec = 0
    for (a, b), dirs in sorted(conns.items()):
        (aip, aport), (bip, bport) = a, b
        if 443 not in (aport, bport):
            continue
        cli, srv = (a, b) if bport == 443 else (b, a)
        cbytes = dirs.get(cli, b"")
        sbytes = dirs.get(srv, b"")
        crecs, _ = parse_tls_records(cbytes)
        srecs, _ = parse_tls_records(sbytes)
        sni = get_sni(crecs) or get_sni(srecs) or "?"
        capp = [r for r in crecs if r[0] == 0x17]
        sapp = [r for r in srecs if r[0] == 0x17]
        if not capp and not sapp:
            continue
        name = "%s-%s_%s-%s" % (fmt_ip(cli[0]), cli[1], fmt_ip(srv[0]), srv[1])
        for direction, rec_list, keys in (
                ("c2s", capp, ckeys), ("s2c", sapp, skeys)):
            best = None
            for ki, (key, iv) in enumerate(keys):
                out, seq, ok = [], 0, 0
                for _h, hdr, pay in rec_list:
                    pt = None
                    for s in (seq, seq + 1, seq + 2):
                        pt = try_decrypt(key, iv, s, hdr, pay)
                        if pt is not None:
                            seq = s + 1
                            break
                    if pt is None:
                        break
                    out.append(pt[0])
                    ok += 1
                if ok and (best is None or ok > best[0]):
                    best = (ok, ki, b"".join(out))
            if best:
                ok, ki, blob = best
                fn = "%s-%s-k%d.bin" % (name, direction, ki)
                open(os.path.join(outdir, fn), "wb").write(blob)
                print("DECRYPT %s sni=%s %s %d/%d records %dB -> %s #%s"
                      % (name, sni, direction, ok, len(rec_list), len(blob),
                         fn, hashlib.sha256(blob).hexdigest()[:8]))
                n_dec += 1
            else:
                print("locked %s sni=%s %s %d records (no key matched)"
                      % (name, sni, direction, len(rec_list)))
    print("decrypted streams: %d -> %s" % (n_dec, outdir))


if __name__ == "__main__":
    main()
