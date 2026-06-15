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
