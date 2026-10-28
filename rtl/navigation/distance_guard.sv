// Read distance samples in mm. The sensor trigger/echo logic is separate.
// Stop if a reading is invalid, too old or too close.
// Clear the obstacle stop after CLEAR_SAMPLES readings in a row reach CLEAR_MM.
module distance_guard #(
 parameter integer STOP_MM=180,CLEAR_MM=240,TIMEOUT_CYCLES=5000000,CLEAR_SAMPLES=3
)(
 input logic clk,reset,sample,valid,
 input logic [15:0] distance_mm,
 output logic blocked,fault
);
 localparam integer AW=$clog2(TIMEOUT_CYCLES+1),CW=$clog2(CLEAR_SAMPLES+1);
 logic [AW-1:0] age;
 logic [CW-1:0] clear_count;
 logic seen;
 assign fault=!seen || age>=AW'(TIMEOUT_CYCLES);
 always_ff @(posedge clk) begin
  if(reset) begin age<=AW'(TIMEOUT_CYCLES);seen<=0;blocked<=1;clear_count<=0;end
  else begin
   if(age<AW'(TIMEOUT_CYCLES)) age<=age+1'b1;
   if(fault) begin blocked<=1;clear_count<=0;end
   if(sample) begin
    if(!valid) begin seen<=0;blocked<=1;clear_count<=0;end
    else begin
     seen<=1;age<=0;
     if(distance_mm<=16'(STOP_MM)) begin blocked<=1;clear_count<=0;end
     else if(distance_mm>=16'(CLEAR_MM)) begin
      if(fault) clear_count<=CW'(1);
      else if(clear_count<CW'(CLEAR_SAMPLES)) clear_count<=clear_count+1'b1;
      if(CLEAR_SAMPLES==1 || (!fault && clear_count>=CW'(CLEAR_SAMPLES-1))) blocked<=0;
     end else clear_count<=0;
    end
   end
  end
 end
endmodule
