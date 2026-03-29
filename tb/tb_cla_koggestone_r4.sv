//=========================================================================================================
// Copyright (C) 2026 by TechAnalytics LLC Author: Donald W McCauley
//
// File: tb_cla_koggestone_r4.sv
//
// Description: Test Bench for a 8/16/24/32‑bit Radix‑4 Kogge‑Stone Carry‑Lookahead Adder
//
// License: This project is released under the: CERN Open Hardware Licence Version 2 - Permissive
//     https://ohwr.org/cern_ohl_p_v2.pdf
//=========================================================================================================
`timescale 1ns/1ps
`define PARITY 

module tb_cla_koggestone_r4;

    // -----------------------------------------------------------------
    // Parameters & local constants
    // WIDTHs of 16, 24 or 32 bits are supported
    // -----------------------------------------------------------------
    //localparam int WIDTH       = 32;
    //localparam int WIDTH       = 24;
    localparam int WIDTH       = 16;
    localparam int NUM_VECTORS = 1_000_000;   // random vectors

    // -----------------------------------------------------------------
    // Optional SEED from the command line
    // -----------------------------------------------------------------
    integer seed;
    initial begin
        if ($value$plusargs("SEED=%d", seed)) begin
            $display("Running with WIDTH: %0d Seed: %0d", WIDTH, seed);
            void'($urandom(seed));
        end else $display("Running with WIDTH: %0d", WIDTH);
    end

    // -----------------------------------------------------------------
    // DUT interface
    // -----------------------------------------------------------------
    logic [WIDTH-1:0] a, b;
`ifdef PARITY
    logic [(WIDTH/8)-1:0] a_pty;  // a parity 
    logic [(WIDTH/8)-1:0] b_pty;  // b parity 
`endif
    logic             cin;    // carry in 
    logic [WIDTH-1:0] sum;
`ifdef PARITY
    logic [(WIDTH/8-1):0] parity; // predicted sum parity
`endif
    logic             ovfl;   // overflow

    // -----------------------------------------------------------------
    // DUT instantiation
    // -----------------------------------------------------------------
    cla_koggestone_r4 #(.WIDTH(WIDTH)) dut (
        .a   (a),
        .b   (b),
`ifdef PARITY
        .a_pty (a_pty),
        .b_pty (b_pty),
`endif
        .cin (cin),
        .sum (sum),
`ifdef PARITY
        .parity (parity),
`endif
        .ovfl (ovfl)
    );

    // -----------------------------------------------------------------
    // Scoreboard & counters
    // -----------------------------------------------------------------
    int unsigned tests = 0;
    int unsigned pass = 0;
    int unsigned fail = 0;

    // -----------------------------------------------------------------
    // Corner‑case block 
    // -----------------------------------------------------------------

    // ---- generic constants that depend only on WIDTH ------------
    localparam unsigned POS_MAX = (1 << (WIDTH-1)) - 1;   // +max  (0x7fffffff for 32‑bit)
    localparam unsigned NEG_MIN = 1 << (WIDTH-1);        // -min  (0x80000000 for 32‑bit)
    localparam unsigned ALL_ONES = {WIDTH{1'b1}};        // -1    (all bits = 1)
    localparam unsigned ONE      = 1;                   // literal 1 (zero‑extended)

    // A handful of directed corner cases
    typedef struct packed {
        logic [WIDTH-1:0] a;
        logic [WIDTH-1:0] b;
        logic             cin;
    } corner_t;

    corner_t corners[6] = '{
        '{POS_MAX, ONE, 1'b0},      // +max + 1 → overflow
        '{NEG_MIN, ALL_ONES, 1'b0}, // -min - 1 → overflow  (NEG_MIN + ALL_ONES)
        '{'0, '0, 1'b0},            // zero + zero
        '{ALL_ONES, ONE, 1'b0},     // -1 + 1 → zero, no overflow
        '{POS_MAX, POS_MAX, 1'b0},  // +max + +max → overflow
        '{8'h6, 20'h50c19, 1'b1}    // 0x6, 0x50c19, cin
    };

    // -----------------------------------------------------------------
    // Corner cases first than random stimulus
    // -----------------------------------------------------------------
    logic [WIDTH-1:0] sum_ref;
`ifdef PARITY
    logic [(WIDTH/8-1):0] parity_ref;
`endif
    logic             ovfl_ref;

    initial begin
        repeat (NUM_VECTORS) begin
            if (tests < $size(corners)) begin 
                corner_t cur;     
                cur = corners[tests];
                a   = cur.a;
                b   = cur.b;
                cin = cur.cin;
            end else begin
                a   = $urandom_range((1<<WIDTH)-1, 1);
                b   = $urandom_range((1<<WIDTH)-1, 1);
                cin = $urandom_range(1, 0);
            end   
`ifdef PARITY
            if (WIDTH > 24) begin a_pty[3] = ^a[31:24]; b_pty[3] = ^b[31:24]; end
            if (WIDTH > 16) begin a_pty[2] = ^a[23:16]; b_pty[2] = ^b[23:16]; end
            if (WIDTH >  8) begin a_pty[1] = ^a[15:8];  b_pty[1] = ^b[15:8] ; end
                                  a_pty[0] = ^a[7:0];   b_pty[0] = ^b[7:0];
`endif

            #0.1ns;                // let combinational logic settle

            reference_model(a, b, cin, 
                sum_ref,
`ifdef PARITY
                parity_ref,
`endif
                ovfl_ref
            );

            if ( (sum !== sum_ref) || 
`ifdef PARITY
                 (parity !== parity_ref) ||
`endif
                 (ovfl !== ovfl_ref) ) begin
                fail = fail + 1;
                $display("ERROR at vector %0d:", tests);
                $display("    a   = 0x%0h (%0d)", a, $signed(a));
                $display("    b   = 0x%0h (%0d)", b, $signed(b));
                $display("    cin = %0d", cin);
                $display("    DUT sum = 0x%0h (%0d)", sum, $signed(sum));
                $display("    REF sum = 0x%0h (%0d)", sum_ref, $signed(sum_ref));
                $display("    DUT ovfl = %b REF ovfl = %b", ovfl, ovfl_ref);
`ifdef PARITY
                $display("    DUT Parity = %0b Ref Parity = %0b", parity, parity_ref);
`endif
            end else pass = pass + 1;
            tests = tests + 1;
        end

        if (fail == 0) 
            $display("\n*** PASS ***  All %0d test vectors matched the reference model.", tests);
        else
            $display("\n*** FAIL ***  %0d mismatches out of %0d test vectors.", fail, tests);
    end

    // -----------------------------------------------------------------
    // Reference model
    // -----------------------------------------------------------------
    task reference_model (
       // localparam int WIDTH       = 16;
        input  logic [WIDTH-1:0] a,
        input  logic [WIDTH-1:0] b,
        input  logic             cin,
        output logic [WIDTH-1:0] sum,
`ifdef PARITY
        output logic [(WIDTH/8-1):0] parity, // parity
`endif
        output logic            ovfl
    );
        logic signed [WIDTH:0] tmp;
        tmp = $signed({1'b0, a}) + $signed({1'b0, b}) + { {WIDTH{1'b0}}, cin };
        sum = tmp[WIDTH-1:0];
        ovfl = tmp[WIDTH] & ~cin;

`ifdef PARITY
        // --- Byte Parity Generation ---
        if (WIDTH > 24) parity[3] = ^sum[31:24]; 
        if (WIDTH > 16) parity[2] = ^sum[23:16]; 
        if (WIDTH > 8)  parity[1] = ^sum[15:8]; 
                        parity[0] = ^sum[7:0]; 
`endif
    endtask : reference_model
endmodule : tb_cla_koggestone_r4


