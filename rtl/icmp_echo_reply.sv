// ICMP Echo Reply Module
// Responds to ICMP echo requests (ping) with echo replies
//
// This module intercepts incoming IP packets and checks for ICMP echo requests.
// When found, it generates an appropriate ICMP echo reply.
// All non-ICMP packets are passed through to the UDP/LUDP protocol.
//
// Placement: Between udp_complete_64 (m_ip_*) and ludp_protocol (rx_udp_*)

`resetall
`timescale 1ns / 1ps
`default_nettype none

module icmp_echo_reply #(
    parameter DATA_WIDTH = 64,
    parameter KEEP_WIDTH = 8
)(
    input  wire        clk,
    input  wire        rst,

    // Configuration
    input  wire [47:0] local_mac,
    input  wire [31:0] local_ip,

    // IP frame input (from udp_complete_64 m_ip_*)
    input  wire        s_ip_hdr_valid,
    output logic       s_ip_hdr_ready,
    input  wire [47:0] s_ip_eth_dest_mac,
    input  wire [47:0] s_ip_eth_src_mac,
    input  wire [15:0] s_ip_eth_type,
    input  wire [3:0]  s_ip_version,
    input  wire [3:0]  s_ip_ihl,
    input  wire [5:0]  s_ip_dscp,
    input  wire [1:0]  s_ip_ecn,
    input  wire [15:0] s_ip_length,
    input  wire [15:0] s_ip_identification,
    input  wire [2:0]  s_ip_flags,
    input  wire [12:0] s_ip_fragment_offset,
    input  wire [7:0]  s_ip_ttl,
    input  wire [7:0]  s_ip_protocol,
    input  wire [15:0] s_ip_header_checksum,
    input  wire [31:0] s_ip_source_ip,
    input  wire [31:0] s_ip_dest_ip,
    input  wire [DATA_WIDTH-1:0] s_ip_payload_axis_tdata,
    input  wire [KEEP_WIDTH-1:0] s_ip_payload_axis_tkeep,
    input  wire        s_ip_payload_axis_tvalid,
    output logic       s_ip_payload_axis_tready,
    input  wire        s_ip_payload_axis_tlast,
    input  wire        s_ip_payload_axis_tuser,

    // IP frame output (to udp_complete_64 s_ip_* for TX reply)
    // Note: udp_complete_64 s_ip_* only has dscp, ecn, length, ttl, protocol, source_ip, dest_ip, payload
    output logic       m_ip_hdr_valid,
    input  wire        m_ip_hdr_ready,
    output logic [5:0]  m_ip_dscp,
    output logic [1:0]  m_ip_ecn,
    output logic [15:0] m_ip_length,
    output logic [7:0]  m_ip_ttl,
    output logic [7:0]  m_ip_protocol,
    output logic [31:0] m_ip_source_ip,
    output logic [31:0] m_ip_dest_ip,
    output logic [DATA_WIDTH-1:0] m_ip_payload_axis_tdata,
    output logic [KEEP_WIDTH-1:0] m_ip_payload_axis_tkeep,
    output logic        m_ip_payload_axis_tvalid,
    input  wire         m_ip_payload_axis_tready,
    output logic        m_ip_payload_axis_tlast,
    output logic        m_ip_payload_axis_tuser,

    // Pass-through IP frame output (for non-ICMP packets to LUDP)
    output logic       m_ip_pass_hdr_valid,
    input  wire        m_ip_pass_hdr_ready,
    output logic [47:0] m_ip_pass_eth_dest_mac,
    output logic [47:0] m_ip_pass_eth_src_mac,
    output logic [15:0] m_ip_pass_eth_type,
    output logic [3:0]  m_ip_pass_version,
    output logic [3:0]  m_ip_pass_ihl,
    output logic [5:0]  m_ip_pass_dscp,
    output logic [1:0]  m_ip_pass_ecn,
    output logic [15:0] m_ip_pass_length,
    output logic [15:0] m_ip_pass_identification,
    output logic [2:0]  m_ip_pass_flags,
    output logic [12:0] m_ip_pass_fragment_offset,
    output logic [7:0]  m_ip_pass_ttl,
    output logic [7:0]  m_ip_pass_protocol,
    output logic [15:0] m_ip_pass_header_checksum,
    output logic [31:0] m_ip_pass_source_ip,
    output logic [31:0] m_ip_pass_dest_ip,
    output logic [DATA_WIDTH-1:0] m_ip_pass_payload_axis_tdata,
    output logic [KEEP_WIDTH-1:0] m_ip_pass_payload_axis_tkeep,
    output logic        m_ip_pass_payload_axis_tvalid,
    input  wire         m_ip_pass_payload_axis_tready,
    output logic        m_ip_pass_payload_axis_tlast,
    output logic        m_ip_pass_payload_axis_tuser
);

    // ICMP protocol number
    localparam ICMP_PROTOCOL = 8'h01;

    // ICMP types
    localparam ICMP_ECHO_REQUEST = 8'h08;
    localparam ICMP_ECHO_REPLY   = 8'h00;

    // State machine
    typedef enum logic [2:0] {
        STATE_IDLE,
        STATE_RX_PAYLOAD,
        STATE_TX_HEADER,
        STATE_TX_PAYLOAD,
        STATE_PASS_THROUGH
    } state_t;

    state_t state_reg, state_next;

    // Pending TX flag: set when ICMP reply is ready but TX path is blocked
    // This prevents deadlock with ip_arb_mux when ARP cache is empty
    logic pending_tx_reg, pending_tx_next;

    // Registers for captured packet info
    logic [47:0] rx_eth_src_mac_reg;
    logic [31:0] rx_source_ip_reg;
    logic [31:0] rx_dest_ip_reg;
    logic [15:0] rx_ip_length_reg;
    logic [15:0] rx_identification_reg;
    logic [7:0]  rx_ttl_reg;
    logic [15:0] rx_checksum_reg;

    // ICMP header fields (first 8 bytes of payload)
    // Byte 0: type, Byte 1: code, Bytes 2-3: checksum
    // Bytes 4-5: identifier, Bytes 6-7: sequence number
    logic [7:0]  icmp_type_reg;
    logic [7:0]  icmp_code_reg;
    logic [15:0] icmp_checksum_reg;
    logic [15:0] icmp_id_reg;
    logic [15:0] icmp_seq_reg;

    // Registered payload tlast and tkeep for echo reply generation
    logic rx_payload_tlast_reg;
    logic [KEEP_WIDTH-1:0] rx_payload_tkeep_reg;

    // Flag to track if we have received tlast during RX
    logic rx_done_reg;

    // Payload buffer for echo reply
    // Maximum payload: 1480 bytes (max IP payload) / 8 = 185 beats, but we only need small ping packets
    // For typical ping: 32-64 bytes payload = 4-8 beats
    // Buffer size: 16 beats x 64 bits = 128 bytes (enough for most ping packets)
    localparam PAYLOAD_BUF_DEPTH = 16;
    localparam PAYLOAD_BUF_ADDR_WIDTH = $clog2(PAYLOAD_BUF_DEPTH);

    logic [DATA_WIDTH-1:0] payload_buf [0:PAYLOAD_BUF_DEPTH-1];
    logic [KEEP_WIDTH-1:0] payload_buf_keep [0:PAYLOAD_BUF_DEPTH-1];
    logic payload_buf_last [0:PAYLOAD_BUF_DEPTH-1];
    logic [PAYLOAD_BUF_ADDR_WIDTH:0] payload_buf_wr_ptr;
    logic [PAYLOAD_BUF_ADDR_WIDTH:0] payload_buf_rd_ptr;
    logic [PAYLOAD_BUF_ADDR_WIDTH:0] payload_buf_count;

    // Detect ICMP echo request
    // ip_eth_rx_64 outputs m_ip_hdr_valid and first payload beat in same cycle,
    // but first payload beat contains last IP header bytes, not ICMP header.
    // ICMP header (type/code/checksum/id/seq) starts on the NEXT payload beat.
    // So we detect ICMP type on the first valid payload beat in STATE_RX_PAYLOAD.
    logic is_icmp_protocol;
    assign is_icmp_protocol = (s_ip_protocol == ICMP_PROTOCOL);

    // ICMP checksum for reply: type changes from 08 to 00
    // Checksum adjustment: ~checksum = ~old_checksum + 0x0800
    logic [15:0] reply_icmp_checksum;
    assign reply_icmp_checksum = ~(~icmp_checksum_reg + 16'h0800);

    // Next state logic
    always_comb begin
        state_next = state_reg;
        pending_tx_next = pending_tx_reg;

        case (state_reg)
            STATE_IDLE: begin
                if (pending_tx_reg) begin
                    // Retry pending TX - go directly to TX_PAYLOAD
                    // m_ip_hdr_valid will be set, and we assume m_ip_hdr_ready will be asserted
                    state_next = STATE_TX_PAYLOAD;
                end else if (s_ip_hdr_valid && s_ip_hdr_ready) begin
                    if (is_icmp_protocol) begin
                        // Go to RX_PAYLOAD to inspect first real payload beat
                        state_next = STATE_RX_PAYLOAD;
                    end else begin
                        state_next = STATE_PASS_THROUGH;
                    end
                end
            end

            STATE_RX_PAYLOAD: begin
                // Check first payload beat for ICMP echo request type
                if (s_ip_payload_axis_tvalid && s_ip_payload_axis_tready) begin
                    if (payload_buf_wr_ptr == '0) begin
                        // First payload beat: check ICMP type
                        if (s_ip_payload_axis_tdata[7:0] != ICMP_ECHO_REQUEST || s_ip_payload_axis_tdata[15:8] != 8'h00) begin
                            // Not an echo request, abort and go to pass-through
                            state_next = STATE_PASS_THROUGH;
                        end else if (s_ip_payload_axis_tlast) begin
                            state_next = STATE_TX_HEADER;
                        end
                    end else if (s_ip_payload_axis_tlast) begin
                        // Subsequent beat with tlast
                        state_next = STATE_TX_HEADER;
                    end
                end else if (rx_done_reg && payload_buf_wr_ptr != '0) begin
                    // tlast was already received, go to TX
                    state_next = STATE_TX_HEADER;
                end
            end

            STATE_TX_HEADER: begin
                if (m_ip_hdr_valid && m_ip_hdr_ready) begin
                    state_next = STATE_TX_PAYLOAD;
                    pending_tx_next = 1'b0;
                end else if (!m_ip_hdr_ready) begin
                    // TX path blocked (e.g. ARP cache empty), release arbiter and retry later
                    state_next = STATE_IDLE;
                    pending_tx_next = 1'b1;
                end
            end

            STATE_TX_PAYLOAD: begin
                if (m_ip_payload_axis_tvalid && m_ip_payload_axis_tready && m_ip_payload_axis_tlast) begin
                    state_next = STATE_IDLE;
                    pending_tx_next = 1'b0;
                end
            end

            STATE_PASS_THROUGH: begin
                if (s_ip_payload_axis_tvalid && s_ip_payload_axis_tready && s_ip_payload_axis_tlast)
                    state_next = STATE_IDLE;
            end

            default: begin
                state_next = STATE_IDLE;
                pending_tx_next = 1'b0;
            end
        endcase
    end

    // Input handshaking
    assign s_ip_hdr_ready = (state_reg == STATE_IDLE) ||
                            (state_reg == STATE_PASS_THROUGH && m_ip_pass_hdr_ready);

    assign s_ip_payload_axis_tready = (state_reg == STATE_RX_PAYLOAD) ? 1'b1 :
                                      (state_reg == STATE_PASS_THROUGH) ? m_ip_pass_payload_axis_tready : 1'b0;

    // Pass-through outputs (for non-ICMP packets)
    assign m_ip_pass_hdr_valid = (state_reg == STATE_PASS_THROUGH) ? s_ip_hdr_valid : 1'b0;
    assign m_ip_pass_eth_dest_mac = s_ip_eth_dest_mac;
    assign m_ip_pass_eth_src_mac = s_ip_eth_src_mac;
    assign m_ip_pass_eth_type = s_ip_eth_type;
    assign m_ip_pass_version = s_ip_version;
    assign m_ip_pass_ihl = s_ip_ihl;
    assign m_ip_pass_dscp = s_ip_dscp;
    assign m_ip_pass_ecn = s_ip_ecn;
    assign m_ip_pass_length = s_ip_length;
    assign m_ip_pass_identification = s_ip_identification;
    assign m_ip_pass_flags = s_ip_flags;
    assign m_ip_pass_fragment_offset = s_ip_fragment_offset;
    assign m_ip_pass_ttl = s_ip_ttl;
    assign m_ip_pass_protocol = s_ip_protocol;
    assign m_ip_pass_header_checksum = s_ip_header_checksum;
    assign m_ip_pass_source_ip = s_ip_source_ip;
    assign m_ip_pass_dest_ip = s_ip_dest_ip;
    assign m_ip_pass_payload_axis_tdata = s_ip_payload_axis_tdata;
    assign m_ip_pass_payload_axis_tkeep = s_ip_payload_axis_tkeep;
    assign m_ip_pass_payload_axis_tvalid = (state_reg == STATE_PASS_THROUGH) ? s_ip_payload_axis_tvalid : 1'b0;
    assign m_ip_pass_payload_axis_tlast = s_ip_payload_axis_tlast;
    assign m_ip_pass_payload_axis_tuser = s_ip_payload_axis_tuser;

    // TX reply outputs (for ICMP echo reply)
    assign m_ip_hdr_valid = (state_reg == STATE_TX_HEADER) || (state_reg == STATE_TX_PAYLOAD && pending_tx_reg);
    assign m_ip_dscp = 6'd0;
    assign m_ip_ecn = 2'd0;
    assign m_ip_length = rx_ip_length_reg;
    assign m_ip_ttl = 8'd64;
    assign m_ip_protocol = ICMP_PROTOCOL;
    assign m_ip_source_ip = local_ip;
    assign m_ip_dest_ip = rx_source_ip_reg;

    // TX payload: ICMP echo reply header + echoed data
    // First beat contains ICMP header (8 bytes)
    // Byte order: type(1), code(1), checksum(2), id(2), seq(2)
    // Bits [7:0]=type, [15:8]=code, [31:16]=checksum, [47:32]=id, [63:48]=seq
    logic [63:0] icmp_reply_header;
    assign icmp_reply_header = {icmp_seq_reg, icmp_id_reg, reply_icmp_checksum, 8'h00, ICMP_ECHO_REPLY};

    // Buffer read data
    logic [DATA_WIDTH-1:0] payload_buf_rd_data;
    logic [KEEP_WIDTH-1:0] payload_buf_rd_keep;
    logic payload_buf_rd_last;

    assign payload_buf_rd_data = payload_buf[payload_buf_rd_ptr[PAYLOAD_BUF_ADDR_WIDTH-1:0]];
    assign payload_buf_rd_keep = payload_buf_keep[payload_buf_rd_ptr[PAYLOAD_BUF_ADDR_WIDTH-1:0]];
    assign payload_buf_rd_last = payload_buf_last[payload_buf_rd_ptr[PAYLOAD_BUF_ADDR_WIDTH-1:0]];

    // TX payload output from buffer
    assign m_ip_payload_axis_tdata = (state_reg == STATE_TX_HEADER) ? icmp_reply_header : payload_buf_rd_data;
    assign m_ip_payload_axis_tkeep = (state_reg == STATE_TX_HEADER) ? 8'hFF : payload_buf_rd_keep;
    assign m_ip_payload_axis_tvalid = (state_reg == STATE_TX_HEADER) || (state_reg == STATE_TX_PAYLOAD && payload_buf_rd_ptr != payload_buf_wr_ptr);
    assign m_ip_payload_axis_tlast = (state_reg == STATE_TX_PAYLOAD) ? payload_buf_rd_last : 1'b0;
    assign m_ip_payload_axis_tuser = 1'b0;

    // Sequential logic
    always_ff @(posedge clk) begin
        if (rst) begin
            state_reg <= STATE_IDLE;
            rx_eth_src_mac_reg <= 48'd0;
            rx_source_ip_reg <= 32'd0;
            rx_dest_ip_reg <= 32'd0;
            rx_ip_length_reg <= 16'd0;
            rx_identification_reg <= 16'd0;
            rx_ttl_reg <= 8'd0;
            rx_checksum_reg <= 16'd0;
            icmp_type_reg <= 8'd0;
            icmp_code_reg <= 8'd0;
            icmp_checksum_reg <= 16'd0;
            icmp_id_reg <= 16'd0;
            icmp_seq_reg <= 16'd0;
            rx_payload_tlast_reg <= 1'b0;
            rx_payload_tkeep_reg <= 8'h00;
            rx_done_reg <= 1'b0;
            pending_tx_reg <= 1'b0;
            payload_buf_wr_ptr <= '0;
            payload_buf_rd_ptr <= '0;
            payload_buf_count <= '0;
        end else begin
            state_reg <= state_next;
            pending_tx_reg <= pending_tx_next;

            if (state_reg == STATE_IDLE && s_ip_hdr_valid && s_ip_hdr_ready) begin
                // Capture IP header info
                rx_eth_src_mac_reg <= s_ip_eth_src_mac;
                rx_source_ip_reg <= s_ip_source_ip;
                rx_dest_ip_reg <= s_ip_dest_ip;
                rx_ip_length_reg <= s_ip_length;
                rx_identification_reg <= s_ip_identification;
                rx_ttl_reg <= s_ip_ttl;
                rx_checksum_reg <= s_ip_header_checksum;

                // Reset buffer pointers at start of new packet
                payload_buf_wr_ptr <= '0;
                payload_buf_rd_ptr <= '0;
                payload_buf_count <= '0;

                $display("[%0t] ICMP: hdr_valid=1 proto=%02h is_icmp=%b", $time, s_ip_protocol, is_icmp_protocol);
            end

            // Capture ICMP header from first real payload beat
            if (state_reg == STATE_RX_PAYLOAD && s_ip_payload_axis_tvalid && s_ip_payload_axis_tready && payload_buf_wr_ptr == '0) begin
                // First payload beat contains ICMP header
                icmp_type_reg <= s_ip_payload_axis_tdata[7:0];
                icmp_code_reg <= s_ip_payload_axis_tdata[15:8];
                icmp_checksum_reg <= s_ip_payload_axis_tdata[31:16];
                icmp_id_reg <= s_ip_payload_axis_tdata[47:32];
                icmp_seq_reg <= s_ip_payload_axis_tdata[63:48];

                // Capture payload tkeep and tlast for echo reply
                rx_payload_tkeep_reg <= s_ip_payload_axis_tkeep;
                rx_payload_tlast_reg <= s_ip_payload_axis_tlast;

                $display("[%0t] ICMP: first payload beat=%016h type=%02h code=%02h", $time, s_ip_payload_axis_tdata, s_ip_payload_axis_tdata[7:0], s_ip_payload_axis_tdata[15:8]);
            end

            // Buffer payload during RX (including first beat with ICMP header)
            if (state_reg == STATE_RX_PAYLOAD && s_ip_payload_axis_tvalid && s_ip_payload_axis_tready) begin
                // Store payload beat in buffer
                payload_buf[payload_buf_wr_ptr[PAYLOAD_BUF_ADDR_WIDTH-1:0]] <= s_ip_payload_axis_tdata;
                payload_buf_keep[payload_buf_wr_ptr[PAYLOAD_BUF_ADDR_WIDTH-1:0]] <= s_ip_payload_axis_tkeep;
                payload_buf_last[payload_buf_wr_ptr[PAYLOAD_BUF_ADDR_WIDTH-1:0]] <= s_ip_payload_axis_tlast;
                payload_buf_wr_ptr <= payload_buf_wr_ptr + 1;
                payload_buf_count <= payload_buf_count + 1;

                // Capture payload tkeep and tlast for echo reply
                rx_payload_tkeep_reg <= s_ip_payload_axis_tkeep;
                rx_payload_tlast_reg <= s_ip_payload_axis_tlast;

                // Set rx_done flag when tlast is received
                if (s_ip_payload_axis_tlast) begin
                    rx_done_reg <= 1'b1;
                end
            end

            // Read from buffer during TX
            if (state_reg == STATE_TX_PAYLOAD && m_ip_payload_axis_tvalid && m_ip_payload_axis_tready) begin
                payload_buf_rd_ptr <= payload_buf_rd_ptr + 1;
            end

            if (state_reg == STATE_RX_PAYLOAD && s_ip_payload_axis_tvalid && s_ip_payload_axis_tready && s_ip_payload_axis_tlast) begin
                $display("[%0t] ICMP: RX payload done, going to TX, buf_count=%0d", $time, payload_buf_count + 1);
            end

            if (state_reg == STATE_TX_HEADER && m_ip_hdr_valid && m_ip_hdr_ready) begin
                $display("[%0t] ICMP: TX header accepted, dest_ip=%08h", $time, m_ip_dest_ip);
            end
            if (state_reg == STATE_TX_HEADER && !m_ip_hdr_ready) begin
                $display("[%0t] ICMP: TX blocked, releasing arbiter, pending_tx=1", $time);
            end
            if (state_reg == STATE_IDLE && pending_tx_reg && m_ip_hdr_ready) begin
                $display("[%0t] ICMP: Retrying pending TX", $time);
            end

            if (state_reg == STATE_TX_PAYLOAD && m_ip_payload_axis_tvalid && m_ip_payload_axis_tready) begin
                $display("[%0t] ICMP: TX payload beat, tlast=%b rd_ptr=%0d wr_ptr=%0d", $time, m_ip_payload_axis_tlast, payload_buf_rd_ptr, payload_buf_wr_ptr);
            end

            if (state_reg == STATE_TX_PAYLOAD && m_ip_payload_axis_tvalid && m_ip_payload_axis_tready && m_ip_payload_axis_tlast) begin
                $display("[%0t] ICMP: TX payload done, going to IDLE", $time);
            end
        end
    end
endmodule
