//===================================================================
// Copyright (C) 2026 by TechAnalytics LLC Author: Donald W McCauley
//
// File: mod3_adder.sv
// Description: 2-bit modulo-3 added (aka residue-3 generator)
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

endmodule
