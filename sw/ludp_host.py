#!/usr/bin/env python3
"""
LUDP Host Application - Python reference implementation for PC side.

This application implements the Lightweight Ultrasonic DAQ Protocol (LUDP)
to communicate with the FPGA over UDP. It handles:
  - Command sending (START, STOP, READ_REG, WRITE_REG)
  - Credit-based flow control
  - High-throughput data reception with sequence tracking
  - NACK-based retransmission for lost packets
  - Out-of-order packet buffering and reordering

Usage:
    python ludp_host.py --fpga-ip 192.168.1.128 --duration 10

Requirements:
    - Python 3.7+
    - 10G Ethernet NIC with jumbo frame support (MTU >= 9000)
    - FPGA running LUDP bitstream connected via SFP+
"""

import argparse
import socket
import struct
import sys
import threading
import time
from collections import defaultdict
from dataclasses import dataclass, field
from typing import Callable, Dict, List, Optional

# ============================================================================
# LUDP Protocol Constants
# ============================================================================

LUDP_PORT = 1234
LUDP_MAGIC = 0xDA01

# Packet Types
PKT_DATA = 0x01
PKT_CMD = 0x02
PKT_NACK = 0x03
PKT_CMD_ACK = 0x04
PKT_CMD_CPL = 0x05
PKT_CREDIT = 0x06

# CMD Opcodes
CMD_START = 0x0001
CMD_STOP = 0x0002
CMD_READ_REG = 0x0010
CMD_WRITE_REG = 0x0011

# LUDP Header Sizes
LUDP_HDR_LEN = 16  # bytes

# Default window size for credit-based flow control
DEFAULT_WINDOW_SIZE = 1024  # packets
DEFAULT_CREDIT_INTERVAL = 64  # Send credit update every N packets received


# ============================================================================
# Data Structures
# ============================================================================

@dataclass
class LudpDataPacket:
    """Represents a received LUDP DATA packet."""
    magic: int
    pkt_type: int
    flags: int
    seq_num: int
    payload_len: int
    timestamp: int
    payload: bytes

    @property
    def is_retransmit(self) -> bool:
        return (self.flags & 0x01) != 0


@dataclass
class LudpStats:
    """Runtime statistics for monitoring."""
    packets_received: int = 0
    packets_processed: int = 0
    packets_out_of_order: int = 0
    packets_retransmitted: int = 0
    nacks_sent: int = 0
    credits_sent: int = 0
    bytes_received: int = 0
    start_time: float = 0.0
    last_seq: int = -1
    gap_count: int = 0

    @property
    def throughput_mbps(self) -> float:
        """Calculate throughput in Mbps."""
        elapsed = time.time() - self.start_time
        if elapsed <= 0:
            return 0.0
        return (self.bytes_received * 8) / (elapsed * 1e6)

    @property
    def packet_rate_kpps(self) -> float:
        """Calculate packet rate in kpps."""
        elapsed = time.time() - self.start_time
        if elapsed <= 0:
            return 0.0
        return self.packets_received / (elapsed * 1000)

    def __str__(self) -> str:
        elapsed = time.time() - self.start_time
        return (
            f"Stats: {self.packets_processed} processed, "
            f"{self.packets_out_of_order} OOO, "
            f"{self.packets_retransmitted} retrans, "
            f"{self.nacks_sent} NACKs, "
            f"{self.throughput_mbps:.1f} Mbps, "
            f"{self.packet_rate_kpps:.1f} kpps, "
            f"elapsed={elapsed:.1f}s"
        )


# ============================================================================
# LUDP Host Class
# ============================================================================

class LudpHost:
    """
    LUDP Host implementation.

    Manages the UDP socket, handles incoming DATA packets, sends CREDIT/NACK/CMD
    packets, and provides ordered data delivery to the application layer.
    """

    def __init__(
        self,
        fpga_ip: str,
        local_port: int = LUDP_PORT,
        window_size: int = DEFAULT_WINDOW_SIZE,
        credit_interval: int = DEFAULT_CREDIT_INTERVAL,
        nack_timeout_ms: float = 5.0,
        credit_poll_ms: float = 50.0,
        cmd_timeout_ms: float = 100.0,
        on_data: Optional[Callable[[LudpDataPacket], None]] = None,
    ):
        self.fpga_ip = fpga_ip
        self.fpga_addr = (fpga_ip, LUDP_PORT)
        self.local_port = local_port
        self.window_size = window_size
        self.credit_interval = credit_interval
        self.nack_timeout_ms = nack_timeout_ms
        self.credit_poll_ms = credit_poll_ms
        self.cmd_timeout_ms = cmd_timeout_ms
        self.on_data = on_data

        # Socket setup
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.bind(("0.0.0.0", local_port))
        # Increase socket buffer sizes for high-throughput reception
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 256 * 1024 * 1024)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 16 * 1024 * 1024)

        # State
        self.expected_seq = 0
        self.abs_credit = window_size
        self.out_of_order: Dict[int, LudpDataPacket] = {}
        self.pending_nacks: Dict[int, float] = {}  # seq -> last_nack_time
        self.running = False
        self.stats = LudpStats()

        # Threading
        self.recv_thread: Optional[threading.Thread] = None
        self.poll_thread: Optional[threading.Thread] = None
        self.lock = threading.Lock()

        # CMD pending response tracking
        self.pending_cmds: Dict[int, Dict] = {}  # cmd_id -> {"event": Event, "response": bytes}
        self.next_cmd_id = 1

    # ------------------------------------------------------------------
    # Packet Builders
    # ------------------------------------------------------------------

    def _build_cmd(
        self,
        opcode: int,
        arg1: int = 0,
        arg2: int = 0,
        flags: int = 0x00,
        cmd_id: Optional[int] = None,
    ) -> bytes:
        """Build a CMD packet (16 bytes)."""
        if cmd_id is None:
            cmd_id = self.next_cmd_id
            self.next_cmd_id += 1
        return struct.pack(
            ">HBBIHHI",
            LUDP_MAGIC,
            PKT_CMD,
            flags,
            cmd_id,
            opcode,
            arg1,
            arg2,
        )

    def _build_credit(self, abs_credit: int) -> bytes:
        """Build a CREDIT packet (16 bytes)."""
        return struct.pack(
            ">HBBIQ",
            LUDP_MAGIC,
            PKT_CREDIT,
            0x00,
            abs_credit,
            0,  # Reserved (8 bytes pad)
        )

    def _build_nack(self, miss_seq: int, count: int = 1) -> bytes:
        """Build a NACK packet (16 bytes)."""
        return struct.pack(
            ">HBBIHQ",
            LUDP_MAGIC,
            PKT_NACK,
            0x00,
            miss_seq,
            count,
            0,  # Reserved (6 bytes pad + 2 bytes)
        )

    # ------------------------------------------------------------------
    # Public API: Commands
    # ------------------------------------------------------------------

    def send_start(self) -> bool:
        """Send START command to FPGA. Returns True if ACK received."""
        return self._send_cmd_wait_ack(CMD_START, "START")

    def send_stop(self) -> bool:
        """Send STOP command to FPGA. Returns True if ACK received."""
        return self._send_cmd_wait_ack(CMD_STOP, "STOP")

    def write_reg(self, addr: int, data: int) -> bool:
        """Write to FPGA register. Returns True if ACK received."""
        return self._send_cmd_wait_ack(CMD_WRITE_REG, "WRITE_REG", arg1=addr, arg2=data)

    def read_reg(self, addr: int) -> Optional[int]:
        """Read FPGA register. Returns register value or None on timeout."""
        cmd_id = self.next_cmd_id
        self.next_cmd_id += 1
        pkt = self._build_cmd(CMD_READ_REG, arg1=addr, flags=0x01, cmd_id=cmd_id)

        with self.lock:
            self.pending_cmds[cmd_id] = {
                "event": threading.Event(),
                "response": None,
            }

        self.sock.sendto(pkt, self.fpga_addr)

        # Wait for CMD_CPL
        if self.pending_cmds[cmd_id]["event"].wait(timeout=self.cmd_timeout_ms / 1000.0):
            with self.lock:
                resp = self.pending_cmds[cmd_id]["response"]
                del self.pending_cmds[cmd_id]
            if resp and len(resp) >= 16:
                # Parse CMD_CPL: Read_Data at offset 10 (32-bit)
                read_data = struct.unpack(">I", resp[10:14])[0]
                return read_data
        else:
            with self.lock:
                if cmd_id in self.pending_cmds:
                    del self.pending_cmds[cmd_id]
        return None

    def _send_cmd_wait_ack(
        self, opcode: int, name: str, arg1: int = 0, arg2: int = 0
    ) -> bool:
        """Send a posted CMD and wait for CMD_ACK."""
        cmd_id = self.next_cmd_id
        self.next_cmd_id += 1
        pkt = self._build_cmd(opcode, arg1=arg1, arg2=arg2, flags=0x00, cmd_id=cmd_id)

        with self.lock:
            self.pending_cmds[cmd_id] = {
                "event": threading.Event(),
                "response": None,
            }

        self.sock.sendto(pkt, self.fpga_addr)

        success = self.pending_cmds[cmd_id]["event"].wait(
            timeout=self.cmd_timeout_ms / 1000.0
        )
        with self.lock:
            if cmd_id in self.pending_cmds:
                del self.pending_cmds[cmd_id]

        if success:
            print(f"[OK] {name} command acknowledged")
        else:
            print(f"[TIMEOUT] {name} command no ACK")
        return success

    def send_credit(self, abs_credit: int) -> None:
        """Send explicit credit update to FPGA."""
        pkt = self._build_credit(abs_credit)
        self.sock.sendto(pkt, self.fpga_addr)
        with self.lock:
            self.stats.credits_sent += 1

    # ------------------------------------------------------------------
    # Receive Loop
    # ------------------------------------------------------------------

    def start(self) -> None:
        """Start the receive and polling threads."""
        self.running = True
        self.stats.start_time = time.time()
        self.recv_thread = threading.Thread(target=self._recv_loop, daemon=True)
        self.poll_thread = threading.Thread(target=self._poll_loop, daemon=True)
        self.recv_thread.start()
        self.poll_thread.start()
        print(f"[LUDP] Host started. FPGA={self.fpga_ip}:{LUDP_PORT}")

    def stop(self) -> None:
        """Stop all threads and close socket."""
        self.running = False
        if self.recv_thread:
            self.recv_thread.join(timeout=2.0)
        if self.poll_thread:
            self.poll_thread.join(timeout=2.0)
        self.sock.close()
        print("[LUDP] Host stopped.")

    def _recv_loop(self) -> None:
        """Main receive loop running in a dedicated thread."""
        while self.running:
            try:
                data, addr = self.sock.recvfrom(65535)
            except OSError:
                break  # Socket closed

            if len(data) < LUDP_HDR_LEN:
                continue

            # Parse header
            magic = struct.unpack(">H", data[0:2])[0]
            if magic != LUDP_MAGIC:
                continue

            pkt_type = data[2]

            if pkt_type == PKT_DATA:
                self._handle_data(data)
            elif pkt_type == PKT_CMD_ACK:
                self._handle_cmd_ack(data)
            elif pkt_type == PKT_CMD_CPL:
                self._handle_cmd_cpl(data)
            # Ignore other types (we don't expect CMD/NACK/CREDIT from FPGA)

    def _handle_data(self, data: bytes) -> None:
        """Process an incoming DATA packet."""
        if len(data) < LUDP_HDR_LEN:
            return

        pkt = LudpDataPacket(
            magic=struct.unpack(">H", data[0:2])[0],
            pkt_type=data[2],
            flags=data[3],
            seq_num=struct.unpack(">I", data[4:8])[0],
            payload_len=struct.unpack(">H", data[8:10])[0],
            timestamp=struct.unpack(">I", data[10:14])[0],
            payload=data[LUDP_HDR_LEN:],
        )

        with self.lock:
            self.stats.packets_received += 1
            self.stats.bytes_received += len(data)
            self.stats.last_seq = pkt.seq_num

            if pkt.is_retransmit:
                self.stats.packets_retransmitted += 1

        # In-order packet
        if pkt.seq_num == self.expected_seq:
            self._deliver(pkt)
            self.expected_seq += 1

            # Drain out-of-order buffer
            while self.expected_seq in self.out_of_order:
                self._deliver(self.out_of_order[self.expected_seq])
                del self.out_of_order[self.expected_seq]
                self.expected_seq += 1

            # Send credit update
            if self.expected_seq % self.credit_interval == 0:
                new_credit = self.expected_seq + self.window_size
                self.send_credit(new_credit)
                self.abs_credit = new_credit

        # Future packet (gap detected)
        elif pkt.seq_num > self.expected_seq:
            with self.lock:
                self.stats.packets_out_of_order += 1
                self.stats.gap_count += 1

            # Store out-of-order packet
            self.out_of_order[pkt.seq_num] = pkt

            # Send NACK for missing sequences
            for miss_seq in range(self.expected_seq, pkt.seq_num):
                now = time.time() * 1000
                last_nack = self.pending_nacks.get(miss_seq, 0)
                if now - last_nack > self.nack_timeout_ms:
                    nack_pkt = self._build_nack(miss_seq, pkt.seq_num - self.expected_seq)
                    self.sock.sendto(nack_pkt, self.fpga_addr)
                    self.pending_nacks[miss_seq] = now
                    with self.lock:
                        self.stats.nacks_sent += 1

        # Old packet (retransmission we already processed)
        else:
            if pkt.is_retransmit and pkt.seq_num in self.pending_nacks:
                del self.pending_nacks[pkt.seq_num]

    def _deliver(self, pkt: LudpDataPacket) -> None:
        """Deliver an in-order packet to the application layer."""
        with self.lock:
            self.stats.packets_processed += 1
        if self.on_data:
            self.on_data(pkt)

    def _handle_cmd_ack(self, data: bytes) -> None:
        """Handle CMD_ACK from FPGA."""
        if len(data) < 12:
            return
        cmd_id = struct.unpack(">I", data[4:8])[0]
        with self.lock:
            if cmd_id in self.pending_cmds:
                self.pending_cmds[cmd_id]["response"] = data
                self.pending_cmds[cmd_id]["event"].set()

    def _handle_cmd_cpl(self, data: bytes) -> None:
        """Handle CMD_CPL from FPGA."""
        if len(data) < 16:
            return
        cmd_id = struct.unpack(">I", data[4:8])[0]
        with self.lock:
            if cmd_id in self.pending_cmds:
                self.pending_cmds[cmd_id]["response"] = data
                self.pending_cmds[cmd_id]["event"].set()

    # ------------------------------------------------------------------
    # Polling Loop (Keep-Alive & Credit Resend)
    # ------------------------------------------------------------------

    def _poll_loop(self) -> None:
        """Periodic tasks: resend credit if no data flowing."""
        last_data_time = time.time()
        while self.running:
            time.sleep(self.credit_poll_ms / 1000.0)
            if not self.running:
                break

            # If no data received recently, resend credit (keep-alive)
            now = time.time()
            with self.lock:
                if self.stats.packets_received > 0:
                    last_data_time = now

            if now - last_data_time > self.credit_poll_ms / 1000.0 * 2:
                # No data for a while, resend credit
                self.send_credit(self.abs_credit)
                last_data_time = now

    # ------------------------------------------------------------------
    # Utility
    # ------------------------------------------------------------------

    def get_stats(self) -> LudpStats:
        """Get a copy of current statistics."""
        with self.lock:
            return LudpStats(
                packets_received=self.stats.packets_received,
                packets_processed=self.stats.packets_processed,
                packets_out_of_order=self.stats.packets_out_of_order,
                packets_retransmitted=self.stats.packets_retransmitted,
                nacks_sent=self.stats.nacks_sent,
                credits_sent=self.stats.credits_sent,
                bytes_received=self.stats.bytes_received,
                start_time=self.stats.start_time,
                last_seq=self.stats.last_seq,
                gap_count=self.stats.gap_count,
            )


# ============================================================================
# Example Application: Data Logger
# ============================================================================

def run_data_logger(args: argparse.Namespace) -> None:
    """
    Example application: Start acquisition, receive data, log to file.
    """
    # Open output file if specified
    outfile = None
    if args.output:
        outfile = open(args.output, "wb")
        print(f"[APP] Writing raw payload data to {args.output}")

    # Statistics tracking
    seq_log: List[int] = []
    timestamp_log: List[int] = []

    def on_data(pkt: LudpDataPacket) -> None:
        """Callback for each received in-order DATA packet."""
        if outfile:
            outfile.write(pkt.payload)
            outfile.flush()
        seq_log.append(pkt.seq_num)
        timestamp_log.append(pkt.timestamp)

    # Create LUDP host
    host = LudpHost(
        fpga_ip=args.fpga_ip,
        local_port=args.local_port,
        window_size=args.window_size,
        credit_interval=args.credit_interval,
        nack_timeout_ms=args.nack_timeout,
        credit_poll_ms=args.credit_poll,
        on_data=on_data,
    )

    host.start()

    # Send START command
    if not host.send_start():
        print("[APP] Failed to start acquisition. Exiting.")
        host.stop()
        if outfile:
            outfile.close()
        return

    # Send initial credit
    host.send_credit(args.window_size)

    # Run for specified duration
    print(f"[APP] Receiving data for {args.duration} seconds...")
    try:
        for i in range(args.duration):
            time.sleep(1.0)
            stats = host.get_stats()
            print(f"[APP] {stats}")
    except KeyboardInterrupt:
        print("\n[APP] Interrupted by user.")

    # Send STOP command
    host.send_stop()

    # Final stats
    stats = host.get_stats()
    print(f"\n[APP] Final Statistics:")
    print(f"  Total packets received: {stats.packets_received}")
    print(f"  Total packets processed: {stats.packets_processed}")
    print(f"  Out-of-order packets: {stats.packets_out_of_order}")
    print(f"  Retransmitted packets: {stats.packets_retransmitted}")
    print(f"  NACKs sent: {stats.nacks_sent}")
    print(f"  Credits sent: {stats.credits_sent}")
    print(f"  Gaps detected: {stats.gap_count}")
    print(f"  Total bytes: {stats.bytes_received}")
    print(f"  Average throughput: {stats.throughput_mbps:.1f} Mbps")
    print(f"  Average packet rate: {stats.packet_rate_kpps:.1f} kpps")

    if seq_log:
        print(f"  Sequence range: {seq_log[0]} -> {seq_log[-1]}")
        expected_count = seq_log[-1] - seq_log[0] + 1
        actual_count = len(set(seq_log))
        if expected_count != actual_count:
            print(f"  WARNING: Missing {expected_count - actual_count} packets!")

    host.stop()
    if outfile:
        outfile.close()
        print(f"[APP] Data saved to {args.output}")


# ============================================================================
# Example Application: Interactive Shell
# ============================================================================

def run_interactive(args: argparse.Namespace) -> None:
    """Interactive shell for sending commands and monitoring."""
    host = LudpHost(
        fpga_ip=args.fpga_ip,
        local_port=args.local_port,
        window_size=args.window_size,
        on_data=lambda pkt: print(
            f"[DATA] seq={pkt.seq_num} len={pkt.payload_len} ts={pkt.timestamp} "
            f"payload[:8]={pkt.payload[:8].hex()}"
        ),
    )

    host.start()
    print("\nLUDP Interactive Shell")
    print("Commands: start, stop, read <addr>, write <addr> <data>, credit <n>, stats, quit")

    try:
        while True:
            cmd = input("ludp> ").strip().split()
            if not cmd:
                continue

            if cmd[0] == "start":
                host.send_start()
                host.send_credit(args.window_size)
            elif cmd[0] == "stop":
                host.send_stop()
            elif cmd[0] == "read" and len(cmd) == 2:
                addr = int(cmd[1], 0)
                val = host.read_reg(addr)
                print(f"  read_reg(0x{addr:04x}) = {val}")
            elif cmd[0] == "write" and len(cmd) == 3:
                addr = int(cmd[1], 0)
                data = int(cmd[2], 0)
                ok = host.write_reg(addr, data)
                print(f"  write_reg(0x{addr:04x}, 0x{data:04x}) = {'OK' if ok else 'FAIL'}")
            elif cmd[0] == "credit" and len(cmd) == 2:
                n = int(cmd[1], 0)
                host.send_credit(n)
                print(f"  Sent credit={n}")
            elif cmd[0] == "stats":
                print(f"  {host.get_stats()}")
            elif cmd[0] in ("quit", "exit", "q"):
                break
            else:
                print("  Unknown command")
    except KeyboardInterrupt:
        pass
    finally:
        host.stop()


# ============================================================================
# Main Entry Point
# ============================================================================

def main() -> int:
    parser = argparse.ArgumentParser(
        description="LUDP Host Application - PC-side reference implementation",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Log data for 10 seconds
  python ludp_host.py --fpga-ip 192.168.1.128 --duration 10 -o data.bin

  # Interactive mode
  python ludp_host.py --fpga-ip 192.168.1.128 --mode interactive

  # Large window for high throughput
  python ludp_host.py --fpga-ip 192.168.1.128 --window-size 4096 --duration 60
        """,
    )
    parser.add_argument(
        "--fpga-ip",
        default="192.168.1.128",
        help="FPGA IP address (default: 192.168.1.128)",
    )
    parser.add_argument(
        "--local-port",
        type=int,
        default=LUDP_PORT,
        help=f"Local UDP port (default: {LUDP_PORT})",
    )
    parser.add_argument(
        "--duration",
        type=int,
        default=10,
        help="Acquisition duration in seconds (default: 10)",
    )
    parser.add_argument(
        "--window-size",
        type=int,
        default=DEFAULT_WINDOW_SIZE,
        help=f"Credit window size in packets (default: {DEFAULT_WINDOW_SIZE})",
    )
    parser.add_argument(
        "--credit-interval",
        type=int,
        default=DEFAULT_CREDIT_INTERVAL,
        help=f"Send credit update every N packets (default: {DEFAULT_CREDIT_INTERVAL})",
    )
    parser.add_argument(
        "--nack-timeout",
        type=float,
        default=5.0,
        help="NACK retransmit timeout in ms (default: 5.0)",
    )
    parser.add_argument(
        "--credit-poll",
        type=float,
        default=50.0,
        help="Credit keep-alive poll interval in ms (default: 50.0)",
    )
    parser.add_argument(
        "-o", "--output",
        default=None,
        help="Output file for raw payload data",
    )
    parser.add_argument(
        "--mode",
        choices=["logger", "interactive"],
        default="logger",
        help="Application mode (default: logger)",
    )

    args = parser.parse_args()

    if args.mode == "logger":
        run_data_logger(args)
    else:
        run_interactive(args)

    return 0


if __name__ == "__main__":
    sys.exit(main())
