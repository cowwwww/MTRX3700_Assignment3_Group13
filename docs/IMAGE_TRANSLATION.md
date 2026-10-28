# Local image translation prototype

`rtl/vision/image_translation_sad.sv` is a standalone, synthesizable local
correspondence kernel. It is not connected to robot_system, does not estimate
metres or heading, and does not currently constitute complete visual odometry.
Its proposed reviewer is the Pitch VO owner; confirmation remains pending.

## Calculation and meaning

Default reference block is 16×16 gray8. The current-image search window is 24×24,
centred at the same nominal image location. Evaluate each displacement dx,dy in
[-4,+4] with the sum of absolute differences over all 256 reference pixels:

`SAD(dx,dy) = sum(abs(reference[y,x] - current[y+4+dy,x+4+dx]))`.

The lowest score wins; equal minima keep the first row-major candidate. A tie
also becomes the second-best score and therefore fails the default uniqueness
margin. Positive dx means the matching patch moved right in image coordinates;
positive dy means it moved down. These are pixels of the supplied arrays. If a
future extractor downsamples, record that scale explicitly. Image motion is not
the same as robot displacement or yaw.

Every completed search emits result_valid once. motion_valid additionally
requires best_sad≤256×20, second_sad−best_sad≥512, reference range≥32 and distinct
frame IDs. These quality parameters are engineering starting values. The result
also exposes both scores, contrast and at_search_boundary. A boundary match can
be numerically valid but may indicate motion outside the search range; a future
consumer must decide its policy using recordings. Do not use invalid results.

The single-patch translation assumption cannot distinguish rotation, changing
perspective/height, independently moving objects or poorly textured ground.
Confidence gates reject some failures but cannot prove a correct match. Metric
odometry needs calibrated geometry, multiple spatial observations, frame time,
outlier handling and validation on real recordings.

## Handshake and storage

All ports are synchronous to one processing clock. While load_ready is high,
write each array in ascending address order starting at zero. A write to address
zero starts/restarts that array's load; partial/out-of-order loads leave ready
low. The two arrays can load in parallel. Invalid ordering must be repaired by
a complete reload from zero. RAM has no reset; ready masks uninitialized data.

`start && ready` accepts a job and snapshots both frame IDs. ready excludes any
simultaneous writes. While busy, load_ready is low and writes/start are ignored;
a producer must keep its own transaction until accepted. The arrays and result
IDs cannot be changed by unaccepted writes or live metadata changes. Completed
arrays can be reused, but reusing them is not evidence of new frames.

Use result_valid to consume dx/dy, quality and IDs atomically. Fields remain
held outside that event and must not be interpreted as a fresh measurement.
Synchronous reset cancels a job and invalidates both loaded arrays. Frame IDs
are 16-bit labels; 65535→0 is a distinct pair, but equality is rejected. The
module does not prove that caller-provided labels belong to captured frames.

Two synchronous RAM reads and one accumulation take two clocks per pixel.
After accepting start, completion takes 2×81×256+1 = **41,473 clocks**. At an
assumed 50 MHz this is 0.82946 ms of kernel compute time, excluding block
acquisition/loading/CDC. Default storage is 832 bytes; fitted M10K allocation is
reported separately in round2 evidence. Parameter experiments beyond N=16,R=4
have not received the same verification. N≥2 and R≥1 are required by widths.

## Verification and next integration

The separate C++ bench enumerates all 81 displacement vectors and compares
best/runner-up scores with an independent batch search. It checks flat scenes,
periodic ambiguity, unrelated frames, same-frame IDs, wraparound, invalid load
ordering, busy writes/metadata changes, reset cancellation, and maximum SAD
65280 without overflow. All images are synthetic.

Before connecting this to navigation:

1. Build an extractor that preserves a previous reference and a current search
   window from distinct complete frames, with exact source frame IDs and timing.
2. Validate extraction, dropped/aborted frames and processing deadlines. The
   present display bank handshake must not be treated as an automatic VO store.
3. Compare recorded real inputs against an independent model, tune rejection
   thresholds and measure failure cases before claiming usable image motion.
4. Only then design calibrated motion estimation and a validity-aware consumer.

The current robot control has no dependency on this prototype; its invalid or
missing output cannot affect motor commands.
