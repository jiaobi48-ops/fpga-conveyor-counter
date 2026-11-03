`timescale 1ns/1ps
module vision_lcd_bridge #(
 parameter integer WIDTH=800,HEIGHT=480
)(
 (* X_INTERFACE_INFO="xilinx.com:signal:clock:1.0 pixel_clk CLK" *)
 (* X_INTERFACE_PARAMETER="XIL_INTERFACENAME pixel_clk, FREQ_HZ 25000000" *) input wire pixel_clk,
 input wire reset_n,video_locked,input wire [23:0] video_rgb,input wire video_de,video_vsync,
 input wire [1023:0] display_packet,input wire [15:0] projection_value,
 output wire [9:0] projection_address,output wire display_tick,
 output reg [23:0] lcd_rgb,output reg lcd_de,
 output wire lcd_hs,lcd_vs,lcd_bl,lcd_clk,lcd_rst,ms7200_rst_n
);
 (* ASYNC_REG="TRUE" *) reg [1:0] rn;
 reg de_d,vs_d;reg [10:0] x;reg [9:0] y;
 assign display_tick=video_vsync && !vs_d;
 assign projection_address=x<WIDTH-1?x+1'b1:0;
 wire [31:0] total=display_packet[0+:32],stable=display_packet[32+:32],thresholds=display_packet[64+:32];
 wire [31:0] flags=display_packet[96+:32],reason_count=display_packet[128+:32];
 wire [31:0] dx=display_packet[160+:32],dt=display_packet[192+:32],lanes=display_packet[224+:32];
 wire [15:0] line_a=display_packet[256+:16],line_b=display_packet[288+:16];
 wire [15:0] roi_y0=display_packet[320+:16],roi_y1=display_packet[352+:16];
 wire mask=display_packet[384];
 reg [23:0] rgb;
 reg [2:0] col,field;
 reg [3:0] row,cell_index;
 reg [6:0] off;
 reg [5:0] shift;
 reg [7:0] ch;reg [34:0] glyph_bits;reg [31:0] number;
 reg [63:0] field_label;
 wire [39:0] total_bcd=display_packet[22*32+:40];
 wire [7:0] red=video_rgb[23:16],green=video_rgb[15:8],blue=video_rgb[7:0];
 wire [15:0] gray_sum=red*16'd77+green*16'd150+blue*16'd29+16'd128;
 wire foreground=(gray_sum[15:8]>=thresholds[15:8]) ^ display_packet[16*32];
 function [34:0] glyph;
  input [7:0] c;
  begin
   case(c)
    "0":glyph={5'b01110,5'b10001,5'b10011,5'b10101,5'b11001,5'b10001,5'b01110};
    "1":glyph={5'b00100,5'b01100,5'b00100,5'b00100,5'b00100,5'b00100,5'b01110};
    "2":glyph={5'b01110,5'b10001,5'b00001,5'b00010,5'b00100,5'b01000,5'b11111};
    "3":glyph={5'b11110,5'b00001,5'b00001,5'b01110,5'b00001,5'b00001,5'b11110};
    "4":glyph={5'b00010,5'b00110,5'b01010,5'b10010,5'b11111,5'b00010,5'b00010};
    "5":glyph={5'b11111,5'b10000,5'b10000,5'b11110,5'b00001,5'b00001,5'b11110};
    "6":glyph={5'b01110,5'b10000,5'b10000,5'b11110,5'b10001,5'b10001,5'b01110};
    "7":glyph={5'b11111,5'b00001,5'b00010,5'b00100,5'b01000,5'b01000,5'b01000};
    "8":glyph={5'b01110,5'b10001,5'b10001,5'b01110,5'b10001,5'b10001,5'b01110};
    "9":glyph={5'b01110,5'b10001,5'b10001,5'b01111,5'b00001,5'b00001,5'b01110};
    "A":glyph={5'b01110,5'b10001,5'b10001,5'b11111,5'b10001,5'b10001,5'b10001};
    "B":glyph={5'b11110,5'b10001,5'b10001,5'b11110,5'b10001,5'b10001,5'b11110};
    "C":glyph={5'b01111,5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b01111};
    "D":glyph={5'b11110,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b11110};
    "E":glyph={5'b11111,5'b10000,5'b10000,5'b11110,5'b10000,5'b10000,5'b11111};
    "F":glyph={5'b11111,5'b10000,5'b10000,5'b11110,5'b10000,5'b10000,5'b10000};
    "T":glyph={5'b11111,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100};
    "L":glyph={5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b11111};
    "S":glyph={5'b01111,5'b10000,5'b10000,5'b01110,5'b00001,5'b00001,5'b11110};
    "P":glyph={5'b11110,5'b10001,5'b10001,5'b11110,5'b10000,5'b10000,5'b10000};
    "N":glyph={5'b10001,5'b11001,5'b10101,5'b10011,5'b10001,5'b10001,5'b10001};
    "O":glyph={5'b01110,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01110};
    "U":glyph={5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01110};
    "I":glyph={5'b01110,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100,5'b01110};
    "X":glyph={5'b10001,5'b10001,5'b01010,5'b00100,5'b01010,5'b10001,5'b10001};
    default:glyph=0;
   endcase
  end
 endfunction
 always @(posedge pixel_clk or negedge reset_n)begin
  if(!reset_n)rn<=0;else rn<={rn[0],1'b1};
 end
 always @(posedge pixel_clk)begin
  if(!rn[1] || !video_locked)begin x<=0;y<=0;de_d<=0;vs_d<=video_vsync;end
  else begin
   de_d<=video_de;vs_d<=video_vsync;
   if(display_tick)begin x<=0;y<=0;end
   else begin
    if(video_de)x<=x+1'b1;
    if(de_d && !video_de)begin x<=0;y<=y+1'b1;end
   end
  end
 end
 wire [15:0] proj_height=projection_value>>2;
 wire [9:0] plot_y=proj_height>64?10'd402:10'd466-proj_height[9:0];
 always @* begin
  rgb=video_rgb;col=0;row=0;cell_index=0;field=0;off=0;shift=0;ch=" ";glyph_bits=0;number=0;field_label=0;
  if(mask)rgb=foreground?24'hffffff:24'h202020;
  if((x==line_a || x==line_b) && y>=roi_y0 && y<roi_y1)rgb=x==line_a?24'hffe030:24'h00dfff;
  for(integer c=0;c<8;c=c+1)
   if(c<display_packet[17*32+:4] && x==display_packet[18*32+c*16+:16] && y>=roi_y0 && y<roi_y1)rgb=24'h20ff40;
  if(y>=400 && y<472)begin
   rgb={video_rgb[23:18],2'b00,video_rgb[15:10],2'b00,video_rgb[7:2],2'b00};
   if(y==plot_y)rgb=24'hff3030;
  end
  // Hexadecimal fields avoid a wide combinational binary/decimal divider.
  if(y>=8 && y<40 && x>=8 && x<792)begin
   rgb=24'h102030;
   if(x<136)begin field=0;off=x-8;end
   else if(x<244)begin field=1;off=x-136;end
   else if(x<352)begin field=2;off=x-244;end
   else if(x<460)begin field=3;off=x-352;end
   else if(x<568)begin field=4;off=x-460;end
   else if(x<676)begin field=5;off=x-568;end
   else begin field=6;off=x-676;end
   cell_index=off/12;col=(off%12)/2;row=(y-10)/2;
   case(field)
    0:number=total;
    1:number={16'd0,reason_count[15:0]};
    2:number={6'd0,thresholds[25:0]};
    3:number={16'd0,stable[15:0]};
    4:number=lanes;
    5:number=dx;
    default:number=dt;
   endcase
   if((field==0 && cell_index<10) || (field>0 && cell_index<8))begin
    if(field==0)begin shift=(9-cell_index)*4;ch="0"+((total_bcd>>shift)&15);end
    else begin shift=(7-cell_index)*4;ch=(number>>shift)&15;ch=ch<10?"0"+ch:"A"+ch-10;end
    glyph_bits=glyph(ch);
    if(y>=10 && y<24 && col<5 && row<7 && glyph_bits[(6-row)*5+(4-col)])rgb=field==0?24'h00ff80:24'hffffff;
   end
   case(field)
    0:field_label="COUNT   ";1:field_label="STATIC  ";2:field_label="T       ";
    3:field_label="STABLE  ";4:field_label="LANES   ";5:field_label="DX      ";default:field_label="DT      ";
   endcase
   if(y>=26 && y<40 && cell_index<8)begin
    ch=field_label[(7-cell_index)*8+:8];row=(y-26)/2;glyph_bits=glyph(ch);
    if(col<5 && row<7 && glyph_bits[(6-row)*5+(4-col)])rgb=24'h80a0c0;
   end
  end
  if(x>=8 && x<24 && y>=48 && y<64)
   rgb=!flags[0]?24'h808080:flags[1] || flags[8]?24'hff2020:flags[4:2]==5 || flags[5]?24'h00ff80:24'hffa000;
  if(x>=32 && x<48 && y>=48 && y<64)rgb=flags[5]?24'h0080ff:24'h202020;
  if(x>=56 && x<72 && y>=48 && y<64)rgb=flags[10]?(flags[11]?24'h00ff80:24'hff2020):flags[9]?24'hffa000:24'h202020;
 end
 always @(posedge pixel_clk)begin
  if(!rn[1] || !video_locked)begin lcd_rgb<=0;lcd_de<=0;end
  else begin lcd_rgb<=video_de?rgb:0;lcd_de<=video_de;end
 end
 assign lcd_hs=1'b1,lcd_vs=1'b1,lcd_bl=rn[1] && video_locked,lcd_rst=1'b1,ms7200_rst_n=1'b0;
 ODDR #(.DDR_CLK_EDGE("SAME_EDGE"),.INIT(1'b0),.SRTYPE("SYNC"))
  u_forward_clock(.C(pixel_clk),.CE(1'b1),.D1(1'b0),.D2(1'b1),.Q(lcd_clk),.R(1'b0),.S(1'b0));
endmodule
