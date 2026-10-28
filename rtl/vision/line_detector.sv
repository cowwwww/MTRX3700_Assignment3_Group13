// Find the line centre on three image rows. Gaps between valid pixels are allowed.
// SOF marks the first pixel and EOF marks the last pixel of a frame.
// Sample rows at H/4, 2*(H/4) and 3*(H/4), from farthest to nearest.
// Pixels must arrive in row order. Mark the results invalid if the frame is bad.
// Save the threshold and dark/bright setting at SOF and use them for the whole frame.
module line_detector #(
 parameter integer W=320,H=240,MIN_PIXELS=2,MAX_PIXELS=W/2,
 parameter integer XW=$clog2(W),YW=$clog2(H),SW=$clog2(W*W),CW=$clog2(W+1)
)(
 input logic clk,reset,pixel_valid,sof,eof,frame_abort,
 input logic [7:0] gray,threshold,
 input logic dark_line,
 input logic [XW-1:0] x,
 input logic [YW-1:0] y,
 output logic feature_valid,frame_good,
 output logic [2:0] row_valid,junction,
 output logic [3*XW-1:0] centroids,
 output logic [3*CW-1:0] counts,
 output logic [15:0] frame_id
);
 logic active,bad,have_end,polarity;
 logic [7:0] frame_threshold;
 logic [XW-1:0] expect_x;
 logic [YW-1:0] expect_y;
 logic [SW-1:0] sums[3];
 logic [CW-1:0] hits[3],runs[3];
 logic previous_dark[3];
 logic [2:0] div_busy,div_done,div_zero;
 logic [SW-1:0] quotients[3];
 logic [2:0] pending_valid,pending_junction;
 logic [3*CW-1:0] pending_counts;
 logic pending_good;
 logic [15:0] sequence_id;
 wire first_ok=sof && x==0 && y==0;
 wire ordered=(sof ? first_ok : active && x==expect_x && y==expect_y);
 wire last_ok=eof && x==XW'(W-1) && y==YW'(H-1);
 wire match_pixel=polarity ? gray<frame_threshold : gray>frame_threshold;
 wire close_frame=pixel_valid && eof;
 wire start_div=close_frame && !(|div_busy) && !have_end;
 genvar r;
 generate for(r=0;r<3;r=r+1) begin: divisions
  unsigned_divider #(.WIDTH(SW)) div(
   .clk,.reset,.start(start_div),.numerator(sums[r]),
   .denominator(SW'(hits[r])),.busy(div_busy[r]),.done(div_done[r]),
   .divide_by_zero(div_zero[r]),.quotient(quotients[r]));
 end endgenerate
 always_ff @(posedge clk) begin
  feature_valid<=0;
  if(reset) begin
   active<=0;bad<=0;have_end<=0;polarity<=1;frame_threshold<=96;
   expect_x<=0;expect_y<=0;pending_good<=0;pending_valid<=0;
   pending_junction<=0;pending_counts<=0;sequence_id<=0;frame_id<=0;
   frame_good<=0;row_valid<=0;junction<=0;centroids<=0;counts<=0;
   for(integer r=0;r<3;r=r+1) begin sums[r]<=0;hits[r]<=0;runs[r]<=0;previous_dark[r]<=0;end
  end else if(frame_abort) begin
   // Send an invalid result now, even if the previous division is still running.
   // Let that division finish. Clearing have_end stops its old result being sent.
   active<=0;bad<=1;have_end<=0;feature_valid<=1;frame_good<=0;
   row_valid<=0;junction<=0;centroids<=0;counts<=0;
   sequence_id<=sequence_id+1'b1;frame_id<=sequence_id+1'b1;
   for(integer r=0;r<3;r=r+1) begin sums[r]<=0;hits[r]<=0;runs[r]<=0;previous_dark[r]<=0;end
  end else begin
   if(pixel_valid) begin
    if(sof) begin
     active<=1; bad<=!first_ok; polarity<=dark_line;frame_threshold<=threshold;
     for(integer r=0;r<3;r=r+1) begin sums[r]<=0;hits[r]<=0;runs[r]<=0;previous_dark[r]<=0;end
    end else if(!ordered) bad<=1;
    if(x==XW'(W-1)) begin expect_x<=0;expect_y<=y+1'b1;end
    else begin expect_x<=x+1'b1;expect_y<=y;end
    if(active && !sof && ordered) begin
     for(integer r=0;r<3;r=r+1) begin
      if(y==YW'((r+1)*(H/4))) begin
       if(match_pixel) begin
        sums[r]<=sums[r]+SW'(x);hits[r]<=hits[r]+1'b1;
        if(!previous_dark[r]) runs[r]<=runs[r]+1'b1;
       end
       previous_dark[r]<=match_pixel;
      end
     end
    end
    if(eof) begin
     active<=0;
     if(start_div) begin
      have_end<=1;
      pending_good<=active && !bad && ordered && last_ok && !sof;
      sequence_id<=sequence_id+1'b1;
      for(integer r=0;r<3;r=r+1) begin
       pending_valid[r]<=hits[r]>=CW'(MIN_PIXELS) && hits[r]<=CW'(MAX_PIXELS) && runs[r]==1;
       pending_junction[r]<=runs[r]>1 || hits[r]>CW'(MAX_PIXELS);
       pending_counts[r*CW+:CW]<=hits[r];
      end
     end else bad<=1;
    end else if(x==XW'(W-1) && y==YW'(H-1)) begin bad<=1;active<=0;end
   end
   if(have_end && (&div_done)) begin
    feature_valid<=1;frame_good<=pending_good;row_valid<=pending_good ? pending_valid : 3'b0;
    junction<=pending_good ? pending_junction : 3'b0;counts<=pending_counts;
    frame_id<=sequence_id;have_end<=0;
    for(integer r=0;r<3;r=r+1) centroids[r*XW+:XW]<=quotients[r][XW-1:0];
   end
  end
 end
endmodule
