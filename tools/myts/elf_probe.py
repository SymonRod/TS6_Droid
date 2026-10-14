#!/usr/bin/env python3
"""Read-only ELF probes for stripped TeamSpeak builds (no fixed offsets).

Requires capstone and pyelftools. Uses .eh_frame_hdr function starts instead
of guessing boundaries from RET bytes. Addresses are ELF virtual addresses,
not file offsets or addresses from a differently rebased Ghidra project.
"""

import argparse
import bisect
import re
import struct

from capstone import Cs, CS_ARCH_X86, CS_MODE_64
from elftools.elf.elffile import ELFFile


class Binary:
    def __init__(self, path):
        with open(path, "rb") as stream:
            elf = ELFFile(stream)
            self.sections = [
                (s.name, s["sh_addr"], s.data())
                for s in elf.iter_sections() if s["sh_type"] == "SHT_PROGBITS"
            ]
        self.text_address, self.text = self.section(".text")
        address, data = self.section(".eh_frame_hdr")
        if data[:4] != b"\x01\x1b\x03\x3b":
            raise ValueError("unsupported .eh_frame_hdr encoding")
        count = struct.unpack_from("<I", data, 8)[0]
        self.starts = sorted({
            address + struct.unpack_from("<i", data, 12 + i * 8)[0]
            for i in range(count)
        })
        self.disassembler = Cs(CS_ARCH_X86, CS_MODE_64)

    def section(self, name):
        return next((address, data) for n, address, data in self.sections if n == name)

    def bytes_at(self, address, length):
        for _, base, data in self.sections:
            if base <= address < base + len(data):
                return data[address - base:address - base + length]
        return b""

    def bounds(self, address):
        index = bisect.bisect_right(self.starts, address) - 1
        if index < 0:
            raise ValueError("address precedes first unwind entry")
        end = self.starts[index + 1] if index + 1 < len(self.starts) else self.text_address + len(self.text)
        return self.starts[index], end

    def rip_leas(self, target):
        # REX.W LEA r64,[RIP+disp32]; validate each candidate with Capstone.
        for m in re.finditer(rb"[\x48\x4c]\x8d[\x05\x0d\x15\x1d\x25\x2d\x35\x3d]", self.text):
            pos = m.start()
            if pos + 7 > len(self.text):
                continue
            address = self.text_address + pos
            dest = address + 7 + struct.unpack_from("<i", self.text, pos + 3)[0]
            if dest == target:
                yield address

    def callers(self, target):
        # Direct rel32 CALL/JMP candidates; instruction boundaries still need
        # checking in the containing unwind function before using a breakpoint.
        for m in re.finditer(rb"[\xe8\xe9]", self.text):
            pos = m.start()
            if pos + 5 <= len(self.text):
                address = self.text_address + pos
                if address + 5 + struct.unpack_from("<i", self.text, pos + 1)[0] == target:
                    yield address

    def dump(self, address):
        start, end = self.bounds(address)
        print("FUNCTION 0x%x..0x%x (unwind boundaries)" % (start, end))
        for instruction in self.disassembler.disasm(self.bytes_at(start, end - start), start):
            print("0x%x: %-8s %s" % (instruction.address, instruction.mnemonic, instruction.op_str))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("binary")
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--string", help="find literal and direct RIP-relative LEA references")
    group.add_argument("--function", type=lambda v: int(v, 0))
    group.add_argument("--callers", type=lambda v: int(v, 0))
    args = parser.parse_args()
    binary = Binary(args.binary)
    if args.function is not None:
        binary.dump(args.function)
    elif args.callers is not None:
        for address in binary.callers(args.callers):
            print("candidate 0x%x, function 0x%x" % (address, binary.bounds(address)[0]))
    else:
        needle = args.string.encode()
        for name, base, data in binary.sections:
            for m in re.finditer(re.escape(needle), data):
                address = base + m.start()
                print("LITERAL %s 0x%x" % (name, address))
                for reference in binary.rip_leas(address):
                    print("LEA 0x%x, function 0x%x" % (reference, binary.bounds(reference)[0]))


if __name__ == "__main__":
    main()
