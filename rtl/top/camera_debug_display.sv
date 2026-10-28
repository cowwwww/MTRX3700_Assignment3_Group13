// Store incoming grayscale pixels in two frame buffers and send them to VGA.
// Feed the same pixels to robot_core so dropped display frames do not stop control.
// The display shows grayscale video only. The line-position overlay still needs
// matching frame data and a connection across the camera and display clocks.
module camera_debug_display #(
 parameter integer W=320,H=240,H_FRONT=16,H_SYNC=96,H_BACK=48,V_FRONT=10,V_SYNC=2,V_BACK=33,
 parameter integer XW=$clog2(W),YW=$clog2(H),HW=$clog2(2*W+H_FRONT+H_SYNC+H_BACK),
 parameter integer VW=$clog2(2*H+V_FRONT+V_SYNC+V_BACK)
)(
 input logic cam_clk,video_clk,arst,pixel_valid,sof,eof,frame_abort,
 input logic [7:0] gray,
 input logic [XW-1:0] x,
 input logic [YW-1:0] y,
 output logic [7:0] red,green,blue,
 output logic hsync_n,vsync_n,blank_n,display_valid,
 output logic [HW-1:0] scan_x,
 output logic [VW-1:0] scan_y
);
 logic cam_reset,video_reset,read_enable,swap_boundary,read_valid,pending;
 logic [$clog2(W*H)-1:0] read_address;
 logic [7:0] read_gray;
 logic [15:0] dropped,displayed;
 reset_sync cr(.clk(cam_clk),.arst,.reset(cam_reset));
 reset_sync vr(.clk(video_clk),.arst,.reset(video_reset));
 vga_scanout #(.W(W),.H(H),.H_FRONT(H_FRONT),.H_SYNC(H_SYNC),.H_BACK(H_BACK),
  .V_FRONT(V_FRONT),.V_SYNC(V_SYNC),.V_BACK(V_BACK)) scan(
  .clk(video_clk),.reset(video_reset),.read_enable,.swap_boundary,.read_address,.hsync_n,.vsync_n,
  .active(blank_n),.scan_x,.scan_y);
 video_framebuffer #(.W(W),.H(H)) frames(
  .cam_clk,.cam_reset,.pixel_valid,.sof,.eof,.frame_abort,.gray,.x,.y,
  .display_clk(video_clk),.display_reset(video_reset),.swap_boundary,.read_enable,.read_address,
  .read_gray,.read_valid,.display_valid,.frame_pending(pending),.dropped_frames(dropped),.displayed_frames(displayed));
 always_comb begin
  red=(read_valid && blank_n && !arst) ? read_gray:8'b0;
  green=red;blue=red;
 end
endmodule
