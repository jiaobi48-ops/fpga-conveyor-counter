# ATK-4384 RGB/DE interface, 25 MHz forwarded clock.
# Source: supplied ATK-4.3 RGBLCD manual, table 2.2.2.2, pages 4-5.
# Receiver setup/hold requirement: 12 ns each.
# Board data-minus-clock propagation budget: -1 ns to +1 ns.
# Keep the existing rising sampling edge of lcd_forwarded.
set_output_delay -clock [get_clocks lcd_forwarded] -max 13.000 [get_ports {lcd_rgb[*] lcd_de}]
set_output_delay -clock [get_clocks lcd_forwarded] -min -13.000 [get_ports {lcd_rgb[*] lcd_de}]
