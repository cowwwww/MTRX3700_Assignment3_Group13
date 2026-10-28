# Integration contracts

See ARCHITECTURE.md for current widths, formulae, states and clock domains.

## robot_core inputs

| Port group | Producer obligation |
|---|---|
| clk, cam_clk, arst | Free-running clocks; assert global reset to both domains before stream/control use |
| pixel_valid / gray / x / y / sof / eof | Camera-clock synchronous, one complete in-order raster per frame; SOF/EOF on the first/last valid pixels, gaps allowed |
| frame_abort | Camera-clock pulse invalidating the current/in-progress frame; cancels pending good publication and sends an invalid feature event |
| threshold / dark_line | Camera-domain stable at SOF; core snapshots them for each frame |
| stop_event / release_event | Control-clock synchronous pulses from distinct decoded IR keys; stop must not be suppressed by held-key/repeat handling |
| bypass | Control-clock synchronized SW0; 1 = basic, 0 = quadratic lookahead |
| distance_sample / valid / mm | Control-clock atomic measurement event, validity and calibrated mm |
| sensor_required | Board configuration; 1 means missing/invalid/stale readings inhibit; simulation can use 0 while no sensor adapter exists |

There is no pixel ready/backpressure. Camera cannot wait for downstream logic.
Frame cadence must allow divider completion (default 17 camera clocks plus
publication) and mailbox acknowledgement before the next published result.
At default dimensions the raster itself easily exceeds this interval. A mailbox
overrun is latched as a fault instead of silently mixing or losing feature data.

## robot_core outputs

`motor_left/right` are continuously valid signed abstract targets. They are not
UART-encoded, not PWM duty cycles, and not m/s. `inhibited=1` guarantees both
values are zero at the core boundary. The physical UART adapter must prioritize
stop over periodic motion and must not replay old queued targets after release.

`debug_feature_valid` pulses once per transferred frame. All debug feature fields
are held coherently between pulses. The future packet logger/VGA overlay must
sample on that pulse and preserve the frame ID. `debug_junction` only indicates
multiple dark/bright runs or excessive width; it is not a stable junction ID.

## Generic uart_tx

Byte accepted on a rising control clock when valid && ready. Producer must hold
data and valid until acceptance. 8N1, LSB first, `CLKS_PER_BIT` clocks per bit.
Reset/abort discard an in-flight character and drive idle at the next clock.
Default 434 clocks is a configurable development setting, not a verified robot
baud requirement. Receiver resynchronization depends on the real protocol.

## camera_byte_capture and robot_system

`camera_data`, HREF and VSYNC must satisfy setup/hold relative to cam_clk. This
module samples bytes on rising cam_clk; it does not generate XCLK or configure
the sensor over SCCB. `VSYNC_ACTIVE_HIGH` is a compile-time polarity parameter.
The module waits for the active VSYNC edge after reset. HREF is active high and
is ignored while VSYNC is active.

`pixel_format` (0 gray8, 1 RGB565, 2 YUV422, 3 unsupported), `rgb_msb_first` and
`y_first` latch at that VSYNC edge. They must already be stable in the camera
domain; do not connect an asynchronous multi-bit switch bus directly. RGB565
expands 5/6/5 channels by bit replication and uses floor((R+2G+B)/4) grayscale.
YUV extracts one Y byte per two bytes, with Y-first or chroma-first selectable.
The choice is configurable infrastructure, not proof of the kit's format.

Each HREF line must contain exactly W complete pixels. Short/long/odd-byte
lines and premature VSYNC raise one abort and discard the rest of that frame.
After H complete lines, further bytes are ignored until the next VSYNC; the
adapter consumes the configured raster, not an automatic sensor-size detector.
Only the final pixel/EOF waits for HREF deassertion, so downstream consumers see
a gap before EOF. This prevents a malformed final line being accepted early.

`robot_system` adds video_clk and RGB8/HSn/VSn/blank_n outputs to the raw-camera
control wrapper. Pixel-clock forwarding, VGA sync-on-green conventions, board
DAC pins and any clock phase adjustment belong in the verified board wrapper.
`video_ready` is synchronous to video_clk and says one complete bank has been
adopted; it is not a camera freshness indication or a control-domain signal.

## Framebuffer and VGA

`video_framebuffer` accepts the same normalized camera stream with no ready.
Read address is linear y*W+x. A read enabled on a display clock produces gray
and `read_valid` after that edge. Consumers must ignore gray while read_valid=0.
`swap_boundary` must be asserted during blanking with reads disabled; the
provided scanout does this at (0,2*H). RAM is never cleared on reset; reset both
domains together to reset ownership. `frame_pending` and `dropped_frames` belong
to cam_clk, `display_valid` and `displayed_frames` to display_clk. Counters wrap
modulo 65536 and need their own CDC if exported elsewhere.

Display drops an incoming frame while the previous completed bank is waiting
for adoption. A corrupt/aborted in-progress frame never replaces the displayed
bank. A later abort cannot revoke a completed bank already handed off. There is
no requirement to show every camera frame. `vga_scanout` scales nearest-neighbour
by two and aligns sync, coordinates and blanking with the RAM's one-cycle read.
`debug_overlay` requires already paired same-frame centroids and synchronized
stop state from its caller; this pairing is not provided by the live display yet.

## Standalone junction_memory

`present` defines one junction episode; `request` asks for a decision only when
present. `key` must identify the same physical junction across revisits. Bits of
available are left=0, straight=1, right=2. Output choice is the selected bit index.
No choice when available=0; after one decision, present must drop before another.
All keys/history clear on reset. Default depth 8 uses round-robin replacement.
An optional VO/localization pipeline may supply an ID later; no ID fabrication
or junction steering is hidden inside this first version.

## Future obstacle recovery and VO

Obstacle recovery should consume distance validity/age, line features and an
explicit manoeuvre timeout. Its request must go through the same safety arbiter.
With VO invalid it must still have a bounded fallback. Present baseline only
stops and waits for fresh visible line/distance, so new moving states require
new system tests and physical clearances.

VO interface is a design reservation only: `(frame_id, dx, dy, dtheta, valid,
confidence, age)` with units/formats to be selected from real image recordings.
There is deliberately no synthesizable fake VO implementation.
