module ludp_dma_wrapper #(
    parameter int AXI_DATA_WIDTH = 512,
    parameter int AXI_ADDR_WIDTH = 32,
    parameter int AXI_ID_WIDTH   = 4,
    parameter int AXI_MAX_BURST_LEN = 16,
    parameter int AXIS_DATA_WIDTH = 512,
    parameter int LEN_WIDTH      = 16
)(
    input  wire        s_clk,
    input  wire        s_rst,
    input  wire        m_clk,
    input  wire        m_rst,

    input  wire [AXI_ADDR_WIDTH-1:0] wr_desc_addr,
    input  wire [LEN_WIDTH-1:0]      wr_desc_len,
    input  wire                       wr_desc_valid,
    output wire                       wr_desc_ready,

    input  wire [AXIS_DATA_WIDTH-1:0] wr_axis_tdata,
    input  wire [(AXIS_DATA_WIDTH/8)-1:0] wr_axis_tkeep,
    input  wire                       wr_axis_tvalid,
    output wire                       wr_axis_tready,
    input  wire                       wr_axis_tlast,

    output wire                       wr_complete,

    input  wire [AXI_ADDR_WIDTH-1:0] rd_desc_addr,
    input  wire [LEN_WIDTH-1:0]      rd_desc_len,
    input  wire                       rd_desc_valid,
    output wire                       rd_desc_ready,

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

    // ============================================================
    // Write descriptor CDC (s_clk -> m_clk)
    // Register data in s_clk, then toggle-handshake to m_clk
    // ============================================================
    reg [AXI_ADDR_WIDTH-1:0] wr_desc_addr_s;
    reg [LEN_WIDTH-1:0]      wr_desc_len_s;
    reg                      wr_desc_toggle_s;
    reg                      wr_desc_toggle_m_sync1, wr_desc_toggle_m_sync2;
    reg [AXI_ADDR_WIDTH-1:0] wr_desc_addr_m;
    reg [LEN_WIDTH-1:0]      wr_desc_len_m;
    reg                      wr_desc_ready_m;
    wire                     wr_desc_accept_m = wr_desc_toggle_m_sync2 ^ wr_desc_toggle_m_sync1;
    wire                     wr_desc_ready_s;

    always @(posedge s_clk) begin
        if (s_rst) begin
            wr_desc_toggle_s <= 1'b0;
            wr_desc_addr_s   <= '0;
            wr_desc_len_s    <= '0;
        end else if (wr_desc_valid && wr_desc_ready_s) begin
            wr_desc_toggle_s <= ~wr_desc_toggle_s;
            wr_desc_addr_s   <= wr_desc_addr;
            wr_desc_len_s    <= wr_desc_len;
        end
    end

    always @(posedge m_clk) begin
        if (m_rst) begin
            wr_desc_toggle_m_sync1 <= 1'b0;
            wr_desc_toggle_m_sync2 <= 1'b0;
            wr_desc_addr_m <= '0;
            wr_desc_len_m  <= '0;
            wr_desc_ready_m <= 1'b0;
        end else begin
            wr_desc_toggle_m_sync1 <= wr_desc_toggle_s;
            wr_desc_toggle_m_sync2 <= wr_desc_toggle_m_sync1;
            if (wr_desc_accept_m) begin
                wr_desc_addr_m <= wr_desc_addr_s;
                wr_desc_len_m  <= wr_desc_len_s;
                wr_desc_ready_m <= 1'b1;
            end else begin
                wr_desc_ready_m <= 1'b0;
            end
        end
    end

    assign wr_desc_ready_s = (wr_desc_toggle_s == wr_desc_toggle_m_sync2);
    assign wr_desc_ready   = wr_desc_ready_s;

    // ============================================================
    // Read descriptor CDC (s_clk -> m_clk)
    // Register data in s_clk, then toggle-handshake to m_clk
    // ============================================================
    reg [AXI_ADDR_WIDTH-1:0] rd_desc_addr_s;
    reg [LEN_WIDTH-1:0]      rd_desc_len_s;
    reg                      rd_desc_toggle_s;
    reg                      rd_desc_toggle_m_sync1, rd_desc_toggle_m_sync2;
    reg [AXI_ADDR_WIDTH-1:0] rd_desc_addr_m;
    reg [LEN_WIDTH-1:0]      rd_desc_len_m;
    reg                      rd_desc_ready_m;
    wire                     rd_desc_accept_m = rd_desc_toggle_m_sync2 ^ rd_desc_toggle_m_sync1;
    wire                     rd_desc_ready_s;

    always @(posedge s_clk) begin
        if (s_rst) begin
            rd_desc_toggle_s <= 1'b0;
            rd_desc_addr_s   <= '0;
            rd_desc_len_s    <= '0;
        end else if (rd_desc_valid && rd_desc_ready_s) begin
            rd_desc_toggle_s <= ~rd_desc_toggle_s;
            rd_desc_addr_s   <= rd_desc_addr;
            rd_desc_len_s    <= rd_desc_len;
        end
    end

    always @(posedge m_clk) begin
        if (m_rst) begin
            rd_desc_toggle_m_sync1 <= 1'b0;
            rd_desc_toggle_m_sync2 <= 1'b0;
            rd_desc_addr_m <= '0;
            rd_desc_len_m  <= '0;
            rd_desc_ready_m <= 1'b0;
        end else begin
            rd_desc_toggle_m_sync1 <= rd_desc_toggle_s;
            rd_desc_toggle_m_sync2 <= rd_desc_toggle_m_sync1;
            if (rd_desc_accept_m) begin
                rd_desc_addr_m <= rd_desc_addr_s;
                rd_desc_len_m  <= rd_desc_len_s;
                rd_desc_ready_m <= 1'b1;
            end else begin
                rd_desc_ready_m <= 1'b0;
            end
        end
    end

    assign rd_desc_ready_s = (rd_desc_toggle_s == rd_desc_toggle_m_sync2);
    assign rd_desc_ready   = rd_desc_ready_s;

    // ============================================================
    // Write complete CDC (m_clk -> s_clk)
    // Toggle-handshake synchronizer for BRESP completion
    // ============================================================
    reg                      wr_complete_toggle_m;
    reg                      wr_complete_toggle_s_sync1, wr_complete_toggle_s_sync2;
    reg                      wr_complete_pulse_s;

    always @(posedge m_clk) begin
        if (m_rst) begin
            wr_complete_toggle_m <= 1'b0;
        end else begin
            if (m_axi_bvalid && m_axi_bready) begin
                wr_complete_toggle_m <= ~wr_complete_toggle_m;
            end
        end
    end

    always @(posedge s_clk) begin
        if (s_rst) begin
            wr_complete_toggle_s_sync1 <= 1'b0;
            wr_complete_toggle_s_sync2 <= 1'b0;
            wr_complete_pulse_s        <= 1'b0;
        end else begin
            wr_complete_toggle_s_sync1 <= wr_complete_toggle_m;
            wr_complete_toggle_s_sync2 <= wr_complete_toggle_s_sync1;
            wr_complete_pulse_s        <= wr_complete_toggle_s_sync2 ^ wr_complete_toggle_s_sync1;
        end
    end

    assign wr_complete = wr_complete_pulse_s;

    // ============================================================
    // Write data path: async FIFO (s_clk -> m_clk)
    // ============================================================
    taxi_axis_if #(
        .DATA_W(AXIS_DATA_WIDTH)
    ) wr_axis_m_if ();

    taxi_axis_if #(
        .DATA_W(AXIS_DATA_WIDTH)
    ) wr_axis_s_if ();

    assign wr_axis_s_if.tdata  = wr_axis_tdata;
    assign wr_axis_s_if.tkeep  = wr_axis_tkeep;
    assign wr_axis_s_if.tvalid = wr_axis_tvalid;
    assign wr_axis_s_if.tlast  = wr_axis_tlast;
    assign wr_axis_s_if.tuser  = 1'b0;
    assign wr_axis_tready      = wr_axis_s_if.tready;

    taxi_axis_async_fifo #(
        .DEPTH(512),
        .FRAME_FIFO(1'b0)
    ) wr_async_fifo_inst (
        .s_clk(s_clk),
        .s_rst(s_rst),
        .s_axis(wr_axis_s_if),
        .m_clk(m_clk),
        .m_rst(m_rst),
        .m_axis(wr_axis_m_if)
    );

    // ============================================================
    // Read data path: async FIFO (m_clk -> s_clk)
    // ============================================================
    taxi_axis_if #(
        .DATA_W(AXIS_DATA_WIDTH)
    ) rd_axis_m_if ();

    taxi_axis_if #(
        .DATA_W(AXIS_DATA_WIDTH)
    ) rd_axis_s_if ();

    assign rd_axis_tdata  = rd_axis_s_if.tdata;
    assign rd_axis_tkeep  = rd_axis_s_if.tkeep;
    assign rd_axis_tvalid = rd_axis_s_if.tvalid;
    assign rd_axis_tlast  = rd_axis_s_if.tlast;
    assign rd_axis_s_if.tready = rd_axis_tready;

    taxi_axis_async_fifo #(
        .DEPTH(512),
        .FRAME_FIFO(1'b0)
    ) rd_async_fifo_inst (
        .s_clk(m_clk),
        .s_rst(m_rst),
        .s_axis(rd_axis_m_if),
        .m_clk(s_clk),
        .m_rst(s_rst),
        .m_axis(rd_axis_s_if)
    );

    // ============================================================
    // AXI DMA engines (on m_clk domain)
    // ============================================================
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
        .TAG_WIDTH(4),
        .ENABLE_SG(0),
        .ENABLE_UNALIGNED(0)
    ) u_axi_dma_wr (
        .clk(m_clk),
        .rst(m_rst),
        .s_axis_write_desc_addr(wr_desc_addr_m),
        .s_axis_write_desc_len(wr_desc_len_m),
        .s_axis_write_desc_tag(4'h1),
        .s_axis_write_desc_valid(wr_desc_ready_m),
        .s_axis_write_desc_ready(),
        .m_axis_write_desc_status_len(),
        .m_axis_write_desc_status_tag(),
        .m_axis_write_desc_status_id(),
        .m_axis_write_desc_status_dest(),
        .m_axis_write_desc_status_user(),
        .m_axis_write_desc_status_error(),
        .m_axis_write_desc_status_valid(),
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
        .s_axis_read_desc_tag(4'hB),
        .s_axis_read_desc_id(8'h0),
        .s_axis_read_desc_dest(8'h0),
        .s_axis_read_desc_user(1'b0),
        .s_axis_read_desc_valid(rd_desc_ready_m),
        .s_axis_read_desc_ready(),
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
