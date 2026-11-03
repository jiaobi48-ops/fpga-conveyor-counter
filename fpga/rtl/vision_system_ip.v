module vision_system_ip #(
 parameter integer WIDTH=800,HEIGHT=480,SOURCE_WIDTH=1280,SOURCE_HEIGHT=720,
 parameter integer CROP_X=240,CROP_Y=120,FRAME_GAP=2116000,
 parameter ROM_FILE="scenes_200x120.hex"
)(
 (* X_INTERFACE_INFO="xilinx.com:signal:clock:1.0 clk CLK" *)
 (* X_INTERFACE_PARAMETER="XIL_INTERFACENAME clk, ASSOCIATED_BUSIF S_AXIS:M_AXIS, ASSOCIATED_RESET reset_n, FREQ_HZ 75000000" *) input wire clk,
 (* X_INTERFACE_INFO="xilinx.com:signal:reset:1.0 reset_n RST" *)
 (* X_INTERFACE_PARAMETER="XIL_INTERFACENAME reset_n, POLARITY ACTIVE_LOW" *) input wire reset_n,
 (* X_INTERFACE_INFO="xilinx.com:interface:axis:1.0 S_AXIS TDATA" *) input wire [23:0] s_axis_tdata,
 (* X_INTERFACE_INFO="xilinx.com:interface:axis:1.0 S_AXIS TVALID" *) input wire s_axis_tvalid,
 (* X_INTERFACE_INFO="xilinx.com:interface:axis:1.0 S_AXIS TREADY" *) output wire s_axis_tready,
 (* X_INTERFACE_INFO="xilinx.com:interface:axis:1.0 S_AXIS TUSER" *) input wire s_axis_tuser,
 (* X_INTERFACE_INFO="xilinx.com:interface:axis:1.0 S_AXIS TLAST" *) input wire s_axis_tlast,
 (* X_INTERFACE_INFO="xilinx.com:interface:axis:1.0 M_AXIS TDATA" *) output wire [23:0] m_axis_tdata,
 (* X_INTERFACE_INFO="xilinx.com:interface:axis:1.0 M_AXIS TVALID" *) output wire m_axis_tvalid,
 (* X_INTERFACE_INFO="xilinx.com:interface:axis:1.0 M_AXIS TREADY" *) input wire m_axis_tready,
 (* X_INTERFACE_INFO="xilinx.com:interface:axis:1.0 M_AXIS TUSER" *) output wire m_axis_tuser,
 (* X_INTERFACE_INFO="xilinx.com:interface:axis:1.0 M_AXIS TLAST" *) output wire m_axis_tlast,
 input wire [31:0] request,output wire [31:0] response,
 input wire display_clk,display_tick,
 output wire [1023:0] display_packet,
 input wire [9:0] projection_address,output wire [15:0] projection_value
);
vision_system_bridge #(
 .WIDTH(WIDTH),
 .HEIGHT(HEIGHT),
 .SOURCE_WIDTH(SOURCE_WIDTH),
 .SOURCE_HEIGHT(SOURCE_HEIGHT),
 .CROP_X(CROP_X),
 .CROP_Y(CROP_Y),
 .FRAME_GAP(FRAME_GAP),
 .ROM_FILE(ROM_FILE)
) impl (
 .clk(clk),
 .reset_n(reset_n),
 .s_axis_tdata(s_axis_tdata),
 .s_axis_tvalid(s_axis_tvalid),
 .s_axis_tready(s_axis_tready),
 .s_axis_tuser(s_axis_tuser),
 .s_axis_tlast(s_axis_tlast),
 .m_axis_tdata(m_axis_tdata),
 .m_axis_tvalid(m_axis_tvalid),
 .m_axis_tready(m_axis_tready),
 .m_axis_tuser(m_axis_tuser),
 .m_axis_tlast(m_axis_tlast),
 .request(request),
 .response(response),
 .display_clk(display_clk),
 .display_tick(display_tick),
 .display_packet(display_packet),
 .projection_address(projection_address),
 .projection_value(projection_value)
);
endmodule
