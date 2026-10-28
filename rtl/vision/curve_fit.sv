// Fit a quadratic curve through line positions on three equally spaced rows.
// Use near t=0, middle t=1 and far t=2. The target at t=1.5 is
// (-near + 6*mid + 3*far)/8. Curvature is in image units, not physical units.
// Positive error means the target is to the right. Check camera and motor signs.
module curve_fit #(parameter integer W=320,XW=$clog2(W))(
 input logic [3*XW-1:0] centroids,
 output logic signed [15:0] basic_error,advanced_error,heading,curvature
);
 integer far_x,mid_x,near_x,target_x;
 always_comb begin
  far_x=int'(centroids[0+:XW]);mid_x=int'(centroids[XW+:XW]);near_x=int'(centroids[2*XW+:XW]);
  target_x=(-near_x+6*mid_x+3*far_x)/8;
  if(target_x<0) target_x=0;
  if(target_x>W-1) target_x=W-1;
  basic_error=16'(near_x-W/2);advanced_error=16'(target_x-W/2);
  heading=16'(far_x-near_x);curvature=16'(near_x-2*mid_x+far_x);
 end
endmodule
