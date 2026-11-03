`timescale 1ns/1ps
module tb_parallel_consensus_local;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,flush=0,enable=1,cv=0,lv=0,hv=0,ready=0;
    reg [15:0] tolerance=2;
    reg [257:0] tag;reg [63:0] lt,ht;
    reg [7:0] cc=0,lc=0,hc=0;
    reg [63:0] cl=0,cr=0,ll=0,lr=0,hl=0,hr=0;
    wire cready,lready,hready,ov,busy,fault,sticky;
    wire [257:0] ot;wire [7:0] oc,why;wire [63:0] ol,orr;wire [11:0] support;
    wire [31:0] rejects,disagreements,dropped;
    interval_consensus3 #(.MAX_OBJECTS(4),.WAIT_CYCLES(16),.LOCAL_PAYLOAD(1)) dut(
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
        // Cancellation coincident with private input capture must never publish.
        cc=1;lc=1;hc=1;cl=10;cr=20;ll=cl;lr=cr;hl=cl;hr=cr;
        @(negedge clk);tag=258'd99;lt=0;ht=0;cv=1;lv=1;hv=1;flush=1;
        @(negedge clk);cv=0;lv=0;hv=0;flush=0;
        repeat(20)begin @(negedge clk);if(ov||fault)$fatal(1,"FAIL LOCAL cancelled capture");end
        cases=cases+1;
        start_packet();
        guard=0;while(dut.state!=7&&guard<1000)begin @(negedge clk);guard=guard+1;end
        if(guard>=1000)$fatal(1,"FAIL LOCAL publish phase");
        flush=1;@(negedge clk);flush=0;
        repeat(20)begin @(negedge clk);if(ov||fault)$fatal(1,"FAIL LOCAL cancelled publication");end
        cases=cases+1;
        start_packet();good(1,cl,cr,12'h007);
        $display("PASS PARALLEL CONSENSUS LOCAL cases=%0d rejected=%0d disagreement=%0d dropped=%0d voting/central_outlier/empty/ambiguity/tag/order/bypass/backpressure/timeout/flush",cases,rejects,disagreements,dropped);$finish;
    end
    initial begin #1000000;$fatal(1,"FAIL PARALLEL CONSENSUS watchdog");end
endmodule
