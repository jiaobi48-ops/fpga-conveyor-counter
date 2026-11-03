`timescale 1ns/1ps
module tb_speed_indices800;
    localparam W=800,K=32;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,flush=0,iv=0,enabled=1;
    reg [31:0] fid=0,stamp=0;reg [127:0] ctx=1;reg test=0;
    reg [7:0] count=0;reg [63:0] lefts=0,rights=0;
    wire ready,busy,update,valid;wire signed [15:0] dx;
    wire [31:0] dt,ofid;wire [127:0] octx;wire ot;wire [15:0] best,second,pop;wire [7:0] reason;
    projection_correlation_speed #(.WIDTH(W),.MAX_OBJECTS(4),.MAX_SHIFT(K)) dut(
        .clk(clk),.rst_n(rst_n),.flush(flush),.in_valid(iv),.in_ready(ready),.cfg_enable(enabled),
        .cfg_min_foreground(16'd3),.cfg_margin(16'd1),.in_frame_id(fid),.in_timestamp(stamp),.in_context(ctx),.in_is_test(test),
        .in_count(count),.in_lefts(lefts),.in_rights(rights),.busy(busy),.update(update),.valid(valid),.dx(dx),
        .cycles_per_frame(dt),.frame_id(ofid),.context_tag(octx),.is_test(ot),.overlap(best),.second_overlap(second),.foreground_pixels(pop),.reason(reason));
    reg current[0:W-1],previous[0:W-1];reg history=0;
    reg [31:0] prev_id=0,prev_stamp=0;reg [127:0] prev_ctx=0;reg prev_test=0;
    integer cases=0,x,j,s,score,gold_best,gold_second,gold_dx,prev_pop,cur_pop,guard,expected_valid,compare,batch_bad;
    task submit(input integer id,time_value,n,a,b,c,d);
        begin
            @(negedge clk);fid=id;stamp=time_value;count=n;lefts={32'd0,16'(c),16'(a)};rights={32'd0,16'(d),16'(b)};
            cur_pop=0;prev_pop=0;batch_bad=n>4||(n>0&&(a>b||b>=W))||(n>1&&(c>d||d>=W||c<=b));
            for(x=0;x<W;x=x+1)begin
                current[x]=(n>0&&x>=a&&x<=b)||(n>1&&x>=c&&x<=d);
                cur_pop=cur_pop+current[x];prev_pop=prev_pop+previous[x];
            end
            compare=history&&ctx==prev_ctx&&test==prev_test&&32'(id)==prev_id+1&&32'(time_value)!=prev_stamp;
            gold_best=0;gold_second=0;gold_dx=0;
            for(s=-K;s<=K;s=s+1)begin
                score=0;
                if(compare)for(x=0;x<W;x=x+1)if(x-s>=0&&x-s<W)score=score+(current[x]&&previous[x-s]);
                if(score>gold_best)begin gold_second=gold_best;gold_best=score;gold_dx=s;end
                else if(score>gold_second)gold_second=score;
            end
            expected_valid=enabled&&!batch_bad&&compare&&cur_pop>=3&&prev_pop>=3&&gold_best>=3&&gold_best>gold_second&&gold_dx>-K&&gold_dx<K;
            iv=1;while(!ready)@(negedge clk);@(negedge clk);iv=0;
            guard=0;while(!update&&guard<(4*W+4*K+128))begin @(negedge clk);guard=guard+1;end
            if(!update||valid!=expected_valid||ofid!=fid||octx!=ctx||ot!=test||
               (valid&&(dx!=gold_dx||dt!=stamp-prev_stamp))||
               (enabled&&!batch_bad&&(best!=gold_best||second!=gold_second||pop!=cur_pop)))
                $fatal(1,"FAIL PARALLEL SPEED case=%0d valid=%0d/%0d dx=%0d/%0d overlap=%0d/%0d second=%0d/%0d reason=%h",cases,valid,expected_valid,dx,gold_dx,best,gold_best,second,gold_second,reason);
            cases=cases+1;
            if(!enabled||batch_bad)history=0;
            else begin history=1;for(x=0;x<W;x=x+1)previous[x]=current[x];prev_id=fid;prev_stamp=stamp;prev_ctx=ctx;prev_test=test;end
            @(negedge clk);
        end
    endtask
    initial begin
        for(x=0;x<W;x=x+1)previous[x]=0;
        repeat(3)@(negedge clk);rst_n=1;
        submit(1,100,2,30,38,48,56);submit(2,200,2,27,35,45,53);submit(3,330,2,24,32,42,50);
        submit(4,450,2,24,32,42,50);submit(5,550,2,28,36,46,54);
        submit(7,650,1,20,28,0,0);submit(8,750,1,17,25,0,0);
        ctx=2;submit(9,850,1,20,28,0,0);submit(10,950,1,22,30,0,0);
        submit(11,1050,0,0,0,0,0);submit(12,1150,0,0,0,0,0);
        submit(13,1250,1,35,43,0,0);submit(14,1350,1,27,35,0,0);
        submit(15,1450,1,27,39,0,0);
        enabled=0;submit(16,1550,1,25,33,0,0);enabled=1;
        submit(17,1650,1,25,33,0,0);submit(18,1750,1,22,30,0,0);
        @(negedge clk);flush=1;@(negedge clk);flush=0;history=0;
        submit(19,32'hfffffff0,1,22,30,0,0);submit(20,32'h20,1,24,32,0,0);
        submit(20,32'h30,1,24,32,0,0);submit(21,32'h30,1,24,32,0,0);
        submit(22,1000,1,50,80,0,0);submit(23,1100,1,20,28,0,0);submit(24,1200,1,18,26,0,0);
        $display("PASS SPEED INDICES800 cases=%0d exhaustive_reference/left/right/stop/gap/context/empty/clipped/tie/disable/flush/timestamp_wrap/malformed",cases);$finish;
    end
    initial begin #1000000;$fatal(1,"FAIL PARALLEL SPEED watchdog");end
endmodule

