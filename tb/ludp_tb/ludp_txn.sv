class ludp_txn extends uvm_sequence_item;

    rand frame_type_e frame_type;
    rand stim_cmd_e   stim_cmd;

    rand bit [7:0]  pkt_type;
    rand bit [7:0]  flags;
    rand bit [31:0] seq_num;
    rand bit [15:0] opcode;
    rand bit [31:0] arg1;
    rand bit [15:0] arg2;
    rand int        payload_len;
    rand bit [7:0]  payload[];

    rand bit [47:0] eth_dst;
    rand bit [47:0] eth_src;

    rand bit [15:0] icmp_id;
    rand bit [15:0] icmp_seq;

    rand bit tuser_err;

    rand bit [15:0] payload_size;
    rand bit [31:0] credit;
    rand bit [31:0] nack_seq;
    rand bit [15:0] nack_count;

    constraint pkt_type_c {
        pkt_type inside {TYPE_DATA, TYPE_CMD, TYPE_NACK, TYPE_CMD_ACK, TYPE_CMD_CPL, TYPE_CREDIT};
    }

    constraint payload_len_c {
        payload_len >= 0;
        payload_len <= 8960;
        payload_len % 8 == 0;
    }

    constraint payload_size_c {
        payload_size inside {16, 32, 64, 128, 256, 512, 1024, 2048, 4096, 8960};
    }

    constraint credit_c {
        credit inside {[1:32]};
    }

    `uvm_object_utils_begin(ludp_txn)
        `uvm_field_enum(frame_type_e, frame_type, UVM_DEFAULT)
        `uvm_field_enum(stim_cmd_e, stim_cmd, UVM_DEFAULT)
        `uvm_field_int(pkt_type, UVM_DEFAULT)
        `uvm_field_int(flags, UVM_DEFAULT)
        `uvm_field_int(seq_num, UVM_DEFAULT)
        `uvm_field_int(opcode, UVM_DEFAULT)
        `uvm_field_int(arg1, UVM_DEFAULT)
        `uvm_field_int(arg2, UVM_DEFAULT)
        `uvm_field_int(payload_len, UVM_DEFAULT)
        `uvm_field_int(payload_size, UVM_DEFAULT)
        `uvm_field_int(credit, UVM_DEFAULT)
        `uvm_field_int(nack_seq, UVM_DEFAULT)
        `uvm_field_int(nack_count, UVM_DEFAULT)
        `uvm_field_int(tuser_err, UVM_DEFAULT)
    `uvm_object_utils_end

    function new(string name = "ludp_txn");
        super.new(name);
        frame_type = FRAME_UNKNOWN;
        stim_cmd   = CMD_IDLE;
        pkt_type   = TYPE_CMD;
        flags      = 8'h00;
        seq_num    = 32'h0;
        opcode     = CMD_START;
        arg1       = 32'h0;
        arg2       = 16'h0;
        payload_len = 0;
        eth_dst    = DUT_MAC;
        eth_src    = HOST_MAC;
        tuser_err  = 0;
        payload_size = 64;
        credit     = 1;
        nack_seq   = 32'h0;
        nack_count = 16'h1;
    endfunction

    function void set_cmd(input bit [15:0] op, input bit [31:0] a1,
                          input bit [15:0] a2, input bit [7:0] fl);
        stim_cmd   = CMD_LUDP_CMD;
        frame_type = FRAME_LUDP_CMD;
        pkt_type   = TYPE_CMD;
        opcode     = op;
        arg1       = a1;
        arg2       = a2;
        flags      = fl;
        payload_len = 0;
    endfunction

    function void set_credit(input bit [31:0] cr);
        stim_cmd   = CMD_LUDP_CREDIT;
        frame_type = FRAME_LUDP_CREDIT;
        pkt_type   = TYPE_CREDIT;
        seq_num    = cr;
        opcode     = 16'h0;
        arg1       = 32'h0;
        arg2       = 16'h0;
        flags      = 8'h00;
        payload_len = 0;
    endfunction

    function void set_nack(input bit [31:0] miss_seq, input bit [15:0] count);
        stim_cmd   = CMD_LUDP_NACK;
        frame_type = FRAME_LUDP_NACK;
        pkt_type   = TYPE_NACK;
        seq_num    = miss_seq;
        opcode     = count;
        arg1       = 32'h0;
        arg2       = 16'h0;
        flags      = 8'h00;
        payload_len = 0;
    endfunction

    function void set_start(input bit [15:0] psize);
        stim_cmd     = CMD_LUDP_START;
        payload_size = psize;
    endfunction

    function void set_stop();
        stim_cmd = CMD_LUDP_STOP;
    endfunction

endclass
