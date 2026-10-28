// Store the branches already tried at each junction.
// The caller must supply the same ID when revisiting a junction.
// This module does not detect junctions or work out the robot's position.
// Bits 0, 1 and 2 mean left, straight and right. Try unused branches first.
// When all available branches have been tried, start again.
// Choose once per visit. When full, replace entries in order and wrap around.
module junction_memory #(parameter integer DEPTH=8,KEY_WIDTH=8)(
 input logic clk,reset,present,request,
 input logic [KEY_WIDTH-1:0] key,
 input logic [2:0] available,
 output logic decision_valid,revisited,
 output logic [1:0] choice
);
 localparam integer IW=$clog2(DEPTH);
 logic [DEPTH-1:0] occupied;
 logic [KEY_WIDTH-1:0] keys[DEPTH];
 logic [2:0] tried[DEPTH];
 logic [IW-1:0] replace_index;
 logic episode_used;
 integer found,slot,pick;
 logic [2:0] candidates,old_tried;
 always_comb begin
  found=-1;
  for(integer i=0;i<DEPTH;i=i+1) if(occupied[i] && keys[i]==key) found=i;
  slot=found>=0 ? found : int'(replace_index);
  old_tried=found>=0 ? tried[slot] : 3'b0;
  candidates=available & ~old_tried;
  if(candidates==0) candidates=available;
  pick=0;
  // Choose straight first, then left, then right.
  if(candidates[1]) pick=1; else if(candidates[0]) pick=0; else pick=2;
 end
 always_ff @(posedge clk) begin
  decision_valid<=0;
  if(reset) begin
   occupied<=0;replace_index<=0;episode_used<=0;revisited<=0;choice<=0;
   for(integer i=0;i<DEPTH;i=i+1) begin keys[i]<=0;tried[i]<=0;end
  end else begin
   if(!present) episode_used<=0;
   if(present && request && !episode_used && available!=0) begin
    decision_valid<=1;revisited<=found>=0;choice<=2'(pick);episode_used<=1;
    occupied[slot]<=1;keys[slot]<=key;
    tried[slot]<=((available & ~old_tried)==0 ? 3'b0 : old_tried) | (3'b1<<pick);
    if(found<0) replace_index<=replace_index==IW'(DEPTH-1) ? '0 : replace_index+1'b1;
   end
  end
 end
endmodule
