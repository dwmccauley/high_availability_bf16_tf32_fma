`timescale 1ns/1ps
module tb_cla_koggestone_r4;

    // -----------------------------------------------------------------
    // 1. Parameters & local constants
    // WIDTHs of 24 or 32 bits are supported
    // -----------------------------------------------------------------
    //localparam int WIDTH       = 32;
    //localparam int WIDTH       = 24;
    localparam int WIDTH       = 16;
    localparam int NUM_VECTORS = 10_000_000;   // random vectors
    localparam int N_CORNER    = 5;            // number of directed tests

    // -----------------------------------------------------------------
    // 2. DUT interface
    // -----------------------------------------------------------------
    logic [WIDTH-1:0] a, b;
    logic [WIDTH-1:0] sum;
    logic             ovfl; // overflow
    logic             cin; // carry in 

    // -----------------------------------------------------------------
    // 3. Optional SEED from the command line
    // -----------------------------------------------------------------
    integer seed;
    initial begin
        if ($value$plusargs("SEED=%d", seed)) begin
            $display("Running with WIDTH: %0d Seed: %0d", WIDTH, seed);
            void'($urandom(seed));
        end else $display("Running with WIDTH: %0d", WIDTH);
    end

    // -----------------------------------------------------------------
    // 4. DUT instantiation
    // -----------------------------------------------------------------
    cla_koggestone_r4 #(.WIDTH(WIDTH)) dut (
        .a   (a),
        .b   (b),
        .cin (cin),
        .sum (sum),
        .ovfl (ovfl)
    );

    // -----------------------------------------------------------------
    // 5. Reference model (identical to the one you already used)
    // -----------------------------------------------------------------
    task automatic ref_model(
        input  logic [WIDTH-1:0] a,
        input  logic [WIDTH-1:0] b,
        input  logic             cin,
        output logic [WIDTH-1:0] sum,
        output logic            ovfl
    );
        logic signed [WIDTH:0] tmp;
        tmp = $signed({1'b0, a}) + $signed({1'b0, b}) + { {WIDTH{1'b0}}, cin };
        sum = tmp[WIDTH-1:0];
        ovfl = (a[WIDTH-1] & b[WIDTH-1] & ~tmp[WIDTH-1]) |
              (~a[WIDTH-1] & ~b[WIDTH-1] &  tmp[WIDTH-1]);
    endtask

    // -----------------------------------------------------------------
    // 6. Scoreboard & counters
    // -----------------------------------------------------------------
    int unsigned err_cnt = 0;
    int unsigned vec_cnt = 0;

    // -----------------------------------------------------------------
    // 7. Random stimulus (unchanged)
    // -----------------------------------------------------------------
    logic [WIDTH-1:0] sum_ref;
    logic             ovfl_ref;

    initial begin
        repeat (NUM_VECTORS) begin
            a   = $urandom_range((1<<WIDTH)-1, 1);
            b   = $urandom_range((1<<WIDTH)-1, 1);
            cin = $urandom_range(1, 0);

            #0.1ns;                // let combinational logic settle

            ref_model(a, b, cin, sum_ref, ovfl_ref);

            if ( (sum !== sum_ref) || (ovfl !== ovfl_ref) ) begin
                err_cnt = err_cnt + 1;
                $display("ERROR at vector %0d:", vec_cnt);
                $display("    a   = 0x%0h (%0d)", a, $signed(a));
                $display("    b   = 0x%0h (%0d)", b, $signed(b));
                $display("    cin = %0d", cin);
                $display("    DUT sum = 0x%0h (%0d)", sum, $signed(sum));
                $display("    REF sum = 0x%0h (%0d)", sum_ref, $signed(sum_ref));
                $display("    DUT ovfl = %b REF ovfl = %b", ovfl, ovfl_ref);
            end
            vec_cnt = vec_cnt + 1;
        end

        if (err_cnt == 0)
            $display("\n*** PASS ***  All %0d random vectors matched the reference model.", vec_cnt);
        else
            $display("\n*** FAIL ***  %0d mismatches out of %0d random vectors.", err_cnt, vec_cnt);
    end

    // -----------------------------------------------------------------
    // 8. Corner‑case block 
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
        '{8'h6, 20'h50c19, 1'b1}     // 0x6, 0x50c19, cin
    };

    initial begin
        // Wait until the random test finishes
        wait (vec_cnt == NUM_VECTORS);

        for (int i = 0; i < $size(corners); i++) begin
            corner_t cur;     
            cur = corners[i];
            a   = cur.a;
            b   = cur.b;
            cin = cur.cin;
            ref_model(a, b, cin, sum_ref, ovfl_ref);
            #0.1ns
            if ( (sum !== sum_ref) || (ovfl !== ovfl_ref) ) begin
                err_cnt = err_cnt + 1;
                $display("CORNER‑CASE ERROR %0d:", i);
                $display("    a = 0x%0h  b = 0x%0h  cin = %0d", a, b, cin);
                $display("    DUT sum = 0x%0h, REF sum = 0x%0h", sum, sum_ref);
                $display("    DUT ovfl = %b,   REF ovfl = %b", ovfl, ovfl_ref);
            end
        end

        // -----------------------------------------------------------------
        // 9. Final report (includes corner‑case errors)
        // -----------------------------------------------------------------
        if (err_cnt == 0)
            $display("\n*** PASS ***  All corner cases also matched.");
        else
            $display("\n*** FAIL ***  %0d total errors (including corner cases).", err_cnt);

        $finish;
    end

endmodule : tb_cla_koggestone_r4
