# Estimate timing for the connected logic. Real device and pin timing is not checked.
source robot_core.sdc
create_clock -name video -period 40.000 [get_ports {video_clk}]
derive_clock_uncertainty
set_false_path -to [get_registers {*frames*request_sync[0]}]
set_false_path -to [get_registers {*frames*ack_sync[0]}]
set_max_delay 40.0 -from [get_registers {*frames*published_bank}] -to [get_registers {*frames*read_bank}]
set_min_delay 0.0 -from [get_registers {*frames*published_bank}] -to [get_registers {*frames*read_bank}]
