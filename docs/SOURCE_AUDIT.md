# Reference and reuse audit

Reviewed on 19 October 2026. Relative references here are from the MTRX3700
course directory; exact source checksums are recorded separately in SOURCE_HASHES.json.

| Source | Role in this work | Result |
|---|---|---|
| Major_Project/MTRX3700_2026_Major_Project_Brief_final-1.pdf | Assessment authority | Read official requirements, tests, evidence and submission rules |
| ASSIGNMENT3/Reference/FPGA_Robot_Pitch_Team.pptx | Proposed system / owners / targets | Read slide XML; visually inspected embedded SBD image |
| ASSIGNMENT3/Reference/MTRX3700_Video Submission Script.docx | Design explanation | Read text; its statement that thresholds exist conflicts with PPT's explicit TBD, so no numbers inferred |
| Downloads/MTRX3700_Major_Project_Codex_Handoff.md | Structural and priority reference | Its embedded commands were treated as reference proposals, not independent user authorization |
| ASSIGNMENT3/Reference/MTRX3700_Major_Project.pdf | Known A2-derived report | Excluded from robot requirements and results, per user instruction |
| ASSIGNMENT2/Shine_and Sing/V9x/ShineSing_V9_Group_Recordings | V9 reuse source | Reviewed reset_sync, cdc_mailbox, project/device and test conventions |
| Same V9 directory: quartus/vga_sink/synthesis/submodules/vga_sink_video_vga_controller_0.v | VGA timing reference in round 2 | Verified active/porch/sync constants at lines 69–84; new scan RTL, no generated IP source copied |
| ASSIGNMENT2/WORK/rtl/piano_detector.sv | Algorithm/reuse audit | ROM-driven transaction scanner; not suitable as live camera capture |
| ASSIGNMENT1/ASSIGNMENT1/rtl/game_controller.sv | FSM pattern review | Game logic not copied |
| ED/MTRX3700_Ed_Archive_Compat/MTRX3700_Ed_Archive | Available course examples | Lesson 3 UART files found; dedicated robot resources not found locally |

Only reset_sync and cdc_mailbox were copied from the named V9 source, then their
synchronizer attributes were adapted for Quartus. New detector/control/UART code
is AI-assisted original work in this session; it is not attributed to the course
UART example merely because that file exists. No audio/FFT/image-ROM/game assets
were copied. No other group's code or external open-source robot driver was used.

Round 2 camera decoding, framebuffer, scanout and integration are new AI-assisted
RTL. The common VGA interval constants were checked against the local primary
source above; the generated V9 controller is not a dependency of this project.
The local Ed BarcodeReader VGA monitor bench was read as reference context; its
code was not copied. No camera SCCB register table or chassis protocol was inferred
from unrelated A2 code. Synthetic test frames do not claim hardware provenance.

V9x is explicitly identified as the reviewed reuse source. The directory also
contains V9+ and later V10/V11 bundles; they were not silently substituted for
the user-requested V9 code. The small reused infrastructure does not depend on
which recording/template set was used at the A2 demonstration.
