// V2 physical DE1-SoC top. AI-assisted integration, shared owner pending.
// GPIO mapping and peripheral configuration are from official 2026 hwtest.
// Existing V1 processing stays in rtl/. No automatic movement after reset.
module robot_board(
 input wire CLOCK_50,
 input wire [3:0] KEY,
 input wire [9:0] SW,
 output wire [9:0] LEDR,
 output wire [6:0] HEX0,HEX1,HEX2,HEX3,HEX4,HEX5,
 inout wire [35:0] GPIO_1,
 input wire IRDA_RXD,
 output wire VGA_CLK,VGA_HS,VGA_VS,VGA_BLANK_N,VGA_SYNC_N,
 output wire [7:0] VGA_R,VGA_G,VGA_B
);
 // Power reset initializes the transport once. KEY0 must not hold the UART in
 // reset while the chassis might still be executing its previous command.
 logic [7:0] power_pipe=8'hff;
 always_ff @(posedge CLOCK_50)power_pipe<={power_pipe[6:0],1'b0};
 wire power_reset=|power_pipe;
 wire clk25,clk10,clk_sonar,video_locked,sonar_locked,sccb_clk;
 video_pll video_pll_u(.refclk(CLOCK_50),.rst(1'b0),.outclk_0(clk25),.outclk_1(clk10),.locked(video_locked));
 sonar_pll sonar_pll_u(.refclk(CLOCK_50),.rst(1'b0),.outclk_0(clk_sonar),.locked(sonar_locked));
 clock_divider #(.DIVISOR(250)) sccb_clk_u(.clk_in(clk25),.clk_out(sccb_clk));
 wire board_reset=power_reset || !KEY[0] || !video_locked || !sonar_locked;
 wire reset50,reset_sonar,reset_sccb;
 reset_sync cr(.clk(CLOCK_50),.arst(board_reset),.reset(reset50));
 reset_sync sr(.clk(clk_sonar),.arst(board_reset),.reset(reset_sonar));
 reset_sync ir(.clk(sccb_clk),.arst(board_reset),.reset(reset_sccb));

 wire cfg_done,cfg_error,cam_reset_n,cam_pwdn,sioc;
 ov7670_config cfg_u(.clk(sccb_clk),.reset(reset_sccb),.sioc,.siod(GPIO_1[24]),
  .cam_reset_n,.cam_pwdn,.done(cfg_done),.error(cfg_error));
 assign GPIO_1[20]=clk10;assign GPIO_1[11]=cam_reset_n;
 assign GPIO_1[10]=cam_pwdn;assign GPIO_1[25]=sioc;
 (* altera_attribute="-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS",preserve *) logic [1:0] cfg_sync;
 always_ff @(posedge CLOCK_50 or posedge reset50)
  if(reset50)cfg_sync<=0;else cfg_sync<={cfg_sync[0],cfg_done};
 wire stream_arst=board_reset || !cfg_sync[1];
 wire cam_reset,pixel_valid,sof,eof,frame_abort;
 wire [7:0] gray;
 wire [8:0] x;wire [7:0] y;
 wire cam_clk=GPIO_1[21];
 reset_sync cam_rst(.clk(cam_clk),.arst(stream_arst),.reset(cam_reset));
 camera_to_qvga camera(.pclk(cam_clk),.reset(cam_reset),.href(GPIO_1[22]),.vsync(GPIO_1[23]),
  .data(GPIO_1[19:12]),.pixel_valid,.sof,.eof,.frame_abort,.gray,.x,.y);

 (* altera_attribute="-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS",preserve *) logic [3:0] key_meta,key_sync;
 (* altera_attribute="-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS",preserve *) logic [9:0] sw_meta,sw_sync;
 logic [3:0] key_previous;
 always_ff @(posedge CLOCK_50)begin
  if(reset50)begin key_meta<=4'hf;key_sync<=4'hf;key_previous<=4'hf;sw_meta<=0;sw_sync<=0;end
  else begin key_meta<=KEY;key_sync<=key_meta;key_previous<=key_sync;sw_meta<=SW;sw_sync<=sw_meta;end
 end
 wire ir_valid,ir_repeat;
 wire [31:0] ir_code;
 nec_decoder remote(.clk(CLOCK_50),.rst(reset50),.ir(IRDA_RXD),.valid(ir_valid),.code(ir_code),.repeat_code(ir_repeat));
 // Numeric 1 STOP; numeric 2 RELEASE (official ir_drive's key-code table).
 // SW9 master enable, SW0 basic bypass, SW8 bright-line polarity (0=dark).
 wire stop_event=!sw_sync[9] || !key_sync[1] || (ir_valid && ir_code[23:16]==8'h01);
 wire release_event=sw_sync[9] && ((key_previous[2] && !key_sync[2]) ||
                                (ir_valid && ir_code[23:16]==8'h02));
 // Polarity is slow configuration, crossed separately and latched by detector SOF.
 (* altera_attribute="-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS",preserve *) logic [1:0] polarity_sync;
 always_ff @(posedge cam_clk or posedge cam_reset)
  if(cam_reset)polarity_sync<=0;else polarity_sync<={polarity_sync[0],sw_sync[8]};

 // Front sensor J3, official 43.904 MHz/mm scaling. A measurement every 100 ms.
 logic [22:0] sonar_pace;
 wire sonar_start=sonar_pace<23'd16;
 wire sonar_valid,sonar_trigger,sonar_busy;
 wire [11:0] sonar_distance;
 always_ff @(posedge clk_sonar)begin
  if(reset_sonar)sonar_pace<=0;
  else sonar_pace<=sonar_pace==23'd4390399 ? 23'd0:sonar_pace+1'b1;
 end
 sonar_range front_sensor(.clk(clk_sonar),.start_measure(sonar_start),.rst(reset_sonar),
  .echo(GPIO_1[29]),.trig(sonar_trigger),.distance(sonar_distance),.ready(),.valid(sonar_valid));
 assign GPIO_1[27]=sonar_trigger;
 assign GPIO_1[30]=1'b0;assign GPIO_1[35]=1'b0; // unused trigger ports stay low
 wire range_usable=sonar_distance>0 && sonar_distance<=4000;
 wire [16:0] distance_packet;
 wire distance_sample;
 logic range_overrun;
 (* altera_attribute="-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS",preserve *) logic [1:0] range_fault_sync;
 always_ff @(posedge clk_sonar or posedge reset_sonar)
  if(reset_sonar)range_overrun<=0;else if(sonar_valid && sonar_busy)range_overrun<=1;
 always_ff @(posedge CLOCK_50 or posedge reset50)
  if(reset50)range_fault_sync<=0;else range_fault_sync<={range_fault_sync[0],range_overrun};
 cdc_mailbox #(.WIDTH(17)) distance_crossing(
  .src_clk(clk_sonar),.src_reset(reset_sonar),.src_valid(sonar_valid),
  .src_data({range_usable,4'b0,sonar_distance}),.src_busy(sonar_busy),
  .dst_clk(CLOCK_50),.dst_reset(reset50),.dst_accept(1'b1),.dst_data(distance_packet),.dst_valid(distance_sample));

 wire signed [15:0] motor_left,motor_right;
 wire inhibited,stopped,cdc_fault,feature_valid,frame_good;
 wire [3:0] nav_state;
 wire [2:0] row_valid,junction;
 wire [26:0] centroids,counts;
 wire [15:0] frame_id;
 robot_core #(.DISTANCE_TIMEOUT(15000000)) core(
  .clk(CLOCK_50),.cam_clk,.arst(stream_arst),.pixel_valid,.sof,.eof,.frame_abort,.gray,
  .threshold(8'd96),.dark_line(!polarity_sync[1]),.x,.y,.stop_event,.release_event,
  .bypass(sw_sync[0]),.sensor_required(1'b1),.distance_sample,
  .distance_valid(distance_packet[16]),.distance_mm(distance_packet[15:0]),
  .motor_left,.motor_right,.inhibited,.stopped,.cdc_fault,.nav_state,
  .debug_feature_valid(feature_valid),.debug_frame_good(frame_good),.debug_row_valid(row_valid),
  .debug_junction(junction),.debug_centroids(centroids),.debug_counts(counts),.debug_frame_id(frame_id));
 wire video_ready;
 camera_debug_display display(.cam_clk,.video_clk(clk25),.arst(stream_arst),.pixel_valid,.sof,.eof,.frame_abort,
  .gray,.x,.y,.red(VGA_R),.green(VGA_G),.blue(VGA_B),.hsync_n(VGA_HS),.vsync_n(VGA_VS),
  .blank_n(VGA_BLANK_N),.display_valid(video_ready),.scan_x(),.scan_y());
 assign VGA_CLK=clk25;assign VGA_SYNC_N=1'b0;

 // Preserve V1's image-motion branch; pixels only, no metric pose/navigation.
 wire motion_result_valid,match_valid,boundary,motion_dropped,motion_busy;
 wire signed [4:0] dx,dy;
 wire [15:0] reference_id,current_id,dropped_count,best_sad,second_sad;
 wire [7:0] contrast;
 wire motion_accepted,motion_rejected,tracking_valid,continuity_lost,motion_overflow;
 wire signed [31:0] total_x,total_y;
 camera_motion motion(.clk(cam_clk),.reset(cam_reset),.pixel_valid,.sof,.eof,.frame_abort,.gray,.x,.y,
  .busy(motion_busy),.frame_dropped(motion_dropped),.dropped_frames(dropped_count),
  .result_valid(motion_result_valid),.match_valid,.at_search_boundary(boundary),.dx,.dy,
  .best_sad,.second_sad,.contrast,.reference_id,.current_id);
 motion_result motion_status(.clk(cam_clk),.reset(cam_reset),.result_valid(motion_result_valid),.match_valid,
  .at_search_boundary(boundary),.frame_dropped(motion_dropped),.dx,.dy,.reference_id,.current_id,
  .accepted(motion_accepted),.rejected(motion_rejected),.tracking_valid,.continuity_lost,
  .overflow(motion_overflow),.total_x,.total_y);

 wire transport_inhibit=inhibited || !sw_sync[9] || board_reset || !cfg_sync[1] || range_fault_sync[1];
 wire chassis_tx,chassis_busy,packet_done,packet_zero;
 chassis_json_tx transport(.clk(CLOCK_50),.reset(power_reset),.inhibit(transport_inhibit),
  .left(motor_left),.right(motor_right),.tx(chassis_tx),.busy(chassis_busy),.packet_done,.packet_zero);
 assign GPIO_1[31]=chassis_tx;
 assign GPIO_1[0]=!reset50;assign GPIO_1[5]=1'b1; // Nano released/idle, separate from chassis UART

 // Read-only camera status crossing for LEDs. Motion never crosses into control.
 logic frame_toggle;
 (* altera_attribute="-name SYNCHRONIZER_IDENTIFICATION FORCED_IF_ASYNCHRONOUS",preserve *) logic [1:0] frame_sync;
 always_ff @(posedge cam_clk or posedge cam_reset)
  if(cam_reset)frame_toggle<=0;else if(eof && pixel_valid)frame_toggle<=!frame_toggle;
 always_ff @(posedge CLOCK_50 or posedge reset50)
  if(reset50)frame_sync<=0;else frame_sync<={frame_sync[0],frame_toggle};
 assign LEDR={sw_sync[9],range_fault_sync[1]||cdc_fault,nav_state==4'd5,
              distance_packet[16],!stopped,!transport_inhibit,stopped,frame_good,frame_sync[1],cfg_sync[1]};
 function automatic [6:0] hex(input [3:0] v);
  case(v)
   0:hex=7'h40;1:hex=7'h79;2:hex=7'h24;3:hex=7'h30;
   4:hex=7'h19;5:hex=7'h12;6:hex=7'h02;7:hex=7'h78;
   8:hex=7'h00;9:hex=7'h10;10:hex=7'h08;11:hex=7'h03;
   12:hex=7'h46;13:hex=7'h21;14:hex=7'h06;default:hex=7'h0e;
  endcase
 endfunction
 // Atomic diagnostic snapshot keeps the motion datapath observable in hardware.
 // Delay publication so motion_result has updated its accumulated displacement.
 logic motion_publish;
 always_ff @(posedge cam_clk or posedge cam_reset)
  if(cam_reset)motion_publish<=0;else motion_publish<=motion_result_valid;
 wire debug_reset;
 reset_sync debug_rst(.clk(CLOCK_50),.arst(stream_arst),.reset(debug_reset));
 wire [169:0] motion_debug;
 cdc_mailbox #(.WIDTH(170)) motion_debug_crossing(
  .src_clk(cam_clk),.src_reset(cam_reset),.src_valid(motion_publish),
  .src_data({total_x,total_y,dx,dy,reference_id,current_id,best_sad,second_sad,contrast,dropped_count,
             1'b0,motion_accepted,motion_rejected,tracking_valid,continuity_lost,motion_overflow,boundary,match_valid}),
  .src_busy(),.dst_clk(CLOCK_50),.dst_reset(debug_reset),.dst_accept(1'b1),.dst_data(motion_debug),.dst_valid());
 wire [31:0] dbg_x=motion_debug[169:138],dbg_y=motion_debug[137:106];
 wire [4:0] dbg_dx=motion_debug[105:101],dbg_dy=motion_debug[100:96];
 logic [7:0] last_ir;
 always_ff @(posedge CLOCK_50)if(reset50)last_ir<=0;else if(ir_valid)last_ir<=ir_code[23:16];
 logic [23:0] digits;
 always_comb begin
  case(sw_sync[7:4])
   1:digits=dbg_x[23:0];
   2:digits=dbg_y[23:0];
   3:digits={{3{dbg_dx[4]}},dbg_dx,{3{dbg_dy[4]}},dbg_dy,motion_debug[7:0]};
   4:digits={motion_debug[63:48],motion_debug[31:24]};
   5:digits={motion_debug[91:80],motion_debug[75:64]};
   6:digits={motion_debug[47:32],motion_debug[7:0]};
   7:digits=motion_debug[23:0];
   8:digits={dbg_x[31:24],dbg_y[31:24],motion_debug[7:0]};
   default:digits={distance_packet[11:0],last_ir,nav_state};
  endcase
 end
 assign HEX0=hex(digits[3:0]);assign HEX1=hex(digits[7:4]);assign HEX2=hex(digits[11:8]);
 assign HEX3=hex(digits[15:12]);assign HEX4=hex(digits[19:16]);assign HEX5=hex(digits[23:20]);
endmodule
