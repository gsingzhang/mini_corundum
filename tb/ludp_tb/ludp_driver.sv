`timescale 1ns / 1ps

import ludp_tb_pkg::*;

class ludp_driver;

    virtual xgmii_if vif;
    virtual dut_ctrl_if ctrl_vif;

    bit [7:0] frame_data [0:1519];

    function new();
    endfunction

    task send_xgmii_frame(input int len);
        int i;
        int beat;
        int lane;
        bit [63:0] d;
        bit [7:0]  c;
        bit [7:0]  xgmii_data [0:1535];
        int        xgmii_len;
        int        total_beats;
        bit [31:0] crc;
        begin
            crc = eth_crc32(frame_data, len);

            xgmii_data[0] = XGMII_START;
            for (i = 1; i < 7; i++)
                xgmii_data[i] = ETH_PRE;
            xgmii_data[7] = ETH_SFD;

            for (i = 0; i < len; i++)
                xgmii_data[8 + i] = frame_data[i];

            xgmii_data[8 + len + 0] = crc[7:0];
            xgmii_data[8 + len + 1] = crc[15:8];
            xgmii_data[8 + len + 2] = crc[23:16];
            xgmii_data[8 + len + 3] = crc[31:24];
            xgmii_data[8 + len + 4] = XGMII_TERM;

            xgmii_len = 13 + len;
            total_beats = (xgmii_len + 7) / 8;

            for (beat = 0; beat < total_beats; beat++) begin
                d = 64'h0707070707070707;
                c = 8'hff;

                for (lane = 0; lane < 8; lane++) begin
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

                @(posedge vif.clk);
                #0.1;
                vif.rxd <= d;
                vif.rxc <= c;
            end

            @(posedge vif.clk);
            #0.1;
            vif.rxd <= XGMII_IDLE_QW;
            vif.rxc <= XGMII_IDLE_CTRL;
            @(posedge vif.clk);
            #0.1;
            vif.rxd <= XGMII_IDLE_QW;
            vif.rxc <= XGMII_IDLE_CTRL;
        end
    endtask

    task send_xgmii_frame_with_err(input int len);
        int i;
        int beat;
        int lane;
        bit [63:0] d;
        bit [7:0]  c;
        bit [7:0]  xgmii_data [0:1535];
        int        xgmii_len;
        int        total_beats;
        bit [31:0] crc;
        begin
            crc = eth_crc32(frame_data, len);

            xgmii_data[0] = XGMII_START;
            for (i = 1; i < 7; i++)
                xgmii_data[i] = ETH_PRE;
            xgmii_data[7] = ETH_SFD;

            for (i = 0; i < len; i++)
                xgmii_data[8 + i] = frame_data[i];

            xgmii_data[8 + len + 0] = crc[7:0];
            xgmii_data[8 + len + 1] = crc[15:8];
            xgmii_data[8 + len + 2] = crc[23:16];
            xgmii_data[8 + len + 3] = crc[31:24];
            xgmii_data[8 + len + 4] = XGMII_ERROR;

            xgmii_len = 13 + len;
            total_beats = (xgmii_len + 7) / 8;

            for (beat = 0; beat < total_beats; beat++) begin
                d = 64'h0707070707070707;
                c = 8'hff;

                for (lane = 0; lane < 8; lane++) begin
                    i = beat * 8 + lane;
                    if (i < xgmii_len) begin
                        d[lane*8 +: 8] = xgmii_data[i];
                        if (beat == 0 && lane == 0)
                            c[lane] = 1'b1;
                        else if (xgmii_data[i] == XGMII_ERROR)
                            c[lane] = 1'b1;
                        else if (i == xgmii_len - 1)
                            c[lane] = 1'b1;
                        else
                            c[lane] = 1'b0;
                    end
                end

                @(posedge vif.clk);
                #0.1;
                vif.rxd <= d;
                vif.rxc <= c;
            end

            @(posedge vif.clk);
            #0.1;
            vif.rxd <= XGMII_IDLE_QW;
            vif.rxc <= XGMII_IDLE_CTRL;
            @(posedge vif.clk);
            #0.1;
            vif.rxd <= XGMII_IDLE_QW;
            vif.rxc <= XGMII_IDLE_CTRL;
        end
    endtask

    task send_arp_request();
        int i;
        begin
            $display("[%0t] DRV: Sending ARP request...", $time);
            frame_data[0]  = 8'hFF; frame_data[1]  = 8'hFF; frame_data[2]  = 8'hFF;
            frame_data[3]  = 8'hFF; frame_data[4]  = 8'hFF; frame_data[5]  = 8'hFF;
            frame_data[6]  = HOST_MAC[47:40]; frame_data[7]  = HOST_MAC[39:32];
            frame_data[8]  = HOST_MAC[31:24]; frame_data[9]  = HOST_MAC[23:16];
            frame_data[10] = HOST_MAC[15:8];  frame_data[11] = HOST_MAC[7:0];
            frame_data[12] = 8'h08; frame_data[13] = 8'h06;
            frame_data[14] = 8'h00; frame_data[15] = 8'h01;
            frame_data[16] = 8'h08; frame_data[17] = 8'h00;
            frame_data[18] = 8'h06; frame_data[19] = 8'h04;
            frame_data[20] = 8'h00; frame_data[21] = 8'h01;
            frame_data[22] = HOST_MAC[47:40]; frame_data[23] = HOST_MAC[39:32];
            frame_data[24] = HOST_MAC[31:24]; frame_data[25] = HOST_MAC[23:16];
            frame_data[26] = HOST_MAC[15:8];  frame_data[27] = HOST_MAC[7:0];
            frame_data[28] = HOST_IP[31:24];  frame_data[29] = HOST_IP[23:16];
            frame_data[30] = HOST_IP[15:8];   frame_data[31] = HOST_IP[7:0];
            frame_data[32] = 8'h00; frame_data[33] = 8'h00; frame_data[34] = 8'h00;
            frame_data[35] = 8'h00; frame_data[36] = 8'h00; frame_data[37] = 8'h00;
            frame_data[38] = DUT_IP[31:24];   frame_data[39] = DUT_IP[23:16];
            frame_data[40] = DUT_IP[15:8];    frame_data[41] = DUT_IP[7:0];
            for (i = 42; i < 60; i++) frame_data[i] = 8'h00;
            send_xgmii_frame(60);
        end
    endtask

    task send_arp_reply();
        int i;
        begin
            $display("[%0t] DRV: Sending ARP reply...", $time);
            frame_data[0]  = DUT_MAC[47:40]; frame_data[1]  = DUT_MAC[39:32];
            frame_data[2]  = DUT_MAC[31:24]; frame_data[3]  = DUT_MAC[23:16];
            frame_data[4]  = DUT_MAC[15:8];  frame_data[5]  = DUT_MAC[7:0];
            frame_data[6]  = HOST_MAC[47:40]; frame_data[7]  = HOST_MAC[39:32];
            frame_data[8]  = HOST_MAC[31:24]; frame_data[9]  = HOST_MAC[23:16];
            frame_data[10] = HOST_MAC[15:8];  frame_data[11] = HOST_MAC[7:0];
            frame_data[12] = 8'h08; frame_data[13] = 8'h06;
            frame_data[14] = 8'h00; frame_data[15] = 8'h01;
            frame_data[16] = 8'h08; frame_data[17] = 8'h00;
            frame_data[18] = 8'h06; frame_data[19] = 8'h04;
            frame_data[20] = 8'h00; frame_data[21] = 8'h02;
            frame_data[22] = HOST_MAC[47:40]; frame_data[23] = HOST_MAC[39:32];
            frame_data[24] = HOST_MAC[31:24]; frame_data[25] = HOST_MAC[23:16];
            frame_data[26] = HOST_MAC[15:8];  frame_data[27] = HOST_MAC[7:0];
            frame_data[28] = HOST_IP[31:24];  frame_data[29] = HOST_IP[23:16];
            frame_data[30] = HOST_IP[15:8];   frame_data[31] = HOST_IP[7:0];
            frame_data[32] = DUT_MAC[47:40];  frame_data[33] = DUT_MAC[39:32];
            frame_data[34] = DUT_MAC[31:24];  frame_data[35] = DUT_MAC[23:16];
            frame_data[36] = DUT_MAC[15:8];   frame_data[37] = DUT_MAC[7:0];
            frame_data[38] = DUT_IP[31:24];   frame_data[39] = DUT_IP[23:16];
            frame_data[40] = DUT_IP[15:8];    frame_data[41] = DUT_IP[7:0];
            for (i = 42; i < 60; i++) frame_data[i] = 8'h00;
            send_xgmii_frame(60);
        end
    endtask

    task build_ludp_packet(input bit [7:0] pkt_type, input bit [7:0] flags,
                           input bit [31:0] seq_num, input bit [15:0] opcode,
                           input bit [31:0] arg1, input bit [15:0] arg2,
                           input int payload_len);
        int i;
        int udp_len;
        int total_len;
        bit [159:0] ip_hdr;
        bit [15:0] cksum;
        begin
            udp_len = 8 + 16 + payload_len;
            total_len = 20 + udp_len;

            frame_data[0]  = DUT_MAC[47:40];  frame_data[1]  = DUT_MAC[39:32];
            frame_data[2]  = DUT_MAC[31:24];  frame_data[3]  = DUT_MAC[23:16];
            frame_data[4]  = DUT_MAC[15:8];   frame_data[5]  = DUT_MAC[7:0];
            frame_data[6]  = HOST_MAC[47:40]; frame_data[7]  = HOST_MAC[39:32];
            frame_data[8]  = HOST_MAC[31:24]; frame_data[9]  = HOST_MAC[23:16];
            frame_data[10] = HOST_MAC[15:8];  frame_data[11] = HOST_MAC[7:0];
            frame_data[12] = 8'h08; frame_data[13] = 8'h00;

            frame_data[14] = 8'h45; frame_data[15] = 8'h00;
            frame_data[16] = total_len[15:8]; frame_data[17] = total_len[7:0];
            frame_data[18] = 8'h00; frame_data[19] = 8'h01;
            frame_data[20] = 8'h00; frame_data[21] = 8'h00;
            frame_data[22] = 8'h40; frame_data[23] = 8'h11;
            frame_data[24] = 8'h00; frame_data[25] = 8'h00;
            frame_data[26] = HOST_IP[31:24]; frame_data[27] = HOST_IP[23:16];
            frame_data[28] = HOST_IP[15:8];  frame_data[29] = HOST_IP[7:0];
            frame_data[30] = DUT_IP[31:24];  frame_data[31] = DUT_IP[23:16];
            frame_data[32] = DUT_IP[15:8];   frame_data[33] = DUT_IP[7:0];

            ip_hdr = {DUT_IP, HOST_IP, 16'h0000, 16'h4011, 16'h0000, 16'h0001, total_len[15:0], 16'h4500};
            cksum = ip_checksum(ip_hdr);
            frame_data[24] = cksum[15:8];
            frame_data[25] = cksum[7:0];

            frame_data[34] = LUDP_PORT[15:8]; frame_data[35] = LUDP_PORT[7:0];
            frame_data[36] = LUDP_PORT[15:8]; frame_data[37] = LUDP_PORT[7:0];
            frame_data[38] = udp_len[15:8];  frame_data[39] = udp_len[7:0];
            frame_data[40] = 8'h00; frame_data[41] = 8'h00;

            frame_data[42] = MAGIC[7:0];   frame_data[43] = MAGIC[15:8];
            frame_data[44] = pkt_type;     frame_data[45] = flags;
            frame_data[46] = seq_num[7:0];  frame_data[47] = seq_num[15:8];
            frame_data[48] = seq_num[23:16]; frame_data[49] = seq_num[31:24];

            frame_data[50] = opcode[7:0];  frame_data[51] = opcode[15:8];
            frame_data[52] = arg1[7:0];    frame_data[53] = arg1[15:8];
            frame_data[54] = arg1[23:16];  frame_data[55] = arg1[31:24];
            frame_data[56] = arg2[7:0];    frame_data[57] = arg2[15:8];
            frame_data[58] = 8'h00;        frame_data[59] = 8'h00;

            for (i = 0; i < payload_len; i++)
                frame_data[60 + i] = 8'h00;
        end
    endtask

    task send_ludp_packet(input bit [7:0] pkt_type, input bit [7:0] flags,
                          input bit [31:0] seq_num, input bit [15:0] opcode,
                          input bit [31:0] arg1, input bit [15:0] arg2,
                          input int payload_len);
        int udp_len;
        begin
            build_ludp_packet(pkt_type, flags, seq_num, opcode, arg1, arg2, payload_len);
            udp_len = 8 + 16 + payload_len;
            send_xgmii_frame(34 + udp_len);
        end
    endtask

    task send_ludp_packet_with_tuser_err(input bit [7:0] pkt_type, input bit [7:0] flags,
                                         input bit [31:0] seq_num, input bit [15:0] opcode,
                                         input bit [31:0] arg1, input bit [15:0] arg2,
                                         input int payload_len);
        int udp_len;
        begin
            build_ludp_packet(pkt_type, flags, seq_num, opcode, arg1, arg2, payload_len);
            udp_len = 8 + 16 + payload_len;
            send_xgmii_frame_with_err(34 + udp_len);
        end
    endtask

    task send_ludp_cmd(input bit [15:0] opcode, input bit [31:0] arg1,
                       input bit [15:0] arg2, input bit [7:0] flags);
        begin
            $display("[%0t] DRV: Sending LUDP CMD: opcode=%04h arg1=%08h arg2=%04h flags=%02h",
                     $time, opcode, arg1, arg2, flags);
            send_ludp_packet(TYPE_CMD, flags, 32'h0, opcode, arg1, arg2, 0);
        end
    endtask

    task send_ludp_credit(input bit [31:0] credit);
        begin
            $display("[%0t] DRV: Sending LUDP CREDIT: credit=%08h", $time, credit);
            send_ludp_packet(TYPE_CREDIT, 8'h00, credit, 16'h0, 32'h0, 16'h0, 0);
        end
    endtask

    task send_ludp_nack(input bit [31:0] miss_seq, input bit [15:0] count);
        begin
            $display("[%0t] DRV: Sending LUDP NACK: miss_seq=%08h count=%04h", $time, miss_seq, count);
            send_ludp_packet(TYPE_NACK, 8'h00, miss_seq, count, 32'h0, 16'h0, 0);
        end
    endtask

    task send_icmp_echo_request(input bit [15:0] icmp_id, input bit [15:0] icmp_seq,
                                input int payload_len);
        int i;
        int total_len;
        bit [159:0] ip_hdr;
        bit [15:0] cksum;
        bit [15:0] icmp_cksum;
        begin
            total_len = 20 + 8 + payload_len;

            frame_data[0]  = DUT_MAC[47:40];  frame_data[1]  = DUT_MAC[39:32];
            frame_data[2]  = DUT_MAC[31:24];  frame_data[3]  = DUT_MAC[23:16];
            frame_data[4]  = DUT_MAC[15:8];   frame_data[5]  = DUT_MAC[7:0];
            frame_data[6]  = HOST_MAC[47:40]; frame_data[7]  = HOST_MAC[39:32];
            frame_data[8]  = HOST_MAC[31:24]; frame_data[9]  = HOST_MAC[23:16];
            frame_data[10] = HOST_MAC[15:8];  frame_data[11] = HOST_MAC[7:0];
            frame_data[12] = 8'h08; frame_data[13] = 8'h00;

            frame_data[14] = 8'h45; frame_data[15] = 8'h00;
            frame_data[16] = total_len[15:8]; frame_data[17] = total_len[7:0];
            frame_data[18] = 8'h00; frame_data[19] = 8'h01;
            frame_data[20] = 8'h00; frame_data[21] = 8'h00;
            frame_data[22] = 8'h40; frame_data[23] = 8'h01;
            frame_data[24] = 8'h00; frame_data[25] = 8'h00;
            frame_data[26] = HOST_IP[31:24]; frame_data[27] = HOST_IP[23:16];
            frame_data[28] = HOST_IP[15:8];  frame_data[29] = HOST_IP[7:0];
            frame_data[30] = DUT_IP[31:24];  frame_data[31] = DUT_IP[23:16];
            frame_data[32] = DUT_IP[15:8];   frame_data[33] = DUT_IP[7:0];

            ip_hdr = {DUT_IP, HOST_IP, 16'h0000, 16'h4001, 16'h0000, 16'h0001, total_len[15:0], 16'h4500};
            cksum = ip_checksum(ip_hdr);
            frame_data[24] = cksum[15:8];
            frame_data[25] = cksum[7:0];

            frame_data[34] = 8'h08;
            frame_data[35] = 8'h00;
            frame_data[36] = 8'h00; frame_data[37] = 8'h00;
            frame_data[38] = icmp_id[15:8];  frame_data[39] = icmp_id[7:0];
            frame_data[40] = icmp_seq[15:8]; frame_data[41] = icmp_seq[7:0];

            for (i = 0; i < payload_len; i++)
                frame_data[42 + i] = 8'hA5 + i[7:0];

            icmp_cksum = icmp_checksum_calc(frame_data, 34, 42 + payload_len);
            frame_data[36] = icmp_cksum[15:8];
            frame_data[37] = icmp_cksum[7:0];

            $display("[%0t] DRV: Sending ICMP Echo Request: id=%04h seq=%04h payload=%0d bytes",
                     $time, icmp_id, icmp_seq, payload_len);
            send_xgmii_frame(34 + 8 + payload_len);
        end
    endtask

    task set_payload_size(input bit [15:0] size_bytes);
        begin
            $display("[%0t] DRV: Setting test payload size to %0d bytes", $time, size_bytes);
            ctrl_vif.set_payload_size(size_bytes);
        end
    endtask

    task reset_dut(ref bit rst, ref bit sfp0_tx_rst, ref bit sfp0_rx_rst,
                   ref bit sfp1_tx_rst, ref bit sfp1_rx_rst);
        begin
            $display("[%0t] DRV: Resetting DUT...", $time);
            rst = 1;
            sfp0_tx_rst = 1; sfp0_rx_rst = 1;
            sfp1_tx_rst = 1; sfp1_rx_rst = 1;
            repeat(20) @(posedge vif.clk);
            rst = 0;
            sfp0_tx_rst = 0; sfp0_rx_rst = 0;
            sfp1_tx_rst = 0; sfp1_rx_rst = 0;
            $display("[%0t] DRV: Reset released", $time);
            repeat(600) @(posedge vif.clk);
            resolve_arp();
        end
    endtask

    task resolve_arp();
        begin
            send_arp_request();
            repeat(1000) @(posedge vif.clk);
            repeat(500) @(posedge vif.clk);
            send_arp_reply();
            repeat(1000) @(posedge vif.clk);
        end
    endtask

    task start_ludp_session(input bit [15:0] payload_size);
        begin
            set_payload_size(payload_size);
            @(posedge vif.clk);
            send_ludp_cmd(CMD_START, 32'h0, 16'h0, 8'h00);
            repeat(1000) @(posedge vif.clk);
        end
    endtask

    task stop_ludp_session();
        begin
            send_ludp_cmd(CMD_STOP, 32'h0, 16'h0, 8'h00);
            repeat(500) @(posedge vif.clk);
        end
    endtask

    task send_idle();
        begin
            @(posedge vif.clk);
            #0.1;
            vif.rxd <= XGMII_IDLE_QW;
            vif.rxc <= XGMII_IDLE_CTRL;
        end
    endtask

endclass
