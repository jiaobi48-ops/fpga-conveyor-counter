# Integrated camera, counter, AXI and LCD project with relative source paths.
set task_root [file normalize [file dirname [info script]]]
if {[current_project -quiet] ne ""} {error "File > Close Project first; the existing project is preserved."}
set project_dir [file join $task_root project [clock format [clock seconds] -format {%Y%m%d_%H%M%S}]]
create_project camera_vision_integrated_v14 $project_dir -part xc7z015clg485-2
set_property target_language Verilog [current_project]
set shared_cache [file join $task_root ip_cache]
file mkdir $shared_cache
config_ip_cache -use_cache_location $shared_cache
set_property ip_repo_paths [list [file normalize [file join $task_root ip_repo]]] [current_project]
update_ip_catalog
add_files -norecurse [glob [file join $task_root rtl *.v]]
add_files -norecurse [file join $task_root rtl vision_bindings.vh]
set_property file_type {Verilog Header} [get_files [file join $task_root rtl vision_bindings.vh]]
set_property file_type SystemVerilog [get_files [glob [file join $task_root rtl *.v]]]
set_property file_type Verilog [get_files [list [file join $task_root rtl vision_system_ip.v] [file join $task_root rtl vision_lcd_ip.v] [file join $task_root rtl follow_capture.v]]]
set_property include_dirs [list [file join $task_root rtl]] [get_filesets sources_1]
add_files -norecurse [file join $task_root data scenes_200x120.hex]
create_bd_design system
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 axi_mem_intercon
set_property -dict [list CONFIG.NUM_MI {1} CONFIG.NUM_SI {2}] [get_bd_cells axi_mem_intercon]
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_vdma:6.3 axi_vdma_0
set_property -dict [list CONFIG.c_include_s2mm {1} CONFIG.c_m_axis_mm2s_tdata_width {24} CONFIG.c_mm2s_linebuffer_depth {2048} CONFIG.c_mm2s_max_burst_length {64} CONFIG.c_num_fstores {3} CONFIG.c_s2mm_linebuffer_depth {2048} CONFIG.c_s2mm_max_burst_length {64} CONFIG.c_include_mm2s {1} CONFIG.c_mm2s_genlock_mode {3} CONFIG.c_s2mm_genlock_mode {2} CONFIG.c_include_internal_genlock {1}] [get_bd_cells axi_vdma_0]
create_bd_cell -type ip -vlnv xilinx.com:ip:clk_wiz:6.0 clk_wiz_0
set_property -dict [list CONFIG.PRIM_SOURCE {No_buffer} CONFIG.PRIM_IN_FREQ {100} CONFIG.CLKOUT1_REQUESTED_OUT_FREQ {25} CONFIG.CLKOUT2_USED {false} CONFIG.NUM_OUT_CLKS {1} CONFIG.USE_DYN_RECONFIG {false} CONFIG.AXI_DRP {false}] [get_bd_cells clk_wiz_0]
create_bd_cell -type ip -vlnv alientek.com:user:ov5640_capture_data:1.0 ov5640_capture_data_0
create_bd_cell -type ip -vlnv xilinx.com:ip:processing_system7:5.5 processing_system7_0
set_property -dict [list CONFIG.PCW_ACT_APU_PERIPHERAL_FREQMHZ {666.666687} CONFIG.PCW_ACT_CAN0_PERIPHERAL_FREQMHZ {23.8095} CONFIG.PCW_ACT_CAN1_PERIPHERAL_FREQMHZ {23.8095} CONFIG.PCW_ACT_CAN_PERIPHERAL_FREQMHZ {10.000000} CONFIG.PCW_ACT_DCI_PERIPHERAL_FREQMHZ {10.158730} CONFIG.PCW_ACT_ENET0_PERIPHERAL_FREQMHZ {10.000000} CONFIG.PCW_ACT_ENET1_PERIPHERAL_FREQMHZ {10.000000} CONFIG.PCW_ACT_FPGA0_PERIPHERAL_FREQMHZ {100.000000} CONFIG.PCW_ACT_FPGA1_PERIPHERAL_FREQMHZ {150.000000} CONFIG.PCW_ACT_FPGA2_PERIPHERAL_FREQMHZ {10.000000} CONFIG.PCW_ACT_FPGA3_PERIPHERAL_FREQMHZ {10.000000} CONFIG.PCW_ACT_I2C_PERIPHERAL_FREQMHZ {50} CONFIG.PCW_ACT_PCAP_PERIPHERAL_FREQMHZ {200.000000} CONFIG.PCW_ACT_QSPI_PERIPHERAL_FREQMHZ {10.000000} CONFIG.PCW_ACT_SDIO_PERIPHERAL_FREQMHZ {10.000000} CONFIG.PCW_ACT_SMC_PERIPHERAL_FREQMHZ {10.000000} CONFIG.PCW_ACT_SPI_PERIPHERAL_FREQMHZ {10.000000} CONFIG.PCW_ACT_TPIU_PERIPHERAL_FREQMHZ {200.000000} CONFIG.PCW_ACT_TTC0_CLK0_PERIPHERAL_FREQMHZ {111.111115} CONFIG.PCW_ACT_TTC0_CLK1_PERIPHERAL_FREQMHZ {111.111115} CONFIG.PCW_ACT_TTC0_CLK2_PERIPHERAL_FREQMHZ {111.111115} CONFIG.PCW_ACT_TTC1_CLK0_PERIPHERAL_FREQMHZ {111.111115} CONFIG.PCW_ACT_TTC1_CLK1_PERIPHERAL_FREQMHZ {111.111115} CONFIG.PCW_ACT_TTC1_CLK2_PERIPHERAL_FREQMHZ {111.111115} CONFIG.PCW_ACT_TTC_PERIPHERAL_FREQMHZ {50} CONFIG.PCW_ACT_UART_PERIPHERAL_FREQMHZ {100.000000} CONFIG.PCW_ACT_USB0_PERIPHERAL_FREQMHZ {60} CONFIG.PCW_ACT_USB1_PERIPHERAL_FREQMHZ {60} CONFIG.PCW_ACT_WDT_PERIPHERAL_FREQMHZ {111.111115} CONFIG.PCW_APU_CLK_RATIO_ENABLE {6:2:1} CONFIG.PCW_APU_PERIPHERAL_FREQMHZ {666.666666} CONFIG.PCW_CAN0_PERIPHERAL_CLKSRC {External} CONFIG.PCW_CAN0_PERIPHERAL_ENABLE {0} CONFIG.PCW_CAN1_PERIPHERAL_CLKSRC {External} CONFIG.PCW_CAN1_PERIPHERAL_ENABLE {0} CONFIG.PCW_CAN_PERIPHERAL_CLKSRC {IO PLL} CONFIG.PCW_CAN_PERIPHERAL_VALID {0} CONFIG.PCW_CLK0_FREQ {100000000} CONFIG.PCW_CLK1_FREQ {150000000} CONFIG.PCW_CLK2_FREQ {10000000} CONFIG.PCW_CLK3_FREQ {10000000} CONFIG.PCW_CPU_CPU_6X4X_MAX_RANGE {767} CONFIG.PCW_CPU_PERIPHERAL_CLKSRC {ARM PLL} CONFIG.PCW_CRYSTAL_PERIPHERAL_FREQMHZ {33.333333} CONFIG.PCW_DCI_PERIPHERAL_CLKSRC {DDR PLL} CONFIG.PCW_DCI_PERIPHERAL_FREQMHZ {10.159} CONFIG.PCW_DDR_PERIPHERAL_CLKSRC {DDR PLL} CONFIG.PCW_DDR_RAM_BASEADDR {0x00100000} CONFIG.PCW_DDR_RAM_HIGHADDR {0x3FFFFFFF} CONFIG.PCW_DM_WIDTH {4} CONFIG.PCW_DQS_WIDTH {4} CONFIG.PCW_DQ_WIDTH {32} CONFIG.PCW_ENET0_PERIPHERAL_CLKSRC {IO PLL} CONFIG.PCW_ENET0_PERIPHERAL_ENABLE {0} CONFIG.PCW_ENET1_PERIPHERAL_CLKSRC {IO PLL} CONFIG.PCW_ENET1_PERIPHERAL_ENABLE {0} CONFIG.PCW_ENET_RESET_POLARITY {Active Low} CONFIG.PCW_EN_4K_TIMER {0} CONFIG.PCW_EN_CAN0 {0} CONFIG.PCW_EN_CAN1 {0} CONFIG.PCW_EN_CLK0_PORT {1} CONFIG.PCW_EN_CLK1_PORT {1} CONFIG.PCW_EN_CLK2_PORT {0} CONFIG.PCW_EN_CLK3_PORT {0} CONFIG.PCW_EN_CLKTRIG0_PORT {0} CONFIG.PCW_EN_CLKTRIG1_PORT {0} CONFIG.PCW_EN_CLKTRIG2_PORT {0} CONFIG.PCW_EN_CLKTRIG3_PORT {0} CONFIG.PCW_EN_DDR {1} CONFIG.PCW_EN_EMIO_CAN0 {0} CONFIG.PCW_EN_EMIO_CAN1 {0} CONFIG.PCW_EN_EMIO_CD_SDIO0 {0} CONFIG.PCW_EN_EMIO_CD_SDIO1 {0} CONFIG.PCW_EN_EMIO_ENET0 {0} CONFIG.PCW_EN_EMIO_ENET1 {0} CONFIG.PCW_EN_EMIO_GPIO {1} CONFIG.PCW_EN_EMIO_I2C0 {0} CONFIG.PCW_EN_EMIO_I2C1 {0} CONFIG.PCW_EN_EMIO_MODEM_UART0 {0} CONFIG.PCW_EN_EMIO_MODEM_UART1 {0} CONFIG.PCW_EN_EMIO_PJTAG {0} CONFIG.PCW_EN_EMIO_SDIO0 {0} CONFIG.PCW_EN_EMIO_SDIO1 {0} CONFIG.PCW_EN_EMIO_SPI0 {0} CONFIG.PCW_EN_EMIO_SPI1 {0} CONFIG.PCW_EN_EMIO_SRAM_INT {0} CONFIG.PCW_EN_EMIO_TRACE {0} CONFIG.PCW_EN_EMIO_TTC0 {0} CONFIG.PCW_EN_EMIO_TTC1 {0} CONFIG.PCW_EN_EMIO_UART0 {0} CONFIG.PCW_EN_EMIO_UART1 {0} CONFIG.PCW_EN_EMIO_WDT {0} CONFIG.PCW_EN_EMIO_WP_SDIO0 {0} CONFIG.PCW_EN_EMIO_WP_SDIO1 {0} CONFIG.PCW_EN_ENET0 {0} CONFIG.PCW_EN_ENET1 {0} CONFIG.PCW_EN_GPIO {1} CONFIG.PCW_EN_I2C0 {0} CONFIG.PCW_EN_I2C1 {0} CONFIG.PCW_EN_MODEM_UART0 {0} CONFIG.PCW_EN_MODEM_UART1 {0} CONFIG.PCW_EN_PJTAG {0} CONFIG.PCW_EN_PTP_ENET0 {0} CONFIG.PCW_EN_PTP_ENET1 {0} CONFIG.PCW_EN_QSPI {0} CONFIG.PCW_EN_RST0_PORT {1} CONFIG.PCW_EN_RST1_PORT {0} CONFIG.PCW_EN_RST2_PORT {0} CONFIG.PCW_EN_RST3_PORT {0} CONFIG.PCW_EN_SDIO0 {0} CONFIG.PCW_EN_SDIO1 {0} CONFIG.PCW_EN_SMC {0} CONFIG.PCW_EN_SPI0 {0} CONFIG.PCW_EN_SPI1 {0} CONFIG.PCW_EN_TRACE {0} CONFIG.PCW_EN_TTC0 {0} CONFIG.PCW_EN_TTC1 {0} CONFIG.PCW_EN_UART0 {1} CONFIG.PCW_EN_UART1 {0} CONFIG.PCW_EN_USB0 {0} CONFIG.PCW_EN_USB1 {0} CONFIG.PCW_EN_WDT {0} CONFIG.PCW_FCLK0_PERIPHERAL_CLKSRC {IO PLL} CONFIG.PCW_FCLK1_PERIPHERAL_CLKSRC {IO PLL} CONFIG.PCW_FCLK2_PERIPHERAL_CLKSRC {IO PLL} CONFIG.PCW_FCLK3_PERIPHERAL_CLKSRC {IO PLL} CONFIG.PCW_FCLK_CLK0_BUF {FALSE} CONFIG.PCW_FCLK_CLK1_BUF {TRUE} CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ {100} CONFIG.PCW_FPGA1_PERIPHERAL_FREQMHZ {150} CONFIG.PCW_FPGA2_PERIPHERAL_FREQMHZ {50} CONFIG.PCW_FPGA3_PERIPHERAL_FREQMHZ {50} CONFIG.PCW_FPGA_FCLK0_ENABLE {1} CONFIG.PCW_FPGA_FCLK1_ENABLE {1} CONFIG.PCW_GP0_EN_MODIFIABLE_TXN {1} CONFIG.PCW_GP0_NUM_READ_THREADS {4} CONFIG.PCW_GP0_NUM_WRITE_THREADS {4} CONFIG.PCW_GP1_EN_MODIFIABLE_TXN {1} CONFIG.PCW_GP1_NUM_READ_THREADS {4} CONFIG.PCW_GP1_NUM_WRITE_THREADS {4} CONFIG.PCW_GPIO_EMIO_GPIO_ENABLE {1} CONFIG.PCW_GPIO_EMIO_GPIO_IO {2} CONFIG.PCW_GPIO_EMIO_GPIO_WIDTH {2} CONFIG.PCW_GPIO_MIO_GPIO_ENABLE {1} CONFIG.PCW_GPIO_MIO_GPIO_IO {MIO} CONFIG.PCW_GPIO_PERIPHERAL_ENABLE {0} CONFIG.PCW_I2C0_PERIPHERAL_ENABLE {0} CONFIG.PCW_I2C1_PERIPHERAL_ENABLE {0} CONFIG.PCW_I2C_RESET_ENABLE {1} CONFIG.PCW_I2C_RESET_POLARITY {Active Low} CONFIG.PCW_IMPORT_BOARD_PRESET {None} CONFIG.PCW_INCLUDE_ACP_TRANS_CHECK {0} CONFIG.PCW_MIO_0_IOTYPE {LVCMOS 3.3V} CONFIG.PCW_MIO_0_PULLUP {disabled} CONFIG.PCW_MIO_0_SLEW {slow} CONFIG.PCW_MIO_10_IOTYPE {LVCMOS 3.3V} CONFIG.PCW_MIO_10_PULLUP {enabled} CONFIG.PCW_MIO_10_SLEW {slow} CONFIG.PCW_MIO_11_IOTYPE {LVCMOS 3.3V} CONFIG.PCW_MIO_11_PULLUP {enabled} CONFIG.PCW_MIO_11_SLEW {slow} CONFIG.PCW_MIO_12_IOTYPE {LVCMOS 3.3V} CONFIG.PCW_MIO_12_PULLUP {enabled} CONFIG.PCW_MIO_12_SLEW {slow} CONFIG.PCW_MIO_13_IOTYPE {LVCMOS 3.3V} CONFIG.PCW_MIO_13_PULLUP {enabled} CONFIG.PCW_MIO_13_SLEW {slow} CONFIG.PCW_MIO_14_IOTYPE {LVCMOS 3.3V} CONFIG.PCW_MIO_14_PULLUP {enabled} CONFIG.PCW_MIO_14_SLEW {slow} CONFIG.PCW_MIO_15_IOTYPE {LVCMOS 3.3V} CONFIG.PCW_MIO_15_PULLUP {enabled} CONFIG.PCW_MIO_15_SLEW {slow} CONFIG.PCW_MIO_16_IOTYPE {LVCMOS 3.3V} CONFIG.PCW_MIO_16_PULLUP {enabled} CONFIG.PCW_MIO_16_SLEW {slow} CONFIG.PCW_MIO_17_IOTYPE {LVCMOS 3.3V} CONFIG.PCW_MIO_17_PULLUP {enabled} CONFIG.PCW_MIO_17_SLEW {slow} CONFIG.PCW_MIO_18_IOTYPE {LVCMOS 3.3V} CONFIG.PCW_MIO_18_PULLUP {enabled} CONFIG.PCW_MIO_18_SLEW {slow} CONFIG.PCW_MIO_19_IOTYPE {LVCMOS 3.3V} CONFIG.PCW_MIO_19_PULLUP {enabled} CONFIG.PCW_MIO_19_SLEW {slow} CONFIG.PCW_MIO_1_IOTYPE {LVCMOS 3.3V} CONFIG.PCW_MIO_1_PULLUP {enabled} CONFIG.PCW_MIO_1_SLEW {slow} CONFIG.PCW_MIO_20_IOTYPE {LVCMOS 3.3V} CONFIG.PCW_MIO_20_PULLUP {enabled} CONFIG.PCW_MIO_20_SLEW {slow} CONFIG.PCW_MIO_21_IOTYPE {LVCMOS 3.3V} CONFIG.PCW_MIO_21_PULLUP {enabled} CONFIG.PCW_MIO_21_SLEW {slow} CONFIG.PCW_MIO_22_IOTYPE {LVCMOS 3.3V} CONFIG.PCW_MIO_22_PULLUP {enabled} CONFIG.PCW_MIO_22_SLEW {slow} CONFIG.PCW_MIO_23_IOTYPE {LVCMOS 3.3V} CONFIG.PCW_MIO_23_PULLUP {enabled} CONFIG.PCW_MIO_23_SLEW {slow} CONFIG.PCW_MIO_24_IOTYPE {LVCMOS 3.3V} CONFIG.PCW_MIO_24_PULLUP {enabled} CONFIG.PCW_MIO_24_SLEW {slow} CONFIG.PCW_MIO_25_IOTYPE {LVCMOS 3.3V} CONFIG.PCW_MIO_25_PULLUP {enabled} CONFIG.PCW_MIO_25_SLEW {slow} CONFIG.PCW_MIO_26_IOTYPE {LVCMOS 3.3V} CONFIG.PCW_MIO_26_PULLUP {enabled} CONFIG.PCW_MIO_26_SLEW {slow} CONFIG.PCW_MIO_27_IOTYPE {LVCMOS 3.3V} CONFIG.PCW_MIO_27_PULLUP {enabled} CONFIG.PCW_MIO_27_SLEW {slow} CONFIG.PCW_MIO_28_IOTYPE {LVCMOS 3.3V} CONFIG.PCW_MIO_28_PULLUP {enabled} CONFIG.PCW_MIO_28_SLEW {slow} CONFIG.PCW_MIO_29_IOTYPE {LVCMOS 3.3V} CONFIG.PCW_MIO_29_PULLUP {enabled} CONFIG.PCW_MIO_29_SLEW {slow} CONFIG.PCW_MIO_2_IOTYPE {LVCMOS 3.3V} CONFIG.PCW_MIO_2_SLEW {slow} CONFIG.PCW_MIO_30_IOTYPE {LVCMOS 3.3V} CONFIG.PCW_MIO_30_PULLUP {enabled} CONFIG.PCW_MIO_30_SLEW {slow} CONFIG.PCW_MIO_31_IOTYPE {LVCMOS 3.3V} CONFIG.PCW_MIO_31_PULLUP {enabled} CONFIG.PCW_MIO_31_SLEW {slow} CONFIG.PCW_MIO_32_IOTYPE {LVCMOS 3.3V} CONFIG.PCW_MIO_32_PULLUP {enabled} CONFIG.PCW_MIO_32_SLEW {slow} CONFIG.PCW_MIO_33_IOTYPE {LVCMOS 3.3V} CONFIG.PCW_MIO_33_PULLUP {enabled} CONFIG.PCW_MIO_33_SLEW {slow} CONFIG.PCW_MIO_34_IOTYPE {LVCMOS 3.3V} CONFIG.PCW_MIO_34_PULLUP {enabled} CONFIG.PCW_MIO_34_SLEW {slow} CONFIG.PCW_MIO_35_IOTYPE {LVCMOS 3.3V} CONFIG.PCW_MIO_35_PULLUP {enabled} CONFIG.PCW_MIO_35_SLEW {slow} CONFIG.PCW_MIO_36_IOTYPE {LVCMOS 3.3V} CONFIG.PCW_MIO_36_PULLUP {enabled} CONFIG.PCW_MIO_36_SLEW {slow} CONFIG.PCW_MIO_37_IOTYPE {LVCMOS 3.3V} CONFIG.PCW_MIO_37_PULLUP {enabled} CONFIG.PCW_MIO_37_SLEW {slow} CONFIG.PCW_MIO_38_IOTYPE {LVCMOS 3.3V} CONFIG.PCW_MIO_38_PULLUP {enabled} CONFIG.PCW_MIO_38_SLEW {slow} CONFIG.PCW_MIO_39_IOTYPE {LVCMOS 3.3V} CONFIG.PCW_MIO_39_PULLUP {enabled} CONFIG.PCW_MIO_39_SLEW {slow} CONFIG.PCW_MIO_3_IOTYPE {LVCMOS 3.3V} CONFIG.PCW_MIO_3_SLEW {slow} CONFIG.PCW_MIO_40_IOTYPE {LVCMOS 3.3V} CONFIG.PCW_MIO_40_PULLUP {enabled} CONFIG.PCW_MIO_40_SLEW {slow} CONFIG.PCW_MIO_41_IOTYPE {LVCMOS 3.3V} CONFIG.PCW_MIO_41_PULLUP {enabled} CONFIG.PCW_MIO_41_SLEW {slow} CONFIG.PCW_MIO_42_IOTYPE {LVCMOS 3.3V} CONFIG.PCW_MIO_42_PULLUP {enabled} CONFIG.PCW_MIO_42_SLEW {slow} CONFIG.PCW_MIO_43_IOTYPE {LVCMOS 3.3V} CONFIG.PCW_MIO_43_PULLUP {enabled} CONFIG.PCW_MIO_43_SLEW {slow} CONFIG.PCW_MIO_44_IOTYPE {LVCMOS 3.3V} CONFIG.PCW_MIO_44_PULLUP {enabled} CONFIG.PCW_MIO_44_SLEW {slow} CONFIG.PCW_MIO_45_IOTYPE {LVCMOS 3.3V} CONFIG.PCW_MIO_45_PULLUP {enabled} CONFIG.PCW_MIO_45_SLEW {slow} CONFIG.PCW_MIO_46_IOTYPE {LVCMOS 3.3V} CONFIG.PCW_MIO_46_PULLUP {enabled} CONFIG.PCW_MIO_46_SLEW {slow} CONFIG.PCW_MIO_47_IOTYPE {LVCMOS 3.3V} CONFIG.PCW_MIO_47_PULLUP {enabled} CONFIG.PCW_MIO_47_SLEW {slow} CONFIG.PCW_MIO_48_IOTYPE {LVCMOS 3.3V} CONFIG.PCW_MIO_48_PULLUP {enabled} CONFIG.PCW_MIO_48_SLEW {slow} CONFIG.PCW_MIO_49_IOTYPE {LVCMOS 3.3V} CONFIG.PCW_MIO_49_PULLUP {enabled} CONFIG.PCW_MIO_49_SLEW {slow} CONFIG.PCW_MIO_4_IOTYPE {LVCMOS 3.3V} CONFIG.PCW_MIO_4_SLEW {slow} CONFIG.PCW_MIO_50_IOTYPE {LVCMOS 3.3V} CONFIG.PCW_MIO_50_PULLUP {enabled} CONFIG.PCW_MIO_50_SLEW {slow} CONFIG.PCW_MIO_51_IOTYPE {LVCMOS 3.3V} CONFIG.PCW_MIO_51_PULLUP {enabled} CONFIG.PCW_MIO_51_SLEW {slow} CONFIG.PCW_MIO_52_IOTYPE {LVCMOS 3.3V} CONFIG.PCW_MIO_52_PULLUP {enabled} CONFIG.PCW_MIO_52_SLEW {slow} CONFIG.PCW_MIO_53_IOTYPE {LVCMOS 3.3V} CONFIG.PCW_MIO_53_PULLUP {enabled} CONFIG.PCW_MIO_53_SLEW {slow} CONFIG.PCW_MIO_5_IOTYPE {LVCMOS 3.3V} CONFIG.PCW_MIO_5_SLEW {slow} CONFIG.PCW_MIO_6_IOTYPE {LVCMOS 3.3V} CONFIG.PCW_MIO_6_SLEW {slow} CONFIG.PCW_MIO_7_IOTYPE {LVCMOS 3.3V} CONFIG.PCW_MIO_7_SLEW {slow} CONFIG.PCW_MIO_8_IOTYPE {LVCMOS 3.3V} CONFIG.PCW_MIO_8_SLEW {slow} CONFIG.PCW_MIO_9_IOTYPE {LVCMOS 3.3V} CONFIG.PCW_MIO_9_PULLUP {enabled} CONFIG.PCW_MIO_9_SLEW {slow} CONFIG.PCW_MIO_PRIMITIVE {54} CONFIG.PCW_MIO_TREE_PERIPHERALS {GPIO#GPIO#GPIO#GPIO#GPIO#GPIO#GPIO#GPIO#GPIO#GPIO#GPIO#GPIO#GPIO#GPIO#UART 0#UART 0#GPIO#GPIO#GPIO#GPIO#GPIO#GPIO#GPIO#GPIO#GPIO#GPIO#GPIO#GPIO#GPIO#GPIO#GPIO#GPIO#GPIO#GPIO#GPIO#GPIO#GPIO#GPIO#GPIO#GPIO#GPIO#GPIO#GPIO#GPIO#GPIO#GPIO#GPIO#GPIO#GPIO#GPIO#GPIO#GPIO#GPIO#GPIO} CONFIG.PCW_MIO_TREE_SIGNALS {gpio[0]#gpio[1]#gpio[2]#gpio[3]#gpio[4]#gpio[5]#gpio[6]#gpio[7]#gpio[8]#gpio[9]#gpio[10]#gpio[11]#gpio[12]#gpio[13]#rx#tx#gpio[16]#gpio[17]#gpio[18]#gpio[19]#gpio[20]#gpio[21]#gpio[22]#gpio[23]#gpio[24]#gpio[25]#gpio[26]#gpio[27]#gpio[28]#gpio[29]#gpio[30]#gpio[31]#gpio[32]#gpio[33]#gpio[34]#gpio[35]#gpio[36]#gpio[37]#gpio[38]#gpio[39]#gpio[40]#gpio[41]#gpio[42]#gpio[43]#gpio[44]#gpio[45]#gpio[46]#gpio[47]#gpio[48]#gpio[49]#gpio[50]#gpio[51]#gpio[52]#gpio[53]} CONFIG.PCW_M_AXI_GP0_ENABLE_STATIC_REMAP {0} CONFIG.PCW_M_AXI_GP0_ID_WIDTH {12} CONFIG.PCW_M_AXI_GP0_SUPPORT_NARROW_BURST {0} CONFIG.PCW_M_AXI_GP0_THREAD_ID_WIDTH {12} CONFIG.PCW_NAND_CYCLES_T_AR {1} CONFIG.PCW_NAND_CYCLES_T_CLR {1} CONFIG.PCW_NAND_CYCLES_T_RC {11} CONFIG.PCW_NAND_CYCLES_T_REA {1} CONFIG.PCW_NAND_CYCLES_T_RR {1} CONFIG.PCW_NAND_CYCLES_T_WC {11} CONFIG.PCW_NAND_CYCLES_T_WP {1} CONFIG.PCW_NAND_PERIPHERAL_ENABLE {0} CONFIG.PCW_NOR_CS0_T_CEOE {1} CONFIG.PCW_NOR_CS0_T_PC {1} CONFIG.PCW_NOR_CS0_T_RC {11} CONFIG.PCW_NOR_CS0_T_TR {1} CONFIG.PCW_NOR_CS0_T_WC {11} CONFIG.PCW_NOR_CS0_T_WP {1} CONFIG.PCW_NOR_CS0_WE_TIME {0} CONFIG.PCW_NOR_CS1_T_CEOE {1} CONFIG.PCW_NOR_CS1_T_PC {1} CONFIG.PCW_NOR_CS1_T_RC {11} CONFIG.PCW_NOR_CS1_T_TR {1} CONFIG.PCW_NOR_CS1_T_WC {11} CONFIG.PCW_NOR_CS1_T_WP {1} CONFIG.PCW_NOR_CS1_WE_TIME {0} CONFIG.PCW_NOR_PERIPHERAL_ENABLE {0} CONFIG.PCW_NOR_SRAM_CS0_T_CEOE {1} CONFIG.PCW_NOR_SRAM_CS0_T_PC {1} CONFIG.PCW_NOR_SRAM_CS0_T_RC {11} CONFIG.PCW_NOR_SRAM_CS0_T_TR {1} CONFIG.PCW_NOR_SRAM_CS0_T_WC {11} CONFIG.PCW_NOR_SRAM_CS0_T_WP {1} CONFIG.PCW_NOR_SRAM_CS0_WE_TIME {0} CONFIG.PCW_NOR_SRAM_CS1_T_CEOE {1} CONFIG.PCW_NOR_SRAM_CS1_T_PC {1} CONFIG.PCW_NOR_SRAM_CS1_T_RC {11} CONFIG.PCW_NOR_SRAM_CS1_T_TR {1} CONFIG.PCW_NOR_SRAM_CS1_T_WC {11} CONFIG.PCW_NOR_SRAM_CS1_T_WP {1} CONFIG.PCW_NOR_SRAM_CS1_WE_TIME {0} CONFIG.PCW_OVERRIDE_BASIC_CLOCK {0} CONFIG.PCW_PACKAGE_DDR_BOARD_DELAY0 {0.096} CONFIG.PCW_PACKAGE_DDR_BOARD_DELAY1 {0.102} CONFIG.PCW_PACKAGE_DDR_BOARD_DELAY2 {0.100} CONFIG.PCW_PACKAGE_DDR_BOARD_DELAY3 {0.090} CONFIG.PCW_PACKAGE_DDR_DQS_TO_CLK_DELAY_0 {-0.054} CONFIG.PCW_PACKAGE_DDR_DQS_TO_CLK_DELAY_1 {-0.040} CONFIG.PCW_PACKAGE_DDR_DQS_TO_CLK_DELAY_2 {-0.041} CONFIG.PCW_PACKAGE_DDR_DQS_TO_CLK_DELAY_3 {-0.010} CONFIG.PCW_PACKAGE_NAME {clg485} CONFIG.PCW_PCAP_PERIPHERAL_CLKSRC {IO PLL} CONFIG.PCW_PCAP_PERIPHERAL_FREQMHZ {200} CONFIG.PCW_PERIPHERAL_BOARD_PRESET {None} CONFIG.PCW_PJTAG_PERIPHERAL_ENABLE {0} CONFIG.PCW_PLL_BYPASSMODE_ENABLE {0} CONFIG.PCW_PRESET_BANK0_VOLTAGE {LVCMOS 3.3V} CONFIG.PCW_PRESET_BANK1_VOLTAGE {LVCMOS 3.3V} CONFIG.PCW_PS7_SI_REV {PRODUCTION} CONFIG.PCW_QSPI_INTERNAL_HIGHADDRESS {0xFCFFFFFF} CONFIG.PCW_QSPI_PERIPHERAL_CLKSRC {IO PLL} CONFIG.PCW_QSPI_PERIPHERAL_ENABLE {0} CONFIG.PCW_SD0_PERIPHERAL_ENABLE {0} CONFIG.PCW_SD1_PERIPHERAL_ENABLE {0} CONFIG.PCW_SDIO_PERIPHERAL_CLKSRC {IO PLL} CONFIG.PCW_SDIO_PERIPHERAL_VALID {0} CONFIG.PCW_SMC_CYCLE_T0 {NA} CONFIG.PCW_SMC_CYCLE_T1 {NA} CONFIG.PCW_SMC_CYCLE_T2 {NA} CONFIG.PCW_SMC_CYCLE_T3 {NA} CONFIG.PCW_SMC_CYCLE_T4 {NA} CONFIG.PCW_SMC_CYCLE_T5 {NA} CONFIG.PCW_SMC_CYCLE_T6 {NA} CONFIG.PCW_SMC_PERIPHERAL_CLKSRC {IO PLL} CONFIG.PCW_SMC_PERIPHERAL_VALID {0} CONFIG.PCW_SPI0_PERIPHERAL_ENABLE {0} CONFIG.PCW_SPI1_PERIPHERAL_ENABLE {0} CONFIG.PCW_SPI_PERIPHERAL_CLKSRC {IO PLL} CONFIG.PCW_SPI_PERIPHERAL_VALID {0} CONFIG.PCW_S_AXI_HP0_DATA_WIDTH {64} CONFIG.PCW_S_AXI_HP0_ID_WIDTH {6} CONFIG.PCW_TPIU_PERIPHERAL_CLKSRC {External} CONFIG.PCW_TRACE_INTERNAL_WIDTH {2} CONFIG.PCW_TRACE_PERIPHERAL_ENABLE {0} CONFIG.PCW_TTC0_CLK0_PERIPHERAL_CLKSRC {CPU_1X} CONFIG.PCW_TTC0_CLK0_PERIPHERAL_DIVISOR0 {1} CONFIG.PCW_TTC0_CLK1_PERIPHERAL_CLKSRC {CPU_1X} CONFIG.PCW_TTC0_CLK1_PERIPHERAL_DIVISOR0 {1} CONFIG.PCW_TTC0_CLK2_PERIPHERAL_CLKSRC {CPU_1X} CONFIG.PCW_TTC0_CLK2_PERIPHERAL_DIVISOR0 {1} CONFIG.PCW_TTC0_PERIPHERAL_ENABLE {0} CONFIG.PCW_TTC1_CLK0_PERIPHERAL_CLKSRC {CPU_1X} CONFIG.PCW_TTC1_CLK0_PERIPHERAL_DIVISOR0 {1} CONFIG.PCW_TTC1_CLK1_PERIPHERAL_CLKSRC {CPU_1X} CONFIG.PCW_TTC1_CLK1_PERIPHERAL_DIVISOR0 {1} CONFIG.PCW_TTC1_CLK2_PERIPHERAL_CLKSRC {CPU_1X} CONFIG.PCW_TTC1_CLK2_PERIPHERAL_DIVISOR0 {1} CONFIG.PCW_TTC1_PERIPHERAL_ENABLE {0} CONFIG.PCW_UART0_BASEADDR {0xE0000000} CONFIG.PCW_UART0_BAUD_RATE {115200} CONFIG.PCW_UART0_GRP_FULL_ENABLE {0} CONFIG.PCW_UART0_HIGHADDR {0xE0000FFF} CONFIG.PCW_UART0_PERIPHERAL_ENABLE {1} CONFIG.PCW_UART0_UART0_IO {MIO 14 .. 15} CONFIG.PCW_UART1_PERIPHERAL_ENABLE {0} CONFIG.PCW_UART_PERIPHERAL_CLKSRC {IO PLL} CONFIG.PCW_UART_PERIPHERAL_FREQMHZ {100} CONFIG.PCW_UART_PERIPHERAL_VALID {1} CONFIG.PCW_UIPARAM_ACT_DDR_FREQ_MHZ {533.333374} CONFIG.PCW_UIPARAM_DDR_ADV_ENABLE {0} CONFIG.PCW_UIPARAM_DDR_AL {0} CONFIG.PCW_UIPARAM_DDR_BL {8} CONFIG.PCW_UIPARAM_DDR_BOARD_DELAY0 {0.25} CONFIG.PCW_UIPARAM_DDR_BOARD_DELAY1 {0.25} CONFIG.PCW_UIPARAM_DDR_BOARD_DELAY2 {0.25} CONFIG.PCW_UIPARAM_DDR_BOARD_DELAY3 {0.25} CONFIG.PCW_UIPARAM_DDR_BUS_WIDTH {32 Bit} CONFIG.PCW_UIPARAM_DDR_CLOCK_0_LENGTH_MM {0} CONFIG.PCW_UIPARAM_DDR_CLOCK_0_PACKAGE_LENGTH {80.0515} CONFIG.PCW_UIPARAM_DDR_CLOCK_0_PROPOGATION_DELAY {160} CONFIG.PCW_UIPARAM_DDR_CLOCK_1_LENGTH_MM {0} CONFIG.PCW_UIPARAM_DDR_CLOCK_1_PACKAGE_LENGTH {80.0515} CONFIG.PCW_UIPARAM_DDR_CLOCK_1_PROPOGATION_DELAY {160} CONFIG.PCW_UIPARAM_DDR_CLOCK_2_LENGTH_MM {0} CONFIG.PCW_UIPARAM_DDR_CLOCK_2_PACKAGE_LENGTH {80.0515} CONFIG.PCW_UIPARAM_DDR_CLOCK_2_PROPOGATION_DELAY {160} CONFIG.PCW_UIPARAM_DDR_CLOCK_3_LENGTH_MM {0} CONFIG.PCW_UIPARAM_DDR_CLOCK_3_PACKAGE_LENGTH {80.0515} CONFIG.PCW_UIPARAM_DDR_CLOCK_3_PROPOGATION_DELAY {160} CONFIG.PCW_UIPARAM_DDR_CLOCK_STOP_EN {0} CONFIG.PCW_UIPARAM_DDR_DQS_0_LENGTH_MM {0} CONFIG.PCW_UIPARAM_DDR_DQS_0_PACKAGE_LENGTH {133.8645} CONFIG.PCW_UIPARAM_DDR_DQS_0_PROPOGATION_DELAY {160} CONFIG.PCW_UIPARAM_DDR_DQS_1_LENGTH_MM {0} CONFIG.PCW_UIPARAM_DDR_DQS_1_PACKAGE_LENGTH {119.997} CONFIG.PCW_UIPARAM_DDR_DQS_1_PROPOGATION_DELAY {160} CONFIG.PCW_UIPARAM_DDR_DQS_2_LENGTH_MM {0} CONFIG.PCW_UIPARAM_DDR_DQS_2_PACKAGE_LENGTH {121.146} CONFIG.PCW_UIPARAM_DDR_DQS_2_PROPOGATION_DELAY {160} CONFIG.PCW_UIPARAM_DDR_DQS_3_LENGTH_MM {0} CONFIG.PCW_UIPARAM_DDR_DQS_3_PACKAGE_LENGTH {90.125} CONFIG.PCW_UIPARAM_DDR_DQS_3_PROPOGATION_DELAY {160} CONFIG.PCW_UIPARAM_DDR_DQS_TO_CLK_DELAY_0 {0.0} CONFIG.PCW_UIPARAM_DDR_DQS_TO_CLK_DELAY_1 {0.0} CONFIG.PCW_UIPARAM_DDR_DQS_TO_CLK_DELAY_2 {0.0} CONFIG.PCW_UIPARAM_DDR_DQS_TO_CLK_DELAY_3 {0.0} CONFIG.PCW_UIPARAM_DDR_DQ_0_LENGTH_MM {0} CONFIG.PCW_UIPARAM_DDR_DQ_0_PACKAGE_LENGTH {111.7605} CONFIG.PCW_UIPARAM_DDR_DQ_0_PROPOGATION_DELAY {160} CONFIG.PCW_UIPARAM_DDR_DQ_1_LENGTH_MM {0} CONFIG.PCW_UIPARAM_DDR_DQ_1_PACKAGE_LENGTH {123.5525} CONFIG.PCW_UIPARAM_DDR_DQ_1_PROPOGATION_DELAY {160} CONFIG.PCW_UIPARAM_DDR_DQ_2_LENGTH_MM {0} CONFIG.PCW_UIPARAM_DDR_DQ_2_PACKAGE_LENGTH {120.714} CONFIG.PCW_UIPARAM_DDR_DQ_2_PROPOGATION_DELAY {160} CONFIG.PCW_UIPARAM_DDR_DQ_3_LENGTH_MM {0} CONFIG.PCW_UIPARAM_DDR_DQ_3_PACKAGE_LENGTH {100.836} CONFIG.PCW_UIPARAM_DDR_DQ_3_PROPOGATION_DELAY {160} CONFIG.PCW_UIPARAM_DDR_ENABLE {1} CONFIG.PCW_UIPARAM_DDR_FREQ_MHZ {533.333333} CONFIG.PCW_UIPARAM_DDR_HIGH_TEMP {Normal (0-85)} CONFIG.PCW_UIPARAM_DDR_MEMORY_TYPE {DDR 3 (Low Voltage)} CONFIG.PCW_UIPARAM_DDR_PARTNO {MT41K256M16 RE-125} CONFIG.PCW_UIPARAM_DDR_TRAIN_DATA_EYE {1} CONFIG.PCW_UIPARAM_DDR_TRAIN_READ_GATE {1} CONFIG.PCW_UIPARAM_DDR_TRAIN_WRITE_LEVEL {1} CONFIG.PCW_UIPARAM_DDR_USE_INTERNAL_VREF {0} CONFIG.PCW_UIPARAM_GENERATE_SUMMARY {NA} CONFIG.PCW_USB0_PERIPHERAL_ENABLE {0} CONFIG.PCW_USB1_PERIPHERAL_ENABLE {0} CONFIG.PCW_USB_RESET_ENABLE {1} CONFIG.PCW_USB_RESET_POLARITY {Active Low} CONFIG.PCW_USE_AXI_FABRIC_IDLE {0} CONFIG.PCW_USE_AXI_NONSECURE {0} CONFIG.PCW_USE_CORESIGHT {0} CONFIG.PCW_USE_CROSS_TRIGGER {0} CONFIG.PCW_USE_CR_FABRIC {1} CONFIG.PCW_USE_DDR_BYPASS {0} CONFIG.PCW_USE_DEBUG {0} CONFIG.PCW_USE_DMA0 {0} CONFIG.PCW_USE_DMA1 {0} CONFIG.PCW_USE_DMA2 {0} CONFIG.PCW_USE_DMA3 {0} CONFIG.PCW_USE_EXPANDED_IOP {0} CONFIG.PCW_USE_FABRIC_INTERRUPT {0} CONFIG.PCW_USE_HIGH_OCM {0} CONFIG.PCW_USE_M_AXI_GP0 {1} CONFIG.PCW_USE_M_AXI_GP1 {0} CONFIG.PCW_USE_PROC_EVENT_BUS {0} CONFIG.PCW_USE_PS_SLCR_REGISTERS {0} CONFIG.PCW_USE_S_AXI_ACP {0} CONFIG.PCW_USE_S_AXI_GP0 {0} CONFIG.PCW_USE_S_AXI_GP1 {0} CONFIG.PCW_USE_S_AXI_HP0 {1} CONFIG.PCW_USE_S_AXI_HP1 {0} CONFIG.PCW_USE_S_AXI_HP2 {0} CONFIG.PCW_USE_S_AXI_HP3 {0} CONFIG.PCW_USE_TRACE {0} CONFIG.PCW_VALUE_SILVERSION {3} CONFIG.PCW_WDT_PERIPHERAL_CLKSRC {CPU_1X} CONFIG.PCW_WDT_PERIPHERAL_DIVISOR0 {1} CONFIG.PCW_WDT_PERIPHERAL_ENABLE {0}] [get_bd_cells processing_system7_0]
# Lower the existing shared algorithm/AXI clock domain; retain DDR/CPU/UART.
set_property CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ 75 [get_bd_cells processing_system7_0]
set_property CONFIG.PCW_FPGA1_PERIPHERAL_FREQMHZ 100 [get_bd_cells processing_system7_0]
set actual_algorithm_mhz [get_property CONFIG.PCW_ACT_FPGA0_PERIPHERAL_FREQMHZ [get_bd_cells processing_system7_0]]
if {abs($actual_algorithm_mhz-75.0)>0.001} {error "PS did not realize the requested 75MHz clock"}
set_property CONFIG.PRIM_IN_FREQ $actual_algorithm_mhz [get_bd_cells clk_wiz_0]
set actual_axi_mhz [get_property CONFIG.PCW_ACT_FPGA1_PERIPHERAL_FREQMHZ [get_bd_cells processing_system7_0]]
if {abs($actual_axi_mhz-100.0)>0.001} {error "PS did not realize the requested 100MHz AXI clock"}
puts "CLOCK75_AXI100_CONFIG algorithm_mhz=$actual_algorithm_mhz axi_mhz=$actual_axi_mhz lcd_requested_mhz=25"
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_interconnect:2.1 ps7_0_axi_periph
set_property -dict [list CONFIG.NUM_MI {3}] [get_bd_cells ps7_0_axi_periph]
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_ps7_0_100M
create_bd_cell -type ip -vlnv xilinx.com:ip:proc_sys_reset:5.0 rst_ps7_0_150M
create_bd_cell -type ip -vlnv xilinx.com:ip:v_axi4s_vid_out:4.0 v_axi4s_vid_out_0
set_property -dict [list CONFIG.C_HAS_ASYNC_CLK {1}] [get_bd_cells v_axi4s_vid_out_0]
create_bd_cell -type ip -vlnv xilinx.com:ip:v_tc:6.2 v_tc_0
set_property -dict [list CONFIG.enable_detection {false}] [get_bd_cells v_tc_0]
create_bd_cell -type ip -vlnv xilinx.com:ip:v_vid_in_axi4s:5.0 v_vid_in_axi4s_0
set_property -dict [list CONFIG.C_HAS_ASYNC_CLK {1}] [get_bd_cells v_vid_in_axi4s_0]
create_bd_cell -type ip -vlnv xilinx.com:ip:util_vector_logic:2.0 util_vector_logic_0
set_property -dict [list CONFIG.C_OPERATION {not} CONFIG.C_SIZE {1}] [get_bd_cells util_vector_logic_0]
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 cup_gpio
set_property -dict [list CONFIG.C_GPIO_WIDTH {32} CONFIG.C_ALL_INPUTS {1} CONFIG.C_IS_DUAL {1} CONFIG.C_GPIO2_WIDTH {32} CONFIG.C_ALL_OUTPUTS_2 {1} CONFIG.C_DOUT_DEFAULT_2 {0x00000000}] [get_bd_cells cup_gpio]
create_bd_cell -type module -reference vision_lcd_ip lcd_video_bridge_0
connect_bd_intf_net [get_bd_intf_pins ps7_0_axi_periph/M02_AXI] [get_bd_intf_pins cup_gpio/S_AXI]
connect_bd_net [get_bd_pins v_axi4s_vid_out_0/vid_vsync] [get_bd_pins lcd_video_bridge_0/video_vsync]
proc lcd_external {pin name} {
    set prior [get_bd_intf_ports -quiet]
    make_bd_intf_pins_external [get_bd_intf_pins $pin]
    set added {}
    foreach p [get_bd_intf_ports -quiet] {if {$p ni $prior} {lappend added $p}}
    if {[llength $added]!=1} {error "Expected one external interface for $pin"}
    set_property name $name $added
}
lcd_external processing_system7_0/DDR DDR
lcd_external processing_system7_0/FIXED_IO FIXED_IO
lcd_external processing_system7_0/GPIO_0 emio_sccb
create_bd_port -dir I cam_pclk
create_bd_port -dir I cam_vsync
create_bd_port -dir I cam_href
create_bd_port -dir I -from 7 -to 0 cam_data
create_bd_port -dir O cam_rst_n
create_bd_port -dir O cam_pwdn
create_bd_port -dir O -from 23 -to 0 lcd_rgb
create_bd_port -dir O lcd_de
create_bd_port -dir O lcd_hs
create_bd_port -dir O lcd_vs
create_bd_port -dir O lcd_bl
create_bd_port -dir O lcd_clk
create_bd_port -dir O lcd_rst
create_bd_port -dir O ms7200_rst_n
connect_bd_intf_net [get_bd_intf_pins {axi_mem_intercon/M00_AXI}] [get_bd_intf_pins {processing_system7_0/S_AXI_HP0}]
connect_bd_intf_net [get_bd_intf_pins {axi_vdma_0/M_AXIS_MM2S}] [get_bd_intf_pins {v_axi4s_vid_out_0/video_in}]
connect_bd_intf_net [get_bd_intf_pins {axi_vdma_0/M_AXI_MM2S}] [get_bd_intf_pins {axi_mem_intercon/S00_AXI}]
connect_bd_intf_net [get_bd_intf_pins {axi_vdma_0/M_AXI_S2MM}] [get_bd_intf_pins {axi_mem_intercon/S01_AXI}]
connect_bd_intf_net [get_bd_intf_pins {ov5640_capture_data_0/cmos_rgb}] [get_bd_intf_pins {v_vid_in_axi4s_0/vid_io_in}]
connect_bd_intf_net [get_bd_intf_ports {DDR}] [get_bd_intf_pins {processing_system7_0/DDR}]
connect_bd_intf_net [get_bd_intf_ports {FIXED_IO}] [get_bd_intf_pins {processing_system7_0/FIXED_IO}]
connect_bd_intf_net [get_bd_intf_ports {emio_sccb}] [get_bd_intf_pins {processing_system7_0/GPIO_0}]
connect_bd_intf_net [get_bd_intf_pins {processing_system7_0/M_AXI_GP0}] [get_bd_intf_pins {ps7_0_axi_periph/S00_AXI}]
connect_bd_intf_net [get_bd_intf_pins {ps7_0_axi_periph/M00_AXI}] [get_bd_intf_pins {axi_vdma_0/S_AXI_LITE}]
connect_bd_intf_net [get_bd_intf_pins {ps7_0_axi_periph/M01_AXI}] [get_bd_intf_pins {v_tc_0/ctrl}]
connect_bd_intf_net [get_bd_intf_pins {v_tc_0/vtiming_out}] [get_bd_intf_pins {v_axi4s_vid_out_0/vtiming_in}]

connect_bd_net [get_bd_ports {cam_data}] [get_bd_pins {ov5640_capture_data_0/cam_data}]
connect_bd_net [get_bd_ports {cam_href}] [get_bd_pins {ov5640_capture_data_0/cam_href}]
connect_bd_net [get_bd_ports {cam_pclk}] [get_bd_pins {ov5640_capture_data_0/cam_pclk}]
connect_bd_net [get_bd_ports {cam_vsync}] [get_bd_pins {ov5640_capture_data_0/cam_vsync}]
connect_bd_net [get_bd_pins {clk_wiz_0/clk_out1}] [get_bd_pins {v_axi4s_vid_out_0/vid_io_out_clk}] [get_bd_pins {v_tc_0/clk}] [get_bd_pins {lcd_video_bridge_0/pixel_clk}]
connect_bd_net [get_bd_pins {clk_wiz_0/locked}] [get_bd_pins {ov5640_capture_data_0/rst_n}] [get_bd_pins {util_vector_logic_0/Op1}] [get_bd_pins {v_vid_in_axi4s_0/aresetn}] [get_bd_pins {lcd_video_bridge_0/reset_n}]
connect_bd_net [get_bd_pins {ov5640_capture_data_0/cam_pwdn}] [get_bd_ports {cam_pwdn}]
connect_bd_net [get_bd_pins {ov5640_capture_data_0/cam_rst_n}] [get_bd_ports {cam_rst_n}]
connect_bd_net [get_bd_pins {ov5640_capture_data_0/cmos_frame_ce}] [get_bd_pins {v_vid_in_axi4s_0/vid_io_in_ce}]
connect_bd_net [get_bd_pins {ov5640_capture_data_0/cmos_frame_clk}] [get_bd_pins {v_vid_in_axi4s_0/vid_io_in_clk}]
connect_bd_net [get_bd_pins {processing_system7_0/FCLK_CLK0}] [get_bd_pins {axi_mem_intercon/S01_ACLK}] [get_bd_pins {axi_vdma_0/s_axi_lite_aclk}] [get_bd_pins {axi_vdma_0/m_axi_s2mm_aclk}] [get_bd_pins {axi_vdma_0/s_axis_s2mm_aclk}] [get_bd_pins {clk_wiz_0/clk_in1}] [get_bd_pins {processing_system7_0/M_AXI_GP0_ACLK}] [get_bd_pins {ps7_0_axi_periph/ACLK}] [get_bd_pins {ps7_0_axi_periph/S00_ACLK}] [get_bd_pins {ps7_0_axi_periph/M00_ACLK}] [get_bd_pins {ps7_0_axi_periph/M01_ACLK}] [get_bd_pins {rst_ps7_0_100M/slowest_sync_clk}] [get_bd_pins {cup_gpio/s_axi_aclk}] [get_bd_pins {ps7_0_axi_periph/M02_ACLK}] [get_bd_pins {v_tc_0/s_axi_aclk}] [get_bd_pins {v_vid_in_axi4s_0/aclk}]
connect_bd_net [get_bd_pins {processing_system7_0/FCLK_CLK1}] [get_bd_pins {axi_mem_intercon/ACLK}] [get_bd_pins {axi_mem_intercon/S00_ACLK}] [get_bd_pins {axi_mem_intercon/M00_ACLK}] [get_bd_pins {axi_vdma_0/m_axi_mm2s_aclk}] [get_bd_pins {axi_vdma_0/m_axis_mm2s_aclk}] [get_bd_pins {processing_system7_0/S_AXI_HP0_ACLK}] [get_bd_pins {rst_ps7_0_150M/slowest_sync_clk}] [get_bd_pins {v_axi4s_vid_out_0/aclk}]
connect_bd_net [get_bd_pins {processing_system7_0/FCLK_RESET0_N}] [get_bd_pins {rst_ps7_0_100M/ext_reset_in}] [get_bd_pins {rst_ps7_0_150M/ext_reset_in}]
connect_bd_net [get_bd_pins {rst_ps7_0_100M/peripheral_aresetn}] [get_bd_pins {axi_mem_intercon/S01_ARESETN}] [get_bd_pins {axi_vdma_0/axi_resetn}] [get_bd_pins {ps7_0_axi_periph/ARESETN}] [get_bd_pins {ps7_0_axi_periph/S00_ARESETN}] [get_bd_pins {ps7_0_axi_periph/M00_ARESETN}] [get_bd_pins {ps7_0_axi_periph/M01_ARESETN}] [get_bd_pins {v_tc_0/s_axi_aresetn}] [get_bd_pins {cup_gpio/s_axi_aresetn}] [get_bd_pins {ps7_0_axi_periph/M02_ARESETN}]
connect_bd_net [get_bd_pins {rst_ps7_0_100M/peripheral_reset}] [get_bd_pins {clk_wiz_0/reset}]
connect_bd_net [get_bd_pins {rst_ps7_0_150M/peripheral_aresetn}] [get_bd_pins {axi_mem_intercon/ARESETN}] [get_bd_pins {axi_mem_intercon/S00_ARESETN}] [get_bd_pins {axi_mem_intercon/M00_ARESETN}]
connect_bd_net [get_bd_pins {util_vector_logic_0/Res}] [get_bd_pins {v_vid_in_axi4s_0/vid_io_in_reset}]
connect_bd_net [get_bd_pins {v_axi4s_vid_out_0/vtg_ce}] [get_bd_pins {v_tc_0/gen_clken}]
connect_bd_net [get_bd_pins {v_axi4s_vid_out_0/vid_data}] [get_bd_pins {lcd_video_bridge_0/video_rgb}]
connect_bd_net [get_bd_pins {v_axi4s_vid_out_0/vid_active_video}] [get_bd_pins {lcd_video_bridge_0/video_de}]
connect_bd_net [get_bd_pins {v_axi4s_vid_out_0/locked}] [get_bd_pins {lcd_video_bridge_0/video_locked}]
connect_bd_net [get_bd_ports {lcd_rgb}] [get_bd_pins {lcd_video_bridge_0/lcd_rgb}]
connect_bd_net [get_bd_ports {lcd_de}] [get_bd_pins {lcd_video_bridge_0/lcd_de}]
connect_bd_net [get_bd_ports {lcd_hs}] [get_bd_pins {lcd_video_bridge_0/lcd_hs}]
connect_bd_net [get_bd_ports {lcd_vs}] [get_bd_pins {lcd_video_bridge_0/lcd_vs}]
connect_bd_net [get_bd_ports {lcd_bl}] [get_bd_pins {lcd_video_bridge_0/lcd_bl}]
connect_bd_net [get_bd_ports {lcd_clk}] [get_bd_pins {lcd_video_bridge_0/lcd_clk}]
connect_bd_net [get_bd_ports {lcd_rst}] [get_bd_pins {lcd_video_bridge_0/lcd_rst}]
connect_bd_net [get_bd_ports {ms7200_rst_n}] [get_bd_pins {lcd_video_bridge_0/ms7200_rst_n}]
# Frozen source thumbnail / safety lease; separate acknowledged GPIO endpoint.
set_property CONFIG.NUM_MI 4 [get_bd_cells ps7_0_axi_periph]
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 follow_gpio
set_property -dict [list CONFIG.C_GPIO_WIDTH 32 CONFIG.C_ALL_INPUTS 1 CONFIG.C_IS_DUAL 1 CONFIG.C_GPIO2_WIDTH 32 CONFIG.C_ALL_OUTPUTS_2 1 CONFIG.C_DOUT_DEFAULT_2 0x00000000] [get_bd_cells follow_gpio]
create_bd_cell -type module -reference follow_capture follow_capture_0
connect_bd_intf_net [get_bd_intf_pins ps7_0_axi_periph/M03_AXI] [get_bd_intf_pins follow_gpio/S_AXI]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins follow_gpio/s_axi_aclk] [get_bd_pins ps7_0_axi_periph/M03_ACLK] [get_bd_pins follow_capture_0/clk]
connect_bd_net [get_bd_pins rst_ps7_0_100M/peripheral_aresetn] [get_bd_pins follow_gpio/s_axi_aresetn] [get_bd_pins ps7_0_axi_periph/M03_ARESETN] [get_bd_pins follow_capture_0/reset_n]
connect_bd_net [get_bd_pins follow_gpio/gpio2_io_o] [get_bd_pins follow_capture_0/request]
connect_bd_net [get_bd_pins follow_capture_0/response] [get_bd_pins follow_gpio/gpio_io_i]
create_bd_cell -type module -reference vision_system_ip vision_system_bridge_0
set scene_rom [file normalize [file join $task_root data scenes_200x120.hex]]
if {![file exists $scene_rom]} {error "Missing scene ROM"}
set_property -dict [list CONFIG.ROM_FILE $scene_rom] [get_bd_cells vision_system_bridge_0]
if {[get_property CONFIG.ROM_FILE [get_bd_cells vision_system_bridge_0]] ne $scene_rom} {error "ROM configuration mismatch"}
set_property CONFIG.NUM_MI 5 [get_bd_cells ps7_0_axi_periph]
create_bd_cell -type ip -vlnv xilinx.com:ip:axi_gpio:2.0 vision_gpio
set_property -dict [list CONFIG.C_GPIO_WIDTH 32 CONFIG.C_ALL_INPUTS 1 CONFIG.C_IS_DUAL 1 CONFIG.C_GPIO2_WIDTH 32 CONFIG.C_ALL_OUTPUTS_2 1 CONFIG.C_DOUT_DEFAULT_2 {0x00000000}] [get_bd_cells vision_gpio]
connect_bd_intf_net [get_bd_intf_pins ps7_0_axi_periph/M04_AXI] [get_bd_intf_pins vision_gpio/S_AXI]
connect_bd_net [get_bd_pins processing_system7_0/FCLK_CLK0] [get_bd_pins vision_gpio/s_axi_aclk] [get_bd_pins ps7_0_axi_periph/M04_ACLK] [get_bd_pins vision_system_bridge_0/clk]
connect_bd_net [get_bd_pins rst_ps7_0_100M/peripheral_aresetn] [get_bd_pins vision_gpio/s_axi_aresetn] [get_bd_pins ps7_0_axi_periph/M04_ARESETN] [get_bd_pins vision_system_bridge_0/reset_n]
connect_bd_net [get_bd_pins vision_gpio/gpio2_io_o] [get_bd_pins vision_system_bridge_0/request]
connect_bd_net [get_bd_pins vision_system_bridge_0/response] [get_bd_pins vision_gpio/gpio_io_i] [get_bd_pins cup_gpio/gpio_io_i]
# Camera stream pins are connected together with their observer taps below.
connect_bd_intf_net [get_bd_intf_pins vision_system_bridge_0/M_AXIS] [get_bd_intf_pins axi_vdma_0/S_AXIS_S2MM]
foreach {axis observer} {tdata stream_rgb tvalid stream_valid tuser stream_sof tlast stream_eol} {
 connect_bd_net [get_bd_pins v_vid_in_axi4s_0/m_axis_video_$axis] [get_bd_pins vision_system_bridge_0/s_axis_$axis] [get_bd_pins follow_capture_0/$observer]
}
connect_bd_net [get_bd_pins vision_system_bridge_0/s_axis_tready] [get_bd_pins v_vid_in_axi4s_0/m_axis_video_tready] [get_bd_pins follow_capture_0/stream_ready]
connect_bd_net [get_bd_pins clk_wiz_0/clk_out1] [get_bd_pins vision_system_bridge_0/display_clk]
foreach pin {display_packet projection_value} {
 connect_bd_net [get_bd_pins vision_system_bridge_0/$pin] [get_bd_pins lcd_video_bridge_0/$pin]
}
foreach pin {display_tick projection_address} {
 connect_bd_net [get_bd_pins lcd_video_bridge_0/$pin] [get_bd_pins vision_system_bridge_0/$pin]
}
assign_bd_address -offset 0x43C40000 -range 64K -target_address_space [get_bd_addr_spaces processing_system7_0/Data] [get_bd_addr_segs vision_gpio/S_AXI/Reg] -force
assign_bd_address -offset 0x43C30000 -range 64K -target_address_space [get_bd_addr_spaces processing_system7_0/Data] [get_bd_addr_segs follow_gpio/S_AXI/Reg] -force
assign_bd_address -offset 0x00000000 -range 1G -target_address_space [get_bd_addr_spaces {/axi_vdma_0/Data_MM2S}] [get_bd_addr_segs {/processing_system7_0/S_AXI_HP0/HP0_DDR_LOWOCM}] -force
assign_bd_address -offset 0x00000000 -range 1G -target_address_space [get_bd_addr_spaces {/axi_vdma_0/Data_S2MM}] [get_bd_addr_segs {/processing_system7_0/S_AXI_HP0/HP0_DDR_LOWOCM}] -force
assign_bd_address -offset 0x43000000 -range 64K -target_address_space [get_bd_addr_spaces {/processing_system7_0/Data}] [get_bd_addr_segs {/axi_vdma_0/S_AXI_LITE/Reg}] -force
assign_bd_address -offset 0x43C10000 -range 64K -target_address_space [get_bd_addr_spaces {/processing_system7_0/Data}] [get_bd_addr_segs {/v_tc_0/ctrl/Reg}] -force
assign_bd_address -offset 0x43C20000 -range 64K -target_address_space [get_bd_addr_spaces {/processing_system7_0/Data}] [get_bd_addr_segs {/cup_gpio/S_AXI/Reg}] -force
validate_bd_design
save_bd_design
set bd_file [get_files -quiet */system.bd]
if {[llength $bd_file]!=1} {error "Expected one independent BD"}
add_files -norecurse [make_wrapper -files $bd_file -top]
add_files -fileset constrs_1 -norecurse [file join $task_root constraints camera_lcd.xdc]
set_property top system_wrapper [get_filesets sources_1]
update_compile_order -fileset sources_1
puts "CUP_COUNT_PROJECT_READY"
generate_target all $bd_file
update_compile_order -fileset sources_1
puts "FIXED_COUNTER_PROJECT_GENERATED"

# Pack equivalent narrow-index logic and optimize small enables into datapaths.
create_ip_run $bd_file
foreach run [get_runs -filter {IS_SYNTHESIS == 1}] {
 if {![regexp {^(synth_1|system_(vision_system_bridge|lcd_video_bridge|follow_capture)_0(_0)?_synth_1)$} [get_property NAME $run]]} {continue}
 set_property STEPS.SYNTH_DESIGN.ARGS.CONTROL_SET_OPT_THRESHOLD 16 $run
 set_property STEPS.SYNTH_DESIGN.ARGS.RESOURCE_SHARING on $run
 set_property STEPS.SYNTH_DESIGN.ARGS.RETIMING true $run
 set_property STEPS.SYNTH_DESIGN.ARGS.FSM_EXTRACTION one_hot $run
}
set_property STEPS.PHYS_OPT_DESIGN.IS_ENABLED false [get_runs impl_1]
set_property STEPS.PHYS_OPT_DESIGN.ARGS.DIRECTIVE AggressiveExplore [get_runs impl_1]
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.IS_ENABLED false [get_runs impl_1]
set_property STEPS.POST_ROUTE_PHYS_OPT_DESIGN.ARGS.DIRECTIVE AggressiveExplore [get_runs impl_1]
set implementation_hook [file normalize [file join $task_root .. tools physical_threads.tcl]]
add_files -fileset utils_1 -norecurse $implementation_hook
set_property STEPS.OPT_DESIGN.TCL.PRE $implementation_hook [get_runs impl_1]

add_files -fileset utils_1 -norecurse [file normalize [file join $task_root .. tools native_synth_pre.tcl]]
set_property STEPS.SYNTH_DESIGN.TCL.PRE [file normalize [file join $task_root .. tools native_synth_pre.tcl]] [get_runs system_vision_system_bridge_0_0_synth_1]


