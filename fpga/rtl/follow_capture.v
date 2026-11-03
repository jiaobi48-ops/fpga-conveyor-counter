`timescale 1ns/1ps
// Passive AXIS observer in the AXI clock domain. Never drives ready or pixels.
// An armed next COMPLETE source frame owns the frozen thumbnail until re-arm.
module follow_capture #(
 parameter integer WIDTH=1280,HEIGHT=720,STEP=8,LEASE_CYCLES=75000000,
 parameter integer COLS=WIDTH/STEP,ROWS=HEIGHT/STEP,WORDS=COLS*ROWS/3
)(
 input wire clk,reset_n,
 input wire [23:0] stream_rgb,
 input wire stream_valid,stream_ready,stream_sof,stream_eol,
 input wire [31:0] request,
 output reg [31:0] response,
 output wire follow_active,
 output reg follow_hold
);
 (* ram_style="block" *) reg [23:0] memory[0:WORDS-1];
 reg seen,waiting,capturing,ready,bad,enabled,line_bad;
 reg [31:0] lease,source_age;
 reg [23:0] source_id,frozen_id,granted_id,errors;
 reg [15:0] x,y,samples,word_index;
 reg [19:0] pixels;
 reg [1:0] pack_index;
 reg [15:0] sample_pack;
 reg read_pending,read_token;
 reg [23:0] read_value;
 wire accepted=stream_valid && stream_ready;
 wire [15:0] px=stream_sof?16'd0:x,py=stream_sof?16'd0:y;
 wire [9:0] sum={2'b0,stream_rgb[23:16]}+{1'b0,stream_rgb[15:8],1'b0}+{2'b0,stream_rgb[7:0]};
 wire [7:0] gray=sum[9:2];
 wire [6:0] op=request[30:24];wire [23:0] data=request[23:0];
 assign follow_active=enabled;

 always @(posedge clk)begin
  if(!reset_n)begin
   follow_hold<=0;seen<=0;response<=0;waiting<=0;capturing<=0;ready<=0;bad<=0;enabled<=0;
   lease<=0;source_age<=LEASE_CYCLES;source_id<=0;frozen_id<=0;granted_id<=0;errors<=0;
   x<=0;y<=0;samples<=0;word_index<=0;pixels<=0;line_bad<=0;
   pack_index<=0;sample_pack<=0;read_pending<=0;read_token<=0;read_value<=0;
  end else begin
   follow_hold<=enabled && (lease<=1 || source_age>=LEASE_CYCLES-1);
   if(source_age<32'hffffffff)source_age<=source_age+1'b1;
   if(lease!=0)lease<=lease-1'b1;
   if(read_pending)begin response<={read_token,7'd3,read_value};read_pending<=0;end
   else if(request[31]!=seen)begin
    seen<=request[31];response<={request[31],1'b0,op[5:0],24'd0};
    case(op)
     0:response<={request[31],7'd0,24'hF10401};
     1:if(capturing||waiting)response<={request[31],1'b1,6'd1,24'd1};
       else begin waiting<=1;ready<=0;bad<=0;end
     2:response<={request[31],7'd2,21'd0,(capturing||waiting),bad,ready};
     3:if(!ready||bad||data>=WORDS)response<={request[31],1'b1,6'd3,24'd2};
       else begin read_value<=memory[data];read_pending<=1;read_token<=request[31];response<=response;end
     4:response<={request[31],7'd4,frozen_id};
     5:response<={request[31],7'd5,source_id};
     6:begin enabled<=data[0];follow_hold<=data[0];lease<=0;end
     7:if(data==0)begin lease<=0;follow_hold<=enabled;end
       else if(ready&&!bad&&frozen_id!=granted_id)begin
        if(source_age<LEASE_CYCLES)begin lease<=LEASE_CYCLES;follow_hold<=0;granted_id<=frozen_id;end
        else begin lease<=0;follow_hold<=enabled;end
       end
       else response<={request[31],1'b1,6'd7,24'd3};
     8:response<={request[31],7'd8,errors};
     default:response<={request[31],1'b1,op[5:0],24'd4};
    endcase
   end
   if(accepted)begin
    if(stream_sof)begin
     source_age<=0;source_id<=source_id+1'b1;x<=1;y<=0;
     if(capturing)begin capturing<=0;ready<=1;bad<=1;errors<=errors+1'b1;end
     if(waiting)begin
      waiting<=0;capturing<=1;ready<=0;bad<=0;frozen_id<=source_id+1'b1;
      samples<=0;word_index<=0;pack_index<=0;sample_pack<=0;pixels<=1;line_bad<=stream_eol;
     end
    end else begin
     if(stream_eol)begin x<=0;y<=y+1'b1;end else x<=x+1'b1;
     if(capturing)begin
      pixels<=pixels+1'b1;
      if(px>=WIDTH||py>=HEIGHT||(stream_eol!=(px==WIDTH-1)))line_bad<=1;
      if(px%STEP==STEP/2 && py%STEP==STEP/2 && px<WIDTH && py<HEIGHT)begin
       samples<=samples+1'b1;
       if(pack_index==2)begin
        if(word_index<WORDS)memory[word_index]<={gray,sample_pack};
        word_index<=word_index+1'b1;pack_index<=0;
       end else begin
        if(pack_index==0)sample_pack[7:0]<=gray;else sample_pack[15:8]<=gray;
        pack_index<=pack_index+1'b1;
       end
      end
      if(stream_eol && py==HEIGHT-1)begin
       capturing<=0;ready<=1;
       bad<=line_bad || px!=WIDTH-1 || pixels!=WIDTH*HEIGHT-1 || samples!=COLS*ROWS;
       if(line_bad || px!=WIDTH-1 || pixels!=WIDTH*HEIGHT-1 || samples!=COLS*ROWS)errors<=errors+1'b1;
      end
     end
    end
   end
  end
 end
endmodule

