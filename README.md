# FPGA 传送带视觉计数系统：完整代码提交版 v1.2

本包包含当前固定机位整机工程的全部自主源代码、第三方 BSP/IP、约束、仿真、构建脚本，以及配套 bit/XSA/ELF 和 Windows 控制台入口。无技术报告 PDF、现场照片、串口运行记录或历史旧工程。

## 文件入口

- console/控制台.exe：串口日志、相机预览、调框、手动遮挡与计数控制。须保留完整目录，依赖 Python 3、NumPy、Pillow、Tk 和 AMD Vitis/Vivado 2025.2。
- console/src/：ARM 裸机程序；默认手动暂停。邮箱协议 3，主循环处理 UART；常用按钮走已连接的 JTAG/DDR 控制邮箱，并核对实际生效状态。
- fpga/rtl、fpga/constraints、fpga/ip_repo、fpga/reference、fpga/create_project.tcl：完整 RTL、引脚约束、定制 IP、BD 参考和工程重建入口。
- bsp/：配套 ARM standalone BSP 头文件、库及库源码。
- fpga/sim/：RTL 仿真；tools/：完整性检查及独立重编译脚本。

## 运行与升级

先停带并关闭旧控制台和 SSCOM 串口，打开 console/控制台.exe，选择开发板串口，接好 JTAG 后点击“初始化开发板”。本次会下载 v1.2 并清零，默认保持暂停。只点连接不会升级，旧固件会明确拒绝。

清空两条检测框后点击“正常计数·手动无遮挡”；点击“暂停计数·有遮挡”只暂停计数，累计保留、视频继续。调框、取高清图或载入场景后保持暂停。自动遮挡依然使用原图像规则，背景亮度误判与粘连目标分离不是本版已解决问题。

## 从源码重建

在本包根目录执行：

```powershell
python -I -X utf8 tools/verify_package.py
python -I -X utf8 tools/build_firmware.py
python -I -X utf8 tools/run_rtl_tests.py
```

ARM 编译器可通过 ARM_CC 指定；RTL 工具可通过 VIVADO_BIN 指定。默认 AMD 安装路径 D:/vivado/2025.2。ARM 重编译结果放 rebuild/firmware，不覆盖封存 ELF。完整 FPGA 构建入口为 tools/build_fpga.tcl，使用 Vivado 运行；不自动下载开发板。硬件历史名称含 follow，但当前 ARM 程序未启用自动跟随；观察器用于相机预览。

控制台可在已安装 Python 依赖的环境直接执行 `python -I -X utf8 console/app.py`。GUI 的 XSDB/Python 路径采用本机默认安装位置，迁移电脑时应核对 console/controller.py、transport.py、run_control.tcl 和 Launcher.cs 的工具路径；所有源代码已提供。

## 本地检查与边界

```powershell
python -I -X utf8 console/test_firmware.py
python -I -X utf8 console/test_mailbox_controls.py
python -I -X utf8 console/test_controller.py
python -I -X utf8 console/test_ui.py
python -I -X utf8 console/test_poll_wiring.py
python -I -X utf8 console/test_launcher.py
```

实际 C 邮箱、控制分派、计数配置联合检查使用模拟 PL；Python 控制器测试使用模拟设备，界面测试使用隐藏 Tk 窗口。已完成 ARM 编译和这些本地检查，尚未把 v1.2 下载到真实开发板验收。不得把这些检查写作整机计数准确率。B/C 独立离线研究未接入当前整机，不属于本包已启用功能。

第三方版权、原始许可证见 THIRD_PARTY_NOTICES.md 及各源文件。MANIFEST.json 记录每个文件的大小及 SHA256；重新构建产生的目录不属于原封存交付。
