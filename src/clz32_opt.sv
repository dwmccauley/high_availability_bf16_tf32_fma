`timescale 1ns/1ps
//===================================================================
// Copyright (C) 2026 by TechAnalytics LLC Author: Donald W McCauley
//
// File: clz32_opt.sv
// Description: 32‑bit Leading‑Zero Detector – log2(N) tree
//
// License: This project is released under the: CERN Open Hardware Licence Version 2 - Permissive
//     https://ohwr.org/cern_ohl_p_v2.pdf
//===================================================================
module clz32_opt (
    input  logic [31:0] data,
    output logic [5:0]  count   // 0 … 32
);
    // -----------------------------------------------------------
    // 2‑bit encoder → {valid, zero_cnt}
    // zero_cnt fits in *5* bits for the whole tree (max 31)
    // -----------------------------------------------------------
    function automatic [5:0] enc2 (input logic [1:0] s);
        // return {valid, zero_cnt[4:0]}
        casez (s)
            2'b1?   : enc2 = {1'b1, 5'd0};   // "1x" → 0 leading zeros
            2'b01   : enc2 = {1'b1, 5'd1};   // "01" → 1 leading zero
            default : enc2 = {1'b0, 5'd2};   // "00" → 2 leading zeros, not valid
        endcase
    endfunction

    // -----------------------------------------------------------
    // Level‑0 : 16 × 2‑bit slices (taken from the *MSB* side)
    // -----------------------------------------------------------
    logic [5:0] lvl0 [15:0];
    genvar i;
    generate
        for (i = 0; i < 16; i = i + 1) begin : slice2
            // data[31 -: 2] is bits 31:30, data[29 -: 2] is bits 29:28, …
            assign lvl0[i] = enc2( data[31 - 2*i -: 2] );
        end
    endgenerate

    // -----------------------------------------------------------
    // combine({v0,z0},{v1,z1})
    //   if v0 == 1 → propagate the more‑significant block
    //   else       → {v1, z0+z1}
    // -----------------------------------------------------------
    function automatic [5:0] combine (input [5:0] a, input [5:0] b);
        // a = {v0, z0[4:0]}, b = {v1, z1[4:0]}
        if (a[5])               // a.valid ? 
            combine = a;        // most‑significant block already has a ‘1’
        else
            combine = {b[5], a[4:0] + b[4:0]}; // add the leading‑zero counts
    endfunction

    // -----------------------------------------------------------
    // Level‑1 : 8 groups of 4 bits
    // -----------------------------------------------------------
    logic [5:0] lvl1 [7:0];
    generate
        for (i = 0; i < 8; i = i + 1) begin : lvl1_gen
            // note: the *more‑significant* block is the one with the lower index
            assign lvl1[i] = combine( lvl0[2*i] , lvl0[2*i+1] );
        end
    endgenerate

    // -----------------------------------------------------------
    // Level‑2 : 4 groups of 8 bits
    // -----------------------------------------------------------
    logic [5:0] lvl2 [3:0];
    generate
        for (i = 0; i < 4; i = i + 1) begin : lvl2_gen
            assign lvl2[i] = combine( lvl1[2*i] , lvl1[2*i+1] );
        end
    endgenerate

    // -----------------------------------------------------------
    // Level‑3 : 2 groups of 16 bits
    // -----------------------------------------------------------
    logic [5:0] lvl3 [1:0];
    assign lvl3[0] = combine( lvl2[0] , lvl2[1] );
    assign lvl3[1] = combine( lvl2[2] , lvl2[3] );

    // -----------------------------------------------------------
    // Level‑4 : whole 32‑bit word
    // -----------------------------------------------------------
    logic [5:0] final_res;
    assign final_res = combine( lvl3[0] , lvl3[1] );

    // -----------------------------------------------------------
    // Final result: if the word is all‑zero we must output 32
    // -----------------------------------------------------------
    // final_res[6] == valid (1 → there is a ‘1’, 0 → all‑zero)
    assign count = final_res[5] ? {1'b0, final_res[4:0]}   // valid → use accumulated zero count
                               : 6'd32;                    // not valid → all‑zero
endmodule : clz32_opt
