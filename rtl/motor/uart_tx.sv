// Send one byte with a start bit, eight data bits and one stop bit (8N1).
// Accept a byte when valid and ready are high. On abort, discard the current
// byte and return TX to idle at the next clock edge.
module uart_tx #(parameter integer CLKS_PER_BIT=434)(
 input logic clk,reset,abort_tx,valid,
 input logic [7:0] data,
 output logic ready,tx,busy
);
 localparam integer CW=$clog2(CLKS_PER_BIT+1);
 logic [CW-1:0] ticks;
 logic [3:0] bit_index;
 logic [9:0] shift;
 assign ready=!busy && !abort_tx && !reset;
 assign tx=busy ? shift[0] : 1'b1;
 always_ff @(posedge clk) begin
  if(reset || abort_tx) begin busy<=0;ticks<=0;bit_index<=0;shift<=10'h3ff;end
  else if(valid && ready) begin
   shift<={1'b1,data,1'b0};busy<=1;ticks<=CW'(CLKS_PER_BIT-1);bit_index<=0;
  end else if(busy) begin
   if(ticks==0) begin
    ticks<=CW'(CLKS_PER_BIT-1);shift<={1'b1,shift[9:1]};
    if(bit_index==9) busy<=0; else bit_index<=bit_index+1'b1;
   end else ticks<=ticks-1'b1;
  end
 end
endmodule
