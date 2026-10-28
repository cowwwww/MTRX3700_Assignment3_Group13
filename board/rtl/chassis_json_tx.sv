// V2 chassis transport. AI-assisted; shared owner pending.
// Protocol/pins/baud from official hwtest/chassis_command.sv: newline-delimited
// {"T":1,"L":m/s,"R":m/s}, UART 115200 8N1. Scale abstract +/-255 to a bounded
// mm/s magnitude; default cap 100 mm/s (0.100 m/s), pending physical calibration.
// Never truncate a JSON line on stop: finish the current packet, then send zero
// immediately. No old queued motion packets. reset is POWER-ON only; KEY reset
// must use inhibit so that zero packets keep transmitting while KEY is held.
module chassis_json_tx #(
 parameter integer CLKS_PER_BIT=434,PERIOD_CLKS=10000000,MAX_MMPS=100
)(
 input logic clk,reset,inhibit,
 input logic signed [15:0] left,right,
 output logic tx,busy,packet_done,packet_zero
);
 localparam integer LEN=30,TW=$clog2(PERIOD_CLKS+1);
 localparam logic [2:0] SYNC=0,WAIT_SYNC=1,IDLE=2,SEND=3,DRAIN=4,PREPARE=5;
 logic [2:0] state;
 logic [LEN*8-1:0] payload;
 logic [5:0] remaining;
 logic [TW-1:0] timer;
 logic stop_pending,previous_inhibit,active_zero,ready,uart_busy,valid;
 logic [7:0] data;
 logic signed [15:0] saved_left,saved_right;
 // Constant table: division is elaborated, never a 32-bit combinational divider.
 function automatic [3071:0] make_decimal_table();
  integer i,m;
  begin
   make_decimal_table='0;
   for(i=0;i<256;i=i+1)begin
    m=i*MAX_MMPS/255;
    make_decimal_table[i*12+:12]={4'(m/100),4'((m/10)%10),4'(m%10)};
   end
  end
 endfunction
 localparam logic [3071:0] DECIMAL_TABLE=make_decimal_table();
 function automatic logic [47:0] wheel_text(input logic signed [15:0] command);
  logic signed [15:0] value;
  logic [7:0] mag;
  logic [11:0] digits;
  logic [7:0] sign_char,hundreds,tens,ones;
  begin
   value=command;if(value>255)value=255;if(value< -255)value=-255;
   mag=8'(value<0 ? -value:value);
   digits=DECIMAL_TABLE[mag*12+:12];
   sign_char=(value<0 && digits!=0) ? 8'h2d:8'h20;
   hundreds={4'h3,digits[11:8]};tens={4'h3,digits[7:4]};ones={4'h3,digits[3:0]};
   wheel_text={sign_char,8'h30,8'h2e,hundreds,tens,ones};
  end
 endfunction
 function automatic logic [LEN*8-1:0] make_packet(input logic signed [15:0] l,r);
  make_packet={"{\"T\":1,\"L\":",wheel_text(l),",\"R\":",wheel_text(r),"}\n"};
 endfunction
 always_comb begin
  valid=state==SYNC || (state==SEND && remaining!=0);
  data=state==SYNC ? 8'h0a:payload[LEN*8-1-:8];
  busy=state!=IDLE;
 end
 uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) serial(
  .clk,.reset,.abort_tx(1'b0),.valid,.data,.ready,.tx,.busy(uart_busy));
 initial begin
  if(MAX_MMPS<1 || MAX_MMPS>500 || PERIOD_CLKS<2) $fatal(1,"invalid chassis limits");
 end
 always_ff @(posedge clk) begin
  packet_done<=0;
  if(reset) begin
   state<=SYNC;payload<=0;remaining<=0;timer<=TW'(PERIOD_CLKS);
   saved_left<=0;saved_right<=0;
   stop_pending<=1;previous_inhibit<=1;active_zero<=1;packet_zero<=1;packet_done<=0;
  end else begin
   previous_inhibit<=inhibit;
   if(timer<TW'(PERIOD_CLKS))timer<=timer+1'b1;
   case(state)
    SYNC: if(ready)state<=WAIT_SYNC;
    WAIT_SYNC: if(ready)state<=IDLE;
    IDLE: if(stop_pending || (inhibit && !previous_inhibit) || timer>=TW'(PERIOD_CLKS)) begin
     saved_left<=left;saved_right<=right;state<=PREPARE;
    end
    PREPARE: begin
     payload<=make_packet((inhibit || stop_pending) ? 16'sd0:saved_left,
                          (inhibit || stop_pending) ? 16'sd0:saved_right);
     active_zero<=(inhibit || stop_pending) ||
                  (wheel_text(saved_left)==wheel_text(16'sd0) && wheel_text(saved_right)==wheel_text(16'sd0));
     remaining<=6'(LEN);timer<=0;state<=SEND;
     if(inhibit || stop_pending)stop_pending<=0;
    end
    SEND: if(ready && remaining!=0) begin
     payload<=payload<<8;remaining<=remaining-1'b1;
     if(remaining==1)state<=DRAIN;
    end
    DRAIN: if(ready) begin state<=IDLE;packet_done<=1;packet_zero<=active_zero;end
    default:state<=SYNC;
   endcase
   if(inhibit && !previous_inhibit)stop_pending<=1;
  end
 end
endmodule
