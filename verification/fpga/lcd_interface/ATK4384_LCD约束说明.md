# ATK-4384 LCD输出时序约束

适用ABC v1.4 75MHz/AXI100MHz工程，LCD像素时钟25MHz，器件xc7z015clg485-2。

参数来自所提供LCD手册第4—5页表2.2.2.2：RGB数据与DE的建立时间和保持时间均为12ns。板级数据相对时钟的传播差预算为-1ns至+1ns，因此输出约束取max=13ns、min=-13ns。采样关系沿用当前工程lcd_forwarded上升沿。

| 检查项 | 结果 |
|---|---:|
| RGB与DE输出 | 25个 |
| LCD最差setup余量 | 3.358 ns |
| LCD最差hold余量 | 7.135 ns |
| 全局WNS/TNS | 0.355 / 0.000 ns |
| 全局WHS/THS | 0.013 / 0.000 ns |

在现有布线检查点上加入输出约束后，25个端口分别完成setup和hold检查。本版已将新增输出延时合入fpga/constraints/camera_lcd.xdc，工程重建时自动加载。已有引脚分配、时钟相位与RTL保持一致。随包bit/XSA/ELF沿用对应布线实现，输出约束已在该布线检查点上完成检查。

手册中ATK-4384的频率栏与周期栏存在冲突；本次按实际25MHz、40ns时钟分析。HSYNC与VSYNC在当前DE显示模式中为常量，背光lcd_bl单独作为控制信号，lcd_clk使用已有生成时钟定义。

相机cam_data[7:0]、cam_href和cam_vsync共10个输入端口还需要OV5640模块相对PCLK的输出延时范围。该项由相机接口资料确定。

时序明细见timing.rpt与lcd_output_paths.rpt，参数、来源和文件哈希见result.json。
