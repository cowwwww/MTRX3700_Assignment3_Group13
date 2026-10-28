# Physical V2, official camera input assumptions. Bundled CDC data is bounded,
# not hidden behind asynchronous clock groups. External VGA timing follows the
# official teaching baseline (outputs excepted); verify the monitor on hardware.
create_clock -name CLOCK_50 -period 20.000 [get_ports CLOCK_50]
create_clock -name PCLK -period 25.000 [get_ports {GPIO_1[21]}]
derive_pll_clocks
create_generated_clock -name sccb_clk -source [get_pins {video_pll_u|altera_pll_i|general[0].gpll~PLL_OUTPUT_COUNTER|divclk}] -divide_by 250 [get_registers {clock_divider:sccb_clk_u|clk_out}]
derive_clock_uncertainty
set camera_data [get_ports {GPIO_1[12] GPIO_1[13] GPIO_1[14] GPIO_1[15] GPIO_1[16] GPIO_1[17] GPIO_1[18] GPIO_1[19] GPIO_1[22] GPIO_1[23]}]
set_input_delay -clock PCLK -clock_fall -max 7.0 $camera_data
set_input_delay -clock PCLK -clock_fall -min 0.0 $camera_data
set_false_path -from [get_ports {KEY[*] SW[*] IRDA_RXD GPIO_1[24] GPIO_1[29]}]
set_false_path -to [get_ports {LEDR[*] HEX0[*] HEX1[*] HEX2[*] HEX3[*] HEX4[*] HEX5[*] GPIO_1[0] GPIO_1[5] GPIO_1[10] GPIO_1[11] GPIO_1[20] GPIO_1[24] GPIO_1[25] GPIO_1[27] GPIO_1[30] GPIO_1[31] GPIO_1[35] VGA_*}]
# Only first stages of genuine single-bit synchronizers are excepted.
set_false_path -to [get_registers {*req_sync[0] *ack_sync[0] *request_sync[0] *overrun_sync[0] *cfg_sync[0] *polarity_sync[0] *range_fault_sync[0] *frame_sync[0]}]
# Async reset assertion; release is synchronized independently in each domain.
set_false_path -to [get_registers {*reset_sync*|pipe[*]}]
foreach box {features_crossing distance_crossing motion_debug_crossing} {
 set_max_delay 20.0 -from [get_registers *${box}*payload*] -to [get_registers *${box}*dst_data*]
 set_min_delay 0.0 -from [get_registers *${box}*payload*] -to [get_registers *${box}*dst_data*]
}
set_max_delay 40.0 -from [get_registers {*frames*published_bank}] -to [get_registers {*frames*read_bank}]
set_min_delay 0.0 -from [get_registers {*frames*published_bank}] -to [get_registers {*frames*read_bank}]
