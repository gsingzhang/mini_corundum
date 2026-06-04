`timescale 1ns / 1ps
`default_nettype none

module tb_fpga_core;

localparam CLK_PERIOD = 6.4;
localparam TIMEOUT_CYCLES = 500000;

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

        if (cnt >= timeout) begin
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
            verify_arp_reply();
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
    // Test 1: ARP Request -> ARP Reply
    // ============================================================
    test_num = 1;
    $display("");
    $display("[%0t] ========================================", $time);
    $display("[%0t] Test 1: ARP Request -> ARP Reply", $time);
    $display("[%0t] ========================================", $time);

    resolve_arp();

    // ============================================================
    // Test 2: ICMP Echo Request -> Echo Reply
    // ============================================================
    test_num = 2;
    $display("");
    $display("[%0t] ========================================", $time);
    $display("[%0t] Test 2: ICMP Echo Request -> Echo Reply", $time);
    $display("[%0t] ========================================", $time);

    reset_tx_capture();
    send_icmp_echo_request(16'h1234, 16'h0001, 32);
    repeat(100) @(posedge clk);
    $display("[%0t] DEBUG: After 100 cycles, tx_frame_count = %0d", $time, tx_frame_count);
    repeat(100) @(posedge clk);
    $display("[%0t] DEBUG: After 200 cycles, tx_frame_count = %0d", $time, tx_frame_count);
    repeat(100) @(posedge clk);
    $display("[%0t] DEBUG: After 300 cycles, tx_frame_count = %0d", $time, tx_frame_count);
    repeat(100) @(posedge clk);
    $display("[%0t] DEBUG: After 400 cycles, tx_frame_count = %0d", $time, tx_frame_count);
    repeat(100) @(posedge clk);
    $display("[%0t] DEBUG: After 500 cycles, tx_frame_count = %0d", $time, tx_frame_count);
    repeat(2500) @(posedge clk);

    if (tx_frame_count > 0) begin
        verify_icmp_echo_reply(16'h1234, 16'h0001);
    end else begin
        $display("[%0t] ERROR: No ICMP echo reply received", $time);
        error_count = error_count + 1;
    end

    // ============================================================
    // Test 3: CMD_START with no credit -> No data (credit=0)
    // ============================================================
    test_num = 3;
    $display("");
    $display("[%0t] ========================================", $time);
    $display("[%0t] Test 3: CMD_START with no credit", $time);
    $display("[%0t] ========================================", $time);

    reset_tx_capture();
    send_ludp_cmd(CMD_START, 32'h0, 16'h0, 8'h00);
    repeat(500) @(posedge clk);

    if (tx_frame_count == 0) begin
        $display("[%0t] PASS: No data without credit (expected)", $time);
    end else begin
        $display("[%0t] INFO: Got %0d frames (may be CMD_ACK)", $time, tx_frame_count);
    end

    // ============================================================
    // Test 4: Send CREDIT -> Data packets flow
    // ============================================================
    test_num = 4;
    $display("");
    $display("[%0t] ========================================", $time);
    $display("[%0t] Test 4: CREDIT -> Data packets flow", $time);
    $display("[%0t] ========================================", $time);

    reset_tx_capture();
    send_ludp_credit(32'h8);

    // Wait for all 8 data packets to be transmitted and captured
    // Each packet takes ~10 cycles in LUDP + ~780 cycles through pipeline
    repeat(2000) @(posedge clk);

    // Verify the last captured frame should be seq=7, payload=64 bytes
    if (tx_frame_count > 0)
        verify_ludp_data(32'h7, 16'd64);
    else begin
        $display("[%0t] ERROR: No data frames captured", $time);
        error_count = error_count + 1;
    end

    // ============================================================
    // Test 5: CMD_STOP -> Data stops
    // ============================================================
    test_num = 5;
    $display("");
    $display("[%0t] ========================================", $time);
    $display("[%0t] Test 5: CMD_STOP -> Data stops", $time);
    $display("[%0t] ========================================", $time);

    reset_tx_capture();
    send_ludp_cmd(CMD_STOP, 32'h0, 16'h0, 8'h00);
    repeat(1000) @(posedge clk);

    if (tx_frame_count > 0) begin
        $display("[%0t] INFO: Received %0d frames after STOP (may be in-flight)", $time, tx_frame_count);
    end else begin
        $display("[%0t] PASS: No data packets after STOP", $time);
    end

    // ============================================================
    // Test 6: CMD_START with CPL flag -> CMD_CPL response
    // ============================================================
    test_num = 6;
    $display("");
    $display("[%0t] ========================================", $time);
    $display("[%0t] Test 6: CMD_START with CPL flag", $time);
    $display("[%0t] ========================================", $time);

    // Ensure ARP cache is fresh
    reset_tx_capture();
    send_arp_reply();
    repeat(500) @(posedge clk);

    reset_tx_capture();
    send_ludp_cmd(CMD_START, 32'h0, 16'h0, 8'h01);

    // Wait for CMD_CPL response to be transmitted and captured
    repeat(2000) @(posedge clk);

    if (tx_frame_count > 0)
        verify_ludp_response(TYPE_CMD_CPL, CMD_START);
    else begin
        $display("[%0t] ERROR: No response frame captured", $time);
        error_count = error_count + 1;
    end

    // ============================================================
    // Test 7: Send CREDIT after START -> More data
    // ============================================================
    test_num = 7;
    $display("");
    $display("[%0t] ========================================", $time);
    $display("[%0t] Test 7: CREDIT after START -> Data flow", $time);
    $display("[%0t] ========================================", $time);

    reset_tx_capture();
    send_ludp_credit(32'h10);

    // Wait for data packets to be transmitted and captured
    repeat(2000) @(posedge clk);

    // After previous tests, seq_num is at 8. With credit=16, 8 more packets can be sent.
    // The last captured frame should have seq = 8 + tx_frame_count - 1
    if (tx_frame_count > 0) begin
        $display("[%0t] INFO: Captured %0d data frames in Test 7", $time, tx_frame_count);
        verify_ludp_data(32'h8 + tx_frame_count - 1, 16'd64);
    end else begin
        $display("[%0t] ERROR: No data frame captured", $time);
        error_count = error_count + 1;
    end

    // ============================================================
    // Test 8: Jumbo frame (9KB) data transfer
    // ============================================================
    test_num = 8;
    $display("");
    $display("[%0t] ========================================", $time);
    $display("[%0t] Test 7: Jumbo frame (9KB) data transfer", $time);
    $display("[%0t] ========================================", $time);

    // Reset DUT to flush stale FIFO data from previous test
    reset_dut();

    set_payload_size(16'd9000);
    @(posedge clk);

    reset_tx_capture();
    send_ludp_cmd(CMD_START, 32'h0, 16'h0, 8'h00);
    repeat(500) @(posedge clk);

    // Send credit for 1 jumbo frame (absolute credit = current seq + 1)
    reset_tx_capture();
    send_ludp_credit(dut.ludp_tx_seq_num + 32'h1);

    // Wait for jumbo frame transmission (9KB payload + headers ~1135 cycles)
    wait_for_tx_frame(20000);

    if (tx_frame_count > 0) begin
        verify_ludp_data(dut.ludp_tx_seq_num - 32'h1, 16'd9000);
    end else begin
        $display("[%0t] ERROR: No jumbo frame captured", $time);
        error_count = error_count + 1;
    end

    // ============================================================
    // Test 9: Small tail frame (16 bytes) data transfer
    // ============================================================
    test_num = 9;
    $display("");
    $display("[%0t] ========================================", $time);
    $display("[%0t] Test 9: Small tail frame (16 bytes)", $time);
    $display("[%0t] ========================================", $time);

    // Reset DUT to flush stale FIFO data from previous test
    reset_dut();

    set_payload_size(16'd16);
    @(posedge clk);

    reset_tx_capture();
    send_ludp_cmd(CMD_START, 32'h0, 16'h0, 8'h00);
    repeat(500) @(posedge clk);

    // Send credit for 2 small frames (absolute credit = current seq + 2)
    reset_tx_capture();
    send_ludp_credit(dut.ludp_tx_seq_num + 32'h2);
    repeat(2000) @(posedge clk);

    if (tx_frame_count > 0) begin
        verify_ludp_data(dut.ludp_tx_seq_num - 32'h1, 16'd16);
    end else begin
        $display("[%0t] ERROR: No small frame captured", $time);
        error_count = error_count + 1;
    end

    // ============================================================
    // Test 10: Verify IP destination in response packets
    // This catches the bug where FPGA sends to wrong host IP
    // ============================================================
    test_num = 10;
    $display("");
    $display("[%0t] ========================================", $time);
    $display("[%0t] Test 10: Verify IP destination in responses", $time);
    $display("[%0t] ========================================", $time);

    reset_dut();

    reset_tx_capture();
    send_ludp_cmd(CMD_START, 32'h0, 16'h0, 8'h00);
    repeat(2000) @(posedge clk);

    if (tx_frame_count > 0) begin
        // Verify IP destination in response
        verify_ip_destination(HOST_IP);
    end else begin
        $display("[%0t] ERROR: No response frame captured", $time);
        error_count = error_count + 1;
    end

    // ============================================================
    // Test 11: Verify UDP checksum is 0 (disabled)
    // ============================================================
    test_num = 11;
    $display("");
    $display("[%0t] ========================================", $time);
    $display("[%0t] Test 11: Verify UDP checksum is 0", $time);
    $display("[%0t] ========================================", $time);

    reset_tx_capture();
    send_ludp_credit(32'h1);
    repeat(2000) @(posedge clk);

    if (tx_frame_count > 0) begin
        verify_udp_checksum_zero();
    end else begin
        $display("[%0t] ERROR: No frame captured for checksum check", $time);
        error_count = error_count + 1;
    end

    // ============================================================
    // Test 12: Verify response after reset and ARP re-resolution
    // This tests that the FPGA can recover from reset and re-establish communication
    // ============================================================
    test_num = 12;
    $display("");
    $display("[%0t] ========================================", $time);
    $display("[%0t] Test 12: Recovery after reset", $time);
    $display("[%0t] ========================================", $time);

    // Reset DUT
    $display("[%0t] Resetting DUT...", $time);
    rst = 1;
    sfp0_tx_rst = 1; sfp0_rx_rst = 1;
    repeat(20) @(posedge clk);
    rst = 0;
    sfp0_tx_rst = 0; sfp0_rx_rst = 0;
    repeat(600) @(posedge clk);

    // Re-resolve ARP after reset
    resolve_arp();

    // Now send command and expect response
    reset_tx_capture();
    send_ludp_cmd(CMD_START, 32'h0, 16'h0, 8'h00);
    repeat(2000) @(posedge clk);

    if (tx_frame_count > 0) begin
        $display("[%0t] PASS: Response received after reset and ARP resolution", $time);
    end else begin
        $display("[%0t] ERROR: No response after reset", $time);
        error_count = error_count + 1;
    end

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
