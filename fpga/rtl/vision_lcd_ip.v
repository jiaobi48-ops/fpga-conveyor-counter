module vision_lcd_ip #(
 parameter integer WIDTH=800,HEIGHT=480
)(
 (* X_INTERFACE_INFO="xilinx.com:signal:clock:1.0 pixel_clk CLK" *)
 (* X_INTERFACE_PARAMETER="XIL_INTERFACENAME pixel_clk, FREQ_HZ 25000000" *) input wire pixel_clk,
 input wire reset_n,video_locked,input wire [23:0] video_rgb,input wire video_de,video_vsync,
 input wire [1023:0] display_packet,input wire [15:0] projection_value,
 output wire [9:0] projection_address,output wire display_tick,
 output wire [23:0] lcd_rgb,output wire lcd_de,
 output wire lcd_hs,lcd_vs,lcd_bl,lcd_clk,lcd_rst,ms7200_rst_n
);
vision_lcd_bridge #(
 .WIDTH(WIDTH),
 .HEIGHT(HEIGHT)
) impl (
 .pixel_clk(pixel_clk),
 .reset_n(reset_n),
 .video_locked(video_locked),
 .video_rgb(video_rgb),
 .video_de(video_de),
 .video_vsync(video_vsync),
 .display_packet(display_packet),
 .projection_value(projection_value),
 .projection_address(projection_address),
 .display_tick(display_tick),
 .lcd_rgb(lcd_rgb),
 .lcd_de(lcd_de),
 .lcd_hs(lcd_hs),
 .lcd_vs(lcd_vs),
 .lcd_bl(lcd_bl),
 .lcd_clk(lcd_clk),
 .lcd_rst(lcd_rst),
 .ms7200_rst_n(ms7200_rst_n)
);
endmodule
