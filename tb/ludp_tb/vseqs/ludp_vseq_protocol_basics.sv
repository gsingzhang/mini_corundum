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
