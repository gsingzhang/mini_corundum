module ludp_protocol #(
    parameter int DATA_WIDTH        = 64,
    parameter int KEEP_WIDTH        = 8,
    parameter int MAX_PAYLOAD_BYTES = 9000,
    parameter int NUM_BLOCKS        = 3,
    parameter int MEM_SLOT_SIZE     = 16384,
    parameter int AXI_DATA_WIDTH    = 512
)(
    input  wire        clk,
    input  wire        rst,
    input  wire        m_clk,
    input  wire        m_rst,

    input  wire [47:0] local_mac,
    input  wire [31:0] local_ip,
    input  wire [47:0] host_mac,
    input  wire [31:0] host_ip,
    input  wire [15:0] udp_port,

    output logic [15:0] cmd_opcode,
    output logic [31:0] cmd_arg1,
    output logic [15:0] cmd_arg2,
    output logic        cmd_valid,
    input  wire         cmd_ready,

    input  wire  [15:0] status_opcode,
    input  wire  [31:0] status_data,
    input  wire         status_valid,
    output logic        status_ready,

    input  wire [DATA_WIDTH-1:0] dma_axis_tdata,
    input  wire [KEEP_WIDTH-1:0] dma_axis_tkeep,
    input  wire                  dma_axis_tvalid,
    output logic                 dma_axis_tready,
    input  wire                  dma_axis_tlast,
    input  wire                  dma_axis_tuser,
    input  wire [15:0]           dma_pkt_size,

    input  wire        rx_udp_hdr_valid,
    output logic       rx_udp_hdr_ready,
    input  wire [47:0] rx_udp_eth_dest_mac,
    input  wire [47:0] rx_udp_eth_src_mac,
    input  wire [15:0] rx_udp_eth_type,
    input  wire [31:0] rx_udp_ip_source_ip,
    input  wire [31:0] rx_udp_ip_dest_ip,
    input  wire [15:0] rx_udp_source_port,
    input  wire [15:0] rx_udp_dest_port,
    input  wire [15:0] rx_udp_length,
    input  wire [15:0] rx_udp_checksum,

    input  wire [DATA_WIDTH-1:0] rx_udp_payload_axis_tdata,
    input  wire [KEEP_WIDTH-1:0] rx_udp_payload_axis_tkeep,
    input  wire                  rx_udp_payload_axis_tvalid,
    output logic                 rx_udp_payload_axis_tready,
    input  wire                  rx_udp_payload_axis_tlast,
    input  wire                  rx_udp_payload_axis_tuser,

    output logic       tx_udp_hdr_valid,
    input  wire        tx_udp_hdr_ready,
    output logic [5:0] tx_udp_ip_dscp,
    output logic [1:0] tx_udp_ip_ecn,
    output logic [7:0] tx_udp_ip_ttl,
    output logic [31:0] tx_udp_ip_source_ip,
    output logic [31:0] tx_udp_ip_dest_ip,
    output logic [15:0] tx_udp_source_port,
    output logic [15:0] tx_udp_dest_port,
    output logic [15:0] tx_udp_length,
    output logic [15:0] tx_udp_checksum,

    output logic [DATA_WIDTH-1:0] tx_udp_payload_axis_tdata,
    output logic [KEEP_WIDTH-1:0] tx_udp_payload_axis_tkeep,
    output logic                  tx_udp_payload_axis_tvalid,
    input  wire                   tx_udp_payload_axis_tready,
    output logic                  tx_udp_payload_axis_tlast,
    output logic                  tx_udp_payload_axis_tuser,

    output logic [31:0] tx_seq_num,
    output logic [31:0] rx_credit_limit,
    output logic        f2h_tx_enabled,
    output logic [31:0] packets_sent,
    output logic [31:0] packets_retx,
    output logic [31:0] cmd_count,
    output logic [15:0] last_payload_size,

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
    input  logic [1:0]         m_axi_bresp,
    input  logic                m_axi_bvalid,
    output logic                m_axi_bready,

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

    logic [31:0] seq_num_reg;
    logic [31:0] credit_limit_reg;
    logic        f2h_tx_enabled_reg;
    logic [31:0] packets_sent_reg;

    logic [15:0] resp_opcode_reg;
    logic [31:0] resp_cmd_id_reg;
    logic [7:0]  resp_status_reg;
    logic [31:0] resp_data_reg;
    logic        resp_ongoing_reg;
    logic        resp_is_cpl_reg;

    logic        rx_resp_req;
    logic [15:0] rx_resp_opcode;
    logic [31:0] rx_resp_cmd_id;
    logic [7:0]  rx_resp_status;
    logic [31:0] rx_resp_data;
    logic        rx_resp_is_cpl;
    logic        rx_cmd_start_req;
    logic        rx_cmd_stop_req;
    logic        rx_credit_valid;
    logic [31:0] rx_credit_new;
    logic        rx_status_req;
    logic [15:0] rx_status_opcode;
    logic [31:0] rx_status_data;
    logic        rx_retx_req;
    logic [31:0] rx_retx_seq;

    logic        tx_resp_done;

    logic [47:0] rx_src_mac;
    logic [31:0] rx_src_ip;
    logic [15:0] rx_src_port;

    logic        sch_tx_pkt_ready;
    logic        sch_ready;
    logic        sch_tx_pkt_start;
    logic [31:0] sch_tx_pkt_seq;
    logic        sch_tx_pkt_done;
    logic        sch_dma_wr_enable;
    logic        sch_retx_found;
    logic [15:0] sch_rd_pkt_size;
    logic [31:0] sch_rd_pkt_seq;
    logic        sch_rd_is_retx;

    logic [31:0]           dma_wr_desc_addr;
    logic [15:0]           dma_wr_desc_len;
    logic                  dma_wr_desc_valid;
    logic                  dma_wr_desc_ready;

    logic [511:0]          dma_wr_axis_tdata;
    logic [63:0]           dma_wr_axis_tkeep;
    logic                  dma_wr_axis_tvalid;
    logic                  dma_wr_axis_tready;
    logic                  dma_wr_axis_tlast;

    logic [31:0]           dma_rd_desc_addr;
    logic [15:0]           dma_rd_desc_len;
    logic                  dma_rd_desc_valid;
    logic                  dma_rd_desc_ready;

    logic [511:0]          dma_rd_axis_tdata;
    logic [63:0]           dma_rd_axis_tkeep;
    logic                  dma_rd_axis_tvalid;
    logic                  dma_rd_axis_tready;
    logic                  dma_rd_axis_tlast;

    logic [DATA_WIDTH-1:0] tx_rd_axis_tdata;
    logic [KEEP_WIDTH-1:0] tx_rd_axis_tkeep;
    logic                  tx_rd_axis_tvalid;
    logic                  tx_rd_axis_tready;
    logic                  tx_rd_axis_tlast;
    logic                  tx_rd_axis_tuser;

    ludp_protocol_rx #(
        .DATA_WIDTH(DATA_WIDTH),
        .KEEP_WIDTH(KEEP_WIDTH),
        .MAX_PAYLOAD_BYTES(MAX_PAYLOAD_BYTES)
    ) rx_inst (
        .clk(clk),
        .rst(rst),

        .local_mac(local_mac),
        .local_ip(local_ip),
        .host_mac(host_mac),
        .host_ip(host_ip),
        .udp_port(udp_port),

        .cmd_opcode(cmd_opcode),
        .cmd_arg1(cmd_arg1),
        .cmd_arg2(cmd_arg2),
        .cmd_valid(cmd_valid),

        .status_opcode(status_opcode),
        .status_data(status_data),
        .status_valid(status_valid),

        .rx_udp_hdr_valid(rx_udp_hdr_valid),
        .rx_udp_hdr_ready(rx_udp_hdr_ready),
        .rx_udp_eth_dest_mac(rx_udp_eth_dest_mac),
        .rx_udp_eth_src_mac(rx_udp_eth_src_mac),
        .rx_udp_eth_type(rx_udp_eth_type),
        .rx_udp_ip_source_ip(rx_udp_ip_source_ip),
        .rx_udp_ip_dest_ip(rx_udp_ip_dest_ip),
        .rx_udp_source_port(rx_udp_source_port),
        .rx_udp_dest_port(rx_udp_dest_port),
        .rx_udp_length(rx_udp_length),
        .rx_udp_checksum(rx_udp_checksum),

        .rx_udp_payload_axis_tdata(rx_udp_payload_axis_tdata),
        .rx_udp_payload_axis_tkeep(rx_udp_payload_axis_tkeep),
        .rx_udp_payload_axis_tvalid(rx_udp_payload_axis_tvalid),
        .rx_udp_payload_axis_tready(rx_udp_payload_axis_tready),
        .rx_udp_payload_axis_tlast(rx_udp_payload_axis_tlast),
        .rx_udp_payload_axis_tuser(rx_udp_payload_axis_tuser),

        .rx_resp_req(rx_resp_req),
        .rx_resp_opcode(rx_resp_opcode),
        .rx_resp_cmd_id(rx_resp_cmd_id),
        .rx_resp_status(rx_resp_status),
        .rx_resp_data(rx_resp_data),
        .rx_resp_is_cpl(rx_resp_is_cpl),

        .rx_cmd_start_req(rx_cmd_start_req),
        .rx_cmd_stop_req(rx_cmd_stop_req),
        .rx_credit_valid(rx_credit_valid),
        .rx_credit_new(rx_credit_new),

        .rx_status_req(rx_status_req),
        .rx_status_opcode(rx_status_opcode),
        .rx_status_data(rx_status_data),

        .rx_retx_req(rx_retx_req),
        .rx_retx_seq(rx_retx_seq),

        .rx_src_mac(rx_src_mac),
        .rx_src_ip(rx_src_ip),
        .rx_src_port(rx_src_port),

        .cmd_count(cmd_count),
        .packets_retx(packets_retx),

        .f2h_tx_enabled(f2h_tx_enabled_reg),
        .credit_limit(credit_limit_reg),
        .resp_ongoing(resp_ongoing_reg)
    );

    ludp_tx_scheduler #(
        .NUM_BLOCKS(NUM_BLOCKS),
        .KEEP_WIDTH(KEEP_WIDTH),
        .DATA_WIDTH(DATA_WIDTH),
        .MEM_ADDR_W(32),
        .MEM_BASE_ADDR('0),
        .MEM_SLOT_SIZE(MEM_SLOT_SIZE),
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .MAX_PAYLOAD_BYTES(MAX_PAYLOAD_BYTES)
    ) scheduler_inst (
        .clk(clk),
        .rst(rst),
        .clear(rx_cmd_start_req),

        .dma_axis_tdata (dma_axis_tdata),
        .dma_axis_tkeep (dma_axis_tkeep),
        .dma_axis_tvalid(dma_axis_tvalid),
        .dma_axis_tready(dma_axis_tready),
        .dma_axis_tlast (dma_axis_tlast),
        .dma_axis_tuser (dma_axis_tuser),
        .dma_pkt_size   (dma_pkt_size),

        .tx_pkt_ready   (sch_tx_pkt_ready),
        .sch_ready      (sch_ready),
        .tx_pkt_start   (sch_tx_pkt_start),
        .tx_pkt_seq     (sch_tx_pkt_seq),
        .tx_pkt_done    (sch_tx_pkt_done),

        .dma_wr_enable  (sch_dma_wr_enable),

        .retx_req       (rx_retx_req),
        .retx_seq       (rx_retx_seq),
        .retx_found     (sch_retx_found),

        .rd_pkt_size    (sch_rd_pkt_size),
        .rd_pkt_seq     (sch_rd_pkt_seq),

        .rd_axis_tdata (tx_rd_axis_tdata),
        .rd_axis_tkeep (tx_rd_axis_tkeep),
        .rd_axis_tvalid(tx_rd_axis_tvalid),
        .rd_axis_tready(tx_rd_axis_tready),
        .rd_axis_tlast (tx_rd_axis_tlast),
        .rd_axis_tuser (tx_rd_axis_tuser),

        .dma_wr_desc_addr  (dma_wr_desc_addr),
        .dma_wr_desc_len   (dma_wr_desc_len),
        .dma_wr_desc_valid (dma_wr_desc_valid),
        .dma_wr_desc_ready (dma_wr_desc_ready),

        .dma_wr_axis_tdata (dma_wr_axis_tdata),
        .dma_wr_axis_tkeep (dma_wr_axis_tkeep),
        .dma_wr_axis_tvalid(dma_wr_axis_tvalid),
        .dma_wr_axis_tready(dma_wr_axis_tready),
        .dma_wr_axis_tlast (dma_wr_axis_tlast),

        .dma_rd_desc_addr  (dma_rd_desc_addr),
        .dma_rd_desc_len   (dma_rd_desc_len),
        .dma_rd_desc_valid (dma_rd_desc_valid),
        .dma_rd_desc_ready (dma_rd_desc_ready),

        .dma_rd_axis_tdata (dma_rd_axis_tdata),
        .dma_rd_axis_tkeep (dma_rd_axis_tkeep),
        .dma_rd_axis_tvalid(dma_rd_axis_tvalid),
        .dma_rd_axis_tready(dma_rd_axis_tready),
        .dma_rd_axis_tlast (dma_rd_axis_tlast),

        .rd_is_retx        (sch_rd_is_retx)
    );

    ludp_dma_wrapper #(
        .AXI_DATA_WIDTH(AXI_DATA_WIDTH),
        .AXI_ADDR_WIDTH(32),
        .AXI_ID_WIDTH(4),
        .AXI_MAX_BURST_LEN(16),
        .AXIS_DATA_WIDTH(AXI_DATA_WIDTH),
        .LEN_WIDTH(16)
    ) dma_wrapper_inst (
        .s_clk(clk),
        .s_rst(rst),
        .m_clk(m_clk),
        .m_rst(m_rst),

        .wr_desc_addr (dma_wr_desc_addr),
        .wr_desc_len  (dma_wr_desc_len),
        .wr_desc_valid(dma_wr_desc_valid),
        .wr_desc_ready(dma_wr_desc_ready),

        .wr_axis_tdata (dma_wr_axis_tdata),
        .wr_axis_tkeep (dma_wr_axis_tkeep),
        .wr_axis_tvalid(dma_wr_axis_tvalid),
        .wr_axis_tready(dma_wr_axis_tready),
        .wr_axis_tlast (dma_wr_axis_tlast),

        .rd_desc_addr (dma_rd_desc_addr),
        .rd_desc_len  (dma_rd_desc_len),
        .rd_desc_valid(dma_rd_desc_valid),
        .rd_desc_ready(dma_rd_desc_ready),

        .rd_axis_tdata (dma_rd_axis_tdata),
        .rd_axis_tkeep (dma_rd_axis_tkeep),
        .rd_axis_tvalid(dma_rd_axis_tvalid),
        .rd_axis_tready(dma_rd_axis_tready),
        .rd_axis_tlast (dma_rd_axis_tlast),

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
        .m_axi_rready(m_axi_rready)
    );

    ludp_protocol_tx #(
        .DATA_WIDTH(DATA_WIDTH),
        .KEEP_WIDTH(KEEP_WIDTH),
        .MAX_PAYLOAD_BYTES(MAX_PAYLOAD_BYTES)
    ) tx_inst (
        .clk(clk),
        .rst(rst),

        .local_mac(local_mac),
        .local_ip(local_ip),
        .host_mac(host_mac),
        .host_ip(host_ip),
        .udp_port(udp_port),

        .data_in_tdata (tx_rd_axis_tdata),
        .data_in_tkeep (tx_rd_axis_tkeep),
        .data_in_tvalid(tx_rd_axis_tvalid),
        .data_in_tready(tx_rd_axis_tready),
        .data_in_tlast (tx_rd_axis_tlast),
        .data_in_tuser (tx_rd_axis_tuser),
        .data_in_done  (sch_tx_pkt_done),

        .tx_pkt_ready   (sch_tx_pkt_ready),
        .sch_ready      (sch_ready),
        .tx_pkt_start   (sch_tx_pkt_start),
        .tx_pkt_seq     (sch_tx_pkt_seq),
        .rd_is_retx     (sch_rd_is_retx),
        .retx_found     (sch_retx_found),
        .rd_pkt_size    (sch_rd_pkt_size),
        .rd_pkt_seq     (sch_rd_pkt_seq),

        .tx_udp_hdr_valid(tx_udp_hdr_valid),
        .tx_udp_hdr_ready(tx_udp_hdr_ready),
        .tx_udp_ip_dscp(tx_udp_ip_dscp),
        .tx_udp_ip_ecn(tx_udp_ip_ecn),
        .tx_udp_ip_ttl(tx_udp_ip_ttl),
        .tx_udp_ip_source_ip(tx_udp_ip_source_ip),
        .tx_udp_ip_dest_ip(tx_udp_ip_dest_ip),
        .tx_udp_source_port(tx_udp_source_port),
        .tx_udp_dest_port(tx_udp_dest_port),
        .tx_udp_length(tx_udp_length),
        .tx_udp_checksum(tx_udp_checksum),

        .tx_udp_payload_axis_tdata(tx_udp_payload_axis_tdata),
        .tx_udp_payload_axis_tkeep(tx_udp_payload_axis_tkeep),
        .tx_udp_payload_axis_tvalid(tx_udp_payload_axis_tvalid),
        .tx_udp_payload_axis_tready(tx_udp_payload_axis_tready),
        .tx_udp_payload_axis_tlast(tx_udp_payload_axis_tlast),
        .tx_udp_payload_axis_tuser(tx_udp_payload_axis_tuser),

        .resp_opcode(resp_opcode_reg),
        .resp_cmd_id(resp_cmd_id_reg),
        .resp_status(resp_status_reg),
        .resp_data(resp_data_reg),
        .resp_ongoing(resp_ongoing_reg),
        .resp_is_cpl(resp_is_cpl_reg),
        .resp_done(tx_resp_done),

        .seq_num(seq_num_reg),
        .credit_limit(credit_limit_reg),
        .f2h_tx_enabled(f2h_tx_enabled_reg),

        .rx_src_ip(rx_src_ip),
        .rx_src_port(rx_src_port),

        .cmd_start_req(rx_cmd_start_req),

        .last_payload_size(last_payload_size)
    );

    always_ff @(posedge clk) begin
        if (rst) begin
            seq_num_reg       <= 0;
            credit_limit_reg  <= 0;
            f2h_tx_enabled_reg <= 1'b0;
            packets_sent_reg  <= 0;
            resp_ongoing_reg  <= 1'b0;
            resp_opcode_reg   <= 16'h0;
            resp_cmd_id_reg   <= 32'h0;
            resp_status_reg   <= 8'h0;
            resp_data_reg     <= 32'h0;
            resp_is_cpl_reg   <= 1'b0;
        end else begin
            if (tx_resp_done) begin
                resp_ongoing_reg <= 1'b0;
            end
            if (sch_tx_pkt_done) begin
                seq_num_reg      <= seq_num_reg + 1;
                packets_sent_reg <= packets_sent_reg + 1;
            end

            if (rx_cmd_start_req) begin
                f2h_tx_enabled_reg <= 1'b1;
                seq_num_reg      <= 0;
                credit_limit_reg <= 0;
            end
            if (rx_cmd_stop_req) begin
                f2h_tx_enabled_reg <= 1'b0;
            end

            if (rx_credit_valid) begin
                credit_limit_reg <= rx_credit_new;
            end

            if (!resp_ongoing_reg) begin
                if (rx_resp_req) begin
                    resp_opcode_reg <= rx_resp_opcode;
                    resp_cmd_id_reg <= rx_resp_cmd_id;
                    resp_status_reg <= rx_resp_status;
                    resp_data_reg   <= rx_resp_data;
                    resp_ongoing_reg  <= 1'b1;
                    resp_is_cpl_reg <= rx_resp_is_cpl;
                end else if (rx_status_req) begin
                    resp_opcode_reg <= rx_status_opcode;
                    resp_cmd_id_reg <= 32'h0;
                    resp_status_reg <= 8'h00;
                    resp_data_reg   <= rx_status_data;
                    resp_ongoing_reg  <= 1'b1;
                    resp_is_cpl_reg <= 1'b1;
                end
            end
        end
    end

    assign sch_tx_pkt_seq = seq_num_reg;

    assign tx_seq_num      = seq_num_reg;
    assign rx_credit_limit = credit_limit_reg;
    assign f2h_tx_enabled  = f2h_tx_enabled_reg;
    assign packets_sent    = packets_sent_reg;
    assign status_ready    = 1'b1;

endmodule
