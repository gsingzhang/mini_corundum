class ludp_agent extends uvm_agent;

    ludp_driver    driver;
    ludp_monitor   monitor;
    ludp_sequencer sequencer;

    virtual xgmii_if    vif;
    virtual dut_ctrl_if ctrl_vif;

    uvm_analysis_port #(ludp_rx_frame) ap;
    uvm_analysis_port #(ludp_txn)      tx_ap;

    `uvm_component_utils(ludp_agent)

    function new(string name = "ludp_agent", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        if (!uvm_config_db#(virtual xgmii_if)::get(this, "", "vif", vif))
            `uvm_fatal("AGT", "Failed to get xgmii_if via config_db")
        if (!uvm_config_db#(virtual dut_ctrl_if)::get(this, "", "ctrl_vif", ctrl_vif))
            `uvm_fatal("AGT", "Failed to get dut_ctrl_if via config_db")

        monitor = ludp_monitor::type_id::create("monitor", this);
        ap   = new("ap", this);
        tx_ap = new("tx_ap", this);

        if (get_is_active() == UVM_ACTIVE) begin
            driver    = ludp_driver::type_id::create("driver", this);
            sequencer = ludp_sequencer::type_id::create("sequencer", this);
            uvm_config_db#(virtual xgmii_if)::set(this, "driver", "vif", vif);
            uvm_config_db#(virtual xgmii_if)::set(this, "monitor", "vif", vif);
            uvm_config_db#(virtual dut_ctrl_if)::set(this, "driver", "ctrl_vif", ctrl_vif);
        end else begin
            uvm_config_db#(virtual xgmii_if)::set(this, "monitor", "vif", vif);
        end
    endfunction

    virtual function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        monitor.ap.connect(ap);
        if (get_is_active() == UVM_ACTIVE) begin
            driver.seq_item_port.connect(sequencer.seq_item_export);
            driver.ap.connect(tx_ap);
        end
    endfunction

endclass
