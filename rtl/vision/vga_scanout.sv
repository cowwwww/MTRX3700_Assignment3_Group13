// Read a grayscale frame and display each pixel as a 2x2 block.
// Timing values come from the A2 V9 generated VGA controller:
// 640/16/96/48 horizontally and 480/10/2/33 vertically.
// The pixel clock, PLL and DAC pins must be connected separately.
// Delay sync, blanking and coordinates by one clock to match the RAM output.
module vga_scanout #(
 parameter integer W=320,H=240,H_FRONT=16,H_SYNC=96,H_BACK=48,V_FRONT=10,V_SYNC=2,V_BACK=33,
 parameter integer HT=2*W+H_FRONT+H_SYNC+H_BACK,VT=2*H+V_FRONT+V_SYNC+V_BACK,
 parameter integer HW=$clog2(HT),VW=$clog2(VT),AW=$clog2(W*H)
)(
 input logic clk,reset,
 output logic read_enable,swap_boundary,
 output logic [AW-1:0] read_address,
 output logic hsync_n,vsync_n,active,
 output logic [HW-1:0] scan_x,
 output logic [VW-1:0] scan_y
);
 logic [HW-1:0] horizontal;
 logic [VW-1:0] vertical;
 always_comb begin
  read_enable=!reset && int'(horizontal)<2*W && int'(vertical)<2*H;
  read_address=read_enable ? AW'((int'(vertical)/2)*W+int'(horizontal)/2) : '0;
  swap_boundary=!reset && horizontal==0 && vertical==VW'(2*H);
 end
 always_ff @(posedge clk) begin
  if(reset) begin horizontal<=0;vertical<=0;hsync_n<=1;vsync_n<=1;active<=0;scan_x<=0;scan_y<=0;end
  else begin
   scan_x<=horizontal;scan_y<=vertical;active<=read_enable;
   hsync_n<=!(int'(horizontal)>=2*W+H_FRONT && int'(horizontal)<2*W+H_FRONT+H_SYNC);
   vsync_n<=!(int'(vertical)>=2*H+V_FRONT && int'(vertical)<2*H+V_FRONT+V_SYNC);
   if(horizontal==HW'(HT-1)) begin
    horizontal<=0;
    if(vertical==VW'(VT-1)) vertical<=0;else vertical<=vertical+1'b1;
   end else horizontal<=horizontal+1'b1;
  end
 end
endmodule
