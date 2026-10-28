// Use stop and release events that have already been decoded on this clock.
// Start stopped after reset. Only release_event clears the stop.
module safety_stop(input logic clk,reset,stop_event,release_event,output logic stopped);
 always_ff @(posedge clk) begin
  if(reset || stop_event) stopped<=1;
  else if(release_event) stopped<=0;
 end
endmodule
