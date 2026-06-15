class reset_and_init_vseq extends ludp_virtual_sequence_base;
    `uvm_object_utils(reset_and_init_vseq)

    function new(string name = "reset_and_init_vseq");
        super.new(name);
    endfunction

    virtual task body();
        super.body();
        reset_dut();
    endtask
endclass
