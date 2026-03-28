//=========================================================================================================
// Copyright (C) 2026 by TechAnalytics LLC Author: Donald W McCauley
//
// File: cla_koggestone_r4.sv
// Description: A 8/16/24/32‑bit Radix‑4 Kogge‑Stone Carry‑Lookahead Adder
//
// License: This project is released under the: CERN Open Hardware Licence Version 2 - Permissive
//     https://ohwr.org/cern_ohl_p_v2.pdf
//
// Design Note: ~8 logic levels in ASAP7
//=========================================================================================================
`timescale 1ns/1ps
`define PARITY 

module cla_koggestone_r4 #(
    parameter int WIDTH = 16             // must be 16, 24 or 32 for this design
) (
    input  logic [WIDTH-1:0] a,
    input  logic [WIDTH-1:0] b,
`ifdef PARITY
    input  logic [(WIDTH/8)-1:0] a_pty,  // a parity 
    input  logic [(WIDTH/8)-1:0] b_pty,  // b parity 
`endif
    input  logic             cin,
    output logic [WIDTH-1:0] sum,
`ifdef PARITY
    output logic [(WIDTH/8)-1:0] parity, // predicted sum parity
`endif
    output logic             ovfl        // unsigned‑overflow flag
);
    // -----------------------------------------------------------------
    // 0. Sanity check
    // -----------------------------------------------------------------
    initial begin
        if ((WIDTH != 16) && (WIDTH != 24) && (WIDTH != 32))
            $error("cla_koggestone_r4 is written for WIDTH = 16, 24 or 32 (got %0d)", WIDTH);
    end

    // -----------------------------------------------------------------
    // 1. Bit‑wise generate (g) and propagate (p)
    // -----------------------------------------------------------------
    logic [WIDTH-1:0] g, p;
    assign g = a & b;          // generate
    assign p = a ^ b;          // propagate

    // -----------------------------------------------------------------
    // 2. Prefix tree – Radix‑4 (3 stages)
    // -----------------------------------------------------------------
    // G[k][i] / P[k][i] : generate / propagate of the group that ends
    // at bit i after stage k.
    localparam int STAGES = 3;               // distances: 1, 2, 8 (covers 32 bits)
    logic [WIDTH-1:0] G [STAGES:0];
    logic [WIDTH-1:0] P [STAGES:0];

    // stage 0 – raw bit values
    assign G[0] = g;
    assign P[0] = p;

    // -----------------------------------------------------------------
    // Stage 1 – distance = 1   (combine two 1‑bit groups → 2‑bit groups)
    // -----------------------------------------------------------------
    genvar i;
    generate
        for (i = 0; i < WIDTH; i++) begin : STAGE1
            if (i >= 1) begin
                assign G[1][i] = G[0][i] | (P[0][i] & G[0][i-1]);
                assign P[1][i] = P[0][i] & P[0][i-1];
            end else begin
                assign G[1][i] = G[0][i];
                assign P[1][i] = P[0][i];
            end
        end
    endgenerate

    // -----------------------------------------------------------------
    // Stage 2 – distance = 2   (combine two 2‑bit groups → 4‑bit groups)
    // -----------------------------------------------------------------
    generate
        for (i = 0; i < WIDTH; i++) begin : STAGE2
            // look back 2 bits, 4 bits and 6 bits (the three preceding groups)
            if (i >= 6) begin
                assign G[2][i] = G[1][i] |
                                 (P[1][i]           & G[1][i-2]) |
                                 (P[1][i] & P[1][i-2] & G[1][i-4]) |
                                 (P[1][i] & P[1][i-2] & P[1][i-4] & G[1][i-6]);
                assign P[2][i] = P[1][i] &
                                 (i>=2 ? P[1][i-2] : 1'b1) &
                                 (i>=4 ? P[1][i-4] : 1'b1) &
                                 (i>=6 ? P[1][i-6] : 1'b1);
            end else if (i >= 4) begin
                assign G[2][i] = G[1][i] |
                                 (P[1][i]           & G[1][i-2]) |
                                 (P[1][i] & P[1][i-2] & G[1][i-4]);
                assign P[2][i] = P[1][i] &
                                 (i>=2 ? P[1][i-2] : 1'b1) &
                                 (i>=4 ? P[1][i-4] : 1'b1);
            end else if (i >= 2) begin
                assign G[2][i] = G[1][i] |
                                 (P[1][i]           & G[1][i-2]);
                assign P[2][i] = P[1][i] &
                                 (i>=2 ? P[1][i-2] : 1'b1);
            end else begin
                // first two bits cannot look back far enough – just forward
                assign G[2][i] = G[1][i];
                assign P[2][i] = P[1][i];
            end
        end
    endgenerate

    // -----------------------------------------------------------------
    // Stage 3 – distance = 8   (combine four 4‑bit groups → 16‑bit groups)
    // -----------------------------------------------------------------
    generate
        for (i = 0; i < WIDTH; i++) begin : STAGE3
            // after stage‑2 each group spans 4 bits, so we look back 8,16,24 bits
            if (i >= 24) begin
                assign G[3][i] = G[2][i] |
                                 (P[2][i]           & G[2][i-8]) |
                                 (P[2][i] & P[2][i-8] & G[2][i-16]) |
                                 (P[2][i] & P[2][i-8] & P[2][i-16] & G[2][i-24]);
                assign P[3][i] = P[2][i] &
                                 (i>=8  ? P[2][i-8]  : 1'b1) &
                                 (i>=16 ? P[2][i-16] : 1'b1) &
                                 (i>=24 ? P[2][i-24] : 1'b1);
            end else if (i >= 16) begin
                assign G[3][i] = G[2][i] |
                                 (P[2][i]           & G[2][i-8]) |
                                 (P[2][i] & P[2][i-8] & G[2][i-16]);
                assign P[3][i] = P[2][i] &
                                 (i>=8  ? P[2][i-8]  : 1'b1) &
                                 (i>=16 ? P[2][i-16] : 1'b1);
            end else if (i >= 8) begin
                assign G[3][i] = G[2][i] |
                                 (P[2][i]           & G[2][i-8]);
                assign P[3][i] = P[2][i] &
                                 (i>=8  ? P[2][i-8]  : 1'b1);
            end else begin
                assign G[3][i] = G[2][i];
                assign P[3][i] = P[2][i];
            end
        end
    endgenerate

    // -----------------------------------------------------------------
    // 4. Carry vector
    // -----------------------------------------------------------------
    logic [WIDTH:0] c; // c[0] … c[32]
    assign c[0]  = cin;
    generate
        for (i = 0; i < WIDTH; i++) begin : CARRY_GEN
            assign c[i+1] = G[3][i] | (P[3][i] & cin);
        end
    endgenerate

`ifdef PARITY
    (* DONT_TOUCH = "true" *) logic [WIDTH:0] c_dup;    // duplicate carry gen logic for parity predict
    assign c_dup[0]  = cin;
    generate
        for (i = 0; i < WIDTH; i++) begin : CARRY_GEN_DUP
            assign c_dup[i+1] = G[3][i] | (P[3][i] & cin);
        end
    endgenerate

    // --- Byte Parity Prediction ---
    genvar byte_idx;
    generate
        for (byte_idx = 0; byte_idx < WIDTH / 8; byte_idx++) begin : gen_byte_parity
            // Range for the current byte
            localparam int LOW  = byte_idx * 8;
            localparam int HIGH = LOW + 7;

            // P_sum = P_a ^ P_b ^ P_carries_in
            // Carries needed: c_internal[LOW] through c_internal[HIGH]
            assign parity[byte_idx] = a_pty[byte_idx] ^ b_pty[byte_idx] ^ (^c_dup[HIGH:LOW]);
        end
    endgenerate
`endif

    // -----------------------------------------------------------------
    // 5a. Sum and Signed overflow
    // -----------------------------------------------------------------
    assign sum = p ^ c[WIDTH-1:0];          // sum[i] = p[i] XOR c[i]
    assign ovfl = c[WIDTH] & !cin;          // unsigned overflow - Add only

    // -----------------------------------------------------------------
    // 5b. Unsigned overflow – just the final carry out of the whole adder
    // -----------------------------------------------------------------
    //assign uovf = c[WIDTH];                // 1 if a+b produced a carry beyond bit WIDTH‑1

endmodule : cla_koggestone_r4
