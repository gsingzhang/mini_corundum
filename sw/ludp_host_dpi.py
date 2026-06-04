#!/usr/bin/env python3
"""
LUDP Host for DPI-C Co-Simulation

This version of ludp_host sends packets over a Unix domain socket
instead of real UDP sockets, allowing co-simulation with VCS.

Usage:
    python ludp_host_dpi.py --mode generate --script <test_script.py>

The script will:
1. Connect to the DPI-C socket server (created by VCS)
2. Run the specified test script to generate LUDP packets
3. Send packets to the DUT via the socket
4. Optionally receive responses and validate them
"""

import struct
import socket
import time
import sys
import os
import argparse
import importlib.util

# Add parent directory to path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from ludp_host import LudpHost, LUDP_MAGIC, LUDP_PORT, PKT_CMD, PKT_CREDIT, PKT_NACK

SOCKET_PATH = "/tmp/ludp_dpi_socket"


class LudpHostDPI(LudpHost):
    """LUDP Host that sends packets via Unix domain socket for DPI-C co-simulation."""

    def __init__(self, fpga_ip="192.168.1.128", fpga_port=LUDP_PORT, window_size=64):
        # Don't call parent __init__ (it creates a real socket)
        self.fpga_ip = fpga_ip
        self.fpga_port = fpga_port
        self.window_size = window_size
        self.abs_credit = 0
        self.next_cmd_id = 1
        self.sock = None
        self.connected = False
        self.sent_packets = []
        self.received_packets = []

    def connect_dpi(self, timeout=30):
        """Connect to DPI-C socket server."""
        print(f"[DPI-Client] Connecting to {SOCKET_PATH}...")
        start_time = time.time()

        while time.time() - start_time < timeout:
            try:
                self.sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                self.sock.connect(SOCKET_PATH)
                self.connected = True
                print(f"[DPI-Client] Connected to DPI-C socket server")
                return True
            except (socket.error, FileNotFoundError):
                if self.sock:
                    self.sock.close()
                    self.sock = None
                time.sleep(0.1)

        print(f"[DPI-Client] Failed to connect within {timeout} seconds")
        return False

    def disconnect(self):
        """Disconnect from DPI-C socket."""
        if self.sock:
            self.sock.close()
            self.sock = None
        self.connected = False
        print("[DPI-Client] Disconnected")

    def _send_packet(self, data):
        """Send packet via DPI-C socket."""
        if not self.connected or not self.sock:
            raise RuntimeError("Not connected to DPI-C socket")

        # Packet format: [4 bytes length (little-endian)] [packet data]
        length = len(data)
        header = struct.pack("<I", length)
        self.sock.sendall(header + data)
        self.sent_packets.append(data)
        return True

    def send_cmd(self, opcode, arg1=0, arg2=0, flags=0x00):
        """Send a command packet."""
        cmd_id = self.next_cmd_id
        self.next_cmd_id += 1
        pkt = self._build_cmd(opcode, arg1, arg2, flags, cmd_id)
        self._send_packet(pkt)
        return cmd_id

    def send_credit(self, abs_credit):
        """Send a credit packet."""
        pkt = self._build_credit(abs_credit)
        self._send_packet(pkt)
        self.abs_credit = abs_credit
        return True

    def send_nack(self, miss_seq, count):
        """Send a NACK packet."""
        pkt = self._build_nack(miss_seq, count)
        self._send_packet(pkt)
        return True

    def receive_response(self, timeout=5.0):
        """Receive response from DUT (not implemented in this direction)."""
        # In DPI mode, responses are captured by the testbench, not Python
        return None


def run_test_script(script_path, host):
    """Run a user-provided test script."""
    print(f"[DPI-Client] Loading test script: {script_path}")

    # Load the test script as a module
    spec = importlib.util.spec_from_file_location("test_script", script_path)
    module = importlib.util.module_from_spec(spec)
    sys.modules["test_script"] = module
    spec.loader.exec_module(module)

    # Run the test function if it exists
    if hasattr(module, 'run_test'):
        print("[DPI-Client] Executing run_test() function...")
        module.run_test(host)
    else:
        print("[DPI-Client] Warning: No run_test() function found in script")


def generate_arp_request():
    """Generate a raw ARP request packet (Ethernet + ARP)."""
    # Ethernet header
    eth_dst = b'\xff\xff\xff\xff\xff\xff'  # Broadcast
    eth_src = b'\x02\x00\x00\x00\x00\x01'  # Host MAC
    eth_type = struct.pack(">H", 0x0806)  # ARP

    # ARP packet
    hw_type = struct.pack(">H", 1)       # Ethernet
    proto_type = struct.pack(">H", 0x0800)  # IPv4
    hw_len = b'\x06'
    proto_len = b'\x04'
    opcode = struct.pack(">H", 1)        # Request
    sender_mac = eth_src
    sender_ip = struct.pack(">I", 0xC0A801C7)  # 192.168.1.199
    target_mac = b'\x00\x00\x00\x00\x00\x00'
    target_ip = struct.pack(">I", 0xC0A80180)  # 192.168.1.128

    arp_packet = (hw_type + proto_type + hw_len + proto_len + opcode +
                  sender_mac + sender_ip + target_mac + target_ip)

    # Pad to minimum Ethernet frame size (60 bytes without FCS)
    frame = eth_dst + eth_src + eth_type + arp_packet
    while len(frame) < 60:
        frame += b'\x00'

    return frame


def generate_icmp_echo_request(identifier=0x1234, sequence=0x0001, payload_size=32):
    """Generate a raw ICMP echo request packet."""
    # Ethernet header
    eth_dst = b'\x02\x00\x00\x00\x00\x00'  # FPGA MAC
    eth_src = b'\x02\x00\x00\x00\x00\x01'  # Host MAC
    eth_type = struct.pack(">H", 0x0800)  # IPv4

    # IP header
    ip_version_ihl = 0x45
    ip_dscp_ecn = 0x00
    ip_total_length = 20 + 8 + payload_size  # IP header + ICMP header + payload
    ip_id = 0x0000
    ip_flags_frag = 0x4000  # Don't fragment
    ip_ttl = 64
    ip_proto = 1  # ICMP
    ip_checksum = 0  # Will be calculated
    ip_src = struct.pack(">I", 0xC0A801C7)  # 192.168.1.199
    ip_dst = struct.pack(">I", 0xC0A80180)  # 192.168.1.128

    ip_header = struct.pack(">BBHHHBBH", ip_version_ihl, ip_dscp_ecn, ip_total_length,
                            ip_id, ip_flags_frag, ip_ttl, ip_proto, ip_checksum) + ip_src + ip_dst

    # Calculate IP checksum
    ip_checksum = calculate_checksum(ip_header)
    ip_header = struct.pack(">BBHHHBBH", ip_version_ihl, ip_dscp_ecn, ip_total_length,
                            ip_id, ip_flags_frag, ip_ttl, ip_proto, ip_checksum) + ip_src + ip_dst

    # ICMP header
    icmp_type = 8   # Echo request
    icmp_code = 0
    icmp_checksum = 0  # Will be calculated
    icmp_id = identifier
    icmp_seq = sequence

    icmp_header = struct.pack(">BBHHH", icmp_type, icmp_code, icmp_checksum, icmp_id, icmp_seq)

    # ICMP payload
    payload = bytes([i & 0xFF for i in range(payload_size)])

    # Calculate ICMP checksum
    icmp_checksum = calculate_checksum(icmp_header + payload)
    icmp_header = struct.pack(">BBHHH", icmp_type, icmp_code, icmp_checksum, icmp_id, icmp_seq)

    # Full ICMP packet
    icmp_packet = icmp_header + payload

    # Full IP packet
    ip_packet = ip_header + icmp_packet

    # Full Ethernet frame
    frame = eth_dst + eth_src + eth_type + ip_packet

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


def generate_ludp_start():
    """Generate a raw LUDP START command packet (Ethernet + IP + UDP + LUDP)."""
    # Ethernet header
    eth_dst = b'\x02\x00\x00\x00\x00\x00'
    eth_src = b'\x02\x00\x00\x00\x00\x01'
    eth_type = struct.pack(">H", 0x0800)

    # UDP payload (LUDP packet)
    ludp_pkt = struct.pack("<HBBIHIH",
                           LUDP_MAGIC,    # magic
                           PKT_CMD,       # type
                           0x00,          # flags
                           0x00000001,    # cmd_id
                           0x0001,        # opcode = START
                           0x00000000,    # arg1
                           0x0000)        # arg2

    # UDP header
    udp_src_port = 12345
    udp_dst_port = LUDP_PORT
    udp_length = 8 + len(ludp_pkt)
    udp_checksum = 0

    udp_header = struct.pack(">HHHH", udp_src_port, udp_dst_port, udp_length, udp_checksum)

    # IP header
    ip_version_ihl = 0x45
    ip_dscp_ecn = 0x00
    ip_total_length = 20 + len(udp_header) + len(ludp_pkt)
    ip_id = 0x0001
    ip_flags_frag = 0x4000
    ip_ttl = 64
    ip_proto = 17  # UDP
    ip_checksum = 0
    ip_src = struct.pack(">I", 0xC0A801C7)
    ip_dst = struct.pack(">I", 0xC0A80180)

    ip_header = struct.pack(">BBHHHBBH", ip_version_ihl, ip_dscp_ecn, ip_total_length,
                            ip_id, ip_flags_frag, ip_ttl, ip_proto, ip_checksum) + ip_src + ip_dst

    ip_checksum = calculate_checksum(ip_header)
    ip_header = struct.pack(">BBHHHBBH", ip_version_ihl, ip_dscp_ecn, ip_total_length,
                            ip_id, ip_flags_frag, ip_ttl, ip_proto, ip_checksum) + ip_src + ip_dst

    # Full frame
    frame = eth_dst + eth_src + eth_type + ip_header + udp_header + ludp_pkt

    return frame


def generate_ludp_credit(credit_value=64):
    """Generate a raw LUDP CREDIT packet."""
    eth_dst = b'\x02\x00\x00\x00\x00\x00'
    eth_src = b'\x02\x00\x00\x00\x00\x01'
    eth_type = struct.pack(">H", 0x0800)

    # LUDP CREDIT packet
    ludp_pkt = struct.pack("<HBBIHIH",
                           LUDP_MAGIC,
                           PKT_CREDIT,
                           0x00,
                           credit_value,  # abs_credit
                           0x0000,
                           0x00000000,
                           0x0000)

    # UDP header
    udp_src_port = 12345
    udp_dst_port = LUDP_PORT
    udp_length = 8 + len(ludp_pkt)
    udp_checksum = 0
    udp_header = struct.pack(">HHHH", udp_src_port, udp_dst_port, udp_length, udp_checksum)

    # IP header
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
    parser = argparse.ArgumentParser(description='LUDP Host DPI-C Co-Simulation')
    parser.add_argument('--mode', choices=['generate', 'interactive'], default='generate',
                        help='Operation mode')
    parser.add_argument('--script', type=str, help='Test script to run')
    parser.add_argument('--fpga-ip', type=str, default='192.168.1.128')
    parser.add_argument('--fpga-port', type=int, default=LUDP_PORT)
    parser.add_argument('--packet-type', choices=['arp', 'icmp', 'ludp_start', 'ludp_credit'],
                        help='Generate a specific packet type')

    args = parser.parse_args()

    host = LudpHostDPI(args.fpga_ip, args.fpga_port)

    if not host.connect_dpi():
        print("[DPI-Client] Failed to connect, exiting")
        return 1

    try:
        if args.packet_type:
            # Generate specific packet type
            if args.packet_type == 'arp':
                pkt = generate_arp_request()
                print(f"[DPI-Client] Sending ARP request ({len(pkt)} bytes)")
                host._send_packet(pkt)
            elif args.packet_type == 'icmp':
                pkt = generate_icmp_echo_request()
                print(f"[DPI-Client] Sending ICMP echo request ({len(pkt)} bytes)")
                host._send_packet(pkt)
            elif args.packet_type == 'ludp_start':
                pkt = generate_ludp_start()
                print(f"[DPI-Client] Sending LUDP START ({len(pkt)} bytes)")
                host._send_packet(pkt)
            elif args.packet_type == 'ludp_credit':
                pkt = generate_ludp_credit()
                print(f"[DPI-Client] Sending LUDP CREDIT ({len(pkt)} bytes)")
                host._send_packet(pkt)

            # Wait a bit for processing
            time.sleep(1)

        elif args.script:
            run_test_script(args.script, host)

        else:
            print("[DPI-Client] No packet type or script specified")
            parser.print_help()

    finally:
        host.disconnect()

    return 0


if __name__ == "__main__":
    sys.exit(main())
