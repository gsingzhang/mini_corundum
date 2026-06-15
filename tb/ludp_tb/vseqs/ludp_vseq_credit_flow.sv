class credit_flow_vseq extends ludp_virtual_sequence_base;
    `uvm_object_utils(credit_flow_vseq)

    function new(string name = "credit_flow_vseq");
        super.new(name);
    endfunction

    virtual task body();
        bit [31:0] saved_seq;
        super.body();

        `uvm_info("VSEQ", "Phase A: Credit advance", UVM_NONE)
        reset_dut();
        send_start(16'd64);
        send_credit(32'h1);
        wait_clocks(5000);

        `uvm_info("VSEQ", "Phase B: Credit exhaustion", UVM_NONE)
        wait_clocks(2000);

        `uvm_info("VSEQ", "Phase C: Stale credit rejected", UVM_NONE)
        saved_seq = get_tx_seq_num() - 32'h1;
        send_credit(saved_seq);
        wait_clocks(2000);

        `uvm_info("VSEQ", "Phase D: Multiple credits", UVM_NONE)
        send_credit(get_tx_seq_num() + 32'h4);
        wait_clocks(5000);
        send_stop();
        wait_clocks(500);
    endtask
endclass
