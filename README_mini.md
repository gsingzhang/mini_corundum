# Minimal 10G Ethernet UDP Streamer

This is a minimal FPGA project utilizing the Corundum 10G Ethernet MAC and UDP stack to receive commands and send streaming data over 10G Ethernet without requiring PCIe.

## Architecture

The top-level module `mini_corundum_top` connects:
1. `eth_mac_10g`: Corundum 10G MAC interfacing with the XGMII PHY layer.
2. `eth_axis_rx` / `eth_axis_tx`: Converts raw Ethernet frames to AXI stream payloads.
3. `udp_complete_64`: Implements the ARP, IP, and UDP stack.
4. `cmd_stream_app`: A custom application that parses UDP commands and generates streaming data.

## Usage

*   **Network Config**: The FPGA's IP address is hardcoded to `192.168.1.10` with MAC `02:00:00:00:00:00`.
*   **Start Streaming**: Send a UDP packet to `192.168.1.10` on port `1234`. The FPGA will start streaming 1024-byte UDP packets containing a 64-bit counter back to your source IP and port.
*   **Stop Streaming**: Send a UDP packet to `192.168.1.10` on port `1235`. The FPGA will stop streaming.

## Verification

The project includes a `Makefile` that uses Vivado's `xvlog` and `xelab` to verify the syntax and elaboration of the design.

Run:
```bash
make check
```
