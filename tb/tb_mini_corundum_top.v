`timescale 1ns / 1ps

module tb_mini_corundum_top;

    reg clk;
    reg rst;

    initial begin
        clk = 0;
        forever #3.2 clk = ~clk; // 156.25 MHz
    end

    initial begin
        rst = 1;
        #100;
        @(posedge clk);
        rst = 0;
    end

    wire [63:0] dut_xgmii_txd;
    wire [7:0]  dut_xgmii_txc;
    wire [63:0] host_xgmii_txd;
    wire [7:0]  host_xgmii_txc;

    mini_corundum_top dut (
        .clk(clk),
        .rst(rst),
        .xgmii_rxd(host_xgmii_txd),
        .xgmii_rxc(host_xgmii_txc),
        .xgmii_txd(dut_xgmii_txd),
        .xgmii_txc(dut_xgmii_txc)
    );

    // Host side MAC & UDP Stack
    wire [63:0] host_mac_rx_axis_tdata;
    wire [7:0]  host_mac_rx_axis_tkeep;
    wire        host_mac_rx_axis_tvalid;
    wire        host_mac_rx_axis_tlast;
    wire        host_mac_rx_axis_tuser;

    wire [63:0] host_mac_tx_axis_tdata;
    wire [7:0]  host_mac_tx_axis_tkeep;
    wire        host_mac_tx_axis_tvalid;
    wire        host_mac_tx_axis_tready;
    wire        host_mac_tx_axis_tlast;
    wire        host_mac_tx_axis_tuser;

    eth_mac_10g #(
        .DATA_WIDTH(64),
        .KEEP_WIDTH(8)
    ) host_mac (
        .tx_clk(clk),
        .tx_rst(rst),
        .rx_clk(clk),
        .rx_rst(rst),
        .tx_axis_tdata(host_mac_tx_axis_tdata),
        .tx_axis_tkeep(host_mac_tx_axis_tkeep),
        .tx_axis_tvalid(host_mac_tx_axis_tvalid),
        .tx_axis_tready(host_mac_tx_axis_tready),
        .tx_axis_tlast(host_mac_tx_axis_tlast),
        .tx_axis_tuser(host_mac_tx_axis_tuser),
        .rx_axis_tdata(host_mac_rx_axis_tdata),
        .rx_axis_tkeep(host_mac_rx_axis_tkeep),
        .rx_axis_tvalid(host_mac_rx_axis_tvalid),
        .rx_axis_tlast(host_mac_rx_axis_tlast),
        .rx_axis_tuser(host_mac_rx_axis_tuser),
        .xgmii_rxd(dut_xgmii_txd),
        .xgmii_rxc(dut_xgmii_txc),
        .xgmii_txd(host_xgmii_txd),
        .xgmii_txc(host_xgmii_txc),
        .tx_ptp_ts(96'd0),
        .rx_ptp_ts(96'd0),
        .tx_axis_ptp_ts(),
        .tx_axis_ptp_ts_tag(),
        .tx_axis_ptp_ts_valid(),
        .cfg_ifg(8'd12),
        .cfg_tx_enable(1'b1),
        .cfg_rx_enable(1'b1)
    );

    wire        host_eth_rx_hdr_valid;
    wire        host_eth_rx_hdr_ready;
    wire [47:0] host_eth_rx_dest_mac;
    wire [47:0] host_eth_rx_src_mac;
    wire [15:0] host_eth_rx_type;
    wire [63:0] host_eth_rx_payload_axis_tdata;
    wire [7:0]  host_eth_rx_payload_axis_tkeep;
    wire        host_eth_rx_payload_axis_tvalid;
    wire        host_eth_rx_payload_axis_tready;
    wire        host_eth_rx_payload_axis_tlast;
    wire        host_eth_rx_payload_axis_tuser;

    eth_axis_rx #(.DATA_WIDTH(64)) host_eth_rx (
        .clk(clk), .rst(rst),
        .s_axis_tdata(host_mac_rx_axis_tdata),
        .s_axis_tkeep(host_mac_rx_axis_tkeep),
        .s_axis_tvalid(host_mac_rx_axis_tvalid),
        .s_axis_tready(),
        .s_axis_tlast(host_mac_rx_axis_tlast),
        .s_axis_tuser(host_mac_rx_axis_tuser),
        .m_eth_hdr_valid(host_eth_rx_hdr_valid),
        .m_eth_hdr_ready(host_eth_rx_hdr_ready),
        .m_eth_dest_mac(host_eth_rx_dest_mac),
        .m_eth_src_mac(host_eth_rx_src_mac),
        .m_eth_type(host_eth_rx_type),
        .m_eth_payload_axis_tdata(host_eth_rx_payload_axis_tdata),
        .m_eth_payload_axis_tkeep(host_eth_rx_payload_axis_tkeep),
        .m_eth_payload_axis_tvalid(host_eth_rx_payload_axis_tvalid),
        .m_eth_payload_axis_tready(host_eth_rx_payload_axis_tready),
        .m_eth_payload_axis_tlast(host_eth_rx_payload_axis_tlast),
        .m_eth_payload_axis_tuser(host_eth_rx_payload_axis_tuser),
        .busy(), .error_header_early_termination()
    );

    wire        host_eth_tx_hdr_valid;
    wire        host_eth_tx_hdr_ready;
    wire [47:0] host_eth_tx_dest_mac;
    wire [47:0] host_eth_tx_src_mac;
    wire [15:0] host_eth_tx_type;
    wire [63:0] host_eth_tx_payload_axis_tdata;
    wire [7:0]  host_eth_tx_payload_axis_tkeep;
    wire        host_eth_tx_payload_axis_tvalid;
    wire        host_eth_tx_payload_axis_tready;
    wire        host_eth_tx_payload_axis_tlast;
    wire        host_eth_tx_payload_axis_tuser;

    eth_axis_tx #(.DATA_WIDTH(64)) host_eth_tx (
        .clk(clk), .rst(rst),
        .s_eth_hdr_valid(host_eth_tx_hdr_valid),
        .s_eth_hdr_ready(host_eth_tx_hdr_ready),
        .s_eth_dest_mac(host_eth_tx_dest_mac),
        .s_eth_src_mac(host_eth_tx_src_mac),
        .s_eth_type(host_eth_tx_type),
        .s_eth_payload_axis_tdata(host_eth_tx_payload_axis_tdata),
        .s_eth_payload_axis_tkeep(host_eth_tx_payload_axis_tkeep),
        .s_eth_payload_axis_tvalid(host_eth_tx_payload_axis_tvalid),
        .s_eth_payload_axis_tready(host_eth_tx_payload_axis_tready),
        .s_eth_payload_axis_tlast(host_eth_tx_payload_axis_tlast),
        .s_eth_payload_axis_tuser(host_eth_tx_payload_axis_tuser),
        .m_axis_tdata(host_mac_tx_axis_tdata),
        .m_axis_tkeep(host_mac_tx_axis_tkeep),
        .m_axis_tvalid(host_mac_tx_axis_tvalid),
        .m_axis_tready(host_mac_tx_axis_tready),
        .m_axis_tlast(host_mac_tx_axis_tlast),
        .m_axis_tuser(host_mac_tx_axis_tuser),
        .busy()
    );

    reg         host_udp_tx_hdr_valid = 0;
    wire        host_udp_tx_hdr_ready;
    reg  [31:0] host_udp_tx_dest_ip = 0;
    reg  [15:0] host_udp_tx_source_port = 0;
    reg  [15:0] host_udp_tx_dest_port = 0;
    reg  [15:0] host_udp_tx_length = 0;
    reg  [63:0] host_udp_tx_payload_axis_tdata = 0;
    reg  [7:0]  host_udp_tx_payload_axis_tkeep = 0;
    reg         host_udp_tx_payload_axis_tvalid = 0;
    wire        host_udp_tx_payload_axis_tready;
    reg         host_udp_tx_payload_axis_tlast = 0;

    wire        host_udp_rx_hdr_valid;
    wire        host_udp_rx_hdr_ready = 1;
    wire [31:0] host_udp_rx_source_ip;
    wire [15:0] host_udp_rx_source_port;
    wire [15:0] host_udp_rx_dest_port;
    wire [15:0] host_udp_rx_length;
    wire [63:0] host_udp_rx_payload_axis_tdata;
    wire        host_udp_rx_payload_axis_tvalid;
    wire        host_udp_rx_payload_axis_tready = 1;
    wire        host_udp_rx_payload_axis_tlast;

    udp_complete_64 host_udp (
        .clk(clk), .rst(rst),
        .s_eth_hdr_valid(host_eth_rx_hdr_valid),
        .s_eth_hdr_ready(host_eth_rx_hdr_ready),
        .s_eth_dest_mac(host_eth_rx_dest_mac),
        .s_eth_src_mac(host_eth_rx_src_mac),
        .s_eth_type(host_eth_rx_type),
        .s_eth_payload_axis_tdata(host_eth_rx_payload_axis_tdata),
        .s_eth_payload_axis_tkeep(host_eth_rx_payload_axis_tkeep),
        .s_eth_payload_axis_tvalid(host_eth_rx_payload_axis_tvalid),
        .s_eth_payload_axis_tready(host_eth_rx_payload_axis_tready),
        .s_eth_payload_axis_tlast(host_eth_rx_payload_axis_tlast),
        .s_eth_payload_axis_tuser(host_eth_rx_payload_axis_tuser),
        .m_eth_hdr_valid(host_eth_tx_hdr_valid),
        .m_eth_hdr_ready(host_eth_tx_hdr_ready),
        .m_eth_dest_mac(host_eth_tx_dest_mac),
        .m_eth_src_mac(host_eth_tx_src_mac),
        .m_eth_type(host_eth_tx_type),
        .m_eth_payload_axis_tdata(host_eth_tx_payload_axis_tdata),
        .m_eth_payload_axis_tkeep(host_eth_tx_payload_axis_tkeep),
        .m_eth_payload_axis_tvalid(host_eth_tx_payload_axis_tvalid),
        .m_eth_payload_axis_tready(host_eth_tx_payload_axis_tready),
        .m_eth_payload_axis_tlast(host_eth_tx_payload_axis_tlast),
        .m_eth_payload_axis_tuser(host_eth_tx_payload_axis_tuser),
        .s_ip_hdr_valid(1'b0), .m_ip_hdr_ready(),
        .m_udp_hdr_valid(host_udp_rx_hdr_valid),
        .m_udp_hdr_ready(host_udp_rx_hdr_ready),
        .m_udp_ip_source_ip(host_udp_rx_source_ip),
        .m_udp_source_port(host_udp_rx_source_port),
        .m_udp_dest_port(host_udp_rx_dest_port),
        .m_udp_length(host_udp_rx_length),
        .m_udp_payload_axis_tdata(host_udp_rx_payload_axis_tdata),
        .m_udp_payload_axis_tvalid(host_udp_rx_payload_axis_tvalid),
        .m_udp_payload_axis_tready(host_udp_rx_payload_axis_tready),
        .m_udp_payload_axis_tlast(host_udp_rx_payload_axis_tlast),
        .s_udp_hdr_valid(host_udp_tx_hdr_valid),
        .s_udp_hdr_ready(host_udp_tx_hdr_ready),
        .s_udp_ip_dscp(0), .s_udp_ip_ecn(0), .s_udp_ip_ttl(64),
        .s_udp_ip_source_ip(32'hc0_a8_01_64), // 192.168.1.100
        .s_udp_ip_dest_ip(host_udp_tx_dest_ip),
        .s_udp_source_port(host_udp_tx_source_port),
        .s_udp_dest_port(host_udp_tx_dest_port),
        .s_udp_length(host_udp_tx_length),
        .s_udp_checksum(16'd0),
        .s_udp_payload_axis_tdata(host_udp_tx_payload_axis_tdata),
        .s_udp_payload_axis_tkeep(host_udp_tx_payload_axis_tkeep),
        .s_udp_payload_axis_tvalid(host_udp_tx_payload_axis_tvalid),
        .s_udp_payload_axis_tready(host_udp_tx_payload_axis_tready),
        .s_udp_payload_axis_tlast(host_udp_tx_payload_axis_tlast),
        .s_udp_payload_axis_tuser(1'b0),
        .local_mac(48'h02_00_00_00_00_01),
        .local_ip(32'hc0_a8_01_64), // 192.168.1.100
        .gateway_ip(32'hc0_a8_01_01),
        .subnet_mask(32'hff_ff_ff_00),
        .clear_arp_cache(1'b0)
    );

    // Test Sequence
    integer pkt_count = 0;
    
    initial begin
        // Wait for reset to deassert
        @(negedge rst);
        #10000000;
        
        $display("[%0t] Starting Test...", $time);
        
        // Send ARP request manually to bypass cache timing issues
        @(posedge clk);
        force host_udp.ip_complete_64_inst.arp_request_valid = 1;
        force host_udp.ip_complete_64_inst.arp_request_ip = 32'hc0_a8_01_0a;
        @(posedge clk);
        force host_udp.ip_complete_64_inst.arp_request_valid = 0;
        
        #50000000;
        
        // Send command to DUT to start streaming (Port 1234)
        @(posedge clk);
        host_udp_tx_dest_ip <= 32'hc0_a8_01_0a; // 192.168.1.10
        host_udp_tx_source_port <= 16'd5678;
        host_udp_tx_dest_port <= 16'd1234; // Start streaming port
        host_udp_tx_length <= 16'd24; // 8 bytes UDP header + 16 payload
        host_udp_tx_hdr_valid <= 1;
        
        wait(host_udp_tx_hdr_ready);
        @(posedge clk);
        host_udp_tx_hdr_valid <= 0;
        
        host_udp_tx_payload_axis_tdata <= 64'hAABBCCDDEEFF0011;
        host_udp_tx_payload_axis_tkeep <= 8'hFF;
        host_udp_tx_payload_axis_tvalid <= 1;
        host_udp_tx_payload_axis_tlast <= 0;
        
        wait(host_udp_tx_payload_axis_tready);
        @(posedge clk);
        
        host_udp_tx_payload_axis_tlast <= 1;
        wait(host_udp_tx_payload_axis_tready);
        @(posedge clk);
        host_udp_tx_payload_axis_tvalid <= 0;
        host_udp_tx_payload_axis_tlast <= 0;
        
        $display("[%0t] Sent Start Command. Waiting for stream data from DUT...", $time);
    end
    
    always @(posedge clk) begin
        if (host_udp_rx_payload_axis_tvalid && host_udp_rx_payload_axis_tready) begin
            if (host_udp_rx_payload_axis_tlast) begin
                pkt_count = pkt_count + 1;
                $display("[%0t] Received stream packet %d", $time, pkt_count);
                if (pkt_count == 5) begin
                    $display("Successfully received 5 packets. Test Passed!");
                    $finish;
                end
            end
        end
    end
    
    // Timeout
    initial begin
        #1000000000; // 1ms timeout
        $display("Test Timeout!");
        $finish;
    end

endmodule

module tb_fsdb;
    initial begin
        $fsdbDumpfile("tb.fsdb");
        $fsdbDumpvars(0, tb_mini_corundum_top);
    end
endmodule
