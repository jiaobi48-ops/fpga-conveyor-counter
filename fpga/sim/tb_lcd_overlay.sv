`timescale 1ns/1ps
module tb_lcd_overlay;
 reg pixel_clk=0;always #20 pixel_clk=~pixel_clk;
 reg reset_n=0,video_locked=1,video_de=1,video_vsync=0;
 reg [23:0] video_rgb=24'h204060;reg [1023:0] display_packet=0;
 reg [15:0] projection_value=0;wire [9:0] projection_address;wire display_tick;
 wire [23:0] lcd_rgb;wire lcd_de,lcd_hs,lcd_vs,lcd_bl,lcd_clk,lcd_rst,ms7200_rst_n;
 vision_lcd_bridge dut(.*);
 reg [10:0] tx=0;reg [9:0] ty=0;integer checks=0;
 task pixel(input [10:0] px,input [9:0] py,input [23:0] expected);
  @(negedge pixel_clk);tx=px;ty=py;
  @(posedge pixel_clk);#1;
  if(lcd_rgb!==expected || lcd_de!==1)$fatal(1,"FAIL LCD x=%0d y=%0d want=%h got=%h",px,py,expected,lcd_rgb);
  checks++;
 endtask
 initial begin
  force dut.x=tx;force dut.y=ty;
  repeat(3)@(negedge pixel_clk);reset_n=1;repeat(4)@(negedge pixel_clk);
  pixel(100,100,24'h204060);
  display_packet[64+8+:8]=128;display_packet[384]=1;display_packet[16*32]=1;
  pixel(100,100,24'hffffff);video_rgb=24'hc8c8c8;pixel(100,100,24'h202020);
  display_packet[384]=0;video_rgb=24'h204060;
  display_packet[256+:16]=410;display_packet[288+:16]=220;
  display_packet[320+:16]=2;display_packet[352+:16]=478;
  pixel(410,100,24'hffe030);pixel(220,100,24'h00dfff);
  display_packet[17*32+:4]=1;display_packet[18*32+:16]=350;
  pixel(350,100,24'h20ff40);
  projection_value=80;pixel(100,446,24'hff3030);
  if(projection_address!=101)$fatal(1,"FAIL LCD projection lookahead");
  display_packet[96+:32]=3;pixel(10,52,24'hff2020);
  display_packet[96+:32]=1|(5<<2);pixel(10,52,24'h00ff80);
  display_packet[96+5]=1;pixel(36,52,24'h0080ff);
  display_packet[96+10]=1;display_packet[96+11]=1;pixel(60,52,24'h00ff80);
  display_packet[22*32+:40]=40'h1234567890;
  pixel(8,10,24'h102030);pixel(12,10,24'h00ff80);pixel(22,10,24'h00ff80);pixel(118,10,24'h00ff80);
  @(negedge pixel_clk);video_de=0;@(posedge pixel_clk);#1;
  if(lcd_de!==0 || lcd_rgb!==0)$fatal(1,"FAIL LCD blanking");
  $display("PASS LCD checks=%0d decimal10/mask/polarity/gates/cuts/projection/status/BIST/blanking",checks);$finish;
 end
 initial begin #100000;$fatal(1,"FAIL LCD watchdog");end
endmodule
