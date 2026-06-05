`timescale 1ns / 1ps
`default_nettype none

module tb_fpga_core_dpi;

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
localparam [7:0]  XGMII_START   = 8'hfb;
localparam [7:0]  XGMII_TERM    = 8'hfd;
localparam [7:0]  XGMII_ERROR   = 8'hfe;
localparam [63:0] XGMII_IDLE_QW = 64'h0707070707070707;
localparam [7:0]  XGMII_IDLE_CTRL = 8'hff;
localparam [7:0]  ETH_PRE       = 8'h55;
localparam [7:0]  ETH_SFD       = 8'hD5;

// Include DPI-C safe interface
`include "dpi_safe.sv"

// CRC32 function for Ethernet FCS
function [31:0] eth_crc32;
    input integer data_len;
    integer i, j;
    reg [31:0] crc;
    reg [7:0]  byte_data;
    reg        bit_in;
    begin
        crc = 32'hFFFFFFFF;
        for (i = 0; i < data_len; i = i + 1) begin
            byte_data = dpi_get_byte(i);
            for (j = 0; j < 8; j = j + 1) begin
                bit_in = byte_data[j] ^ crc[0];
                crc = crc >> 1;
                if (bit_in) crc = crc ^ 32'hEDB88320;
            end
        end
        eth_crc32 = ~crc;
    end
endfunction

// DUT instantiation
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

// XGMII frame capture for TX verification
integer tx_frame_count = 0;
reg tx_frame_active = 0;

always @(posedge clk) begin
    if (sfp0_txc != 8'hff && !tx_frame_active) begin
        tx_frame_active <= 1;
    end
    if (tx_frame_active && sfp0_txc == 8'hff) begin
        tx_frame_active <= 0;
        tx_frame_count <= tx_frame_count + 1;
    end
end

// DPI-C packet feeding task using safe scalar functions
// Builds proper XGMII frame with Preamble, SFD, CRC, and Terminate
task feed_packet_from_dpi;
    integer i;
    integer pkt_len;
    integer beat;
    integer lane;
    integer xgmii_len;
    integer total_beats;
    reg [63:0] d;
    reg [7:0]  c;
    reg [7:0]  xgmii_data [0:1535];
    reg [31:0] crc;
    begin
        if (!dpi_packet_available()) begin
            $display("[%0t] DPI: No packet available", $time);
            return;
        end

        pkt_len = dpi_get_length();
        $display("[%0t] DPI: Feeding packet of %0d bytes", $time, pkt_len);

        // Compute Ethernet CRC32 over packet data
        crc = eth_crc32(pkt_len);

        // Build XGMII frame: [START][6xPREAMBLE][SFD][DATA][CRC][TERM]
        xgmii_data[0] = XGMII_START;
        for (i = 1; i < 7; i = i + 1)
            xgmii_data[i] = ETH_PRE;
        xgmii_data[7] = ETH_SFD;

        for (i = 0; i < pkt_len; i = i + 1)
            xgmii_data[8 + i] = dpi_get_byte(i);

        xgmii_data[8 + pkt_len + 0] = crc[7:0];
        xgmii_data[8 + pkt_len + 1] = crc[15:8];
        xgmii_data[8 + pkt_len + 2] = crc[23:16];
        xgmii_data[8 + pkt_len + 3] = crc[31:24];
        xgmii_data[8 + pkt_len + 4] = XGMII_TERM;

        xgmii_len = 13 + pkt_len;
        total_beats = (xgmii_len + 7) / 8;

        for (beat = 0; beat < total_beats; beat = beat + 1) begin
            d = XGMII_IDLE_QW;
            c = XGMII_IDLE_CTRL;

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
            sfp0_rxd <= d;
            sfp0_rxc <= c;
        end

        // Send idle cycles after packet
        repeat(12) begin
            @(posedge clk);
            sfp0_rxd <= XGMII_IDLE_QW;
            sfp0_rxc <= XGMII_IDLE_CTRL;
        end

        // Advance to next packet
        dpi_next_packet();
    end
endtask

`ifdef VPD_DUMP
initial begin
    $vcdplusfile("simv_dpi.vpd");
    $vcdpluson();
end
`endif

`ifdef FSDB_DUMP
initial begin
    $fsdbDumpfile("simv_dpi.fsdb");
    $fsdbDumpvars(0, tb_fpga_core_dpi);
    $fsdbDumpMDA();
end
`endif

`ifdef VCD_DUMP
initial begin
    $dumpfile("simv_dpi.vcd");
    $dumpvars(0, tb_fpga_core_dpi);
end
`endif

// Main test sequence
initial begin
    integer timeout;
    integer dpi_pkt_count;

    $display("========================================");
    $display("FPGA Core Testbench with DPI-C");
    $display("========================================");

    // Reset
    rst = 1;
    sfp0_tx_rst = 1;
    sfp0_rx_rst = 1;
    repeat(20) @(posedge clk);
    rst = 0;
    sfp0_tx_rst = 0;
    sfp0_rx_rst = 0;
    // Wait for ARP cache to finish clearing (512 entries @ 1 cycle each)
    repeat(600) @(posedge clk);

    $display("[%0t] Reset complete, total packets from DPI: %0d", $time, dpi_get_total_packets());

    // Feed all packets from DPI
    dpi_pkt_count = 0;
    while (dpi_packet_available()) begin
        feed_packet_from_dpi();
        dpi_pkt_count = dpi_pkt_count + 1;
        repeat(100) @(posedge clk);  // Wait between packets
    end

    $display("[%0t] All DPI packets fed (%0d packets)", $time, dpi_pkt_count);

    // Wait for responses (increased timeout for DATA packets)
    timeout = 0;
    while (timeout < 200000) begin
        @(posedge clk);
        timeout = timeout + 1;

        if (tx_frame_count > 0) begin
            $display("[%0t] DPI: TX frame detected (count=%0d)", $time, tx_frame_count);
            tx_frame_count = 0;
        end
    end

    // Final check for any remaining TX frames
    repeat(1000) @(posedge clk);
    if (tx_frame_count > 0) begin
        $display("[%0t] DPI: Final TX frame detected (count=%0d)", $time, tx_frame_count);
    end

    $display("[%0t] Simulation complete", $time);

    $display("========================================");
    $display("SIMULATION COMPLETE");
    $display("========================================");

    $finish;
end

// Timeout watchdog
initial begin
    repeat(TIMEOUT_CYCLES) @(posedge clk);
    $display("[%0t] ERROR: Global timeout reached!", $time);
    $finish;
end

endmodule
