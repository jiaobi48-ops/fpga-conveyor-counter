// Optional merge/recovery tracker derived from conveyor_track_counter.v
// Parent SHA256: ee162ffcf4914554c81c3960cf22b091010675bd4e158c31da84082356d8c705
`timescale 1ns / 1ps
// Right-to-left, single-lane interval tracker. All work runs on physical clk.
// A whole detection batch is validated before committing tracks/totals. Events
// belonging to that atomic commit are then serialized, even if flush arrives.
module conveyor_merge_tracker #(
    parameter integer MAX_TRACKS = 8,
    parameter integer MAX_OBJECTS = MAX_TRACKS, REGISTERED_DISPATCH=0
)(
    input wire clk, input wire rst_n, input wire flush, input wire clear_totals,
    input wire batch_valid, output wire batch_ready,
    input wire [31:0] batch_frame_id,
    input wire [127:0] batch_context,
    input wire batch_is_test,
    input wire [7:0] batch_count,
    input wire [MAX_OBJECTS*16-1:0] batch_lefts,
    input wire [MAX_OBJECTS*16-1:0] batch_rights,
    input wire [15:0] cfg_line_a, cfg_line_b, cfg_hysteresis,
    input wire [15:0] cfg_max_step, cfg_width_delta,
    input wire [7:0] cfg_max_missed, cfg_min_hits,
    output wire busy,
    output reg frame_update, output reg frame_rejected,
    output reg [31:0] output_frame_id,
    output reg [127:0] output_context,
    output reg output_is_test,
    output reg [7:0] delta_count,
    output reg [31:0] camera_total, test_total,
    output reg event_valid,
    output reg [31:0] event_track_id, event_frame_id,
    output reg [127:0] event_context,
    output reg event_is_test,
    output reg [31:0] event_seq,
    output reg fault_sticky,
    output reg [15:0] fault_reasons,
    output reg [31:0] rejected_batches, duplicate_batches, uncertain_tracks,
    output reg [7:0] live_tracks,
    output reg debug_valid,
    output reg [31:0] debug_track_id, debug_frame_id,
    output reg [15:0] debug_left, debug_right, debug_center,
    output reg [1:0] debug_phase,
    output reg debug_counted, debug_eligible,
    input wire cfg_merge_enable,
    input wire merge_explicit_reset,
    input wire [7:0] cfg_merge_max_frames,cfg_merge_confirm_frames,
    input wire [15:0] cfg_merge_shape_tolerance,cfg_merge_recovery_tolerance,
    output reg merge_active,merge_recovering,merge_blocked,merge_update,merge_recovered,merge_uncertain,
    output reg [MAX_TRACKS-1:0] merge_member_mask,
    output reg [7:0] merge_age,merge_confirm_count,merge_reason,
    output reg [31:0] merged_frames,restored_groups,unresolved_groups,
    output reg [31:0] merge_track_a,merge_track_b,
    output reg debug_occluded,debug_recovering,
    input wire batch_capture
);
    localparam [4:0] IDLE=0, CHECK=1, INTERVAL=2, PREP=3, SEARCH=4,
        ASSOC=5, BIRTH=6, AGE=7, ORDER=8, COMMIT=9, EMIT=10,
        DEBUG=11, REJECT=12, MSTART=13, MSCAN=14, MEVAL=15, MDECIDE=16,
        MBUILD=17, MVERIFY=18, MBLOCK=19, MREGION=20,
        M_ECALC=21, M_ECHECK=22, M_RLOAD=23, M_RCHECK=24, M_GLOAD=25, M_GCALC=26, M_GCHECK=27,A_SELECT=28,CHECK_META=29;
    localparam [15:0] R_CFG=16'h0001, R_CAPACITY=16'h0002,
        R_INTERVAL=16'h0004, R_ASSOC=16'h0008, R_WIDTH=16'h0010,
        R_ORDER=16'h0020, R_LATE=16'h0040, R_UNCERTAIN=16'h0080,
        R_ID=16'h0100, R_TOTAL=16'h0200, R_GAP=16'h0800,
        R_DUP=16'h1000, R_MERGE=16'h2000;
    reg [4:0] state;
    reg [1:0] selected_kind;
    assign batch_ready=(state==IDLE)&&!flush&&!clear_totals;
    assign busy=(state!=IDLE);

    reg valid[0:MAX_TRACKS-1], counted[0:MAX_TRACKS-1], eligible[0:MAX_TRACKS-1];
    reg [31:0] identity[0:MAX_TRACKS-1];
    reg [15:0] left_x[0:MAX_TRACKS-1], right_x[0:MAX_TRACKS-1], center_x[0:MAX_TRACKS-1];
    reg [16:0] width_x[0:MAX_TRACKS-1];
    reg [7:0] hits[0:MAX_TRACKS-1], missed[0:MAX_TRACKS-1];
    reg [1:0] phase[0:MAX_TRACKS-1];
    // Candidate arrays are discarded on any pre-commit rejection or flush.
    reg tv[0:MAX_TRACKS-1], tc[0:MAX_TRACKS-1], te[0:MAX_TRACKS-1];
    reg original[0:MAX_TRACKS-1], matched[0:MAX_TRACKS-1];
    reg [31:0] ti[0:MAX_TRACKS-1];
    reg [15:0] tl[0:MAX_TRACKS-1], tr[0:MAX_TRACKS-1], tx[0:MAX_TRACKS-1];
    reg [16:0] tw[0:MAX_TRACKS-1];
    reg [7:0] th[0:MAX_TRACKS-1], tm[0:MAX_TRACKS-1];
    reg [1:0] tp[0:MAX_TRACKS-1];
    reg [7:0] order_rank[0:MAX_TRACKS-1];
    reg ordered_mode;
    reg [15:0] dl[0:MAX_OBJECTS-1], dr[0:MAX_OBJECTS-1];
    reg [31:0] pending_events[0:MAX_TRACKS-1];
    reg [31:0] next_id, candidate_next_id;
    reg last_valid, last_test;
    reg [31:0] last_frame;
    reg [127:0] last_context;
    reg [31:0] fid;
    reg [127:0] context_tag;
    // Balanced parallel context comparison; avoid one 128-bit carry cascade.
    (* KEEP="TRUE" *) wire [7:0] context_diff;
    generate for(genvar cp=0;cp<8;cp=cp+1)begin:context_compare
        assign context_diff[cp]=context_tag[16*cp+:16]!=last_context[16*cp+:16];
    end endgenerate
    reg checked_context;
    reg [31:0] checked_distance;
    wire same_context=REGISTERED_DISPATCH?checked_context:!(|context_diff);
    reg source_test;
    reg [7:0] object_count;
    reg [15:0] line_a, line_b, hysteresis, max_step, width_delta;
    reg [7:0] max_missed, min_hits;
    reg [15:0] reject_reason, candidate_reasons;
    reg [7:0] candidate_uncertain, event_count;
    reg [15:0] object_center;
    reg [16:0] object_width;
    localparam integer INDEX_BITS=$clog2(MAX_TRACKS+MAX_OBJECTS+4)+1;
    reg signed [INDEX_BITS-1:0] di, si, candidate_slot, candidates, nearby, age_index;
    reg signed [INDEX_BITS-1:0] rank_slot, selected_slot;
    reg rank_found;
    reg signed [INDEX_BITS-1:0] oi, oj, emit_index, debug_index;
    integer i, j;
    reg signed [INDEX_BITS-1:0] rank_value, original_count;
    reg [31:0] frame_distance;
    reg [16:0] distance_x, distance_w;
    reg [8:0] next_hits;
    reg [7:0] valid_count;
    reg [7:0] gap_uncertain;

    // Single two-member merge cohort; other tracks remain ordinary observations.
    // Estimated intervals are internal association aids, never detection/count evidence.
    reg merge_en;reg [7:0] merge_limit,merge_required;
    reg [15:0] merge_shape,merge_distance;
    reg [15:0] raw_l[0:MAX_OBJECTS-1],raw_r[0:MAX_OBJECTS-1];
    reg [7:0] raw_count;
    reg [1:0] det_kind[0:MAX_OBJECTS-1]; // 0 real,1 occluded estimate,2 restore wait,3 restore final
    reg signed [INDEX_BITS-1:0] det_slot[0:MAX_OBJECTS-1];
    reg predicted[0:MAX_TRACKS-1],recovering_track[0:MAX_TRACKS-1];
    reg next_predicted[0:MAX_TRACKS-1],next_recovering[0:MAX_TRACKS-1];
    reg signed [INDEX_BITS-1:0] group_a,group_b,ca,cb,probe_a,probe_b,carrier,probe_count,carrier_count;
    reg signed [INDEX_BITS-1:0] probe_raw,probe_track,region_count,region0,region1,build_raw,build_count,verify_slot;
    // 16-bit coordinates plus two independent 16-bit motion margins fit signed 20 bits.
    reg signed [19:0] g_left,g_right,c_left,c_right,translate,span_left,span_right,span_width;
    reg signed [19:0] new_width,new_center,old_center,shape_error,near_left,near_right;
    reg signed [19:0] center_a,center_b,width_a,width_b,limit_distance;
    reg signed [INDEX_BITS-1:0] affected;
    reg c_active,c_recovering,c_blocked,c_merged,c_restored,c_unresolved;
    reg [7:0] c_age,c_confirm,c_reason;
    reg [MAX_TRACKS-1:0] c_members;
    reg geometry_ok;

    function [31:0] add_sat;
        input [31:0] a; input [31:0] b;
        reg [32:0] s;
        begin s={1'b0,a}+{1'b0,b}; add_sat=s[32]?32'hffffffff:s[31:0]; end
    endfunction

    always @(posedge clk) begin
        frame_update<=0; frame_rejected<=0; event_valid<=0; debug_valid<=0;
        merge_update<=0;merge_recovered<=0;merge_uncertain<=0;
        if(!rst_n || clear_totals) begin
            state<=IDLE; last_valid<=0; next_id<=1;
            merge_active<=0;merge_recovering<=0;merge_blocked<=0;merge_update<=0;merge_recovered<=0;merge_uncertain<=0;
            merge_member_mask<=0;merge_age<=0;merge_confirm_count<=0;merge_reason<=0;
            merged_frames<=0;restored_groups<=0;unresolved_groups<=0;
            merge_track_a<=0;merge_track_b<=0;
            debug_occluded<=0;debug_recovering<=0;group_a<=0;group_b<=0;g_left<=0;g_right<=0;
            camera_total<=0; test_total<=0; event_seq<=0;
            frame_update<=0; frame_rejected<=0; event_valid<=0; debug_valid<=0;
            output_frame_id<=0; output_context<=0; output_is_test<=0; delta_count<=0;
            event_track_id<=0; event_frame_id<=0; event_context<=0; event_is_test<=0;
            fault_sticky<=0; fault_reasons<=0; rejected_batches<=0;
            duplicate_batches<=0; uncertain_tracks<=0; live_tracks<=0;
            debug_track_id<=0; debug_frame_id<=0; debug_left<=0;
            debug_right<=0; debug_center<=0; debug_phase<=0;
            debug_counted<=0; debug_eligible<=0;
            last_frame<=0; last_context<=0; last_test<=0;
            for(i=0;i<MAX_TRACKS;i=i+1) begin
                valid[i]<=0; counted[i]<=0; eligible[i]<=0;predicted[i]<=0;recovering_track[i]<=0;
                identity[i]<=0; left_x[i]<=0; right_x[i]<=0; center_x[i]<=0;
                width_x[i]<=0; hits[i]<=0; missed[i]<=0; phase[i]<=0;
                tv[i]<=0; tc[i]<=0; te[i]<=0; original[i]<=0; matched[i]<=0;
                ti[i]<=0; tl[i]<=0; tr[i]<=0; tx[i]<=0; tw[i]<=0;
                th[i]<=0; tm[i]<=0; tp[i]<=0; pending_events[i]<=0;
            end
        end else begin
            if(flush) begin
                last_valid<=0; live_tracks<=0;
                merge_active<=0;merge_recovering<=0;merge_member_mask<=0;
                merge_age<=0;merge_confirm_count<=0;
                merge_track_a<=0;merge_track_b<=0;
                if(merge_explicit_reset)begin merge_blocked<=0;merge_reason<=0;end
                else if(merge_active||merge_blocked)begin
                    merge_blocked<=1;merge_reason<=7;
                    if(merge_active)begin
                        affected=0;
                        for(i=0;i<MAX_TRACKS;i=i+1)if(valid[i]&&eligible[i]&&!counted[i])affected=affected+1;
                        unresolved_groups<=add_sat(unresolved_groups,1);uncertain_tracks<=add_sat(uncertain_tracks,affected);
                        fault_sticky<=1;fault_reasons<=fault_reasons|R_MERGE;
                        merge_uncertain<=1;merge_update<=1;
                    end
                end else begin merge_blocked<=0;merge_reason<=0;end
                for(i=0;i<MAX_TRACKS;i=i+1) begin
                    valid[i]<=0; counted[i]<=0; eligible[i]<=0;
                end
                if(state!=EMIT && state!=DEBUG) begin state<=IDLE; delta_count<=0; end
            end
            // A committed event list is a historical packet and must finish.
            if(!flush || state==EMIT || state==DEBUG) begin
                case(state)
                IDLE: if(batch_valid && batch_ready) begin
                    if(!REGISTERED_DISPATCH)begin
                    fid<=batch_frame_id; context_tag<=batch_context;
                    source_test<=batch_is_test; object_count<=batch_count;
                    line_a<=cfg_line_a; line_b<=cfg_line_b;
                    hysteresis<=cfg_hysteresis; max_step<=cfg_max_step;
                    width_delta<=cfg_width_delta; max_missed<=cfg_max_missed;
                    min_hits<=cfg_min_hits;
                    merge_en<=cfg_merge_enable;merge_limit<=cfg_merge_max_frames;merge_required<=cfg_merge_confirm_frames;
                    merge_shape<=cfg_merge_shape_tolerance;merge_distance<=cfg_merge_recovery_tolerance;
                    raw_count<=batch_count;
                    for(i=0;i<MAX_OBJECTS;i=i+1) begin
                        dl[i]<=batch_lefts[16*i+:16]; dr[i]<=batch_rights[16*i+:16];
                        raw_l[i]<=batch_lefts[16*i+:16];raw_r[i]<=batch_rights[16*i+:16];
                        det_kind[i]<=0;det_slot[i]<=0;
                    end
                    end
                    event_count<=0;
                    candidate_uncertain<=0; candidate_reasons<=0;
                    candidate_next_id<=next_id;state<=REGISTERED_DISPATCH?CHECK_META:CHECK;
                end
                CHECK_META: begin
                    // A batch stays private until CHECK validates it. Register
                    // metadata before the track-wide gap/uncertainty reduction.
                    // Flush still cancels this state through the common guard.
                    checked_context<=!(|context_diff);
                    checked_distance<=fid-last_frame;
                    state<=CHECK;
                end
                CHECK: begin
                    frame_distance=REGISTERED_DISPATCH?checked_distance:fid-last_frame;
                    c_active=merge_active;
                    c_recovering=c_active&&merge_recovering;c_blocked=merge_blocked;
                    c_members=c_active?merge_member_mask:0;ca=group_a;cb=group_b;
                    c_age=c_active?merge_age:0;c_confirm=c_active?merge_confirm_count:0;c_reason=merge_reason;
                    c_left=g_left;c_right=g_right;c_merged=0;c_restored=0;c_unresolved=0;translate=0;
                    carrier=-1;carrier_count=0;region_count=0;region0=-1;region1=-1;
                    if((merge_en&&(merge_required<2||merge_limit<merge_required+1))||MAX_TRACKS<1 || MAX_TRACKS>255 || MAX_OBJECTS<1 ||
                       MAX_OBJECTS>MAX_TRACKS || min_hits==0 || max_step==0 ||
                       {1'b0,line_b}<{1'b0,hysteresis} ||
                       ({1'b0,line_a}+{1'b0,hysteresis})>17'd65535 ||
                       {2'b0,line_a}<=({2'b0,line_b}+({2'b0,hysteresis}<<1))) begin
                        reject_reason<=R_CFG; state<=REJECT;
                    end else if(object_count>MAX_OBJECTS) begin
                        reject_reason<=R_CAPACITY; state<=REJECT;
                    end else if(last_valid && same_context && source_test==last_test && frame_distance==0) begin
                        reject_reason<=R_DUP; state<=REJECT;
                    end else if(last_valid && same_context && source_test==last_test && frame_distance[31]) begin
                        reject_reason<=R_LATE; state<=REJECT;
                    end else begin
                        original_count=0; gap_uncertain=0;
                        for(i=0;i<MAX_TRACKS;i=i+1) begin
                            // Once the previous grace frames are exhausted, an
                            // absent downstream ghost must not compete with a
                            // following target before AGE gets a chance to run.
                            tv[i]<=valid[i] && last_valid && same_context && source_test==last_test &&
                                !(missed[i]!=0 && missed[i]>=max_missed);
                            original[i]<=valid[i] && last_valid && same_context && source_test==last_test &&
                                !(missed[i]!=0 && missed[i]>=max_missed);
                            matched[i]<=0;next_predicted[i]<=0;next_recovering[i]<=0;
                            tc[i]<=counted[i]; ti[i]<=identity[i];
                            tl[i]<=left_x[i]; tr[i]<=right_x[i]; tx[i]<=center_x[i];
                            tw[i]<=width_x[i]; th[i]<=hits[i]; tm[i]<=missed[i]; tp[i]<=phase[i];
                            te[i]<=eligible[i] && !(missed[i]!=0 && missed[i]>=max_missed);
                            rank_value=0;
                            for(j=0;j<MAX_TRACKS;j=j+1)
                                if(valid[j] && !(missed[j]!=0 && missed[j]>=max_missed) && (center_x[j]<center_x[i] ||
                                   (center_x[j]==center_x[i] && j<i))) rank_value=rank_value+1;
                            order_rank[i]<=rank_value;
                            if(valid[i] && last_valid && same_context && source_test==last_test &&
                               !(missed[i]!=0 && missed[i]>=max_missed))
                                original_count=original_count+1;
                            if(valid[i] && last_valid && same_context && source_test==last_test &&
                               missed[i]!=0 && missed[i]>=max_missed && eligible[i] && !counted[i])
                                gap_uncertain=gap_uncertain+1'b1;
                            if(last_valid && same_context && source_test==last_test && frame_distance>1) begin
                                te[i]<=0;
                                if(valid[i] && !(missed[i]!=0 && missed[i]>=max_missed) && eligible[i] && !counted[i])
                                    gap_uncertain=gap_uncertain+1'b1;
                            end
                        end
                        ordered_mode<=(original_count==object_count && original_count!=0);
                        candidate_uncertain<=gap_uncertain;
                        if(last_valid && same_context && source_test==last_test && frame_distance>1)
                            candidate_reasons<=R_GAP|(gap_uncertain!=0?R_UNCERTAIN:16'b0);
                        else if(gap_uncertain!=0) candidate_reasons<=R_UNCERTAIN;
                        di<=0;
                        if(object_count==0) state<=MSTART;
                        else state<=INTERVAL;
                    end
                end
                INTERVAL: begin
                    if(dl[di]>dr[di] || (di>0 && dl[di]<=dr[di-1])) begin
                        reject_reason<=R_INTERVAL; state<=REJECT;
                    end else if(di+1>=object_count) begin di<=0; state<=MSTART; end
                    else di<=di+1;
                end
                MSTART: begin
                    build_raw=0;build_count=0;
                    if(!merge_en)begin
                        c_active=0;c_recovering=0;c_blocked=0;c_members=0;c_age=0;c_confirm=0;c_reason=0;
                        state<=MBUILD;
                    end else if(c_blocked)begin
                        // An unresolved cohort must never become a fresh wide target.
                        // Require an actually empty ROI (or explicit context reset).
                        if(raw_count==0)begin c_blocked=0;c_reason=0;end
                        state<=MBLOCK;
                    end else if(c_active)begin
                        probe_raw=0;state<=raw_count==0?MDECIDE:MREGION;
                    end else if(raw_count!=0)begin
                        probe_raw=0;probe_track=0;probe_count=0;probe_a=-1;probe_b=-1;state<=MSCAN;
                    end else state<=MBUILD;
                end
                MREGION: begin
                    near_left=g_left-integer'(max_step)-integer'(merge_distance);
                    near_right=g_right+integer'(max_step)+integer'(merge_distance);
                    if(integer'(raw_r[probe_raw])>=near_left&&integer'(raw_l[probe_raw])<=near_right)begin
                        if(region_count==0)region0=probe_raw;else if(region_count==1)region1=probe_raw;
                        region_count=region_count+1;
                    end
                    if(probe_raw+1>=raw_count)state<=MDECIDE;else probe_raw=probe_raw+1;
                end
                MSCAN: begin
                    near_left=integer'(left_x[probe_track])-integer'(max_step);
                    near_right=integer'(right_x[probe_track])+integer'(max_step);
                    if(original[probe_track]&&integer'(raw_r[probe_raw])>=near_left&&integer'(raw_l[probe_raw])<=near_right)begin
                        if(probe_count==0)probe_a=probe_track;else if(probe_count==1)probe_b=probe_track;
                        probe_count=probe_count+1;
                    end
                    if(probe_track+1>=MAX_TRACKS)state<=MEVAL;else probe_track=probe_track+1;
                end
                MEVAL: begin
                    if(probe_count==2)begin
                        span_left=left_x[probe_a]<left_x[probe_b]?left_x[probe_a]:left_x[probe_b];
                        span_right=right_x[probe_a]>right_x[probe_b]?right_x[probe_a]:right_x[probe_b];
                        new_width=integer'(raw_r[probe_raw])-integer'(raw_l[probe_raw])+1;
                        new_center=(integer'(raw_l[probe_raw])+integer'(raw_r[probe_raw]))/2;
                        state<=M_ECALC;
                    end else begin
                    if(probe_raw+1>=raw_count)state<=MDECIDE;
                    else begin probe_raw=probe_raw+1;probe_track=0;probe_count=0;probe_a=-1;probe_b=-1;state<=MSCAN;end
                    end
                end
                M_ECALC: begin
                    span_width=span_right-span_left+1;
                    old_center=(span_left+span_right)/2;translate=new_center-old_center;
                    state<=M_ECHECK;
                end
                M_ECHECK: begin
                    shape_error=new_width>span_width?new_width-span_width:span_width-new_width;
                    geometry_ok=hits[probe_a]>=min_hits&&hits[probe_b]>=min_hits&&missed[probe_a]==0&&missed[probe_b]==0&&
                        new_width>integer'(width_x[probe_a])+1&&new_width>integer'(width_x[probe_b])+1&&
                        shape_error<=merge_shape&&translate<=integer'(max_step)&&translate>=-integer'(max_step)&&
                        span_left+translate>=0&&span_right+translate<=65535;
                    if(geometry_ok)begin
                        carrier_count=carrier_count+1;
                        if(carrier_count==1)begin
                            carrier=probe_raw;
                            if(center_x[probe_a]<center_x[probe_b])begin ca=probe_a;cb=probe_b;end
                            else begin ca=probe_b;cb=probe_a;end
                        end
                    end
                    if(probe_raw+1>=raw_count)state<=MDECIDE;
                    else begin probe_raw=probe_raw+1;probe_track=0;probe_count=0;probe_a=-1;probe_b=-1;state<=MSCAN;end
                end
                MDECIDE: begin
                    if(c_active&&(frame_distance!=1||!same_context||source_test!=last_test||!original[ca]||!original[cb]))begin
                        c_reason=2;c_unresolved=1;c_blocked=raw_count!=0;state<=MBLOCK;
                    end else if(c_active&&integer'(c_age)+1>integer'(merge_limit))begin
                        c_reason=3;c_unresolved=1;c_blocked=raw_count!=0;state<=MBLOCK;
                    end else if(c_active&&region_count==2)begin
                        state<=M_RLOAD;
                    end else if(c_active&&region_count!=1)begin
                        c_reason=region_count==0?8'd5:8'd6;c_unresolved=1;c_blocked=raw_count!=0;state<=MBLOCK;
                    end else if(!c_active&&carrier_count>1)begin
                        c_reason=6;c_unresolved=1;c_blocked=1;state<=MBLOCK;
                    end else if(c_active||carrier_count==1)begin
                        if(c_active)carrier=region0;
                        state<=M_GLOAD;
                    end else begin c_members=0;c_age=0;c_confirm=0;c_recovering=0;c_reason=0;state<=MBUILD;end
                end
                M_RLOAD: begin
                    center_a=(integer'(raw_l[region0])+integer'(raw_r[region0]))/2;
                    center_b=(integer'(raw_l[region1])+integer'(raw_r[region1]))/2;
                    width_a=integer'(raw_r[region0])-integer'(raw_l[region0])+1;
                    width_b=integer'(raw_r[region1])-integer'(raw_l[region1])+1;
                    limit_distance=integer'(max_step)+integer'(merge_distance);
                    state<=M_RCHECK;
                end
                M_RCHECK: begin
                    geometry_ok=center_a<center_b&&
                        center_a-integer'(center_x[ca])<=limit_distance&&integer'(center_x[ca])-center_a<=limit_distance&&
                        center_b-integer'(center_x[cb])<=limit_distance&&integer'(center_x[cb])-center_b<=limit_distance&&
                        width_a-integer'(width_x[ca])<=integer'(width_delta)&&integer'(width_x[ca])-width_a<=integer'(width_delta)&&
                        width_b-integer'(width_x[cb])<=integer'(width_delta)&&integer'(width_x[cb])-width_b<=integer'(width_delta);
                        if(!geometry_ok)begin c_reason=4;c_unresolved=1;c_blocked=1;state<=MBLOCK;end
                        else begin
                            c_age=c_age+1'b1;c_confirm=c_recovering?c_confirm+1'b1:8'd1;
                            c_recovering=c_confirm<merge_required;c_active=c_recovering;c_restored=!c_recovering;
                            c_left=raw_l[region0];c_right=raw_r[region1];c_reason=0;carrier=-1;state<=MBUILD;
                        end

                end
                M_GLOAD: begin
                    span_left=left_x[ca]<left_x[cb]?left_x[ca]:left_x[cb];
                    span_right=right_x[ca]>right_x[cb]?right_x[ca]:right_x[cb];
                    new_width=integer'(raw_r[carrier])-integer'(raw_l[carrier])+1;
                    new_center=(integer'(raw_l[carrier])+integer'(raw_r[carrier]))/2;
                    state<=M_GCALC;
                end
                M_GCALC: begin
                    span_width=span_right-span_left+1;
                    old_center=c_active?(g_left+g_right)/2:(span_left+span_right)/2;
                    translate=new_center-old_center;
                    state<=M_GCHECK;
                end
                M_GCHECK: begin
                    shape_error=new_width>span_width?new_width-span_width:span_width-new_width;
                    geometry_ok=shape_error<=merge_shape&&translate<=integer'(max_step)&&translate>=-integer'(max_step)&&
                        new_width>integer'(width_x[ca])+1&&new_width>integer'(width_x[cb])+1&&
                        span_left+translate>=0&&span_right+translate<=65535;
                        if(!geometry_ok||raw_count>=MAX_OBJECTS)begin
                            c_reason=!geometry_ok?8'd1:8'd6;c_unresolved=1;c_blocked=1;state<=MBLOCK;
                        end else begin
                            c_age=c_active?c_age+1'b1:8'd1;c_active=1;c_recovering=0;c_confirm=0;c_merged=1;c_reason=0;
                            c_members=0;c_members[ca]=1;c_members[cb]=1;
                            c_left=raw_l[carrier];c_right=raw_r[carrier];state<=MBUILD;
                        end

                end
                MBUILD: begin
                    if(build_raw>=raw_count)begin
                        object_count<=build_count;ordered_mode<=original_count==build_count&&build_count!=0;
                        verify_slot=0;state<=MVERIFY;
                    end else if(c_merged&&build_raw==carrier)begin
                        dl[build_count]<=integer'(left_x[ca])+translate;dr[build_count]<=integer'(right_x[ca])+translate;
                        det_kind[build_count]<=1;det_slot[build_count]<=ca;
                        dl[build_count+1]<=integer'(left_x[cb])+translate;dr[build_count+1]<=integer'(right_x[cb])+translate;
                        det_kind[build_count+1]<=1;det_slot[build_count+1]<=cb;
                        build_count=build_count+2;build_raw=build_raw+1;
                    end else begin
                        dl[build_count]<=raw_l[build_raw];dr[build_count]<=raw_r[build_raw];det_kind[build_count]<=0;det_slot[build_count]<=0;
                        if((c_recovering||c_restored)&&(build_raw==region0||build_raw==region1))begin
                            det_kind[build_count]<=c_restored?3:2;det_slot[build_count]<=build_raw==region0?ca:cb;
                        end
                        build_count=build_count+1;build_raw=build_raw+1;
                    end
                end
                MVERIFY: begin
                    if(verify_slot>=object_count)begin
                        di<=0;age_index<=0;state<=object_count==0?AGE:PREP;
                    end else if(dl[verify_slot]>dr[verify_slot]||(verify_slot>0&&dl[verify_slot]<=dr[verify_slot-1]))begin
                        if(c_active||c_restored)begin c_reason=4;c_unresolved=1;c_blocked=1;state<=MBLOCK;end
                        else begin reject_reason<=R_INTERVAL;state<=REJECT;end
                    end else verify_slot=verify_slot+1;
                end
                MBLOCK: begin
                    affected=0;
                    for(i=0;i<MAX_TRACKS;i=i+1)begin
                        if(valid[i]&&eligible[i]&&!counted[i])affected=affected+1;
                        valid[i]<=0;counted[i]<=0;eligible[i]<=0;predicted[i]<=0;recovering_track[i]<=0;
                    end
                    merge_active<=0;merge_recovering<=0;merge_blocked<=c_blocked;
                    merge_member_mask<=0;merge_age<=0;merge_confirm_count<=0;merge_reason<=c_reason;
                    merge_track_a<=0;merge_track_b<=0;
                    if(c_unresolved)begin
                        unresolved_groups<=add_sat(unresolved_groups,1);uncertain_tracks<=add_sat(uncertain_tracks,affected);
                        fault_sticky<=1;fault_reasons<=fault_reasons|R_MERGE;merge_uncertain<=1;
                    end
                    live_tracks<=0;last_valid<=1;last_frame<=fid;last_context<=context_tag;last_test<=source_test;
                    output_frame_id<=fid;output_context<=context_tag;output_is_test<=source_test;
                    delta_count<=0;frame_update<=1;merge_update<=1;state<=IDLE;
                end
                PREP: begin
                    object_center<=({1'b0,dl[di]}+{1'b0,dr[di]})>>1;
                    object_width<={1'b0,dr[di]}-{1'b0,dl[di]}+1'b1;
                    si<=0; candidates<=0; nearby<=0; candidate_slot<=0;
                    rank_found<=0; rank_slot<=0;
                    state<=SEARCH;
                end
                SEARCH: begin
                    if(original[si]&&!(c_members[si]&&det_kind[di]==0)) begin
                        distance_x=object_center>=center_x[si] ?
                            {1'b0,object_center}-{1'b0,center_x[si]} :
                            {1'b0,center_x[si]}-{1'b0,object_center};
                        distance_w=object_width>=width_x[si] ? object_width-width_x[si] : width_x[si]-object_width;
                        if(distance_x<={1'b0,max_step} ||
                           (dl[di]<=right_x[si] && dr[di]>=left_x[si])) nearby<=nearby+1;
                        if(distance_x<={1'b0,max_step} && distance_w<={1'b0,width_delta}) begin
                            candidates<=candidates+1; candidate_slot<=si;
                            if(ordered_mode && order_rank[si]==di) begin rank_found<=1;rank_slot<=si;end
                        end
                    end
                    if(si+1>=MAX_TRACKS) state<=A_SELECT;
                    else si<=si+1;
                end
                A_SELECT: begin
                    // Resolve the detection and track array addresses before
                    // the atomic association/event decision.
                    selected_slot<=det_kind[di]!=0?det_slot[di]:(rank_found?rank_slot:candidate_slot);
                    selected_kind<=det_kind[di];state<=ASSOC;
                end
                ASSOC: begin
                    // Prefer a gated monotone rank pair. When an exit and an
                    // entry occur together, rank can shift; a unique gated pair
                    // or a clean upstream birth is still admissible.
                    if((selected_kind!=0&&(!original[selected_slot]||matched[selected_slot]))||
                       (selected_kind==0&&((!rank_found && candidates>1)||
                       (!rank_found && candidates==1 && nearby>1)||(candidates!=0 && matched[selected_slot])))) begin
                        reject_reason<=R_ASSOC; state<=REJECT;
                    end else if(selected_kind==0&&candidates==0 && nearby>0) begin
                        // Possible merge or excessive size change: keep old locks.
                        reject_reason<=R_WIDTH; state<=REJECT;
                    end else if(selected_kind==0&&candidates==0) begin si<=0; state<=BIRTH; end
                    else begin
                        matched[selected_slot]<=1;
                        tl[selected_slot]<=dl[di]; tr[selected_slot]<=dr[di];
                        tx[selected_slot]<=object_center; tw[selected_slot]<=object_width;
                        next_hits={1'b0,hits[selected_slot]}+1'b1;
                        th[selected_slot]<=selected_kind==1?hits[selected_slot]:(next_hits[8]?8'hff:next_hits[7:0]);tm[selected_slot]<=0;
                        next_predicted[selected_slot]<=selected_kind==1;
                        next_recovering[selected_slot]<=selected_kind==2;
                        // Resume only after consecutive real, ordered, size-gated observations.
                        // Both-line catch-up uses pre-merge qualification and real recovered positions.
                        if(selected_kind==3&&!tc[selected_slot]&&te[selected_slot]&&next_hits>=min_hits)begin
                            if(object_center<=line_b-hysteresis)begin
                                tc[selected_slot]<=1;tp[selected_slot]<=2;
                                pending_events[event_count]<=ti[selected_slot];event_count<=event_count+1'b1;
                            end else if(object_center<=line_a-hysteresis)tp[selected_slot]<=1;
                            else if(object_center>=line_a+hysteresis)tp[selected_slot]<=0;
                        end
                        if(selected_kind==0&&!tc[selected_slot] && te[selected_slot]) begin
                            if(tp[selected_slot]==0 && object_center<=line_a-hysteresis) begin
                                if(missed[selected_slot]!=0 || object_center<=line_b-hysteresis) begin
                                    te[selected_slot]<=0; candidate_uncertain<=candidate_uncertain+1'b1;
                                    candidate_reasons<=candidate_reasons|R_UNCERTAIN;
                                end else tp[selected_slot]<=1;
                            end else if(tp[selected_slot]==1) begin
                                if(object_center>=line_a+hysteresis) tp[selected_slot]<=0;
                                else if(object_center<=line_b-hysteresis) begin
                                    if(missed[selected_slot]!=0 || next_hits<min_hits) begin
                                        te[selected_slot]<=0; candidate_uncertain<=candidate_uncertain+1'b1;
                                        candidate_reasons<=candidate_reasons|R_UNCERTAIN;
                                    end else begin
                                        tc[selected_slot]<=1; tp[selected_slot]<=2;
                                        pending_events[event_count]<=ti[selected_slot];
                                        event_count<=event_count+1'b1;
                                    end
                                end
                            end
                        end
                        if(di+1>=object_count) begin age_index<=0; state<=AGE; end
                        else begin di<=di+1; state<=PREP; end
                    end
                end
                BIRTH: begin
                    if(!tv[si]) begin
                        if(candidate_next_id==0) begin reject_reason<=R_ID; state<=REJECT; end
                        else begin
                            tv[si]<=1; original[si]<=0; matched[si]<=1;
                            ti[si]<=candidate_next_id; candidate_next_id<=candidate_next_id+1'b1;
                            tl[si]<=dl[di]; tr[si]<=dr[di]; tx[si]<=object_center; tw[si]<=object_width;
                            th[si]<=1; tm[si]<=0; tp[si]<=0; tc[si]<=0;
                            te[si]<=object_center>=line_a+hysteresis;
                            if(di+1>=object_count) begin age_index<=0; state<=AGE; end
                            else begin di<=di+1; state<=PREP; end
                        end
                    end else if(si+1>=MAX_TRACKS) begin reject_reason<=R_CAPACITY; state<=REJECT; end
                    else si<=si+1;
                end
                AGE: begin
                    if(original[age_index] && !matched[age_index]) begin
                        th[age_index]<=0;
                        if({1'b0,missed[age_index]}+9'd1>{1'b0,max_missed}) begin
                            tv[age_index]<=0;
                            if(te[age_index] && !tc[age_index]) begin
                                candidate_uncertain<=candidate_uncertain+1'b1;
                                candidate_reasons<=candidate_reasons|R_UNCERTAIN;
                            end
                        end else tm[age_index]<=missed[age_index]+1'b1;
                    end
                    if(age_index+1>=MAX_TRACKS) begin oi<=0; oj<=0; state<=ORDER; end
                    else age_index<=age_index+1;
                end
                ORDER: begin
                    if(oi<oj && original[oi] && original[oj] && matched[oi] && matched[oj] &&
                       ((center_x[oi]<center_x[oj] && tx[oi]>=tx[oj]) ||
                        (center_x[oi]>center_x[oj] && tx[oi]<=tx[oj]))) begin
                        reject_reason<=R_ORDER; state<=REJECT;
                    end else if(oj+1>=MAX_TRACKS) begin
                        oj<=0;
                        if(oi+1>=MAX_TRACKS) state<=COMMIT; else oi<=oi+1;
                    end else oj<=oj+1;
                end
                COMMIT: begin
                    if((source_test && {1'b0,test_total}+event_count>33'h0ffffffff) ||
                       (!source_test && {1'b0,camera_total}+event_count>33'h0ffffffff)) begin
                        reject_reason<=R_TOTAL; state<=REJECT;
                    end else begin
                        valid_count=0;
                        for(i=0;i<MAX_TRACKS;i=i+1) begin
                            valid[i]<=tv[i]; counted[i]<=tc[i]; eligible[i]<=te[i]; identity[i]<=ti[i];
                            predicted[i]<=next_predicted[i];recovering_track[i]<=next_recovering[i];
                            left_x[i]<=tl[i]; right_x[i]<=tr[i]; center_x[i]<=tx[i]; width_x[i]<=tw[i];
                            hits[i]<=th[i]; missed[i]<=tm[i]; phase[i]<=tp[i];
                            if(tv[i]) valid_count=valid_count+1'b1;
                        end
                        live_tracks<=valid_count; next_id<=candidate_next_id;
                        merge_active<=c_active;merge_recovering<=c_recovering;merge_blocked<=c_blocked;
                        merge_member_mask<=c_members;merge_age<=c_age;merge_confirm_count<=c_confirm;merge_reason<=c_reason;
                        group_a<=ca;group_b<=cb;g_left<=c_left;g_right<=c_right;
                        merge_track_a<=c_members!=0?ti[ca]:0;merge_track_b<=c_members!=0?ti[cb]:0;
                        merge_update<=1;merge_recovered<=c_restored;
                        if(c_merged)merged_frames<=add_sat(merged_frames,1);
                        if(c_restored)restored_groups<=add_sat(restored_groups,1);
                        last_valid<=1; last_frame<=fid; last_context<=context_tag; last_test<=source_test;
                        output_frame_id<=fid; output_context<=context_tag; output_is_test<=source_test;
                        delta_count<=event_count; frame_update<=1;
                        if(source_test) test_total<=test_total+event_count;
                        else camera_total<=camera_total+event_count;
                        uncertain_tracks<=add_sat(uncertain_tracks,{24'b0,candidate_uncertain});
                        if(candidate_reasons!=0) begin fault_sticky<=1; fault_reasons<=fault_reasons|candidate_reasons; end
                        emit_index<=0; debug_index<=0;
                        if(event_count!=0) state<=EMIT; else state<=DEBUG;
                    end
                end
                EMIT: begin
                    event_valid<=1; event_track_id<=pending_events[emit_index];
                    event_frame_id<=output_frame_id; event_context<=output_context;
                    event_is_test<=output_is_test; event_seq<=event_seq+1'b1;
                    if(emit_index+1>=event_count) state<=DEBUG; else emit_index<=emit_index+1;
                end
                DEBUG: begin
                    if(tv[debug_index]) begin
                        debug_valid<=1; debug_track_id<=ti[debug_index]; debug_frame_id<=output_frame_id;
                        debug_left<=tl[debug_index]; debug_right<=tr[debug_index]; debug_center<=tx[debug_index];
                        debug_phase<=tp[debug_index]; debug_counted<=tc[debug_index]; debug_eligible<=te[debug_index];
                        debug_occluded<=next_predicted[debug_index];debug_recovering<=next_recovering[debug_index];
                    end
                    if(debug_index+1>=MAX_TRACKS) state<=IDLE; else debug_index<=debug_index+1;
                end
                REJECT: begin
                    frame_rejected<=1; output_frame_id<=fid; output_context<=context_tag;
                    output_is_test<=source_test; delta_count<=0;
                    rejected_batches<=add_sat(rejected_batches,1);
                    if(reject_reason==R_DUP) duplicate_batches<=add_sat(duplicate_batches,1);
                    else fault_sticky<=1;
                    fault_reasons<=fault_reasons|reject_reason; state<=IDLE;
                end
                default: state<=IDLE;
                endcase
            end
            // These are private scratch fields, not committed tracks/totals.
            // A registered packet loads them even when its current-cycle permit
            // is cancelled. Only the qualified IDLE transition can use them.
            if(REGISTERED_DISPATCH&&batch_capture&&state==IDLE)begin
                    fid<=batch_frame_id; context_tag<=batch_context;
                    source_test<=batch_is_test; object_count<=batch_count;
                    line_a<=cfg_line_a; line_b<=cfg_line_b;
                    hysteresis<=cfg_hysteresis; max_step<=cfg_max_step;
                    width_delta<=cfg_width_delta; max_missed<=cfg_max_missed;
                    min_hits<=cfg_min_hits;
                    merge_en<=cfg_merge_enable;merge_limit<=cfg_merge_max_frames;merge_required<=cfg_merge_confirm_frames;
                    merge_shape<=cfg_merge_shape_tolerance;merge_distance<=cfg_merge_recovery_tolerance;
                    raw_count<=batch_count;
                    for(i=0;i<MAX_OBJECTS;i=i+1) begin
                        dl[i]<=batch_lefts[16*i+:16]; dr[i]<=batch_rights[16*i+:16];
                        raw_l[i]<=batch_lefts[16*i+:16];raw_r[i]<=batch_rights[16*i+:16];
                        det_kind[i]<=0;det_slot[i]<=0;
                    end
            end
        end
    end
endmodule
