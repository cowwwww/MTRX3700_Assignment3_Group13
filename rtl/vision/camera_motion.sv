// Compare a small patch in consecutive camera frames, using the camera clock.
// Store two search areas, then copy the previous centre and current area to SAD.
// Capture can continue during matching. Drop a frame if it would overwrite
// data still being copied, or if matching has not finished by the next EOF.
// Outputs describe image pixels, not robot distance or position.
module camera_motion #(
 parameter integer W=320,H=240,N=16,R=4,S=N+2*R,
 parameter integer ROI_X=(W-S)/2,ROI_Y=(3*H/4)-S/2,
 parameter integer XW=$clog2(W),YW=$clog2(H),DW=$clog2(2*R+1)+1,
 parameter integer SW=$clog2(N*N*255+1),FRAME_TIMEOUT=5000000,
 parameter integer MAX_MEAN_ERROR=20,MIN_MARGIN=512,MIN_CONTRAST=32
)(
 input logic clk,reset,pixel_valid,sof,eof,frame_abort,
 input logic [7:0] gray,
 input logic [XW-1:0] x,
 input logic [YW-1:0] y,
 output logic busy,frame_dropped,
 output logic [15:0] dropped_frames,
 output logic result_valid,match_valid,at_search_boundary,
 output logic signed [DW-1:0] dx,dy,
 output logic [SW-1:0] best_sad,second_sad,
 output logic [7:0] contrast,
 output logic [15:0] reference_id,current_id
);
 localparam integer SP=S*S,NP=N*N,SA=$clog2(SP),RA=$clog2(NP);
 localparam integer AW=$clog2(FRAME_TIMEOUT+1);
 typedef enum logic [2:0] {IDLE,READ_PATCH,WRITE_PATCH,START_MATCH,WAIT_MATCH} state_t;
 state_t state;
 (* ramstyle="M10K" *) logic [7:0] memory0[0:SP-1];
 (* ramstyle="M10K" *) logic [7:0] memory1[0:SP-1];
 logic write_bank,previous_bank,pair_previous_bank,pair_current_bank;
 logic have_previous,active,bad;
 logic [XW-1:0] expected_x;
 logic [YW-1:0] expected_y;
 logic [15:0] sequence_id,frame_id,previous_id,pair_previous_id,pair_current_id;
 logic [AW-1:0] age;
 logic [SA-1:0] copy_index;
 logic [SA-1:0] capture_address,reference_address,search_address;
 logic [7:0] reference_pixel,search_pixel;
 logic sad_ready,sad_load_ready,sad_busy;
 wire copying=state==READ_PATCH || state==WRITE_PATCH;
 wire in_patch=int'(x)>=ROI_X && int'(x)<ROI_X+S &&
               int'(y)>=ROI_Y && int'(y)<ROI_Y+S;
 wire ordered=sof ? (x==0 && y==0) :
                    (active && x==expected_x && y==expected_y);
 wire capture_ok=pixel_valid && ordered && !frame_abort && !reset;
 assign busy=state!=IDLE || sad_busy;

 // These checks catch an impossible patch size before a simulation starts.
 initial begin
  if(N<2 || R<1 || ROI_X<0 || ROI_Y<0 || ROI_X+S>W || ROI_Y+S>H)
   $fatal(1,"camera_motion patch must fit inside the frame");
  if(FRAME_TIMEOUT<2) $fatal(1,"camera_motion timeout must be at least two clocks");
 end

 always_comb begin
  capture_address=SA'((int'(y)-ROI_Y)*S+int'(x)-ROI_X);
  reference_address=SA'(int'(copy_index)<NP ?
                     (int'(copy_index)/N+R)*S+int'(copy_index)%N+R : 0);
  search_address=copy_index;
 end
 // Each RAM bank has one write port and one clocked read port.
 logic [7:0] read0,read1;
 logic [SA-1:0] read_address0,read_address1;
 always_comb begin
  read_address0=pair_previous_bank ? search_address:reference_address;
  read_address1=pair_previous_bank ? reference_address:search_address;
  reference_pixel=pair_previous_bank ? read1:read0;
  search_pixel=pair_current_bank ? read1:read0;
 end
 always_ff @(posedge clk) begin
  if(capture_ok && in_patch && !copying && (sof || !bad)) begin
   if(write_bank) memory1[capture_address]<=gray;
   else memory0[capture_address]<=gray;
  end
  if(state==READ_PATCH) begin
   read0<=memory0[read_address0];
   read1<=memory1[read_address1];
  end
 end
 image_translation_sad #(.N(N),.R(R),.MAX_MEAN_ERROR(MAX_MEAN_ERROR),
  .MIN_MARGIN(MIN_MARGIN),.MIN_CONTRAST(MIN_CONTRAST)) matcher(
  .clk,.reset,
  .reference_write(state==WRITE_PATCH && sad_load_ready && int'(copy_index)<NP),
  .search_write(state==WRITE_PATCH && sad_load_ready),
  .reference_address(RA'(copy_index)),.search_address(copy_index),
  .reference_gray(reference_pixel),.search_gray(search_pixel),
  .start(state==START_MATCH),.reference_frame_id(pair_previous_id),
  .current_frame_id(pair_current_id),.load_ready(sad_load_ready),.ready(sad_ready),
  .busy(sad_busy),.result_valid,.motion_valid(match_valid),.at_search_boundary,
  .dx,.dy,.best_sad,.second_sad,.reference_contrast(contrast),
  .result_reference_id(reference_id),.result_current_id(current_id));

 always_ff @(posedge clk) begin
  frame_dropped<=0;
  if(reset) begin
   state<=IDLE;write_bank<=0;previous_bank<=0;have_previous<=0;
   pair_previous_bank<=0;pair_current_bank<=0;copy_index<=0;
   active<=0;bad<=0;expected_x<=0;expected_y<=0;
   sequence_id<=0;frame_id<=0;previous_id<=0;pair_previous_id<=0;pair_current_id<=0;
   age<=0;dropped_frames<=0;
  end else begin
   case(state)
    READ_PATCH: state<=WRITE_PATCH;
    WRITE_PATCH: if(sad_load_ready) begin
     if(copy_index==SA'(SP-1)) state<=START_MATCH;
     else begin copy_index<=copy_index+1'b1;state<=READ_PATCH;end
    end
    START_MATCH: if(sad_ready) state<=WAIT_MATCH;
    WAIT_MATCH: if(result_valid) state<=IDLE;
    default: begin end
   endcase

   // A missing camera frame breaks continuity once, rather than every clock.
   if(age<AW'(FRAME_TIMEOUT)) age<=age+1'b1;
   if(age==AW'(FRAME_TIMEOUT-1)) begin
    active<=0;have_previous<=0;bad<=1;
    frame_dropped<=1;dropped_frames<=dropped_frames+1'b1;
   end
   if(frame_abort) begin
    active<=0;have_previous<=0;bad<=1;age<=0;
    frame_dropped<=1;dropped_frames<=dropped_frames+1'b1;
   end else if(pixel_valid) begin
    if(sof) begin
     sequence_id<=sequence_id+1'b1;frame_id<=sequence_id+1'b1;
     active<=1;bad<=!ordered;age<=0;
     if(active) begin
      have_previous<=0;frame_dropped<=1;dropped_frames<=dropped_frames+1'b1;
     end
    end else if(!ordered) bad<=1;
    if(in_patch && copying) bad<=1;
    if(x==XW'(W-1)) begin expected_x<=0;expected_y<=y+1'b1;end
    else begin expected_x<=x+1'b1;expected_y<=y;end
    if(eof || (x==XW'(W-1) && y==YW'(H-1))) begin
     active<=0;
     if(!eof || !active || sof || bad || !ordered ||
        x!=XW'(W-1) || y!=YW'(H-1) || state!=IDLE ||
        age>=AW'(FRAME_TIMEOUT-1) || (in_patch && copying)) begin
      have_previous<=0;frame_dropped<=1;dropped_frames<=dropped_frames+1'b1;
     end else begin
      if(have_previous) begin
       pair_previous_bank<=previous_bank;pair_current_bank<=write_bank;
       pair_previous_id<=previous_id;pair_current_id<=frame_id;
       copy_index<=0;state<=READ_PATCH;
      end
      previous_bank<=write_bank;write_bank<=!write_bank;
      previous_id<=frame_id;have_previous<=1;
     end
    end
   end
  end
 end
endmodule
