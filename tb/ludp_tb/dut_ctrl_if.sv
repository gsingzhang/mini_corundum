`timescale 1ns / 1ps

interface dut_ctrl_if(input bit clk);

    bit [15:0] payload_size;
    bit        payload_size_we;

    bit [31:0] tx_seq_num;
    bit        tx_enabled;
    bit        dma_wr_enable;

    bit [15:0] force_status_opcode;
    bit [31:0] force_status_data;
    bit        force_status_valid;
    bit        force_status_en;
    bit        force_status_release;

    clocking cb @(posedge clk);
        output payload_size, payload_size_we;
        output force_status_opcode, force_status_data, force_status_valid;
        output force_status_en, force_status_release;
        input tx_seq_num, tx_enabled, dma_wr_enable;
    endclocking

    modport ctrl(clocking cb);

    task set_payload_size(input bit [15:0] size);
        cb.payload_size <= size;
        cb.payload_size_we <= 1'b1;
        @(posedge clk);
        cb.payload_size_we <= 1'b0;
    endtask

    task inject_status(input bit [15:0] opcode, input bit [31:0] data);
        cb.force_status_opcode <= opcode;
        cb.force_status_data  <= data;
        cb.force_status_valid <= 1'b1;
        cb.force_status_en    <= 1'b1;
        cb.force_status_release <= 1'b0;
        @(posedge clk);
        @(posedge clk);
        cb.force_status_en    <= 1'b0;
        cb.force_status_release <= 1'b1;
        @(posedge clk);
        cb.force_status_release <= 1'b0;
        cb.force_status_opcode <= 16'h0;
        cb.force_status_data  <= 32'h0;
        cb.force_status_valid <= 1'b0;
    endtask

    function bit [31:0] get_tx_seq_num();
        return cb.tx_seq_num;
    endfunction

    function bit get_tx_enabled();
        return cb.tx_enabled;
    endfunction

    function bit get_dma_wr_enable();
        return cb.dma_wr_enable;
    endfunction

endinterface
