`timescale 1ns/1ps
module tb_valley_vectors #(parameter integer W=32,N=854,PIPE=0);
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,sv=0;
    reg [31:0] sid=0;
    reg [1:0] mode=0;
    reg [15:0] hi=0,lo=0,mw=0,gap=0,depth=0,vwidth=0,distance=0,support=0;
    reg enable=0;
    reg [7:0] ratio=0;
    wire req,busy,rv,update,abort,sample,cut;
    wire [15:0] addr,count,cut_count,cx,sx,sp,rhi,rlo,rmw,rgap,rdp,rvw,rds,rsp;
    wire [31:0] rid,aborts,sample_id,cut_id;
    wire [1:0] rmode;
    wire [2:0] reason;
    wire ren;
    wire [7:0] rratio;
    reg ready=0,valid=0,error=0;
    reg [15:0] ra=0,data=0;
    reg [31:0] rf=0;
    projection_valley_scanner #(.WIDTH(W),.PIPELINED(PIPE),.TIMEOUT_CYCLES(4*W+32)) dut (
        .clk(clk),.rst_n(rst_n),.snapshot_valid(sv),.snapshot_frame_id(sid),.snapshot_mode(mode),
        .cfg_high(hi),.cfg_low(lo),.cfg_min_width(mw),.cfg_gap(gap),
        .cfg_valley_enable(enable),.cfg_valley_ratio(ratio),.cfg_valley_depth(depth),
        .cfg_valley_width(vwidth),.cfg_peak_distance(distance),.cfg_peak_support(support),
        .rd_req(req),.rd_addr(addr),.rd_ready(ready),.rd_valid(valid),.rd_error(error),
        .rd_resp_addr(ra),.rd_data(data),.rd_frame_id(rf),.busy(busy),
        .result_valid(rv),.result_update(update),.scan_abort(abort),.abort_reason(reason),
        .aborted_scans(aborts),.result_frame_id(rid),.result_count(count),.result_mode(rmode),
        .result_high(rhi),.result_low(rlo),.result_min_width(rmw),.result_gap(rgap),
        .result_valley_enable(ren),.result_valley_ratio(rratio),.result_valley_depth(rdp),
        .result_valley_width(rvw),.result_peak_distance(rds),.result_peak_support(rsp),
        .result_cut_count(cut_count),.cut_update(cut),.cut_x(cx),.cut_frame_id(cut_id),
        .sample_valid(sample),.sample_x(sx),.sample_value(sp),.sample_frame_id(sample_id)
    );
    localparam STRIDE=14+2*W;
    reg [15:0] vectors[0:N*STRIDE-1];
    integer n=0,base=0,fault=0,age=0,ticks=0,accepted=0,samples=0,cuts=0;
    integer total_good=0,total_bad=0,total_samples=0,total_cuts=0,total_stalls=0;
    integer guard=0;
    reg pending=0,injected=0,prev_update=0,prev_abort=0;
    reg [15:0] pa=0,pd=0;
    reg [31:0] pf=0;
    string vector_path;
    always @(posedge clk) begin
        if(!rst_n) begin pending<=0;valid<=0;error<=0;age=0;end
        else begin
            if(req&&ready) begin
                if(addr!==accepted||addr>=W) $fatal(1,"FAIL valley request order");
                accepted=accepted+1;
            end
            if(req&&!ready) total_stalls=total_stalls+1;
            if(sample) begin
                if(sample_id!=n+1||sx!=samples||sp!=vectors[base+14+samples])
                    $fatal(1,"FAIL valley sample case%0d x%0d",n,sx);
                samples=samples+1;total_samples=total_samples+1;
            end
            valid<=pending&&(fault!=8);error<=0;ra<=pa;data<=pd;rf<=pf;
            if(pending&&pa==2&&!injected&&fault>=3&&fault<=5) begin
                injected=1;
                if(fault==3) rf<=pf+10000;
                if(fault==4) ra<=pa+1;
                if(fault==5) error<=1;
            end
            if(busy&&age==0&&fault==6) begin valid<=1;rf<=sid;ra<=0;data<=50;end
            pending<=req&&ready;
            if(req&&ready) begin pa<=addr;pd<=vectors[base+14+addr];pf<=sid;end
            if(busy) age=age+1;else age=0;
            #1;
            if(update&&prev_update||abort&&prev_abort||update&&abort) $fatal(1,"FAIL valley pulses");
            prev_update=update;prev_abort=abort;
            if(cut) begin
                if(cut_id!=n+1||cx!==vectors[base+14+W+cuts]||cuts>=vectors[base+11])
                    $fatal(1,"FAIL valley cut W%0d case%0d x%0d expected%0d",W,n,cx,vectors[base+14+W+cuts]);
                cuts=cuts+1;total_cuts=total_cuts+1;
            end
        end
    end
    always @(negedge clk) begin
        ticks=ticks+1;ready=rst_n&&fault!=7&&ticks%7!=0&&ticks%11!=0;
        if(busy) begin
            hi=0;lo=65535;mw=0;gap=0;enable=0;ratio=0;depth=0;vwidth=0;distance=0;support=0;
            if(age==4&&fault==1) sv=0;
            if(age==4&&fault==2) sid=sid+10000;
            if(cuts>0&&fault==9) sv=0;
            if(samples==W&&fault==10) sv=0;
        end
    end
    initial begin
        if(!$value$plusargs("VECTORS=%s",vector_path)) $fatal(1,"FAIL missing valley vectors");
        $readmemh(vector_path,vectors);
        repeat(4) @(negedge clk);rst_n=1;
        for(n=0;n<N;n=n+1) begin
            base=n*STRIDE;accepted=0;samples=0;cuts=0;injected=0;fault=vectors[base+12];
            hi=vectors[base];lo=vectors[base+1];mw=vectors[base+2];gap=vectors[base+3];
            enable=vectors[base+4];ratio=vectors[base+5];depth=vectors[base+6];vwidth=vectors[base+7];
            distance=vectors[base+8];support=vectors[base+9];mode=n%4;sid=n+1;sv=1;
            @(posedge clk);#2;guard=0;
            while(!update&&!abort) begin
                @(posedge clk);#2;guard=guard+1;
                if(guard>(PIPE?2*(4*W+42):4*W+42)) $fatal(1,"FAIL valley watchdog");
            end
            if(vectors[base+13]) begin
                if(!abort||reason!=vectors[base+13]) $fatal(1,"FAIL valley abort case%0d",n);
                total_bad=total_bad+1;
            end else begin
                if(!update||!rv||rid!=n+1||rmode!=n%4||count!==vectors[base+10]||
                   cut_count!==vectors[base+11]||cuts!=cut_count||samples!=W)
                    $fatal(1,"FAIL valley count W%0d case%0d count%0d expected%0d cuts%0d expected%0d",W,n,count,vectors[base+10],cut_count,vectors[base+11]);
                if(rhi!==vectors[base]||rlo!==vectors[base+1]||rmw!==vectors[base+2]||rgap!==vectors[base+3]||
                   ren!==vectors[base+4][0]||rratio!==vectors[base+5][7:0]||rdp!==vectors[base+6]||
                   rvw!==vectors[base+7]||rds!==vectors[base+8]||rsp!==vectors[base+9]) $fatal(1,"FAIL valley config latch");
                total_good=total_good+1;
            end
            if(aborts!=total_bad) $fatal(1,"FAIL valley abort counter");
            @(negedge clk);sv=0;
            if(!vectors[base+13]) begin
                sv=1;repeat(3) begin @(posedge clk);#2;if(update||busy||abort||cut) $fatal(1,"FAIL repeated valley scan");end
                @(negedge clk);sv=0;
            end
            repeat(2) @(negedge clk);
        end
        @(negedge clk);rst_n=0;
        @(posedge clk);#2;if(busy||rv||update||abort||cut||aborts!=0) $fatal(1,"FAIL valley reset");
        $display("PASS VALLEY VECTORS W=%0d cases=%0d good=%0d aborted=%0d samples=%0d cuts=%0d stalls=%0d",W,N,total_good,total_bad,total_samples,total_cuts,total_stalls);
        $finish;
    end
endmodule
module tb_valley_unit;tb_valley_vectors unit();endmodule
module tb_valley_min;tb_valley_vectors #(.W(5),.N(3125)) unit();endmodule


module tb_valley_pipe32;tb_valley_vectors #(.PIPE(1)) unit();endmodule
module tb_valley_pipe5;tb_valley_vectors #(.W(5),.N(3125),.PIPE(1)) unit();endmodule
