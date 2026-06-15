`uvm_analysis_imp_decl(_rx)
`uvm_analysis_imp_decl(_tx)

class ludp_coverage extends uvm_component;

    covergroup ludp_cov;
        cp_frame_type: coverpoint m_frame_type {
            bins arp_reply    = {FRAME_ARP_REPLY};
            bins ludp_data    = {FRAME_LUDP_DATA};
            bins ludp_ack     = {FRAME_LUDP_ACK};
            bins ludp_cpl     = {FRAME_LUDP_CPL};
            bins ludp_cmd     = {FRAME_LUDP_CMD};
            bins ludp_credit  = {FRAME_LUDP_CREDIT};
            bins ludp_nack    = {FRAME_LUDP_NACK};
            bins icmp_reply   = {FRAME_ICMP_REPLY};
            bins unknown      = {FRAME_UNKNOWN};
        }
        cp_ludp_type: coverpoint m_ludp_type {
            bins data     = {TYPE_DATA};
            bins cmd      = {TYPE_CMD};
            bins nack     = {TYPE_NACK};
            bins cmd_ack  = {TYPE_CMD_ACK};
            bins cmd_cpl  = {TYPE_CMD_CPL};
            bins credit   = {TYPE_CREDIT};
        }
        cp_prbs_result: coverpoint m_prbs_ok {
            bins ok  = {1};
            bins err = {0};
        }
        cp_payload_size: coverpoint m_payload_size {
            bins b_small   = {[8:32]};
            bins b_medium  = {[33:128]};
            bins b_large   = {[129:512]};
            bins b_xlarge  = {[513:2048]};
            bins b_jumbo   = {[2049:8960]};
        }
        cp_magic_valid: coverpoint m_magic_valid {
            bins valid   = {1};
            bins invalid = {0};
        }
        cp_stim_cmd: coverpoint m_stim_cmd {
            bins cmd_start  = {CMD_LUDP_START};
            bins cmd_stop   = {CMD_LUDP_STOP};
            bins cmd_ludp   = {CMD_LUDP_CMD};
            bins credit     = {CMD_LUDP_CREDIT};
            bins nack       = {CMD_LUDP_NACK};
            bins arp_req    = {CMD_ARP_REQUEST};
            bins arp_rep    = {CMD_ARP_REPLY};
            bins icmp_req   = {CMD_ICMP_REQUEST};
            bins reset_cmd  = {CMD_RESET};
            bins idle       = {CMD_IDLE};
        }
        cp_tuser_err: coverpoint m_tuser_err {
            bins no_err = {0};
            bins err    = {1};
        }
    endgroup

    uvm_analysis_imp_rx #(ludp_rx_frame, ludp_coverage) rx_ap;
    uvm_analysis_imp_tx #(ludp_txn, ludp_coverage)       tx_ap;

    virtual dut_ctrl_if ctrl_vif;

    frame_type_e m_frame_type;
    bit [7:0]    m_ludp_type;
    bit          m_prbs_ok;
    bit [15:0]   m_payload_size;
    bit          m_magic_valid;
    stim_cmd_e   m_stim_cmd;
    bit          m_tuser_err;

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

    bit session_active;
    int prev_cmd_start_count;
    int credit_count;

    `uvm_component_utils(ludp_coverage)

    function new(string name = "ludp_coverage", uvm_component parent = null);
        super.new(name, parent);
        ludp_cov = new();

        cov_arp_reply = 0; cov_cmd_start = 0; cov_cmd_stop = 0;
        cov_cmd_ack = 0; cov_cmd_cpl = 0; cov_cmd_skip_resp = 0;
        cov_credit_valid = 0; cov_credit_stale = 0;
        cov_nack_retx = 0; cov_nack_noent = 0;
        cov_data_sent = 0; cov_prbs_ok = 0; cov_prbs_err = 0;
        cov_bad_magic = 0; cov_unknown_type = 0; cov_tuser_err = 0;
        cov_reset_recovery = 0; cov_wr_backpressure = 0;
        cov_status_resp = 0; cov_status_suppress = 0;
        cov_retx_priority = 0; cov_block_recycle = 0;
        cov_double_start = 0; cov_credit_exhaust = 0;
        cov_credit_advance = 0;
        cov_payload_bins[0] = 0; cov_payload_bins[1] = 0;
        cov_payload_bins[2] = 0; cov_payload_bins[3] = 0;
        cov_payload_bins[4] = 0;
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        rx_ap = new("rx_ap", this);
        tx_ap = new("tx_ap", this);
        if (!uvm_config_db#(virtual dut_ctrl_if)::get(this, "", "ctrl_vif", ctrl_vif))
            `uvm_info("COV", "ctrl_vif not set, internal signal coverage disabled", UVM_LOW)
    endfunction

    virtual task run_phase(uvm_phase phase);
        bit prev_dma_wr_enable;
        if (ctrl_vif == null) return;
        forever begin
            @(posedge ctrl_vif.clk);
            if (ctrl_vif.rst) begin
                prev_dma_wr_enable = 0;
            end else begin
                if (ctrl_vif.get_dma_wr_enable() && !prev_dma_wr_enable)
                    cov_wr_backpressure = cov_wr_backpressure + 1;
                prev_dma_wr_enable = ctrl_vif.get_dma_wr_enable();
            end
        end
    endtask

    virtual function void write_rx(ludp_rx_frame t);
        int prbs_err;
        m_frame_type  = t.frame_type;
        m_ludp_type   = t.ludp_type;
        m_payload_size = t.ludp_pay_len;
        m_magic_valid = (t.ludp_magic == MAGIC) ? 1 : 0;

        if (t.frame_type == FRAME_LUDP_DATA) begin
            cov_data_sent = cov_data_sent + 1;
            t.verify_prbs(prbs_err);
            m_prbs_ok = (prbs_err == 0) ? 1 : 0;
            if (prbs_err == 0)
                cov_prbs_ok = cov_prbs_ok + 1;
            else
                cov_prbs_err = cov_prbs_err + 1;
            sample_payload_size(t.ludp_pay_len);
        end else begin
            m_prbs_ok = 0;
        end

        if (t.frame_type == FRAME_ARP_REPLY)
            cov_arp_reply = cov_arp_reply + 1;
        if (t.frame_type == FRAME_LUDP_ACK)
            cov_cmd_ack = cov_cmd_ack + 1;
        if (t.frame_type == FRAME_LUDP_CPL)
            cov_cmd_cpl = cov_cmd_cpl + 1;

        if (t.frame_type == FRAME_LUDP_CMD)
            cov_status_resp = cov_status_resp + 1;

        if (t.frame_type == FRAME_UNKNOWN)
            cov_unknown_type = cov_unknown_type + 1;

        if (t.eth_type == 16'h0800 && t.ip_proto == 8'h11 && t.ludp_magic !== MAGIC)
            cov_bad_magic = cov_bad_magic + 1;

        ludp_cov.sample();
    endfunction

    virtual function void write_tx(ludp_txn t);
        m_stim_cmd  = t.stim_cmd;
        m_tuser_err = t.tuser_err;

        case (t.stim_cmd)
            CMD_LUDP_START: begin
                cov_cmd_start = cov_cmd_start + 1;
                if (session_active)
                    cov_double_start = cov_double_start + 1;
                session_active = 1'b1;
            end
            CMD_LUDP_STOP: begin
                cov_cmd_stop = cov_cmd_stop + 1;
                session_active = 1'b0;
            end
            CMD_LUDP_CREDIT:  cov_credit_valid = cov_credit_valid + 1;
            CMD_LUDP_NACK:    cov_nack_retx = cov_nack_retx + 1;
            CMD_RESET: begin
                cov_reset_recovery = cov_reset_recovery + 1;
                session_active = 1'b0;
            end
            default: ;
        endcase

        if (t.stim_cmd == CMD_LUDP_CMD) begin
            if (t.opcode == CMD_START) begin
                cov_cmd_start = cov_cmd_start + 1;
                if (session_active)
                    cov_double_start = cov_double_start + 1;
                session_active = 1'b1;
            end
            if (t.opcode == CMD_STOP) begin
                cov_cmd_stop = cov_cmd_stop + 1;
                session_active = 1'b0;
            end
        end

        if (t.tuser_err)
            cov_tuser_err = cov_tuser_err + 1;

        if (t.stim_cmd == CMD_LUDP_CMD && t.pkt_type == 8'hFF)
            cov_bad_magic = cov_bad_magic + 1;

        if (t.stim_cmd == CMD_LUDP_CMD && t.pkt_type == 8'h7F)
            cov_unknown_type = cov_unknown_type + 1;

        if (t.stim_cmd == CMD_LUDP_NACK && t.seq_num >= 32'hFFFF)
            cov_nack_noent = cov_nack_noent + 1;

        if (t.stim_cmd == CMD_LUDP_CREDIT)
            cov_credit_advance = cov_credit_advance + 1;

        if (t.stim_cmd == CMD_LUDP_CREDIT)
            credit_count = credit_count + 1;
        if (t.stim_cmd == CMD_LUDP_START)
            credit_count = 0;
        if (t.stim_cmd == CMD_LUDP_CREDIT && credit_count <= 1 && session_active)
            cov_credit_exhaust = cov_credit_exhaust + 1;

        if (t.stim_cmd == CMD_LUDP_CMD && t.opcode == CMD_START && session_active)
            cov_cmd_skip_resp = cov_cmd_skip_resp + 1;

        if (t.stim_cmd == CMD_LUDP_CREDIT && t.seq_num < 32'h10)
            cov_credit_stale = cov_credit_stale + 1;

        ludp_cov.sample();
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

    virtual function void report_phase(uvm_phase phase);
        int total_bins;
        int hit_bins;
        begin
            total_bins = 25;
            hit_bins = 0;

            `uvm_info("COV", "", UVM_NONE)
            `uvm_info("COV", "========================================", UVM_NONE)
            `uvm_info("COV", " Functional Coverage Report", UVM_NONE)
            `uvm_info("COV", "========================================", UVM_NONE)
            `uvm_info("COV", "", UVM_NONE)
            `uvm_info("COV", $sformatf("  Covergroup coverage: %0.1f%%", ludp_cov.get_coverage()), UVM_NONE)
            `uvm_info("COV", "", UVM_NONE)
            `uvm_info("COV", $sformatf("--- Protocol RX ---"), UVM_NONE)
            `uvm_info("COV", $sformatf("  ARP reply:           %0d hits", cov_arp_reply), UVM_NONE)
            `uvm_info("COV", $sformatf("  CMD_START:           %0d hits", cov_cmd_start), UVM_NONE)
            `uvm_info("COV", $sformatf("  CMD_STOP:            %0d hits", cov_cmd_stop), UVM_NONE)
            `uvm_info("COV", $sformatf("  CMD_ACK (flags=0):   %0d hits", cov_cmd_ack), UVM_NONE)
            `uvm_info("COV", $sformatf("  CMD_CPL (flags=CPL): %0d hits", cov_cmd_cpl), UVM_NONE)
            `uvm_info("COV", $sformatf("  CMD skip (resp_ongoing): %0d hits", cov_cmd_skip_resp), UVM_NONE)
            `uvm_info("COV", $sformatf("  CREDIT valid:        %0d hits", cov_credit_valid), UVM_NONE)
            `uvm_info("COV", $sformatf("  CREDIT stale reject: %0d hits", cov_credit_stale), UVM_NONE)
            `uvm_info("COV", $sformatf("  NACK -> RETX:        %0d hits", cov_nack_retx), UVM_NONE)
            `uvm_info("COV", $sformatf("  NACK no-entry:       %0d hits", cov_nack_noent), UVM_NONE)
            `uvm_info("COV", $sformatf("  Bad MAGIC discard:   %0d hits", cov_bad_magic), UVM_NONE)
            `uvm_info("COV", $sformatf("  Unknown TYPE ignore: %0d hits", cov_unknown_type), UVM_NONE)
            `uvm_info("COV", $sformatf("  tuser error handle:  %0d hits", cov_tuser_err), UVM_NONE)
            `uvm_info("COV", $sformatf("  Status suppress:     %0d hits", cov_status_suppress), UVM_NONE)
            `uvm_info("COV", "", UVM_NONE)
            `uvm_info("COV", $sformatf("--- Protocol TX ---"), UVM_NONE)
            `uvm_info("COV", $sformatf("  DATA sent:           %0d hits", cov_data_sent), UVM_NONE)
            `uvm_info("COV", $sformatf("  PRBS OK:             %0d hits", cov_prbs_ok), UVM_NONE)
            `uvm_info("COV", $sformatf("  PRBS ERR:            %0d hits", cov_prbs_err), UVM_NONE)
            `uvm_info("COV", $sformatf("  RETX priority:       %0d hits", cov_retx_priority), UVM_NONE)
            `uvm_info("COV", $sformatf("  Status RESP:         %0d hits", cov_status_resp), UVM_NONE)
            `uvm_info("COV", "", UVM_NONE)
            `uvm_info("COV", $sformatf("--- Scheduler ---"), UVM_NONE)
            `uvm_info("COV", $sformatf("  Block recycle:       %0d hits", cov_block_recycle), UVM_NONE)
            `uvm_info("COV", $sformatf("  WR backpressure:     %0d hits", cov_wr_backpressure), UVM_NONE)
            `uvm_info("COV", "", UVM_NONE)
            `uvm_info("COV", $sformatf("--- System ---"), UVM_NONE)
            `uvm_info("COV", $sformatf("  Reset recovery:      %0d hits", cov_reset_recovery), UVM_NONE)
            `uvm_info("COV", $sformatf("  Double START:        %0d hits", cov_double_start), UVM_NONE)
            `uvm_info("COV", $sformatf("  Credit exhaust:      %0d hits", cov_credit_exhaust), UVM_NONE)
            `uvm_info("COV", $sformatf("  Credit advance:      %0d hits", cov_credit_advance), UVM_NONE)
            `uvm_info("COV", "", UVM_NONE)
            `uvm_info("COV", $sformatf("--- Payload Size Bins ---"), UVM_NONE)
            `uvm_info("COV", $sformatf("  [0]    8-32B:    %0d hits", cov_payload_bins[0]), UVM_NONE)
            `uvm_info("COV", $sformatf("  [1]   33-128B:   %0d hits", cov_payload_bins[1]), UVM_NONE)
            `uvm_info("COV", $sformatf("  [2]  129-512B:   %0d hits", cov_payload_bins[2]), UVM_NONE)
            `uvm_info("COV", $sformatf("  [3]  513-2KB:    %0d hits", cov_payload_bins[3]), UVM_NONE)
            `uvm_info("COV", $sformatf("  [4]   2KB-9KB:   %0d hits", cov_payload_bins[4]), UVM_NONE)

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

            `uvm_info("COV", "", UVM_NONE)
            `uvm_info("COV", $sformatf("  Functional bins hit: %0d / %0d = %0d%%", hit_bins, total_bins, (hit_bins * 100) / total_bins), UVM_NONE)
            `uvm_info("COV", "========================================", UVM_NONE)
        end
    endfunction

endclass
