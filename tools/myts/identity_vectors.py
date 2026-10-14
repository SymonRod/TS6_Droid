"""Independent, disposable TeamSpeak identity vectors; NEVER use for login.

Every private scalar below is public synthetic test data. No account files,
captures or network are read. PyCryptodome supplies only the P-256 point;
the TomCrypt DER, obfuscation and UID encoding are constructed here.
"""

import base64
import hashlib

from Crypto.PublicKey import ECC


OBFUSCATION = (
    b"b9dfaa7bee6ac57ac7b65f1094a1c155e747327bc2fe5d51c512023fe54a2802"
    b"01004e90ad1daaae1075d53b7d571c30e063b5a62a4a017bb394833aa0983e6e"
)


def tlv(tag, content):
    length = len(content)
    size = bytes([length]) if length < 128 else b"\x81" + bytes([length])
    return bytes([tag]) + size + content


def integer(value):
    data = value.to_bytes(max(1, (value.bit_length() + 7) // 8), "big")
    if data[0] & 0x80:
        data = b"\x00" + data
    return tlv(2, data)


def tomcrypt(scalar, private):
    point = ECC.construct(curve="P-256", d=scalar).pointQ
    fields = [tlv(3, b"\x07\x80" if private else b"\x07\x00"),
              integer(32), integer(int(point.x)), integer(int(point.y))]
    if private:
        fields.append(integer(scalar))
    return tlv(0x30, b"".join(fields))


def obfuscate(raw_base64):
    data = bytearray(raw_base64)
    for index in range(min(100, len(data))):
        data[index] ^= OBFUSCATION[index]
    digest = hashlib.sha1(bytes(data[20:]).split(b"\x00", 1)[0]).digest()
    for index in range(20):
        data[index] ^= digest[index]
    return base64.b64encode(data).decode("ascii")


def vector(name, scalar, counter):
    public = base64.b64encode(tomcrypt(scalar, False))
    raw = base64.b64encode(tomcrypt(scalar, True))
    return {
        "name": name,
        "scalar": scalar.to_bytes(32, "big"),
        "counter": counter,
        "raw": raw.decode("ascii"),
        "public": public.decode("ascii"),
        "desktop": str(counter) + "V" + obfuscate(raw),
        "uid": base64.b64encode(hashlib.sha1(public).digest()).decode("ascii"),
    }


def vectors():
    return [vector("one", 1, 0),
            vector("pattern", int.from_bytes(bytes(range(1, 33)), "big"), 2792354),
            vector("high-bit", int.from_bytes(b"\x80" * 32, "big"), 18446744073709551615)]


if __name__ == "__main__":
    # Public metadata only, not the disposable private-key encodings.
    for item in vectors():
        print(item["name"], "counter=%d" % item["counter"], "uid=" + item["uid"],
              "obfuscated_sha1=" + hashlib.sha1(item["desktop"].split("V", 1)[1].encode()).hexdigest())
