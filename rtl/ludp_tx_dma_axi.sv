module ludp_tx_dma_axi #(
    parameter int DATA_WIDTH        = 64,
    parameter int KEEP_WIDTH        = 8,
    parameter int MAX_PAYLOAD_BYTES = 9000,
    parameter int MEM_ADDR_W        = 32,
    parameter int MEM_SLOT_SIZE     = 16384,
    parameter int AXI_DATA_WIDTH    = 512,
    parameter int AXI_KEEP_WIDTH    = AXI_DATA_WIDTH / 8,
    parameter int AXI_MAX_BURST_LEN = 256
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

    // AXI4 Write Master
    output logic [3:0]           m_axi_awid,
    output logic [31:0]         m_axi_awaddr,
    output logic [7:0]          m_axi_awlen,
    output logic [2:0]          m_axi_awsize,
    output logic [1:0]          m_axi_awburst,
    output logic                m_axi_awlock,
    output logic [3:0]          m_axi_awcache,
    output logic [2:0]          m_axi_awprot,
    output logic [3:0]          m_axi_awqos,
    output logic                m_axi_awvalid,
    input  logic                m_axi_awready,
    output logic [511:0]        m_axi_wdata,
    output logic [63:0]         m_axi_wstrb,
    output logic                m_axi_wlast,
    output logic                m_axi_wvalid,
    input  logic                m_axi_wready,
    input  logic [3:0]          m_axi_bid,
    input  logic [1:0]          m_axi_bresp,
    input  logic                m_axi_bvalid,
    output logic                m_axi_bready,

    // AXI4 Read Master
    output logic [3:0]           m_axi_arid,
    output logic [31:0]         m_axi_araddr,
    output logic [7:0]          m_axi_arlen,
    output logic [2:0]          m_axi_arsize,
    output logic [1:0]          m_axi_arburst,
    output logic                m_axi_arlock,
    output logic [3:0]          m_axi_arcache,
    output logic [2:0]          m_axi_arprot,
    output logic [3:0]          m_axi_arqos,
    output logic                m_axi_arvalid,
    input  logic                m_axi_arready,
    input  logic [3:0]          m_axi_rid,
    input  logic [511:0]        m_axi_rdata,
    input  logic [1:0]          m_axi_rresp,
    input  logic                m_axi_rlast,
    input  logic                m_axi_rvalid,
    output logic                m_axi_rready
);

    localparam int RATIO        = AXI_DATA_WIDTH / DATA_WIDTH;
    localparam int RATIO_W      = $clog2(RATIO);
    localparam int MAX_BEATS    = (MAX_PAYLOAD_BYTES + KEEP_WIDTH - 1) / KEEP_WIDTH;
    localparam int AXI_BEAT_W   = $clog2(AXI_KEEP_WIDTH);
    localparam int BURST_LEN_W  = $clog2(AXI_MAX_BURST_LEN + 1);

    // ============================================================
    // WRITE PATH: 64-bit AXI-Stream -> Pack -> 512-bit AXI4
    // ============================================================
    typedef enum logic [2:0] {
        WR_IDLE,
        WR_PACK,
        WR_AW,
        WR_DATA,
        WR_B,
        WR_RESP
    } wr_state_t;

    wr_state_t wr_state_reg;
    logic [MEM_ADDR_W-1:0]      wr_addr_reg;
    logic [15:0]                wr_axis_beats_sent_reg;
    logic [15:0]                wr_axis_total_beats_reg;
    logic [BURST_LEN_W-1:0]    wr_burst_count_reg;
    logic [BURST_LEN_W-1:0]    wr_cur_burst_len_reg;
    logic [RATIO_W-1:0]        wr_pack_idx_reg;
    logic [AXI_DATA_WIDTH-1:0]  wr_pack_data_reg;
    logic [AXI_KEEP_WIDTH-1:0]  wr_pack_strb_reg;
    logic                       wr_pack_last_reg;

    wire [15:0] wr_axis_beats_remaining = wr_axis_total_beats_reg - wr_axis_beats_sent_reg;
    wire [15:0] wr_axi_beats_remaining  = (wr_axis_beats_remaining + RATIO - 1) / RATIO;

    wire [MEM_ADDR_W-1:0] wr_4k_boundary = {wr_addr_reg[MEM_ADDR_W-1:12], 12'b0} + 32'h1000;
    wire [MEM_ADDR_W-1:0] wr_beats_to_boundary = (wr_4k_boundary - wr_addr_reg) >> AXI_BEAT_W;

    logic [7:0] wr_awlen_calc;

    always_comb begin
        if (wr_axi_beats_remaining == '0) begin
            wr_awlen_calc = 8'h00;
        end else if (wr_axi_beats_remaining >= AXI_MAX_BURST_LEN) begin
            if (wr_beats_to_boundary >= AXI_MAX_BURST_LEN)
                wr_awlen_calc = 8'(AXI_MAX_BURST_LEN - 1);
            else
                wr_awlen_calc = 8'(wr_beats_to_boundary - 1);
        end else begin
            if (wr_beats_to_boundary >= wr_axi_beats_remaining)
                wr_awlen_calc = 8'(wr_axi_beats_remaining - 1);
            else
                wr_awlen_calc = 8'(wr_beats_to_boundary - 1);
        end
    end

    wire [BURST_LEN_W-1:0] wr_burst_len = BURST_LEN_W'(wr_awlen_calc + 1);

    wire wr_pack_full  = (wr_pack_idx_reg == RATIO_W'(RATIO - 1));
    wire wr_pack_flush = wr_axis_tlast && wr_axis_tvalid && wr_axis_tready;

    assign wr_axis_tready = (wr_state_reg == WR_PACK);

    always_ff @(posedge clk) begin
        if (rst) begin
            wr_state_reg           <= WR_IDLE;
            wr_addr_reg            <= '0;
            wr_axis_beats_sent_reg <= '0;
            wr_axis_total_beats_reg<= '0;
            wr_burst_count_reg     <= '0;
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
                        wr_burst_count_reg     <= '0;
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
                            wr_state_reg    <= WR_AW;
                        end else begin
                            wr_pack_idx_reg <= wr_pack_idx_reg + 1'b1;
                        end
                    end
                end

                WR_AW: begin
                    if (m_axi_awready) begin
                        wr_burst_count_reg   <= '0;
                        wr_cur_burst_len_reg <= wr_burst_len;
                        wr_state_reg         <= WR_DATA;
                    end
                end

                WR_DATA: begin
                    if (m_axi_wready) begin
                        wr_burst_count_reg <= wr_burst_count_reg + 1'b1;
                        wr_addr_reg        <= wr_addr_reg + (MEM_ADDR_W'(AXI_KEEP_WIDTH));

                        if (wr_burst_count_reg + 1 >= wr_cur_burst_len_reg) begin
                            if (wr_pack_last_reg) begin
                                wr_state_reg <= WR_RESP;
                            end else begin
                                wr_state_reg <= WR_B;
                            end
                        end else begin
                            wr_state_reg <= WR_PACK;
                            wr_pack_idx_reg  <= '0;
                            wr_pack_data_reg <= '0;
                            wr_pack_strb_reg <= '0;
                        end
                    end
                end

                WR_B: begin
                    if (m_axi_bvalid) begin
                        wr_state_reg <= WR_AW;
                    end
                end

                WR_RESP: begin
                    if (m_axi_bvalid) begin
                        wr_done      <= 1'b1;
                        wr_state_reg <= WR_IDLE;
                    end
                end

                default: wr_state_reg <= WR_IDLE;
            endcase
        end
    end

    always_comb begin
        m_axi_awid     = '0;
        m_axi_awaddr   = wr_addr_reg;
        m_axi_awlen    = wr_awlen_calc;
        m_axi_awsize   = 3'($clog2(AXI_KEEP_WIDTH));
        m_axi_awburst  = 2'b01;
        m_axi_awlock   = 1'b0;
        m_axi_awcache  = 4'b0011;
        m_axi_awprot   = 3'b010;
        m_axi_awqos    = 4'd0;
        m_axi_awvalid  = (wr_state_reg == WR_AW);

        m_axi_wdata  = wr_pack_data_reg;
        m_axi_wstrb  = wr_pack_strb_reg;
        m_axi_wlast  = (wr_burst_count_reg + 1 >= wr_cur_burst_len_reg);
        m_axi_wvalid = (wr_state_reg == WR_DATA);

        m_axi_bready = (wr_state_reg == WR_RESP) || (wr_state_reg == WR_B);
    end

    // ============================================================
    // READ PATH: 512-bit AXI4 -> Unpack -> 64-bit AXI-Stream
    // ============================================================
    typedef enum logic [1:0] {
        RD_IDLE,
        RD_AR,
        RD_DATA
    } rd_state_t;

    rd_state_t rd_state_reg;
    logic [MEM_ADDR_W-1:0]      rd_addr_reg;
    logic [15:0]                rd_axis_total_beats_reg;
    logic [15:0]                rd_axis_beat_count_reg;
    logic [15:0]                rd_axi_burst_remaining_reg;
    logic                       rd_clear_pending_reg;

    logic [AXI_DATA_WIDTH-1:0]  rd_unpack_data_reg;
    logic [AXI_KEEP_WIDTH-1:0]  rd_unpack_strb_reg;
    logic [RATIO_W-1:0]         rd_unpack_idx_reg;
    logic                       rd_unpack_valid_reg;
    logic                       rd_unpack_last_axi_reg;

    logic [7:0] rd_arlen_calc;

    wire [15:0] rd_axi_beats_remaining = (rd_axi_burst_remaining_reg + RATIO - 1) / RATIO;

    wire [MEM_ADDR_W-1:0] rd_4k_boundary = {rd_addr_reg[MEM_ADDR_W-1:12], 12'b0} + 32'h1000;
    wire [MEM_ADDR_W-1:0] rd_beats_to_boundary = (rd_4k_boundary - rd_addr_reg) >> AXI_BEAT_W;

    always_comb begin
        if (rd_axi_burst_remaining_reg == '0) begin
            rd_arlen_calc = 8'h00;
        end else if (rd_axi_beats_remaining >= AXI_MAX_BURST_LEN) begin
            if (rd_beats_to_boundary >= AXI_MAX_BURST_LEN)
                rd_arlen_calc = 8'(AXI_MAX_BURST_LEN - 1);
            else
                rd_arlen_calc = 8'(rd_beats_to_boundary - 1);
        end else begin
            if (rd_beats_to_boundary >= rd_axi_beats_remaining)
                rd_arlen_calc = 8'(rd_axi_beats_remaining - 1);
            else
                rd_arlen_calc = 8'(rd_beats_to_boundary - 1);
        end
    end

    assign rd_busy = (rd_state_reg != RD_IDLE) || rd_unpack_valid_reg;

    always_ff @(posedge clk) begin
        if (rst) begin
            rd_state_reg            <= RD_IDLE;
            rd_addr_reg             <= '0;
            rd_axis_total_beats_reg <= '0;
            rd_axis_beat_count_reg  <= '0;
            rd_axi_burst_remaining_reg <= '0;
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
                        rd_axi_burst_remaining_reg <= rd_desc_total_beats;
                        rd_state_reg            <= RD_AR;
                        rd_clear_pending_reg    <= 1'b0;
                    end
                end

                RD_AR: begin
                    if (m_axi_arready) begin
                        rd_state_reg <= RD_DATA;
                    end
                end

                RD_DATA: begin
                    if (m_axi_rvalid && (!rd_unpack_valid_reg || rd_axis_tready)) begin
                        rd_unpack_data_reg     <= m_axi_rdata;
                        rd_unpack_strb_reg     <= {AXI_KEEP_WIDTH{1'b1}};
                        rd_unpack_valid_reg    <= 1'b1;
                        rd_unpack_idx_reg      <= '0;
                        rd_unpack_last_axi_reg <= m_axi_rlast;

                        if (RATIO == 1) begin
                            rd_axi_burst_remaining_reg <= rd_axi_burst_remaining_reg - 1'b1;
                        end else begin
                            if (rd_axi_burst_remaining_reg >= RATIO)
                                rd_axi_burst_remaining_reg <= rd_axi_burst_remaining_reg - RATIO;
                            else
                                rd_axi_burst_remaining_reg <= '0;
                        end
                        rd_addr_reg <= rd_addr_reg + MEM_ADDR_W'(AXI_KEEP_WIDTH);

                        if (m_axi_rlast) begin
                            if (rd_clear_pending_reg) begin
                                rd_clear_pending_reg <= 1'b0;
                                rd_unpack_valid_reg  <= 1'b0;
                                rd_state_reg <= RD_IDLE;
                            end else if (rd_axi_burst_remaining_reg <= RATIO) begin
                                rd_state_reg <= RD_IDLE;
                            end else begin
                                rd_state_reg <= RD_AR;
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

    always_comb begin
        m_axi_arid     = '0;
        m_axi_araddr   = rd_addr_reg;
        m_axi_arlen    = rd_arlen_calc;
        m_axi_arsize   = 3'($clog2(AXI_KEEP_WIDTH));
        m_axi_arburst  = 2'b01;
        m_axi_arlock   = 1'b0;
        m_axi_arcache  = 4'b0011;
        m_axi_arprot   = 3'b010;
        m_axi_arqos    = 4'd0;
        m_axi_arvalid  = (rd_state_reg == RD_AR);

        m_axi_rready = (rd_state_reg == RD_DATA) && (!rd_unpack_valid_reg || rd_axis_tready);
    end

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
