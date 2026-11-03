`timescale 1ns/1ps
module tb_800_sources;
 reg clk=0;always #5 clk=~clk;
 reg rn=0,ce=1,en=0,restart=1;reg [1:0] profile=0;
 wire v,sof,eol,finished,error;wire [23:0] rgb;wire [15:0] x,y;wire [31:0] frame_id,expected;wire [1:0] active_profile;
 conveyor_bist_source #(.WIDTH(800),.HEIGHT(480),.FRAME_GAP_CYCLES(16)) source(
  .clk(clk),.rst_n(rn),.ce(ce),.enable(en),.restart(restart),.cfg_profile(profile),.cfg_seed(32'h12345678),
  .out_valid(v),.out_sof(sof),.out_eol(eol),.out_rgb(rgb),.out_x(x),.out_y(y),.out_frame_id(frame_id),
  .active_profile(active_profile),.expected_total(expected),.frame_done(),.finished(finished),.configuration_error(error));
 reg static_en=0,static_restart=1;reg [1:0] scene=0;
 wire sv,ss,se;wire [23:0] srgb;wire [15:0] sx,sy;wire [1:0] out_scene;wire static_done;
 selftest_video_source #(.WIDTH(800),.HEIGHT(480),.ROM_WIDTH(200),.ROM_HEIGHT(120),.SCALE(4),.FRAME_GAP_CYCLES(32),
  .ROM_FILE("../../../fpga/data/scenes_200x120.hex")) rom_source(
  .clk(clk),.rst_n(rn),.ce(ce),.enable(static_en),.restart(static_restart),.cfg_scene_auto(1'b0),.cfg_scene(scene),
  .out_valid(sv),.out_sof(ss),.out_eol(se),.out_rgb(srgb),.out_scene(out_scene),.out_x(sx),.out_y(sy),.frame_done(static_done),.scene_change());
 integer cycles=0,pixels=0,frames=0,foreground=0,total_checks=0,static_checks=0,static_frames=0;
 integer bx,by;reg shape;reg [7:0] want;
 reg [25:0] held;reg stalled=0;
 always @(negedge clk)ce=cycles%257<251;
 always @(posedge clk)begin
  cycles++;
  if(rn)begin
   if(error)$fatal(1,"FAIL 800 SOURCE geometry rejected");
   if(ce && en && !restart && v)begin
    if(sof)begin
     if(pixels!=0 && pixels!=800*480)$fatal(1,"FAIL 800 SOURCE raster length");
     pixels=0;foreground=0;frames++;
    end
    if(eol!=(x==799) || x>=800 || y>=480 || frame_id!=frames)$fatal(1,"FAIL 800 SOURCE markers");
    if(frame_id==1 && profile!=1)begin
     bx=profile==3?95:470;
     shape=y>=160 && y<310 && ((x>=bx-30 && x<bx+35)||(profile!=2 && x>=bx+80 && x<bx+145));
     if(rgb!==(shape?24'hdcdcdc:24'h202020))$fatal(1,"FAIL 800 SOURCE scale/padding profile=%0d x=%0d y=%0d",profile,x,y);
    end
    if(frame_id>=41)begin
     want=profile==1?92-3*(frame_id-1-30):32;
     if(rgb!=={want,want,want})$fatal(1,"FAIL 800 SOURCE ending blank");
    end
    if(rgb[23:16]!=rgb[15:8] || rgb[15:8]!=rgb[7:0])$fatal(1,"FAIL 800 SOURCE color channels");
    pixels++;total_checks++;
   end
   if(ce && static_en && !static_restart && sv)begin
    bx=sx/4;by=sy/4;
    shape=by>=25 && by<95 && ((bx>=38 && bx<60)||(bx>=89 && bx<111)||(bx>=140 && bx<162));
    if(out_scene==1 && by>=57 && by<61 && bx>=60 && bx<140)shape=1;
    if(out_scene==2 && bx%7==2 && by%7==2)shape=1;
    if(out_scene==3 && by>=59 && by<67 && bx>=30 && bx<169)shape=0;
    want=shape?224:32;
    if(srgb!=={want,want,want} || se!=(sx==799) || ss!=(sx==0 && sy==0))$fatal(1,"FAIL 800 ROM scene=%0d x=%0d y=%0d",out_scene,sx,sy);
    static_checks++;
    if(se && sy==479)static_frames++;
   end
  end
 end
 initial begin
  repeat(5)@(negedge clk);rn=1;repeat(5)@(negedge clk);
  for(integer sc=0;sc<4;sc++)begin
   @(negedge clk);scene=sc;static_restart=0;static_en=1;
   wait(static_done);repeat(8)@(negedge clk);static_restart=1;static_en=0;repeat(10)@(negedge clk);
  end
  if(static_frames!=4 || static_checks!=4*800*480)$fatal(1,"FAIL 800 ROM frame conservation");
  for(integer pr=0;pr<4;pr++)begin
   @(negedge clk);profile=pr;restart=1;en=0;frames=0;pixels=0;repeat(5)@(negedge clk);
   restart=0;en=1;wait(finished);repeat(10)@(negedge clk);
   if(frames!=48 || pixels!=800*480 || expected!=(pr==2?1:pr==3?0:2))$fatal(1,"FAIL 800 SOURCE frames/oracle");
   restart=1;en=0;repeat(5)@(negedge clk);
  end
  $display("PASS 800 SOURCES BIST_profiles=4 RGB_pixels=%0d ROM_scenes=4 ROM_pixels=%0d scale=5 horizontal_padding=160",total_checks,static_checks);$finish;
 end
 initial begin repeat(90000000)@(posedge clk);$fatal(1,"FAIL 800 SOURCE watchdog");end
endmodule
