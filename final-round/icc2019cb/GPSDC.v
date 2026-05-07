// vcs -R -full64 -sverilog testbench.v GPSDC.v +access+r +vcs+fsdbon 
// vcs -R -full64 -sverilog tb.sv geofence.v +access+r +vcs+fsdbon +define+SDF -v /cad/CBDK/CBDK_IC_Contest_v2.1/Verilog/tsmc13_neg.v +maxdelays

module Multiply (
    input wire signed [64:0]a, // signed
    input wire signed [64:0]b, // signed
    output reg signed [128:0]o // signed
);
    always @(*) begin
        o = a * b;
    end
endmodule


module SeqDiv (
    input  wire        clk,
    input  wire        rst,
    input  wire        start,
    input  wire signed [128:0] num,
    input  wire signed [128:0] den,
    output wire signed [128:0] quo,
    output reg         done
);
    reg [8:0] count;
    reg [256:0] remainder;
    reg [128:0] divisor;
    reg sign;

    wire [128:0] abs_num = (num[128]) ? -num : num;
    wire [128:0] abs_den = (den[128]) ? -den : den;
    wire [129:0] sub_res = {1'b0, remainder[255:128]} - {1'b0, divisor};

    assign quo = sign ? -remainder[128:0] : remainder[128:0];

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            count <= 0; done <= 0;
            remainder <= 0; divisor <= 0; sign <= 0;
        end else begin
            if (start) begin
                count <= 9'd129;
                remainder <= {129'd0, abs_num};
                divisor <= abs_den;
                sign <= num[128] ^ den[128];
                done <= 0;
            end else if (count > 0) begin
                if (!sub_res[129]) remainder <= {sub_res[128:0], remainder[127:0], 1'b1};
                else remainder <= {remainder[255:0], 1'b0};
                
                count <= count - 1;
                if (count == 1) done <= 1;
            end else begin
                done <= 0;
            end
        end
    end
endmodule


module CosInterpolate (
    input wire clk, 
    input wire reset, 
    input wire start,
    output reg done,  

    output reg [64:0]mul_in1, 
    output reg [64:0]mul_in2, 
    input wire [128:0]mul_out,

    output reg [6:0]cos_chart_address, 
    input wire [95:0]cos_chart_value, 

    input wire[47:0]input_value, 
    output reg [47:0]cos_interpolate_value
);  
    localparam S_IDLE = 3'b000;
    localparam S_SEARCH = 3'b001;
    localparam S_STORE_LEFT = 3'b010;
    localparam S_MUL_A = 3'b011;
    localparam S_MUL_B = 3'b100;
    localparam S_DIV = 3'b101; 
    localparam S_DIV_WAIT = 3'b110;
    localparam S_DONE = 3'b111;

    reg [2:0] state_r, next_state_r;

    reg [6:0]curr_r, bit_r;
    reg [47:0]input_value_r;
    
    reg [64:0] mul_in1_r, mul_in2_r;
    reg [128:0] mul_out1_r, mul_out2_r;
    reg [95:0] left_point_r, right_point_r;

    reg div_rst_r, div_start_r;
    reg [128:0]div_num_r, div_den_r;
    wire [128:0]div_quo;
    wire div_done;
    SeqDiv div(.clk(clk), .rst(reset), .start(div_start_r), .num(div_num_r), .den(div_den_r), .quo(div_quo), .done(div_done));

    `ifdef DEBUG
    always @(posedge clk) begin
        $strobe("CosInterpolate [%0t] state=%0d curr_r=%0d bit_r=%0d input_value_r=%f x=%f left_x=%f left_cos_x=%f right_x=%f right_cos_x=%f",
            $time, state_r, 
            curr_r, bit_r, 
            $itor(input_value_r) / 65536.0, 
            $itor(cos_chart_value[95:48]), 
            $itor(left_point_r[95:48]) / 4294967296.0, $itor(left_point_r[47:0]) / 4294967296.0, 
            $itor(right_point_r[95:48]) / 4294967296.0, $itor(right_point_r[47:0]) / 4294967296.0
        );
    end
    `endif

    /*`ifdef DEBUG
    always @(posedge clk) begin
        $strobe("DIV t=%0t state=%0d div_start=%b div_done=%b count=%0d den=%0d num=%0d",
            $time, state_r, div_start_r, div_done,
            div.count, div_den_r, div_num_r
        );
    end
    `endif*/

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state_r <= S_IDLE;
            curr_r <= 7'b1000000;
            bit_r <= 7'b1000000;
        end else begin
            if (state_r == S_IDLE) begin
                input_value_r <= input_value;
                curr_r <= 7'b1000000;
                bit_r <= 7'b1000000;
            end else if (state_r == S_SEARCH) begin
                // binary serach
                curr_r <= (input_value < cos_chart_value[95:48]) ? ((curr_r ^ bit_r) | (bit_r >> 1)) : (curr_r | (bit_r >> 1));
                bit_r <= bit_r >> 1;
            end else if (state_r == S_STORE_LEFT) begin
                left_point_r <= cos_chart_value;
                curr_r <= curr_r + 1;
            end else if (state_r == S_MUL_A) begin
                // interpolate
                // y0 * (x1 - x0)
                mul_in1_r <= 65'(signed'(left_point_r[47:0]));
                mul_in2_r <= 65'(signed'(cos_chart_value[95:48] - left_point_r[95:48]));
                right_point_r <= cos_chart_value;
            end else if (state_r == S_MUL_B) begin
                mul_out1_r <= mul_out;
                // (x - x0) * (y1 - y0)
                mul_in1_r <= 65'(signed'(input_value - left_point_r[95:48]));
                mul_in2_r <= 65'(signed'(right_point_r[47:0] - left_point_r[47:0]));
            end else if (state_r == S_DIV) begin
                div_num_r <= 128'(signed'(right_point_r[47:0] - left_point_r[47:0]));
                div_den_r <= 128'(signed'(mul_out1_r + mul_out));
                div_start_r <= 1'b1;
            end else if (state_r == S_DIV_WAIT) begin
                div_start_r <= 1'b0;
            end
            state_r <= next_state_r;
        end
    end
    
    always @(*) begin
        next_state_r = state_r;
        case (state_r) 
            S_IDLE: if (start) next_state_r = S_SEARCH;
            S_SEARCH: if (~(|bit_r)) next_state_r = S_STORE_LEFT;
            S_STORE_LEFT: next_state_r = S_MUL_A;
            S_MUL_A: next_state_r = S_MUL_B;
            S_MUL_B: next_state_r = S_DIV;
            S_DIV: next_state_r = S_DIV_WAIT;
            S_DIV_WAIT: if (div_done) next_state_r = S_DONE;
            S_DONE: next_state_r = S_IDLE;
        endcase
    end
    always @(*) begin
        cos_chart_address = curr_r;
        done = (state_r == S_DONE);
        mul_in1 = mul_in1_r;
        mul_in2 = mul_in2_r;
        cos_interpolate_value = div_quo;
    end
endmodule


module AsinInterpolate (
    input wire clk, 
    input wire start,
    input wire reset, 
    output reg done,  

    output reg [64:0]mul_in1, 
    output reg [64:0]mul_in2, 
    input wire [128:0]mul_out,

    output reg [5:0]asin_chart_address, 
    input wire [127:0]asin_chart_value, 

    input wire[63:0]input_value, 
    output reg [63:0]asin_interpolate_value
);  
    localparam S_IDLE = 3'b000;
    localparam S_SEARCH = 3'b001;
    localparam S_STORE_LEFT = 3'b010;
    localparam S_MUL_A = 3'b011;
    localparam S_MUL_B = 3'b100;
    localparam S_DIV = 3'b101; 
    localparam S_DIV_WAIT = 3'b110;
    localparam S_DONE = 3'b111;
    reg [2:0] state_r, next_state_r;

    reg [5:0]curr_r, bit_r;
    reg [63:0]input_value_r;
    
    reg [64:0] mul_in1_r, mul_in2_r;
    reg [128:0] mul_out1_r, mul_out2_r;
    reg [127:0] left_point_r, right_point_r;

    reg div_rst_r, div_start_r;
    reg [128:0]div_num_r, div_den_r;
    wire [128:0]div_quo;
    wire div_done;
    SeqDiv _div(.clk(clk), .rst(reset), .start(div_start_r), .num(div_num_r), .den(div_den_r), .quo(div_quo), .done(div_done));

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state_r <= S_IDLE;
            curr_r <= 6'b100000;
            bit_r <= 6'b100000;
        end else begin
            if (state_r == S_IDLE) begin
                input_value_r <= input_value;
                curr_r <= 6'b100000;
                bit_r <= 6'b100000;
            end else if (state_r == S_SEARCH) begin
                // binary serach
                curr_r <= (input_value < asin_chart_value[127:64]) ? ((curr_r ^ bit_r) | (bit_r >> 1)) : (curr_r | (bit_r >> 1));
                bit_r <= bit_r >> 1;
            end else if (state_r == S_STORE_LEFT) begin
                left_point_r <= asin_chart_value;
                curr_r <= curr_r + 1;
            end else if (state_r == S_MUL_A) begin
                // interpolate
                // y0 * (x1 - x0)
                mul_in1_r <= 65'(signed'(left_point_r[63:0]));
                mul_in2_r <= 65'(signed'(asin_chart_value[127:64] - left_point_r[127:64]));
                right_point_r <= asin_chart_value;
            end else if (state_r == S_MUL_B) begin
                mul_out1_r <= mul_out;
                // (x - x0) * (y1 - y0)
                mul_in1_r <= 65'(signed'(input_value - left_point_r[127:64]));
                mul_in2_r <= 65'(signed'(right_point_r[63:0] - left_point_r[63:0]));
            end else if (state_r == S_DIV) begin
                div_num_r <= 128'(signed'(right_point_r[63:0] - left_point_r[63:0]));
                div_den_r <= 128'(signed'(mul_out1_r + mul_out));
                div_start_r <= 1'b1;
            end else if (state_r == S_DIV_WAIT) begin
                div_start_r <= 1'b0;
            end
            state_r <= next_state_r;
        end
    end
    always @(*) begin
        next_state_r = state_r;
        case (state_r) 
            S_IDLE: if (start) next_state_r = S_SEARCH;
            S_SEARCH: if (~(|bit_r)) next_state_r = S_STORE_LEFT;
            S_STORE_LEFT: next_state_r = S_MUL_A;
            S_MUL_A: next_state_r = S_MUL_B;
            S_MUL_B: next_state_r = S_DIV;
            S_DIV: next_state_r = S_DIV_WAIT;
            S_DIV_WAIT: if (div_done) next_state_r = S_DONE;
            S_DONE: next_state_r = S_IDLE;
        endcase
    end
    always @(*) begin
        asin_chart_address = curr_r;
        done = (state_r == S_DONE);
        mul_in1 = mul_in1_r;
        mul_in2 = mul_in2_r;
        asin_interpolate_value = div_quo;
    end
endmodule



`timescale 1ns/10ps
module GPSDC(clk, reset_n, DEN, LON_IN, LAT_IN, COS_ADDR, COS_DATA, ASIN_ADDR, ASIN_DATA, Valid, a, D);

input              clk;
input              reset_n;
input              DEN;
input      [23:0]  LAT_IN; //8.16
input      [23:0]  LON_IN; //8.16
input      [95:0]  COS_DATA; //16.32(x) + 16.32(cosx)
output reg [6:0]   COS_ADDR;
input      [127:0] ASIN_DATA; //0.64(x) + 0.64(arcsin(sqrt(x)))
output reg [5:0]   ASIN_ADDR;
output reg         Valid;
output reg [39:0]  D; //8.32
output reg [63:0]  a; //0.64

parameter rad = 16'h477; //0.16
parameter R = 12756274;

reg [3:0] state;
reg [3:0] nextstate;

localparam IDLE0 = 4'd0;
localparam FINDCOSA = 4'd1;
localparam IDLE = 4'd2;
localparam FINDCOSB1 = 4'd3;
localparam FINDCOSB2 = 4'd4;
localparam FINDA = 4'd5;
localparam FINDASIN = 4'd6;
localparam FINDD = 4'd7;
localparam OUTPUT = 4'd8;

reg [23:0] phi_a;
reg [23:0] phi_b;
reg [23:0] lambda_a;
reg [23:0] lambda_b;

reg [47:0] cos_phi_a;
reg [47:0] cos_phi_b;
reg [47:0] cos_phi_mul;

wire signed [24:0] dif_phi;
wire signed [24:0] dif_lambda;

reg signed [24:0] dif_phi_rad;
reg signed [24:0] dif_lambda_rad;
wire signed [24:0] dif_phi_rad_div2;
wire signed [24:0] dif_lambda_rad_div2;
reg [47:0] sinsquare_phi;
reg [47:0] sinsquare_lambda;

reg [47:0] RHS;

reg [63:0] asin_a;



assign dif_phi = $signed({1'b0, phi_b}) - $signed({1'b0, phi_a});
assign dif_lambda = $signed({1'b0, lambda_b}) - $signed({1'b0, lambda_a});

assign dif_phi_rad_div2 = dif_phi_rad >>> 1;
assign dif_lambda_rad_div2 = dif_lambda_rad >>> 1;

assign a = sinsquare_phi + RHS;

reg [2:0] step;

reg [64:0] mul_a;
reg [64:0] mul_b;
wire [128:0] mul_o;

Multiply _mul(.a(mul_a), .b(mul_b), .o(mul_o));

reg cos_find_start, cos_done;
reg [47:0] COS_INPUT, COS_FOUND;

reg asin_find_start, asin_done;
reg [63:0] ASIN_INPUT, ASIN_FOUND;

wire [64:0] mul_a_cos;
wire [64:0] mul_b_cos;

wire [64:0] mul_a_asin;
wire [64:0] mul_b_asin;

reg [64:0] mul_a_main;
reg [64:0] mul_b_main;

CosInterpolate _cos(.clk(clk), .start(cos_find_start), .done(cos_done),  
    .mul_in1(mul_a_cos), .mul_in2(mul_b_cos), .mul_out(mul_o),
    .cos_chart_address(COS_ADDR), .cos_chart_value(COS_DATA), 
    .input_value(COS_INPUT), .cos_interpolate_value(COS_FOUND), .reset(~reset_n)
);

AsinInterpolate _asin(.clk(clk), .start(asin_find_start), .done(asin_done),  
    .mul_in1(mul_a_asin), .mul_in2(mul_b_asin), .mul_out(mul_o),
    .asin_chart_address(ASIN_ADDR), .asin_chart_value(ASIN_DATA), 
    .input_value(ASIN_INPUT), .asin_interpolate_value(ASIN_FOUND), .reset(~reset_n)
);

always @(*) begin
    if (state == FINDCOSA || state == FINDCOSB2) begin
        mul_a = mul_a_cos;
        mul_b = mul_b_cos;
    end else if (state == FINDASIN) begin
        mul_a = mul_a_asin;
        mul_b = mul_b_asin;
    end else begin
        mul_a = mul_a_main;
        mul_b = mul_b_main;
    end
end

always @(posedge clk or negedge reset_n) begin
    
    if(!reset_n) begin
        state <= IDLE0;
        Valid <= 1'b0;
        cos_find_start <= 1'b0;
        asin_find_start <= 1'b0;
        step <= 3'd0;
        D <= 40'd0;
    end
    else begin
        state <= nextstate;
        
        case(state)
        
        IDLE0: begin 
            Valid <= 1'b0;
            if (DEN) begin
                phi_a <= LAT_IN;
                lambda_a <= LON_IN;

                COS_INPUT <= LAT_IN;  //LAT_IN go inside findcos
                cos_find_start <= 1'b1;
            end
        end

        FINDCOSA: begin//findcos cycle
            Valid <= 1'b0;
            cos_find_start <= 1'b0;
            if (cos_done) begin
                cos_phi_a <= COS_FOUND;
            end
        end

        IDLE: begin
            Valid <= 1'b0;
            step <= 3'd0;

            if (DEN) begin
                phi_b <= LAT_IN;
                lambda_b <= LON_IN;
                COS_INPUT <= LAT_IN; //LAT_IN go inside findcos
                cos_find_start <= 1'b1;
                step <= 3'd0;
            end
        end

        FINDCOSB1: begin //max(4, findcos) cycle
            Valid <= 1'b0;
            cos_find_start <= 1'b0;

            case(step)
            
            3'd0: begin
                mul_a_main <= dif_phi;
                mul_b_main <= rad;
                step <= step + 1;                
            end
            3'd1: begin
                dif_phi_rad <= mul_o;
                mul_a_main <= dif_lambda;
                mul_b_main <= rad;
                step <= step + 1;
            end
            3'd2: begin
                dif_lambda_rad <= mul_o;
                mul_a_main <= dif_phi_rad_div2;
                mul_b_main <= dif_phi_rad_div2;
                step <= step + 1;
            end
            3'd3: begin
                sinsquare_phi <= mul_o;
                mul_a_main <= dif_lambda_rad_div2;
                mul_b_main <= dif_lambda_rad_div2;
                step <= step + 1;              
            end       
            3'd4: begin
                sinsquare_lambda <= mul_o;
            end
            endcase
        end

        FINDCOSB2: begin
            Valid <= 1'b0;
        
            if (cos_done) begin
                cos_phi_b <= COS_FOUND;
                step <= 3'd0;
            end
        end

        FINDA: begin//3 cycle
            Valid <= 1'b0;

            case(step)

            3'd0:begin
                mul_a_main <= cos_phi_a;
                mul_b_main <= cos_phi_b;
                step <= step + 1;
            end
            3'd1:begin
                mul_a_main <= mul_o;
                mul_b_main <= sinsquare_lambda;
                step <= step + 1;
            end
            3'd2:begin
                RHS <= mul_o;
                step <= 3'd0;
            end
            endcase
        end

        FINDASIN: begin//findasin cycle
            Valid <= 1'b0;

            case(step)

            1'b0: begin
                ASIN_INPUT <= a;
                asin_find_start <= 1'b1;
                step <= step + 1;
            end

            1'b1: begin    

                asin_find_start <= 1'b0;
                
                if (asin_done) begin
                    asin_a <= ASIN_FOUND;
                    step <= 3'd0;
                end
            end

            endcase

        end
        
        FINDD: begin//2 cycle
            Valid <= 1'b0;

            case(step)

            3'd0: begin
                mul_a_main <= asin_a;
                mul_b_main <= R;
                step <= step + 1;
            end
            3'd1: begin
                D <= mul_o;
            end
            endcase
        end

        OUTPUT:begin
            Valid <= 1'b1;
            step <= 3'd0;
            //swap b to a
            phi_a <= phi_b;
            lambda_a <= lambda_b;
            cos_phi_a <= cos_phi_b;
        end
        endcase
    end
end

always @(*) begin
    nextstate = state;
    
    case (state)
        IDLE0: begin
            if (DEN)
                nextstate = FINDCOSA;
            else
                nextstate = IDLE0;
        end
        FINDCOSA: begin
            if (cos_done)
                nextstate = IDLE;
            else
                nextstate = FINDCOSA;
        end
        IDLE: begin
            if (DEN)
                nextstate = FINDCOSB1;
            else
                nextstate = IDLE;
        end
        FINDCOSB1: begin
            if (step == 3'd4)
                nextstate = FINDCOSB2;
            else
                nextstate = FINDCOSB1;
        end
        FINDCOSB2: begin
            if (cos_done)
                nextstate = FINDA;
            else
                nextstate = FINDCOSB2;
        
        end
        FINDA: begin
            if (step == 3'd2)
                nextstate = FINDASIN;
            else
                nextstate = FINDA;
        end
        FINDASIN:  begin
            if (asin_done)
                nextstate = FINDD;
            else
                nextstate = FINDASIN;
        end
        FINDD: begin
            if (step == 3'd1)
                nextstate = OUTPUT;
            else
                nextstate = FINDD; 
        end
        OUTPUT: begin
            nextstate = IDLE;
        end
        
        default: begin
            nextstate = IDLE0;
        end

    endcase
end


`ifdef DEBUG
always @(posedge clk) begin

    if (state != FINDCOSA && state != FINDCOSB1 || state != FINDCOSB2 || state != FINDASIN) begin
        $strobe("[%0t] state=%0d next=%0d DEN=%b Valid=%b step=%0d cos_start=%b cos_done=%b asin_start=%b asin_done=%b mula=%f mulb=%f LAT_IN=%f LON_IN=%f phia=%f",
                $time, state, nextstate, DEN, Valid, step,
                cos_find_start, cos_done,
                asin_find_start, asin_done, mul_a, mul_b, 
                $itor(LAT_IN) / 65536.0, $itor(LON_IN) / 65536.0, $itor(phi_a) / 65536.0
        );
    end
end
`endif

endmodule
