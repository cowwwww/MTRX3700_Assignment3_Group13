// Use the same camera pixels for motor control and the live VGA display.
// Camera setup, clock generation, IR and ultrasonic decoding, board pins and
// Nano/UGV02 command formatting still need to be connected and checked.
module robot_system #(
 parameter integer W=320,H=240,XW=$clog2(W),CW=$clog2(W+1),VSYNC_ACTIVE_HIGH=1,
 parameter integer MOTION_N=16,MOTION_R=4,
 parameter integer MOTION_MAX_MEAN_ERROR=20,MOTION_MIN_MARGIN=512,MOTION_MIN_CONTRAST=32,
 parameter integer MOTION_TIMEOUT=5000000,
 parameter integer MOTION_X=(W-MOTION_N-2*MOTION_R)/2,
 parameter integer MOTION_Y=3*H/4-(MOTION_N+2*MOTION_R)/2,
 parameter integer H_FRONT=16,H_SYNC=96,H_BACK=48,V_FRONT=10,V_SYNC=2,V_BACK=33
)(
 input logic clk,cam_clk,video_clk,arst,href,vsync,
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
 output logic [15:0] debug_frame_id,
 output logic [7:0] vga_red,vga_green,vga_blue,
 output logic vga_hsync_n,vga_vsync_n,vga_blank_n,video_ready,
 // Motion debug outputs use cam_clk. Synchronize them before using another clock.
 output logic motion_result_valid,motion_accepted,motion_rejected,motion_tracking_valid,
 output logic motion_continuity_lost,motion_overflow,motion_boundary,motion_busy,
 output logic signed [15:0] motion_dx,motion_dy,
 output logic signed [31:0] motion_total_x,motion_total_y,
 output logic [15:0] motion_reference_id,motion_current_id,motion_dropped_frames,
 output logic [$clog2(MOTION_N*MOTION_N*255+1)-1:0] motion_best_sad,motion_second_sad,
 output logic [7:0] motion_contrast
);
 logic camera_reset,pixel_valid,sof,eof,frame_abort;
 logic [7:0] gray;
 logic [XW-1:0] x;
 logic [$clog2(H)-1:0] y;
 logic [$clog2(2*W+H_FRONT+H_SYNC+H_BACK)-1:0] scan_x;
 logic [$clog2(2*H+V_FRONT+V_SYNC+V_BACK)-1:0] scan_y;
 reset_sync camera_reset_release(.clk(cam_clk),.arst,.reset(camera_reset));
 camera_byte_capture #(.W(W),.H(H),.VSYNC_ACTIVE_HIGH(VSYNC_ACTIVE_HIGH)) capture(
  .cam_clk,.reset(camera_reset),.href,.vsync,.data(camera_data),.pixel_format,.rgb_msb_first,.y_first,
  .pixel_valid,.sof,.eof,.frame_abort,.gray,.x,.y);
 robot_core #(.W(W),.H(H)) core(
  .clk,.cam_clk,.arst,.pixel_valid,.sof,.eof,.frame_abort,.gray,.threshold,.dark_line,.x,.y,
  .stop_event,.release_event,.bypass,.sensor_required,.distance_sample,.distance_valid,.distance_mm,
  .motor_left,.motor_right,.inhibited,.stopped,.cdc_fault,.nav_state,.debug_feature_valid,
  .debug_frame_good,.debug_row_valid,.debug_junction,.debug_centroids,.debug_counts,.debug_frame_id);
 camera_debug_display #(.W(W),.H(H),.H_FRONT(H_FRONT),.H_SYNC(H_SYNC),.H_BACK(H_BACK),
  .V_FRONT(V_FRONT),.V_SYNC(V_SYNC),.V_BACK(V_BACK)) display(
  .cam_clk,.video_clk,.arst,.pixel_valid,.sof,.eof,.frame_abort,.gray,.x,.y,
  .red(vga_red),.green(vga_green),.blue(vga_blue),.hsync_n(vga_hsync_n),.vsync_n(vga_vsync_n),
  .blank_n(vga_blank_n),.display_valid(video_ready),.scan_x,.scan_y);
 // Motion is for measurement only until camera geometry has been calibrated.
 // It does not change the motor commands or delay the line-following path.
 localparam integer MDW=$clog2(2*MOTION_R+1)+1;
 logic signed [MDW-1:0] pixel_dx,pixel_dy;
 logic motion_match_valid,motion_frame_dropped;
 assign motion_dx=16'(pixel_dx);
 assign motion_dy=16'(pixel_dy);
 camera_motion #(.W(W),.H(H),.N(MOTION_N),.R(MOTION_R),.ROI_X(MOTION_X),.ROI_Y(MOTION_Y),
  .MAX_MEAN_ERROR(MOTION_MAX_MEAN_ERROR),.MIN_MARGIN(MOTION_MIN_MARGIN),
  .MIN_CONTRAST(MOTION_MIN_CONTRAST),.FRAME_TIMEOUT(MOTION_TIMEOUT)) motion(
  .clk(cam_clk),.reset(camera_reset),.pixel_valid,.sof,.eof,.frame_abort,.gray,.x,.y,
  .busy(motion_busy),.frame_dropped(motion_frame_dropped),.dropped_frames(motion_dropped_frames),
  .result_valid(motion_result_valid),.match_valid(motion_match_valid),.at_search_boundary(motion_boundary),
  .dx(pixel_dx),.dy(pixel_dy),.best_sad(motion_best_sad),.second_sad(motion_second_sad),
  .contrast(motion_contrast),.reference_id(motion_reference_id),.current_id(motion_current_id));
 motion_result #(.DW(MDW),.TIMEOUT_CYCLES(MOTION_TIMEOUT)) motion_status(
  .clk(cam_clk),.reset(camera_reset),.result_valid(motion_result_valid),.match_valid(motion_match_valid),
  .at_search_boundary(motion_boundary),.frame_dropped(motion_frame_dropped),
  .dx(pixel_dx),.dy(pixel_dy),.reference_id(motion_reference_id),.current_id(motion_current_id),
  .accepted(motion_accepted),.rejected(motion_rejected),.tracking_valid(motion_tracking_valid),
  .continuity_lost(motion_continuity_lost),.overflow(motion_overflow),
  .total_x(motion_total_x),.total_y(motion_total_y));
endmodule
