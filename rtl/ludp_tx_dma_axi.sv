module ludp_tx_dma_axi #(
    parameter int DATA_WIDTH        = 64,
    parameter int KEEP_WIDTH        = 8,
    parameter int MAX_PAYLOAD_BYTES = 9000,
    parameter int MEM_ADDR_W        = 32,
    parameter int MEM_SLOT_SIZE     = 16384,
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

    taxi_axi_if.wr_mst           m_axi_wr,
    taxi_axi_if.rd_mst           m_axi_rd
);

    localparam int MAX_BEATS   = (MAX_PAYLOAD_BYTES + KEEP_WIDTH - 1) / KEEP_WIDTH;
    localparam int BEAT_A_W    = $clog2(MAX_BEATS);
    localparam int BEAT_BYTE_W = $clog2(KEEP_WIDTH);
    localparam int BURST_LEN_W = $clog2(AXI_MAX_BURST_LEN + 1);

    // ============================================================
    // WRITE PATH: AXI-Stream -> AXI4 Burst Write
    // ============================================================
    typedef enum logic [2:0] {
        WR_IDLE,
        WR_AW,
        WR_DATA,
        WR_B,
        WR_RESP
    } wr_state_t;

    wr_state_t wr_state_reg;
    logic [MEM_ADDR_W-1:0] wr_addr_reg;
    logic [15:0]           wr_beats_sent_reg;
    logic [15:0]           wr_total_beats_reg;
    logic [BURST_LEN_W-1:0] wr_burst_count_reg;
    logic [BURST_LEN_W-1:0] wr_cur_burst_len_reg;

    wire [15:0] wr_beats_remaining = wr_total_beats_reg - wr_beats_sent_reg;

    wire [MEM_ADDR_W-1:0] wr_4k_boundary = {wr_addr_reg[MEM_ADDR_W-1:12], 12'b0} + 32'h1000;
    wire [MEM_ADDR_W-1:0] wr_beats_to_boundary = (wr_4k_boundary - wr_addr_reg) >> BEAT_BYTE_W;

    logic [7:0] wr_awlen_calc;

    always_comb begin
        if (wr_beats_remaining == '0) begin
            wr_awlen_calc = 8'h00;
        end else if (wr_beats_remaining >= AXI_MAX_BURST_LEN) begin
            if (wr_beats_to_boundary >= AXI_MAX_BURST_LEN)
                wr_awlen_calc = 8'(AXI_MAX_BURST_LEN - 1);
            else
                wr_awlen_calc = 8'(wr_beats_to_boundary - 1);
        end else begin
            if (wr_beats_to_boundary >= wr_beats_remaining)
                wr_awlen_calc = 8'(wr_beats_remaining - 1);
            else
                wr_awlen_calc = 8'(wr_beats_to_boundary - 1);
        end
    end

    wire [BURST_LEN_W-1:0] wr_burst_len = BURST_LEN_W'(wr_awlen_calc + 1);

    assign wr_axis_tready = (wr_state_reg == WR_DATA);

    always_ff @(posedge clk) begin
        if (rst) begin
            wr_state_reg       <= WR_IDLE;
            wr_addr_reg        <= '0;
            wr_beats_sent_reg  <= '0;
            wr_total_beats_reg <= '0;
            wr_burst_count_reg <= '0;
            wr_done            <= 1'b0;
        end else begin
            wr_done <= 1'b0;

            case (wr_state_reg)
                WR_IDLE: begin
                    if (wr_desc_enable && wr_axis_tvalid && !wr_done) begin
                        wr_addr_reg        <= wr_desc_base_addr;
                        wr_beats_sent_reg  <= '0;
                        wr_total_beats_reg <= wr_desc_total_beats;
                        wr_burst_count_reg <= '0;
                        wr_state_reg       <= WR_AW;
                        $display("[DMA_WR] %0t START addr=%08h total_beats=%0d", $time, wr_desc_base_addr, wr_desc_total_beats);
                    end
                end

                WR_AW: begin
                    if (m_axi_wr.awready) begin
                        wr_burst_count_reg   <= '0;
                        wr_cur_burst_len_reg <= wr_burst_len;
                        wr_state_reg         <= WR_DATA;
                        $display("[DMA_WR] %0t AW accepted awlen=%0d beats_rem=%0d beats_to_4k=%0d addr=%08h", 
                                 $time, wr_awlen_calc, wr_beats_remaining, wr_beats_to_boundary, wr_addr_reg);
                    end
                end

                WR_DATA: begin
                    if (wr_axis_tvalid && m_axi_wr.wready) begin
                        wr_burst_count_reg <= wr_burst_count_reg + 1'b1;
                        wr_beats_sent_reg  <= wr_beats_sent_reg + 1'b1;
                        wr_addr_reg        <= wr_addr_reg + (MEM_ADDR_W'(1) << BEAT_BYTE_W);

                        if (wr_burst_count_reg + 1 >= wr_cur_burst_len_reg) begin
                            if (wr_beats_sent_reg + 1 >= wr_total_beats_reg) begin
                                wr_state_reg <= WR_RESP;
                                $display("[DMA_WR] %0t Last beat sent -> WR_RESP", $time);
                            end else begin
                                wr_state_reg <= WR_B;
                                $display("[DMA_WR] %0t Burst done -> WR_B beats_sent=%0d", $time, wr_beats_sent_reg + 1);
                            end
                        end
                    end
                end

                WR_B: begin
                    if (m_axi_wr.bvalid) begin
                        wr_state_reg <= WR_AW;
                    end
                end

                WR_RESP: begin
                    if (m_axi_wr.bvalid) begin
                        wr_done      <= 1'b1;
                        wr_state_reg <= WR_IDLE;
                        $display("[DMA_WR] %0t DONE bresp=%0d", $time, m_axi_wr.bresp);
                    end
                end

                default: wr_state_reg <= WR_IDLE;
            endcase
        end
    end

    always_comb begin
        m_axi_wr.awid     = '0;
        m_axi_wr.awaddr   = wr_addr_reg;
        m_axi_wr.awlen    = wr_awlen_calc;
        m_axi_wr.awsize   = 3'($clog2(KEEP_WIDTH));
        m_axi_wr.awburst  = 2'b01;
        m_axi_wr.awlock   = 1'b0;
        m_axi_wr.awcache  = 4'b0011;
        m_axi_wr.awprot   = 3'b010;
        m_axi_wr.awqos    = 4'd0;
        m_axi_wr.awregion = 4'd0;
        m_axi_wr.awuser   = '0;
        m_axi_wr.awvalid  = (wr_state_reg == WR_AW);

        m_axi_wr.wdata  = wr_axis_tdata;
        m_axi_wr.wstrb  = wr_axis_tkeep;
        m_axi_wr.wlast  = (wr_burst_count_reg + 1 >= wr_cur_burst_len_reg);
        m_axi_wr.wuser  = '0;
        m_axi_wr.wvalid = (wr_state_reg == WR_DATA) && wr_axis_tvalid;

        m_axi_wr.bready = (wr_state_reg == WR_RESP) || (wr_state_reg == WR_B);
    end

    // ============================================================
    // READ PATH: AXI4 Burst Read -> AXI-Stream
    // ============================================================
    typedef enum logic [1:0] {
        RD_IDLE,
        RD_AR,
        RD_DATA
    } rd_state_t;

    rd_state_t rd_state_reg;
    logic [MEM_ADDR_W-1:0] rd_addr_reg;
    logic [15:0]           rd_total_beats_reg;
    logic [15:0]           rd_beat_count_reg;
    logic [15:0]           rd_burst_remaining_reg;
    logic                  rd_clear_pending_reg;

    logic [7:0] rd_arlen_calc;

    wire [MEM_ADDR_W-1:0] rd_4k_boundary = {rd_addr_reg[MEM_ADDR_W-1:12], 12'b0} + 32'h1000;
    wire [MEM_ADDR_W-1:0] rd_beats_to_boundary = (rd_4k_boundary - rd_addr_reg) >> BEAT_BYTE_W;

    always_comb begin
        if (rd_burst_remaining_reg == '0) begin
            rd_arlen_calc = 8'h00;
        end else if (rd_burst_remaining_reg >= AXI_MAX_BURST_LEN) begin
            if (rd_beats_to_boundary >= AXI_MAX_BURST_LEN)
                rd_arlen_calc = 8'(AXI_MAX_BURST_LEN - 1);
            else
                rd_arlen_calc = 8'(rd_beats_to_boundary - 1);
        end else begin
            if (rd_beats_to_boundary >= rd_burst_remaining_reg)
                rd_arlen_calc = 8'(rd_burst_remaining_reg - 1);
            else
                rd_arlen_calc = 8'(rd_beats_to_boundary - 1);
        end
    end

    assign rd_busy = (rd_state_reg != RD_IDLE);

    always_ff @(posedge clk) begin
        if (rst) begin
            rd_state_reg          <= RD_IDLE;
            rd_addr_reg           <= '0;
            rd_total_beats_reg    <= '0;
            rd_beat_count_reg     <= '0;
            rd_burst_remaining_reg <= '0;
            rd_done               <= 1'b0;
            rd_clear_pending_reg  <= 1'b0;
        end else begin
            rd_done <= 1'b0;

            if (clear && rd_state_reg != RD_IDLE) begin
                rd_clear_pending_reg <= 1'b1;
            end

            case (rd_state_reg)
                RD_IDLE: begin
                    if (rd_desc_req && !rd_done) begin
                        rd_addr_reg           <= rd_desc_base_addr;
                        rd_total_beats_reg    <= rd_desc_total_beats;
                        rd_beat_count_reg     <= '0;
                        rd_burst_remaining_reg <= rd_desc_total_beats;
                        rd_state_reg          <= RD_AR;
                        rd_clear_pending_reg  <= 1'b0;
                        $display("[DMA_RD] %0t START addr=%08h total_beats=%0d", $time, rd_desc_base_addr, rd_desc_total_beats);
                    end
                end

                RD_AR: begin
                    if (m_axi_rd.arready) begin
                        rd_state_reg <= RD_DATA;
                    end
                end

                RD_DATA: begin
                    if (m_axi_rd.rvalid && rd_axis_tready) begin
                        rd_beat_count_reg     <= rd_beat_count_reg + 1'b1;
                        rd_burst_remaining_reg <= rd_burst_remaining_reg - 1'b1;
                        rd_addr_reg           <= rd_addr_reg + (MEM_ADDR_W'(1) << BEAT_BYTE_W);

                        if (m_axi_rd.rlast) begin
                            if (rd_beat_count_reg + 1 >= rd_total_beats_reg) begin
                                if (rd_clear_pending_reg) begin
                                    rd_clear_pending_reg <= 1'b0;
                                    $display("[DMA_RD] %0t DONE (suppressed-clear) beats=%0d", $time, rd_beat_count_reg + 1);
                                end else begin
                                    rd_done <= 1'b1;
                                    $display("[DMA_RD] %0t DONE beats=%0d", $time, rd_beat_count_reg + 1);
                                end
                                rd_state_reg <= RD_IDLE;
                            end else begin
                                rd_state_reg <= RD_AR;
                            end
                        end
                    end
                end

                default: rd_state_reg <= RD_IDLE;
            endcase
        end
    end

    always_comb begin
        m_axi_rd.arid     = '0;
        m_axi_rd.araddr   = rd_addr_reg;
        m_axi_rd.arlen    = rd_arlen_calc;
        m_axi_rd.arsize   = 3'($clog2(KEEP_WIDTH));
        m_axi_rd.arburst  = 2'b01;
        m_axi_rd.arlock   = 1'b0;
        m_axi_rd.arcache  = 4'b0011;
        m_axi_rd.arprot   = 3'b010;
        m_axi_rd.arqos    = 4'd0;
        m_axi_rd.arregion = 4'd0;
        m_axi_rd.aruser   = '0;
        m_axi_rd.arvalid  = (rd_state_reg == RD_AR);

        m_axi_rd.rready = (rd_state_reg == RD_DATA) && rd_axis_tready;
    end

    assign rd_axis_tdata  = m_axi_rd.rdata;
    assign rd_axis_tkeep  = {KEEP_WIDTH{1'b1}};
    assign rd_axis_tvalid = (rd_state_reg == RD_DATA) && m_axi_rd.rvalid;
    assign rd_axis_tlast  = m_axi_rd.rvalid && m_axi_rd.rlast &&
                            (rd_beat_count_reg + 1 >= rd_total_beats_reg);
    assign rd_axis_tuser  = 1'b0;

endmodule
