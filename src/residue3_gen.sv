//===================================================================
// Copyright (C) 2026 by TechAnalytics LLC Author: Donald W McCauley
//
// File: residue3_gen.sv
// Description: 8-bit residue-3 (aka modulo-3) generator
//===================================================================

`timescale 1ns/1ps
module residue3_gen (
    input [7:0] data_in,  // 8-bit input number
    output logic [1:0] residue // 2-bit output for (data_in % 3)
);

    // Helper macro for readability
    `define MOD3 mod3_adder 

    logic [1:0] s7_4;
    logic [1:0] s3_0;

    `MOD3 mod3_7_4 ( .a(data_in[7:6]), .b(data_in[5:4]), .sum(s7_4[1:0]) );
    `MOD3 mod3_3_0 ( .a(data_in[3:2]), .b(data_in[1:0]), .sum(s3_0[1:0]) );

    `MOD3 mod3_7_0 ( .a(s7_4[1:0]), .b(s3_0[1:0]), .sum(residue[1:0]) );

    `undef MOD3 
endmodule : residue3_gen 
