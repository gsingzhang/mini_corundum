// LUDP Protocol TX Module
// Sends data packets and response packets through priority AXIS MUX
// Response stream (port 0) has higher priority than data stream (port 1)
module ludp_protocol_tx #(
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

    input  wire [DATA_WIDTH-1:0] tx_data_axis_tdata,
    input  wire [KEEP_WIDTH-1:0] tx_data_axis_tkeep,
    input  wire                  tx_data_axis_tvalid,
    output logic                 tx_data_axis_tready,
    input  wire                  tx_data_axis_tlast,
    input  wire                  tx_data_axis_tuser,
    input  wire [15:0]           tx_data_payload_size,

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

    input  wire [15:0] resp_opcode,
    input  wire [31:0] resp_cmd_id,
    input  wire [7:0]  resp_status,
    input  wire [31:0] resp_data,
    input  wire        resp_ongoing,
    input  wire        resp_is_cpl,
    output logic       resp_done,

    input  wire [31:0] seq_num,
    input  wire [31:0] credit_limit,
    input  wire        burst_active,
    output logic       tx_data_done,

    input  wire [47:0] rx_src_ip,
    input  wire [15:0] rx_src_port,

    output logic [15:0] last_payload_size
);

    localparam logic [15:0] MAGIC = 16'hDA01;
    localparam logic [7:0] TYPE_DATA    = 8'h01;
    localparam logic [7:0] TYPE_CMD_ACK = 8'h04;
    localparam logic [7:0] TYPE_CMD_CPL = 8'h05;

    localparam int LUDP_HEADER_BYTES = 16;
    localparam int UDP_HEADER_BYTES  = 8;
    localparam int TOTAL_HDR_BYTES   = UDP_HEADER_BYTES + LUDP_HEADER_BYTES;
    localparam logic [15:0] RESP_UDP_LENGTH = TOTAL_HDR_BYTES;

    typedef enum logic [1:0] {
        TX_IDLE,
        TX_RESP,
        TX_DATA_HDR,
        TX_DATA
    } tx_state_t;

    tx_state_t tx_state_reg;

    logic [3:0]  tx_beat_count_reg;
    logic [63:0] tx_header_beat0_reg;
    logic [63:0] tx_header_beat1_reg;

    logic [15:0] tx_payload_size_reg;
    logic [15:0] tx_payload_bytes_sent_reg;

    // TCP RFC 793 SEQ_GT: credit_limit is ahead of seq_num → we have credit to send.
    // Signed subtraction handles wrap-around: if seq=0xFFFFFFF8, credit_limit=0x00000010,
    // $signed(0x00000010 - 0xFFFFFFF8) = $signed(24) > 0 → can_send = 1
    wire can_send = burst_active && ($signed(credit_limit - seq_num) > 0);

    taxi_axis_if #(
        .DATA_W(DATA_WIDTH),
        .KEEP_W(KEEP_WIDTH),
        .KEEP_EN(1'b1),
        .LAST_EN(1'b1)
    ) tx_axis_s [2] ();

    taxi_axis_if #(
        .DATA_W(DATA_WIDTH),
        .KEEP_W(KEEP_WIDTH),
        .KEEP_EN(1'b1),
        .LAST_EN(1'b1)
    ) tx_axis_m ();

    always_comb begin
        resp_done   = 1'b0;
        tx_data_done = 1'b0;

        case (tx_state_reg)
            TX_RESP: begin
                if (tx_axis_s[0].tvalid && tx_axis_s[0].tready && tx_axis_s[0].tlast)
                    resp_done = 1'b1;
            end
            TX_DATA: begin
                if (tx_data_axis_tvalid && tx_axis_s[1].tready && tx_data_axis_tlast)
                    tx_data_done = 1'b1;
            end
        endcase
    end

    always_ff @(posedge clk) begin
        if (rst) begin
            tx_state_reg            <= TX_IDLE;
            tx_beat_count_reg       <= 0;
            tx_header_beat0_reg     <= 0;
            tx_header_beat1_reg     <= 0;
            tx_payload_size_reg     <= 0;
            tx_payload_bytes_sent_reg <= 0;
        end else begin
            case (tx_state_reg)
                TX_IDLE: begin
                    tx_beat_count_reg         <= 0;
                    tx_payload_bytes_sent_reg <= 0;

                    if (resp_ongoing) begin
                        tx_state_reg      <= TX_RESP;
                        tx_beat_count_reg <= 0;
                        if (resp_is_cpl) begin
                            tx_header_beat0_reg <= {resp_cmd_id, resp_status, TYPE_CMD_CPL, MAGIC};
                            tx_header_beat1_reg <= {16'h0000, resp_data, resp_opcode};
                        end else begin
                            tx_header_beat0_reg <= {resp_cmd_id, resp_status, TYPE_CMD_ACK, MAGIC};
                            tx_header_beat1_reg <= {48'h0, resp_opcode};
                        end
                    end else if (tx_data_axis_tvalid && can_send) begin
                        tx_state_reg          <= TX_DATA_HDR;
                        tx_payload_size_reg   <= tx_data_payload_size;
                        tx_header_beat0_reg   <= {seq_num, 8'h00, TYPE_DATA, MAGIC};
                        tx_header_beat1_reg   <= {16'h0000, 32'h0, tx_data_payload_size};
                        tx_beat_count_reg     <= 0;
                    end
                end

                TX_RESP: begin
                    if (tx_axis_s[0].tvalid && tx_axis_s[0].tready) begin
                        tx_beat_count_reg <= tx_beat_count_reg + 1;
                        if (tx_axis_s[0].tlast) begin
                            tx_state_reg    <= TX_IDLE;
                        end
                    end
                end

                TX_DATA_HDR: begin
                    if (tx_axis_s[1].tvalid && tx_axis_s[1].tready) begin
                        tx_beat_count_reg <= tx_beat_count_reg + 1;
                        if (tx_beat_count_reg >= 4'd1) begin
                            tx_state_reg <= TX_DATA;
                        end
                    end
                end

                TX_DATA: begin
                    if (tx_data_axis_tvalid && tx_axis_s[1].tready) begin
                        if (tx_data_axis_tlast) begin
                            tx_payload_size_reg <= tx_payload_bytes_sent_reg + KEEP_WIDTH;
                            tx_state_reg        <= TX_IDLE;
                        end else begin
                            tx_payload_bytes_sent_reg <= tx_payload_bytes_sent_reg + KEEP_WIDTH;
                        end
                    end
                end

                default: tx_state_reg <= TX_IDLE;
            endcase
        end
    end

    always_comb begin
        tx_axis_s[0].tdata  = {DATA_WIDTH{1'b0}};
        tx_axis_s[0].tkeep  = {KEEP_WIDTH{1'b1}};
        tx_axis_s[0].tvalid = 1'b0;
        tx_axis_s[0].tlast  = 1'b0;
        tx_axis_s[0].tstrb  = {KEEP_WIDTH{1'b1}};
        tx_axis_s[0].tid    = '0;
        tx_axis_s[0].tdest  = '0;
        tx_axis_s[0].tuser  = '0;

        if (tx_state_reg == TX_RESP) begin
            case (tx_beat_count_reg)
                4'd0: begin
                    tx_axis_s[0].tvalid = 1'b1;
                    tx_axis_s[0].tdata  = tx_header_beat0_reg;
                    tx_axis_s[0].tlast  = 1'b0;
                end
                4'd1: begin
                    tx_axis_s[0].tvalid = 1'b1;
                    tx_axis_s[0].tdata  = tx_header_beat1_reg;
                    tx_axis_s[0].tlast  = 1'b1;
                end
                default: begin
                    tx_axis_s[0].tvalid = 1'b1;
                    tx_axis_s[0].tdata  = tx_header_beat1_reg;
                    tx_axis_s[0].tlast  = 1'b1;
                end
            endcase
        end
    end

    always_comb begin
        tx_axis_s[1].tdata  = {DATA_WIDTH{1'b0}};
        tx_axis_s[1].tkeep  = {KEEP_WIDTH{1'b1}};
        tx_axis_s[1].tvalid = 1'b0;
        tx_axis_s[1].tlast  = 1'b0;
        tx_axis_s[1].tstrb  = {KEEP_WIDTH{1'b1}};
        tx_axis_s[1].tid    = '0;
        tx_axis_s[1].tdest  = '0;
        tx_axis_s[1].tuser  = '0;

        if (tx_state_reg == TX_DATA_HDR) begin
            case (tx_beat_count_reg)
                4'd0: begin
                    tx_axis_s[1].tvalid = 1'b1;
                    tx_axis_s[1].tdata  = tx_header_beat0_reg;
                    tx_axis_s[1].tlast  = 1'b0;
                end
                4'd1: begin
                    tx_axis_s[1].tvalid = 1'b1;
                    tx_axis_s[1].tdata  = tx_header_beat1_reg;
                    tx_axis_s[1].tlast  = 1'b0;
                end
                default: begin
                    tx_axis_s[1].tvalid = 1'b0;
                end
            endcase
        end else if (tx_state_reg == TX_DATA) begin
            tx_axis_s[1].tdata  = tx_data_axis_tdata;
            tx_axis_s[1].tkeep  = tx_data_axis_tkeep;
            tx_axis_s[1].tvalid = tx_data_axis_tvalid;
            tx_axis_s[1].tlast  = tx_data_axis_tlast;
        end
    end

    assign tx_data_axis_tready = (tx_state_reg == TX_DATA) && tx_axis_s[1].tready;

    taxi_axis_arb_mux #(
        .S_COUNT(2),
        .UPDATE_TID(1'b0),
        .ARB_ROUND_ROBIN(1'b0),
        .ARB_LSB_HIGH_PRIO(1'b1)
    ) tx_mux_inst (
        .clk(clk),
        .rst(rst),
        .s_axis(tx_axis_s),
        .m_axis(tx_axis_m)
    );

    assign tx_udp_payload_axis_tdata  = tx_axis_m.tdata;
    assign tx_udp_payload_axis_tkeep  = tx_axis_m.tkeep;
    assign tx_udp_payload_axis_tvalid = tx_axis_m.tvalid;
    assign tx_udp_payload_axis_tlast  = tx_axis_m.tlast;
    assign tx_udp_payload_axis_tuser  = 1'b0;
    assign tx_axis_m.tready = tx_udp_payload_axis_tready;

    assign tx_udp_hdr_valid = (tx_state_reg == TX_RESP) ||
                              (tx_state_reg == TX_DATA_HDR);

    assign tx_udp_ip_dscp    = 6'h0;
    assign tx_udp_ip_ecn     = 2'h0;
    assign tx_udp_ip_ttl     = 8'd64;
    assign tx_udp_ip_source_ip = local_ip;
    assign tx_udp_ip_dest_ip   = (rx_src_ip != 32'h0) ? rx_src_ip : host_ip;
    assign tx_udp_checksum   = 16'h0;
    assign tx_udp_source_port = udp_port;
    assign tx_udp_dest_port   = (rx_src_port != 16'h0) ? rx_src_port : udp_port;

    always_comb begin
        tx_udp_length = RESP_UDP_LENGTH;
        if (tx_state_reg == TX_DATA_HDR || tx_state_reg == TX_DATA) begin
            tx_udp_length = TOTAL_HDR_BYTES + tx_payload_size_reg;
        end
    end

    assign last_payload_size = tx_payload_size_reg;

endmodule
