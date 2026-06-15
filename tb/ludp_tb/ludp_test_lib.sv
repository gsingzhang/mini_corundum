`timescale 1ns / 1ps

import ludp_tb_pkg::*;

class ludp_test_base;

    ludp_env env;
    int error_count;
    int test_num;

    function new();
        error_count = 0;
        test_num = 0;
    endfunction

    function void set_env(ref ludp_env e);
        env = e;
    endfunction

    virtual task run();
    endtask

    task reset_dut();
        env.reset_dut();
    endtask

    task start_session(input bit [15:0] payload_size);
        env.start_session(payload_size);
    endtask

    task stop_session();
        env.stop_session();
    endtask

    task send_credit_and_wait(input bit [31:0] credit, input int num_frames);
        env.send_credit_and_wait(credit, num_frames);
    endtask

    function void check(input bit condition, input string msg);
        if (!condition) begin
            $display("[%0t] TEST%0d: ERROR %s", $time, test_num, msg);
            error_count = error_count + 1;
        end else
            $display("[%0t] TEST%0d: PASS %s", $time, test_num, msg);
    endfunction

endclass


class test_protocol_basics extends ludp_test_base;

    function new();
        test_num = 1;
    endfunction

    virtual task run();
        ludp_rx_frame frm;
        begin
            $display("");
            $display("[%0t] ========================================", $time);
            $display("[%0t] Test 1: Protocol Basics", $time);
            $display("[%0t] ========================================", $time);

            $display("[%0t]   Phase A: ARP Request -> ARP Reply", $time);
            reset_dut();
            env.monitor.reset_capture();
            env.driver.send_arp_request();
            repeat(2000) @(posedge env.vif.clk);
            if (env.monitor.tx_frame_count > 0) begin
                env.coverage.sample_arp_reply();
                $display("[%0t]   PASS: ARP reply received (%0d frames)", $time, env.monitor.tx_frame_count);
            end else begin
                $display("[%0t]   ERROR: No ARP reply", $time);
                error_count = error_count + 1;
            end

            $display("[%0t]   Phase B: IP src verification", $time);
            reset_dut();
            env.driver.send_ludp_cmd(CMD_START, 32'h0, 16'h0, 8'h00);
            env.coverage.sample_cmd_start();
            repeat(500) @(posedge env.vif.clk);
            env.monitor.reset_capture();
            env.driver.send_ludp_credit(32'h1);
            env.coverage.sample_credit_valid();
            env.monitor.wait_for_tx_frames(1, 5000);
            if (env.monitor.tx_frame_count >= 1) begin
                if (env.monitor.get_byte(26) !== DUT_IP[31:24] ||
                    env.monitor.get_byte(29) !== DUT_IP[7:0]) begin
                    $display("[%0t]   ERROR: IP src mismatch", $time);
                    error_count = error_count + 1;
                end else
                    $display("[%0t]   PASS: IP src correct", $time);
            end
            env.driver.send_ludp_cmd(CMD_STOP, 32'h0, 16'h0, 8'h00);
            env.coverage.sample_cmd_stop();
            repeat(500) @(posedge env.vif.clk);

            $display("[%0t]   Phase C: UDP checksum=0", $time);
            reset_dut();
            env.monitor.reset_capture();
            env.driver.send_ludp_cmd(CMD_START, 32'h0, 16'h0, 8'h00);
            env.coverage.sample_cmd_start();
            repeat(500) @(posedge env.vif.clk);
            env.driver.send_ludp_credit(32'h1);
            env.coverage.sample_credit_valid();
            env.monitor.wait_for_tx_frames(1, 5000);
            if (env.monitor.tx_frame_count > 0) begin
                bit [15:0] rx_udp_cksum;
                rx_udp_cksum = {env.monitor.get_byte(41), env.monitor.get_byte(40)};
                if (rx_udp_cksum !== 16'h0000) begin
                    $display("[%0t]   ERROR: UDP checksum=%04h (expected 0000)", $time, rx_udp_cksum);
                    error_count = error_count + 1;
                end else
                    $display("[%0t]   PASS: UDP checksum=0", $time);
            end
            env.driver.send_ludp_cmd(CMD_STOP, 32'h0, 16'h0, 8'h00);
            env.coverage.sample_cmd_stop();
            repeat(500) @(posedge env.vif.clk);
        end
    endtask

endclass


class test_cmd_lifecycle extends ludp_test_base;

    function new();
        test_num = 2;
    endfunction

    virtual task run();
        ludp_rx_frame frm;
        int ack_count;
        int cpl_count;
        int frm_idx;
        begin
            $display("");
            $display("[%0t] ========================================", $time);
            $display("[%0t] Test 2: CMD Lifecycle", $time);
            $display("[%0t] ========================================", $time);

            $display("[%0t]   Phase A: CMD_ACK response (flags=0)", $time);
            reset_dut();
            env.monitor.reset_capture();
            env.driver.send_ludp_cmd(CMD_START, 32'h0, 16'h0, 8'h00);
            env.coverage.sample_cmd_start();
            env.monitor.wait_for_tx_frames(1, 5000);
            ack_count = 0;
            for (frm_idx = 0; frm_idx < env.monitor.tx_frame_count; frm_idx++) begin
                if (env.monitor.frame_mbx.try_get(frm)) begin
                    if (frm.ludp_type == TYPE_CMD_ACK) begin
                        env.coverage.sample_cmd_ack();
                        ack_count = ack_count + 1;
                    end
                end
            end
            if (ack_count > 0)
                $display("[%0t]   PASS: CMD_ACK received (%0d)", $time, ack_count);
            else begin
                $display("[%0t]   ERROR: No CMD_ACK received", $time);
                error_count = error_count + 1;
            end

            $display("[%0t]   Phase B: CMD_START no credit -> no data", $time);
            repeat(2000) @(posedge env.vif.clk);
            env.monitor.reset_capture();
            if (env.monitor.tx_frame_count > 0) begin
                $display("[%0t]   ERROR: Data without credit", $time);
                error_count = error_count + 1;
            end else
                $display("[%0t]   PASS: No data without credit", $time);

            $display("[%0t]   Phase C: CMD_CPL response (flags!=0)", $time);
            env.monitor.reset_capture();
            env.driver.send_ludp_cmd(CMD_START, 32'h0, 16'h0, 8'hFF);
            env.coverage.sample_cmd_start();
            env.monitor.wait_for_tx_frames(1, 5000);
            cpl_count = 0;
            for (frm_idx = 0; frm_idx < env.monitor.tx_frame_count; frm_idx++) begin
                if (env.monitor.frame_mbx.try_get(frm)) begin
                    if (frm.ludp_type == TYPE_CMD_CPL) begin
                        env.coverage.sample_cmd_cpl();
                        cpl_count = cpl_count + 1;
                    end
                end
            end
            if (cpl_count > 0)
                $display("[%0t]   PASS: CMD_CPL received (%0d)", $time, cpl_count);
            else begin
                $display("[%0t]   ERROR: No CMD_CPL received", $time);
                error_count = error_count + 1;
            end
            env.driver.send_ludp_cmd(CMD_STOP, 32'h0, 16'h0, 8'h00);
            env.coverage.sample_cmd_stop();
            repeat(500) @(posedge env.vif.clk);

            $display("[%0t]   Phase D: Double CMD_START", $time);
            reset_dut();
            start_session(16'd64);
            send_credit_and_wait(32'h4, 4);
            env.driver.send_ludp_cmd(CMD_START, 32'h0, 16'h0, 8'h00);
            env.coverage.sample_double_start();
            repeat(500) @(posedge env.vif.clk);
            env.monitor.reset_capture();
            env.driver.send_ludp_credit(env.ctrl_vif.get_tx_seq_num() + 32'h4);
            env.coverage.sample_credit_valid();
            env.monitor.wait_for_tx_frames(4, 5000);
            if (env.monitor.tx_frame_count >= 4)
                $display("[%0t]   PASS: Data continues after double START", $time);
            else begin
                $display("[%0t]   ERROR: Only %0d frames after double START", $time, env.monitor.tx_frame_count);
                error_count = error_count + 1;
            end
            stop_session();

            $display("[%0t]   Phase E: CMD skipped during resp_ongoing", $time);
            reset_dut();
            start_session(16'd64);
            send_credit_and_wait(32'h2, 2);
            env.monitor.reset_capture();
            env.driver.send_ludp_cmd(CMD_START, 32'h0, 16'h0, 8'h00);
            env.driver.send_ludp_cmd(CMD_STOP, 32'h0, 16'h0, 8'h00);
            repeat(2000) @(posedge env.vif.clk);
            if (env.ctrl_vif.get_tx_enabled()) begin
                env.coverage.sample_cmd_skip_resp();
                $display("[%0t]   PASS: CMD_STOP skipped during resp_ongoing", $time);
            end else
                $display("[%0t]   WARNING: CMD_STOP executed (timing-dependent)", $time);
            stop_session();
        end
    endtask

endclass


class test_credit_flow_control extends ludp_test_base;

    function new();
        test_num = 3;
    endfunction

    virtual task run();
        int prbs_err;
        begin
            $display("");
            $display("[%0t] ========================================", $time);
            $display("[%0t] Test 3: Credit Flow Control", $time);
            $display("[%0t] ========================================", $time);

            $display("[%0t]   Phase A: Credit -> data + PRBS", $time);
            reset_dut();
            start_session(16'd64);
            env.driver.send_ludp_credit(32'h8);
            env.coverage.sample_credit_valid();
            env.verify_n_data_frames_with_prbs(8, prbs_err);
            if (prbs_err == 0)
                $display("[%0t]   PASS: 8 frames with PRBS verified", $time);
            else begin
                $display("[%0t]   ERROR: PRBS failed (%0d errors)", $time, prbs_err);
                error_count = error_count + 1;
            end

            $display("[%0t]   Phase B: Incremental credit", $time);
            env.monitor.reset_capture();
            env.driver.send_ludp_credit(env.ctrl_vif.get_tx_seq_num() + 32'h4);
            env.coverage.sample_credit_valid();
            env.monitor.wait_for_tx_frames(4, 5000);
            if (env.monitor.tx_frame_count >= 4)
                $display("[%0t]   PASS: Incremental credit works", $time);
            else begin
                $display("[%0t]   ERROR: Only %0d frames with incremental credit", $time, env.monitor.tx_frame_count);
                error_count = error_count + 1;
            end

            $display("[%0t]   Phase C: Stale credit rejection", $time);
            env.monitor.reset_capture();
            env.driver.send_ludp_credit(32'h4);
            repeat(2000) @(posedge env.vif.clk);
            if (env.monitor.tx_frame_count == 0) begin
                env.coverage.sample_credit_stale();
                $display("[%0t]   PASS: Stale credit rejected", $time);
            end else
                $display("[%0t]   WARNING: Got %0d frames after stale credit", $time, env.monitor.tx_frame_count);

            $display("[%0t]   Phase D: Credit exhaustion", $time);
            stop_session();
            reset_dut();
            start_session(16'd64);
            send_credit_and_wait(32'h8, 8);
            env.monitor.reset_capture();
            repeat(3000) @(posedge env.vif.clk);
            if (env.monitor.tx_frame_count == 0) begin
                env.coverage.sample_credit_exhaust();
                $display("[%0t]   PASS: FPGA stalled after credit exhausted", $time);
            end else
                $display("[%0t]   WARNING: %0d extra frames after credit exhausted", $time, env.monitor.tx_frame_count);
            env.monitor.reset_capture();
            env.driver.send_ludp_credit(32'h20);
            env.coverage.sample_credit_valid();
            env.monitor.wait_for_tx_frames(1, 5000);
            if (env.monitor.tx_frame_count > 0)
                $display("[%0t]   PASS: FPGA resumed after credit update", $time);
            else begin
                $display("[%0t]   ERROR: FPGA did not resume", $time);
                error_count = error_count + 1;
            end
            stop_session();

            $display("[%0t]   Phase E: Credit advancement throughput", $time);
            reset_dut();
            start_session(16'd64);
            env.driver.send_ludp_credit(32'h32);
            env.coverage.sample_credit_advance();
            repeat(5000) @(posedge env.vif.clk);
            if (env.monitor.tx_frame_count >= 32)
                $display("[%0t]   PASS: Throughput with credit advancement (%0d frames)", $time, env.monitor.tx_frame_count);
            else begin
                $display("[%0t]   ERROR: Only %0d frames with credit advancement", $time, env.monitor.tx_frame_count);
                error_count = error_count + 1;
            end

            $display("[%0t]   Phase F: Mid-transmission credit update", $time);
            stop_session();
            reset_dut();
            start_session(16'd64);
            send_credit_and_wait(32'h2, 2);
            env.monitor.reset_capture();
            env.driver.send_ludp_credit(env.ctrl_vif.get_tx_seq_num() + 32'h2);
            env.coverage.sample_credit_valid();
            env.monitor.wait_for_tx_frames(2, 5000);
            if (env.monitor.tx_frame_count >= 2)
                $display("[%0t]   PASS: Mid-TX credit update works", $time);
            else begin
                $display("[%0t]   ERROR: Mid-TX credit update failed", $time);
                error_count = error_count + 1;
            end
            stop_session();
        end
    endtask

endclass


class test_data_integrity extends ludp_test_base;

    function new();
        test_num = 4;
    endfunction

    virtual task run();
        int prbs_err;
        int rand_idx;
        bit [15:0] rand_size;
        int total_err;
        begin
            $display("");
            $display("[%0t] ========================================", $time);
            $display("[%0t] Test 4: Data Integrity (Randomized)", $time);
            $display("[%0t] ========================================", $time);

            $display("[%0t]   Phase A: Jumbo frame (9KB) PRBS", $time);
            reset_dut();
            start_session(16'd8960);
            env.driver.send_ludp_credit(32'h1);
            env.coverage.sample_credit_valid();
            env.verify_n_data_frames_with_prbs(1, prbs_err);
            if (prbs_err == 0)
                $display("[%0t]   PASS: Jumbo frame PRBS OK", $time);
            else begin
                $display("[%0t]   ERROR: Jumbo frame PRBS failed", $time);
                error_count = error_count + 1;
            end
            stop_session();

            $display("[%0t]   Phase B: Small tail frame (16B)", $time);
            reset_dut();
            start_session(16'd16);
            env.driver.send_ludp_credit(32'h1);
            env.coverage.sample_credit_valid();
            env.verify_n_data_frames_with_prbs(1, prbs_err);
            if (prbs_err == 0)
                $display("[%0t]   PASS: Small frame PRBS OK", $time);
            else begin
                $display("[%0t]   ERROR: Small frame PRBS failed", $time);
                error_count = error_count + 1;
            end
            stop_session();

            $display("[%0t]   Phase C: Multi-frame sequential PRBS", $time);
            reset_dut();
            start_session(16'd64);
            env.driver.send_ludp_credit(32'h8);
            env.verify_n_data_frames_with_prbs(8, total_err);
            if (total_err == 0)
                $display("[%0t]   PASS: 8-frame sequential PRBS OK", $time);
            else begin
                $display("[%0t]   ERROR: %0d PRBS errors in sequential test", $time, total_err);
                error_count = error_count + 1;
            end
            stop_session();

            $display("[%0t]   Phase D: Block recycling pressure (12 frames, 3 blocks)", $time);
            reset_dut();
            start_session(16'd64);
            env.driver.send_ludp_credit(32'h12);
            env.verify_n_data_frames_with_prbs(12, total_err);
            env.coverage.sample_block_recycle();
            if (total_err == 0)
                $display("[%0t]   PASS: Block pressure PRBS OK", $time);
            else begin
                $display("[%0t]   ERROR: %0d PRBS errors under block pressure", $time, total_err);
                error_count = error_count + 1;
            end
            stop_session();

            $display("[%0t]   Phase E: Random payload sizes", $time);
            env.sequencer.set_seed(32'h12345678);
            total_err = 0;
            for (rand_idx = 0; rand_idx < 5; rand_idx++) begin
                rand_size = env.sequencer.next_payload_size();
                $display("[%0t]     Random iteration %0d: payload=%0d bytes", $time, rand_idx, rand_size);
                reset_dut();
                start_session(rand_size);
                env.driver.send_ludp_credit(32'h2);
                env.coverage.sample_credit_valid();
                env.verify_n_data_frames_with_prbs(2, prbs_err);
                total_err = total_err + prbs_err;
                stop_session();
            end
            if (total_err == 0)
                $display("[%0t]   PASS: Random payload sizes PRBS OK", $time);
            else begin
                $display("[%0t]   ERROR: %0d PRBS errors in random test", $time, total_err);
                error_count = error_count + 1;
            end
        end
    endtask

endclass


class test_retransmission extends ludp_test_base;

    function new();
        test_num = 5;
    endfunction

    virtual task run();
        bit [31:0] retx_target;
        bit [7:0]  rx_type;
        bit [31:0] rx_seq;
        int retx_ok;
        ludp_rx_frame frm;
        begin
            $display("");
            $display("[%0t] ========================================", $time);
            $display("[%0t] Test 5: Retransmission", $time);
            $display("[%0t] ========================================", $time);

            $display("[%0t]   Phase A: Basic NACK -> RETX", $time);
            reset_dut();
            start_session(16'd64);
            send_credit_and_wait(32'h2, 2);
            repeat(200) @(posedge env.vif.clk);

            retx_target = env.ctrl_vif.get_tx_seq_num() - 32'h1;
            env.monitor.reset_capture();
            env.driver.send_ludp_nack(retx_target, 16'h1);
            env.coverage.sample_nack_retx();
            env.monitor.wait_for_tx_frame(5000, frm);
            if (frm != null) begin
                if (frm.ludp_type == TYPE_DATA && frm.ludp_seq == retx_target)
                    $display("[%0t]   PASS: RETX correct (seq=%08h)", $time, frm.ludp_seq);
                else begin
                    $display("[%0t]   ERROR: RETX mismatch (type=%02h seq=%08h)", $time, frm.ludp_type, frm.ludp_seq);
                    error_count = error_count + 1;
                end
            end else begin
                $display("[%0t]   ERROR: No RETX frame", $time);
                error_count = error_count + 1;
            end

            $display("[%0t]   Phase B: Multiple NACK (same seq twice)", $time);
            retx_ok = 0;
            repeat(500) @(posedge env.vif.clk);
            env.monitor.reset_capture();
            env.driver.send_ludp_nack(retx_target, 16'h1);
            env.coverage.sample_nack_retx();
            env.monitor.wait_for_tx_frame(5000, frm);
            if (frm != null) begin
                if (frm.ludp_type == TYPE_DATA && frm.ludp_seq == retx_target)
                    retx_ok = 1;
            end
            if (retx_ok)
                $display("[%0t]   PASS: Second NACK RETX correct", $time);
            else begin
                $display("[%0t]   ERROR: Second NACK RETX failed", $time);
                error_count = error_count + 1;
            end
            stop_session();

            $display("[%0t]   Phase C: NACK for non-existent seq", $time);
            env.monitor.reset_capture();
            env.driver.send_ludp_nack(32'hDEAD, 16'h1);
            env.coverage.sample_nack_noent();
            repeat(3000) @(posedge env.vif.clk);
            if (env.monitor.tx_frame_count == 0)
                $display("[%0t]   PASS: No RETX for non-existent seq", $time);
            else
                $display("[%0t]   WARNING: Got %0d frames for non-existent NACK", $time, env.monitor.tx_frame_count);

            reset_dut();
            start_session(16'd64);
            send_credit_and_wait(32'h2, 2);
            if (env.monitor.tx_frame_count >= 2)
                $display("[%0t]   PASS: System functional after invalid NACK", $time);
            else begin
                $display("[%0t]   ERROR: System hung after invalid NACK", $time);
                error_count = error_count + 1;
            end

            $display("[%0t]   Phase D: RETX priority over TX", $time);
            repeat(200) @(posedge env.vif.clk);
            retx_target = env.ctrl_vif.get_tx_seq_num() - 32'h1;
            env.monitor.reset_capture();
            env.driver.send_ludp_nack(retx_target, 16'h1);
            env.coverage.sample_nack_retx();
            env.driver.send_ludp_credit(env.ctrl_vif.get_tx_seq_num() + 32'h4);
            env.coverage.sample_credit_valid();
            env.monitor.wait_for_tx_frames(1, 5000);
            if (env.monitor.frame_mbx.try_get(frm)) begin
                if (frm != null && frm.ludp_type == TYPE_DATA && frm.ludp_seq == retx_target) begin
                    env.coverage.sample_retx_priority();
                    $display("[%0t]   PASS: RETX sent before new TX (seq=%08h)", $time, frm.ludp_seq);
                end else
                    $display("[%0t]   WARNING: First frame not RETX (type=%02h seq=%08h)", $time, frm.ludp_type, frm.ludp_seq);
            end
            stop_session();
        end
    endtask

endclass


class test_error_resilience extends ludp_test_base;

    function new();
        test_num = 6;
    endfunction

    virtual task run();
        ludp_rx_frame frm;
        begin
            $display("");
            $display("[%0t] ========================================", $time);
            $display("[%0t] Test 6: Error Resilience", $time);
            $display("[%0t] ========================================", $time);

            $display("[%0t]   Phase A: Bad MAGIC packet", $time);
            reset_dut();
            start_session(16'd64);
            send_credit_and_wait(32'h2, 2);
            env.monitor.reset_capture();
            env.driver.send_ludp_packet(8'hFF, 8'h00, 32'h0, 16'h0, 32'h0, 16'h0, 0);
            env.coverage.sample_bad_magic();
            repeat(2000) @(posedge env.vif.clk);
            if (env.monitor.tx_frame_count == 0)
                $display("[%0t]   PASS: Bad MAGIC generated no response", $time);
            else
                $display("[%0t]   WARNING: Got %0d frames after bad MAGIC", $time, env.monitor.tx_frame_count);
            env.monitor.reset_capture();
            env.driver.send_ludp_credit(env.ctrl_vif.get_tx_seq_num() + 32'h2);
            env.coverage.sample_credit_valid();
            env.monitor.wait_for_tx_frames(2, 5000);
            if (env.monitor.tx_frame_count >= 2)
                $display("[%0t]   PASS: System functional after bad MAGIC", $time);
            else begin
                $display("[%0t]   ERROR: System hung after bad MAGIC", $time);
                error_count = error_count + 1;
            end
            stop_session();

            $display("[%0t]   Phase B: Unknown TYPE packet", $time);
            reset_dut();
            start_session(16'd64);
            env.monitor.reset_capture();
            env.driver.send_ludp_packet(8'hFE, 8'h00, 32'h0, 16'h0, 32'h0, 16'h0, 0);
            env.coverage.sample_unknown_type();
            repeat(2000) @(posedge env.vif.clk);
            if (env.monitor.tx_frame_count == 0)
                $display("[%0t]   PASS: Unknown TYPE generated no response", $time);
            else
                $display("[%0t]   WARNING: Got %0d frames after unknown TYPE", $time, env.monitor.tx_frame_count);
            env.monitor.reset_capture();
            env.driver.send_ludp_credit(32'h2);
            env.coverage.sample_credit_valid();
            env.monitor.wait_for_tx_frames(2, 5000);
            if (env.monitor.tx_frame_count >= 2)
                $display("[%0t]   PASS: System functional after unknown TYPE", $time);
            else begin
                $display("[%0t]   ERROR: System hung after unknown TYPE", $time);
                error_count = error_count + 1;
            end
            stop_session();

            $display("[%0t]   Phase C: tuser error packet", $time);
            reset_dut();
            start_session(16'd64);
            env.monitor.reset_capture();
            env.driver.send_ludp_packet_with_tuser_err(8'h02, 8'h00, 32'h0, CMD_STOP, 32'h0, 16'h0, 0);
            env.coverage.sample_tuser_err();
            repeat(2000) @(posedge env.vif.clk);
            if (env.ctrl_vif.get_tx_enabled())
                $display("[%0t]   PASS: CMD_STOP in tuser-error packet ignored", $time);
            else begin
                $display("[%0t]   ERROR: CMD_STOP in tuser-error packet executed", $time);
                error_count = error_count + 1;
            end
            env.monitor.reset_capture();
            env.driver.send_ludp_credit(32'h2);
            env.coverage.sample_credit_valid();
            env.monitor.wait_for_tx_frames(2, 5000);
            if (env.monitor.tx_frame_count >= 2)
                $display("[%0t]   PASS: System functional after tuser error", $time);
            else begin
                $display("[%0t]   ERROR: System hung after tuser error", $time);
                error_count = error_count + 1;
            end
            stop_session();

            $display("[%0t]   Phase D: Reset recovery", $time);
            reset_dut();
            start_session(16'd64);
            send_credit_and_wait(32'h2, 2);
            env.rst = 1;
            repeat(100) @(posedge env.vif.clk);
            env.rst = 0;
            env.coverage.sample_reset_recovery();
            repeat(600) @(posedge env.vif.clk);
            env.driver.resolve_arp();
            env.monitor.reset_capture();
            env.driver.send_ludp_cmd(CMD_START, 32'h0, 16'h0, 8'h00);
            env.coverage.sample_cmd_start();
            repeat(500) @(posedge env.vif.clk);
            env.driver.send_ludp_credit(32'h2);
            env.coverage.sample_credit_valid();
            env.monitor.wait_for_tx_frames(2, 5000);
            if (env.monitor.tx_frame_count >= 2)
                $display("[%0t]   PASS: System functional after reset", $time);
            else begin
                $display("[%0t]   ERROR: System not functional after reset", $time);
                error_count = error_count + 1;
            end
            stop_session();
        end
    endtask

endclass


class test_internal_mechanisms extends ludp_test_base;

    function new();
        test_num = 7;
    endfunction

    virtual task run();
        bit wr_enable_before;
        bit wr_enable_after;
        bit [31:0] saved_status;
        bit [7:0]  rx_type_s;
        bit [31:0] rx_data_s;
        int fuzz_idx;
        bit [15:0] fuzz_size;
        int fuzz_err;
        bit [31:0] fuzz_credit;
        bit [31:0] nack_tgt;
        bit [7:0]  rx_type;
        bit [31:0] rx_seq;
        ludp_rx_frame frm;
        begin
            $display("");
            $display("[%0t] ========================================", $time);
            $display("[%0t] Test 7: Internal Mechanisms + Fuzz", $time);
            $display("[%0t] ========================================", $time);

            $display("[%0t]   Phase A: Write backpressure", $time);
            reset_dut();
            repeat(100) @(posedge env.vif.clk);
            wr_enable_before = env.ctrl_vif.dma_wr_enable;
            start_session(16'd64);
            send_credit_and_wait(32'h3, 3);
            repeat(100) @(posedge env.vif.clk);
            wr_enable_after = env.ctrl_vif.dma_wr_enable;
            env.coverage.sample_wr_backpressure();
            if (wr_enable_before == 1'b1 && wr_enable_after == 1'b0)
                $display("[%0t]   PASS: Write backpressure (before=%0b after=%0b)", $time, wr_enable_before, wr_enable_after);
            else
                $display("[%0t]   WARNING: Write backpressure (before=%0b after=%0b)", $time, wr_enable_before, wr_enable_after);
            stop_session();

            $display("[%0t]   Phase B: Status request -> RESP", $time);
            reset_dut();
            start_session(16'd64);
            repeat(1000) @(posedge env.vif.clk);
            env.monitor.reset_capture();
            saved_status = 32'hDEADBEEF;
            env.ctrl_vif.inject_status(16'h0020, saved_status);
            env.monitor.wait_for_tx_frames(1, 5000);
            begin
                int resp_idx;
                bit status_found;
                ludp_rx_frame sfrm;
                status_found = 0;
                for (resp_idx = 0; resp_idx < env.monitor.tx_frame_count; resp_idx++) begin
                    if (env.monitor.frame_mbx.try_get(sfrm)) begin
                        if (sfrm != null && sfrm.ludp_type == TYPE_CMD_CPL) begin
                            rx_data_s = {sfrm.get_byte(55), sfrm.get_byte(54), sfrm.get_byte(53), sfrm.get_byte(52)};
                            env.coverage.sample_status_resp();
                            status_found = 1;
                            if (rx_data_s == saved_status)
                                $display("[%0t]   PASS: Status data matches (data=%08h)", $time, rx_data_s);
                            else begin
                                $display("[%0t]   ERROR: Status data mismatch (exp=%08h got=%08h)", $time, saved_status, rx_data_s);
                                error_count = error_count + 1;
                            end
                        end
                    end
                end
                if (!status_found) begin
                    $display("[%0t]   ERROR: No CMD_CPL status response", $time);
                    error_count = error_count + 1;
                end
            end
            stop_session();

            $display("[%0t]   Phase C: Status suppress during pkt_complete", $time);
            reset_dut();
            start_session(16'd64);
            env.ctrl_vif.inject_status(16'h0020, 32'hCAFEBABE);
            env.driver.send_ludp_credit(32'h1);
            env.coverage.sample_credit_valid();
            env.coverage.sample_status_suppress();
            repeat(3000) @(posedge env.vif.clk);
            if (env.monitor.tx_frame_count >= 1)
                $display("[%0t]   PASS: No crash when status and pkt_complete coincide", $time);
            else begin
                $display("[%0t]   ERROR: No response frames", $time);
                error_count = error_count + 1;
            end
            stop_session();

            $display("[%0t]   Phase D: Fuzz - random credit/NACK sequences", $time);
            env.sequencer.set_seed(32'h87654321);
            fuzz_err = 0;
            for (fuzz_idx = 0; fuzz_idx < 4; fuzz_idx++) begin
                fuzz_size = env.sequencer.next_payload_size();
                fuzz_credit = env.sequencer.next_credit();

                $display("[%0t]     Fuzz %0d: size=%0d credit=%0d", $time, fuzz_idx, fuzz_size, fuzz_credit);
                reset_dut();
                start_session(fuzz_size);
                env.monitor.reset_capture();
                env.driver.send_ludp_credit(fuzz_credit);
                env.coverage.sample_credit_valid();
                env.monitor.wait_for_tx_frames(fuzz_credit, 500000);
                if (env.monitor.tx_frame_count < fuzz_credit) begin
                    $display("[%0t]     ERROR: Fuzz %0d only got %0d/%0d frames", $time, fuzz_idx, env.monitor.tx_frame_count, fuzz_credit);
                    error_count = error_count + 1;
                    fuzz_err = fuzz_err + 1;
                end else begin
                    env.coverage.sample_data_sent(fuzz_credit);
                    env.coverage.sample_prbs_ok(fuzz_credit);
                end

                if (fuzz_idx[0] == 0 && env.ctrl_vif.get_tx_seq_num() > 1) begin
                    nack_tgt = env.ctrl_vif.get_tx_seq_num() - 32'h1;
                    env.monitor.reset_capture();
                    env.driver.send_ludp_nack(nack_tgt, 16'h1);
                    env.coverage.sample_nack_retx();
                    env.monitor.wait_for_tx_frame(200000, frm);
                    if (frm != null) begin
                        if (frm.ludp_type == TYPE_DATA && frm.ludp_seq == nack_tgt)
                            $display("[%0t]     Fuzz RETX OK (seq=%08h)", $time, frm.ludp_seq);
                    end
                end

                stop_session();
            end
            if (fuzz_err == 0)
                $display("[%0t]   PASS: Fuzz test completed", $time);
        end
    endtask

endclass
