# AI and engineering decision record

Tool: Codex, 19 October 2026. User requested starting the MTRX3700 Major Project
implementation, with output under ASSIGNMENT3/WORK and a system/progress report.
User explicitly identified the existing major-project report as reused A2 content.

This is an initial record, not the final required one-page statement. Preserve
the exported relevant chat separately for final submission. Every source marked
new in OWNERS.md is AI-assisted and requires the responsible student's review.

Decisions made this round:

1. Use streaming row statistics rather than A2's static image-ROM scanner. This
   accepts live valid-pixel timing without a frame buffer and leaves camera
   capture/configuration dependent on official resources.
2. Divide the three sums iteratively in parallel. This bounds division latency
   and avoids three large variable combinational dividers in the main path.
3. Cross feature packets after frame completion, reusing V9's request/ack mailbox.
   Detect producer overflow and require reset instead of silently losing data.
4. Keep all motion decisions and per-pixel work in RTL. The Nano interface remains
   an unimplemented relay adapter until its actual protocol is available.
5. Use conservative stationary recovery. No open-loop blind detour is presented
   as completed obstacle avoidance, and command integration is not called VO.

Errors/limitations found and addressed during verification:

- Quartus 18.1 rejected the implicit generate / inline genvar style and a unary
  negation adjacent to an int cast. Explicit generate/genvar and parentheses
  fixed synthesis portability; default-size elaboration and synthesis were rerun.
- Windows headers define legacy `near`/`far` macros. C++ test argument names were
  changed to near_x/far_x; this was a host build issue, not an FPGA defect.
- Quartus 18.1 does not accept `set_max_delay -datapath_only`. Constraints were
  rewritten with supported max/min delay commands and subsequently rechecked.
- Scope of virtual pins initially matched internal nodes or used QSF quoting
  that Quartus treated literally. Assignments were restricted to actual data
  ports; clock ports remain physical but unassigned because board mapping is absent.
- Review identified a stale distance clear-count hazard at a timeout/sample
  boundary. Fresh sequences now restart at one when faulted; timeout recovery
  is part of the regression. No physical safety result is inferred from it.
- Local Verilator package metadata says 5.48.0 and its binary prints an unknown
  development version. Exact 5.050 compliance remains unverified; scripts reject
  a mismatch by default rather than silently claiming the required version.

Validation uses an independently formulated Python batch model, C++ assertions
including exhaustive small curve cases, wire-level UART checks, disposable
RTL mutation and Quartus core resource/timing analysis. Hardware adapter inputs,
electrical connections, image calibration and mechanical behaviour remain open.

## Round 2 continuation

The user explicitly requested continuing implementation. A generic camera byte
adapter now handles three configurable formats; it does not invent an OV7670
register setup. The same capture stream feeds control and a separate live VGA
branch. Display ownership uses two frame banks and a request/ack handshake;
camera frames can be dropped by display without stalling camera/control.

The last pixel/EOF is delayed until the final HREF fall validates the line.
An overlong/partial last line therefore cannot first publish a good frame and
then report an error. Explicit frame_abort also cancels an in-progress divider
publication and transfers an invalid feature, rather than waiting for timeout.

Display RAM is never reset, preserving M10K inference. Valid flags mask it until
a whole frame is adopted at vertical blanking. A stopped-camera image may remain
visible; it is not proof of healthy control. A separate marker overlay is tested
but deliberately not wired to unrelated/latest feature packets: matching the
displayed frame and its features still needs a bank metadata design.

Verification work exposed a test-driver timing mistake: an extra control wait
held pixel_valid across two camera edges, duplicating pixels. Removing that wait
restored the intended one-pixel-per-camera-edge stimulus. Independent-clock
read/write tests, explicit swap checks and the default-size full image scoreboard
subsequently passed. A paused video clock was tested separately to demonstrate
that pending display ownership cannot block wheel control or emergency stop.

Default-size functional coverage now supplements lint and Quartus: four QVGA
raw frames, wide-coordinate/count statistics, signed control and all 420000 VGA
scan positions are checked. These are synthetic tests, not R7 real recordings.
Integrated fit uses 689 ALM and 152 M10K with unconstrained external I/O; no board
timing closure, final bitstream or physical safety result is claimed.

The later round-2 step adds a standalone local SAD translation kernel, with an
independent batch search oracle and all 81 displacement tests. It uses complete
ordered loads, snapshots frame IDs, masks uninitialized RAM, ignores unaccepted
busy writes and reports quality separately from result completion. The module
estimates image pixels only; no metric distance or rotation is inferred. Its
proposed owner follows the existing Pitch VO role, pending human confirmation.
It is not instantiated in robot_system and does not affect wheel commands.

Final packaging review identified that a failed new test invocation could leave
an older successful test_results.json. The runner now removes that file before
starting; an isolated wrong-version test verifies nonzero exit and removal.
The clean-copy regression is retained with its exact source snapshot separately
from the final delivery run after this script-only correction.
