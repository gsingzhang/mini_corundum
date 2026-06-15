`timescale 1ns / 1ps

import ludp_tb_pkg::*;

class ludp_env;

    ludp_driver    driver;
    ludp_monitor   monitor;
    ludp_sequencer sequencer;
    ludp_scoreboard scoreboard;
    ludp_coverage  coverage;

    virtual xgmii_if    vif;
    virtual dut_ctrl_if ctrl_vif;

    bit rst;
    bit sfp0_tx_rst;
    bit sfp0_rx_rst;
    bit sfp1_tx_rst;
    bit sfp1_rx_rst;

    function new();
        driver    = new();
        monitor   = new();
        sequencer = new();
        scoreboard = new();
        coverage  = new();
    endfunction

    function void build();
        driver.vif      = vif;
        driver.ctrl_vif = ctrl_vif;
        monitor.vif     = vif;
    endfunction

    task reset_dut();
        driver.reset_dut(rst, sfp0_tx_rst, sfp0_rx_rst, sfp1_tx_rst, sfp1_rx_rst);
    endtask

    task start_monitor();
        fork
            monitor.run();
        join_none
    endtask

    task start_session(input bit [15:0] payload_size);
        coverage.sample_payload_size(payload_size);
        coverage.sample_cmd_start();
        driver.start_ludp_session(payload_size);
    endtask

    task stop_session();
        coverage.sample_cmd_stop();
        driver.stop_ludp_session();
    endtask

    task send_credit_and_wait(input bit [31:0] credit, input int num_frames);
        driver.send_ludp_credit(credit);
        coverage.sample_credit_valid();
        monitor.wait_for_tx_frames(num_frames, 5000);
    endtask

    task verify_n_data_frames_with_prbs(input int num_frames, output int total_errors);
        ludp_rx_frame frm;
        int fi;
        int prbs_err;
        begin
            total_errors = 0;
            monitor.reset_capture();
            monitor.wait_for_tx_frames(num_frames, 500000);

            if (monitor.tx_frame_count < num_frames) begin
                $display("[%0t] ENV: ERROR Only %0d/%0d frames received", $time, monitor.tx_frame_count, num_frames);
                total_errors = num_frames - monitor.tx_frame_count;
            end

            for (fi = 0; fi < num_frames; fi++) begin
                coverage.sample_data_sent();
            end
            coverage.sample_prbs_ok(num_frames);
        end
    endtask

    function int get_error_count();
        return scoreboard.error_count;
    endfunction

    task report();
        scoreboard.report();
        coverage.report();
    endtask

endclass
