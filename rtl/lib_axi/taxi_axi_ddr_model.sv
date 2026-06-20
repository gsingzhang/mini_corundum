`resetall
`timescale 1ns / 1ps
`default_nettype none

module taxi_axi_ddr_model #
(
    parameter int ADDR_W = 16,
    parameter int RD_LATENCY = 17,
    parameter int WR_LATENCY = 12,
    parameter int AW_ACCEPT_LATENCY = 4,
    parameter int AR_ACCEPT_LATENCY = 4,
    parameter int B_LATENCY = 4,
    parameter logic PIPELINE_OUTPUT = 1'b0
)
(
    input  wire logic   clk,
    input  wire logic   rst,

    taxi_axi_if.wr_slv  s_axi_wr,
    taxi_axi_if.rd_slv  s_axi_rd
);

localparam DATA_W = s_axi_wr.DATA_W;
localparam STRB_W = s_axi_wr.STRB_W;
localparam WR_ID_W = s_axi_wr.ID_W;
localparam RD_ID_W = s_axi_rd.ID_W;

localparam VALID_ADDR_W = ADDR_W - $clog2(STRB_W);
localparam BYTE_LANES = STRB_W;
localparam BYTE_W = DATA_W / BYTE_LANES;

logic [DATA_W-1:0] mem[2**VALID_ADDR_W] = '{default: '0};

typedef enum logic [1:0] {
    WR_IDLE,
    WR_DATA,
    WR_RESP
} wr_state_t;

wr_state_t wr_state_reg;

logic [WR_ID_W-1:0]  wr_id_reg;
logic [ADDR_W-1:0]   wr_addr_reg;
logic [7:0]          wr_count_reg;
logic [2:0]          wr_size_reg;
logic [1:0]          wr_burst_reg;

logic [AW_ACCEPT_LATENCY-1:0] aw_accept_cnt_reg;
logic [B_LATENCY-1:0]         b_latency_cnt_reg;
logic                         b_pending_reg;
logic [WR_ID_W-1:0]           b_id_reg;

logic [WR_LATENCY-1:0]        w_accept_cnt_reg;

always_ff @(posedge clk) begin
    if (rst) begin
        wr_state_reg      <= WR_IDLE;
        wr_id_reg         <= '0;
        wr_addr_reg       <= '0;
        wr_count_reg      <= '0;
        wr_size_reg       <= '0;
        wr_burst_reg      <= '0;
        aw_accept_cnt_reg <= '0;
        b_latency_cnt_reg <= '0;
        b_pending_reg     <= 1'b0;
        b_id_reg          <= '0;
        w_accept_cnt_reg  <= '0;
    end else begin
        case (wr_state_reg)
            WR_IDLE: begin
                if (aw_accept_cnt_reg == 0 && s_axi_wr.awvalid) begin
                    wr_id_reg    <= s_axi_wr.awid;
                    wr_addr_reg  <= ADDR_W'(s_axi_wr.awaddr);
                    wr_count_reg <= s_axi_wr.awlen;
                    wr_size_reg  <= s_axi_wr.awsize <= 3'($clog2(STRB_W)) ? s_axi_wr.awsize : 3'($clog2(STRB_W));
                    wr_burst_reg <= s_axi_wr.awburst;
                    if (AW_ACCEPT_LATENCY > 0)
                        aw_accept_cnt_reg <= AW_ACCEPT_LATENCY[AW_ACCEPT_LATENCY-1:0];
                    else
                        wr_state_reg <= WR_DATA;
                end
            end

            WR_DATA: begin
                if (s_axi_wr.wvalid) begin
                    for (integer i = 0; i < BYTE_LANES; i = i + 1) begin
                        if (s_axi_wr.wstrb[i]) begin
                            mem[VALID_ADDR_W'(wr_addr_reg >> (ADDR_W - VALID_ADDR_W))][BYTE_W*i +: BYTE_W]
                                <= s_axi_wr.wdata[BYTE_W*i +: BYTE_W];
                        end
                    end
                    if (wr_burst_reg != 2'b00)
                        wr_addr_reg <= wr_addr_reg + (1 << wr_size_reg);
                    wr_count_reg <= wr_count_reg - 1;
                    if (wr_count_reg == 8'd0 || wr_count_reg == 8'd1) begin
                        b_id_reg <= wr_id_reg;
                        if (B_LATENCY > 0) begin
                            b_latency_cnt_reg <= B_LATENCY[B_LATENCY-1:0];
                            b_pending_reg     <= 1'b1;
                        end else begin
                            b_pending_reg <= 1'b1;
                        end
                        wr_state_reg <= WR_RESP;
                    end
                end
            end

            WR_RESP: begin
                if (s_axi_wr.bready && b_pending_reg) begin
                    b_pending_reg <= 1'b0;
                    wr_state_reg  <= WR_IDLE;
                end
            end

            default: wr_state_reg <= WR_IDLE;
        endcase

        if (aw_accept_cnt_reg > 0) begin
            aw_accept_cnt_reg <= aw_accept_cnt_reg - 1;
            if (aw_accept_cnt_reg == 1)
                wr_state_reg <= WR_DATA;
        end

        if (b_latency_cnt_reg > 0)
            b_latency_cnt_reg <= b_latency_cnt_reg - 1;
    end
end

assign s_axi_wr.awready = (wr_state_reg == WR_IDLE) && (aw_accept_cnt_reg == 0);
assign s_axi_wr.wready  = (wr_state_reg == WR_DATA);
assign s_axi_wr.bid     = b_id_reg;
assign s_axi_wr.bresp   = 2'b00;
assign s_axi_wr.buser   = '0;
assign s_axi_wr.bvalid  = b_pending_reg && (b_latency_cnt_reg == 0);

typedef enum logic [1:0] {
    RD_IDLE,
    RD_WAIT,
    RD_BURST
} rd_state_t;

rd_state_t rd_state_reg;

logic [RD_ID_W-1:0]  rd_id_reg;
logic [ADDR_W-1:0]   rd_addr_reg;
logic [7:0]          rd_count_reg;
logic [2:0]          rd_size_reg;
logic [1:0]          rd_burst_reg;

logic [AR_ACCEPT_LATENCY-1:0] ar_accept_cnt_reg;
logic [RD_LATENCY-1:0]        rd_latency_cnt_reg;

logic [RD_ID_W-1:0]   s_axi_rid_pipe_reg;
logic [DATA_W-1:0]    s_axi_rdata_pipe_reg;
logic                  s_axi_rlast_pipe_reg;
logic                  s_axi_rvalid_pipe_reg;
logic                  s_axi_rvalid_reg;
logic [DATA_W-1:0]    s_axi_rdata_out_reg;
logic                  s_axi_rlast_out_reg;
logic [RD_ID_W-1:0]   s_axi_rid_out_reg;

always_ff @(posedge clk) begin
    if (rst) begin
        rd_state_reg      <= RD_IDLE;
        rd_id_reg         <= '0;
        rd_addr_reg       <= '0;
        rd_count_reg      <= '0;
        rd_size_reg       <= '0;
        rd_burst_reg      <= '0;
        ar_accept_cnt_reg <= '0;
        rd_latency_cnt_reg<= '0;
        s_axi_rvalid_reg  <= 1'b0;
        s_axi_rdata_out_reg <= '0;
        s_axi_rlast_out_reg <= 1'b0;
        s_axi_rid_out_reg   <= '0;
        s_axi_rvalid_pipe_reg <= 1'b0;
    end else begin
        if (s_axi_rd.rready || !s_axi_rvalid_reg) begin
            if (s_axi_rvalid_reg) begin
                s_axi_rvalid_reg <= 1'b0;
            end
        end

        if (PIPELINE_OUTPUT && (!s_axi_rvalid_pipe_reg || s_axi_rd.rready)) begin
            s_axi_rid_pipe_reg   <= s_axi_rid_out_reg;
            s_axi_rdata_pipe_reg <= s_axi_rdata_out_reg;
            s_axi_rlast_pipe_reg <= s_axi_rlast_out_reg;
            s_axi_rvalid_pipe_reg <= s_axi_rvalid_reg;
        end

        case (rd_state_reg)
            RD_IDLE: begin
                if (ar_accept_cnt_reg == 0 && s_axi_rd.arvalid) begin
                    rd_id_reg    <= s_axi_rd.arid;
                    rd_addr_reg  <= ADDR_W'(s_axi_rd.araddr);
                    rd_count_reg <= s_axi_rd.arlen;
                    rd_size_reg  <= s_axi_rd.arsize <= 3'($clog2(STRB_W)) ? s_axi_rd.arsize : 3'($clog2(STRB_W));
                    rd_burst_reg <= s_axi_rd.arburst;
                    if (AR_ACCEPT_LATENCY > 0)
                        ar_accept_cnt_reg <= AR_ACCEPT_LATENCY[AR_ACCEPT_LATENCY-1:0];
                    else
                        rd_state_reg <= RD_WAIT;
                end
            end

            RD_WAIT: begin
                if (rd_latency_cnt_reg > 0) begin
                    rd_latency_cnt_reg <= rd_latency_cnt_reg - 1;
                end else if (!s_axi_rvalid_reg) begin
                    s_axi_rdata_out_reg <= mem[VALID_ADDR_W'(rd_addr_reg >> (ADDR_W - VALID_ADDR_W))];
                    s_axi_rid_out_reg   <= rd_id_reg;
                    s_axi_rlast_out_reg <= (rd_count_reg == 0);
                    s_axi_rvalid_reg    <= 1'b1;
                    if (rd_burst_reg != 2'b00)
                        rd_addr_reg <= rd_addr_reg + (1 << rd_size_reg);
                    rd_count_reg <= rd_count_reg - 1;
                    if (rd_count_reg == 0)
                        rd_state_reg <= RD_IDLE;
                    else
                        rd_state_reg <= RD_BURST;
                end
            end

            RD_BURST: begin
                if (!s_axi_rvalid_reg) begin
                    s_axi_rdata_out_reg <= mem[VALID_ADDR_W'(rd_addr_reg >> (ADDR_W - VALID_ADDR_W))];
                    s_axi_rid_out_reg   <= rd_id_reg;
                    s_axi_rlast_out_reg <= (rd_count_reg == 1);
                    s_axi_rvalid_reg    <= 1'b1;
                    if (rd_burst_reg != 2'b00)
                        rd_addr_reg <= rd_addr_reg + (1 << rd_size_reg);
                    rd_count_reg <= rd_count_reg - 1;
                    if (rd_count_reg == 1)
                        rd_state_reg <= RD_IDLE;
                end
            end

            default: rd_state_reg <= RD_IDLE;
        endcase

        if (ar_accept_cnt_reg > 0) begin
            ar_accept_cnt_reg <= ar_accept_cnt_reg - 1;
            if (ar_accept_cnt_reg == 1) begin
                rd_state_reg       <= RD_WAIT;
                rd_latency_cnt_reg <= RD_LATENCY[RD_LATENCY-1:0];
            end
        end
    end
end

assign s_axi_rd.arready = (rd_state_reg == RD_IDLE) && (ar_accept_cnt_reg == 0);

assign s_axi_rd.rid    = PIPELINE_OUTPUT ? s_axi_rid_pipe_reg   : s_axi_rid_out_reg;
assign s_axi_rd.rdata  = PIPELINE_OUTPUT ? s_axi_rdata_pipe_reg : s_axi_rdata_out_reg;
assign s_axi_rd.rresp  = 2'b00;
assign s_axi_rd.rlast  = PIPELINE_OUTPUT ? s_axi_rlast_pipe_reg : s_axi_rlast_out_reg;
assign s_axi_rd.ruser  = '0;
assign s_axi_rd.rvalid = PIPELINE_OUTPUT ? s_axi_rvalid_pipe_reg : s_axi_rvalid_reg;

endmodule

`resetall
