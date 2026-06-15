`timescale 1ns / 1ps

import ludp_tb_pkg::*;

class ludp_monitor;

    virtual xgmii_if vif;

    bit [63:0] tx_capture [0:2047];
    bit [7:0]  tx_ctrl_capture [0:2047];
    int        tx_capture_len;
    int        tx_frame_count;
    bit        tx_frame_active;

    mailbox frame_mbx;

    function new();
        tx_capture_len  = 0;
        tx_frame_count  = 0;
        tx_frame_active = 0;
        frame_mbx = new();
    endfunction

    function void reset_capture();
        ludp_rx_frame dummy;
        tx_frame_count  = 0;
        tx_frame_active = 0;
        tx_capture_len  = 0;
        while (frame_mbx.try_get(dummy)) begin
        end
    endfunction

    task run();
        bit sof_detected;
        forever begin
            @(posedge vif.clk);
            if (vif.rst) begin
                tx_frame_count  = 0;
                tx_frame_active = 0;
                tx_capture_len  = 0;
            end else begin
                sof_detected = (vif.txc[0] && vif.txd[7:0] == XGMII_START) ||
                               (vif.txc[1] && vif.txd[15:8] == XGMII_START) ||
                               (vif.txc[2] && vif.txd[23:16] == XGMII_START) ||
                               (vif.txc[3] && vif.txd[31:24] == XGMII_START) ||
                               (vif.txc[4] && vif.txd[39:32] == XGMII_START) ||
                               (vif.txc[5] && vif.txd[47:40] == XGMII_START) ||
                               (vif.txc[6] && vif.txd[55:48] == XGMII_START) ||
                               (vif.txc[7] && vif.txd[63:56] == XGMII_START);

                if (sof_detected) begin
                    if (tx_frame_active) begin
                        publish_frame();
                        tx_frame_count = tx_frame_count + 1;
                    end
                    tx_frame_active = 1;
                    tx_capture_len  = 0;
                    tx_capture[0]  <= vif.txd;
                    tx_ctrl_capture[0] <= vif.txc;
                    tx_capture_len  = 1;
                end else if (vif.txc != 8'hff) begin
                    if (!tx_frame_active) begin
                        tx_frame_active = 1;
                        tx_capture_len  = 0;
                    end
                    if (tx_capture_len < 2048) begin
                        tx_capture[tx_capture_len] <= vif.txd;
                        tx_ctrl_capture[tx_capture_len] <= vif.txc;
                        tx_capture_len = tx_capture_len + 1;
                    end
                end else begin
                    if (tx_frame_active) begin
                        publish_frame();
                        tx_frame_active = 0;
                        tx_frame_count  = tx_frame_count + 1;
                    end
                end
            end
        end
    endtask

    task publish_frame();
        ludp_rx_frame frm;
        int i;
        begin
            frm = new();
            frm.raw_len = tx_capture_len;
            for (i = 0; i < tx_capture_len && i < 2048; i++) begin
                frm.raw_data[i] = tx_capture[i];
                frm.raw_ctrl[i] = tx_ctrl_capture[i];
            end
            frm.parse();
            frame_mbx.put(frm);
        end
    endtask

    task wait_for_tx_frame(input int timeout, output ludp_rx_frame frm);
        int cnt;
        int start_count;
        begin
            start_count = tx_frame_count;
            cnt = 0;
            while (tx_frame_count == start_count && cnt < timeout) begin
                @(posedge vif.clk);
                cnt = cnt + 1;
            end

            if (cnt >= timeout) begin
                $display("[%0t] MON: Timeout waiting for TX frame", $time);
                frm = null;
            end else begin
                if (frame_mbx.try_get(frm)) begin
                    $display("[%0t] MON: TX frame received (%0d beats, type=%s)",
                             $time, frm.raw_len, frm.frame_type.name);
                end else begin
                    $display("[%0t] MON: Frame count incremented but no frame in mailbox", $time);
                    frm = null;
                end
            end
        end
    endtask

    task wait_for_tx_frames(input int count, input int timeout);
        int cnt;
        int target;
        begin
            target = tx_frame_count + count;
            cnt = 0;
            while (tx_frame_count < target && cnt < timeout) begin
                @(posedge vif.clk);
                cnt = cnt + 1;
            end

            if (tx_frame_count < target) begin
                $display("[%0t] MON: Timeout waiting for %0d TX frames (got %0d)",
                         $time, count, tx_frame_count);
            end else begin
                $display("[%0t] MON: %0d TX frames received", $time, count);
            end
        end
    endtask

    task drain_frames(input int count, output int total_errors);
        ludp_rx_frame frm;
        int i;
        begin
            total_errors = 0;
            for (i = 0; i < count; i++) begin
                if (frame_mbx.try_get(frm)) begin
                    if (frm.frame_type == FRAME_LUDP_DATA) begin
                        int prbs_err;
                        frm.verify_prbs(prbs_err);
                        total_errors = total_errors + prbs_err;
                    end
                end else begin
                    @(posedge vif.clk);
                    i = i - 1;
                end
            end
        end
    endtask

    function bit [7:0] get_byte(input int pos);
        int beat;
        int lane;
        int actual_pos;
        begin
            actual_pos = pos + 8;
            beat = actual_pos / 8;
            lane = actual_pos % 8;
            if (beat < tx_capture_len)
                get_byte = tx_capture[beat][lane*8 +: 8];
            else
                get_byte = 8'h00;
        end
    endfunction

endclass
