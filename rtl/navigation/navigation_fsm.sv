// Stop when the line is lost. Resume after RECOVER_FRAMES usable frames in a row.
// This version waits for the line to return; it does not search for it.
// bypass=1 selects basic line following instead of the curve-based target.
// Connect the physical SW0 switch to bypass in the board wrapper.
module navigation_fsm #(
 parameter integer FRAME_TIMEOUT=5000000,RECOVER_FRAMES=3,BASE_SPEED=96
)(
 input logic clk,reset,stopped,stop_event,bypass,
 input logic feature_valid,frame_good,
 input logic [2:0] row_valid,
 input logic signed [15:0] basic_error,advanced_error,heading,
 input logic sensor_required,sensor_fault,obstacle,
 output logic inhibit,
 output logic signed [15:0] steering,
 output logic [7:0] speed,
 output logic [3:0] state
);
 localparam integer AW=$clog2(FRAME_TIMEOUT+1),RW=$clog2(RECOVER_FRAMES+1);
 logic [AW-1:0] age;
 logic [RW-1:0] good_frames;
 logic have_frame,usable;
 logic [2:0] saved_valid;
 logic saved_good;
 logic signed [15:0] saved_basic,saved_advanced,saved_heading;
 integer slowdown;
 // States: INIT 0, BASIC 1, ADVANCED 2, LINE_LOST 3, SENSOR_FAULT 4,
 // OBSTACLE_STOP 5, E_STOP 6. The checks below choose the state and whether to stop.
 always_comb begin
  usable=saved_good && (bypass ? saved_valid[2] : &saved_valid);
  slowdown=saved_heading<0 ? -(int'(saved_heading))/2 : int'(saved_heading)/2;
  if(slowdown>40) slowdown=40;
  state=0;inhibit=1;steering=0;speed=0;
  if(reset || stopped || stop_event) state=6;
  else if(sensor_required && sensor_fault) state=4;
  else if(sensor_required && obstacle) state=5;
  else if(!have_frame) state=0;
  else if(age>=AW'(FRAME_TIMEOUT) || !usable || good_frames<RW'(RECOVER_FRAMES)) state=3;
  else begin
   state=bypass ? 4'd1 : 4'd2;inhibit=0;
   steering=bypass ? saved_basic : saved_advanced;
   speed=bypass ? 8'(BASE_SPEED) : 8'(BASE_SPEED-slowdown);
  end
 end
 always_ff @(posedge clk) begin
  if(reset) begin
   age<=AW'(FRAME_TIMEOUT);good_frames<=0;have_frame<=0;
   saved_valid<=0;saved_good<=0;saved_basic<=0;saved_advanced<=0;saved_heading<=0;
  end else begin
   if(age<AW'(FRAME_TIMEOUT)) age<=age+1'b1;
   if(age>=AW'(FRAME_TIMEOUT) || stopped || stop_event ||
      (sensor_required && (sensor_fault || obstacle))) begin
    good_frames<=0;
    if(stopped || stop_event) have_frame<=0;
   end
   if(feature_valid) begin
    age<=0;saved_good<=frame_good;saved_valid<=row_valid;
    saved_basic<=basic_error;saved_advanced<=advanced_error;saved_heading<=heading;
    if(!stopped && !stop_event && !(sensor_required && (sensor_fault || obstacle))) begin
     have_frame<=1;
     if(frame_good && (bypass ? row_valid[2] : &row_valid)) begin
      // After a timeout, restart the good-frame count at one.
      if(age>=AW'(FRAME_TIMEOUT)) good_frames<=RW'(1);
      else if(good_frames<RW'(RECOVER_FRAMES)) good_frames<=good_frames+1'b1;
     end else good_frames<=0;
    end
   end
  end
 end
endmodule
