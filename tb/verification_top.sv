// Connect the modules used by the C++ module and system tests.
module verification_top(
 input logic clk,cam_clk,video_clk,arst,
 input logic pixel_valid,sof,eof,frame_abort,
 input logic [7:0] gray,threshold,
 input logic dark_line,
 input logic [4:0] x,
 input logic [3:0] y,
 input logic stop_event,release_event,bypass,sensor_required,
 input logic distance_sample,distance_valid,
 input logic [15:0] distance_mm,
 output logic signed [15:0] motor_left,motor_right,
 output logic inhibited,stopped,cdc_fault,mock_tx,
 output logic [3:0] nav_state,
 output logic debug_feature_valid,debug_frame_good,
 output logic [2:0] debug_row_valid,debug_junction,
 output logic [14:0] debug_centroids,
 output logic [17:0] debug_counts,
 output logic [15:0] debug_frame_id,
 input logic unit_reset,unit_inhibit,
 input logic signed [15:0] unit_steering,
 input logic [7:0] unit_speed,
 output logic signed [15:0] unit_left,unit_right,
 input logic [14:0] unit_centroids,
 output logic signed [15:0] unit_basic,unit_advanced,unit_heading,unit_curvature,
 input logic unit_uart_valid,unit_uart_abort,
 input logic [7:0] unit_uart_data,
 output logic unit_uart_tx,unit_uart_ready,unit_uart_busy,
 input logic div_start,
 input logic [17:0] div_n,div_d,
 output logic div_busy,div_done,div_zero,
 output logic [17:0] div_q,
 input logic j_present,j_request,
 input logic [7:0] j_key,
 input logic [2:0] j_available,
 output logic j_valid,j_revisited,
 output logic [1:0] j_choice,
 input logic d_sample,d_valid,
 input logic [15:0] d_mm,
 output logic d_blocked,d_fault,
 output logic unit_stopped,
 input logic use_capture,cap_href,cap_vsync,cap_msb,cap_y_first,
 input logic [7:0] cap_data,
 input logic [1:0] cap_format,
 output logic cap_valid,cap_sof,cap_eof,cap_abort,
 output logic [7:0] cap_gray,
 output logic [4:0] cap_x,
 output logic [3:0] cap_y,
 output logic [7:0] overlay_red,overlay_green,overlay_blue,
 input logic fb_swap,fb_read,
 input logic [8:0] fb_address,
 output logic [7:0] fb_gray,
 output logic fb_valid,fb_display_valid,fb_pending,
 output logic [15:0] fb_dropped,fb_displayed,
 output logic [7:0] video_red,video_green,video_blue,
 output logic video_hs,video_vs,video_active,video_valid,
 output logic [6:0] video_x,
 output logic [5:0] video_y,
 output logic signed [15:0] integrated_left,integrated_right,
 output logic integrated_inhibited,integrated_video_ready,
 output logic [7:0] integrated_red,
 output logic integrated_blank
);
 robot_core #(.W(32),.H(16),.FRAME_TIMEOUT(30000),.DISTANCE_TIMEOUT(50000),.RECOVER_FRAMES(3)) core(
  .clk,.cam_clk,.arst,.pixel_valid(use_capture ? cap_valid:pixel_valid),
  .sof(use_capture ? cap_sof:sof),.eof(use_capture ? cap_eof:eof),.frame_abort(use_capture ? cap_abort:frame_abort),
  .gray(use_capture ? cap_gray:gray),.threshold,.dark_line,
  .x(use_capture ? cap_x:x),.y(use_capture ? cap_y:y),
  .stop_event,.release_event,.bypass,.sensor_required,.distance_sample,.distance_valid,.distance_mm,
  .motor_left,.motor_right,.inhibited,.stopped,.cdc_fault,.nav_state,.debug_feature_valid,.debug_frame_good,
  .debug_row_valid,.debug_junction,.debug_centroids,.debug_counts,.debug_frame_id);
 mock_motor_packet packet(.clk,.reset(arst),.inhibit(inhibited),.left(motor_left),.right(motor_right),.tx(mock_tx));
 motion_control unit_motor(.inhibit(unit_inhibit),.steering(unit_steering),.speed(unit_speed),.left(unit_left),.right(unit_right));
 curve_fit #(.W(32)) unit_curve(.centroids(unit_centroids),.basic_error(unit_basic),.advanced_error(unit_advanced),.heading(unit_heading),.curvature(unit_curvature));
 uart_tx #(.CLKS_PER_BIT(4)) unit_uart(.clk,.reset(unit_reset),.abort_tx(unit_uart_abort),
  .valid(unit_uart_valid),.data(unit_uart_data),.ready(unit_uart_ready),.tx(unit_uart_tx),.busy(unit_uart_busy));
 unsigned_divider unit_div(.clk,.reset(unit_reset),.start(div_start),.numerator(div_n),.denominator(div_d),
  .busy(div_busy),.done(div_done),.divide_by_zero(div_zero),.quotient(div_q));
 junction_memory #(.DEPTH(4)) unit_junction(.clk,.reset(unit_reset),.present(j_present),.request(j_request),
  .key(j_key),.available(j_available),.decision_valid(j_valid),.revisited(j_revisited),.choice(j_choice));
 distance_guard #(.TIMEOUT_CYCLES(40)) unit_distance(.clk,.reset(unit_reset),.sample(d_sample),.valid(d_valid),
  .distance_mm(d_mm),.blocked(d_blocked),.fault(d_fault));
 safety_stop unit_safety(.clk,.reset(unit_reset),.stop_event,.release_event,.stopped(unit_stopped));
 camera_byte_capture #(.W(32),.H(16)) capture(.cam_clk,.reset(unit_reset),.href(cap_href),.vsync(cap_vsync),
  .data(cap_data),.pixel_format(cap_format),.rgb_msb_first(cap_msb),.y_first(cap_y_first),
  .pixel_valid(cap_valid),.sof(cap_sof),.eof(cap_eof),.frame_abort(cap_abort),.gray(cap_gray),.x(cap_x),.y(cap_y));
 debug_overlay #(.W(32),.H(16)) overlay(.pixel_valid,.inhibited(unit_inhibit),.gray,.x,.y,
  .centroids(unit_centroids),.row_valid(3'b111),.red(overlay_red),.green(overlay_green),.blue(overlay_blue));
 video_framebuffer #(.W(32),.H(16)) framebuffer(.cam_clk,.cam_reset(unit_reset),.pixel_valid,.sof,.eof,.frame_abort,.gray,.x,.y,
  .display_clk(clk),.display_reset(unit_reset),.swap_boundary(fb_swap),.read_enable(fb_read),.read_address(fb_address),
  .read_gray(fb_gray),.read_valid(fb_valid),.display_valid(fb_display_valid),.frame_pending(fb_pending),
  .dropped_frames(fb_dropped),.displayed_frames(fb_displayed));
 camera_debug_display #(.W(32),.H(16),.H_FRONT(2),.H_SYNC(4),.H_BACK(2),.V_FRONT(1),.V_SYNC(2),.V_BACK(1)) video(
  .cam_clk,.video_clk(clk),.arst,.pixel_valid,.sof,.eof,.frame_abort,.gray,.x,.y,
  .red(video_red),.green(video_green),.blue(video_blue),.hsync_n(video_hs),.vsync_n(video_vs),
  .blank_n(video_active),.display_valid(video_valid),.scan_x(video_x),.scan_y(video_y));
 robot_system #(.W(32),.H(16),.MOTION_N(4),.MOTION_R(1),.H_FRONT(2),.H_SYNC(4),.H_BACK(2),.V_FRONT(1),.V_SYNC(2),.V_BACK(1)) integrated(
  .clk,.cam_clk,.video_clk,.arst,.href(cap_href),.vsync(cap_vsync),.camera_data(cap_data),.threshold,
  .pixel_format(cap_format),.rgb_msb_first(cap_msb),.y_first(cap_y_first),.dark_line,
  .stop_event,.release_event,.bypass,.sensor_required,.distance_sample,.distance_valid,.distance_mm,
  .motor_left(integrated_left),.motor_right(integrated_right),.inhibited(integrated_inhibited),.stopped(),.cdc_fault(),
  .nav_state(),.debug_feature_valid(),.debug_frame_good(),.debug_row_valid(),.debug_junction(),
  .debug_centroids(),.debug_counts(),.debug_frame_id(),.vga_red(integrated_red),.vga_green(),.vga_blue(),
  .vga_hsync_n(),.vga_vsync_n(),.vga_blank_n(integrated_blank),.video_ready(integrated_video_ready),
  .motion_result_valid(),.motion_accepted(),.motion_rejected(),.motion_tracking_valid(),
  .motion_continuity_lost(),.motion_overflow(),.motion_boundary(),.motion_busy(),
  .motion_dx(),.motion_dy(),.motion_total_x(),.motion_total_y(),
  .motion_reference_id(),.motion_current_id(),.motion_dropped_frames(),
  .motion_best_sad(),.motion_second_sad(),.motion_contrast());
endmodule
