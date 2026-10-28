# Estimate display-buffer timing. Real board pin timing still needs checking.
create_clock -name camera -period 41.667 [get_ports {cam_clk}]
create_clock -name display -period 40.000 [get_ports {display_clk}]
derive_clock_uncertainty
set_false_path -to [get_registers {*request_sync[0]}]
set_false_path -to [get_registers {*ack_sync[0]}]
set_max_delay 40.0 -from [get_registers {*published_bank}] -to [get_registers {*read_bank}]
set_min_delay 0.0 -from [get_registers {*published_bank}] -to [get_registers {*read_bank}]
set_false_path -from [get_ports {cam_reset display_reset}]
