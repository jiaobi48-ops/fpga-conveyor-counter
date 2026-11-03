`timescale 1ns/1ps
// Same-clock frame-report supervisor. No AXI/CDC and no autonomous clearing of totals.
// States: 0 bypass,1 uncalibrated,2 blocked,3 confirming,4 wait-empty,5 run,6 stale/fault.
module scene_recovery_supervisor #(
    parameter integer REPORT_PIPELINE=0, COUNT_BITS=32
) (
    input wire clk,rst_n,enable,scene_valid,explicit_rearm,integrity_fault,link_fault,
    input wire update,frame_good,geometry_good,guard_enabled,
    input wire [31:0] frame_id,source_id,source_generation,timestamp,epoch,
    input wire [31:0] roi_pixels,foreground_pixels,guard_pixels,guard_dark,guard_warm,
    input wire [8:0] cfg_dark_on,cfg_dark_off,cfg_warm_on,cfg_warm_off,cfg_empty_ratio,
    input wire [7:0] cfg_normal_frames,cfg_empty_frames,
    input wire [31:0] cfg_timeout_cycles,
    output reg [2:0] state,
    output reg [15:0] reason,current_frame_reason,sticky_reasons,
    output wire blocked,policy_hold,
    output reg history_flush,report_update,report_count_allowed,report_policy_allowed,
    output reg [31:0] report_frame_id,accepted_source_frames,duplicate_reports,stale_reports,blocked_frames,recoveries,
    output reg [31:0] age_cycles,
    output reg [7:0] normal_count,empty_count
);
    localparam [15:0] R_DARK=16'h0001,R_WARM=16'h0002,R_INVALID=16'h0004,R_STALE=16'h0008,
        R_CONFIG=16'h0010,R_CONFIRM=16'h0020,R_EMPTY=16'h0040,R_LINK=16'h0080,R_HISTORY=16'h0100;
    reg seen,dark_latched,warm_latched;
    reg [31:0] last_id,last_generation,last_epoch,last_timestamp;
    // Frame-rate arithmetic has its own stage; pixel throughput and fault inputs remain independent.
    // COUNT_BITS is dimension-bounded by the integrated front end; the default preserves 32-bit callers.
    localparam integer PRODUCT_BITS=COUNT_BITS+9;
    wire [PRODUCT_BITS-1:0] product_dark_on=guard_pixels[COUNT_BITS-1:0]*cfg_dark_on,
        product_dark_off=guard_pixels[COUNT_BITS-1:0]*cfg_dark_off,
        product_warm_on=guard_pixels[COUNT_BITS-1:0]*cfg_warm_on,
        product_warm_off=guard_pixels[COUNT_BITS-1:0]*cfg_warm_off,
        product_empty_bound=roi_pixels[COUNT_BITS-1:0]*cfg_empty_ratio;
    reg q_update;
    reg q_frame_good,q_geometry_good,q_guard_enabled;
    reg [31:0] q_frame_id,q_source_id,q_source_generation,q_timestamp,q_epoch,
        q_roi_pixels,q_foreground_pixels,q_guard_pixels,q_guard_dark,q_guard_warm;
    reg [PRODUCT_BITS-1:0] q_dark_on,q_dark_off,q_warm_on,q_warm_off,q_empty_bound;
    generate if(REPORT_PIPELINE) begin: report_stage
        // No reset on data registers permits the multiplier output registers to pack into DSPs.
        // q_update is the validity bit and discards all packets during reset or an immediate fault.
        always @(posedge clk) begin
            if(!rst_n||explicit_rearm||integrity_fault||link_fault)q_update<=0;
            else q_update<=update;
            q_frame_good<=frame_good;q_geometry_good<=geometry_good;q_guard_enabled<=guard_enabled;
            q_frame_id<=frame_id;q_source_id<=source_id;q_source_generation<=source_generation;
            q_timestamp<=timestamp;q_epoch<=epoch;
            q_roi_pixels<=roi_pixels;q_foreground_pixels<=foreground_pixels;q_guard_pixels<=guard_pixels;
            q_guard_dark<=guard_dark;q_guard_warm<=guard_warm;
            q_dark_on<=product_dark_on;q_dark_off<=product_dark_off;
            q_warm_on<=product_warm_on;q_warm_off<=product_warm_off;q_empty_bound<=product_empty_bound;
        end
    end endgenerate
    wire r_frame_good=REPORT_PIPELINE?q_frame_good:frame_good;
    wire r_geometry_good=REPORT_PIPELINE?q_geometry_good:geometry_good;
    wire r_guard_enabled=REPORT_PIPELINE?q_guard_enabled:guard_enabled;
    wire [31:0] r_frame_id=REPORT_PIPELINE?q_frame_id:frame_id;
    wire [31:0] r_source_id=REPORT_PIPELINE?q_source_id:source_id;
    wire [31:0] r_source_generation=REPORT_PIPELINE?q_source_generation:source_generation;
    wire [31:0] r_timestamp=REPORT_PIPELINE?q_timestamp:timestamp;
    wire [31:0] r_epoch=REPORT_PIPELINE?q_epoch:epoch;
    wire [31:0] r_roi_pixels=REPORT_PIPELINE?q_roi_pixels:roi_pixels;
    wire [31:0] r_foreground_pixels=REPORT_PIPELINE?q_foreground_pixels:foreground_pixels;
    wire [31:0] r_guard_pixels=REPORT_PIPELINE?q_guard_pixels:guard_pixels;
    wire [31:0] r_guard_dark=REPORT_PIPELINE?q_guard_dark:guard_dark;
    wire [31:0] r_guard_warm=REPORT_PIPELINE?q_guard_warm:guard_warm;
    wire r_update=REPORT_PIPELINE?q_update:update;
    wire [31:0] distance=r_source_id-last_id;
    wire new_context=!seen||r_source_generation!=last_generation||r_epoch!=last_epoch;
    wire forward=(distance!=0)&&!distance[31];
    wire fresh=new_context||forward;
    wire gap=seen&&!new_context&&distance!=1;
    wire legal=cfg_dark_on<=256&&cfg_dark_off<cfg_dark_on&&cfg_warm_on<=256&&cfg_warm_off<cfg_warm_on&&
        cfg_empty_ratio<=256&&cfg_normal_frames!=0&&cfg_empty_frames!=0&&cfg_timeout_cycles!=0;
    wire [40:0] dark_scaled={1'b0,r_guard_dark,8'd0},warm_scaled={1'b0,r_guard_warm,8'd0},fg_scaled={1'b0,r_foreground_pixels,8'd0};
    wire [40:0] dark_on=REPORT_PIPELINE?q_dark_on:product_dark_on,
        dark_off=REPORT_PIPELINE?q_dark_off:product_dark_off,
        warm_on=REPORT_PIPELINE?q_warm_on:product_warm_on,
        warm_off=REPORT_PIPELINE?q_warm_off:product_warm_off,
        empty_bound=REPORT_PIPELINE?q_empty_bound:product_empty_bound;
    wire dn=r_guard_enabled&&(new_context||!dark_latched?dark_scaled>=dark_on:dark_scaled>dark_off);
    wire wn=r_guard_enabled&&(new_context||!warm_latched?warm_scaled>=warm_on:warm_scaled>warm_off);
    wire valid=r_frame_good&&r_geometry_good&&r_roi_pixels!=0&&(!r_guard_enabled||r_guard_pixels!=0)&&
        r_foreground_pixels<=r_roi_pixels&&r_guard_dark<=r_guard_pixels&&r_guard_warm<=r_guard_pixels;
    wire empty=valid&&fg_scaled<=empty_bound;
    wire [15:0] pixel_reason=(dn?R_DARK:16'd0)|(wn?R_WARM:16'd0)|(!valid?R_INVALID:16'd0);
    wire timeout_now=age_cycles>=cfg_timeout_cycles-1'b1;
    assign blocked=enable&&state!=5;
    assign policy_hold=blocked;
    always @(posedge clk) begin
        if(!rst_n)begin
            state<=1;reason<=R_CONFIG;current_frame_reason<=0;sticky_reasons<=0;
            history_flush<=0;report_update<=0;report_count_allowed<=0;report_policy_allowed<=0;report_frame_id<=0;
            accepted_source_frames<=0;duplicate_reports<=0;stale_reports<=0;blocked_frames<=0;recoveries<=0;
            age_cycles<=0;normal_count<=0;empty_count<=0;seen<=0;dark_latched<=0;warm_latched<=0;
            last_id<=0;last_generation<=0;last_epoch<=0;last_timestamp<=0;
        end else begin
            history_flush<=0;report_update<=0;report_count_allowed<=0;report_policy_allowed<=0;
            if(age_cycles!=32'hffffffff)age_cycles<=age_cycles+1'b1;
            if(!enable)begin
                state<=0;reason<=0;normal_count<=0;empty_count<=0;dark_latched<=0;warm_latched<=0;age_cycles<=0;seen<=0;
                if(r_update)begin report_update<=1;report_frame_id<=r_frame_id;report_count_allowed<=1;report_policy_allowed<=1;end
            end else if(!scene_valid||!legal)begin
                if(state==5)history_flush<=1;
                state<=1;reason<=R_CONFIG;sticky_reasons<=sticky_reasons|R_CONFIG;normal_count<=0;empty_count<=0;
                if(r_update)begin report_update<=1;report_frame_id<=r_frame_id;current_frame_reason<=R_CONFIG;end
            end else if(explicit_rearm||integrity_fault||link_fault)begin
                history_flush<=1;state<=link_fault?6:3;reason<=link_fault?R_LINK:integrity_fault?R_INVALID:R_HISTORY;
                sticky_reasons<=sticky_reasons|(link_fault?R_LINK:integrity_fault?R_INVALID:R_HISTORY);
                normal_count<=0;empty_count<=0;
                if(explicit_rearm)begin seen<=0;age_cycles<=0;dark_latched<=0;warm_latched<=0;end
            end else if(r_update)begin
                report_update<=1;report_frame_id<=r_frame_id;current_frame_reason<=pixel_reason;
                if(!fresh)begin
                    if(distance==0)duplicate_reports<=duplicate_reports+1'b1;
                    else begin stale_reports<=stale_reports+1'b1;history_flush<=1;state<=6;reason<=R_HISTORY;normal_count<=0;empty_count<=0;end
                    if(timeout_now)begin history_flush<=1;state<=6;reason<=R_STALE;normal_count<=0;empty_count<=0;sticky_reasons<=sticky_reasons|R_STALE;end
                end else begin
                    seen<=1;last_id<=r_source_id;last_generation<=r_source_generation;last_epoch<=r_epoch;last_timestamp<=r_timestamp;
                    age_cycles<=0;accepted_source_frames<=accepted_source_frames+1'b1;
                    dark_latched<=dn;warm_latched<=wn;
                    if(pixel_reason!=0)begin
                        history_flush<=1;state<=2;reason<=pixel_reason;sticky_reasons<=sticky_reasons|pixel_reason;
                        normal_count<=0;empty_count<=0;blocked_frames<=blocked_frames+1'b1;
                    end else if(state==5&&!new_context&&!gap&&!timeout_now)begin
                        reason<=0;report_count_allowed<=1;report_policy_allowed<=1;
                    end else if(state==5||new_context||gap||state==0||state==1||state==2||state==6)begin
                        history_flush<=1;state<=cfg_normal_frames==1?4:3;reason<=cfg_normal_frames==1?R_EMPTY:R_CONFIRM;
                        normal_count<=1;empty_count<=0;
                    end else if(state==3)begin
                        if(normal_count<cfg_normal_frames)normal_count<=normal_count+1'b1;
                        if({1'b0,normal_count}+9'd1>=cfg_normal_frames)begin state<=4;reason<=R_EMPTY;empty_count<=0;end
                    end else if(state==4)begin
                        reason<=R_EMPTY;
                        if(empty)begin
                            if({1'b0,empty_count}+9'd1>=cfg_empty_frames)begin state<=5;reason<=0;empty_count<=0;recoveries<=recoveries+1'b1;history_flush<=1;end
                            else empty_count<=empty_count+1'b1;
                        end else empty_count<=0;
                    end
                end
            end else if(timeout_now)begin
                if(state!=6||reason!=R_STALE)history_flush<=1;
                state<=6;reason<=R_STALE;sticky_reasons<=sticky_reasons|R_STALE;normal_count<=0;empty_count<=0;
            end
        end
    end
endmodule
