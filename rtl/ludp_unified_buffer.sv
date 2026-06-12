module ludp_unified_buffer #(
    parameter int DATA_WIDTH        = 64,
    parameter int KEEP_WIDTH        = 8,
    parameter int MAX_PAYLOAD_BYTES = 9000,
    parameter int NUM_BLOCKS        = 3,
    parameter int MEM_ADDR_W        = 32,
    parameter logic [MEM_ADDR_W-1:0] MEM_BASE_ADDR = '0,
    parameter int MEM_SLOT_SIZE     = 16384
)(
    input  wire        clk,
    input  wire        rst,

    input  wire [DATA_WIDTH-1:0] dma_axis_tdata,
    input  wire [KEEP_WIDTH-1:0] dma_axis_tkeep,
    input  wire                  dma_axis_tvalid,
    output logic                 dma_axis_tready,
    input  wire                  dma_axis_tlast,
    input  wire                  dma_axis_tuser,
    input  wire [15:0]           dma_pkt_size,

    output logic        tx_pkt_ready,
    output logic [15:0] tx_pkt_size,
    input  wire         tx_pkt_start,
    input  wire [31:0]  tx_pkt_seq,
    output logic [DATA_WIDTH-1:0] tx_axis_tdata,
    output logic [KEEP_WIDTH-1:0] tx_axis_tkeep,
    output logic                  tx_axis_tvalid,
    input  wire                   tx_axis_tready,
    output logic                  tx_axis_tlast,
    output logic                  tx_axis_tuser,
    output logic        tx_pkt_done,

    input  wire        retx_req,
    input  wire [31:0] retx_seq,
    output logic       retx_found,
    output logic       retx_not_found,
    output logic [31:0] retx_seq_out,
    output logic [DATA_WIDTH-1:0] retx_axis_tdata,
    output logic [KEEP_WIDTH-1:0] retx_axis_tkeep,
    output logic                  retx_axis_tvalid,
    input  wire                   retx_axis_tready,
    output logic                  retx_axis_tlast,
    output logic                  retx_axis_tuser,
    output logic [15:0] retx_pkt_size,

    output logic [MEM_ADDR_W-1:0] mem_wr_addr,
    output logic [DATA_WIDTH-1:0] mem_wr_data,
    output logic [KEEP_WIDTH-1:0] mem_wr_strb,
    output logic                  mem_wr_valid,
    input  wire                   mem_wr_ready,
    output logic [MEM_ADDR_W-1:0] mem_rd_addr,
    output logic                  mem_rd_valid,
    input  wire                   mem_rd_ready,
    input  wire  [DATA_WIDTH-1:0] mem_rd_data,
    input  wire                   mem_rd_valid_in,

    input  wire        clear
);

    localparam int MAX_BEATS   = (MAX_PAYLOAD_BYTES + KEEP_WIDTH - 1) / KEEP_WIDTH;
    localparam int BLK_W       = $clog2(NUM_BLOCKS);
    localparam int BEAT_A_W    = $clog2(MAX_BEATS);
    localparam int BEAT_BYTE_W = $clog2(KEEP_WIDTH);

    localparam logic [1:0] BLK_EMPTY = 2'd0;
    localparam logic [1:0] BLK_READY = 2'd1;
    localparam logic [1:0] BLK_SENT  = 2'd2;

    logic [15:0] blk_size  [NUM_BLOCKS-1:0];
    logic [31:0] blk_seq   [NUM_BLOCKS-1:0];
    logic [1:0]  blk_state [NUM_BLOCKS-1:0];

    logic [BLK_W-1:0]   dma_wr_idx_reg;
    logic [BEAT_A_W-1:0] dma_beat_idx_reg;

    logic [BLK_W-1:0]   tx_rd_idx_reg;

    typedef enum logic [2:0] {
        RD_IDLE,
        RD_TX_REQ,
        RD_TX_WAIT,
        RD_TX_READ,
        RD_RETX_REQ,
        RD_RETX_WAIT,
        RD_RETX_READ
    } rd_state_t;

    rd_state_t rd_state_reg;
    logic [BLK_W-1:0]   rd_blk_idx_reg;
    logic [BEAT_A_W-1:0] rd_beat_idx_reg;
    logic [15:0]         rd_total_beats_reg;
    logic [DATA_WIDTH-1:0] rd_data_reg;
    logic                  rd_data_valid_reg;

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

    logic              retx_pending_reg;
    logic [BLK_W-1:0]  retx_pending_idx_reg;
    logic [31:0]       retx_pending_seq_reg;

    assign retx_found     = retx_pending_reg;
    assign retx_not_found = retx_req_pulse && !retx_lookup_found && !retx_pending_reg;
    assign retx_seq_out   = retx_pending_seq_reg;

    assign tx_pkt_ready = (blk_state[tx_rd_idx_reg] == BLK_READY);
    assign tx_pkt_size  = blk_size[tx_rd_idx_reg];

    function automatic [BLK_W-1:0] blk_next;
        input [BLK_W-1:0] idx;
        if (idx == NUM_BLOCKS[BLK_W-1:0] - 1)
            blk_next = '0;
        else
            blk_next = idx + 1'b1;
    endfunction

    wire [MEM_ADDR_W-1:0] dma_base_addr = MEM_BASE_ADDR + MEM_ADDR_W'(dma_wr_idx_reg) * MEM_ADDR_W'(MEM_SLOT_SIZE);
    wire [MEM_ADDR_W-1:0] dma_beat_addr = dma_base_addr + (MEM_ADDR_W'(dma_beat_idx_reg) << BEAT_BYTE_W);

    wire [MEM_ADDR_W-1:0] rd_base_addr = MEM_BASE_ADDR + MEM_ADDR_W'(rd_blk_idx_reg) * MEM_ADDR_W'(MEM_SLOT_SIZE);
    wire [MEM_ADDR_W-1:0] rd_beat_addr = rd_base_addr + (MEM_ADDR_W'(rd_beat_idx_reg) << BEAT_BYTE_W);

    assign dma_axis_tready = (blk_state[dma_wr_idx_reg] == BLK_EMPTY);

    wire dma_wr_beat = dma_axis_tvalid && dma_axis_tready;

    wire tx_pkt_done_w = (rd_state_reg == RD_TX_READ) && rd_data_valid_reg &&
                         tx_axis_tvalid && tx_axis_tready &&
                         (rd_beat_idx_reg + 1 >= rd_total_beats_reg);

    always_ff @(posedge clk) begin
        if (rst || clear) begin
            dma_wr_idx_reg     <= '0;
            dma_beat_idx_reg   <= '0;
            tx_rd_idx_reg      <= '0;
            rd_state_reg       <= RD_IDLE;
            rd_blk_idx_reg     <= '0;
            rd_beat_idx_reg    <= '0;
            rd_total_beats_reg <= '0;
            rd_data_valid_reg  <= 1'b0;
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

            // --- TX seq latch ---
            if (tx_pkt_start && (blk_state[tx_rd_idx_reg] == BLK_READY)) begin
                blk_seq[tx_rd_idx_reg] <= tx_pkt_seq;
            end

            // --- TX done: mark block SENT, advance tx_rd_idx, recycle old SENT blocks ---
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

            // --- Read FSM ---
            case (rd_state_reg)
                RD_IDLE: begin
                    rd_beat_idx_reg   <= '0;
                    rd_data_valid_reg <= 1'b0;
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
                        rd_data_reg        <= mem_rd_data;
                        rd_data_valid_reg  <= 1'b1;
                        rd_state_reg       <= RD_TX_READ;
                    end
                end

                RD_TX_READ: begin
                    if (tx_axis_tvalid && tx_axis_tready) begin
                        rd_data_valid_reg <= 1'b0;
                        if (rd_beat_idx_reg + 1 >= rd_total_beats_reg) begin
                            rd_state_reg <= RD_IDLE;
                        end else begin
                            rd_beat_idx_reg <= rd_beat_idx_reg + 1'b1;
                            rd_state_reg    <= RD_TX_REQ;
                        end
                    end else if (mem_rd_valid_in && !rd_data_valid_reg) begin
                        rd_data_reg       <= mem_rd_data;
                        rd_data_valid_reg <= 1'b1;
                    end
                end

                RD_RETX_REQ: begin
                    if (mem_rd_ready) begin
                        rd_state_reg <= RD_RETX_WAIT;
                    end
                end

                RD_RETX_WAIT: begin
                    if (mem_rd_valid_in) begin
                        rd_data_reg        <= mem_rd_data;
                        rd_data_valid_reg  <= 1'b1;
                        rd_state_reg       <= RD_RETX_READ;
                    end
                end

                RD_RETX_READ: begin
                    if (retx_axis_tvalid && retx_axis_tready) begin
                        rd_data_valid_reg <= 1'b0;
                        if (rd_beat_idx_reg + 1 >= rd_total_beats_reg) begin
                            rd_state_reg <= RD_IDLE;
                        end else begin
                            rd_beat_idx_reg <= rd_beat_idx_reg + 1'b1;
                            rd_state_reg    <= RD_RETX_REQ;
                        end
                    end else if (mem_rd_valid_in && !rd_data_valid_reg) begin
                        rd_data_reg       <= mem_rd_data;
                        rd_data_valid_reg <= 1'b1;
                    end
                end

                default: rd_state_reg <= RD_IDLE;
            endcase
        end
    end

    assign mem_wr_addr  = dma_beat_addr;
    assign mem_wr_data  = dma_axis_tdata;
    assign mem_wr_strb  = dma_axis_tkeep;
    assign mem_wr_valid = dma_wr_beat;

    assign mem_rd_addr  = rd_beat_addr;
    assign mem_rd_valid = (rd_state_reg == RD_TX_REQ) || (rd_state_reg == RD_RETX_REQ);

    assign tx_axis_tdata  = rd_data_reg;
    assign tx_axis_tkeep  = {KEEP_WIDTH{1'b1}};
    assign tx_axis_tlast  = (rd_beat_idx_reg + 1 >= rd_total_beats_reg);
    assign tx_axis_tvalid = (rd_state_reg == RD_TX_READ) && rd_data_valid_reg;
    assign tx_axis_tuser  = 1'b0;

    assign tx_pkt_done = tx_pkt_done_w;

    assign retx_axis_tdata  = rd_data_reg;
    assign retx_axis_tkeep  = {KEEP_WIDTH{1'b1}};
    assign retx_axis_tlast  = (rd_beat_idx_reg + 1 >= rd_total_beats_reg);
    assign retx_axis_tvalid = (rd_state_reg == RD_RETX_READ) && rd_data_valid_reg;
    assign retx_axis_tuser  = 1'b0;

    assign retx_pkt_size = blk_size[retx_pending_idx_reg];

endmodule
