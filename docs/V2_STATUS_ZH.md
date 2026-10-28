# V2 状态 — 2026-10-22

当前阶段：物理 FPGA 工程编译、内部时序和开发仿真完成，等待实体 bring-up。

入口 `../board/quartus/robot_board.qpf`；操作说明 `../README_V2_ZH.md`；实体测试记录 `V2_HARDWARE_TEST_RECORD.csv`。

- Quartus 18.1 完整编译 0 errors，74 条普通 warnings；TimeQuest 0 errors / 0 warnings，报告所有工况 slack 为正。
- 133 个实际引脚，0 虚拟引脚；2060 ALM、2289 寄存器、156 M10K、2 PLL、0 DSP。
- 原有功能回归通过，mutation 被捕获；新增相机/底盘接口测试通过。当前原生 Verilator 版本未满足课程指定 5.050 的精确版本要求。
- `evidence/board/release_audit.json` 记录源码与 SOF 哈希、原 V1 RTL 一致性及官方文件一致性。
- 未连接、烧录或实测硬件；不得用仿真结果替代真实停止延迟、跟线效果、真实图像 replay 或标定位移误差。
- 图像位移输出仍为像素；完整里程计、路口探索、主动绕障尚未实现。

当前最先需要完成的工作是按 README 验证官方自测、相机画面、J3 距离、架空轮向和四种停车操作。通过后再进行地面跟线和参数标定。根目录旧 README 与旧 quartus 工程属于历史说明。
