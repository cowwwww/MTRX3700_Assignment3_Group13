# Requirements and present evidence

> Historical Round2 matrix. The current V2 implementation/evidence matrix is in ../HANDOFF_V2_ZH.md. Physical demonstration and assessment evidence remain outstanding.

Authority: original Major Project brief, pages 3–7. The A2-derived major-project
report PDF is not used as a requirement, robot result or completed architecture.

| ID | Present implementation / evidence | Outstanding |
|---|---|---|
| R1 | Synthetic raw camera bytes decoded in RTL change wheel commands; default QVGA loop and live VGA tested | Actual OV7670 configuration/pins and witnessed physical camera-to-wheel loop |
| R2 | Signed turning/variable-speed commands, saturated mixer, generic uart_tx | Actual Nano/UGV02 driver and physical motion |
| R3 | Reset-to-stop latch; stop wins simultaneous release; system-level priority | Real IR decode/key mapping and physical stopped-wheel evidence |
| R4 | Byte capture, per-pixel processing, navigation and display in synthesizable RTL; integrated virtual-pin fit passes | Physical board implementation and evidence; Nano relay firmware |
| R5 | Four pitch target definitions preserved in validation plan | Group-approved conditions, thresholds/goals and three-trial measurements |
| R6 | Portable script, reduced and default-size module/system C++ benches, disposable mutation | Exact Verilator 5.050 clean-run certification; see evidence/round2 for local version |
| R7 | Independent Python batch model, synthetic RTL differential test, replay comparator | Recorded real-hardware pixels and independently captured matching RTL outputs |
| R8 | Every source listed with origin and provisional/pending ownership; image-shift kernel/bench proposed under Pitch VO owner | Group confirmation, student review/understanding and shared-file owners |
| R9 | SW0 logical bypass changes near-row control versus quadratic lookahead and speed | Physical switch adapter and measured difference on relevant target |

Neither Pass nor a higher achievement level is claimed. R1 and R2 require
hardware demonstration; new module count by itself does not establish a level.
