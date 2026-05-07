`timescale 1ns/10ps

module tb_SeqMul;

    reg clk;
    reg rst;
    reg start;

    reg  signed [64:0]  a;
    reg  signed [64:0]  b;
    wire signed [128:0] o;

    wire done;
    wire busy;

    integer i;
    integer error_count;

    reg signed [128:0] golden;

    SeqMul dut (
        .clk(clk),
        .rst(rst),
        .start(start),
        .a(a),
        .b(b),
        .o(o),
        .done(done),
        .busy(busy)
    );

    // clock: 20ns period
    always #10 clk = ~clk;

    task run_test;
        input signed [64:0] ta;
        input signed [64:0] tb;
        begin
            @(negedge clk);
            a = ta;
            b = tb;
            golden = ta * tb;

            start = 1'b1;

            @(negedge clk);
            start = 1'b0;

            // 等 done
            while (done !== 1'b1) begin
                @(negedge clk);
            end

            // done 那拍 o 應該有效
            if (o !== golden) begin
                $display("ERROR:");
                $display("    a      = %0d", ta);
                $display("    b      = %0d", tb);
                $display("    o      = %0d", o);
                $display("    golden = %0d", golden);
                $display("    o_hex      = %h", o);
                $display("    golden_hex = %h", golden);
                error_count = error_count + 1;
            end else begin
                $display("PASS: a=%0d b=%0d o=%0d", ta, tb, o);
            end

            @(negedge clk);
        end
    endtask

    initial begin
        clk = 1'b0;
        rst = 1'b1;
        start = 1'b0;
        a = 65'sd0;
        b = 65'sd0;
        error_count = 0;

        repeat (5) @(negedge clk);
        rst = 1'b0;

        $display("======================================");
        $display("Start SeqMul Test");
        $display("======================================");

        // basic cases
        run_test(65'sd0,  65'sd0);
        run_test(65'sd1,  65'sd0);
        run_test(65'sd0,  65'sd1);
        run_test(65'sd1,  65'sd1);
        run_test(65'sd2,  65'sd3);
        run_test(65'sd7,  65'sd9);

        // signed cases
        run_test(-65'sd1,  65'sd1);
        run_test( 65'sd1, -65'sd1);
        run_test(-65'sd1, -65'sd1);
        run_test(-65'sd7,  65'sd9);
        run_test( 65'sd7, -65'sd9);
        run_test(-65'sd7, -65'sd9);

        // fixed-point-like values
        run_test(65'sd4037293384, 65'sd4037338097);
        run_test(65'sd16299918387989250048, 65'sd326041);
        run_test(65'sd12756274, 65'sd198143023);

        // boundary-ish cases
        run_test(65'sh0000_0000_0000_0001, 65'sh0000_0000_0000_0001);
        run_test(65'sh0000_0000_ffff_ffff, 65'sh0000_0000_ffff_ffff);

        // random tests
        for (i = 0; i < 100; i = i + 1) begin
            run_test(
                $signed({33'd0, $random}),
                $signed({33'd0, $random})
            );
        end

        // random signed tests
        for (i = 0; i < 100; i = i + 1) begin
            run_test(
                $signed({$random, $random, 1'b0}),
                $signed({$random, $random, 1'b0})
            );
        end

        $display("======================================");
        if (error_count == 0) begin
            $display("ALL PASS");
        end else begin
            $display("FAILED, error_count = %0d", error_count);
        end
        $display("======================================");

        $finish;
    end

endmodule