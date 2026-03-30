// =============================================================================
// Copyright (C) 2026 by TechAnalytics LLC Author: Donald W McCauley
//  Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
//
// File        : tb_cla_adder.sv
// Description : Self-checking testbench for cla_adder.
//               Tests WIDTH = 8, 16, and 24.
//
//   Test plan
//   ─────────
//   1. Corner cases  – all-zeros, all-ones, alternating patterns, cin=0/1
//   2. Overflow cases – max+max, max+1, etc.
//   3. Random vectors – 10 000 per width, results compared to Verilog '+' and '^'
//   4. Parity injection – toggle single a_pty / b_pty bits and verify parity
//      output changes (parity error detection smoke-test)
//
// Compile & simulate (Icarus Verilog):
//   iverilog -g2012 -o cla_adder_sim cla_adder.sv tb_cla_adder.sv && vvp cla_adder_sim
//
// License: This project is released under the: CERN Open Hardware Licence Version 2 - Permissive
//     https://ohwr.org/cern_ohl_p_v2.pdf
// =============================================================================

`timescale 1ns/1ps

module tb_cla_adder;

    // -----------------------------------------------------------------------
    // Macros / helpers
    // -----------------------------------------------------------------------
    int error_count = 0;
    int test_count  = 0;

    // -----------------------------------------------------------------------
    // Task: run one instance of WIDTH-parameterised checks
    // -----------------------------------------------------------------------

    // ── 8-bit instance ──────────────────────────────────────────────────────
    localparam int W8 = 8;
    logic [W8-1:0]      a8, b8, sum8;
    logic [(W8/8)-1:0]  ap8, bp8, pty8;
    logic               cin8, ovfl8;

    cla_adder #(.WIDTH(W8)) dut8 (
        .a(a8), .b(b8), .a_pty(ap8), .b_pty(bp8),
        .cin(cin8), .sum(sum8), .parity(pty8), .ovfl(ovfl8)
    );

    // ── 16-bit instance ─────────────────────────────────────────────────────
    localparam int W16 = 16;
    logic [W16-1:0]     a16, b16, sum16;
    logic [(W16/8)-1:0] ap16, bp16, pty16;
    logic               cin16, ovfl16;

    cla_adder #(.WIDTH(W16)) dut16 (
        .a(a16), .b(b16), .a_pty(ap16), .b_pty(bp16),
        .cin(cin16), .sum(sum16), .parity(pty16), .ovfl(ovfl16)
    );

    // ── 24-bit instance ─────────────────────────────────────────────────────
    localparam int W24 = 24;
    logic [W24-1:0]     a24, b24, sum24;
    logic [(W24/8)-1:0] ap24, bp24, pty24;
    logic               cin24, ovfl24;

    cla_adder #(.WIDTH(W24)) dut24 (
        .a(a24), .b(b24), .a_pty(ap24), .b_pty(bp24),
        .cin(cin24), .sum(sum24), .parity(pty24), .ovfl(ovfl24)
    );

    // -----------------------------------------------------------------------
    // Helper functions – one per supported width (parameterised functions
    // are not supported by iverilog / verilator in this context)
    // -----------------------------------------------------------------------

    function automatic logic [0:0] byte_parity8(input logic [7:0] v);
        byte_parity8[0] = ^v[7:0];
    endfunction

    function automatic logic [1:0] byte_parity16(input logic [15:0] v);
        int b;
        for (b = 0; b < 2; b++) byte_parity16[b] = ^v[8*b +: 8];
    endfunction

    function automatic logic [2:0] byte_parity24(input logic [23:0] v);
        int b;
        for (b = 0; b < 3; b++) byte_parity24[b] = ^v[8*b +: 8];
    endfunction

    // -----------------------------------------------------------------------
    // Check task for generic width – uses string-tagged DUT outputs
    // -----------------------------------------------------------------------

    // ── Per-width check task (uses WIDTH-generic arguments) ─────────────────

    task automatic check8 (
        input logic [7:0]  av, bv,
        input logic        civ,
        input string       label
    );
        logic [8:0]  ref_full;
        logic [7:0]  ref_sum;
        logic        ref_ovfl;
        logic [0:0]  ref_pty;

        a8   = av;
        b8   = bv;
        cin8 = civ;
        ap8  = byte_parity8(av);
        bp8  = byte_parity8(bv);
        #1;  // allow combinational settle

        ref_full = {1'b0, av} + {1'b0, bv} + {8'b0, civ};
        ref_sum  = ref_full[7:0];
        ref_ovfl = ref_full[8];
        ref_pty  = byte_parity8(ref_sum);

        test_count++;
        if (sum8 !== ref_sum) begin
            $display("FAIL [%0s W8]: a=%0h b=%0h cin=%0b | sum exp=%0h got=%0h",
                     label, av, bv, civ, ref_sum, sum8);
            error_count++;
        end
        if (ovfl8 !== ref_ovfl) begin
            $display("FAIL [%0s W8]: a=%0h b=%0h cin=%0b | ovfl exp=%0b got=%0b",
                     label, av, bv, civ, ref_ovfl, ovfl8);
            error_count++;
        end
        if (pty8 !== ref_pty) begin
            $display("FAIL [%0s W8]: a=%0h b=%0h cin=%0b | parity exp=%0b got=%0b",
                     label, av, bv, civ, ref_pty, pty8);
            error_count++;
        end
    endtask

    task automatic check16 (
        input logic [15:0] av, bv,
        input logic        civ,
        input string       label
    );
        logic [16:0] ref_full;
        logic [15:0] ref_sum;
        logic        ref_ovfl;
        logic [1:0]  ref_pty;

        a16   = av;
        b16   = bv;
        cin16 = civ;
        ap16  = byte_parity16(av);
        bp16  = byte_parity16(bv);
        #1;

        ref_full = {1'b0, av} + {1'b0, bv} + {16'b0, civ};
        ref_sum  = ref_full[15:0];
        ref_ovfl = ref_full[16];
        ref_pty  = byte_parity16(ref_sum);

        test_count++;
        if (sum16 !== ref_sum) begin
            $display("FAIL [%0s W16]: a=%0h b=%0h cin=%0b | sum exp=%0h got=%0h",
                     label, av, bv, civ, ref_sum, sum16);
            error_count++;
        end
        if (ovfl16 !== ref_ovfl) begin
            $display("FAIL [%0s W16]: a=%0h b=%0h cin=%0b | ovfl exp=%0b got=%0b",
                     label, av, bv, civ, ref_ovfl, ovfl16);
            error_count++;
        end
        if (pty16 !== ref_pty) begin
            $display("FAIL [%0s W16]: a=%0h b=%0h cin=%0b | parity exp=%0b got=%0b",
                     label, av, bv, civ, ref_pty, pty16);
            error_count++;
        end
    endtask

    task automatic check24 (
        input logic [23:0] av, bv,
        input logic        civ,
        input string       label
    );
        logic [24:0] ref_full;
        logic [23:0] ref_sum;
        logic        ref_ovfl;
        logic [2:0]  ref_pty;

        a24   = av;
        b24   = bv;
        cin24 = civ;
        ap24  = byte_parity24(av);
        bp24  = byte_parity24(bv);
        #1;

        ref_full = {1'b0, av} + {1'b0, bv} + {24'b0, civ};
        ref_sum  = ref_full[23:0];
        ref_ovfl = ref_full[24];
        ref_pty  = byte_parity24(ref_sum);

        test_count++;
        if (sum24 !== ref_sum) begin
            $display("FAIL [%0s W24]: a=%0h b=%0h cin=%0b | sum exp=%0h got=%0h",
                     label, av, bv, civ, ref_sum, sum24);
            error_count++;
        end
        if (ovfl24 !== ref_ovfl) begin
            $display("FAIL [%0s W24]: a=%0h b=%0h cin=%0b | ovfl exp=%0b got=%0b",
                     label, av, bv, civ, ref_ovfl, ovfl24);
            error_count++;
        end
        if (pty24 !== ref_pty) begin
            $display("FAIL [%0s W24]: a=%0h b=%0h cin=%0b | parity exp=%0b got=%0b",
                     label, av, bv, civ, ref_pty, pty24);
            error_count++;
        end
    endtask

    // -----------------------------------------------------------------------
    // Test sequence
    // -----------------------------------------------------------------------
    initial begin
        //$dumpfile("cla_adder.vcd");
        //$dumpvars(0, tb_cla_adder);

        // ── Initialise ──────────────────────────────────────────────────────
        a8=0; b8=0; cin8=0; ap8=0; bp8=0;
        a16=0; b16=0; cin16=0; ap16=0; bp16=0;
        a24=0; b24=0; cin24=0; ap24=0; bp24=0;

        // ════════════════════════════════════════════════════════════════════
        // 1. Corner cases – 8-bit
        // ════════════════════════════════════════════════════════════════════
        $display("── Corner cases W=8 ──");
        check8(8'h00, 8'h00, 0, "zero+zero");
        check8(8'hFF, 8'h00, 0, "max+0");
        check8(8'hFF, 8'h01, 0, "max+1 ovfl");
        check8(8'hFF, 8'hFF, 0, "max+max");
        check8(8'hFF, 8'hFF, 1, "max+max+cin");
        check8(8'hAA, 8'h55, 0, "alt_A+alt_B");
        check8(8'hAA, 8'h55, 1, "alt_A+alt_B+cin");
        check8(8'h0F, 8'hF0, 0, "nibble_lo+hi");
        check8(8'h00, 8'h00, 1, "0+0+cin");
        check8(8'h80, 8'h80, 0, "msb+msb");

        // ── 16-bit ──────────────────────────────────────────────────────────
        $display("── Corner cases W=16 ──");
        check16(16'h0000, 16'h0000, 0, "zero+zero");
        check16(16'hFFFF, 16'h0001, 0, "max+1 ovfl");
        check16(16'hFFFF, 16'hFFFF, 0, "max+max");
        check16(16'hFFFF, 16'hFFFF, 1, "max+max+cin");
        check16(16'hAAAA, 16'h5555, 0, "alt_A+alt_B");
        check16(16'hAAAA, 16'h5555, 1, "alt_A+alt_B+cin");
        check16(16'h00FF, 16'hFF00, 0, "byte_lo+hi");
        check16(16'h0001, 16'hFFFE, 1, "wrap+cin");

        // ── 24-bit ──────────────────────────────────────────────────────────
        $display("── Corner cases W=24 ──");
        check24(24'h000000, 24'h000000, 0, "zero+zero");
        check24(24'hFFFFFF, 24'h000001, 0, "max+1 ovfl");
        check24(24'hFFFFFF, 24'hFFFFFF, 0, "max+max");
        check24(24'hFFFFFF, 24'hFFFFFF, 1, "max+max+cin");
        check24(24'hAAAAAA, 24'h555555, 0, "alt_A+alt_B");
        check24(24'hAAAAAA, 24'h555555, 1, "alt_A+alt_B+cin");
        check24(24'h00FF00, 24'hFF00FF, 0, "byte_pattern");
        check24(24'h000001, 24'hFFFFFE, 1, "wrap+cin");

        // ════════════════════════════════════════════════════════════════════
        // 2. Exhaustive – full 8-bit space with cin=0 and cin=1
        // ════════════════════════════════════════════════════════════════════
        $display("── Exhaustive 8-bit (65536 cases × 2 cin) ──");
        for (int ia = 0; ia < 256; ia++)
            for (int ib = 0; ib < 256; ib++) begin
                check8(ia[7:0], ib[7:0], 1'b0, "exh");
                check8(ia[7:0], ib[7:0], 1'b1, "exh_cin");
            end

        // ════════════════════════════════════════════════════════════════════
        // 3. Random vectors – 16-bit and 24-bit
        // ════════════════════════════════════════════════════════════════════
        $display("── Random 16-bit (100000 vectors) ──");
        repeat (100000) begin
            logic [15:0] ra, rb;
            logic        rci;
            ra  = 16'($urandom);
            rb  = 16'($urandom);
            rci = 1'($urandom_range(0,1));
            check16(ra, rb, rci, "rand");
        end

        $display("── Random 24-bit (100000 vectors) ──");
        repeat (100000) begin
            logic [23:0] ra, rb;
            logic [15:0] tmp_a, tmp_b;
            logic        rci;
            tmp_a = 16'($urandom);
            tmp_b = 16'($urandom);
            ra  = {8'($urandom_range(0,255)), tmp_a};
            rb  = {8'($urandom_range(0,255)), tmp_b};
            rci = 1'($urandom_range(0,1));
            check24(ra, rb, rci, "rand");
        end

        // ════════════════════════════════════════════════════════════════════
        // 4. Parity inject – verify DUT detects a_pty / b_pty mismatch
        //    (smoke-test: if we flip a_pty, output parity must also flip)
        // ════════════════════════════════════════════════════════════════════
        $display("── Parity inject W=8 ──");
        begin
            logic op;
            a8 = 8'hC3; b8 = 8'h3C; cin8 = 0;
            ap8 = byte_parity8(a8);
            bp8 = byte_parity8(b8);
            #1; op = pty8;
            // Flip ap8 – parity should invert
            ap8 = ~ap8; #1;
            test_count++;
            if (pty8 === op)
                $display("FAIL [parity inject W8]: parity did not change on ap8 flip");
            else begin
                // restore
                ap8 = ~ap8; #1;
                if (pty8 !== op)
                    $display("FAIL [parity inject W8]: parity did not restore");
            end
        end

        $display("── Parity inject W=16 ──");
        begin
            logic [1:0] op;
            a16 = 16'hDEAD; b16 = 16'hBEEF; cin16 = 1;
            ap16 = byte_parity16(a16);
            bp16 = byte_parity16(b16);
            #1; op = pty16;
            for (int bit_i = 0; bit_i < 2; bit_i++) begin
                ap16[bit_i] = ~ap16[bit_i]; #1;
                test_count++;
                if (pty16 === op)
                    $display("FAIL [parity inject W16 bit%0d]: parity unchanged", bit_i);
                ap16[bit_i] = ~ap16[bit_i]; #1;
            end
        end

        $display("── Parity inject W=24 ──");
        begin
            logic [2:0] op;
            a24 = 24'hCAFE42; b24 = 24'h123456; cin24 = 0;
            ap24 = byte_parity24(a24);
            bp24 = byte_parity24(b24);
            #1; op = pty24;
            for (int bit_i = 0; bit_i < 3; bit_i++) begin
                bp24[bit_i] = ~bp24[bit_i]; #1;
                test_count++;
                if (pty24 === op)
                    $display("FAIL [parity inject W24 bit%0d]: parity unchanged", bit_i);
                bp24[bit_i] = ~bp24[bit_i]; #1;
            end
        end

        // ════════════════════════════════════════════════════════════════════
        // Summary
        // ════════════════════════════════════════════════════════════════════
        $display("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");
        $display("Tests run : %0d", test_count);
        $display("Errors    : %0d", error_count);
        if (error_count == 0)
            $display("RESULT    : ALL TESTS PASSED ✓");
        else
            $display("RESULT    : FAILED – see messages above");
        $display("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━");

        $finish;
    end

endmodule
