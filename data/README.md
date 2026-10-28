# Replay data

There are currently **no recorded hardware inputs** in this directory.
The test runner generates explicitly synthetic fixtures in build/.

For eventual R7 evidence, place genuine captures under data/hardware/ with:

- pixels.csv: frame,x,y,gray, one row for each valid camera pixel.
- rtl_features.csv: frame,frame_good,row_valid,junction,far_x,mid_x,near_x,far_count,mid_count,near_count.
- metadata.json: date, capture source/method, board source hash and bitstream,
  image width/height, polarity, threshold, camera configuration, clock rates,
  track conditions, hardware=true, and identity of the person recording it.

Use decimal integers; unwrap frame IDs across 65535→0. Keep all pixels in order.
The RTL output file must be captured from FPGA outputs or from a separate RTL
replay run using the recorded inputs, never manufactured by the golden model.
The original recording and its provenance must be retained either way.
