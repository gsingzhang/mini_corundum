class ludp_base_seq extends uvm_sequence #(ludp_txn);
    `uvm_object_utils(ludp_base_seq)

    function new(string name = "ludp_base_seq");
        super.new(name);
    endfunction

    virtual task body();
    endtask

    task send_start(input bit [15:0] payload_size);
        ludp_txn txn;
        txn = ludp_txn::type_id::create("txn");
        start_item(txn);
        txn.set_start(payload_size);
        finish_item(txn);
    endtask

    task send_stop();
        ludp_txn txn;
        txn = ludp_txn::type_id::create("txn");
        start_item(txn);
        txn.set_stop();
        finish_item(txn);
    endtask

    task send_credit(input bit [31:0] credit_val);
        ludp_txn txn;
        txn = ludp_txn::type_id::create("txn");
        start_item(txn);
        txn.set_credit(credit_val);
        finish_item(txn);
    endtask

    task send_nack(input bit [31:0] miss_seq, input bit [15:0] miss_count);
        ludp_txn txn;
        txn = ludp_txn::type_id::create("txn");
        start_item(txn);
        txn.set_nack(miss_seq, miss_count);
        finish_item(txn);
    endtask

    task send_cmd(input bit [15:0] opcode, input bit [31:0] arg1,
                  input bit [15:0] arg2, input bit [7:0] flags);
        ludp_txn txn;
        txn = ludp_txn::type_id::create("txn");
        start_item(txn);
        txn.set_cmd(opcode, arg1, arg2, flags);
        finish_item(txn);
    endtask

    task send_arp_request();
        ludp_txn txn;
        txn = ludp_txn::type_id::create("txn");
        start_item(txn);
        txn.stim_cmd = CMD_ARP_REQUEST;
        finish_item(txn);
    endtask

    task send_arp_reply();
        ludp_txn txn;
        txn = ludp_txn::type_id::create("txn");
        start_item(txn);
        txn.stim_cmd = CMD_ARP_REPLY;
        finish_item(txn);
    endtask

    task send_icmp_request(input bit [15:0] id = 16'h1234, input bit [15:0] seq_num = 16'h0001,
                           input int plen = 56);
        ludp_txn txn;
        txn = ludp_txn::type_id::create("txn");
        start_item(txn);
        txn.stim_cmd = CMD_ICMP_REQUEST;
        txn.icmp_id = id;
        txn.icmp_seq = seq_num;
        txn.payload_len = plen;
        finish_item(txn);
    endtask

    task send_idle();
        ludp_txn txn;
        txn = ludp_txn::type_id::create("txn");
        start_item(txn);
        txn.stim_cmd = CMD_IDLE;
        finish_item(txn);
    endtask

    task send_reset();
        ludp_txn txn;
        txn = ludp_txn::type_id::create("txn");
        start_item(txn);
        txn.stim_cmd = CMD_RESET;
        finish_item(txn);
    endtask

    task send_ludp_raw(input bit [7:0] pkt_type, input bit [7:0] flags,
                       input bit [31:0] seq_num, input bit [15:0] opcode,
                       input bit [31:0] arg1, input bit [15:0] arg2,
                       input int payload_len, input bit tuser_err = 0);
        ludp_txn txn;
        txn = ludp_txn::type_id::create("txn");
        start_item(txn);
        txn.stim_cmd = CMD_LUDP_CMD;
        txn.pkt_type = pkt_type;
        txn.flags    = flags;
        txn.seq_num  = seq_num;
        txn.opcode   = opcode;
        txn.arg1     = arg1;
        txn.arg2     = arg2;
        txn.payload_len = payload_len;
        txn.tuser_err = tuser_err;
        finish_item(txn);
    endtask

    task send_ludp_raw_with_magic(input bit [15:0] magic_val,
                                  input bit [7:0] pkt_type, input bit [7:0] flags,
                                  input bit [31:0] seq_num, input bit [15:0] opcode,
                                  input bit [31:0] arg1, input bit [15:0] arg2,
                                  input int payload_len);
        ludp_txn txn;
        txn = ludp_txn::type_id::create("txn");
        start_item(txn);
        txn.stim_cmd = CMD_LUDP_CMD;
        txn.pkt_type = pkt_type;
        txn.flags    = flags;
        txn.seq_num  = seq_num;
        txn.opcode   = opcode;
        txn.arg1     = arg1;
        txn.arg2     = arg2;
        txn.payload_len = payload_len;
        txn.magic_val = magic_val;
        txn.use_custom_magic = 1'b1;
        txn.tuser_err = 1'b0;
        finish_item(txn);
    endtask

endclass
