// Lightweight UDP (LUDP) Protocol Module
// Implements a lightweight reliable data transfer protocol over UDP for FPGA-to-host communication.
// Features:
//   - Magic number validation (0xDA01) for protocol identification
//   - Command/response interface for host-to-FPGA control
//   - Data streaming interface for FPGA-to-host high-throughput data transfer
//   - Variable payload sizes: small frames to 9KB jumbo frames
//   - Credit-based flow control with sequence numbers
//   - NACK-based retransmission support
//   - Status reporting interface
//
// Packet Types:
//   TYPE_DATA (0x01): Data payload packets from FPGA to host
//   TYPE_CMD  (0x02): Command packets from host to FPGA
//
// Data Packet Format (variable payload):
//   LUDP Header (16 bytes):
//     [15:0]   - Magic (0xDA01)
//     [23:16]  - Type (0x01 = DATA)
//     [31:24]  - Flags (reserved)
//     [63:32]  - Sequence number
//     [79:64]  - Payload length in bytes (for host buffer allocation)
//     [95:80]  - Reserved
//     [127:96] - Reserved
//   Payload: 0 to MAX_PAYLOAD_BYTES bytes (variable, determined by upstream tlast)
//
// Parameters:
//   DATA_WIDTH       - AXI-Stream data width (default 64 bits)
//   KEEP_WIDTH       - AXI-Stream byte keep width (default 8 bytes)
//   MAX_PAYLOAD_BYTES- Maximum payload size (default 9000 for jumbo frames)
//   RETRY_TIMEOUT    - Clock cycles before retransmission (default 10000)
//
// Interfaces:
//   - AXI-Stream slave for TX data (FPGA -> host)
//   - AXI-Stream master for RX data (host -> FPGA, via UDP payload)
//   - Command output (decoded host commands)
//   - Status input (FPGA status to report back)
//   - UDP header/payload interfaces to Ethernet stack
//
module ludp_protocol #(
    parameter int DATA_WIDTH        = 64,
    parameter int KEEP_WIDTH        = 8,
    parameter int MAX_PAYLOAD_BYTES = 9000,  // Jumbo frame support (max ~9KB)
    parameter int RETRY_TIMEOUT     = 10000
)(
    // Clock and reset
    input  wire        clk,
    input  wire        rst,

    // Network configuration
    input  wire [47:0] local_mac,
    input  wire [31:0] local_ip,
    input  wire [47:0] host_mac,
    input  wire [31:0] host_ip,
    input  wire [15:0] udp_port,

    // Command output interface (host -> FPGA)
    output logic [15:0] cmd_opcode,
    output logic [31:0] cmd_arg1,
    output logic [15:0] cmd_arg2,
    output logic        cmd_valid,
    input  wire         cmd_ready,

    // Status input interface (FPGA -> host)
    input  wire  [15:0] status_opcode,
    input  wire  [31:0] status_data,
    input  wire         status_valid,
    output logic        status_ready,

    // TX data stream interface (FPGA -> host) - variable payload size
    // Upstream module controls payload length via tlast
    // tx_data_payload_size provides a hint for correct UDP header length
    input  wire [DATA_WIDTH-1:0] tx_data_axis_tdata,
    input  wire [KEEP_WIDTH-1:0] tx_data_axis_tkeep,
    input  wire                  tx_data_axis_tvalid,
    output logic                 tx_data_axis_tready,
    input  wire                  tx_data_axis_tlast,
    input  wire                  tx_data_axis_tuser,
    input  wire [15:0]           tx_data_payload_size,

    // RX UDP header interface (host -> FPGA)
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

    // RX UDP payload interface (host -> FPGA)
    input  wire [DATA_WIDTH-1:0] rx_udp_payload_axis_tdata,
    input  wire [KEEP_WIDTH-1:0] rx_udp_payload_axis_tkeep,
    input  wire                  rx_udp_payload_axis_tvalid,
    output logic                 rx_udp_payload_axis_tready,
    input  wire                  rx_udp_payload_axis_tlast,
    input  wire                  rx_udp_payload_axis_tuser,

    // TX UDP header interface (FPGA -> host)
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

    // TX UDP payload interface (FPGA -> host)
    output logic [DATA_WIDTH-1:0] tx_udp_payload_axis_tdata,
    output logic [KEEP_WIDTH-1:0] tx_udp_payload_axis_tkeep,
    output logic                  tx_udp_payload_axis_tvalid,
    input  wire                   tx_udp_payload_axis_tready,
    output logic                  tx_udp_payload_axis_tlast,
    output logic                  tx_udp_payload_axis_tuser,

    // Debug/monitoring outputs
    output logic [31:0] tx_seq_num,
    output logic [31:0] rx_credit_limit,
    output logic        burst_active,
    output logic [31:0] packets_sent,
    output logic [31:0] packets_retx,
    output logic [31:0] cmd_count,
    output logic [15:0] last_payload_size  // Debug: size of last transmitted payload
);

    // Protocol magic number for packet identification
    localparam logic [15:0] MAGIC = 16'hDA01;

    // LUDP packet type definitions
    localparam logic [7:0] TYPE_DATA    = 8'h01;  // Data packet (FPGA -> host)
    localparam logic [7:0] TYPE_CMD     = 8'h02;  // Command packet (host -> FPGA)
    localparam logic [7:0] TYPE_NACK    = 8'h03;  // Negative acknowledgment
    localparam logic [7:0] TYPE_CMD_ACK = 8'h04;  // Command acknowledgment
    localparam logic [7:0] TYPE_CMD_CPL = 8'h05;  // Command completion
    localparam logic [7:0] TYPE_CREDIT  = 8'h06;  // Credit update for flow control

    // Command opcode definitions
    localparam logic [15:0] CMD_START     = 16'h0001;  // Start data burst
    localparam logic [15:0] CMD_STOP      = 16'h0002;  // Stop data burst
    localparam logic [15:0] CMD_READ_REG  = 16'h0010;  // Read register
    localparam logic [15:0] CMD_WRITE_REG = 16'h0011;  // Write register

    // Header and UDP overhead constants
    localparam int LUDP_HEADER_BYTES = 16;  // LUDP header size
    localparam int UDP_HEADER_BYTES  = 8;   // UDP header size
    localparam int TOTAL_HDR_BYTES   = UDP_HEADER_BYTES + LUDP_HEADER_BYTES;

    // Response packet UDP length (fixed size: 8 + 16 = 24 bytes)
    localparam logic [15:0] RESP_UDP_LENGTH = TOTAL_HDR_BYTES;

    // Maximum UDP length for jumbo frame
    localparam int MAX_UDP_LENGTH = TOTAL_HDR_BYTES + MAX_PAYLOAD_BYTES;

    // Main FSM state definitions
    typedef enum logic [2:0] {
        STATE_IDLE,      // Wait for RX header, response trigger, or TX data
        STATE_RX_CMD,    // Receive and parse command packet
        STATE_TX_HEADER, // Transmit LUDP header beats
        STATE_TX_DATA,   // Transmit data payload (variable length)
        STATE_TX_RESP    // Transmit response packet
    } state_t;

    // FSM state registers
    state_t state_reg, state_next;

    // Sequence number and flow control registers
    logic [31:0] seq_num_reg;       // Current TX sequence number
    logic [31:0] abs_credit_reg;    // Absolute credit limit from host
    logic        burst_active_reg;  // Data burst active flag
    logic [31:0] cmd_count_reg;     // Total commands received
    logic [31:0] packets_sent_reg;  // Total data packets sent
    logic [31:0] packets_retx_reg;  // Total retransmissions

    // RX packet field registers (captured during STATE_RX_CMD)
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

    // Response packet registers
    logic [15:0] resp_opcode_reg;
    logic [31:0] resp_cmd_id_reg;
    logic [7:0]  resp_status_reg;
    logic [31:0] resp_data_reg;
    logic        resp_valid_reg;
    logic        resp_is_cpl_reg;

    // Command output registers
    logic [15:0] cmd_opcode_reg;
    logic [31:0] cmd_arg1_reg;
    logic [15:0] cmd_arg2_reg;
    logic        cmd_valid_reg;

    // TX header construction registers
    logic [3:0]  tx_beat_count_reg;   // Beat counter for header transmission
    logic [63:0] tx_header_beat0_reg; // First 8 bytes of LUDP header
    logic [63:0] tx_header_beat1_reg; // Second 8 bytes of LUDP header
    logic        tx_hdr_sent_reg;     // UDP header has been sent
    logic        tx_is_data_reg;      // Current TX is data packet

    // Variable payload size tracking
    logic [15:0] tx_payload_size_reg;     // Actual payload size in bytes
    logic [15:0] tx_payload_bytes_sent_reg; // Bytes sent counter

    // Packet processing registers (updated in RX_CMD, used in IDLE)
    logic [15:0] rx_pkt_magic_reg;
    logic [7:0]  rx_pkt_type_reg;
    logic [7:0]  rx_pkt_flags_reg;
    logic [31:0] rx_pkt_seq_reg;
    logic [15:0] rx_pkt_opcode_reg;
    logic [31:0] rx_pkt_arg1_reg;
    logic [15:0] rx_pkt_arg2_reg;
    logic        rx_pkt_valid_reg;

    // Last RX source address (captured from UDP header for response routing)
    logic [47:0] rx_src_mac_reg;
    logic [31:0] rx_src_ip_reg;
    logic [15:0] rx_src_port_reg;

    // Flow control: allow TX when burst is active and we have credit
    wire can_send = burst_active_reg && (seq_num_reg < abs_credit_reg);

    // Combinational packet parsing from RX payload (beat 0 fields)
    wire [15:0] rx_pkt_magic  = (tx_beat_count_reg == 0) ? rx_udp_payload_axis_tdata[15:0]  : rx_magic_reg;
    wire [7:0]  rx_pkt_type   = (tx_beat_count_reg == 0) ? rx_udp_payload_axis_tdata[23:16] : rx_type_reg;
    wire [7:0]  rx_pkt_flags  = (tx_beat_count_reg == 0) ? rx_udp_payload_axis_tdata[31:24] : rx_flags_reg;
    wire [31:0] rx_pkt_seq    = (tx_beat_count_reg == 0) ? rx_udp_payload_axis_tdata[63:32] : rx_seq_reg;

    // Combinational packet parsing from RX payload (beat 1 fields)
    wire [15:0] rx_pkt_opcode = rx_udp_payload_axis_tdata[15:0];
    wire [31:0] rx_pkt_arg1   = rx_udp_payload_axis_tdata[47:16];
    wire [15:0] rx_pkt_arg2   = rx_udp_payload_axis_tdata[63:48];

    // Output assignments
    assign tx_seq_num      = seq_num_reg;
    assign rx_credit_limit = abs_credit_reg;
    assign burst_active    = burst_active_reg;
    assign packets_sent    = packets_sent_reg;
    assign packets_retx    = packets_retx_reg;
    assign cmd_count       = cmd_count_reg;
    assign last_payload_size = tx_payload_size_reg;

    assign cmd_opcode  = cmd_opcode_reg;
    assign cmd_arg1    = cmd_arg1_reg;
    assign cmd_arg2    = cmd_arg2_reg;
    assign cmd_valid   = cmd_valid_reg;
    assign status_ready = 1'b1;

    // Main FSM next-state logic
    always_comb begin
        state_next = state_reg;

        case (state_reg)
            STATE_IDLE: begin
                // Priority: RX command > TX response > TX data
                if (rx_udp_hdr_valid && rx_udp_hdr_ready) begin
                    state_next = STATE_RX_CMD;
                end else if (resp_valid_reg) begin
                    state_next = STATE_TX_RESP;
                end else if (tx_data_axis_tvalid && can_send) begin
                    state_next = STATE_TX_HEADER;
                end
            end

            STATE_RX_CMD: begin
                // Return to IDLE when last payload beat received
                if (rx_udp_payload_axis_tvalid && rx_udp_payload_axis_tready && rx_udp_payload_axis_tlast)
                    state_next = STATE_IDLE;
            end

            STATE_TX_HEADER: begin
                // Transition to data transmission after header beats (2 beats for LUDP header)
                if (tx_beat_count_reg >= 4'd2)
                    state_next = STATE_TX_DATA;
            end

            STATE_TX_DATA: begin
                // Return to IDLE when last data beat transmitted (tlast from upstream)
                if (tx_udp_payload_axis_tvalid && tx_udp_payload_axis_tready && tx_udp_payload_axis_tlast)
                    state_next = STATE_IDLE;
            end

            STATE_TX_RESP: begin
                // Return to IDLE when last response beat transmitted
                if (tx_udp_payload_axis_tvalid && tx_udp_payload_axis_tready && tx_udp_payload_axis_tlast)
                    state_next = STATE_IDLE;
            end

            default: state_next = STATE_IDLE;
        endcase
    end

    // RX interface handshaking
    assign rx_udp_hdr_ready = (state_reg == STATE_IDLE) || (state_reg == STATE_RX_CMD);
    assign rx_udp_payload_axis_tready = (state_reg == STATE_RX_CMD) || (state_reg == STATE_IDLE);

    // TX UDP header valid signal
    always_comb begin
        tx_udp_hdr_valid = 0;
        if (state_reg == STATE_TX_HEADER)
            tx_udp_hdr_valid = 1;
        else if (state_reg == STATE_TX_RESP && !tx_hdr_sent_reg)
            tx_udp_hdr_valid = 1;
    end

    // TX UDP header field assignments
    assign tx_udp_ip_dscp    = 6'h0;
    assign tx_udp_ip_ecn     = 2'h0;
    assign tx_udp_ip_ttl     = 8'd64;
    assign tx_udp_ip_source_ip = local_ip;
    // Use captured source IP from last RX packet for response routing,
    // fallback to configured host_ip for data packets (no prior RX)
    assign tx_udp_ip_dest_ip   = (rx_src_ip_reg != 32'h0) ? rx_src_ip_reg : host_ip;
    assign tx_udp_checksum   = 16'h0;
    assign tx_udp_source_port = udp_port;
    // Use captured source port from last RX packet for response routing,
    // fallback to configured udp_port for data packets
    assign tx_udp_dest_port   = (rx_src_port_reg != 16'h0) ? rx_src_port_reg : udp_port;

    // TX UDP length: dynamically calculated based on actual payload size
    // UDP length = 8 (UDP header) + 16 (LUDP header) + payload_bytes
    always_comb begin
        tx_udp_length = RESP_UDP_LENGTH;  // Default for response packets
        if (state_reg == STATE_TX_HEADER || state_reg == STATE_TX_DATA) begin
            // Data packet: include actual payload size
            tx_udp_length = TOTAL_HDR_BYTES + tx_payload_size_reg;
        end
    end

    // TX UDP payload data multiplexing
    always_comb begin
        tx_udp_payload_axis_tdata  = {DATA_WIDTH{1'b0}};
        tx_udp_payload_axis_tkeep  = {KEEP_WIDTH{1'b1}};
        tx_udp_payload_axis_tvalid = 1'b0;
        tx_udp_payload_axis_tlast  = 1'b0;

        if (state_reg == STATE_TX_HEADER) begin
            // Transmit LUDP header (2 beats) then pass through data
            tx_udp_payload_axis_tkeep  = {KEEP_WIDTH{1'b1}};
            case (tx_beat_count_reg)
                4'd0: begin
                    tx_udp_payload_axis_tvalid = 1'b1;
                    tx_udp_payload_axis_tdata  = tx_header_beat0_reg;
                    tx_udp_payload_axis_tlast  = 1'b0;
                end
                4'd1: begin
                    tx_udp_payload_axis_tvalid = 1'b1;
                    tx_udp_payload_axis_tdata  = tx_header_beat1_reg;
                    tx_udp_payload_axis_tlast  = 1'b0;
                end
                default: begin
                    tx_udp_payload_axis_tvalid = 1'b0;
                    tx_udp_payload_axis_tdata  = tx_data_axis_tdata;
                    tx_udp_payload_axis_tlast  = 1'b0;
                end
            endcase
        end else if (state_reg == STATE_TX_DATA) begin
            // Pass through TX data stream from upstream
            // Upstream controls actual payload length via tlast
            tx_udp_payload_axis_tdata  = tx_data_axis_tdata;
            tx_udp_payload_axis_tkeep  = tx_data_axis_tkeep;
            tx_udp_payload_axis_tvalid = tx_data_axis_tvalid;
            tx_udp_payload_axis_tlast  = tx_data_axis_tlast;
        end else if (state_reg == STATE_TX_RESP) begin
            // Transmit response packet (2 beats, fixed size)
            tx_udp_payload_axis_tvalid = 1'b1;
            tx_udp_payload_axis_tkeep  = {KEEP_WIDTH{1'b1}};
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

    // Main sequential logic
    always_ff @(posedge clk) begin
        if (rst) begin
            state_reg               <= STATE_IDLE;
            seq_num_reg             <= 0;
            abs_credit_reg          <= 0;
            burst_active_reg        <= 0;
            cmd_count_reg           <= 0;
            packets_sent_reg        <= 0;
            packets_retx_reg        <= 0;
            rx_magic_reg            <= 0;
            rx_type_reg             <= 0;
            rx_flags_reg            <= 0;
            rx_seq_reg              <= 0;
            rx_opcode_reg           <= 0;
            rx_arg1_reg             <= 0;
            rx_arg2_reg             <= 0;
            rx_cmd_id_reg           <= 0;
            rx_miss_seq_reg         <= 0;
            rx_count_reg            <= 0;
            rx_abs_credit_reg       <= 0;
            resp_opcode_reg         <= 0;
            resp_cmd_id_reg         <= 0;
            resp_status_reg         <= 0;
            resp_data_reg           <= 0;
            resp_valid_reg          <= 0;
            resp_is_cpl_reg         <= 0;
            cmd_opcode_reg          <= 0;
            cmd_arg1_reg            <= 0;
            cmd_arg2_reg            <= 0;
            cmd_valid_reg           <= 0;
            tx_beat_count_reg       <= 0;
            tx_header_beat0_reg     <= 0;
            tx_header_beat1_reg     <= 0;
            tx_hdr_sent_reg         <= 0;
            tx_is_data_reg          <= 0;
            tx_payload_size_reg     <= 0;
            tx_payload_bytes_sent_reg <= 0;
            rx_pkt_magic_reg        <= 0;
            rx_pkt_type_reg         <= 0;
            rx_pkt_flags_reg        <= 0;
            rx_pkt_seq_reg          <= 0;
            rx_pkt_opcode_reg       <= 0;
            rx_pkt_arg1_reg         <= 0;
            rx_pkt_arg2_reg         <= 0;
            rx_pkt_valid_reg        <= 0;
            rx_src_mac_reg          <= 0;
            rx_src_ip_reg           <= 0;
            rx_src_port_reg         <= 0;
        end else begin
            // Default: clear command valid (pulse for one cycle)
            cmd_valid_reg <= 1'b0;

            case (state_reg)
                STATE_IDLE: begin
                // Clear TX control flags
                tx_hdr_sent_reg           <= 0;
                tx_beat_count_reg         <= 0;
                tx_payload_bytes_sent_reg <= 0;

                if (rx_pkt_valid_reg) begin
                    // Process packet received in previous RX_CMD state
                    rx_pkt_valid_reg <= 1'b0;
                    if (rx_pkt_magic_reg == MAGIC) begin
                            case (rx_pkt_type_reg)
                                TYPE_CMD: begin
                                    // Decode command fields
                                    cmd_opcode_reg <= rx_pkt_opcode_reg;
                                    cmd_arg1_reg   <= rx_pkt_arg1_reg;
                                    cmd_arg2_reg   <= rx_pkt_arg2_reg;
                                    cmd_valid_reg  <= 1'b1;
                                    cmd_count_reg  <= cmd_count_reg + 1;

                                    // Generate response (ACK or CPL based on flags)
                                    if (rx_pkt_flags_reg == 8'h00) begin
                                        resp_opcode_reg <= rx_pkt_opcode_reg;
                                        resp_cmd_id_reg <= rx_pkt_seq_reg;
                                        resp_status_reg <= 8'h00;
                                        resp_data_reg   <= 32'h0;
                                        resp_valid_reg  <= 1'b1;
                                        resp_is_cpl_reg <= 1'b0;
                                    end else begin
                                        resp_opcode_reg <= rx_pkt_opcode_reg;
                                        resp_cmd_id_reg <= rx_pkt_seq_reg;
                                        resp_status_reg <= 8'h00;
                                        resp_data_reg   <= {burst_active_reg, 31'h0};
                                        resp_valid_reg  <= 1'b1;
                                        resp_is_cpl_reg <= 1'b1;
                                    end

                                    // Execute command
                                    case (rx_pkt_opcode_reg)
                                        CMD_START: begin
                                            burst_active_reg <= 1'b1;
                                            seq_num_reg      <= 0;
                                        end
                                        CMD_STOP: begin
                                            burst_active_reg <= 1'b0;
                                        end
                                        CMD_WRITE_REG: begin
                                            // TODO: implement register write
                                        end
                                        CMD_READ_REG: begin
                                            // TODO: implement register read
                                        end
                                        default: begin
                                            // Unknown command
                                        end
                                    endcase
                                end

                                TYPE_NACK: begin
                                    // Host reported missing packets
                                    packets_retx_reg <= packets_retx_reg + 1;
                                end

                                TYPE_CREDIT: begin
                                    abs_credit_reg <= rx_pkt_seq_reg;
                                    resp_opcode_reg <= 8'h06;
                                    resp_cmd_id_reg <= rx_pkt_seq_reg;
                                    resp_status_reg <= 8'h00;
                                    resp_data_reg   <= {16'h0, burst_active_reg, abs_credit_reg[15:0]};
                                    resp_valid_reg  <= 1'b1;
                                    resp_is_cpl_reg <= 1'b1;  // Use CMD_CPL to include resp_data_reg
                                end

                                default: begin
                                    // Unknown packet type
                                end
                            endcase
                        end
                    end else if (rx_udp_hdr_valid && rx_udp_hdr_ready) begin
                        // Prepare for new RX packet - capture source address for response routing
                        rx_magic_reg    <= 0;
                        rx_type_reg     <= 0;
                        rx_flags_reg    <= 0;
                        rx_seq_reg      <= 0;
                        rx_src_mac_reg  <= rx_udp_eth_src_mac;
                        rx_src_ip_reg   <= rx_udp_ip_source_ip;
                        rx_src_port_reg <= rx_udp_source_port;
                    end else if (resp_valid_reg) begin
                        // Prepare response packet header (fixed 24-byte UDP payload)
                        tx_hdr_sent_reg   <= 0;
                        tx_beat_count_reg <= 0;
                        tx_is_data_reg    <= 1'b0;
                        $display("[%0t] LUDP: Preparing response opcode=%04h dest_ip=%08h dest_port=%0d", $time, resp_opcode_reg, rx_src_ip_reg, rx_src_port_reg);
                        if (resp_is_cpl_reg) begin
                            // Command completion response
                            tx_header_beat0_reg <= {resp_cmd_id_reg, resp_status_reg, TYPE_CMD_CPL, MAGIC};
                            tx_header_beat1_reg <= {16'h0000, resp_data_reg, resp_opcode_reg};
                        end else begin
                            // Command acknowledgment response
                            tx_header_beat0_reg <= {resp_cmd_id_reg, resp_status_reg, TYPE_CMD_ACK, MAGIC};
                            tx_header_beat1_reg <= {48'h0, resp_opcode_reg};
                        end
                    end else if (tx_data_axis_tvalid && can_send) begin
                        // Prepare data packet header with variable payload
                        // Use payload_size hint from upstream for correct UDP header
                        tx_payload_size_reg     <= tx_data_payload_size;
                        tx_payload_bytes_sent_reg <= 0;
                        tx_header_beat0_reg     <= {seq_num_reg, 8'h00, TYPE_DATA, MAGIC};
                        tx_header_beat1_reg     <= {16'h0000, 32'h0, tx_data_payload_size};
                        tx_hdr_sent_reg         <= 0;
                        tx_beat_count_reg       <= 0;
                        tx_is_data_reg          <= 1'b1;
                        $display("[%0t] LUDP: DATA TX start seq=%0d payload_size=%0d", $time, seq_num_reg, tx_data_payload_size);
                    end
                end

                STATE_RX_CMD: begin
                    rx_pkt_valid_reg <= 1'b0;
                    if (rx_udp_payload_axis_tvalid && rx_udp_payload_axis_tready) begin
                        // Parse incoming packet fields by beat
                        case (tx_beat_count_reg)
                            4'd0: begin
                                // Beat 0: magic, type, flags, sequence
                                rx_magic_reg <= rx_udp_payload_axis_tdata[15:0];
                                rx_type_reg  <= rx_udp_payload_axis_tdata[23:16];
                                rx_flags_reg <= rx_udp_payload_axis_tdata[31:24];
                                rx_seq_reg   <= rx_udp_payload_axis_tdata[63:32];
                            end
                            4'd1: begin
                                // Beat 1: opcode, arg1, arg2
                                rx_opcode_reg <= rx_udp_payload_axis_tdata[15:0];
                                rx_arg1_reg   <= rx_udp_payload_axis_tdata[47:16];
                                rx_arg2_reg   <= rx_udp_payload_axis_tdata[63:48];
                                rx_cmd_id_reg <= rx_seq_reg;
                                rx_miss_seq_reg <= rx_seq_reg;
                                rx_abs_credit_reg <= rx_seq_reg;
                            end
                        endcase
                        tx_beat_count_reg <= tx_beat_count_reg + 1;

                        if (rx_udp_payload_axis_tlast) begin
                            // Last beat: capture parsed packet for IDLE processing
                            tx_beat_count_reg   <= 0;
                            rx_pkt_magic_reg    <= rx_pkt_magic;
                            rx_pkt_type_reg     <= rx_pkt_type;
                            rx_pkt_flags_reg    <= rx_pkt_flags;
                            rx_pkt_seq_reg      <= rx_pkt_seq;
                            rx_pkt_opcode_reg   <= rx_pkt_opcode;
                            rx_pkt_arg1_reg     <= rx_pkt_arg1;
                            rx_pkt_arg2_reg     <= rx_pkt_arg2;
                            rx_pkt_valid_reg    <= 1'b1;
                            $display("[%0t] LUDP: RX parsed magic=%04h type=%02h opcode=%04h", $time, rx_pkt_magic, rx_pkt_type, rx_pkt_opcode);
                        end
                    end
                end

                STATE_TX_HEADER: begin
                    // Track UDP header handshake
                    if (tx_udp_hdr_ready) begin
                        tx_hdr_sent_reg <= 1'b1;
                    end

                    // Count payload beats
                    if (tx_udp_payload_axis_tvalid && tx_udp_payload_axis_tready) begin
                        tx_beat_count_reg <= tx_beat_count_reg + 1;
                    end
                end

                STATE_TX_DATA: begin
                    // Track actual payload size as data flows through
                    if (tx_data_axis_tvalid && tx_data_axis_tready) begin
                        // Count bytes based on tkeep
                        // For 64-bit data: tkeep[0]=1 means byte 0 valid, etc.
                        // Simplified: assume full beats except possibly last
                        if (tx_data_axis_tlast) begin
                            // Last beat: count actual bytes from tkeep
                            // This is a simplified calculation - could be more precise
                            tx_payload_size_reg <= tx_payload_bytes_sent_reg + KEEP_WIDTH;
                            seq_num_reg         <= seq_num_reg + 1;
                            packets_sent_reg    <= packets_sent_reg + 1;
                        end else begin
                            tx_payload_bytes_sent_reg <= tx_payload_bytes_sent_reg + KEEP_WIDTH;
                        end
                    end
                end

                STATE_TX_RESP: begin
                    // Track UDP header handshake
                    if (!tx_hdr_sent_reg && tx_udp_hdr_ready) begin
                        tx_hdr_sent_reg <= 1'b1;
                        $display("[%0t] LUDP: TX resp header ready", $time);
                    end

                    // Count payload beats and clear response valid on completion
                    if (tx_udp_payload_axis_tvalid && tx_udp_payload_axis_tready) begin
                        tx_beat_count_reg <= tx_beat_count_reg + 1;
                        if (tx_udp_payload_axis_tlast) begin
                            resp_valid_reg <= 1'b0;
                            $display("[%0t] LUDP: TX resp complete", $time);
                        end
                    end
                end

                default: begin
                    // Should not reach here
                end
            endcase

            // Update FSM state
            state_reg <= state_next;

            // Handle status interface (higher priority than FSM)
            if (status_valid && status_ready) begin
                resp_opcode_reg <= status_opcode;
                resp_cmd_id_reg <= 32'h0;
                resp_status_reg <= 8'h00;
                resp_data_reg   <= status_data;
                resp_valid_reg  <= 1'b1;
                resp_is_cpl_reg <= 1'b1;
            end
        end
    end

endmodule
