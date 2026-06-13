// ---------------------------------------------------------------------------
// ludp_tx_buffer: Unified TX buffer for LUDP protocol
// ---------------------------------------------------------------------------
//
// Architecture Overview:
//
//   DMA WRITE (AXI-S) -> [BLOCK N] -> EXTERNAL RAM (64-bit wide)
//                                         |
//   TX READ (AXI-S)   <------------------ (reads from blocks in READY state)
//                                         |
//   RETX READ (AXI-S) <------------------ (reads from blocks in SENT state)
//
// This module manages a pool of "blocks" (NUM_BLOCKS = 3).
// Each block is a fixed-size memory slot in the external RAM (MEM_SLOT_SIZE bytes).
// A block can be in one of three states:
//
//   EMPTY (2'd0):  Free, available for DMA to write a new packet.
//   READY (2'd1):  DMA has finished writing, TX can start reading this packet.
//   SENT  (2'd2):  TX has finished reading. The data is kept for NACK retransmission.
//                  A SENT block is recycled back to EMPTY when the NEXT packet is done.
//                  If a block is "pending" for retransmission (retx_pending_reg), it is
//                  protected from being recycled until the retransmission starts.
//
// Block management uses three independent pointers:
//   dma_wr_idx_reg - points to the block DMA is currently writing to.
//   tx_rd_idx_reg  - points to the block TX should read next.
//   rd_blk_idx_reg - points to the block currently being read (TX or RETX).
//
// Read FSM with fully-pipelined prefetch:
//   RD_IDLE       -> RD_TX_REQ:   TX requests reading (tx_pkt_start)
//   RD_IDLE       -> RD_RETX_REQ: Retransmission was latched (retx_pending_reg)
//   RD_TX_REQ     -> RD_TX_WAIT:  Memory read request issued, waiting for data.
//   RD_TX_WAIT    -> RD_TX_READ:  First beat of data returned.
//                                  Also issues prefetch for beat 1 here.
//   RD_TX_READ    -> RD_TX_READ:  Beat consumed, prefetch data available (0 bubbles!)
//   RD_TX_READ    -> RD_TX_WAIT:  Beat consumed, prefetch in flight (1 bubble, rare)
//   RD_TX_READ    -> RD_IDLE:     Last beat consumed on AXI-Stream.
//   RD_RETX_* is the same flow but for retransmission data.
//
// Prefetch pipeline (fully-pipelined for maximum throughput):
//   The key insight: for a 1-cycle latency RAM, we can issue a new read every
//   cycle and get data back every cycle. The prefetch engine issues reads as
//   early as possible:
//
//   1. In RD_TX_WAIT: while waiting for beat 0 data, issue prefetch for beat 1.
//      When we enter RD_TX_READ, beat 1's data is already 1 cycle away.
//
//   2. In RD_TX_READ: when consuming beat K and beat K+1's data arrives
//      (mem_rd_valid_in), immediately issue a read for beat K+2. This achieves
//      0 bubbles between consecutive beats.
//
//   Two counters track progress:
//     rd_beat_idx_reg   - the beat currently being OUTPUT (incremented on consume)
//     rd_read_beat_reg  - the next beat to issue a READ for (incremented on issue)
//
//   The prefetch is issued when:
//     - We're in RD_TX_READ/RETX_READ or RD_TX_WAIT/RETX_WAIT
//     - rd_read_beat_reg < rd_total_beats_reg (more beats to read)
//     - Prefetch buffer is empty (!rd_prefetch_valid_reg)
//     - No read in flight, OR the in-flight read completes this cycle
//       (!rd_prefetch_issued_reg || mem_rd_valid_in)
//
//   The last condition enables back-to-back prefetches: when the previous
//   prefetch's data arrives (mem_rd_valid_in), we can immediately issue the
//   next one without waiting.
//
// Retransmission flow:
//   1. retx_req arrives with retx_seq
//   2. Combinational lookup: search all SENT blocks for matching seq
//   3. If found: retx_pending_reg = 1, store block index and seq
//   4. retx_found is held high, signaling TX module to start retx
//   5. Read FSM picks up retx_pending_reg, starts reading from that block
//   6. After retx data is read to the end, FSM returns to RD_IDLE
// ---------------------------------------------------------------------------
module ludp_tx_buffer #(
    parameter int DATA_WIDTH        = 64,
    parameter int KEEP_WIDTH        = 8,
    parameter int MAX_PAYLOAD_BYTES = 9000,
    parameter int NUM_BLOCKS        = 3,
    parameter int MEM_ADDR_W        = 32,
    parameter logic [MEM_ADDR_W-1:0] MEM_BASE_ADDR = '0,
    parameter int MEM_SLOT_SIZE     = 16384
)(
    input  wire        clk,              // system clock
    input  wire        rst,              // async reset (active high)
    input  wire        clear,            // sync clear all state

    // ---- DMA write port (AXI-Stream, from DMA controller) -----------------
    input  wire [DATA_WIDTH-1:0] dma_axis_tdata,   // payload data
    input  wire [KEEP_WIDTH-1:0] dma_axis_tkeep,   // byte valid (1 bit = 1 byte)
    input  wire                  dma_axis_tvalid,  // master has data
    output logic                 dma_axis_tready,  // buffer ready to accept
    input  wire                  dma_axis_tlast,   // last beat of packet
    input  wire                  dma_axis_tuser,   // unused (user signal)
    input  wire [15:0]           dma_pkt_size,     // total packet size in bytes

    // ---- TX read port (to TX module, AXI-Stream) --------------------------
    output logic        tx_pkt_ready,   // a block is READY; TX can start reading
    output logic [15:0] tx_pkt_size,    // size of the ready block (bytes)
    input  wire         tx_pkt_start,   // TX starts reading the current block
    input  wire [31:0]  tx_pkt_seq,     // TX assigns this sequence number
    output logic [DATA_WIDTH-1:0] tx_axis_tdata,
    output logic [KEEP_WIDTH-1:0] tx_axis_tkeep,
    output logic                  tx_axis_tvalid,
    input  wire                   tx_axis_tready,
    output logic                  tx_axis_tlast,
    output logic                  tx_axis_tuser,
    output logic        tx_pkt_done,     // 1-cycle pulse when TX read finished

    // ---- Retransmission read port (to TX module, AXI-Stream) ---------------
    input  wire        retx_req,         // 1-cycle pulse: request retransmission
    input  wire [31:0] retx_seq,         // sequence number to retransmit
    output logic       retx_found,       // held high until retx starts reading
    output logic       retx_not_found,   // 1-cycle pulse: seq not in SENT blocks
    output logic [31:0] retx_seq_out,    // seq of the pending retx
    output logic [DATA_WIDTH-1:0] retx_axis_tdata,
    output logic [KEEP_WIDTH-1:0] retx_axis_tkeep,
    output logic                  retx_axis_tvalid,
    input  wire                   retx_axis_tready,
    output logic                  retx_axis_tlast,
    output logic                  retx_axis_tuser,
    output logic [15:0] retx_pkt_size,   // size of the retx packet

    // ---- External RAM (1R1W) port ------------------------------------------
    output logic [MEM_ADDR_W-1:0] mem_wr_addr,   // write address
    output logic [DATA_WIDTH-1:0] mem_wr_data,   // write data
    output logic [KEEP_WIDTH-1:0] mem_wr_strb,   // write byte strobe
    output logic                  mem_wr_valid,  // write request
    input  wire                   mem_wr_ready,  // RAM accepted write
    output logic [MEM_ADDR_W-1:0] mem_rd_addr,   // read address
    output logic                  mem_rd_valid,  // read request
    input  wire                   mem_rd_ready,  // RAM accepted read
    input  wire  [DATA_WIDTH-1:0] mem_rd_data,   // read data (next cycle)
    input  wire                   mem_rd_valid_in  // read data valid flag
);

    localparam int MAX_BEATS   = (MAX_PAYLOAD_BYTES + KEEP_WIDTH - 1) / KEEP_WIDTH;
    localparam int BLK_W       = $clog2(NUM_BLOCKS);
    localparam int BEAT_A_W    = $clog2(MAX_BEATS);
    localparam int BEAT_BYTE_W = $clog2(KEEP_WIDTH);

    localparam logic [1:0] BLK_EMPTY = 2'd0;
    localparam logic [1:0] BLK_READY = 2'd1;
    localparam logic [1:0] BLK_SENT  = 2'd2;

    // ---- Per-block metadata -------------------------------------------------
    logic [15:0] blk_size  [NUM_BLOCKS-1:0];
    logic [31:0] blk_seq   [NUM_BLOCKS-1:0];
    logic [1:0]  blk_state [NUM_BLOCKS-1:0];

    // ---- DMA write side -----------------------------------------------------
    logic [BLK_W-1:0]   dma_wr_idx_reg;
    logic [BEAT_A_W-1:0] dma_beat_idx_reg;

    // ---- TX read side -------------------------------------------------------
    logic [BLK_W-1:0]   tx_rd_idx_reg;

    // ---- Unified read FSM (shared by TX and RETX) ---------------------------
    typedef enum logic [2:0] {
        RD_IDLE,         // idle, waiting for request
        RD_TX_REQ,       // TX: issue initial mem read request
        RD_TX_WAIT,      // TX: wait for first mem read response (prefetch may start here)
        RD_TX_READ,      // TX: outputting data on AXI-Stream (prefetch pipeline active)
        RD_RETX_REQ,     // RETX: issue initial mem read request
        RD_RETX_WAIT,    // RETX: wait for first mem read response
        RD_RETX_READ     // RETX: outputting data on AXI-Stream (prefetch pipeline active)
    } rd_state_t;

    rd_state_t rd_state_reg;
    logic [BLK_W-1:0]   rd_blk_idx_reg;
    logic [BEAT_A_W-1:0] rd_beat_idx_reg;    // beat currently being OUTPUT
    logic [BEAT_A_W-1:0] rd_read_beat_reg;   // next beat to issue a READ for
    logic [15:0]         rd_total_beats_reg;
    logic [DATA_WIDTH-1:0] rd_data_reg;
    logic                  rd_data_valid_reg;

    // ---- Prefetch pipeline registers ----------------------------------------
    logic                  rd_prefetch_issued_reg;
    logic                  rd_prefetch_valid_reg;
    logic [DATA_WIDTH-1:0] rd_prefetch_data_reg;

    // ---- Retx request detection: rising-edge pulse -------------------------
    logic retx_req_d;
    always_ff @(posedge clk) begin
        if (rst || clear)
            retx_req_d <= 1'b0;
        else
            retx_req_d <= retx_req;
    end
    wire retx_req_pulse = retx_req && !retx_req_d;

    // ---- Retx lookup: combinational seq match among SENT blocks -------------
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

    // ---- Retx pending latch -------------------------------------------------
    logic              retx_pending_reg;
    logic [BLK_W-1:0]  retx_pending_idx_reg;
    logic [31:0]       retx_pending_seq_reg;

    assign retx_found     = retx_pending_reg;
    assign retx_not_found = retx_req_pulse && !retx_lookup_found && !retx_pending_reg;
    assign retx_seq_out   = retx_pending_seq_reg;

    // ---- TX status outputs ---------------------------------------------------
    assign tx_pkt_ready = (blk_state[tx_rd_idx_reg] == BLK_READY);
    assign tx_pkt_size  = blk_size[tx_rd_idx_reg];

    // ---- Helper: circular block advance -------------------------------------
    function automatic [BLK_W-1:0] blk_next;
        input [BLK_W-1:0] idx;
        if (idx == NUM_BLOCKS[BLK_W-1:0] - 1)
            blk_next = '0;
        else
            blk_next = idx + 1'b1;
    endfunction

    // ---- External RAM address calculation ------------------------------------
    wire [MEM_ADDR_W-1:0] dma_base_addr = MEM_BASE_ADDR + MEM_ADDR_W'(dma_wr_idx_reg) * MEM_ADDR_W'(MEM_SLOT_SIZE);
    wire [MEM_ADDR_W-1:0] dma_beat_addr = dma_base_addr + (MEM_ADDR_W'(dma_beat_idx_reg) << BEAT_BYTE_W);

    wire [MEM_ADDR_W-1:0] rd_base_addr = MEM_BASE_ADDR + MEM_ADDR_W'(rd_blk_idx_reg) * MEM_ADDR_W'(MEM_SLOT_SIZE);

    // Read address uses rd_read_beat_reg (tracks next beat to READ, not output)
    wire [MEM_ADDR_W-1:0] rd_read_addr = rd_base_addr + (MEM_ADDR_W'(rd_read_beat_reg) << BEAT_BYTE_W);

    // ---- Prefetch control: combinational ------------------------------------
    //   Issue a prefetch when:
    //     - In READ or WAIT state (not IDLE or initial REQ)
    //     - There are more beats to read (rd_read_beat_reg < total)
    //     - Prefetch buffer is empty, OR full but we're consuming and it
    //       won't be refilled this cycle (enables speculative prefetch
    //       for zero-bubble back-to-back reads)
    //     - No read in flight, OR the in-flight read completes this cycle
    //       (this enables back-to-back prefetches for full throughput)
    //     - Not about to fill the buffer in the else-branch capture
    //       (prevents overfilling: pf_valid=1 + pf_issued=1 deadlock)
    wire rd_last_beat = (rd_beat_idx_reg + 1 >= rd_total_beats_reg);
    wire rd_consuming = (rd_state_reg == RD_TX_READ   && tx_axis_tvalid   && tx_axis_tready) ||
                        (rd_state_reg == RD_RETX_READ && retx_axis_tvalid && retx_axis_tready);
    wire rd_buffer_will_refill = rd_consuming && rd_prefetch_valid_reg &&
                                 rd_prefetch_issued_reg && mem_rd_valid_in;
    wire rd_filling_prefetch = (rd_state_reg == RD_TX_READ || rd_state_reg == RD_RETX_READ) &&
                               !rd_prefetch_valid_reg && rd_prefetch_issued_reg && mem_rd_valid_in &&
                               !rd_consuming;
    wire rd_prefetch_needed = (rd_state_reg == RD_TX_READ   || rd_state_reg == RD_RETX_READ ||
                               rd_state_reg == RD_TX_WAIT   || rd_state_reg == RD_RETX_WAIT) &&
                              (rd_read_beat_reg < rd_total_beats_reg) &&
                              (!rd_prefetch_valid_reg || (rd_consuming && !rd_buffer_will_refill)) &&
                              (!rd_prefetch_issued_reg || mem_rd_valid_in) &&
                              !rd_filling_prefetch;
    wire rd_prefetch_firing = rd_prefetch_needed && mem_rd_ready;

    // ---- DMA write: backpressure --------------------------------------------
    assign dma_axis_tready = (blk_state[dma_wr_idx_reg] == BLK_EMPTY);

    wire dma_wr_beat = dma_axis_tvalid && dma_axis_tready;

    // ---- TX done detection --------------------------------------------------
    wire tx_pkt_done_w = (rd_state_reg == RD_TX_READ) && rd_data_valid_reg &&
                         tx_axis_tvalid && tx_axis_tready &&
                         rd_last_beat;

    // ---- Read accepted by RAM (for rd_read_beat_reg tracking) ---------------
    wire rd_read_accepted = mem_rd_valid && mem_rd_ready;

    // ---- Main sequential block ----------------------------------------------
    always_ff @(posedge clk) begin
        if (rst || clear) begin
            dma_wr_idx_reg     <= '0;
            dma_beat_idx_reg   <= '0;
            tx_rd_idx_reg      <= '0;
            rd_state_reg       <= RD_IDLE;
            rd_blk_idx_reg     <= '0;
            rd_beat_idx_reg    <= '0;
            rd_read_beat_reg   <= '0;
            rd_total_beats_reg <= '0;
            rd_data_valid_reg  <= 1'b0;
            rd_prefetch_issued_reg <= 1'b0;
            rd_prefetch_valid_reg  <= 1'b0;
            rd_prefetch_data_reg   <= '0;
            retx_pending_reg      <= 1'b0;
            retx_pending_idx_reg  <= '0;
            retx_pending_seq_reg  <= 32'd0;
            for (int i = 0; i < NUM_BLOCKS; i = i + 1) begin
                blk_state[i] <= BLK_EMPTY;
                blk_seq[i]   <= 32'd0;
                blk_size[i]  <= 16'd0;
            end
        end else begin
            // --- Retx pending latch ---
            if (retx_req_pulse && retx_lookup_found && !retx_pending_reg) begin
                retx_pending_reg     <= 1'b1;
                retx_pending_idx_reg <= retx_lookup_idx;
                retx_pending_seq_reg <= retx_seq;
            end

            // --- DMA write: move data beat-by-beat into RAM ---
            if (dma_wr_beat) begin
                if (dma_axis_tlast) begin
                    blk_size[dma_wr_idx_reg]  <= dma_pkt_size;
                    blk_state[dma_wr_idx_reg] <= BLK_READY;
                    dma_beat_idx_reg <= '0;
                    dma_wr_idx_reg   <= blk_next(dma_wr_idx_reg);
                end else begin
                    dma_beat_idx_reg <= dma_beat_idx_reg + 1'b1;
                end
            end

            // --- TX seq latch: record the assigned sequence number ---
            if (tx_pkt_start && (blk_state[tx_rd_idx_reg] == BLK_READY)) begin
                blk_seq[tx_rd_idx_reg] <= tx_pkt_seq;
            end

            // --- TX done: mark block SENT, recycle old SENT blocks ---
            if (tx_pkt_done_w) begin
                blk_state[rd_blk_idx_reg] <= BLK_SENT;
                tx_rd_idx_reg <= blk_next(tx_rd_idx_reg);
                for (int i = 0; i < NUM_BLOCKS; i = i + 1) begin
                    if (i != rd_blk_idx_reg && blk_state[i] == BLK_SENT &&
                        !(retx_pending_reg && retx_pending_idx_reg == i[BLK_W-1:0])) begin
                        blk_state[i] <= BLK_EMPTY;
                    end
                end
            end

            // --- Read beat counter: increment when RAM accepts a read request ---
            if (rd_read_accepted) begin
                rd_read_beat_reg <= rd_read_beat_reg + 1'b1;
            end

            // --- Read FSM (shared by normal TX reads and RETX reads) ---
            case (rd_state_reg)
                RD_IDLE: begin
                    rd_beat_idx_reg        <= '0;
                    rd_read_beat_reg       <= '0;
                    rd_data_valid_reg      <= 1'b0;
                    rd_prefetch_issued_reg <= 1'b0;
                    rd_prefetch_valid_reg  <= 1'b0;
                    if (tx_pkt_start && (blk_state[tx_rd_idx_reg] == BLK_READY)) begin
                        rd_state_reg       <= RD_TX_REQ;
                        rd_blk_idx_reg     <= tx_rd_idx_reg;
                        rd_total_beats_reg <= (blk_size[tx_rd_idx_reg] + KEEP_WIDTH - 1) / KEEP_WIDTH;
                    end else if (retx_pending_reg) begin
                        rd_state_reg       <= RD_RETX_REQ;
                        rd_blk_idx_reg     <= retx_pending_idx_reg;
                        rd_total_beats_reg <= (blk_size[retx_pending_idx_reg] + KEEP_WIDTH - 1) / KEEP_WIDTH;
                        retx_pending_reg   <= 1'b0;
                    end
                end

                RD_TX_REQ: begin
                    if (mem_rd_ready) begin
                        rd_state_reg <= RD_TX_WAIT;
                    end
                end

                RD_TX_WAIT: begin
                    if (mem_rd_valid_in) begin
                        rd_data_reg            <= mem_rd_data;
                        rd_data_valid_reg      <= 1'b1;
                        rd_state_reg           <= RD_TX_READ;
                        rd_prefetch_issued_reg <= 1'b0;
                    end
                end

                RD_TX_READ: begin
                    if (tx_axis_tvalid && tx_axis_tready) begin
                        if (rd_last_beat) begin
                            rd_state_reg           <= RD_IDLE;
                            rd_data_valid_reg      <= 1'b0;
                            rd_prefetch_issued_reg <= 1'b0;
                            rd_prefetch_valid_reg  <= 1'b0;
                        end else if (rd_prefetch_valid_reg) begin
                            rd_data_reg       <= rd_prefetch_data_reg;
                            rd_data_valid_reg <= 1'b1;
                            rd_beat_idx_reg   <= rd_beat_idx_reg + 1'b1;
                            // Bug1 fix: if RAM data also arrives, capture it
                            // into the now-empty prefetch buffer (refill)
                            if (rd_prefetch_issued_reg && mem_rd_valid_in) begin
                                rd_prefetch_data_reg   <= mem_rd_data;
                                rd_prefetch_valid_reg  <= 1'b1;
                                rd_prefetch_issued_reg <= 1'b0;
                            end else begin
                                rd_prefetch_valid_reg <= 1'b0;
                            end
                        end else if (rd_prefetch_issued_reg && mem_rd_valid_in) begin
                            rd_data_reg            <= mem_rd_data;
                            rd_data_valid_reg      <= 1'b1;
                            rd_beat_idx_reg        <= rd_beat_idx_reg + 1'b1;
                            rd_prefetch_issued_reg <= 1'b0;
                        end else if (rd_prefetch_issued_reg || rd_prefetch_firing) begin
                            rd_data_valid_reg <= 1'b0;
                            rd_beat_idx_reg   <= rd_beat_idx_reg + 1'b1;
                            rd_state_reg      <= RD_TX_WAIT;
                        end else begin
                            rd_data_valid_reg <= 1'b0;
                            rd_beat_idx_reg   <= rd_beat_idx_reg + 1'b1;
                            rd_state_reg      <= RD_TX_REQ;
                        end
                    end else begin
                        // Bug2 fix: only capture if prefetch buffer is empty
                        if (mem_rd_valid_in && rd_prefetch_issued_reg && !rd_prefetch_valid_reg) begin
                            rd_prefetch_data_reg   <= mem_rd_data;
                            rd_prefetch_valid_reg  <= 1'b1;
                            rd_prefetch_issued_reg <= 1'b0;
                        end
                    end
                end

                RD_RETX_REQ: begin
                    if (mem_rd_ready) begin
                        rd_state_reg <= RD_RETX_WAIT;
                    end
                end

                RD_RETX_WAIT: begin
                    if (mem_rd_valid_in) begin
                        rd_data_reg            <= mem_rd_data;
                        rd_data_valid_reg      <= 1'b1;
                        rd_state_reg           <= RD_RETX_READ;
                        rd_prefetch_issued_reg <= 1'b0;
                    end
                end

                RD_RETX_READ: begin
                    if (retx_axis_tvalid && retx_axis_tready) begin
                        if (rd_last_beat) begin
                            rd_state_reg           <= RD_IDLE;
                            rd_data_valid_reg      <= 1'b0;
                            rd_prefetch_issued_reg <= 1'b0;
                            rd_prefetch_valid_reg  <= 1'b0;
                        end else if (rd_prefetch_valid_reg) begin
                            rd_data_reg       <= rd_prefetch_data_reg;
                            rd_data_valid_reg <= 1'b1;
                            rd_beat_idx_reg   <= rd_beat_idx_reg + 1'b1;
                            if (rd_prefetch_issued_reg && mem_rd_valid_in) begin
                                rd_prefetch_data_reg   <= mem_rd_data;
                                rd_prefetch_valid_reg  <= 1'b1;
                                rd_prefetch_issued_reg <= 1'b0;
                            end else begin
                                rd_prefetch_valid_reg <= 1'b0;
                            end
                        end else if (rd_prefetch_issued_reg && mem_rd_valid_in) begin
                            rd_data_reg            <= mem_rd_data;
                            rd_data_valid_reg      <= 1'b1;
                            rd_beat_idx_reg        <= rd_beat_idx_reg + 1'b1;
                            rd_prefetch_issued_reg <= 1'b0;
                        end else if (rd_prefetch_issued_reg || rd_prefetch_firing) begin
                            rd_data_valid_reg <= 1'b0;
                            rd_beat_idx_reg   <= rd_beat_idx_reg + 1'b1;
                            rd_state_reg      <= RD_RETX_WAIT;
                        end else begin
                            rd_data_valid_reg <= 1'b0;
                            rd_beat_idx_reg   <= rd_beat_idx_reg + 1'b1;
                            rd_state_reg      <= RD_RETX_REQ;
                        end
                    end else begin
                        if (mem_rd_valid_in && rd_prefetch_issued_reg && !rd_prefetch_valid_reg) begin
                            rd_prefetch_data_reg   <= mem_rd_data;
                            rd_prefetch_valid_reg  <= 1'b1;
                            rd_prefetch_issued_reg <= 1'b0;
                        end
                    end
                end

                default: rd_state_reg <= RD_IDLE;
            endcase

            // --- Prefetch issue tracking ---
            //   When rd_prefetch_needed is asserted and the RAM accepts the
            //   request, mark the prefetch as issued. This comes AFTER the FSM
            //   case so it overrides any FSM clearing of the flag — this is
            //   intentional: when we consume an old prefetch and issue a new
            //   one in the same cycle, the flag correctly stays at 1.
            if (rd_prefetch_firing) begin
                rd_prefetch_issued_reg <= 1'b1;
            end
        end
    end

    // ---- Debug: count cycles per state --------------------------------------
    (* mark_debug = "true" *) rd_state_t rd_state_dbg;
    always_ff @(posedge clk) begin
        if (rst || clear) begin
            rd_state_dbg <= RD_IDLE;
        end else begin
            rd_state_dbg <= rd_state_reg;
        end
    end

    // ---- External RAM write port: driven directly from DMA AXI-Stream ------
    assign mem_wr_addr  = dma_beat_addr;
    assign mem_wr_data  = dma_axis_tdata;
    assign mem_wr_strb  = dma_axis_tkeep;
    assign mem_wr_valid = dma_wr_beat;

    // ---- External RAM read port: driven by the read FSM + prefetch ----------
    //   Address always uses rd_read_beat_reg, which tracks the next beat to
    //   read. This ensures correct addressing even when consuming a beat and
    //   issuing a new prefetch in the same cycle.
    assign mem_rd_addr  = rd_read_addr;
    assign mem_rd_valid = (rd_state_reg == RD_TX_REQ) || (rd_state_reg == RD_RETX_REQ) ||
                          rd_prefetch_needed;

    // ---- TX AXI-Stream output port ------------------------------------------
    assign tx_axis_tdata  = rd_data_reg;
    assign tx_axis_tkeep  = {KEEP_WIDTH{1'b1}};
    assign tx_axis_tlast  = rd_last_beat;
    assign tx_axis_tvalid = (rd_state_reg == RD_TX_READ) && rd_data_valid_reg;
    assign tx_axis_tuser  = 1'b0;

    assign tx_pkt_done = tx_pkt_done_w;

    // ---- Retx AXI-Stream output port ----------------------------------------
    assign retx_axis_tdata  = rd_data_reg;
    assign retx_axis_tkeep  = {KEEP_WIDTH{1'b1}};
    assign retx_axis_tlast  = rd_last_beat;
    assign retx_axis_tvalid = (rd_state_reg == RD_RETX_READ) && rd_data_valid_reg;
    assign retx_axis_tuser  = 1'b0;

    assign retx_pkt_size = blk_size[retx_pending_idx_reg];

endmodule
