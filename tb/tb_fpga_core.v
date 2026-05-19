/*
 * Testbench for fpga_core
 * Properly verifies ARP request/response and UDP echo
 */

`timescale 1ns / 1ps
`default_nettype none

module tb_fpga_core;

// Clock period for 156.25 MHz
localparam CLK_PERIOD = 6.4;

// Test timeout
localparam TIMEOUT_CYCLES = 500000;

// Clock and reset
reg clk = 0;
reg rst = 1;

// SFP clocks (same as clk for simulation)
wire sfp0_tx_clk = clk;
wire sfp0_rx_clk = clk;
wire sfp1_tx_clk = clk;
wire sfp1_rx_clk = clk;

// SFP resets
reg sfp0_tx_rst = 1;
reg sfp0_rx_rst = 1;
reg sfp1_tx_rst = 1;
reg sfp1_rx_rst = 1;

// GPIO
reg btnu = 0;
reg btnl = 0;
reg btnd = 0;
reg btnr = 0;
reg btnc = 0;
reg [7:0] sw = 0;
wire [7:0] led;

// UART
reg uart_rxd = 0;
wire uart_txd;
reg uart_rts = 0;
wire uart_cts;

// SFP0 XGMII TX (from DUT)
wire [63:0] sfp0_txd;
wire [7:0]  sfp0_txc;

// SFP0 XGMII RX (to DUT)
reg [63:0] sfp0_rxd = 64'h0707070707070707;
reg [7:0]  sfp0_rxc = 8'hff;

// SFP1 XGMII TX (from DUT)
wire [63:0] sfp1_txd;
wire [7:0]  sfp1_txc;

// SFP1 XGMII RX (to DUT)
reg [63:0] sfp1_rxd = 64'h0707070707070707;
reg [7:0]  sfp1_rxc = 8'hff;

// Test control
integer error_count = 0;
integer test_num = 0;

// XGMII constants
localparam [7:0]  XGMII_IDLE    = 8'h07;
localparam [7:0]  XGMII_START   = 8'hFB;
localparam [7:0]  XGMII_TERM    = 8'hFD;
localparam [7:0]  XGMII_ERROR   = 8'hFE;
localparam [7:0]  ETH_PRE       = 8'h55;
localparam [7:0]  ETH_SFD       = 8'hD5;
localparam [63:0] XGMII_IDLE_QW = 64'h0707070707070707;
localparam [7:0]  XGMII_IDLE_CTRL = 8'hff;

// DUT configuration
localparam [47:0] DUT_MAC  = 48'h02_00_00_00_00_00;
localparam [31:0] DUT_IP   = {8'd192, 8'd168, 8'd1, 8'd128};

// Test host configuration
localparam [47:0] HOST_MAC = 48'h02_00_00_00_00_01;
localparam [31:0] HOST_IP  = {8'd192, 8'd168, 8'd1, 8'd1};

// DUT instance
fpga_core dut (
    .clk(clk),
    .rst(rst),
    .btnu(btnu),
    .btnl(btnl),
    .btnd(btnd),
    .btnr(btnr),
    .btnc(btnc),
    .sw(sw),
    .led(led),
    .uart_rxd(uart_rxd),
    .uart_txd(uart_txd),
    .uart_rts(uart_rts),
    .uart_cts(uart_cts),
    .sfp0_tx_clk(sfp0_tx_clk),
    .sfp0_tx_rst(sfp0_tx_rst),
    .sfp0_txd(sfp0_txd),
    .sfp0_txc(sfp0_txc),
    .sfp0_rx_clk(sfp0_rx_clk),
    .sfp0_rx_rst(sfp0_rx_rst),
    .sfp0_rxd(sfp0_rxd),
    .sfp0_rxc(sfp0_rxc),
    .sfp1_tx_clk(sfp1_tx_clk),
    .sfp1_tx_rst(sfp1_tx_rst),
    .sfp1_txd(sfp1_txd),
    .sfp1_txc(sfp1_txc),
    .sfp1_rx_clk(sfp1_rx_clk),
    .sfp1_rx_rst(sfp1_rx_rst),
    .sfp1_rxd(sfp1_rxd),
    .sfp1_rxc(sfp1_rxc)
);

// Clock generation
always #(CLK_PERIOD/2) clk = ~clk;

// -------------------------------------------------------------------------
// XGMII Frame Transmit/Receive Tasks
// -------------------------------------------------------------------------

// XGMII TX monitor: capture frames from DUT
reg [63:0] tx_capture [0:127];
reg [7:0]  tx_ctrl_capture [0:127];
integer    tx_capture_len;
integer    tx_frame_count;
reg        tx_frame_active;

always @(posedge clk) begin
    if (sfp0_tx_rst) begin
        tx_frame_count <= 0;
        tx_frame_active <= 0;
        tx_capture_len <= 0;
    end else begin
        if (sfp0_txc != 8'hff) begin
            if (!tx_frame_active) begin
                tx_frame_active <= 1;
                tx_capture_len <= 0;
            end
            tx_capture[tx_capture_len] <= sfp0_txd;
            tx_ctrl_capture[tx_capture_len] <= sfp0_txc;
            tx_capture_len <= tx_capture_len + 1;
        end else begin
            if (tx_frame_active) begin
                tx_frame_active <= 0;
                tx_frame_count <= tx_frame_count + 1;
            end
        end
    end
end

// Task: Reset TX capture state
task reset_tx_capture;
    begin
        tx_frame_count = 0;
        tx_frame_active = 0;
        tx_capture_len = 0;
    end
endtask

// Frame data buffer
reg [7:0]  frame_data [0:1519];
integer    frame_len;

// Task: Send Ethernet frame over XGMII
// Frame data is in frame_data[0:frame_len-1]
// XGMII format: START + preamble(7) + SFD + data + CRC(4) + TERM
// Note: XGMII lanes are little-endian (lane 0 = byte 0 = bits [7:0])
task send_xgmii_frame;
    input integer len;
    integer i;
    integer beat;
    integer lane;
    reg [63:0] d;
    reg [7:0]  c;
    reg [7:0]  xgmii_data [0:1535];
    integer    xgmii_len;
    integer    total_beats;
    reg [31:0] crc;
    begin
        // Compute CRC over frame data (Ethernet header + payload)
        crc = eth_crc32(len);

        // Build XGMII data list
        // Start character replaces first preamble byte
        xgmii_data[0] = XGMII_START;
        // 6 more preamble bytes
        for (i = 1; i < 7; i = i + 1) begin
            xgmii_data[i] = ETH_PRE;
        end
        // SFD
        xgmii_data[7] = ETH_SFD;
        // Actual frame data
        for (i = 0; i < len; i = i + 1) begin
            xgmii_data[8 + i] = frame_data[i];
        end
        // CRC32 (little-endian byte order)
        xgmii_data[8 + len + 0] = crc[7:0];
        xgmii_data[8 + len + 1] = crc[15:8];
        xgmii_data[8 + len + 2] = crc[23:16];
        xgmii_data[8 + len + 3] = crc[31:24];
        // Terminate
        xgmii_data[8 + len + 4] = XGMII_TERM;
        xgmii_len = 13 + len;

        total_beats = (xgmii_len + 7) / 8;

        for (beat = 0; beat < total_beats; beat = beat + 1) begin
            d = 64'h0707070707070707;
            c = 8'hff;
            for (lane = 0; lane < 8; lane = lane + 1) begin
                i = beat * 8 + lane;
                if (i < xgmii_len) begin
                    d[lane*8 +: 8] = xgmii_data[i];
                    // Only lane 0 of first beat is START control
                    // Only last byte is TERM control
                    if (beat == 0 && lane == 0) begin
                        c[lane] = 1'b1; // START
                    end else if (i == xgmii_len - 1) begin
                        c[lane] = 1'b1; // TERM
                    end else begin
                        c[lane] = 1'b0; // Data
                    end
                end
            end
            @(posedge clk);
            #0.1;
            sfp0_rxd <= d;
            sfp0_rxc <= c;
        end

        // Idle for a few cycles
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

// Task: Wait for TX frame from DUT
task wait_for_tx_frame;
    input integer timeout;
    integer cnt;
    begin
        cnt = 0;
        while (tx_frame_count == 0 && cnt < timeout) begin
            @(posedge clk);
            cnt = cnt + 1;
        end
        if (cnt >= timeout) begin
            $display("[%0t] ERROR: Timeout waiting for TX frame", $time);
            error_count = error_count + 1;
        end else begin
            $display("[%0t] TX frame received (%0d beats)", $time, tx_capture_len);
        end
    end
endtask

// -------------------------------------------------------------------------
// Ethernet Packet Construction
// -------------------------------------------------------------------------

// IP checksum calculation
function [15:0] ip_checksum;
    input [159:0] header;
    integer i;
    reg [31:0] sum;
    begin
        sum = 0;
        for (i = 0; i < 10; i = i + 1) begin
            sum = sum + header[i*16 +: 16];
        end
        while (sum[31:16] != 0) begin
            sum = sum[15:0] + sum[31:16];
        end
        ip_checksum = ~sum[15:0];
    end
endfunction

// Ethernet CRC32 calculation
// CRC-32 IEEE 802.3 (polynomial 0x04C11DB7)
function [31:0] eth_crc32;
    input integer data_len;
    integer i, j;
    reg [31:0] crc;
    reg [7:0]  byte_data;
    reg        bit_in;
    begin
        crc = 32'hFFFFFFFF;
        for (i = 0; i < data_len; i = i + 1) begin
            byte_data = frame_data[i];
            for (j = 0; j < 8; j = j + 1) begin
                bit_in = byte_data[j] ^ crc[0];
                crc = crc >> 1;
                if (bit_in) crc = crc ^ 32'hEDB88320;
            end
        end
        eth_crc32 = ~crc;
    end
endfunction

// Task: Build and send ARP request
task send_arp_request;
    integer i;
    begin
        $display("[%0t] Sending ARP request...", $time);

        // Ethernet header
        frame_data[0]  = 8'hFF; frame_data[1]  = 8'hFF; frame_data[2]  = 8'hFF;
        frame_data[3]  = 8'hFF; frame_data[4]  = 8'hFF; frame_data[5]  = 8'hFF;
        frame_data[6]  = HOST_MAC[47:40]; frame_data[7]  = HOST_MAC[39:32];
        frame_data[8]  = HOST_MAC[31:24]; frame_data[9]  = HOST_MAC[23:16];
        frame_data[10] = HOST_MAC[15:8];  frame_data[11] = HOST_MAC[7:0];
        frame_data[12] = 8'h08; frame_data[13] = 8'h06;

        // ARP packet
        frame_data[14] = 8'h00; frame_data[15] = 8'h01; // HW type: Ethernet
        frame_data[16] = 8'h08; frame_data[17] = 8'h00; // Proto: IPv4
        frame_data[18] = 8'h06; frame_data[19] = 8'h04; // HW len, proto len
        frame_data[20] = 8'h00; frame_data[21] = 8'h01; // Opcode: request
        frame_data[22] = HOST_MAC[47:40]; frame_data[23] = HOST_MAC[39:32];
        frame_data[24] = HOST_MAC[31:24]; frame_data[25] = HOST_MAC[23:16];
        frame_data[26] = HOST_MAC[15:8];  frame_data[27] = HOST_MAC[7:0];
        frame_data[28] = HOST_IP[31:24];  frame_data[29] = HOST_IP[23:16];
        frame_data[30] = HOST_IP[15:8];   frame_data[31] = HOST_IP[7:0];
        frame_data[32] = 8'h00; frame_data[33] = 8'h00; frame_data[34] = 8'h00;
        frame_data[35] = 8'h00; frame_data[36] = 8'h00; frame_data[37] = 8'h00;
        frame_data[38] = DUT_IP[31:24];   frame_data[39] = DUT_IP[23:16];
        frame_data[40] = DUT_IP[15:8];    frame_data[41] = DUT_IP[7:0];

        for (i = 42; i < 60; i = i + 1) frame_data[i] = 8'h00;

        send_xgmii_frame(60);
    end
endtask

// Task: Build and send ARP reply
// DUT_IP is at DUT_MAC; tell HOST_IP
task send_arp_reply;
    integer i;
    begin
        $display("[%0t] Sending ARP reply...", $time);

        // Ethernet header
        frame_data[0]  = HOST_MAC[47:40]; frame_data[1]  = HOST_MAC[39:32];
        frame_data[2]  = HOST_MAC[31:24]; frame_data[3]  = HOST_MAC[23:16];
        frame_data[4]  = HOST_MAC[15:8];  frame_data[5]  = HOST_MAC[7:0];
        frame_data[6]  = DUT_MAC[47:40];  frame_data[7]  = DUT_MAC[39:32];
        frame_data[8]  = DUT_MAC[31:24];  frame_data[9]  = DUT_MAC[23:16];
        frame_data[10] = DUT_MAC[15:8];   frame_data[11] = DUT_MAC[7:0];
        frame_data[12] = 8'h08; frame_data[13] = 8'h06;

        // ARP packet
        frame_data[14] = 8'h00; frame_data[15] = 8'h01; // HW type: Ethernet
        frame_data[16] = 8'h08; frame_data[17] = 8'h00; // Proto: IPv4
        frame_data[18] = 8'h06; frame_data[19] = 8'h04; // HW len, proto len
        frame_data[20] = 8'h00; frame_data[21] = 8'h02; // Opcode: reply
        frame_data[22] = DUT_MAC[47:40];  frame_data[23] = DUT_MAC[39:32];
        frame_data[24] = DUT_MAC[31:24];  frame_data[25] = DUT_MAC[23:16];
        frame_data[26] = DUT_MAC[15:8];   frame_data[27] = DUT_MAC[7:0];
        frame_data[28] = DUT_IP[31:24];   frame_data[29] = DUT_IP[23:16];
        frame_data[30] = DUT_IP[15:8];    frame_data[31] = DUT_IP[7:0];
        frame_data[32] = HOST_MAC[47:40]; frame_data[33] = HOST_MAC[39:32];
        frame_data[34] = HOST_MAC[31:24]; frame_data[35] = HOST_MAC[23:16];
        frame_data[36] = HOST_MAC[15:8];  frame_data[37] = HOST_MAC[7:0];
        frame_data[38] = HOST_IP[31:24];  frame_data[39] = HOST_IP[23:16];
        frame_data[40] = HOST_IP[15:8];   frame_data[41] = HOST_IP[7:0];

        for (i = 42; i < 60; i = i + 1) frame_data[i] = 8'h00;

        send_xgmii_frame(60);
    end
endtask

// Shared payload array for UDP
reg [7:0] udp_payload_data [0:63];
integer   udp_payload_len;

// Task: Build and send UDP packet
task send_udp_echo;
    input [15:0] src_port;
    input [15:0] dst_port;
    integer i;
    integer udp_len;
    integer total_len;
    reg [159:0] ip_hdr;
    reg [15:0] cksum;
    begin
        $display("[%0t] Sending UDP packet to port %0d...", $time, dst_port);

        udp_len = 8 + udp_payload_len;
        total_len = 20 + udp_len;

        // Ethernet header
        frame_data[0]  = DUT_MAC[47:40];  frame_data[1]  = DUT_MAC[39:32];
        frame_data[2]  = DUT_MAC[31:24];  frame_data[3]  = DUT_MAC[23:16];
        frame_data[4]  = DUT_MAC[15:8];   frame_data[5]  = DUT_MAC[7:0];
        frame_data[6]  = HOST_MAC[47:40]; frame_data[7]  = HOST_MAC[39:32];
        frame_data[8]  = HOST_MAC[31:24]; frame_data[9]  = HOST_MAC[23:16];
        frame_data[10] = HOST_MAC[15:8];  frame_data[11] = HOST_MAC[7:0];
        frame_data[12] = 8'h08; frame_data[13] = 8'h00;

        // IP header
        frame_data[14] = 8'h45; frame_data[15] = 8'h00;
        frame_data[16] = total_len[15:8]; frame_data[17] = total_len[7:0];
        frame_data[18] = 8'h00; frame_data[19] = 8'h01;
        frame_data[20] = 8'h00; frame_data[21] = 8'h00;
        frame_data[22] = 8'h40; frame_data[23] = 8'h11;
        frame_data[24] = 8'h00; frame_data[25] = 8'h00;
        frame_data[26] = HOST_IP[31:24]; frame_data[27] = HOST_IP[23:16];
        frame_data[28] = HOST_IP[15:8];  frame_data[29] = HOST_IP[7:0];
        frame_data[30] = DUT_IP[31:24];  frame_data[31] = DUT_IP[23:16];
        frame_data[32] = DUT_IP[15:8];   frame_data[33] = DUT_IP[7:0];

        // Build IP header for checksum
        // Note: ip_checksum reads from LSB, so concatenate in reverse order
        ip_hdr = {DUT_IP, HOST_IP, 16'h0000, 16'h4011, 16'h0000, 16'h0001, total_len[15:0], 16'h4500};
        cksum = ip_checksum(ip_hdr);
        $display("[%0t] DEBUG: IP checksum computed = %h (total_len=%h)", $time, cksum, total_len[15:0]);
        frame_data[24] = cksum[15:8];
        frame_data[25] = cksum[7:0];

        // UDP header
        frame_data[34] = src_port[15:8]; frame_data[35] = src_port[7:0];
        frame_data[36] = dst_port[15:8]; frame_data[37] = dst_port[7:0];
        frame_data[38] = udp_len[15:8];  frame_data[39] = udp_len[7:0];
        frame_data[40] = 8'h00; frame_data[41] = 8'h00;

        for (i = 0; i < udp_payload_len; i = i + 1) begin
            frame_data[42 + i] = udp_payload_data[i];
        end

        send_xgmii_frame(34 + udp_len);
    end
endtask

// -------------------------------------------------------------------------
// Verification Tasks
// -------------------------------------------------------------------------

// Extract byte from captured TX frame at specified byte position
// Skips 8 bytes of XGMII preamble/SFD overhead
// Handles XGMII lane ordering (lane 0 = bits [7:0])
function [7:0] get_tx_byte;
    input integer byte_pos;
    integer beat;
    integer lane;
    integer actual_pos;
    begin
        // Skip 8 bytes: START(1) + preamble(6) + SFD(1)
        actual_pos = byte_pos + 8;
        beat = actual_pos / 8;
        lane = actual_pos % 8;
        if (beat < tx_capture_len) begin
            get_tx_byte = tx_capture[beat][lane*8 +: 8];
        end else begin
            get_tx_byte = 8'h00;
        end
    end
endfunction

task verify_arp_reply;
    integer i;
    reg [47:0] eth_dst;
    reg [47:0] eth_src;
    reg [15:0] eth_type;
    reg [15:0] arp_opcode;
    begin
        $display("[%0t] Verifying ARP reply...", $time);
        wait_for_tx_frame(5000);

        if (tx_capture_len < 3) begin
            $display("[%0t] ERROR: TX frame too short", $time);
            error_count = error_count + 1;
            return;
        end

        // Debug: dump first few beats
        $display("[%0t] DEBUG: TX capture len = %0d", $time, tx_capture_len);
        for (i = 0; i < 4 && i < tx_capture_len; i = i + 1) begin
            $display("[%0t] DEBUG: beat %0d: data=%h ctrl=%h", $time, i, tx_capture[i], tx_ctrl_capture[i]);
        end

        // Parse Ethernet header (bytes 0-13)
        // MAC addresses: byte 0 is MSB
        eth_dst = {get_tx_byte(0), get_tx_byte(1), get_tx_byte(2),
                   get_tx_byte(3), get_tx_byte(4), get_tx_byte(5)};
        eth_src = {get_tx_byte(6), get_tx_byte(7), get_tx_byte(8),
                   get_tx_byte(9), get_tx_byte(10), get_tx_byte(11)};
        eth_type = {get_tx_byte(12), get_tx_byte(13)};

        // ARP opcode at bytes 20-21 (big-endian)
        arp_opcode = {get_tx_byte(20), get_tx_byte(21)};

        $display("[%0t] DEBUG: eth_dst=%h eth_src=%h eth_type=%h arp_opcode=%h", $time, eth_dst, eth_src, eth_type, arp_opcode);

        if (eth_dst !== HOST_MAC) begin
            $display("[%0t] ERROR: ARP dst MAC mismatch: expected %h, got %h", $time, HOST_MAC, eth_dst);
            error_count = error_count + 1;
        end else $display("[%0t] PASS: ARP dst MAC correct", $time);

        if (eth_src !== DUT_MAC) begin
            $display("[%0t] ERROR: ARP src MAC mismatch: expected %h, got %h", $time, DUT_MAC, eth_src);
            error_count = error_count + 1;
        end else $display("[%0t] PASS: ARP src MAC correct", $time);

        if (eth_type !== 16'h0806) begin
            $display("[%0t] ERROR: ARP EtherType mismatch: expected 0806, got %h", $time, eth_type);
            error_count = error_count + 1;
        end else $display("[%0t] PASS: ARP EtherType correct", $time);

        if (arp_opcode !== 16'h0002) begin
            $display("[%0t] ERROR: ARP opcode mismatch: expected 0002, got %h", $time, arp_opcode);
            error_count = error_count + 1;
        end else $display("[%0t] PASS: ARP opcode correct (reply)", $time);
    end
endtask

// Shared expected payload
reg [7:0] expected_payload_data [0:63];
integer   expected_payload_len;

task verify_udp_echo;
    input [15:0] exp_src_port;
    input [15:0] exp_dst_port;
    integer i;
    reg [15:0] udp_src_port;
    reg [15:0] udp_dst_port;
    reg [7:0]  rx_payload;
    reg payload_match;
    begin
        $display("[%0t] Verifying UDP echo reply...", $time);
        wait_for_tx_frame(5000);

        if (tx_capture_len < 3) begin
            $display("[%0t] ERROR: TX echo frame too short", $time);
            error_count = error_count + 1;
            return;
        end

        // Debug: dump captured frame bytes 0-50
        $display("[%0t] DEBUG: TX capture len = %0d", $time, tx_capture_len);
        for (i = 0; i < 50; i = i + 1) begin
            $display("[%0t] DEBUG: byte %0d = %h", $time, i, get_tx_byte(i));
        end

        // UDP src port at bytes 34-35 (big-endian)
        udp_src_port = {get_tx_byte(34), get_tx_byte(35)};
        // UDP dst port at bytes 36-37 (big-endian)
        udp_dst_port = {get_tx_byte(36), get_tx_byte(37)};

        $display("[%0t] DEBUG: UDP src_port=%h dst_port=%h", $time, udp_src_port, udp_dst_port);

        if (udp_src_port !== exp_src_port) begin
            $display("[%0t] ERROR: UDP echo src port mismatch: expected %0d, got %0d",
                     $time, exp_src_port, udp_src_port);
            error_count = error_count + 1;
        end else $display("[%0t] PASS: UDP echo src port correct (%0d)", $time, udp_src_port);

        if (udp_dst_port !== exp_dst_port) begin
            $display("[%0t] ERROR: UDP echo dst port mismatch: expected %0d, got %0d",
                     $time, exp_dst_port, udp_dst_port);
            error_count = error_count + 1;
        end else $display("[%0t] PASS: UDP echo dst port correct (%0d)", $time, udp_dst_port);

        // Verify payload
        payload_match = 1;
        for (i = 0; i < expected_payload_len && i < 16; i = i + 1) begin
            rx_payload = get_tx_byte(42 + i);
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
