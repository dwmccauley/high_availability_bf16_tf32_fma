//===================================================================
// File: tb_unsigned_multiplier_8x8.v
// Description: Simple test‑bench that verifies the 8x8 multiplier
//              against the built‑in '*' operator for a set of vectors.
//===================================================================
`timescale 1ns/1ps

module tb_unsigned_multiplier_8x8;
    // DUT signals
    logic  [7:0] a, b;
    logic [15:0] product;
    logic [1:0] residue;

    // DUT instantiation
    unsigned_multiplier_8x8 dut (.*); // connects a,b,product,residue

    logic  [15:0] expected;
    logic  [1:0] expected_residue;
    integer pass = 0;
    integer fail = 0;
    integer seed = 12345;
    logic init;  // 0 = normal operation, 1 = reset‑like condition

    // 1) Simple corner cases
    initial begin 
        init = 1'b1;
        a = '0;
        b = '0;
        #0;
        init = 1'b0;
    end

    // ---------------------------------------------------------------
    // 1) Simple corner cases
    // ---------------------------------------------------------------
    initial begin : simple
        #10
        $display("\n=== Corner‑case test vectors ===");
        a = 8'd0; b = 8'd0;   #0 check();
        a = 8'd0; b = 8'd55;  #1 check();
        a = 8'd127; b = 8'd0; #1 check();
        a = 8'd2; b = 8'd7; #1 check();
        a = 8'd8; b = 8'd2; #1 check();
        a = 8'd15; b = 8'd15; #1 check();
        a = 8'd16; b = 8'd16; #1 check();
        a = 8'd31; b = 8'd31; #1 check();
        a = 8'd255; b = 8'd1; #1 check();
        a = 8'd255; b = 8'd255; #1 check();
        a = 8'd123; b = 8'd45; #1 check();
    end : simple

    // ---------------------------------------------------------------
    // 2) Randomised vectors (100 iterations)
    // ---------------------------------------------------------------
    initial begin : random
        integer i;
        #10000; // give corner‑case part some time
        $display("\n=== Randomised test (100 vectors) ===");
        for (i = 0; i < 100; i = i + 1) begin
            a = $random(seed);
            b = $random(seed);
            #1 check();
        end
        if (fail == 0) begin
            $display("\nAll %0d tests passed.\n", pass);
        end
        else
        begin
            $display("\n%0d tests passed; %0d tests failed.\n", pass, fail);
        end
    end : random

    // ---------------------------------------------------------------
    // 3) all vectors (65536=256*256 iterations)
    // ---------------------------------------------------------------
    initial begin : comprehensive
        integer i, j;
        #800000; // give random tests some time. (Roughly 4000 ps per test case.)
        $display("\n=== comprehensive test (65536 vectors) ===");
        for (i = 0; i < 256; i = i + 1) begin
            for (j = 0; j < 256; j = j + 1) begin
                a = i;
                b = j;
                #1 check();
            end
        end
        if (fail == 0) begin
            $display("\nAll %0d tests passed.\n", pass);
        end
        else
        begin
            $display("\n%0d tests passed; %0d tests failed.\n", pass, fail);
        end
        $finish;
    end : comprehensive

    // ---------------------------------------------------------------
    // 4) Checker task
    // ---------------------------------------------------------------
    task check;
        begin
            expected = a * b;   // built‑in multiplication (reference)
            expected_residue = (a * b) % 3;
            if ( (product !== expected) || (residue !== expected_residue) ) begin
                fail=fail+1;
                $display("FAIL: %0d * %0d = %0h (exp %0h). Residue %0b (exp %0b)", a, b, product, expected, residue, expected_residue);
            end else begin
                pass=pass+1;
//                $display("PASS: %0d * %0d = %0h. Residue %0b", a, b, product, residue);
            end
        end
    endtask
endmodule
