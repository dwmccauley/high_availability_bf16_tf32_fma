//===================================================================
// Copyright (C) 2026 by TechAnalytics LLC Author: Donald W McCauley
//
// File: residue3_gen.sv
// Description: 8- or 16-bit residue-3 (aka modulo-3) generator
//
// License: This project is released under the: CERN Open Hardware Licence Version 2 - Permissive
//     https://ohwr.org/cern_ohl_p_v2.pdf
//===================================================================
`timescale 1ns/1ps
module residue3_gen #(
    parameter int WIDTH = 8               // must be 8 or 16 for this design
) (
    input [WIDTH-1:0] data_in,  // 8-bit input number
    output logic [1:0] residue // 2-bit output for (data_in % 3)
);
    // Sanity check
    initial begin
        if ((WIDTH != 8) && (WIDTH != 16))
            $error("residue3_gen is written for WIDTH = 8 or 16 (got %0d)", WIDTH);
    end

    // Helper macro for readability
    `define MOD3 mod3_adder 

    logic [1:0] s7_4;
    logic [1:0] s3_0;

    `MOD3 mod3_7_4  ( .a(data_in[7:6]),    .b(data_in[5:4]),   .sum(s7_4[1:0]) );
    `MOD3 mod3_3_0  ( .a(data_in[3:2]),    .b(data_in[1:0]),   .sum(s3_0[1:0]) );

    if (WIDTH == 16) begin
        logic [1:0] s7_0;
        logic [1:0] s11_8;
        logic [1:0] s15_8;
        logic [1:0] s15_12;
        `MOD3 mod3_15_12 ( .a(data_in[15:14]), .b(data_in[13:12]), .sum(s15_12[1:0]) );
        `MOD3 mod3_11_8  ( .a(data_in[11:10]), .b(data_in[9:8]),   .sum(s11_8[1:0]) );
        `MOD3 mod3_15_8 ( .a(s15_12[1:0]), .b(s11_8[1:0]), .sum(s15_8[1:0]) );
        `MOD3 mod3_7_0a ( .a(s7_4[1:0]),   .b(s3_0[1:0]),  .sum(s7_0[1:0]) );
        `MOD3 mod3_15_0 ( .a(s15_8[1:0]),  .b(s7_0[1:0]),  .sum(residue[1:0]) );
    end else begin
        `MOD3 mod3_7_0  ( .a(s7_4[1:0]),   .b(s3_0[1:0]),  .sum(residue[1:0]) );
    end

    `undef MOD3 
endmodule : residue3_gen 
