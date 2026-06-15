`timescale 1ns / 1ps

package ludp_tb_pkg;

import uvm_pkg::*;
`include "uvm_macros.svh"

localparam CLK_PERIOD = 6.4;

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

localparam [15:0] CMD_START     = 16'h0001;
localparam [15:0] CMD_STOP      = 16'h0002;
localparam [15:0] CMD_READ_REG  = 16'h0010;
localparam [15:0] CMD_WRITE_REG = 16'h0011;

localparam ETH_HDR_LEN   = 14;
localparam IP_HDR_LEN    = 20;
localparam UDP_HDR_LEN   = 8;
localparam LUDP_HDR_LEN  = 16;

typedef enum int {
    FRAME_ARP_REQUEST  = 0,
    FRAME_ARP_REPLY    = 1,
    FRAME_LUDP_CMD     = 2,
    FRAME_LUDP_CREDIT  = 3,
    FRAME_LUDP_NACK    = 4,
    FRAME_LUDP_DATA    = 5,
    FRAME_LUDP_ACK     = 6,
    FRAME_LUDP_CPL     = 7,
    FRAME_ICMP_REQUEST = 8,
    FRAME_ICMP_REPLY   = 9,
    FRAME_UNKNOWN      = 10
} frame_type_e;

typedef enum int {
    CMD_ARP_REQUEST  = 0,
    CMD_ARP_REPLY    = 1,
    CMD_LUDP_CMD     = 2,
    CMD_LUDP_CREDIT  = 3,
    CMD_LUDP_NACK    = 4,
    CMD_LUDP_START   = 5,
    CMD_LUDP_STOP    = 6,
    CMD_ICMP_REQUEST = 7,
    CMD_IDLE         = 8,
    CMD_RESET        = 9
} stim_cmd_e;

function [31:0] eth_crc32(input bit [7:0] data[], input int len);
    int i, j;
    bit [31:0] crc;
    bit [7:0] byte_data;
    bit bit_in;
    begin
        crc = 32'hFFFFFFFF;
        for (i = 0; i < len; i++) begin
            byte_data = data[i];
            for (j = 0; j < 8; j++) begin
                bit_in = byte_data[j] ^ crc[0];
                crc = crc >> 1;
                if (bit_in) crc = crc ^ 32'hEDB88320;
            end
        end
        eth_crc32 = ~crc;
    end
endfunction

function [15:0] ip_checksum(input bit [159:0] header);
    int i;
    bit [31:0] sum;
    bit [15:0] word;
    begin
        sum = 0;
        for (i = 0; i < 10; i++) begin
            word = header[i*16 +: 16];
            sum = sum + word;
        end
        while (sum[31:16] != 0)
            sum = sum[15:0] + sum[31:16];
        ip_checksum = ~sum[15:0];
    end
endfunction

function [15:0] icmp_checksum_calc(input bit [7:0] data[], input int start_off, input int end_off);
    int i;
    bit [31:0] sum;
    bit [15:0] word;
    begin
        sum = 0;
        for (i = start_off; i < end_off; i += 2) begin
            if (i + 1 < end_off)
                word = {data[i], data[i+1]};
            else
                word = {data[i], 8'h00};
            sum = sum + word;
        end
        while (sum[31:16] != 0)
            sum = sum[31:16] + sum[15:0];
        icmp_checksum_calc = ~sum[15:0];
    end
endfunction

`include "ludp_tb/ludp_txn.sv"
`include "ludp_tb/ludp_rx_frame.sv"
`include "ludp_tb/ludp_env_config.sv"
`include "ludp_tb/ludp_seq_base.sv"
`include "ludp_tb/ludp_sequencer.sv"
`include "ludp_tb/ludp_driver.sv"
`include "ludp_tb/ludp_monitor.sv"
`include "ludp_tb/ludp_agent.sv"
`include "ludp_tb/ludp_scoreboard.sv"
`include "ludp_tb/ludp_coverage.sv"
`include "ludp_tb/ludp_env.sv"
`include "ludp_tb/ludp_virtual_sequencer.sv"
`include "ludp_tb/ludp_virtual_sequence_base.sv"

`include "ludp_tb/vseqs/ludp_vseq_reset_init.sv"
`include "ludp_tb/vseqs/ludp_vseq_protocol_basics.sv"
`include "ludp_tb/vseqs/ludp_vseq_cmd_lifecycle.sv"
`include "ludp_tb/vseqs/ludp_vseq_credit_flow.sv"
`include "ludp_tb/vseqs/ludp_vseq_data_integrity.sv"
`include "ludp_tb/vseqs/ludp_vseq_retransmission.sv"
`include "ludp_tb/vseqs/ludp_vseq_error_resilience.sv"
`include "ludp_tb/vseqs/ludp_vseq_internal_mechanisms.sv"
`include "ludp_tb/vseqs/ludp_vseq_coverage_enhance.sv"
`include "ludp_tb/vseqs/ludp_vseq_test_all.sv"

`include "ludp_tb/ludp_test_lib.sv"

endpackage
