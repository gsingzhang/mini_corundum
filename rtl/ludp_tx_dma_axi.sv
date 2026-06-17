module ludp_tx_dma_axi #(
    parameter int DATA_WIDTH        = 64,
    parameter int KEEP_WIDTH        = 8,
    parameter int MAX_PAYLOAD_BYTES = 9000,
    parameter int MEM_ADDR_W        = 32,
    parameter int MEM_SLOT_SIZE     = 16384,
    parameter int AXI_DATA_WIDTH    = 512,
    parameter int AXI_KEEP_WIDTH   = AXI_DATA_WIDTH / 8,
    parameter int RATIO             = AXI_DATA_WIDTH / DATA_WIDTH,
    parameter int RATIO_W          = $clog2(RATIO)
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        clear,

    input  wire [DATA_WIDTH-1:0] wr_axis_tdata,
    input  wire [KEEP_WIDTH-1:0] wr_axis_tkeep,
    input  wire                  wr_axis_tvalid,
    output logic                 wr_axis_tready,
    input  wire                  wr_axis_tlast,
    input  wire                  wr_axis_tuser,

    input  wire [MEM_ADDR_W-1:0] wr_desc_base_addr,
    input  wire [15:0]           wr_desc_total_beats,
    input  wire                  wr_desc_enable,
    output logic                 wr_done,

    output logic [DATA_WIDTH-1:0] rd_axis_tdata,
    output logic [KEEP_WIDTH-1:0] rd_axis_tkeep,
    output logic                  rd_axis_tvalid,
    input  wire                   rd_axis_tready,
    output logic                  rd_axis_tlast,
    output logic                  rd_axis_tuser,
    output logic                  rd_done,

    input  wire                  rd_desc_req,
    input  wire [MEM_ADDR_W-1:0] rd_desc_base_addr,
    input  wire [15:0]           rd_desc_total_beats,
    output logic                 rd_busy,

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
    input  wire                      dma_rd_axis_tlast
);

    localparam int MAX_BEATS = (MAX_PAYLOAD_BYTES + KEEP_WIDTH - 1) / KEEP_WIDTH;

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

    assign wr_axis_tready = (wr_state_reg == WR_PACK);

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
            wr_done                <= 1'b0;
        end else begin
            wr_done <= 1'b0;

            case (wr_state_reg)
                WR_IDLE: begin
                    if (wr_desc_enable && wr_axis_tvalid) begin
                        wr_addr_reg            <= wr_desc_base_addr;
                        wr_axis_beats_sent_reg <= '0;
                        wr_axis_total_beats_reg<= wr_desc_total_beats;
                        wr_pack_idx_reg        <= '0;
                        wr_pack_data_reg       <= '0;
                        wr_pack_strb_reg       <= '0;
                        wr_pack_last_reg       <= 1'b0;
                        wr_state_reg           <= WR_PACK;
                    end
                end

                WR_PACK: begin
                    if (wr_axis_tvalid) begin
                        wr_pack_data_reg[wr_pack_idx_reg * DATA_WIDTH +: DATA_WIDTH] <= wr_axis_tdata;
                        wr_pack_strb_reg[wr_pack_idx_reg * KEEP_WIDTH +: KEEP_WIDTH] <= wr_axis_tkeep;
                        wr_axis_beats_sent_reg <= wr_axis_beats_sent_reg + 1'b1;

                        if (wr_pack_full || wr_axis_tlast) begin
                            wr_pack_last_reg <= wr_axis_tlast;
                            if (wr_axis_tlast) begin
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
                            wr_done <= 1'b1;
                            wr_state_reg <= WR_IDLE;
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

    assign dma_wr_desc_addr  = wr_desc_base_addr;
    assign dma_wr_desc_len   = wr_desc_total_beats * KEEP_WIDTH;
    assign dma_wr_desc_valid = (wr_state_reg == WR_IDLE) && wr_desc_enable && wr_axis_tvalid;

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

    assign rd_busy = (rd_state_reg != RD_IDLE) || rd_unpack_valid_reg;

    always_ff @(posedge clk) begin
        if (rst) begin
            rd_state_reg            <= RD_IDLE;
            rd_addr_reg             <= '0;
            rd_axis_total_beats_reg <= '0;
            rd_axis_beat_count_reg  <= '0;
            rd_done                 <= 1'b0;
            rd_clear_pending_reg    <= 1'b0;
            rd_unpack_data_reg      <= '0;
            rd_unpack_strb_reg      <= '0;
            rd_unpack_idx_reg       <= '0;
            rd_unpack_valid_reg     <= 1'b0;
            rd_unpack_last_axi_reg  <= 1'b0;
        end else begin
            rd_done <= 1'b0;

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
                    if (rd_desc_req && !rd_unpack_valid_reg) begin
                        rd_addr_reg             <= rd_desc_base_addr;
                        rd_axis_total_beats_reg <= rd_desc_total_beats;
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
                    rd_done <= 1'b1;
                end
                rd_clear_pending_reg <= 1'b0;
            end
        end
    end

    assign dma_rd_desc_addr  = rd_desc_base_addr;
    assign dma_rd_desc_len   = rd_desc_total_beats * KEEP_WIDTH;
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

endmodule
