class ludp_virtual_sequence_base extends uvm_sequence;

    `uvm_object_utils(ludp_virtual_sequence_base)
    `uvm_declare_p_sequencer(ludp_virtual_sequencer)

    function new(string name = "ludp_virtual_sequence_base");
        super.new(name);
    endfunction

    virtual task body();
    endtask

    task reset_dut();
        ludp_base_seq seq;
        seq = ludp_base_seq::type_id::create("seq");
        seq.start(p_sequencer.ludp_seqr);
        seq.send_reset();
    endtask

    task send_start(input bit [15:0] payload_size);
        ludp_base_seq seq;
        seq = ludp_base_seq::type_id::create("seq");
        seq.start(p_sequencer.ludp_seqr);
        seq.send_start(payload_size);
    endtask

    task send_stop();
        ludp_base_seq seq;
        seq = ludp_base_seq::type_id::create("seq");
        seq.start(p_sequencer.ludp_seqr);
        seq.send_stop();
    endtask

    task send_credit(input bit [31:0] credit_val);
        ludp_base_seq seq;
        seq = ludp_base_seq::type_id::create("seq");
        seq.start(p_sequencer.ludp_seqr);
        seq.send_credit(credit_val);
    endtask

    task send_nack(input bit [31:0] miss_seq, input bit [15:0] miss_count);
        ludp_base_seq seq;
        seq = ludp_base_seq::type_id::create("seq");
        seq.start(p_sequencer.ludp_seqr);
        seq.send_nack(miss_seq, miss_count);
    endtask

    task send_cmd(input bit [15:0] opcode, input bit [31:0] arg1,
                  input bit [15:0] arg2, input bit [7:0] flags);
        ludp_base_seq seq;
        seq = ludp_base_seq::type_id::create("seq");
        seq.start(p_sequencer.ludp_seqr);
        seq.send_cmd(opcode, arg1, arg2, flags);
    endtask

    task send_arp_request();
        ludp_base_seq seq;
        seq = ludp_base_seq::type_id::create("seq");
        seq.start(p_sequencer.ludp_seqr);
        seq.send_arp_request();
    endtask

    task send_arp_reply();
        ludp_base_seq seq;
        seq = ludp_base_seq::type_id::create("seq");
        seq.start(p_sequencer.ludp_seqr);
        seq.send_arp_reply();
    endtask

    task send_icmp_request(input bit [15:0] id = 16'h1234, input bit [15:0] seq_num = 16'h0001,
                           input int plen = 56);
        ludp_base_seq seq;
        seq = ludp_base_seq::type_id::create("seq");
        seq.start(p_sequencer.ludp_seqr);
        seq.send_icmp_request(id, seq_num, plen);
    endtask

    task send_ludp_raw(input bit [7:0] pkt_type, input bit [7:0] flags,
                       input bit [31:0] seq_num, input bit [15:0] opcode,
                       input bit [31:0] arg1, input bit [15:0] arg2,
                       input int payload_len, input bit tuser_err = 0);
        ludp_base_seq seq;
        seq = ludp_base_seq::type_id::create("seq");
        seq.start(p_sequencer.ludp_seqr);
        seq.send_ludp_raw(pkt_type, flags, seq_num, opcode, arg1, arg2, payload_len, tuser_err);
    endtask

    task wait_clocks(input int n);
        repeat(n) @(posedge p_sequencer.vif.clk);
    endtask

    function bit [31:0] get_tx_seq_num();
        return p_sequencer.ctrl_vif.get_tx_seq_num();
    endfunction

    function bit get_tx_enabled();
        return p_sequencer.ctrl_vif.get_tx_enabled();
    endfunction

    function bit get_dma_wr_enable();
        return p_sequencer.ctrl_vif.get_dma_wr_enable();
    endfunction

    task inject_status(input bit [15:0] opcode, input bit [31:0] data);
        p_sequencer.ctrl_vif.inject_status(opcode, data);
    endtask

endclass

class reset_and_init_vseq extends ludp_virtual_sequence_base;
    `uvm_object_utils(reset_and_init_vseq)

    function new(string name = "reset_and_init_vseq");
        super.new(name);
    endfunction

    virtual task body();
        super.body();
        reset_dut();
    endtask
endclass

class protocol_basics_vseq extends ludp_virtual_sequence_base;
    `uvm_object_utils(protocol_basics_vseq)

    function new(string name = "protocol_basics_vseq");
        super.new(name);
    endfunction

    virtual task body();
        super.body();

        `uvm_info("VSEQ", "Phase A: ARP resolution", UVM_NONE)
        reset_dut();
        wait_clocks(5000);

        `uvm_info("VSEQ", "Phase B: ICMP echo reply", UVM_NONE)
        send_icmp_request();
        wait_clocks(5000);

        `uvm_info("VSEQ", "Phase C: CMD_START + credit -> data", UVM_NONE)
        send_start(16'd64);
        send_credit(32'h2);
        wait_clocks(20000);
        send_stop();
        wait_clocks(2000);

        `uvm_info("VSEQ", "Phase D: CMD_STOP -> no more data", UVM_NONE)
        wait_clocks(2000);
    endtask
endclass

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

class data_integrity_vseq extends ludp_virtual_sequence_base;
    `uvm_object_utils(data_integrity_vseq)

    bit [15:0] sizes [0:4];

    function new(string name = "data_integrity_vseq");
        super.new(name);
    endfunction

    virtual task body();
        int size_idx;
        super.body();

        sizes[0] = 16'd64; sizes[1] = 16'd128; sizes[2] = 16'd256;
        sizes[3] = 16'd512; sizes[4] = 16'd1024;

        for (size_idx = 0; size_idx < 5; size_idx++) begin
            `uvm_info("VSEQ", $sformatf("Phase %0d: Payload size = %0d bytes", size_idx + 1, sizes[size_idx]), UVM_NONE)
            reset_dut();
            send_start(sizes[size_idx]);
            send_credit(32'h3);
            wait_clocks(20000);
            send_stop();
            wait_clocks(500);
        end
    endtask
endclass

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

class test_all_vseq extends ludp_virtual_sequence_base;
    `uvm_object_utils(test_all_vseq)

    function new(string name = "test_all_vseq");
        super.new(name);
    endfunction

    virtual task body();
        protocol_basics_vseq     seq1;
        cmd_lifecycle_vseq       seq2;
        credit_flow_vseq         seq3;
        data_integrity_vseq      seq4;
        retransmission_vseq      seq5;
        error_resilience_vseq    seq6;
        internal_mechanisms_vseq seq7;
        coverage_enhance_vseq    seq8;
        super.body();

        `uvm_info("VSEQ", "", UVM_NONE)
        `uvm_info("VSEQ", "========================================", UVM_NONE)
        `uvm_info("VSEQ", " Running All Tests via Virtual Sequence", UVM_NONE)
        `uvm_info("VSEQ", "========================================", UVM_NONE)

        seq1 = protocol_basics_vseq::type_id::create("seq1");
        seq1.start(p_sequencer);

        seq2 = cmd_lifecycle_vseq::type_id::create("seq2");
        seq2.start(p_sequencer);

        seq3 = credit_flow_vseq::type_id::create("seq3");
        seq3.start(p_sequencer);

        seq4 = data_integrity_vseq::type_id::create("seq4");
        seq4.start(p_sequencer);

        seq5 = retransmission_vseq::type_id::create("seq5");
        seq5.start(p_sequencer);

        seq6 = error_resilience_vseq::type_id::create("seq6");
        seq6.start(p_sequencer);

        seq7 = internal_mechanisms_vseq::type_id::create("seq7");
        seq7.start(p_sequencer);

        seq8 = coverage_enhance_vseq::type_id::create("seq8");
        seq8.start(p_sequencer);

        `uvm_info("VSEQ", "", UVM_NONE)
        `uvm_info("VSEQ", "========================================", UVM_NONE)
        `uvm_info("VSEQ", " ALL TESTS COMPLETE", UVM_NONE)
        `uvm_info("VSEQ", "========================================", UVM_NONE)
    endtask
endclass
