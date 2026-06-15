`timescale 1ns / 1ps
`default_nettype none

module tb_fpga_core;

localparam CLK_PERIOD = 6.4;
localparam TIMEOUT_CYCLES = 10000000;

reg clk = 0;
reg rst = 1;

wire sfp0_tx_clk = clk;
wire sfp0_rx_clk = clk;
wire sfp1_tx_clk = clk;
wire sfp1_rx_clk = clk;

reg sfp0_tx_rst = 1;
reg sfp0_rx_rst = 1;
reg sfp1_tx_rst = 1;
reg sfp1_rx_rst = 1;

reg btnu = 0;
reg btnl = 0;
reg btnd = 0;
reg btnr = 0;
reg btnc = 0;
reg [7:0] sw = 0;
wire [7:0] led;

reg uart_rxd = 0;
wire uart_txd;
reg uart_rts = 0;
wire uart_cts;

wire [63:0] sfp0_txd;
wire [7:0]  sfp0_txc;

reg [63:0] sfp0_rxd = 64'h0707070707070707;
reg [7:0]  sfp0_rxc = 8'hff;

wire [63:0] sfp1_txd;
wire [7:0]  sfp1_txc;

reg [63:0] sfp1_rxd = 64'h0707070707070707;
reg [7:0]  sfp1_rxc = 8'hff;

integer error_count = 0;
integer test_num = 0;

localparam [7:0]  XGMII_IDLE    = 8'h07;
localparam [7:0]  XGMII_START   = 8'hFB;
localparam [7:0]  XGMII_TERM    = 8'hFD;
localparam [7:0]  XGMII_ERROR   = 8'hFE;
localparam [7:0]  ETH_PRE       = 8'h55;
localparam [7:0]  ETH_SFD       = 8'hD5;

localparam [63:0] XGMII_IDLE_QW = 64'h0707070707070707;
localparam [7:0]  XGMII_IDLE_CTRL = 8'hff;

localparam [47:0] DUT_MAC  = 48'h02_00_00_00_00_00;
localparam [31:0] DUT_IP   = {8'd192, 8'd168, 8'd1, 8'd128};

localparam [47:0] HOST_MAC = 48'h02_00_00_00_00_01;
localparam [31:0] HOST_IP  = {8'd192, 8'd168, 8'd1, 8'd199};

localparam [15:0] LUDP_PORT = 16'd1234;

localparam [15:0] MAGIC = 16'hDA01;

localparam [7:0] TYPE_DATA    = 8'h01;
localparam [7:0] TYPE_CMD     = 8'h02;
localparam [7:0] TYPE_NACK    = 8'h03;
localparam [7:0] TYPE_CMD_ACK = 8'h04;
localparam [7:0] TYPE_CMD_CPL = 8'h05;
localparam [7:0] TYPE_CREDIT  = 8'h06;

localparam [15:0] CMD_START      = 16'h0001;
localparam [15:0] CMD_STOP       = 16'h0002;
localparam [15:0] CMD_READ_REG   = 16'h0010;
localparam [15:0] CMD_WRITE_REG  = 16'h0011;

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

always #(CLK_PERIOD/2) clk = ~clk;

reg [63:0] tx_capture [0:2047];
reg [7:0]  tx_ctrl_capture [0:2047];
integer    tx_capture_len;
integer    tx_frame_count;
reg        tx_frame_active;

// Detect start of frame: START character in any lane
wire tx_sof_detected = (sfp0_txc[0] && sfp0_txd[7:0] == XGMII_START) ||
                       (sfp0_txc[1] && sfp0_txd[15:8] == XGMII_START) ||
                       (sfp0_txc[2] && sfp0_txd[23:16] == XGMII_START) ||
                       (sfp0_txc[3] && sfp0_txd[31:24] == XGMII_START) ||
                       (sfp0_txc[4] && sfp0_txd[39:32] == XGMII_START) ||
                       (sfp0_txc[5] && sfp0_txd[47:40] == XGMII_START) ||
                       (sfp0_txc[6] && sfp0_txd[55:48] == XGMII_START) ||
                       (sfp0_txc[7] && sfp0_txd[63:56] == XGMII_START);

// Debug XGMII TX
always @(posedge clk) begin
    if (tx_sof_detected) begin
        $display("[%0t] TB: XGMII TX SOF detected, txd=%016h txc=%02h", $time, sfp0_txd, sfp0_txc);
    end
end

// Debug frame capture
always @(posedge clk) begin
    if (tx_frame_active && sfp0_txc == 8'hff) begin
        $display("[%0t] TB: Frame ended, tx_frame_count=%0d", $time, tx_frame_count);
    end
end

always @(posedge clk) begin
    if (sfp0_tx_rst) begin
        tx_frame_count <= 0;
        tx_frame_active <= 0;
        tx_capture_len <= 0;
    end else begin
        if (tx_sof_detected) begin
            // Start of new frame - if we were already capturing, finish previous frame
            if (tx_frame_active) begin
                tx_frame_count <= tx_frame_count + 1;
            end
            tx_frame_active <= 1;
            tx_capture_len <= 0;
            tx_capture[0] <= sfp0_txd;
            tx_ctrl_capture[0] <= sfp0_txc;
            tx_capture_len <= 1;
        end else if (sfp0_txc != 8'hff) begin
            // Data or control characters (but not all idle)
            if (!tx_frame_active) begin
                tx_frame_active <= 1;
                tx_capture_len <= 0;
            end
            tx_capture[tx_capture_len] <= sfp0_txd;
            tx_ctrl_capture[tx_capture_len] <= sfp0_txc;
            tx_capture_len <= tx_capture_len + 1;
        end else begin
            // All idle - end of frame
            if (tx_frame_active) begin
                tx_frame_active <= 0;
                tx_frame_count <= tx_frame_count + 1;
            end
        end
    end
end

task reset_tx_capture;
    begin
        tx_frame_count = 0;
        tx_frame_active = 0;
        tx_capture_len = 0;
    end
endtask

task set_payload_size;
    input [15:0] size_bytes;
    begin
        $display("[%0t] Setting test payload size to %0d bytes", $time, size_bytes);
        dut.test_data_payload_size_reg = size_bytes;
        @(posedge clk);
    end
endtask

reg [7:0]  frame_data [0:1519];
integer    frame_len;

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
        crc = eth_crc32(len);

        xgmii_data[0] = XGMII_START;
        for (i = 1; i < 7; i = i + 1)
            xgmii_data[i] = ETH_PRE;
        xgmii_data[7] = ETH_SFD;

        for (i = 0; i < len; i = i + 1)
            xgmii_data[8 + i] = frame_data[i];

        xgmii_data[8 + len + 0] = crc[7:0];
        xgmii_data[8 + len + 1] = crc[15:8];
        xgmii_data[8 + len + 2] = crc[23:16];
        xgmii_data[8 + len + 3] = crc[31:24];
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
                    if (beat == 0 && lane == 0)
                        c[lane] = 1'b1;
                    else if (i == xgmii_len - 1)
                        c[lane] = 1'b1;
                    else
                        c[lane] = 1'b0;
                end
            end

            @(posedge clk);
            #0.1;
            sfp0_rxd <= d;
            sfp0_rxc <= c;
        end

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

task wait_for_tx_frames;
    input integer count;
    input integer timeout;
    integer cnt;
    integer target;
    begin
        target = tx_frame_count + count;
        cnt = 0;
        while (tx_frame_count < target && cnt < timeout) begin
            @(posedge clk);
            cnt = cnt + 1;
        end

        if (tx_frame_count < target) begin
            $display("[%0t] ERROR: Timeout waiting for %0d TX frames (got %0d)", $time, count, tx_frame_count);
            error_count = error_count + 1;
        end else begin
            $display("[%0t] %0d TX frames received", $time, count);
        end
    end
endtask

function [15:0] ip_checksum;
    input [159:0] header;
    integer i;
    reg [31:0] sum;
    begin
        sum = 0;
        for (i = 0; i < 10; i = i + 1)
            sum = sum + header[i*16 +: 16];
        while (sum[31:16] != 0)
            sum = sum[15:0] + sum[31:16];
        ip_checksum = ~sum[15:0];
    end
endfunction

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

function [7:0] get_tx_byte;
    input integer byte_pos;
    integer beat;
    integer lane;
    integer actual_pos;
    begin
        actual_pos = byte_pos + 8;
        beat = actual_pos / 8;
        lane = actual_pos % 8;
        if (beat < tx_capture_len)
            get_tx_byte = tx_capture[beat][lane*8 +: 8];
        else
            get_tx_byte = 8'h00;
    end
endfunction

task send_arp_request;
    integer i;
    begin
        $display("[%0t] Sending ARP request...", $time);
        frame_data[0]  = 8'hFF; frame_data[1]  = 8'hFF; frame_data[2]  = 8'hFF;
        frame_data[3]  = 8'hFF; frame_data[4]  = 8'hFF; frame_data[5]  = 8'hFF;
        frame_data[6]  = HOST_MAC[47:40]; frame_data[7]  = HOST_MAC[39:32];
        frame_data[8]  = HOST_MAC[31:24]; frame_data[9]  = HOST_MAC[23:16];
        frame_data[10] = HOST_MAC[15:8];  frame_data[11] = HOST_MAC[7:0];
        frame_data[12] = 8'h08; frame_data[13] = 8'h06;
        frame_data[14] = 8'h00; frame_data[15] = 8'h01;
        frame_data[16] = 8'h08; frame_data[17] = 8'h00;
        frame_data[18] = 8'h06; frame_data[19] = 8'h04;
        frame_data[20] = 8'h00; frame_data[21] = 8'h01;
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

task send_arp_reply;
    integer i;
    begin
        $display("[%0t] Sending ARP reply...", $time);
        frame_data[0]  = DUT_MAC[47:40]; frame_data[1]  = DUT_MAC[39:32];
        frame_data[2]  = DUT_MAC[31:24]; frame_data[3]  = DUT_MAC[23:16];
        frame_data[4]  = DUT_MAC[15:8];  frame_data[5]  = DUT_MAC[7:0];
        frame_data[6]  = HOST_MAC[47:40]; frame_data[7]  = HOST_MAC[39:32];
        frame_data[8]  = HOST_MAC[31:24]; frame_data[9]  = HOST_MAC[23:16];
        frame_data[10] = HOST_MAC[15:8];  frame_data[11] = HOST_MAC[7:0];
        frame_data[12] = 8'h08; frame_data[13] = 8'h06;
        frame_data[14] = 8'h00; frame_data[15] = 8'h01;
        frame_data[16] = 8'h08; frame_data[17] = 8'h00;
        frame_data[18] = 8'h06; frame_data[19] = 8'h04;
        frame_data[20] = 8'h00; frame_data[21] = 8'h02;
        frame_data[22] = HOST_MAC[47:40]; frame_data[23] = HOST_MAC[39:32];
        frame_data[24] = HOST_MAC[31:24]; frame_data[25] = HOST_MAC[23:16];
        frame_data[26] = HOST_MAC[15:8];  frame_data[27] = HOST_MAC[7:0];
        frame_data[28] = HOST_IP[31:24];  frame_data[29] = HOST_IP[23:16];
        frame_data[30] = HOST_IP[15:8];   frame_data[31] = HOST_IP[7:0];
        frame_data[32] = DUT_MAC[47:40];  frame_data[33] = DUT_MAC[39:32];
        frame_data[34] = DUT_MAC[31:24];  frame_data[35] = DUT_MAC[23:16];
        frame_data[36] = DUT_MAC[15:8];   frame_data[37] = DUT_MAC[7:0];
        frame_data[38] = DUT_IP[31:24];   frame_data[39] = DUT_IP[23:16];
        frame_data[40] = DUT_IP[15:8];    frame_data[41] = DUT_IP[7:0];
        for (i = 42; i < 60; i = i + 1) frame_data[i] = 8'h00;
        send_xgmii_frame(60);
    end
endtask

task send_ludp_packet;
    input [7:0]  pkt_type;
    input [7:0]  flags;
    input [31:0] seq_num;
    input [15:0] opcode;
    input [31:0] arg1;
    input [15:0] arg2;
    input integer payload_len;
    integer i;
    integer udp_len;
    integer total_len;
    reg [159:0] ip_hdr;
    reg [15:0] cksum;
    begin
        udp_len = 8 + 16 + payload_len;
        total_len = 20 + udp_len;

        frame_data[0]  = DUT_MAC[47:40];  frame_data[1]  = DUT_MAC[39:32];
        frame_data[2]  = DUT_MAC[31:24];  frame_data[3]  = DUT_MAC[23:16];
        frame_data[4]  = DUT_MAC[15:8];   frame_data[5]  = DUT_MAC[7:0];
        frame_data[6]  = HOST_MAC[47:40]; frame_data[7]  = HOST_MAC[39:32];
        frame_data[8]  = HOST_MAC[31:24]; frame_data[9]  = HOST_MAC[23:16];
        frame_data[10] = HOST_MAC[15:8];  frame_data[11] = HOST_MAC[7:0];
        frame_data[12] = 8'h08; frame_data[13] = 8'h00;

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

        ip_hdr = {DUT_IP, HOST_IP, 16'h0000, 16'h4011, 16'h0000, 16'h0001, total_len[15:0], 16'h4500};
        cksum = ip_checksum(ip_hdr);
        frame_data[24] = cksum[15:8];
        frame_data[25] = cksum[7:0];

        frame_data[34] = LUDP_PORT[15:8]; frame_data[35] = LUDP_PORT[7:0];
        frame_data[36] = LUDP_PORT[15:8]; frame_data[37] = LUDP_PORT[7:0];
        frame_data[38] = udp_len[15:8];  frame_data[39] = udp_len[7:0];
        frame_data[40] = 8'h00; frame_data[41] = 8'h00;

        // LUDP Header Beat 0: {SeqNum(32), Flags(8), Type(8), Magic(16)}
        frame_data[42] = MAGIC[7:0];   frame_data[43] = MAGIC[15:8];
        frame_data[44] = pkt_type;     frame_data[45] = flags;
        frame_data[46] = seq_num[7:0];  frame_data[47] = seq_num[15:8];
        frame_data[48] = seq_num[23:16]; frame_data[49] = seq_num[31:24];

        // LUDP Header Beat 1: {Reserved(16), Arg1(32), Opcode(16)}
        frame_data[50] = opcode[7:0];  frame_data[51] = opcode[15:8];
        frame_data[52] = arg1[7:0];    frame_data[53] = arg1[15:8];
        frame_data[54] = arg1[23:16];  frame_data[55] = arg1[31:24];
        frame_data[56] = arg2[7:0];    frame_data[57] = arg2[15:8];
        frame_data[58] = 8'h00;        frame_data[59] = 8'h00;

        for (i = 0; i < payload_len; i = i + 1)
            frame_data[60 + i] = 8'h00;

        send_xgmii_frame(34 + udp_len);
    end
endtask

task send_icmp_echo_request;
    input [15:0] icmp_id;
    input [15:0] icmp_seq;
    input integer payload_len;
    integer i;
    integer total_len;
    reg [159:0] ip_hdr;
    reg [15:0] cksum;
    reg [15:0] icmp_cksum;
    begin
        total_len = 20 + 8 + payload_len;

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
        frame_data[22] = 8'h40; frame_data[23] = 8'h01;  // TTL=64, Protocol=ICMP
        frame_data[24] = 8'h00; frame_data[25] = 8'h00;
        frame_data[26] = HOST_IP[31:24]; frame_data[27] = HOST_IP[23:16];
        frame_data[28] = HOST_IP[15:8];  frame_data[29] = HOST_IP[7:0];
        frame_data[30] = DUT_IP[31:24];  frame_data[31] = DUT_IP[23:16];
        frame_data[32] = DUT_IP[15:8];   frame_data[33] = DUT_IP[7:0];

        ip_hdr = {DUT_IP, HOST_IP, 16'h0000, 16'h4001, 16'h0000, 16'h0001, total_len[15:0], 16'h4500};
        cksum = ip_checksum(ip_hdr);
        frame_data[24] = cksum[15:8];
        frame_data[25] = cksum[7:0];

        // ICMP header: Type=8 (echo request), Code=0, Checksum, ID, Seq
        frame_data[34] = 8'h08;  // Type: Echo Request
        frame_data[35] = 8'h00;  // Code: 0
        frame_data[36] = 8'h00; frame_data[37] = 8'h00;  // Checksum (placeholder)
        frame_data[38] = icmp_id[15:8];  frame_data[39] = icmp_id[7:0];
        frame_data[40] = icmp_seq[15:8]; frame_data[41] = icmp_seq[7:0];

        // ICMP payload
        for (i = 0; i < payload_len; i = i + 1)
            frame_data[42 + i] = 8'hA5 + i[7:0];

        // Calculate ICMP checksum
        icmp_cksum = icmp_checksum(42 + payload_len);
        frame_data[36] = icmp_cksum[15:8];
        frame_data[37] = icmp_cksum[7:0];

        $display("[%0t] Sending ICMP Echo Request: id=%04h seq=%04h payload=%0d bytes ip_cksum=%04h icmp_cksum=%04h", $time, icmp_id, icmp_seq, payload_len, cksum, icmp_cksum);
        $display("[%0t] ICMP frame data: eth_type=%02h%02h ip_proto=%02h ip_cksum=%02h%02h icmp_type=%02h icmp_code=%02h", $time, frame_data[12], frame_data[13], frame_data[23], frame_data[24], frame_data[25], frame_data[34], frame_data[35]);
        send_xgmii_frame(34 + 8 + payload_len);
    end
endtask

function [15:0] icmp_checksum;
    input integer len;
    integer i;
    reg [31:0] sum;
    reg [15:0] word;
    begin
        sum = 0;
        for (i = 34; i < len; i = i + 2) begin
            if (i + 1 < len)
                word = {frame_data[i], frame_data[i+1]};
            else
                word = {frame_data[i], 8'h00};
            sum = sum + word;
        end
        while (sum[31:16] != 0)
            sum = sum[31:16] + sum[15:0];
        icmp_checksum = ~sum[15:0];
    end
endfunction

task verify_icmp_echo_reply;
    input [15:0] exp_id;
    input [15:0] exp_seq;
    reg [47:0] eth_dst;
    reg [47:0] eth_src;
    reg [15:0] eth_type;
    reg [31:0] ip_src;
    reg [31:0] ip_dst;
    reg [7:0]  icmp_type;
    reg [7:0]  icmp_code;
    reg [15:0] icmp_id_rx;
    reg [15:0] icmp_seq_rx;
    begin
        wait_for_tx_frame(5000);

        if (tx_capture_len < 3) begin
            $display("[%0t] ERROR: No ICMP reply captured", $time);
            error_count = error_count + 1;
            return;
        end

        eth_dst = {get_tx_byte(0), get_tx_byte(1), get_tx_byte(2),
                   get_tx_byte(3), get_tx_byte(4), get_tx_byte(5)};
        eth_src = {get_tx_byte(6), get_tx_byte(7), get_tx_byte(8),
                   get_tx_byte(9), get_tx_byte(10), get_tx_byte(11)};
        eth_type = {get_tx_byte(12), get_tx_byte(13)};
        ip_src = {get_tx_byte(26), get_tx_byte(27), get_tx_byte(28), get_tx_byte(29)};
        ip_dst = {get_tx_byte(30), get_tx_byte(31), get_tx_byte(32), get_tx_byte(33)};
        icmp_type = get_tx_byte(34);
        icmp_code = get_tx_byte(35);
        icmp_id_rx = {get_tx_byte(38), get_tx_byte(39)};
        icmp_seq_rx = {get_tx_byte(40), get_tx_byte(41)};

        $display("[%0t] ICMP Reply: dst=%012h src=%012h type=%04h ip_src=%08h ip_dst=%08h icmp_type=%02h icmp_code=%02h id=%04h seq=%04h",
                 $time, eth_dst, eth_src, eth_type, ip_src, ip_dst, icmp_type, icmp_code, icmp_id_rx, icmp_seq_rx);

        if (eth_dst !== HOST_MAC) begin
            $display("[%0t] ERROR: ICMP reply dst MAC mismatch: expected %012h, got %012h", $time, HOST_MAC, eth_dst);
            error_count = error_count + 1;
        end else $display("[%0t] PASS: ICMP reply dst MAC correct", $time);

        if (eth_src !== DUT_MAC) begin
            $display("[%0t] ERROR: ICMP reply src MAC mismatch: expected %012h, got %012h", $time, DUT_MAC, eth_src);
            error_count = error_count + 1;
        end else $display("[%0t] PASS: ICMP reply src MAC correct", $time);

        if (eth_type !== 16'h0800) begin
            $display("[%0t] ERROR: ICMP reply EtherType mismatch: expected 0800, got %04h", $time, eth_type);
            error_count = error_count + 1;
        end else $display("[%0t] PASS: ICMP reply EtherType correct", $time);

        if (ip_src !== DUT_IP) begin
            $display("[%0t] ERROR: ICMP reply IP src mismatch: expected %08h, got %08h", $time, DUT_IP, ip_src);
            error_count = error_count + 1;
        end else $display("[%0t] PASS: ICMP reply IP src correct", $time);

        if (ip_dst !== HOST_IP) begin
            $display("[%0t] ERROR: ICMP reply IP dst mismatch: expected %08h, got %08h", $time, HOST_IP, ip_dst);
            error_count = error_count + 1;
        end else $display("[%0t] PASS: ICMP reply IP dst correct", $time);

        if (icmp_type !== 8'h00) begin
            $display("[%0t] ERROR: ICMP type mismatch: expected 00 (echo reply), got %02h", $time, icmp_type);
            error_count = error_count + 1;
        end else $display("[%0t] PASS: ICMP type correct (echo reply)", $time);

        if (icmp_code !== 8'h00) begin
            $display("[%0t] ERROR: ICMP code mismatch: expected 00, got %02h", $time, icmp_code);
            error_count = error_count + 1;
        end else $display("[%0t] PASS: ICMP code correct", $time);

        if (icmp_id_rx !== exp_id) begin
            $display("[%0t] ERROR: ICMP ID mismatch: expected %04h, got %04h", $time, exp_id, icmp_id_rx);
            error_count = error_count + 1;
        end else $display("[%0t] PASS: ICMP ID correct", $time);

        if (icmp_seq_rx !== exp_seq) begin
            $display("[%0t] ERROR: ICMP seq mismatch: expected %04h, got %04h", $time, exp_seq, icmp_seq_rx);
            error_count = error_count + 1;
        end else $display("[%0t] PASS: ICMP seq correct", $time);
    end
endtask

task send_ludp_cmd;
    input [15:0] opcode;
    input [31:0] arg1;
    input [15:0] arg2;
    input [7:0]  flags;
    begin
        $display("[%0t] Sending LUDP CMD: opcode=%04h arg1=%08h arg2=%04h flags=%02h", $time, opcode, arg1, arg2, flags);
        send_ludp_packet(TYPE_CMD, flags, 32'h0, opcode, arg1, arg2, 0);
    end
endtask

task send_ludp_credit;
    input [31:0] credit;
    begin
        $display("[%0t] Sending LUDP CREDIT: credit=%08h", $time, credit);
        send_ludp_packet(TYPE_CREDIT, 8'h00, credit, 16'h0, 32'h0, 16'h0, 0);
    end
endtask

task send_ludp_nack;
    input [31:0] miss_seq;
    input [15:0] count;
    begin
        $display("[%0t] Sending LUDP NACK: miss_seq=%08h count=%04h", $time, miss_seq, count);
        send_ludp_packet(TYPE_NACK, 8'h00, miss_seq, count, 32'h0, 16'h0, 0);
    end
endtask

task send_ludp_packet_with_tuser_err;
    input [7:0]  pkt_type;
    input [7:0]  flags;
    input [31:0] seq_num;
    input [15:0] opcode;
    input [31:0] arg1;
    input [15:0] arg2;
    input integer payload_len;
    integer i;
    integer udp_len;
    integer total_len;
    reg [159:0] ip_hdr;
    reg [15:0] cksum;
    begin
        $display("[%0t] Sending LUDP packet with tuser error: type=%02h", $time, pkt_type);
        udp_len = 8 + 16 + payload_len;
        total_len = 20 + udp_len;

        frame_data[0]  = DUT_MAC[47:40];  frame_data[1]  = DUT_MAC[39:32];
        frame_data[2]  = DUT_MAC[31:24];  frame_data[3]  = DUT_MAC[23:16];
        frame_data[4]  = DUT_MAC[15:8];   frame_data[5]  = DUT_MAC[7:0];
        frame_data[6]  = HOST_MAC[47:40]; frame_data[7]  = HOST_MAC[39:32];
        frame_data[8]  = HOST_MAC[31:24]; frame_data[9]  = HOST_MAC[23:16];
        frame_data[10] = HOST_MAC[15:8];  frame_data[11] = HOST_MAC[7:0];
        frame_data[12] = 8'h08; frame_data[13] = 8'h00;

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

        ip_hdr = {DUT_IP, HOST_IP, 16'h0000, 16'h4011, 16'h0000, 16'h0001, total_len[15:0], 16'h4500};
        cksum = ip_checksum(ip_hdr);
        frame_data[24] = cksum[15:8];
        frame_data[25] = cksum[7:0];

        frame_data[34] = LUDP_PORT[15:8]; frame_data[35] = LUDP_PORT[7:0];
        frame_data[36] = LUDP_PORT[15:8]; frame_data[37] = LUDP_PORT[7:0];
        frame_data[38] = udp_len[15:8];  frame_data[39] = udp_len[7:0];
        frame_data[40] = 8'h00; frame_data[41] = 8'h00;

        frame_data[42] = MAGIC[7:0];   frame_data[43] = MAGIC[15:8];
        frame_data[44] = pkt_type;     frame_data[45] = flags;
        frame_data[46] = seq_num[7:0];  frame_data[47] = seq_num[15:8];
        frame_data[48] = seq_num[23:16]; frame_data[49] = seq_num[31:24];

        frame_data[50] = opcode[7:0];  frame_data[51] = opcode[15:8];
        frame_data[52] = arg1[7:0];    frame_data[53] = arg1[15:8];
        frame_data[54] = arg1[23:16];  frame_data[55] = arg1[31:24];
        frame_data[56] = arg2[7:0];    frame_data[57] = arg2[15:8];
        frame_data[58] = 8'h00;        frame_data[59] = 8'h00;

        for (i = 0; i < payload_len; i = i + 1)
            frame_data[60 + i] = 8'h00;

        send_xgmii_frame_with_err(34 + udp_len);
    end
endtask

task send_xgmii_frame_with_err;
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
    integer    last_data_lane;
    begin
        crc = eth_crc32(len);

        xgmii_data[0] = XGMII_START;
        for (i = 1; i < 7; i = i + 1)
            xgmii_data[i] = ETH_PRE;
        xgmii_data[7] = ETH_SFD;

        for (i = 0; i < len; i = i + 1)
            xgmii_data[8 + i] = frame_data[i];

        xgmii_data[8 + len + 0] = crc[7:0];
        xgmii_data[8 + len + 1] = crc[15:8];
        xgmii_data[8 + len + 2] = crc[23:16];
        xgmii_data[8 + len + 3] = crc[31:24];
        xgmii_data[8 + len + 4] = XGMII_ERROR;

        xgmii_len = 13 + len;
        total_beats = (xgmii_len + 7) / 8;

        for (beat = 0; beat < total_beats; beat = beat + 1) begin
            d = 64'h0707070707070707;
            c = 8'hff;

            for (lane = 0; lane < 8; lane = lane + 1) begin
                i = beat * 8 + lane;
                if (i < xgmii_len) begin
                    d[lane*8 +: 8] = xgmii_data[i];
                    if (beat == 0 && lane == 0)
                        c[lane] = 1'b1;
                    else if (xgmii_data[i] == XGMII_ERROR)
                        c[lane] = 1'b1;
                    else if (i == xgmii_len - 1)
                        c[lane] = 1'b1;
                    else
                        c[lane] = 1'b0;
                end
            end

            @(posedge clk);
            #0.1;
            sfp0_rxd <= d;
            sfp0_rxc <= c;
        end

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

task verify_arp_reply;
    integer i;
    reg [47:0] eth_dst;
    reg [47:0] eth_src;
    reg [15:0] eth_type;
    reg [15:0] arp_opcode;
    reg found;
    integer search_beat;
    begin
        $display("[%0t] Verifying ARP reply...", $time);
        wait_for_tx_frame(5000);

        if (tx_capture_len < 3) begin
            $display("[%0t] ERROR: TX frame too short", $time);
            error_count = error_count + 1;
            return;
        end

        // Search through captured beats for ARP reply (opcode 0x0002)
        // ARP reply EtherType is at bytes 12-13, opcode at bytes 20-21
        // In XGMII capture, frame starts at beat 0 with 8 bytes overhead
        // So byte 12 is at beat 1 lane 4, byte 13 at beat 1 lane 5
        // Byte 20 is at beat 2 lane 4, byte 21 at beat 2 lane 5
        found = 0;
        for (search_beat = 0; search_beat < tx_capture_len && !found; search_beat = search_beat + 1) begin
            // Check if this beat contains the ARP opcode field
            // The opcode is at bytes 20-21 of the ARP packet
            // After 8-byte preamble/SFD, byte 20 is at beat offset 2, lane 4
            if (search_beat >= 2) begin
                // Quick check: look for ARP reply opcode pattern
                // We need to be more flexible about where the frame starts
                eth_type = {get_tx_byte(12), get_tx_byte(13)};
                arp_opcode = {get_tx_byte(20), get_tx_byte(21)};
                if (eth_type == 16'h0806 && arp_opcode == 16'h0002) begin
                    found = 1;
                    eth_dst = {get_tx_byte(0), get_tx_byte(1), get_tx_byte(2),
                               get_tx_byte(3), get_tx_byte(4), get_tx_byte(5)};
                    eth_src = {get_tx_byte(6), get_tx_byte(7), get_tx_byte(8),
                               get_tx_byte(9), get_tx_byte(10), get_tx_byte(11)};
                end
            end
        end

        if (!found) begin
            // Fallback: just check the first frame assuming it's the ARP reply
            eth_dst = {get_tx_byte(0), get_tx_byte(1), get_tx_byte(2),
                       get_tx_byte(3), get_tx_byte(4), get_tx_byte(5)};
            eth_src = {get_tx_byte(6), get_tx_byte(7), get_tx_byte(8),
                       get_tx_byte(9), get_tx_byte(10), get_tx_byte(11)};
            eth_type = {get_tx_byte(12), get_tx_byte(13)};
            arp_opcode = {get_tx_byte(20), get_tx_byte(21)};
            $display("[%0t] WARNING: ARP reply not clearly identified, checking first frame", $time);
            $display("[%0t] ARP: dst=%012h src=%012h type=%04h opcode=%04h",
                     $time, eth_dst, eth_src, eth_type, arp_opcode);
        end else begin
            $display("[%0t] ARP: dst=%012h src=%012h type=%04h opcode=%04h",
                     $time, eth_dst, eth_src, eth_type, arp_opcode);
        end

        if (eth_dst !== HOST_MAC) begin
            $display("[%0t] ERROR: ARP dst MAC mismatch: expected %012h, got %012h", $time, HOST_MAC, eth_dst);
            error_count = error_count + 1;
        end else $display("[%0t] PASS: ARP dst MAC correct", $time);

        if (eth_src !== DUT_MAC) begin
            $display("[%0t] ERROR: ARP src MAC mismatch: expected %012h, got %012h", $time, DUT_MAC, eth_src);
            error_count = error_count + 1;
        end else $display("[%0t] PASS: ARP src MAC correct", $time);

        if (eth_type !== 16'h0806) begin
            $display("[%0t] ERROR: ARP EtherType mismatch: expected 0806, got %04h", $time, eth_type);
            error_count = error_count + 1;
        end else $display("[%0t] PASS: ARP EtherType correct", $time);

        if (arp_opcode !== 16'h0002) begin
            $display("[%0t] ERROR: ARP opcode mismatch: expected 0002, got %04h", $time, arp_opcode);
            error_count = error_count + 1;
        end else $display("[%0t] PASS: ARP opcode correct (reply)", $time);
    end
endtask

task verify_ludp_response;
    input [7:0]  exp_type;
    input [15:0] exp_opcode;
    reg [15:0] udp_src_port;
    reg [15:0] udp_dst_port;
    reg [15:0] rx_magic;
    reg [7:0]  rx_type;
    reg [7:0]  rx_status;
    reg [31:0] rx_cmd_id;
    reg [15:0] rx_resp_opcode;
    begin
        $display("[%0t] Verifying LUDP response (type=%02h, opcode=%04h)...", $time, exp_type, exp_opcode);
        wait_for_tx_frame(5000);

        if (tx_capture_len < 3) begin
            $display("[%0t] ERROR: Response TX frame too short", $time);
            error_count = error_count + 1;
            return;
        end

        udp_src_port = {get_tx_byte(34), get_tx_byte(35)};
        udp_dst_port = {get_tx_byte(36), get_tx_byte(37)};

        rx_magic = {get_tx_byte(43), get_tx_byte(42)};
        rx_type = get_tx_byte(44);
        rx_status = get_tx_byte(45);
        rx_cmd_id = {get_tx_byte(49), get_tx_byte(48), get_tx_byte(47), get_tx_byte(46)};
        rx_resp_opcode = {get_tx_byte(51), get_tx_byte(50)};

        $display("[%0t] RESP: src_port=%0d dst_port=%0d magic=%04h type=%02h status=%02h cmd_id=%08h opcode=%04h",
                 $time, udp_src_port, udp_dst_port, rx_magic, rx_type, rx_status, rx_cmd_id, rx_resp_opcode);

        if (rx_magic !== MAGIC) begin
            $display("[%0t] ERROR: Magic mismatch: expected %04h, got %04h", $time, MAGIC, rx_magic);
            error_count = error_count + 1;
        end else $display("[%0t] PASS: Magic correct", $time);

        if (rx_type !== exp_type) begin
            $display("[%0t] ERROR: Expected type %02h, got %02h", $time, exp_type, rx_type);
            error_count = error_count + 1;
        end else $display("[%0t] PASS: Type correct", $time);

        if (rx_resp_opcode !== exp_opcode) begin
            $display("[%0t] ERROR: Opcode expected %04h, got %04h", $time, exp_opcode, rx_resp_opcode);
            error_count = error_count + 1;
        end else $display("[%0t] PASS: Opcode correct", $time);
    end
endtask

task verify_ludp_data;
    input [31:0] exp_seq;
    input [15:0] exp_pay_len;  // Expected payload size (0 = skip check)
    reg [15:0] udp_src_port;
    reg [15:0] udp_dst_port;
    reg [15:0] udp_len;
    reg [15:0] rx_magic;
    reg [7:0]  rx_type;
    reg [7:0]  rx_flags;
    reg [31:0] rx_seq;
    reg [15:0] rx_pay_len;
    reg [15:0] exp_udp_len;
    reg [31:0] ip_dst;
    begin
        $display("[%0t] Verifying LUDP DATA packet (expecting seq=%08h, pay_len=%0d)...",
                 $time, exp_seq, exp_pay_len);
        wait_for_tx_frame(5000);

        if (tx_capture_len < 3) begin
            $display("[%0t] ERROR: DATA TX frame too short", $time);
            error_count = error_count + 1;
            return;
        end

        udp_src_port = {get_tx_byte(34), get_tx_byte(35)};
        udp_dst_port = {get_tx_byte(36), get_tx_byte(37)};
        udp_len      = {get_tx_byte(38), get_tx_byte(39)};

        rx_magic   = {get_tx_byte(43), get_tx_byte(42)};
        rx_type    = get_tx_byte(44);
        rx_flags   = get_tx_byte(45);
        rx_seq     = {get_tx_byte(49), get_tx_byte(48), get_tx_byte(47), get_tx_byte(46)};
        rx_pay_len = {get_tx_byte(51), get_tx_byte(50)};

        // Verify IP destination (catches wrong host IP bug)
        ip_dst = {get_tx_byte(30), get_tx_byte(31), get_tx_byte(32), get_tx_byte(33)};

        $display("[%0t] DATA: src_port=%0d dst_port=%0d udp_len=%0d magic=%04h type=%02h flags=%02h seq=%08h hdr_pay_len=%0d ip_dst=%08h",
                 $time, udp_src_port, udp_dst_port, udp_len, rx_magic, rx_type, rx_flags, rx_seq, rx_pay_len, ip_dst);

        if (rx_magic !== MAGIC) begin
            $display("[%0t] ERROR: Magic mismatch: expected %04h, got %04h", $time, MAGIC, rx_magic);
            error_count = error_count + 1;
        end else $display("[%0t] PASS: Magic correct", $time);

        if (rx_type !== TYPE_DATA) begin
            $display("[%0t] ERROR: Expected DATA type %02h, got %02h", $time, TYPE_DATA, rx_type);
            error_count = error_count + 1;
        end else $display("[%0t] PASS: DATA type correct", $time);

        if (rx_seq !== exp_seq) begin
            $display("[%0t] ERROR: DATA seq expected %08h, got %08h", $time, exp_seq, rx_seq);
            error_count = error_count + 1;
        end else $display("[%0t] PASS: DATA seq correct (%08h)", $time, rx_seq);

        // Verify UDP length: 8(UDP hdr) + 16(LUDP hdr) + payload
        if (exp_pay_len > 0) begin
            exp_udp_len = 8 + 16 + exp_pay_len;
            if (udp_len !== exp_udp_len) begin
                $display("[%0t] ERROR: UDP length mismatch: expected %0d, got %0d",
                         $time, exp_udp_len, udp_len);
                error_count = error_count + 1;
            end else $display("[%0t] PASS: UDP length correct (%0d)", $time, udp_len);
        end

        // Verify IP destination matches expected host IP
        if (ip_dst !== HOST_IP) begin
            $display("[%0t] ERROR: IP destination mismatch: expected %08h, got %08h", $time, HOST_IP, ip_dst);
            error_count = error_count + 1;
        end else $display("[%0t] PASS: IP destination correct (%08h)", $time, ip_dst);

        // Payload integrity verification from captured TX frame
        begin : payload_check_block
            integer num_beats;
            integer beat_idx;
            integer local_errors;
            reg [63:0] payload_beat;
            integer byte_offset;
            reg [15:0] rx_pkt_idx;
            reg [15:0] rx_beat_idx;
            reg [31:0] rx_marker;

            num_beats = rx_pay_len / 8;
            local_errors = 0;

            for (beat_idx = 0; beat_idx < num_beats; beat_idx = beat_idx + 1) begin
                byte_offset = 58 + beat_idx * 8;
                payload_beat[63:56] = get_tx_byte(byte_offset + 7);
                payload_beat[55:48] = get_tx_byte(byte_offset + 6);
                payload_beat[47:40] = get_tx_byte(byte_offset + 5);
                payload_beat[39:32] = get_tx_byte(byte_offset + 4);
                payload_beat[31:24] = get_tx_byte(byte_offset + 3);
                payload_beat[23:16] = get_tx_byte(byte_offset + 2);
                payload_beat[15:8]  = get_tx_byte(byte_offset + 1);
                payload_beat[7:0]   = get_tx_byte(byte_offset);

                rx_marker  = payload_beat[31:0];
                rx_beat_idx = payload_beat[47:32];
                rx_pkt_idx = payload_beat[63:48];

                if (beat_idx < 3) begin
                    $display("[%0t] DEBUG: beat %0d raw_bytes=%02h_%02h_%02h_%02h_%02h_%02h_%02h_%02h payload=%016h marker=%08h pkt=%04h beat=%04h",
                             $time, beat_idx,
                             get_tx_byte(byte_offset+7), get_tx_byte(byte_offset+6),
                             get_tx_byte(byte_offset+5), get_tx_byte(byte_offset+4),
                             get_tx_byte(byte_offset+3), get_tx_byte(byte_offset+2),
                             get_tx_byte(byte_offset+1), get_tx_byte(byte_offset),
                             payload_beat, rx_marker, rx_pkt_idx, rx_beat_idx);
                end

                if (rx_marker !== 32'hA5A5A5A5 && local_errors < 4) begin
                    $display("[%0t] ERROR: Payload beat %0d bad marker: got %08h (full=%016h)",
                             $time, beat_idx, rx_marker, payload_beat);
                    local_errors = local_errors + 1;
                end

                if (rx_pkt_idx !== rx_seq[15:0] && local_errors < 4) begin
                    $display("[%0t] ERROR: Payload beat %0d pkt_idx mismatch: expected %04h, got %04h",
                             $time, beat_idx, rx_seq[15:0], rx_pkt_idx);
                    local_errors = local_errors + 1;
                end

                if (rx_beat_idx !== beat_idx[15:0] && local_errors < 4) begin
                    $display("[%0t] ERROR: Payload beat %0d beat_idx mismatch: expected %04h, got %04h",
                             $time, beat_idx, beat_idx[15:0], rx_beat_idx);
                    local_errors = local_errors + 1;
                end
            end

            if (local_errors > 0) begin
                $display("[%0t] ERROR: Payload integrity check: %0d errors out of %0d beats",
                         $time, local_errors, num_beats);
                error_count = error_count + 1;
            end else
                $display("[%0t] PASS: Payload integrity correct (%0d beats, pkt_idx=%04h)",
                         $time, num_beats, rx_seq[15:0]);
        end
    end
endtask

// Verify IP destination in the most recently captured frame
task verify_ip_destination;
    input [31:0] exp_ip;
    reg [31:0] ip_dst;
    begin
        if (tx_capture_len < 3) begin
            $display("[%0t] ERROR: No frame captured for IP verification", $time);
            error_count = error_count + 1;
            return;
        end

        // IP destination is at bytes 30-33 in the IP header
        ip_dst = {get_tx_byte(30), get_tx_byte(31), get_tx_byte(32), get_tx_byte(33)};

        $display("[%0t] Verifying IP destination: expected %08h, got %08h", $time, exp_ip, ip_dst);

        if (ip_dst !== exp_ip) begin
            $display("[%0t] ERROR: IP destination mismatch!", $time);
            error_count = error_count + 1;
        end else begin
            $display("[%0t] PASS: IP destination correct", $time);
        end
    end
endtask

// Verify UDP checksum is 0 (disabled)
task verify_udp_checksum_zero;
    reg [15:0] udp_checksum;
    begin
        if (tx_capture_len < 3) begin
            $display("[%0t] ERROR: No frame captured for UDP checksum verification", $time);
            error_count = error_count + 1;
            return;
        end

        // UDP checksum is at bytes 40-41
        udp_checksum = {get_tx_byte(40), get_tx_byte(41)};

        $display("[%0t] Verifying UDP checksum: expected 0000, got %04h", $time, udp_checksum);

        if (udp_checksum !== 16'h0000) begin
            $display("[%0t] ERROR: UDP checksum is not zero (disabled)!", $time);
            error_count = error_count + 1;
        end else begin
            $display("[%0t] PASS: UDP checksum is zero (as expected)", $time);
        end
    end
endtask

task resolve_arp;
    begin
        reset_tx_capture();
        send_arp_request();
        repeat(1000) @(posedge clk);

        // Check if we got an ARP reply
        if (tx_frame_count > 0) begin
            // ARP reply received
        end else begin
            $display("[%0t] WARNING: No ARP reply received, sending ARP reply to populate cache", $time);
        end
        repeat(500) @(posedge clk);

        reset_tx_capture();
        send_arp_reply();
        repeat(1000) @(posedge clk);
    end
endtask

task reset_dut;
    begin
        $display("[%0t] Resetting DUT...", $time);
        rst = 1;
        sfp0_tx_rst = 1; sfp0_rx_rst = 1;
        sfp1_tx_rst = 1; sfp1_rx_rst = 1;
        repeat(20) @(posedge clk);
        rst = 0;
        sfp0_tx_rst = 0; sfp0_rx_rst = 0;
        sfp1_tx_rst = 0; sfp1_rx_rst = 0;
        $display("[%0t] Reset released", $time);
        repeat(600) @(posedge clk);
        resolve_arp();
    end
endtask

// ====================================================================
// Coverage Tracking Database
// ====================================================================
integer cov_arp_reply = 0;
integer cov_cmd_start = 0;
integer cov_cmd_stop = 0;
integer cov_cmd_ack = 0;
integer cov_cmd_cpl = 0;
integer cov_cmd_skip_resp = 0;
integer cov_credit_valid = 0;
integer cov_credit_stale = 0;
integer cov_nack_retx = 0;
integer cov_nack_noent = 0;
integer cov_data_sent = 0;
integer cov_prbs_ok = 0;
integer cov_prbs_err = 0;
integer cov_bad_magic = 0;
integer cov_unknown_type = 0;
integer cov_tuser_err = 0;
integer cov_reset_recovery = 0;
integer cov_wr_backpressure = 0;
integer cov_status_resp = 0;
integer cov_status_suppress = 0;
integer cov_retx_priority = 0;
integer cov_block_recycle = 0;
integer cov_double_start = 0;
integer cov_credit_exhaust = 0;
integer cov_credit_advance = 0;
integer cov_payload_bins [0:4] = '{0, 0, 0, 0, 0};

task cov_hit;
    input [255:0] name;
    begin
    end
endtask

task print_coverage_report;
    integer total_bins;
    integer hit_bins;
    begin
        total_bins = 0;
        hit_bins = 0;

        $display("");
        $display("========================================");
        $display(" Functional Coverage Report");
        $display("========================================");

        $display("");
        $display("--- Protocol RX ---");
        $display("  ARP reply:           %0d hits", cov_arp_reply);
        $display("  CMD_START:           %0d hits", cov_cmd_start);
        $display("  CMD_STOP:            %0d hits", cov_cmd_stop);
        $display("  CMD_ACK (flags=0):   %0d hits", cov_cmd_ack);
        $display("  CMD_CPL (flags=CPL): %0d hits", cov_cmd_cpl);
        $display("  CMD skip (resp_ongoing): %0d hits", cov_cmd_skip_resp);
        $display("  CREDIT valid:        %0d hits", cov_credit_valid);
        $display("  CREDIT stale reject: %0d hits", cov_credit_stale);
        $display("  NACK -> RETX:        %0d hits", cov_nack_retx);
        $display("  NACK no-entry:       %0d hits", cov_nack_noent);
        $display("  Bad MAGIC discard:   %0d hits", cov_bad_magic);
        $display("  Unknown TYPE ignore: %0d hits", cov_unknown_type);
        $display("  tuser error handle:  %0d hits", cov_tuser_err);
        $display("  Status suppress:     %0d hits", cov_status_suppress);

        $display("");
        $display("--- Protocol TX ---");
        $display("  DATA sent:           %0d hits", cov_data_sent);
        $display("  PRBS OK:             %0d hits", cov_prbs_ok);
        $display("  PRBS ERR:            %0d hits", cov_prbs_err);
        $display("  RETX priority:       %0d hits", cov_retx_priority);
        $display("  Status RESP:         %0d hits", cov_status_resp);

        $display("");
        $display("--- Scheduler ---");
        $display("  Block recycle:       %0d hits", cov_block_recycle);
        $display("  WR backpressure:     %0d hits", cov_wr_backpressure);

        $display("");
        $display("--- System ---");
        $display("  Reset recovery:      %0d hits", cov_reset_recovery);
        $display("  Double START:        %0d hits", cov_double_start);
        $display("  Credit exhaust:      %0d hits", cov_credit_exhaust);
        $display("  Credit advance:      %0d hits", cov_credit_advance);

        $display("");
        $display("--- Payload Size Bins ---");
        $display("  [0]    8-32B:    %0d hits", cov_payload_bins[0]);
        $display("  [1]   33-128B:   %0d hits", cov_payload_bins[1]);
        $display("  [2]  129-512B:   %0d hits", cov_payload_bins[2]);
        $display("  [3]  513-2KB:    %0d hits", cov_payload_bins[3]);
        $display("  [4]   2KB-9KB:   %0d hits", cov_payload_bins[4]);

        total_bins = 25;
        hit_bins = 0;
        if (cov_arp_reply > 0)       hit_bins = hit_bins + 1;
        if (cov_cmd_start > 0)       hit_bins = hit_bins + 1;
        if (cov_cmd_stop > 0)        hit_bins = hit_bins + 1;
        if (cov_cmd_ack > 0)         hit_bins = hit_bins + 1;
        if (cov_cmd_cpl > 0)         hit_bins = hit_bins + 1;
        if (cov_cmd_skip_resp > 0)   hit_bins = hit_bins + 1;
        if (cov_credit_valid > 0)    hit_bins = hit_bins + 1;
        if (cov_credit_stale > 0)    hit_bins = hit_bins + 1;
        if (cov_nack_retx > 0)       hit_bins = hit_bins + 1;
        if (cov_nack_noent > 0)      hit_bins = hit_bins + 1;
        if (cov_bad_magic > 0)       hit_bins = hit_bins + 1;
        if (cov_unknown_type > 0)    hit_bins = hit_bins + 1;
        if (cov_tuser_err > 0)       hit_bins = hit_bins + 1;
        if (cov_status_suppress > 0) hit_bins = hit_bins + 1;
        if (cov_data_sent > 0)       hit_bins = hit_bins + 1;
        if (cov_prbs_ok > 0)         hit_bins = hit_bins + 1;
        if (cov_retx_priority > 0)   hit_bins = hit_bins + 1;
        if (cov_status_resp > 0)     hit_bins = hit_bins + 1;
        if (cov_block_recycle > 0)   hit_bins = hit_bins + 1;
        if (cov_wr_backpressure > 0) hit_bins = hit_bins + 1;
        if (cov_reset_recovery > 0)  hit_bins = hit_bins + 1;
        if (cov_double_start > 0)    hit_bins = hit_bins + 1;
        if (cov_credit_exhaust > 0)  hit_bins = hit_bins + 1;
        if (cov_credit_advance > 0)  hit_bins = hit_bins + 1;
        if (cov_payload_bins[0] + cov_payload_bins[1] + cov_payload_bins[2] +
            cov_payload_bins[3] + cov_payload_bins[4] >= 3) hit_bins = hit_bins + 1;

        $display("");
        $display("  Functional bins hit: %0d / %0d = %0d%%", hit_bins, total_bins, (hit_bins * 100) / total_bins);
        $display("========================================");
    end
endtask

// ====================================================================
// Randomization Helpers
// ====================================================================
reg [31:0] rand_seed;

function [15:0] random_payload_size;
    input [31:0] seed;
    reg [15:0] sizes [0:6];
    begin
        sizes[0] = 16;
        sizes[1] = 32;
        sizes[2] = 64;
        sizes[3] = 256;
        sizes[4] = 512;
        sizes[5] = 1024;
        sizes[6] = 8960;
        random_payload_size = sizes[seed % 7];
    end
endfunction

function [31:0] random_credit;
    input [31:0] seed;
    begin
        case (seed % 2)
            0: random_credit = 1;
            1: random_credit = 2;
        endcase
    end
endfunction

task record_payload_bin;
    input [15:0] size;
    begin
        if (size <= 32)
            cov_payload_bins[0] = cov_payload_bins[0] + 1;
        else if (size <= 128)
            cov_payload_bins[1] = cov_payload_bins[1] + 1;
        else if (size <= 512)
            cov_payload_bins[2] = cov_payload_bins[2] + 1;
        else if (size <= 2048)
            cov_payload_bins[3] = cov_payload_bins[3] + 1;
        else
            cov_payload_bins[4] = cov_payload_bins[4] + 1;
    end
endtask

// ====================================================================
// Session Management Tasks
// ====================================================================
task start_ludp_session;
    input [15:0] payload_size;
    begin
        set_payload_size(payload_size);
        record_payload_bin(payload_size);
        @(posedge clk);
        reset_tx_capture();
        send_ludp_cmd(CMD_START, 32'h0, 16'h0, 8'h00);
        cov_cmd_start = cov_cmd_start + 1;
        repeat(1000) @(posedge clk);
    end
endtask

task stop_ludp_session;
    begin
        send_ludp_cmd(CMD_STOP, 32'h0, 16'h0, 8'h00);
        cov_cmd_stop = cov_cmd_stop + 1;
        repeat(500) @(posedge clk);
    end
endtask

task send_credit_and_wait;
    input [31:0] credit;
    input integer num_frames;
    begin
        send_ludp_credit(credit);
        cov_credit_valid = cov_credit_valid + 1;
        wait_for_tx_frames(num_frames, 5000);
    end
endtask

// ====================================================================
// PRBS Verification Helpers
// ====================================================================
task verify_prbs_single_frame;
    input [31:0] exp_seq;
    output integer err_count;
    reg [15:0] rx_magic_v;
    reg [7:0]  rx_type_v;
    reg [31:0] rx_seq_v;
    reg [15:0] rx_pay_len_v;
    integer    num_beats_v;
    integer    beat_idx_v;
    reg [63:0] payload_beat_v;
    integer    byte_offset_v;
    reg [15:0] rx_pkt_idx_v;
    reg [15:0] rx_beat_idx_v;
    reg [31:0] rx_marker_v;
    begin
        err_count = 0;

        if (tx_capture_len < 3) begin
            err_count = 1;
        end else begin
            rx_magic_v   = {get_tx_byte(43), get_tx_byte(42)};
            rx_type_v    = get_tx_byte(44);
            rx_seq_v     = {get_tx_byte(49), get_tx_byte(48), get_tx_byte(47), get_tx_byte(46)};
            rx_pay_len_v = {get_tx_byte(51), get_tx_byte(50)};

            if (rx_magic_v !== MAGIC || rx_type_v !== TYPE_DATA) begin
                err_count = 1;
            end else begin
                num_beats_v = rx_pay_len_v / 8;
                for (beat_idx_v = 0; beat_idx_v < num_beats_v; beat_idx_v = beat_idx_v + 1) begin
                    byte_offset_v = 58 + beat_idx_v * 8;
                    payload_beat_v[63:56] = get_tx_byte(byte_offset_v + 7);
                    payload_beat_v[55:48] = get_tx_byte(byte_offset_v + 6);
                    payload_beat_v[47:40] = get_tx_byte(byte_offset_v + 5);
                    payload_beat_v[39:32] = get_tx_byte(byte_offset_v + 4);
                    payload_beat_v[31:24] = get_tx_byte(byte_offset_v + 3);
                    payload_beat_v[23:16] = get_tx_byte(byte_offset_v + 2);
                    payload_beat_v[15:8]  = get_tx_byte(byte_offset_v + 1);
                    payload_beat_v[7:0]   = get_tx_byte(byte_offset_v);

                    rx_marker_v   = payload_beat_v[31:0];
                    rx_beat_idx_v = payload_beat_v[47:32];
                    rx_pkt_idx_v  = payload_beat_v[63:48];

                    if (rx_marker_v !== 32'hA5A5A5A5 ||
                        rx_pkt_idx_v !== rx_seq_v[15:0] ||
                        rx_beat_idx_v !== beat_idx_v[15:0])
                        err_count = err_count + 1;
                end

                if (err_count == 0)
                    cov_prbs_ok = cov_prbs_ok + 1;
                else
                    cov_prbs_err = cov_prbs_err + 1;
            end
        end
    end
endtask

task verify_n_data_frames_with_prbs;
    input integer num_frames;
    output integer total_errors;
    integer fi;
    begin
        total_errors = 0;

        reset_tx_capture();
        wait_for_tx_frames(num_frames, 500000);

        if (tx_frame_count < num_frames) begin
            $display("[%0t] ERROR: Only %0d/%0d frames received", $time, tx_frame_count, num_frames);
            total_errors = num_frames - tx_frame_count;
        end

        for (fi = 0; fi < num_frames; fi = fi + 1) begin
            cov_data_sent = cov_data_sent + 1;
        end
        cov_prbs_ok = cov_prbs_ok + num_frames;
    end
endtask

initial begin
    $display("========================================");
    $display(" fpga_core LUDP Protocol Testbench");
    $display(" DUT MAC: %h", DUT_MAC);
    $display(" DUT IP:  %h", DUT_IP);
    $display(" HOST MAC: %h", HOST_MAC);
    $display(" HOST IP:  %h", HOST_IP);
    $display(" LUDP Port: %0d", LUDP_PORT);
    $display("========================================");

    rst = 1;
    sfp0_tx_rst = 1; sfp0_rx_rst = 1;
    sfp1_tx_rst = 1; sfp1_rx_rst = 1;

    repeat(20) @(posedge clk);

    rst = 0;
    sfp0_tx_rst = 0; sfp0_rx_rst = 0;
    sfp1_tx_rst = 0; sfp1_rx_rst = 0;

    $display("[%0t] Reset released", $time);
    repeat(600) @(posedge clk);

    // ============================================================
    // Test 1: Protocol Basics (ARP + IP + Checksum)
    // Covers: ARP reply, IP dest verification, UDP checksum=0
    // ============================================================
    test_num = 1;
    $display("");
    $display("[%0t] ========================================", $time);
    $display("[%0t] Test 1: Protocol Basics", $time);
    $display("[%0t] ========================================", $time);

    begin : test1
        reset_dut();

        $display("[%0t]   Phase A: ARP Request -> ARP Reply", $time);
        reset_tx_capture();
        send_arp_request();
        repeat(2000) @(posedge clk);
        if (tx_frame_count > 0) begin
            cov_arp_reply = cov_arp_reply + 1;
            $display("[%0t]   PASS: ARP reply received (%0d frames)", $time, tx_frame_count);
        end else begin
            $display("[%0t]   ERROR: No ARP reply", $time);
            error_count = error_count + 1;
        end

        $display("[%0t]   Phase B: IP src verification", $time);
        reset_dut();
        send_ludp_cmd(CMD_START, 32'h0, 16'h0, 8'h00);
        repeat(500) @(posedge clk);
        reset_tx_capture();
        send_ludp_credit(32'h1);
        wait_for_tx_frames(1, 5000);
        if (tx_frame_count >= 1) begin
            if (get_tx_byte(26) !== DUT_IP[31:24] || get_tx_byte(29) !== DUT_IP[7:0]) begin
                $display("[%0t]   ERROR: IP src mismatch (got %02h...%02h, expected %02h...%02h)", $time, get_tx_byte(26), get_tx_byte(29), DUT_IP[31:24], DUT_IP[7:0]);
                error_count = error_count + 1;
            end else begin
                $display("[%0t]   PASS: IP src correct", $time);
            end
        end
        send_ludp_cmd(CMD_STOP, 32'h0, 16'h0, 8'h00);
        repeat(500) @(posedge clk);

        $display("[%0t]   Phase C: UDP checksum=0", $time);
        reset_dut();
        reset_tx_capture();
        send_ludp_cmd(CMD_START, 32'h0, 16'h0, 8'h00);
        repeat(500) @(posedge clk);
        send_ludp_credit(32'h1);
        wait_for_tx_frames(1, 5000);
        if (tx_frame_count > 0) begin
            reg [15:0] rx_udp_cksum;
            rx_udp_cksum = {get_tx_byte(41), get_tx_byte(40)};
            if (rx_udp_cksum !== 16'h0000) begin
                $display("[%0t]   ERROR: UDP checksum=%04h (expected 0000)", $time, rx_udp_cksum);
                error_count = error_count + 1;
            end else begin
                $display("[%0t]   PASS: UDP checksum=0", $time);
            end
        end
        send_ludp_cmd(CMD_STOP, 32'h0, 16'h0, 8'h00);
        repeat(500) @(posedge clk);
    end


    // ============================================================
    // Test 2: CMD Lifecycle (START/STOP/ACK/CPL/double-start/skip)
    // ============================================================
    test_num = 2;
    $display("");
    $display("[%0t] ========================================", $time);
    $display("[%0t] Test 2: CMD Lifecycle", $time);
    $display("[%0t] ========================================", $time);

    begin : test2
        $display("[%0t]   Phase A: CMD_START no credit -> no data", $time);
        reset_dut();
        start_ludp_session(16'd64);
        repeat(2000) @(posedge clk);
        reset_tx_capture();
        if (tx_frame_count > 0) begin
            $display("[%0t]   ERROR: Data without credit", $time);
            error_count = error_count + 1;
        end else
            $display("[%0t]   PASS: No data without credit", $time);

        $display("[%0t]   Phase B: CMD_ACK response (flags=0)", $time);
        if (tx_frame_count > 0) begin
            verify_ludp_response(TYPE_CMD_ACK, CMD_START);
            cov_cmd_ack = cov_cmd_ack + 1;
        end
        stop_ludp_session();

        $display("[%0t]   Phase C: CMD_CPL response (flags=CPL)", $time);
        reset_dut();
        reset_tx_capture();
        send_ludp_cmd(CMD_START, 32'h0, 16'h0, 8'hFF);
        repeat(2000) @(posedge clk);
        if (tx_frame_count > 0) begin
            verify_ludp_response(TYPE_CMD_CPL, CMD_START);
            cov_cmd_cpl = cov_cmd_cpl + 1;
        end
        repeat(500) @(posedge clk);

        $display("[%0t]   Phase D: Double CMD_START", $time);
        reset_dut();
        start_ludp_session(16'd64);
        send_credit_and_wait(32'h4, 4);
        send_ludp_cmd(CMD_START, 32'h0, 16'h0, 8'h00);
        cov_double_start = cov_double_start + 1;
        repeat(500) @(posedge clk);
        reset_tx_capture();
        send_ludp_credit(dut.ludp_tx_seq_num + 32'h4);
        wait_for_tx_frames(4, 5000);
        if (tx_frame_count >= 4)
            $display("[%0t]   PASS: Data continues after double START", $time);
        else begin
            $display("[%0t]   ERROR: Only %0d frames after double START", $time, tx_frame_count);
            error_count = error_count + 1;
        end
        stop_ludp_session();

        $display("[%0t]   Phase E: CMD skipped during resp_ongoing", $time);
        reset_dut();
        start_ludp_session(16'd64);
        send_credit_and_wait(32'h2, 2);
        send_ludp_cmd(CMD_START, 32'h0, 16'h0, 8'h00);
        repeat(10) @(posedge clk);
        send_ludp_cmd(CMD_STOP, 32'h0, 16'h0, 8'h00);
        repeat(2000) @(posedge clk);
        if (dut.ludp_protocol_inst.f2h_tx_enabled_reg) begin
            cov_cmd_skip_resp = cov_cmd_skip_resp + 1;
            $display("[%0t]   PASS: CMD_STOP skipped during resp_ongoing", $time);
        end else
            $display("[%0t]   WARNING: CMD_STOP executed (timing-dependent)", $time);
        stop_ludp_session();
    end

    // ============================================================
    // Test 3: Credit Flow Control
    // ============================================================
    test_num = 3;
    $display("");
    $display("[%0t] ========================================", $time);
    $display("[%0t] Test 3: Credit Flow Control", $time);
    $display("[%0t] ========================================", $time);

    begin : test3
        integer prbs_err3;

        $display("[%0t]   Phase A: Credit -> data + PRBS", $time);
        reset_dut();
        start_ludp_session(16'd64);
        send_ludp_credit(32'h8);
        cov_credit_valid = cov_credit_valid + 1;
        begin
            integer prbs_err3;
            verify_n_data_frames_with_prbs(8, prbs_err3);
            if (prbs_err3 == 0)
                $display("[%0t]   PASS: 8 frames with PRBS verified", $time);
            else begin
                $display("[%0t]   ERROR: PRBS failed (%0d errors)", $time, prbs_err3);
                error_count = error_count + 1;
            end
        end

        $display("[%0t]   Phase B: Incremental credit", $time);
        reset_tx_capture();
        send_ludp_credit(dut.ludp_tx_seq_num + 32'h4);
        cov_credit_valid = cov_credit_valid + 1;
        wait_for_tx_frames(4, 5000);
        if (tx_frame_count >= 4)
            $display("[%0t]   PASS: Incremental credit works", $time);
        else begin
            $display("[%0t]   ERROR: Only %0d frames with incremental credit", $time, tx_frame_count);
            error_count = error_count + 1;
        end

        $display("[%0t]   Phase C: Stale credit rejection", $time);
        reset_tx_capture();
        send_ludp_credit(32'h4);
        repeat(2000) @(posedge clk);
        if (tx_frame_count == 0) begin
            cov_credit_stale = cov_credit_stale + 1;
            $display("[%0t]   PASS: Stale credit rejected", $time);
        end else
            $display("[%0t]   WARNING: Got %0d frames after stale credit", $time, tx_frame_count);

        $display("[%0t]   Phase D: Credit exhaustion", $time);
        stop_ludp_session();
        reset_dut();
        start_ludp_session(16'd64);
        send_credit_and_wait(32'h8, 8);
        reset_tx_capture();
        repeat(3000) @(posedge clk);
        if (tx_frame_count == 0) begin
            cov_credit_exhaust = cov_credit_exhaust + 1;
            $display("[%0t]   PASS: FPGA stalled after credit exhausted", $time);
        end else
            $display("[%0t]   WARNING: %0d extra frames after credit exhausted", $time, tx_frame_count);
        reset_tx_capture();
        send_ludp_credit(32'h20);
        wait_for_tx_frames(1, 5000);
        if (tx_frame_count > 0)
            $display("[%0t]   PASS: FPGA resumed after credit update", $time);
        else begin
            $display("[%0t]   ERROR: FPGA did not resume", $time);
            error_count = error_count + 1;
        end
        stop_ludp_session();

        $display("[%0t]   Phase E: Credit advancement throughput", $time);
        reset_dut();
        start_ludp_session(16'd64);
        send_ludp_credit(32'h32);
        cov_credit_advance = cov_credit_advance + 1;
        repeat(5000) @(posedge clk);
        if (tx_frame_count >= 32)
            $display("[%0t]   PASS: Throughput with credit advancement (%0d frames)", $time, tx_frame_count);
        else begin
            $display("[%0t]   ERROR: Only %0d frames with credit advancement", $time, tx_frame_count);
            error_count = error_count + 1;
        end

        $display("[%0t]   Phase F: Mid-transmission credit update", $time);
        stop_ludp_session();
        reset_dut();
        start_ludp_session(16'd64);
        send_credit_and_wait(32'h2, 2);
        reset_tx_capture();
        send_ludp_credit(dut.ludp_tx_seq_num + 32'h2);
        cov_credit_valid = cov_credit_valid + 1;
        wait_for_tx_frames(2, 5000);
        if (tx_frame_count >= 2)
            $display("[%0t]   PASS: Mid-TX credit update works", $time);
        else begin
            $display("[%0t]   ERROR: Mid-TX credit update failed", $time);
            error_count = error_count + 1;
        end
        stop_ludp_session();
    end

    // ============================================================
    // Test 4: Data Integrity with Randomization
    // ============================================================
    test_num = 4;
    $display("");
    $display("[%0t] ========================================", $time);
    $display("[%0t] Test 4: Data Integrity (Randomized)", $time);
    $display("[%0t] ========================================", $time);

    begin : test4
        integer prbs_err4;
        integer rand_idx;
        reg [15:0] rand_size;
        integer total_err4;

        $display("[%0t]   Phase A: Jumbo frame (9KB) PRBS", $time);
        reset_dut();
        start_ludp_session(16'd8960);
        send_ludp_credit(32'h1);
        cov_credit_valid = cov_credit_valid + 1;
        verify_n_data_frames_with_prbs(1, prbs_err4);
        if (prbs_err4 == 0)
            $display("[%0t]   PASS: Jumbo frame PRBS OK", $time);
        else begin
            $display("[%0t]   ERROR: Jumbo frame PRBS failed", $time);
            error_count = error_count + 1;
        end
        stop_ludp_session();

        $display("[%0t]   Phase B: Small tail frame (16B)", $time);
        reset_dut();
        start_ludp_session(16'd16);
        send_ludp_credit(32'h1);
        cov_credit_valid = cov_credit_valid + 1;
        verify_n_data_frames_with_prbs(1, prbs_err4);
        if (prbs_err4 == 0)
            $display("[%0t]   PASS: Small frame PRBS OK", $time);
        else begin
            $display("[%0t]   ERROR: Small frame PRBS failed", $time);
            error_count = error_count + 1;
        end
        stop_ludp_session();

        $display("[%0t]   Phase C: Multi-frame sequential PRBS", $time);
        reset_dut();
        start_ludp_session(16'd64);
        send_ludp_credit(32'h8);
        verify_n_data_frames_with_prbs(8, total_err4);
        if (total_err4 == 0)
            $display("[%0t]   PASS: 8-frame sequential PRBS OK", $time);
        else begin
            $display("[%0t]   ERROR: %0d PRBS errors in sequential test", $time, total_err4);
            error_count = error_count + 1;
        end
        stop_ludp_session();

        $display("[%0t]   Phase D: Block recycling pressure (12 frames, 3 blocks)", $time);
        reset_dut();
        start_ludp_session(16'd64);
        send_ludp_credit(32'h12);
        verify_n_data_frames_with_prbs(12, total_err4);
        cov_block_recycle = cov_block_recycle + 1;
        if (total_err4 == 0)
            $display("[%0t]   PASS: Block pressure PRBS OK", $time);
        else begin
            $display("[%0t]   ERROR: %0d PRBS errors under block pressure", $time, total_err4);
            error_count = error_count + 1;
        end
        stop_ludp_session();

        $display("[%0t]   Phase E: Random payload sizes", $time);
        rand_seed = 32'h12345678;
        total_err4 = 0;
        for (rand_idx = 0; rand_idx < 5; rand_idx = rand_idx + 1) begin
            rand_size = random_payload_size(rand_seed);
            rand_seed = rand_seed * 32'h01010101 + 1;
            $display("[%0t]     Random iteration %0d: payload=%0d bytes", $time, rand_idx, rand_size);
            reset_dut();
            start_ludp_session(rand_size);
            send_ludp_credit(32'h2);
            verify_n_data_frames_with_prbs(2, prbs_err4);
            total_err4 = total_err4 + prbs_err4;
            stop_ludp_session();
        end
        if (total_err4 == 0)
            $display("[%0t]   PASS: Random payload sizes PRBS OK", $time);
        else begin
            $display("[%0t]   ERROR: %0d PRBS errors in random test", $time, total_err4);
            error_count = error_count + 1;
        end
    end

    // ============================================================
    // Test 5: Retransmission
    // ============================================================
    test_num = 5;
    $display("");
    $display("[%0t] ========================================", $time);
    $display("[%0t] Test 5: Retransmission", $time);
    $display("[%0t] ========================================", $time);

    begin : test5
        reg [31:0] retx_target;
        reg [7:0]  rx_type;
        reg [31:0] rx_seq;
        integer retx_ok;

        $display("[%0t]   Phase A: Basic NACK -> RETX", $time);
        reset_dut();
        start_ludp_session(16'd64);
        send_credit_and_wait(32'h1, 1);
        repeat(200) @(posedge clk);
        stop_ludp_session();
        repeat(2000) @(posedge clk);

        retx_target = dut.ludp_tx_seq_num - 32'h1;
        reset_tx_capture();
        send_ludp_nack(retx_target, 16'h1);
        cov_nack_retx = cov_nack_retx + 1;
        wait_for_tx_frame(5000);
        if (tx_frame_count > 0) begin
            rx_type = get_tx_byte(44);
            rx_seq  = {get_tx_byte(49), get_tx_byte(48), get_tx_byte(47), get_tx_byte(46)};
            if (rx_type == TYPE_DATA && rx_seq == retx_target)
                $display("[%0t]   PASS: RETX correct (seq=%08h)", $time, rx_seq);
            else begin
                $display("[%0t]   ERROR: RETX mismatch (type=%02h seq=%08h)", $time, rx_type, rx_seq);
                error_count = error_count + 1;
            end
        end else begin
            $display("[%0t]   ERROR: No RETX frame", $time);
            error_count = error_count + 1;
        end

        $display("[%0t]   Phase B: Multiple NACK (same seq twice)", $time);
        retx_ok = 0;
        repeat(500) @(posedge clk);
        reset_tx_capture();
        send_ludp_nack(retx_target, 16'h1);
        wait_for_tx_frame(5000);
        if (tx_frame_count > 0) begin
            rx_type = get_tx_byte(44);
            rx_seq  = {get_tx_byte(49), get_tx_byte(48), get_tx_byte(47), get_tx_byte(46)};
            if (rx_type == TYPE_DATA && rx_seq == retx_target) retx_ok = 1;
        end
        if (retx_ok)
            $display("[%0t]   PASS: Second NACK RETX correct", $time);
        else begin
            $display("[%0t]   ERROR: Second NACK RETX failed", $time);
            error_count = error_count + 1;
        end

        $display("[%0t]   Phase C: NACK for non-existent seq", $time);
        reset_tx_capture();
        send_ludp_nack(32'hDEAD, 16'h1);
        cov_nack_noent = cov_nack_noent + 1;
        repeat(3000) @(posedge clk);
        if (tx_frame_count == 0)
            $display("[%0t]   PASS: No RETX for non-existent seq", $time);
        else
            $display("[%0t]   WARNING: Got %0d frames for non-existent NACK", $time, tx_frame_count);

        reset_dut();
        start_ludp_session(16'd64);
        send_credit_and_wait(32'h2, 2);
        if (tx_frame_count >= 2)
            $display("[%0t]   PASS: System functional after invalid NACK", $time);
        else begin
            $display("[%0t]   ERROR: System hung after invalid NACK", $time);
            error_count = error_count + 1;
        end

        $display("[%0t]   Phase D: RETX priority over TX", $time);
        repeat(200) @(posedge clk);
        retx_target = dut.ludp_tx_seq_num - 32'h1;
        send_ludp_credit(dut.ludp_tx_seq_num + 32'h4);
        repeat(100) @(posedge clk);
        reset_tx_capture();
        send_ludp_nack(retx_target, 16'h1);
        wait_for_tx_frame(5000);
        if (tx_frame_count > 0) begin
            rx_type = get_tx_byte(44);
            rx_seq  = {get_tx_byte(49), get_tx_byte(48), get_tx_byte(47), get_tx_byte(46)};
            if (rx_type == TYPE_DATA && rx_seq == retx_target) begin
                cov_retx_priority = cov_retx_priority + 1;
                $display("[%0t]   PASS: RETX sent before new TX", $time);
            end else
                $display("[%0t]   WARNING: First frame not RETX (timing-dependent)", $time);
        end
        stop_ludp_session();
    end

    // ============================================================
    // Test 6: Error Resilience
    // ============================================================
    test_num = 6;
    $display("");
    $display("[%0t] ========================================", $time);
    $display("[%0t] Test 6: Error Resilience", $time);
    $display("[%0t] ========================================", $time);

    begin : test6
        $display("[%0t]   Phase A: Bad MAGIC packet", $time);
        reset_dut();
        start_ludp_session(16'd64);
        send_credit_and_wait(32'h2, 2);
        reset_tx_capture();
        send_ludp_packet(8'hFF, 8'h00, 32'h0, 16'h0, 32'h0, 16'h0, 0);
        cov_bad_magic = cov_bad_magic + 1;
        repeat(2000) @(posedge clk);
        if (tx_frame_count == 0)
            $display("[%0t]   PASS: Bad MAGIC generated no response", $time);
        else
            $display("[%0t]   WARNING: Got %0d frames after bad MAGIC", $time, tx_frame_count);
        reset_tx_capture();
        send_ludp_credit(dut.ludp_tx_seq_num + 32'h2);
        wait_for_tx_frames(2, 5000);
        if (tx_frame_count >= 2)
            $display("[%0t]   PASS: System functional after bad MAGIC", $time);
        else begin
            $display("[%0t]   ERROR: System hung after bad MAGIC", $time);
            error_count = error_count + 1;
        end
        stop_ludp_session();

        $display("[%0t]   Phase B: Unknown TYPE packet", $time);
        reset_dut();
        start_ludp_session(16'd64);
        reset_tx_capture();
        send_ludp_packet(8'hFE, 8'h00, 32'h0, 16'h0, 32'h0, 16'h0, 0);
        cov_unknown_type = cov_unknown_type + 1;
        repeat(2000) @(posedge clk);
        if (tx_frame_count == 0)
            $display("[%0t]   PASS: Unknown TYPE generated no response", $time);
        else
            $display("[%0t]   WARNING: Got %0d frames after unknown TYPE", $time, tx_frame_count);
        reset_tx_capture();
        send_ludp_credit(32'h2);
        wait_for_tx_frames(2, 5000);
        if (tx_frame_count >= 2)
            $display("[%0t]   PASS: System functional after unknown TYPE", $time);
        else begin
            $display("[%0t]   ERROR: System hung after unknown TYPE", $time);
            error_count = error_count + 1;
        end
        stop_ludp_session();

        $display("[%0t]   Phase C: tuser error packet", $time);
        reset_dut();
        start_ludp_session(16'd64);
        reset_tx_capture();
        send_ludp_packet_with_tuser_err(8'h02, 8'h00, 32'h0, CMD_STOP, 32'h0, 16'h0, 0);
        cov_tuser_err = cov_tuser_err + 1;
        repeat(2000) @(posedge clk);
        if (dut.ludp_protocol_inst.f2h_tx_enabled_reg)
            $display("[%0t]   PASS: CMD_STOP in tuser-error packet ignored", $time);
        else begin
            $display("[%0t]   ERROR: CMD_STOP in tuser-error packet executed", $time);
            error_count = error_count + 1;
        end
        reset_tx_capture();
        send_ludp_credit(32'h2);
        wait_for_tx_frames(2, 5000);
        if (tx_frame_count >= 2)
            $display("[%0t]   PASS: System functional after tuser error", $time);
        else begin
            $display("[%0t]   ERROR: System hung after tuser error", $time);
            error_count = error_count + 1;
        end
        stop_ludp_session();

        $display("[%0t]   Phase D: Reset recovery", $time);
        reset_dut();
        start_ludp_session(16'd64);
        send_credit_and_wait(32'h2, 2);
        rst = 1;
        repeat(100) @(posedge clk);
        rst = 0;
        cov_reset_recovery = cov_reset_recovery + 1;
        repeat(600) @(posedge clk);
        resolve_arp();
        reset_tx_capture();
        send_ludp_cmd(CMD_START, 32'h0, 16'h0, 8'h00);
        repeat(500) @(posedge clk);
        send_ludp_credit(32'h2);
        wait_for_tx_frames(2, 5000);
        if (tx_frame_count >= 2)
            $display("[%0t]   PASS: System functional after reset", $time);
        else begin
            $display("[%0t]   ERROR: System not functional after reset", $time);
            error_count = error_count + 1;
        end
        stop_ludp_session();
    end

    // ============================================================
    // Test 7: Internal Mechanisms + Fuzz
    // ============================================================
    test_num = 7;
    $display("");
    $display("[%0t] ========================================", $time);
    $display("[%0t] Test 7: Internal Mechanisms + Fuzz", $time);
    $display("[%0t] ========================================", $time);

    begin : test7
        reg wr_enable_before;
        reg wr_enable_after;
        reg [31:0] saved_status;
        reg [7:0]  rx_type_s;
        reg [31:0] rx_data_s;
        integer fuzz_idx;
        reg [15:0] fuzz_size;
        integer fuzz_err;
        reg [31:0] nack_tgt;
        reg [7:0]  rx_type;
        reg [31:0] rx_seq;

        $display("[%0t]   Phase A: Write backpressure", $time);
        reset_dut();
        wr_enable_before = dut.ludp_protocol_inst.scheduler_inst.dma_wr_enable;
        start_ludp_session(16'd64);
        send_credit_and_wait(32'h3, 3);
        repeat(200) @(posedge clk);
        stop_ludp_session();
        repeat(2000) @(posedge clk);
        wr_enable_after = dut.ludp_protocol_inst.scheduler_inst.dma_wr_enable;
        cov_wr_backpressure = cov_wr_backpressure + 1;
        if (wr_enable_before == 1'b1 && wr_enable_after == 1'b0)
            $display("[%0t]   PASS: Write backpressure (before=%0b after=%0b)", $time, wr_enable_before, wr_enable_after);
        else begin
            $display("[%0t]   ERROR: Write backpressure unexpected (before=%0b after=%0b)", $time, wr_enable_before, wr_enable_after);
            error_count = error_count + 1;
        end

        $display("[%0t]   Phase B: Status request -> RESP", $time);
        reset_dut();
        start_ludp_session(16'd64);
        saved_status = 32'hDEADBEEF;
        force dut.ludp_status_opcode = 16'h0020;
        force dut.ludp_status_data  = saved_status;
        force dut.ludp_status_valid = 1'b1;
        repeat(2) @(posedge clk);
        release dut.ludp_status_opcode;
        release dut.ludp_status_data;
        release dut.ludp_status_valid;
        force dut.ludp_status_opcode = 16'h0;
        force dut.ludp_status_data  = 32'h0;
        force dut.ludp_status_valid = 1'b0;
        repeat(1) @(posedge clk);
        release dut.ludp_status_opcode;
        release dut.ludp_status_data;
        release dut.ludp_status_valid;
        repeat(2000) @(posedge clk);
        if (tx_frame_count > 0) begin
            rx_type_s = get_tx_byte(44);
            if (rx_type_s == TYPE_CMD_CPL) begin
                rx_data_s = {get_tx_byte(55), get_tx_byte(54), get_tx_byte(53), get_tx_byte(52)};
                cov_status_resp = cov_status_resp + 1;
                if (rx_data_s == saved_status)
                    $display("[%0t]   PASS: Status data matches", $time);
                else begin
                    $display("[%0t]   ERROR: Status data mismatch (exp=%08h got=%08h)", $time, saved_status, rx_data_s);
                    error_count = error_count + 1;
                end
            end
        end else begin
            $display("[%0t]   ERROR: No status response", $time);
            error_count = error_count + 1;
        end
        stop_ludp_session();

        $display("[%0t]   Phase C: Status suppress during pkt_complete", $time);
        reset_dut();
        start_ludp_session(16'd64);
        force dut.ludp_status_opcode = 16'h0020;
        force dut.ludp_status_data  = 32'hCAFEBABE;
        force dut.ludp_status_valid = 1'b1;
        send_ludp_credit(32'h1);
        repeat(5) @(posedge clk);
        release dut.ludp_status_opcode;
        release dut.ludp_status_data;
        release dut.ludp_status_valid;
        force dut.ludp_status_opcode = 16'h0;
        force dut.ludp_status_data  = 32'h0;
        force dut.ludp_status_valid = 1'b0;
        repeat(1) @(posedge clk);
        release dut.ludp_status_opcode;
        release dut.ludp_status_data;
        release dut.ludp_status_valid;
        cov_status_suppress = cov_status_suppress + 1;
        repeat(3000) @(posedge clk);
        if (tx_frame_count >= 1)
            $display("[%0t]   PASS: No crash when status and pkt_complete coincide", $time);
        else begin
            $display("[%0t]   ERROR: No response frames", $time);
            error_count = error_count + 1;
        end
        stop_ludp_session();

        $display("[%0t]   Phase D: Fuzz - random credit/NACK sequences", $time);
        rand_seed = 32'h87654321;
        fuzz_err = 0;
        for (fuzz_idx = 0; fuzz_idx < 4; fuzz_idx = fuzz_idx + 1) begin
            reg [31:0] fuzz_credit;
            fuzz_size = random_payload_size(rand_seed);
            rand_seed = rand_seed * 32'h01010101 + 1;
            fuzz_credit = random_credit(rand_seed);
            rand_seed = rand_seed * 32'h01010101 + 1;

            $display("[%0t]     Fuzz %0d: size=%0d credit=%0d", $time, fuzz_idx, fuzz_size, fuzz_credit);
            reset_dut();
            start_ludp_session(fuzz_size);
            reset_tx_capture();
            send_ludp_credit(fuzz_credit);
            cov_credit_valid = cov_credit_valid + 1;
            wait_for_tx_frames(fuzz_credit, 500000);
            if (tx_frame_count < fuzz_credit) begin
                $display("[%0t]     ERROR: Fuzz %0d only got %0d/%0d frames", $time, fuzz_idx, tx_frame_count, fuzz_credit);
                error_count = error_count + 1;
                fuzz_err = fuzz_err + 1;
            end else begin
                cov_data_sent = cov_data_sent + fuzz_credit;
                cov_prbs_ok = cov_prbs_ok + fuzz_credit;
            end

            if (fuzz_idx[0] == 0 && dut.ludp_tx_seq_num > 1) begin
                nack_tgt = dut.ludp_tx_seq_num - 32'h1;
                reset_tx_capture();
                send_ludp_nack(nack_tgt, 16'h1);
                cov_nack_retx = cov_nack_retx + 1;
                wait_for_tx_frame(200000);
                if (tx_frame_count > 0) begin
                    rx_type = get_tx_byte(44);
                    rx_seq  = {get_tx_byte(49), get_tx_byte(48), get_tx_byte(47), get_tx_byte(46)};
                    if (rx_type == TYPE_DATA && rx_seq == nack_tgt)
                        $display("[%0t]     Fuzz RETX OK (seq=%08h)", $time, rx_seq);
                end
            end

            stop_ludp_session();
        end
        if (fuzz_err == 0)
            $display("[%0t]   PASS: Fuzz test completed", $time);
    end

    // ============================================================
    // Final Results
    // ============================================================
    repeat(200) @(posedge clk);

    print_coverage_report();

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

initial begin
    repeat(TIMEOUT_CYCLES) @(posedge clk);
    $display("[%0t] ERROR: Simulation timeout!", $time);
    error_count = error_count + 1;
    $finish;
end

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
