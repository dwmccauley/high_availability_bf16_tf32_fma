//===================================================================
// File: half_adder.sv
// Description: 1‑bit half adder (sum, cout)
//===================================================================
`timescale 1ns/1ps
module half_adder (
    input  logic a,
    input  logic b,
    output logic sum,
    output logic cout
);
    assign sum  = a ^ b;
    assign cout = a & b;
endmodule : half_adder
