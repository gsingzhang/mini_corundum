module ludp_dma_wrapper #(
    parameter int AXI_DATA_WIDTH = 512,
    parameter int AXI_ADDR_WIDTH = 32,
    parameter int AXI_ID_WIDTH   = 4,
    parameter int AXI_MAX_BURST_LEN = 16,
    parameter int AXIS_DATA_WIDTH = 512,
    parameter int LEN_WIDTH      = 16,
    parameter int TAG_WIDTH      = 4,
    parameter int RAM_SEL_WIDTH  = 1,
    parameter int RAM_ADDR_WIDTH = 16,
    parameter int RAM_SIZE       = 65536,
    parameter int RAM_SEG_COUNT  = 2,
    parameter int RAM_SEG_DATA_WIDTH = AXI_DATA_WIDTH,
    parameter int RAM_SEG_BE_WIDTH   = RAM_SEG_DATA_WIDTH / 8,
    parameter int RAM_SEG_ADDR_WIDTH = $clog2(RAM_SIZE / (RAM_SEG_COUNT * RAM_SEG_BE_WIDTH))
)(
    input  wire        s_clk,
    input  wire        s_rst,
    input  wire        m_clk,
    input  wire        m_rst,

    input  wire [RAM_ADDR_WIDTH-1:0] sink_desc_ram_addr,
    input  wire [LEN_WIDTH-1:0]      sink_desc_len,
    input  wire [TAG_WIDTH-1:0]       sink_desc_tag,
    input  wire                       sink_desc_valid,
    output wire                       sink_desc_ready,

    output wire [LEN_WIDTH-1:0]       sink_status_len,
    output wire [TAG_WIDTH-1:0]       sink_status_tag,
    output wire                       sink_status_valid,

    input  wire [AXIS_DATA_WIDTH-1:0] sink_axis_tdata,
    input  wire [(AXIS_DATA_WIDTH/8)-1:0] sink_axis_tkeep,
    input  wire                       sink_axis_tvalid,
    output wire                       sink_axis_tready,
    input  wire                       sink_axis_tlast,

    taxi_axis_if   wr_dma_desc_if,
    taxi_axis_if   wr_dma_status_if,

    taxi_axis_if   rd_desc_if,

    output wire [AXI_DATA_WIDTH-1:0] rd_axis_tdata_out,
    output wire [(AXI_DATA_WIDTH/8)-1:0] rd_axis_tkeep_out,
    output wire                       rd_axis_tvalid_out,
    input  wire                       rd_axis_tready_out,
    output wire                       rd_axis_tlast_out,

    output wire [AXI_ID_WIDTH-1:0]    m_axi_awid,
    output wire [AXI_ADDR_WIDTH-1:0]  m_axi_awaddr,
    output wire [7:0]                 m_axi_awlen,
    output wire [2:0]                 m_axi_awsize,
    output wire [1:0]                 m_axi_awburst,
    output wire                       m_axi_awlock,
    output wire [3:0]                 m_axi_awcache,
    output wire [2:0]                 m_axi_awprot,
    output wire                       m_axi_awvalid,
    input  wire                       m_axi_awready,
    output wire [AXI_DATA_WIDTH-1:0]  m_axi_wdata,
    output wire [(AXI_DATA_WIDTH/8)-1:0] m_axi_wstrb,
    output wire                       m_axi_wlast,
    output wire                       m_axi_wvalid,
    input  wire                       m_axi_wready,
    input  wire [AXI_ID_WIDTH-1:0]    m_axi_bid,
    input  wire [1:0]                 m_axi_bresp,
    input  wire                       m_axi_bvalid,
    output wire                       m_axi_bready,

    output wire [AXI_ID_WIDTH-1:0]    m_axi_arid,
    output wire [AXI_ADDR_WIDTH-1:0]  m_axi_araddr,
    output wire [7:0]                 m_axi_arlen,
    output wire [2:0]                 m_axi_arsize,
    output wire [1:0]                 m_axi_arburst,
    output wire                       m_axi_arlock,
    output wire [3:0]                 m_axi_arcache,
    output wire [2:0]                 m_axi_arprot,
    output wire                       m_axi_arvalid,
    input  wire                       m_axi_arready,
    input  wire [AXI_ID_WIDTH-1:0]    m_axi_rid,
    input  wire [AXI_DATA_WIDTH-1:0]  m_axi_rdata,
    input  wire [1:0]                 m_axi_rresp,
    input  wire                       m_axi_rlast,
    input  wire                       m_axi_rvalid,
    output wire                       m_axi_rready
);

    localparam int AXIS_KEEP_WIDTH = AXIS_DATA_WIDTH / 8;
    localparam int WR_DMA_DESC_W = AXI_ADDR_WIDTH + RAM_SEL_WIDTH + RAM_ADDR_WIDTH + LEN_WIDTH + TAG_WIDTH;
    localparam int WR_DMA_STATUS_W = TAG_WIDTH + 4;
    localparam int RD_DESC_DATA_W = AXI_ADDR_WIDTH + LEN_WIDTH;

    // ============================================================
    // RAM signals (connect sink write port and DMA read port)
    // ============================================================
    wire [RAM_SEG_COUNT*RAM_SEG_BE_WIDTH-1:0]   ram_wr_cmd_be;
    wire [RAM_SEG_COUNT*RAM_SEG_ADDR_WIDTH-1:0]  ram_wr_cmd_addr;
    wire [RAM_SEG_COUNT*RAM_SEG_DATA_WIDTH-1:0]  ram_wr_cmd_data;
    wire [RAM_SEG_COUNT-1:0]                     ram_wr_cmd_valid;
    wire [RAM_SEG_COUNT-1:0]                     ram_wr_cmd_ready;
    wire [RAM_SEG_COUNT-1:0]                     ram_wr_done;

    wire [RAM_SEG_COUNT*RAM_SEG_ADDR_WIDTH-1:0]  ram_rd_cmd_addr;
    wire [RAM_SEG_COUNT-1:0]                     ram_rd_cmd_valid;
    wire [RAM_SEG_COUNT-1:0]                     ram_rd_cmd_ready;
    wire [RAM_SEG_COUNT*RAM_SEG_DATA_WIDTH-1:0]  ram_rd_resp_data;
    wire [RAM_SEG_COUNT-1:0]                     ram_rd_resp_valid;
    wire [RAM_SEG_COUNT-1:0]                     ram_rd_resp_ready;

    // ============================================================
    // Shared Packet Buffer RAM (async: wr=s_clk, rd=m_clk)
    // ============================================================
    dma_psdpram_async #(
        .SIZE(RAM_SIZE),
        .SEG_COUNT(RAM_SEG_COUNT),
        .SEG_DATA_WIDTH(RAM_SEG_DATA_WIDTH),
        .SEG_BE_WIDTH(RAM_SEG_BE_WIDTH),
        .SEG_ADDR_WIDTH(RAM_SEG_ADDR_WIDTH),
        .PIPELINE(2)
    ) ram_inst (
        .clk_wr(s_clk),
        .rst_wr(s_rst),
        .wr_cmd_be(ram_wr_cmd_be),
        .wr_cmd_addr(ram_wr_cmd_addr),
        .wr_cmd_data(ram_wr_cmd_data),
        .wr_cmd_valid(ram_wr_cmd_valid),
        .wr_cmd_ready(ram_wr_cmd_ready),
        .wr_done(ram_wr_done),

        .clk_rd(m_clk),
        .rst_rd(m_rst),
        .rd_cmd_addr(ram_rd_cmd_addr),
        .rd_cmd_valid(ram_rd_cmd_valid),
        .rd_cmd_ready(ram_rd_cmd_ready),
        .rd_resp_data(ram_rd_resp_data),
        .rd_resp_valid(ram_rd_resp_valid),
        .rd_resp_ready(ram_rd_resp_ready)
    );

    // ============================================================
    // AXI-Stream Sink (s_clk domain)
    // Receives 512-bit data, writes to RAM
    // ============================================================
    dma_client_axis_sink #(
        .RAM_ADDR_WIDTH(RAM_ADDR_WIDTH),
        .SEG_COUNT(RAM_SEG_COUNT),
        .SEG_DATA_WIDTH(RAM_SEG_DATA_WIDTH),
        .SEG_BE_WIDTH(RAM_SEG_BE_WIDTH),
        .SEG_ADDR_WIDTH(RAM_SEG_ADDR_WIDTH),
        .AXIS_DATA_WIDTH(AXIS_DATA_WIDTH),
        .AXIS_KEEP_ENABLE(1),
        .AXIS_KEEP_WIDTH(AXIS_KEEP_WIDTH),
        .AXIS_LAST_ENABLE(1),
        .AXIS_ID_ENABLE(0),
        .AXIS_DEST_ENABLE(0),
        .AXIS_USER_ENABLE(0),
        .LEN_WIDTH(LEN_WIDTH),
        .TAG_WIDTH(TAG_WIDTH)
    ) sink_inst (
        .clk(s_clk),
        .rst(s_rst),

        .s_axis_write_desc_ram_addr(sink_desc_ram_addr),
        .s_axis_write_desc_len(sink_desc_len),
        .s_axis_write_desc_tag(sink_desc_tag),
        .s_axis_write_desc_valid(sink_desc_valid),
        .s_axis_write_desc_ready(sink_desc_ready),

        .m_axis_write_desc_status_len(sink_status_len),
        .m_axis_write_desc_status_tag(sink_status_tag),
        .m_axis_write_desc_status_id(),
        .m_axis_write_desc_status_dest(),
        .m_axis_write_desc_status_user(),
        .m_axis_write_desc_status_error(),
        .m_axis_write_desc_status_valid(sink_status_valid),

        .s_axis_write_data_tdata(sink_axis_tdata),
        .s_axis_write_data_tkeep(sink_axis_tkeep),
        .s_axis_write_data_tvalid(sink_axis_tvalid),
        .s_axis_write_data_tready(sink_axis_tready),
        .s_axis_write_data_tlast(sink_axis_tlast),
        .s_axis_write_data_tid(8'h0),
        .s_axis_write_data_tdest(8'h0),
        .s_axis_write_data_tuser(1'b0),

        .ram_wr_cmd_be(ram_wr_cmd_be),
        .ram_wr_cmd_addr(ram_wr_cmd_addr),
        .ram_wr_cmd_data(ram_wr_cmd_data),
        .ram_wr_cmd_valid(ram_wr_cmd_valid),
        .ram_wr_cmd_ready(ram_wr_cmd_ready),
        .ram_wr_done(ram_wr_done),

        .enable(1'b1),
        .abort(1'b0)
    );

    // ============================================================
    // Write DMA descriptor CDC (s_clk -> m_clk)
    // tdata = {axi_addr, ram_sel, ram_addr, len, tag}
    // ============================================================
    taxi_axis_if #(
        .DATA_W(WR_DMA_DESC_W),
        .KEEP_EN(1'b0),
        .LAST_EN(1'b0)
    ) wr_dma_desc_m_if ();

    taxi_axis_async_fifo #(
        .DEPTH(16),
        .FRAME_FIFO(1'b0)
    ) wr_dma_desc_cdc_inst (
        .s_clk(s_clk),
        .s_rst(s_rst),
        .s_axis(wr_dma_desc_if),
        .m_clk(m_clk),
        .m_rst(m_rst),
        .m_axis(wr_dma_desc_m_if)
    );

    // ============================================================
    // Write DMA status CDC (m_clk -> s_clk)
    // tdata = {error[3:0], tag[TAG_WIDTH-1:0]}
    // ============================================================
    taxi_axis_if #(
        .DATA_W(WR_DMA_STATUS_W),
        .KEEP_EN(1'b0),
        .LAST_EN(1'b0)
    ) wr_dma_status_m_if ();

    wire [TAG_WIDTH-1:0] dma_wr_status_tag;
    wire [3:0]           dma_wr_status_error;
    wire                 dma_wr_status_valid;
    reg                  wr_status_pending;
    reg [TAG_WIDTH-1:0]  wr_status_tag_r;
    reg [3:0]            wr_status_error_r;

    always @(posedge m_clk) begin
        if (m_rst) begin
            wr_status_pending  <= 1'b0;
            wr_status_tag_r    <= '0;
            wr_status_error_r  <= '0;
        end else begin
            if (dma_wr_status_valid && !wr_status_pending) begin
                wr_status_pending  <= 1'b1;
                wr_status_tag_r    <= dma_wr_status_tag;
                wr_status_error_r  <= dma_wr_status_error;
            end else if (wr_dma_status_m_if.tready) begin
                wr_status_pending <= 1'b0;
            end
        end
    end

    assign wr_dma_status_m_if.tdata[TAG_WIDTH-1:0]           = wr_status_tag_r;
    assign wr_dma_status_m_if.tdata[TAG_WIDTH+3-1:TAG_WIDTH]  = wr_status_error_r;
    assign wr_dma_status_m_if.tvalid = wr_status_pending;

    taxi_axis_async_fifo #(
        .DEPTH(16),
        .FRAME_FIFO(1'b0)
    ) wr_dma_status_cdc_inst (
        .s_clk(m_clk),
        .s_rst(m_rst),
        .s_axis(wr_dma_status_m_if),
        .m_clk(s_clk),
        .m_rst(s_rst),
        .m_axis(wr_dma_status_if)
    );

    // ============================================================
    // Read descriptor CDC (s_clk -> m_clk)
    // ============================================================
    taxi_axis_if #(
        .DATA_W(RD_DESC_DATA_W),
        .KEEP_EN(1'b0),
        .LAST_EN(1'b0)
    ) rd_desc_m_if ();

    taxi_axis_async_fifo #(
        .DEPTH(16),
        .FRAME_FIFO(1'b0)
    ) rd_desc_cdc_inst (
        .s_clk(s_clk),
        .s_rst(s_rst),
        .s_axis(rd_desc_if),
        .m_clk(m_clk),
        .m_rst(m_rst),
        .m_axis(rd_desc_m_if)
    );

    // ============================================================
    // Read data CDC (m_clk -> s_clk)
    // rd_axis_m_if <- axi_dma_rd output
    // rd_axis_s_if -> output port
    // ============================================================
    taxi_axis_if #(.DATA_W(AXI_DATA_WIDTH)) rd_axis_m_if ();
    taxi_axis_if #(.DATA_W(AXI_DATA_WIDTH)) rd_axis_s_if ();

    taxi_axis_async_fifo #(
        .DEPTH(512),
        .FRAME_FIFO(1'b0)
    ) rd_data_cdc_inst (
        .s_clk(m_clk),
        .s_rst(m_rst),
        .s_axis(rd_axis_m_if),
        .m_clk(s_clk),
        .m_rst(s_rst),
        .m_axis(rd_axis_s_if)
    );

    assign rd_axis_tdata_out  = rd_axis_s_if.tdata;
    assign rd_axis_tkeep_out  = rd_axis_s_if.tkeep;
    assign rd_axis_tvalid_out = rd_axis_s_if.tvalid;
    assign rd_axis_tlast_out  = rd_axis_s_if.tlast;
    assign rd_axis_s_if.tready = rd_axis_tready_out;

    logic s_rst_d1;
    always_ff @(posedge m_clk) begin
        s_rst_d1 <= s_rst;
    end

    // ============================================================
    // AXI DMA Write engine (m_clk domain)
    // Reads from RAM, writes to AXI bus
    // Uses op_table for pipelined operation tracking
    // ============================================================
    wire [AXI_ADDR_WIDTH-1:0] wr_dma_desc_axi_addr = wr_dma_desc_m_if.tdata[WR_DMA_DESC_W-1:TAG_WIDTH+LEN_WIDTH+RAM_ADDR_WIDTH+RAM_SEL_WIDTH];
    wire [RAM_SEL_WIDTH-1:0]  wr_dma_desc_ram_sel  = wr_dma_desc_m_if.tdata[TAG_WIDTH+LEN_WIDTH+RAM_ADDR_WIDTH+RAM_SEL_WIDTH-1:TAG_WIDTH+LEN_WIDTH+RAM_ADDR_WIDTH];
    wire [RAM_ADDR_WIDTH-1:0] wr_dma_desc_ram_addr = wr_dma_desc_m_if.tdata[TAG_WIDTH+LEN_WIDTH+RAM_ADDR_WIDTH-1:TAG_WIDTH+LEN_WIDTH];
    wire [LEN_WIDTH-1:0]      wr_dma_desc_len      = wr_dma_desc_m_if.tdata[TAG_WIDTH+LEN_WIDTH-1:TAG_WIDTH];
    wire [TAG_WIDTH-1:0]      wr_dma_desc_tag      = wr_dma_desc_m_if.tdata[TAG_WIDTH-1:0];

    dma_if_axi_wr #(
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_STRB_WIDTH(AXI_DATA_WIDTH/8),
        .AXI_ID_WIDTH(AXI_ID_WIDTH),
        .AXI_MAX_BURST_LEN(AXI_MAX_BURST_LEN),
        .RAM_SEL_WIDTH(RAM_SEL_WIDTH),
        .RAM_ADDR_WIDTH(RAM_ADDR_WIDTH),
        .RAM_SEG_COUNT(RAM_SEG_COUNT),
        .RAM_SEG_DATA_WIDTH(RAM_SEG_DATA_WIDTH),
        .RAM_SEG_BE_WIDTH(RAM_SEG_BE_WIDTH),
        .RAM_SEG_ADDR_WIDTH(RAM_SEG_ADDR_WIDTH),
        .IMM_ENABLE(0),
        .IMM_WIDTH(32),
        .LEN_WIDTH(LEN_WIDTH),
        .TAG_WIDTH(TAG_WIDTH),
        .OP_TABLE_SIZE(2**AXI_ID_WIDTH),
        .USE_AXI_ID(1)
    ) dma_wr_inst (
        .clk(m_clk),
        .rst(m_rst),

        .m_axi_awid(m_axi_awid),
        .m_axi_awaddr(m_axi_awaddr),
        .m_axi_awlen(m_axi_awlen),
        .m_axi_awsize(m_axi_awsize),
        .m_axi_awburst(m_axi_awburst),
        .m_axi_awlock(m_axi_awlock),
        .m_axi_awcache(m_axi_awcache),
        .m_axi_awprot(m_axi_awprot),
        .m_axi_awvalid(m_axi_awvalid),
        .m_axi_awready(m_axi_awready),
        .m_axi_wdata(m_axi_wdata),
        .m_axi_wstrb(m_axi_wstrb),
        .m_axi_wlast(m_axi_wlast),
        .m_axi_wvalid(m_axi_wvalid),
        .m_axi_wready(m_axi_wready),
        .m_axi_bid(m_axi_bid),
        .m_axi_bresp(m_axi_bresp),
        .m_axi_bvalid(m_axi_bvalid),
        .m_axi_bready(m_axi_bready),

        .s_axis_write_desc_axi_addr(wr_dma_desc_axi_addr),
        .s_axis_write_desc_ram_sel(wr_dma_desc_ram_sel),
        .s_axis_write_desc_ram_addr(wr_dma_desc_ram_addr),
        .s_axis_write_desc_imm(32'h0),
        .s_axis_write_desc_imm_en(1'b0),
        .s_axis_write_desc_len(wr_dma_desc_len),
        .s_axis_write_desc_tag(wr_dma_desc_tag),
        .s_axis_write_desc_valid(wr_dma_desc_m_if.tvalid),
        .s_axis_write_desc_ready(wr_dma_desc_m_if.tready),

        .m_axis_write_desc_status_tag(dma_wr_status_tag),
        .m_axis_write_desc_status_error(dma_wr_status_error),
        .m_axis_write_desc_status_valid(dma_wr_status_valid),

        .ram_rd_cmd_sel(),
        .ram_rd_cmd_addr(ram_rd_cmd_addr),
        .ram_rd_cmd_valid(ram_rd_cmd_valid),
        .ram_rd_cmd_ready(ram_rd_cmd_ready),
        .ram_rd_resp_data(ram_rd_resp_data),
        .ram_rd_resp_valid(ram_rd_resp_valid),
        .ram_rd_resp_ready(ram_rd_resp_ready),

        .enable(1'b1),
        .status_busy(),
        .stat_wr_op_start_tag(),
        .stat_wr_op_start_len(),
        .stat_wr_op_start_valid(),
        .stat_wr_op_finish_tag(),
        .stat_wr_op_finish_status(),
        .stat_wr_op_finish_valid(),
        .stat_wr_req_start_tag(),
        .stat_wr_req_start_len(),
        .stat_wr_req_start_valid(),
        .stat_wr_req_finish_tag(),
        .stat_wr_req_finish_status(),
        .stat_wr_req_finish_valid(),
        .stat_wr_op_table_full(),
        .stat_wr_tx_stall()
    );

    // ============================================================
    // AXI DMA Read engine (m_clk domain)
    // ============================================================
    wire [AXI_ADDR_WIDTH-1:0] rd_desc_addr_m = rd_desc_m_if.tdata[RD_DESC_DATA_W-1:LEN_WIDTH];
    wire [LEN_WIDTH-1:0]      rd_desc_len_m  = rd_desc_m_if.tdata[LEN_WIDTH-1:0];

    axi_dma_rd #(
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_ID_WIDTH(AXI_ID_WIDTH),
        .AXI_MAX_BURST_LEN(AXI_MAX_BURST_LEN),
        .AXIS_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXIS_KEEP_ENABLE(1),
        .AXIS_KEEP_WIDTH(AXI_DATA_WIDTH/8),
        .AXIS_LAST_ENABLE(1),
        .AXIS_ID_ENABLE(0),
        .AXIS_DEST_ENABLE(0),
        .AXIS_USER_ENABLE(0),
        .LEN_WIDTH(LEN_WIDTH),
        .TAG_WIDTH(4),
        .ENABLE_SG(0),
        .ENABLE_UNALIGNED(0)
    ) dma_rd_inst (
        .clk(m_clk),
        .rst(m_rst),
        .s_axis_read_desc_addr(rd_desc_addr_m),
        .s_axis_read_desc_len(rd_desc_len_m),
        .s_axis_read_desc_tag(4'h0),
        .s_axis_read_desc_id(8'h0),
        .s_axis_read_desc_dest(8'h0),
        .s_axis_read_desc_user(1'b0),
        .s_axis_read_desc_valid(rd_desc_m_if.tvalid),
        .s_axis_read_desc_ready(rd_desc_m_if.tready),
        .m_axis_read_desc_status_tag(),
        .m_axis_read_desc_status_error(),
        .m_axis_read_desc_status_valid(),
        .m_axis_read_data_tdata(rd_axis_m_if.tdata),
        .m_axis_read_data_tkeep(rd_axis_m_if.tkeep),
        .m_axis_read_data_tvalid(rd_axis_m_if.tvalid),
        .m_axis_read_data_tready(rd_axis_m_if.tready),
        .m_axis_read_data_tlast(rd_axis_m_if.tlast),
        .m_axis_read_data_tid(),
        .m_axis_read_data_tdest(),
        .m_axis_read_data_tuser(),
        .m_axi_arid(m_axi_arid),
        .m_axi_araddr(m_axi_araddr),
        .m_axi_arlen(m_axi_arlen),
        .m_axi_arsize(m_axi_arsize),
        .m_axi_arburst(m_axi_arburst),
        .m_axi_arlock(m_axi_arlock),
        .m_axi_arcache(m_axi_arcache),
        .m_axi_arprot(m_axi_arprot),
        .m_axi_arvalid(m_axi_arvalid),
        .m_axi_arready(m_axi_arready),
        .m_axi_rid(m_axi_rid),
        .m_axi_rdata(m_axi_rdata),
        .m_axi_rresp(m_axi_rresp),
        .m_axi_rlast(m_axi_rlast),
        .m_axi_rvalid(m_axi_rvalid),
        .m_axi_rready(m_axi_rready),
        .enable(1'b1)
    );

endmodule
