`timescale 1ns/1ps
module tb_guard_identity;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,ce=1,enable=1,in_valid=0,in_sof=0,in_eol=0;
    reg [23:0] in_rgb=24'h123456;
    reg [31:0] in_frame_id=0,in_generation=1,in_timestamp=0;
    wire out_valid,out_sof,out_eol,discontinuity;wire [23:0] out_rgb;
    wire [31:0] out_frame_id,out_generation,out_timestamp,duplicate_frames,stale_frames,accepted_frames;
    camera_frame_identity dut(.*);
    integer checks=0;
    task send(input logic [31:0] id,input bit accept);
        @(negedge clk);in_frame_id=id;in_timestamp+=100;in_valid=1;in_sof=1;in_eol=0;ce=0;
        repeat(3)@(negedge clk);
        if(accepted_frames+duplicate_frames+stale_frames!=checks)$fatal(1,"FAIL GUARD ID CE consumed marker");
        ce=1;#1;if(out_valid!==accept||out_frame_id!==id)$fatal(1,"FAIL GUARD ID admission");
        @(negedge clk);in_sof=0;in_frame_id=999;in_generation=999;in_timestamp=999;
        for(integer p=0;p<4;p++)begin
            #1;if(out_valid!==accept||out_sof||out_rgb!==24'h123456)$fatal(1,"FAIL GUARD ID whole-frame filter");
            if(accept&&out_frame_id!==id)$fatal(1,"FAIL GUARD ID metadata not SOF held");
            in_eol=p==3;@(negedge clk);
        end
        in_valid=0;in_eol=0;in_generation=1;checks++;
    endtask
    initial begin
        repeat(3)@(negedge clk);rst_n=1;
        send(10,1);send(10,0);send(9,0);send(11,1);send(14,1);
        in_generation=2;send(0,1);in_generation=2;send(1,1);
        in_generation=3;send(32'hfffffffe,1);in_generation=3;send(32'hffffffff,1);in_generation=3;send(0,1);
        enable=0;send(0,1);
        if(duplicate_frames!=1||stale_frames!=1||accepted_frames!=9)$fatal(1,"FAIL GUARD ID totals");
        $display("PASS GUARD ID frames=%0d accepted=%0d duplicate=%0d stale=%0d CE/metadata/wrap/bypass",checks,accepted_frames,duplicate_frames,stale_frames);$finish;
    end
    initial begin #1000000;$fatal(1,"FAIL GUARD ID watchdog");end
endmodule
