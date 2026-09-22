#!/usr/bin/env python3
"""Recover myTeamSpeak .proto files from the TeamSpeak desktop client.

The client links full protobuf reflection, so every generated file embeds its
serialized FileDescriptorProto. This scans the binary for them, renders each as
.proto source, and checks that protoc compiles the result back to the same
descriptor (field numbers, types, labels, oneofs, services).

Usage:
    python3 extract_descriptors.py [/opt/teamspeak/TeamSpeak] [out_dir]

Needs the `protobuf` Python package and `protoc` on PATH. Writes only the
import closure of ROOTS; pass --all to write every TeamSpeak descriptor.
"""

import os
import re
import subprocess
import sys
import tempfile

from google.protobuf import descriptor_pb2 as D

ROOTS = [
    "myteamspeak_login.proto",
    "myteamspeak_synchronization.proto",
    "myteamspeak_user.proto",
    "Sync_Serializing.proto",
    "Account_Serializing.proto",
]
THIRD_PARTY = ("envoy", "google", "xds", "udpa", "validate", "opencensus",
               "opentelemetry", "grpc", "src/proto", "cel")

F = D.FieldDescriptorProto
TYPES = {v: k[5:].lower() for k, v in F.Type.items()}
LABELS = {F.LABEL_OPTIONAL: "optional", F.LABEL_REQUIRED: "required",
          F.LABEL_REPEATED: "repeated"}
# FileDescriptorProto field number -> wire type
FILE_FIELDS = {1: 2, 2: 2, 3: 2, 4: 2, 5: 2, 6: 2, 7: 2, 8: 2, 9: 2,
               10: 0, 11: 0, 12: 2, 14: 0, 15: 2}


def varint(b, i):
    r = s = 0
    while True:
        c = b[i]
        i += 1
        r |= (c & 0x7F) << s
        s += 7
        if not c & 0x80:
            return r, i
        if s > 63:
            raise ValueError


def descriptor_end(data, start):
    """Walk FileDescriptorProto fields until one does not fit the schema."""
    i = last = start
    try:
        while True:
            tag, j = varint(data, i)
            if FILE_FIELDS.get(tag >> 3) != tag & 7:
                break
            if tag & 7 == 0:
                _, j = varint(data, j)
            else:
                n, j = varint(data, j)
                j += n
                if j > len(data):
                    break
            i = last = j
    except (IndexError, ValueError):
        pass
    return last


def extract(data):
    found = {}
    for m in re.finditer(rb"\x0a([\x01-\x7f])([\w./-]{1,127}\.proto)", data):
        if m.group(1)[0] != len(m.group(2)):
            continue
        blob = data[m.start():descriptor_end(data, m.start())]
        fd = D.FileDescriptorProto()
        try:
            fd.ParseFromString(blob)
        except Exception:
            continue
        if not (fd.message_type or fd.enum_type or fd.service):
            continue
        if fd.name.startswith(THIRD_PARTY):
            continue
        if fd.name not in found or len(blob) > found[fd.name].ByteSize():
            found[fd.name] = fd
    return found


def render_enum(e, ind):
    out = [f"{ind}enum {e.name} {{"]
    out += [f"{ind}  {v.name} = {v.number};" for v in e.value]
    return out + [f"{ind}}}"]


def render_message(m, ind, syntax):
    out = [f"{ind}message {m.name} {{"]
    maps = {n.name: n for n in m.nested_type if n.options.map_entry}
    for e in m.enum_type:
        out += render_enum(e, ind + "  ")
    for n in m.nested_type:
        if n.name not in maps:
            out += render_message(n, ind + "  ", syntax)
    oneofs = {}
    body = []
    for f in m.field:
        short = f.type_name.split(".")[-1] if f.type_name else ""
        in_oneof = f.HasField("oneof_index") and not f.proto3_optional
        if short in maps:
            k, v = maps[short].field
            line = (f"map<{TYPES[k.type]}, {v.type_name or TYPES[v.type]}> "
                    f"{f.name} = {f.number};")
        else:
            label = ""
            if not in_oneof and (syntax == "proto2" or f.proto3_optional
                                 or f.label == F.LABEL_REPEATED):
                label = LABELS[f.label] + " "
            opts = []
            if f.HasField("default_value"):
                opts.append(f"default = {f.default_value}")
            if f.options.HasField("packed"):
                opts.append(f"packed = {str(f.options.packed).lower()}")
            if f.options.deprecated:
                opts.append("deprecated = true")
            line = f"{label}{f.type_name or TYPES[f.type]} {f.name} = {f.number}"
            line += (f" [{', '.join(opts)}]" if opts else "") + ";"
        if in_oneof:
            if f.oneof_index not in oneofs:
                body.append(("oneof", f.oneof_index))
            oneofs.setdefault(f.oneof_index, []).append(line)
        else:
            body.append(line)
    for item in body:
        if isinstance(item, tuple):
            idx = item[1]
            out.append(f"{ind}  oneof {m.oneof_decl[idx].name} {{")
            out += [f"{ind}    {line}" for line in oneofs[idx]]
            out.append(f"{ind}  }}")
        else:
            out.append(f"{ind}  {item}")
    ranges = [str(r.start) if r.end == r.start + 1 else f"{r.start} to {r.end - 1}"
              for r in m.reserved_range]
    if ranges:
        out.append(f"{ind}  reserved {', '.join(ranges)};")
    if m.reserved_name:
        out.append(f"{ind}  reserved {', '.join(chr(34) + n + chr(34) for n in m.reserved_name)};")
    return out + [f"{ind}}}"]


def render(fd, provenance):
    syntax = fd.syntax or "proto2"
    out = [f"// Recovered from the descriptor embedded in {provenance}.",
           "// Generated by docs/proto/extract_descriptors.py; do not edit.",
           f'syntax = "{syntax}";', "", f"package {fd.package};", ""]
    out += [f'import "{d}";' for d in fd.dependency]
    if fd.dependency:
        out.append("")
    opts = fd.options.ListFields()
    for field, value in opts:
        if field.enum_type:
            value = field.enum_type.values_by_number[value].name
        elif isinstance(value, str):
            value = f'"{value}"'
        else:
            value = str(value).lower()
        out.append(f"option {field.name} = {value};")
    if opts:
        out.append("")
    for e in fd.enum_type:
        out += render_enum(e, "") + [""]
    for m in fd.message_type:
        out += render_message(m, "", syntax) + [""]
    for s in fd.service:
        out.append(f"service {s.name} {{")
        for rpc in s.method:
            cs = "stream " if rpc.client_streaming else ""
            ss = "stream " if rpc.server_streaming else ""
            out.append(f"  rpc {rpc.name}({cs}{rpc.input_type}) "
                       f"returns ({ss}{rpc.output_type});")
        out += ["}", ""]
    return "\n".join(out).rstrip() + "\n"


def closure(found, roots):
    keep = set()

    def visit(name):
        if name in keep or name not in found:
            return
        keep.add(name)
        for dep in found[name].dependency:
            visit(dep)

    for root in roots:
        visit(root)
    return keep


def strip_json_names(fd):
    def visit(m):
        for f in m.field:
            f.ClearField("json_name")
        for n in m.nested_type:
            visit(n)
    for m in fd.message_type:
        visit(m)
    return fd


def verify(found, names, out_dir):
    with tempfile.TemporaryDirectory() as tmp:
        desc = os.path.join(tmp, "set.pb")
        subprocess.run(["protoc", f"-I{out_dir}", f"--descriptor_set_out={desc}",
                        *sorted(names)], check=True, cwd=out_dir,
                       stderr=subprocess.DEVNULL)
        compiled = D.FileDescriptorSet.FromString(open(desc, "rb").read())
    bad = 0
    for fd in compiled.file:
        want = strip_json_names(D.FileDescriptorProto.FromString(
            found[fd.name].SerializeToString()))
        got = strip_json_names(fd)
        for part in ("package", "dependency", "message_type", "enum_type", "service"):
            if getattr(want, part) != getattr(got, part):
                print(f"MISMATCH {fd.name}: {part}", file=sys.stderr)
                bad += 1
    return bad


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    binary = args[0] if args else "/opt/teamspeak/TeamSpeak"
    out_dir = args[1] if len(args) > 1 else os.path.dirname(os.path.abspath(__file__))
    found = extract(open(binary, "rb").read())
    names = set(found) if "--all" in sys.argv else closure(found, ROOTS)
    for name in sorted(names):
        with open(os.path.join(out_dir, name), "w") as f:
            f.write(render(found[name], binary))
    bad = verify(found, names, out_dir)
    print(f"{len(found)} descriptors found, {len(names)} written, {bad} mismatches")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()
