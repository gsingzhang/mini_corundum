class error_resilience_vseq extends ludp_virtual_sequence_base;
    `uvm_object_utils(error_resilience_vseq)

    function new(string name = "error_resilience_vseq");
        super.new(name);
    endfunction

    virtual task body();
        super.body();

        `uvm_info("VSEQ", "Phase A: Bad MAGIC discard", UVM_NONE)
        reset_dut();
        send_start(16'd64);
        send_credit(32'h2);
        wait_clocks(20000);
        send_ludp_raw(8'hFF, 8'h00, 32'h0, 16'h0, 32'h0, 16'h0, 0);
        wait_clocks(500);

        `uvm_info("VSEQ", "Phase B: Unknown TYPE ignore", UVM_NONE)
        send_ludp_raw(8'h7F, 8'h00, 32'h0, 16'h0, 32'h0, 16'h0, 0);
        wait_clocks(500);

        `uvm_info("VSEQ", "Phase C: tuser error handling", UVM_NONE)
        send_ludp_raw(TYPE_CMD, 8'h00, 32'h0, CMD_STOP, 32'h0, 16'h0, 0, 1);
        wait_clocks(500);

        `uvm_info("VSEQ", "Phase D: Data still valid after errors", UVM_NONE)
        send_credit(get_tx_seq_num() + 32'h2);
        wait_clocks(5000);
        send_stop();
        wait_clocks(500);

        `uvm_info("VSEQ", "Phase E: Reset recovery", UVM_NONE)
        reset_dut();
        send_start(16'd64);
        send_credit(32'h1);
        wait_clocks(5000);
        send_stop();
        wait_clocks(500);
    endtask
endclass
