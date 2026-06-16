class tx_dma_codecov_vseq extends ludp_virtual_sequence_base;
    `uvm_object_utils(tx_dma_codecov_vseq)

    function new(string name = "tx_dma_codecov_vseq");
        super.new(name);
    endfunction

    virtual task body();
        bit [31:0] cur_seq;
        super.body();

        `uvm_info("VSEQ", "=== TX + DMA Code Coverage ===", UVM_NONE)

        // ---- Phase 1: Small payload (16 bytes) - single beat data path ----
        `uvm_info("VSEQ", "Phase 1: Small payload (16 bytes)", UVM_NONE)
        reset_dut();
        send_start(16'd16);
        send_credit(32'h8);
        wait_clocks(20000);
        send_stop();
        wait_clocks(500);

        // ---- Phase 2: Medium payload (32 bytes) - standard 2-beat data ----
        `uvm_info("VSEQ", "Phase 2: Medium payload (32 bytes)", UVM_NONE)
        reset_dut();
        send_start(16'd32);
        send_credit(32'h8);
        wait_clocks(30000);
        send_stop();
        wait_clocks(500);

        // ---- Phase 3: Medium payload (64 bytes) - multiple packets ----
        `uvm_info("VSEQ", "Phase 3: Medium payload (64 bytes)", UVM_NONE)
        reset_dut();
        send_start(16'd64);
        send_credit(32'h16);
        wait_clocks(50000);
        send_stop();
        wait_clocks(500);

        // ---- Phase 4: Large payload (1024 bytes) - multi-beat data ----
        `uvm_info("VSEQ", "Phase 4: Large payload (1024 bytes)", UVM_NONE)
        reset_dut();
        send_start(16'd1024);
        send_credit(32'h16);
        wait_clocks(100000);
        send_stop();
        wait_clocks(500);

        // ---- Phase 5: Max payload (8960 bytes) - maximum size boundary ----
        `uvm_info("VSEQ", "Phase 5: Max payload (8960 bytes)", UVM_NONE)
        reset_dut();
        send_start(16'd8960);
        send_credit(32'h4);
        wait_clocks(200000);
        send_stop();
        wait_clocks(500);

        // ---- Phase 6: NACK injection - RETX path, RETX header generation ----
        `uvm_info("VSEQ", "Phase 6: NACK injection triggers RETX path", UVM_NONE)
        reset_dut();
        send_start(16'd128);
        send_credit(32'h16);
        wait_clocks(30000);

        cur_seq = get_tx_seq_num();
        `uvm_info("VSEQ", $sformatf("  current tx_seq=%0h, NACK seq=%0h",
                  cur_seq, cur_seq - 32'h5), UVM_NONE)
        send_nack(cur_seq - 32'h5, 16'h1);
        wait_clocks(2000);
        send_credit(cur_seq + 32'h8);
        wait_clocks(50000);
        send_stop();
        wait_clocks(500);

        // ---- Phase 7: Rapid status response injections - RESP path ----
        `uvm_info("VSEQ", "Phase 7: Status responses (RESP state machine)", UVM_NONE)
        reset_dut();
        send_start(16'd64);
        wait_clocks(1000);

        // Status responses: each goes through TX_RESP state
        inject_status(16'h0010, 32'hDEAD0001);
        wait_clocks(50);
        inject_status(16'h0020, 32'hDEAD0002);
        wait_clocks(50);
        inject_status(16'h0030, 32'hDEAD0003);
        wait_clocks(50);
        inject_status(16'h0040, 32'hDEAD0004);
        wait_clocks(50);
        inject_status(16'h0050, 32'hDEAD0005);
        wait_clocks(5000);

        send_credit(32'h8);
        wait_clocks(30000);
        send_stop();
        wait_clocks(500);

        // ---- Phase 8: Throttling - small credit, large data (f2h_tx_ok path) ----
        `uvm_info("VSEQ", "Phase 8: Throttling (credit exhaustion test)", UVM_NONE)
        reset_dut();
        send_start(16'd128);
        // Send minimal credit - forces f2h_tx_ok to toggle between 0 and 1
        send_credit(32'h1);
        wait_clocks(30000);
        send_credit(32'h2);
        wait_clocks(30000);
        send_credit(32'h4);
        wait_clocks(30000);
        send_stop();
        wait_clocks(500);

        // ---- Phase 9: Quick start/stop (test state machine transitions) ----
        `uvm_info("VSEQ", "Phase 9: Quick start/stop cycles", UVM_NONE)
        reset_dut();
        send_start(16'd64);
        send_credit(32'h2);
        wait_clocks(10000);
        send_stop();
        wait_clocks(200);

        reset_dut();
        send_start(16'd32);
        send_credit(32'h4);
        wait_clocks(15000);
        send_stop();
        wait_clocks(200);

        `uvm_info("VSEQ", "=== TX + DMA Code Coverage DONE ===", UVM_NONE)
    endtask
endclass
