/*

Copyright (c) 2020-2021 Alex Forencich

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

*/

// Language: SystemVerilog

`resetall
`timescale 1ns / 1ps
`default_nettype none

/*
 * FPGA core logic
 */
module fpga_core
(
    /*
     * Clock: 156.25MHz
     * Synchronous reset
     */
    input  wire        clk,
    input  wire        rst,

    /*
     * GPIO
     */
    input  wire        btnu,
    input  wire        btnl,
    input  wire        btnd,
    input  wire        btnr,
    input  wire        btnc,
    input  wire [7:0]  sw,
    output wire [7:0]  led,

    /*
     * UART: 115200 bps, 8N1
     */
    input  wire        uart_rxd,
    output wire        uart_txd,
    input  wire        uart_rts,
    output wire        uart_cts,

    /*
     * Ethernet: SFP+
     */
    input  wire        sfp0_tx_clk,
    input  wire        sfp0_tx_rst,
    output wire [63:0] sfp0_txd,
    output wire [7:0]  sfp0_txc,
    input  wire        sfp0_rx_clk,
    input  wire        sfp0_rx_rst,
    input  wire [63:0] sfp0_rxd,
    input  wire [7:0]  sfp0_rxc,
    input  wire        sfp1_tx_clk,
    input  wire        sfp1_tx_rst,
    output wire [63:0] sfp1_txd,
    output wire [7:0]  sfp1_txc,
    input  wire        sfp1_rx_clk,
    input  wire        sfp1_rx_rst,
    input  wire [63:0] sfp1_rxd,
    input  wire [7:0]  sfp1_rxc
);

// AXI between MAC and Ethernet modules
wire [63:0] rx_axis_tdata;
wire [7:0] rx_axis_tkeep;
wire rx_axis_tvalid;
wire rx_axis_tready;
wire rx_axis_tlast;
wire rx_axis_tuser;

wire [63:0] tx_axis_tdata;
wire [7:0] tx_axis_tkeep;
wire tx_axis_tvalid;
wire tx_axis_tready;
wire tx_axis_tlast;
wire tx_axis_tuser;
wire tx_error_underflow;
wire tx_fifo_overflow;
wire tx_fifo_bad_frame;
wire tx_fifo_good_frame;

// Ethernet frame between Ethernet modules and UDP stack
wire rx_eth_hdr_ready;
wire rx_eth_hdr_valid;
wire [47:0] rx_eth_dest_mac;
wire [47:0] rx_eth_src_mac;
wire [15:0] rx_eth_type;
wire [63:0] rx_eth_payload_axis_tdata;
wire [7:0] rx_eth_payload_axis_tkeep;
wire rx_eth_payload_axis_tvalid;
wire rx_eth_payload_axis_tready;
wire rx_eth_payload_axis_tlast;
wire rx_eth_payload_axis_tuser;

wire tx_eth_hdr_ready;
wire tx_eth_hdr_valid;
wire [47:0] tx_eth_dest_mac;
wire [47:0] tx_eth_src_mac;
wire [15:0] tx_eth_type;
wire [63:0] tx_eth_payload_axis_tdata;
wire [7:0] tx_eth_payload_axis_tkeep;
wire tx_eth_payload_axis_tvalid;
wire tx_eth_payload_axis_tready;
wire tx_eth_payload_axis_tlast;
wire tx_eth_payload_axis_tuser;

// IP frame connections
wire rx_ip_hdr_valid;
wire rx_ip_hdr_ready;
wire [47:0] rx_ip_eth_dest_mac;
wire [47:0] rx_ip_eth_src_mac;
wire [15:0] rx_ip_eth_type;
wire [3:0] rx_ip_version;
wire [3:0] rx_ip_ihl;
wire [5:0] rx_ip_dscp;
wire [1:0] rx_ip_ecn;
wire [15:0] rx_ip_length;
wire [15:0] rx_ip_identification;
wire [2:0] rx_ip_flags;
wire [12:0] rx_ip_fragment_offset;
wire [7:0] rx_ip_ttl;
wire [7:0] rx_ip_protocol;
wire [15:0] rx_ip_header_checksum;
wire [31:0] rx_ip_source_ip;
wire [31:0] rx_ip_dest_ip;
wire [63:0] rx_ip_payload_axis_tdata;
wire [7:0] rx_ip_payload_axis_tkeep;
wire rx_ip_payload_axis_tvalid;
wire rx_ip_payload_axis_tready;
wire rx_ip_payload_axis_tlast;
wire rx_ip_payload_axis_tuser;

wire tx_ip_hdr_valid;
wire tx_ip_hdr_ready;
wire [5:0] tx_ip_dscp;
wire [1:0] tx_ip_ecn;
wire [15:0] tx_ip_length;
wire [7:0] tx_ip_ttl;
wire [7:0] tx_ip_protocol;
wire [31:0] tx_ip_source_ip;
wire [31:0] tx_ip_dest_ip;
wire [63:0] tx_ip_payload_axis_tdata;
wire [7:0] tx_ip_payload_axis_tkeep;
wire tx_ip_payload_axis_tvalid;
wire tx_ip_payload_axis_tready;
wire tx_ip_payload_axis_tlast;
wire tx_ip_payload_axis_tuser;

// UDP frame connections
wire rx_udp_hdr_valid;
wire rx_udp_hdr_ready;
wire [47:0] rx_udp_eth_dest_mac;
wire [47:0] rx_udp_eth_src_mac;
wire [15:0] rx_udp_eth_type;
wire [3:0] rx_udp_ip_version;
wire [3:0] rx_udp_ip_ihl;
wire [5:0] rx_udp_ip_dscp;
wire [1:0] rx_udp_ip_ecn;
wire [15:0] rx_udp_ip_length;
wire [15:0] rx_udp_ip_identification;
wire [2:0] rx_udp_ip_flags;
wire [12:0] rx_udp_ip_fragment_offset;
wire [7:0] rx_udp_ip_ttl;
wire [7:0] rx_udp_ip_protocol;
wire [15:0] rx_udp_ip_header_checksum;
wire [31:0] rx_udp_ip_source_ip;
wire [31:0] rx_udp_ip_dest_ip;
wire [15:0] rx_udp_source_port;
wire [15:0] rx_udp_dest_port;
wire [15:0] rx_udp_length;
wire [15:0] rx_udp_checksum;
wire [63:0] rx_udp_payload_axis_tdata;
wire [7:0] rx_udp_payload_axis_tkeep;
wire rx_udp_payload_axis_tvalid;
wire rx_udp_payload_axis_tready;
wire rx_udp_payload_axis_tlast;
wire rx_udp_payload_axis_tuser;

wire tx_udp_hdr_valid;
wire tx_udp_hdr_ready;
wire [5:0] tx_udp_ip_dscp;
wire [1:0] tx_udp_ip_ecn;
wire [7:0] tx_udp_ip_ttl;
wire [31:0] tx_udp_ip_source_ip;
wire [31:0] tx_udp_ip_dest_ip;
wire [15:0] tx_udp_source_port;
wire [15:0] tx_udp_dest_port;
wire [15:0] tx_udp_length;
wire [15:0] tx_udp_checksum;
wire [63:0] tx_udp_payload_axis_tdata;
wire [7:0] tx_udp_payload_axis_tkeep;
wire tx_udp_payload_axis_tvalid;
wire tx_udp_payload_axis_tready;
wire tx_udp_payload_axis_tlast;
wire tx_udp_payload_axis_tuser;

// Configuration
wire [47:0] local_mac   = 48'h02_00_00_00_00_00;
wire [31:0] local_ip    = {8'd192, 8'd168, 8'd1,   8'd128};
wire [31:0] gateway_ip  = {8'd192, 8'd168, 8'd1,   8'd1};
wire [31:0] subnet_mask = {8'd255, 8'd255, 8'd255, 8'd0};

// ICMP support removed - focusing on LUDP protocol only
// Tie off IP TX signals to prevent issues with udp_complete_64
assign tx_ip_hdr_valid = 1'b0;
assign tx_ip_dscp = 6'd0;
assign tx_ip_ecn = 2'd0;
assign tx_ip_length = 16'd0;
assign tx_ip_ttl = 8'd0;
assign tx_ip_protocol = 8'd0;
assign tx_ip_source_ip = 32'd0;
assign tx_ip_dest_ip = 32'd0;
assign tx_ip_payload_axis_tdata = 64'd0;
assign tx_ip_payload_axis_tkeep = 8'd0;
assign tx_ip_payload_axis_tvalid = 1'b0;
assign tx_ip_payload_axis_tlast = 1'b0;
assign tx_ip_payload_axis_tuser = 1'b0;

// LUDP Protocol Configuration
wire [47:0] host_mac_reg = 48'h02_00_00_00_00_01;
wire [31:0] host_ip_reg  = {8'd192, 8'd168, 8'd1, 8'd199};
wire [15:0] ludp_port_reg = 16'd1234;

// LUDP Protocol Signals
wire [15:0] ludp_cmd_opcode;
wire [31:0] ludp_cmd_arg1;
wire [15:0] ludp_cmd_arg2;
wire        ludp_cmd_valid;
wire        ludp_cmd_ready;
wire [15:0] ludp_status_opcode;
wire [31:0] ludp_status_data;
wire        ludp_status_valid;
wire        ludp_status_ready;
wire [63:0] ludp_dma_axis_tdata;
wire [7:0]  ludp_dma_axis_tkeep;
wire        ludp_dma_axis_tvalid;
wire        ludp_dma_axis_tready;
wire        ludp_dma_axis_tlast;
wire        ludp_dma_axis_tuser;
wire [15:0] ludp_dma_pkt_size;
wire [31:0] ludp_tx_seq_num;
wire [31:0] ludp_rx_credit_limit;
wire        ludp_f2h_tx_enabled;
wire [31:0] ludp_packets_sent;
wire [31:0] ludp_packets_retx;
wire [31:0] ludp_cmd_count;
wire [15:0] ludp_last_payload_size;

// Retx buffer external memory signals
wire [31:0] ludp_retx_mem_wr_addr;
wire [63:0] ludp_retx_mem_wr_data;
wire [7:0]  ludp_retx_mem_wr_strb;
wire        ludp_retx_mem_wr_valid;
wire        ludp_retx_mem_wr_ready;
wire [31:0] ludp_retx_mem_rd_addr;
wire        ludp_retx_mem_rd_valid;
wire        ludp_retx_mem_rd_ready;
wire [63:0] ludp_retx_mem_rd_data;
wire        ludp_retx_mem_rd_valid_in;

// Test data generator for ultrasonic data simulation
// Supports variable payload sizes from 8 bytes up to jumbo frames
// Payload size is configurable via test_data_payload_size_reg (in bytes)
reg [63:0] test_data_reg = 0;
reg        test_data_valid_reg = 0;
reg        test_data_last_reg = 0;
reg [15:0] test_data_count_reg = 0;
reg        f2h_tx_enabled_dly = 0;
reg [15:0] test_data_payload_size_reg = 8960;  // Jumbo frame payload (requires MTU>=9000)
wire       test_data_fifo_tready;

always @(posedge clk) begin
    if (rst) begin
        test_data_reg <= 64'h0;
        test_data_valid_reg <= 1'b0;
        test_data_last_reg <= 1'b0;
        test_data_count_reg <= 16'h0;
        f2h_tx_enabled_dly <= 1'b0;
        test_data_payload_size_reg <= 8960;  // Jumbo frame payload
    end else begin
        f2h_tx_enabled_dly <= ludp_f2h_tx_enabled;

        if (ludp_f2h_tx_enabled) begin
            test_data_valid_reg <= 1'b1;
            if (test_data_valid_reg && test_data_fifo_tready) begin
                test_data_reg <= {test_data_count_reg[7:0], 56'h0};
                test_data_last_reg <= (test_data_count_reg == (test_data_payload_size_reg/8 - 1));
                if (test_data_count_reg == (test_data_payload_size_reg/8 - 1))
                    test_data_count_reg <= 16'h0;
                else
                    test_data_count_reg <= test_data_count_reg + 1;
            end
        end else begin
            test_data_valid_reg <= 1'b0;
            test_data_last_reg <= 1'b0;
            test_data_count_reg <= 16'h0;
        end
    end
end

// AXI-Stream FIFO between test data generator and LUDP protocol
wire [63:0] ludp_tx_fifo_axis_tdata;
wire [7:0]  ludp_tx_fifo_axis_tkeep;
wire        ludp_tx_fifo_axis_tvalid;
wire        ludp_tx_fifo_axis_tready;
wire        ludp_tx_fifo_axis_tlast;
wire        ludp_tx_fifo_axis_tuser;

axis_fifo #(
    .DEPTH(16384),
    .DATA_WIDTH(64),
    .KEEP_ENABLE(1),
    .KEEP_WIDTH(8),
    .LAST_ENABLE(1),
    .ID_ENABLE(0),
    .DEST_ENABLE(0),
    .USER_ENABLE(1),
    .USER_WIDTH(1),
    .RAM_PIPELINE(1),
    .OUTPUT_FIFO_ENABLE(0),
    .FRAME_FIFO(0),
    .PAUSE_ENABLE(0)
)
ludp_tx_fifo_inst (
    .clk(clk),
    .rst(rst),

    .s_axis_tdata(test_data_reg),
    .s_axis_tkeep(8'hFF),
    .s_axis_tvalid(test_data_valid_reg),
    .s_axis_tready(test_data_fifo_tready),
    .s_axis_tlast(test_data_last_reg),
    .s_axis_tid(8'h0),
    .s_axis_tdest(8'h0),
    .s_axis_tuser(1'b0),

    .m_axis_tdata(ludp_tx_fifo_axis_tdata),
    .m_axis_tkeep(ludp_tx_fifo_axis_tkeep),
    .m_axis_tvalid(ludp_tx_fifo_axis_tvalid),
    .m_axis_tready(ludp_tx_fifo_axis_tready),
    .m_axis_tlast(ludp_tx_fifo_axis_tlast),
    .m_axis_tid(),
    .m_axis_tdest(),
    .m_axis_tuser(ludp_tx_fifo_axis_tuser),

    .pause_req(1'b0),
    .pause_ack(),

    .status_depth(),
    .status_depth_commit(),
    .status_overflow(),
    .status_bad_frame(),
    .status_good_frame()
);

assign ludp_dma_axis_tdata  = ludp_tx_fifo_axis_tdata;
assign ludp_dma_axis_tkeep  = ludp_tx_fifo_axis_tkeep;
assign ludp_dma_axis_tvalid = ludp_tx_fifo_axis_tvalid;
assign ludp_dma_axis_tlast  = ludp_tx_fifo_axis_tlast;
assign ludp_dma_axis_tuser  = ludp_tx_fifo_axis_tuser;
assign ludp_dma_pkt_size    = test_data_payload_size_reg;
assign ludp_tx_fifo_axis_tready = ludp_dma_axis_tready;

// LUDP Protocol Instance
ludp_protocol #(
    .DATA_WIDTH(64),
    .KEEP_WIDTH(8),
    .NUM_BLOCKS(3),
    .MEM_SLOT_SIZE(16384)
)
ludp_protocol_inst (
    .clk(clk),
    .rst(rst),

    .local_mac(local_mac),
    .local_ip(local_ip),
    .host_mac(host_mac_reg),
    .host_ip(host_ip_reg),
    .udp_port(ludp_port_reg),

    .cmd_opcode(ludp_cmd_opcode),
    .cmd_arg1(ludp_cmd_arg1),
    .cmd_arg2(ludp_cmd_arg2),
    .cmd_valid(ludp_cmd_valid),
    .cmd_ready(ludp_cmd_ready),

    .status_opcode(ludp_status_opcode),
    .status_data(ludp_status_data),
    .status_valid(ludp_status_valid),
    .status_ready(ludp_status_ready),

    .dma_axis_tdata(ludp_dma_axis_tdata),
    .dma_axis_tkeep(ludp_dma_axis_tkeep),
    .dma_axis_tvalid(ludp_dma_axis_tvalid),
    .dma_axis_tready(ludp_dma_axis_tready),
    .dma_axis_tlast(ludp_dma_axis_tlast),
    .dma_axis_tuser(ludp_dma_axis_tuser),
    .dma_pkt_size(ludp_dma_pkt_size),

    .rx_udp_hdr_valid(rx_udp_hdr_valid),
    .rx_udp_hdr_ready(rx_udp_hdr_ready),
    .rx_udp_eth_dest_mac(rx_udp_eth_dest_mac),
    .rx_udp_eth_src_mac(rx_udp_eth_src_mac),
    .rx_udp_eth_type(rx_udp_eth_type),
    .rx_udp_ip_source_ip(rx_udp_ip_source_ip),
    .rx_udp_ip_dest_ip(rx_udp_ip_dest_ip),
    .rx_udp_source_port(rx_udp_source_port),
    .rx_udp_dest_port(rx_udp_dest_port),
    .rx_udp_length(rx_udp_length),
    .rx_udp_checksum(rx_udp_checksum),
    .rx_udp_payload_axis_tdata(rx_udp_payload_axis_tdata),
    .rx_udp_payload_axis_tkeep(rx_udp_payload_axis_tkeep),
    .rx_udp_payload_axis_tvalid(rx_udp_payload_axis_tvalid),
    .rx_udp_payload_axis_tready(rx_udp_payload_axis_tready),
    .rx_udp_payload_axis_tlast(rx_udp_payload_axis_tlast),
    .rx_udp_payload_axis_tuser(rx_udp_payload_axis_tuser),

    .tx_udp_hdr_valid(tx_udp_hdr_valid),
    .tx_udp_hdr_ready(tx_udp_hdr_ready),
    .tx_udp_ip_dscp(tx_udp_ip_dscp),
    .tx_udp_ip_ecn(tx_udp_ip_ecn),
    .tx_udp_ip_ttl(tx_udp_ip_ttl),
    .tx_udp_ip_source_ip(tx_udp_ip_source_ip),
    .tx_udp_ip_dest_ip(tx_udp_ip_dest_ip),
    .tx_udp_source_port(tx_udp_source_port),
    .tx_udp_dest_port(tx_udp_dest_port),
    .tx_udp_length(tx_udp_length),
    .tx_udp_checksum(tx_udp_checksum),
    .tx_udp_payload_axis_tdata(tx_udp_payload_axis_tdata),
    .tx_udp_payload_axis_tkeep(tx_udp_payload_axis_tkeep),
    .tx_udp_payload_axis_tvalid(tx_udp_payload_axis_tvalid),
    .tx_udp_payload_axis_tready(tx_udp_payload_axis_tready),
    .tx_udp_payload_axis_tlast(tx_udp_payload_axis_tlast),
    .tx_udp_payload_axis_tuser(tx_udp_payload_axis_tuser),

    .tx_seq_num(ludp_tx_seq_num),
    .rx_credit_limit(ludp_rx_credit_limit),
    .f2h_tx_enabled(ludp_f2h_tx_enabled),
    .packets_sent(ludp_packets_sent),
    .packets_retx(ludp_packets_retx),
    .cmd_count(ludp_cmd_count),
    .last_payload_size(ludp_last_payload_size),

    .retx_mem_wr_addr (ludp_retx_mem_wr_addr),
    .retx_mem_wr_data (ludp_retx_mem_wr_data),
    .retx_mem_wr_strb (ludp_retx_mem_wr_strb),
    .retx_mem_wr_valid(ludp_retx_mem_wr_valid),
    .retx_mem_wr_ready(ludp_retx_mem_wr_ready),

    .retx_mem_rd_addr  (ludp_retx_mem_rd_addr),
    .retx_mem_rd_valid (ludp_retx_mem_rd_valid),
    .retx_mem_rd_ready (ludp_retx_mem_rd_ready),
    .retx_mem_rd_data  (ludp_retx_mem_rd_data),
    .retx_mem_rd_valid_in(ludp_retx_mem_rd_valid_in)
);

assign ludp_status_opcode = 16'h0;
assign ludp_status_data  = {f2h_tx_enabled_dly, 31'h0};
assign ludp_status_valid = 1'b0;
assign ludp_cmd_ready    = 1'b1;

// Retx buffer external memory model (simple 1R1W RAM)
// In real application, this connects to DDR/AXI RAM
taxi_ram_1r1w_1c #(
    .ADDR_W(16),
    .DATA_W(64),
    .STRB_EN(1'b1),
    .STRB_W(8)
) retx_ram_inst (
    .clk(clk),

    .wr_en(ludp_retx_mem_wr_valid),
    .wr_addr(ludp_retx_mem_wr_addr[15:0]),
    .wr_data(ludp_retx_mem_wr_data),
    .wr_strb(ludp_retx_mem_wr_strb),

    .rd_en(ludp_retx_mem_rd_valid),
    .rd_addr(ludp_retx_mem_rd_addr[15:0]),
    .rd_data(ludp_retx_mem_rd_data)
);

assign ludp_retx_mem_wr_ready = 1'b1;
assign ludp_retx_mem_rd_ready = 1'b1;

// taxi_ram_1r1w_1c has 1-cycle read latency: data is valid the cycle AFTER rd_en.
// Delay rd_valid by 1 cycle to match.
reg ludp_retx_mem_rd_valid_d;
always @(posedge clk) begin
    if (rst)
        ludp_retx_mem_rd_valid_d <= 1'b0;
    else
        ludp_retx_mem_rd_valid_d <= ludp_retx_mem_rd_valid;
end
assign ludp_retx_mem_rd_valid_in = ludp_retx_mem_rd_valid_d;

// LED output: show burst status and command count
reg [7:0] led_reg = 0;

always @(posedge clk) begin
    if (rst) begin
        led_reg <= 8'h00;
    end else begin
        led_reg <= {ludp_f2h_tx_enabled, ludp_cmd_count[6:0]};
    end
end

assign led = led_reg;

assign sfp1_txd = 64'h0707070707070707;
assign sfp1_txc = 8'hff;

// Increase TX/RX FIFO depth to support jumbo frames (9KB+).
// The default 4KB FIFO drops frames larger than half its depth
// when FRAME_FIFO=1 and DROP_OVERSIZE_FRAME=1.
// 32KB depth provides 16KB frame capacity, sufficient for 9KB payloads.
eth_mac_10g_fifo #(
    .ENABLE_PADDING(1),
    .ENABLE_DIC(1),
    .MIN_FRAME_LENGTH(64),
    .TX_FIFO_DEPTH(32768),
    .TX_FRAME_FIFO(1),
    .RX_FIFO_DEPTH(32768),
    .RX_FRAME_FIFO(1)
)
eth_mac_10g_fifo_inst (
    .rx_clk(sfp0_rx_clk),
    .rx_rst(sfp0_rx_rst),
    .tx_clk(sfp0_tx_clk),
    .tx_rst(sfp0_tx_rst),
    .logic_clk(clk),
    .logic_rst(rst),

    .tx_axis_tdata(tx_axis_tdata),
    .tx_axis_tkeep(tx_axis_tkeep),
    .tx_axis_tvalid(tx_axis_tvalid),
    .tx_axis_tready(tx_axis_tready),
    .tx_axis_tlast(tx_axis_tlast),
    .tx_axis_tuser(tx_axis_tuser),

    .rx_axis_tdata(rx_axis_tdata),
    .rx_axis_tkeep(rx_axis_tkeep),
    .rx_axis_tvalid(rx_axis_tvalid),
    .rx_axis_tready(rx_axis_tready),
    .rx_axis_tlast(rx_axis_tlast),
    .rx_axis_tuser(rx_axis_tuser),

    .xgmii_rxd(sfp0_rxd),
    .xgmii_rxc(sfp0_rxc),
    .xgmii_txd(sfp0_txd),
    .xgmii_txc(sfp0_txc),

    .tx_error_underflow(tx_error_underflow),
    .tx_fifo_overflow(tx_fifo_overflow),
    .tx_fifo_bad_frame(tx_fifo_bad_frame),
    .tx_fifo_good_frame(tx_fifo_good_frame),
    .rx_error_bad_frame(),
    .rx_error_bad_fcs(),
    .rx_fifo_overflow(),
    .rx_fifo_bad_frame(),
    .rx_fifo_good_frame(),

    .cfg_ifg(8'd12),
    .cfg_tx_enable(1'b1),
    .cfg_rx_enable(1'b1)
);

eth_axis_rx #(
    .DATA_WIDTH(64)
)
eth_axis_rx_inst (
    .clk(clk),
    .rst(rst),
    // AXI input
    .s_axis_tdata(rx_axis_tdata),
    .s_axis_tkeep(rx_axis_tkeep),
    .s_axis_tvalid(rx_axis_tvalid),
    .s_axis_tready(rx_axis_tready),
    .s_axis_tlast(rx_axis_tlast),
    .s_axis_tuser(rx_axis_tuser),
    // Ethernet frame output
    .m_eth_hdr_valid(rx_eth_hdr_valid),
    .m_eth_hdr_ready(rx_eth_hdr_ready),
    .m_eth_dest_mac(rx_eth_dest_mac),
    .m_eth_src_mac(rx_eth_src_mac),
    .m_eth_type(rx_eth_type),
    .m_eth_payload_axis_tdata(rx_eth_payload_axis_tdata),
    .m_eth_payload_axis_tkeep(rx_eth_payload_axis_tkeep),
    .m_eth_payload_axis_tvalid(rx_eth_payload_axis_tvalid),
    .m_eth_payload_axis_tready(rx_eth_payload_axis_tready),
    .m_eth_payload_axis_tlast(rx_eth_payload_axis_tlast),
    .m_eth_payload_axis_tuser(rx_eth_payload_axis_tuser),
    // Status signals
    .busy(),
    .error_header_early_termination()
);

eth_axis_tx #(
    .DATA_WIDTH(64)
)
eth_axis_tx_inst (
    .clk(clk),
    .rst(rst),
    // Ethernet frame input
    .s_eth_hdr_valid(tx_eth_hdr_valid),
    .s_eth_hdr_ready(tx_eth_hdr_ready),
    .s_eth_dest_mac(tx_eth_dest_mac),
    .s_eth_src_mac(tx_eth_src_mac),
    .s_eth_type(tx_eth_type),
    .s_eth_payload_axis_tdata(tx_eth_payload_axis_tdata),
    .s_eth_payload_axis_tkeep(tx_eth_payload_axis_tkeep),
    .s_eth_payload_axis_tvalid(tx_eth_payload_axis_tvalid),
    .s_eth_payload_axis_tready(tx_eth_payload_axis_tready),
    .s_eth_payload_axis_tlast(tx_eth_payload_axis_tlast),
    .s_eth_payload_axis_tuser(tx_eth_payload_axis_tuser),
    // AXI output
    .m_axis_tdata(tx_axis_tdata),
    .m_axis_tkeep(tx_axis_tkeep),
    .m_axis_tvalid(tx_axis_tvalid),
    .m_axis_tready(tx_axis_tready),
    .m_axis_tlast(tx_axis_tlast),
    .m_axis_tuser(tx_axis_tuser),
    // Status signals
    .busy()
);

// Disable UDP checksum generation to support jumbo frames.
// The checksum generator's internal payload FIFO (2KB) cannot hold
// 9KB jumbo frames, causing backpressure that stalls transmission.
// UDP checksum is optional in IPv4; setting it to 0 is valid.
// MAC-layer FCS and LUDP's magic number provide sufficient integrity.
udp_complete_64 #(
    .UDP_CHECKSUM_GEN_ENABLE(0)
)
udp_complete_inst (
    .clk(clk),
    .rst(rst),
    // Ethernet frame input
    .s_eth_hdr_valid(rx_eth_hdr_valid),
    .s_eth_hdr_ready(rx_eth_hdr_ready),
    .s_eth_dest_mac(rx_eth_dest_mac),
    .s_eth_src_mac(rx_eth_src_mac),
    .s_eth_type(rx_eth_type),
    .s_eth_payload_axis_tdata(rx_eth_payload_axis_tdata),
    .s_eth_payload_axis_tkeep(rx_eth_payload_axis_tkeep),
    .s_eth_payload_axis_tvalid(rx_eth_payload_axis_tvalid),
    .s_eth_payload_axis_tready(rx_eth_payload_axis_tready),
    .s_eth_payload_axis_tlast(rx_eth_payload_axis_tlast),
    .s_eth_payload_axis_tuser(rx_eth_payload_axis_tuser),
    // Ethernet frame output
    .m_eth_hdr_valid(tx_eth_hdr_valid),
    .m_eth_hdr_ready(tx_eth_hdr_ready),
    .m_eth_dest_mac(tx_eth_dest_mac),
    .m_eth_src_mac(tx_eth_src_mac),
    .m_eth_type(tx_eth_type),
    .m_eth_payload_axis_tdata(tx_eth_payload_axis_tdata),
    .m_eth_payload_axis_tkeep(tx_eth_payload_axis_tkeep),
    .m_eth_payload_axis_tvalid(tx_eth_payload_axis_tvalid),
    .m_eth_payload_axis_tready(tx_eth_payload_axis_tready),
    .m_eth_payload_axis_tlast(tx_eth_payload_axis_tlast),
    .m_eth_payload_axis_tuser(tx_eth_payload_axis_tuser),
    // IP frame input
    .s_ip_hdr_valid(tx_ip_hdr_valid),
    .s_ip_hdr_ready(tx_ip_hdr_ready),
    .s_ip_dscp(tx_ip_dscp),
    .s_ip_ecn(tx_ip_ecn),
    .s_ip_length(tx_ip_length),
    .s_ip_ttl(tx_ip_ttl),
    .s_ip_protocol(tx_ip_protocol),
    .s_ip_source_ip(tx_ip_source_ip),
    .s_ip_dest_ip(tx_ip_dest_ip),
    .s_ip_payload_axis_tdata(tx_ip_payload_axis_tdata),
    .s_ip_payload_axis_tkeep(tx_ip_payload_axis_tkeep),
    .s_ip_payload_axis_tvalid(tx_ip_payload_axis_tvalid),
    .s_ip_payload_axis_tready(tx_ip_payload_axis_tready),
    .s_ip_payload_axis_tlast(tx_ip_payload_axis_tlast),
    .s_ip_payload_axis_tuser(tx_ip_payload_axis_tuser),
    // IP frame output
    .m_ip_hdr_valid(rx_ip_hdr_valid),
    .m_ip_hdr_ready(rx_ip_hdr_ready),
    .m_ip_eth_dest_mac(rx_ip_eth_dest_mac),
    .m_ip_eth_src_mac(rx_ip_eth_src_mac),
    .m_ip_eth_type(rx_ip_eth_type),
    .m_ip_version(rx_ip_version),
    .m_ip_ihl(rx_ip_ihl),
    .m_ip_dscp(rx_ip_dscp),
    .m_ip_ecn(rx_ip_ecn),
    .m_ip_length(rx_ip_length),
    .m_ip_identification(rx_ip_identification),
    .m_ip_flags(rx_ip_flags),
    .m_ip_fragment_offset(rx_ip_fragment_offset),
    .m_ip_ttl(rx_ip_ttl),
    .m_ip_protocol(rx_ip_protocol),
    .m_ip_header_checksum(rx_ip_header_checksum),
    .m_ip_source_ip(rx_ip_source_ip),
    .m_ip_dest_ip(rx_ip_dest_ip),
    .m_ip_payload_axis_tdata(rx_ip_payload_axis_tdata),
    .m_ip_payload_axis_tkeep(rx_ip_payload_axis_tkeep),
    .m_ip_payload_axis_tvalid(rx_ip_payload_axis_tvalid),
    .m_ip_payload_axis_tready(rx_ip_payload_axis_tready),
    .m_ip_payload_axis_tlast(rx_ip_payload_axis_tlast),
    .m_ip_payload_axis_tuser(rx_ip_payload_axis_tuser),
    // UDP frame input
    .s_udp_hdr_valid(tx_udp_hdr_valid),
    .s_udp_hdr_ready(tx_udp_hdr_ready),
    .s_udp_ip_dscp(tx_udp_ip_dscp),
    .s_udp_ip_ecn(tx_udp_ip_ecn),
    .s_udp_ip_ttl(tx_udp_ip_ttl),
    .s_udp_ip_source_ip(tx_udp_ip_source_ip),
    .s_udp_ip_dest_ip(tx_udp_ip_dest_ip),
    .s_udp_source_port(tx_udp_source_port),
    .s_udp_dest_port(tx_udp_dest_port),
    .s_udp_length(tx_udp_length),
    .s_udp_checksum(tx_udp_checksum),
    .s_udp_payload_axis_tdata(tx_udp_payload_axis_tdata),
    .s_udp_payload_axis_tkeep(tx_udp_payload_axis_tkeep),
    .s_udp_payload_axis_tvalid(tx_udp_payload_axis_tvalid),
    .s_udp_payload_axis_tready(tx_udp_payload_axis_tready),
    .s_udp_payload_axis_tlast(tx_udp_payload_axis_tlast),
    .s_udp_payload_axis_tuser(tx_udp_payload_axis_tuser),
    // UDP frame output
    .m_udp_hdr_valid(rx_udp_hdr_valid),
    .m_udp_hdr_ready(rx_udp_hdr_ready),
    .m_udp_eth_dest_mac(rx_udp_eth_dest_mac),
    .m_udp_eth_src_mac(rx_udp_eth_src_mac),
    .m_udp_eth_type(rx_udp_eth_type),
    .m_udp_ip_version(rx_udp_ip_version),
    .m_udp_ip_ihl(rx_udp_ip_ihl),
    .m_udp_ip_dscp(rx_udp_ip_dscp),
    .m_udp_ip_ecn(rx_udp_ip_ecn),
    .m_udp_ip_length(rx_udp_ip_length),
    .m_udp_ip_identification(rx_udp_ip_identification),
    .m_udp_ip_flags(rx_udp_ip_flags),
    .m_udp_ip_fragment_offset(rx_udp_ip_fragment_offset),
    .m_udp_ip_ttl(rx_udp_ip_ttl),
    .m_udp_ip_protocol(rx_udp_ip_protocol),
    .m_udp_ip_header_checksum(rx_udp_ip_header_checksum),
    .m_udp_ip_source_ip(rx_udp_ip_source_ip),
    .m_udp_ip_dest_ip(rx_udp_ip_dest_ip),
    .m_udp_source_port(rx_udp_source_port),
    .m_udp_dest_port(rx_udp_dest_port),
    .m_udp_length(rx_udp_length),
    .m_udp_checksum(rx_udp_checksum),
    .m_udp_payload_axis_tdata(rx_udp_payload_axis_tdata),
    .m_udp_payload_axis_tkeep(rx_udp_payload_axis_tkeep),
    .m_udp_payload_axis_tvalid(rx_udp_payload_axis_tvalid),
    .m_udp_payload_axis_tready(rx_udp_payload_axis_tready),
    .m_udp_payload_axis_tlast(rx_udp_payload_axis_tlast),
    .m_udp_payload_axis_tuser(rx_udp_payload_axis_tuser),
    // Status signals
    .ip_rx_busy(),
    .ip_tx_busy(),
    .udp_rx_busy(),
    .udp_tx_busy(),
    .ip_rx_error_header_early_termination(),
    .ip_rx_error_payload_early_termination(),
    .ip_rx_error_invalid_header(),
    .ip_rx_error_invalid_checksum(),
    .ip_tx_error_payload_early_termination(),
    .ip_tx_error_arp_failed(),
    .udp_rx_error_header_early_termination(),
    .udp_rx_error_payload_early_termination(),
    .udp_tx_error_payload_early_termination(),
    // Configuration
    .local_mac(local_mac),
    .local_ip(local_ip),
    .gateway_ip(gateway_ip),
    .subnet_mask(subnet_mask),
    .clear_arp_cache(1'b0)
);

// Debug prints for packet tracing
always @(posedge clk) begin
    if (tx_eth_hdr_valid && tx_eth_hdr_ready) begin
        $display("[%0t] FPGA: Ethernet TX hdr out from udp_complete_64, dest=%012h type=%04h", $time, tx_eth_dest_mac, tx_eth_type);
    end
    if (tx_eth_payload_axis_tvalid && tx_eth_payload_axis_tready) begin
        $display("[%0t] FPGA: eth_axis TX payload data=%016h keep=%02h last=%b", $time, tx_eth_payload_axis_tdata, tx_eth_payload_axis_tkeep, tx_eth_payload_axis_tlast);
    end
    if (tx_axis_tvalid && tx_axis_tready) begin
        $display("[%0t] FPGA: AXIS TX data=%016h keep=%02h last=%b", $time, tx_axis_tdata, tx_axis_tkeep, tx_axis_tlast);
    end
    if (tx_error_underflow) begin
        $display("[%0t] FPGA: TX error underflow!", $time);
    end
    if (tx_fifo_overflow) begin
        $display("[%0t] FPGA: TX FIFO overflow!", $time);
    end
    if (tx_fifo_bad_frame) begin
        $display("[%0t] FPGA: TX FIFO bad frame!", $time);
    end
    if (tx_fifo_good_frame) begin
        $display("[%0t] FPGA: TX FIFO good frame!", $time);
    end
end

endmodule

`resetall
