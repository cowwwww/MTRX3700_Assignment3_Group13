// Connect camera byte capture to the robot control logic.
// Camera register setup, XCLK, IR decoding, chassis commands and board pins
// still need to be added using the supplied hardware details.
module robot_camera_system #(
 parameter integer W=320,H=240,XW=$clog2(W),CW=$clog2(W+1),VSYNC_ACTIVE_HIGH=1
)(
 input logic clk,cam_clk,arst,href,vsync,
 input logic [7:0] camera_data,threshold,
 input logic [1:0] pixel_format,
 input logic rgb_msb_first,y_first,dark_line,
 input logic stop_event,release_event,bypass,sensor_required,
 input logic distance_sample,distance_valid,
 input logic [15:0] distance_mm,
 output logic signed [15:0] motor_left,motor_right,
 output logic inhibited,stopped,cdc_fault,
 output logic [3:0] nav_state,
 output logic debug_feature_valid,debug_frame_good,
 output logic [2:0] debug_row_valid,debug_junction,
 output logic [3*XW-1:0] debug_centroids,
 output logic [3*CW-1:0] debug_counts,
 output logic [15:0] debug_frame_id
);
 logic camera_reset,pixel_valid,sof,eof,frame_abort;
 logic [7:0] gray;
 logic [XW-1:0] x;
 logic [$clog2(H)-1:0] y;
 reset_sync camera_reset_release(.clk(cam_clk),.arst,.reset(camera_reset));
 camera_byte_capture #(.W(W),.H(H),.VSYNC_ACTIVE_HIGH(VSYNC_ACTIVE_HIGH)) capture(
  .cam_clk,.reset(camera_reset),.href,.vsync,.data(camera_data),.pixel_format,.rgb_msb_first,.y_first,
  .pixel_valid,.sof,.eof,.frame_abort,.gray,.x,.y);
 robot_core #(.W(W),.H(H)) core(
  .clk,.cam_clk,.arst,.pixel_valid,.sof,.eof,.frame_abort,.gray,.threshold,.dark_line,.x,.y,
  .stop_event,.release_event,.bypass,.sensor_required,.distance_sample,.distance_valid,.distance_mm,
  .motor_left,.motor_right,.inhibited,.stopped,.cdc_fault,.nav_state,.debug_feature_valid,
  .debug_frame_good,.debug_row_valid,.debug_junction,.debug_centroids,.debug_counts,.debug_frame_id);
endmodule
