`timescale 1ns/1ps

// Ordered-column reducer. start latches one scan's configuration.
// cut_update events are provisional until the surrounding scanner commits.
module projection_valley_counter #(parameter integer PIPELINED=0) (
    input wire clk,rst_n,start,sample_valid,
    input wire [15:0] sample_x,sample_value,
    input wire sample_last,
    input wire [15:0] cfg_high,cfg_low,cfg_min_width,cfg_gap,
    input wire cfg_valley_enable,
    input wire [7:0] cfg_valley_ratio,
    input wire [15:0] cfg_valley_depth,cfg_valley_width,cfg_peak_distance,cfg_peak_support,
    output reg done,cut_update,
    output reg [15:0] count,cut_count,cut_x
);
    reg [15:0] high_t,low_t,min_t,gap_t,depth_t,vwidth_t,distance_t,support_t;
    reg [7:0] ratio_t;
    reg enable_t,active;
    reg [15:0] begin_x,last_support,gaps,segment_cuts,piece_begin;
    reg [15:0] left_peak,left_x,high_run;
    reg left_qualified;
    // 0 tracking left peak, 1 contiguous valley, 2 waiting for right support.
    reg [1:0] phase;
    reg [15:0] valley_begin,valley_end,valley_min,valley_run;
    reg [15:0] right_begin,right_peak,right_x,right_run;
    reg [15:0] total,total_cuts;
    // The pipelined scanner leaves three clocks between accepted columns.
    // Pixel processing remains independent; only blanking-time column reduction is scheduled.
    reg v1,v2,last1,last2;
    reg [15:0] x1,x2,value1,value2;
    reg [23:0] product_left1,product_right1;
    reg valley2,right2,gap_close2,close_width2,final_width2,right_geometry2;
    reg [15:0] middle1,middle2;
    reg [15:0] cached_total,cached_cuts;
    wire [23:0] scaled1={value1,8'd0};
    wire valley1=scaled1<=product_left1&&value1<=left_peak&&left_peak-value1>=depth_t;
    wire right1=value1>=high_t&&{valley_min,8'd0}<=product_right1&&
        value1>=valley_min&&value1-valley_min>=depth_t;
    wire [16:0] middle_sum={1'b0,valley_begin}+{1'b0,valley_end};
    wire [15:0] middle_raw=middle_sum[16:1];
    wire [15:0] candidate_right_begin1=right_run==0?x1:right_begin;
    wire [15:0] final_support1=value1>low_t?x1:last_support;
    generate if(PIPELINED) begin: column_pipeline
        always @(posedge clk) begin
            if(!rst_n||start)begin v1<=0;v2<=0;end
            else begin v1<=sample_valid;v2<=v1;end
            x1<=sample_x;value1<=sample_value;last1<=sample_last;
            product_left1<=left_peak*ratio_t;product_right1<=sample_value*ratio_t;
            x2<=x1;value2<=value1;last2<=last1;valley2<=valley1;right2<=right1;
            // The scanner spaces input columns by three clocks. State from
            // the previous column is stable throughout these two stages.
            // Register the midpoint before doing endpoint geometry; keep
            // the final cut decision separate from the count increment.
            middle1<=middle_raw;middle2<=middle1;
            gap_close2<=value1<=low_t&&{1'b0,gaps}+17'd1>=gap_t;
            close_width2<={1'b0,last_support}-{1'b0,begin_x}+17'd1>=min_t;
            final_width2<=active?({1'b0,final_support1}-{1'b0,begin_x}+17'd1>=min_t):(min_t<=16'd1);
            right_geometry2<=right_run+16'd1>=support_t&&
                {1'b0,candidate_right_begin1}-{1'b0,left_x}>=distance_t&&
                {1'b0,middle1}-{1'b0,piece_begin}+17'd1>=min_t&&
                {1'b0,x1}-{1'b0,middle1}>=min_t;
            cached_total<=total+segment_cuts+16'd1;cached_cuts<=total_cuts+segment_cuts;
        end
    end endgenerate
    wire accept=PIPELINED?v2:sample_valid;
    wire [15:0] s_x=PIPELINED?x2:sample_x,s_value=PIPELINED?value2:sample_value;
    wire s_last=PIPELINED?last2:sample_last;
    wire [15:0] right_run_increment=right_run+16'd1;
    wire [15:0] candidate_right_begin=right_run==0?s_x:right_begin;
    wire [23:0] value_scaled={s_value,8'b0};
    wire [23:0] left_product=left_peak*ratio_t;
    wire [23:0] right_product=s_value*ratio_t;
    wire valley_low=PIPELINED?valley2:(value_scaled<=left_product)&&(s_value<=left_peak)&&
                    (left_peak-s_value>=depth_t);
    wire right_ok=PIPELINED?right2:(s_value>=high_t)&&({valley_min,8'b0}<=right_product)&&
                  (s_value>=valley_min)&&(s_value-valley_min>=depth_t);
    wire [15:0] middle=PIPELINED?middle2:middle_raw;

    // Next-state variables keep final-column flushing and cut confirmation in
    // the same transaction. Products use 24 bits; no division hardware.
    reg a_n,lq_n;
    reg [15:0] b_n,last_n,g_n,sc_n,pb_n,lp_n,lx_n,hr_n;
    reg [1:0] ph_n;
    reg [15:0] vb_n,ve_n,vm_n,vr_n,rb_n,rp_n,rx_n,rr_n,t_n,tc_n;
    reg cut_n;
    reg [15:0] cut_pos_n;
    always @* begin
        a_n=active;b_n=begin_x;last_n=last_support;g_n=gaps;sc_n=segment_cuts;
        pb_n=piece_begin;lp_n=left_peak;lx_n=left_x;hr_n=high_run;lq_n=left_qualified;
        ph_n=phase;vb_n=valley_begin;ve_n=valley_end;vm_n=valley_min;vr_n=valley_run;
        rb_n=right_begin;rp_n=right_peak;rx_n=right_x;rr_n=right_run;
        t_n=total;tc_n=total_cuts;cut_n=0;cut_pos_n=middle;
        if(!active) begin
            if(s_value>=high_t) begin
                a_n=1;b_n=s_x;last_n=s_x;g_n=0;sc_n=0;pb_n=s_x;
                lp_n=s_value;lx_n=s_x;hr_n=1;lq_n=(support_t==1);
                ph_n=0;vr_n=0;rr_n=0;
            end
        end else begin
            if(s_value>low_t) begin last_n=s_x;g_n=0;end
            else g_n=gaps+1'b1;
            // Ordinary low gaps take precedence; no valley cut across a closed segment.
            if(PIPELINED?gap_close2:(s_value<=low_t&&{1'b0,gaps}+17'd1>=gap_t)) begin
                if(PIPELINED?close_width2:({1'b0,last_support}-{1'b0,begin_x}+17'd1>=min_t)) begin
                    t_n=PIPELINED?cached_total:total+segment_cuts+1'b1;tc_n=PIPELINED?cached_cuts:total_cuts+segment_cuts;
                end
                a_n=0;ph_n=0;rr_n=0;
            end else if(enable_t) begin
                if(phase==0) begin
                    if(s_value>=high_t&&!valley_low) hr_n=high_run+1'b1;
                    else hr_n=0;
                    if(hr_n>=support_t) lq_n=1;
                    if(s_value>left_peak) begin lp_n=s_value;lx_n=s_x;end
                    if(left_qualified&&valley_low) begin
                        ph_n=1;vb_n=s_x;ve_n=s_x;vm_n=s_value;vr_n=1;rr_n=0;
                    end
                end else if(valley_low) begin
                    if(phase==1) begin
                        ve_n=s_x;vr_n=valley_run+1'b1;
                        if(s_value<valley_min) vm_n=s_value;
                    end else begin
                        // A new dip before right confirmation replaces the candidate.
                        ph_n=1;vb_n=s_x;ve_n=s_x;vm_n=s_value;vr_n=1;
                    end
                    rr_n=0;
                end else if(valley_run<vwidth_t) begin
                    ph_n=0;rr_n=0;hr_n=(s_value>=high_t) ? 16'd1 : 16'd0;
                    if(s_value>left_peak) begin lp_n=s_value;lx_n=s_x;end
                end else begin
                    ph_n=2;
                    if(right_ok) begin
                        rr_n=right_run+1'b1;
                        if(right_run==0) begin
                            rb_n=s_x;rp_n=s_value;rx_n=s_x;
                        end else if(s_value>right_peak) begin rp_n=s_value;rx_n=s_x;end
                    end else rr_n=0;
                    if(right_ok&&(PIPELINED?right_geometry2:(right_run_increment>=support_t&&
                       {1'b0,candidate_right_begin}-{1'b0,left_x}>=distance_t&&
                       {1'b0,middle}-{1'b0,piece_begin}+17'd1>=min_t&&
                       {1'b0,s_x}-{1'b0,middle}>=min_t))) begin
                        sc_n=segment_cuts+1'b1;cut_n=1;
                        pb_n=middle+1'b1;lp_n=rp_n;lx_n=rx_n;
                        hr_n=rr_n;lq_n=1;ph_n=0;vr_n=0;rr_n=0;
                    end
                end
            end
        end
        if(s_last&&a_n) begin
            if(PIPELINED?final_width2:({1'b0,last_n}-{1'b0,b_n}+17'd1>=min_t)) begin
                t_n=PIPELINED?(active?cached_total+cut_n:total+16'd1):t_n+sc_n+1'b1;
                tc_n=PIPELINED?(active?cached_cuts+cut_n:total_cuts):tc_n+sc_n;
            end
            a_n=0;
        end
    end
    always @(posedge clk) begin
        if(!rst_n) begin
            high_t<=0;low_t<=0;min_t<=0;gap_t<=0;enable_t<=0;ratio_t<=0;
            depth_t<=0;vwidth_t<=0;distance_t<=0;support_t<=0;
            active<=0;begin_x<=0;last_support<=0;gaps<=0;segment_cuts<=0;piece_begin<=0;
            left_peak<=0;left_x<=0;high_run<=0;left_qualified<=0;phase<=0;
            valley_begin<=0;valley_end<=0;valley_min<=0;valley_run<=0;
            right_begin<=0;right_peak<=0;right_x<=0;right_run<=0;total<=0;total_cuts<=0;
            done<=0;cut_update<=0;count<=0;cut_count<=0;cut_x<=0;
        end else begin
            done<=0;cut_update<=0;
            if(start) begin
                high_t<=cfg_high;low_t<=cfg_low;min_t<=cfg_min_width;gap_t<=cfg_gap;
                enable_t<=cfg_valley_enable;ratio_t<=cfg_valley_ratio;depth_t<=cfg_valley_depth;
                vwidth_t<=cfg_valley_width;distance_t<=cfg_peak_distance;support_t<=cfg_peak_support;
                active<=0;total<=0;total_cuts<=0;phase<=0;segment_cuts<=0;
                high_run<=0;left_qualified<=0;right_run<=0;gaps<=0;
            end else if(accept) begin
                active<=a_n;begin_x<=b_n;last_support<=last_n;gaps<=g_n;segment_cuts<=sc_n;
                piece_begin<=pb_n;left_peak<=lp_n;left_x<=lx_n;high_run<=hr_n;left_qualified<=lq_n;
                phase<=ph_n;valley_begin<=vb_n;valley_end<=ve_n;valley_min<=vm_n;valley_run<=vr_n;
                right_begin<=rb_n;right_peak<=rp_n;right_x<=rx_n;right_run<=rr_n;
                total<=t_n;total_cuts<=tc_n;cut_update<=cut_n;
                if(cut_n) cut_x<=cut_pos_n;
                if(s_last) begin done<=1;count<=t_n;cut_count<=tc_n;end
            end
        end
    end
endmodule
