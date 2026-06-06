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
from heapq import heappush, heappop
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
DEFAULT_WINDOW_SIZE = 256  # packets (smaller window = less burst = fewer drops)
DEFAULT_CREDIT_INTERVAL = 8  # Send credit update every N in-order packets


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
        credit_poll_ms: float = 5.0,
        cmd_timeout_ms: float = 100.0,
        on_data: Optional[Callable[[LudpDataPacket], None]] = None,
        debug: bool = False,
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
        self.debug = debug

        # Socket setup
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.bind(("0.0.0.0", local_port))
        # Increase socket buffer sizes for high-throughput reception
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 256 * 1024 * 1024)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_SNDBUF, 16 * 1024 * 1024)

        # State
        self.expected_seq = 0
        self.abs_credit = window_size
        self.highest_seq = 0  # Highest seq received (for credit advancement)
        self.out_of_order: Dict[int, LudpDataPacket] = {}
        self.ooo_heap: List[int] = []  # Min-heap for O(1) min seq lookup
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
        # LUDP header fields are transmitted in little-endian byte order on the wire.
        # The FPGA receives bytes via XGMII and assembles them into 64-bit words
        # where the first byte goes into bits [7:0]. For a 16-bit magic number,
        # byte0 (LSB) at tdata[7:0] and byte1 (MSB) at tdata[15:8] gives the
        # correct value 0xDA01 when read as tdata[15:0].
        return struct.pack(
            "<HBBIHIH",
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
            "<HBBIHIH",
            LUDP_MAGIC,
            PKT_CREDIT,
            0x00,
            abs_credit,
            0,  # opcode (reserved)
            0,  # arg1 (reserved, 32-bit)
            0,  # arg2 (reserved, 16-bit)
        )

    def _build_nack(self, miss_seq: int, count: int = 1) -> bytes:
        """Build a NACK packet (16 bytes)."""
        return struct.pack(
            "<HBBIHIH",
            LUDP_MAGIC,
            PKT_NACK,
            0x00,
            miss_seq,
            count,
            0,  # arg1 (reserved, 32-bit)
            0,  # arg2 (reserved, 16-bit)
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
                # Parse CMD_CPL: Read_Data at offset 10 (32-bit, little-endian)
                read_data = struct.unpack("<I", resp[10:14])[0]
                return read_data
        else:
            with self.lock:
                if cmd_id in self.pending_cmds:
                    del self.pending_cmds[cmd_id]
        return None

    def _send_cmd_wait_ack(
        self, opcode: int, name: str, arg1: int = 0, arg2: int = 0, retries: int = 3
    ) -> bool:
        """Send a posted CMD and wait for CMD_ACK with retry."""
        for attempt in range(retries):
            cmd_id = self.next_cmd_id
            self.next_cmd_id += 1
            pkt = self._build_cmd(opcode, arg1=arg1, arg2=arg2, flags=0x00, cmd_id=cmd_id)

            with self.lock:
                self.pending_cmds[cmd_id] = {
                    "event": threading.Event(),
                    "response": None,
                }

            self.sock.sendto(pkt, self.fpga_addr)

            if self.debug:
                print(f"[DEBUG TX] {len(pkt)}B to {self.fpga_addr}: {pkt.hex()}")

            success = self.pending_cmds[cmd_id]["event"].wait(
                timeout=self.cmd_timeout_ms / 1000.0
            )
            with self.lock:
                if cmd_id in self.pending_cmds:
                    del self.pending_cmds[cmd_id]

            if success:
                print(f"[OK] {name} command acknowledged")
                return True

        print(f"[TIMEOUT] {name} command no ACK after {retries} retries")
        return False

    def send_credit(self, abs_credit: int) -> None:
        """Send explicit credit update to FPGA."""
        pkt = self._build_credit(abs_credit)
        self.sock.sendto(pkt, self.fpga_addr)
        if self.debug:
            print(f"[DEBUG TX] CREDIT {len(pkt)}B to {self.fpga_addr}: abs_credit={abs_credit} hex={pkt.hex()}")
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

            if self.debug:
                print(f"[DEBUG RX] {len(data)}B from {addr}: {data.hex()}")

            if len(data) < LUDP_HDR_LEN:
                if self.debug:
                    print(f"[DEBUG RX] Too short ({len(data)}B), expected >= {LUDP_HDR_LEN}")
                continue

            # Parse header (LUDP uses little-endian byte order on the wire)
            magic = struct.unpack("<H", data[0:2])[0]
            if magic != LUDP_MAGIC:
                if self.debug:
                    print(f"[DEBUG RX] Bad magic: 0x{magic:04x}, expected 0x{LUDP_MAGIC:04x}")
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
            magic=struct.unpack("<H", data[0:2])[0],
            pkt_type=data[2],
            flags=data[3],
            seq_num=struct.unpack("<I", data[4:8])[0],
            payload_len=struct.unpack("<H", data[8:10])[0],
            timestamp=struct.unpack("<I", data[10:14])[0],
            payload=data[LUDP_HDR_LEN:],
        )

        with self.lock:
            self.stats.packets_received += 1
            self.stats.bytes_received += len(data)
            self.stats.last_seq = pkt.seq_num

            if pkt.is_retransmit:
                self.stats.packets_retransmitted += 1

        # Track highest received sequence for credit advancement
        if pkt.seq_num > self.highest_seq:
            self.highest_seq = pkt.seq_num

        # In-order packet
        if pkt.seq_num == self.expected_seq:
            self._deliver(pkt)
            self.expected_seq += 1

            # Drain out-of-order buffer using heap
            while self.ooo_heap and self.ooo_heap[0] < self.expected_seq:
                heappop(self.ooo_heap)  # Remove stale entries
            while self.ooo_heap and self.ooo_heap[0] == self.expected_seq:
                seq = heappop(self.ooo_heap)
                self._deliver(self.out_of_order.pop(seq))
                self.expected_seq += 1

            # Send credit update frequently to keep FPGA pipeline full
            # but not so fast that we flood it with small credit packets
            if self.expected_seq % self.credit_interval == 0:
                new_credit = self.expected_seq + self.window_size
                if new_credit > self.abs_credit:
                    self.send_credit(new_credit)
                    self.abs_credit = new_credit

        # Future packet (gap detected)
        elif pkt.seq_num > self.expected_seq:
            with self.lock:
                self.stats.packets_out_of_order += 1
                self.stats.gap_count += 1

            # Store out-of-order packet with min-heap for O(1) lookup
            if pkt.seq_num not in self.out_of_order:
                heappush(self.ooo_heap, pkt.seq_num)
            self.out_of_order[pkt.seq_num] = pkt

        # Old packet (already processed)
        else:
            pass

    def _deliver(self, pkt: LudpDataPacket) -> None:
        """Deliver an in-order packet to the application layer."""
        with self.lock:
            self.stats.packets_processed += 1
        if self.on_data:
            self.on_data(pkt)

    def _handle_cmd_ack(self, data: bytes) -> None:
        """Handle CMD_ACK from FPGA."""
        if len(data) < 12:
            if self.debug:
                print(f"[DEBUG CMD_ACK] Too short: {len(data)}B")
            return
        cmd_id = struct.unpack("<I", data[4:8])[0]
        status = data[3]
        opcode = struct.unpack("<H", data[8:10])[0] if len(data) >= 10 else 0
        if self.debug:
            print(f"[DEBUG CMD_ACK] cmd_id={cmd_id} status={status} opcode=0x{opcode:04x} pending={list(self.pending_cmds.keys())}")
        with self.lock:
            if cmd_id in self.pending_cmds:
                self.pending_cmds[cmd_id]["response"] = data
                self.pending_cmds[cmd_id]["event"].set()

    def _handle_cmd_cpl(self, data: bytes) -> None:
        """Handle CMD_CPL from FPGA (includes CREDIT_ACK with resp_data)."""
        if len(data) < 16:
            return
        cmd_id = struct.unpack("<I", data[4:8])[0]
        opcode = struct.unpack("<H", data[8:10])[0] if len(data) >= 10 else 0
        resp_data = struct.unpack("<I", data[10:14])[0] if len(data) >= 14 else 0

        if self.debug and opcode == 0x0006:
            burst_active = (resp_data >> 16) & 0x1
            credit_val = resp_data & 0xFFFF
            print(f"[DEBUG CREDIT_ACK] credit={credit_val} burst_active={burst_active} cmd_id={cmd_id}")

        with self.lock:
            if cmd_id in self.pending_cmds:
                self.pending_cmds[cmd_id]["response"] = data
                self.pending_cmds[cmd_id]["event"].set()

    # ------------------------------------------------------------------
    # Polling Loop (Keep-Alive & Credit Resend)
    # ------------------------------------------------------------------

    def _poll_loop(self) -> None:
        """Periodic tasks: advance credit based on processed packets, skip gaps."""
        last_data_time = time.time()
        last_debug_time = time.time()
        last_expected_seq = self.expected_seq
        gap_stall_start = None

        while self.running:
            time.sleep(self.credit_poll_ms / 1000.0)
            if not self.running:
                break

            now = time.time()
            with self.lock:
                if self.stats.packets_received > 0:
                    last_data_time = now

            if self.debug and now - last_debug_time >= 1.0:
                last_debug_time = now
                print(f"[DEBUG POLL] rx={self.stats.packets_received} processed={self.stats.packets_processed} expected_seq={self.expected_seq} highest_seq={self.highest_seq} abs_credit={self.abs_credit}")

            # Advance credit based on expected_seq (processed packets), NOT highest_seq.
            # Using highest_seq defeats flow control: it tells the FPGA to send more
            # before we've actually processed the data, causing socket buffer overflow.
            new_credit = self.expected_seq + self.window_size
            if new_credit > self.abs_credit:
                self.send_credit(new_credit)
                self.abs_credit = new_credit

            # Gap skip: if expected_seq hasn't advanced and we have OOO packets,
            # skip the gap since FPGA cannot retransmit missing packets.
            # Use a short timeout (5ms) to quickly resume credit advancement.
            if self.expected_seq != last_expected_seq:
                last_expected_seq = self.expected_seq
                gap_stall_start = None
            elif self.out_of_order:
                if gap_stall_start is None:
                    gap_stall_start = now
                elif now - gap_stall_start > 0.005:  # 5ms gap timeout
                    # Skip to the lowest sequence in the OOO buffer (O(1) via heap)
                    while self.ooo_heap and self.ooo_heap[0] < self.expected_seq:
                        heappop(self.ooo_heap)
                    if not self.ooo_heap:
                        gap_stall_start = None
                        continue
                    skip_to = self.ooo_heap[0]
                    if self.debug:
                        print(f"[DEBUG GAP SKIP] expected_seq {self.expected_seq} -> {skip_to} (skipped {skip_to - self.expected_seq} packets)")
                    with self.lock:
                        self.stats.gap_count += skip_to - self.expected_seq
                    self.expected_seq = skip_to
                    # Drain from the skipped position
                    while self.ooo_heap and self.ooo_heap[0] == self.expected_seq:
                        seq = heappop(self.ooo_heap)
                        self._deliver(self.out_of_order.pop(seq))
                        self.expected_seq += 1
                    # Update credit after gap skip to unblock FPGA
                    new_credit = self.expected_seq + self.window_size
                    self.send_credit(new_credit)
                    self.abs_credit = new_credit
                    gap_stall_start = None
                    last_expected_seq = self.expected_seq

            if now - last_data_time > self.credit_poll_ms / 1000.0 * 2:
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
# Main Entry Point
# ============================================================================

def main():
    parser = argparse.ArgumentParser(description="LUDP Host Application")
    parser.add_argument("--fpga-ip", required=True, help="FPGA IP address")
    parser.add_argument("--port", type=int, default=LUDP_PORT, help="UDP port")
    parser.add_argument("--duration", type=float, default=10.0, help="Acquisition duration in seconds")
    parser.add_argument("-o", "--output", default="data.bin", help="Output file for raw data")
    parser.add_argument("--mode", choices=["logger", "interactive"], default="logger", help="Run mode")
    parser.add_argument("--window-size", type=int, default=DEFAULT_WINDOW_SIZE, help="Credit window size")
    parser.add_argument("--credit-interval", type=int, default=DEFAULT_CREDIT_INTERVAL, help="Credit interval")
    parser.add_argument("--timeout", type=float, default=100.0, help="CMD timeout in ms")
    parser.add_argument("--debug", action="store_true", help="Enable debug output (hex dump all packets)")
    args = parser.parse_args()

    if args.mode == "logger":
        run_logger(args)
    else:
        run_interactive(args)


def run_logger(args):
    """Data logger mode: receive data for a fixed duration."""
    output_file = open(args.output, "wb", buffering=8*1024*1024)
    print(f"[APP] Writing raw payload data to {args.output}")

    # Use a list buffer to batch file writes and reduce I/O blocking
    write_buf = []
    write_buf_size = 0
    FLUSH_THRESHOLD = 4 * 1024 * 1024  # Flush every 4 MB

    def on_data(pkt: LudpDataPacket):
        nonlocal write_buf_size
        write_buf.append(pkt.payload)
        write_buf_size += len(pkt.payload)
        if write_buf_size >= FLUSH_THRESHOLD:
            output_file.write(b"".join(write_buf))
            write_buf.clear()
            write_buf_size = 0

    host = LudpHost(
        fpga_ip=args.fpga_ip,
        local_port=args.port,
        window_size=args.window_size,
        credit_interval=args.credit_interval,
        on_data=on_data,
        cmd_timeout_ms=args.timeout,
        debug=args.debug,
    )

    host.start()

    # Send START command
    if not host.send_start():
        print("[APP] Failed to start acquisition. Exiting.")
        host.stop()
        output_file.close()
        sys.exit(1)

    # Send initial credit
    host.send_credit(host.abs_credit)

    # Run for specified duration
    time.sleep(args.duration)

    # Send STOP
    host.send_stop()

    # Print stats
    stats = host.get_stats()
    print(f"[APP] {stats}")

    host.stop()
    # Flush remaining buffered data
    if write_buf:
        output_file.write(b"".join(write_buf))
        write_buf.clear()
    output_file.close()
    print(f"[APP] Data saved to {args.output}")


def run_interactive(args):
    """Interactive mode: manual command shell."""
    host = LudpHost(
        fpga_ip=args.fpga_ip,
        local_port=args.port,
        window_size=args.window_size,
        credit_interval=args.credit_interval,
        cmd_timeout_ms=args.timeout,
        debug=args.debug,
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
                if host.send_start():
                    host.send_credit(host.abs_credit)
            elif cmd[0] == "stop":
                host.send_stop()
            elif cmd[0] == "read" and len(cmd) == 2:
                addr = int(cmd[1], 0)
                val = host.read_reg(addr)
                print(f"  read_reg(0x{addr:04x}) = {val}")
            elif cmd[0] == "write" and len(cmd) == 3:
                addr = int(cmd[1], 0)
                data = int(cmd[2], 0)
                if host.write_reg(addr, data):
                    print(f"  write_reg(0x{addr:04x}, 0x{data:08x}) OK")
            elif cmd[0] == "credit" and len(cmd) == 2:
                n = int(cmd[1], 0)
                host.send_credit(n)
                print(f"  Sent credit={n}")
            elif cmd[0] == "stats":
                print(f"  {host.get_stats()}")
            elif cmd[0] in ("quit", "exit"):
                break
            else:
                print("  Unknown command")
    except KeyboardInterrupt:
        pass
    finally:
        host.stop()


if __name__ == "__main__":
    main()
