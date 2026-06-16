class tx_dma_codecov_vseq extends ludp_virtual_sequence_base;
    `uvm_object_utils(tx_dma_codecov_vseq)

    function new(string name = "tx_dma_codecov_vseq");
        super.new(name);
    endfunction

    virtual task body();
        bit [31:0] cur_seq;
        super.body();

        `uvm_info("VSEQ", "=== TX + DMA Code Coverage ===", UVM_NONE)

        `uvm_info("VSEQ", "Phase 1: Small payload (16 bytes) - bin[0]", UVM_NONE)
        reset_dut();
        send_start(16'd16);
        send_credit(32'h16);
        wait_clocks(80000);
        send_stop();
        wait_clocks(500);

        `uvm_info("VSEQ", "Phase 2: Medium payload (64 bytes) - bin[1]", UVM_NONE)
        reset_dut();
        send_start(16'd64);
        send_credit(32'h16);
        wait_clocks(80000);
        send_stop();
        wait_clocks(500);

        `uvm_info("VSEQ", "Phase 3: Medium-large payload (256 bytes) - bin[2]", UVM_NONE)
        reset_dut();
        send_start(16'd256);
        send_credit(32'h8);
        wait_clocks(120000);
        send_stop();
        wait_clocks(500);

        `uvm_info("VSEQ", "Phase 4: Large payload (1024 bytes) - bin[3]", UVM_NONE)
        reset_dut();
        send_start(16'd1024);
        send_credit(32'h4);
        wait_clocks(200000);
        send_stop();
        wait_clocks(500);

        `uvm_info("VSEQ", "Phase 5: Jumbo payload (8960 bytes) - bin[4]", UVM_NONE)
        reset_dut();
        send_start(16'd8960);
        send_credit(32'h2);
        wait_clocks(400000);
        send_stop();
        wait_clocks(500);

        `uvm_info("VSEQ", "Phase 6: RETX priority - NACK while tx_enabled", UVM_NONE)
        reset_dut();
        send_start(16'd64);
        send_credit(32'h1);
        wait_clocks(60000);
        send_nack(32'h0, 16'h1);
        wait_clocks(30000);
        send_credit(32'h4);
        wait_clocks(40000);
        send_stop();
        wait_clocks(500);

        `uvm_info("VSEQ", "Phase 7: Status responses (RESP state machine)", UVM_NONE)
        reset_dut();
        send_start(16'd64);
        wait_clocks(1000);

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
        wait_clocks(40000);
        send_stop();
        wait_clocks(500);

        `uvm_info("VSEQ", "Phase 8: Throttling (credit exhaustion test)", UVM_NONE)
        reset_dut();
        send_start(16'd128);
        send_credit(32'h1);
        wait_clocks(40000);
        send_credit(32'h2);
        wait_clocks(40000);
        send_credit(32'h4);
        wait_clocks(40000);
        send_stop();
        wait_clocks(500);

        `uvm_info("VSEQ", "Phase 9: Quick start/stop cycles", UVM_NONE)
        reset_dut();
        send_start(16'd64);
        send_credit(32'h2);
        wait_clocks(20000);
        send_stop();
        wait_clocks(200);

        reset_dut();
        send_start(16'd32);
        send_credit(32'h4);
        wait_clocks(30000);
        send_stop();
        wait_clocks(200);

        `uvm_info("VSEQ", "Phase 10: Bad MAGIC discard", UVM_NONE)
        reset_dut();
        send_ludp_raw(8'hFF, 8'h00, 32'h0, 16'h0, 32'h0, 16'h0, 0);
        wait_clocks(5000);

        `uvm_info("VSEQ", "Phase 11: Unknown TYPE ignore", UVM_NONE)
        send_ludp_raw(8'h7F, 8'h00, 32'h0, 16'h0, 32'h0, 16'h0, 0);
        wait_clocks(5000);

        `uvm_info("VSEQ", "Phase 12: NACK no-entry (seq >= FFFF)", UVM_NONE)
        send_nack(32'hFFFF, 16'h1);
        wait_clocks(5000);

        `uvm_info("VSEQ", "Phase 13: tuser error injection", UVM_NONE)
        send_ludp_raw(TYPE_CMD, 8'h00, 32'h0, CMD_START, 32'h0, 16'h0, 0, 1'b1);
        wait_clocks(5000);

        `uvm_info("VSEQ", "Phase 14: Double START (CMD_START while session active)", UVM_NONE)
        reset_dut();
        send_start(16'd64);
        send_credit(32'h4);
        wait_clocks(2000);
        send_start(16'd128);
        wait_clocks(5000);
        send_stop();
        wait_clocks(500);

        `uvm_info("VSEQ", "Phase 15: CMD skip resp (CMD_LUDP_CMD + CMD_START while active)", UVM_NONE)
        reset_dut();
        send_start(16'd64);
        send_credit(32'h4);
        wait_clocks(2000);
        send_cmd(CMD_START, 32'h0, 16'h0, 8'h00);
        wait_clocks(5000);
        send_stop();
        wait_clocks(500);

        `uvm_info("VSEQ", "Phase 16: PRBS ERR - corrupt data via tuser_err on DATA frame", UVM_NONE)
        reset_dut();
        send_start(16'd64);
        send_credit(32'h4);
        wait_clocks(30000);
        send_ludp_raw(TYPE_DATA, 8'h00, 32'h0, 16'h0, 32'h0, 16'h0, 64, 1'b1);
        wait_clocks(10000);
        send_stop();
        wait_clocks(500);

        `uvm_info("VSEQ", "=== TX + DMA Code Coverage DONE ===", UVM_NONE)
    endtask
endclass
