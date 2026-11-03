`timescale 1ns/1ps
module tb_merge_tracks;
    localparam N=8;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,flush=0,clear_totals=0,batch_valid=0;
    wire batch_ready,busy;
    reg [31:0] batch_frame_id=0;reg [127:0] batch_context=1;reg batch_is_test=0;
    reg [7:0] batch_count=0;reg [127:0] batch_lefts=0,batch_rights=0;
    reg [15:0] cfg_line_a=60,cfg_line_b=30,cfg_hysteresis=1,cfg_max_step=8,cfg_width_delta=2;
    reg [7:0] cfg_max_missed=2,cfg_min_hits=2;
    reg merge_explicit_reset=0;
    reg cfg_merge_enable=1;reg [7:0] cfg_merge_max_frames=24,cfg_merge_confirm_frames=2;
    reg [15:0] cfg_merge_shape_tolerance=10,cfg_merge_recovery_tolerance=12;
    wire frame_update,frame_rejected,output_is_test,event_valid,event_is_test,fault_sticky,debug_valid,debug_counted,debug_eligible;
    wire [31:0] output_frame_id,camera_total,test_total,event_track_id,event_frame_id,event_seq,rejected_batches,duplicate_batches,uncertain_tracks,debug_track_id,debug_frame_id;
    wire [127:0] output_context,event_context;wire [7:0] delta_count,live_tracks;
    wire [15:0] fault_reasons,debug_left,debug_right,debug_center;wire [1:0] debug_phase;
    wire merge_active,merge_recovering,merge_blocked,merge_update,merge_recovered,merge_uncertain,debug_occluded,debug_recovering;
    wire [7:0] merge_member_mask,merge_age,merge_confirm_count,merge_reason;
    wire [31:0] merged_frames,restored_groups,unresolved_groups,merge_track_a,merge_track_b;
    wire batch_capture=1'b0;
    conveyor_merge_tracker #(.MAX_TRACKS(N),.MAX_OBJECTS(N)) dut(.*);
    integer cases=0,transactions=0,checks=0,events=0,csv,q,last_delta,guard,old_events,j;
    integer centers[0:63];reg seen[0:63],was_predicted[0:63],was_recovering[0:63];
    reg counted_ids[0:63];reg [31:0] last_event_seq=0;
    string output_path;
    always @(posedge clk)begin
        #1;
        if(!rst_n||clear_totals)begin
            last_event_seq=0;for(integer k=0;k<64;k=k+1)counted_ids[k]=0;
        end else begin
            if(event_valid)begin
                if(event_track_id>=64||counted_ids[event_track_id]||event_seq!=last_event_seq+1||event_frame_id!=output_frame_id||event_context!=output_context||event_is_test!=output_is_test)
                    $fatal(1,"FAIL MERGE TRACKS duplicate/incoherent event");
                counted_ids[event_track_id]=1;last_event_seq=event_seq;events=events+1;
            end
            if(debug_valid)begin
                if(debug_track_id>=64||debug_left>debug_center||debug_center>debug_right)$fatal(1,"FAIL MERGE TRACKS invalid debug");
                seen[debug_track_id]=1;centers[debug_track_id]=debug_center;
                was_predicted[debug_track_id]=debug_occluded;was_recovering[debug_track_id]=debug_recovering;
            end
        end
    end
    task check(input bit condition,input string message);
        begin checks=checks+1;if(!condition)$fatal(1,"FAIL MERGE TRACKS case=%0d check=%0d %s",cases,checks,message);end
    endtask
    task clear_session;
        begin
            while(!batch_ready)@(negedge clk);
            @(negedge clk);clear_totals=1;@(negedge clk);clear_totals=0;
            cfg_max_step=8;cfg_width_delta=2;cfg_min_hits=2;cfg_merge_enable=1;
            cfg_merge_max_frames=24;cfg_merge_confirm_frames=2;cfg_merge_shape_tolerance=10;cfg_merge_recovery_tolerance=12;
            batch_context=1;batch_is_test=0;cases=cases+1;
            check(camera_total==0&&test_total==0&&!merge_active&&!merge_blocked,"clear resets explicit session");
        end
    endtask
    task send(input integer f,n,a,b,c,d,e,g,expected_delta,input bit rejected=0);
        begin
            while(!batch_ready)@(negedge clk);
            for(j=0;j<64;j=j+1)begin seen[j]=0;was_predicted[j]=0;was_recovering[j]=0;end
            @(negedge clk);batch_frame_id=f;batch_count=n;
            batch_lefts={80'd0,16'(e),16'(c),16'(a)};batch_rights={80'd0,16'(g),16'(d),16'(b)};
            if(n==4)begin batch_lefts[63:48]=16'(e+20);batch_rights[63:48]=16'(g+20);end
            batch_valid=1;old_events=events;@(negedge clk);batch_valid=0;guard=0;
            while(!frame_update&&!frame_rejected&&guard<3000)begin @(negedge clk);guard=guard+1;end
            check(guard<3000&&frame_rejected==rejected,"accepted/rejected frame result");
            check(delta_count==expected_delta&&output_frame_id==f&&output_context==batch_context&&output_is_test==batch_is_test,"delta and metadata");
            last_delta=delta_count;
            $fwrite(csv,"%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d\n",cases,f,n,last_delta,camera_total,test_total,merge_active,merge_recovering,merge_blocked,merge_age,merge_confirm_count,merge_reason,merged_frames,restored_groups,unresolved_groups);
            while(!batch_ready&&guard<3300)begin @(negedge clk);guard=guard+1;end
            check(batch_ready&&events-old_events==expected_delta,"bounded transaction and serialized events");transactions=transactions+1;
        end
    endtask
    task prepare_pair;
        begin send(1,2,76,84,96,104,0,0,0);send(2,2,72,80,92,100,0,0,0);end
    endtask
    initial begin
        if(!$value$plusargs("OUTPUT=%s",output_path))$fatal(1,"FAIL MERGE TRACKS missing output");
        csv=$fopen(output_path,"w");$fwrite(csv,"case,frame_id,raw_count,delta,camera_total,test_total,active,recovering,blocked,age,confirm,reason,merged_frames,restored_groups,unresolved_groups\n");
        repeat(4)@(negedge clk);rst_n=1;
        clear_session();prepare_pair();
        // Partial overlap: a narrower observation replaces two confirmed intervals.
        send(3,1,68,88,0,0,0,0,0);
        check(merge_active&&!merge_recovering&&merge_age==1&&live_tracks==2&&seen[1]&&seen[2]&&was_predicted[1]&&was_predicted[2],"recognize partial merge and preserve both IDs");
        check(merge_track_a==1&&merge_track_b==2,"cohort reports real track IDs");
        send(4,1,64,84,0,0,0,0,0);send(5,2,60,68,80,88,0,0,0);
        check(merge_active&&merge_recovering&&merge_confirm_count==1&&was_recovering[1]&&was_recovering[2],"first split is provisional");
        send(6,2,56,64,76,84,0,0,0);
        check(!merge_active&&restored_groups==1&&seen[1]&&seen[2]&&centers[1]==60&&centers[2]==80,"real consecutive recovery preserves identities");
        send(7,2,52,60,72,80,0,0,0);send(8,2,44,52,64,72,0,0,0);
        send(9,2,36,44,56,64,0,0,0);send(10,2,28,36,48,56,0,0,0);
        send(11,2,20,28,40,48,0,0,1);send(12,2,16,24,32,40,0,0,0);send(13,2,12,20,24,32,0,0,1);
        check(camera_total==2&&counted_ids[1]&&counted_ids[2]&&merged_frames==2&&!fault_sticky,"restored pair counts exactly twice");
        // Counted identities remain counted through another merge, stop and reversal.
        send(14,1,11,39,0,0,0,0,0);send(15,1,10,38,0,0,0,0,0);
        send(16,2,8,16,20,28,0,0,0);send(17,2,7,15,19,27,0,0,0);
        check(camera_total==2&&restored_groups==2&&seen[1]&&seen[2],"counted locks survive remerge");
        for(q=18;q<24;q=q+1)send(q,2,7,15,19,27,0,0,0);
        // A long merge spanning both count gates is never counted while hidden.
        clear_session();prepare_pair();
        for(q=0;q<16;q=q+1)begin send(3+q,1,68-4*q,96-4*q,0,0,0,0,0);check(camera_total==0,"no predicted crossing events");end
        send(19,2,4,12,24,32,0,0,0);send(20,2,3,11,23,31,0,0,2);
        check(camera_total==2&&restored_groups==1&&counted_ids[1]&&counted_ids[2],"catch-up only after actual confirmed split");
        // A downstream unrelated track can count while the upstream pair is merged.
        clear_session();cfg_max_step=16;
        send(1,3,66,74,146,154,166,174,0);send(2,3,52,60,142,150,162,170,0);
        send(3,2,38,46,138,166,0,0,0);send(4,2,24,32,134,162,0,0,1);
        check(merge_active&&camera_total==1&&counted_ids[1]&&seen[2]&&seen[3],"unrelated target commits while cohort held");
        send(5,3,24,32,130,138,150,158,0);send(6,3,24,32,126,134,146,154,0);
        check(restored_groups==1&&seen[2]&&seen[3]&&centers[2]==130&&centers[3]==150,"pair restoration with other tracks");
        // Timeout enters a visible fail-closed state, without assuming one wide item.
        clear_session();cfg_merge_max_frames=4;prepare_pair();
        for(q=0;q<4;q=q+1)send(3+q,1,68-4*q,96-4*q,0,0,0,0,0);
        send(7,1,52,80,0,0,0,0,0);
        check(merge_blocked&&merge_reason==3&&unresolved_groups==1&&uncertain_tracks==2&&fault_reasons[13],"timeout blocks uncertain counts");
        send(8,2,48,56,68,76,0,0,0);check(merge_blocked&&live_tracks==0,"split after expiry cannot silently resume");
        send(9,0,0,0,0,0,0,0,0);check(!merge_blocked,"empty scene releases interlock");
        send(10,2,76,84,96,104,0,0,0);check(seen[3]&&seen[4],"new IDs are monotonic after interlock");
        clear_session();prepare_pair();send(3,1,68,96,0,0,0,0,0);
        send(5,1,64,92,0,0,0,0,0);check(merge_blocked&&merge_reason==2&&camera_total==0,"frame gap invalidates merge evidence");
        clear_session();prepare_pair();send(3,1,68,96,0,0,0,0,0);
        send(4,2,60,78,80,98,0,0,0);check(merge_blocked&&merge_reason==4,"wrong split widths rejected");
        clear_session();prepare_pair();send(3,1,68,96,0,0,0,0,0);
        send(4,0,0,0,0,0,0,0,0);check(!merge_active&&!merge_blocked&&unresolved_groups==1&&merge_reason==5,"merged disappearance reports unresolved");
        clear_session();prepare_pair();send(3,1,68,96,0,0,0,0,0);
        @(negedge clk);merge_explicit_reset=1;flush=1;@(negedge clk);flush=0;merge_explicit_reset=0;
        check(!merge_active&&!merge_blocked&&camera_total==0,"flush clears identity history");
        batch_context=2;batch_is_test=1;send(1,1,76,104,0,0,0,0,0);
        check(!merge_active&&live_tracks==1&&seen[3],"new context never reuses old cohort");
        clear_session();send(1,2,76,84,96,104,0,0,0);send(2,1,72,100,0,0,0,0,0,1);
        check(!merge_active&&merged_frames==0&&live_tracks==2,"unconfirmed tracks cannot invent a cohort");
        clear_session();prepare_pair();send(3,1,68,96,0,0,0,0,0);
        send(3,1,64,92,0,0,0,0,0,1);check(merge_age==1&&duplicate_batches==1,"duplicate packet cannot age/restore cohort");
        send(4,1,64,92,0,0,0,0,0);check(merge_age==2,"next real packet continues cohort");
        clear_session();cfg_merge_enable=0;prepare_pair();send(3,1,68,96,0,0,0,0,0,1);
        check(!merge_active&&merged_frames==0,"disabled mode retains old rejection behavior");
        // First-seen wide silhouettes have no evidence of two historical objects.
        clear_session();send(1,1,76,104,0,0,0,0,0);send(2,1,68,96,0,0,0,0,0);
        check(!merge_active&&live_tracks==1,"no hallucinated split at startup");
        // One apparent split followed by remerge must reset confirmation evidence.
        clear_session();prepare_pair();send(3,1,68,96,0,0,0,0,0);
        send(4,2,64,72,84,92,0,0,0);check(merge_recovering&&merge_confirm_count==1,"provisional split");
        send(5,1,60,88,0,0,0,0,0);check(merge_active&&!merge_recovering&&merge_confirm_count==0,"remerge resets confirmation");
        send(6,2,56,64,76,84,0,0,0);check(merge_recovering&&restored_groups==0,"one real frame still insufficient");
        send(7,2,52,60,72,80,0,0,0);check(!merge_active&&restored_groups==1&&camera_total==0,"fresh consecutive confirmation restores");
        // Only one two-member cohort is supported; multiple groups fail closed.
        clear_session();send(1,4,76,84,96,104,156,164,0);send(2,4,72,80,92,100,152,160,0);
        send(3,2,68,96,148,176,0,0,0);
        check(merge_blocked&&merge_reason==6&&unresolved_groups==1&&camera_total==0,"multiple cohorts cannot silently collapse");
        // A later ordinary association failure rolls back a candidate merge too.
        clear_session();cfg_max_step=16;
        send(1,3,66,74,146,154,166,174,0);send(2,3,52,60,142,150,162,170,0);
        send(3,2,38,56,138,166,0,0,0,1);
        check(!merge_active&&merged_frames==0&&live_tracks==3&&camera_total==0,"merge state is atomic with whole batch");
        send(3,2,38,46,138,166,0,0,0);check(merge_active&&merged_frames==1,"valid retry commits original IDs");
        // Unexpected history flushes hold the interlock across the following epoch change.
        clear_session();prepare_pair();send(3,1,68,96,0,0,0,0,0);
        @(negedge clk);flush=1;@(negedge clk);flush=0;
        check(merge_blocked&&merge_reason==7&&unresolved_groups==1,"unexpected flush cannot erase unresolved overlap");
        batch_context=2;send(4,1,64,92,0,0,0,0,0);
        check(merge_blocked&&live_tracks==0&&camera_total==0,"context mismatch cannot bypass interlock");
        @(negedge clk);flush=1;@(negedge clk);flush=0;
        check(merge_blocked&&unresolved_groups==1,"repeated history flush preserves interlock without double-report");
        send(5,0,0,0,0,0,0,0,0);check(!merge_blocked,"actual empty scene releases lost-history interlock");
        clear_session();cfg_merge_confirm_frames=1;send(1,0,0,0,0,0,0,0,0,1);check(fault_reasons[0],"at least two real recovery frames required");
        $fclose(csv);$display("PASS MERGE TRACKS cases=%0d transactions=%0d checks=%0d events=%0d partial/identity/confirmation/catchup/no_prediction/other_tracks/remerge/timeout/gap/bad_split/empty/flush/context/immature/duplicate/disable/startup/config",cases,transactions,checks,events);$finish;
    end
    initial begin #10000000;$fatal(1,"FAIL MERGE TRACKS watchdog");end
endmodule
