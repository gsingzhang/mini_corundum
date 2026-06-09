// LUDP Protocol RX Module
// Receives and parses host packets (CREDIT, CMD, NACK)
// Generates request signals for shared register updates and response queuing
module ludp_protocol_rx #(
    parameter int DATA_WIDTH        = 64,
    parameter int KEEP_WIDTH        = 8,
    parameter int MAX_PAYLOAD_BYTES = 9000
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

    input  wire  [15:0] status_opcode,
    input  wire  [31:0] status_data,
    input  wire         status_valid,

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

    output logic        rx_resp_req,
    output logic [15:0] rx_resp_opcode,
    output logic [31:0] rx_resp_cmd_id,
    output logic [7:0]  rx_resp_status,
    output logic [31:0] rx_resp_data,
    output logic        rx_resp_is_cpl,

    output logic        rx_cmd_start_req,
    output logic        rx_cmd_stop_req,
    output logic        rx_credit_valid,
    output logic [31:0] rx_credit_new,

    output logic        rx_status_req,
    output logic [15:0] rx_status_opcode,
    output logic [31:0] rx_status_data,

    output logic [47:0] rx_src_mac,
    output logic [31:0] rx_src_ip,
    output logic [15:0] rx_src_port,

    output logic [31:0] cmd_count,
    output logic [31:0] packets_retx,

    input  wire         burst_active,
    input  wire [31:0]  credit_limit,
    input  wire         resp_ongoing
);

    localparam logic [15:0] MAGIC = 16'hDA01;
    localparam logic [7:0] TYPE_CMD    = 8'h02;
    localparam logic [7:0] TYPE_NACK   = 8'h03;
    localparam logic [7:0] TYPE_CREDIT = 8'h06;
    localparam logic [15:0] CMD_START  = 16'h0001;
    localparam logic [15:0] CMD_STOP   = 16'h0002;

    typedef enum logic {
        RX_IDLE,
        RX_PACKET
    } rx_state_t;

    rx_state_t rx_state_reg;

    logic [3:0]  rx_beat_count_reg;
    logic [15:0] rx_magic_reg;
    logic [7:0]  rx_type_reg;
    logic [7:0]  rx_flags_reg;
    logic [31:0] rx_seq_reg;
    logic [15:0] rx_opcode_reg;
    logic [31:0] rx_arg1_reg;
    logic [15:0] rx_arg2_reg;

    logic [15:0] cmd_opcode_reg;
    logic [31:0] cmd_arg1_reg;
    logic [15:0] cmd_arg2_reg;
    logic        cmd_valid_reg;

    logic [31:0] cmd_count_reg;
    logic [31:0] packets_retx_reg;

    logic [47:0] rx_src_mac_reg;
    logic [31:0] rx_src_ip_reg;
    logic [15:0] rx_src_port_reg;

    assign rx_udp_hdr_ready = (rx_state_reg == RX_IDLE);
    assign rx_udp_payload_axis_tready = (rx_state_reg == RX_PACKET);

    // Packet field extraction:
    // LUDP header is 16 bytes = 2 beats on 64-bit bus.
    // Beat 0 fields (magic, type, flags, seq) are latched into *_reg at beat 0.
    // Beat 1 fields (opcode, arg1, arg2) are consumed directly from tdata at beat 1.
    // All packet processing happens at the last beat (tlast).

    wire rx_pkt_complete = (rx_state_reg == RX_PACKET) &&
                           rx_udp_payload_axis_tvalid &&
                           rx_udp_payload_axis_tready &&
                           rx_udp_payload_axis_tlast &&
                           !rx_udp_payload_axis_tuser &&
                           (rx_magic_reg == MAGIC);

    always_comb begin
        rx_resp_req      = 1'b0;
        rx_resp_opcode   = 16'h0;
        rx_resp_cmd_id   = 32'h0;
        rx_resp_status   = 8'h0;
        rx_resp_data     = 32'h0;
        rx_resp_is_cpl   = 1'b0;
        rx_cmd_start_req = 1'b0;
        rx_cmd_stop_req  = 1'b0;
        rx_credit_valid  = 1'b0;
        rx_credit_new    = 32'h0;
        rx_status_req    = 1'b0;
        rx_status_opcode = 16'h0;
        rx_status_data   = 32'h0;

        if (rx_pkt_complete) begin
            // Use latched beat 0 fields (valid at tlast for multi-beat packets)
            case (rx_type_reg)
                TYPE_CMD: begin
                    //if resp onging, just skip the command, will not respond ack too
                    //so host need to resend the command
                    if (!resp_ongoing) begin
                        rx_resp_req    = 1'b1;
                        rx_resp_opcode = rx_udp_payload_axis_tdata[15:0];
                        rx_resp_cmd_id = rx_seq_reg;
                        rx_resp_status = 8'h00;
                        if (rx_flags_reg == 8'h00) begin
                            rx_resp_data   = 32'h0;
                            rx_resp_is_cpl = 1'b0;
                        end else begin
                            rx_resp_data   = {burst_active, 31'h0};
                            rx_resp_is_cpl = 1'b1;
                        end

                        // Execute command only when ACK can be sent (atomicity)
                        case (rx_udp_payload_axis_tdata[15:0])
                            CMD_START: rx_cmd_start_req = 1'b1;
                            CMD_STOP:  rx_cmd_stop_req  = 1'b1;
                            default: ;
                        endcase
                    end
                end

                TYPE_CREDIT: begin
                    // TCP RFC 793 SEQ_GT: new credit must be ahead of current credit_limit.
                    // Signed subtraction correctly handles wrap-around:
                    //   seq at 0xFFFFFFF5, credit_limit = 0x00000010:
                    //     $signed(0x00000010 - 0xFFFFFFF5) = $signed(27) > 0 → accept
                    if ($signed(rx_seq_reg - credit_limit) > 0) begin
                        rx_credit_valid = 1'b1;
                        rx_credit_new = rx_seq_reg;
                    end
                end

                default: ;
            endcase
        end

        if (status_valid && !resp_ongoing && !rx_pkt_complete) begin
            rx_status_req    = 1'b1;
            rx_status_opcode = status_opcode;
            rx_status_data   = status_data;
        end
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            rx_state_reg     <= RX_IDLE;
            rx_beat_count_reg <= 0;
            rx_magic_reg     <= 0;
            rx_type_reg      <= 0;
            rx_flags_reg     <= 0;
            rx_seq_reg       <= 0;
            rx_opcode_reg    <= 0;
            rx_arg1_reg      <= 0;
            rx_arg2_reg      <= 0;
            cmd_opcode_reg   <= 0;
            cmd_arg1_reg     <= 0;
            cmd_arg2_reg     <= 0;
            cmd_valid_reg    <= 0;
            cmd_count_reg    <= 0;
            packets_retx_reg <= 0;
            rx_src_mac_reg   <= 0;
            rx_src_ip_reg    <= 0;
            rx_src_port_reg  <= 0;
        end else begin
            cmd_valid_reg <= 1'b0;

            case (rx_state_reg)
                RX_IDLE: begin
                    rx_beat_count_reg <= 0;
                    if (rx_udp_hdr_valid && rx_udp_hdr_ready) begin
                        rx_state_reg   <= RX_PACKET;
                        rx_src_mac_reg <= rx_udp_eth_src_mac;
                        rx_src_ip_reg  <= rx_udp_ip_source_ip;
                        rx_src_port_reg <= rx_udp_source_port;
                    end
                end

                RX_PACKET: begin
                    if (rx_udp_payload_axis_tvalid && rx_udp_payload_axis_tready) begin
                        if (rx_udp_payload_axis_tuser) begin
                            rx_beat_count_reg <= 0;
                            rx_state_reg <= RX_IDLE;
                        end else begin
                            case (rx_beat_count_reg)
                                4'd0: begin
                                    rx_magic_reg <= rx_udp_payload_axis_tdata[15:0];
                                    rx_type_reg  <= rx_udp_payload_axis_tdata[23:16];
                                    rx_flags_reg <= rx_udp_payload_axis_tdata[31:24];
                                    rx_seq_reg   <= rx_udp_payload_axis_tdata[63:32];
                                end
                                4'd1: begin
                                    rx_opcode_reg <= rx_udp_payload_axis_tdata[15:0];
                                    rx_arg1_reg   <= rx_udp_payload_axis_tdata[47:16];
                                    rx_arg2_reg   <= rx_udp_payload_axis_tdata[63:48];
                                end
                            endcase
                            rx_beat_count_reg <= rx_beat_count_reg + 1;

                            if (rx_udp_payload_axis_tlast) begin
                                rx_beat_count_reg <= 0;
                                rx_state_reg <= RX_IDLE;

                                if (rx_magic_reg == MAGIC) begin
                                    case (rx_type_reg)
                                        TYPE_CMD: begin
                                            cmd_opcode_reg <= rx_udp_payload_axis_tdata[15:0];
                                            cmd_arg1_reg   <= rx_udp_payload_axis_tdata[47:16];
                                            cmd_arg2_reg   <= rx_udp_payload_axis_tdata[63:48];
                                            cmd_valid_reg  <= 1'b1;
                                            cmd_count_reg  <= cmd_count_reg + 1;
                                        end

                                        TYPE_NACK: begin
                                            packets_retx_reg <= packets_retx_reg + 1;
                                        end

                                        TYPE_CREDIT: begin
                                        end

                                        default: begin
                                        end
                                    endcase
                                end
                            end
                        end
                    end
                end
            endcase
        end
    end

    assign cmd_opcode  = cmd_opcode_reg;
    assign cmd_arg1    = cmd_arg1_reg;
    assign cmd_arg2    = cmd_arg2_reg;
    assign cmd_valid   = cmd_valid_reg;
    assign cmd_count   = cmd_count_reg;
    assign packets_retx = packets_retx_reg;
    assign rx_src_mac  = rx_src_mac_reg;
    assign rx_src_ip   = rx_src_ip_reg;
    assign rx_src_port = rx_src_port_reg;

endmodule
