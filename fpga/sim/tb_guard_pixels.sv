`timescale 1ns/1ps
module tb_guard_pixels;
    reg clk=0;always #5 clk=~clk;
    reg rst_n=0,ce=1,in_valid=0,in_sof=0,in_eol=0;reg [23:0] in_rgb=0;
    reg [31:0] in_source_id=0,in_source_generation=7,in_timestamp=0,cfg_epoch=9;
    reg cfg_guard_enable=1,cfg_v3_model=0,cfg_invert=0;reg [7:0] cfg_threshold=128;
    reg [15:0] cfg_roi_x0=0,cfg_roi_y0=0,cfg_roi_x1=32,cfg_roi_y1=16,cfg_guard_x0=4,cfg_guard_y0=0,cfg_guard_x1=20,cfg_guard_y1=2;
    wire update,integrity_fault,frame_good,geometry_good,guard_enabled;
    wire [31:0] frame_id,source_id,source_generation,timestamp,epoch,roi_pixels,foreground_pixels,guard_pixels,guard_dark,guard_warm,rejected_frames,roi_gray_sum;
    scene_guard_statistics #(.WIDTH(32),.HEIGHT(16)) dut(.*);
    reg [23:0] pixels[0:6143];reg [31:0] expected[0:107],config_words[0:95];
    integer f,x,y,checks=0,reports=0,pauses=0,bubbles=0;
    always @(posedge clk)begin
        #1;if(update)begin
            if(frame_id!=reports+1||source_id!=100+reports||source_generation!=7||timestamp!=1000+reports||epoch!=9)
                $fatal(1,"FAIL GUARD PIXELS metadata");
            if(geometry_good!==1'(expected[9*reports])||frame_good!==1'(expected[9*reports+1])||
                roi_pixels!=expected[9*reports+2]||foreground_pixels!=expected[9*reports+3]||guard_pixels!=expected[9*reports+4]||
                guard_dark!=expected[9*reports+5]||guard_warm!=expected[9*reports+6]||roi_gray_sum!=expected[9*reports+8])
                $fatal(1,"FAIL GUARD PIXELS frame%0d oracle ROI%0d FG%0d G%0d D%0d W%0d",frame_id,roi_pixels,foreground_pixels,guard_pixels,guard_dark,guard_warm);
            reports++;checks+=12;
        end
    end
    initial begin
        $readmemh("../../fixtures/guard/random_rgb.hex",pixels);$readmemh("../../fixtures/guard/random_expected.hex",expected);$readmemh("../../fixtures/guard/random_config.hex",config_words);
        repeat(4)@(negedge clk);rst_n=1;
        for(f=0;f<12;f++)begin
            cfg_v3_model=1'(config_words[8*f]);cfg_invert=1'(config_words[8*f+1]);cfg_threshold=8'(config_words[8*f+2]);
            cfg_roi_x0=16'(config_words[8*f+3]);cfg_roi_y0=16'(config_words[8*f+4]);cfg_roi_x1=16'(config_words[8*f+5]);cfg_roi_y1=16'(config_words[8*f+6]);cfg_guard_enable=1'(config_words[8*f+7]);
            in_source_id=100+f;in_timestamp=1000+f;
            for(y=0;y<16;y++)for(x=0;x<32;x++)begin
                if((y*32+x)%29==7)begin @(negedge clk);in_valid=0;bubbles++;end
                @(negedge clk);in_valid=1;in_sof=x==0&&y==0;in_eol=x==31;
                if(f==8&&x==7&&y==3)in_eol=1;
                in_rgb=pixels[f*512+y*32+x];
                if((y*32+x)%17==5)begin ce=0;repeat(2)begin @(negedge clk);pauses++;end ce=1;end
                if(x==20&&y==10)begin cfg_threshold=200;cfg_roi_y0=9;end
            end
            @(negedge clk);in_valid=0;in_sof=0;in_eol=0;repeat(3)@(negedge clk);
        end
        if(reports!=12||rejected_frames!=1)$fatal(1,"FAIL GUARD PIXELS conservation");
        $display("PASS GUARD PIXELS frames=%0d checks=%0d NumPy-oracle/2models/polarity/invalidROI/badEOL/SOF-config/CE=%0d bubbles=%0d",reports,checks,pauses,bubbles);$finish;
    end
    initial begin #2000000;$fatal(1,"FAIL GUARD PIXELS watchdog");end
endmodule
