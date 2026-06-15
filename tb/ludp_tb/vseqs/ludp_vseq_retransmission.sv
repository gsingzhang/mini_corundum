class retransmission_vseq extends ludp_virtual_sequence_base;
    `uvm_object_utils(retransmission_vseq)

    function new(string name = "retransmission_vseq");
        super.new(name);
    endfunction

    virtual task body();
        bit [31:0] retx_target;
        super.body();

        `uvm_info("VSEQ", "Phase A: Basic NACK -> RETX", UVM_NONE)
        reset_dut();
        send_start(16'd64);
        send_credit(32'h2);
        wait_clocks(20000);
        retx_target = get_tx_seq_num() - 32'h1;
        send_nack(retx_target, 16'h1);
        wait_clocks(5000);

        `uvm_info("VSEQ", "Phase B: NACK no-entry", UVM_NONE)
        send_nack(32'hFFFF, 16'h1);
        wait_clocks(500);

        `uvm_info("VSEQ", "Phase C: Block recycle", UVM_NONE)
        send_credit(get_tx_seq_num() + 32'h4);
        wait_clocks(5000);

        `uvm_info("VSEQ", "Phase D: RETX priority over TX", UVM_NONE)
        wait_clocks(200);
        retx_target = get_tx_seq_num() - 32'h1;
        send_nack(retx_target, 16'h1);
        send_credit(get_tx_seq_num() + 32'h4);
        wait_clocks(5000);
        send_stop();
        wait_clocks(500);
    endtask
endclass
