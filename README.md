# FPGA 传送带视觉计数系统：完整代码提交版 v1.4r2

本次修订包含ATK-4384 LCD输出时序约束、控制台Vivado/Vitis XSDB自动识别及C离线标定工具。算法75MHz、AXI100MHz、LCD25MHz，完整算法与配套程序沿用v1.4。

本包包含整机自主源代码、第三方BSP/IP、约束、仿真、构建脚本、配套bit/XSA/ELF和Windows控制台。B的完整算法流水线已接入摄像头、PS控制与RGBLCD显示。

已接入动态阈值、动态噪声统计与去噪策略、3×3形态学、三阈值硬件并行与融合、投影峰谷切分、右到左轨迹防重复、合并判别与轨迹恢复、相关测速、多帧稳定、场景保护与自动恢复、拨码参数字配置、静态BRAM场景与动态BIST。LCD叠加累计、状态、投影波形与切割线。

像素链路保持单像素/周期；帧后投影归约将乘法、峰谷判决和计数提交分级处理。

## 文件入口

- tools/offline_calibration/index.html：离线标定入口；生成800×480的ROI、阈值、保护区和控制台算法场景。
- console/控制台.exe：串口日志、相机预览、调框、算法参数、三路结果、遮挡与计数控制。启动时使用完整目录，运行环境包括 Python 3、NumPy、Pillow、Tk 和 AMD Vitis/Vivado 2025.2。
- console/src/：ARM 裸机程序；默认手动暂停。邮箱协议4，主循环处理 UART；常用按钮走已连接的 JTAG/DDR 控制邮箱，并核对实际生效状态。
- fpga/rtl、fpga/constraints、fpga/ip_repo、fpga/reference、fpga/create_project.tcl：完整 RTL、引脚约束、定制 IP、BD 参考和工程重建入口。
- bsp/：配套 ARM standalone BSP 头文件、库及库源码。
- fpga/sim/：RTL 仿真；tools/：完整性检查及独立重编译脚本。

## 运行与升级

先停带并关闭旧控制台和 SSCOM 串口，打开 console/控制台.exe，选择开发板串口，接好 JTAG 后点击“初始化开发板”。本次会下载 v1.4 并清零，默认保持暂停。“连接设备”用于连接已运行的配套固件；升级使用“初始化开发板”。

设置右侧入口线A、左侧出口线B及ROI后点击正常计数。“FPGA算法 / 三路并行”页提供全部算法配置和硬件读回。人工暂停保留累计、清除轨迹并冻结自适应反馈；解除后按正常帧和空场确认恢复。静态ROM与动态BIST经过完整算法，相机和测试累计独立保存。

## 从源码重建

在本包根目录执行：

```powershell
python -I -X utf8 tools/verify_package.py
python -I -X utf8 tools/build_firmware.py
python -I -X utf8 tools/run_rtl_tests.py
```

首次重编译可先运行 tools/setup_compiler.ps1 安装配套 ARM 编译器；已有编译器可通过 ARM_CC 指定。RTL 工具可通过 VIVADO_BIN 指定。可设置AMD_ROOT、VIVADO_BIN和XSDB_EXE指定本机工具。ARM 重编译结果放 rebuild/firmware，配套 ELF 位于 console/build。完整 FPGA 构建入口为 tools/build_fpga.ps1，调用 Vivado 执行 tools/build_fpga.tcl，生成文件输出至 fpga/generated。相机1280×720采集，PL裁剪中间800×480；算法75MHz、AXI/HP0及VDMA互联100MHz、LCD像素25MHz。观察器负责实时预览。

控制台可在已安装 Python 依赖的环境直接执行 `python -I -X utf8 console/app.py`。工具路径支持环境变量配置。算法参数与结果映射见fpga/vision_registers.json，操作说明见console/算法功能.md。

## 本地检查

```powershell
python -I -X utf8 console/test_vision_v14.py
```

整链仿真覆盖逐像素裁剪、背压、动态阈值与去噪、三路并行、峰谷切分、轨迹事件、合并恢复、相关测速、四种动态BIST、配置/事件读回、显示快照与十进制计数。另含800×480四种静态ROM与四种动态图像源自检。800×480默认ROI的48帧整链动态BIST覆盖光照变化、噪声与粘连。检查结果见verification/。

第三方版权、原始许可证见 THIRD_PARTY_NOTICES.md 及各源文件。MANIFEST.json 记录每个文件的大小及 SHA256，用于核对交付文件。

## 离线标定

双击tools/offline_calibration/index.html，点击“载入当前版本800×480配置”，添加RGB图与黑白目标掩膜。检查通过后导出控制台算法场景，在控制台“FPGA算法 / 三路并行”页载入。参数提交后保持暂停；清空检测区，再点击“自动判遮挡”。采图、标注与字段映射见tools/offline_calibration/使用说明.md。
