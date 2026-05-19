/*
 * ============================================================================
 * Testbench for fpga_core - Mini Corundum 10G Ethernet Core
 * ============================================================================
 * 
 * This testbench verifies the following functionality:
 * 1. ARP Request/Reply handling - DUT responds to ARP requests with correct MAC
 * 2. UDP Echo Server - DUT echoes UDP packets sent to port 1234
 * 3. Port Filtering - DUT does NOT echo packets sent to wrong ports
 * 4. Multiple Packets - DUT handles multiple sequential UDP packets
 *
 * Interface:
 * - XGMII (10 Gigabit Media Independent Interface): 64-bit data + 8-bit control
 * - SFP0: Primary Ethernet port used for testing
 * - SFP1: Secondary port (not used in this testbench)
 *
 * Test Flow:
 * 1. Send ARP request to DUT -> Verify DUT sends ARP reply
 * 2. Send UDP packet to port 1234 -> Verify DUT echoes back with swapped ports
 * 3. Send UDP packet to wrong port -> Verify NO echo response
 * 4. Send multiple UDP packets -> Verify all are echoed correctly
 *
 * Author: Mini Corundum Project
 * Date: 2026
 */

`timescale 1ns / 1ps
`default_nettype none

module tb_fpga_core;

// ============================================================================
// Simulation Parameters
// ============================================================================

// Clock period for 156.25 MHz (standard 10G Ethernet clock)
// Period = 1/156.25MHz = 6.4ns
localparam CLK_PERIOD = 6.4;

// Test timeout to prevent infinite simulations
localparam TIMEOUT_CYCLES = 500000;  // ~3.2ms at 156.25MHz

// ============================================================================
// Clock and Reset Signals
// ============================================================================

// Main clock generator
reg clk = 0;
reg rst = 1;

// SFP clock domains (tied to main clock for simulation simplicity)
// In real hardware, these would be separate clock domains from SFP modules
wire sfp0_tx_clk = clk;
wire sfp0_rx_clk = clk;
wire sfp1_tx_clk = clk;
wire sfp1_rx_clk = clk;

// SFP reset signals (active high)
reg sfp0_tx_rst = 1;
reg sfp0_rx_rst = 1;
reg sfp1_tx_rst = 1;
reg sfp1_rx_rst = 1;

// ============================================================================
// GPIO and Peripheral Signals (Not used in this testbench)
// ============================================================================

// Board buttons (active high)
reg btnu = 0;
reg btnl = 0;
reg btnd = 0;
reg btnr = 0;
reg btnc = 0;

// DIP switches (8-bit)
reg [7:0] sw = 0;

// LEDs (output from DUT)
wire [7:0] led;

// UART interface
reg uart_rxd = 0;      // UART receive data (input to DUT)
wire uart_txd;         // UART transmit data (output from DUT)
reg uart_rts = 0;      // Request to Send (flow control)
wire uart_cts;         // Clear to Send (flow control)

// ============================================================================
// XGMII Interface - SFP0 (Primary Test Port)
// ============================================================================
// XGMII uses 64-bit data bus + 8-bit control bus
// Each control bit indicates whether corresponding data byte is control or data
// Control bit = 0: Data byte
// Control bit = 1: Control character (IDLE, START, TERM, ERROR)

// TX: Data transmitted FROM DUT (captured by testbench for verification)
wire [63:0] sfp0_txd;
wire [7:0]  sfp0_txc;

// RX: Data transmitted TO DUT (driven by testbench stimulus)
// Default to IDLE state: all control characters, data = 0x07
reg [63:0] sfp0_rxd = 64'h0707070707070707;
reg [7:0]  sfp0_rxc = 8'hff;

// ============================================================================
// XGMII Interface - SFP1 (Not used in this testbench)
// ============================================================================

wire [63:0] sfp1_txd;
wire [7:0]  sfp1_txc;

reg [63:0] sfp1_rxd = 64'h0707070707070707;
reg [7:0]  sfp1_rxc = 8'hff;

// ============================================================================
// Test Control and Status
// ============================================================================

integer error_count = 0;  // Cumulative error counter
integer test_num = 0;     // Current test number

// ============================================================================
// XGMII Control Character Definitions
// ============================================================================
// XGMII uses special control characters for frame delimiting
// Reference: IEEE 802.3ae Clause 47

localparam [7:0]  XGMII_IDLE    = 8'h07;   // Idle character (/I/)
localparam [7:0]  XGMII_START   = 8'hFB;   // Start of packet (/S/)
localparam [7:0]  XGMII_TERM    = 8'hFD;   // End of packet (/T/)
localparam [7:0]  XGMII_ERROR   = 8'hFE;   // Error indicator (/E/)
localparam [7:0]  ETH_PRE       = 8'h55;   // Ethernet preamble (0x55)
localparam [7:0]  ETH_SFD       = 8'hD5;   // Start Frame Delimiter (0xD5)

// Convenience constants for 64-bit (8-byte) XGMII lanes
localparam [63:0] XGMII_IDLE_QW = 64'h0707070707070707;  // Quad-word of IDLE
localparam [7:0]  XGMII_IDLE_CTRL = 8'hff;               // All lanes are control

// ============================================================================
// Network Configuration - Device Under Test (DUT)
// ============================================================================

// DUT MAC address (locally administered, unicast)
// Format: AA:BB:CC:DD:EE:FF where AA bit 1 = 1 (locally administered)
localparam [47:0] DUT_MAC  = 48'h02_00_00_00_00_00;  // 02:00:00:00:00:00

// DUT IP address: 192.168.1.128
localparam [31:0] DUT_IP   = {8'd192, 8'd168, 8'd1, 8'd128};

// ============================================================================
// Network Configuration - Test Host (Simulated External Device)
// ============================================================================

// Test host MAC address (simulates a PC/server on the network)
localparam [47:0] HOST_MAC = 48'h02_00_00_00_00_01;  // 02:00:00:00:00:01

// Test host IP address: 192.168.1.1 (typically the gateway/router)
localparam [31:0] HOST_IP  = {8'd192, 8'd168, 8'd1, 8'd1};

// ============================================================================
// Device Under Test (DUT) Instantiation
// ============================================================================

fpga_core dut (
    // Clock and reset
    .clk(clk),
    .rst(rst),
    
    // GPIO inputs (buttons, switches)
    .btnu(btnu),
    .btnl(btnl),
    .btnd(btnd),
    .btnr(btnr),
    .btnc(btnc),
    .sw(sw),
    
    // GPIO outputs (LEDs)
    .led(led),
    
    // UART interface
    .uart_rxd(uart_rxd),
    .uart_txd(uart_txd),
    .uart_rts(uart_rts),
    .uart_cts(uart_cts),
    
    // SFP0 XGMII TX (data from DUT)
    .sfp0_tx_clk(sfp0_tx_clk),
    .sfp0_tx_rst(sfp0_tx_rst),
    .sfp0_txd(sfp0_txd),
    .sfp0_txc(sfp0_txc),
    
    // SFP0 XGMII RX (data to DUT)
    .sfp0_rx_clk(sfp0_rx_clk),
    .sfp0_rx_rst(sfp0_rx_rst),
    .sfp0_rxd(sfp0_rxd),
    .sfp0_rxc(sfp0_rxc),
    
    // SFP1 XGMII (not used, but must be connected)
    .sfp1_tx_clk(sfp1_tx_clk),
    .sfp1_tx_rst(sfp1_tx_rst),
    .sfp1_txd(sfp1_txd),
    .sfp1_txc(sfp1_txc),
    .sfp1_rx_clk(sfp1_rx_clk),
    .sfp1_rx_rst(sfp1_rx_rst),
    .sfp1_rxd(sfp1_rxd),
    .sfp1_rxc(sfp1_rxc)
);

// ============================================================================
// Clock Generation
// ============================================================================
// Generates 156.25 MHz clock with 50% duty cycle
// Toggle every CLK_PERIOD/2 = 3.2ns

always #(CLK_PERIOD/2) clk = ~clk;

// ============================================================================
// XGMII Frame Transmit/Receive Tasks
// ============================================================================

// -----------------------------------------------------------------------------
// TX Frame Monitor: Captures frames transmitted by the DUT
// -----------------------------------------------------------------------------
// This monitor continuously watches the XGMII TX interface and captures
// complete Ethernet frames for verification. It detects frame boundaries
// by monitoring the control signal:
// - sfp0_txc != 8'hff: At least one lane has data (frame active)
// - sfp0_txc == 8'hff: All lanes are IDLE (frame inactive)
//
// Storage:
// - tx_capture[]: Stores 64-bit XGMII data words
// - tx_ctrl_capture[]: Stores corresponding 8-bit control words
// - tx_capture_len: Number of XGMII beats captured
// - tx_frame_count: Total number of complete frames captured

reg [63:0] tx_capture [0:127];       // Capture buffer (max 128 XGMII beats)
reg [7:0]  tx_ctrl_capture [0:127];  // Control bit capture
integer    tx_capture_len;           // Current frame length in beats
integer    tx_frame_count;           // Total frames captured
reg        tx_frame_active;          // Frame detection flag

// Frame capture state machine
always @(posedge clk) begin
    if (sfp0_tx_rst) begin
        // Reset: clear all capture registers
        tx_frame_count <= 0;
        tx_frame_active <= 0;
        tx_capture_len <= 0;
    end else begin
        // Detect frame activity by checking if any lane is NOT idle
        if (sfp0_txc != 8'hff) begin
            // Frame is active
            if (!tx_frame_active) begin
                // Rising edge: start of new frame
                tx_frame_active <= 1;
                tx_capture_len <= 0;  // Reset capture index
            end
            // Capture current XGMII beat
            tx_capture[tx_capture_len] <= sfp0_txd;
            tx_ctrl_capture[tx_capture_len] <= sfp0_txc;
            tx_capture_len <= tx_capture_len + 1;
        end else begin
            // All lanes idle
            if (tx_frame_active) begin
                // Falling edge: end of frame detected
                tx_frame_active <= 0;
                tx_frame_count <= tx_frame_count + 1;  // Increment frame counter
            end
        end
    end
end

// Task: Reset TX capture state
// Call this before each test to clear previous frame data
task reset_tx_capture;
    begin
        tx_frame_count = 0;
        tx_frame_active = 0;
        tx_capture_len = 0;
    end
endtask

// ============================================================================
// Frame Data Buffer
// ============================================================================
// Used to build Ethernet frames before sending via XGMII
// Max size: 1520 bytes (supports jumbo frames up to ~1500 byte payload)

reg [7:0]  frame_data [0:1519];  // Frame payload buffer
integer    frame_len;            // Current frame length in bytes

// ============================================================================
// Task: Send Ethernet Frame over XGMII
// ============================================================================
// This task converts a raw Ethernet frame into XGMII format and transmits
// it to the DUT via the sfp0_rxd/sfp0_rxc interface.
//
// XGMII Frame Structure:
//   Beat 0: [START][PRE][PRE][PRE][PRE][PRE][PRE][SFD]
//   Beat 1-N: [DATA][DATA][DATA][DATA][DATA][DATA][DATA][DATA]
//   Last-1: [DATA][DATA][DATA][DATA][CRC0][CRC1][CRC2][CRC3]
//   Last: [TERM][IDLE][IDLE][IDLE][IDLE][IDLE][IDLE][IDLE]
//
// Where:
//   - START (0xFB): Marks beginning of packet (replaces first preamble byte)
//   - PRE (0x55): Ethernet preamble (7 bytes total, 1 replaced by START)
//   - SFD (0xD5): Start Frame Delimiter
//   - DATA: Ethernet frame (header + payload)
//   - CRC: 32-bit Ethernet CRC (little-endian byte order)
//   - TERM (0xFD): End of packet marker
//   - IDLE (0x07): Idle fill characters
//
// Note: XGMII lanes are little-endian
//       Lane 0 = bits [7:0] (first byte in time)
//       Lane 7 = bits [63:56] (last byte in time)

task send_xgmii_frame;
    input integer len;  // Length of frame_data in bytes
    integer i;
    integer beat;
    integer lane;
    reg [63:0] d;       // 64-bit XGMII data word
    reg [7:0]  c;       // 8-bit XGMII control word
    reg [7:0]  xgmii_data [0:1535];  // XGMII byte stream
    integer    xgmii_len;             // Total XGMII bytes
    integer    total_beats;           // Number of 8-byte beats
    reg [31:0] crc;                   // Ethernet CRC32
    begin
        // Step 1: Compute CRC32 over Ethernet frame (header + payload)
        // CRC is calculated over 'len' bytes starting from frame_data[0]
        crc = eth_crc32(len);

        // Step 2: Build XGMII byte stream
        // Start character replaces first preamble byte (XGMII optimization)
        xgmii_data[0] = XGMII_START;
        
        // Add remaining 6 preamble bytes
        for (i = 1; i < 7; i = i + 1) begin
            xgmii_data[i] = ETH_PRE;
        end
        
        // Add Start Frame Delimiter
        xgmii_data[7] = ETH_SFD;
        
        // Add actual Ethernet frame data
        for (i = 0; i < len; i = i + 1) begin
            xgmii_data[8 + i] = frame_data[i];
        end
        
        // Add CRC32 in little-endian byte order
        // Byte 0 = LSB, Byte 3 = MSB
        xgmii_data[8 + len + 0] = crc[7:0];
        xgmii_data[8 + len + 1] = crc[15:8];
        xgmii_data[8 + len + 2] = crc[23:16];
        xgmii_data[8 + len + 3] = crc[31:24];
        
        // Add termination character
        xgmii_data[8 + len + 4] = XGMII_TERM;
        
        // Total XGMII bytes: START(1) + PRE(6) + SFD(1) + DATA(len) + CRC(4) + TERM(1)
        xgmii_len = 13 + len;

        // Calculate number of 8-byte beats needed
        total_beats = (xgmii_len + 7) / 8;

        // Step 3: Transmit XGMII beats to DUT
        for (beat = 0; beat < total_beats; beat = beat + 1) begin
            // Default to IDLE for all lanes
            d = 64'h0707070707070707;
            c = 8'hff;  // All control bits set (IDLE characters)
            
            // Fill in actual data for this beat
            for (lane = 0; lane < 8; lane = lane + 1) begin
                i = beat * 8 + lane;
                if (i < xgmii_len) begin
                    d[lane*8 +: 8] = xgmii_data[i];
                    
                    // Set control bits appropriately:
                    // - Lane 0 of Beat 0: START control character
                    // - Last byte: TERM control character
                    // - All others: Data (control bit = 0)
                    if (beat == 0 && lane == 0) begin
                        c[lane] = 1'b1; // START
                    end else if (i == xgmii_len - 1) begin
                        c[lane] = 1'b1; // TERM
                    end else begin
                        c[lane] = 1'b0; // Data
                    end
                end
            end
            
            // Drive XGMII interface on clock edge
            @(posedge clk);
            #0.1;  // Small delta delay for timing
            sfp0_rxd <= d;
            sfp0_rxc <= c;
        end

        // Step 4: Return to IDLE state for a few cycles
        @(posedge clk);
        #0.1;
        sfp0_rxd <= XGMII_IDLE_QW;
        sfp0_rxc <= XGMII_IDLE_CTRL;
        @(posedge clk);
        #0.1;
        sfp0_rxd <= XGMII_IDLE_QW;
        sfp0_rxc <= XGMII_IDLE_CTRL;
    end
endtask

// ============================================================================
// Task: Wait for TX Frame from DUT
// ============================================================================
// Blocks until the DUT transmits a frame or timeout occurs
// Used to synchronize testbench with DUT responses

task wait_for_tx_frame;
    input integer timeout;  // Maximum clock cycles to wait
    integer cnt;
    begin
        cnt = 0;
        // Wait for tx_frame_count to increment (frame captured)
        while (tx_frame_count == 0 && cnt < timeout) begin
            @(posedge clk);
            cnt = cnt + 1;
        end
        
        // Check if timeout occurred
        if (cnt >= timeout) begin
            $display("[%0t] ERROR: Timeout waiting for TX frame", $time);
            error_count = error_count + 1;
        end else begin
            $display("[%0t] TX frame received (%0d beats)", $time, tx_capture_len);
        end
    end
endtask

// ============================================================================
// Ethernet Packet Construction Helper Functions
// ============================================================================

// -----------------------------------------------------------------------------
// Function: IP Header Checksum Calculation
// -----------------------------------------------------------------------------
// Calculates the one's complement sum checksum used in IPv4 headers.
// 
// Algorithm:
// 1. Sum all 16-bit words in the header
// 2. Add carry bits back to the sum (fold 32-bit to 16-bit)
// 3. Take one's complement (invert all bits)
//
// Input: 160-bit header (10 x 16-bit words)
//   - Words 0-1: Version/IHL, ToS
//   - Words 2-3: Total Length
//   - Words 4-5: ID, Flags/Fragment Offset
//   - Words 6-7: TTL, Protocol
//   - Words 8-9: Checksum (set to 0 during calculation)
//   - Words 10-11: Source IP
//   - Words 12-13: Destination IP
//
// Output: 16-bit checksum value
//
// Note: The input is constructed in reverse byte order because Verilog
//       reads from LSB to MSB. See send_udp_echo for usage example.

function [15:0] ip_checksum;
    input [159:0] header;
    integer i;
    reg [31:0] sum;
    begin
        sum = 0;
        // Sum all 10 16-bit words
        for (i = 0; i < 10; i = i + 1) begin
            sum = sum + header[i*16 +: 16];
        end
        // Fold 32-bit sum to 16-bit (add carry bits)
        while (sum[31:16] != 0) begin
            sum = sum[15:0] + sum[31:16];
        end
        // One's complement (invert all bits)
        ip_checksum = ~sum[15:0];
    end
endfunction

// -----------------------------------------------------------------------------
// Function: Ethernet CRC32 Calculation
// -----------------------------------------------------------------------------
// Calculates the 32-bit CRC used in Ethernet frame check sequence (FCS).
// 
// Standard: IEEE 802.3 (CRC-32)
// Polynomial: 0x04C11DB7 (reflected: 0xEDB88320)
// Initial Value: 0xFFFFFFFF
// XOR Out: 0xFFFFFFFF (final inversion)
//
// Algorithm:
// 1. Initialize CRC to all 1s
// 2. For each byte in the frame:
//    - XOR byte with LSB of CRC
//    - Shift CRC right 8 times
//    - If bit shifted out was 1, XOR with polynomial
// 3. Invert final CRC value
//
// Input: data_len (number of bytes in frame_data[] to process)
// Output: 32-bit CRC value (to be appended to frame in little-endian order)

function [31:0] eth_crc32;
    input integer data_len;
    integer i, j;
    reg [31:0] crc;
    reg [7:0]  byte_data;
    reg        bit_in;
    begin
        // Initialize CRC to all 1s (per IEEE 802.3)
        crc = 32'hFFFFFFFF;
        
        // Process each byte of the frame
        for (i = 0; i < data_len; i = i + 1) begin
            byte_data = frame_data[i];
            
            // Process each bit in the byte (LSB first)
            for (j = 0; j < 8; j = j + 1) begin
                bit_in = byte_data[j] ^ crc[0];
                crc = crc >> 1;
                if (bit_in) crc = crc ^ 32'hEDB88320;  // Reflected polynomial
            end
        end
        
        // Final XOR (invert all bits)
        eth_crc32 = ~crc;
    end
endfunction

// ============================================================================
// ARP Packet Tasks
// ============================================================================

// -----------------------------------------------------------------------------
// Task: Build and Send ARP Request
// -----------------------------------------------------------------------------
// Sends a "Who has DUT_IP? Tell HOST_IP" ARP request.
// 
// ARP Request Format (28 bytes of ARP data, 42 bytes total with Ethernet):
//   Ethernet Header (14 bytes):
//     - Destination: FF:FF:FF:FF:FF:FF (broadcast)
//     - Source: HOST_MAC
//     - Type: 0x0806 (ARP)
//   ARP Payload (28 bytes):
//     - Hardware Type: 0x0001 (Ethernet)
//     - Protocol Type: 0x0800 (IPv4)
//     - HW Addr Len: 6, Proto Addr Len: 4
//     - Opcode: 0x0001 (Request)
//     - Sender MAC: HOST_MAC
//     - Sender IP: HOST_IP
//     - Target MAC: 00:00:00:00:00:00 (unknown, to be filled by DUT)
//     - Target IP: DUT_IP
//
// Total frame size: 60 bytes (minimum Ethernet frame size with padding)

task send_arp_request;
    integer i;
    begin
        $display("[%0t] Sending ARP request...", $time);

        // Ethernet header (bytes 0-13)
        // Destination MAC: Broadcast address
        frame_data[0]  = 8'hFF; frame_data[1]  = 8'hFF; frame_data[2]  = 8'hFF;
        frame_data[3]  = 8'hFF; frame_data[4]  = 8'hFF; frame_data[5]  = 8'hFF;
        // Source MAC: Test host
        frame_data[6]  = HOST_MAC[47:40]; frame_data[7]  = HOST_MAC[39:32];
        frame_data[8]  = HOST_MAC[31:24]; frame_data[9]  = HOST_MAC[23:16];
        frame_data[10] = HOST_MAC[15:8];  frame_data[11] = HOST_MAC[7:0];
        // EtherType: ARP (0x0806)
        frame_data[12] = 8'h08; frame_data[13] = 8'h06;

        // ARP packet (bytes 14-41)
        // Hardware type: Ethernet (1)
        frame_data[14] = 8'h00; frame_data[15] = 8'h01;
        // Protocol type: IPv4 (0x0800)
        frame_data[16] = 8'h08; frame_data[17] = 8'h00;
        // Address lengths: MAC=6 bytes, IP=4 bytes
        frame_data[18] = 8'h06; frame_data[19] = 8'h04;
        // Opcode: Request (1)
        frame_data[20] = 8'h00; frame_data[21] = 8'h01;
        // Sender MAC address
        frame_data[22] = HOST_MAC[47:40]; frame_data[23] = HOST_MAC[39:32];
        frame_data[24] = HOST_MAC[31:24]; frame_data[25] = HOST_MAC[23:16];
        frame_data[26] = HOST_MAC[15:8];  frame_data[27] = HOST_MAC[7:0];
        // Sender IP address
        frame_data[28] = HOST_IP[31:24];  frame_data[29] = HOST_IP[23:16];
        frame_data[30] = HOST_IP[15:8];   frame_data[31] = HOST_IP[7:0];
        // Target MAC address (unknown, set to 0)
        frame_data[32] = 8'h00; frame_data[33] = 8'h00; frame_data[34] = 8'h00;
        frame_data[35] = 8'h00; frame_data[36] = 8'h00; frame_data[37] = 8'h00;
        // Target IP address (the DUT we're querying)
        frame_data[38] = DUT_IP[31:24];   frame_data[39] = DUT_IP[23:16];
        frame_data[40] = DUT_IP[15:8];    frame_data[41] = DUT_IP[7:0];

        // Pad to minimum Ethernet frame size (60 bytes)
        for (i = 42; i < 60; i = i + 1) frame_data[i] = 8'h00;

        send_xgmii_frame(60);
    end
endtask

// -----------------------------------------------------------------------------
// Task: Build and Send ARP Reply
// -----------------------------------------------------------------------------
// Sends an ARP reply in response to DUT's ARP request.
// Tells DUT: "HOST_IP is at HOST_MAC"
//
// ARP Reply Format:
//   Ethernet Header:
//     - Destination: DUT_MAC (unicast to requester)
//     - Source: HOST_MAC
//     - Type: 0x0806 (ARP)
//   ARP Payload:
//     - Opcode: 0x0002 (Reply)
//     - Sender MAC: HOST_MAC
//     - Sender IP: HOST_IP
//     - Target MAC: DUT_MAC
//     - Target IP: DUT_IP

task send_arp_reply;
    integer i;
    begin
        $display("[%0t] Sending ARP reply...", $time);

        // Ethernet header (bytes 0-13)
        // Destination MAC: DUT (the requester)
        frame_data[0]  = HOST_MAC[47:40]; frame_data[1]  = HOST_MAC[39:32];
        frame_data[2]  = HOST_MAC[31:24]; frame_data[3]  = HOST_MAC[23:16];
        frame_data[4]  = HOST_MAC[15:8];  frame_data[5]  = HOST_MAC[7:0];
        // Source MAC: Test host
        frame_data[6]  = DUT_MAC[47:40];  frame_data[7]  = DUT_MAC[39:32];
        frame_data[8]  = DUT_MAC[31:24];  frame_data[9]  = DUT_MAC[23:16];
        frame_data[10] = DUT_MAC[15:8];   frame_data[11] = DUT_MAC[7:0];
        // EtherType: ARP (0x0806)
        frame_data[12] = 8'h08; frame_data[13] = 8'h06;

        // ARP packet (bytes 14-41)
        // Hardware type, Protocol type, Address lengths (same as request)
        frame_data[14] = 8'h00; frame_data[15] = 8'h01;
        frame_data[16] = 8'h08; frame_data[17] = 8'h00;
        frame_data[18] = 8'h06; frame_data[19] = 8'h04;
        // Opcode: Reply (2)
        frame_data[20] = 8'h00; frame_data[21] = 8'h02;
        // Sender MAC: DUT's MAC (we're replying on behalf of DUT)
        frame_data[22] = DUT_MAC[47:40];  frame_data[23] = DUT_MAC[39:32];
        frame_data[24] = DUT_MAC[31:24];  frame_data[25] = DUT_MAC[23:16];
        frame_data[26] = DUT_MAC[15:8];   frame_data[27] = DUT_MAC[7:0];
        // Sender IP: DUT's IP
        frame_data[28] = DUT_IP[31:24];   frame_data[29] = DUT_IP[23:16];
        frame_data[30] = DUT_IP[15:8];    frame_data[31] = DUT_IP[7:0];
        // Target MAC: HOST_MAC (the original requester)
        frame_data[32] = HOST_MAC[47:40]; frame_data[33] = HOST_MAC[39:32];
        frame_data[34] = HOST_MAC[31:24]; frame_data[35] = HOST_MAC[23:16];
        frame_data[36] = HOST_MAC[15:8];  frame_data[37] = HOST_MAC[7:0];
        // Target IP: HOST_IP
        frame_data[38] = HOST_IP[31:24];  frame_data[39] = HOST_IP[23:16];
        frame_data[40] = HOST_IP[15:8];   frame_data[41] = HOST_IP[7:0];

        // Pad to 60 bytes
        for (i = 42; i < 60; i = i + 1) frame_data[i] = 8'h00;

        send_xgmii_frame(60);
    end
endtask

// ============================================================================
// UDP Packet Tasks
// ============================================================================

// Shared payload array for UDP packets
// Max payload size: 64 bytes (can be increased if needed)
reg [7:0] udp_payload_data [0:63];
integer   udp_payload_len;

// -----------------------------------------------------------------------------
// Task: Build and Send UDP Echo Packet
// -----------------------------------------------------------------------------
// Sends a UDP packet to the DUT's echo server (port 1234).
//
// Packet Structure:
//   Ethernet Header (14 bytes):
//     - Destination: DUT_MAC
//     - Source: HOST_MAC
//     - Type: 0x0800 (IPv4)
//   IP Header (20 bytes):
//     - Version: 4, IHL: 5 (20 bytes)
//     - ToS: 0x00
//     - Total Length: 20 + UDP length
//     - ID: 0x0001
//     - Flags: 0x40 (Don't Fragment)
//     - Protocol: 17 (UDP)
//     - Checksum: Calculated by ip_checksum()
//     - Source IP: HOST_IP
//     - Destination IP: DUT_IP
//   UDP Header (8 bytes):
//     - Source Port: src_port
//     - Destination Port: dst_port (typically 1234 for echo server)
//     - Length: 8 + payload length
//     - Checksum: 0x0000 (optional for IPv4)
//   UDP Payload: Variable length data
//
// Parameters:
//   src_port: Source UDP port (will be echoed back as dst_port)
//   dst_port: Destination UDP port (DUT's echo server port)

task send_udp_echo;
    input [15:0] src_port;
    input [15:0] dst_port;
    integer i;
    integer udp_len;     // UDP header + payload
    integer total_len;   // IP header + UDP
    reg [159:0] ip_hdr;  // IP header for checksum calculation
    reg [15:0] cksum;    // Computed checksum
    begin
        $display("[%0t] Sending UDP packet to port %0d...", $time, dst_port);

        // Calculate lengths
        udp_len = 8 + udp_payload_len;    // UDP header (8) + payload
        total_len = 20 + udp_len;          // IP header (20) + UDP

        // Ethernet header (bytes 0-13)
        // Destination MAC: DUT
        frame_data[0]  = DUT_MAC[47:40];  frame_data[1]  = DUT_MAC[39:32];
        frame_data[2]  = DUT_MAC[31:24];  frame_data[3]  = DUT_MAC[23:16];
        frame_data[4]  = DUT_MAC[15:8];   frame_data[5]  = DUT_MAC[7:0];
        // Source MAC: HOST
        frame_data[6]  = HOST_MAC[47:40]; frame_data[7]  = HOST_MAC[39:32];
        frame_data[8]  = HOST_MAC[31:24]; frame_data[9]  = HOST_MAC[23:16];
        frame_data[10] = HOST_MAC[15:8];  frame_data[11] = HOST_MAC[7:0];
        // EtherType: IPv4 (0x0800)
        frame_data[12] = 8'h08; frame_data[13] = 8'h00;

        // IP header (bytes 14-33)
        // Version (4) + IHL (5) = 0x45
        frame_data[14] = 8'h45; frame_data[15] = 8'h00;
        // Total length (big-endian)
        frame_data[16] = total_len[15:8]; frame_data[17] = total_len[7:0];
        // Identification (0x0001)
        frame_data[18] = 8'h00; frame_data[19] = 8'h01;
        // Flags (0x40 = Don't Fragment) + Fragment Offset (0)
        frame_data[20] = 8'h00; frame_data[21] = 8'h00;
        // TTL (64) + Protocol (17 = UDP)
        frame_data[22] = 8'h40; frame_data[23] = 8'h11;
        // Checksum placeholder (will be computed below)
        frame_data[24] = 8'h00; frame_data[25] = 8'h00;
        // Source IP: HOST_IP
        frame_data[26] = HOST_IP[31:24]; frame_data[27] = HOST_IP[23:16];
        frame_data[28] = HOST_IP[15:8];  frame_data[29] = HOST_IP[7:0];
        // Destination IP: DUT_IP
        frame_data[30] = DUT_IP[31:24];  frame_data[31] = DUT_IP[23:16];
        frame_data[32] = DUT_IP[15:8];   frame_data[33] = DUT_IP[7:0];

        // Build IP header for checksum calculation
        // Note: ip_checksum() reads from LSB, so concatenate in reverse order
        // Format: {dst_ip, src_ip, checksum_field, ttl_proto, frag_id, total_len, version_tos}
        ip_hdr = {DUT_IP, HOST_IP, 16'h0000, 16'h4011, 16'h0000, 16'h0001, total_len[15:0], 16'h4500};
        cksum = ip_checksum(ip_hdr);
        $display("[%0t] DEBUG: IP checksum computed = %h (total_len=%h)", $time, cksum, total_len[15:0]);
        
        // Insert computed checksum (big-endian)
        frame_data[24] = cksum[15:8];
        frame_data[25] = cksum[7:0];

        // UDP header (bytes 34-41)
        // Source port (big-endian)
        frame_data[34] = src_port[15:8]; frame_data[35] = src_port[7:0];
        // Destination port (big-endian)
        frame_data[36] = dst_port[15:8]; frame_data[37] = dst_port[7:0];
        // UDP length (big-endian)
        frame_data[38] = udp_len[15:8];  frame_data[39] = udp_len[7:0];
        // UDP checksum (0x0000 = optional, not used)
        frame_data[40] = 8'h00; frame_data[41] = 8'h00;

        // UDP payload
        for (i = 0; i < udp_payload_len; i = i + 1) begin
            frame_data[42 + i] = udp_payload_data[i];
        end

        // Send frame: 34 bytes (headers) + UDP payload length
        send_xgmii_frame(34 + udp_len);
    end
endtask

// ============================================================================
// Verification Tasks
// ============================================================================
// These tasks parse captured TX frames from the DUT and verify correctness

// -----------------------------------------------------------------------------
// Function: Extract Byte from Captured TX Frame
// -----------------------------------------------------------------------------
// Extracts a specific byte from the captured Ethernet frame data.
// 
// The captured data includes XGMII overhead:
//   Beat 0: [START][PRE][PRE][PRE][PRE][PRE][PRE][SFD]
//   Beat 1+: [DATA][DATA][DATA][DATA][DATA][DATA][DATA][DATA]
//
// This function skips the 8-byte XGMII preamble/SFD overhead and extracts
// the actual Ethernet frame byte at the specified position.
//
// XGMII Lane Ordering:
//   - Lane 0 = bits [7:0] (first byte in time within the beat)
//   - Lane 7 = bits [63:56] (last byte in time)
//
// Example: To get Ethernet destination MAC byte 0 (first MAC byte):
//   get_tx_byte(0) returns frame_data[0]

function [7:0] get_tx_byte;
    input integer byte_pos;  // Byte position in Ethernet frame (0 = first MAC byte)
    integer beat;
    integer lane;
    integer actual_pos;
    begin
        // Skip 8 bytes of XGMII overhead: START(1) + preamble(6) + SFD(1)
        actual_pos = byte_pos + 8;
        
        // Calculate which XGMII beat and lane contains this byte
        beat = actual_pos / 8;      // Integer division
        lane = actual_pos % 8;      // Modulo
        
        // Extract the byte from capture buffer
        if (beat < tx_capture_len) begin
            get_tx_byte = tx_capture[beat][lane*8 +: 8];
        end else begin
            get_tx_byte = 8'h00;  // Return 0 if out of bounds
        end
    end
endfunction

// -----------------------------------------------------------------------------
// Task: Verify ARP Reply
// -----------------------------------------------------------------------------
// Verifies that the DUT's ARP reply is correctly formatted:
//   1. Waits for DUT to transmit a frame
//   2. Parses Ethernet header (destination, source, type)
//   3. Parses ARP opcode
//   4. Checks all fields against expected values
//
// Expected ARP Reply:
//   - Ethernet Destination: HOST_MAC (unicast to requester)
//   - Ethernet Source: DUT_MAC
//   - EtherType: 0x0806 (ARP)
//   - ARP Opcode: 0x0002 (Reply)
//
// Note: Only checks header fields, not full ARP payload content

task verify_arp_reply;
    integer i;
    reg [47:0] eth_dst;     // Ethernet destination MAC
    reg [47:0] eth_src;     // Ethernet source MAC
    reg [15:0] eth_type;    // EtherType
    reg [15:0] arp_opcode;  // ARP operation code
    begin
        $display("[%0t] Verifying ARP reply...", $time);
        
        // Wait for DUT to send a frame (timeout: 5000 cycles)
        wait_for_tx_frame(5000);

        // Sanity check: frame must have at least 3 XGMII beats
        if (tx_capture_len < 3) begin
            $display("[%0t] ERROR: TX frame too short", $time);
            error_count = error_count + 1;
            return;
        end

        // Debug: Print first few XGMII beats for troubleshooting
        $display("[%0t] DEBUG: TX capture len = %0d", $time, tx_capture_len);
        for (i = 0; i < 4 && i < tx_capture_len; i = i + 1) begin
            $display("[%0t] DEBUG: beat %0d: data=%h ctrl=%h", $time, i, tx_capture[i], tx_ctrl_capture[i]);
        end

        // Parse Ethernet header (bytes 0-13)
        // MAC addresses are transmitted MSB first (byte 0 = most significant)
        eth_dst = {get_tx_byte(0), get_tx_byte(1), get_tx_byte(2),
                   get_tx_byte(3), get_tx_byte(4), get_tx_byte(5)};
        eth_src = {get_tx_byte(6), get_tx_byte(7), get_tx_byte(8),
                   get_tx_byte(9), get_tx_byte(10), get_tx_byte(11)};
        eth_type = {get_tx_byte(12), get_tx_byte(13)};

        // Parse ARP opcode (bytes 20-21, big-endian)
        arp_opcode = {get_tx_byte(20), get_tx_byte(21)};

        // Debug: Print parsed header fields
        $display("[%0t] DEBUG: eth_dst=%h eth_src=%h eth_type=%h arp_opcode=%h", $time, eth_dst, eth_src, eth_type, arp_opcode);

        // Verification 1: Destination MAC should be HOST_MAC
        if (eth_dst !== HOST_MAC) begin
            $display("[%0t] ERROR: ARP dst MAC mismatch: expected %h, got %h", $time, HOST_MAC, eth_dst);
            error_count = error_count + 1;
        end else $display("[%0t] PASS: ARP dst MAC correct", $time);

        // Verification 2: Source MAC should be DUT_MAC
        if (eth_src !== DUT_MAC) begin
            $display("[%0t] ERROR: ARP src MAC mismatch: expected %h, got %h", $time, DUT_MAC, eth_src);
            error_count = error_count + 1;
        end else $display("[%0t] PASS: ARP src MAC correct", $time);

        // Verification 3: EtherType should be 0x0806 (ARP)
        if (eth_type !== 16'h0806) begin
            $display("[%0t] ERROR: ARP EtherType mismatch: expected 0806, got %h", $time, eth_type);
            error_count = error_count + 1;
        end else $display("[%0t] PASS: ARP EtherType correct", $time);

        // Verification 4: ARP opcode should be 0x0002 (Reply)
        if (arp_opcode !== 16'h0002) begin
            $display("[%0t] ERROR: ARP opcode mismatch: expected 0002, got %h", $time, arp_opcode);
            error_count = error_count + 1;
        end else $display("[%0t] PASS: ARP opcode correct (reply)", $time);
    end
endtask

// ============================================================================
// Expected Payload Buffer for UDP Verification
// ============================================================================

reg [7:0] expected_payload_data [0:63];  // Expected UDP payload
integer   expected_payload_len;           // Expected payload length

// -----------------------------------------------------------------------------
// Task: Verify UDP Echo Reply
// -----------------------------------------------------------------------------
// Verifies that the DUT's UDP echo response is correct:
//   1. Waits for DUT to transmit a frame
//   2. Parses UDP header (source port, destination port)
//   3. Compares payload against expected data
//
// UDP Echo Behavior:
//   - DUT swaps source and destination ports
//   - DUT echoes payload exactly as received
//
// Parameters:
//   exp_src_port: Expected source port in reply (should be original dst_port)
//   exp_dst_port: Expected destination port in reply (should be original src_port)

task verify_udp_echo;
    input [15:0] exp_src_port;  // Expected UDP source port in reply
    input [15:0] exp_dst_port;  // Expected UDP destination port in reply
    integer i;
    reg [15:0] udp_src_port;    // Actual source port from reply
    reg [15:0] udp_dst_port;    // Actual destination port from reply
    reg [7:0]  rx_payload;      // Received payload byte
    reg payload_match;          // Payload comparison flag
    begin
        $display("[%0t] Verifying UDP echo reply...", $time);
        
        // Wait for DUT to send echo frame (timeout: 5000 cycles)
        wait_for_tx_frame(5000);

        // Sanity check: frame must have at least 3 XGMII beats
        if (tx_capture_len < 3) begin
            $display("[%0t] ERROR: TX echo frame too short", $time);
            error_count = error_count + 1;
            return;
        end

        // Debug: Print first 50 bytes of captured frame
        $display("[%0t] DEBUG: TX capture len = %0d", $time, tx_capture_len);
        for (i = 0; i < 50; i = i + 1) begin
            $display("[%0t] DEBUG: byte %0d = %h", $time, i, get_tx_byte(i));
        end

        // Parse UDP header
        // UDP source port at bytes 34-35 (big-endian)
        udp_src_port = {get_tx_byte(34), get_tx_byte(35)};
        // UDP destination port at bytes 36-37 (big-endian)
        udp_dst_port = {get_tx_byte(36), get_tx_byte(37)};

        $display("[%0t] DEBUG: UDP src_port=%h dst_port=%h", $time, udp_src_port, udp_dst_port);

        // Verification 1: Source port should match expected (original dst_port)
        if (udp_src_port !== exp_src_port) begin
            $display("[%0t] ERROR: UDP echo src port mismatch: expected %0d, got %0d",
                     $time, exp_src_port, udp_src_port);
            error_count = error_count + 1;
        end else $display("[%0t] PASS: UDP echo src port correct (%0d)", $time, udp_src_port);

        // Verification 2: Destination port should match expected (original src_port)
        if (udp_dst_port !== exp_dst_port) begin
            $display("[%0t] ERROR: UDP echo dst port mismatch: expected %0d, got %0d",
                     $time, exp_dst_port, udp_dst_port);
            error_count = error_count + 1;
        end else $display("[%0t] PASS: UDP echo dst port correct (%0d)", $time, udp_dst_port);

        // Verification 3: Payload should match expected data
        payload_match = 1;
        for (i = 0; i < expected_payload_len && i < 16; i = i + 1) begin
            rx_payload = get_tx_byte(42 + i);  // Payload starts at byte 42
            if (rx_payload !== expected_payload_data[i]) begin
                payload_match = 0;
                $display("[%0t] DEBUG: payload[%0d] expected %h got %h", $time, i, expected_payload_data[i], rx_payload);
            end
        end

        if (!payload_match) begin
            $display("[%0t] ERROR: UDP echo payload mismatch", $time);
            error_count = error_count + 1;
        end else $display("[%0t] PASS: UDP echo payload matches", $time);
    end
endtask

// -------------------------------------------------------------------------
// Main Test Sequence
// -------------------------------------------------------------------------
initial begin
    $display("========================================");
    $display(" fpga_core Testbench Started");
    $display(" DUT MAC: %h", DUT_MAC);
    $display(" DUT IP:  %h", DUT_IP);
    $display("========================================");

    rst = 1;
    sfp0_tx_rst = 1; sfp0_rx_rst = 1;
    sfp1_tx_rst = 1; sfp1_rx_rst = 1;

    repeat(20) @(posedge clk);

    rst = 0;
    sfp0_tx_rst = 0; sfp0_rx_rst = 0;
    sfp1_tx_rst = 0; sfp1_rx_rst = 0;

    $display("[%0t] Reset released", $time);
    // Wait for DUT internal reset to complete (ARP cache clear takes 512 cycles)
    repeat(600) @(posedge clk);

    // ============================================================
    // Test 1: ARP Request -> ARP Reply
    // ============================================================
    test_num = 1;
    $display("");
    $display("[%0t] ========================================", $time);
    $display("[%0t] Test 1: ARP Request -> ARP Reply", $time);
    $display("[%0t] ========================================", $time);

    reset_tx_capture();
    send_arp_request();
    repeat(500) @(posedge clk);
    verify_arp_reply();

    // Wait for DUT ARP cache to settle
    repeat(1000) @(posedge clk);

    // ============================================================
    // Test 2: UDP Echo to port 1234
    // ============================================================
    test_num = 2;
    $display("");
    $display("[%0t] ========================================", $time);
    $display("[%0t] Test 2: UDP Echo to port 1234", $time);
    $display("[%0t] ========================================", $time);

    reset_tx_capture();
    udp_payload_data[0] = 8'h48; udp_payload_data[1] = 8'h65;
    udp_payload_data[2] = 8'h6C; udp_payload_data[3] = 8'h6C;
    udp_payload_data[4] = 8'h6F; udp_payload_data[5] = 8'h21;
    udp_payload_data[6] = 8'h0A; udp_payload_data[7] = 8'h00;
    udp_payload_len = 8;
    send_udp_echo(16'd5678, 16'd1234);

    // Wait for DUT to potentially send ARP request first
    wait_for_tx_frame(2000);

    // If DUT sent ARP request, reply to it, then re-send UDP
    if (tx_frame_count > 0) begin
        $display("[%0t] DUT sent ARP request, replying...", $time);
        reset_tx_capture();
        send_arp_reply();
        repeat(1000) @(posedge clk);

        // Re-send the UDP packet now that DUT knows our MAC
        $display("[%0t] Re-sending UDP packet after ARP resolution...", $time);
        reset_tx_capture();
        send_udp_echo(16'd5678, 16'd1234);
    end

    // Now wait for UDP echo reply
    wait_for_tx_frame(5000);
    expected_payload_data[0] = 8'h48; expected_payload_data[1] = 8'h65;
    expected_payload_data[2] = 8'h6C; expected_payload_data[3] = 8'h6C;
    expected_payload_data[4] = 8'h6F; expected_payload_data[5] = 8'h21;
    expected_payload_data[6] = 8'h0A; expected_payload_data[7] = 8'h00;
    expected_payload_len = 8;
    verify_udp_echo(16'd1234, 16'd5678);

    // ============================================================
    // Test 3: UDP to wrong port (should NOT echo)
    // ============================================================
    test_num = 3;
    $display("");
    $display("[%0t] ========================================", $time);
    $display("[%0t] Test 3: UDP to wrong port (no echo)", $time);
    $display("[%0t] ========================================", $time);

    reset_tx_capture();
    udp_payload_data[0] = 8'hDE; udp_payload_data[1] = 8'hAD;
    udp_payload_data[2] = 8'hBE; udp_payload_data[3] = 8'hEF;
    udp_payload_len = 4;
    send_udp_echo(16'd9999, 16'd9999);

    repeat(1000) @(posedge clk);
    if (tx_frame_count != 0) begin
        $display("[%0t] ERROR: Unexpected TX frame for wrong port", $time);
        error_count = error_count + 1;
    end else $display("[%0t] PASS: No echo for wrong port", $time);

    // ============================================================
    // Test 4: Multiple UDP packets
    // ============================================================
    test_num = 4;
    $display("");
    $display("[%0t] ========================================", $time);
    $display("[%0t] Test 4: Multiple UDP echo packets", $time);
    $display("[%0t] ========================================", $time);

    reset_tx_capture();
    udp_payload_data[0] = 8'h11; udp_payload_data[1] = 8'h22;
    udp_payload_data[2] = 8'h33; udp_payload_data[3] = 8'h44;
    udp_payload_len = 4;
    send_udp_echo(16'd1111, 16'd1234);
    repeat(500) @(posedge clk);
    expected_payload_data[0] = 8'h11; expected_payload_data[1] = 8'h22;
    expected_payload_data[2] = 8'h33; expected_payload_data[3] = 8'h44;
    expected_payload_len = 4;
    verify_udp_echo(16'd1234, 16'd1111);

    reset_tx_capture();
    udp_payload_data[0] = 8'hAA; udp_payload_data[1] = 8'hBB;
    udp_payload_data[2] = 8'hCC; udp_payload_data[3] = 8'hDD;
    udp_payload_len = 4;
    send_udp_echo(16'd2222, 16'd1234);
    repeat(500) @(posedge clk);
    expected_payload_data[0] = 8'hAA; expected_payload_data[1] = 8'hBB;
    expected_payload_data[2] = 8'hCC; expected_payload_data[3] = 8'hDD;
    expected_payload_len = 4;
    verify_udp_echo(16'd1234, 16'd2222);

    // ============================================================
    // Final Results
    // ============================================================
    repeat(200) @(posedge clk);

    $display("");
    $display("========================================");
    if (error_count == 0) begin
        $display(" ALL TESTS PASSED (%0d tests)", test_num);
    end else begin
        $display(" TEST FAILED: %0d errors in %0d tests", error_count, test_num);
    end
    $display("========================================");

    $finish;
end

// Timeout watchdog
initial begin
    repeat(TIMEOUT_CYCLES) @(posedge clk);
    $display("[%0t] ERROR: Simulation timeout!", $time);
    error_count = error_count + 1;
    $finish;
end

// Waveform dumping for VCS
`ifdef VPD_DUMP
initial begin
    $vcdplusfile("tb_fpga_core.vpd");
    $vcdpluson();
end
`endif

`ifdef FSDB_DUMP
initial begin
    $fsdbDumpfile("tb_fpga_core.fsdb");
    $fsdbDumpvars(0, tb_fpga_core);
    $fsdbDumpMDA();
end
`endif

// VCD waveform dumping (works with both Icarus and VCS)
`ifdef VCD_DUMP
initial begin
    $dumpfile("tb_fpga_core.vcd");
    $dumpvars(0, tb_fpga_core);
end
`endif

`ifdef IVERILOG
initial begin
    $dumpfile("tb_fpga_core.vcd");
    $dumpvars(0, tb_fpga_core);
end
`endif

endmodule

`resetall
