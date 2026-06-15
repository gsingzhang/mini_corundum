class ludp_monitor extends uvm_monitor;

    virtual xgmii_if vif;

    uvm_analysis_port #(ludp_rx_frame) ap;

    bit [63:0] tx_capture [0:2047];
    bit [7:0]  tx_ctrl_capture [0:2047];
    int        tx_capture_len;
    int        tx_frame_count;
    bit        tx_frame_active;

    `uvm_component_utils(ludp_monitor)

    function new(string name = "ludp_monitor", uvm_component parent = null);
        super.new(name, parent);
        tx_capture_len  = 0;
        tx_frame_count  = 0;
        tx_frame_active = 0;
    endfunction

    virtual function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        ap = new("ap", this);
        if (!uvm_config_db#(virtual xgmii_if)::get(this, "", "vif", vif))
            `uvm_fatal("MON", "Failed to get xgmii_if via config_db")
    endfunction

    virtual task run_phase(uvm_phase phase);
        bit sof_detected;
        forever begin
            @(posedge vif.clk);
            if (vif.rst) begin
                tx_frame_count  = 0;
                tx_frame_active = 0;
                tx_capture_len  = 0;
            end else begin
                sof_detected = (vif.mon_cb.txc[0] && vif.mon_cb.txd[7:0] == XGMII_START) ||
                               (vif.mon_cb.txc[1] && vif.mon_cb.txd[15:8] == XGMII_START) ||
                               (vif.mon_cb.txc[2] && vif.mon_cb.txd[23:16] == XGMII_START) ||
                               (vif.mon_cb.txc[3] && vif.mon_cb.txd[31:24] == XGMII_START) ||
                               (vif.mon_cb.txc[4] && vif.mon_cb.txd[39:32] == XGMII_START) ||
                               (vif.mon_cb.txc[5] && vif.mon_cb.txd[47:40] == XGMII_START) ||
                               (vif.mon_cb.txc[6] && vif.mon_cb.txd[55:48] == XGMII_START) ||
                               (vif.mon_cb.txc[7] && vif.mon_cb.txd[63:56] == XGMII_START);

                if (sof_detected) begin
                    if (tx_frame_active) begin
                        publish_frame();
                        tx_frame_count = tx_frame_count + 1;
                    end
                    tx_frame_active = 1;
                    tx_capture_len  = 0;
                    tx_capture[0]  <= vif.mon_cb.txd;
                    tx_ctrl_capture[0] <= vif.mon_cb.txc;
                    tx_capture_len  = 1;
                end else if (vif.mon_cb.txc != 8'hff) begin
                    if (!tx_frame_active) begin
                        tx_frame_active = 1;
                        tx_capture_len  = 0;
                    end
                    if (tx_capture_len < 2048) begin
                        tx_capture[tx_capture_len] <= vif.mon_cb.txd;
                        tx_ctrl_capture[tx_capture_len] <= vif.mon_cb.txc;
                        tx_capture_len = tx_capture_len + 1;
                    end
                end else begin
                    if (tx_frame_active) begin
                        publish_frame();
                        tx_frame_active = 0;
                        tx_frame_count  = tx_frame_count + 1;
                    end
                end
            end
        end
    endtask

    task publish_frame();
        ludp_rx_frame frm;
        int i;
        begin
            frm = ludp_rx_frame::type_id::create("frm");
            frm.raw_len = tx_capture_len;
            for (i = 0; i < tx_capture_len && i < 2048; i++) begin
                frm.raw_data[i] = tx_capture[i];
                frm.raw_ctrl[i] = tx_ctrl_capture[i];
            end
            frm.parse();
            `uvm_info("MON", $sformatf("Frame detected: type=%0s ludp_type=%02h seq=%08h",
                     frm.frame_type.name(), frm.ludp_type, frm.ludp_seq), UVM_HIGH)
            ap.write(frm);
        end
    endtask

    virtual function void report_phase(uvm_phase phase);
        `uvm_info("MON", $sformatf("Total frames captured: %0d", tx_frame_count), UVM_NONE)
    endfunction

endclass
