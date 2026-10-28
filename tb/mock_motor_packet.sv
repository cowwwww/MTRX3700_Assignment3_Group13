// Test-only packet format. Do not use this as a Nano/UGV02 driver.
// Bytes: A5, left low/high, right low/high, status, then XOR of those six bytes.
// When inhibit rises, cancel the packet, wait at least one character time,
// and send a packet with both wheel commands set to zero.
module mock_motor_packet #(parameter integer CPB=4,PERIOD=400)(
 input logic clk,reset,inhibit,
 input logic signed [15:0] left,right,
 output logic tx
);
 logic previous_inhibit,busy,ready,valid,aborting;
 logic [7:0] data,packet[7];
 integer index,wait_count;
 wire abort_now=inhibit && !previous_inhibit;
 assign aborting=abort_now;
 assign valid=index<7 && wait_count==0 && !abort_now;
 assign data=index<7 ? packet[index] : 8'b0;
 uart_tx #(.CLKS_PER_BIT(CPB)) uart(.clk,.reset,.abort_tx(aborting),.valid,.data,.ready,.tx,.busy);
 always_ff @(posedge clk) begin
  if(reset) begin
   previous_inhibit<=1;index<=7;wait_count<=0;
   for(integer i=0;i<7;i=i+1) packet[i]<=0;
  end else begin
   previous_inhibit<=inhibit;
   if(abort_now) begin index<=7;wait_count<=CPB*11;end
   else if(wait_count>0) wait_count<=wait_count-1;
   else if(index==7 && !busy) begin
    packet[0]<=8'ha5;packet[1]<=inhibit ? 8'b0:left[7:0];packet[2]<=inhibit ? 8'b0:left[15:8];
    packet[3]<=inhibit ? 8'b0:right[7:0];packet[4]<=inhibit ? 8'b0:right[15:8];packet[5]<={7'b0,inhibit};
    packet[6]<=8'ha5 ^ (inhibit ? 8'b0:left[7:0]) ^ (inhibit ? 8'b0:left[15:8]) ^
                 (inhibit ? 8'b0:right[7:0]) ^ (inhibit ? 8'b0:right[15:8]) ^ {7'b0,inhibit};
    index<=0;
   end else if(valid && ready) begin
    index<=index+1;
    if(index==6) wait_count<=PERIOD;
   end
  end
 end
endmodule
