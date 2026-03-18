//=========================================================================================================
// Copyright (C) 2026 by TechAnalytics LLC Author: Donald W McCauley
//
// File: ha_bf16_tf32_fma.sv
//
// Description: A bfloat16 × bfloat16 + TensorFloat‑32 → TensorFloat‑32 floating-point multiply-adder unit.
//  * bfloat16 : 1 sign, 8 exponent, 7 fraction (implicit 1)
//  * TF32     : IEEE‑754 single‑precision but only the top 10 fraction
//               bits are kept, the low 13 bits are always zero.
//
// License: This project is released under the: CERN Open Hardware Licence Version 2 - Permissive
//     https://ohwr.org/cern_ohl_p_v2.pdf
//=========================================================================================================
`default_nettype none
`timescale 1ns/1ps
`define RESIDUE3
`define PARITY

module ha_bf16_tf32_fma #(
    parameter int ADDER_WIDTH = 16
) (
    // ----- inputs ----------------------------------------------------
    input  logic [15:0] a_bfloat,   // bfloat16 operand A
    input  logic [15:0] b_bfloat,   // bfloat16 operand B
    input  logic [31:0] c_tf32,     // TensorFloat‑32 operand C
    // ----- output ----------------------------------------------------
    output logic [31:0] product_tf32, // For Debug Only. Product in TensorFloat‑32 format 
`ifdef RESIDUE3
    output logic [1:0]  residue_predict, // predicted residue for product
    output logic [1:0]  residue, // actual residue for product
`endif
    output logic [31:0] result_tf32, // TensorFloat‑32 result
`ifdef PARITY
    output logic [(ADDER_WIDTH/8-1):0] parity_predict, // predicted parity for result
    output logic [(ADDER_WIDTH/8-1):0] parity, // actual parity for result
`endif
    output logic [7:0] flags
);
//    `define DEBUG 
    // -----------------------------------------------------------------
    // 1.  Decode the bfloat16 operands
    // -----------------------------------------------------------------
    // a_bfloat
    logic [7:0]  exp_a;
    logic [6:0]  frac_a;
    assign exp_a  = a_bfloat[14:7];
    assign frac_a = a_bfloat[6:0];

    // b_bfloat
    logic [7:0]  exp_b;
    logic [6:0]  frac_b;
    assign exp_b  = b_bfloat[14:7];
    assign frac_b = b_bfloat[6:0];

    // -----------------------------------------------------------------
    // 2.  Build the *effective* 8‑bit mantissas (including hidden bit)
    // -----------------------------------------------------------------
    // Normal numbers (exp != 0) have an implicit leading 1.
    // Subnormals (exp == 0) have no hidden bit.
    // It is acceptable to flush BF16 subnormals to zero, as it is done   
    //    here.
    bit hidden_a, hidden_b;
    assign hidden_a = (exp_a != 0);
    assign hidden_b = (exp_b != 0);

    logic [7:0] mant_a, mant_b;
    assign mant_a = {hidden_a, frac_a};
    assign mant_b = {hidden_b, frac_b};

    // -----------------------------------------------------------------
    // 2.  Multiply the mantissas with the supplied 8×8 unsigned multiplier
    // -----------------------------------------------------------------
    logic [15:0] mant_prod;                // 16‑bit unsigned product
    unsigned_multiplier_8x8 u_mul (
        .a (mant_a),
        .b (mant_b),
`ifdef RESIDUE3
        .residue_predict (residue_predict),        // predicted Residue-3 for product
`endif
        .product (mant_prod)
    );

`ifdef RESIDUE3
    residue3_gen #(.WIDTH(16)) gen_prod_res ( .data_in(mant_prod[15:0]), .residue(residue[1:0]) ); // actual residue for product
`endif

    // -----------------------------------------------------------------
    // 3.  Normalise the 16‑bit mantissa product
    // -----------------------------------------------------------------
    // After multiplying two numbers in the range [1,2) the raw product is
    // in [1,4).  If the top bit (bit‑15) is ‘1’ the value is >= 2 and must be
    // shifted right once; the exponent is then incremented.
    logic        prod_sign, prod_ovfl, prod_uflw, prod_zero, prod_sub;
    logic        prod_exp_adj;     // 0 → no extra bias, 1 → exponent +1

    assign prod_sign = a_bfloat[15] ^ b_bfloat[15];

    // exponent add (bias = 127)
    localparam bit [8:0] BIAS_9BIT = 9'b0_0111_1111; // 127
    logic [7:0]  EXP_ALL_ONES = 8'b1111_1111;   // exponent all ones
    localparam int EXP_W     = 8;        // exponent width
    localparam int EXP_MAX    = (1 << EXP_W)-1; // 255 Signed
    logic signed [9:0] exp_a_plus_b; // one extra bit for possible overflow
    logic signed [9:0] exp_a_plus_b_pl1;
    assign exp_a_plus_b     = (exp_a == 0 || exp_b == 0) ? 0 : $signed({1'b0, exp_a}) + $signed({1'b0, exp_b}) - BIAS_9BIT; // guard zero exponent
    assign exp_a_plus_b_pl1 = (exp_a == 0 || exp_b == 0) ? 0 : $signed({1'b0, exp_a}) + $signed({1'b0, exp_b}) + 1'b1 - BIAS_9BIT;

    // Normalization of the mantissa product 
    assign prod_exp_adj = mant_prod[15];             // MSB == 1  →  shift‑right‑1
    // Note: fraction should be zero if exponent is zero. Product will be zero if either fraction is zero.

    // Final exponent after normalization
    logic signed [9:0] prod_exp_raw; // 9‑bit to hold a possible carry 
    logic [7:0] prod_exp; 
    assign prod_exp_raw = prod_exp_adj ? exp_a_plus_b_pl1 : exp_a_plus_b; 

    // Detect overflow / underflow after normalisation
    assign prod_ovfl = (prod_exp_raw >= EXP_MAX); // Product exponent >= ~+/-3.4e+38 (or +/-2**128). 
    assign prod_uflw = prod_exp_adj ? (exp_a_plus_b_pl1 < 0) : (exp_a_plus_b < 0); // Product exponent <  ~+/-1.7e-38 (or +/-2**-126). Product fraction rounded to zero; no product subnormal

    // Saturate exponent and mantissa
    assign prod_exp = prod_ovfl  ? 8'hFF :        // all‑ones → Inf/NaN
                         prod_uflw ? 8'h00 :      // all‑zeros → zero/subnormal
                              prod_exp_raw[7:0];

    // -----------------------------------------------------------------
    // 4.  Convert the product into a TF32 value (sign, exp, 10‑bit frac)
    // -----------------------------------------------------------------
    // Full‑precision (24‑bit) mantissa for a single‑precision number:
    //   {hidden‑1, fraction[22:0]}  →  bit‑23 is the hidden 1.
    // Our 16‑bit mant_prod has its leading 1 at bit‑14 (after exponent adjustment)
    logic [23:13] mant_prod_24; // 1 hidden + 10 fraction bits (TF32 precision)
    assign mant_prod_24[23:13] = (prod_exp_adj) ? mant_prod[15:5] : mant_prod[14:4]; // place the hidden 1 at bit‑23.

    // TF32 keeps only the top 10 fraction bits (bits 22‑13).
    // The low 13 bits are forced to zero / truncated. 
    logic [9:0] prod_frac_tf32; // 10‑bit fraction for TF32
    assign prod_frac_tf32 = prod_ovfl  ? 10'h0 :         // mantissa cleared for ovfl/Inf
                                prod_uflw ? 10'h0 :      // mantissa cleared for uflw
                                    mant_prod_24[22:13]; // bits 22‑13 → 10‑bit frac. Could be subnormal 

    assign prod_zero = (prod_exp_raw == '0) & (mant_prod_24[23:13] == '0); // product is zero 
    assign prod_sub  = (prod_exp_raw == '0) & (mant_prod_24[23:13] != '0); // product is subnormal

//always @* 
//  $display("2.prod_frac_tf32 %03h exp_a %02h exp_b %02h prod_exp_adj %0d exp_a_plus_b %03h (%0d) exp_a_plus_b_pl1 %03h (%0d) prod_exp_raw %03h prod_exp %02h prod_ovfl %0d prod_uflw %0d", {2'b00,prod_frac_tf32[9:0]}, exp_a, exp_b, prod_exp_adj, {2'b0,exp_a_plus_b}, exp_a_plus_b, {2'b0,exp_a_plus_b_pl1}, exp_a_plus_b_pl1, {3'b0,prod_exp_raw}, prod_exp, prod_ovfl, prod_uflw );
//    $display("mant_a %02h, mant_b %02h, mant_prod %04h, prod_sign %0d, prod_exp %02h, prod_frac_tf32 %03h", mant_a, mant_b, mant_prod, prod_sign, prod_exp, {2'b00,prod_frac_tf32[9:0]}, );
    // -----------------------------------------------------------------
    // 5.  Add the TF32 operand C
    // -----------------------------------------------------------------
    //   a)  Decode both TF32 numbers (product and C)
    //   b)  Align mantissas
    //   c)  Normalise, re‑bias exponent, round to 10‑bit fraction
    // -----------------------------------------------------------------

    // ----- Decode TF32 operand C ---------------------------------------------
    logic        sign_c;
    logic [7:0]  exp_c;
    logic [9:0]  frac_c;
    logic [12:0] unused_c;
    assign sign_c   = c_tf32[31];
    assign exp_c    = c_tf32[30:23];
    assign frac_c   = c_tf32[22:13]; 
    assign unused_c = c_tf32[12:0]; // low 13 bits of c are guaranteed zero

    // ----- Build the *full* 24‑bit mantissas (including hidden 1) -------------
    //   For a normal TF32 number the hidden bit is 1.  For zero/denorm we
    //   treat the hidden bit as 0 – the exponent will be zero as well.
    function automatic logic [23:0] build_full_mant_unsigned (logic [7:0]  exp,
                                                    logic [9:0]  frac);
        // Returns a unsigned 24‑bit mantissa.
        //   bit‑23  : hidden 1 (or 0 for subnormal/zero)
        //   bits‑22‑13 : the 10‑bit fraction from the TF32 format
        //   bits‑12‑0  : all zeros (TF32 precision)
        logic hidden;
        logic [23:0] mant;
        hidden = (exp == '0) ? 1'b0 : 1'b1; // subnormal → hidden = 0 
        // Assemble the 24‑bit mantissa
        mant = {hidden, frac, 13'b0}; // hidden at bit‑23, fraction at 22‑13
        build_full_mant_unsigned = mant; // magnitude only; unsigned. Minimum width: 12. 
    endfunction

    logic unsigned [23:0] mant_p_sc; // unsigned mantissa of product
    logic unsigned [23:0] mant_c_sc; // unsigned mantissa of operand C
    assign mant_p_sc = build_full_mant_unsigned(prod_exp, prod_frac_tf32); 
    assign mant_c_sc = build_full_mant_unsigned(exp_c, frac_c);

//  always @*
//      $display("prod_sign %d, prod_exp %02h, prod_frac_tf32 %03h, mant_p_sc %06h, sign_c %d, exp_c %02h, frac_c %03h, mant_c_sc %06h", prod_sign, prod_exp, {2'b00,prod_frac_tf32}, mant_p_sc, sign_c, exp_c, {2'b00,frac_c}, mant_c_sc);
    // ----- Align mantissas --------------------------------------------------
    // Shift the mantissa of the smaller‑exponent operand right by the
    // absolute exponent difference (right shift inserts zeros).
    logic unsigned [23:0] mant_p_aligned, mant_c_aligned, mant_mask;
    logic [7:0]  exp_res_align;   // exponent that will be used after alignment
    logic [7:0]  prod_exp_diff, prod_exp_diff_pl1, c_exp_diff, c_exp_diff_pl1;
    logic        shift_c; // 1 → shift C, 0 → shift product
    localparam logic [3:0] PROD_INTERNAL_PREC = 15; // TF32 internal mantissa (fraction) width, including hidden bit. Min: 12; Max: 15. Includes Guard, Round & 2 Sticky bits.

    // Compute the exponent difference separately for product and c (unsigned)
    //                            shift out entire product if underflow
    assign prod_exp_diff     = (exp_a_plus_b < 0)     ? PROD_INTERNAL_PREC : ( (exp_a_plus_b >= exp_c)     ? '0 : (exp_c - exp_a_plus_b) );
    assign prod_exp_diff_pl1 = (exp_a_plus_b_pl1 < 0) ? PROD_INTERNAL_PREC : ( (exp_a_plus_b_pl1 >= exp_c) ? '0 : (exp_c - exp_a_plus_b_pl1) );
    assign c_exp_diff        = (exp_a_plus_b < 0)     ? '0                 : ( (exp_a_plus_b >= exp_c)     ? (exp_a_plus_b - exp_c)     : '0 ); 
    assign c_exp_diff_pl1    = (exp_a_plus_b_pl1 < 0) ? '0                 : ( (exp_a_plus_b_pl1 >= exp_c) ? (exp_a_plus_b_pl1 - exp_c) : '0 ); 
    assign shift_c           = prod_exp_adj ? ( (exp_a_plus_b_pl1 > 0) & (exp_a_plus_b_pl1 > exp_c) ) : ( (exp_a_plus_b > 0) & (exp_a_plus_b > exp_c) ); // true → C has the smaller exponent

    // Limit the shift amount to the width of the product mantissa (max 12-13). 
    // Any shift larger than 12-13 just produces zero – the operand is too small to affect the sum.
    logic [3:0] prod_shift_amount, prod_shift_amount_pl1, prod_shift_amount_mux, c_shift_amount, c_shift_amount_pl1, c_shift_amount_mux; // 0‑15 fits in 4 bits
    assign mant_mask = {{(PROD_INTERNAL_PREC){1'b1}},{(24-PROD_INTERNAL_PREC){1'b0}}};
    assign prod_shift_amount     = (prod_exp_diff     > {4'b0,PROD_INTERNAL_PREC}) ? PROD_INTERNAL_PREC : prod_exp_diff[3:0];
    assign prod_shift_amount_pl1 = (prod_exp_diff_pl1 > {4'b0,PROD_INTERNAL_PREC}) ? PROD_INTERNAL_PREC : prod_exp_diff_pl1[3:0];
    assign c_shift_amount        = (c_exp_diff        > {4'b0,PROD_INTERNAL_PREC}) ? PROD_INTERNAL_PREC : c_exp_diff[3:0];
    assign c_shift_amount_pl1    = (c_exp_diff_pl1    > {4'b0,PROD_INTERNAL_PREC}) ? PROD_INTERNAL_PREC : c_exp_diff_pl1[3:0];

    // Align the two unsigned mantissas
    always_comb begin
        prod_shift_amount_mux = (prod_exp_adj) ? prod_shift_amount_pl1 : prod_shift_amount; 
        c_shift_amount_mux    = (prod_exp_adj) ?    c_shift_amount_pl1 : c_shift_amount; 
        mant_p_aligned = (mant_p_sc >> prod_shift_amount_mux) & mant_mask; // product shifted right. unsigned 
        mant_c_aligned = (mant_c_sc >> c_shift_amount_mux)    & mant_mask; // C shifted right. unsigned

        if (shift_c) begin               // product exponent >= C exponent
            exp_res_align  = prod_exp;
        end else begin                  // C exponent > product exponent
            exp_res_align  = exp_c;
        end
    end

    // -------------------------------------------------------------
    // decide which unsigned, aligned operand is larger (in magnitude)
    // -------------------------------------------------------------
    logic  p_gt_c, p_gt_c_raw;
    assign p_gt_c_raw = (mant_p_sc[23:13] > mant_c_sc[23:13]); // Includes product Guard bit. This should be ~4-5 logic levels.
    assign p_gt_c = (prod_exp > exp_c) | ((prod_exp == exp_c) & p_gt_c_raw);

    // -------------------------------------------------------------
    //  Choose between add/sub based on sign comparison.
    // -------------------------------------------------------------
    logic  add_op;                           // 1 = add, 0 = subtract
    assign add_op   = (prod_sign == sign_c);    // same sign → addition
    logic  flip_p, flip_c, sum_sign;
    assign flip_p = !add_op & !p_gt_c;       // decide which operand - if any - to flip
    assign flip_c = !add_op &  p_gt_c;
    assign sum_sign = add_op ? prod_sign :      // add → sign of either operand
                      (p_gt_c ? prod_sign : sign_c); // subtract → sign of sum is sign of larger operand 

    // ----- Add the unsigned mantissas ----------------------------------------
    // The sum can be up to 24 bits (+ overflow) 
    // for later normalization.
    logic unsigned [23:8] mant_p_true_complement, mant_c_true_complement;
    assign mant_p_true_complement = flip_p ? ~mant_p_aligned[23:8] : mant_p_aligned[23:8];
    assign mant_c_true_complement = flip_c ? ~mant_c_aligned[23:8] : mant_c_aligned[23:8];

    logic unsigned [23:8] sum_sc; // 24‑bit unsigned result. 
    logic sum_cout, sum_mant_zero;
    cla_koggestone_r4 #(.WIDTH(ADDER_WIDTH)) add ( // 16-bit unsigned carry-look-ahead adder
        .a (mant_p_true_complement[23:8]), 
        .b (mant_c_true_complement[23:8]), 
        .cin (!add_op), 
        .sum (sum_sc[23:8]), 
`ifdef PARITY
        .parity (parity_predict[(ADDER_WIDTH/8-1):0]), 
`endif
        .ovfl (sum_cout) 
    );
    assign sum_mant_zero = (sum_sc[23:8] == 0) & !add_op;

`ifdef PARITY
    // --- Byte Parity Generation ---
    genvar byte_idx;
    generate
        for (byte_idx = 0; byte_idx < ADDER_WIDTH / 8; byte_idx++) begin : gen_byte_parity
            // Range for the current byte
            localparam int LOW  = (byte_idx+1) * 8; // using sum_sc[23:8]
            localparam int HIGH = LOW + 7;

            // P_sum = P_a ^ P_b ^ P_carries_in
            // Carries needed: c_internal[LOW] through c_internal[HIGH]
            assign parity[byte_idx] = (^sum_sc[HIGH:LOW]); 
        end
    endgenerate
`endif

`ifdef DEBUG 
    always @*
        $display("shift_c %0d prod_shift_amount %02h mant_p_aligned %06h c_shift_amount %02h mant_c_aligned %06h sum_sc %06h sum_cout %d sum_mant_zero %d", shift_c, prod_shift_amount_mux, mant_p_aligned, c_shift_amount_mux, mant_c_aligned, {sum_sc[23:8],8'b0}, sum_cout, sum_mant_zero);
`endif

    // ----- Normalise the addition result ------------------------------------
    // The sum may be:
    //   * zero                     → exponent = 0, fraction = 0
    //   * overflow                 → shift right 1, exponent +1
    //   * otherwise                → leading 1 may be at bit‑25 … bit‑13
    //   *           (leading zeros) → shift left until the hidden 1 is in
    //                                 bit‑23, decrement exponent accordingly.
    //

    // Normalization
    // We use a simple leading‑zero count (CLZ) on the absolute value.
    //     When used with <32 bits, the input is padded with trailing ones (LSB)
    //     and the high order bit of cnt is not used.
    logic [5:0] leading_zeros;
    clz32_opt u_clz27 ( .data( {sum_sc[23:8], 16'b1} ), .count(leading_zeros) ); // TODO #5: add support for 16-bit count-leading-zeros

`ifdef DEBUG 
    always @*
        $display("sum_sign %d, sum_sc = %08h, leading_zeros = %0d", sum_sign, {sum_sc[23:8], 16'b1}, leading_zeros);
`endif
    // After CLZ we know where the hidden 1 should be.
    // The hidden 1 for a TF32 number is at bit‑23.
    // If the sum is zero, we force the result to +0 (sign = 0).
    logic        final_sign;
    logic signed [8:0]  final_exp_raw;
    logic [7:0]  final_exp;
    logic [9:0]  final_frac; // TF32 fraction (10 bits)
    logic sum_ovfl, sum_uflw, sum_zero, sum_sub;
    logic [5:0] shift_left;
    logic [23:0] mant_norm; // absolute value; no sign bit
    logic guard, round, sticky;
    logic [9:0] frac_trunc;
    logic [9:0] frac_rounded;

    always_comb begin                         
        if (sum_mant_zero) begin 
            final_sign = sum_sign;             // result is positive or negative zero based on sign.                     
            final_exp_raw  = 9'b0;
            final_frac = 10'b0;
            guard = 0; round = 0; sticky = 0;
            shift_left =0; mant_norm = 0; frac_trunc = 0; frac_rounded = 0;
        end else begin
            // Normalise the magnitude
            //   shift_left = leading_zeros    // bring hidden 1 to bit‑23
            shift_left = leading_zeros; // we need 24‑bit mantissa (hidden+10+13)
            // The minimum shift_left is 0, which means the hidden bit is in the correct position: bit 23
            // The maximum shift_left is 24, which will zero out the mantissa. 
            // If we have an overflow, we must shift right by 1.

            // Normalised 24‑bit mantissa (hidden + 10‑bit fraction + 13 zero bits)
            if (sum_cout) begin
                mant_norm = {sum_sc[23:8],8'b0} >> 1'b1; // drop low bit 
                // Exponent will be increased by 1 because we lost a bit of magnitude
                final_exp_raw = (exp_res_align == EXP_ALL_ONES) ? EXP_ALL_ONES : $signed({2'b0,exp_res_align}) + 1'b1;
            end else begin
                mant_norm = {sum_sc[23:8],8'b0} << shift_left; // shift left to place hidden 1 at bit‑23
                final_exp_raw = $signed({2'b0,exp_res_align}) - {4'b0,shift_left};
            end

            // Extract the TF32 fraction (top 10 bits) 
            // Round-to-Nearest, Ties-to-Even (RTN-TE)
            //   Guard  = bit‑12, Round = bit‑11, Sticky = any lower bit
            guard  = mant_norm[12];
            round  = mant_norm[11];
            sticky = |mant_norm[10:8];

            frac_trunc[9:0] = mant_norm[22:13]; // top 10 bits
            // Round‑to‑nearest‑even
            if (guard && (round | sticky | frac_trunc[0])) begin
                frac_rounded[9:0] = frac_trunc[9:0] + 1'b1;
                if (frac_rounded == 10'b0000_0000_00) begin
                    // If rounding caused a carry out of the fraction, propagate to exponent
                    // fraction overflow → shift right once, exponent +1
                    if (final_exp_raw != EXP_ALL_ONES) final_exp_raw = final_exp_raw + 1'b1; 
                end
            end else begin
                frac_rounded[9:0] = frac_trunc[9:0];
            end
            final_frac = ((final_exp_raw >= EXP_ALL_ONES) || (final_exp_raw < 0)) ? '0 : frac_rounded;

            // Final sign is XOR of the two addends' signs (product ^ c) 
            final_sign = sum_sign; 
    //$display("guard %d, round %d, sticky %d, frac_trunc %03h, frac_rounded %03h, final_frac %03h", guard, round, sticky, {2'b00,frac_trunc}, {2'b00,frac_rounded}, {2'b00,final_frac});
        end
    end

//  always @*
//    $display("final_exp_raw = %03h, final_frac = %03h", {2'b0,final_exp_raw}, {2'b0,final_frac});

    // Detect overflow / underflow after normalization
    assign sum_ovfl = (final_exp_raw >= EXP_ALL_ONES); // Sum exponent >= ~+/-3.4e+38 (or +/-2**128). 
    assign sum_uflw = (final_exp_raw < 0);             // Sum exponent < ~+/-1.7e-38 (or +/-2**-126).
    assign sum_zero = (final_exp_raw == '0) & (final_frac == '0); // sum is zero 
    assign sum_sub  = (final_exp_raw == '0) & (final_frac != '0); // sum is subnormal

    assign final_exp = sum_ovfl ? EXP_ALL_ONES :
                           sum_uflw  ? 8'h00 :
                               final_exp_raw[7:0];

    // -----------------------------------------------------------------
    // Pack the final product (for debug) and result TF32 words (low 13 fraction bits are forced zero)
    // -----------------------------------------------------------------
    assign product_tf32 = {             // 
        prod_sign,                // 31
        prod_exp,                 // 30‑23
        prod_frac_tf32,           // 22‑13  (10‑bit fraction)
        13'b0                     // 12‑0   (always zero in TF32)
    };
    assign result_tf32 = {
        final_sign,               // 31
        final_exp[7:0],           // 30‑23
        final_frac,               // 22‑13  (10‑bit fraction)
        13'b0                     // 12‑0   (always zero in TF32)
    };
    assign flags = {prod_ovfl, prod_sub, prod_zero, prod_uflw, sum_ovfl, sum_sub, sum_zero, sum_uflw};

endmodule : ha_bf16_tf32_fma
