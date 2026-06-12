// LUDP Retransmission Buffer Module
// Interfaces with external AXI RAM (or any memory with write/read ports).
// Stores packet metadata locally, but payload data is written to/read from
// external memory. This avoids large internal BRAM usage.
//
// Architecture:
//   - Local metadata table: seq, size, valid, mem_base_addr
//   - External memory write port: stores payload beats as they are transmitted
//   - External memory read port: reads payload beats for retransmission
//
// Memory layout (per packet):
//   Each packet occupies a contiguous region in external memory.
//   Base addresses are assigned round-robin from a circular buffer.
module ludp_retx_buffer #(
    parameter int DATA_WIDTH        = 64,
    parameter int KEEP_WIDTH        = 8,
    parameter int MAX_PAYLOAD_BYTES = 9000,
    parameter int MAX_PKTS          = 16,
    // External memory address width (byte address)
    parameter int MEM_ADDR_W        = 32,
    // Base address of the circular buffer in external memory
    parameter logic [MEM_ADDR_W-1:0] MEM_BASE_ADDR = '0,
    // Size of each packet slot in external memory (must be >= MAX_PAYLOAD_BYTES)
    parameter int MEM_SLOT_SIZE     = 16384
)(
    input  wire        clk,
    input  wire        rst,

    // Store interface (AXI-Stream slave)
    // Used by TX to store payload beats as they are transmitted.
    input  wire [DATA_WIDTH-1:0] store_axis_tdata,
    input  wire [KEEP_WIDTH-1:0] store_axis_tkeep,
    input  wire                  store_axis_tvalid,
    output logic                 store_axis_tready,
    input  wire                  store_axis_tlast,
    input  wire                  store_axis_tuser,

    // Packet metadata (valid when store_pkt_done is asserted)
    input  wire [31:0] store_seq,
    input  wire        store_pkt_done,
    input  wire [15:0] store_pkt_size,

    // Retransmission request
    input  wire        retx_req,
    input  wire [31:0] retx_seq,
    output logic       retx_found,
    output logic       retx_not_found,

    // Retransmission read interface (AXI-Stream master)
    output logic [DATA_WIDTH-1:0] retx_axis_tdata,
    output logic [KEEP_WIDTH-1:0] retx_axis_tkeep,
    output logic                  retx_axis_tvalid,
    input  wire                   retx_axis_tready,
    output logic                  retx_axis_tlast,
    output logic                  retx_axis_tuser,

    output logic [15:0] retx_pkt_size,

    // External memory write port (simple write-only interface)
    // Write address is byte-aligned. Data is written on wvalid && wready.
    output logic [MEM_ADDR_W-1:0] mem_wr_addr,
    output logic [DATA_WIDTH-1:0] mem_wr_data,
    output logic [KEEP_WIDTH-1:0] mem_wr_strb,
    output logic                  mem_wr_valid,
    input  wire                   mem_wr_ready,

    // External memory read port (simple read-only interface)
    // Read address is byte-aligned. Data returned on rvalid.
    output logic [MEM_ADDR_W-1:0] mem_rd_addr,
    output logic                  mem_rd_valid,
    input  wire                   mem_rd_ready,
    input  wire  [DATA_WIDTH-1:0] mem_rd_data,
    input  wire                   mem_rd_valid_in,

    // Clear all buffered packets (e.g. on CMD_START)
    input  wire        clear
);

    localparam int MAX_BEATS = (MAX_PAYLOAD_BYTES + KEEP_WIDTH - 1) / KEEP_WIDTH;
    localparam int PKTA_W    = $clog2(MAX_PKTS);
    localparam int BEAT_A_W  = $clog2(MAX_BEATS);
    localparam int BEAT_BYTE_W = $clog2(KEEP_WIDTH);

    // Packet metadata (stored locally in registers/BRAM)
    logic [15:0]           pkt_size [MAX_PKTS-1:0];
    logic [31:0]           pkt_seq  [MAX_PKTS-1:0];
    logic                  pkt_valid[MAX_PKTS-1:0];
    logic [MEM_ADDR_W-1:0] pkt_base_addr [MAX_PKTS-1:0];

    // Write state
    logic [PKTA_W-1:0]   wr_pkt_idx_reg;
    logic [BEAT_A_W-1:0] wr_beat_idx_reg;

    // Retransmission state
    typedef enum logic [2:0] {
        RETX_IDLE,
        RETX_RD_REQ,
        RETX_RD_WAIT,
        RETX_READ
    } retx_state_t;
    retx_state_t retx_state_reg;
    logic [PKTA_W-1:0]   retx_pkt_idx_reg;
    logic [BEAT_A_W-1:0] retx_beat_idx_reg;
    logic [15:0]         retx_total_beats_reg;

    // Retransmission read data buffer (1-deep to handle mem latency)
    logic [DATA_WIDTH-1:0] retx_rd_data_reg;
    logic                  retx_rd_data_valid_reg;

    // Retx req edge detection
    logic retx_req_d;
    always_ff @(posedge clk) begin
        if (rst || clear)
            retx_req_d <= 1'b0;
        else
            retx_req_d <= retx_req;
    end
    wire retx_req_pulse = retx_req && !retx_req_d;

    // Lookup logic (combinational)
    logic [PKTA_W-1:0] lookup_idx;
    logic              lookup_found;

    always_comb begin
        lookup_idx   = '0;
        lookup_found = 1'b0;
        for (int i = 0; i < MAX_PKTS; i = i + 1) begin
            if (pkt_valid[i] && (pkt_seq[i] == retx_seq)) begin
                lookup_found = 1'b1;
                lookup_idx   = i[PKTA_W-1:0];
            end
        end
    end

    // Memory address calculation
    wire [MEM_ADDR_W-1:0] wr_base_addr = MEM_BASE_ADDR + MEM_ADDR_W'(wr_pkt_idx_reg) * MEM_ADDR_W'(MEM_SLOT_SIZE);
    wire [MEM_ADDR_W-1:0] wr_beat_addr = wr_base_addr + (MEM_ADDR_W'(wr_beat_idx_reg) << BEAT_BYTE_W);

    wire [MEM_ADDR_W-1:0] retx_base_addr = pkt_base_addr[retx_pkt_idx_reg];
    wire [MEM_ADDR_W-1:0] retx_beat_addr = retx_base_addr + (MEM_ADDR_W'(retx_beat_idx_reg) << BEAT_BYTE_W);

    // Store logic: write payload beats to external memory
    always_ff @(posedge clk) begin
        if (rst || clear) begin
            wr_pkt_idx_reg  <= '0;
            wr_beat_idx_reg <= '0;
            for (int i = 0; i < MAX_PKTS; i = i + 1) begin
                pkt_valid[i] <= 1'b0;
            end
        end else begin
            if (store_pkt_done) begin
                pkt_seq[wr_pkt_idx_reg]      <= store_seq;
                pkt_size[wr_pkt_idx_reg]     <= store_pkt_size;
                pkt_valid[wr_pkt_idx_reg]    <= 1'b1;
                pkt_base_addr[wr_pkt_idx_reg] <= wr_base_addr;
                wr_pkt_idx_reg <= wr_pkt_idx_reg + 1;
                wr_beat_idx_reg <= '0;
            end else if (store_axis_tvalid && store_axis_tready) begin
                wr_beat_idx_reg <= wr_beat_idx_reg + 1;
            end
        end
    end

    assign store_axis_tready = 1'b1;

    // External memory write port assignment
    assign mem_wr_addr = wr_beat_addr;
    assign mem_wr_data = store_axis_tdata;
    assign mem_wr_strb = store_axis_tkeep;
    assign mem_wr_valid = store_axis_tvalid && store_axis_tready;

    // Combinational retx status for immediate visibility
    always_comb begin
        retx_found     = retx_req_pulse && lookup_found;
        retx_not_found = retx_req_pulse && !lookup_found;
    end

    // Retransmission control FSM
    always_ff @(posedge clk) begin
        if (rst || clear) begin
            retx_state_reg       <= RETX_IDLE;
            retx_pkt_idx_reg     <= '0;
            retx_beat_idx_reg    <= '0;
            retx_total_beats_reg <= '0;
            retx_rd_data_valid_reg <= 1'b0;
        end else begin
            case (retx_state_reg)
                RETX_IDLE: begin
                    retx_beat_idx_reg <= '0;
                    retx_rd_data_valid_reg <= 1'b0;
                    if (retx_req_pulse) begin
                        if (lookup_found) begin
                            retx_state_reg       <= RETX_RD_REQ;
                            retx_pkt_idx_reg     <= lookup_idx;
                            retx_total_beats_reg <= (pkt_size[lookup_idx] + KEEP_WIDTH - 1) / KEEP_WIDTH;
                        end
                    end
                end

                RETX_RD_REQ: begin
                    // Issue read request for current beat
                    if (mem_rd_ready) begin
                        retx_state_reg <= RETX_RD_WAIT;
                    end
                end

                RETX_RD_WAIT: begin
                    // Wait for read data to arrive
                    if (mem_rd_valid_in) begin
                        retx_rd_data_reg <= mem_rd_data;
                        retx_rd_data_valid_reg <= 1'b1;
                        retx_state_reg <= RETX_READ;
                    end
                end

                RETX_READ: begin
                    // Current beat is being consumed on AXIS
                    if (retx_axis_tvalid && retx_axis_tready) begin
                        retx_rd_data_valid_reg <= 1'b0;

                        if (retx_beat_idx_reg + 1 >= retx_total_beats_reg) begin
                            // Last beat done
                            retx_state_reg <= RETX_IDLE;
                        end else begin
                            // Move to next beat and pre-fetch
                            retx_beat_idx_reg <= retx_beat_idx_reg + 1;
                            retx_state_reg <= RETX_RD_REQ;
                        end
                    end else if (mem_rd_valid_in && !retx_rd_data_valid_reg) begin
                        // Data arrived while we were stalled
                        retx_rd_data_reg <= mem_rd_data;
                        retx_rd_data_valid_reg <= 1'b1;
                    end
                end

                default: retx_state_reg <= RETX_IDLE;
            endcase
        end
    end

    // External memory read port assignment
    assign mem_rd_addr  = retx_beat_addr;
    assign mem_rd_valid = (retx_state_reg == RETX_RD_REQ);

    // Retransmission AXIS output
    always_comb begin
        retx_axis_tdata  = retx_rd_data_reg;
        retx_axis_tkeep  = {KEEP_WIDTH{1'b1}};
        retx_axis_tlast  = (retx_beat_idx_reg + 1 >= retx_total_beats_reg);
        retx_axis_tvalid = (retx_state_reg == RETX_READ) && retx_rd_data_valid_reg;
        retx_axis_tuser  = 1'b0;
    end

    assign retx_pkt_size = pkt_size[retx_pkt_idx_reg];

endmodule
