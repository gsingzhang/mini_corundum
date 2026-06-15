class ludp_virtual_sequencer extends uvm_sequencer;

    ludp_sequencer   ludp_seqr;
    virtual xgmii_if    vif;
    virtual dut_ctrl_if ctrl_vif;

    `uvm_component_utils(ludp_virtual_sequencer)

    function new(string name = "ludp_virtual_sequencer", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual xgmii_if)::get(this, "", "vif", vif))
            `uvm_fatal("VSEQ", "Failed to get xgmii_if via config_db")
        if (!uvm_config_db#(virtual dut_ctrl_if)::get(this, "", "ctrl_vif", ctrl_vif))
            `uvm_fatal("VSEQ", "Failed to get dut_ctrl_if via config_db")
    endfunction

endclass
