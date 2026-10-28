# Validation and evidence plan

## Automated coverage

The C++ bench drives independent asynchronous clocks (control period 10 ticks,
camera period 14 ticks, integrated video period 22 ticks), samples complete frame features and independently
decodes UART 8N1 output. It runs unit and system functions under one compiled
test fixture to reduce clean-build time. A separate executable exercises the
default 320×240 robot_system and full 640×480 VGA frame. Four top-level lint runs
also elaborate the default dimensions. Standard run requires Verilator 5.050; local fallback requires an
explicit opt-in and never labels itself as exact-version compliance.

| Test group | Assertions |
|---|---|
| Safety | Reset stop, persistent latch, 600 event sequences, simultaneous stop/release |
| Motion | Saturation and sign at extreme signed inputs, unconditional inhibited zero |
| Curve fit | All 32³ centroid triples against independent rational interpolation |
| Divider | 220 random/zero denominator cases, exact 18-cycle standalone latency |
| UART | All 256 bytes at exact bit timing, abort at all 40 character-clock positions |
| Distance | Reset invalid, inclusive thresholds, consecutive clear samples, hysteresis interruption, invalid and timeout |
| Junction | New key, revisit, no repeated event per episode, exhausted branches, no choices, eviction |
| Vision | 36 independently modeled synthetic frames, both polarities, equality threshold, narrow/broad/split/random lines, pixel gaps, malformed coordinate |
| System | Camera-derived steering, atomic CDC, SW0 behavioural difference, decoded mock packet, release/freshness, line loss, frozen stream, missing distance, obstacle, priority, CDC overflow |
| Camera bytes | Gray8/RGB565/YUV422, byte orders, RGB weighting, format latch, pre-VSYNC discard, short/long/odd-byte lines, premature VSYNC and prompt control invalidation |
| Pending abort | Invalidate an in-flight divider result; no stale good packet, recover with fresh frames |
| Framebuffer | Every pixel of both banks, concurrent write/read without tearing, drop pending frames, malformed frames, explicit blanking swap, coordinated reset |
| VGA | All 2592 small raster positions with exact sync/blanking and 2x data; complete frame replacement and reset masking |
| Clock independence | Pause integrated display clock while camera/controller continue; pending display never blocks control or stop, then resume |
| Full-size system | Four raw 320×240 frames, counts up to 159 and centroids above 255, independent row sums, basic/advanced signed wheel outputs, frame IDs and emergency stop |
| Full-size VGA | All 420000 raster positions including 307200 active pixels; every RGB value, 2x scaling, 50400 low HS positions, 1600 low VS positions, whole-frame drop coherence |
| Image translation | All 81 shifts of a synthetic 16×16 patch; independent SAD/runner-up oracle, contrast/uniqueness/error gates, IDs, malformed load, busy isolation, reset and 65280 maximum score |
| Mutation | Change inhibited left wheel zero to one in disposable copy; require the intended assertion failure and CAUGHT |
| Runner rejection | Wrong simulator version returns nonzero; a prior PASS JSON is removed before the attempt so failed runs cannot reuse stale success |

Digital tests do not simulate optical noise, metastability, chassis inertia,
motor packet compatibility or physical remote range. Default-size functional
tests still use synthetic scenes, not hardware recordings. Virtual-pin system
synthesis is not a board fit. The standalone overlay has unit coverage but is
not part of the live display or full-size image comparison.

## Pitch targets retained (not yet finalized)

| Target | Proposed procedure | Conditions / threshold / goal / measured |
|---|---|---|
| T1 Line re-acquisition error (mm) | Three recoveries; greatest lateral offset from desired line | TBD with group after moving recovery exists |
| T2 Recovery time (s) | Three trials from obstacle trigger to stable tracking; maximum elapsed time | TBD; present stationary recovery does not satisfy the planned detour |
| T3 Camera-to-UART latency (ms) | Three scene changes; first changed frame to first actual command bit; maximum | TBD; use SignalTap and actual serial output |
| T4 Visual odometry error (mm) | Three known displacements; maximum absolute estimation error | Local pixel-shift kernel exists; metric VO/recordings/calibration and measurement still pending |

If VO does not become viable, select a genuine contribution-based accuracy or
repeatability target before the final datasheet. For example, a measured
curve-following lateral error could be proposed, but its conditions and limits
must come from the group and real testing. Do not copy example brief values.

## Hardware replay acquisition

Record `frame,x,y,gray` for valid camera pixels and a separate RTL feature CSV
with `frame,frame_good,row_valid,junction,far_x,mid_x,near_x,far_count,mid_count,near_count`.
Frame IDs must refer to the same captured frame; unwrap 16-bit rollover for a
long recording. Record dimensions, polarity, threshold, clock rates, FPGA source
hash/bitstream, date, capture method, camera settings and scene alongside data.
Never generate the recorded RTL CSV from the golden model.

The batch replay comparator expects complete frames, one SOF/EOF pair and no
coordinate faults. Malformed-stream behaviour is checked separately by the
cycle-level testbench; the batch model's counts are not intended to mimic
discarded malformed pixels. For hardware R7, record valid complete frames first.

```bash
python3 tools/compare_replay.py --pixels data/hardware/pixels.csv \
  --rtl data/hardware/rtl_features.csv --width 320 --height 240 --threshold 96
```

No hardware data currently exists in this project. Synthetic vectors are generated
under build/ and explicitly identified in test_results.json.
