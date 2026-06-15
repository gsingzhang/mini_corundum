class ludp_env extends uvm_env;

    ludp_agent     agent;
    ludp_scoreboard scoreboard;
    ludp_coverage  coverage;

    ludp_env_config cfg;

    `uvm_component_utils(ludp_env)

    function new(string name = "ludp_env", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!uvm_config_db#(ludp_env_config)::get(this, "", "cfg", cfg)) begin
            cfg = ludp_env_config::type_id::create("cfg");
            if (!uvm_config_db#(virtual xgmii_if)::get(this, "", "vif", cfg.vif))
                `uvm_fatal("ENV", "Failed to get xgmii_if via config_db")
            if (!uvm_config_db#(virtual dut_ctrl_if)::get(this, "", "ctrl_vif", cfg.ctrl_vif))
                `uvm_fatal("ENV", "Failed to get dut_ctrl_if via config_db")
        end

        uvm_config_db#(virtual xgmii_if)::set(this, "agent", "vif", cfg.vif);
        uvm_config_db#(virtual dut_ctrl_if)::set(this, "agent", "ctrl_vif", cfg.ctrl_vif);

        if (cfg.is_active)
            uvm_config_db#(uvm_active_passive_enum)::set(this, "agent", "is_active", UVM_ACTIVE);
        else
            uvm_config_db#(uvm_active_passive_enum)::set(this, "agent", "is_active", UVM_PASSIVE);

        agent = ludp_agent::type_id::create("agent", this);

        if (cfg.has_scoreboard)
            scoreboard = ludp_scoreboard::type_id::create("scoreboard", this);

        if (cfg.has_coverage) begin
            uvm_config_db#(virtual dut_ctrl_if)::set(this, "coverage", "ctrl_vif", cfg.ctrl_vif);
            coverage = ludp_coverage::type_id::create("coverage", this);
        end
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        if (scoreboard != null)
            agent.ap.connect(scoreboard.ap);
        if (coverage != null) begin
            agent.ap.connect(coverage.rx_ap);
            agent.tx_ap.connect(coverage.tx_ap);
        end
    endfunction

endclass
