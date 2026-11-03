`timescale 1ns/1ps
module tb_parallel_consensus;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,flush=0,enable=1,cv=0,lv=0,hv=0,ready=0;
    reg [15:0] tolerance=2;
    reg [257:0] tag;reg [63:0] lt,ht;
    reg [7:0] cc=0,lc=0,hc=0;
    reg [63:0] cl=0,cr=0,ll=0,lr=0,hl=0,hr=0;
    wire cready,lready,hready,ov,busy,fault,sticky;
    wire [257:0] ot;wire [7:0] oc,why;wire [63:0] ol,orr;wire [11:0] support;
    wire [31:0] rejects,disagreements,dropped;
    interval_consensus3 #(.MAX_OBJECTS(4),.WAIT_CYCLES(16)) dut(
        .clk(clk),.rst_n(rst_n),.flush(flush),.cfg_enable(enable),.cfg_tolerance(tolerance),
        .c_valid(cv),.c_ready(cready),.c_tag(tag),.c_count(cc),.c_lefts(cl),.c_rights(cr),
        .l_valid(lv),.l_ready(lready),.l_tag(lt),.l_count(lc),.l_lefts(ll),.l_rights(lr),
        .h_valid(hv),.h_ready(hready),.h_tag(ht),.h_count(hc),.h_lefts(hl),.h_rights(hr),
        .out_valid(ov),.out_ready(ready),.out_tag(ot),.out_count(oc),.out_lefts(ol),.out_rights(orr),.out_support(support),
        .busy(busy),.fault(fault),.fault_sticky(sticky),.fault_reason(why),.rejected_frames(rejects),.disagreement_frames(disagreements),.dropped_objects(dropped));
    integer cases=0,i,guard;reg [63:0] heldl,heldr;reg [257:0] heldtag;
    task start_packet;
        begin
            @(negedge clk);tag={97'd0,1'b0,32'd11,32'd0,32'd7,32'd1,32'(cases+1)};
            lt={32'd7,32'(cases+1)};ht=lt;cv=1;lv=enable;hv=enable;
             #1;guard=0;while(!cready&&guard<30)begin @(negedge clk);guard=guard+1;end
            if(!cready)$fatal(1,"FAIL PARALLEL CONSENSUS input ready");
            @(negedge clk);cv=0;lv=0;hv=0;
        end
    endtask
    task good(input integer number,input [63:0] lefts,rights,input [11:0] votes);
        begin
            guard=0;while(!ov&&!fault&&guard<1000)begin @(negedge clk);guard=guard+1;end
            if(!ov||fault||oc!=number||ol!==lefts||orr!==rights||support!==votes||ot!==tag)
                $fatal(1,"FAIL PARALLEL CONSENSUS case=%0d count=%0d support=%h why=%0d",cases,oc,support,why);
            heldl=ol;heldr=orr;heldtag=ot;
            repeat(4) begin @(negedge clk);if(!ov||ol!=heldl||orr!=heldr||ot!=heldtag)$fatal(1,"FAIL PARALLEL CONSENSUS held packet");end
            ready=1;@(negedge clk);ready=0;cases=cases+1;
        end
    endtask
    task bad(input integer code);
        begin
            guard=0;while(!fault&&guard<1000)begin @(negedge clk);guard=guard+1;end
            if(!fault||ov||why!=code)$fatal(1,"FAIL PARALLEL CONSENSUS reject case=%0d why=%0d",cases,why);
            cases=cases+1;@(negedge clk);flush=1;@(negedge clk);flush=0;
        end
    endtask
    initial begin
        repeat(3)@(negedge clk);rst_n=1;
        cc=2;lc=2;hc=2;cl={32'd0,16'd35,16'd10};cr={32'd0,16'd45,16'd20};ll=cl;lr=cr;hl=cl;hr=cr;
        start_packet();good(2,cl,cr,12'h03f);
        lc=2;cc=3;hc=2;ll={32'd0,16'd35,16'd10};lr={32'd0,16'd45,16'd27};
        cl={16'd0,16'd35,16'd25,16'd10};cr={16'd0,16'd45,16'd27,16'd20};
        hl={32'd0,16'd35,16'd10};hr={32'd0,16'd45,16'd20};
        start_packet();good(2,hl,hr,12'h03e);
        lc=1;ll=35;lr=45;cc=2;cl=hl;cr=hr;start_packet();good(2,hl,hr,12'h03e);
        lc=0;cc=0;hc=0;start_packet();good(0,0,0,0);
        lc=1;cc=2;hc=1;tolerance=8;ll=10;lr=20;hl=10;hr=20;cl={32'd0,16'd18,16'd7};cr={32'd0,16'd28,16'd17};start_packet();bad(5);
        tolerance=2;cc=1;lc=1;hc=1;cl=10;cr=20;ll=10;lr=20;hl=10;hr=20;
        @(negedge clk);tag={97'd0,1'b0,32'd11,32'd0,32'd7,32'd1,32'd30};lt={32'd8,32'd30};ht=lt;
        cv=1;lv=1;hv=1;@(negedge clk);cv=0;lv=0;hv=0;bad(1);
        lc=2;ll={32'd0,16'd20,16'd10};lr={32'd0,16'd30,16'd20};start_packet();bad(4);
        enable=0;cc=3;cl={16'd0,16'd40,16'd25,16'd10};cr={16'd0,16'd45,16'd28,16'd20};start_packet();good(3,cl,cr,12'h492);
        enable=1;@(negedge clk);lv=1;cv=0;hv=0;bad(3);lv=0;
        @(negedge clk);lv=1;repeat(3)@(negedge clk);flush=1;@(negedge clk);flush=0;lv=0;
        repeat(20)@(negedge clk);if(ov||fault)$fatal(1,"FAIL PARALLEL CONSENSUS flush");cases=cases+1;
        $display("PASS PARALLEL CONSENSUS cases=%0d rejected=%0d disagreement=%0d dropped=%0d voting/central_outlier/empty/ambiguity/tag/order/bypass/backpressure/timeout/flush",cases,rejects,disagreements,dropped);$finish;
    end
    initial begin #1000000;$fatal(1,"FAIL PARALLEL CONSENSUS watchdog");end
endmodule

module tb_parallel_speed;
    localparam W=64,K=8;
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
            guard=0;while(!update&&guard<1000)begin @(negedge clk);guard=guard+1;end
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
        $display("PASS PARALLEL SPEED cases=%0d exhaustive_reference/left/right/stop/gap/context/empty/clipped/tie/disable/flush/timestamp_wrap/malformed",cases);$finish;
    end
    initial begin #1000000;$fatal(1,"FAIL PARALLEL SPEED watchdog");end
endmodule
