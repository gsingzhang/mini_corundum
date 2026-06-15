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

class ludp_txn extends uvm_sequence_item;

    rand frame_type_e frame_type;
    rand stim_cmd_e   stim_cmd;

    rand bit [7:0]  pkt_type;
    rand bit [7:0]  flags;
    rand bit [31:0] seq_num;
    rand bit [15:0] opcode;
    rand bit [31:0] arg1;
    rand bit [15:0] arg2;
    rand int        payload_len;
    rand bit [7:0]  payload[];

    rand bit [47:0] eth_dst;
    rand bit [47:0] eth_src;

    rand bit [15:0] icmp_id;
    rand bit [15:0] icmp_seq;

    rand bit tuser_err;

    rand bit [15:0] payload_size;
    rand bit [31:0] credit;
    rand bit [31:0] nack_seq;
    rand bit [15:0] nack_count;

    constraint pkt_type_c {
        pkt_type inside {TYPE_DATA, TYPE_CMD, TYPE_NACK, TYPE_CMD_ACK, TYPE_CMD_CPL, TYPE_CREDIT};
    }

    constraint payload_len_c {
        payload_len >= 0;
        payload_len <= 8960;
        payload_len % 8 == 0;
    }

    constraint payload_size_c {
        payload_size inside {16, 32, 64, 128, 256, 512, 1024, 2048, 4096, 8960};
    }

    constraint credit_c {
        credit inside {[1:32]};
    }

    `uvm_object_utils_begin(ludp_txn)
        `uvm_field_enum(frame_type_e, frame_type, UVM_DEFAULT)
        `uvm_field_enum(stim_cmd_e, stim_cmd, UVM_DEFAULT)
        `uvm_field_int(pkt_type, UVM_DEFAULT)
        `uvm_field_int(flags, UVM_DEFAULT)
        `uvm_field_int(seq_num, UVM_DEFAULT)
        `uvm_field_int(opcode, UVM_DEFAULT)
        `uvm_field_int(arg1, UVM_DEFAULT)
        `uvm_field_int(arg2, UVM_DEFAULT)
        `uvm_field_int(payload_len, UVM_DEFAULT)
        `uvm_field_int(payload_size, UVM_DEFAULT)
        `uvm_field_int(credit, UVM_DEFAULT)
        `uvm_field_int(nack_seq, UVM_DEFAULT)
        `uvm_field_int(nack_count, UVM_DEFAULT)
        `uvm_field_int(tuser_err, UVM_DEFAULT)
    `uvm_object_utils_end

    function new(string name = "ludp_txn");
        super.new(name);
        frame_type = FRAME_UNKNOWN;
        stim_cmd   = CMD_IDLE;
        pkt_type   = TYPE_CMD;
        flags      = 8'h00;
        seq_num    = 32'h0;
        opcode     = CMD_START;
        arg1       = 32'h0;
        arg2       = 16'h0;
        payload_len = 0;
        eth_dst    = DUT_MAC;
        eth_src    = HOST_MAC;
        tuser_err  = 0;
        payload_size = 64;
        credit     = 1;
        nack_seq   = 32'h0;
        nack_count = 16'h1;
    endfunction

    function void set_cmd(input bit [15:0] op, input bit [31:0] a1,
                          input bit [15:0] a2, input bit [7:0] fl);
        stim_cmd   = CMD_LUDP_CMD;
        frame_type = FRAME_LUDP_CMD;
        pkt_type   = TYPE_CMD;
        opcode     = op;
        arg1       = a1;
        arg2       = a2;
        flags      = fl;
        payload_len = 0;
    endfunction

    function void set_credit(input bit [31:0] cr);
        stim_cmd   = CMD_LUDP_CREDIT;
        frame_type = FRAME_LUDP_CREDIT;
        pkt_type   = TYPE_CREDIT;
        seq_num    = cr;
        opcode     = 16'h0;
        arg1       = 32'h0;
        arg2       = 16'h0;
        flags      = 8'h00;
        payload_len = 0;
    endfunction

    function void set_nack(input bit [31:0] miss_seq, input bit [15:0] count);
        stim_cmd   = CMD_LUDP_NACK;
        frame_type = FRAME_LUDP_NACK;
        pkt_type   = TYPE_NACK;
        seq_num    = miss_seq;
        opcode     = count;
        arg1       = 32'h0;
        arg2       = 16'h0;
        flags      = 8'h00;
        payload_len = 0;
    endfunction

    function void set_start(input bit [15:0] psize);
        stim_cmd     = CMD_LUDP_START;
        payload_size = psize;
    endfunction

    function void set_stop();
        stim_cmd = CMD_LUDP_STOP;
    endfunction

endclass

class ludp_rx_frame extends uvm_sequence_item;

    bit [63:0] raw_data [0:2047];
    bit [7:0]  raw_ctrl [0:2047];
    int        raw_len;

    bit [47:0] eth_dst;
    bit [47:0] eth_src;
    bit [15:0] eth_type;

    bit [31:0] ip_src;
    bit [31:0] ip_dst;
    bit [7:0]  ip_proto;
    bit [15:0] ip_len;

    bit [15:0] udp_src_port;
    bit [15:0] udp_dst_port;
    bit [15:0] udp_len;
    bit [15:0] udp_checksum;

    bit [15:0] ludp_magic;
    bit [7:0]  ludp_type;
    bit [7:0]  ludp_flags;
    bit [31:0] ludp_seq;
    bit [15:0] ludp_opcode;
    bit [31:0] ludp_arg1;
    bit [15:0] ludp_arg2;
    bit [15:0] ludp_pay_len;

    bit [7:0]  ludp_payload [];
    int        ludp_payload_beats;

    bit [7:0]  icmp_type;
    bit [7:0]  icmp_code;
    bit [15:0] icmp_id;
    bit [15:0] icmp_seq;

    bit [15:0] arp_opcode;

    frame_type_e frame_type;

    `uvm_object_utils_begin(ludp_rx_frame)
        `uvm_field_enum(frame_type_e, frame_type, UVM_DEFAULT)
        `uvm_field_int(eth_type, UVM_DEFAULT)
        `uvm_field_int(ludp_type, UVM_DEFAULT)
        `uvm_field_int(ludp_seq, UVM_DEFAULT)
        `uvm_field_int(ludp_opcode, UVM_DEFAULT)
        `uvm_field_int(ludp_pay_len, UVM_DEFAULT)
    `uvm_object_utils_end

    function new(string name = "ludp_rx_frame");
        super.new(name);
        raw_len = 0;
        frame_type = FRAME_UNKNOWN;
    endfunction

    function bit [7:0] get_byte(input int pos);
        int beat;
        int lane;
        int actual_pos;
        actual_pos = pos + 8;
        beat = actual_pos / 8;
        lane = actual_pos % 8;
        if (beat < raw_len)
            return raw_data[beat][lane*8 +: 8];
        else
            return 8'h00;
    endfunction

    function void parse();
        if (raw_len < 3) begin
            return;
        end

        eth_dst  = {get_byte(0), get_byte(1), get_byte(2),
                    get_byte(3), get_byte(4), get_byte(5)};
        eth_src  = {get_byte(6), get_byte(7), get_byte(8),
                    get_byte(9), get_byte(10), get_byte(11)};
        eth_type = {get_byte(12), get_byte(13)};

        if (eth_type == 16'h0806) begin
            arp_opcode = {get_byte(20), get_byte(21)};
            if (arp_opcode == 16'h0001)
                frame_type = FRAME_ARP_REQUEST;
            else if (arp_opcode == 16'h0002)
                frame_type = FRAME_ARP_REPLY;
            return;
        end

        if (eth_type == 16'h0800) begin
            ip_proto = get_byte(23);
            ip_src   = {get_byte(26), get_byte(27), get_byte(28), get_byte(29)};
            ip_dst   = {get_byte(30), get_byte(31), get_byte(32), get_byte(33)};
            ip_len   = {get_byte(16), get_byte(17)};

            if (ip_proto == 8'h01) begin
                icmp_type = get_byte(34);
                icmp_code = get_byte(35);
                icmp_id   = {get_byte(38), get_byte(39)};
                icmp_seq  = {get_byte(40), get_byte(41)};
                if (icmp_type == 8'h00)
                    frame_type = FRAME_ICMP_REPLY;
                else if (icmp_type == 8'h08)
                    frame_type = FRAME_ICMP_REQUEST;
                return;
            end

            if (ip_proto == 8'h11) begin
                udp_src_port = {get_byte(34), get_byte(35)};
                udp_dst_port = {get_byte(36), get_byte(37)};
                udp_len      = {get_byte(38), get_byte(39)};
                udp_checksum = {get_byte(40), get_byte(41)};

                ludp_magic   = {get_byte(43), get_byte(42)};
                ludp_type    = get_byte(44);
                ludp_flags   = get_byte(45);
                ludp_seq     = {get_byte(49), get_byte(48), get_byte(47), get_byte(46)};
                ludp_opcode  = {get_byte(51), get_byte(50)};
                ludp_arg1    = {get_byte(55), get_byte(54), get_byte(53), get_byte(52)};
                ludp_arg2    = {get_byte(57), get_byte(56)};
                ludp_pay_len = {get_byte(51), get_byte(50)};

                case (ludp_type)
                    TYPE_DATA: begin
                        frame_type = FRAME_LUDP_DATA;
                        ludp_pay_len = ludp_arg2;
                        ludp_payload_beats = ludp_pay_len / 8;
                    end
                    TYPE_CMD_ACK: frame_type = FRAME_LUDP_ACK;
                    TYPE_CMD_CPL: frame_type = FRAME_LUDP_CPL;
                    TYPE_CMD:     frame_type = FRAME_LUDP_CMD;
                    TYPE_CREDIT:  frame_type = FRAME_LUDP_CREDIT;
                    TYPE_NACK:    frame_type = FRAME_LUDP_NACK;
                    default:      frame_type = FRAME_UNKNOWN;
                endcase
            end
        end
    endfunction

    function bit verify_prbs(output int err_count);
        int num_beats;
        int beat_idx;
        bit [63:0] payload_beat;
        int byte_offset;
        bit [15:0] rx_pkt_idx;
        bit [15:0] rx_beat_idx;
        bit [31:0] rx_marker;

        err_count = 0;
        if (frame_type != FRAME_LUDP_DATA) begin
            err_count = 1;
            return 0;
        end

        num_beats = ludp_pay_len / 8;
        for (beat_idx = 0; beat_idx < num_beats; beat_idx++) begin
            byte_offset = 58 + beat_idx * 8;
            payload_beat[63:56] = get_byte(byte_offset + 7);
            payload_beat[55:48] = get_byte(byte_offset + 6);
            payload_beat[47:40] = get_byte(byte_offset + 5);
            payload_beat[39:32] = get_byte(byte_offset + 4);
            payload_beat[31:24] = get_byte(byte_offset + 3);
            payload_beat[23:16] = get_byte(byte_offset + 2);
            payload_beat[15:8]  = get_byte(byte_offset + 1);
            payload_beat[7:0]   = get_byte(byte_offset);

            rx_marker   = payload_beat[31:0];
            rx_beat_idx = payload_beat[47:32];
            rx_pkt_idx  = payload_beat[63:48];

            if (rx_marker !== 32'hA5A5A5A5 ||
                rx_pkt_idx !== ludp_seq[15:0] ||
                rx_beat_idx !== beat_idx[15:0])
                err_count++;
        end

        return (err_count == 0);
    endfunction

endclass

class ludp_env_config extends uvm_object;

    virtual xgmii_if    vif;
    virtual dut_ctrl_if ctrl_vif;
    bit                 has_scoreboard = 1;
    bit                 has_coverage   = 1;
    bit                 is_active      = UVM_ACTIVE;

    `uvm_object_utils(ludp_env_config)

    function new(string name = "ludp_env_config");
        super.new(name);
    endfunction

endclass

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

`include "ludp_tb/ludp_sequencer.sv"
`include "ludp_tb/ludp_driver.sv"
`include "ludp_tb/ludp_monitor.sv"
`include "ludp_tb/ludp_agent.sv"
`include "ludp_tb/ludp_scoreboard.sv"
`include "ludp_tb/ludp_coverage.sv"
`include "ludp_tb/ludp_env.sv"
`include "ludp_tb/ludp_virtual_sequencer.sv"
`include "ludp_tb/ludp_virtual_sequences.sv"
`include "ludp_tb/ludp_test_lib.sv"

endpackage
