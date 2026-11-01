`timescale 1ns/1ps
module lcd_video_bridge #(
    parameter integer WIDTH=800,HEIGHT=480,
    parameter integer AX0=416,AX1=420,BX0=376,BX1=380,Y0=96,Y1=128,
    parameter integer ON_PIXELS=52,OFF_PIXELS=25,WARM_GATE_LIMIT=32,
    parameter integer UX0=320,UX1=480,UY0=8,UY1=48,
    parameter integer UPPER_WARM_LIMIT=640,UPPER_DARK_LIMIT=3200
)(
    (* X_INTERFACE_INFO="xilinx.com:signal:clock:1.0 pixel_clk CLK" *)
    (* X_INTERFACE_PARAMETER="XIL_INTERFACENAME pixel_clk, FREQ_HZ 25000000" *)
    input wire pixel_clk,
    (* X_INTERFACE_INFO="xilinx.com:signal:clock:1.0 axi_clk CLK" *)
    (* X_INTERFACE_PARAMETER="XIL_INTERFACENAME axi_clk, FREQ_HZ 100000000" *)
    input wire axi_clk,reset_n,video_locked,
    input wire [23:0] video_rgb,
    input wire video_de,video_vsync,
    input wire [31:0] count_control,
    output wire [31:0] count_status,
    output reg [23:0] lcd_rgb,
    output reg lcd_de,
    output wire lcd_hs,lcd_vs,lcd_bl,lcd_clk,lcd_rst,ms7200_rst_n,
    input wire follow_active,follow_hold
);
    (* ASYNC_REG="TRUE" *) reg [1:0] reset_sync;
    always @(posedge pixel_clk or negedge reset_n)
        if(!reset_n)reset_sync<=0;
        else reset_sync<={reset_sync[0],1'b1};
    wire [15:0] ax0,bx0,gate_width,y0,y1,on_pixels,off_pixels,warm_limit;
    wire [7:0] threshold;
    wire enabled,show_mask,manual_mode,manual_block,rearm,clear_count,cfg_rejected;
    wire [23:0] cfg_epoch,session;
    wire [383:0] snapshot_source;
    wire frame_tick;
    reg frame_sample;
    (* ASYNC_REG="TRUE" *) reg [1:0] follow_a_sync,follow_h_sync;
    always @(posedge pixel_clk or negedge reset_n)begin
      if(!reset_n)begin follow_a_sync<=0;follow_h_sync<=0;end
      else begin follow_a_sync<={follow_a_sync[0],follow_active};follow_h_sync<={follow_h_sync[0],follow_hold};end
    end
    cup_control #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.AX0(AX0),.BX0(BX0),.GW(AX1-AX0),.Y0(Y0),.Y1(Y1)) u_control(
        .pixel_clk(pixel_clk),.axi_clk(axi_clk),.reset_n(reset_sync[1]),
        .request(count_control),.response(count_status),.frame_tick(frame_tick),
        .frame_sample(frame_sample),.video_locked(video_locked),.snapshot_source(snapshot_source),
        .ax0(ax0),.bx0(bx0),.gate_width(gate_width),.y0(y0),.y1(y1),
        .on_pixels(on_pixels),.off_pixels(off_pixels),.warm_limit(warm_limit),.threshold(threshold),
        .enabled(enabled),.show_mask(show_mask),.manual_mode(manual_mode),.manual_block(manual_block),.rearm(rearm),.clear_count(clear_count),
        .cfg_epoch(cfg_epoch),.session(session),.cfg_rejected(cfg_rejected));
    reg de_d,vs_d,have_frame,line_bad;
    reg [10:0] x;
    reg [9:0] y,line_count;
    reg [19:0] pixel_count;
    reg [15:0] a_pixels,b_pixels;
    reg [15:0] a_warm,b_warm,upper_warm,upper_dark;
    reg warm_veto,upper_veto,effective_blocked;
    assign frame_tick=video_vsync && !vs_d;
    wire frame_good=have_frame && video_locked && !line_bad &&
         pixel_count==WIDTH*HEIGHT && line_count==HEIGHT && !video_de;
    wire [9:0] luma_sum={2'b0,video_rgb[23:16]}+{1'b0,video_rgb[15:8],1'b0}+{2'b0,video_rgb[7:0]};
    wire dark_pixel=luma_sum[9:2]<threshold;
    wire warm_pixel=video_rgb[23:16]>80 &&
        {1'b0,video_rgb[23:16]}>{1'b0,video_rgb[15:8]}+9'd12 &&
        {1'b0,video_rgb[23:16]}>{1'b0,video_rgb[7:0]}+9'd16;
    // Eligible foreground is neutral/cool dark material as in the grey/blue cups.
    // This is scene-specific color screening, NOT semantic hand recognition.
    wire cup_pixel=dark_pixel &&
        {1'b0,video_rgb[23:16]}<={1'b0,video_rgb[15:8]}+9'd12 &&
        {1'b0,video_rgb[23:16]}<={1'b0,video_rgb[7:0]}+9'd16;
    wire frame_warm_veto=(a_warm>=warm_limit || b_warm>=warm_limit);
    wire frame_upper_veto=(upper_warm>=UPPER_WARM_LIMIT || upper_dark>=UPPER_DARK_LIMIT);
    wire effective_veto=manual_mode?manual_block:(frame_warm_veto || frame_upper_veto);
    always @(posedge pixel_clk)begin
        if(!reset_sync[1] || !video_locked)begin
            de_d<=0;vs_d<=video_vsync;have_frame<=0;line_bad<=0;
            x<=0;y<=0;line_count<=0;pixel_count<=0;a_pixels<=0;b_pixels<=0;
            a_warm<=0;b_warm<=0;upper_warm<=0;upper_dark<=0;warm_veto<=0;upper_veto<=0;effective_blocked<=0;
        end else begin
            de_d<=video_de;vs_d<=video_vsync;
            if(frame_tick)begin
                have_frame<=1;line_bad<=0;x<=0;y<=0;line_count<=0;
                pixel_count<=0;a_pixels<=0;b_pixels<=0;
                a_warm<=0;b_warm<=0;upper_warm<=0;upper_dark<=0;
                warm_veto<=frame_good && frame_warm_veto;
                upper_veto<=frame_good && frame_upper_veto;
                effective_blocked<=frame_good && effective_veto;
            end else begin
                if(video_de)begin
                    if(x<WIDTH && y<HEIGHT)begin
                        pixel_count<=pixel_count+1'b1;
                        if(y>=y0 && y<y1)begin
                            if(x>=ax0 && x<ax0+gate_width)begin
                                if(cup_pixel)a_pixels<=a_pixels+1'b1;
                                if(warm_pixel)a_warm<=a_warm+1'b1;
                            end
                            if(x>=bx0 && x<bx0+gate_width)begin
                                if(cup_pixel)b_pixels<=b_pixels+1'b1;
                                if(warm_pixel)b_warm<=b_warm+1'b1;
                            end
                        end
                        if(x>=UX0 && x<UX1 && y>=UY0 && y<UY1)begin
                            if(warm_pixel)upper_warm<=upper_warm+1'b1;
                            if(dark_pixel)upper_dark<=upper_dark+1'b1;
                        end
                    end else line_bad<=1;
                    if(x<2047)x<=x+1'b1;
                end
                if(de_d && !video_de)begin
                    if(x!=WIDTH)line_bad<=1;
                    x<=0;
                    if(y<1023)y<=y+1'b1;
                    if(line_count<1023)line_count<=line_count+1'b1;
                end
            end
        end
    end
    wire [19:0] count,count_gray;
    wire [23:0] count_bcd;
    wire gate_a,gate_b,saturated,frame_toggle;
    wire veto_seen,queue_overflow;
    wire [3:0] pending;
    wire [1:0] phase;
    // Losing video lock invalidates passage history even if no VSYNC arrives.
    // Total count is retained until explicit R/global reset.
    cup_passage #(.ON_PIXELS(ON_PIXELS),.OFF_PIXELS(OFF_PIXELS)) u_passage(
        .clk(pixel_clk),.reset_n(reset_sync[1]),
        .enable(enabled && video_locked && !rearm && !follow_h_sync[1]),.clear_count(clear_count),
        .frame_tick(frame_tick),.frame_good(frame_good),
        .reject_frame(effective_veto),
        .a_pixels(a_pixels>=on_pixels?16'd128:a_pixels<=off_pixels?16'd0:16'd32),
        .b_pixels(b_pixels>=on_pixels?16'd128:b_pixels<=off_pixels?16'd0:16'd32),
        .count(count),.count_gray(count_gray),.count_bcd(count_bcd),
        .gate_a(gate_a),.gate_b(gate_b),.phase(phase),
        .saturated(saturated),.frame_toggle(frame_toggle),.veto_seen(veto_seen),
        .queue_overflow(queue_overflow),.pending(pending));
    // Snapshot is captured one cycle AFTER the frame FSM consumes its inputs.
    // Counts, phase, diagnostic pixels, epoch and session belong to this boundary.
    reg [23:0] display_frame,bad_frames,blocked_frames;
    reg [15:0] last_a,last_b,last_aw,last_bw,last_uw,last_ud;
    reg last_follow_active,last_follow_hold;
    reg last_good,last_enabled,last_mask,last_manual_mode,last_manual_block;
    reg [7:0] last_threshold;
    reg [23:0] last_epoch;
    always @(posedge pixel_clk) begin
        if(!reset_sync[1])begin
            last_follow_active<=0;last_follow_hold<=0;frame_sample<=0;display_frame<=0;bad_frames<=0;blocked_frames<=0;
            last_a<=0;last_b<=0;last_aw<=0;last_bw<=0;last_uw<=0;last_ud<=0;last_good<=0;last_manual_mode<=0;last_manual_block<=0;
            last_epoch<=0;last_threshold<=144;last_enabled<=0;last_mask<=0;
        end else begin
            frame_sample<=frame_tick && video_locked;
            if(frame_tick && video_locked)begin
                last_follow_active<=follow_a_sync[1];last_follow_hold<=follow_h_sync[1];display_frame<=display_frame+1'b1;last_good<=frame_good;
                last_epoch<=cfg_epoch;last_threshold<=threshold;last_enabled<=enabled;last_mask<=show_mask;last_manual_mode<=manual_mode;last_manual_block<=manual_block;
                last_a<=a_pixels;last_b<=b_pixels;last_aw<=a_warm;last_bw<=b_warm;
                last_uw<=upper_warm;last_ud<=upper_dark;
                if(!frame_good && bad_frames!=24'hffffff)bad_frames<=bad_frames+1'b1;
                if(frame_good && effective_veto && blocked_frames!=24'hffffff)
                    blocked_frames<=blocked_frames+1'b1;
            end
        end
    end
    assign snapshot_source[0*24+:24]={gate_b,gate_a,phase,count};
    assign snapshot_source[1*24+:24]={11'd0,effective_blocked,last_manual_block,last_manual_mode,cfg_rejected,upper_veto,warm_veto,queue_overflow,veto_seen,saturated,
        (last_good&&video_locked),video_locked,last_mask,last_enabled};
    assign snapshot_source[2*24+:24]=display_frame;
    assign snapshot_source[3*24+:24]=last_epoch;
    assign snapshot_source[4*24+:24]=session;
    assign snapshot_source[5*24+:24]={4'd0,pending,last_a};
    assign snapshot_source[6*24+:24]={8'd0,last_b};
    assign snapshot_source[7*24+:24]={8'd0,last_aw};
    assign snapshot_source[8*24+:24]={8'd0,last_bw};
    assign snapshot_source[9*24+:24]={8'd0,last_uw};
    assign snapshot_source[10*24+:24]={8'd0,last_ud};
    assign snapshot_source[11*24+:24]=bad_frames;
    assign snapshot_source[12*24+:24]=blocked_frames;
    assign snapshot_source[13*24+:24]={16'd0,last_threshold};
    assign snapshot_source[14*24+:24]=24'hC30401;
    assign snapshot_source[15*24+:24]={22'd0,last_follow_hold,last_follow_active};
    wire [23:0] overlay_rgb;
    cup_overlay u_overlay(.ax0(ax0),.bx0(bx0),.gate_width(gate_width),.y0(y0),.y1(y1),.x(x),.y(y),.video_rgb(video_rgb),.count_bcd(count_bcd),
        .gate_a(gate_a),.gate_b(gate_b),.phase(phase),.enabled(enabled),
        .saturated(saturated),.show_mask(show_mask),.dark_pixel(cup_pixel),
        .warm_pixel(warm_pixel),.manual_mode(manual_mode),.follow_active(follow_a_sync[1]),.follow_hold(follow_h_sync[1]),.blocked(effective_blocked || follow_h_sync[1]),.rgb(overlay_rgb));
    always @(posedge pixel_clk)begin
        if(!reset_sync[1] || !video_locked)begin lcd_de<=0;lcd_rgb<=0;end
        else begin lcd_de<=video_de;lcd_rgb<=video_de?overlay_rgb:24'h000000;end
    end
    assign lcd_hs=1'b1,lcd_vs=1'b1;
    assign lcd_bl=reset_sync[1] && video_locked;
    assign lcd_rst=1'b1,ms7200_rst_n=1'b0;
    ODDR #(.DDR_CLK_EDGE("SAME_EDGE"),.INIT(1'b0),.SRTYPE("SYNC"))
        u_forward_clock(.C(pixel_clk),.CE(1'b1),.D1(1'b0),.D2(1'b1),.Q(lcd_clk),.R(1'b0),.S(1'b0));
endmodule
