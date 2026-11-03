`timescale 1ns/1ps
module tb_guard_supervisor;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,enable=1,scene_valid=1,explicit_rearm=0,integrity_fault=0,link_fault=0;
    reg update=0,frame_good=1,geometry_good=1,guard_enabled=1;
    reg [31:0] frame_id=0,source_id=0,source_generation=1,timestamp=0,epoch=1;
    reg [31:0] roi_pixels=1000,foreground_pixels=0,guard_pixels=100,guard_dark=0,guard_warm=0;
    reg [8:0] cfg_dark_on=128,cfg_dark_off=64,cfg_warm_on=32,cfg_warm_off=16,cfg_empty_ratio=8;
    reg [7:0] cfg_normal_frames=3,cfg_empty_frames=2;
    reg [31:0] cfg_timeout_cycles=1000;
    wire [2:0] state;wire [15:0] reason,current_frame_reason,sticky_reasons;
    wire blocked,policy_hold,history_flush,report_update,report_count_allowed,report_policy_allowed;
    wire [31:0] report_frame_id,accepted_source_frames,duplicate_reports,stale_reports,blocked_frames,recoveries,age_cycles;
    wire [7:0] normal_count,empty_count;
    scene_recovery_supervisor dut(.*);
    integer checks=0,reports=0;
    task check(input bit condition,input string msg);
        checks++;if(!condition)$fatal(1,"FAIL GUARD SUPERVISOR %s state=%0d reason=%h",msg,state,reason);
    endtask
    task report(input integer next_state,input bit allowed,input bit advance=1);
        @(negedge clk);if(advance)source_id++;frame_id++;timestamp+=100;update=1;
        @(negedge clk);
        check(report_update&&report_frame_id==frame_id,"coherent pulse and ID");
        check(state==next_state&&report_count_allowed==allowed&&report_policy_allowed==allowed,"state and frame permission");
        check(blocked==(enable&&state!=5)&&policy_hold==blocked,"current block meaning");
        update=0;reports++;
    endtask
    task recover;
        report(3,0);report(3,0);report(4,0);report(4,0);report(5,0);report(5,1);
    endtask
    initial begin
        repeat(4)@(negedge clk);rst_n=1;recover();
        report(5,0,0);check(duplicate_reports==1,"duplicate frame cannot confirm/count");
        report(5,1);
        guard_dark=60;report(2,0);check(reason==1,"dark reason");
        guard_dark=30;report(2,0);check(reason==1,"exit hysteresis retains block");
        guard_dark=20;report(3,0);report(3,0);report(4,0);
        foreground_pixels=300;repeat(5)report(4,0);check(empty_count==0,"occupied scene cannot timeout into ready");
        foreground_pixels=0;report(4,0);report(5,0);report(5,1);
        guard_dark=0;guard_warm=20;report(2,0);check(reason==2,"warm reason independent of dark");
        guard_warm=8;report(2,0);guard_warm=0;recover();
        frame_good=0;report(2,0);check(current_frame_reason[2],"invalid image distinct from color");
        frame_good=1;recover();
        @(negedge clk);explicit_rearm=1;@(negedge clk);explicit_rearm=0;
        check(state==3&&history_flush,"rearm flushes history, no total clear port exists");recover();
        source_id+=2;report(3,0);report(3,0);report(4,0);report(4,0);report(5,0);report(5,1);
        scene_valid=0;@(negedge clk);@(negedge clk);check(state==1&&reason[4],"uncalibrated cannot run");
        scene_valid=1;recover();
        source_generation++;recover();
        cfg_timeout_cycles=12;repeat(14)@(negedge clk);check(state==6&&reason[3],"physical watchdog without any frame");
        repeat(4)report(6,0,0);check(duplicate_reports==5,"replayed reports do not reset freshness watchdog");
        cfg_timeout_cycles=1000;recover();
        @(negedge clk);link_fault=1;@(negedge clk);check(state==6&&reason[7],"link failure distinct");
        link_fault=0;recover();
        @(negedge clk);source_id-=10;report(6,0,0);check(stale_reports==1,"older source frame fails closed");
        source_generation++;source_id=32'hfffffffa;recover();report(5,1);
        check(source_id==1,"serial frame identity wraps modulo 32 bits");
        enable=0;guard_dark=100;@(negedge clk);report(0,1);check(!blocked,"explicit bypass");
        enable=1;cfg_dark_on=300;report(1,0);check(reason[4],"invalid ratio rejected");
        check(sticky_reasons[0]&&sticky_reasons[1]&&sticky_reasons[2]&&sticky_reasons[3]&&sticky_reasons[7],"current and historical reasons separated");
        $display("PASS GUARD SUPERVISOR reports=%0d checks=%0d duplicate/stale/wrap/hysteresis/occupied/rearm/timeout/link/config",reports,checks);$finish;
    end
    initial begin #1000000;$fatal(1,"FAIL GUARD SUPERVISOR watchdog");end
endmodule
