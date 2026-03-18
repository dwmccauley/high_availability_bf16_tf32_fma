//=========================================================================================================
// Copyright (C) 2026 by TechAnalytics LLC Author: Donald W McCauley
//
// File: cla_adder_8.sv
// Description: 8‑bit Carry‑Look‑Ahead adder (unsigned)
//
// License: This project is released under the: CERN Open Hardware Licence Version 2 - Permissive
//     https://ohwr.org/cern_ohl_p_v2.pdf
//=========================================================================================================
`timescale 1ns/1ps
module cla_adder_8 (
    input  logic [7:0] a,
    input  logic [7:0] b,
    input  logic       cin,   // normally 0 for multiplier
    output logic [7:0] sum,
    output logic       cout
);
    // ---- Generate and Propagate signals ----
    logic   [7:0] g;   // generate
    assign g[7:0] = a & b; 
    logic   [7:0] p;   // propagate
    assign p[7:0] = a ^ b;   

    // ---- Carry look‑ahead logic (4‑bit blocks) ----
    // we build 2 groups of 4 bits each.
    // Group carry signals (C4, C8)
    /* verilator lint_off UNOPTFLAT */
    logic [2:0] c;   // c[0] = cin, c[2] = cout
    /* verilator lint_on UNOPTFLAT */
    assign c[0] = cin;

    genvar i;
    generate
        for (i = 0; i < 2; i=i+1) begin : block
            // indices for the 4‑bit group
            localparam int L = i*4;
            // group generate & propagate
            wire g4 = g[L+3] | (p[L+3] & g[L+2]) |
                      (p[L+3] & p[L+2] & g[L+1]) |
                      (p[L+3] & p[L+2] & p[L+1] & g[L]);

            wire p4 = p[L+3] & p[L+2] & p[L+1] & p[L];

            // carry out of the block
            assign c[i+1] = g4 | (p4 & c[i]);
        end : block
    endgenerate

    // TODO: Per Shibu Menon, 3-bit groupings are arguably more efficient than 4-bit groupings

    // ---- Individual carries inside each block ----
    logic [7:0] carry;
    generate
        for (i = 0; i < 2; i=i+1) begin : inner
            localparam int L = i*4;
            // c[L] is the incoming carry for the block
            assign carry[L]   = c[i];
            assign carry[L+1] = g[L]   | (p[L]   & c[i]);
            assign carry[L+2] = g[L+1] | (p[L+1] & g[L])   |
                                         (p[L+1] & p[L] & c[i]);
            assign carry[L+3] = g[L+2] | (p[L+2] & g[L+1]) |
                                         (p[L+2] & p[L+1] & g[L]) |
                                         (p[L+2] & p[L+1] & p[L] & c[i]);
        end : inner
    endgenerate

    // ---- Sum bits ----
    assign sum = p ^ carry;

    // ---- Final carry out ----
    assign cout = c[2];

//  always @*
//   	 $display("a = %h, b = %h, cin = %h, sum = %h, carry = %h, p = %h, g = %h", a, b, cin, sum, carry, p, g);
endmodule : cla_adder_8
