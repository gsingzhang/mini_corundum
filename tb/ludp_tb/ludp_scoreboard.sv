`timescale 1ns / 1ps

import ludp_tb_pkg::*;

class ludp_scoreboard;

    int error_count;
    int check_count;
    int prbs_ok_count;
    int prbs_err_count;

    mailbox frame_mbx;

    function new();
        error_count   = 0;
        check_count   = 0;
        prbs_ok_count = 0;
        prbs_err_count = 0;
        frame_mbx = new();
    endfunction

    function void reset();
        error_count   = 0;
        check_count   = 0;
        prbs_ok_count = 0;
        prbs_err_count = 0;
    endfunction

    task check_ludp_response(input bit [7:0] exp_type, input bit [15:0] exp_opcode,
                             ref ludp_rx_frame frm);
        begin
            if (frm == null) begin
                $display("[%0t] SB: ERROR - No frame for response check", $time);
                error_count = error_count + 1;
                return;
            end

            check_count = check_count + 1;

            if (frm.ludp_magic !== MAGIC) begin
                $display("[%0t] SB: ERROR Magic mismatch: expected %04h, got %04h", $time, MAGIC, frm.ludp_magic);
                error_count = error_count + 1;
            end else
                $display("[%0t] SB: PASS Magic correct", $time);

            if (frm.ludp_type !== exp_type) begin
                $display("[%0t] SB: ERROR Expected type %02h, got %02h", $time, exp_type, frm.ludp_type);
                error_count = error_count + 1;
            end else
                $display("[%0t] SB: PASS Type correct", $time);

            if (frm.ludp_opcode !== exp_opcode) begin
                $display("[%0t] SB: ERROR Opcode expected %04h, got %04h", $time, exp_opcode, frm.ludp_opcode);
                error_count = error_count + 1;
            end else
                $display("[%0t] SB: PASS Opcode correct", $time);
        end
    endtask

    task check_ludp_data(input bit [31:0] exp_seq, input bit [15:0] exp_pay_len,
                         ref ludp_rx_frame frm);
        bit [15:0] exp_udp_len;
        begin
            if (frm == null) begin
                $display("[%0t] SB: ERROR - No frame for data check", $time);
                error_count = error_count + 1;
                return;
            end

            check_count = check_count + 1;

            if (frm.ludp_magic !== MAGIC) begin
                $display("[%0t] SB: ERROR Magic mismatch: expected %04h, got %04h", $time, MAGIC, frm.ludp_magic);
                error_count = error_count + 1;
            end else
                $display("[%0t] SB: PASS Magic correct", $time);

            if (frm.ludp_type !== TYPE_DATA) begin
                $display("[%0t] SB: ERROR Expected DATA type %02h, got %02h", $time, TYPE_DATA, frm.ludp_type);
                error_count = error_count + 1;
            end else
                $display("[%0t] SB: PASS DATA type correct", $time);

            if (frm.ludp_seq !== exp_seq) begin
                $display("[%0t] SB: ERROR DATA seq expected %08h, got %08h", $time, exp_seq, frm.ludp_seq);
                error_count = error_count + 1;
            end else
                $display("[%0t] SB: PASS DATA seq correct (%08h)", $time, frm.ludp_seq);

            if (exp_pay_len > 0) begin
                exp_udp_len = 8 + 16 + exp_pay_len;
                if (frm.udp_len !== exp_udp_len) begin
                    $display("[%0t] SB: ERROR UDP length mismatch: expected %0d, got %0d",
                             $time, exp_udp_len, frm.udp_len);
                    error_count = error_count + 1;
                end else
                    $display("[%0t] SB: PASS UDP length correct (%0d)", $time, frm.udp_len);
            end

            if (frm.ip_dst !== HOST_IP) begin
                $display("[%0t] SB: ERROR IP destination mismatch: expected %08h, got %08h",
                         $time, HOST_IP, frm.ip_dst);
                error_count = error_count + 1;
            end else
                $display("[%0t] SB: PASS IP destination correct (%08h)", $time, frm.ip_dst);
        end
    endtask

    task check_arp_reply(ref ludp_rx_frame frm);
        begin
            if (frm == null) begin
                $display("[%0t] SB: ERROR - No frame for ARP check", $time);
                error_count = error_count + 1;
                return;
            end

            check_count = check_count + 1;

            if (frm.eth_dst !== HOST_MAC) begin
                $display("[%0t] SB: ERROR ARP dst MAC mismatch: expected %012h, got %012h", $time, HOST_MAC, frm.eth_dst);
                error_count = error_count + 1;
            end else
                $display("[%0t] SB: PASS ARP dst MAC correct", $time);

            if (frm.eth_src !== DUT_MAC) begin
                $display("[%0t] SB: ERROR ARP src MAC mismatch: expected %012h, got %012h", $time, DUT_MAC, frm.eth_src);
                error_count = error_count + 1;
            end else
                $display("[%0t] SB: PASS ARP src MAC correct", $time);

            if (frm.eth_type !== 16'h0806) begin
                $display("[%0t] SB: ERROR ARP EtherType mismatch: expected 0806, got %04h", $time, frm.eth_type);
                error_count = error_count + 1;
            end else
                $display("[%0t] SB: PASS ARP EtherType correct", $time);

            if (frm.arp_opcode !== 16'h0002) begin
                $display("[%0t] SB: ERROR ARP opcode mismatch: expected 0002, got %04h", $time, frm.arp_opcode);
                error_count = error_count + 1;
            end else
                $display("[%0t] SB: PASS ARP opcode correct (reply)", $time);
        end
    endtask

    task check_icmp_echo_reply(input bit [15:0] exp_id, input bit [15:0] exp_seq,
                               ref ludp_rx_frame frm);
        begin
            if (frm == null) begin
                $display("[%0t] SB: ERROR - No frame for ICMP check", $time);
                error_count = error_count + 1;
                return;
            end

            check_count = check_count + 1;

            if (frm.eth_dst !== HOST_MAC) begin
                $display("[%0t] SB: ERROR ICMP dst MAC mismatch", $time);
                error_count = error_count + 1;
            end else
                $display("[%0t] SB: PASS ICMP dst MAC correct", $time);

            if (frm.eth_src !== DUT_MAC) begin
                $display("[%0t] SB: ERROR ICMP src MAC mismatch", $time);
                error_count = error_count + 1;
            end else
                $display("[%0t] SB: PASS ICMP src MAC correct", $time);

            if (frm.icmp_type !== 8'h00) begin
                $display("[%0t] SB: ERROR ICMP type mismatch: expected 00, got %02h", $time, frm.icmp_type);
                error_count = error_count + 1;
            end else
                $display("[%0t] SB: PASS ICMP type correct (echo reply)", $time);

            if (frm.icmp_id !== exp_id) begin
                $display("[%0t] SB: ERROR ICMP ID mismatch: expected %04h, got %04h", $time, exp_id, frm.icmp_id);
                error_count = error_count + 1;
            end else
                $display("[%0t] SB: PASS ICMP ID correct", $time);

            if (frm.icmp_seq !== exp_seq) begin
                $display("[%0t] SB: ERROR ICMP seq mismatch: expected %04h, got %04h", $time, exp_seq, frm.icmp_seq);
                error_count = error_count + 1;
            end else
                $display("[%0t] SB: PASS ICMP seq correct", $time);
        end
    endtask

    task check_prbs(ref ludp_rx_frame frm, output int err_count);
        begin
            if (frm == null) begin
                err_count = 1;
                return;
            end
            frm.verify_prbs(err_count);
            if (err_count == 0)
                prbs_ok_count = prbs_ok_count + 1;
            else
                prbs_err_count = prbs_err_count + 1;
        end
    endtask

    task check_ip_destination(input bit [31:0] exp_ip, ref ludp_rx_frame frm);
        begin
            if (frm == null) begin
                $display("[%0t] SB: ERROR - No frame for IP check", $time);
                error_count = error_count + 1;
                return;
            end

            if (frm.ip_dst !== exp_ip) begin
                $display("[%0t] SB: ERROR IP destination mismatch: expected %08h, got %08h", $time, exp_ip, frm.ip_dst);
                error_count = error_count + 1;
            end else
                $display("[%0t] SB: PASS IP destination correct", $time);
        end
    endtask

    task check_udp_checksum_zero(ref ludp_rx_frame frm);
        begin
            if (frm == null) begin
                $display("[%0t] SB: ERROR - No frame for UDP checksum check", $time);
                error_count = error_count + 1;
                return;
            end

            if (frm.udp_checksum !== 16'h0000) begin
                $display("[%0t] SB: ERROR UDP checksum=%04h (expected 0000)", $time, frm.udp_checksum);
                error_count = error_count + 1;
            end else
                $display("[%0t] SB: PASS UDP checksum=0", $time);
        end
    endtask

    function void report();
        $display("");
        $display("========================================");
        $display(" Scoreboard Report");
        $display("========================================");
        $display("  Checks:      %0d", check_count);
        $display("  Errors:      %0d", error_count);
        $display("  PRBS OK:     %0d", prbs_ok_count);
        $display("  PRBS ERR:    %0d", prbs_err_count);
        $display("========================================");
    endfunction

endclass
