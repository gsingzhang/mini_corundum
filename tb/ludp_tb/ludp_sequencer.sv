`timescale 1ns / 1ps

import ludp_tb_pkg::*;

class ludp_sequencer;

    bit [31:0] rand_seed;

    function new();
        rand_seed = 32'h12345678;
    endfunction

    function void set_seed(input bit [31:0] seed);
        rand_seed = seed;
    endfunction

    function bit [15:0] next_payload_size();
        bit [15:0] result;
        result = random_payload_size(rand_seed);
        rand_seed = rand_seed * 32'h01010101 + 1;
        return result;
    endfunction

    function bit [31:0] next_credit();
        bit [31:0] result;
        result = random_credit(rand_seed);
        rand_seed = rand_seed * 32'h01010101 + 1;
        return result;
    endfunction

    function bit [31:0] next_rand();
        bit [31:0] result;
        result = rand_seed;
        rand_seed = rand_seed * 32'h01010101 + 1;
        return result;
    endfunction

endclass
