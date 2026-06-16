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
        rx_codecov_vseq          seq9;
        tx_dma_codecov_vseq      seq10;
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

        seq9 = rx_codecov_vseq::type_id::create("seq9");
        seq9.start(p_sequencer);

        seq10 = tx_dma_codecov_vseq::type_id::create("seq10");
        seq10.start(p_sequencer);

        `uvm_info("VSEQ", "", UVM_NONE)
        `uvm_info("VSEQ", "========================================", UVM_NONE)
        `uvm_info("VSEQ", " ALL TESTS COMPLETE", UVM_NONE)
        `uvm_info("VSEQ", "========================================", UVM_NONE)
    endtask
endclass
