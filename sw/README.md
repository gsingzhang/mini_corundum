# LUDP Host Software

PC-side Python reference implementation for the Lightweight Ultrasonic DAQ Protocol (LUDP).

## Requirements

- Python 3.7+
- 10G Ethernet NIC with jumbo frame support (MTU >= 9000)
- FPGA running LUDP bitstream connected via SFP+

## Quick Start

### 1. Configure Network

Set your PC's NIC to use jumbo frames and a static IP on the same subnet as the FPGA:

```bash
# Linux
sudo ip link set eth0 mtu 9000
sudo ip addr add 192.168.1.1/24 dev eth0

# Verify
ping 192.168.1.128  # FPGA default IP
```

### 2. Data Logger Mode

Receive ultrasonic data for a specified duration and save to file:

```bash
python ludp_host.py --fpga-ip 192.168.1.128 --duration 10 -o data.bin
```

Output:
```
[LUDP] Host started. FPGA=192.168.1.128:1234
[OK] START command acknowledged
[APP] Receiving data for 10 seconds...
[APP] Stats: 1024 processed, 0 OOO, 0 retrans, 0 NACKs, 8234.5 Mbps, 128.0 kpps, elapsed=1.0s
...
[APP] Final Statistics:
  Total packets received: 12800
  Total packets processed: 12800
  Out-of-order packets: 0
  Retransmitted packets: 0
  NACKs sent: 0
  Credits sent: 201
  Gaps detected: 0
  Total bytes: 115343360
  Average throughput: 8234.5 Mbps
  Average packet rate: 128.0 kpps
[APP] Data saved to data.bin
```

### 3. Interactive Mode

Send commands manually and monitor incoming data:

```bash
python ludp_host.py --fpga-ip 192.168.1.128 --mode interactive
```

Commands:
```
ludp> start          # Send START command + initial credit
ludp> credit 2048    # Grant credit for 2048 packets
ludp> stats          # Show receive statistics
ludp> read 0x0000    # Read FPGA register
ludp> write 0x0001 0x1234  # Write FPGA register
ludp> stop           # Send STOP command
ludp> quit           # Exit
```

## Architecture

```
+------------------+        UDP        +------------------+
|   PC Host        |<----------------->|   FPGA (ZCU106)  |
|  (ludp_host.py)  |    Port 1234      |  (ludp_protocol) |
+------------------+                   +------------------+
        |                                      |
        |  CREDIT (flow control)               |  DATA (ultrasonic)
        |  NACK (retransmission req)           |  CMD_ACK / CMD_CPL
        |  CMD (start/stop/read/write)         |
        v                                      v
   +---------+                            +---------+
   |  App    |                            |  ADC    |
   | Buffer  |                            | FIFO    |
   +---------+                            +---------+
```

## Key Features

| Feature | Description |
|---------|-------------|
| **Credit-Based Flow Control** | Host grants explicit credits to prevent FPGA from overwhelming socket buffers |
| **NACK Retransmission** | Host detects gaps and requests missing packets from FPGA retransmit buffer |
| **Out-of-Order Buffering** | Temporarily stores future packets until missing ones arrive |
| **Keep-Alive Credits** | Resends credit if no data flows (handles dropped CREDIT packets) |
| **CMD Timeout & Retry** | Automatically retries commands if ACK/CPL not received |
| **Real-Time Statistics** | Tracks throughput, packet rate, gaps, retransmissions |

## Command-Line Options

| Option | Default | Description |
|--------|---------|-------------|
| `--fpga-ip` | `192.168.1.128` | FPGA IP address |
| `--local-port` | `1234` | Local UDP port |
| `--duration` | `10` | Acquisition duration in seconds (logger mode) |
| `--window-size` | `1024` | Credit window size in packets |
| `--credit-interval` | `64` | Send credit update every N packets |
| `--nack-timeout` | `5.0` | NACK retransmit timeout in ms |
| `--credit-poll` | `50.0` | Credit keep-alive interval in ms |
| `-o, --output` | `None` | Output file for raw payload data |
| `--mode` | `logger` | `logger` or `interactive` |

## Performance Tuning

For maximum throughput:

1. **Increase socket buffers** (already set to 256MB RX / 16MB TX in code)
2. **Use larger window size**: `--window-size 4096`
3. **Enable CPU affinity**: `taskset -c 0 python ludp_host.py ...`
4. **Use dedicated NIC**: Avoid sharing the 10G NIC with other traffic
5. **Tune interrupt coalescing**: `ethtool -C eth0 rx-usecs 50 tx-usecs 50`

## Data Format

The raw payload saved to file is the concatenation of all DATA packet payloads. Each payload contains the ultrasonic ADC samples as sent by the FPGA. Parse according to your ADC configuration (e.g., 16-bit samples interleaved across channels).

## Troubleshooting

| Issue | Solution |
|-------|----------|
| No data received | Check network connectivity (`ping FPGA_IP`), verify FPGA is running, check firewall rules |
| High packet loss | Increase `--window-size`, check NIC buffer sizes, enable jumbo frames |
| Many NACKs sent | Reduce FPGA burst rate, increase host buffer size, check for switch congestion |
| CMD timeout | Verify FPGA IP, check ARP table (`arp -a`), ensure FPGA is not in reset |
