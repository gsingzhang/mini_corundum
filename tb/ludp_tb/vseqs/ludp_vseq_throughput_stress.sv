class throughput_stress_vseq extends ludp_virtual_sequence_base;
    `uvm_object_utils(throughput_stress_vseq)

    function new(string name = "throughput_stress_vseq");
        super.new(name);
    endfunction

    virtual task body();
        super.body();

        `uvm_info("VSEQ", "", UVM_NONE)
        `uvm_info("VSEQ", "========================================", UVM_NONE)
        `uvm_info("VSEQ", " Throughput Stress Test", UVM_NONE)
        `uvm_info("VSEQ", "========================================", UVM_NONE)

        reset_dut();

        `uvm_info("VSEQ", "Phase 1: Large payload 8960B (max jumbo) with generous credit", UVM_NONE)
        send_start(16'd8960);
        send_credit(32'h10);
        wait_clocks(200000);
        send_stop();
        wait_clocks(5000);

        `uvm_info("VSEQ", "Phase 2: Back-to-back 4096B frames with large credit window", UVM_NONE)
        send_start(16'd4096);
        send_credit(32'h20);
        wait_clocks(300000);
        send_stop();
        wait_clocks(5000);

        `uvm_info("VSEQ", "Phase 3: Continuous 2048B stream with sustained credit", UVM_NONE)
        send_start(16'd2048);
        send_credit(32'h40);
        wait_clocks(300000);
        send_credit(32'h80);
        wait_clocks(300000);
        send_stop();
        wait_clocks(5000);

        `uvm_info("VSEQ", "Phase 4: Rapid 512B frames with burst credit", UVM_NONE)
        send_start(16'd512);
        send_credit(32'h10);
        wait_clocks(100000);
        send_credit(32'h20);
        wait_clocks(100000);
        send_credit(32'h30);
        wait_clocks(100000);
        send_stop();
        wait_clocks(5000);

        `uvm_info("VSEQ", "Phase 5: Max throughput - 8960B with unlimited credit", UVM_NONE)
        send_start(16'd8960);
        send_credit(32'hFFFFFFFF);
        wait_clocks(500000);
        send_stop();
        wait_clocks(5000);

        `uvm_info("VSEQ", "", UVM_NONE)
        `uvm_info("VSEQ", "========================================", UVM_NONE)
        `uvm_info("VSEQ", " Throughput Stress Test COMPLETE", UVM_NONE)
        `uvm_info("VSEQ", "========================================", UVM_NONE)
    endtask
endclass
