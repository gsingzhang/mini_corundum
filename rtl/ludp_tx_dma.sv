// ---------------------------------------------------------------------------
// ludp_tx_dma: DMA read/write engine for LUDP TX path
// ---------------------------------------------------------------------------
//
// Pure DMA engine that reads/writes an external RAM.
// NO knowledge of TX vs RETX — the scheduler tells it which address to read.
//
// Write path: receives wr_desc_base_addr, computes beat addresses, drives RAM
// write port from the wr_axis AXI-Stream input.
//
// Read path: receives rd_desc_req + rd_desc_base_addr + rd_desc_total_beats
// from the scheduler, reads data from RAM, outputs on rd_axis AXI-Stream.
// Uses fully-pipelined prefetch for zero-bubble throughput.
//
// Pipeline architecture (read path):
//   FLIGHT -> PREFETCH -> OUTPUT -> AXI-Stream
// ---------------------------------------------------------------------------
module ludp_tx_dma #(
    parameter int DATA_WIDTH        = 64,
    parameter int KEEP_WIDTH        = 8,
    parameter int MAX_PAYLOAD_BYTES = 9000,
    parameter int MEM_ADDR_W        = 32,
    parameter int MEM_SLOT_SIZE     = 16384
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        clear,

    // ---- Write channel (AXI-Stream input, from DMA controller) ---------------
    input  wire [DATA_WIDTH-1:0] wr_axis_tdata,
    input  wire [KEEP_WIDTH-1:0] wr_axis_tkeep,
    input  wire                  wr_axis_tvalid,
    input  wire                  wr_axis_tlast,
    input  wire                  wr_axis_tuser,

    // ---- Write descriptor (from scheduler) ----------------------------------
    input  wire [MEM_ADDR_W-1:0] wr_desc_base_addr,
    input  wire                  wr_desc_enable,
    output logic                 wr_desc_done,

    // ---- Read descriptor (from scheduler) -----------------------------------
    input  wire                  rd_desc_req,
    input  wire [MEM_ADDR_W-1:0] rd_desc_base_addr,
    input  wire [15:0]           rd_desc_total_beats,
    output logic                 rd_desc_busy,

    // ---- Read channel (AXI-Stream output, no TX/RETX distinction) -----------
    output logic [DATA_WIDTH-1:0] rd_axis_tdata,
    output logic [KEEP_WIDTH-1:0] rd_axis_tkeep,
    output logic                  rd_axis_tvalid,
    input  wire                   rd_axis_tready,
    output logic                  rd_axis_tlast,
    output logic                  rd_axis_tuser,
    output logic                  rd_axis_done,

    // ---- External RAM (1R1W) port -------------------------------------------
    output logic [MEM_ADDR_W-1:0] mem_wr_addr,
    output logic [DATA_WIDTH-1:0] mem_wr_data,
    output logic [KEEP_WIDTH-1:0] mem_wr_strb,
    output logic                  mem_wr_valid,
    input  wire                   mem_wr_ready,
    output logic [MEM_ADDR_W-1:0] mem_rd_addr,
    output logic                  mem_rd_valid,
    input  wire                   mem_rd_ready,
    input  wire  [DATA_WIDTH-1:0] mem_rd_data,
    input  wire                   mem_rd_valid_in
);

    localparam int MAX_BEATS   = (MAX_PAYLOAD_BYTES + KEEP_WIDTH - 1) / KEEP_WIDTH;
    localparam int BEAT_A_W    = $clog2(MAX_BEATS);
    localparam int BEAT_BYTE_W = $clog2(KEEP_WIDTH);

    // ======== DMA Write Side =================================================
    logic [BEAT_A_W-1:0] dma_beat_idx_reg;

    wire dma_wr_beat = wr_axis_tvalid && wr_desc_enable;
    assign wr_desc_done = dma_wr_beat && wr_axis_tlast;

    wire [MEM_ADDR_W-1:0] dma_beat_addr = wr_desc_base_addr +
                                           (MEM_ADDR_W'(dma_beat_idx_reg) << BEAT_BYTE_W);

    always_ff @(posedge clk) begin
        if (rst || clear) begin
            dma_beat_idx_reg <= '0;
        end else if (dma_wr_beat) begin
            if (wr_axis_tlast)
                dma_beat_idx_reg <= '0;
            else
                dma_beat_idx_reg <= dma_beat_idx_reg + 1'b1;
        end
    end

    // ======== Read Pipeline ==================================================
    typedef enum logic [1:0] {
        RD_IDLE,
        RD_REQ,
        RD_WAIT,
        RD_READ
    } rd_state_t;

    rd_state_t rd_state_reg;
    logic [MEM_ADDR_W-1:0] rd_base_addr_reg;
    logic [BEAT_A_W-1:0]   rd_beat_idx_reg;
    logic [BEAT_A_W-1:0]   rd_read_beat_reg;
    logic [15:0]           rd_total_beats_reg;

    logic [DATA_WIDTH-1:0] rd_data_reg;
    logic                  rd_data_valid_reg;
    logic [DATA_WIDTH-1:0] rd_prefetch_data_reg;
    logic                  rd_prefetch_valid_reg;
    logic                  rd_prefetch_issued_reg;

    // ======== Pipeline Condition Wires =======================================
    wire rd_last_beat  = (rd_beat_idx_reg + 1 >= rd_total_beats_reg);
    wire rd_more_beats = (rd_read_beat_reg < rd_total_beats_reg);
    wire rd_in_pipe    = (rd_state_reg == RD_READ) || (rd_state_reg == RD_WAIT);

    wire rd_consume = (rd_state_reg == RD_READ) && rd_data_valid_reg &&
                      rd_axis_tvalid && rd_axis_tready;

    wire rd_flight_complete = rd_prefetch_issued_reg && mem_rd_valid_in;

    wire rd_prefetch_free = !rd_prefetch_valid_reg || (rd_consume && rd_prefetch_valid_reg);
    wire rd_flight_free   = !rd_prefetch_issued_reg || rd_flight_complete;

    wire rd_issue_prefetch = rd_in_pipe && rd_more_beats &&
                             rd_prefetch_free && rd_flight_free && mem_rd_ready;

    wire rd_capture_prefetch = (rd_state_reg == RD_READ) && rd_flight_complete &&
                               !rd_consume && !rd_prefetch_valid_reg;

    wire rd_read_accepted = mem_rd_valid && mem_rd_ready;

    wire [MEM_ADDR_W-1:0] rd_read_addr = rd_base_addr_reg +
                                          (MEM_ADDR_W'(rd_read_beat_reg) << BEAT_BYTE_W);

    // ======== Sequential Logic ===============================================
    always_ff @(posedge clk) begin
        if (rst || clear) begin
            rd_state_reg          <= RD_IDLE;
            rd_base_addr_reg      <= '0;
            rd_beat_idx_reg       <= '0;
            rd_read_beat_reg      <= '0;
            rd_total_beats_reg    <= '0;
            rd_data_valid_reg     <= 1'b0;
            rd_prefetch_issued_reg <= 1'b0;
            rd_prefetch_valid_reg  <= 1'b0;
            rd_prefetch_data_reg   <= '0;
        end else begin
            if (rd_read_accepted)
                rd_read_beat_reg <= rd_read_beat_reg + 1'b1;

            case (rd_state_reg)
                RD_IDLE: begin
                    rd_beat_idx_reg        <= '0;
                    rd_read_beat_reg       <= '0;
                    rd_data_valid_reg      <= 1'b0;
                    rd_prefetch_issued_reg <= 1'b0;
                    rd_prefetch_valid_reg  <= 1'b0;
                    if (rd_desc_req) begin
                        rd_state_reg       <= RD_REQ;
                        rd_base_addr_reg   <= rd_desc_base_addr;
                        rd_total_beats_reg <= rd_desc_total_beats;
                    end
                end

                RD_REQ: begin
                    if (mem_rd_ready)
                        rd_state_reg <= RD_WAIT;
                end

                RD_WAIT: begin
                    if (mem_rd_valid_in || rd_prefetch_issued_reg) begin
                        rd_data_reg            <= mem_rd_data;
                        rd_data_valid_reg      <= 1'b1;
                        rd_state_reg           <= RD_READ;
                        rd_prefetch_issued_reg <= 1'b0;
                    end
                end

                RD_READ: begin
                    if (rd_consume) begin
                        if (rd_last_beat) begin
                            rd_state_reg           <= RD_IDLE;
                            rd_data_valid_reg      <= 1'b0;
                            rd_prefetch_issued_reg <= 1'b0;
                            rd_prefetch_valid_reg  <= 1'b0;
                        end else if (rd_prefetch_valid_reg) begin
                            rd_data_reg       <= rd_prefetch_data_reg;
                            rd_data_valid_reg <= 1'b1;
                            rd_beat_idx_reg   <= rd_beat_idx_reg + 1'b1;
                            if (rd_flight_complete) begin
                                rd_prefetch_data_reg   <= mem_rd_data;
                                rd_prefetch_valid_reg  <= 1'b1;
                                rd_prefetch_issued_reg <= 1'b0;
                            end else begin
                                rd_prefetch_valid_reg  <= 1'b0;
                            end
                        end else if (rd_flight_complete) begin
                            rd_data_reg            <= mem_rd_data;
                            rd_data_valid_reg      <= 1'b1;
                            rd_beat_idx_reg        <= rd_beat_idx_reg + 1'b1;
                            rd_prefetch_issued_reg <= 1'b0;
                        end else if (rd_prefetch_issued_reg) begin
                            rd_data_valid_reg <= 1'b0;
                            rd_beat_idx_reg   <= rd_beat_idx_reg + 1'b1;
                            rd_state_reg      <= RD_WAIT;
                        end else begin
                            rd_data_valid_reg <= 1'b0;
                            rd_beat_idx_reg   <= rd_beat_idx_reg + 1'b1;
                            rd_state_reg      <= RD_REQ;
                        end
                    end
                end

                default: rd_state_reg <= RD_IDLE;
            endcase

            if (rd_capture_prefetch) begin
                rd_prefetch_data_reg   <= mem_rd_data;
                rd_prefetch_valid_reg  <= 1'b1;
                rd_prefetch_issued_reg <= 1'b0;
            end
            if (rd_issue_prefetch) begin
                rd_prefetch_issued_reg <= 1'b1;
            end
        end
    end

    // ======== Output Assignments =============================================
    assign rd_desc_busy = (rd_state_reg != RD_IDLE);

    assign rd_axis_tdata  = rd_data_reg;
    assign rd_axis_tkeep  = {KEEP_WIDTH{1'b1}};
    assign rd_axis_tlast  = rd_last_beat;
    assign rd_axis_tvalid = (rd_state_reg == RD_READ) && rd_data_valid_reg;
    assign rd_axis_tuser  = 1'b0;
    assign rd_axis_done   = (rd_state_reg == RD_READ) && rd_consume && rd_last_beat;

    assign mem_wr_addr  = dma_beat_addr;
    assign mem_wr_data  = wr_axis_tdata;
    assign mem_wr_strb  = wr_axis_tkeep;
    assign mem_wr_valid = dma_wr_beat;

    assign mem_rd_addr  = rd_read_addr;
    assign mem_rd_valid = (rd_state_reg == RD_REQ) || rd_issue_prefetch;

endmodule
