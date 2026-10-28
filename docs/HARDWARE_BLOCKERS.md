# Hardware integration dependencies

> Historical Round2 record. Official 2026 sources have now been supplied and integrated in V2. See ../HANDOFF_V2_ZH.md for remaining physical validation and assessment evidence. The original V1 files remain unchanged.

Local search on 19 October 2026 covered ASSIGNMENT3/Reference, Major_Project,
ED sourcebook/archive and prior assignment sources. The local Ed archive contains
Lesson 3 UART examples and A2 image/audio exercises. The dedicated Major Project
Resources (official robot pin map, device models and relay software) were not
located. This does not establish whether they are available on live Ed.

| Needed input | Why it blocks physical integration | Prepared interface |
|---|---|---|
| Robot adaptor QSF/schematic and official self-test | Establish approved pin/electrical mapping | Core has no physical GPIO assignments |
| OV7670 SCCB register script, format and timing model | Confirm RGB565/YUV, byte order, clocking, mirror, active sync levels | Configurable byte capture now implemented; settings still unverified |
| Camera/video PLL and VGA DAC pin/timing specification | Establish real sampling edges, clocks and output delays | Live double-buffered grayscale VGA at assumed 25 MHz |
| Nano firmware and UGV02 UART command specification | Confirm baud, encoding, speed units, checksum, stop semantics and acknowledgement/watchdog | Signed left/right abstract commands and uart_tx |
| IR receiver/decoder and remote key codes | A logical event test is not proof of physical remote emergency stop | stop_event / release_event, separate keys |
| RCWL-1601 official trigger/echo adapter and sensor connection | Establish timing, usable range and invalid readings | sample / valid / distance_mm |
| Physical line colour/width, camera mount and track geometry | Validate threshold, centroids, sign, camera scale and safe speed | Parameterized dimensions, polarity, threshold and control constants |
| Real pixel/feature captures | Official R7 requires real-hardware replay | CSV formats + independent reference comparison |

The official brief specifies 3.3 V ultrasonic devices, checking polarity,
not connecting adaptor J5 3V3 to chassis, and retaining the Plexiglas cover.
Run the official kit self-test and confirm remote stop before driving, as required
by the brief. No device has been programmed by this work.

## Physical stop has a separate transport requirement

The logical motor command is zero on stop and stays zero. A UART serializer can
already have transmitted part of a movement command. The official parser's
resynchronization and chassis watchdog behaviour must determine whether it is
safe to abort, finish or supersede a packet. The invented test protocol supports
abort + idle + zero packet, but that is **not** evidence of UGV02 stop latency.
Measure remote-to-wheel stop with the actual firmware before enabling motion.

## Next board integration sequence

1. Import the official self-test into a separate board wrapper project and keep
   its original source attribution. Prove each hardware endpoint independently.
2. Configure the camera and bind its raw data/HREF/VSYNC to camera_byte_capture,
   or use the official capture with robot_core's normalized raster contract.
   Validate pixel/byte order with the live grayscale VGA. Capture one frame with
   coordinates, pixel values and matching detector features.
3. Bind IR events and validate latched stop/release while motors are disabled.
4. Bind the actual command serializer and establish zero-command priority,
   stale-command timeout and bounded stop transport latency.
5. With wheels lifted, check motor signs, scaling, camera orientation and SW0.
6. Perform low-speed line tests, then distance-stop tests, then measure targets.
7. Develop moving recovery/junction recognition only after this baseline works.
