class ludp_scoreboard extends uvm_scoreboard;

    uvm_analysis_imp #(ludp_rx_frame, ludp_scoreboard) ap;

    int error_count;
    int check_count;
    int prbs_ok_count;
    int prbs_err_count;

    int arp_reply_count;
    int cmd_ack_count;
    int cmd_cpl_count;
    int data_frame_count;
    int icmp_reply_count;

    `uvm_component_utils(ludp_scoreboard)

    function new(string name = "ludp_scoreboard", uvm_component parent = null);
        super.new(name, parent);
        error_count   = 0;
        check_count   = 0;
        prbs_ok_count = 0;
        prbs_err_count = 0;
        arp_reply_count = 0;
        cmd_ack_count = 0;
        cmd_cpl_count = 0;
        data_frame_count = 0;
        icmp_reply_count = 0;
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ap = new("ap", this);
    endfunction

    virtual function void write(ludp_rx_frame frm);
        int prbs_err;
        check_count = check_count + 1;

        case (frm.frame_type)
            FRAME_ARP_REPLY: begin
                arp_reply_count = arp_reply_count + 1;
                `uvm_info("SB", $sformatf("ARP reply received"), UVM_HIGH)
            end
            FRAME_ICMP_REPLY: begin
                icmp_reply_count = icmp_reply_count + 1;
                `uvm_info("SB", $sformatf("ICMP reply received"), UVM_HIGH)
            end
            FRAME_LUDP_ACK: begin
                cmd_ack_count = cmd_ack_count + 1;
                `uvm_info("SB", $sformatf("CMD_ACK received flags=%02h", frm.ludp_flags), UVM_HIGH)
            end
            FRAME_LUDP_CPL: begin
                cmd_cpl_count = cmd_cpl_count + 1;
                `uvm_info("SB", $sformatf("CMD_CPL received opcode=%04h", frm.ludp_opcode), UVM_HIGH)
            end
            FRAME_LUDP_DATA: begin
                data_frame_count = data_frame_count + 1;
                frm.verify_prbs(prbs_err);
                if (prbs_err == 0) begin
                    prbs_ok_count = prbs_ok_count + 1;
                    `uvm_info("SB", $sformatf("DATA frame PRBS OK seq=%08h", frm.ludp_seq), UVM_HIGH)
                end else begin
                    prbs_err_count = prbs_err_count + 1;
                    `uvm_error("SB", $sformatf("DATA frame PRBS ERR seq=%08h errors=%0d", frm.ludp_seq, prbs_err))
                end
            end
            default: begin
                `uvm_info("SB", $sformatf("Frame type=%0s", frm.frame_type.name()), UVM_HIGH)
            end
        endcase

        if (frm.ludp_magic !== MAGIC && frm.eth_type == 16'h0800 && frm.ip_proto == 8'h11) begin
            `uvm_error("SB", $sformatf("Magic mismatch: expected %04h, got %04h", MAGIC, frm.ludp_magic))
            error_count = error_count + 1;
        end
    endfunction

    virtual function void report_phase(uvm_phase phase);
        `uvm_info("SB", "", UVM_NONE)
        `uvm_info("SB", "========================================", UVM_NONE)
        `uvm_info("SB", " Scoreboard Report", UVM_NONE)
        `uvm_info("SB", "========================================", UVM_NONE)
        `uvm_info("SB", $sformatf("  Total checks:    %0d", check_count), UVM_NONE)
        `uvm_info("SB", $sformatf("  Errors:          %0d", error_count), UVM_NONE)
        `uvm_info("SB", $sformatf("  ARP replies:     %0d", arp_reply_count), UVM_NONE)
        `uvm_info("SB", $sformatf("  ICMP replies:    %0d", icmp_reply_count), UVM_NONE)
        `uvm_info("SB", $sformatf("  CMD_ACK:         %0d", cmd_ack_count), UVM_NONE)
        `uvm_info("SB", $sformatf("  CMD_CPL:         %0d", cmd_cpl_count), UVM_NONE)
        `uvm_info("SB", $sformatf("  DATA frames:     %0d", data_frame_count), UVM_NONE)
        `uvm_info("SB", $sformatf("  PRBS OK:         %0d", prbs_ok_count), UVM_NONE)
        `uvm_info("SB", $sformatf("  PRBS ERR:        %0d", prbs_err_count), UVM_NONE)
        `uvm_info("SB", "========================================", UVM_NONE)
    endfunction

endclass
