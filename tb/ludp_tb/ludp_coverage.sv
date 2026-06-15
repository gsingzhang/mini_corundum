`timescale 1ns / 1ps

import ludp_tb_pkg::*;

class ludp_coverage;

    int cov_arp_reply;
    int cov_cmd_start;
    int cov_cmd_stop;
    int cov_cmd_ack;
    int cov_cmd_cpl;
    int cov_cmd_skip_resp;
    int cov_credit_valid;
    int cov_credit_stale;
    int cov_nack_retx;
    int cov_nack_noent;
    int cov_data_sent;
    int cov_prbs_ok;
    int cov_prbs_err;
    int cov_bad_magic;
    int cov_unknown_type;
    int cov_tuser_err;
    int cov_reset_recovery;
    int cov_wr_backpressure;
    int cov_status_resp;
    int cov_status_suppress;
    int cov_retx_priority;
    int cov_block_recycle;
    int cov_double_start;
    int cov_credit_exhaust;
    int cov_credit_advance;
    int cov_payload_bins [0:4];

    function new();
        cov_arp_reply      = 0;
        cov_cmd_start      = 0;
        cov_cmd_stop       = 0;
        cov_cmd_ack        = 0;
        cov_cmd_cpl        = 0;
        cov_cmd_skip_resp  = 0;
        cov_credit_valid   = 0;
        cov_credit_stale   = 0;
        cov_nack_retx      = 0;
        cov_nack_noent     = 0;
        cov_data_sent      = 0;
        cov_prbs_ok        = 0;
        cov_prbs_err       = 0;
        cov_bad_magic      = 0;
        cov_unknown_type   = 0;
        cov_tuser_err      = 0;
        cov_reset_recovery = 0;
        cov_wr_backpressure = 0;
        cov_status_resp    = 0;
        cov_status_suppress = 0;
        cov_retx_priority  = 0;
        cov_block_recycle  = 0;
        cov_double_start   = 0;
        cov_credit_exhaust = 0;
        cov_credit_advance = 0;
        cov_payload_bins[0] = 0;
        cov_payload_bins[1] = 0;
        cov_payload_bins[2] = 0;
        cov_payload_bins[3] = 0;
        cov_payload_bins[4] = 0;
    endfunction

    function void sample_arp_reply();
        cov_arp_reply = cov_arp_reply + 1;
    endfunction

    function void sample_cmd_start();
        cov_cmd_start = cov_cmd_start + 1;
    endfunction

    function void sample_cmd_stop();
        cov_cmd_stop = cov_cmd_stop + 1;
    endfunction

    function void sample_cmd_ack();
        cov_cmd_ack = cov_cmd_ack + 1;
    endfunction

    function void sample_cmd_cpl();
        cov_cmd_cpl = cov_cmd_cpl + 1;
    endfunction

    function void sample_cmd_skip_resp();
        cov_cmd_skip_resp = cov_cmd_skip_resp + 1;
    endfunction

    function void sample_credit_valid();
        cov_credit_valid = cov_credit_valid + 1;
    endfunction

    function void sample_credit_stale();
        cov_credit_stale = cov_credit_stale + 1;
    endfunction

    function void sample_nack_retx();
        cov_nack_retx = cov_nack_retx + 1;
    endfunction

    function void sample_nack_noent();
        cov_nack_noent = cov_nack_noent + 1;
    endfunction

    function void sample_data_sent(input int count = 1);
        cov_data_sent = cov_data_sent + count;
    endfunction

    function void sample_prbs_ok(input int count = 1);
        cov_prbs_ok = cov_prbs_ok + count;
    endfunction

    function void sample_prbs_err();
        cov_prbs_err = cov_prbs_err + 1;
    endfunction

    function void sample_bad_magic();
        cov_bad_magic = cov_bad_magic + 1;
    endfunction

    function void sample_unknown_type();
        cov_unknown_type = cov_unknown_type + 1;
    endfunction

    function void sample_tuser_err();
        cov_tuser_err = cov_tuser_err + 1;
    endfunction

    function void sample_reset_recovery();
        cov_reset_recovery = cov_reset_recovery + 1;
    endfunction

    function void sample_wr_backpressure();
        cov_wr_backpressure = cov_wr_backpressure + 1;
    endfunction

    function void sample_status_resp();
        cov_status_resp = cov_status_resp + 1;
    endfunction

    function void sample_status_suppress();
        cov_status_suppress = cov_status_suppress + 1;
    endfunction

    function void sample_retx_priority();
        cov_retx_priority = cov_retx_priority + 1;
    endfunction

    function void sample_block_recycle();
        cov_block_recycle = cov_block_recycle + 1;
    endfunction

    function void sample_double_start();
        cov_double_start = cov_double_start + 1;
    endfunction

    function void sample_credit_exhaust();
        cov_credit_exhaust = cov_credit_exhaust + 1;
    endfunction

    function void sample_credit_advance();
        cov_credit_advance = cov_credit_advance + 1;
    endfunction

    function void sample_payload_size(input bit [15:0] size);
        if (size <= 32)
            cov_payload_bins[0] = cov_payload_bins[0] + 1;
        else if (size <= 128)
            cov_payload_bins[1] = cov_payload_bins[1] + 1;
        else if (size <= 512)
            cov_payload_bins[2] = cov_payload_bins[2] + 1;
        else if (size <= 2048)
            cov_payload_bins[3] = cov_payload_bins[3] + 1;
        else
            cov_payload_bins[4] = cov_payload_bins[4] + 1;
    endfunction

    function void report();
        int total_bins;
        int hit_bins;
        begin
            total_bins = 25;
            hit_bins = 0;

            $display("");
            $display("========================================");
            $display(" Functional Coverage Report");
            $display("========================================");

            $display("");
            $display("--- Protocol RX ---");
            $display("  ARP reply:           %0d hits", cov_arp_reply);
            $display("  CMD_START:           %0d hits", cov_cmd_start);
            $display("  CMD_STOP:            %0d hits", cov_cmd_stop);
            $display("  CMD_ACK (flags=0):   %0d hits", cov_cmd_ack);
            $display("  CMD_CPL (flags=CPL): %0d hits", cov_cmd_cpl);
            $display("  CMD skip (resp_ongoing): %0d hits", cov_cmd_skip_resp);
            $display("  CREDIT valid:        %0d hits", cov_credit_valid);
            $display("  CREDIT stale reject: %0d hits", cov_credit_stale);
            $display("  NACK -> RETX:        %0d hits", cov_nack_retx);
            $display("  NACK no-entry:       %0d hits", cov_nack_noent);
            $display("  Bad MAGIC discard:   %0d hits", cov_bad_magic);
            $display("  Unknown TYPE ignore: %0d hits", cov_unknown_type);
            $display("  tuser error handle:  %0d hits", cov_tuser_err);
            $display("  Status suppress:     %0d hits", cov_status_suppress);

            $display("");
            $display("--- Protocol TX ---");
            $display("  DATA sent:           %0d hits", cov_data_sent);
            $display("  PRBS OK:             %0d hits", cov_prbs_ok);
            $display("  PRBS ERR:            %0d hits", cov_prbs_err);
            $display("  RETX priority:       %0d hits", cov_retx_priority);
            $display("  Status RESP:         %0d hits", cov_status_resp);

            $display("");
            $display("--- Scheduler ---");
            $display("  Block recycle:       %0d hits", cov_block_recycle);
            $display("  WR backpressure:     %0d hits", cov_wr_backpressure);

            $display("");
            $display("--- System ---");
            $display("  Reset recovery:      %0d hits", cov_reset_recovery);
            $display("  Double START:        %0d hits", cov_double_start);
            $display("  Credit exhaust:      %0d hits", cov_credit_exhaust);
            $display("  Credit advance:      %0d hits", cov_credit_advance);

            $display("");
            $display("--- Payload Size Bins ---");
            $display("  [0]    8-32B:    %0d hits", cov_payload_bins[0]);
            $display("  [1]   33-128B:   %0d hits", cov_payload_bins[1]);
            $display("  [2]  129-512B:   %0d hits", cov_payload_bins[2]);
            $display("  [3]  513-2KB:    %0d hits", cov_payload_bins[3]);
            $display("  [4]   2KB-9KB:   %0d hits", cov_payload_bins[4]);

            if (cov_arp_reply > 0)       hit_bins = hit_bins + 1;
            if (cov_cmd_start > 0)       hit_bins = hit_bins + 1;
            if (cov_cmd_stop > 0)        hit_bins = hit_bins + 1;
            if (cov_cmd_ack > 0)         hit_bins = hit_bins + 1;
            if (cov_cmd_cpl > 0)         hit_bins = hit_bins + 1;
            if (cov_cmd_skip_resp > 0)   hit_bins = hit_bins + 1;
            if (cov_credit_valid > 0)    hit_bins = hit_bins + 1;
            if (cov_credit_stale > 0)    hit_bins = hit_bins + 1;
            if (cov_nack_retx > 0)       hit_bins = hit_bins + 1;
            if (cov_nack_noent > 0)      hit_bins = hit_bins + 1;
            if (cov_bad_magic > 0)       hit_bins = hit_bins + 1;
            if (cov_unknown_type > 0)    hit_bins = hit_bins + 1;
            if (cov_tuser_err > 0)       hit_bins = hit_bins + 1;
            if (cov_status_suppress > 0) hit_bins = hit_bins + 1;
            if (cov_data_sent > 0)       hit_bins = hit_bins + 1;
            if (cov_prbs_ok > 0)         hit_bins = hit_bins + 1;
            if (cov_retx_priority > 0)   hit_bins = hit_bins + 1;
            if (cov_status_resp > 0)     hit_bins = hit_bins + 1;
            if (cov_block_recycle > 0)   hit_bins = hit_bins + 1;
            if (cov_wr_backpressure > 0) hit_bins = hit_bins + 1;
            if (cov_reset_recovery > 0)  hit_bins = hit_bins + 1;
            if (cov_double_start > 0)    hit_bins = hit_bins + 1;
            if (cov_credit_exhaust > 0)  hit_bins = hit_bins + 1;
            if (cov_credit_advance > 0)  hit_bins = hit_bins + 1;
            if (cov_payload_bins[0] + cov_payload_bins[1] + cov_payload_bins[2] +
                cov_payload_bins[3] + cov_payload_bins[4] >= 3) hit_bins = hit_bins + 1;

            $display("");
            $display("  Functional bins hit: %0d / %0d = %0d%%", hit_bins, total_bins, (hit_bins * 100) / total_bins);
            $display("========================================");
        end
    endfunction

endclass
