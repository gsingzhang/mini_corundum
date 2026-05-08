`timescale 1ns / 1ps

module cmd_stream_app (
    input  wire        clk,
    input  wire        rst,

    // UDP RX
    input  wire        s_udp_hdr_valid,
    output wire        s_udp_hdr_ready,
    input  wire [31:0] s_udp_ip_source_ip,
    input  wire [31:0] s_udp_ip_dest_ip,
    input  wire [15:0] s_udp_source_port,
    input  wire [15:0] s_udp_dest_port,
    input  wire [15:0] s_udp_length,
    input  wire [15:0] s_udp_checksum,
    input  wire [63:0] s_udp_payload_axis_tdata,
    input  wire [7:0]  s_udp_payload_axis_tkeep,
    input  wire        s_udp_payload_axis_tvalid,
    output wire        s_udp_payload_axis_tready,
    input  wire        s_udp_payload_axis_tlast,
    input  wire        s_udp_payload_axis_tuser,

    // UDP TX
    output wire        m_udp_hdr_valid,
    input  wire        m_udp_hdr_ready,
    output wire [31:0] m_udp_ip_source_ip,
    output wire [31:0] m_udp_ip_dest_ip,
    output wire [15:0] m_udp_source_port,
    output wire [15:0] m_udp_dest_port,
    output wire [15:0] m_udp_length,
    output wire [15:0] m_udp_checksum,
    output wire [63:0] m_udp_payload_axis_tdata,
    output wire [7:0]  m_udp_payload_axis_tkeep,
    output wire        m_udp_payload_axis_tvalid,
    input  wire        m_udp_payload_axis_tready,
    output wire        m_udp_payload_axis_tlast,
    output wire        m_udp_payload_axis_tuser
);

    // simple command parser state
    reg streaming_en;
    reg [31:0] target_ip;
    reg [15:0] target_port;
    
    assign s_udp_hdr_ready = 1'b1;
    assign s_udp_payload_axis_tready = 1'b1;

    always @(posedge clk) begin
        if (rst) begin
            streaming_en <= 1'b0;
            target_ip <= 32'd0;
            target_port <= 16'd0;
        end else begin
            if (s_udp_hdr_valid && s_udp_hdr_ready) begin
                if (s_udp_dest_port == 16'd1234) begin
                    streaming_en <= 1'b1;
                    target_ip <= s_udp_ip_source_ip;
                    target_port <= s_udp_source_port;
                end else if (s_udp_dest_port == 16'd1235) begin
                    streaming_en <= 1'b0;
                end
            end
        end
    end

    // stream generator
    reg [15:0] packet_len = 16'd1024; // 1024 bytes payload
    reg [63:0] counter;
    reg [15:0] byte_count;
    
    reg m_hdr_valid_reg;
    reg m_tvalid_reg;
    reg m_tlast_reg;
    
    assign m_udp_hdr_valid = m_hdr_valid_reg;
    assign m_udp_ip_dest_ip = target_ip;
    assign m_udp_ip_source_ip = 32'hc0a8010a; // 192.168.1.10
    assign m_udp_source_port = 16'd1234;
    assign m_udp_dest_port = target_port;
    assign m_udp_length = packet_len;
    assign m_udp_checksum = 16'd0;
    
    assign m_udp_payload_axis_tdata = counter;
    assign m_udp_payload_axis_tkeep = 8'hff;
    assign m_udp_payload_axis_tvalid = m_tvalid_reg;
    assign m_udp_payload_axis_tlast = m_tlast_reg;
    assign m_udp_payload_axis_tuser = 1'b0;
    
    localparam STATE_IDLE = 0, STATE_HDR = 1, STATE_PAYLOAD = 2;
    reg [1:0] state;
    
    always @(posedge clk) begin
        if (rst) begin
            state <= STATE_IDLE;
            m_hdr_valid_reg <= 1'b0;
            m_tvalid_reg <= 1'b0;
            m_tlast_reg <= 1'b0;
            counter <= 0;
            byte_count <= 0;
        end else begin
            case (state)
                STATE_IDLE: begin
                    if (streaming_en) begin
                        m_hdr_valid_reg <= 1'b1;
                        state <= STATE_HDR;
                    end
                end
                STATE_HDR: begin
                    if (m_udp_hdr_ready && m_hdr_valid_reg) begin
                        m_hdr_valid_reg <= 1'b0;
                        m_tvalid_reg <= 1'b1;
                        byte_count <= 8;
                        state <= STATE_PAYLOAD;
                    end
                end
                STATE_PAYLOAD: begin
                    if (m_udp_payload_axis_tready && m_tvalid_reg) begin
                        counter <= counter + 1;
                        byte_count <= byte_count + 8;
                        if (byte_count >= packet_len - 8) begin
                            m_tlast_reg <= 1'b1;
                            if (m_tlast_reg) begin
                                m_tvalid_reg <= 1'b0;
                                m_tlast_reg <= 1'b0;
                                state <= STATE_IDLE;
                            end
                        end
                    end
                end
            endcase
        end
    end

endmodule
