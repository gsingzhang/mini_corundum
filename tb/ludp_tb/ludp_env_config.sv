class ludp_env_config extends uvm_object;

    virtual xgmii_if    vif;
    virtual dut_ctrl_if ctrl_vif;
    bit                 has_scoreboard = 1;
    bit                 has_coverage   = 1;
    bit                 is_active      = UVM_ACTIVE;

    `uvm_object_utils(ludp_env_config)

    function new(string name = "ludp_env_config");
        super.new(name);
    endfunction

endclass
