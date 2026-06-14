// ---------------------------------------------------------------------------
// ludp_tx_scheduler: Block manager + read scheduler for LUDP TX path
// ---------------------------------------------------------------------------
//
// Manages a pool of NUM_BLOCKS memory slots and decides which block the
// DMA engine should read from next.  Priority: RETX > TX.
//
// Block states:
//   EMPTY (0): Free, available for DMA to write a new packet.
//   READY (1): DMA finished writing, TX can start reading.
//   SENT  (2): TX finished reading, data kept for NACK retransmission.
//              Recycled to EMPTY when the next packet completes, unless
//              a retransmission is pending for this block.
//
// This module does NOT handle data — only control signals and addresses.
// Actual data flows through ludp_tx_dma which drives the RAM ports.
// ---------------------------------------------------------------------------
module ludp_tx_scheduler #(
    parameter int NUM_BLOCKS        = 3,
    parameter int KEEP_WIDTH        = 8,
    parameter int MEM_ADDR_W        = 32,
    parameter logic [MEM_ADDR_W-1:0] MEM_BASE_ADDR = '0,
    parameter int MEM_SLOT_SIZE     = 16384
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        clear,

    // ---- DMA write control (scheduler tells DMA, DMA tells scheduler) -------
    output logic                 dma_wr_enable,   // current block is EMPTY, can accept
    input  wire                  dma_wr_block_done, // 1-cycle pulse: DMA wrote last beat
    input  wire [15:0]           dma_pkt_size,    // packet size in bytes

    // ---- TX read request (from protocol layer) ------------------------------
    output logic        tx_pkt_ready,    // a READY block exists
    input  wire         tx_pkt_start,    // protocol layer starts reading
    input  wire [31:0]  tx_pkt_seq,      // sequence number assigned by protocol
    output logic        tx_pkt_done,     // 1-cycle pulse: TX read finished

    // ---- Retransmission interface (control only) ----------------------------
    input  wire        retx_req,         // 1-cycle pulse: request retransmission
    input  wire [31:0] retx_seq,         // sequence number to retransmit
    output logic       retx_found,       // held high until retx starts

    // ---- Unified read metadata ---------------------------------------------
    output logic [15:0] rd_pkt_size,     // size of next packet to transmit
    output logic [31:0] rd_pkt_seq,      // seq of next packet to transmit

    // ---- DMA engine read request --------------------------------------------
    output logic                  dma_rd_req,
    output logic [MEM_ADDR_W-1:0] dma_rd_base_addr,
    output logic [15:0]           dma_rd_total_beats,
    input  wire                   dma_rd_busy,
    input  wire                   dma_rd_done,

    // ---- DMA engine write address -------------------------------------------
    output logic [MEM_ADDR_W-1:0] dma_wr_base_addr,

    // ---- Read type indicator (for protocol layer) ---------------------------
    output logic        rd_is_retx       // current read is a retransmission
);

    localparam int BLK_W  = $clog2(NUM_BLOCKS);
    localparam int KEEP_W = KEEP_WIDTH;

    localparam logic [1:0] BLK_EMPTY = 2'd0;
    localparam logic [1:0] BLK_READY = 2'd1;
    localparam logic [1:0] BLK_SENT  = 2'd2;

    // ======== Per-block metadata =============================================
    logic [15:0] blk_size  [NUM_BLOCKS-1:0];
    logic [31:0] blk_seq   [NUM_BLOCKS-1:0];
    logic [1:0]  blk_state [NUM_BLOCKS-1:0];

    // ======== Pointers =======================================================
    logic [BLK_W-1:0] dma_wr_idx_reg;
    logic [BLK_W-1:0] tx_rd_idx_reg;
    logic [BLK_W-1:0] rd_blk_idx_reg;

    // ======== Retx pending latch =============================================
    logic              retx_pending_reg;
    logic [BLK_W-1:0]  retx_pending_idx_reg;

    // ======== Retx request edge detection ====================================
    logic retx_req_d;
    always_ff @(posedge clk) begin
        if (rst || clear)
            retx_req_d <= 1'b0;
        else
            retx_req_d <= retx_req;
    end
    wire retx_req_pulse = retx_req && !retx_req_d;

    // ======== Retx lookup: combinational =====================================
    logic [BLK_W-1:0] retx_lookup_idx;
    logic              retx_lookup_found;
    always_comb begin
        retx_lookup_idx   = '0;
        retx_lookup_found = 1'b0;
        for (int i = 0; i < NUM_BLOCKS; i = i + 1) begin
            if (blk_state[i] == BLK_SENT && blk_seq[i] == retx_seq) begin
                retx_lookup_found = 1'b1;
                retx_lookup_idx   = i[BLK_W-1:0];
            end
        end
    end

    assign retx_found = retx_pending_reg;

    // ======== TX status outputs ==============================================
    assign tx_pkt_ready = (blk_state[tx_rd_idx_reg] == BLK_READY);

    // ======== Unified read metadata ==========================================
    wire [BLK_W-1:0] sch_target_blk = retx_pending_reg ? retx_pending_idx_reg :
                                                         tx_rd_idx_reg;
    assign rd_pkt_size = blk_size[sch_target_blk];
    assign rd_pkt_seq  = retx_pending_reg ? blk_seq[retx_pending_idx_reg] : tx_pkt_seq;

    // ======== DMA write backpressure =========================================
    assign dma_wr_enable = (blk_state[dma_wr_idx_reg] == BLK_EMPTY);

    // ======== Helper: circular block advance =================================
    function automatic [BLK_W-1:0] blk_next;
        input [BLK_W-1:0] idx;
        if (idx == NUM_BLOCKS[BLK_W-1:0] - 1)
            blk_next = '0;
        else
            blk_next = idx + 1'b1;
    endfunction

    // ======== Address calculation ============================================
    assign dma_wr_base_addr = MEM_BASE_ADDR + MEM_ADDR_W'(dma_wr_idx_reg) * MEM_ADDR_W'(MEM_SLOT_SIZE);

    // ======== Scheduling FSM =================================================
    typedef enum logic [1:0] {
        SCH_IDLE,
        SCH_READING
    } sch_state_t;

    sch_state_t sch_state_reg;
    logic       sch_is_retx_reg;

    wire sch_can_issue = !dma_rd_busy;

    always_ff @(posedge clk) begin
        if (rst || clear) begin
            dma_wr_idx_reg     <= '0;
            tx_rd_idx_reg      <= '0;
            rd_blk_idx_reg     <= '0;
            retx_pending_reg   <= 1'b0;
            retx_pending_idx_reg <= '0;
            sch_state_reg      <= SCH_IDLE;
            sch_is_retx_reg    <= 1'b0;
            for (int i = 0; i < NUM_BLOCKS; i = i + 1) begin
                blk_state[i] <= BLK_EMPTY;
                blk_seq[i]   <= 32'd0;
                blk_size[i]  <= 16'd0;
            end
        end else begin
            if (retx_req_pulse && retx_lookup_found && !retx_pending_reg) begin
                retx_pending_reg     <= 1'b1;
                retx_pending_idx_reg <= retx_lookup_idx;
            end

            if (dma_wr_block_done) begin
                blk_size[dma_wr_idx_reg]  <= dma_pkt_size;
                blk_state[dma_wr_idx_reg] <= BLK_READY;
                dma_wr_idx_reg <= blk_next(dma_wr_idx_reg);
            end

            if (tx_pkt_start && (blk_state[tx_rd_idx_reg] == BLK_READY)) begin
                blk_seq[tx_rd_idx_reg] <= tx_pkt_seq;
            end

            if (dma_rd_done) begin
                if (sch_is_retx_reg) begin
                end else begin
                    blk_state[rd_blk_idx_reg] <= BLK_SENT;
                    tx_rd_idx_reg <= blk_next(tx_rd_idx_reg);
                    for (int i = 0; i < NUM_BLOCKS; i = i + 1) begin
                        if (i != rd_blk_idx_reg && blk_state[i] == BLK_SENT &&
                            !(retx_pending_reg && retx_pending_idx_reg == i[BLK_W-1:0])) begin
                            blk_state[i] <= BLK_EMPTY;
                        end
                    end
                end
            end

            case (sch_state_reg)
                SCH_IDLE: begin
                    if (retx_pending_reg && sch_can_issue) begin
                        sch_state_reg   <= SCH_READING;
                        sch_is_retx_reg <= 1'b1;
                        rd_blk_idx_reg  <= retx_pending_idx_reg;
                        retx_pending_reg <= 1'b0;
                    end else if (tx_pkt_start && (blk_state[tx_rd_idx_reg] == BLK_READY) && sch_can_issue) begin
                        sch_state_reg   <= SCH_READING;
                        sch_is_retx_reg <= 1'b0;
                        rd_blk_idx_reg  <= tx_rd_idx_reg;
                    end
                end

                SCH_READING: begin
                    if (dma_rd_done)
                        sch_state_reg <= SCH_IDLE;
                end

                default: sch_state_reg <= SCH_IDLE;
            endcase
        end
    end

    // ======== DMA read request outputs =======================================

    assign dma_rd_req = (sch_state_reg == SCH_IDLE) && (
                        (retx_pending_reg && sch_can_issue) ||
                        (tx_pkt_start && (blk_state[tx_rd_idx_reg] == BLK_READY) && sch_can_issue));

    assign dma_rd_base_addr = MEM_BASE_ADDR + MEM_ADDR_W'(sch_target_blk) * MEM_ADDR_W'(MEM_SLOT_SIZE);

    assign dma_rd_total_beats = (blk_size[sch_target_blk] + KEEP_W - 1) / KEEP_W;

    assign rd_is_retx = sch_is_retx_reg;

    assign tx_pkt_done = dma_rd_done && !sch_is_retx_reg;

endmodule
