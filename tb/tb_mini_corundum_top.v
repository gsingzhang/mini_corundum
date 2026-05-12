`timescale 1ns / 1ps

module tb_mini_corundum_top;

    reg clk;
    reg rst;

    initial begin
        clk = 0;
        forever #3.2 clk = ~clk;
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

    reg         host_arp_request_valid = 0;
    reg  [31:0] host_arp_request_ip = 0;

    reg         host_tx_hdr_valid = 0;
    wire        host_tx_hdr_ready;
    reg  [31:0] host_tx_dest_ip = 0;
    reg  [15:0] host_tx_source_port = 0;
    reg  [15:0] host_tx_dest_port = 0;
    reg  [15:0] host_tx_length = 0;
    reg  [63:0] host_tx_payload_axis_tdata = 0;
    reg  [7:0]  host_tx_payload_axis_tkeep = 0;
    reg         host_tx_payload_axis_tvalid = 0;
    wire        host_tx_payload_axis_tready;
    reg         host_tx_payload_axis_tlast = 0;

    wire [63:0] host_rx_payload_axis_tdata;
    wire [7:0]  host_rx_payload_axis_tkeep;
    wire        host_rx_payload_axis_tvalid;
    wire        host_rx_payload_axis_tready;
    wire        host_rx_payload_axis_tlast;
    wire        host_rx_payload_axis_tuser;

    assign host_rx_payload_axis_tready = 1'b1;

    host_network_stack host_stack (
        .clk(clk),
        .rst(rst),
        .xgmii_rxd(dut_xgmii_txd),
        .xgmii_rxc(dut_xgmii_txc),
        .xgmii_txd(host_xgmii_txd),
        .xgmii_txc(host_xgmii_txc),
        .rx_payload_axis_tdata(host_rx_payload_axis_tdata),
        .rx_payload_axis_tkeep(host_rx_payload_axis_tkeep),
        .rx_payload_axis_tvalid(host_rx_payload_axis_tvalid),
        .rx_payload_axis_tready(host_rx_payload_axis_tready),
        .rx_payload_axis_tlast(host_rx_payload_axis_tlast),
        .rx_payload_axis_tuser(host_rx_payload_axis_tuser),
        .tx_hdr_valid(host_tx_hdr_valid),
        .tx_hdr_ready(host_tx_hdr_ready),
        .tx_dest_ip(host_tx_dest_ip),
        .tx_source_port(host_tx_source_port),
        .tx_dest_port(host_tx_dest_port),
        .tx_length(host_tx_length),
        .tx_payload_axis_tdata(host_tx_payload_axis_tdata),
        .tx_payload_axis_tkeep(host_tx_payload_axis_tkeep),
        .tx_payload_axis_tvalid(host_tx_payload_axis_tvalid),
        .tx_payload_axis_tready(host_tx_payload_axis_tready),
        .tx_payload_axis_tlast(host_tx_payload_axis_tlast),
        .arp_request_valid(host_arp_request_valid),
        .arp_request_ip(host_arp_request_ip)
    );

    integer pkt_count = 0;

    initial begin
        @(negedge rst);
        #10000000;

        $display("[%0t] Starting Test...", $time);

        @(posedge clk);
        host_arp_request_valid = 1;
        host_arp_request_ip = 32'hc0_a8_01_0a;
        @(posedge clk);
        host_arp_request_valid = 0;

        #50000000;

        @(posedge clk);
        host_tx_dest_ip = 32'hc0_a8_01_0a;
        host_tx_source_port = 16'd5678;
        host_tx_dest_port = 16'd1234;
        host_tx_length = 16'd24;
        host_tx_hdr_valid = 1;

        wait(host_tx_hdr_ready);
        @(posedge clk);
        host_tx_hdr_valid = 0;

        host_tx_payload_axis_tdata = 64'hAABBCCDDEEFF0011;
        host_tx_payload_axis_tkeep = 8'hFF;
        host_tx_payload_axis_tvalid = 1;
        host_tx_payload_axis_tlast = 0;

        wait(host_tx_payload_axis_tready);
        @(posedge clk);

        host_tx_payload_axis_tlast = 1;
        wait(host_tx_payload_axis_tready);
        @(posedge clk);
        host_tx_payload_axis_tvalid = 0;
        host_tx_payload_axis_tlast = 0;

        $display("[%0t] Sent Start Command. Waiting for stream data from DUT...", $time);
    end

    always @(posedge clk) begin
        if (host_rx_payload_axis_tvalid && host_rx_payload_axis_tready) begin
            if (host_rx_payload_axis_tlast) begin
                pkt_count = pkt_count + 1;
                $display("[%0t] Received stream packet %d", $time, pkt_count);
                if (pkt_count == 5) begin
                    $display("Successfully received 5 packets. Test Passed!");
                    $finish;
                end
            end
        end
    end

    initial begin
        #1000000000;
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
