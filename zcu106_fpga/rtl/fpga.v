`timescale 1ns / 1ps

module fpga (
    input  wire         clk_125mhz_p,
    input  wire         clk_125mhz_n,

    // SFP+ 0
    input  wire         sfp0_rx_p,
    input  wire         sfp0_rx_n,
    output wire         sfp0_tx_p,
    output wire         sfp0_tx_n,
    input  wire         sfp_mgt_refclk_0_p,
    input  wire         sfp_mgt_refclk_0_n,
    output wire         sfp0_tx_disable_b,

    output wire [7:0]   led
);

    wire clk_125mhz;
    IBUFGDS ibufgds_125mhz (
        .I(clk_125mhz_p),
        .IB(clk_125mhz_n),
        .O(clk_125mhz)
    );

    wire sfp_mgt_refclk_0;
    IBUFDS_GTE4 ibufds_mgt_refclk_0 (
        .I(sfp_mgt_refclk_0_p),
        .IB(sfp_mgt_refclk_0_n),
        .CEB(1'b0),
        .O(sfp_mgt_refclk_0),
        .ODIV2()
    );

    wire sfp_tx_clk;
    wire sfp_tx_rst;
    wire sfp_rx_clk;
    wire sfp_rx_rst;
    wire [63:0] sfp_txd;
    wire [7:0]  sfp_txc;
    wire [63:0] sfp_rxd;
    wire [7:0]  sfp_rxc;

    assign sfp0_tx_disable_b = 1'b1;

    wire sfp0_rx_block_lock;
    wire sfp0_rx_status;

    // Instance of GTH wrapper (assuming 1 channel)
    eth_xcvr_phy_10g_gty_wrapper #(
        .HAS_COMMON(1),
        .GT_GTH(1),
        .GT_USP(1)
    ) phy_inst (
        .xcvr_ctrl_clk(clk_125mhz),
        .xcvr_ctrl_rst(1'b0),
        
        .xcvr_gtrefclk00_in(sfp_mgt_refclk_0),

        .xcvr_txp(sfp0_tx_p),
        .xcvr_txn(sfp0_tx_n),
        .xcvr_rxp(sfp0_rx_p),
        .xcvr_rxn(sfp0_rx_n),

        .tx_clk(sfp_tx_clk),
        .tx_rst(sfp_tx_rst),
        .xgmii_txd(sfp_txd),
        .xgmii_txc(sfp_txc),

        .rx_clk(sfp_rx_clk),
        .rx_rst(sfp_rx_rst),
        .xgmii_rxd(sfp_rxd),
        .xgmii_rxc(sfp_rxc),
        
        .rx_block_lock(sfp0_rx_block_lock),
        .rx_status(sfp0_rx_status)
    );

    // Reset sync
    reg rst_sync_reg1 = 1'b1;
    reg rst_sync_reg2 = 1'b1;
    always @(posedge sfp_tx_clk) begin
        rst_sync_reg1 <= sfp_tx_rst || sfp_rx_rst;
        rst_sync_reg2 <= rst_sync_reg1;
    end

    mini_corundum_top dut (
        .clk(sfp_tx_clk),
        .rst(rst_sync_reg2),
        .xgmii_rxd(sfp_rxd),
        .xgmii_rxc(sfp_rxc),
        .xgmii_txd(sfp_txd),
        .xgmii_txc(sfp_txc)
    );

    assign led[0] = ~rst_sync_reg2;
    assign led[1] = sfp0_rx_block_lock;
    assign led[2] = sfp0_rx_status;
    assign led[7:3] = 5'd0;

endmodule
