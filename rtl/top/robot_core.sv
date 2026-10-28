// Connect line detection, steering and stop checks.
// The camera input must provide grayscale pixels in row order.
// IR decoding, SW0 debounce, ultrasonic timing and chassis commands are separate.
// This module has no physical board pin assignments.
module robot_core #(
 parameter integer W=320,H=240,XW=$clog2(W),YW=$clog2(H),CW=$clog2(W+1),
 parameter integer FRAME_TIMEOUT=5000000,DISTANCE_TIMEOUT=5000000,RECOVER_FRAMES=3
)(
 input logic clk,cam_clk,arst,
 input logic pixel_valid,sof,eof,frame_abort,
 input logic [7:0] gray,threshold,
 input logic dark_line,
 input logic [XW-1:0] x,
 input logic [YW-1:0] y,
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
 localparam integer FW=16+3*CW+3*XW+7;
 logic reset,cam_reset,feature_valid,frame_good,busy;
 logic [2:0] row_valid,junction;
 logic [3*XW-1:0] centroids;
 logic [3*CW-1:0] counts;
 logic [15:0] frame_id;
 logic [FW-1:0] payload;
 logic cam_overrun;
 (* altera_attribute="-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS", preserve *) logic [1:0] overrun_sync;
 logic signed [15:0] basic_error,advanced_error,heading,curvature,steering;
 logic [7:0] speed;
 logic obstacle,sensor_fault,nav_inhibit;
 reset_sync control_reset(.clk,.arst,.reset);
 reset_sync camera_reset(.clk(cam_clk),.arst,.reset(cam_reset));
 line_detector #(.W(W),.H(H)) detector(
  .clk(cam_clk),.reset(cam_reset),.pixel_valid,.sof,.eof,.frame_abort,.gray,.threshold,.dark_line,.x,.y,
  .feature_valid,.frame_good,.row_valid,.junction,.centroids,.counts,.frame_id);
 always_ff @(posedge cam_clk or posedge cam_reset)
  if(cam_reset) cam_overrun<=0;
  else if(feature_valid && busy) cam_overrun<=1;
 always_ff @(posedge clk or posedge reset)
  if(reset) overrun_sync<=0; else overrun_sync<={overrun_sync[0],cam_overrun};
 assign cdc_fault=overrun_sync[1];
 cdc_mailbox #(.WIDTH(FW)) features_crossing(
  .src_clk(cam_clk),.src_reset(cam_reset),.src_valid(feature_valid),
  .src_data({frame_id,counts,centroids,junction,row_valid,frame_good}),.src_busy(busy),
  .dst_clk(clk),.dst_reset(reset),.dst_accept(1'b1),.dst_data(payload),.dst_valid(debug_feature_valid));
 assign {debug_frame_id,debug_counts,debug_centroids,debug_junction,debug_row_valid,debug_frame_good}=payload;
 safety_stop safety(.clk,.reset,.stop_event,.release_event,.stopped);
 curve_fit #(.W(W)) fit(.centroids(debug_centroids),.basic_error,.advanced_error,.heading,.curvature);
 distance_guard #(.TIMEOUT_CYCLES(DISTANCE_TIMEOUT)) range_guard(
  .clk,.reset,.sample(distance_sample),.valid(distance_valid),.distance_mm,.blocked(obstacle),.fault(sensor_fault));
 navigation_fsm #(.FRAME_TIMEOUT(FRAME_TIMEOUT),.RECOVER_FRAMES(RECOVER_FRAMES)) navigation(
  .clk,.reset,.stopped,.stop_event,.bypass,.feature_valid(debug_feature_valid),
  .frame_good(debug_frame_good && !cdc_fault),.row_valid(debug_row_valid),
  .basic_error,.advanced_error,.heading,.sensor_required,.sensor_fault,.obstacle,
  .inhibit(nav_inhibit),.steering,.speed,.state(nav_state));
 assign inhibited=arst || reset || nav_inhibit || cdc_fault;
 motion_control motor_mixer(.inhibit(inhibited),.steering,.speed,.left(motor_left),.right(motor_right));
endmodule
