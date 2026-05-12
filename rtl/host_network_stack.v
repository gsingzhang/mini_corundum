`timescale 1ns / 1ps

module host_network_stack (
    input  wire        clk,
    input  wire        rst,

    input  wire [63:0] xgmii_rxd,
    input  wire [7:0]  xgmii_rxc,
    output wire [63:0] xgmii_txd,
    output wire [7:0]  xgmii_txc,

    output wire [63:0] rx_payload_axis_tdata,
    output wire [7:0]  rx_payload_axis_tkeep,
    output wire        rx_payload_axis_tvalid,
    input  wire        rx_payload_axis_tready,
    output wire        rx_payload_axis_tlast,
    output wire        rx_payload_axis_tuser,

    input  wire        tx_hdr_valid,
    output wire        tx_hdr_ready,
    input  wire [31:0] tx_dest_ip,
    input  wire [15:0] tx_source_port,
    input  wire [15:0] tx_dest_port,
    input  wire [15:0] tx_length,
    input  wire [63:0] tx_payload_axis_tdata,
    input  wire [7:0]  tx_payload_axis_tkeep,
    input  wire        tx_payload_axis_tvalid,
    output wire        tx_payload_axis_tready,
    input  wire        tx_payload_axis_tlast,

    input  wire        arp_request_valid,
    input  wire [31:0] arp_request_ip
);

    localparam DATA_WIDTH = 64;
    localparam KEEP_WIDTH = 8;

    wire [DATA_WIDTH-1:0] mac_rx_axis_tdata;
    wire [KEEP_WIDTH-1:0] mac_rx_axis_tkeep;
    wire                  mac_rx_axis_tvalid;
    wire                  mac_rx_axis_tlast;
    wire                  mac_rx_axis_tuser;

    wire [DATA_WIDTH-1:0] mac_tx_axis_tdata;
    wire [KEEP_WIDTH-1:0] mac_tx_axis_tkeep;
    wire                  mac_tx_axis_tvalid;
    wire                  mac_tx_axis_tready;
    wire                  mac_tx_axis_tlast;
    wire                  mac_tx_axis_tuser;

    eth_mac_10g #(
        .DATA_WIDTH(DATA_WIDTH),
        .KEEP_WIDTH(KEEP_WIDTH)
    ) host_mac (
        .tx_clk(clk),
        .tx_rst(rst),
        .rx_clk(clk),
        .rx_rst(rst),
        .tx_axis_tdata(mac_tx_axis_tdata),
        .tx_axis_tkeep(mac_tx_axis_tkeep),
        .tx_axis_tvalid(mac_tx_axis_tvalid),
        .tx_axis_tready(mac_tx_axis_tready),
        .tx_axis_tlast(mac_tx_axis_tlast),
        .tx_axis_tuser(mac_tx_axis_tuser),
        .rx_axis_tdata(mac_rx_axis_tdata),
        .rx_axis_tkeep(mac_rx_axis_tkeep),
        .rx_axis_tvalid(mac_rx_axis_tvalid),
        .rx_axis_tlast(mac_rx_axis_tlast),
        .rx_axis_tuser(mac_rx_axis_tuser),
        .xgmii_rxd(xgmii_rxd),
        .xgmii_rxc(xgmii_rxc),
        .xgmii_txd(xgmii_txd),
        .xgmii_txc(xgmii_txc),
        .tx_ptp_ts(96'd0),
        .rx_ptp_ts(96'd0),
        .tx_axis_ptp_ts(),
        .tx_axis_ptp_ts_tag(),
        .tx_axis_ptp_ts_valid(),
        .cfg_ifg(8'd12),
        .cfg_tx_enable(1'b1),
        .cfg_rx_enable(1'b1)
    );

    wire        eth_rx_hdr_valid;
    wire        eth_rx_hdr_ready;
    wire [47:0] eth_rx_dest_mac;
    wire [47:0] eth_rx_src_mac;
    wire [15:0] eth_rx_type;
    wire [63:0] eth_rx_payload_axis_tdata;
    wire [7:0]  eth_rx_payload_axis_tkeep;
    wire        eth_rx_payload_axis_tvalid;
    wire        eth_rx_payload_axis_tready;
    wire        eth_rx_payload_axis_tlast;
    wire        eth_rx_payload_axis_tuser;

    eth_axis_rx #(.DATA_WIDTH(DATA_WIDTH)) host_eth_rx (
        .clk(clk), .rst(rst),
        .s_axis_tdata(mac_rx_axis_tdata),
        .s_axis_tkeep(mac_rx_axis_tkeep),
        .s_axis_tvalid(mac_rx_axis_tvalid),
        .s_axis_tready(),
        .s_axis_tlast(mac_rx_axis_tlast),
        .s_axis_tuser(mac_rx_axis_tuser),
        .m_eth_hdr_valid(eth_rx_hdr_valid),
        .m_eth_hdr_ready(eth_rx_hdr_ready),
        .m_eth_dest_mac(eth_rx_dest_mac),
        .m_eth_src_mac(eth_rx_src_mac),
        .m_eth_type(eth_rx_type),
        .m_eth_payload_axis_tdata(eth_rx_payload_axis_tdata),
        .m_eth_payload_axis_tkeep(eth_rx_payload_axis_tkeep),
        .m_eth_payload_axis_tvalid(eth_rx_payload_axis_tvalid),
        .m_eth_payload_axis_tready(eth_rx_payload_axis_tready),
        .m_eth_payload_axis_tlast(eth_rx_payload_axis_tlast),
        .m_eth_payload_axis_tuser(eth_rx_payload_axis_tuser),
        .busy(), .error_header_early_termination()
    );

    wire        eth_tx_hdr_valid;
    wire        eth_tx_hdr_ready;
    wire [47:0] eth_tx_dest_mac;
    wire [47:0] eth_tx_src_mac;
    wire [15:0] eth_tx_type;
    wire [63:0] eth_tx_payload_axis_tdata;
    wire [7:0]  eth_tx_payload_axis_tkeep;
    wire        eth_tx_payload_axis_tvalid;
    wire        eth_tx_payload_axis_tready;
    wire        eth_tx_payload_axis_tlast;
    wire        eth_tx_payload_axis_tuser;

    eth_axis_tx #(.DATA_WIDTH(DATA_WIDTH)) host_eth_tx (
        .clk(clk), .rst(rst),
        .s_eth_hdr_valid(eth_tx_hdr_valid),
        .s_eth_hdr_ready(eth_tx_hdr_ready),
        .s_eth_dest_mac(eth_tx_dest_mac),
        .s_eth_src_mac(eth_tx_src_mac),
        .s_eth_type(eth_tx_type),
        .s_eth_payload_axis_tdata(eth_tx_payload_axis_tdata),
        .s_eth_payload_axis_tkeep(eth_tx_payload_axis_tkeep),
        .s_eth_payload_axis_tvalid(eth_tx_payload_axis_tvalid),
        .s_eth_payload_axis_tready(eth_tx_payload_axis_tready),
        .s_eth_payload_axis_tlast(eth_tx_payload_axis_tlast),
        .s_eth_payload_axis_tuser(eth_tx_payload_axis_tuser),
        .m_axis_tdata(mac_tx_axis_tdata),
        .m_axis_tkeep(mac_tx_axis_tkeep),
        .m_axis_tvalid(mac_tx_axis_tvalid),
        .m_axis_tready(mac_tx_axis_tready),
        .m_axis_tlast(mac_tx_axis_tlast),
        .m_axis_tuser(mac_tx_axis_tuser),
        .busy()
    );

    wire        udp_rx_hdr_valid;
    wire        udp_rx_hdr_ready;
    wire [31:0] udp_rx_source_ip;
    wire [15:0] udp_rx_source_port;
    wire [15:0] udp_rx_dest_port;
    wire [15:0] udp_rx_length;
    wire [63:0] udp_rx_payload_axis_tdata;
    wire        udp_rx_payload_axis_tvalid;
    wire        udp_rx_payload_axis_tlast;

    udp_complete_64_local host_udp (
        .clk(clk), .rst(rst),
        .s_eth_hdr_valid(eth_rx_hdr_valid),
        .s_eth_hdr_ready(eth_rx_hdr_ready),
        .s_eth_dest_mac(eth_rx_dest_mac),
        .s_eth_src_mac(eth_rx_src_mac),
        .s_eth_type(eth_rx_type),
        .s_eth_payload_axis_tdata(eth_rx_payload_axis_tdata),
        .s_eth_payload_axis_tkeep(eth_rx_payload_axis_tkeep),
        .s_eth_payload_axis_tvalid(eth_rx_payload_axis_tvalid),
        .s_eth_payload_axis_tready(eth_rx_payload_axis_tready),
        .s_eth_payload_axis_tlast(eth_rx_payload_axis_tlast),
        .s_eth_payload_axis_tuser(eth_rx_payload_axis_tuser),
        .m_eth_hdr_valid(eth_tx_hdr_valid),
        .m_eth_hdr_ready(eth_tx_hdr_ready),
        .m_eth_dest_mac(eth_tx_dest_mac),
        .m_eth_src_mac(eth_tx_src_mac),
        .m_eth_type(eth_tx_type),
        .m_eth_payload_axis_tdata(eth_tx_payload_axis_tdata),
        .m_eth_payload_axis_tkeep(eth_tx_payload_axis_tkeep),
        .m_eth_payload_axis_tvalid(eth_tx_payload_axis_tvalid),
        .m_eth_payload_axis_tready(eth_tx_payload_axis_tready),
        .m_eth_payload_axis_tlast(eth_tx_payload_axis_tlast),
        .m_eth_payload_axis_tuser(eth_tx_payload_axis_tuser),
        .s_ip_hdr_valid(1'b0), .m_ip_hdr_ready(),
        .m_udp_hdr_valid(udp_rx_hdr_valid),
        .m_udp_hdr_ready(udp_rx_hdr_ready),
        .m_udp_ip_source_ip(udp_rx_source_ip),
        .m_udp_source_port(udp_rx_source_port),
        .m_udp_dest_port(udp_rx_dest_port),
        .m_udp_length(udp_rx_length),
        .m_udp_payload_axis_tdata(udp_rx_payload_axis_tdata),
        .m_udp_payload_axis_tvalid(udp_rx_payload_axis_tvalid),
        .m_udp_payload_axis_tready(rx_payload_axis_tready),
        .m_udp_payload_axis_tlast(udp_rx_payload_axis_tlast),
        .s_udp_hdr_valid(tx_hdr_valid),
        .s_udp_hdr_ready(tx_hdr_ready),
        .s_udp_ip_dscp(6'd0), .s_udp_ip_ecn(2'd0), .s_udp_ip_ttl(8'd64),
        .s_udp_ip_source_ip(32'hc0_a8_01_64),
        .s_udp_ip_dest_ip(tx_dest_ip),
        .s_udp_source_port(tx_source_port),
        .s_udp_dest_port(tx_dest_port),
        .s_udp_length(tx_length),
        .s_udp_checksum(16'd0),
        .s_udp_payload_axis_tdata(tx_payload_axis_tdata),
        .s_udp_payload_axis_tkeep(tx_payload_axis_tkeep),
        .s_udp_payload_axis_tvalid(tx_payload_axis_tvalid),
        .s_udp_payload_axis_tready(tx_payload_axis_tready),
        .s_udp_payload_axis_tlast(tx_payload_axis_tlast),
        .s_udp_payload_axis_tuser(1'b0),
        .local_mac(48'h02_00_00_00_00_01),
        .local_ip(32'hc0_a8_01_64),
        .gateway_ip(32'hc0_a8_01_01),
        .subnet_mask(32'hff_ff_ff_00),
        .clear_arp_cache(1'b0),
        .arp_request_valid(arp_request_valid),
        .arp_request_ready(),
        .arp_request_ip(arp_request_ip)
    );

    assign rx_payload_axis_tdata  = udp_rx_payload_axis_tdata;
    assign rx_payload_axis_tkeep  = 8'hFF;
    assign rx_payload_axis_tvalid = udp_rx_payload_axis_tvalid;
    assign rx_payload_axis_tlast  = udp_rx_payload_axis_tlast;
    assign rx_payload_axis_tuser   = 1'b0;

endmodule
