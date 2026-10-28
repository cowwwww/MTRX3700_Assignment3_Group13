module board_adapters_top(
 input logic clk,reset,inhibit,href,vsync,
 input logic [7:0] data,
 input logic signed [15:0] left,right,
 output wire tx,packet_done,packet_zero,pixel_valid,sof,eof,frame_abort,
 output wire [7:0] gray,
 output wire [8:0] x,
 output wire [7:0] y
);
 chassis_json_tx #(.CLKS_PER_BIT(4),.PERIOD_CLKS(2000)) transport(
  .clk,.reset,.inhibit,.left,.right,.tx,.busy(),.packet_done,.packet_zero);
 camera_to_qvga camera(.pclk(clk),.reset,.href,.vsync,.data,.pixel_valid,.sof,.eof,.frame_abort,.gray,.x,.y);
endmodule
