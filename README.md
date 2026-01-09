# high_availability_bf16_tf32_fma
A High Availability BF16 / TF32 Fused Multiplier-Adder

This SystemVerilog hardware design project currently only includes the unsigned 8-bit multiplier with residue-3 prediction, which is the core of this high-availability FMA. More to come.

This multiplier uses a Wallace Tree for partial-product reduction with a carry-lookahead final adder stage.

# To compile using iverilog:
iverilog -g2012 -Wall  -pfileline=1  src/half_adder.sv src/full_adder.sv src/cla_adder_8.sv src/mod3_adder.sv src/mod3_multiplier.sv src/residue3_gen.sv src/unsigned_multiplier_8x8.sv tb/tb_unsigned_multiplier_8x8.sv -o build/unsigned_multiplier_8x8_sim

# To simulate using vvp:
vvp build/unsigned_multiplier_8x8_sim

# To synthesis using Yosys:
yosys -p  "read_verilog -sv  src/full_adder.sv  src/half_adder.sv src/cla_adder_8.sv src/mod3_adder.sv src/mod3_multiplier.sv src/residue3_gen.sv src/unsigned_multiplier_8x8.sv; hierarchy -check -top unsigned_multiplier_8x8; synth; techmap; abc ;"

# Documentation:
docs/HighAvailability_BF16_TF32_FMA.pdf

# License: 
This project is released under the: CERN Open Hardware Licence Version 2 - Permissive
https://ohwr.org/cern_ohl_p_v2.pdf

Don McCauley TechAnalytics LLC January 9, 2026

