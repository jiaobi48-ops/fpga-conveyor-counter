`timescale 1ns/1ps
// Q0.8 isolated/foreground ratio, hysteresis and consecutive-frame confirmation.
module dynamic_noise_policy #(parameter integer PIXEL_BITS=32,PIPELINED_PRODUCTS=0) (
    input wire clk,rst_n,stats_update,
    input wire [31:0] stats_frame_id,stats_epoch,stats_foreground,stats_isolated,
    input wire cfg_auto,
    input wire [7:0] cfg_on,cfg_off,cfg_confirm,
    input wire [15:0] cfg_min_foreground,
    output wire mode_valid,
    output wire [1:0] suggested_mode,
    output wire [31:0] mode_epoch,mode_frame_id
);
    // Optional coherent packet stage separates ratio multiplication from
    // hysteresis/history decisions. A reset cancels the entire pending report.
    wire valid_i;
    wire [39:0] on_i,off_i;
    wire [31:0] stats_frame_id_i;
    wire [31:0] stats_epoch_i;
    wire [31:0] stats_foreground_i;
    wire [31:0] stats_isolated_i;
    wire [0:0] cfg_auto_i;
    wire [7:0] cfg_on_i;
    wire [7:0] cfg_off_i;
    wire [7:0] cfg_confirm_i;
    wire [15:0] cfg_min_foreground_i;
    generate if(PIPELINED_PRODUCTS) begin: products
        reg valid_d;
        reg [39:0] on_d,off_d;
        reg [31:0] stats_frame_id_d;
        reg [31:0] stats_epoch_d;
        reg [31:0] stats_foreground_d;
        reg [31:0] stats_isolated_d;
        reg [0:0] cfg_auto_d;
        reg [7:0] cfg_on_d;
        reg [7:0] cfg_off_d;
        reg [7:0] cfg_confirm_d;
        reg [15:0] cfg_min_foreground_d;
        always @(posedge clk) begin
            if(!rst_n)valid_d<=0;else valid_d<=stats_update;
            on_d<=stats_foreground[PIXEL_BITS-1:0]*cfg_on;
            off_d<=stats_foreground[PIXEL_BITS-1:0]*cfg_off;
            stats_frame_id_d<=stats_frame_id;
            stats_epoch_d<=stats_epoch;
            stats_foreground_d<=stats_foreground;
            stats_isolated_d<=stats_isolated;
            cfg_auto_d<=cfg_auto;
            cfg_on_d<=cfg_on;
            cfg_off_d<=cfg_off;
            cfg_confirm_d<=cfg_confirm;
            cfg_min_foreground_d<=cfg_min_foreground;
        end
        assign valid_i=valid_d;assign on_i=on_d;assign off_i=off_d;
        assign stats_frame_id_i=stats_frame_id_d;
        assign stats_epoch_i=stats_epoch_d;
        assign stats_foreground_i=stats_foreground_d;
        assign stats_isolated_i=stats_isolated_d;
        assign cfg_auto_i=cfg_auto_d;
        assign cfg_on_i=cfg_on_d;
        assign cfg_off_i=cfg_off_d;
        assign cfg_confirm_i=cfg_confirm_d;
        assign cfg_min_foreground_i=cfg_min_foreground_d;
    end else begin: direct
        assign valid_i=stats_update;assign on_i=0;assign off_i=0;
        assign stats_frame_id_i=stats_frame_id;
        assign stats_epoch_i=stats_epoch;
        assign stats_foreground_i=stats_foreground;
        assign stats_isolated_i=stats_isolated;
        assign cfg_auto_i=cfg_auto;
        assign cfg_on_i=cfg_on;
        assign cfg_off_i=cfg_off;
        assign cfg_confirm_i=cfg_confirm;
        assign cfg_min_foreground_i=cfg_min_foreground;
    end endgenerate
    dynamic_noise_policy_decision #(.PIXEL_BITS(PIXEL_BITS),.PRECOMPUTED(PIPELINED_PRODUCTS)) decision(
        .clk(clk),.rst_n(rst_n),.stats_update(valid_i),
        .stats_frame_id(stats_frame_id_i),
        .stats_epoch(stats_epoch_i),
        .stats_foreground(stats_foreground_i),
        .stats_isolated(stats_isolated_i),
        .cfg_auto(cfg_auto_i),
        .cfg_on(cfg_on_i),
        .cfg_off(cfg_off_i),
        .cfg_confirm(cfg_confirm_i),
        .cfg_min_foreground(cfg_min_foreground_i),
        .product_on(on_i),.product_off(off_i),.mode_valid(mode_valid),
        .suggested_mode(suggested_mode),.mode_epoch(mode_epoch),.mode_frame_id(mode_frame_id)
    );
endmodule
`timescale 1ns/1ps
// Q0.8 isolated/foreground ratio, hysteresis and consecutive-frame confirmation.
module dynamic_noise_policy_decision #(parameter integer PIXEL_BITS=32,PRECOMPUTED=0) (
    input wire clk,rst_n,stats_update,
    input wire [31:0] stats_frame_id,stats_epoch,stats_foreground,stats_isolated,
    input wire cfg_auto,
    input wire [7:0] cfg_on,cfg_off,cfg_confirm,
    input wire [15:0] cfg_min_foreground,
    input wire [39:0] product_on,product_off,
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
    wire [39:0] on_bound=PRECOMPUTED ? product_on : stats_foreground[PIXEL_BITS-1:0]*cfg_on;
    wire [39:0] off_bound=PRECOMPUTED ? product_off : stats_foreground[PIXEL_BITS-1:0]*cfg_off;
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
