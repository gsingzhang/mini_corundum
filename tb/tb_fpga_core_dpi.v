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

// Include DPI-C safe interface
`include "dpi_safe.sv"

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
task feed_packet_from_dpi;
    integer i;
    integer pkt_len;
    integer remaining;
    begin
        if (!dpi_packet_available()) begin
            $display("[%0t] DPI: No packet available", $time);
            return;
        end

        pkt_len = dpi_get_length();
        $display("[%0t] DPI: Feeding packet of %0d bytes", $time, pkt_len);

        i = 0;
        while (i < pkt_len) begin
            @(posedge clk);

            if (i == 0) begin
                // First cycle: Start + data
                sfp0_rxd[7:0]   <= XGMII_START;
                sfp0_rxc[0]     <= 1'b1;

                if (pkt_len >= 8) begin
                    sfp0_rxd[15:8]  <= dpi_get_byte(0);
                    sfp0_rxd[23:16] <= dpi_get_byte(1);
                    sfp0_rxd[31:24] <= dpi_get_byte(2);
                    sfp0_rxd[39:32] <= dpi_get_byte(3);
                    sfp0_rxd[47:40] <= dpi_get_byte(4);
                    sfp0_rxd[55:48] <= dpi_get_byte(5);
                    sfp0_rxd[63:56] <= dpi_get_byte(6);
                    sfp0_rxc[7:1]   <= 7'b0000000;
                    i = i + 7;
                end else begin
                    remaining = pkt_len - 1;
                    if (remaining >= 1) sfp0_rxd[15:8]  <= dpi_get_byte(0);
                    if (remaining >= 2) sfp0_rxd[23:16] <= dpi_get_byte(1);
                    if (remaining >= 3) sfp0_rxd[31:24] <= dpi_get_byte(2);
                    if (remaining >= 4) sfp0_rxd[39:32] <= dpi_get_byte(3);
                    if (remaining >= 5) sfp0_rxd[47:40] <= dpi_get_byte(4);
                    if (remaining >= 6) sfp0_rxd[55:48] <= dpi_get_byte(5);
                    if (remaining >= 7) begin
                        sfp0_rxd[63:56] <= XGMII_TERM;
                        sfp0_rxc[7]     <= 1'b1;
                    end
                    sfp0_rxc[7:1]   <= {remaining >= 7, 6'b000000};
                    i = pkt_len;
                end
            end else if (i + 8 >= pkt_len) begin
                // Last cycle: data + terminate
                remaining = pkt_len - i;
                sfp0_rxd[7:0]   <= dpi_get_byte(i);
                if (remaining >= 2) sfp0_rxd[15:8]  <= dpi_get_byte(i+1);
                if (remaining >= 3) sfp0_rxd[23:16] <= dpi_get_byte(i+2);
                if (remaining >= 4) sfp0_rxd[31:24] <= dpi_get_byte(i+3);
                if (remaining >= 5) sfp0_rxd[39:32] <= dpi_get_byte(i+4);
                if (remaining >= 6) sfp0_rxd[47:40] <= dpi_get_byte(i+5);
                if (remaining >= 7) sfp0_rxd[55:48] <= dpi_get_byte(i+6);
                if (remaining >= 8) begin
                    sfp0_rxd[63:56] <= dpi_get_byte(i+7);
                    sfp0_rxc        <= 8'h00;
                    i = i + 8;
                end else begin
                    sfp0_rxd[63:56] <= XGMII_TERM;
                    sfp0_rxc        <= {1'b1, 7'b0000000};
                    i = pkt_len;
                end
            end else begin
                // Middle cycle: all data
                sfp0_rxd[7:0]   <= dpi_get_byte(i);
                sfp0_rxd[15:8]  <= dpi_get_byte(i+1);
                sfp0_rxd[23:16] <= dpi_get_byte(i+2);
                sfp0_rxd[31:24] <= dpi_get_byte(i+3);
                sfp0_rxd[39:32] <= dpi_get_byte(i+4);
                sfp0_rxd[47:40] <= dpi_get_byte(i+5);
                sfp0_rxd[55:48] <= dpi_get_byte(i+6);
                sfp0_rxd[63:56] <= dpi_get_byte(i+7);
                sfp0_rxc        <= 8'h00;
                i = i + 8;
            end
        end

        // Send idle cycles after packet
        repeat(12) begin
            @(posedge clk);
            sfp0_rxd <= 64'h0707070707070707;
            sfp0_rxc <= 8'hff;
        end

        // Advance to next packet
        dpi_next_packet();
    end
endtask

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
    repeat(100) @(posedge clk);

    $display("[%0t] Reset complete, total packets from DPI: %0d", $time, dpi_get_total_packets());

    // Feed all packets from DPI
    dpi_pkt_count = 0;
    while (dpi_packet_available()) begin
        feed_packet_from_dpi();
        dpi_pkt_count = dpi_pkt_count + 1;
        repeat(100) @(posedge clk);  // Wait between packets
    end

    $display("[%0t] All DPI packets fed (%0d packets)", $time, dpi_pkt_count);

    // Wait for responses
    timeout = 0;
    while (timeout < 10000) begin
        @(posedge clk);
        timeout = timeout + 1;

        if (tx_frame_count > 0) begin
            $display("[%0t] DPI: TX frame detected (count=%0d)", $time, tx_frame_count);
            tx_frame_count = 0;
        end
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
