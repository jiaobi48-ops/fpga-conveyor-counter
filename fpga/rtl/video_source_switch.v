`timescale 1ns/1ps
// Native PL video only: no DVP, AXI, or pixel-clock-domain crossing.
// Accept a whole frame, drain the algorithm, reset it, then seek the new SOF.
module video_source_switch #(
    parameter integer WIDTH=640, HEIGHT=480,
    parameter integer DEBOUNCE_CYCLES=1000000,
    parameter integer DRAIN_CYCLES=WIDTH+80,
    parameter integer FRAME_TIMEOUT_CYCLES=10000000,
    parameter integer DRAIN_TIMEOUT_CYCLES=20000000,
    parameter integer RESET_CYCLES=2, MIN_DRAIN_STEPS=10
) (
    input wire clk, rst_n, ce,
    input wire cfg_test_async,
    input wire cam_valid, cam_sof, cam_eol,
    input wire [23:0] cam_rgb,
    input wire test_valid, test_sof, test_eol,
    input wire [23:0] test_rgb,
    input wire algorithm_idle,
    output wire out_valid, out_sof, out_eol,
    output wire [23:0] out_rgb,
    output wire pipeline_rst_n,
    output wire test_enable, test_restart,
    output reg active_source,
    output reg requested_source,
    output wire switch_busy, waiting_for_sof,
    output reg switch_done, switch_fault,
    output reg fault_sticky,
    output reg [31:0] source_generation, switch_count,
    output reg [31:0] recovery_count, discarded_camera_pixels
);
    // Attribute covers the first two synchronizer flip-flops only.
    (* ASYNC_REG="TRUE" *) reg test_meta, test_sync;
    reg [31:0] debounce_count;
    always @(posedge clk) begin
        if(!rst_n) begin
            test_meta<=0;test_sync<=0;requested_source<=0;debounce_count<=0;
        end else begin
            test_meta<=cfg_test_async;test_sync<=test_meta;
            if(test_sync==requested_source) debounce_count<=0;
            else if(DEBOUNCE_CYCLES<=1 || debounce_count>=DEBOUNCE_CYCLES-1) begin
                requested_source<=test_sync;debounce_count<=0;
            end else debounce_count<=debounce_count+1'b1;
        end
    end

    localparam [1:0] RESET=0, SEEK=1, RUN=2, DRAIN=3;
    reg [1:0] state;
    reg [15:0] x,y;
    reg [31:0] frame_timer,drain_timer,drain_steps,reset_timer;
    reg [3:0] quiet_timer;
    wire selected_valid=active_source ? test_valid : cam_valid;
    wire selected_sof=active_source ? test_sof : cam_sof;
    wire selected_eol=active_source ? test_eol : cam_eol;
    wire [23:0] selected_rgb=active_source ? test_rgb : cam_rgb;
    wire beginning=state==SEEK&&requested_source==active_source&&selected_sof;
    wire marker_ok=(state==SEEK) ? !selected_eol :
                   (!selected_sof && selected_eol==(x==WIDTH-1));
    wire expired=state==RUN&&frame_timer>=FRAME_TIMEOUT_CYCLES-1;
    assign out_valid=rst_n&&!expired&&selected_valid&&marker_ok&&(beginning||state==RUN);
    assign out_sof=out_valid&&state==SEEK;
    assign out_eol=out_valid&&selected_eol;
    assign out_rgb=selected_rgb;
    assign pipeline_rst_n=rst_n&&state!=RESET;
    assign test_enable=rst_n&&active_source&&(state==SEEK||state==RUN);
    assign test_restart=!rst_n||state==RESET;
    assign switch_busy=state==RESET||state==DRAIN||requested_source!=active_source;
    assign waiting_for_sof=state==SEEK;
    wire take=ce&&out_valid;
    wire malformed=ce&&selected_valid&&
                   ((state==RUN&&!marker_ok)||(beginning&&!marker_ok));
    wire last=state==RUN&&take&&x==WIDTH-1&&y==HEIGHT-1;
    // The configured enabled bubbles empty the pixel/BRAM pipeline. Scans,
    // division, and median registers advance independently of ce.
    // Scanner busy can fall before the coherent result packet and median5
    // finish. Eight quiet clocks protect that physical-clock-only tail.
    wire drained=drain_timer>=DRAIN_CYCLES&&drain_steps>=MIN_DRAIN_STEPS&&algorithm_idle&&quiet_timer>=8;
    always @(posedge clk) begin
        if(!rst_n) begin
            state<=RESET;x<=0;y<=0;frame_timer<=0;drain_timer<=0;
            drain_steps<=0;reset_timer<=0;quiet_timer<=0;active_source<=0;
            switch_done<=0;switch_fault<=0;fault_sticky<=0;
            source_generation<=0;switch_count<=0;recovery_count<=0;
            discarded_camera_pixels<=0;
        end else begin
            switch_done<=0;switch_fault<=0;
            if(state==DRAIN&&drain_steps>=MIN_DRAIN_STEPS&&algorithm_idle) begin
                if(quiet_timer<8) quiet_timer<=quiet_timer+1'b1;
            end else quiet_timer<=0;
            if(ce&&cam_valid&&!(take&&!active_source))
                discarded_camera_pixels<=discarded_camera_pixels+1'b1;
            case(state)
                RESET: begin
                    x<=0;y<=0;frame_timer<=0;drain_timer<=0;drain_steps<=0;
                    if(reset_timer>=RESET_CYCLES-1) begin
                        state<=SEEK;reset_timer<=0;
                        active_source<=requested_source;
                        source_generation<=source_generation+1'b1;
                        if(active_source!=requested_source) switch_count<=switch_count+1'b1;
                        switch_done<=1;
                    end else reset_timer<=reset_timer+1'b1;
                end
                SEEK: begin
                    frame_timer<=0;
                    if(requested_source!=active_source) begin
                        state<=DRAIN;drain_timer<=0;drain_steps<=0;
                    end else if(malformed) begin
                        state<=DRAIN;drain_timer<=0;drain_steps<=0;
                        switch_fault<=1;fault_sticky<=1;recovery_count<=recovery_count+1'b1;
                    end else if(take) begin state<=RUN;x<=1;y<=0;end
                end
                RUN: begin
                    if(malformed||frame_timer>=FRAME_TIMEOUT_CYCLES-1) begin
                        state<=DRAIN;drain_timer<=0;drain_steps<=0;
                        switch_fault<=1;fault_sticky<=1;recovery_count<=recovery_count+1'b1;
                    end else begin
                        frame_timer<=frame_timer+1'b1;
                        if(take) begin
                            if(last) begin
                                state<=requested_source==active_source ? SEEK : DRAIN;
                                drain_timer<=0;drain_steps<=0;x<=0;y<=0;
                            end else if(x==WIDTH-1) begin x<=0;y<=y+1'b1;end
                            else x<=x+1'b1;
                        end
                    end
                end
                DRAIN: begin
                    if(drain_timer!=32'hffffffff) drain_timer<=drain_timer+1'b1;
                    if(ce&&drain_steps<MIN_DRAIN_STEPS) drain_steps<=drain_steps+1'b1;
                    if(drained) begin state<=RESET;reset_timer<=0;end
                    else if(drain_timer>=DRAIN_TIMEOUT_CYCLES-1) begin
                        state<=RESET;reset_timer<=0;switch_fault<=1;fault_sticky<=1;
                        recovery_count<=recovery_count+1'b1;
                    end
                end
                default: state<=RESET;
            endcase
        end
    end
    // Frame/timeout bounds are part of the native contract, not hardware input checks.
    // synthesis translate_off
    initial begin
        if(WIDTH<5||HEIGHT<5||WIDTH>65535||HEIGHT>65535||RESET_CYCLES<2||
           DRAIN_CYCLES<WIDTH+16||FRAME_TIMEOUT_CYCLES<WIDTH*HEIGHT+16||
           DRAIN_TIMEOUT_CYCLES<=DRAIN_CYCLES+RESET_CYCLES)
            $fatal(1,"Invalid video_source_switch parameters");
    end
    // synthesis translate_on
endmodule
