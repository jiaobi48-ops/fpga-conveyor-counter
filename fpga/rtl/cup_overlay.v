`timescale 1ns/1ps
module cup_overlay(
    input wire [15:0] ax0,bx0,gate_width,y0,y1,
    input wire [10:0] x,
    input wire [9:0] y,
    input wire [23:0] video_rgb,count_bcd,
    input wire gate_a,gate_b,enabled,show_mask,dark_pixel,warm_pixel,blocked,
    input wire [1:0] phase,
    input wire saturated,manual_mode,follow_active,follow_hold,
    output reg [23:0] rgb
);
    // 5 columns x 7 rows, one byte per row (low five bits).
    function [34:0] glyph;
        input [7:0] c;
        begin
            case(c)
            "F":glyph={5'b11111,5'b10000,5'b10000,5'b11110,5'b10000,5'b10000,5'b10000};
            "W":glyph={5'b10001,5'b10001,5'b10001,5'b10101,5'b10101,5'b11011,5'b10001};
            "A":glyph={5'b01110,5'b10001,5'b10001,5'b11111,5'b10001,5'b10001,5'b10001};
            "M":glyph={5'b10001,5'b11011,5'b10101,5'b10101,5'b10001,5'b10001,5'b10001};
            "U":glyph={5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01110};
            "L":glyph={5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b11111};
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
            "C":glyph={5'b01111,5'b10000,5'b10000,5'b10000,5'b10000,5'b10000,5'b01111};
            "O":glyph={5'b01110,5'b10001,5'b10001,5'b10001,5'b10001,5'b10001,5'b01110};
            "N":glyph={5'b10001,5'b11001,5'b10101,5'b10011,5'b10001,5'b10001,5'b10001};
            "T":glyph={5'b11111,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100,5'b00100};
            default:glyph=0;
            endcase
        end
    endfunction
    integer cell_index,col,row;
    reg [7:0] ch;
    reg [34:0] bits;
    reg ink;
    always @* begin
        rgb=video_rgb;cell_index=0;col=0;row=0;ch=" ";bits=0;ink=0;
        if(show_mask && x>=80 && x<720 && y>=y0 && y<y1)
            rgb=warm_pixel?24'hFF0000:dark_pixel?24'hFFFF00:24'h202020;
        // Gate outlines are outside the sampled 4x32 cup-body interiors.
        if(((x==ax0-2 || x==ax0+gate_width+1) && y>=y0-2 && y<=y1+1) ||
           ((y==y0-2 || y==y1+1) && x>=ax0-2 && x<=ax0+gate_width+1))rgb=gate_a?24'hFF6000:24'hFFFF00;
        if(((x==bx0-2 || x==bx0+gate_width+1) && y>=y0-2 && y<=y1+1) ||
           ((y==y0-2 || y==y1+1) && x>=bx0-2 && x<=bx0+gate_width+1))rgb=gate_b?24'hFF6000:24'h00FFFF;
        if(show_mask && (((x==320 || x==479) && y>=8 && y<48) ||
           ((y==8 || y==47) && x>=320 && x<480)))rgb=24'hFF00FF;
        // Left arrow, above the detector, drawn without altering detector pixels.
        if((y==60 && x>=376 && x<=424) ||
           (x>=376 && x<=383 && (y==60-(x-376) || y==60+(x-376))))rgb=24'h00FF00;
        if(x>=12 && x<324 && y>=12 && y<52)begin
            rgb=24'h000000;
            if(x>=20 && x<308 && y>=18 && y<46)begin
                cell_index=(x-20)/24;col=((x-20)%24)/4;row=(y-18)/4;
                case(cell_index)
                0:ch="C";1:ch="O";2:ch="U";3:ch="N";4:ch="T";
                6:ch="0"+{4'b0000,count_bcd[23:20]};
                7:ch="0"+{4'b0000,count_bcd[19:16]};
                8:ch="0"+{4'b0000,count_bcd[15:12]};
                9:ch="0"+{4'b0000,count_bcd[11:8]};
                10:ch="0"+{4'b0000,count_bcd[7:4]};
                11:ch="0"+{4'b0000,count_bcd[3:0]};
                default:ch=" ";
                endcase
                bits=glyph(ch);
                if(col<5 && row<7)ink=bits[(6-row)*5+(4-col)];
                if(ink)rgb=saturated?24'hFF0000:24'hFFFFFF;
            end
        end
        // Explicit mode label; this does not feed back into raw detector pixels.
        if(x>=360 && x<432 && y>=18 && y<34)begin
            rgb=24'h000000;cell_index=(x-360)/12;col=((x-360)%12)/2;row=(y-18)/2;
            if(manual_mode)case(cell_index)
                0:ch="M";1:ch="A";2:ch="N";3:ch="U";4:ch="A";5:ch="L";default:ch=" ";
            endcase
            else case(cell_index)
                0:ch="A";1:ch="U";2:ch="T";3:ch="O";default:ch=" ";
            endcase
            bits=glyph(ch);
            if(col<5 && row<7 && bits[(6-row)*5+(4-col)])rgb=manual_mode?24'h80DFFF:24'hFFFFFF;
        end
        if(follow_active && x>=448 && x<520 && y>=18 && y<34)begin
            rgb=0;cell_index=(x-448)/12;col=((x-448)%12)/2;row=(y-18)/2;
            case(cell_index)0:ch="F";1:ch="O";2:ch="L";3:ch="L";4:ch="O";5:ch="W";default:ch=" ";endcase
            bits=glyph(ch);
            if(col<5 && row<7 && bits[(6-row)*5+(4-col)])rgb=follow_hold?24'hff6000:24'h00ffff;
        end
        // State square: disabled=grey, waiting/hold=amber, ready=green, armed=cyan.
        if(x>=332 && x<348 && y>=20 && y<36)
            rgb=!enabled?24'h808080:blocked?24'hFF0000:phase==1?24'h00FF00:phase==2?24'h00FFFF:24'hFFB000;
    end
endmodule
