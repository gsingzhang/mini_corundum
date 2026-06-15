class ludp_test_base extends uvm_test;

    ludp_env             env;
    ludp_virtual_sequencer v_seqr;

    `uvm_component_utils(ludp_test_base)

    function new(string name = "ludp_test_base", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        env = ludp_env::type_id::create("env", this);
        v_seqr = ludp_virtual_sequencer::type_id::create("v_seqr", this);
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        v_seqr.ludp_seqr = env.agent.sequencer;
    endfunction

    virtual task run_phase(uvm_phase phase);
        phase.raise_objection(this);
        run_sequence();
        phase.drop_objection(this);
    endtask

    virtual task run_sequence();
        string vseq_name;
        uvm_sequence_base seq;
        uvm_factory factory;
        uvm_object_wrapper wrapper;

        factory = uvm_factory::get();

        void'(uvm_cmdline_processor::get_inst().get_arg_value("+UVM_VSEQ=", vseq_name));

        if (vseq_name == "")
            vseq_name = "test_all_vseq";

        `uvm_info("TEST", $sformatf("Running virtual sequence: %s", vseq_name), UVM_NONE)

        if (!$cast(seq, factory.create_object_by_name(vseq_name, get_full_name(), "seq"))) begin
            `uvm_error("TEST", $sformatf("Failed to create virtual sequence '%s' via factory. Available: test_all_vseq, protocol_basics_vseq, cmd_lifecycle_vseq, credit_flow_vseq, data_integrity_vseq, retransmission_vseq, error_resilience_vseq, internal_mechanisms_vseq, coverage_enhance_vseq, reset_and_init_vseq", vseq_name))
            return;
        end

        seq.start(v_seqr);
    endtask

    virtual function void report_phase(uvm_phase phase);
        super.report_phase(phase);
    endfunction

endclass
