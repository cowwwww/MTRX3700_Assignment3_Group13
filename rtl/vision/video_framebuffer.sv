// Use two grayscale frame buffers: write one while displaying the other.
// Switch the displayed buffer only at swap_boundary, during vertical blanking.
// If a finished frame is still waiting for display, drop incoming frames whole.
// The live camera cannot be paused by this module.
// Reset both clock domains together. RAM is not cleared; display_valid hides old data.
module video_framebuffer #(
 parameter integer W=320,H=240,XW=$clog2(W),YW=$clog2(H),AW=$clog2(W*H)
)(
 input logic cam_clk,cam_reset,pixel_valid,sof,eof,frame_abort,
 input logic [7:0] gray,
 input logic [XW-1:0] x,
 input logic [YW-1:0] y,
 input logic display_clk,display_reset,swap_boundary,read_enable,
 input logic [AW-1:0] read_address,
 output logic [7:0] read_gray,
 output logic read_valid,display_valid,frame_pending,
 output logic [15:0] dropped_frames,displayed_frames
);
 localparam integer MW=$clog2(2*W*H);
 (* ramstyle="M10K" *) logic [7:0] memory[0:2*W*H-1];
 logic write_bank,published_bank,read_bank,request_toggle,ack_toggle;
 (* altera_attribute="-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS", preserve *) logic [1:0] ack_sync,request_sync;
 logic frame_active,bad;
 logic [XW-1:0] expect_x;
 logic [YW-1:0] expect_y;
 logic [MW-1:0] write_address,bank_read_address;
 wire accept_pixel=pixel_valid && !frame_abort && !cam_reset &&
                    ((sof && !frame_pending) || (!sof && frame_active));
 wire ordered=sof ? (x==0 && y==0) : (x==expect_x && y==expect_y);
 wire in_range=(int'(x)<W && int'(y)<H);
 always_comb begin
  write_address=MW'((write_bank ? W*H:0)+int'(y)*W+int'(x));
  bank_read_address=MW'((read_bank ? W*H:0)+int'(read_address));
 end
 // Use separate read and write clocks so Quartus can implement this as block RAM.
 always_ff @(posedge cam_clk)
  if(accept_pixel && ordered && in_range) memory[write_address]<=gray;
 always_ff @(posedge display_clk)
  if(read_enable && int'(read_address)<W*H) read_gray<=memory[bank_read_address];
 always_ff @(posedge cam_clk) begin
  if(cam_reset) begin
   write_bank<=1;published_bank<=1;request_toggle<=0;ack_sync<=0;
   frame_pending<=0;frame_active<=0;bad<=0;expect_x<=0;expect_y<=0;dropped_frames<=0;
  end else begin
   ack_sync<={ack_sync[0],ack_toggle};
   if(frame_pending && ack_sync[1]==request_toggle) begin
    frame_pending<=0;write_bank<=!write_bank;
   end
   if(frame_abort) begin
    if(frame_active) dropped_frames<=dropped_frames+1'b1;
    frame_active<=0;bad<=1;
   end else if(pixel_valid) begin
    if(sof) begin
     frame_active<=!frame_pending;bad<=!ordered || !in_range;
     if(frame_pending || frame_active) dropped_frames<=dropped_frames+1'b1;
    end else if(frame_active && (!ordered || !in_range)) bad<=1;
    if(accept_pixel) begin
     if(x==XW'(W-1)) begin expect_x<=0;expect_y<=y+1'b1;end
     else begin expect_x<=x+1'b1;expect_y<=y;end
     if(eof) begin
      frame_active<=0;
      if(!sof && !bad && ordered && x==XW'(W-1) && y==YW'(H-1)) begin
       published_bank<=write_bank;request_toggle<=!request_toggle;frame_pending<=1;
      end else dropped_frames<=dropped_frames+1'b1;
     end
    end
   end
  end
 end
 always_ff @(posedge display_clk) begin
  if(display_reset) begin
   read_bank<=0;request_sync<=0;ack_toggle<=0;
   display_valid<=0;read_valid<=0;displayed_frames<=0;
  end else begin
   request_sync<={request_sync[0],request_toggle};
   read_valid<=read_enable && display_valid && int'(read_address)<W*H;
   if(swap_boundary && request_sync[1]!=ack_toggle) begin
    read_bank<=published_bank;display_valid<=1;ack_toggle<=request_sync[1];
    displayed_frames<=displayed_frames+1'b1;
   end
  end
 end
endmodule
