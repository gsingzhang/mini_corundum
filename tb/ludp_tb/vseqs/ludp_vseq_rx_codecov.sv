class rx_codecov_vseq extends ludp_virtual_sequence_base;
    `uvm_object_utils(rx_codecov_vseq)

    function new(string name = "rx_codecov_vseq");
        super.new(name);
    endfunction

    virtual task body();
        bit [31:0] cur_seq;
        super.body();

        `uvm_info("VSEQ", "=== RX Code Coverage ===", UVM_NONE)

        // ---- Phase 1: Multiple CMD packets - covers 2-beat packet path (line 251) ----
        `uvm_info("VSEQ", "Phase 1: CMD packets with various opcode/arg1/arg2", UVM_NONE)
        reset_dut();
        send_start(16'd32);
        wait_clocks(500);

        send_cmd(16'h0010, 32'hDEADBEEF, 16'hCAFE, 8'h00);
        wait_clocks(200);
        send_cmd(16'h0011, 32'h12345678, 16'hBABE, 8'h00);
        wait_clocks(200);
        send_cmd(16'hFFFF, 32'hFFFFFFFF, 16'hFFFF, 8'hFF);
        wait_clocks(200);
        send_cmd(16'h0000, 32'h00000000, 16'h0000, 8'h00);
        wait_clocks(200);
        send_cmd(16'h00AA, 32'h55AA55AA, 16'hAAAA, 8'hAA);
        wait_clocks(200);

        // ---- Phase 2: BAD MAGIC packets - covers line 279 (end of magic check) ----
        `uvm_info("VSEQ", "Phase 2: BAD MAGIC packets", UVM_NONE)
        send_ludp_bad_magic(16'h0000);
        wait_clocks(100);
        send_ludp_bad_magic(16'hFFFF);
        wait_clocks(100);
        send_ludp_bad_magic(16'hA5A5);
        wait_clocks(100);
        send_ludp_bad_magic(16'h5A5A);
        wait_clocks(100);
        send_ludp_bad_magic(16'h0001);
        wait_clocks(100);
        // Bad magic with valid TYPE_CMD header structure
        send_ludp_bad_magic(16'hBAD0, TYPE_CMD, 8'h00, 32'h0, 16'h0001, 32'h0, 16'h0, 0);
        wait_clocks(100);
        send_ludp_bad_magic(16'hDA02, TYPE_CMD, 8'h00, 32'h0, 16'h0001, 32'h0, 16'h0, 0);
        wait_clocks(100);

        // ---- Phase 3: tuser error packets - covers lines 236-238, 282-283 ----
        `uvm_info("VSEQ", "Phase 3: tuser error packets", UVM_NONE)
        // TYPE_CMD with tuser_err
        send_ludp_raw(TYPE_CMD, 8'h00, 32'h0, 16'h0001, 32'h0, 16'h0, 0, 1);
        wait_clocks(200);
        // TYPE_NACK with tuser_err
        send_ludp_raw(TYPE_NACK, 8'h00, 32'h111, 16'h1, 32'h0, 16'h0, 0, 1);
        wait_clocks(200);
        // TYPE_CREDIT with tuser_err
        send_ludp_raw(TYPE_CREDIT, 8'h00, 32'h222, 16'h0, 32'h0, 16'h0, 0, 1);
        wait_clocks(200);
        // TYPE_DATA with tuser_err
        send_ludp_raw(TYPE_DATA, 8'h00, 32'h333, 16'h0, 32'h0, 16'h0, 64, 1);
        wait_clocks(200);

        // ---- Phase 4: Unknown TYPE packets - covers default in type switch ----
        `uvm_info("VSEQ", "Phase 4: Unknown TYPE packets (valid magic, unknown type)", UVM_NONE)
        send_ludp_raw(8'h0F, 8'h00, 32'h0, 16'h0, 32'h0, 16'h0, 0);
        wait_clocks(100);
        send_ludp_raw(8'hF0, 8'h00, 32'h0, 16'h0, 32'h0, 16'h0, 0);
        wait_clocks(100);
        send_ludp_raw(8'hA5, 8'hAA, 32'h5A5A5A5A, 16'hFFFF, 32'hFFFFFFFF, 16'hFFFF, 0);
        wait_clocks(100);

        // ---- Phase 5: NACK packets - covers TYPE_NACK path ----
        `uvm_info("VSEQ", "Phase 5: NACK packets", UVM_NONE)
        send_nack(32'h0, 16'h0);
        wait_clocks(100);
        send_nack(32'hFFFFFFFF, 16'hFFFF);
        wait_clocks(100);
        send_nack(32'hAAAAAAAA, 16'h5555);
        wait_clocks(100);

        // ---- Phase 6: CREDIT packets - covers TYPE_CREDIT path ----
        `uvm_info("VSEQ", "Phase 6: CREDIT packets", UVM_NONE)
        send_credit(32'h0);
        wait_clocks(100);
        send_credit(32'h1);
        wait_clocks(100);
        send_credit(32'hFFFFFFFF);
        wait_clocks(100);
        send_credit(32'h80000000);
        wait_clocks(100);

        // ---- Phase 7: Status injection (no pending response) - covers line 194 ----
        `uvm_info("VSEQ", "Phase 7: Status injection with no pending response", UVM_NONE)
        // Status injection during idle - hits status_valid && !resp_ongoing && !rx_pkt_complete
        inject_status(16'h0010, 32'hDEAD0001);
        wait_clocks(100);
        inject_status(16'h0020, 32'hBEEF0002);
        wait_clocks(100);

        // ---- Phase 8: Normal data flow + mixed control ----
        `uvm_info("VSEQ", "Phase 8: Normal data flow + control packets", UVM_NONE)
        send_credit(32'h8);
        wait_clocks(50000);

        cur_seq = get_tx_seq_num();
        `uvm_info("VSEQ", $sformatf("  current tx_seq=%0h, NACK seq=%0h", cur_seq, cur_seq - 32'h3), UVM_NONE)
        send_nack(cur_seq - 32'h3, 16'h1);
        wait_clocks(2000);

        send_credit(cur_seq + 32'h20);
        wait_clocks(50000);
        send_stop();
        wait_clocks(500);

        `uvm_info("VSEQ", "=== RX Code Coverage DONE ===", UVM_NONE)
    endtask
endclass
