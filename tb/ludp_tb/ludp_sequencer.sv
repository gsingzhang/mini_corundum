class ludp_sequencer extends uvm_sequencer #(ludp_txn);
    `uvm_component_utils(ludp_sequencer)

    function new(string name = "ludp_sequencer", uvm_component parent = null);
        super.new(name, parent);
    endfunction
endclass
