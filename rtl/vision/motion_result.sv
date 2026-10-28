// Keep a diagnostic sum of accepted image shifts. These totals are not mm.
// Reject weak matches, search-edge matches and non-consecutive frame pairs.
// A lost frame or rejected match makes continuity_lost stay high until reset.
// Totals then contain only accepted shifts, not the motion during the gaps.
module motion_result #(
 parameter integer DW=5,TOTAL_WIDTH=32,TIMEOUT_CYCLES=5000000
)(
 input logic clk,reset,result_valid,match_valid,at_search_boundary,frame_dropped,
 input logic signed [DW-1:0] dx,dy,
 input logic [15:0] reference_id,current_id,
 output logic accepted,rejected,tracking_valid,continuity_lost,overflow,
 output logic signed [TOTAL_WIDTH-1:0] total_x,total_y
);
 localparam integer AW=$clog2(TIMEOUT_CYCLES+1);
 localparam logic signed [TOTAL_WIDTH:0] LIMIT_HIGH={2'b00,{(TOTAL_WIDTH-1){1'b1}}};
 localparam logic signed [TOTAL_WIDTH:0] LIMIT_LOW={2'b11,{(TOTAL_WIDTH-1){1'b0}}};
 logic [AW-1:0] age;
 logic seen_result;
 logic [15:0] last_id;
 logic signed [TOTAL_WIDTH:0] sum_x,sum_y;
 wire consecutive=current_id==16'(reference_id+16'd1);
 wire usable=match_valid && !at_search_boundary && consecutive;
 always_comb begin
  sum_x=(TOTAL_WIDTH+1)'(total_x)+(TOTAL_WIDTH+1)'(dx);
  sum_y=(TOTAL_WIDTH+1)'(total_y)+(TOTAL_WIDTH+1)'(dy);
 end
 initial begin
  if(TOTAL_WIDTH<DW || TIMEOUT_CYCLES<2) $fatal(1,"invalid motion_result parameters");
 end
 always_ff @(posedge clk) begin
  accepted<=0;rejected<=0;
  if(reset) begin
   total_x<=0;total_y<=0;overflow<=0;continuity_lost<=0;
   tracking_valid<=0;age<=0;seen_result<=0;last_id<=0;
  end else begin
   if(age<AW'(TIMEOUT_CYCLES)) age<=age+1'b1;
   if(age>=AW'(TIMEOUT_CYCLES-1)) begin
    tracking_valid<=0;continuity_lost<=1;
   end
   if(result_valid) begin
    seen_result<=1;last_id<=current_id;
    if(seen_result && reference_id!=last_id) continuity_lost<=1;
    if(usable) begin
     accepted<=1;age<=0;tracking_valid<=1;
     total_x<=sum_x>LIMIT_HIGH ? TOTAL_WIDTH'(LIMIT_HIGH):
              sum_x<LIMIT_LOW ? TOTAL_WIDTH'(LIMIT_LOW):TOTAL_WIDTH'(sum_x);
     total_y<=sum_y>LIMIT_HIGH ? TOTAL_WIDTH'(LIMIT_HIGH):
              sum_y<LIMIT_LOW ? TOTAL_WIDTH'(LIMIT_LOW):TOTAL_WIDTH'(sum_y);
     if(sum_x>LIMIT_HIGH || sum_x<LIMIT_LOW || sum_y>LIMIT_HIGH || sum_y<LIMIT_LOW) begin
      overflow<=1;continuity_lost<=1;
     end
    end else begin
     rejected<=1;tracking_valid<=0;continuity_lost<=1;
    end
   end
   // A capture fault wins over a result arriving on the same clock.
   if(frame_dropped) begin tracking_valid<=0;continuity_lost<=1;end
  end
 end
endmodule
