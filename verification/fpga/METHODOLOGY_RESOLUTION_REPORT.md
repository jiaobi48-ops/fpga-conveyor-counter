# ABC v1.4 时钟配置与实现结果

算法及控制时钟75 MHz，PS HP0/AXI/VDMA共享互联时钟100 MHz，LCD像素时钟25 MHz。
本版将FCLK1由150 MHz降至100 MHz；CPU、DDR存储器及UART保持原配置。
测速、输入超时、自测帧间隔和预览节拍沿用75 MHz配置。
相机像素、有效、行尾、帧首及ready信号已连接到算法与观察器。

| 布线后指标 | 结果 |
|---|---:|
| Setup WNS | 0.355 ns |
| Setup TNS | 0.000 ns |
| Hold WHS | 0.013 ns |
| Hold THS | 0.000 ns |

| 时钟域 | Setup WNS |
|---|---:|
| 75 MHz 算法及控制 | 0.355 ns |
| 100 MHz HP0/AXI/VDMA互联 | 2.476 ns |
| 25 MHz LCD | 13.993 ns |

动态阈值、自动动态去噪、三阈值并行、峰谷切分、轨迹防重复、合并恢复、相关测速、多帧稳定、场景保护和BRAM自测全部接入。

整链算法联合仿真及800×480动态BIST通过；配置测试70项、控制台9项和ARM裸机编译通过。详细结果见verification/results.json。

控制台提供相机预览、ROI调框、算法参数配置、设备状态和串口日志。

路径、DRC、CDC和方法学报告分别见paths.rpt、drc.rpt、cdc.rpt、methodology.rpt。
