class coverage_enhance_vseq extends ludp_virtual_sequence_base;
    `uvm_object_utils(coverage_enhance_vseq)

    function new(string name = "coverage_enhance_vseq");
        super.new(name);
    endfunction

    virtual task body();
        bit [31:0] saved_seq;
        bit [31:0] retx_target;
        super.body();

        `uvm_info("VSEQ", "COV: Double START scenario", UVM_NONE)
        reset_dut();
        send_start(16'd64);
        send_credit(32'h2);
        wait_clocks(5000);
        send_start(16'd128);
        wait_clocks(5000);
        send_stop();
        wait_clocks(500);

        `uvm_info("VSEQ", "COV: Credit exhaustion then advance", UVM_NONE)
        reset_dut();
        send_start(16'd64);
        send_credit(32'h1);
        wait_clocks(10000);
        send_credit(get_tx_seq_num() + 32'h4);
        wait_clocks(5000);
        send_stop();
        wait_clocks(500);

        `uvm_info("VSEQ", "COV: Stale credit", UVM_NONE)
        reset_dut();
        send_start(16'd64);
        send_credit(32'h2);
        wait_clocks(5000);
        saved_seq = get_tx_seq_num() - 32'h1;
        send_credit(saved_seq);
        wait_clocks(2000);
        send_stop();
        wait_clocks(500);

        `uvm_info("VSEQ", "COV: NACK no-entry", UVM_NONE)
        reset_dut();
        send_start(16'd64);
        send_credit(32'h2);
        wait_clocks(5000);
        send_nack(32'hFFFF, 16'h1);
        wait_clocks(500);
        send_stop();
        wait_clocks(500);

        `uvm_info("VSEQ", "COV: RETX priority", UVM_NONE)
        reset_dut();
        send_start(16'd64);
        send_credit(32'h2);
        wait_clocks(10000);
        retx_target = get_tx_seq_num() - 32'h1;
        send_nack(retx_target, 16'h1);
        send_credit(get_tx_seq_num() + 32'h2);
        wait_clocks(5000);
        send_stop();
        wait_clocks(500);

        `uvm_info("VSEQ", "COV: Bad MAGIC + Unknown TYPE", UVM_NONE)
        reset_dut();
        send_start(16'd64);
        send_credit(32'h2);
        wait_clocks(5000);
        send_ludp_raw(8'hFF, 8'h00, 32'h0, 16'h0, 32'h0, 16'h0, 0);
        wait_clocks(500);
        send_ludp_raw(8'h7F, 8'h00, 32'h0, 16'h0, 32'h0, 16'h0, 0);
        wait_clocks(500);
        send_credit(get_tx_seq_num() + 32'h2);
        wait_clocks(5000);
        send_stop();
        wait_clocks(500);

        `uvm_info("VSEQ", "COV: Payload size variety", UVM_NONE)
        reset_dut();
        send_start(16'd128);
        send_credit(32'h2);
        wait_clocks(10000);
        send_stop();
        wait_clocks(500);

        reset_dut();
        send_start(16'd256);
        send_credit(32'h2);
        wait_clocks(10000);
        send_stop();
        wait_clocks(500);

        reset_dut();
        send_start(16'd512);
        send_credit(32'h2);
        wait_clocks(10000);
        send_stop();
        wait_clocks(500);

        `uvm_info("VSEQ", "COV: Status inject", UVM_NONE)
        reset_dut();
        send_start(16'd64);
        wait_clocks(1000);
        inject_status(16'h0020, 32'hDEADBEEF);
        wait_clocks(5000);
        send_stop();
        wait_clocks(500);
    endtask
endclass
