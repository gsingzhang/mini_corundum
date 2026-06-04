# DPI-C Co-Simulation User Guide

## Quick Start

### Prerequisites

- VCS simulator (tested with W-2024.09-SP1)
- GCC compiler
- Python 3.7+
- mini_corundum RTL source code

### Directory Structure

```
mini_corundum/
├── rtl/
│   ├── fpga_core.v
│   ├── ludp_protocol.sv
│   └── icmp_echo_reply.sv
├── tb/
│   ├── dpi_safe.c              # DPI-C implementation
│   ├── dpi_safe.sv             # DPI-C imports
│   ├── tb_fpga_core_dpi.v      # DPI testbench
│   ├── Makefile.dpi            # Build automation
│   └── filelist_dpi.f          # Source file list (generated)
├── sw/
│   └── ludp_host_fifo.py       # Python packet generator
└── docs/
    ├── dpi_c_interface_spec.md # This specification
    └── dpi_c_user_guide.md     # This guide
```

## Running Co-Simulation Tests

### Test 1: ARP Request → ARP Reply

Verify the FPGA responds to ARP requests with correct ARP replies:

```bash
cd /home/gxzhang/gx/prj/mini_corundum/tb
make -f Makefile.dpi sim-arp
```

**Expected Output:**
```
[DPI] Initialized with 1 test packets
[765000] Reset complete, total packets from DPI: 1
[765000] DPI: Feeding packet of 60 bytes
[1533000] All DPI packets fed (1 packets)
[65533000] Simulation complete
```

**What happens:**
1. Python generates ARP request packet (60 bytes)
2. DPI-C loads packet into buffer
3. Testbench feeds packet via XGMII interface
4. FPGA processes ARP request
5. FPGA sends ARP reply (captured as TX frame)

### Test 2: ICMP Echo Request → Echo Reply

Verify ping functionality:

```bash
cd /home/gxzhang/gx/prj/mini_corundum/tb
make -f Makefile.dpi sim-icmp
```

**What happens:**
1. Python generates ICMP echo request with 32-byte payload
2. FPGA receives ICMP packet via IP stack
3. `icmp_echo_reply` module processes request
4. FPGA sends ICMP echo reply with echoed payload

### Test 3: LUDP START Command

Verify LUDP protocol command processing:

```bash
cd /home/gxzhang/gx/prj/mini_corundum/tb
make -f Makefile.dpi sim-ludp-start
```

**What happens:**
1. Python generates LUDP START command packet
2. FPGA parses UDP packet, extracts LUDP payload
3. `ludp_protocol` module processes START command
4. FPGA may send response or begin data transmission

### Test 4: Full LUDP Sequence

Test complete LUDP flow with ARP resolution:

```bash
cd /home/gxzhang/gx/prj/mini_corundum/tb
make -f Makefile.dpi sim-ludp-full
```

**What happens:**
1. ARP request (for address resolution)
2. LUDP START command (initiate communication)
3. LUDP CREDIT (enable data flow)
4. FPGA sends data packets based on credit

## Customizing Packet Generation

### Adding New Packet Types

Edit `sw/ludp_host_fifo.py` to add new packet generators:

```python
def generate_custom_packet():
    """Generate a custom packet."""
    eth_dst = b'\x02\x00\x00\x00\x00\x00'
    eth_src = b'\x02\x00\x00\x00\x00\x01'
    eth_type = struct.pack(">H", 0x0800)

    # Add your custom payload here
    payload = b'\x00' * 64

    frame = eth_dst + eth_src + eth_type + payload
    return frame
```

Then add to the main function:

```python
elif args.packet_type == 'custom':
    packets.append(generate_custom_packet())
```

### Modifying Packet Content

#### Change Source/Destination IPs

Edit the IP address constants in `ludp_host_fifo.py`:

```python
# Current values
ip_src = struct.pack(">I", 0xC0A801C7)  # 192.168.1.199
ip_dst = struct.pack(">I", 0xC0A80180)  # 192.168.1.128

# Change to your network
ip_src = struct.pack(">I", 0x0A000001)  # 10.0.0.1
ip_dst = struct.pack(">I", 0x0A000002)  # 10.0.0.2
```

#### Change MAC Addresses

```python
# Current values
eth_src = b'\x02\x00\x00\x00\x00\x01'  # 02:00:00:00:00:01
eth_dst = b'\x02\x00\x00\x00\x00\x00'  # 02:00:00:00:00:00

# Change to your MACs
eth_src = b'\x00\x11\x22\x33\x44\x55'
eth_dst = b'\x00\x66\x77\x88\x99\xAA'
```

#### Change LUDP Command Parameters

```python
# LUDP START with custom arguments
ludp_pkt = struct.pack("<HBBIHIH",
                       LUDP_MAGIC,      # 0xDA01
                       PKT_CMD,         # 0x02
                       0x00,            # flags
                       0x00000001,      # cmd_id
                       0x0001,          # opcode = START
                       0x00001234,      # arg1 (custom value)
                       0xABCD)          # arg2 (custom value)
```

## Adding Packets to DPI-C Buffer

### Method 1: Hardcode in C (Current Approach)

Edit `tb/dpi_safe.c` and add packets to `init_packets()`:

```c
void init_packets() {
    if (initialized) return;

    // Packet 0: ARP request
    unsigned char arp_pkt[] = { /* ... */ };
    memcpy(packet_data[0], arp_pkt, 60);
    packet_lengths[0] = 60;

    // Packet 1: Your custom packet
    unsigned char custom_pkt[] = {
        0x02, 0x00, 0x00, 0x00, 0x00, 0x00,  // dst MAC
        0x02, 0x00, 0x00, 0x00, 0x00, 0x01,  // src MAC
        0x08, 0x00,                           // IPv4
        // ... IP header ...
        // ... payload ...
    };
    memcpy(packet_data[1], custom_pkt, sizeof(custom_pkt));
    packet_lengths[1] = sizeof(custom_pkt);

    packet_count = 2;  // Update count
    initialized = 1;
}
```

### Method 2: File-Based Loading (Future Enhancement)

For dynamic packet loading without recompilation:

1. Generate packets with Python:
```bash
python3 sw/ludp_host_fifo.py --packet-type custom
```

2. Modify `dpi_safe.c` to read from file at startup:
```c
void init_packets() {
    FILE *fp = fopen("/tmp/ludp_dpi_fifo/packets.bin", "rb");
    if (fp) {
        // Read packet count
        fread(&packet_count, sizeof(int), 1, fp);
        // Read each packet
        for (int i = 0; i < packet_count; i++) {
            fread(&packet_lengths[i], sizeof(int), 1, fp);
            fread(packet_data[i], 1, packet_lengths[i], fp);
        }
        fclose(fp);
    }
    initialized = 1;
}
```

## Debugging Tips

### Enable VCD Waveform Dumping

Add to `tb_fpga_core_dpi.v`:

```systemverilog
initial begin
    $dumpfile("tb_fpga_core_dpi.vcd");
    $dumpvars(0, tb_fpga_core_dpi);
end
```

Compile with VCD support:
```bash
make -f Makefile.dpi compile-vcd
```

### Add Debug Prints

In `dpi_safe.c`:
```c
int dpi_get_byte(int idx) {
    printf("[DPI] get_byte: packet=%d, idx=%d, value=0x%02X\n",
           current_packet, idx, packet_data[current_packet][idx]);
    return packet_data[current_packet][idx];
}
```

In `tb_fpga_core_dpi.v`:
```systemverilog
always @(posedge clk) begin
    if (sfp0_rxc != 8'hff) begin
        $display("[%0t] XGMII RX: rxd=%016h rxc=%02h",
                 $time, sfp0_rxd, sfp0_rxc);
    end
end
```

### Check Packet Content

Verify packet bytes in simulation:

```systemverilog
task verify_packet_content;
    integer i;
    begin
        for (i = 0; i < dpi_get_length(); i = i + 1) begin
            $display("Byte[%0d] = 0x%02X", i, dpi_get_byte(i));
        end
    end
endtask
```

## Troubleshooting

### Issue: VCS Compilation Errors

**Symptom:** `undefined reference to dpi_*`

**Solution:** Ensure DPI C file is included in compilation:
```makefile
DPI_C_SOURCES = dpi_safe.c  # Must be correct filename
```

### Issue: No TX Frames Detected

**Symptom:** Simulation runs but `tx_frame_count` remains 0

**Check:**
1. Is the packet being fed correctly? Add debug prints in `feed_packet_from_dpi`
2. Is the FPGA MAC address correct? Check `eth_dst` in packet
3. Is ARP resolution needed? Send ARP request first

### Issue: VCS Assertion Failure

**Symptom:** `Assertion failed "pFound" at line 146 in file vcs_fence.c`

**Cause:** Using array arguments in DPI functions

**Solution:** Use only scalar types:
```c
// BAD - causes crash:
void dpi_read_packet(input byte data[], input int max_len);

// GOOD - safe:
int dpi_get_byte(int idx);
```

### Issue: Incorrect Byte Order

**Symptom:** FPGA doesn't recognize packet format

**Check:** XGMII transmits bytes in little-endian lane order:
- `sfp0_rxd[7:0]` = first byte of packet
- `sfp0_rxd[15:8]` = second byte
- etc.

Verify with debug print:
```systemverilog
$display("First byte: 0x%02X (expected 0xFF for ARP broadcast)",
         sfp0_rxd[7:0]);
```

## Advanced Usage

### Batch Testing Multiple Packets

Create a test script that generates multiple packet sequences:

```python
#!/usr/bin/env python3
# test_sequences.py

import sys
sys.path.insert(0, '../sw')
from ludp_host_fifo import write_packets_to_file, generate_arp_request
from ludp_host_fifo import generate_icmp_echo_request, generate_ludp_start

# Test sequence 1: ARP only
seq1 = [generate_arp_request()]

# Test sequence 2: ARP + ICMP
seq2 = [generate_arp_request(), generate_icmp_echo_request()]

# Test sequence 3: Full LUDP
seq3 = [generate_arp_request(), generate_ludp_start()]

# Write all sequences
write_packets_to_file(seq1)  # Overwrites packets.bin
```

### Integrating with CI/CD

Add to your test script:

```bash
#!/bin/bash
# run_dpi_tests.sh

set -e  # Exit on error

cd /home/gxzhang/gx/prj/mini_corundum/tb

# Compile
make -f Makefile.dpi compile

# Run tests
make -f Makefile.dpi sim-arp
make -f Makefile.dpi sim-icmp
make -f Makefile.dpi sim-ludp-start
make -f Makefile.dpi sim-ludp-full

echo "All DPI tests passed!"
```

### Performance Optimization

For large packet sequences:

1. **Increase buffer size** in `dpi_safe.c`:
```c
#define MAX_PACKETS 256    // Increase from 16
#define MAX_PACKET_SIZE 9216
```

2. **Batch packet loading** to reduce DPI calls:
```systemverilog
// Instead of calling dpi_get_byte() for each byte,
// read multiple bytes per cycle if packet is short
```

3. **Use parallel compilation**:
```bash
make -f Makefile.dpi compile -j4
```

## Reference Commands

| Command | Description |
|---------|-------------|
| `make -f Makefile.dpi compile` | Compile simulation |
| `make -f Makefile.dpi sim-arp` | Run ARP test |
| `make -f Makefile.dpi sim-icmp` | Run ICMP test |
| `make -f Makefile.dpi sim-ludp-start` | Run LUDP START test |
| `make -f Makefile.dpi sim-ludp-full` | Run full LUDP sequence |
| `make -f Makefile.dpi clean` | Clean build artifacts |
| `python3 sw/ludp_host_fifo.py --packet-type arp` | Generate ARP packet file |
| `python3 sw/ludp_host_fifo.py --packet-type icmp` | Generate ICMP packet file |

## Support

For issues or questions:
1. Check the specification: `docs/dpi_c_interface_spec.md`
2. Review debug tips in this guide
3. Verify VCS version compatibility
4. Check packet format with Wireshark or similar tool
