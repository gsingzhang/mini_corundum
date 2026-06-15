`timescale 1ns / 1ps

interface xgmii_if(input bit clk, input bit rst);

    bit [63:0] rxd = 64'h0707070707070707;
    bit [7:0]  rxc = 8'hff;

    wire [63:0] txd;
    wire [7:0]  txc;

    clocking drv_cb @(posedge clk);
        output rxd, rxc;
    endclocking

    clocking mon_cb @(posedge clk);
        input txd, txc;
    endclocking

    modport driver(clocking drv_cb, input rst);
    modport monitor(clocking mon_cb, input rst);

endinterface
