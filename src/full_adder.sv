//===================================================================
// File: full_adder.sv
// Description: 1‑bit full adder (sum, cout)
//===================================================================
`timescale 1ns/1ps
module full_adder (
    input  logic a,
    input  logic b,
    input  logic cin,
    output logic sum,
    output logic cout
);
    assign {cout, sum} = a + b + cin;
endmodule : full_adder
