# OOC mapping margin: 12ns mapping budget; implemented algorithm clock is 75MHz; LCD remains 40ns.
create_clock -name clk_fpga_0 -period 12.000 [get_ports clk]
create_clock -name lcd_pixel_ooc -period 40.000 [get_ports display_clk]
