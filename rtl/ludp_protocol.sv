module ludp_protocol #(
    parameter int DATA_WIDTH = 64,
    parameter int KEEP_WIDTH = 8,
    parameter int RETRY_TIMEOUT = 10000
)(
    input  wire        clk,
    input  wire        rst,

    input  wire [47:0] local_mac,
    input  wire [31:0] local_ip,
    input  wire [47:0] host_mac,
    input  wire [31:0] host_ip,
    input  wire [15:0] udp_port,

    output logic [15:0] cmd_opcode,
    output logic [31:0] cmd_arg1,
    output logic [15:0] cmd_arg2,
    output logic        cmd_valid,
    input  wire         cmd_ready,

    input  wire  [15:0] status_opcode,
    input  wire  [31:0] status_data,
    input  wire         status_valid,
    output logic        status_ready,

    input  wire [DATA_WIDTH-1:0] tx_data_axis_tdata,
    input  wire [KEEP_WIDTH-1:0] tx_data_axis_tkeep,
    input  wire                  tx_data_axis_tvalid,
    output logic                 tx_data_axis_tready,
    input  wire                  tx_data_axis_tlast,
    input  wire                  tx_data_axis_tuser,

    input  wire        rx_udp_hdr_valid,
    output logic       rx_udp_hdr_ready,
    input  wire [47:0] rx_udp_eth_dest_mac,
    input  wire [47:0] rx_udp_eth_src_mac,
    input  wire [15:0] rx_udp_eth_type,
    input  wire [31:0] rx_udp_ip_source_ip,
    input  wire [31:0] rx_udp_ip_dest_ip,
    input  wire [15:0] rx_udp_source_port,
    input  wire [15:0] rx_udp_dest_port,
    input  wire [15:0] rx_udp_length,
    input  wire [15:0] rx_udp_checksum,
    input  wire [DATA_WIDTH-1:0] rx_udp_payload_axis_tdata,
    input  wire [KEEP_WIDTH-1:0] rx_udp_payload_axis_tkeep,
    input  wire                  rx_udp_payload_axis_tvalid,
    output logic                 rx_udp_payload_axis_tready,
    input  wire                  rx_udp_payload_axis_tlast,
    input  wire                  rx_udp_payload_axis_tuser,

    output logic       tx_udp_hdr_valid,
    input  wire        tx_udp_hdr_ready,
    output logic [5:0] tx_udp_ip_dscp,
    output logic [1:0] tx_udp_ip_ecn,
    output logic [7:0] tx_udp_ip_ttl,
    output logic [31:0] tx_udp_ip_source_ip,
    output logic [31:0] tx_udp_ip_dest_ip,
    output logic [15:0] tx_udp_source_port,
    output logic [15:0] tx_udp_dest_port,
    output logic [15:0] tx_udp_length,
    output logic [15:0] tx_udp_checksum,
    output logic [DATA_WIDTH-1:0] tx_udp_payload_axis_tdata,
    output logic [KEEP_WIDTH-1:0] tx_udp_payload_axis_tkeep,
    output logic                  tx_udp_payload_axis_tvalid,
    input  wire                   tx_udp_payload_axis_tready,
    output logic                  tx_udp_payload_axis_tlast,
    output logic                  tx_udp_payload_axis_tuser,

    output logic [31:0] tx_seq_num,
    output logic [31:0] rx_credit_limit,
    output logic        burst_active,
    output logic [31:0] packets_sent,
    output logic [31:0] packets_retx,
    output logic [31:0] cmd_count
);

localparam logic [15:0] MAGIC = 16'hDA01;

localparam logic [7:0] TYPE_DATA    = 8'h01;
localparam logic [7:0] TYPE_CMD     = 8'h02;
localparam logic [7:0] TYPE_NACK    = 8'h03;
localparam logic [7:0] TYPE_CMD_ACK = 8'h04;
localparam logic [7:0] TYPE_CMD_CPL = 8'h05;
localparam logic [7:0] TYPE_CREDIT  = 8'h06;

localparam logic [15:0] CMD_START      = 16'h0001;
localparam logic [15:0] CMD_STOP       = 16'h0002;
localparam logic [15:0] CMD_READ_REG   = 16'h0010;
localparam logic [15:0] CMD_WRITE_REG  = 16'h0011;

localparam logic [15:0] DATA_UDP_LENGTH = 16'd88;  // 8(UDP hdr) + 16(LUDP hdr) + 64(data payload)
localparam logic [15:0] RESP_UDP_LENGTH = 16'd24;  // 8(UDP hdr) + 16(LUDP hdr)

typedef enum logic [2:0] {
    STATE_IDLE,
    STATE_RX_CMD,
    STATE_TX_HEADER,
    STATE_TX_DATA,
    STATE_TX_RESP
} state_t;

state_t state_reg, state_next;

logic [31:0] seq_num_reg;
logic [31:0] abs_credit_reg;
logic        burst_active_reg;
logic [31:0] cmd_count_reg;
logic [31:0] packets_sent_reg;
logic [31:0] packets_retx_reg;

logic [15:0] rx_magic_reg;
logic [7:0]  rx_type_reg;
logic [7:0]  rx_flags_reg;
logic [31:0] rx_seq_reg;
logic [15:0] rx_opcode_reg;
logic [31:0] rx_arg1_reg;
logic [15:0] rx_arg2_reg;
logic [31:0] rx_cmd_id_reg;
logic [31:0] rx_miss_seq_reg;
logic [15:0] rx_count_reg;
logic [31:0] rx_abs_credit_reg;

logic [15:0] resp_opcode_reg;
logic [31:0] resp_cmd_id_reg;
logic [7:0]  resp_status_reg;
logic [31:0] resp_data_reg;
logic        resp_valid_reg;
logic        resp_is_cpl_reg;

logic [15:0] cmd_opcode_reg;
logic [31:0] cmd_arg1_reg;
logic [15:0] cmd_arg2_reg;
logic        cmd_valid_reg;

logic [3:0]  tx_beat_count_reg;
logic [63:0] tx_header_beat0_reg;
logic [63:0] tx_header_beat1_reg;
logic        tx_hdr_sent_reg;
logic        tx_is_data_reg;

// Packet processing registers (updated in RX_CMD, used in IDLE)
logic [15:0] rx_pkt_magic_reg;
logic [7:0]  rx_pkt_type_reg;
logic [7:0]  rx_pkt_flags_reg;
logic [31:0] rx_pkt_seq_reg;
logic [15:0] rx_pkt_opcode_reg;
logic [31:0] rx_pkt_arg1_reg;
logic [15:0] rx_pkt_arg2_reg;
logic        rx_pkt_valid_reg;



wire can_send = burst_active_reg && (seq_num_reg < abs_credit_reg);

// Combinational packet parsing from RX payload
wire [15:0] rx_pkt_magic  = (tx_beat_count_reg == 0) ? rx_udp_payload_axis_tdata[15:0] : rx_magic_reg;
wire [7:0]  rx_pkt_type   = (tx_beat_count_reg == 0) ? rx_udp_payload_axis_tdata[23:16] : rx_type_reg;
wire [7:0]  rx_pkt_flags  = (tx_beat_count_reg == 0) ? rx_udp_payload_axis_tdata[31:24] : rx_flags_reg;
wire [31:0] rx_pkt_seq    = (tx_beat_count_reg == 0) ? rx_udp_payload_axis_tdata[63:32] : rx_seq_reg;
wire [15:0] rx_pkt_opcode = rx_udp_payload_axis_tdata[15:0];
wire [31:0] rx_pkt_arg1   = rx_udp_payload_axis_tdata[47:16];
wire [15:0] rx_pkt_arg2   = rx_udp_payload_axis_tdata[63:48];



assign tx_seq_num = seq_num_reg;
assign rx_credit_limit = abs_credit_reg;
assign burst_active = burst_active_reg;
assign packets_sent = packets_sent_reg;
assign packets_retx = packets_retx_reg;
assign cmd_count = cmd_count_reg;

assign cmd_opcode = cmd_opcode_reg;
assign cmd_arg1 = cmd_arg1_reg;
assign cmd_arg2 = cmd_arg2_reg;
assign cmd_valid = cmd_valid_reg;
assign status_ready = 1'b1;

always_comb begin
    state_next = state_reg;

    case (state_reg)
        STATE_IDLE: begin
            if (rx_udp_hdr_valid && rx_udp_hdr_ready) begin
                state_next = STATE_RX_CMD;
            end else if (resp_valid_reg) begin
                state_next = STATE_TX_RESP;
            end else if (tx_data_axis_tvalid && can_send) begin
                state_next = STATE_TX_HEADER;
            end
        end

        STATE_RX_CMD: begin
            if (rx_udp_payload_axis_tvalid && rx_udp_payload_axis_tready && rx_udp_payload_axis_tlast)
                state_next = STATE_IDLE;
        end

        STATE_TX_HEADER: begin
            // Stay in header state until both header beats are transferred
            if (tx_beat_count_reg >= 4'd2)
                state_next = STATE_TX_DATA;
        end

        STATE_TX_DATA: begin
            if (tx_udp_payload_axis_tvalid && tx_udp_payload_axis_tready && tx_udp_payload_axis_tlast)
                state_next = STATE_IDLE;
        end

        STATE_TX_RESP: begin
            if (tx_udp_payload_axis_tvalid && tx_udp_payload_axis_tready && tx_udp_payload_axis_tlast)
                state_next = STATE_IDLE;
        end

        default: state_next = STATE_IDLE;
    endcase
end

assign rx_udp_hdr_ready = (state_reg == STATE_IDLE) || (state_reg == STATE_RX_CMD);
assign rx_udp_payload_axis_tready = (state_reg == STATE_RX_CMD) || (state_reg == STATE_IDLE);

always_comb begin
    tx_udp_hdr_valid = 0;
    if (state_reg == STATE_TX_HEADER)
        tx_udp_hdr_valid = 1;
    else if (state_reg == STATE_TX_RESP && !tx_hdr_sent_reg)
        tx_udp_hdr_valid = 1;
end

assign tx_udp_ip_dscp = 6'h0;
assign tx_udp_ip_ecn = 2'h0;
assign tx_udp_ip_ttl = 8'd64;
assign tx_udp_ip_source_ip = local_ip;
assign tx_udp_ip_dest_ip = host_ip;
assign tx_udp_checksum = 16'h0;
assign tx_udp_source_port = udp_port;
assign tx_udp_dest_port = udp_port;

always_comb begin
    tx_udp_length = RESP_UDP_LENGTH;
    if (state_reg == STATE_TX_HEADER || state_reg == STATE_TX_DATA)
        tx_udp_length = DATA_UDP_LENGTH;
end

always_comb begin
    tx_udp_payload_axis_tdata = {DATA_WIDTH{1'b0}};
    tx_udp_payload_axis_tkeep = {KEEP_WIDTH{1'b1}};
    tx_udp_payload_axis_tvalid = 1'b0;
    tx_udp_payload_axis_tlast = 1'b0;

    if (state_reg == STATE_TX_HEADER) begin
        tx_udp_payload_axis_tvalid = 1'b1;
        tx_udp_payload_axis_tkeep = {KEEP_WIDTH{1'b1}};
        case (tx_beat_count_reg)
            4'd0: begin
                tx_udp_payload_axis_tdata = tx_header_beat0_reg;
                tx_udp_payload_axis_tlast = 1'b0;
            end
            4'd1: begin
                tx_udp_payload_axis_tdata = tx_header_beat1_reg;
                tx_udp_payload_axis_tlast = 1'b0;
            end
            default: begin
                tx_udp_payload_axis_tdata = tx_data_axis_tdata;
                tx_udp_payload_axis_tlast = tx_data_axis_tlast;
            end
        endcase
    end else if (state_reg == STATE_TX_DATA) begin
        tx_udp_payload_axis_tdata = tx_data_axis_tdata;
        tx_udp_payload_axis_tkeep = tx_data_axis_tkeep;
        tx_udp_payload_axis_tvalid = tx_data_axis_tvalid;
        tx_udp_payload_axis_tlast = tx_data_axis_tlast;
    end else if (state_reg == STATE_TX_RESP) begin
        tx_udp_payload_axis_tvalid = 1'b1;
        tx_udp_payload_axis_tkeep = {KEEP_WIDTH{1'b1}};
        case (tx_beat_count_reg)
            4'd0: begin
                tx_udp_payload_axis_tdata = tx_header_beat0_reg;
                tx_udp_payload_axis_tlast = 1'b0;
            end
            4'd1: begin
                tx_udp_payload_axis_tdata = tx_header_beat1_reg;
                tx_udp_payload_axis_tlast = 1'b1;
            end
            default: begin
                tx_udp_payload_axis_tdata = tx_header_beat1_reg;
                tx_udp_payload_axis_tlast = 1'b1;
            end
        endcase
    end
end

assign tx_udp_payload_axis_tuser = 1'b0;
assign tx_data_axis_tready = (state_reg == STATE_TX_DATA) && tx_udp_payload_axis_tready;

always_ff @(posedge clk) begin
    if (rst) begin
        state_reg <= STATE_IDLE;
        seq_num_reg <= 0;
        abs_credit_reg <= 0;
        burst_active_reg <= 0;
        cmd_count_reg <= 0;
        packets_sent_reg <= 0;
        packets_retx_reg <= 0;
        rx_magic_reg <= 0;
        rx_type_reg <= 0;
        rx_flags_reg <= 0;
        rx_seq_reg <= 0;
        rx_opcode_reg <= 0;
        rx_arg1_reg <= 0;
        rx_arg2_reg <= 0;
        rx_cmd_id_reg <= 0;
        rx_miss_seq_reg <= 0;
        rx_count_reg <= 0;
        rx_abs_credit_reg <= 0;
        resp_opcode_reg <= 0;
        resp_cmd_id_reg <= 0;
        resp_status_reg <= 0;
        resp_data_reg <= 0;
        resp_valid_reg <= 0;
        resp_is_cpl_reg <= 0;
        cmd_opcode_reg <= 0;
        cmd_arg1_reg <= 0;
        cmd_arg2_reg <= 0;
        cmd_valid_reg <= 0;
        tx_beat_count_reg <= 0;
        tx_header_beat0_reg <= 0;
        tx_header_beat1_reg <= 0;
        tx_hdr_sent_reg <= 0;
        tx_is_data_reg <= 0;
        rx_pkt_magic_reg <= 0;
        rx_pkt_type_reg <= 0;
        rx_pkt_flags_reg <= 0;
        rx_pkt_seq_reg <= 0;
        rx_pkt_opcode_reg <= 0;
        rx_pkt_arg1_reg <= 0;
        rx_pkt_arg2_reg <= 0;
        rx_pkt_valid_reg <= 0;
    end else begin
        cmd_valid_reg <= 1'b0;

        case (state_reg)
            STATE_IDLE: begin
                tx_hdr_sent_reg <= 0;
                tx_beat_count_reg <= 0;

                if (rx_pkt_valid_reg) begin
                    // Process packet received in previous RX_CMD state
                    rx_pkt_valid_reg <= 1'b0;
                    if (rx_pkt_magic_reg == MAGIC) begin
                            case (rx_pkt_type_reg)
                            TYPE_CMD: begin
                                cmd_opcode_reg <= rx_pkt_opcode_reg;
                                cmd_arg1_reg <= rx_pkt_arg1_reg;
                                cmd_arg2_reg <= rx_pkt_arg2_reg;
                                cmd_valid_reg <= 1'b1;
                                cmd_count_reg <= cmd_count_reg + 1;

                                if (rx_pkt_flags_reg == 8'h00) begin
                                    resp_opcode_reg <= rx_pkt_opcode_reg;
                                    resp_cmd_id_reg <= rx_pkt_seq_reg;
                                    resp_status_reg <= 8'h00;
                                    resp_data_reg <= 32'h0;
                                    resp_valid_reg <= 1'b1;
                                    resp_is_cpl_reg <= 1'b0;
                                end else begin
                                    resp_opcode_reg <= rx_pkt_opcode_reg;
                                    resp_cmd_id_reg <= rx_pkt_seq_reg;
                                    resp_status_reg <= 8'h00;
                                    resp_data_reg <= {burst_active_reg, 31'h0};
                                    resp_valid_reg <= 1'b1;
                                    resp_is_cpl_reg <= 1'b1;
                                end

                                case (rx_pkt_opcode_reg)
                                    CMD_START: begin
                                        burst_active_reg <= 1'b1;
                                    end
                                    CMD_STOP: begin
                                        burst_active_reg <= 1'b0;
                                    end
                                    CMD_WRITE_REG: begin
                                    end
                                    CMD_READ_REG: begin
                                    end
                                    default: begin
                                    end
                                endcase
                            end

                            TYPE_NACK: begin
                                packets_retx_reg <= packets_retx_reg + 1;
                            end

                            TYPE_CREDIT: begin
                                abs_credit_reg <= rx_pkt_seq_reg;
                            end

                            default: begin
                            end
                        endcase
                    end
                end else if (rx_udp_hdr_valid && rx_udp_hdr_ready) begin
                    rx_magic_reg <= 0;
                    rx_type_reg <= 0;
                    rx_flags_reg <= 0;
                    rx_seq_reg <= 0;
                end else if (resp_valid_reg) begin
                    tx_hdr_sent_reg <= 0;
                    tx_beat_count_reg <= 0;
                    tx_is_data_reg <= 1'b0;
                    if (resp_is_cpl_reg) begin
                        tx_header_beat0_reg <= {resp_cmd_id_reg, resp_status_reg, TYPE_CMD_CPL, MAGIC};
                        tx_header_beat1_reg <= {16'h0000, resp_data_reg, resp_opcode_reg};
                    end else begin
                        tx_header_beat0_reg <= {resp_cmd_id_reg, resp_status_reg, TYPE_CMD_ACK, MAGIC};
                        tx_header_beat1_reg <= {48'h0, resp_opcode_reg};
                    end
                end else if (tx_data_axis_tvalid && can_send) begin
                    tx_header_beat0_reg <= {seq_num_reg, 8'h00, TYPE_DATA, MAGIC};
                    tx_header_beat1_reg <= {16'h0000, 32'h0, 16'd1024};
                    tx_hdr_sent_reg <= 0;
                    tx_beat_count_reg <= 0;
                    tx_is_data_reg <= 1'b1;
                end
            end

            STATE_RX_CMD: begin
                rx_pkt_valid_reg <= 1'b0;
                if (rx_udp_payload_axis_tvalid && rx_udp_payload_axis_tready) begin
                    case (tx_beat_count_reg)
                        4'd0: begin
                            rx_magic_reg <= rx_udp_payload_axis_tdata[15:0];
                            rx_type_reg <= rx_udp_payload_axis_tdata[23:16];
                            rx_flags_reg <= rx_udp_payload_axis_tdata[31:24];
                            rx_seq_reg <= rx_udp_payload_axis_tdata[63:32];
                        end
                        4'd1: begin
                            rx_opcode_reg <= rx_udp_payload_axis_tdata[15:0];
                            rx_arg1_reg <= rx_udp_payload_axis_tdata[47:16];
                            rx_arg2_reg <= rx_udp_payload_axis_tdata[63:48];
                            rx_cmd_id_reg <= rx_seq_reg;
                            rx_miss_seq_reg <= rx_seq_reg;
                            rx_abs_credit_reg <= rx_seq_reg;
                        end
                    endcase
                    tx_beat_count_reg <= tx_beat_count_reg + 1;

                    if (rx_udp_payload_axis_tlast) begin
                            tx_beat_count_reg <= 0;
                            // Capture packet fields for processing in IDLE
                            rx_pkt_magic_reg <= rx_pkt_magic;
                            rx_pkt_type_reg <= rx_pkt_type;
                            rx_pkt_flags_reg <= rx_pkt_flags;
                            rx_pkt_seq_reg <= rx_pkt_seq;
                            rx_pkt_opcode_reg <= rx_pkt_opcode;
                            rx_pkt_arg1_reg <= rx_pkt_arg1;
                            rx_pkt_arg2_reg <= rx_pkt_arg2;
                            rx_pkt_valid_reg <= 1'b1;
                        end
                end
            end

            STATE_TX_HEADER: begin
                if (tx_udp_hdr_ready) begin
                    tx_hdr_sent_reg <= 1'b1;
                end

                if (tx_udp_payload_axis_tvalid && tx_udp_payload_axis_tready) begin
                    tx_beat_count_reg <= tx_beat_count_reg + 1;
                end
            end

            STATE_TX_DATA: begin
                if (tx_udp_payload_axis_tvalid && tx_udp_payload_axis_tready) begin
                    if (tx_udp_payload_axis_tlast) begin
                        seq_num_reg <= seq_num_reg + 1;
                        packets_sent_reg <= packets_sent_reg + 1;
                    end
                end
            end

            STATE_TX_RESP: begin
                if (!tx_hdr_sent_reg && tx_udp_hdr_ready) begin
                    tx_hdr_sent_reg <= 1'b1;
                end

                if (tx_udp_payload_axis_tvalid && tx_udp_payload_axis_tready) begin
                    tx_beat_count_reg <= tx_beat_count_reg + 1;
                    if (tx_udp_payload_axis_tlast) begin
                        resp_valid_reg <= 1'b0;
                    end
                end
            end

            default: begin
            end
        endcase

        state_reg <= state_next;

        if (status_valid && status_ready) begin
            resp_opcode_reg <= status_opcode;
            resp_cmd_id_reg <= 32'h0;
            resp_status_reg <= 8'h00;
            resp_data_reg <= status_data;
            resp_valid_reg <= 1'b1;
            resp_is_cpl_reg <= 1'b1;
        end
    end
end

endmodule
