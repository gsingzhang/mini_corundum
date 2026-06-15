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
    endtask

    virtual function void report_phase(uvm_phase phase);
        super.report_phase(phase);
    endfunction

endclass

class test_protocol_basics extends ludp_test_base;

    `uvm_component_utils(test_protocol_basics)

    function new(string name = "test_protocol_basics", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_sequence();
        protocol_basics_vseq seq;
        seq = protocol_basics_vseq::type_id::create("seq");
        seq.start(v_seqr);
    endtask

endclass

class test_cmd_lifecycle extends ludp_test_base;

    `uvm_component_utils(test_cmd_lifecycle)

    function new(string name = "test_cmd_lifecycle", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_sequence();
        cmd_lifecycle_vseq seq;
        seq = cmd_lifecycle_vseq::type_id::create("seq");
        seq.start(v_seqr);
    endtask

endclass

class test_credit_flow extends ludp_test_base;

    `uvm_component_utils(test_credit_flow)

    function new(string name = "test_credit_flow", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_sequence();
        credit_flow_vseq seq;
        seq = credit_flow_vseq::type_id::create("seq");
        seq.start(v_seqr);
    endtask

endclass

class test_data_integrity extends ludp_test_base;

    `uvm_component_utils(test_data_integrity)

    function new(string name = "test_data_integrity", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_sequence();
        data_integrity_vseq seq;
        seq = data_integrity_vseq::type_id::create("seq");
        seq.start(v_seqr);
    endtask

endclass

class test_retransmission extends ludp_test_base;

    `uvm_component_utils(test_retransmission)

    function new(string name = "test_retransmission", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_sequence();
        retransmission_vseq seq;
        seq = retransmission_vseq::type_id::create("seq");
        seq.start(v_seqr);
    endtask

endclass

class test_error_resilience extends ludp_test_base;

    `uvm_component_utils(test_error_resilience)

    function new(string name = "test_error_resilience", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_sequence();
        error_resilience_vseq seq;
        seq = error_resilience_vseq::type_id::create("seq");
        seq.start(v_seqr);
    endtask

endclass

class test_internal_mechanisms extends ludp_test_base;

    `uvm_component_utils(test_internal_mechanisms)

    function new(string name = "test_internal_mechanisms", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_sequence();
        internal_mechanisms_vseq seq;
        seq = internal_mechanisms_vseq::type_id::create("seq");
        seq.start(v_seqr);
    endtask

endclass

class test_all extends ludp_test_base;

    `uvm_component_utils(test_all)

    function new(string name = "test_all", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual task run_sequence();
        test_all_vseq seq;
        seq = test_all_vseq::type_id::create("seq");
        seq.start(v_seqr);
    endtask

endclass
