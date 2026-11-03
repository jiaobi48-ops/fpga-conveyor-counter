`timescale 1ns/1ps
// Restoring division: one job, 32 physical clocks, no combinational '/' operator.
module unsigned_divider32 (
    input wire clk,rst_n,start,
    input wire [31:0] numerator,denominator,
    output reg busy,done,divide_by_zero,
    output reg [31:0] quotient
);
    reg [31:0] q,d;
    reg [32:0] remainder;
    reg [5:0] iteration;
    wire [32:0] shifted={remainder[31:0],q[31]};
    wire subtract=shifted>={1'b0,d};
    wire [31:0] next_q={q[30:0],subtract};
    always @(posedge clk) begin
        if(!rst_n) begin
            busy<=0;done<=0;divide_by_zero<=0;quotient<=0;
            q<=0;d<=0;remainder<=0;iteration<=0;
        end else begin
            done<=0;
            if(start&&!busy) begin
                divide_by_zero<=denominator==0;
                if(denominator==0) begin quotient<=0;done<=1;end
                else begin busy<=1;q<=numerator;d<=denominator;remainder<=0;iteration<=0;end
            end else if(busy) begin
                q<=next_q;remainder<=subtract ? shifted-{1'b0,d} : shifted;
                if(iteration==31) begin busy<=0;done<=1;quotient<=next_q;end
                else iteration<=iteration+1'b1;
            end
        end
    end
endmodule
