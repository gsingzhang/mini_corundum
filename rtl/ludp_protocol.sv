// Lightweight UDP (LUDP) Protocol Module
// Top-level wrapper instantiating separate RX and TX submodules.
//
// Architecture:
//   - ludp_protocol_rx: receives and parses host packets (CREDIT, CMD, NACK)
//   - ludp_protocol_tx: sends data packets and response packets via AXIS MUX
//   - Shared register block in this top module manages state shared between RX/TX
//   - taxi_axis_arb_mux inside TX: response (high prio) > data (low prio)
//
// Packet Types:
//   TYPE_DATA (0x01): Data payload packets from FPGA to host
//   TYPE_CMD  (0x02): Command packets from host to FPGA
//   TYPE_NACK (0x03): Negative acknowledgment
//   TYPE_CMD_ACK (0x04): Command acknowledgment
//   TYPE_CMD_CPL (0x05): Command completion
//   TYPE_CREDIT  (0x06): Credit update for flow control
module ludp_protocol #(
    parameter int DATA_WIDTH        = 64,
    parameter int KEEP_WIDTH        = 8,
    parameter int MAX_PAYLOAD_BYTES = 9000,
    parameter int RETRY_TIMEOUT     = 10000
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
    input  wire [15:0]           tx_data_payload_size,

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
    output logic        f2h_tx_enabled,
    output logic [31:0] packets_sent,
    output logic [31:0] packets_retx,
    output logic [31:0] cmd_count,
    output logic [15:0] last_payload_size
);

    // ================================================================
    // Shared registers (written by RX requests / TX done, managed here)
    // ================================================================
    logic [31:0] seq_num_reg;
    logic [31:0] credit_limit_reg;
    logic        f2h_tx_enabled_reg;
    logic [31:0] packets_sent_reg;

    logic [15:0] resp_opcode_reg;
    logic [31:0] resp_cmd_id_reg;
    logic [7:0]  resp_status_reg;
    logic [31:0] resp_data_reg;
    logic        resp_ongoing_reg;
    logic        resp_is_cpl_reg;

    // RX -> shared register request signals
    logic        rx_resp_req;
    logic [15:0] rx_resp_opcode;
    logic [31:0] rx_resp_cmd_id;
    logic [7:0]  rx_resp_status;
    logic [31:0] rx_resp_data;
    logic        rx_resp_is_cpl;
    logic        rx_cmd_start_req;
    logic        rx_cmd_stop_req;
    logic        rx_credit_valid;
    logic [31:0] rx_credit_new;
    logic        rx_status_req;
    logic [15:0] rx_status_opcode;
    logic [31:0] rx_status_data;

    // TX -> shared register done signals
    logic        tx_resp_done;
    logic        tx_data_done;

    // RX captured source address (passed to TX for response routing)
    logic [47:0] rx_src_mac;
    logic [31:0] rx_src_ip;
    logic [15:0] rx_src_port;

    // ================================================================
    // RX instance
    // ================================================================
    ludp_protocol_rx #(
        .DATA_WIDTH(DATA_WIDTH),
        .KEEP_WIDTH(KEEP_WIDTH),
        .MAX_PAYLOAD_BYTES(MAX_PAYLOAD_BYTES)
    ) rx_inst (
        .clk(clk),
        .rst(rst),

        .local_mac(local_mac),
        .local_ip(local_ip),
        .host_mac(host_mac),
        .host_ip(host_ip),
        .udp_port(udp_port),

        .cmd_opcode(cmd_opcode),
        .cmd_arg1(cmd_arg1),
        .cmd_arg2(cmd_arg2),
        .cmd_valid(cmd_valid),

        .status_opcode(status_opcode),
        .status_data(status_data),
        .status_valid(status_valid),

        .rx_udp_hdr_valid(rx_udp_hdr_valid),
        .rx_udp_hdr_ready(rx_udp_hdr_ready),
        .rx_udp_eth_dest_mac(rx_udp_eth_dest_mac),
        .rx_udp_eth_src_mac(rx_udp_eth_src_mac),
        .rx_udp_eth_type(rx_udp_eth_type),
        .rx_udp_ip_source_ip(rx_udp_ip_source_ip),
        .rx_udp_ip_dest_ip(rx_udp_ip_dest_ip),
        .rx_udp_source_port(rx_udp_source_port),
        .rx_udp_dest_port(rx_udp_dest_port),
        .rx_udp_length(rx_udp_length),
        .rx_udp_checksum(rx_udp_checksum),

        .rx_udp_payload_axis_tdata(rx_udp_payload_axis_tdata),
        .rx_udp_payload_axis_tkeep(rx_udp_payload_axis_tkeep),
        .rx_udp_payload_axis_tvalid(rx_udp_payload_axis_tvalid),
        .rx_udp_payload_axis_tready(rx_udp_payload_axis_tready),
        .rx_udp_payload_axis_tlast(rx_udp_payload_axis_tlast),
        .rx_udp_payload_axis_tuser(rx_udp_payload_axis_tuser),

        .rx_resp_req(rx_resp_req),
        .rx_resp_opcode(rx_resp_opcode),
        .rx_resp_cmd_id(rx_resp_cmd_id),
        .rx_resp_status(rx_resp_status),
        .rx_resp_data(rx_resp_data),
        .rx_resp_is_cpl(rx_resp_is_cpl),

        .rx_cmd_start_req(rx_cmd_start_req),
        .rx_cmd_stop_req(rx_cmd_stop_req),
        .rx_credit_valid(rx_credit_valid),
        .rx_credit_new(rx_credit_new),

        .rx_status_req(rx_status_req),
        .rx_status_opcode(rx_status_opcode),
        .rx_status_data(rx_status_data),

        .rx_src_mac(rx_src_mac),
        .rx_src_ip(rx_src_ip),
        .rx_src_port(rx_src_port),

        .cmd_count(cmd_count),
        .packets_retx(packets_retx),

        .f2h_tx_enabled(f2h_tx_enabled_reg),
        .credit_limit(credit_limit_reg),
        .resp_ongoing(resp_ongoing_reg)
    );

    // ================================================================
    // TX instance
    // ================================================================
    ludp_protocol_tx #(
        .DATA_WIDTH(DATA_WIDTH),
        .KEEP_WIDTH(KEEP_WIDTH),
        .MAX_PAYLOAD_BYTES(MAX_PAYLOAD_BYTES)
    ) tx_inst (
        .clk(clk),
        .rst(rst),

        .local_mac(local_mac),
        .local_ip(local_ip),
        .host_mac(host_mac),
        .host_ip(host_ip),
        .udp_port(udp_port),

        .tx_data_axis_tdata(tx_data_axis_tdata),
        .tx_data_axis_tkeep(tx_data_axis_tkeep),
        .tx_data_axis_tvalid(tx_data_axis_tvalid),
        .tx_data_axis_tready(tx_data_axis_tready),
        .tx_data_axis_tlast(tx_data_axis_tlast),
        .tx_data_axis_tuser(tx_data_axis_tuser),
        .tx_data_payload_size(tx_data_payload_size),

        .tx_udp_hdr_valid(tx_udp_hdr_valid),
        .tx_udp_hdr_ready(tx_udp_hdr_ready),
        .tx_udp_ip_dscp(tx_udp_ip_dscp),
        .tx_udp_ip_ecn(tx_udp_ip_ecn),
        .tx_udp_ip_ttl(tx_udp_ip_ttl),
        .tx_udp_ip_source_ip(tx_udp_ip_source_ip),
        .tx_udp_ip_dest_ip(tx_udp_ip_dest_ip),
        .tx_udp_source_port(tx_udp_source_port),
        .tx_udp_dest_port(tx_udp_dest_port),
        .tx_udp_length(tx_udp_length),
        .tx_udp_checksum(tx_udp_checksum),

        .tx_udp_payload_axis_tdata(tx_udp_payload_axis_tdata),
        .tx_udp_payload_axis_tkeep(tx_udp_payload_axis_tkeep),
        .tx_udp_payload_axis_tvalid(tx_udp_payload_axis_tvalid),
        .tx_udp_payload_axis_tready(tx_udp_payload_axis_tready),
        .tx_udp_payload_axis_tlast(tx_udp_payload_axis_tlast),
        .tx_udp_payload_axis_tuser(tx_udp_payload_axis_tuser),

        .resp_opcode(resp_opcode_reg),
        .resp_cmd_id(resp_cmd_id_reg),
        .resp_status(resp_status_reg),
        .resp_data(resp_data_reg),
        .resp_ongoing(resp_ongoing_reg),
        .resp_is_cpl(resp_is_cpl_reg),
        .resp_done(tx_resp_done),

        .seq_num(seq_num_reg),
        .credit_limit(credit_limit_reg),
        .f2h_tx_enabled(f2h_tx_enabled_reg),
        .tx_data_done(tx_data_done),

        .rx_src_ip(rx_src_ip),
        .rx_src_port(rx_src_port),

        .last_payload_size(last_payload_size)
    );

    // ================================================================
    // Shared register management
    // Sequence number and credit follow TCP RFC 793 wrap-around semantics:
    //   - 32-bit unsigned counters naturally wrap: 0xFFFFFFFF + 1 = 0
    //   - All comparisons use signed subtraction: $signed(a - b) > 0 means "a is ahead of b"
    //   - CMD_START resets both counters, eliminating any wrap ambiguity
    // ================================================================
    always_ff @(posedge clk) begin
        if (rst) begin
            seq_num_reg       <= 0;
            credit_limit_reg    <= 0;
            f2h_tx_enabled_reg  <= 1'b0;
            packets_sent_reg  <= 0;
            resp_ongoing_reg    <= 1'b0;
            resp_opcode_reg   <= 16'h0;
            resp_cmd_id_reg   <= 32'h0;
            resp_status_reg   <= 8'h0;
            resp_data_reg     <= 32'h0;
            resp_is_cpl_reg   <= 1'b0;
        end else begin
            if (tx_resp_done) begin
                resp_ongoing_reg <= 1'b0;
            end
            if (tx_data_done) begin
                // Natural unsigned wrap-around: 0xFFFFFFFF + 1 = 0
                seq_num_reg      <= seq_num_reg + 1;
                packets_sent_reg <= packets_sent_reg + 1;
            end

            if (rx_cmd_start_req) begin
                f2h_tx_enabled_reg <= 1'b1;
                seq_num_reg      <= 0;
                credit_limit_reg   <= 0;
            end
            if (rx_cmd_stop_req) begin
                f2h_tx_enabled_reg <= 1'b0;
            end

            if (rx_credit_valid) begin
                credit_limit_reg <= rx_credit_new;
            end

            if (!resp_ongoing_reg) begin
                if (rx_resp_req) begin
                    resp_opcode_reg <= rx_resp_opcode;
                    resp_cmd_id_reg <= rx_resp_cmd_id;
                    resp_status_reg <= rx_resp_status;
                    resp_data_reg   <= rx_resp_data;
                    resp_ongoing_reg  <= 1'b1;
                    resp_is_cpl_reg <= rx_resp_is_cpl;
                end else if (rx_status_req) begin
                    resp_opcode_reg <= rx_status_opcode;
                    resp_cmd_id_reg <= 32'h0;
                    resp_status_reg <= 8'h00;
                    resp_data_reg   <= rx_status_data;
                    resp_ongoing_reg  <= 1'b1;
                    resp_is_cpl_reg <= 1'b1;
                end
            end
        end
    end

    // ================================================================
    // Output assignments
    // ================================================================
    assign tx_seq_num      = seq_num_reg;
    assign rx_credit_limit = credit_limit_reg;
    assign f2h_tx_enabled    = f2h_tx_enabled_reg;
    assign packets_sent    = packets_sent_reg;
    assign status_ready    = 1'b1;

endmodule
