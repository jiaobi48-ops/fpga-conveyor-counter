`timescale 1ns/1ps
module tb_adaptive_policy;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,start=0;
    reg [31:0] num=0,den=1;
    wire busy,done,zero;wire [31:0] quotient;
    unsigned_divider32 divider(.clk(clk),.rst_n(rst_n),.start(start),.numerator(num),
        .denominator(den),.busy(busy),.done(done),.divide_by_zero(zero),.quotient(quotient));
    reg fs=0,auto_t=1,su=0,sa=1;
    reg [31:0] epoch=1,sum=0,pixels=1,fid=1,sepoch=1;
    reg [7:0] manual=128,tmin=20,tmax=220,step=16,smin=20,smax=220;
    reg signed [8:0] offset=24;
    wire [7:0] selected,active,mean,target;
    wire mb,mu,tv;wire [31:0] mid,tid,te,skips;
    adaptive_threshold policy(.clk(clk),.rst_n(rst_n),.frame_start(fs),.frame_epoch(epoch),
        .cfg_auto(auto_t),.cfg_manual(manual),.cfg_min(tmin),.cfg_max(tmax),.cfg_step(step),
        .stats_update(su),.stats_sum(sum),.stats_pixels(pixels),.stats_frame_id(fid),.stats_epoch(sepoch),
        .stats_auto(sa),.stats_min(smin),.stats_max(smax),.stats_offset(offset),
        .selected_threshold(selected),.active_threshold(active),.busy(mb),.mean_update(mu),
        .mean_gray(mean),.target_threshold(target),.mean_frame_id(mid),.target_frame_id(tid),
        .target_epoch(te),.skipped_statistics(skips),.target_valid(tv));
    reg ns=0,na=1;reg [31:0] ni=0,ne=1,fg=100,iso=0;
    reg [7:0] on=64,off=16,nconfirm=2;reg [15:0] minimum=10;
    wire nv;wire [1:0] nm;wire [31:0] nme,nmid;
    dynamic_noise_policy noise(.clk(clk),.rst_n(rst_n),.stats_update(ns),.stats_frame_id(ni),
        .stats_epoch(ne),.stats_foreground(fg),.stats_isolated(iso),.cfg_auto(na),
        .cfg_on(on),.cfg_off(off),.cfg_confirm(nconfirm),.cfg_min_foreground(minimum),
        .mode_valid(nv),.suggested_mode(nm),.mode_epoch(nme),.mode_frame_id(nmid));
    integer jobs=0,n,k;reg [31:0] seed=32'h81478925;
    task automatic divide_case(input reg [31:0] a,b);
        integer age;
        begin
            @(negedge clk);num=a;den=b;start=1;
            @(posedge clk);#1;
            if(b==0) begin if(!done||!zero||quotient!=0) $fatal(1,"FAIL zero division");end
            else begin
                if(!busy||done) $fatal(1,"FAIL divider start");
                @(negedge clk);start=0;
                for(age=1;age<=32;age=age+1) begin
                    @(posedge clk);#1;
                    if(done!=(age==32)) $fatal(1,"FAIL divider latency");
                end
                if(quotient!=a/b||zero||busy) $fatal(1,"FAIL divider %0d/%0d",a,b);
            end
            @(negedge clk);start=0;jobs=jobs+1;
        end
    endtask
    task automatic frame(input integer expected);
        begin
            @(negedge clk);fs=1;#1;
            if(selected!=expected) $fatal(1,"FAIL selected threshold got=%0d expected=%0d",selected,expected);
            @(negedge clk);fs=0;
            if(active!=expected) $fatal(1,"FAIL active threshold");
        end
    endtask
    task automatic statistics(input integer a,b,ofs,ep,expected_mean,expected_target);
        integer watchdog;
        begin
            @(negedge clk);sum=a;pixels=b;offset=ofs;sepoch=ep;su=1;fid=fid+1;
            @(negedge clk);su=0;watchdog=0;
            while(!mu&&watchdog<40) begin @(negedge clk);watchdog=watchdog+1;end
            if(!mu||mean!=expected_mean||target!=expected_target||mid!=fid)
                $fatal(1,"FAIL mean/target mean=%0d target=%0d expected=%0d,%0d",mean,target,expected_mean,expected_target);
        end
    endtask
    task automatic noise_case(input integer id,e,foreground,single,expected);
        begin
            @(negedge clk);ns=1;ni=id;ne=e;fg=foreground;iso=single;
            @(negedge clk);ns=0;
            if(!nv||nm!=expected||nmid!=id||nme!=e) $fatal(1,"FAIL noise policy id=%0d mode=%0d",id,nm);
        end
    endtask
    initial begin
        repeat(4) @(negedge clk);rst_n=1;
        divide_case(0,1);divide_case(32'hffffffff,1);divide_case(32'hffffffff,32'hffffffff);
        divide_case(78336000,307200);divide_case(1234,0);
        for(n=0;n<128;n=n+1) begin
            seed=1664525*seed+1013904223;num=seed;
            seed=1664525*seed+1013904223;divide_case(num,seed|1);
        end
        frame(128);statistics(6000,100,24,1,60,84);frame(112);frame(96);frame(84);
        step=0;statistics(25500,100,255,1,255,220);frame(84);
        step=255;frame(220);
        statistics(0,100,-256,1,0,20);frame(20);
        // An old epoch's job may finish but must never drive the new policy.
        epoch=2;manual=144;frame(144);frame(144);
        statistics(10000,100,-10,2,100,90);step=8;frame(136);
        auto_t=0;manual=73;frame(73);
        auto_t=1;tmin=200;tmax=50;manual=91;frame(91);
        // Complete an old job after the SOF that changed the policy epoch.
        tmin=20;tmax=220;epoch=3;sepoch=2;manual=150;
        @(negedge clk);su=1;sum=1000;pixels=100;offset=0;
        @(negedge clk);su=0;frame(150);
        repeat(40) @(negedge clk);
        if(te!=2) $fatal(1,"FAIL old pending job tag");
        frame(150);
        // A second stats event during division is counted and skipped.
        @(negedge clk);su=1;sum=500;pixels=10;
        @(negedge clk);su=0;
        repeat(2) @(negedge clk);su=1;
        @(negedge clk);su=0;
        repeat(40) @(negedge clk);
        if(skips!=1) $fatal(1,"FAIL adaptive busy accounting");
        noise_case(1,1,100,30,0);noise_case(2,1,100,30,3);
        noise_case(3,1,100,12,3); // Dead band holds opening.
        noise_case(4,1,100,0,3);noise_case(5,1,100,0,0);
        noise_case(6,1,100,30,0);noise_case(8,1,100,30,0);noise_case(9,1,100,30,3);
        noise_case(10,1,2,0,3); // Insufficient evidence holds opening.
        noise_case(11,1,0,0,3);noise_case(12,1,0,0,0);
        noise_case(13,2,100,30,0);noise_case(14,2,100,30,3);
        on=off;@(negedge clk);ns=1;@(negedge clk);ns=0;
        if(nv) $fatal(1,"FAIL invalid noise configuration");
        $display("PASS ADAPTIVE POLICY divider_jobs=%0d threshold_slew/clamp/epochs/busy noise_hysteresis/gaps",jobs);$finish;
    end
    initial begin #300000; $fatal(1,"FAIL policy watchdog");end
endmodule

module tb_stability;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,flush=0,update=0;
    reg [31:0] id=0,epoch=1;
    reg [15:0] count=0;
    reg [1:0] mode=1;reg [7:0] confirm=3;
    wire sv,su,changed;wire [15:0] sc;wire [31:0] sid,se,duplicates,stale,gaps;wire [7:0] fill;
    count_stabilizer dut(.in_history_epoch(32'd0),.clk(clk),.rst_n(rst_n),.flush(flush),.in_update(update),
        .in_frame_id(id),.in_epoch(epoch),.in_count(count),.cfg_mode(mode),.cfg_confirm(confirm),
        .stable_valid(sv),.stable_update(su),.stable_changed(changed),.stable_count(sc),
        .stable_frame_id(sid),.stable_epoch(se),.history_fill(fill),
        .duplicate_results(duplicates),.stale_results(stale),.gap_resets(gaps));
    integer events=0,commits=0,k,a,b,c,d,e,j,n;integer ref_history[0:4],sorted[0:4],tmp;
    reg [31:0] random_state=32'h41763152;
    reg mv=0,mflush=0;reg [15:0] ma,mb,mc,md,me;
    reg [63:0] mtag=0;wire mov;wire [15:0] median;wire [63:0] otag;
    median5_pipeline pipeline(.clk(clk),.rst_n(rst_n),.flush(mflush),.in_valid(mv),
        .a(ma),.b(mb),.c(mc),.d(md),.e(me),.in_tag(mtag),.out_valid(mov),.median(median),.out_tag(otag));
    task automatic sample(input integer frame,value,expected_valid,expected_update,expected_count);
        integer seen_updates;
        begin
            @(negedge clk);id=frame;count=value;update=1;seen_updates=0;
            @(posedge clk);#1;if(su) seen_updates=seen_updates+1;
            @(negedge clk);update=0;
            repeat(7) begin @(posedge clk);#1;if(su) seen_updates=seen_updates+1;end
            if(sv!=expected_valid||seen_updates!=expected_update||(expected_valid&&sc!=expected_count))
                $fatal(1,"FAIL stable id=%0d mode=%0d value=%0d valid=%0d commits=%0d count=%0d expected=%0d,%0d,%0d",
                    frame,mode,value,sv,seen_updates,sc,expected_valid,expected_update,expected_count);
            if(expected_update&&sid!=frame) $fatal(1,"FAIL stable frame tag");
            events=events+1;commits=commits+seen_updates;
        end
    endtask
    task automatic median_case;
        integer reference_median;
        begin
            sorted[0]=ma;sorted[1]=mb;sorted[2]=mc;sorted[3]=md;sorted[4]=me;
            for(k=0;k<5;k=k+1) for(j=k+1;j<5;j=j+1)
                if(sorted[k]>sorted[j]) begin tmp=sorted[k];sorted[k]=sorted[j];sorted[j]=tmp;end
            reference_median=sorted[2];
            @(negedge clk);mv=1;mtag=mtag+1;
            @(negedge clk);mv=0;
            repeat(4) @(negedge clk);
            if(!mov||median!=reference_median||otag!=mtag)
                $fatal(1,"FAIL median network valid=%0d median=%0d expected=%0d tag=%0d/%0d",mov,median,reference_median,otag,mtag);
            @(negedge clk);
        end
    endtask
    initial begin
        repeat(4) @(negedge clk);rst_n=1;
        sample(1,3,0,0,0);sample(2,3,0,0,0);sample(3,4,0,0,0);sample(4,3,0,0,0);
        sample(5,3,1,1,3);sample(6,4,1,1,3);sample(7,4,1,1,4);
        sample(7,9,1,0,4);sample(6,9,1,0,4);
        if(duplicates!=1||stale!=1) $fatal(1,"FAIL duplicate/stale tracking");
        sample(9,2,0,0,0);sample(10,2,0,0,0);sample(11,2,0,0,0);sample(12,2,0,0,0);sample(13,2,1,1,2);
        if(gaps!=1) $fatal(1,"FAIL gap tracking");
        epoch=2;sample(14,8,0,0,0);
        mode=2;sample(15,3,0,0,0);sample(16,3,0,0,0);sample(17,3,1,1,3);
        sample(18,4,1,0,3);sample(19,3,1,0,3);sample(20,4,1,0,3);
        sample(21,4,1,0,3);sample(22,4,1,1,4);
        @(negedge clk);flush=1;@(negedge clk);flush=0;
        if(sv||fill!=0) $fatal(1,"FAIL explicit flush");
        mode=0;sample(32'hfffffffe,65535,1,1,65535);sample(32'hffffffff,0,1,1,0);sample(0,7,1,1,7);
        mode=3;sample(1,8,0,0,0);
        // Flush a fifth-sample median while it is still travelling in the sorter.
        mode=1;epoch=3;
        sample(2,6,0,0,0);sample(3,6,0,0,0);sample(4,6,0,0,0);sample(5,6,0,0,0);
        @(negedge clk);id=6;count=6;update=1;
        @(negedge clk);update=0;flush=1;
        @(negedge clk);flush=0;
        repeat(8) begin @(posedge clk);#1;if(su||sv) $fatal(1,"FAIL pending median cancellation");end
        // All 120 permutations and 128 seeded arbitrary 16-bit vectors.
        n=0;
        for(a=1;a<=5;a=a+1) for(b=1;b<=5;b=b+1) for(c=1;c<=5;c=c+1)
          for(d=1;d<=5;d=d+1) for(e=1;e<=5;e=e+1)
            if(a!=b&&a!=c&&a!=d&&a!=e&&b!=c&&b!=d&&b!=e&&c!=d&&c!=e&&d!=e) begin
                ma=a;mb=b;mc=c;md=d;me=e;median_case();n=n+1;
            end
        for(a=0;a<128;a=a+1) begin
            random_state=1664525*random_state+1013904223;ma=random_state;
            random_state=1664525*random_state+1013904223;mb=random_state;
            random_state=1664525*random_state+1013904223;mc=random_state;
            random_state=1664525*random_state+1013904223;md=random_state;
            random_state=1664525*random_state+1013904223;me=random_state;median_case();n=n+1;
        end
        $display("PASS ADAPTIVE STABILITY events=%0d commits=%0d median_vectors=%0d duplicate/stale/gap/epoch/flush/wrap",events,commits,n);$finish;
    end
    initial begin #300000; $fatal(1,"FAIL stability watchdog");end
endmodule
