module SeqMul (
    input  wire                clk,
    input  wire                rst,
    input  wire                start,

    input  wire signed [64:0]  a,
    input  wire signed [64:0]  b,
    output reg  signed [128:0] o,

    output reg                 done,
    output reg                 busy
);

    reg [6:0] count;

    reg [128:0] acc;
    reg [128:0] multiplicand;
    reg [64:0]  multiplier;
    reg         sign;

    wire [64:0] abs_a;
    wire [64:0] abs_b;

    assign abs_a = a[64] ? (~a + 65'd1) : a;
    assign abs_b = b[64] ? (~b + 65'd1) : b;

    wire [128:0] addend;
    wire [128:0] acc_next;

    assign addend   = multiplier[0] ? multiplicand : 129'd0;
    assign acc_next = acc + addend;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            count        <= 7'd0;
            acc          <= 129'd0;
            multiplicand <= 129'd0;
            multiplier   <= 65'd0;
            sign         <= 1'b0;
            o            <= 129'sd0;
            done         <= 1'b0;
            busy         <= 1'b0;
        end else begin
            done <= 1'b0;

            if (start && !busy) begin
                count        <= 7'd0;
                acc          <= 129'd0;
                multiplicand <= {64'd0, abs_a};
                multiplier   <= abs_b;
                sign         <= a[64] ^ b[64];
                busy         <= 1'b1;
            end else if (busy) begin
                if (count == 7'd64) begin
                    o    <= sign ? -$signed(acc_next) : $signed(acc_next);
                    busy <= 1'b0;
                    done <= 1'b1;
                end else begin
                    acc          <= acc_next;
                    multiplicand <= multiplicand << 1;
                    multiplier   <= multiplier >> 1;
                    count        <= count + 7'd1;
                end
            end
        end
    end

endmodule