// =============================================================================
// Copyright (C) 2026 by TechAnalytics LLC Author: Donald W McCauley
//  Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
//
// File        : cla_adder.sv
// Description : Parameterized Carry-Lookahead Adder (CLA) with Byte Parity
//               Prediction.  Supports WIDTH = 8, 16, or 24 bits.
//
// License: This project is released under the: CERN Open Hardware Licence Version 2 - Permissive
//     https://ohwr.org/cern_ohl_p_v2.pdf
//
// Parity optimisation (Shannon expansion) suggested by Claude Sonnet 4.6
//
// Parameters
//   WIDTH     – Operand width.  Must be 8, 16, or 24.
//
// Ports
//   a         – Addend A                        [WIDTH-1:0]
//   b         – Addend B                        [WIDTH-1:0]
//   a_pty     – Even-parity bits for each byte  [(WIDTH/8)-1:0]
//                 a_pty[i] == ^a[8*i+7 : 8*i]
//   b_pty     – Even-parity bits for each byte  [(WIDTH/8)-1:0]
//                 b_pty[i] == ^b[8*i+7 : 8*i]
//   cin       – Carry-in
//   sum       – Result A + B + cin              [WIDTH-1:0]
//   parity    – Predicted even-parity per byte  [(WIDTH/8)-1:0]
//               of sum (see theory below)
//   ovfl      – Unsigned overflow  (carry-out of MSB)
//
// ── Carry-Lookahead Theory ────────────────────────────────────────────────────
//
//   Bit-level generate / propagate:
//     g[i] = a[i] & b[i]          (bit i generates a carry)
//     p[i] = a[i] ^ b[i]          (bit i propagates a carry)
//     sum[i] = p[i] ^ c[i]
//     c[i+1] = g[i] | (p[i] & c[i])
//
//   Group (4-bit block) generate / propagate  (one CLA group, bits k..k+3):
//     G = g[3] | p[3]&g[2] | p[3]&p[2]&g[1] | p[3]&p[2]&p[1]&g[0]
//     P = p[3] & p[2] & p[1] & p[0]
//     c[k+4] = G | P & c[k]
//
//   Carries within the group are computed in parallel:
//     c[k+1] = g[k+0] | p[k+0] & c[k]
//     c[k+2] = g[k+1] | p[k+1]&g[k+0] | p[k+1]&p[k+0]&c[k]
//     c[k+3] = g[k+2] | p[k+2]&g[k+1] | p[k+2]&p[k+1]&g[k+0]
//              | p[k+2]&p[k+1]&p[k+0]&c[k]
//
//   For WIDTH=8  : two 4-bit CLA groups; carry between them is resolved by
//                  one second-level lookahead.
//   For WIDTH=16 : four 4-bit groups + one 4-input second-level lookahead.
//   For WIDTH=24 : six 4-bit groups + a 6-input second-level lookahead
//                  (G5..G0, P5..P0) yielding carries c[4], c[8], c[12],
//                  c[16], c[20].  Implemented flat via the same
//                  group_carry_lookahead function parameterised to 6 groups.
//
// ── Byte Parity Prediction Theory ────────────────────────────────────────────
//
//   For byte b of the sum (bits [8b+7 : 8b]):
//     sum_byte  = a_byte ^ b_byte ^ carry_vec    (carry_vec = 8 carry-ins)
//
//   Parity of sum_byte:
//     ^sum_byte = ^a_byte ^ ^b_byte ^ ^carry_vec
//               = a_pty[b] ^ b_pty[b] ^ (^carry_vec)
//
//   carry_vec for byte b:  { c[8b+7], c[8b+6], ..., c[8b+1], c[8b] }
//                          (c[8b] is the carry-in to the byte)
//
//   XOR of carry_vec exploits carry-chain telescoping:
//     ^carry_vec = c[8b] ^ c[8b+1] ^ ... ^ c[8b+7]
//
//   This is computed purely from g[], p[], and c[8b] — no ripple needed.
//
// Design Note: for 16-bit adder, sum & parity both ~8 logic levels in ASAP7
// =============================================================================

`timescale 1ns/1ps
`define PARITY

module cla_adder #(
    parameter int WIDTH = 16   // 8, 16, or 24 only
) (
    input  logic [WIDTH-1:0]       a,
    input  logic [WIDTH-1:0]       b,
`ifdef PARITY
    input  logic [(WIDTH/8)-1:0]   a_pty,   // even parity per byte of a
    input  logic [(WIDTH/8)-1:0]   b_pty,   // even parity per byte of b
`endif
    input  logic                   cin,
    output logic [WIDTH-1:0]       sum,
`ifdef PARITY
    output logic [(WIDTH/8)-1:0]   parity,  // predicted even parity per byte of sum
`endif
    output logic                   ovfl     // unsigned overflow (carry-out)
);

    // -------------------------------------------------------------------------
    // Parameter legality check (elaboration-time)
    // -------------------------------------------------------------------------
    initial begin
        if (WIDTH != 8 && WIDTH != 16 && WIDTH != 24) begin
            $fatal(1, "cla_adder: WIDTH must be 8, 16, or 24 (got %0d)", WIDTH);
        end
    end

    // -------------------------------------------------------------------------
    // Local parameters
    // -------------------------------------------------------------------------
    localparam int NBYTES  = WIDTH / 8;           // 1, 2, or 3
    localparam int NGROUPS = WIDTH / 4;           // 2, 4, or 6  (4-bit CLA groups)

    // -------------------------------------------------------------------------
    // Bit-level generate / propagate
    // -------------------------------------------------------------------------
    logic [WIDTH-1:0] g;   // bit generate
    logic [WIDTH-1:0] p;   // bit propagate

    assign g = a & b;
    assign p = a ^ b;

    // -------------------------------------------------------------------------
    // 4-bit group generate / propagate (first level CLA)
    //
    //   For group k (covering bits [4k+3 : 4k]):
    //     G[k] = g3 | p3&g2 | p3&p2&g1 | p3&p2&p1&g0
    //     P[k] = p3 & p2 & p1 & p0
    // -------------------------------------------------------------------------
    logic [NGROUPS-1:0] G1;   // group generate
    logic [NGROUPS-1:0] P1;   // group propagate

    genvar k;
    generate
        for (k = 0; k < NGROUPS; k++) begin : gen_G1P1
            assign G1[k] = g[4*k+3]
                         | (p[4*k+3] & g[4*k+2])
                         | (p[4*k+3] & p[4*k+2] & g[4*k+1])
                         | (p[4*k+3] & p[4*k+2] & p[4*k+1] & g[4*k+0]);
            assign P1[k] = p[4*k+3] & p[4*k+2] & p[4*k+1] & p[4*k+0];
        end
    endgenerate

    // -------------------------------------------------------------------------
    // Second-level lookahead: derive carry-in to each 4-bit group
    //
    //   c_group[0]   = cin
    //   c_group[k+1] = G1[k] | P1[k] & c_group[k]
    //
    //   The assign chain is equivalent to the fully-expanded parallel form;
    //   synthesis flattens it to parallel lookahead.  Individual assign nets
    //   avoid monolithic always_comb re-execution during simulation.
    // -------------------------------------------------------------------------
    logic [NGROUPS:0] c_group;   // c_group[k] = carry-in to group k

    assign c_group[0] = cin;
    generate
        for (k = 0; k < NGROUPS; k++) begin : gen_cgroup
            assign c_group[k+1] = G1[k] | (P1[k] & c_group[k]);
        end
    endgenerate

    assign ovfl = c_group[NGROUPS];

    // -------------------------------------------------------------------------
    // Bit-level carries within each group (parallel, driven by c_group)
    //
    //   c_bit[4k]   = c_group[k]
    //   c_bit[4k+1] = g[4k]   | p[4k]   & c_group[k]
    //   c_bit[4k+2] = g[4k+1] | p[4k+1] & g[4k]   | p[4k+1]&p[4k]   & c_group[k]
    //   c_bit[4k+3] = g[4k+2] | p[4k+2] & g[4k+1] | p[4k+2]&p[4k+1] & g[4k]
    //                          | p[4k+2]&p[4k+1]&p[4k] & c_group[k]
    // -------------------------------------------------------------------------
    logic [WIDTH-1:0] c_bit;   // c_bit[i] = carry-in to bit i

    generate
        for (k = 0; k < NGROUPS; k++) begin : gen_cbit
            assign c_bit[4*k+0] = c_group[k];

            assign c_bit[4*k+1] = g[4*k+0]
                                 | (p[4*k+0] & c_group[k]);

            assign c_bit[4*k+2] = g[4*k+1]
                                 | (p[4*k+1] & g[4*k+0])
                                 | (p[4*k+1] & p[4*k+0] & c_group[k]);

            assign c_bit[4*k+3] = g[4*k+2]
                                 | (p[4*k+2] & g[4*k+1])
                                 | (p[4*k+2] & p[4*k+1] & g[4*k+0])
                                 | (p[4*k+2] & p[4*k+1] & p[4*k+0] & c_group[k]);
        end
    endgenerate

    // -------------------------------------------------------------------------
    // Sum bits
    //   sum[i] = p[i] ^ c_bit[i]   (since p[i] = a[i]^b[i])
    // -------------------------------------------------------------------------
    assign sum = p ^ c_bit;

`ifdef PARITY
    // -------------------------------------------------------------------------
    // Byte Parity Prediction  – Shannon-expansion optimisation
    //
    //   For byte n (bits [8n+7 : 8n]):
    //
    //     parity[n] = a_pty[n] ^ b_pty[n] ^ carry_xor[n]
    //
    //   where carry_xor[n] = XOR of c_bit[8n..8n+7].
    //
    //   Naïve XOR-of-c_bit chain synthesises to ~5 serial XOR levels on the
    //   critical path.  Instead, apply Shannon expansion on the two group
    //   carry-ins ck0 = c_group[2n] and ck1 = c_group[2n+1]:
    //
    //     carry_xor_lo = K_lo ^ (M_lo & ck0)
    //     carry_xor_hi = K_hi ^ (M_hi & ck1)
    //     carry_xor    = carry_xor_lo ^ carry_xor_hi
    //
    //   K_* and M_* depend only on g[] and p[] (computed in parallel with
    //   the carry chain).  The post-carry critical path from the bottleneck
    //   signal ck1 is then 1 AND + 2 XOR instead of 5 serial XOR/XNOR stages.
    //
    //   Derivation for the low 4-bit group (bits 8n..8n+3):
    //     c[8n]   = ck0
    //     c[8n+1] = g0 | (p0 & ck0)
    //     c[8n+2] = g1 | (p1&g0) | (p1&p0&ck0)
    //     c[8n+3] = g2 | (p2&g1) | (p2&p1&g0) | (p2&p1&p0&ck0)
    //
    //     K_lo = carry_xor_lo(ck0=0)
    //          = 0 ^ g0 ^ (g1|p1&g0) ^ (g2|p2&g1|p2&p1&g0)
    //     M_lo = carry_xor_lo(ck0=0) ^ carry_xor_lo(ck0=1)
    //          = K_lo ^ [1 ^ (g0|p0) ^ (g1|p1&g0|p1&p0)
    //                      ^ (g2|p2&g1|p2&p1&g0|p2&p1&p0)]
    //
    //   High group is identical in structure with base index 8n+4.
    // -------------------------------------------------------------------------

    // Shannon precomputed terms – functions of g[] and p[] only, no carry inputs
    logic [NBYTES-1:0] parity_K_lo, parity_M_lo;
    logic [NBYTES-1:0] parity_K_hi, parity_M_hi;

    genvar n;
    generate
        for (n = 0; n < NBYTES; n++) begin : gen_parity

            // Low 4-bit group of byte n (bits 8n..8n+3, group index 2n)
            // K_lo: XOR of {c[8n], c[8n+1], c[8n+2], c[8n+3]} with ck0 = 0
            assign parity_K_lo[n] =
                  g[8*n+0]
                ^ (g[8*n+1] | (p[8*n+1] & g[8*n+0]))
                ^ (g[8*n+2] | (p[8*n+2] & g[8*n+1])
                             | (p[8*n+2] & p[8*n+1] & g[8*n+0]));

            // M_lo: K_lo XOR (same XOR with ck0 = 1)
            assign parity_M_lo[n] = parity_K_lo[n]
                ^ (1'b1
                   ^ (g[8*n+0] | p[8*n+0])
                   ^ (g[8*n+1] | (p[8*n+1] & g[8*n+0])
                                | (p[8*n+1] & p[8*n+0]))
                   ^ (g[8*n+2] | (p[8*n+2] & g[8*n+1])
                                | (p[8*n+2] & p[8*n+1] & g[8*n+0])
                                | (p[8*n+2] & p[8*n+1] & p[8*n+0])));

            // High 4-bit group of byte n (bits 8n+4..8n+7, group index 2n+1)
            assign parity_K_hi[n] =
                  g[8*n+4]
                ^ (g[8*n+5] | (p[8*n+5] & g[8*n+4]))
                ^ (g[8*n+6] | (p[8*n+6] & g[8*n+5])
                             | (p[8*n+6] & p[8*n+5] & g[8*n+4]));

            assign parity_M_hi[n] = parity_K_hi[n]
                ^ (1'b1
                   ^ (g[8*n+4] | p[8*n+4])
                   ^ (g[8*n+5] | (p[8*n+5] & g[8*n+4])
                                | (p[8*n+5] & p[8*n+4]))
                   ^ (g[8*n+6] | (p[8*n+6] & g[8*n+5])
                                | (p[8*n+6] & p[8*n+5] & g[8*n+4])
                                | (p[8*n+6] & p[8*n+5] & p[8*n+4])));

            // Final parity: critical path from ck1 = c_group[2n+1] is 1 AND + 2 XOR
            assign parity[n] = a_pty[n] ^ b_pty[n]
                             ^ parity_K_lo[n] ^ (parity_M_lo[n] & c_group[2*n])
                             ^ parity_K_hi[n] ^ (parity_M_hi[n] & c_group[2*n+1]);
        end
    endgenerate
`endif

endmodule
