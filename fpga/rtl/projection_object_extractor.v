`timescale 1ns/1ps

// Reconstruct intervals only from a complete, committed projection scan.
// A cut is provisional until commit_valid; nothing reaches the tracker earlier.
// Interval endpoints are inclusive. Cuts divide [left,cut] and [cut+1,right].
// All controls use the physical clk, independently of video ce.
// batch_* is immutable while batch_valid && !batch_ready. flush cancels it.
// Incoming scans cannot overwrite a scan being processed or a held batch.
// Fault reasons: 1 sample order/ID; 2 cut order/ID/range; 3 incomplete/bad
// commit; 4 configuration; 5 object capacity; 6 count mismatch; 7 busy
// collision; 8 orphan cut/too-short split; 9 new scan before old commit.
// One-clock packet stage cuts the scan-validation path; flush also cancels queued inputs.
module projection_object_extractor #(
    parameter integer WIDTH=640,
    parameter integer MAX_OBJECTS=8, PIPELINED_FAULT_COUNTER=0,
    parameter integer TAG_WIDTH=129
) (
    input wire clk,rst_n,flush,
    input wire sample_valid,
    input wire [15:0] sample_x,sample_value,
    input wire [31:0] sample_frame_id,
    input wire cut_valid,
    input wire [15:0] cut_x,
    input wire [31:0] cut_frame_id,
    input wire commit_valid,
    input wire [31:0] commit_frame_id,
    input wire [TAG_WIDTH-1:0] commit_tag,
    input wire [15:0] commit_count,commit_cut_count,
    input wire [15:0] commit_high,commit_low,commit_min_width,commit_gap,
    output reg batch_valid,
    input wire batch_ready,
    output reg [TAG_WIDTH-1:0] batch_tag,
    output reg [7:0] batch_count,
    output reg [MAX_OBJECTS*16-1:0] batch_lefts,batch_rights,
    output wire busy,
    output reg fault,fault_sticky,
    output reg [7:0] fault_reason,
    output reg [31:0] fault_count
);
    reg  sample_valid_d;
    reg [15:0] sample_x_d;
    reg [15:0] sample_value_d;
    reg [31:0] sample_frame_id_d;
    reg  cut_valid_d;
    reg [15:0] cut_x_d;
    reg [31:0] cut_frame_id_d;
    reg  commit_valid_d;
    reg [31:0] commit_frame_id_d;
    reg [TAG_WIDTH-1:0] commit_tag_d;
    reg [15:0] commit_count_d;
    reg [15:0] commit_cut_count_d;
    reg [15:0] commit_high_d;
    reg [15:0] commit_low_d;
    reg [15:0] commit_min_width_d;
    reg [15:0] commit_gap_d;
    reg flush_d;
    wire core_busy;
    assign busy=core_busy||sample_valid_d||cut_valid_d||commit_valid_d;
    always @(posedge clk) begin
        if(!rst_n) begin sample_valid_d<=0;cut_valid_d<=0;commit_valid_d<=0;flush_d<=1;end
        else begin
            flush_d<=flush;
            sample_valid_d<=sample_valid&&!flush;cut_valid_d<=cut_valid&&!flush;commit_valid_d<=commit_valid&&!flush;
        end
        sample_x_d<=sample_x;
        sample_value_d<=sample_value;
        sample_frame_id_d<=sample_frame_id;
        cut_x_d<=cut_x;
        cut_frame_id_d<=cut_frame_id;
        commit_frame_id_d<=commit_frame_id;
        commit_tag_d<=commit_tag;
        commit_count_d<=commit_count;
        commit_cut_count_d<=commit_cut_count;
        commit_high_d<=commit_high;
        commit_low_d<=commit_low;
        commit_min_width_d<=commit_min_width;
        commit_gap_d<=commit_gap;
    end
    projection_object_extractor_impl #(.WIDTH(WIDTH),.MAX_OBJECTS(MAX_OBJECTS),.TAG_WIDTH(TAG_WIDTH),.PIPELINED_FAULT_COUNTER(PIPELINED_FAULT_COUNTER)) stage (
        .clk(clk),
        .rst_n(rst_n),
        .flush((flush||flush_d)),
        .sample_valid(sample_valid_d),
        .sample_x(sample_x_d),
        .sample_value(sample_value_d),
        .sample_frame_id(sample_frame_id_d),
        .cut_valid(cut_valid_d),
        .cut_x(cut_x_d),
        .cut_frame_id(cut_frame_id_d),
        .commit_valid(commit_valid_d),
        .commit_frame_id(commit_frame_id_d),
        .commit_tag(commit_tag_d),
        .commit_count(commit_count_d),
        .commit_cut_count(commit_cut_count_d),
        .commit_high(commit_high_d),
        .commit_low(commit_low_d),
        .commit_min_width(commit_min_width_d),
        .commit_gap(commit_gap_d),
        .batch_valid(batch_valid),
        .batch_ready(batch_ready),
        .batch_tag(batch_tag),
        .batch_count(batch_count),
        .batch_lefts(batch_lefts),
        .batch_rights(batch_rights),
        .busy(core_busy),
        .fault(fault),
        .fault_sticky(fault_sticky),
        .fault_reason(fault_reason),
        .fault_count(fault_count)
    );
endmodule
`timescale 1ns/1ps

// Reconstruct intervals only from a complete, committed projection scan.
// A cut is provisional until commit_valid; nothing reaches the tracker earlier.
// Interval endpoints are inclusive. Cuts divide [left,cut] and [cut+1,right].
// All controls use the physical clk, independently of video ce.
// batch_* is immutable while batch_valid && !batch_ready. flush cancels it.
// Incoming scans cannot overwrite a scan being processed or a held batch.
// Fault reasons: 1 sample order/ID; 2 cut order/ID/range; 3 incomplete/bad
// commit; 4 configuration; 5 object capacity; 6 count mismatch; 7 busy
// collision; 8 orphan cut/too-short split; 9 new scan before old commit.
module projection_object_extractor_impl #(
    parameter integer WIDTH=640,
    parameter integer MAX_OBJECTS=8, PIPELINED_FAULT_COUNTER=0,
    parameter integer TAG_WIDTH=129
) (
    input wire clk,rst_n,flush,
    input wire sample_valid,
    input wire [15:0] sample_x,sample_value,
    input wire [31:0] sample_frame_id,
    input wire cut_valid,
    input wire [15:0] cut_x,
    input wire [31:0] cut_frame_id,
    input wire commit_valid,
    input wire [31:0] commit_frame_id,
    input wire [TAG_WIDTH-1:0] commit_tag,
    input wire [15:0] commit_count,commit_cut_count,
    input wire [15:0] commit_high,commit_low,commit_min_width,commit_gap,
    output reg batch_valid,
    input wire batch_ready,
    output reg [TAG_WIDTH-1:0] batch_tag,
    output reg [7:0] batch_count,
    output reg [MAX_OBJECTS*16-1:0] batch_lefts,batch_rights,
    output wire busy,
    output reg fault,fault_sticky,
    output reg [7:0] fault_reason,
    output reg [31:0] fault_count
);
    localparam integer PX_BITS=$clog2(WIDTH+1), ADDR_BITS=$clog2(WIDTH), OBJ_BITS=$clog2(MAX_OBJECTS+1);
    reg [15:0] last_collected_cut;
    localparam [3:0] COLLECT=0,READ_COLUMN=1,EVAL_COLUMN=2,
                     START_SEGMENT=3,SPLIT_SEGMENT=4,VERIFY=5,PREPARE=6,SPLIT_PREPARE=7,EVAL_PREPARE=8,VALIDATE_COMMIT=9;
    reg [3:0] state;
    // No reset on this memory: the exact ordered sample count is the validity
    // proof. Synchronous reads permit inference of FPGA block memory.
    (* ram_style="block" *) reg [15:0] projection [0:WIDTH-1];
    reg [15:0] projection_prefetch,projection_q;
    reg [15:0] cuts [0:MAX_OBJECTS-1];
    reg [15:0] seg_left [0:MAX_OBJECTS-1];
    reg [15:0] seg_right [0:MAX_OBJECTS-1];
    reg collect_seen,collect_bad;
    reg [31:0] collect_frame;
    reg [PX_BITS-1:0] collected_samples;
    reg [OBJ_BITS-1:0] collected_cuts;
    reg [15:0] high_t,low_t,min_t,gap_t,expected_objects;
    reg [TAG_WIDTH-1:0] tag_t;
    reg [PX_BITS-1:0] scan_x;
    reg [OBJ_BITS-1:0] cut_total,segment_count,segment_index,cut_index,object_count;
    reg scan_active;
    reg [15:0] begin_x,last_support;
    reg [PX_BITS-1:0] gaps;
    reg [15:0] piece_begin;
    reg [MAX_OBJECTS*16-1:0] work_lefts,work_rights;

    // Keep the storage port separate from the resettable control FSM. A single
    // syntactic write and an unreset synchronous read register allow block-RAM
    // inference, rather than expanding the projection into pixel registers.
    wire projection_write=rst_n&&!flush&&state==COLLECT&&!batch_valid&&sample_valid&&
        (sample_x==0 || (collect_seen&&!collect_bad&&sample_frame_id==collect_frame&&
                        {1'b0,sample_x}==collected_samples&&sample_x<WIDTH));
    // Fetch the next column during the preceding evaluation, then use the
    // READ_COLUMN cycle for the BRAM output register. The external scan cadence
    // and complete-scan validity contract are unchanged.
    wire projection_read=rst_n&&!flush&&
        (state==PREPARE || (state==EVAL_COLUMN&&scan_x<WIDTH-1))&&
        !sample_valid&&!cut_valid&&!commit_valid;
    wire projection_register=rst_n&&!flush&&state==READ_COLUMN&&
        !sample_valid&&!cut_valid&&!commit_valid;
    wire [ADDR_BITS-1:0] projection_address=
        state==PREPARE ? {ADDR_BITS{1'b0}} : scan_x[ADDR_BITS-1:0]+1'b1;
    always @(posedge clk) begin
        if(projection_write) projection[sample_x[ADDR_BITS-1:0]]<=sample_value;
        if(projection_read) projection_prefetch<=projection[projection_address];
        if(projection_register) projection_q<=projection_prefetch;
    end

    // One-column next state duplicates only the reducer's ordinary high/low
    // gap segmentation. Valley decisions are consumed from committed cuts.
    reg active_n,close_segment;
    reg [15:0] begin_n,last_n,close_left,close_right;
    reg [PX_BITS-1:0] gaps_n;
    wire close_keep=close_segment &&
        ({1'b0,close_right}-{1'b0,close_left}+17'd1 >= {1'b0,min_t});
    always @* begin
        active_n=scan_active;begin_n=begin_x;last_n=last_support;gaps_n=gaps;
        close_segment=0;close_left=begin_x;close_right=last_support;
        if(!scan_active) begin
            if(projection_q>=high_t) begin
                active_n=1;begin_n=scan_x;last_n=scan_x;gaps_n=0;
            end
        end else begin
            if(projection_q>low_t) begin last_n=scan_x;gaps_n=0;end
            else gaps_n=gaps+17'd1;
            if(projection_q<=low_t && gaps+17'd1>={1'b0,gap_t}) begin
                close_segment=1;close_left=begin_x;close_right=last_support;
                active_n=0;
            end
        end
        if(scan_x==WIDTH-1 && active_n) begin
            close_segment=1;close_left=begin_n;close_right=last_n;active_n=0;
        end
    end

    // Native instances separate column geometry from control/fault dispatch.
    // The legacy public mode keeps its original two-cycle column cadence.
    reg active_p,close_keep_p;
    reg [15:0] begin_p,last_p,close_left_p,close_right_p;
    reg [PX_BITS-1:0] gaps_p;
    wire eval_active=PIPELINED_FAULT_COUNTER?active_p:active_n;
    wire eval_keep=PIPELINED_FAULT_COUNTER?close_keep_p:close_keep;
    wire [15:0] eval_begin=PIPELINED_FAULT_COUNTER?begin_p:begin_n;
    wire [15:0] eval_last=PIPELINED_FAULT_COUNTER?last_p:last_n;
    wire [15:0] eval_left=PIPELINED_FAULT_COUNTER?close_left_p:close_left;
    wire [15:0] eval_right=PIPELINED_FAULT_COUNTER?close_right_p:close_right;
    wire [PX_BITS-1:0] eval_gaps=PIPELINED_FAULT_COUNTER?gaps_p:gaps_n;

    // Blocking temporaries describe simultaneous last sample/cut/commit.
    reg seen_now,bad_now;
    reg [31:0] frame_now;
    reg [PX_BITS-1:0] samples_now;
    reg [OBJ_BITS-1:0] cuts_now;
    reg [7:0] reason_now;
    reg commit_seen_q,commit_bad_q;
    reg [31:0] commit_frame_q,commit_id_q;
    reg [PX_BITS-1:0] commit_samples_q;
    reg [15:0] commit_cuts_q;
    reg [7:0] commit_reason_q;
    reg [15:0] split_end;
    reg split_has_cut,split_last,split_invalid;
    assign busy=(state!=COLLECT)||batch_valid;
    generate if(PIPELINED_FAULT_COUNTER)begin: diagnostic_counter
        always @(posedge clk)begin
            if(!rst_n)fault_count<=0;
            else if(fault)fault_count<=fault_count+1'b1;
        end
    end endgenerate


    always @(posedge clk) begin
        if(!rst_n) begin
            state<=COLLECT;collect_seen<=0;collect_bad<=0;collect_frame<=0;last_collected_cut<=0;
            collected_samples<=0;collected_cuts<=0;
            high_t<=0;low_t<=0;min_t<=0;gap_t<=0;expected_objects<=0;tag_t<=0;
            cut_total<=0;scan_x<=0;segment_count<=0;segment_index<=0;cut_index<=0;
            object_count<=0;scan_active<=0;begin_x<=0;last_support<=0;gaps<=0;
            piece_begin<=0;work_lefts<=0;work_rights<=0;
            batch_valid<=0;batch_tag<=0;batch_count<=0;batch_lefts<=0;batch_rights<=0;
            fault<=0;fault_sticky<=0;fault_reason<=0;if(!PIPELINED_FAULT_COUNTER)fault_count<=0;
        end else begin
            fault<=0;
            if(PIPELINED_FAULT_COUNTER)begin
                if(state==COLLECT&&!batch_valid&&commit_valid)begin
                    high_t<=commit_high;low_t<=commit_low;min_t<=commit_min_width;
                    gap_t<=commit_gap;expected_objects<=commit_count;tag_t<=commit_tag;
                end
                if(!sample_valid&&!cut_valid&&!commit_valid)begin
                    if(state==PREPARE)begin work_lefts<=0;work_rights<=0;end
                    if(state==SPLIT_SEGMENT&&!split_invalid&&object_count<MAX_OBJECTS)begin
                        work_lefts[object_count*16+:16]<=piece_begin;
                        work_rights[object_count*16+:16]<=split_end;
                    end
                    if(state==VERIFY&&cut_index==cut_total&&object_count=={1'b0,expected_objects})begin
                        batch_tag<=tag_t;batch_count<=object_count;
                        batch_lefts<=work_lefts;batch_rights<=work_rights;
                    end
                end
            end
            if(flush) begin
                state<=COLLECT;collect_seen<=0;collect_bad<=0;
                collected_samples<=0;collected_cuts<=0;scan_active<=0;
                batch_valid<=0;batch_count<=0;if(!PIPELINED_FAULT_COUNTER)begin batch_lefts<=0;batch_rights<=0;end
                segment_count<=0;object_count<=0;cut_index<=0;
            end else begin
                if(batch_valid && batch_ready) batch_valid<=0;
                if(state==COLLECT && !batch_valid) begin
                    seen_now=collect_seen;bad_now=collect_bad;frame_now=collect_frame;
                    samples_now=collected_samples;cuts_now=collected_cuts;reason_now=0;
                    if(sample_valid) begin
                        if(sample_x==0) begin
                            if(collect_seen) reason_now=9;
                            seen_now=1;bad_now=0;frame_now=sample_frame_id;
                            samples_now=1;cuts_now=0;
                        end else if(!seen_now || bad_now || sample_frame_id!=frame_now ||
                                    {1'b0,sample_x}!=samples_now || sample_x>=WIDTH) begin
                            bad_now=1;reason_now=1;
                        end else begin
                            samples_now=samples_now+17'd1;
                        end
                    end
                    if(cut_valid) begin
                        if(!seen_now || bad_now || cut_frame_id!=frame_now ||
                           cut_x>=WIDTH-1 || cuts_now>=MAX_OBJECTS) begin
                            bad_now=1;reason_now=2;
                        end else if(cuts_now!=0 && cut_x<=last_collected_cut) begin
                            bad_now=1;reason_now=2;
                        end else begin
                            cuts[cuts_now]<=cut_x;last_collected_cut<=cut_x;cuts_now=cuts_now+1'b1;
                        end
                    end
                    if(commit_valid) begin
                        // Capture private metadata on the commit pulse. Only the
                        // validated FSM branch can ever publish it as a batch.
                        if(!PIPELINED_FAULT_COUNTER)begin
                            high_t<=commit_high;low_t<=commit_low;min_t<=commit_min_width;
                            gap_t<=commit_gap;expected_objects<=commit_count;tag_t<=commit_tag;
                        end
                        cut_total<=cuts_now;
                        if(PIPELINED_FAULT_COUNTER)begin
                            // Complete the simultaneous sample/cut packet first;
                            // validate its immutable commit snapshot next clock.
                            commit_seen_q<=seen_now;commit_bad_q<=bad_now;
                            commit_frame_q<=frame_now;commit_id_q<=commit_frame_id;
                            commit_samples_q<=samples_now;commit_cuts_q<=commit_cut_count;
                            commit_reason_q<=reason_now;reason_now=0;state<=VALIDATE_COMMIT;
                        end else begin
                            if(!seen_now || bad_now || samples_now!=WIDTH ||
                               commit_frame_id!=frame_now || {1'b0,commit_cut_count}!=cuts_now)
                                reason_now=3;
                            else if(commit_high<=commit_low || commit_min_width==0 || commit_gap==0)
                                reason_now=4;
                            else if(commit_count>MAX_OBJECTS || commit_cut_count>=MAX_OBJECTS)
                                reason_now=5;
                            else state<=PREPARE;
                        end
                        seen_now=0;bad_now=0;samples_now=0;cuts_now=0;
                    end
                    collect_seen<=seen_now;collect_bad<=bad_now;collect_frame<=frame_now;
                    collected_samples<=samples_now;collected_cuts<=cuts_now;
                    if(reason_now!=0) begin
                        fault<=1;fault_sticky<=1;fault_reason<=reason_now;if(!PIPELINED_FAULT_COUNTER)fault_count<=fault_count+1'b1;
                    end
                end else if(sample_valid || cut_valid || commit_valid) begin
                    // An occupied batch is preserved. A processing collision
                    // cancels the unpublished candidate and drops the new scan.
                    fault<=1;fault_sticky<=1;fault_reason<=7;if(!PIPELINED_FAULT_COUNTER)fault_count<=fault_count+1'b1;
                    state<=COLLECT;collect_seen<=0;collect_bad<=0;
                    collected_samples<=0;collected_cuts<=0;
                end else begin
                    case(state)
                        VALIDATE_COMMIT: begin
                            reason_now=commit_reason_q;state<=COLLECT;
                            if(!commit_seen_q || commit_bad_q || commit_samples_q!=WIDTH ||
                               commit_id_q!=commit_frame_q || {1'b0,commit_cuts_q}!=cut_total)
                                reason_now=3;
                            else if(high_t<=low_t || min_t==0 || gap_t==0)reason_now=4;
                            else if(expected_objects>MAX_OBJECTS || commit_cuts_q>=MAX_OBJECTS)reason_now=5;
                            else state<=PREPARE;
                            if(reason_now!=0)begin
                                fault<=1;fault_sticky<=1;fault_reason<=reason_now;
                            end
                        end
                        PREPARE: begin
                            scan_x<=0;scan_active<=0;begin_x<=0;last_support<=0;gaps<=0;
                            segment_count<=0;segment_index<=0;cut_index<=0;object_count<=0;
                            if(!PIPELINED_FAULT_COUNTER)begin work_lefts<=0;work_rights<=0;end state<=READ_COLUMN;
                        end
                        READ_COLUMN: state<=PIPELINED_FAULT_COUNTER?EVAL_PREPARE:EVAL_COLUMN;
                        EVAL_PREPARE: begin
                            active_p<=active_n;begin_p<=begin_n;last_p<=last_n;gaps_p<=gaps_n;
                            close_keep_p<=close_keep;close_left_p<=close_left;close_right_p<=close_right;
                            state<=EVAL_COLUMN;
                        end
                        EVAL_COLUMN: begin
                            scan_active<=eval_active;begin_x<=eval_begin;last_support<=eval_last;gaps<=eval_gaps;
                            if(eval_keep && segment_count>=MAX_OBJECTS) begin
                                fault<=1;fault_sticky<=1;fault_reason<=5;if(!PIPELINED_FAULT_COUNTER)fault_count<=fault_count+1'b1;
                                state<=COLLECT;
                            end else begin
                                if(eval_keep) begin
                                    seg_left[segment_count]<=eval_left;seg_right[segment_count]<=eval_right;
                                    segment_count<=segment_count+17'd1;
                                end
                                if(scan_x==WIDTH-1) state<=START_SEGMENT;
                                else begin scan_x<=scan_x+17'd1;state<=READ_COLUMN;end
                            end
                        end
                        START_SEGMENT: begin
                            if(segment_index==segment_count) state<=VERIFY;
                            else begin piece_begin<=seg_left[segment_index];state<=SPLIT_PREPARE;end
                        end
                        SPLIT_PREPARE: begin
                            // Prepare immutable cut geometry before enabling
                            // the packed interval outputs and object counter.
                            split_has_cut=(cut_index<cut_total && cuts[cut_index]<seg_right[segment_index]);
                            split_end=split_has_cut ? cuts[cut_index] : seg_right[segment_index];
                            split_last=!split_has_cut;
                            split_invalid=(cut_index<cut_total && cuts[cut_index]<piece_begin) ||
                               (cut_index<cut_total && cuts[cut_index]==seg_right[segment_index]) ||
                               {1'b0,split_end}-{1'b0,piece_begin}+17'd1<{1'b0,min_t};
                            state<=SPLIT_SEGMENT;
                        end
                        SPLIT_SEGMENT: begin
                            if(split_invalid) begin
                                fault<=1;fault_sticky<=1;fault_reason<=8;if(!PIPELINED_FAULT_COUNTER)fault_count<=fault_count+1'b1;
                                state<=COLLECT;
                            end else if(object_count>=MAX_OBJECTS) begin
                                fault<=1;fault_sticky<=1;fault_reason<=5;if(!PIPELINED_FAULT_COUNTER)fault_count<=fault_count+1'b1;
                                state<=COLLECT;
                            end else begin
                                if(!PIPELINED_FAULT_COUNTER)begin
                                    work_lefts[object_count*16 +:16]<=piece_begin;
                                    work_rights[object_count*16 +:16]<=split_end;
                                end
                                object_count<=object_count+17'd1;
                                if(split_last) begin segment_index<=segment_index+17'd1;state<=START_SEGMENT;end
                                else begin piece_begin<=split_end+1'b1;cut_index<=cut_index+17'd1;state<=SPLIT_PREPARE;end
                            end
                        end
                        VERIFY: begin
                            if(cut_index!=cut_total || object_count!={1'b0,expected_objects}) begin
                                fault<=1;fault_sticky<=1;fault_reason<=6;if(!PIPELINED_FAULT_COUNTER)fault_count<=fault_count+1'b1;
                            end else begin
                                batch_valid<=1;
                                if(!PIPELINED_FAULT_COUNTER)begin batch_tag<=tag_t;batch_count<=object_count;
                                batch_lefts<=work_lefts;batch_rights<=work_rights;end
                            end
                            state<=COLLECT;
                        end
                        default: state<=COLLECT;
                    endcase
                end
            end
        end
    end
endmodule
