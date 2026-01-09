//===================================================================
// Copyright (C) 2026 by TechAnalytics LLC Author: Donald W McCauley
//
// File: mod3_multiplier.sv
// Description: 2-bit modulo-3 multiplier 
//===================================================================

`timescale 1ns/1ps
module mod3_multiplier(
    input [1:0] a,
    input [1:0] b,
    output logic [1:0] product 
);

    // Behavioral description of modulo-3 multiplier operation

    assign product[0] = (~b[1] & b[0] & ~a[1] & a[0]) | (b[1] & ~b[0] & a[1] & ~a[0]);

    assign product[1] = (b[1] & ~b[0] & ~a[1] & a[0]) | (~b[1] & b[0] & a[1] & ~a[0]);

endmodule
