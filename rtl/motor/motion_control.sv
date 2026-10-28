// Calculate signed left and right wheel commands.
// These values still need conversion to the units and format used by the UGV02.
module motion_control #(parameter integer GAIN=2,MAX_COMMAND=255)(
 input logic inhibit,
 input logic signed [15:0] steering,
 input logic [7:0] speed,
 output logic signed [15:0] left,right
);
 integer l,r;
 function automatic logic signed [15:0] saturate(input integer v);
  if(v>MAX_COMMAND) saturate=16'(MAX_COMMAND);
  else if(v< -MAX_COMMAND) saturate=16'(-MAX_COMMAND);
  else saturate=16'(v);
 endfunction
 always_comb begin
  l=int'(speed)+int'(steering)*GAIN;r=int'(speed)-int'(steering)*GAIN;
  left=inhibit ? 16'sd0 : saturate(l);right=inhibit ? 16'sd0 : saturate(r);
 end
endmodule
