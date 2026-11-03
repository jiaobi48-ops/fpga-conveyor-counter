`timescale 1ns/1ps
// Q0.8 isolated/foreground ratio, hysteresis and consecutive-frame confirmation.
module noise_policy_reference #(parameter integer PIXEL_BITS=32) (
    input wire clk,rst_n,stats_update,
    input wire [31:0] stats_frame_id,stats_epoch,stats_foreground,stats_isolated,
    input wire cfg_auto,
    input wire [7:0] cfg_on,cfg_off,cfg_confirm,
    input wire [15:0] cfg_min_foreground,
    output reg mode_valid,
    output reg [1:0] suggested_mode,
    output reg [31:0] mode_epoch,mode_frame_id
);
    reg seen,opening;
    reg [31:0] previous_id,epoch;
    reg [7:0] streak;
    wire same_epoch=seen&&stats_epoch==epoch;
    wire adjacent=same_epoch&&(stats_frame_id==previous_id+1'b1);
    wire [39:0] isolated_scaled={stats_isolated,8'd0};
    wire [39:0] on_bound=stats_foreground[PIXEL_BITS-1:0]*cfg_on;
    wire [39:0] off_bound=stats_foreground[PIXEL_BITS-1:0]*cfg_off;
    wire enough=stats_foreground>=cfg_min_foreground&&stats_foreground!=0;
    wire go_on=enough&&(isolated_scaled>=on_bound);
    wire go_off=(stats_foreground==0)||(enough&&isolated_scaled<=off_bound);
    wire current=same_epoch&&opening;
    wire change=current ? go_off : go_on;
    wire [8:0] next_streak=(adjacent ? {1'b0,streak} : 9'd0)+1'b1;
    wire commit=change&&next_streak>=cfg_confirm;
    wire next_open=commit ? !current : current;
    wire legal=cfg_auto&&cfg_on>cfg_off&&cfg_confirm!=0&&cfg_min_foreground!=0;
    always @(posedge clk) begin
        if(!rst_n) begin
            seen<=0;opening<=0;previous_id<=0;epoch<=0;streak<=0;
            mode_valid<=0;suggested_mode<=0;mode_epoch<=0;mode_frame_id<=0;
        end else if(stats_update) begin
            seen<=1;previous_id<=stats_frame_id;epoch<=stats_epoch;
            if(legal) begin
                opening<=next_open;
                streak<=change&&!commit ? next_streak[7:0] : 8'd0;
                mode_valid<=1;suggested_mode<=next_open ? 2'd3 : 2'd0;
                mode_epoch<=stats_epoch;mode_frame_id<=stats_frame_id;
            end else begin streak<=0;opening<=0;mode_valid<=0;end
        end
    end
endmodule

