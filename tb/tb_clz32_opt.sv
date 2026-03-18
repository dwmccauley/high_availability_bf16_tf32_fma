//=========================================================================================================
// Copyright (C) 2026 by TechAnalytics LLC Author: Donald W McCauley
//
// File: tb_clz32_opt.sv 
//
// Description: Test Bench for a 32‑bit Leading‑Zero Detector 
//
// License: This project is released under the: CERN Open Hardware Licence Version 2 - Permissive
//     https://ohwr.org/cern_ohl_p_v2.pdf
//=========================================================================================================
`timescale 1ns/1ps
module tb_clz32_opt;
    logic [31:0] data;
    logic [5:0]  count;

    clz32_opt dut ( .data(data), .count(count) );

    integer pass = 0;
    integer fail = 0;

    // Reference model (simple loop)
    function automatic [5:0] ref_clz (input [31:0] v);
        integer i;
        for (i = 31; i >= 0; i = i - 1)
            if (v[i]) return 31 - i;
        return 6'd32;               // all‑zero
    endfunction

    // --------------------------------------------------------------
    // Random stimulus
    // --------------------------------------------------------------
    initial begin
        repeat (10000) begin
            data = $urandom();
            #0.1ns
            if (count !== ref_clz(data)) begin
                $error("FAIL: data=%08h count=%0d expected=%0d", data, count, ref_clz(data));
                fail=fail+1;
                //$stop;
            end else begin
//              $display("Pass: data=%08h count=%0d expected=%0d", data, count, ref_clz(data));
                pass=pass+1;
            end
        end

        // Corner‑case: all zeros
        data = 32'h0;
        #0.1ns
        if (count !== 6'd32) begin
            $error("All‑zero case failed. data=%08h count=%0d expected=%0d", data, count, ref_clz(data));
            fail=fail+1;
        end else begin
//          $display("Pass: data=%08h count=%0d expected=%0d", data, count, ref_clz(data)); 
            pass=pass+1;
        end

        if (fail == 0) begin
            $display("\nAll %0d tests passed.\n", pass);
        end else begin
            $display("\n%0d tests passed; %0d tests failed.\n", pass, fail);
        end
        $finish;
    end
endmodule : tb_clz32_opt
