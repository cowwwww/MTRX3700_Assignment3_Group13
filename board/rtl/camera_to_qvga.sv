// V2 shared board adapter. AI-assisted; owner pending. Official SCCB setup emits
// 640x480 RGB565 MSB first. Register pins on the rising PCLK edge as hwtest does,
// validate complete raw lines, then retain odd x/odd y pixels for QVGA.
module camera_to_qvga #(
 parameter integer RAW_W=640,RAW_H=480,XW=$clog2(RAW_W/2),YW=$clog2(RAW_H/2)
)(
 input logic pclk,reset,href,vsync,
 input logic [7:0] data,
 output logic pixel_valid,sof,eof,frame_abort,
 output logic [7:0] gray,
 output logic [XW-1:0] x,
 output logic [YW-1:0] y
);
 logic href_q,vsync_q;
 logic [7:0] data_q,raw_gray;
 logic raw_valid,raw_sof,raw_eof;
 logic [$clog2(RAW_W)-1:0] raw_x;
 logic [$clog2(RAW_H)-1:0] raw_y;
 // The official project's FAST_INPUT_REGISTER assignments place these at pins.
 always_ff @(posedge pclk) begin href_q<=href;vsync_q<=vsync;data_q<=data;end
 camera_byte_capture #(.W(RAW_W),.H(RAW_H)) capture(
  .cam_clk(pclk),.reset,.href(href_q),.vsync(vsync_q),.data(data_q),
  .pixel_format(2'd1),.rgb_msb_first(1'b1),.y_first(1'b1),
  .pixel_valid(raw_valid),.sof(raw_sof),.eof(raw_eof),.frame_abort,.gray(raw_gray),.x(raw_x),.y(raw_y));
 always_comb begin
  pixel_valid=raw_valid && raw_x[0] && raw_y[0] && !reset;
  sof=pixel_valid && raw_x==1 && raw_y==1;
  eof=pixel_valid && raw_eof;
  gray=raw_gray;x=XW'(raw_x>>1);y=YW'(raw_y>>1);
 end
endmodule
