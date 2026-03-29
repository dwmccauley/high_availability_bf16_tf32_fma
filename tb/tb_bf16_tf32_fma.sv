//=========================================================================================================
// Copyright (C) 2026 by TechAnalytics LLC Author: Donald W McCauley
//
// File: tb_bf16_tf32_fma.sv
//
// Description: Test Bench for a bfloat16 × bfloat16 + TensorFloat‑32 → TensorFloat‑32 floating-point multiply-adder unit.
//
// License: This project is released under the: CERN Open Hardware Licence Version 2 - Permissive
//     https://ohwr.org/cern_ohl_p_v2.pdf
//=========================================================================================================
`timescale 1ns/1ps
`define RESIDUE3
`define PARITY
`undef RESIDUE3_OR_PARITY

import float_formats::*;

module tb_bf16_tf32_fma;
  localparam int NUM_VECTORS = 10_000_000;   // random vectors
  localparam int ADDER_WIDTH = 16;
  integer seed;
  integer test_number;
  bit debug = 0;
  initial begin
    // 1. Get seed from command line (e.g., +SEED=123)
    if ($value$plusargs("SEED=%d", seed)) begin
      $display("Running with Seed: %0d", seed);
      void'($urandom(seed));
    end 
    if ($test$plusargs("DEBUG")) begin
      debug = 1;
      $display("Debug enabled");
    end 
    if ($value$plusargs("TEST#=%d", test_number)) begin
      debug = 1;
      $display("Debug enabled, Test# %d", test_number);
    end 
  end

  // DUT
  logic [15:0] a_i, b_i;
  logic [31:0] c_i;
  logic [31:0] product_tf32;
`ifdef RESIDUE3
  `define RESIDUE3_OR_PARITY
  logic [1:0] residue_predict;
  logic [1:0] residue;
`endif
  logic [31:0] sum_tf32;
`ifdef PARITY
  `define RESIDUE3_OR_PARITY
  logic [(ADDER_WIDTH/8-1):0] parity_predict;
  logic [(ADDER_WIDTH/8-1):0] parity;
`endif
  logic [7:0] flags;

  ha_bf16_tf32_fma dut (
    .a_bfloat (a_i),
    .b_bfloat (b_i),
    .c_tf32 (c_i),
    .product_tf32 (product_tf32),
`ifdef RESIDUE3
    .residue_predict (residue_predict),
    .residue (residue),
`endif
    .result_tf32 (sum_tf32),
`ifdef PARITY
    .parity_predict (parity_predict),
    .parity (parity),
`endif
    .flags (flags)
  );

    integer tests = 0;
    integer pass = 0;
    integer fail = 0;
`ifdef RESIDUE3
    integer residue_pass = 0;
    integer residue_fail = 0;
`endif
`ifdef PARITY
    integer parity_pass = 0;
    integer parity_fail = 0;
`endif
    integer prod_ovfl = 0; // Product exponent >= ~+/-3.4e+38 (or +/-2**128). 
    integer prod_uflw = 0; // Product exponent < ~+/-1.7e-38 (or +/-2**-126). Product fraction set to zero;
    integer prod_zero = 0; // Product = zero. Should be extremely rare.
    integer prod_sub = 0;  // Product subnormal
    integer sum_ovfl = 0;  
    integer sum_uflw = 0; 
    integer sum_zero = 0;
    integer sum_sub = 0;

    typedef struct packed {
        logic [15:0] a;
        logic [15:0] b;
        logic [31:0] c;
    } corner_t;

    corner_t corners[9] = '{
                                             // Result/Sum corner cases:
        '{16'hcbf3, 16'hbe39, 32'h4b284000}, //   Product=4aaf8000 Result=4b800000 // both operands positive. No flags set.
        '{16'h45c5, 16'hb6a0, 32'hba9c0000}, //   Product=bcf64000 Result=bd000000 // both operands negative. No flags set.
        '{16'h4166, 16'h467d, 32'hc8634000}, //   Product=48634000 Result=00000000 // TODO #2: (dut)Result negative zero. ExpResult positive zero. sum_zero flag set.
        '{16'hc8c9, 16'h3f5d, 32'h48ad8000}, //   Product=c8ad8000 Result=00000000 // sum_zero flag set.
                                             // Product/Multiplier exponent corner cases:
        '{16'h9884, 16'ha603, 32'h51a3e000}, //   Product=00000000 (0)                    // prod_uflw
        '{16'h6041, 16'he0fe, 32'hc9dba000}, //   Product=ff800000 (-inf) Result=ff800000 // prod_ovfl & sum_ovfl
        '{16'hdd78, 16'he93b, 32'hc2ea6000}, //   Product=7f800000 (inf)  Result=7f800000 // prod_ovfl & sum_ovfl
        '{16'h8fe2, 16'h2a5b, 32'hb48e4000}, //   Product=80000000 (-0)                   // prod_uflw
                                             // Product/Sum subnormal corner cases: TODO #3: add prod_zero, sum_sub & sum_uflw corner cases
        '{16'ha561, 16'h9a13, 32'h3a6d4000} //   Product=00012000                  // prod_sub flag set.
        //'{16'h0001, 16'h3f80, 32'h00001000}  //   2^-133 (0.0078125*2^-126) * 1.0 + 0.0009765625^-126. TODO #4: Product=00010000 (9.183550e-41) Result=7f800000 (inf) ExpProduct=00000000 (0.000000e+00) prod_tol=1.14794e-41 ExpResult=00000000 (0.000000e+00) sum_tol=1.14794e-41 flags=49
    };

    // 0x7F80 Defines floating-point positive infinity value for the nv_bfloat16 data type.
    // 0x7F7F Defines the maximum representable positive value for the nv_bfloat16 data type.
    // 0x0001 Defines the minimum representable (denormalized aka subnormal) value for the nv_bfloat16 data type.
    // 0x00001000 Defines the minimum representable (denormalized aka subnormal) value for the tf32 data type.
    // 0x7FFF Defines canonical NaN value for the nv_bfloat16 data type.
    // 0x8000 Defines a negative zero value for the nv_bfloat16 data type.
    // 0x3F80 Defines a value of 1.0 for the nv_bfloat16 data type.
    // 0x0000 Defines a positive zero value for the nv_bfloat16 data type.

  // -----------------------------------------------------------------
  //  Randomized stimulus
  // -----------------------------------------------------------------
  initial begin

    shortreal a_ref, b_ref, prod_ref_fp32, sum_ref_fp32, product_fp32, dut_sum_fp32, prod_tol, sum_tol;
    tf32_t c, prod_ref_tf32, sum_ref_tf32;
    real real_a, real_b;
    bf16_t a, b;
    logic prod_match, sum_match;

    repeat (NUM_VECTORS) begin 
      if (tests < $size(corners)) begin 
        corner_t cur;     
        cur = corners[tests];
        a = cur.a;
        b = cur.b;
        c = cur.c;
      end else begin
      // Random normal numbers (avoid subnormals / NaNs for simplicity)
        a.sign = $urandom_range(1, 0);
        a.exp  = rand_gauss_exp_clamp(17.5); // SDV=17.5 causes ~seven 0, inf, -inf or -0 product 'events' per 10 million test cases. 
        a.mant = $urandom_range((1<<BF16_MAN_W)-1, 1);
        b.sign = $urandom_range(1, 0);
        b.exp  = rand_gauss_exp_clamp(17.5);
        b.mant = $urandom_range((1<<BF16_MAN_W)-1, 1);
        c.sign = $urandom_range(1, 0);
        c.exp  = rand_gauss_exp_clamp(25.0);
        c.mant = $urandom_range((1<<TF32_MAN_W)-1, 1);
        c.padding = 13'b0;
      end

      a_i = pack_bf16(a);
      b_i = pack_bf16(b);
      c_i = pack_tf32(c);

      // Wait a delta‑cycle for combinational logic to settle
      #0.1ns;

      // Reference using single‑precision fp32 arithmetic
      a_ref = bf16_to_fp32(a);
      b_ref = bf16_to_fp32(b);
      real_a = real'(a_ref);
      real_b = real'(b_ref);
      prod_ref_fp32 = round_toward_zero_32(real_a * real_b); // with round_toward_zero;
      prod_ref_tf32 = fp32_to_tf32(prod_ref_fp32); // prod_ref_fp32 was rounded to zero in the previous step.
      sum_ref_fp32 = prod_ref_fp32 + tf32_to_fp32(c);
      sum_ref_tf32 = fp32_to_tf32(sum_ref_fp32);

      // Convert reference back to TF32 format (rounded the same way)
      // Simple conversion: reinterpret as TF32 (the package already does it)

      // Decompose `ref` into sign/exp/mant (exact TF32 rounding)
      // For brevity we reuse the same packing function that the DUT uses:
      //   (the reference conversion is performed by the TB, not by the DUT)
      //   This ensures both sides apply *identical* rounding rules.
      //   In practice we just call the same `float_formats` routine:
      //   (the function is deliberately left out of the DUT for synthesizability)
      //   → we use the same `tf32_t` struct creation logic.

      if (|sum_tf32 === 1'bx) $error("DUT produced X values!");

      // Compare DUT output with reference
      dut_sum_fp32 = tf32_to_fp32(sum_tf32);
      product_fp32 = tf32_to_fp32(product_tf32);

      // We use a variable tolerance window based on the exponent.  
      prod_tol = calc_tolerance(prod_ref_fp32);
      sum_tol = calc_tolerance(sum_ref_fp32);
      prod_match = (product_fp32 == prod_ref_fp32) || ( (product_fp32 > (prod_ref_fp32 - prod_tol)) && (product_fp32 < (prod_ref_fp32 + prod_tol)) );
      sum_match  = (dut_sum_fp32 == sum_ref_fp32)  || (  (dut_sum_fp32 > (sum_ref_fp32 - sum_tol))  && (dut_sum_fp32 < (sum_ref_fp32 + sum_tol)) );  

      tests=tests+1;
      if (flags[0]) sum_uflw  = sum_uflw+1;
      if (flags[1]) sum_zero  = sum_zero+1;
      if (flags[2]) sum_sub   = sum_sub+1;
      if (flags[3]) sum_ovfl  = sum_ovfl+1;
      if (flags[4]) prod_uflw = prod_uflw+1;
      if (flags[5]) prod_zero = prod_zero+1;
      if (flags[6]) prod_sub  = prod_sub+1;
      if (flags[7]) prod_ovfl = prod_ovfl+1;
      if ( !sum_match || !prod_match ) begin
        $display("Mismatch! Test %0d A=%04h (%0.5e) B=%04h (%0.5e) C=%08h (%0e) | Product=%08h (%0e) Result=%08h (%0e) ExpProduct=%08h (%0e) prod_tol=%0g ExpResult=%08h (%0e) sum_tol=%0g flags=%02h",
             tests,a_i,bf16_to_fp32(a),b_i,bf16_to_fp32(b),c_i,tf32_to_fp32(c),product_tf32,product_fp32,sum_tf32,dut_sum_fp32,prod_ref_tf32,prod_ref_fp32, prod_tol, sum_ref_tf32,sum_ref_fp32, sum_tol, flags);
        fail=fail+1;
        //$stop;
      end else begin
        pass=pass+1;
        if ( (flags == 8'h08) || (NUM_VECTORS <= $size(corners)) ) begin // sum_ovfl *only* or corner cases  only
          $display("Match! Test %0d A=%04h (%0g) B=%04h (%0g) C=%08h (%0g) | Product=%08h (%0g) Result=%08h (%0g) ExpProduct=%08h (%0g) prod_tol=%0g ExpResult=%08h (%0g), sum_tol=%0g flags=%02h",
               tests,a_i,bf16_to_fp32(a),b_i,bf16_to_fp32(b),c_i,tf32_to_fp32(c),product_tf32,product_fp32,sum_tf32,dut_sum_fp32,prod_ref_tf32,prod_ref_fp32, prod_tol, sum_ref_tf32,sum_ref_fp32, sum_tol, flags);
        end
      end
`ifdef RESIDUE3
    if ( (residue_predict != residue) ) begin
        residue_fail=residue_fail+1;
        $display("Product Residue-3 FAIL: %0d * %0d = %8h. Residue %0b (exp %0b)", a_i, b_i, product_tf32, residue, residue_predict);
    end else begin
        residue_pass=residue_pass+1;
//        $display("Product Residue-3 PASS: %0d * %0d = %8h. Residue %0b", a_i, b_i, product_tf32, residue);
    end
`endif
`ifdef PARITY
    if ( (parity_predict != parity) ) begin
        parity_fail=parity_fail+1;
        $display("Result Parity FAIL: %08h + %08h = %08h. Parity %0b (exp %0b)", product_tf32, c_i, sum_tf32, parity, parity_predict);
    end else begin
        parity_pass=parity_pass+1;
//        $display("Result Parity PASS: %08h + %08h = %08h. Parity %0b", product_tf32, c_i, sum_tf32, parity);
    end
`endif
    end

    if (fail == 0) begin
        $display("\nAll %0d FMA tests passed. prod_ovfl %0d prod_sub %0d prod_zero %0d prod_uflw %0d sum_ovfl %0d sum_sub %0d sum_zero %0d sum_uflw %0d\n", pass, prod_ovfl, prod_sub, prod_zero, prod_uflw, sum_ovfl, sum_sub, sum_zero, sum_uflw);
    end else begin
        $display("\n%0d FMA tests passed; %0d tests failed. prod_ovfl %0d prod_sub %0d prod_zero %0d prod_uflw %0d sum_ovfl %0d sum_sub %0d sum_zero %0d sum_uflw %0d\n", pass, fail, prod_ovfl, prod_sub, prod_zero, prod_uflw, sum_ovfl, sum_sub, sum_zero, sum_uflw);
    end
`ifdef RESIDUE3_OR_PARITY
        if ( (residue_fail == 0) && (parity_fail == 0) ) begin
            $display("\nAll %0d Product Residue-3 and %0d Result Parity tests also passed.\n", residue_pass, parity_pass);
        end else begin
            $display("\n%0d Product Residue-3 tests passed; %0d Product Residue-3 tests failed. %0d Result Parity tests passed; %0d Result Parity tests failed.\n", residue_pass, residue_fail, parity_pass, parity_fail);
        end
`endif
    $finish;
  end

  // ------------------------------------------------------------------
  //  calc_tolerance : returns a tolerance window (in FP‑32 units)
  //    based on the unbiased exponent of the reference value.
  //    The window is N_ULP × 1 ULP at that exponent, but never
  //    smaller than MIN_ABS_TOL.
  // ------------------------------------------------------------------
  function automatic shortreal calc_tolerance (shortreal ref_fp32);
      logic [31:0] bits   = $shortrealtobits(ref_fp32);
      logic [7:0]  biased_exp = bits[30:23];
      shortreal tol;
      shortreal one_ulp;
      localparam shortreal N_ULP = 1.0;           // <-- change here (1,2,4,…)
      localparam shortreal MIN_ABS_TOL = 1.0e-8;
     
      int e  = $signed({1'b0, biased_exp}) - BIAS;
      int e2;

      if ((e >= -126) && (e <= 127)) begin // valid exponent range
          e2 = e - 10;
          if (e2 < -126) e2 = -126; 
          one_ulp  = $pow(2.0, e2);   // 1 ULP at this exponent 
          tol = N_ULP * one_ulp;
      end else if (e == -127) begin
          // for subnormals we use a very tiny absolute window
          e2 = -136;
          one_ulp  = $pow(2.0, e2);   // 1 ULP at this exponent 
          tol = N_ULP * one_ulp;
      end else begin
          // for all others we just use a tiny absolute window
          tol = MIN_ABS_TOL;
      end
  
      // absolute floor – never let the window shrink below this value
      //if (tol < MIN_ABS_TOL) tol = MIN_ABS_TOL;
//    $display("TOL: ref_fp32 %08h (%0g) biased_exp %0d e %0d one_ulp %0g tol %0g", fp32_to_tf32(ref_fp32), ref_fp32, biased_exp, e, one_ulp, tol); 
      return tol;
  endfunction : calc_tolerance

  //=====================================================================
  //  rand_gauss_exp_clamp : 8‑bit exponent (1 … 254) drawn from a
  //  normal distribution N(127, 25).  The result is clamped to the
  //  range 1‑254 (so we never generate 0 or 255, which are reserved
  //  for special‑case handling in many BF16/TF32 designs).
  //=====================================================================
  function automatic logic [7:0] rand_gauss_exp_clamp (real SDV);
    // ---------------------------------------------------------------
    // 1.  Box‑Muller transform (two uniform draws → two Gaussian draws)
    // ---------------------------------------------------------------
    real    u1, u2;          // uniform (0,1) values
    real    z0;              // one Gaussian value (the other, z1, is discarded)
    int     i;               // integer version of the Gaussian
    real   two_pi, ln_u1, sqrt_term, angle, r;
  
    // ---------------------------------------------------------------
    // 2.  Get two independent uniform 32‑bit numbers from the *global*
    //     RNG (seeded elsewhere with $urandom(seed) or a +svseed arg).
    // ---------------------------------------------------------------
    u1 = $urandom_range(1, 2_147_483_647);   // avoid 0 → log(0) undefined
    u2 = $urandom_range(1, 2_147_483_647);
  
    // Convert the 31‑bit integers to the real interval (0,1)
    // (the division is done in real arithmetic, so we get a true
    //  floating‑point value.)
    u1 = u1 / 2_147_483_648.0;   // 2^31
    u2 = u2 / 2_147_483_648.0;
  
    // ---------------------------------------------------------------
    // 3.  Box‑Muller (polar) form – gives a standard normal N(0,1)
    // ---------------------------------------------------------------
    //   z0 = sqrt(-2*ln(u1)) * cos(2*π*u2)
    //   z1 = sqrt(-2*ln(u1)) * sin(2*π*u2)   // we ignore z1
    // ---------------------------------------------------------------
    two_pi = 6.28318530717958647692;   // 2π
    ln_u1 = $ln(u1);                  // SystemVerilog provides $ln()
    sqrt_term = $sqrt(-2.0 * ln_u1);
    angle     = two_pi * u2;
    z0 = sqrt_term * $cos(angle);            // N(0,1)
  
    // ---------------------------------------------------------------
    // 4.  Scale & shift to the desired mean (127) and sigma (25)
    // ---------------------------------------------------------------
    r = (z0 * SDV) + 127.0;   // now r ≈ N(127,25)
  
    // ---------------------------------------------------------------
    // 5.  Convert to integer and clamp to the legal exponent range.
    // ---------------------------------------------------------------
    i = $rtoi(r);                 // truncate toward zero (same as $floor for positive)
    if (i < 1)   i = 1;           // keep away from the all‑zero pattern
    if (i > 254) i = 254;         // keep away from the all‑one pattern
  
    // ---------------------------------------------------------------
    // 6.  Return an 8‑bit unsigned value.
    // ---------------------------------------------------------------
    return i[7:0];
  endfunction : rand_gauss_exp_clamp
endmodule : tb_bf16_tf32_fma
