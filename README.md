# high_availability_bf16_tf32_fma
A High Availability BF16 / TF32 Fused Multiplier-Adder

This SystemVerilog hardware design project includes a BF16 / TF32 FMA unit along with its constituent sub-units.

# To compile the entire Floating-Point Fused Multipler-Adder unit:
iverilog -g2012 -Wall  -pfileline=1  src/half_adder.sv src/full_adder.sv src/cla_adder_8.sv src/residue3_gen.sv src/mod3_adder.sv src/mod3_multiplier.sv src/unsigned_multiplier_8x8.sv src/clz32_opt.sv src/cla_adder.sv src/ha_bf16_tf32_fma.sv tb/float_formats.sv tb/tb_bf16_tf32_fma.sv -o build/ha_bf16_tf32_fma_sim

# To simulate the entire FMA:
vvp build/ha_bf16_tf32_fma_sim

This FMA includes an unsigned 8-bit multiplier with residue-3 prediction, which is the core of this high-availbility FMA.

The 8-bit multiplier uses a Wallace Tree for partial-product reduction with a carry-lookahead final adder stage.

# To compile just the unsigned_multiplier_8x8.sv:
iverilog -g2012 -Wall  -pfileline=1  src/half_adder.sv src/full_adder.sv src/cla_adder_8.sv src/mod3_adder.sv src/mod3_multiplier.sv src/residue3_gen.sv src/unsigned_multiplier_8x8.sv tb/tb_unsigned_multiplier_8x8.sv -o build/tb_unsigned_multiplier_8x8_sim 

# To simulate just the unsigned_multiplier_8x8.sv:
vvp build/tb_unsigned_multiplier_8x8_sim 

Similar stand-alone test benches exist for the 16/24/32-bit carry look-ahead adder and the 32-bit count-leading-zeroes unit.

# To synthesize the 8-bit multiplier unit: 
yosys -p  "read_verilog -sv  src/full_adder.sv src/half_adder.sv src/cla_adder_8.sv src/mod3_adder.sv src/mod3_multiplier.sv src/residue3_gen.sv src/unsigned_multiplier_8x8.sv; hierarchy -check -top unsigned_multiplier_8x8; synth; techmap; abc ;"

OpenROAD-flow-scripts is recommended to synthesize the entire FMA unit.

This is a work in progress. This design is currently combinatorial; pipeline registers will be added later. 

# Documentation: 
docs/HighAvailability_BF16_TF32_FMA.pdf

# License: 
This project is released under the: CERN Open Hardware Licence Version 2 - Permissive
https://ohwr.org/cern_ohl_p_v2.pdf

Don McCauley TechAnalytics LLC March 29, 2026
