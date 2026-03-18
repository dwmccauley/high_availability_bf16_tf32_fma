//===================================================================
// Copyright (C) 2026 by TechAnalytics LLC Author: Donald W McCauley
//
// File: mod3_adder.sv
// Description: 2-bit modulo-3 adder (aka residue-3 generator)
//
// License: This project is released under the: CERN Open Hardware Licence Version 2 - Permissive
//     https://ohwr.org/cern_ohl_p_v2.pdf
//===================================================================
`timescale 1ns/1ps
module mod3_adder(
    input [1:0] a,
    input [1:0] b,
    output logic [1:0] sum
);
    // Behavioral description of modulo-3 add operation
    assign sum[0] = (~b[1] & b[0] & a[1] & a[0]) | (b[1] & b[0] & ~a[1] & a[0]) | (~b[1] & ~b[0] & ~a[1] & a[0]) | (b[1] & ~b[0] & a[1] & ~a[0]) | (~b[1] & b[0] & ~a[1] & ~a[0]);

    assign sum[1] = (b[1] & ~b[0] & a[1] & a[0]) | (~b[1] & b[0] & ~a[1] & a[0]) | (b[1] & b[0] & a[1] & ~a[0]) | (~b[1] & ~b[0] & a[1] & ~a[0]) | (b[1] & ~b[0] & ~a[1] & ~a[0]);
endmodule : mod3_adder
