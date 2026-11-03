`timescale 1ns/1ps
// Binary support-projection correlation. All (2*MAX_SHIFT+1) foreground-overlap
// scores accumulate in parallel; synchronous BRAM scan uses two clocks/column.
// Signed dx=current_x-previous_x, negative means right-to-left. No predictions
// are sent to the counter. Output dt is measured from input SOF timestamps.
module projection_correlation_speed #(
    parameter integer WIDTH=640,MAX_OBJECTS=8,MAX_SHIFT=32
)(
    input wire clk,rst_n,flush,in_valid,output wire in_ready,
    input wire cfg_enable,input wire [15:0] cfg_min_foreground,cfg_margin,
    input wire [31:0] in_frame_id,in_timestamp,
    input wire [127:0] in_context,input wire in_is_test,
    input wire [7:0] in_count,input wire [MAX_OBJECTS*16-1:0] in_lefts,in_rights,
    output wire busy,output reg update,valid,
    output reg signed [15:0] dx,
    output reg [31:0] cycles_per_frame,frame_id,
    output reg [127:0] context_tag,output reg is_test,
    output reg [15:0] overlap,second_overlap,foreground_pixels,
    output reg [7:0] reason
);
    localparam IDLE=0,READ=1,ACCUM=2,PEAK=3,REPORT=4;
    localparam CANDIDATES=2*MAX_SHIFT+1;
    reg [2:0] state;assign busy=state!=IDLE;assign in_ready=state==IDLE&&!flush;
    (* ram_style="block" *) reg memory0[0:WIDTH-1];
    (* ram_style="block" *) reg memory1[0:WIDTH-1];
    reg q0,q1,history_valid,previous_bank,write_bank,can_compare;
    reg [31:0] previous_id,previous_timestamp,fid,stamp;
    reg [127:0] previous_context,ctx;reg previous_test,test;
    reg [15:0] lefts[0:MAX_OBJECTS-1],rights[0:MAX_OBJECTS-1];reg [7:0] count;
    reg [15:0] minimum,margin,score[0:CANDIDATES-1],population,previous_population;
    reg [2*MAX_SHIFT:0] window;
    // Include the signed halo (-MAX_SHIFT) and the terminal scan position.
    // Bounded addresses avoid synthesizing 32-bit add/compare chains.
    localparam integer SCAN_BITS=$clog2(WIDTH+MAX_SHIFT+2)+1;
    localparam integer SHIFT_BITS=$clog2(CANDIDATES+1)+1;
    reg signed [SCAN_BITS-1:0] scan,column;
    reg signed [SHIFT_BITS-1:0] peak_index,best_index;
    integer k;
    wire [2*MAX_SHIFT:0] next_window={window[2*MAX_SHIFT-1:0],(scan<WIDTH&&can_compare)?(previous_bank?q1:q0):1'b0};
    reg current_bit;
    reg batch_bad;
    reg [15:0] best,second;
    reg [7:0] initial_reason;
    always @* begin
        column=scan-MAX_SHIFT;current_bit=0;
        for(integer n=0;n<MAX_OBJECTS;n=n+1)
            if(n<count&&column>=0&&column<WIDTH&&column>=lefts[n]&&column<=rights[n])current_bit=1;
    end
    always @(posedge clk) begin
        if(state==READ&&scan<WIDTH&&can_compare) begin
            if(previous_bank)q1<=memory1[scan];else q0<=memory0[scan];
        end
        if(state==ACCUM&&!flush&&column>=0&&column<WIDTH) begin
            if(write_bank)memory1[column]<=current_bit;else memory0[column]<=current_bit;
        end
    end
    always @(posedge clk) begin
        update<=0;
        if(!rst_n) begin
            state<=IDLE;history_valid<=0;previous_bank<=0;write_bank<=0;
            previous_id<=0;previous_timestamp<=0;previous_context<=0;previous_test<=0;
            update<=0;valid<=0;dx<=0;cycles_per_frame<=0;frame_id<=0;context_tag<=0;is_test<=0;
            overlap<=0;second_overlap<=0;foreground_pixels<=0;reason<=0;scan<=0;count<=0;
        end else if(flush) begin state<=IDLE;history_valid<=0;valid<=0;end
        else case(state)
        IDLE: if(in_valid) begin
            fid<=in_frame_id;stamp<=in_timestamp;ctx<=in_context;test<=in_is_test;
            count<=in_count;minimum<=cfg_min_foreground;margin<=cfg_margin;
            frame_id<=in_frame_id;context_tag<=in_context;is_test<=in_is_test;
            batch_bad=in_count>MAX_OBJECTS;
            for(k=0;k<MAX_OBJECTS;k=k+1)if(k<in_count&&
                (in_lefts[16*k+:16]>in_rights[16*k+:16]||in_rights[16*k+:16]>=WIDTH||
                 (k>0&&in_lefts[16*k+:16]<=in_rights[16*(k-1)+:16])))batch_bad=1;
            if(!cfg_enable||batch_bad) begin
                update<=1;valid<=0;reason<=!cfg_enable?8'h80:8'h08;dx<=0;cycles_per_frame<=0;
                overlap<=0;second_overlap<=0;foreground_pixels<=0;history_valid<=0;
            end
            else begin
                initial_reason<=!history_valid ? 8'h01 :
                    (in_context!=previous_context||in_is_test!=previous_test) ? 8'h02 :
                    in_frame_id!=previous_id+1'b1 ? 8'h04 : in_timestamp==previous_timestamp ? 8'h08 : 8'h00;
                can_compare<=history_valid&&in_context==previous_context&&in_is_test==previous_test&&
                    in_frame_id==previous_id+1'b1&&in_timestamp!=previous_timestamp;
                write_bank<=~previous_bank;scan<=0;window<=0;population<=0;previous_population<=0;
                for(k=0;k<MAX_OBJECTS;k=k+1)begin lefts[k]<=in_lefts[16*k+:16];rights[k]<=in_rights[16*k+:16];end
                for(k=0;k<CANDIDATES;k=k+1)score[k]<=0;
                state<=READ;
            end
        end
        READ: state<=ACCUM;
        ACCUM: begin
            window<=next_window;
            if(scan<WIDTH&&can_compare)previous_population<=previous_population+(previous_bank?q1:q0);
            if(column>=0&&column<WIDTH)begin
                population<=population+current_bit;
                for(k=0;k<CANDIDATES;k=k+1)score[k]<=score[k]+(current_bit&&next_window[k]);
            end
            if(scan==WIDTH+MAX_SHIFT-1) begin peak_index<=0;best<=0;second<=0;best_index<=MAX_SHIFT;state<=PEAK;end
            else begin scan<=scan+1;state<=READ;end
        end
        PEAK: begin
            if(score[peak_index]>best) begin second<=best;best<=score[peak_index];best_index<=peak_index;end
            else if(score[peak_index]>second)second<=score[peak_index];
            if(peak_index==CANDIDATES-1)state<=REPORT;else peak_index<=peak_index+1;
        end
        REPORT: begin
            update<=1;frame_id<=fid;context_tag<=ctx;is_test<=test;dx<=best_index-MAX_SHIFT;
            cycles_per_frame<=stamp-previous_timestamp;overlap<=best;second_overlap<=second;foreground_pixels<=population;
            reason<=initial_reason|((population<minimum||previous_population<minimum||best<minimum)?8'h10:0)|
                ((best<=second||best-second<margin)?8'h20:0)|((best_index==0||best_index==CANDIDATES-1)?8'h40:0);
            valid<=initial_reason==0&&minimum!=0&&margin!=0&&count<=MAX_OBJECTS&&
                population>=minimum&&previous_population>=minimum&&best>=minimum&&best>second&&best-second>=margin&&
                best_index>0&&best_index<CANDIDATES-1;
            if(minimum==0||margin==0||count>MAX_OBJECTS)reason<=8'h08;
            previous_id<=fid;previous_timestamp<=stamp;previous_context<=ctx;previous_test<=test;
            previous_bank<=write_bank;history_valid<=1;state<=IDLE;
        end
        default:state<=IDLE;
        endcase
    end
endmodule
