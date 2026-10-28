// Send data between clocks and hold it until the receiver replies.
// Start both resets together; release each on its own clock.
module cdc_mailbox #(parameter WIDTH=16)(
 input logic src_clk, src_reset, src_valid,
 input logic [WIDTH-1:0] src_data,
 output logic src_busy,
 input logic dst_clk, dst_reset, dst_accept,
 output logic [WIDTH-1:0] dst_data,
 output logic dst_valid
);
 logic [WIDTH-1:0] payload;
 logic req, ack;
 // Reused from A2 V9. Use Quartus attributes to keep the synchronizer registers.
 (* altera_attribute="-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS", preserve *) logic [1:0] ack_sync, req_sync;
 assign src_busy = req != ack_sync[1];
 always_ff @(posedge src_clk or posedge src_reset)
  if(src_reset) begin req<=0; ack_sync<=0; payload<=0; end
  else begin
   ack_sync <= {ack_sync[0],ack};
   if(src_valid && !src_busy) begin payload<=src_data; req<=~req; end
  end
 always_ff @(posedge dst_clk or posedge dst_reset)
  if(dst_reset) begin ack<=0; req_sync<=0; dst_valid<=0; dst_data<=0; end
  else begin
   req_sync <= {req_sync[0],req}; dst_valid<=0;
   if(dst_accept && req_sync[1]!=ack) begin
    dst_data<=payload; dst_valid<=1; ack<=req_sync[1];
   end
  end
endmodule
