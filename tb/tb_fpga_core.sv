`timescale 1ns / 1ps
`default_nettype none

import uvm_pkg::*;
`include "uvm_macros.svh"
import ludp_tb_pkg::*;

module tb_fpga_core;

localparam CLK_PERIOD = 6.4;       // 156.25 MHz logic clock
localparam M_CLK_PERIOD = 3.333;   // 300 MHz DMA clock (DDR4 UI clock)
localparam TIMEOUT_CYCLES = 10000000;

reg clk = 0;
reg m_clk = 0;
reg m_rst = 0;

wire sfp0_tx_clk = clk;
wire sfp0_rx_clk = clk;
wire sfp1_tx_clk = clk;
wire sfp1_rx_clk = clk;

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
wire [63:0] sfp1_txd;
wire [7:0]  sfp1_txc;

xgmii_if sfp0_xgmii(.clk(clk), .rst(dut_ctrl.rst));
xgmii_if sfp1_xgmii(.clk(clk), .rst(dut_ctrl.rst));

dut_ctrl_if dut_ctrl(.clk(clk));

assign sfp0_xgmii.txd = sfp0_txd;
assign sfp0_xgmii.txc = sfp0_txc;
assign sfp1_xgmii.txd = sfp1_txd;
assign sfp1_xgmii.txc = sfp1_txc;

fpga_core dut (
    .clk(clk),
    .rst(dut_ctrl.rst),
    .m_clk(m_clk),
    .m_rst(m_rst),
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
    .sfp0_tx_rst(dut_ctrl.sfp0_tx_rst),
    .sfp0_txd(sfp0_txd),
    .sfp0_txc(sfp0_txc),
    .sfp0_rx_clk(sfp0_rx_clk),
    .sfp0_rx_rst(dut_ctrl.sfp0_rx_rst),
    .sfp0_rxd(sfp0_xgmii.rxd),
    .sfp0_rxc(sfp0_xgmii.rxc),
    .sfp1_tx_clk(sfp1_tx_clk),
    .sfp1_tx_rst(dut_ctrl.sfp1_tx_rst),
    .sfp1_txd(sfp1_txd),
    .sfp1_txc(sfp1_txc),
    .sfp1_rx_clk(sfp1_rx_clk),
    .sfp1_rx_rst(dut_ctrl.sfp1_rx_rst),
    .sfp1_rxd(sfp1_xgmii.rxd),
    .sfp1_rxc(sfp1_xgmii.rxc)
);

always #(CLK_PERIOD/2) clk = ~clk;
always #(M_CLK_PERIOD/2) m_clk = ~m_clk;

initial begin
    m_rst = 1;
    repeat(20) @(posedge m_clk);
    m_rst = 0;
end

assign dut_ctrl.tx_seq_num    = dut.ludp_tx_seq_num;
assign dut_ctrl.tx_enabled    = dut.ludp_protocol_inst.f2h_tx_enabled_reg;
assign dut_ctrl.dma_wr_enable = dut.ludp_protocol_inst.scheduler_inst.dma_wr_enable;
assign dut_ctrl.retx_found    = dut.ludp_protocol_inst.sch_retx_found;
assign dut_ctrl.block_recycle = dut.ludp_protocol_inst.scheduler_inst.tx_pkt_done;
assign dut_ctrl.resp_ongoing  = dut.ludp_protocol_inst.resp_ongoing_reg;
assign dut_ctrl.status_valid  = dut.ludp_status_valid;

// AXI burst monitor - logs write/read burst lengths
integer wr_burst_count = 0;
integer rd_burst_count = 0;
integer wr_max_burst   = 0;
integer rd_max_burst   = 0;
integer wr_total_beats = 0;
integer rd_total_beats = 0;

// Monitor AXI write bursts
always @(posedge m_clk) begin
    if (dut.ludp_sim_axi_if_inst.awvalid && dut.ludp_sim_axi_if_inst.awready) begin
        wr_burst_count = wr_burst_count + 1;
        wr_total_beats = wr_total_beats + dut.ludp_sim_axi_if_inst.awlen + 1;
        if (dut.ludp_sim_axi_if_inst.awlen + 1 > wr_max_burst)
            wr_max_burst = dut.ludp_sim_axi_if_inst.awlen + 1;
        $display("[%0t] AXI_WR_BURST #%0d: awlen=%0d (beats=%0d) addr=0x%08x",
                 $time, wr_burst_count, dut.ludp_sim_axi_if_inst.awlen,
                 dut.ludp_sim_axi_if_inst.awlen + 1, dut.ludp_sim_axi_if_inst.awaddr);
    end
end

// Monitor AXI read bursts
always @(posedge m_clk) begin
    if (dut.ludp_sim_axi_if_inst.arvalid && dut.ludp_sim_axi_if_inst.arready) begin
        rd_burst_count = rd_burst_count + 1;
        rd_total_beats = rd_total_beats + dut.ludp_sim_axi_if_inst.arlen + 1;
        if (dut.ludp_sim_axi_if_inst.arlen + 1 > rd_max_burst)
            rd_max_burst = dut.ludp_sim_axi_if_inst.arlen + 1;
        $display("[%0t] AXI_RD_BURST #%0d: arlen=%0d (beats=%0d) addr=0x%08x",
                 $time, rd_burst_count, dut.ludp_sim_axi_if_inst.arlen,
                 dut.ludp_sim_axi_if_inst.arlen + 1, dut.ludp_sim_axi_if_inst.araddr);
    end
end

// Final report
final begin
    $display("");
    $display("========================================");
    $display(" AXI Burst Summary");
    $display("========================================");
    $display(" Write bursts:    %0d", wr_burst_count);
    $display(" Write total beats: %0d", wr_total_beats);
    $display(" Write max burst:   %0d beats", wr_max_burst);
    $display(" Read bursts:     %0d", rd_burst_count);
    $display(" Read total beats:  %0d", rd_total_beats);
    $display(" Read max burst:    %0d beats", rd_max_burst);
    $display("========================================");
end

always @(posedge clk) begin
    if (dut_ctrl.payload_size_we)
        dut.test_data_payload_size_reg <= dut_ctrl.payload_size;
end

always @(posedge clk) begin
    if (dut_ctrl.force_status_en) begin
        force dut.ludp_status_opcode = dut_ctrl.force_status_opcode;
        force dut.ludp_status_data  = dut_ctrl.force_status_data;
        force dut.ludp_status_valid = dut_ctrl.force_status_valid;
    end else if (dut_ctrl.force_status_release) begin
        release dut.ludp_status_opcode;
        release dut.ludp_status_data;
        release dut.ludp_status_valid;
    end
end

initial begin
    dut_ctrl.rst = 1'b1;
    dut_ctrl.sfp0_tx_rst = 1'b1;
    dut_ctrl.sfp0_rx_rst = 1'b1;
    dut_ctrl.sfp1_tx_rst = 1'b1;
    dut_ctrl.sfp1_rx_rst = 1'b1;
end

initial begin
    ludp_env_config cfg;
    cfg = ludp_env_config::type_id::create("cfg");
    cfg.vif      = sfp0_xgmii;
    cfg.ctrl_vif = dut_ctrl;

    uvm_config_db#(ludp_env_config)::set(null, "uvm_test_top.env", "cfg", cfg);
    uvm_config_db#(virtual xgmii_if)::set(null, "uvm_test_top.env", "vif", sfp0_xgmii);
    uvm_config_db#(virtual dut_ctrl_if)::set(null, "uvm_test_top.env", "ctrl_vif", dut_ctrl);
    uvm_config_db#(virtual xgmii_if)::set(null, "uvm_test_top.v_seqr", "vif", sfp0_xgmii);
    uvm_config_db#(virtual dut_ctrl_if)::set(null, "uvm_test_top.v_seqr", "ctrl_vif", dut_ctrl);
    run_test();
end

initial begin
    repeat(TIMEOUT_CYCLES) @(posedge clk);
    $display("[%0t] ERROR: Simulation timeout!", $time);
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
