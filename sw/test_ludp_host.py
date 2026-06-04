#!/usr/bin/env python3
"""
LUDP Host Protocol Validation Test

This test validates that ludp_host.py generates correctly formatted packets
that match what the FPGA expects (little-endian byte order).

Run: python test_ludp_host.py
"""

import struct
import sys
import os

# Add parent directory to path to import ludp_host
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from ludp_host import (
    LudpHost, LUDP_MAGIC, LUDP_PORT, PKT_CMD, PKT_CREDIT, PKT_NACK,
    CMD_START, CMD_STOP, CMD_READ_REG, CMD_WRITE_REG,
    DEFAULT_WINDOW_SIZE
)


def test_cmd_packet_format():
    """Test that CMD packet format matches FPGA expectations."""
    print("=" * 60)
    print("Test 1: CMD Packet Format")
    print("=" * 60)

    # Create a mock host (won't actually send anything)
    host = LudpHost.__new__(LudpHost)
    host.next_cmd_id = 1

    # Build a START command packet
    pkt = host._build_cmd(CMD_START, arg1=0, arg2=0, flags=0x00, cmd_id=0x12345678)

    print(f"Packet length: {len(pkt)} bytes (expected: 16)")
    assert len(pkt) == 16, f"Expected 16 bytes, got {len(pkt)}"

    # Parse the packet manually to verify byte order
    magic = struct.unpack("<H", pkt[0:2])[0]
    pkt_type = pkt[2]
    flags = pkt[3]
    cmd_id = struct.unpack("<I", pkt[4:8])[0]
    opcode = struct.unpack("<H", pkt[8:10])[0]
    arg1 = struct.unpack("<I", pkt[10:14])[0]
    arg2 = struct.unpack("<H", pkt[14:16])[0]

    print(f"Magic:      0x{magic:04X} (expected: 0x{LUDP_MAGIC:04X})")
    print(f"Type:       0x{pkt_type:02X} (expected: 0x{PKT_CMD:02X})")
    print(f"Flags:      0x{flags:02X} (expected: 0x00)")
    print(f"CMD ID:     0x{cmd_id:08X} (expected: 0x12345678)")
    print(f"Opcode:     0x{opcode:04X} (expected: 0x{CMD_START:04X})")
    print(f"Arg1:       0x{arg1:08X} (expected: 0x00000000)")
    print(f"Arg2:       0x{arg2:04X} (expected: 0x0000)")

    assert magic == LUDP_MAGIC, f"Magic mismatch"
    assert pkt_type == PKT_CMD, f"Type mismatch"
    assert flags == 0x00, f"Flags mismatch"
    assert cmd_id == 0x12345678, f"CMD ID mismatch"
    assert opcode == CMD_START, f"Opcode mismatch"
    assert arg1 == 0, f"Arg1 mismatch"
    assert arg2 == 0, f"Arg2 mismatch"

    # Verify byte-level layout (what FPGA sees on XGMII)
    print(f"\nRaw bytes (as FPGA receives them):")
    for i in range(0, len(pkt), 8):
        chunk = pkt[i:i+8]
        hex_str = " ".join(f"{b:02X}" for b in chunk)
        print(f"  Offset {i:2d}: {hex_str}")

    # Verify first 64-bit word layout
    word0 = struct.unpack("<Q", pkt[0:8])[0]
    print(f"\nFirst 64-bit word (little-endian): 0x{word0:016X}")
    print(f"  Bits [7:0]   (byte 0): 0x{word0 & 0xFF:02X} - Magic LSB")
    print(f"  Bits [15:8]  (byte 1): 0x{(word0 >> 8) & 0xFF:02X} - Magic MSB")
    print(f"  Bits [23:16] (byte 2): 0x{(word0 >> 16) & 0xFF:02X} - Type")
    print(f"  Bits [31:24] (byte 3): 0x{(word0 >> 24) & 0xFF:02X} - Flags")
    print(f"  Bits [63:32] (bytes 4-7): 0x{(word0 >> 32) & 0xFFFFFFFF:08X} - CMD ID")

    print("\n[PASS] CMD packet format is correct")
    return True


def test_credit_packet_format():
    """Test that CREDIT packet format matches FPGA expectations."""
    print("\n" + "=" * 60)
    print("Test 2: CREDIT Packet Format")
    print("=" * 60)

    host = LudpHost.__new__(LudpHost)
    host.next_cmd_id = 1

    # Build a CREDIT packet
    pkt = host._build_credit(abs_credit=0xABCDEF00)

    print(f"Packet length: {len(pkt)} bytes (expected: 16)")
    assert len(pkt) == 16, f"Expected 16 bytes, got {len(pkt)}"

    magic = struct.unpack("<H", pkt[0:2])[0]
    pkt_type = pkt[2]
    flags = pkt[3]
    abs_credit = struct.unpack("<I", pkt[4:8])[0]
    opcode = struct.unpack("<H", pkt[8:10])[0]

    print(f"Magic:      0x{magic:04X} (expected: 0x{LUDP_MAGIC:04X})")
    print(f"Type:       0x{pkt_type:02X} (expected: 0x{PKT_CREDIT:02X})")
    print(f"Flags:      0x{flags:02X} (expected: 0x00)")
    print(f"Credit:     0x{abs_credit:08X} (expected: 0xABCDEF00)")
    print(f"Opcode:     0x{opcode:04X} (expected: 0x0000)")

    assert magic == LUDP_MAGIC, f"Magic mismatch"
    assert pkt_type == PKT_CREDIT, f"Type mismatch"
    assert abs_credit == 0xABCDEF00, f"Credit mismatch"

    print("\n[PASS] CREDIT packet format is correct")
    return True


def test_nack_packet_format():
    """Test that NACK packet format matches FPGA expectations."""
    print("\n" + "=" * 60)
    print("Test 3: NACK Packet Format")
    print("=" * 60)

    host = LudpHost.__new__(LudpHost)
    host.next_cmd_id = 1

    # Build a NACK packet
    pkt = host._build_nack(miss_seq=0x12345678, count=5)

    print(f"Packet length: {len(pkt)} bytes (expected: 16)")
    assert len(pkt) == 16, f"Expected 16 bytes, got {len(pkt)}"

    magic = struct.unpack("<H", pkt[0:2])[0]
    pkt_type = pkt[2]
    miss_seq = struct.unpack("<I", pkt[4:8])[0]
    count = struct.unpack("<H", pkt[8:10])[0]

    print(f"Magic:      0x{magic:04X} (expected: 0x{LUDP_MAGIC:04X})")
    print(f"Type:       0x{pkt_type:02X} (expected: 0x{PKT_NACK:02X})")
    print(f"Miss Seq:   0x{miss_seq:08X} (expected: 0x12345678)")
    print(f"Count:      0x{count:04X} (expected: 0x0005)")

    assert magic == LUDP_MAGIC, f"Magic mismatch"
    assert pkt_type == PKT_NACK, f"Type mismatch"
    assert miss_seq == 0x12345678, f"Miss seq mismatch"
    assert count == 5, f"Count mismatch"

    print("\n[PASS] NACK packet format is correct")
    return True


def test_read_reg_packet():
    """Test READ_REG command format."""
    print("\n" + "=" * 60)
    print("Test 4: READ_REG Packet Format")
    print("=" * 60)

    host = LudpHost.__new__(LudpHost)
    host.next_cmd_id = 1

    # Build a READ_REG command
    pkt = host._build_cmd(CMD_READ_REG, arg1=0xABCD, flags=0x01, cmd_id=0x87654321)

    magic = struct.unpack("<H", pkt[0:2])[0]
    pkt_type = pkt[2]
    flags = pkt[3]
    cmd_id = struct.unpack("<I", pkt[4:8])[0]
    opcode = struct.unpack("<H", pkt[8:10])[0]
    arg1 = struct.unpack("<I", pkt[10:14])[0]

    print(f"Magic:      0x{magic:04X}")
    print(f"Type:       0x{pkt_type:02X}")
    print(f"Flags:      0x{flags:02X} (expected: 0x01 for read)")
    print(f"CMD ID:     0x{cmd_id:08X}")
    print(f"Opcode:     0x{opcode:04X} (expected: 0x{CMD_READ_REG:04X})")
    print(f"Arg1 (addr):0x{arg1:08X} (expected: 0x0000ABCD)")

    assert flags == 0x01, f"Flags should be 0x01 for read"
    assert opcode == CMD_READ_REG, f"Opcode mismatch"
    assert arg1 == 0xABCD, f"Address mismatch"

    print("\n[PASS] READ_REG packet format is correct")
    return True


def test_write_reg_packet():
    """Test WRITE_REG command format."""
    print("\n" + "=" * 60)
    print("Test 5: WRITE_REG Packet Format")
    print("=" * 60)

    host = LudpHost.__new__(LudpHost)
    host.next_cmd_id = 1

    # Build a WRITE_REG command (arg2 is 16-bit)
    pkt = host._build_cmd(CMD_WRITE_REG, arg1=0xABCD, arg2=0xBEEF, flags=0x00, cmd_id=0x11111111)

    magic = struct.unpack("<H", pkt[0:2])[0]
    pkt_type = pkt[2]
    flags = pkt[3]
    cmd_id = struct.unpack("<I", pkt[4:8])[0]
    opcode = struct.unpack("<H", pkt[8:10])[0]
    arg1 = struct.unpack("<I", pkt[10:14])[0]
    arg2 = struct.unpack("<H", pkt[14:16])[0]

    print(f"Magic:      0x{magic:04X}")
    print(f"Type:       0x{pkt_type:02X}")
    print(f"Flags:      0x{flags:02X} (expected: 0x00 for write)")
    print(f"CMD ID:     0x{cmd_id:08X}")
    print(f"Opcode:     0x{opcode:04X} (expected: 0x{CMD_WRITE_REG:04X})")
    print(f"Arg1 (addr):0x{arg1:08X} (expected: 0x0000ABCD)")
    print(f"Arg2 (data):0x{arg2:04X} (expected: 0xBEEF)")

    assert flags == 0x00, f"Flags should be 0x00 for write"
    assert opcode == CMD_WRITE_REG, f"Opcode mismatch"
    assert arg1 == 0xABCD, f"Address mismatch"
    assert arg2 == 0xBEEF, f"Data mismatch"

    print("\n[PASS] WRITE_REG packet format is correct")
    return True


def test_fpga_perspective():
    """Simulate what the FPGA sees when parsing a packet."""
    print("\n" + "=" * 60)
    print("Test 6: FPGA Perspective - Byte Order Verification")
    print("=" * 60)

    host = LudpHost.__new__(LudpHost)
    host.next_cmd_id = 1

    # Build a START command
    pkt = host._build_cmd(CMD_START, arg1=0, arg2=0, flags=0x00, cmd_id=0x00000001)

    # FPGA receives bytes via XGMII, first byte at tdata[7:0]
    # For a 64-bit word: byte0 at [7:0], byte1 at [15:8], ..., byte7 at [63:56]
    word0 = struct.unpack("<Q", pkt[0:8])[0]
    word1 = struct.unpack("<Q", pkt[8:16])[0]

    print("FPGA receives 64-bit words (little-endian byte order):")
    print(f"  Word 0: 0x{word0:016X}")
    print(f"    [7:0]   = 0x{word0 & 0xFF:02X} (Magic LSB = 0x01)")
    print(f"    [15:8]  = 0x{(word0 >> 8) & 0xFF:02X} (Magic MSB = 0xDA)")
    print(f"    [23:16] = 0x{(word0 >> 16) & 0xFF:02X} (Type = 0x02)")
    print(f"    [31:24] = 0x{(word0 >> 24) & 0xFF:02X} (Flags = 0x00)")
    print(f"    [63:32] = 0x{(word0 >> 32) & 0xFFFFFFFF:08X} (CMD ID = 0x00000001)")
    print(f"  Word 1: 0x{word1:016X}")
    print(f"    [15:0]  = 0x{word1 & 0xFFFF:04X} (Opcode = 0x0001)")
    print(f"    [47:16] = 0x{(word1 >> 16) & 0xFFFFFFFF:08X} (Arg1 = 0x00000000)")
    print(f"    [63:48] = 0x{(word1 >> 48) & 0xFFFF:04X} (Arg2 = 0x0000)")

    # Verify the magic number appears correctly
    magic_from_word0 = word0 & 0xFFFF
    print(f"\nMagic extracted from word0[15:0]: 0x{magic_from_word0:04X}")
    assert magic_from_word0 == LUDP_MAGIC, f"Magic should be 0x{LUDP_MAGIC:04X}"

    type_from_word0 = (word0 >> 16) & 0xFF
    print(f"Type extracted from word0[23:16]: 0x{type_from_word0:02X}")
    assert type_from_word0 == PKT_CMD, f"Type should be 0x{PKT_CMD:02X}"

    print("\n[PASS] FPGA perspective byte order is correct")
    return True


def main():
    print("LUDP Host Protocol Validation Tests")
    print("=" * 60)
    print("These tests verify that ludp_host.py generates packets")
    print("with the correct little-endian byte order that the FPGA expects.")
    print("=" * 60)

    tests = [
        test_cmd_packet_format,
        test_credit_packet_format,
        test_nack_packet_format,
        test_read_reg_packet,
        test_write_reg_packet,
        test_fpga_perspective,
    ]

    passed = 0
    failed = 0

    for test in tests:
        try:
            if test():
                passed += 1
        except AssertionError as e:
            print(f"\n[FAIL] {test.__name__}: {e}")
            failed += 1
        except Exception as e:
            print(f"\n[ERROR] {test.__name__}: {e}")
            failed += 1

    print("\n" + "=" * 60)
    print(f"Results: {passed} passed, {failed} failed")
    print("=" * 60)

    if failed == 0:
        print("All tests PASSED - ludp_host.py generates correctly formatted packets")
        return 0
    else:
        print("Some tests FAILED - packet format may be incompatible with FPGA")
        return 1


if __name__ == "__main__":
    sys.exit(main())
