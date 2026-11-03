`timescale 1ns/1ps
module tb_conveyor_extract_pipelined;
    localparam W=32,M=4,T=258;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,flush=0,sample_valid=0,cut_valid=0,commit_valid=0,batch_ready=0;
    reg [15:0] sample_x=0,sample_value=0,cut_x=0;
    reg [31:0] sample_frame_id=0,cut_frame_id=0,commit_frame_id=0;
    reg [T-1:0] commit_tag=0;
    reg [15:0] commit_count=0,commit_cut_count=0;
    reg [15:0] commit_high=15,commit_low=0,commit_min_width=3,commit_gap=2;
    wire batch_valid,busy,fault,fault_sticky;
    wire [7:0] batch_count,fault_reason;
    wire [31:0] fault_count;
    wire [T-1:0] batch_tag;
    wire [M*16-1:0] batch_lefts,batch_rights;
    projection_object_extractor #(.PIPELINED_FAULT_COUNTER(1),.WIDTH(W),.MAX_OBJECTS(M),.TAG_WIDTH(T)) dut(.*);
    integer values[0:W-1],lefts[0:M-1],rights[0:M-1];
    integer tests=0,batches=0,errors=0,i,k,n,base_faults;
    reg [T-1:0] expected_tag,held_tag;
    reg [M*16-1:0] held_lefts,held_rights;
    reg [7:0] held_count;
    wire fullsize_done;
    conveyor_extract_fullsize_check_pipelined fullsize(.clk(clk),.done(fullsize_done));
    always @(posedge clk) begin #1;if(fault) errors=errors+1;end

    task automatic clear_values;
        begin for(integer j=0;j<W;j=j+1) values[j]=0;end
    endtask
    task automatic fill(input integer a,b,v);
        begin for(integer j=a;j<=b;j=j+1) values[j]=v;end
    endtask
    task automatic reset_context;
        begin
            @(negedge clk);sample_valid=0;cut_valid=0;commit_valid=0;batch_ready=0;flush=1;
            @(negedge clk);flush=0;commit_high=15;commit_low=0;commit_min_width=3;commit_gap=2;
            if(batch_valid || busy) $fatal(1,"FAIL EXTRACT flush busy/valid");
        end
    endtask
    task automatic sample(input integer x,v,id);
        begin
            @(negedge clk);sample_valid=1;sample_x=x;sample_value=v;sample_frame_id=id;
            @(negedge clk);sample_valid=0;
        end
    endtask
    task automatic scan(input integer id);
        begin
            for(integer j=0;j<W;j=j+1) begin
                @(negedge clk);sample_valid=1;sample_x=j;sample_value=values[j];sample_frame_id=id;
            end
            @(negedge clk);sample_valid=0;
        end
    endtask
    task automatic cut(input integer x,id);
        begin
            @(negedge clk);cut_valid=1;cut_x=x;cut_frame_id=id;
            @(negedge clk);cut_valid=0;
        end
    endtask
    task automatic commit(input integer id,objects,cuts);
        begin
            @(negedge clk);commit_valid=1;commit_frame_id=id;commit_count=objects;commit_cut_count=cuts;
            commit_tag={97'h123456789abcdef0123456789,1'b0,32'd7,32'd9,32'd11,32'd13,id[31:0]};
            expected_tag=commit_tag;
            @(negedge clk);commit_valid=0;
        end
    endtask
    task automatic expect_batch(input integer objects);
        integer cycles;
        begin
            cycles=0;
            while(!batch_valid && cycles<4*W+8*M+32) begin @(posedge clk);#1;cycles=cycles+1;end
            if(!batch_valid || batch_count!=objects || batch_tag!==expected_tag)
                $fatal(1,"FAIL EXTRACT batch missing/count/tag expected=%0d got=%0d valid=%0d",objects,batch_count,batch_valid);
            for(integer j=0;j<objects;j=j+1)
                if(batch_lefts[j*16 +:16]!=lefts[j] || batch_rights[j*16 +:16]!=rights[j])
                    $fatal(1,"FAIL EXTRACT interval=%0d [%0d,%0d] expected [%0d,%0d]",j,batch_lefts[j*16 +:16],batch_rights[j*16 +:16],lefts[j],rights[j]);
            for(integer j=objects;j<M;j=j+1)
                if(batch_lefts[j*16 +:16]!=0 || batch_rights[j*16 +:16]!=0)
                    $fatal(1,"FAIL EXTRACT stale unused lane=%0d",j);
            batches=batches+1;tests=tests+1;
        end
    endtask
    task automatic consume;
        begin
            @(negedge clk);batch_ready=1;@(negedge clk);batch_ready=0;
            if(batch_valid) $fatal(1,"FAIL EXTRACT handshake");
        end
    endtask
    task automatic expect_rejection(input integer old_errors);
        begin
            repeat(4*W+8*M+40) begin
                @(posedge clk);#1;if(batch_valid) $fatal(1,"FAIL EXTRACT rejected frame published");
            end
            if(errors<=old_errors || !fault_sticky) $fatal(1,"FAIL EXTRACT expected diagnostic");
            tests=tests+1;
        end
    endtask

    initial begin
        repeat(4) @(negedge clk);rst_n=1;
        // Three ordinary separated targets.
        clear_values();fill(2,5,20);fill(12,15,20);fill(24,27,20);
        lefts[0]=2;rights[0]=5;lefts[1]=12;rights[1]=15;lefts[2]=24;rights[2]=27;
        scan(1);commit(1,3,0);expect_batch(3);
        held_tag=batch_tag;held_lefts=batch_lefts;held_rights=batch_rights;held_count=batch_count;
        repeat(12) begin @(posedge clk);#1;
            if(!batch_valid || batch_tag!==held_tag || batch_lefts!==held_lefts || batch_rights!==held_rights || batch_count!==held_count)
                $fatal(1,"FAIL EXTRACT backpressure modified packet");
        end
        tests=tests+1;consume();
        // Thick bridge: cuts are committed before they can form identities.
        clear_values();fill(2,27,10);fill(2,7,20);fill(12,17,20);fill(22,27,20);
        lefts[0]=2;rights[0]=9;lefts[1]=10;rights[1]=19;lefts[2]=20;rights[2]=27;
        scan(2);cut(9,2);cut(19,2);
        repeat(6) begin @(posedge clk);#1;if(batch_valid) $fatal(1,"FAIL EXTRACT provisional cut published");end
        commit(2,3,2);expect_batch(3);consume();
        // Gap=2 retains a one-column hole and below-high support thereafter.
        clear_values();fill(2,4,20);fill(6,8,10);lefts[0]=2;rights[0]=8;
        scan(3);commit(3,1,0);expect_batch(1);consume();
        // Too-small segment is discarded, low threshold is strict (>low).
        clear_values();fill(2,2,20);fill(12,15,20);lefts[0]=12;rights[0]=15;
        scan(4);commit(4,1,0);expect_batch(1);consume();
        clear_values();scan(5);commit(5,0,0);expect_batch(0);consume();
        // Last column must create and close an object on the same evaluation.
        clear_values();fill(31,31,20);commit_min_width=1;lefts[0]=31;rights[0]=31;
        scan(6);commit(6,1,0);expect_batch(1);consume();
        // A delayed final-column cut may share the commit edge.
        clear_values();fill(2,31,20);commit_min_width=3;scan(7);
        @(negedge clk);cut_valid=1;cut_x=16;cut_frame_id=7;commit_valid=1;
        commit_frame_id=7;commit_count=2;commit_cut_count=1;commit_tag=258'h123456789;expected_tag=commit_tag;
        @(negedge clk);cut_valid=0;commit_valid=0;
        lefts[0]=2;rights[0]=16;lefts[1]=17;rights[1]=31;
        expect_batch(2);consume();

        // Ordered sample count / frame identity are enforced.
        reset_context();base_faults=errors;clear_values();for(i=0;i<12;i=i+1) sample(i,0,8);
        commit(8,0,0);expect_rejection(base_faults);
        reset_context();base_faults=errors;sample(0,20,9);sample(2,20,9);commit(9,1,0);expect_rejection(base_faults);
        reset_context();base_faults=errors;sample(0,20,10);sample(1,20,99);commit(10,1,0);expect_rejection(base_faults);
        reset_context();base_faults=errors;clear_values();scan(11);cut(8,12);commit(11,0,1);expect_rejection(base_faults);
        reset_context();base_faults=errors;clear_values();fill(2,27,20);scan(12);cut(10,12);cut(10,12);commit(12,3,2);expect_rejection(base_faults);
        reset_context();base_faults=errors;clear_values();scan(13);commit(13,0,1);expect_rejection(base_faults);
        reset_context();base_faults=errors;clear_values();scan(14);commit(14,1,0);expect_rejection(base_faults);
        reset_context();base_faults=errors;clear_values();fill(2,10,20);scan(15);cut(1,15);commit(15,2,1);expect_rejection(base_faults);
        reset_context();base_faults=errors;clear_values();fill(2,10,20);scan(16);cut(10,16);commit(16,2,1);expect_rejection(base_faults);
        reset_context();base_faults=errors;clear_values();fill(2,10,20);scan(17);cut(2,17);commit(17,2,1);expect_rejection(base_faults);
        reset_context();base_faults=errors;clear_values();fill(0,2,20);fill(6,8,20);fill(12,14,20);fill(18,20,20);fill(24,26,20);
        scan(18);commit(18,4,0);expect_rejection(base_faults);
        reset_context();base_faults=errors;clear_values();scan(19);commit(19,5,0);expect_rejection(base_faults);
        reset_context();base_faults=errors;clear_values();scan(20);commit_high=0;commit(20,0,0);expect_rejection(base_faults);
        reset_context();base_faults=errors;clear_values();scan(21);commit_gap=0;commit(21,0,0);expect_rejection(base_faults);
        reset_context();base_faults=errors;clear_values();scan(22);commit(999,0,0);expect_rejection(base_faults);

        // Busy collision cannot leak a partial object set.
        reset_context();base_faults=errors;clear_values();fill(2,10,20);scan(23);commit(23,1,0);
        sample(0,20,24);expect_rejection(base_faults);
        // A held packet survives rejected input byte for byte until flush.
        reset_context();clear_values();fill(2,10,20);scan(25);commit(25,1,0);lefts[0]=2;rights[0]=10;expect_batch(1);
        held_tag=batch_tag;held_lefts=batch_lefts;held_rights=batch_rights;base_faults=errors;
        sample(0,20,26);repeat(4) @(negedge clk);
        if(errors<=base_faults || !batch_valid || batch_tag!==held_tag || batch_lefts!==held_lefts || batch_rights!==held_rights)
            $fatal(1,"FAIL EXTRACT occupied packet corruption");
        tests=tests+1;reset_context();tests=tests+1;
        // Flush during processing cancels the candidate without resetting counters.
        clear_values();fill(2,10,20);scan(27);commit(27,1,0);repeat(8) @(negedge clk);
        base_faults=fault_count;reset_context();repeat(4*W) @(negedge clk);
        if(batch_valid || fault_count!=base_faults) $fatal(1,"FAIL EXTRACT flush process/diagnostics");
        tests=tests+1;
        // Clean frame after all malformed inputs proves recovery.
        clear_values();fill(8,17,20);lefts[0]=8;rights[0]=17;scan(28);commit(28,1,0);expect_batch(1);consume();
        // Last sample and commit may be accepted on the same edge.
        clear_values();fill(27,31,20);lefts[0]=27;rights[0]=31;
        for(i=0;i<31;i=i+1) begin
            @(negedge clk);sample_valid=1;sample_x=i;sample_value=values[i];sample_frame_id=29;
        end
        @(negedge clk);sample_x=31;sample_value=values[31];commit_valid=1;
        commit_frame_id=29;commit_count=1;commit_cut_count=0;commit_tag=258'h29500;expected_tag=commit_tag;
        @(negedge clk);sample_valid=0;commit_valid=0;
        expect_batch(1);consume();
        // Exactly high starts; exactly low does not extend support. One low
        // column below gap keeps the segment, trailing equality is trimmed.
        clear_values();commit_high=15;commit_low=5;
        fill(4,6,15);fill(7,7,5);fill(8,10,6);fill(11,12,5);
        lefts[0]=4;rights[0]=10;scan(30);commit(30,1,0);expect_batch(1);consume();
        wait(fullsize_done);
        $display("PASS CONVEYOR EXTRACT cases=%0d batches=%0d faults=%0d width640=PASS committed_intervals/gaps/cuts/backpressure/flush/recovery",tests+1,batches,fault_count);
        $finish;
    end
    initial begin #1000000;$fatal(1,"FAIL EXTRACT watchdog");end
endmodule

// Real projection width verifies the full RAM address span and parameterized
// scan latency independently of the short directed protocol tests above.
module conveyor_extract_fullsize_check_pipelined(input wire clk,output reg done=0);
    reg rst_n=0,flush=0,sample_valid=0,cut_valid=0,commit_valid=0,batch_ready=0;
    reg [15:0] sample_x=0,sample_value=0,cut_x=300;
    reg [31:0] sample_frame_id=32'hf001,cut_frame_id=32'hf001,commit_frame_id=32'hf001;
    reg [128:0] commit_tag={1'b1,32'h12345678,32'h9abcdef0,32'h81000000,32'hf001};
    reg [15:0] commit_count=3,commit_cut_count=1,commit_high=15,commit_low=0,commit_min_width=3,commit_gap=2;
    wire batch_valid,busy,fault,fault_sticky;
    wire [128:0] batch_tag;
    wire [7:0] batch_count,fault_reason;
    wire [31:0] fault_count;
    wire [63:0] batch_lefts,batch_rights;
    projection_object_extractor #(.PIPELINED_FAULT_COUNTER(1),.WIDTH(640),.MAX_OBJECTS(4),.TAG_WIDTH(129)) dut(.*);
    integer x,cycles;
    reg [128:0] saved_tag;
    initial begin
        repeat(4) @(negedge clk);rst_n=1;
        for(x=0;x<640;x=x+1) begin
            @(negedge clk);sample_valid=1;sample_x=x;
            sample_value=(x>=12 && x<=55)||(x>=210 && x<=420) ? 20 : 0;
            if(x>=280 && x<=320) sample_value=8;
            cut_valid=(x==400);
        end
        @(negedge clk);sample_valid=0;cut_valid=0;commit_valid=1;saved_tag=commit_tag;
        @(negedge clk);commit_valid=0;commit_high=0;commit_low=99;commit_min_width=600;commit_gap=600;
        cycles=0;
        while(!batch_valid && cycles<3*640+8*4+32) begin @(posedge clk);#1;cycles=cycles+1;end
        if(!batch_valid || batch_count!=3 || batch_tag!==saved_tag || fault_sticky ||
           batch_lefts[15:0]!=12 || batch_rights[15:0]!=55 ||
           batch_lefts[31:16]!=210 || batch_rights[31:16]!=300 ||
           batch_lefts[47:32]!=301 || batch_rights[47:32]!=420 ||
           batch_lefts[63:48]!=0 || batch_rights[63:48]!=0)
            $fatal(1,"FAIL EXTRACT WIDTH640/config snapshot/tag/intervals");
        repeat(4) @(negedge clk);
        batch_ready=1;@(negedge clk);batch_ready=0;
        if(batch_valid) $fatal(1,"FAIL EXTRACT WIDTH640 handshake");
        done=1;
    end
endmodule

