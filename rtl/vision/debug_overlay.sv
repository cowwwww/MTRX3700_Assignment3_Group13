// Add markers to the input pixel stream. VGA timing and frame storage are separate.
// Red cross: valid line centre. Cyan: sampled row. Red top strip: movement stopped.
module debug_overlay #(parameter integer W=320,H=240,XW=$clog2(W),YW=$clog2(H))(
 input logic pixel_valid,inhibited,
 input logic [7:0] gray,
 input logic [XW-1:0] x,
 input logic [YW-1:0] y,
 input logic [3*XW-1:0] centroids,
 input logic [2:0] row_valid,
 output logic [7:0] red,green,blue
);
 integer dx,dy;
 always_comb begin
  red=gray;green=gray;blue=gray;dx=0;dy=0;
  for(integer r=0;r<3;r=r+1) begin
   dx=int'(x)-int'(centroids[r*XW+:XW]);dy=int'(y)-(r+1)*(H/4);
   if(dy==0) begin red=0;green=180;blue=180;end
   if(row_valid[r] && ((dx==0 && dy>=-2 && dy<=2) || (dy==0 && dx>=-2 && dx<=2))) begin
    red=255;green=0;blue=0;
   end
  end
  if(inhibited && y<2) begin red=255;green=0;blue=0;end
  if(!pixel_valid) begin red=0;green=0;blue=0;end
 end
endmodule
