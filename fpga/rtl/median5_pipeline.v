`timescale 1ns/1ps
// Five odd/even compare-exchange layers. One comparator per register stage.
module median5_pipeline #(parameter integer TAG_WIDTH=64) (
    input wire clk,rst_n,flush,in_valid,
    input wire [15:0] a,b,c,d,e,
    input wire [TAG_WIDTH-1:0] in_tag,
    output wire out_valid,
    output wire [15:0] median,
    output wire [TAG_WIDTH-1:0] out_tag
);
    reg [15:0] v[0:24];
    reg [4:0] valid;
    reg [TAG_WIDTH-1:0] tag[0:4];
    wire [15:0] inputs[0:4];
    assign inputs[0]=a;assign inputs[1]=b;assign inputs[2]=c;
    assign inputs[3]=d;assign inputs[4]=e;
    genvar s,j;
    generate for(s=0;s<5;s=s+1) begin: stage
        for(j=0;j<5;j=j+1) begin: element
            wire [15:0] value;
            if(s==0) begin: first
                assign value=inputs[j];
            end else begin: later
                assign value=v[(s-1)*5+j];
            end
            if((j%2)==(s%2)&&j<4) begin: smaller
                wire [15:0] partner;
                if(s==0) assign partner=inputs[j+1];
                else assign partner=v[(s-1)*5+j+1];
                always @(posedge clk) v[s*5+j]<=value<partner ? value : partner;
            end else if(j>0&&((j-1)%2)==(s%2)) begin: larger
                wire [15:0] partner;
                if(s==0) assign partner=inputs[j-1];
                else assign partner=v[(s-1)*5+j-1];
                always @(posedge clk) v[s*5+j]<=value>partner ? value : partner;
            end else begin: unchanged
                always @(posedge clk) v[s*5+j]<=value;
            end
        end
    end endgenerate
    integer k;
    always @(posedge clk) begin
        if(!rst_n||flush) begin valid<=0;for(k=0;k<5;k=k+1) tag[k]<=0;end
        else begin
            valid<={valid[3:0],in_valid};tag[0]<=in_tag;
            for(k=1;k<5;k=k+1) tag[k]<=tag[k-1];
        end
    end
    assign out_valid=valid[4];assign median=v[22];assign out_tag=tag[4];
endmodule
