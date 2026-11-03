`timescale 1ns/1ps
// One accepted RGB pixel/cycle; no frame RAM. All geometry is half-open and SOF bound.
// V3 model: (R+2G+B)/4 with neutral/cool screening. B model: BT.601 integer luma.
module scene_guard_statistics #(
    parameter integer WIDTH=640,HEIGHT=480,PIPELINED_STATS=0
)(
    input wire clk,rst_n,ce,in_valid,in_sof,in_eol,
    input wire [23:0] in_rgb,
    input wire [31:0] in_source_id,in_source_generation,in_timestamp,cfg_epoch,
    input wire cfg_guard_enable,cfg_v3_model,cfg_invert,
    input wire [7:0] cfg_threshold,
    input wire [15:0] cfg_roi_x0,cfg_roi_y0,cfg_roi_x1,cfg_roi_y1,
    input wire [15:0] cfg_guard_x0,cfg_guard_y0,cfg_guard_x1,cfg_guard_y1,
    output wire update,integrity_fault,frame_good,geometry_good,guard_enabled,
    output wire [31:0] frame_id,source_id,source_generation,timestamp,epoch,
    output wire [31:0] roi_pixels,foreground_pixels,guard_pixels,guard_dark,guard_warm,roi_gray_sum,
    output wire [31:0] rejected_frames
);
    // Register luma arithmetic with the complete pixel/configuration packet.
    wire p_in_valid;
    wire p_in_sof;
    wire p_in_eol;
    wire [23:0] p_in_rgb;
    wire [31:0] p_in_source_id;
    wire [31:0] p_in_source_generation;
    wire [31:0] p_in_timestamp;
    wire [31:0] p_cfg_epoch;
    wire p_cfg_guard_enable;
    wire p_cfg_v3_model;
    wire p_cfg_invert;
    wire [7:0] p_cfg_threshold;
    wire [15:0] p_cfg_roi_x0;
    wire [15:0] p_cfg_roi_y0;
    wire [15:0] p_cfg_roi_x1;
    wire [15:0] p_cfg_roi_y1;
    wire [15:0] p_cfg_guard_x0;
    wire [15:0] p_cfg_guard_y0;
    wire [15:0] p_cfg_guard_x1;
    wire [15:0] p_cfg_guard_y1;
    reg [293:0] packet;
    reg [15:0] weighted;
    reg [9:0] simple;
    reg neutral,warm;
    wire [7:0] r=in_rgb[23:16],g=in_rgb[15:8],b=in_rgb[7:0];
    generate if(PIPELINED_STATS) begin: pixel_pipeline
        always @(posedge clk) begin
            if(!rst_n)packet<=0;
            else if(ce)packet<={in_valid,in_sof,in_eol,in_rgb,in_source_id,in_source_generation,in_timestamp,cfg_epoch,cfg_guard_enable,cfg_v3_model,cfg_invert,cfg_threshold,cfg_roi_x0,cfg_roi_y0,cfg_roi_x1,cfg_roi_y1,cfg_guard_x0,cfg_guard_y0,cfg_guard_x1,cfg_guard_y1};
            if(ce)begin
                weighted<=16'd77*r+16'd150*g+16'd29*b+16'd128;
                simple<={2'd0,r}+{1'b0,g,1'b0}+{2'd0,b};
                neutral<={1'b0,r}<={1'b0,g}+9'd12&&{1'b0,r}<={1'b0,b}+9'd16;
                warm<=r>80&&{1'b0,r}>{1'b0,g}+9'd12&&{1'b0,r}>{1'b0,b}+9'd16;
            end
        end
        assign {p_in_valid,p_in_sof,p_in_eol,p_in_rgb,p_in_source_id,p_in_source_generation,p_in_timestamp,p_cfg_epoch,p_cfg_guard_enable,p_cfg_v3_model,p_cfg_invert,p_cfg_threshold,p_cfg_roi_x0,p_cfg_roi_y0,p_cfg_roi_x1,p_cfg_roi_y1,p_cfg_guard_x0,p_cfg_guard_y0,p_cfg_guard_x1,p_cfg_guard_y1}=packet;
    end else begin: direct_pixel
        assign p_in_valid=in_valid;
        assign p_in_sof=in_sof;
        assign p_in_eol=in_eol;
        assign p_in_rgb=in_rgb;
        assign p_in_source_id=in_source_id;
        assign p_in_source_generation=in_source_generation;
        assign p_in_timestamp=in_timestamp;
        assign p_cfg_epoch=cfg_epoch;
        assign p_cfg_guard_enable=cfg_guard_enable;
        assign p_cfg_v3_model=cfg_v3_model;
        assign p_cfg_invert=cfg_invert;
        assign p_cfg_threshold=cfg_threshold;
        assign p_cfg_roi_x0=cfg_roi_x0;
        assign p_cfg_roi_y0=cfg_roi_y0;
        assign p_cfg_roi_x1=cfg_roi_x1;
        assign p_cfg_roi_y1=cfg_roi_y1;
        assign p_cfg_guard_x0=cfg_guard_x0;
        assign p_cfg_guard_y0=cfg_guard_y0;
        assign p_cfg_guard_x1=cfg_guard_x1;
        assign p_cfg_guard_y1=cfg_guard_y1;
    end endgenerate
    scene_guard_statistics_core #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.PRECOMPUTED_GRAY(PIPELINED_STATS)) core(
        .clk(clk),
        .rst_n(rst_n),
        .ce(ce),
        .in_valid(p_in_valid),
        .in_sof(p_in_sof),
        .in_eol(p_in_eol),
        .in_rgb(p_in_rgb),
        .in_source_id(p_in_source_id),
        .in_source_generation(p_in_source_generation),
        .in_timestamp(p_in_timestamp),
        .cfg_epoch(p_cfg_epoch),
        .cfg_guard_enable(p_cfg_guard_enable),
        .cfg_v3_model(p_cfg_v3_model),
        .cfg_invert(p_cfg_invert),
        .cfg_threshold(p_cfg_threshold),
        .cfg_roi_x0(p_cfg_roi_x0),
        .cfg_roi_y0(p_cfg_roi_y0),
        .cfg_roi_x1(p_cfg_roi_x1),
        .cfg_roi_y1(p_cfg_roi_y1),
        .cfg_guard_x0(p_cfg_guard_x0),
        .cfg_guard_y0(p_cfg_guard_y0),
        .cfg_guard_x1(p_cfg_guard_x1),
        .cfg_guard_y1(p_cfg_guard_y1),
        .update(update),
        .integrity_fault(integrity_fault),
        .frame_good(frame_good),
        .geometry_good(geometry_good),
        .guard_enabled(guard_enabled),
        .frame_id(frame_id),
        .source_id(source_id),
        .source_generation(source_generation),
        .timestamp(timestamp),
        .epoch(epoch),
        .roi_pixels(roi_pixels),
        .foreground_pixels(foreground_pixels),
        .guard_pixels(guard_pixels),
        .guard_dark(guard_dark),
        .guard_warm(guard_warm),
        .roi_gray_sum(roi_gray_sum),
        .rejected_frames(rejected_frames),
        .pre_weighted(weighted),
        .pre_simple(simple),
        .pre_neutral(neutral),
        .pre_warm(warm));
endmodule

module scene_guard_statistics_core #(
    parameter integer WIDTH=640,HEIGHT=480,PRECOMPUTED_GRAY=0
)(
    input wire clk,rst_n,ce,in_valid,in_sof,in_eol,
    input wire [23:0] in_rgb,
    input wire [15:0] pre_weighted,input wire [9:0] pre_simple,
    input wire pre_neutral,pre_warm,
    input wire [31:0] in_source_id,in_source_generation,in_timestamp,cfg_epoch,
    input wire cfg_guard_enable,cfg_v3_model,cfg_invert,
    input wire [7:0] cfg_threshold,
    input wire [15:0] cfg_roi_x0,cfg_roi_y0,cfg_roi_x1,cfg_roi_y1,
    input wire [15:0] cfg_guard_x0,cfg_guard_y0,cfg_guard_x1,cfg_guard_y1,
    output reg update,integrity_fault,frame_good,geometry_good,guard_enabled,
    output reg [31:0] frame_id,source_id,source_generation,timestamp,epoch,
    output reg [31:0] roi_pixels,foreground_pixels,guard_pixels,guard_dark,guard_warm,roi_gray_sum,
    output reg [31:0] rejected_frames
);
    reg active,bad,legal_cfg,guard_on,v3,invert;
    reg [7:0] threshold;
    reg [15:0] x,y,rx0,ry0,rx1,ry1,gx0,gy0,gx1,gy1;
    // Legal frames contain at most WIDTH*HEIGHT pixels; interfaces remain 32 bits.
    localparam integer COUNT_BITS=$clog2(WIDTH*HEIGHT+1);
    localparam integer SUM_BITS=COUNT_BITS+8;
    reg [31:0] seq,current_id,sid,gen,stamp,tag;
    reg [COUNT_BITS-1:0] nr,nf,ng,nd,nw;
    reg [SUM_BITS-1:0] ns;
    wire [15:0] sx=in_sof?16'd0:x,sy=in_sof?16'd0:y;
    wire cfg_legal=cfg_roi_x0<cfg_roi_x1&&cfg_roi_x1<=WIDTH&&cfg_roi_y0<cfg_roi_y1&&cfg_roi_y1<=HEIGHT&&
        (!cfg_guard_enable||(cfg_guard_x0<cfg_guard_x1&&cfg_guard_x1<=WIDTH&&cfg_guard_y0<cfg_guard_y1&&cfg_guard_y1<=HEIGHT));
    wire [15:0] ax0=in_sof?cfg_roi_x0:rx0,ay0=in_sof?cfg_roi_y0:ry0,
        ax1=in_sof?cfg_roi_x1:rx1,ay1=in_sof?cfg_roi_y1:ry1;
    wire [15:0] bx0=in_sof?cfg_guard_x0:gx0,by0=in_sof?cfg_guard_y0:gy0,
        bx1=in_sof?cfg_guard_x1:gx1,by1=in_sof?cfg_guard_y1:gy1;
    wire model=in_sof?cfg_v3_model:v3,polarity=in_sof?cfg_invert:invert;
    wire gon=in_sof?cfg_guard_enable:guard_on;
    wire [7:0] th=in_sof?cfg_threshold:threshold;
    wire [7:0] r=in_rgb[23:16],g=in_rgb[15:8],b=in_rgb[7:0];
    wire [9:0] simple_sum=PRECOMPUTED_GRAY?pre_simple:{2'd0,r}+{1'b0,g,1'b0}+{2'd0,b};
    wire [15:0] weighted_sum=PRECOMPUTED_GRAY?pre_weighted:16'd77*r+16'd150*g+16'd29*b+16'd128;
    wire [7:0] gray=model?simple_sum[9:2]:weighted_sum[15:8];
    wire neutral=PRECOMPUTED_GRAY?pre_neutral:{1'b0,r}<={1'b0,g}+9'd12&&{1'b0,r}<={1'b0,b}+9'd16;
    wire warm=PRECOMPUTED_GRAY?pre_warm:r>80&&{1'b0,r}>{1'b0,g}+9'd12&&{1'b0,r}>{1'b0,b}+9'd16;
    wire fg=model?((gray<th)&&neutral):((gray>=th)^polarity);
    wire roi=sx>=ax0&&sx<ax1&&sy>=ay0&&sy<ay1;
    wire guard=gon&&sx>=bx0&&sx<bx1&&sy>=by0&&sy<by1;
    wire fault=!(in_sof||active)||(in_sof&&active)||(!in_sof&&bad)||sx>=WIDTH||sy>=HEIGHT||(in_eol!=(sx==WIDTH-1));
    wire [31:0] ar=(in_sof?32'd0:nr)+roi,af=(in_sof?32'd0:nf)+(roi&&fg),
        ag=(in_sof?32'd0:ng)+guard,ad=(in_sof?32'd0:nd)+(guard&&gray<th),aw=(in_sof?32'd0:nw)+(guard&&warm);
    wire [31:0] asum=(in_sof?32'd0:ns)+(roi?{24'd0,gray}:32'd0);
    always @(posedge clk) begin
        if(!rst_n) begin
            active<=0;bad<=0;legal_cfg<=0;guard_on<=0;v3<=0;invert<=0;threshold<=128;
            x<=0;y<=0;rx0<=0;ry0<=0;rx1<=0;ry1<=0;gx0<=0;gy0<=0;gx1<=0;gy1<=0;
            seq<=0;current_id<=0;sid<=0;gen<=0;stamp<=0;tag<=0;nr<=0;nf<=0;ng<=0;nd<=0;nw<=0;ns<=0;
            update<=0;integrity_fault<=0;frame_good<=0;geometry_good<=0;guard_enabled<=0;
            frame_id<=0;source_id<=0;source_generation<=0;timestamp<=0;epoch<=0;
            roi_pixels<=0;foreground_pixels<=0;guard_pixels<=0;guard_dark<=0;guard_warm<=0;roi_gray_sum<=0;rejected_frames<=0;
        end else begin
            update<=0;integrity_fault<=0;
            if(ce&&in_valid) begin
                if(in_sof) begin
                    seq<=seq+1'b1;current_id<=seq+1'b1;active<=1;
                    sid<=in_source_id;gen<=in_source_generation;stamp<=in_timestamp;tag<=cfg_epoch;
                    rx0<=cfg_roi_x0;ry0<=cfg_roi_y0;rx1<=cfg_roi_x1;ry1<=cfg_roi_y1;
                    gx0<=cfg_guard_x0;gy0<=cfg_guard_y0;gx1<=cfg_guard_x1;gy1<=cfg_guard_y1;
                    legal_cfg<=cfg_legal;guard_on<=cfg_guard_enable;v3<=cfg_v3_model;invert<=cfg_invert;threshold<=cfg_threshold;
                    if(active) begin integrity_fault<=1;rejected_frames<=rejected_frames+1'b1;end
                end
                bad<=fault;nr<=ar;nf<=af;ng<=ag;nd<=ad;nw<=aw;ns<=asum;
                if(sx==WIDTH-1)begin x<=0;y<=sy+1'b1;end else begin x<=sx+1'b1;y<=sy;end
                if(sx==WIDTH-1&&sy==HEIGHT-1) begin
                    active<=0;update<=1;frame_good<=!fault;
                    geometry_good<=in_sof?cfg_legal:legal_cfg;guard_enabled<=gon;
                    frame_id<=in_sof?seq+1'b1:current_id;
                    source_id<=in_sof?in_source_id:sid;source_generation<=in_sof?in_source_generation:gen;
                    timestamp<=in_sof?in_timestamp:stamp;epoch<=in_sof?cfg_epoch:tag;
                    roi_pixels<=ar;foreground_pixels<=af;guard_pixels<=ag;guard_dark<=ad;guard_warm<=aw;roi_gray_sum<=asum;
                    if(fault)begin integrity_fault<=1;rejected_frames<=rejected_frames+1'b1;end
                end
            end
        end
    end
endmodule
