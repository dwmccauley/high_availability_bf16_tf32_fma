//===================================================================
//  float_formats.sv
//  Helper package that defines bfloat16 and TF32 (TensorFloat‑32)
//  and provides packing / unpacking utilities.
//===================================================================
`default_nettype none
`timescale 1ns/1ps

package float_formats;

  // -----------------------------------------------------------------
  //  Parameters
  // -----------------------------------------------------------------
  localparam int BIAS      = 127;      // exponent bias for both formats
  localparam int EXP_W     = 8;        // exponent width
  localparam int EXP_ALL_ONES = 255;   // exponent all ones 
  localparam int BF16_MAN_W = 7;       // bfloat16 mantissa (fraction) width
  localparam int TF32_MAN_W = 10;      // TF32 mantissa (fraction) width

  // -----------------------------------------------------------------
  //  Struct definitions – signed‑magnitude representation
  // -----------------------------------------------------------------
  typedef struct packed {
    logic               sign;
    logic [EXP_W-1:0]   exp;
    logic [BF16_MAN_W-1:0] mant;
  } bf16_t;

  typedef struct packed {
    logic                sign;
    logic [EXP_W-1:0]    exp;
    logic [TF32_MAN_W-1:0] mant;
    logic [31-EXP_W-TF32_MAN_W-1:0] padding;
  } tf32_t;

  // -----------------------------------------------------------------
  //  Packing / Unpacking (bit‑wise) helpers
  // -----------------------------------------------------------------
  function automatic logic [15:0] pack_bf16(bf16_t a);
    return a;
  endfunction

  function automatic logic [31:0] pack_tf32(tf32_t a);
    return a;
  endfunction

  // -----------------------------------------------------------------
  //  Conversion to SystemVerilog shortreal (single precision fp32) – 
  //  used only in the test‑bench for reference checking.
  // -----------------------------------------------------------------
  function automatic shortreal bf16_to_fp32(bf16_t a);
    shortreal mant;
    int e;
    if (a.exp == '1) begin          // Inf or NaN
      return $bitstoshortreal({a.sign, 8'hFF, 23'h0});
    end
    if (a.exp == '0) begin          // zero or subnormal 
      return $bitstoshortreal({a.sign, 8'h0, a.mant, 16'b0});
    end
    // Normalised: 1.Fraction
    mant = 1.0 + a.mant / shortreal'(1 << BF16_MAN_W);
    e  = $signed({1'b0, a.exp}) - BIAS;
    return (a.sign ? -1.0 : 1.0) * $pow(2.0, e) * mant;
  endfunction

  function automatic shortreal tf32_to_fp32(tf32_t a);
    shortreal mant;
    int e;
    if (a.exp == '1) begin          // Inf or NaN
      return $bitstoshortreal({a.sign, 8'hFF, 23'h0});
    end
    if (a.exp == '0) begin          // zero or subnormal
      return $bitstoshortreal({a.sign, 8'h0, a.mant, 13'b0});
    end
    mant = 1.0 + a.mant / shortreal'(1 << TF32_MAN_W);
    e  = $signed({1'b0, a.exp}) - BIAS;
    return (a.sign ? -1.0 : 1.0) * $pow(2.0, e) * mant;
  endfunction

// ---------------------------------------------------------------------
//  round_toward_zero_32
//  Input : real   (64‑bit binary64)
//  Output: shortreal (32‑bit binary32) rounded toward zero.
// ---------------------------------------------------------------------
function shortreal round_toward_zero_32 (real val);
    // 1) Get the 64‑bit IEEE‑754 bit pattern of the double‑precision value
    longint unsigned bits64;
    longint unsigned mant64;
    bit sign64;
    int  exp32, exp64;
    logic [9:0] mant10;
    logic [31:0] bits32;

    // 2) Break the fields out
    bits64 = $realtobits(val);
    sign64 = bits64[63];
    exp64  = bits64[62:52];   // 11‑bit exponent, bias = 1023
    mant64 = bits64[51:0];   // 52‑bit mantissa

    // 3) Special cases (NaN, Inf, zero, subnormal)
    if (exp64 == 11'h7FF) begin               // NaN or Inf
        // Propagate Inf (sign preserved) – mantissa cleared.
        // NaN would also become Inf; that is fine for a truncating model.
        return $bitstoshortreal({sign64, 8'hFF, 23'h0});
    end
    if ((exp64 == '0) & (mant64 == '0)) begin  // Zero 
        // Both become +0 or -0 after truncation.
        return $bitstoshortreal({sign64, 8'h0, 23'h0});
    end

    // 4) Normal numbers – re‑bias exponent from 1023 → 127
    exp32 = exp64 - 1023 + 127;

    // 5) Handle overflow / underflow after re‑bias
    if (exp32 >= 255) begin                  // overflow → Inf
        return $bitstoshortreal({sign64, 8'hFF, 23'h0});
    end
    if (exp32 == 0) begin                    // subnormal 
        return $bitstoshortreal({sign64, 8'h0, mant64[51:42], 13'b0});
    end
    if (exp32 < 0) begin                    // underflow → zero
        return $bitstoshortreal({sign64, 8'h0, 23'h0});
    end

    // 6) Keep only the top 10 mantissa bits (the hidden 1 is implicit)
    mant10[9:0] = mant64[51:42];

    // 7) Assemble the 32‑bit pattern
    bits32 = {sign64, exp32[7:0], mant10, 13'b0};

    // 8) Convert back to shortreal
    return $bitstoshortreal(bits32);
endfunction : round_toward_zero_32

  // ------------------------------------------------------------
  //  fp32 → tf32 conversion
  // ------------------------------------------------------------
  function automatic tf32_t fp32_to_tf32 (input shortreal a);
    // ------------------------------------------------------------------
    //  1) Pull the 32‑bit IEEE‑754 representation of the real value.
    // ------------------------------------------------------------------
    logic [31:0] bits32 = $shortrealtobits(a);
    logic        sign   = bits32[31];
    logic [7:0]  exp8   = bits32[30:23];  // 8‑bit exponent (bias 127)
    logic [22:0] frac23 = bits32[22:0];   // 23‑bit fraction

    // ------------------------------------------------------------------
    // 2) Detect special cases (NaN, Inf, zero, subnormal) *before* we
    //     do any rounding.  The HW design does not need exact IEEE
    //     handling, but we keep the same mapping as the bf16 routine:
    //       NaN/Inf → a very large magnitude,
    tf32_t tf;

    logic [TF32_MAN_W-1:0] frac10;

    // ---------- NaN or Inf ----------
    if (exp8 == '1) begin            // all exponent bits = 1 in single
      // Preserve the sign, produce a “huge” TF32 value.
      tf.sign = sign;
      tf.exp  = EXP_ALL_ONES;              // 255 → Inf in TF32
      tf.mant = '0;                        // fraction = 0 → Inf (not NaN)
      tf.padding = 13'b0; 
      return tf;
    end

    // ---------- Zero (including signed zero) ----------
    if (exp8 == '0 && frac23 == 0) begin
      tf.sign = sign;
      tf.exp  = '0;
      tf.mant = '0;
      tf.padding = 13'b0; 
      return tf;
    end

    // ------------------------------------------------------------------
    // 5) Round the 23‑bit fraction to TF32 (10 bits) using round‑to‑nearest‑even.
    // ------------------------------------------------------------------
    frac10[TF32_MAN_W-1:0] = round_fraction_to_tf32(frac23[22:0]);

    // ---------- Subnormal fp32 ---------- 
    if (exp8 == '0) begin
      tf.sign = sign;
      tf.exp  = '0;
      tf.mant = frac10[TF32_MAN_W-1:0];
      tf.padding = 13'b0; 
      return tf;
    end

    // If rounding caused a carry out of the 10‑bit field the result will be 
    // all zeros and we must bump the exponent.
    if ((frac23[22:13] != '0) && (frac10 == '0)) begin
      int e = exp8;
      // Carry out → increment exponent
      if (e != '0) e = e + 1; 
      // If that overflowed to all‑ones, we turn it into Inf.
      if (e >= EXP_ALL_ONES) begin
        tf.sign = sign;
        tf.exp  = EXP_ALL_ONES;
        tf.mant = '0;
        tf.padding = 13'b0; 
        return tf;
      end 
      exp8 = e; 
    end

    // ------------------------------------------------------------------
    // 6) Pack the final TF32 struct.
    // ------------------------------------------------------------------
    tf.sign = sign;
    tf.exp  = exp8;
    tf.mant = frac10[TF32_MAN_W-1:0];
    tf.padding = 13'b0; 
    return tf;
  endfunction

  // ------------------------------------------------------------
  //  Round‑to‑nearest‑even for a 23‑bit mantissa (binary32)
  //  – keep the top 10 bits, the rest are guard/round/sticky.
  // ------------------------------------------------------------
  function automatic logic [TF32_MAN_W-1:0] round_fraction_to_tf32
    ( input logic [22:0] fraction23 );   // the 23‑bit fraction from binary32
    // TF32 keeps the top 10 bits; the next bit is the *guard*,
    // the rest are *round* and *sticky*.
    logic guard, round, sticky;
    logic [TF32_MAN_W-1:0] kept;
    begin
      kept   = fraction23[22 -: TF32_MAN_W];                 // bits 22 … 13
      guard  = fraction23[22-TF32_MAN_W];                   // bit 12
      round  = fraction23[22-TF32_MAN_W-1];                 // bit 11
      sticky = |fraction23[22-TF32_MAN_W-2:0];              // OR of bits 10 … 0

      // Round-to-Nearest, Ties-to-Even (RTN-TE)
      //   increment if guard && (round | sticky | kept[0])
      if (guard && (round | sticky | kept[0])) begin
        kept = kept + 1'b1;
      end
      // If the increment overflowed beyond the 10‑bit field we will
      // let the caller handle the carry (it will become a mantissa of 0
      // and an exponent+1).
      round_fraction_to_tf32 = kept;
    end
  endfunction

endpackage : float_formats
