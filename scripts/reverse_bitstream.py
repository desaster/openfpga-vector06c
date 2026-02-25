#!/usr/bin/env python3
#
# Reverse bits in each byte of an FPGA bitstream.
#

import struct
import sys

if len(sys.argv) != 3:
    print("Usage: reverse_bitstream.py input.rbf output.rbf_r")
    sys.exit(1)

with open(sys.argv[1], "rb") as f:
    data = f.read()

table = bytes(int("{:08b}".format(b)[::-1], 2) for b in range(256))

with open(sys.argv[2], "wb") as f:
    f.write(data.translate(table))

print(f"Reversed {len(data)} bytes: {sys.argv[1]} -> {sys.argv[2]}")
