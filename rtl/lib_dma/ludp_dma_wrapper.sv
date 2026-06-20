module ludp_dma_wrapper #(
    parameter int AXI_DATA_WIDTH = 512,
    parameter int AXI_ADDR_WIDTH = 32,
    parameter int AXI_ID_WIDTH   = 4,
    parameter int AXI_MAX_BURST_LEN = 16,
    parameter int AXIS_DATA_WIDTH = 512,
    parameter int LEN_WIDTH      = 16,
    parameter int TAG_WIDTH      = 4
)(
    input  wire        s_clk,
    input  wire        s_rst,
    input  wire        m_clk,
    input  wire        m_rst,

    taxi_axis_if   wr_desc_if,
    taxi_axis_if   wr_status_if,
    taxi_axis_if   rd_desc_if,

    input  wire [AXIS_DATA_WIDTH-1:0] wr_axis_tdata,
    input  wire [(AXIS_DATA_WIDTH/8)-1:0] wr_axis_tkeep,
    input  wire                       wr_axis_tvalid,
    output wire                       wr_axis_tready,
    input  wire                       wr_axis_tlast,

    output wire [AXIS_DATA_WIDTH-1:0] rd_axis_tdata,
    output wire [(AXIS_DATA_WIDTH/8)-1:0] rd_axis_tkeep,
    output wire                       rd_axis_tvalid,
    input  wire                       rd_axis_tready,
    output wire                       rd_axis_tlast,

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
    localparam int DESC_DATA_W = AXI_ADDR_WIDTH + LEN_WIDTH + TAG_WIDTH;
    localparam int RD_DESC_DATA_W = AXI_ADDR_WIDTH + LEN_WIDTH;
    localparam int WR_STATUS_W = 4 + TAG_WIDTH;

    // ============================================================
    // Write descriptor CDC (s_clk -> m_clk)
    // ============================================================
    taxi_axis_if #(
        .DATA_W(DESC_DATA_W),
        .KEEP_EN(1'b0),
        .LAST_EN(1'b0)
    ) wr_desc_m_if ();

    taxi_axis_async_fifo #(
        .DEPTH(16),
        .FRAME_FIFO(1'b0)
    ) wr_desc_cdc_inst (
        .s_clk(s_clk),
        .s_rst(s_rst),
        .s_axis(wr_desc_if),
        .m_clk(m_clk),
        .m_rst(m_rst),
        .m_axis(wr_desc_m_if)
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
    // Write status CDC (m_clk -> s_clk)
    // axi_dma_wr status is valid-only (no ready), so we need a
    // skid buffer to hold it until the CDC FIFO accepts.
    // tdata = {error[3:0], tag[TAG_WIDTH-1:0]}
    // ============================================================
    taxi_axis_if #(
        .DATA_W(WR_STATUS_W),
        .KEEP_EN(1'b0),
        .LAST_EN(1'b0)
    ) wr_status_m_if ();

    wire [3:0]           wr_desc_status_error;
    wire                 wr_desc_status_valid;
    wire [TAG_WIDTH-1:0] wr_desc_status_tag;
    reg                  wr_status_pending;
    reg [3:0]            wr_status_error_r;
    reg [TAG_WIDTH-1:0]  wr_status_tag_r;

    always @(posedge m_clk) begin
        if (m_rst) begin
            wr_status_pending <= 1'b0;
            wr_status_error_r <= '0;
            wr_status_tag_r   <= '0;
        end else begin
            if (wr_desc_status_valid && !wr_status_pending) begin
                wr_status_pending <= 1'b1;
                wr_status_error_r <= wr_desc_status_error;
                wr_status_tag_r   <= wr_desc_status_tag;
            end else if (wr_status_m_if.tready) begin
                wr_status_pending <= 1'b0;
            end
        end
    end

    assign wr_status_m_if.tdata[TAG_WIDTH-1:0]           = wr_status_tag_r;
    assign wr_status_m_if.tdata[TAG_WIDTH+3-1:TAG_WIDTH]  = wr_status_error_r;
    assign wr_status_m_if.tvalid = wr_status_pending;

    taxi_axis_async_fifo #(
        .DEPTH(16),
        .FRAME_FIFO(1'b0)
    ) wr_status_cdc_inst (
        .s_clk(m_clk),
        .s_rst(m_rst),
        .s_axis(wr_status_m_if),
        .m_clk(s_clk),
        .m_rst(s_rst),
        .m_axis(wr_status_if)
    );

    // ============================================================
    // Write data CDC (s_clk -> m_clk)
    // ============================================================
    taxi_axis_if #(.DATA_W(AXIS_DATA_WIDTH)) wr_axis_s_if ();
    taxi_axis_if #(.DATA_W(AXIS_DATA_WIDTH)) wr_axis_m_if ();

    assign wr_axis_s_if.tdata  = wr_axis_tdata;
    assign wr_axis_s_if.tkeep  = wr_axis_tkeep;
    assign wr_axis_s_if.tvalid = wr_axis_tvalid;
    assign wr_axis_s_if.tlast  = wr_axis_tlast;
    assign wr_axis_s_if.tuser  = 1'b0;
    assign wr_axis_tready      = wr_axis_s_if.tready;

    taxi_axis_async_fifo #(
        .DEPTH(512),
        .FRAME_FIFO(1'b0)
    ) wr_data_cdc_inst (
        .s_clk(s_clk),
        .s_rst(s_rst),
        .s_axis(wr_axis_s_if),
        .m_clk(m_clk),
        .m_rst(m_rst),
        .m_axis(wr_axis_m_if)
    );

    // ============================================================
    // Read data CDC (m_clk -> s_clk)
    // ============================================================
    taxi_axis_if #(.DATA_W(AXIS_DATA_WIDTH)) rd_axis_m_if ();
    taxi_axis_if #(.DATA_W(AXIS_DATA_WIDTH)) rd_axis_s_if ();

    assign rd_axis_tdata  = rd_axis_s_if.tdata;
    assign rd_axis_tkeep  = rd_axis_s_if.tkeep;
    assign rd_axis_tvalid = rd_axis_s_if.tvalid;
    assign rd_axis_tlast  = rd_axis_s_if.tlast;
    assign rd_axis_s_if.tready = rd_axis_tready;

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

    // ============================================================
    // AXI DMA Write (m_clk domain)
    // ============================================================
    wire [AXI_ADDR_WIDTH-1:0] wr_desc_addr_m = wr_desc_m_if.tdata[DESC_DATA_W-1:TAG_WIDTH+LEN_WIDTH];
    wire [LEN_WIDTH-1:0]      wr_desc_len_m  = wr_desc_m_if.tdata[TAG_WIDTH+LEN_WIDTH-1:TAG_WIDTH];
    wire [TAG_WIDTH-1:0]      wr_desc_tag_m  = wr_desc_m_if.tdata[TAG_WIDTH-1:0];

    axi_dma_wr #(
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_ID_WIDTH(AXI_ID_WIDTH),
        .AXI_MAX_BURST_LEN(AXI_MAX_BURST_LEN),
        .AXIS_DATA_WIDTH(AXIS_DATA_WIDTH),
        .AXIS_KEEP_ENABLE(1),
        .AXIS_KEEP_WIDTH(AXIS_KEEP_WIDTH),
        .AXIS_LAST_ENABLE(1),
        .AXIS_ID_ENABLE(0),
        .AXIS_DEST_ENABLE(0),
        .AXIS_USER_ENABLE(0),
        .LEN_WIDTH(LEN_WIDTH),
        .TAG_WIDTH(TAG_WIDTH),
        .ENABLE_SG(0),
        .ENABLE_UNALIGNED(0)
    ) u_axi_dma_wr (
        .clk(m_clk),
        .rst(m_rst),
        .s_axis_write_desc_addr(wr_desc_addr_m),
        .s_axis_write_desc_len(wr_desc_len_m),
        .s_axis_write_desc_tag(wr_desc_tag_m),
        .s_axis_write_desc_valid(wr_desc_m_if.tvalid),
        .s_axis_write_desc_ready(wr_desc_m_if.tready),
        .m_axis_write_desc_status_len(),
        .m_axis_write_desc_status_tag(wr_desc_status_tag),
        .m_axis_write_desc_status_id(),
        .m_axis_write_desc_status_dest(),
        .m_axis_write_desc_status_user(),
        .m_axis_write_desc_status_error(wr_desc_status_error),
        .m_axis_write_desc_status_valid(wr_desc_status_valid),
        .s_axis_write_data_tdata(wr_axis_m_if.tdata),
        .s_axis_write_data_tkeep(wr_axis_m_if.tkeep),
        .s_axis_write_data_tvalid(wr_axis_m_if.tvalid),
        .s_axis_write_data_tready(wr_axis_m_if.tready),
        .s_axis_write_data_tlast(wr_axis_m_if.tlast),
        .s_axis_write_data_tid(8'h0),
        .s_axis_write_data_tdest(8'h0),
        .s_axis_write_data_tuser(1'b0),
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
        .enable(1'b1),
        .abort(1'b0)
    );

    // ============================================================
    // AXI DMA Read (m_clk domain)
    // ============================================================
    wire [AXI_ADDR_WIDTH-1:0] rd_desc_addr_m = rd_desc_m_if.tdata[RD_DESC_DATA_W-1:LEN_WIDTH];
    wire [LEN_WIDTH-1:0]      rd_desc_len_m  = rd_desc_m_if.tdata[LEN_WIDTH-1:0];

    axi_dma_rd #(
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ADDR_WIDTH(AXI_ADDR_WIDTH),
        .AXI_ID_WIDTH(AXI_ID_WIDTH),
        .AXI_MAX_BURST_LEN(AXI_MAX_BURST_LEN),
        .AXIS_DATA_WIDTH(AXIS_DATA_WIDTH),
        .AXIS_KEEP_ENABLE(1),
        .AXIS_KEEP_WIDTH(AXIS_KEEP_WIDTH),
        .AXIS_LAST_ENABLE(1),
        .AXIS_ID_ENABLE(0),
        .AXIS_DEST_ENABLE(0),
        .AXIS_USER_ENABLE(0),
        .LEN_WIDTH(LEN_WIDTH),
        .TAG_WIDTH(4),
        .ENABLE_SG(0),
        .ENABLE_UNALIGNED(0)
    ) u_axi_dma_rd (
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
