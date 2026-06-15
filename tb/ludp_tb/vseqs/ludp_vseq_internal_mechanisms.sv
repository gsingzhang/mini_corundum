class internal_mechanisms_vseq extends ludp_virtual_sequence_base;
    `uvm_object_utils(internal_mechanisms_vseq)

    function new(string name = "internal_mechanisms_vseq");
        super.new(name);
    endfunction

    virtual task body();
        bit wr_enable_before;
        bit wr_enable_after;
        int fuzz_iter;
        bit [7:0] fuzz_type;
        bit [7:0] fuzz_flags;
        bit [31:0] fuzz_seq;
        super.body();

        `uvm_info("VSEQ", "Phase A: Write backpressure", UVM_NONE)
        reset_dut();
        wait_clocks(100);
        wr_enable_before = get_dma_wr_enable();
        send_start(16'd64);
        send_credit(32'h3);
        wait_clocks(20000);
        wait_clocks(100);
        wr_enable_after = get_dma_wr_enable();
        send_stop();
        wait_clocks(500);

        `uvm_info("VSEQ", "Phase B: Status request -> RESP", UVM_NONE)
        reset_dut();
        send_start(16'd64);
        wait_clocks(1000);
        inject_status(16'h0020, 32'hDEADBEEF);
        wait_clocks(5000);
        send_stop();
        wait_clocks(500);

        `uvm_info("VSEQ", "Phase C: Fuzz test", UVM_NONE)
        reset_dut();
        send_start(16'd64);
        for (fuzz_iter = 0; fuzz_iter < 20; fuzz_iter++) begin
            fuzz_type  = $urandom_range(0, 7);
            fuzz_flags = $urandom();
            fuzz_seq   = $urandom();
            send_ludp_raw(fuzz_type, fuzz_flags, fuzz_seq, 16'h0, 32'h0, 16'h0, 0);
            wait_clocks(200);
        end
        send_credit(get_tx_seq_num() + 32'h2);
        wait_clocks(5000);
        send_stop();
        wait_clocks(500);
    endtask
endclass
