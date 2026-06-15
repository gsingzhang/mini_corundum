class data_integrity_vseq extends ludp_virtual_sequence_base;
    `uvm_object_utils(data_integrity_vseq)

    bit [15:0] sizes [0:4];

    function new(string name = "data_integrity_vseq");
        super.new(name);
    endfunction

    virtual task body();
        int size_idx;
        super.body();

        sizes[0] = 16'd64; sizes[1] = 16'd128; sizes[2] = 16'd256;
        sizes[3] = 16'd512; sizes[4] = 16'd1024;

        for (size_idx = 0; size_idx < 5; size_idx++) begin
            `uvm_info("VSEQ", $sformatf("Phase %0d: Payload size = %0d bytes", size_idx + 1, sizes[size_idx]), UVM_NONE)
            reset_dut();
            send_start(sizes[size_idx]);
            send_credit(32'h3);
            wait_clocks(20000);
            send_stop();
            wait_clocks(500);
        end
    endtask
endclass
