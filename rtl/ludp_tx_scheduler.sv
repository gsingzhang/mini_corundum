module ludp_tx_scheduler #(
    parameter int NUM_BLOCKS        = 3,
    parameter int KEEP_WIDTH        = 8,
    parameter int DATA_WIDTH        = 64,
    parameter int MEM_ADDR_W        = 32,
    parameter logic [MEM_ADDR_W-1:0] MEM_BASE_ADDR = '0,
    parameter int MEM_SLOT_SIZE     = 16384,
    parameter int AXI_DATA_WIDTH    = 512,
    parameter int AXI_KEEP_WIDTH   = AXI_DATA_WIDTH / 8,
    parameter int MAX_PAYLOAD_BYTES = 9000,
    parameter int RATIO             = AXI_DATA_WIDTH / DATA_WIDTH,
    parameter int RATIO_W          = $clog2(RATIO)
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        clear,

    input  wire [DATA_WIDTH-1:0] dma_axis_tdata,
    input  wire [KEEP_WIDTH-1:0] dma_axis_tkeep,
    input  wire                  dma_axis_tvalid,
    output logic                 dma_axis_tready,
    input  wire                  dma_axis_tlast,
    input  wire                  dma_axis_tuser,
    input  wire [15:0]           dma_pkt_size,

    output logic        tx_pkt_ready,
    output logic        sch_ready,
    input  wire         tx_pkt_start,
    input  wire [31:0]  tx_pkt_seq,
    output logic        tx_pkt_done,

    output logic        dma_wr_enable,

    input  wire        retx_req,
    input  wire [31:0] retx_seq,
    output logic       retx_found,

    output logic [15:0] rd_pkt_size,
    output logic [31:0] rd_pkt_seq,

    output logic [DATA_WIDTH-1:0] rd_axis_tdata,
    output logic [KEEP_WIDTH-1:0] rd_axis_tkeep,
    output logic                  rd_axis_tvalid,
    input  wire                   rd_axis_tready,
    output logic                  rd_axis_tlast,
    output logic                  rd_axis_tuser,

    output logic [MEM_ADDR_W-1:0] dma_wr_desc_addr,
    output logic [15:0]           dma_wr_desc_len,
    output logic                  dma_wr_desc_valid,
    input  wire                   dma_wr_desc_ready,

    output logic [AXI_DATA_WIDTH-1:0] dma_wr_axis_tdata,
    output logic [AXI_KEEP_WIDTH-1:0] dma_wr_axis_tkeep,
    output logic                      dma_wr_axis_tvalid,
    input  wire                       dma_wr_axis_tready,
    output logic                      dma_wr_axis_tlast,

    output logic [MEM_ADDR_W-1:0] dma_rd_desc_addr,
    output logic [15:0]           dma_rd_desc_len,
    output logic                  dma_rd_desc_valid,
    input  wire                   dma_rd_desc_ready,

    input  wire [AXI_DATA_WIDTH-1:0] dma_rd_axis_tdata,
    input  wire [AXI_KEEP_WIDTH-1:0] dma_rd_axis_tkeep,
    input  wire                      dma_rd_axis_tvalid,
    output logic                     dma_rd_axis_tready,
    input  wire                      dma_rd_axis_tlast,

    output logic        rd_is_retx
);

    localparam int BLK_W  = $clog2(NUM_BLOCKS);
    localparam int KEEP_W = KEEP_WIDTH;

    localparam logic [1:0] BLK_EMPTY = 2'd0;
    localparam logic [1:0] BLK_READY = 2'd1;
    localparam logic [1:0] BLK_SENT  = 2'd2;

    logic [15:0] blk_size  [NUM_BLOCKS-1:0];
    logic [31:0] blk_seq   [NUM_BLOCKS-1:0];
    logic [1:0]  blk_state [NUM_BLOCKS-1:0];

    logic [BLK_W-1:0] dma_wr_idx_reg;
    logic [BLK_W-1:0] tx_rd_idx_reg;
    logic [BLK_W-1:0] rd_blk_idx_reg;

    logic              retx_pending_reg;
    logic [BLK_W-1:0]  retx_pending_idx_reg;

    logic retx_req_d;
    always_ff @(posedge clk) begin
        if (rst || clear)
            retx_req_d <= 1'b0;
        else
            retx_req_d <= retx_req;
    end
    wire retx_req_pulse = retx_req && !retx_req_d;

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

    assign tx_pkt_ready = (blk_state[tx_rd_idx_reg] == BLK_READY);

    assign dma_wr_enable = (blk_state[dma_wr_idx_reg] == BLK_EMPTY);

    wire [BLK_W-1:0] sch_target_blk = retx_pending_reg ? retx_pending_idx_reg :
                                                     tx_rd_idx_reg;
    assign rd_pkt_size = blk_size[sch_target_blk];
    assign rd_pkt_seq  = retx_pending_reg ? blk_seq[retx_pending_idx_reg] : tx_pkt_seq;

    function automatic [BLK_W-1:0] blk_next;
        input [BLK_W-1:0] idx;
        if (idx == NUM_BLOCKS[BLK_W-1:0] - 1)
            blk_next = '0;
        else
            blk_next = idx + 1'b1;
    endfunction

    // ============================================================
    // Scheduling signals (used by both read path and FSM)
    // ============================================================
    logic sch_dma_rd_req;
    logic [MEM_ADDR_W-1:0] sch_dma_rd_base_addr;
    logic [15:0]           sch_dma_rd_total_beats;

    // ============================================================
    // WRITE PATH: 64-bit AXI-Stream -> Pack -> 512-bit AXI-Stream
    // ============================================================
    typedef enum logic [1:0] {
        WR_IDLE,
        WR_PACK,
        WR_FINISH
    } wr_state_t;

    wr_state_t wr_state_reg;
    logic [MEM_ADDR_W-1:0]      wr_addr_reg;
    logic [15:0]                wr_axis_beats_sent_reg;
    logic [15:0]                wr_axis_total_beats_reg;
    logic [RATIO_W-1:0]        wr_pack_idx_reg;
    logic [AXI_DATA_WIDTH-1:0]  wr_pack_data_reg;
    logic [AXI_KEEP_WIDTH-1:0]  wr_pack_strb_reg;
    logic                       wr_pack_last_reg;

    wire wr_pack_full  = (wr_pack_idx_reg == RATIO_W'(RATIO - 1));

    assign dma_axis_tready = (wr_state_reg == WR_PACK);

    logic wr_done_pulse;

    wire [MEM_ADDR_W-1:0] wr_cur_base_addr = MEM_BASE_ADDR + MEM_ADDR_W'(dma_wr_idx_reg) * MEM_ADDR_W'(MEM_SLOT_SIZE);
    wire [15:0] wr_cur_total_beats = (dma_pkt_size + KEEP_WIDTH - 1) / KEEP_WIDTH;

    always_ff @(posedge clk) begin
        if (rst) begin
            wr_state_reg           <= WR_IDLE;
            wr_addr_reg            <= '0;
            wr_axis_beats_sent_reg <= '0;
            wr_axis_total_beats_reg<= '0;
            wr_pack_idx_reg        <= '0;
            wr_pack_data_reg       <= '0;
            wr_pack_strb_reg       <= '0;
            wr_pack_last_reg       <= 1'b0;
            wr_done_pulse          <= 1'b0;
        end else begin
            wr_done_pulse <= 1'b0;

            case (wr_state_reg)
                WR_IDLE: begin
                    if (dma_axis_tvalid && (blk_state[dma_wr_idx_reg] == BLK_EMPTY)) begin
                        wr_addr_reg            <= wr_cur_base_addr;
                        wr_axis_beats_sent_reg <= '0;
                        wr_axis_total_beats_reg<= wr_cur_total_beats;
                        wr_pack_idx_reg        <= '0;
                        wr_pack_data_reg       <= '0;
                        wr_pack_strb_reg       <= '0;
                        wr_pack_last_reg       <= 1'b0;
                        wr_state_reg           <= WR_PACK;
                    end
                end

                WR_PACK: begin
                    if (dma_axis_tvalid) begin
                        wr_pack_data_reg[wr_pack_idx_reg * DATA_WIDTH +: DATA_WIDTH] <= dma_axis_tdata;
                        wr_pack_strb_reg[wr_pack_idx_reg * KEEP_WIDTH +: KEEP_WIDTH] <= dma_axis_tkeep;
                        wr_axis_beats_sent_reg <= wr_axis_beats_sent_reg + 1'b1;

                        if (wr_pack_full || dma_axis_tlast) begin
                            wr_pack_last_reg <= dma_axis_tlast;
                            if (dma_axis_tlast) begin
                                for (int i = RATIO - 1; i > 0; i--) begin
                                    if (i > wr_pack_idx_reg) begin
                                        wr_pack_strb_reg[i * KEEP_WIDTH +: KEEP_WIDTH] <= '0;
                                        wr_pack_data_reg[i * DATA_WIDTH +: DATA_WIDTH] <= '0;
                                    end
                                end
                            end
                            wr_pack_idx_reg <= '0;
                            wr_state_reg    <= WR_FINISH;
                        end else begin
                            wr_pack_idx_reg <= wr_pack_idx_reg + 1'b1;
                        end
                    end
                end

                WR_FINISH: begin
                    if (dma_wr_axis_tready) begin
                        if (wr_pack_last_reg) begin
                            wr_done_pulse <= 1'b1;
                            wr_state_reg  <= WR_IDLE;
                        end else begin
                            wr_pack_data_reg <= '0;
                            wr_pack_strb_reg <= '0;
                            wr_state_reg <= WR_PACK;
                        end
                    end
                end

                default: wr_state_reg <= WR_IDLE;
            endcase
        end
    end

    assign dma_wr_desc_addr  = wr_cur_base_addr;
    assign dma_wr_desc_len   = wr_cur_total_beats * KEEP_WIDTH;
    assign dma_wr_desc_valid = (wr_state_reg == WR_IDLE) && dma_axis_tvalid && (blk_state[dma_wr_idx_reg] == BLK_EMPTY);

    assign dma_wr_axis_tdata  = wr_pack_data_reg;
    assign dma_wr_axis_tkeep  = wr_pack_strb_reg;
    assign dma_wr_axis_tvalid = (wr_state_reg == WR_FINISH);
    assign dma_wr_axis_tlast  = (wr_state_reg == WR_FINISH) && wr_pack_last_reg;

    // ============================================================
    // READ PATH: 512-bit AXI-Stream -> Unpack -> 64-bit AXI-Stream
    // ============================================================
    typedef enum logic [1:0] {
        RD_IDLE,
        RD_DESC,
        RD_DATA
    } rd_state_t;

    rd_state_t rd_state_reg;
    logic [MEM_ADDR_W-1:0]      rd_addr_reg;
    logic [15:0]                rd_axis_total_beats_reg;
    logic [15:0]                rd_axis_beat_count_reg;
    logic                       rd_clear_pending_reg;

    logic [AXI_DATA_WIDTH-1:0]  rd_unpack_data_reg;
    logic [AXI_KEEP_WIDTH-1:0]  rd_unpack_strb_reg;
    logic [RATIO_W-1:0]         rd_unpack_idx_reg;
    logic                       rd_unpack_valid_reg;
    logic                       rd_unpack_last_axi_reg;

    logic rd_done_pulse;

    wire rd_busy = (rd_state_reg != RD_IDLE) || rd_unpack_valid_reg;

    always_ff @(posedge clk) begin
        if (rst) begin
            rd_state_reg            <= RD_IDLE;
            rd_addr_reg             <= '0;
            rd_axis_total_beats_reg <= '0;
            rd_axis_beat_count_reg  <= '0;
            rd_done_pulse           <= 1'b0;
            rd_clear_pending_reg    <= 1'b0;
            rd_unpack_data_reg      <= '0;
            rd_unpack_strb_reg      <= '0;
            rd_unpack_idx_reg       <= '0;
            rd_unpack_valid_reg     <= 1'b0;
            rd_unpack_last_axi_reg  <= 1'b0;
        end else begin
            rd_done_pulse <= 1'b0;

            if (clear && rd_state_reg != RD_IDLE) begin
                rd_clear_pending_reg <= 1'b1;
            end

            if (rd_unpack_valid_reg && rd_axis_tready) begin
                if (rd_unpack_idx_reg == RATIO_W'(RATIO - 1)) begin
                    rd_unpack_valid_reg <= 1'b0;
                    rd_unpack_idx_reg   <= '0;
                end else begin
                    rd_unpack_idx_reg <= rd_unpack_idx_reg + 1'b1;
                end
                rd_axis_beat_count_reg <= rd_axis_beat_count_reg + 1'b1;
            end

            case (rd_state_reg)
                RD_IDLE: begin
                    if (sch_dma_rd_req && !rd_unpack_valid_reg) begin
                        rd_addr_reg             <= sch_dma_rd_base_addr;
                        rd_axis_total_beats_reg <= sch_dma_rd_total_beats;
                        rd_axis_beat_count_reg  <= '0;
                        rd_clear_pending_reg    <= 1'b0;
                        rd_state_reg            <= RD_DESC;
                    end
                end

                RD_DESC: begin
                    if (dma_rd_desc_ready) begin
                        rd_state_reg <= RD_DATA;
                    end
                end

                RD_DATA: begin
                    if (dma_rd_axis_tvalid && (!rd_unpack_valid_reg || rd_axis_tready)) begin
                        rd_unpack_data_reg     <= dma_rd_axis_tdata;
                        rd_unpack_strb_reg     <= {AXI_KEEP_WIDTH{1'b1}};
                        rd_unpack_valid_reg    <= 1'b1;
                        rd_unpack_idx_reg      <= '0;
                        rd_unpack_last_axi_reg <= dma_rd_axis_tlast;

                        if (dma_rd_axis_tlast) begin
                            if (rd_clear_pending_reg) begin
                                rd_clear_pending_reg <= 1'b0;
                                rd_unpack_valid_reg  <= 1'b0;
                                rd_state_reg <= RD_IDLE;
                            end else begin
                                rd_state_reg <= RD_IDLE;
                            end
                        end
                    end
                end

                default: rd_state_reg <= RD_IDLE;
            endcase

            if (rd_unpack_valid_reg && rd_axis_tready &&
                rd_unpack_idx_reg == RATIO_W'(RATIO - 1) &&
                rd_axis_beat_count_reg + 1 >= rd_axis_total_beats_reg) begin
                if (!rd_clear_pending_reg) begin
                    rd_done_pulse <= 1'b1;
                end
                rd_clear_pending_reg <= 1'b0;
            end
        end
    end

    assign dma_rd_desc_addr  = sch_dma_rd_base_addr;
    assign dma_rd_desc_len   = sch_dma_rd_total_beats * KEEP_WIDTH;
    assign dma_rd_desc_valid = (rd_state_reg == RD_DESC);

    assign dma_rd_axis_tready = (rd_state_reg == RD_DATA) && (!rd_unpack_valid_reg || rd_axis_tready);

    assign rd_axis_tdata  = rd_unpack_valid_reg ?
                            rd_unpack_data_reg[rd_unpack_idx_reg * DATA_WIDTH +: DATA_WIDTH] : '0;
    assign rd_axis_tkeep  = rd_unpack_valid_reg ?
                            rd_unpack_strb_reg[rd_unpack_idx_reg * KEEP_WIDTH +: KEEP_WIDTH] : '0;
    assign rd_axis_tvalid = rd_unpack_valid_reg;
    assign rd_axis_tlast  = rd_unpack_valid_reg &&
                            (rd_unpack_idx_reg == RATIO_W'(RATIO - 1)) &&
                            rd_unpack_last_axi_reg &&
                            (rd_axis_beat_count_reg + 1 >= rd_axis_total_beats_reg);
    assign rd_axis_tuser  = 1'b0;

    // ============================================================
    // SCHEDULING FSM
    // ============================================================
    typedef enum logic [1:0] {
        SCH_IDLE,
        SCH_READING
    } sch_state_t;

    sch_state_t sch_state_reg;
    logic       sch_is_retx_reg;

    wire sch_can_issue = !rd_busy;

    assign sch_ready = (sch_state_reg == SCH_IDLE) && sch_can_issue;

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

            if (wr_done_pulse) begin
                blk_size[dma_wr_idx_reg]  <= dma_pkt_size;
                blk_state[dma_wr_idx_reg] <= BLK_READY;
                dma_wr_idx_reg <= blk_next(dma_wr_idx_reg);
            end

            if (tx_pkt_start && (blk_state[tx_rd_idx_reg] == BLK_READY)) begin
                blk_seq[tx_rd_idx_reg] <= tx_pkt_seq;
            end

            if (rd_done_pulse) begin
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
                    if (rd_done_pulse)
                        sch_state_reg <= SCH_IDLE;
                end

                default: sch_state_reg <= SCH_IDLE;
            endcase
        end
    end

    assign sch_dma_rd_req = (sch_state_reg == SCH_IDLE) && (
                        (retx_pending_reg && sch_can_issue) ||
                        (tx_pkt_start && (blk_state[tx_rd_idx_reg] == BLK_READY) && sch_can_issue));

    assign sch_dma_rd_base_addr = MEM_BASE_ADDR + MEM_ADDR_W'(sch_target_blk) * MEM_ADDR_W'(MEM_SLOT_SIZE);

    assign sch_dma_rd_total_beats = (blk_size[sch_target_blk] + KEEP_W - 1) / KEEP_W;

    assign rd_is_retx = sch_is_retx_reg;

    assign tx_pkt_done = rd_done_pulse && !sch_is_retx_reg;

    always @(posedge clk) begin
        if (wr_done_pulse)
            $display("[SCHED] %0t WR done blk=%0d -> READY wr_idx=%0d", $time, dma_wr_idx_reg, blk_next(dma_wr_idx_reg));
        if (rd_done_pulse)
            $display("[SCHED] %0t RD done blk=%0d is_retx=%0b blk_state=[%0d,%0d,%0d] tx_rd_idx=%0d",
                     $time, rd_blk_idx_reg, sch_is_retx_reg,
                     blk_state[0], blk_state[1], blk_state[2], tx_rd_idx_reg);
        if (sch_dma_rd_req)
            $display("[SCHED] %0t RD req blk=%0d addr=%08h beats=%0d busy=%0b",
                     $time, sch_target_blk, sch_dma_rd_base_addr, sch_dma_rd_total_beats, rd_busy);
        if (tx_pkt_start && !sch_dma_rd_req)
            $display("[SCHED] %0t TX start but NO rd_req! sch_state=%0d can_issue=%0b rd_busy=%0b blk_rdy=%0b",
                     $time, sch_state_reg, sch_can_issue, rd_busy, (blk_state[tx_rd_idx_reg] == BLK_READY));
    end

endmodule
