class cmd_lifecycle_vseq extends ludp_virtual_sequence_base;
    `uvm_object_utils(cmd_lifecycle_vseq)

    function new(string name = "cmd_lifecycle_vseq");
        super.new(name);
    endfunction

    virtual task body();
        super.body();

        `uvm_info("VSEQ", "Phase A: CMD_ACK response (flags=0)", UVM_NONE)
        reset_dut();
        send_cmd(CMD_START, 32'h0, 16'h0, 8'h00);
        wait_clocks(5000);

        `uvm_info("VSEQ", "Phase B: CMD_START no credit -> no data", UVM_NONE)
        wait_clocks(2000);

        `uvm_info("VSEQ", "Phase C: CMD_CPL response (flags!=0)", UVM_NONE)
        send_cmd(CMD_START, 32'h0, 16'h0, 8'hFF);
        wait_clocks(5000);
        send_cmd(CMD_STOP, 32'h0, 16'h0, 8'h00);
        wait_clocks(500);

        `uvm_info("VSEQ", "Phase D: Double CMD_START", UVM_NONE)
        reset_dut();
        send_start(16'd64);
        send_credit(32'h4);
        wait_clocks(20000);
        send_cmd(CMD_START, 32'h0, 16'h0, 8'h00);
        wait_clocks(500);
        send_credit(get_tx_seq_num() + 32'h4);
        wait_clocks(5000);
        send_stop();
        wait_clocks(500);

        `uvm_info("VSEQ", "Phase E: CMD skipped during resp_ongoing", UVM_NONE)
        reset_dut();
        send_start(16'd64);
        send_credit(32'h2);
        wait_clocks(20000);
        send_cmd(CMD_START, 32'h0, 16'h0, 8'h00);
        send_cmd(CMD_STOP, 32'h0, 16'h0, 8'h00);
        wait_clocks(2000);
        send_stop();
        wait_clocks(500);
    endtask
endclass
