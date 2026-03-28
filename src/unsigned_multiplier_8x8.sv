`default_nettype none
//===================================================================
// Copyright (C) 2026 by TechAnalytics LLC Author: Donald W McCauley
//
// File: unsigned_multiplier_8x8.sv
// Description: Unsigned 8‑bit × 8‑bit multiplier using a Wallace
//              tree for partial‑product reduction with an 8‑bit
//              Carry‑Lookahead adder for the final adder stage.
//              Includes residue-3 prediction.
//
// License: This project is released under the: CERN Open Hardware Licence Version 2 - Permissive
//     https://ohwr.org/cern_ohl_p_v2.pdf
//
// Design Note: Product: ~13-15 logic levels (+ 5-3 inv) in ASAP7. Residue Predict: ~8 logic levels. 
//===================================================================
`timescale 1ns/1ps
`define RESIDUE3

module unsigned_multiplier_8x8 (
    input  logic [7:0]  a,          // multiplicand
    input  logic [7:0]  b,          // multiplier
`ifdef RESIDUE3
    output logic [1:0]  residue_predict,    // predicted Residue-3 for product
`endif
    output logic [15:0] product
);

    // ----------------------------------------------------------------
    // 1) Generate all 64 partial‑product bits (AND matrix)
    // ----------------------------------------------------------------
    logic [7:0] pp[7:0];   // pp[i][j] = a[i] & b[j]
    genvar i, j;
    generate
        for (i = 0; i < 8; i=i+1) begin : gen_a
            for (j = 0; j < 8; j=j+1) begin : gen_b
                assign pp[i][j] = a[i] & b[j];
            end : gen_b
        end : gen_a
    endgenerate

    // ----------------------------------------------------------------
    // 2) Wallace‑tree reduction
    //    We follow the classic column‑by‑column reduction schedule.
    //    The intermediate signals are named after the column they
    //    belong to (c0 … c15).  Each column contains a list of bits.
    // ----------------------------------------------------------------

    // Helper macros for readability
    `define HA  half_adder
    `define FA  full_adder

    // ---------- Column 0 (LSB) ----------
    // Only one bit: pp[0][0]
    logic s0_0; assign s0_0 = pp[0][0];

    // ---------- Column 1 ----------
    // Bits: pp[1][0], pp[0][1]
    logic s1_0, c1_0;
    `HA ha1_0 ( .a(pp[1][0]), .b(pp[0][1]), .sum(s1_0), .cout(c1_0) );

    // ---------- Column 2 ----------
    // Bits: pp[2][0], pp[1][1], pp[0][2]
    logic s2_0, c2_0, s2_1, c2_1;
    `FA fa2_0 ( .a(pp[2][0]), .b(pp[1][1]), .cin(pp[0][2]), .sum(s2_0), .cout(c2_0) );
    `HA ha2_0 ( .a(s2_0), .b(c1_0), .sum(s2_1), .cout(c2_1) );

    // ---------- Column 3 ----------
    // Bits: pp[3][0], pp[2][1], pp[1][2], pp[0][3]
    //  -> two FA + one HA
    logic s3_0, c3_0, s3_1, c3_1, s3_2, c3_2;
    `FA fa3_0 ( .a(pp[3][0]), .b(pp[2][1]), .cin(pp[1][2]), .sum(s3_0), .cout(c3_0) );
    `FA fa3_1 ( .a(s3_0), .b(pp[0][3]), .cin(c2_0), .sum(s3_1), .cout(c3_1) );
    `HA ha3_0 ( .a(s3_1), .b(c2_1), .sum(s3_2), .cout(c3_2) );

    // ---------- Column 4 ----------
    // Bits: pp[4][0], pp[3][1], pp[2][2], pp[1][3], pp[0][4]
    //  -> three FA + one HA
    logic s4_0, c4_0, s4_1, c4_1, s4_2, c4_2, s4_3, c4_3;
    `FA fa4_0 ( .a(pp[4][0]), .b(pp[3][1]), .cin(pp[2][2]), .sum(s4_0), .cout(c4_0) );
    `FA fa4_1 ( .a(s4_0), .b(pp[1][3]), .cin(c3_0), .sum(s4_1), .cout(c4_1) );
    `FA fa4_2 ( .a(s4_1), .b(pp[0][4]), .cin(c3_1), .sum(s4_2), .cout(c4_2) );
    `HA ha4_0 ( .a(s4_2), .b(c3_2), .sum(s4_3), .cout(c4_3) );

    // ---------- Column 5 ----------
    // Bits: pp[5][0], pp[4][1], pp[3][2], pp[2][3], pp[1][4], pp[0][5]
    //  -> four FA + one HA
    logic s5_0, c5_0, s5_1, c5_1, s5_2, c5_2, s5_3, c5_3, s5_4, c5_4;
    `FA fa5_0 ( .a(pp[5][0]), .b(pp[4][1]), .cin(pp[3][2]), .sum(s5_0), .cout(c5_0) );
    `FA fa5_1 ( .a(s5_0), .b(pp[2][3]), .cin(c4_0), .sum(s5_1), .cout(c5_1) );
    `FA fa5_2 ( .a(s5_1), .b(pp[1][4]), .cin(c4_1), .sum(s5_2), .cout(c5_2) );
    `FA fa5_3 ( .a(s5_2), .b(pp[0][5]), .cin(c4_2), .sum(s5_3), .cout(c5_3) );
    `HA ha5_0 ( .a(s5_3), .b(c4_3), .sum(s5_4), .cout(c5_4) );

    // ---------- Column 6 ----------
    // Bits: pp[6][0], pp[5][1], pp[4][2], pp[3][3], pp[2][4], pp[1][5], pp[0][6]
    //  -> five FA + one HA
    logic s6_0, c6_0, s6_1, c6_1, s6_2, c6_2, s6_3, c6_3, s6_4, c6_4, s6_5, c6_5;
    `FA fa6_0 ( .a(pp[6][0]), .b(pp[5][1]), .cin(pp[4][2]), .sum(s6_0), .cout(c6_0) );
    `FA fa6_1 ( .a(s6_0), .b(pp[3][3]), .cin(c5_0), .sum(s6_1), .cout(c6_1) );
    `FA fa6_2 ( .a(s6_1), .b(pp[2][4]), .cin(c5_1), .sum(s6_2), .cout(c6_2) );
    `FA fa6_3 ( .a(s6_2), .b(pp[1][5]), .cin(c5_2), .sum(s6_3), .cout(c6_3) );
    `FA fa6_4 ( .a(s6_3), .b(pp[0][6]), .cin(c5_3), .sum(s6_4), .cout(c6_4) );
    `HA ha6_0 ( .a(s6_4), .b(c5_4), .sum(s6_5), .cout(c6_5) );

    // ---------- Column 7 ----------
    // Bits: pp[7][0], pp[6][1], pp[5][2], pp[4][3], pp[3][4], pp[2][5], pp[1][6], pp[0][7]
    //  -> six FA + one HA
    logic s7_0, c7_0, s7_1, c7_1, s7_2, c7_2, s7_3, c7_3, s7_4, c7_4, s7_5, c7_5, s7_6, c7_6;
    `FA fa7_0 ( .a(pp[7][0]), .b(pp[6][1]), .cin(pp[5][2]), .sum(s7_0), .cout(c7_0) );
    `FA fa7_1 ( .a(s7_0), .b(pp[4][3]), .cin(c6_0), .sum(s7_1), .cout(c7_1) );
    `FA fa7_2 ( .a(s7_1), .b(pp[3][4]), .cin(c6_1), .sum(s7_2), .cout(c7_2) );
    `FA fa7_3 ( .a(s7_2), .b(pp[2][5]), .cin(c6_2), .sum(s7_3), .cout(c7_3) );
    `FA fa7_4 ( .a(s7_3), .b(pp[1][6]), .cin(c6_3), .sum(s7_4), .cout(c7_4) );
    `FA fa7_5 ( .a(s7_4), .b(pp[0][7]), .cin(c6_4), .sum(s7_5), .cout(c7_5) );
    `HA ha7_0 ( .a(s7_5), .b(c6_5), .sum(s7_6), .cout(c7_6) );

    // ---------- Column 8 ----------
    // Bits: pp[7][1], pp[6][2], pp[5][3], pp[4][4], pp[3][5], pp[2][6], pp[1][7]
    //  -> six FA
    logic s8_0, c8_0, s8_1, c8_1, s8_2, c8_2, s8_3, c8_3, s8_4, c8_4, s8_5, c8_5;
    `FA fa8_0 ( .a(pp[7][1]), .b(pp[6][2]), .cin(c7_0), .sum(s8_0), .cout(c8_0) );
    `FA fa8_1 ( .a(s8_0), .b(pp[5][3]), .cin(c7_1), .sum(s8_1), .cout(c8_1) );
    `FA fa8_2 ( .a(s8_1), .b(pp[4][4]), .cin(c7_2), .sum(s8_2), .cout(c8_2) );
    `FA fa8_3 ( .a(s8_2), .b(pp[3][5]), .cin(c7_3), .sum(s8_3), .cout(c8_3) );
    `FA fa8_4 ( .a(s8_3), .b(pp[2][6]), .cin(c7_4), .sum(s8_4), .cout(c8_4) );
    `FA fa8_5 ( .a(s8_4), .b(pp[1][7]), .cin(c7_5), .sum(s8_5), .cout(c8_5) );

    // ---------- Column 9 ----------
    // Bits: pp[7][2], pp[6][3], pp[5][4], pp[4][5], pp[3][6], pp[2][7]
    //  -> five FA
    logic s9_0, c9_0, s9_1, c9_1, s9_2, c9_2, s9_3, c9_3, s9_4, c9_4;
    `FA fa9_0 ( .a(pp[7][2]), .b(pp[6][3]), .cin(c8_0), .sum(s9_0), .cout(c9_0) );
    `FA fa9_1 ( .a(s9_0), .b(pp[5][4]), .cin(c8_1), .sum(s9_1), .cout(c9_1) );
    `FA fa9_2 ( .a(s9_1), .b(pp[4][5]), .cin(c8_2), .sum(s9_2), .cout(c9_2) );
    `FA fa9_3 ( .a(s9_2), .b(pp[3][6]), .cin(c8_3), .sum(s9_3), .cout(c9_3) );
    `FA fa9_4 ( .a(s9_3), .b(pp[2][7]), .cin(c8_4), .sum(s9_4), .cout(c9_4) );

    // ---------- Column 10 ----------
    // Bits: pp[7][3], pp[6][4], pp[5][5], pp[4][6], pp[3][7]
    //  -> four FA
    logic s10_0, c10_0, s10_1, c10_1, s10_2, c10_2, s10_3, c10_3;
    `FA fa10_0 ( .a(pp[7][3]), .b(pp[6][4]), .cin(c9_0), .sum(s10_0), .cout(c10_0) );
    `FA fa10_1 ( .a(s10_0), .b(pp[5][5]), .cin(c9_1), .sum(s10_1), .cout(c10_1) );
    `FA fa10_2 ( .a(s10_1), .b(pp[4][6]), .cin(c9_2), .sum(s10_2), .cout(c10_2) );
    `FA fa10_3 ( .a(s10_2), .b(pp[3][7]), .cin(c9_3), .sum(s10_3), .cout(c10_3) );

    // ---------- Column 11 ----------
    // Bits: pp[7][4], pp[6][5], pp[5][6], pp[4][7]
    //  -> three FA
    logic s11_0, c11_0, s11_1, c11_1, s11_2, c11_2;
    `FA fa11_0 ( .a(pp[7][4]), .b(pp[6][5]), .cin(c10_0), .sum(s11_0), .cout(c11_0) );
    `FA fa11_1 ( .a(s11_0), .b(pp[5][6]), .cin(c10_1), .sum(s11_1), .cout(c11_1) );
    `FA fa11_2 ( .a(s11_1), .b(pp[4][7]), .cin(c10_2), .sum(s11_2), .cout(c11_2) );

    // ---------- Column 12 ----------
    // Bits: pp[7][5], pp[6][6], pp[5][7]
    //  -> two FA
    logic s12_0, c12_0, s12_1, c12_1;
    `FA fa12_0 ( .a(pp[7][5]), .b(pp[6][6]), .cin(c11_0), .sum(s12_0), .cout(c12_0) );
    `FA fa12_1 ( .a(s12_0), .b(pp[5][7]), .cin(c11_1), .sum(s12_1), .cout(c12_1) );

    // ---------- Column 13 ----------
    // Bits: pp[7][6], pp[6][7]
    //  -> one FA
    logic s13_0, c13_0;
    `FA fa13_0 ( .a(pp[7][6]), .b(pp[6][7]), .cin(c12_0), .sum(s13_0), .cout(c13_0) );

    // ---------- Column 14 ----------
    // Bits: pp[7][7] (only one)
    logic c14_0; assign c14_0 = pp[7][7];

    // ----------------------------------------------------------------
    // 3) Assemble the two final rows (sum_row and carry_row)
    //    The carry_row must be **left‑shifted by one** because every
    //    carry produced by a column belongs to the next higher column.
    // ----------------------------------------------------------------
    logic [7:0] low_product;
    logic [15:8] sum_row;
    logic [15:8] carry_row;
    assign low_product[0] = s0_0;                  // column 0
    assign low_product[1] = s1_0;                  // column 1
    assign low_product[2] = s2_1;                  // column 2
    assign low_product[3] = s3_2;                  // column 3
    assign low_product[4] = s4_3;                  // column 4
    assign low_product[5] = s5_4;                  // column 5
    assign low_product[6] = s6_5;                  // column 6
    assign low_product[7] = s7_6;                  // column 7
    assign sum_row[8]  = s8_5;                     // column 8
    assign sum_row[9]  = s9_4;                     // column 9
    assign sum_row[10] = s10_3;                    // column 10
    assign sum_row[11] = s11_2;                    // column 11
    assign sum_row[12] = s12_1;                    // column 12
    assign sum_row[13] = s13_0;                    // column 13
    assign sum_row[14] = c14_0;                    // column 14 (MSB of product)
    assign sum_row[15] = 1'b0;                     // unused top bit (will be zero)

    // Carry row – shift left by one position
    assign carry_row[8]  = c7_6;                   // column 7 carry -> col 8
    assign carry_row[9]  = c8_5;                   // column 8 carry -> col 9
    assign carry_row[10] = c9_4;                   // column 9 carry -> col10
    assign carry_row[11] = c10_3;                  // column10 carry -> col11
    assign carry_row[12] = c11_2;                  // column11 carry -> col12
    assign carry_row[13] = c12_1;                  // column12 carry -> col13
    assign carry_row[14] = c13_0;                  // column13 carry -> col14 
    assign carry_row[15] = 1'b0;                   // top unused bit

    // ----------------------------------------------------------------
    // 4) Final Carry‑Look‑Ahead addition (sum_row + carry_row) 
    // for high-order product bits
    // ----------------------------------------------------------------
    logic [7:0] high_product;   
    logic unused_cout; 

    cla_adder_8 cla (
        .a   (sum_row[15:8]),
        .b   (carry_row[15:8]),
        .cin (1'b0),          // No external carry‑in for a multiplier
        .sum (high_product),
        .cout(unused_cout)   // product already 16‑bit, overflow would be dropped
    );
    assign product[15:0] = { high_product[7:0], low_product[7:0] };

`ifdef RESIDUE3
    // ----------------------------------------------------------------
    // 5) Residue-3 prediction for the product
    // ----------------------------------------------------------------
    logic [1:0] a_res;
    logic [1:0] b_res;

    residue3_gen #(.WIDTH(8)) gen_a_res ( .data_in(a[7:0]), .residue(a_res[1:0]) );
    residue3_gen #(.WIDTH(8)) gen_b_res ( .data_in(b[7:0]), .residue(b_res[1:0]) );

    mod3_multiplier gen_res ( .a(a_res[1:0]), .b(b_res[1:0]), .product(residue_predict[1:0]) );
`endif

    `undef HA
    `undef FA
endmodule : unsigned_multiplier_8x8
