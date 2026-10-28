# MTRX3700 Major Project — Group 13 robot system

> 本文为 V1/Round2 历史说明。V2 当前入口、编译与上板步骤请读 [README_V2_ZH.md](README_V2_ZH.md)，交接见 [HANDOFF_V2_ZH.md](HANDOFF_V2_ZH.md)。下文“板级待接入”等描述不代表 V2 最新状态。

本项目独立于 A2 ShineSing。当前是**已实现并测试的相机字节采集、FPGA 控制与实时 VGA
逻辑系统，板级适配待接入**，不是可直接下载到小车的完整工程。
最新系统结构和本轮状态见 `docs/ROUND2_PROGRESS_ZH.md`；第一轮版本保存在 `releases/`。

已经实现：实时灰度像素流的三行线检测、迭代质心计算、帧特征跨时钟传输、基础/二次曲线
前视跟踪、锁存急停、距离有效性/障碍停车、失线与图像超时停车、连续帧恢复、轮速饱和。
新增 gray8/RGB565/YUV422 字节采集、异常帧立即失效、双时钟整帧缓冲、2 倍 VGA 扫描。
`rtl/top/robot_system.sv` 用同一份采集流同时驱动控制和显示，显示丢帧不阻塞控制。
独立实现通用 UART 发射器和按路口 ID 索引的选择记忆。路口识别、移动绕障、完整 VO 尚未实现。
另有经过独立数值检查的局部 SAD 图像平移原型；输出仅为像素位移，尚未接相邻帧提取或导航。
质心叠加单元已单测，但尚未连接实时 VGA 的同帧特征配对。

`tb/mock_motor_packet.sv` 是**仅供仿真的协议**，不能接 Nano/UGV02。
官方摄像头配置、机器人接线、IR 键码、距离适配和底盘串口协议未在本地资料中找到。
`quartus/` 用虚拟数据引脚评估核心资源；没有机器人板级引脚映射，也没有可用 `.sof`。

## 从哪里读

- `docs/ROUND2_PROGRESS_ZH.md`：最新系统结构、完成程度、测试结果与下一步。
- `docs/ROUND1_PROGRESS_ZH.md`：第一轮历史记录，不能代表最新代码。
- `docs/ARCHITECTURE.md`：模块图、时钟、宽度、控制优先级与计算公式。
- `docs/INTERFACES.md`：各模块真实接口及后续接板约定。
- `docs/HARDWARE_BLOCKERS.md`：所缺资料、实车接入顺序、串口急停问题。
- `docs/REQUIREMENTS_MATRIX.md`：R1–R9 已有证据与缺口。
- `docs/VALIDATION_PLAN.md`：自动测试范围、目标定义与真实数据回放格式。
- `docs/IMAGE_TRANSLATION.md`：局部平移原型的计算、质量门控、接口和 VO 边界。
- `OWNERS.md`：按 Pitch 保留的拟归属、共享模块待定项与代码来源。
- `docs/evidence/round2/`：本轮执行日志、结果 JSON 和 Quartus 结果；上一级为第一轮历史证据。

## 标准自动测试

Linux / Ed 环境需要 Verilator **5.050**、C++ 编译器、make、Python 3（仅标准库）：

```bash
bash run_all_tests.sh
```

脚本检查版本，运行四个顶层的 full-size lint、模块/系统测试、默认 320×240 功能仿真、
完整 640×480 VGA 扫描检查和一次性故障注入。
正常代码必须通过；故意把停车时左轮命令从 0 改成 1 的副本必须失败并输出 `CAUGHT`。
任何编译错误、超时或意外通过均返回非零。总执行预算 295 秒。

本机只有 Python 包提供的本地开发 Verilator 构建，不能冒充 5.050。Windows 复现命令：

```powershell
python tools/run_tests.py `
  --native-root 'E:\USYD\USYD_2-2\MTRX3700\ASSIGNMENT2\WORK\.deps\verilator' `
  --zig 'E:\USYD\USYD_2-2\MTRX3700\ASSIGNMENT2\WORK\.deps\ziglang\zig.exe' `
  --allow-version-mismatch
```

依赖路径只用于已有本机工具，不是项目源码依赖。换电脑用标准命令即可。
测试生成文件在 `build/`；无需安装 NumPy。最终提交前仍必须在指定版本从干净副本运行。

## 完整逻辑系统综合与资源估算

```bash
python3 tools/create_quartus.py --top robot_system
cd quartus
quartus_map robot_system --read_settings_files=on --write_settings_files=off
quartus_fit robot_system --read_settings_files=on --write_settings_files=off
quartus_sta robot_system
```

使用 Cyclone V `5CSEMA5F31C6`（沿用已核查的 V9 器件型号）。clk 假设 50 MHz，cam_clk
假设 24 MHz，video_clk 假设 25 MHz。数据引脚为虚拟引脚、三个时钟未指定板级位置。
本轮完整逻辑系统使用 689 ALM、920 寄存器、152 M10K；未包含 PLL 和实际外设驱动。
也可选择 `robot_core`、`robot_camera_system`、`video_framebuffer` 或
`image_translation_sad` 做分层估算。
不要生成/下载这份估算工程的 bitstream；接板需官方配置和独立板级 wrapper。

## 真实回放

目前没有真实硬件录制。采集格式在 `data/README.md`。取得匹配的像素与 RTL 特征后：

```bash
python3 tools/compare_replay.py --pixels data/hardware/pixels.csv \
  --rtl data/hardware/rtl_features.csv --width 320 --height 240 --threshold 96
```

代码含本轮 AI 辅助生成内容。每位成员必须审核理解自己的模块及测试；组内尚未确认的
所有权不算 R8 完成。正式提交需附相关 AI 会话导出和 brief 要求的声明。
