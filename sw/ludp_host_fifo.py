#!/usr/bin/env python3
"""
LUDP Host for FIFO-based Co-Simulation

This version writes packets to a file that the VCS simulation reads via DPI-C.
This avoids socket-related issues with VCS.

Usage:
    python ludp_host_fifo.py --packet-type arp
    python ludp_host_fifo.py --packet-type icmp
    python ludp_host_fifo.py --packet-type ludp_start
"""

import struct
import sys
import os
import argparse

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from ludp_host import LUDP_MAGIC, LUDP_PORT, PKT_CMD, PKT_CREDIT, PKT_NACK, CMD_START

FIFO_DIR = "/tmp/ludp_dpi_fifo"
PACKET_FILE = f"{FIFO_DIR}/packets.bin"


def write_packets_to_file(packets):
    """Write packets to file for DPI-C to read."""
    os.makedirs(FIFO_DIR, exist_ok=True)

    with open(PACKET_FILE, "wb") as f:
        # Write packet count
        count = len(packets)
        f.write(struct.pack("<I", count))

        # Write each packet with length prefix
        for pkt in packets:
            f.write(struct.pack("<I", len(pkt)))
            f.write(pkt)

    print(f"[FIFO-Client] Wrote {count} packets to {PACKET_FILE}")


def generate_arp_request():
    """Generate a raw ARP request packet."""
    eth_dst = b'\xff\xff\xff\xff\xff\xff'
    eth_src = b'\x02\x00\x00\x00\x00\x01'
    eth_type = struct.pack(">H", 0x0806)

    hw_type = struct.pack(">H", 1)
    proto_type = struct.pack(">H", 0x0800)
    hw_len = b'\x06'
    proto_len = b'\x04'
    opcode = struct.pack(">H", 1)
    sender_mac = eth_src
    sender_ip = struct.pack(">I", 0xC0A801C7)
    target_mac = b'\x00\x00\x00\x00\x00\x00'
    target_ip = struct.pack(">I", 0xC0A80180)

    arp_packet = (hw_type + proto_type + hw_len + proto_len + opcode +
                  sender_mac + sender_ip + target_mac + target_ip)

    frame = eth_dst + eth_src + eth_type + arp_packet
    while len(frame) < 60:
        frame += b'\x00'

    return frame


def calculate_checksum(data):
    """Calculate Internet checksum."""
    if len(data) % 2 == 1:
        data += b'\x00'
    checksum = 0
    for i in range(0, len(data), 2):
        word = (data[i] << 8) + data[i + 1]
        checksum += word
    while checksum >> 16:
        checksum = (checksum & 0xFFFF) + (checksum >> 16)
    return ~checksum & 0xFFFF


def generate_icmp_echo_request(identifier=0x1234, sequence=0x0001, payload_size=32):
    """Generate a raw ICMP echo request packet."""
    eth_dst = b'\x02\x00\x00\x00\x00\x00'
    eth_src = b'\x02\x00\x00\x00\x00\x01'
    eth_type = struct.pack(">H", 0x0800)

    ip_version_ihl = 0x45
    ip_dscp_ecn = 0x00
    ip_total_length = 20 + 8 + payload_size
    ip_id = 0x0000
    ip_flags_frag = 0x4000
    ip_ttl = 64
    ip_proto = 1
    ip_checksum = 0
    ip_src = struct.pack(">I", 0xC0A801C7)
    ip_dst = struct.pack(">I", 0xC0A80180)

    ip_header = struct.pack(">BBHHHBBH", ip_version_ihl, ip_dscp_ecn, ip_total_length,
                            ip_id, ip_flags_frag, ip_ttl, ip_proto, ip_checksum) + ip_src + ip_dst

    ip_checksum = calculate_checksum(ip_header)
    ip_header = struct.pack(">BBHHHBBH", ip_version_ihl, ip_dscp_ecn, ip_total_length,
                            ip_id, ip_flags_frag, ip_ttl, ip_proto, ip_checksum) + ip_src + ip_dst

    icmp_type = 8
    icmp_code = 0
    icmp_checksum = 0
    icmp_id = identifier
    icmp_seq = sequence

    icmp_header = struct.pack(">BBHHH", icmp_type, icmp_code, icmp_checksum, icmp_id, icmp_seq)
    payload = bytes([i & 0xFF for i in range(payload_size)])
    icmp_checksum = calculate_checksum(icmp_header + payload)
    icmp_header = struct.pack(">BBHHH", icmp_type, icmp_code, icmp_checksum, icmp_id, icmp_seq)

    icmp_packet = icmp_header + payload
    ip_packet = ip_header + icmp_packet
    frame = eth_dst + eth_src + eth_type + ip_packet

    return frame


def generate_ludp_start():
    """Generate a raw LUDP START command packet."""
    eth_dst = b'\x02\x00\x00\x00\x00\x00'
    eth_src = b'\x02\x00\x00\x00\x00\x01'
    eth_type = struct.pack(">H", 0x0800)

    ludp_pkt = struct.pack("<HBBIHIH",
                           LUDP_MAGIC,
                           PKT_CMD,
                           0x00,
                           0x00000001,
                           0x0001,
                           0x00000000,
                           0x0000)

    udp_src_port = 12345
    udp_dst_port = LUDP_PORT
    udp_length = 8 + len(ludp_pkt)
    udp_checksum = 0
    udp_header = struct.pack(">HHHH", udp_src_port, udp_dst_port, udp_length, udp_checksum)

    ip_version_ihl = 0x45
    ip_dscp_ecn = 0x00
    ip_total_length = 20 + len(udp_header) + len(ludp_pkt)
    ip_id = 0x0001
    ip_flags_frag = 0x4000
    ip_ttl = 64
    ip_proto = 17
    ip_checksum = 0
    ip_src = struct.pack(">I", 0xC0A801C7)
    ip_dst = struct.pack(">I", 0xC0A80180)

    ip_header = struct.pack(">BBHHHBBH", ip_version_ihl, ip_dscp_ecn, ip_total_length,
                            ip_id, ip_flags_frag, ip_ttl, ip_proto, ip_checksum) + ip_src + ip_dst

    ip_checksum = calculate_checksum(ip_header)
    ip_header = struct.pack(">BBHHHBBH", ip_version_ihl, ip_dscp_ecn, ip_total_length,
                            ip_id, ip_flags_frag, ip_ttl, ip_proto, ip_checksum) + ip_src + ip_dst

    frame = eth_dst + eth_src + eth_type + ip_header + udp_header + ludp_pkt
    return frame


def generate_ludp_credit(credit_value=64):
    """Generate a raw LUDP CREDIT packet."""
    eth_dst = b'\x02\x00\x00\x00\x00\x00'
    eth_src = b'\x02\x00\x00\x00\x00\x01'
    eth_type = struct.pack(">H", 0x0800)

    ludp_pkt = struct.pack("<HBBIHIH",
                           LUDP_MAGIC,
                           PKT_CREDIT,
                           0x00,
                           credit_value,
                           0x0000,
                           0x00000000,
                           0x0000)

    udp_src_port = 12345
    udp_dst_port = LUDP_PORT
    udp_length = 8 + len(ludp_pkt)
    udp_checksum = 0
    udp_header = struct.pack(">HHHH", udp_src_port, udp_dst_port, udp_length, udp_checksum)

    ip_version_ihl = 0x45
    ip_dscp_ecn = 0x00
    ip_total_length = 20 + len(udp_header) + len(ludp_pkt)
    ip_id = 0x0002
    ip_flags_frag = 0x4000
    ip_ttl = 64
    ip_proto = 17
    ip_checksum = 0
    ip_src = struct.pack(">I", 0xC0A801C7)
    ip_dst = struct.pack(">I", 0xC0A80180)

    ip_header = struct.pack(">BBHHHBBH", ip_version_ihl, ip_dscp_ecn, ip_total_length,
                            ip_id, ip_flags_frag, ip_ttl, ip_proto, ip_checksum) + ip_src + ip_dst

    ip_checksum = calculate_checksum(ip_header)
    ip_header = struct.pack(">BBHHHBBH", ip_version_ihl, ip_dscp_ecn, ip_total_length,
                            ip_id, ip_flags_frag, ip_ttl, ip_proto, ip_checksum) + ip_src + ip_dst

    frame = eth_dst + eth_src + eth_type + ip_header + udp_header + ludp_pkt
    return frame


def main():
    parser = argparse.ArgumentParser(description='LUDP Host FIFO-based Co-Simulation')
    parser.add_argument('--packet-type', choices=['arp', 'icmp', 'ludp_start', 'ludp_credit', 'ludp_full'],
                        required=True, help='Type of packet to generate')
    parser.add_argument('--credit', type=int, default=64, help='Credit value for LUDP CREDIT')

    args = parser.parse_args()

    packets = []

    if args.packet_type == 'arp':
        packets.append(generate_arp_request())
    elif args.packet_type == 'icmp':
        packets.append(generate_icmp_echo_request())
    elif args.packet_type == 'ludp_start':
        packets.append(generate_ludp_start())
    elif args.packet_type == 'ludp_credit':
        packets.append(generate_ludp_credit(args.credit))
    elif args.packet_type == 'ludp_full':
        # Full sequence: ARP -> LUDP START -> LUDP CREDIT
        packets.append(generate_arp_request())
        packets.append(generate_ludp_start())
        packets.append(generate_ludp_credit(args.credit))

    write_packets_to_file(packets)
    print(f"[FIFO-Client] Done. Run VCS simulation to process packets.")

    return 0


if __name__ == "__main__":
    sys.exit(main())
