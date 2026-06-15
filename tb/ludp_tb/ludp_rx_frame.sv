class ludp_rx_frame extends uvm_sequence_item;

    bit [63:0] raw_data [0:2047];
    bit [7:0]  raw_ctrl [0:2047];
    int        raw_len;

    bit [47:0] eth_dst;
    bit [47:0] eth_src;
    bit [15:0] eth_type;

    bit [31:0] ip_src;
    bit [31:0] ip_dst;
    bit [7:0]  ip_proto;
    bit [15:0] ip_len;

    bit [15:0] udp_src_port;
    bit [15:0] udp_dst_port;
    bit [15:0] udp_len;
    bit [15:0] udp_checksum;

    bit [15:0] ludp_magic;
    bit [7:0]  ludp_type;
    bit [7:0]  ludp_flags;
    bit [31:0] ludp_seq;
    bit [15:0] ludp_opcode;
    bit [31:0] ludp_arg1;
    bit [15:0] ludp_arg2;
    bit [15:0] ludp_pay_len;

    bit [7:0]  ludp_payload [];
    int        ludp_payload_beats;

    bit [7:0]  icmp_type;
    bit [7:0]  icmp_code;
    bit [15:0] icmp_id;
    bit [15:0] icmp_seq;

    bit [15:0] arp_opcode;

    frame_type_e frame_type;

    `uvm_object_utils_begin(ludp_rx_frame)
        `uvm_field_enum(frame_type_e, frame_type, UVM_DEFAULT)
        `uvm_field_int(eth_type, UVM_DEFAULT)
        `uvm_field_int(ludp_type, UVM_DEFAULT)
        `uvm_field_int(ludp_seq, UVM_DEFAULT)
        `uvm_field_int(ludp_opcode, UVM_DEFAULT)
        `uvm_field_int(ludp_pay_len, UVM_DEFAULT)
    `uvm_object_utils_end

    function new(string name = "ludp_rx_frame");
        super.new(name);
        raw_len = 0;
        frame_type = FRAME_UNKNOWN;
    endfunction

    function bit [7:0] get_byte(input int pos);
        int beat;
        int lane;
        int actual_pos;
        actual_pos = pos + 8;
        beat = actual_pos / 8;
        lane = actual_pos % 8;
        if (beat < raw_len)
            return raw_data[beat][lane*8 +: 8];
        else
            return 8'h00;
    endfunction

    function void parse();
        if (raw_len < 3) begin
            return;
        end

        eth_dst  = {get_byte(0), get_byte(1), get_byte(2),
                    get_byte(3), get_byte(4), get_byte(5)};
        eth_src  = {get_byte(6), get_byte(7), get_byte(8),
                    get_byte(9), get_byte(10), get_byte(11)};
        eth_type = {get_byte(12), get_byte(13)};

        if (eth_type == 16'h0806) begin
            arp_opcode = {get_byte(20), get_byte(21)};
            if (arp_opcode == 16'h0001)
                frame_type = FRAME_ARP_REQUEST;
            else if (arp_opcode == 16'h0002)
                frame_type = FRAME_ARP_REPLY;
            return;
        end

        if (eth_type == 16'h0800) begin
            ip_proto = get_byte(23);
            ip_src   = {get_byte(26), get_byte(27), get_byte(28), get_byte(29)};
            ip_dst   = {get_byte(30), get_byte(31), get_byte(32), get_byte(33)};
            ip_len   = {get_byte(16), get_byte(17)};

            if (ip_proto == 8'h01) begin
                icmp_type = get_byte(34);
                icmp_code = get_byte(35);
                icmp_id   = {get_byte(38), get_byte(39)};
                icmp_seq  = {get_byte(40), get_byte(41)};
                if (icmp_type == 8'h00)
                    frame_type = FRAME_ICMP_REPLY;
                else if (icmp_type == 8'h08)
                    frame_type = FRAME_ICMP_REQUEST;
                return;
            end

            if (ip_proto == 8'h11) begin
                udp_src_port = {get_byte(34), get_byte(35)};
                udp_dst_port = {get_byte(36), get_byte(37)};
                udp_len      = {get_byte(38), get_byte(39)};
                udp_checksum = {get_byte(40), get_byte(41)};

                ludp_magic   = {get_byte(43), get_byte(42)};
                ludp_type    = get_byte(44);
                ludp_flags   = get_byte(45);
                ludp_seq     = {get_byte(49), get_byte(48), get_byte(47), get_byte(46)};
                ludp_opcode  = {get_byte(51), get_byte(50)};
                ludp_arg1    = {get_byte(55), get_byte(54), get_byte(53), get_byte(52)};
                ludp_arg2    = {get_byte(57), get_byte(56)};
                ludp_pay_len = {get_byte(51), get_byte(50)};

                case (ludp_type)
                    TYPE_DATA: begin
                        frame_type = FRAME_LUDP_DATA;
                        ludp_pay_len = ludp_arg2;
                        ludp_payload_beats = ludp_pay_len / 8;
                    end
                    TYPE_CMD_ACK: frame_type = FRAME_LUDP_ACK;
                    TYPE_CMD_CPL: frame_type = FRAME_LUDP_CPL;
                    TYPE_CMD:     frame_type = FRAME_LUDP_CMD;
                    TYPE_CREDIT:  frame_type = FRAME_LUDP_CREDIT;
                    TYPE_NACK:    frame_type = FRAME_LUDP_NACK;
                    default:      frame_type = FRAME_UNKNOWN;
                endcase
            end
        end
    endfunction

    function bit verify_prbs(output int err_count);
        int num_beats;
        int beat_idx;
        bit [63:0] payload_beat;
        int byte_offset;
        bit [15:0] rx_pkt_idx;
        bit [15:0] rx_beat_idx;
        bit [31:0] rx_marker;

        err_count = 0;
        if (frame_type != FRAME_LUDP_DATA) begin
            err_count = 1;
            return 0;
        end

        num_beats = ludp_pay_len / 8;
        for (beat_idx = 0; beat_idx < num_beats; beat_idx++) begin
            byte_offset = 58 + beat_idx * 8;
            payload_beat[63:56] = get_byte(byte_offset + 7);
            payload_beat[55:48] = get_byte(byte_offset + 6);
            payload_beat[47:40] = get_byte(byte_offset + 5);
            payload_beat[39:32] = get_byte(byte_offset + 4);
            payload_beat[31:24] = get_byte(byte_offset + 3);
            payload_beat[23:16] = get_byte(byte_offset + 2);
            payload_beat[15:8]  = get_byte(byte_offset + 1);
            payload_beat[7:0]   = get_byte(byte_offset);

            rx_marker   = payload_beat[31:0];
            rx_beat_idx = payload_beat[47:32];
            rx_pkt_idx  = payload_beat[63:48];

            if (rx_marker !== 32'hA5A5A5A5 ||
                rx_pkt_idx !== ludp_seq[15:0] ||
                rx_beat_idx !== beat_idx[15:0])
                err_count++;
        end

        return (err_count == 0);
    endfunction

endclass
