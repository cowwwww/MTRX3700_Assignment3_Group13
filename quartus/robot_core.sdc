# Estimate core timing assuming clk=50 MHz and cam_clk=24 MHz.
# Use the supplied clock, pin and setup files when connecting the board.
create_clock -name control -period 20.000 [get_ports {clk}]
create_clock -name camera -period 41.667 [get_ports {cam_clk}]
derive_clock_uncertainty
# Exclude only the first synchronizer stages from timing checks, not the data bus.
set_false_path -to [get_registers {*features_crossing*req_sync[0]}]
set_false_path -to [get_registers {*features_crossing*ack_sync[0]}]
set_false_path -to [get_registers {*overrun_sync[0]}]
# Hold the data until ack returns. It must be stable before the receiver reads it.
# Limit the data delay to one control clock period. The request passes
# through two synchronizer registers before the receiver reads the data.
set_max_delay 20.0 -from [get_registers {*features_crossing*payload*}] -to [get_registers {*features_crossing*dst_data*}]
set_min_delay 0.0 -from [get_registers {*features_crossing*payload*}] -to [get_registers {*features_crossing*dst_data*}]
set_false_path -from [get_ports {arst}]
# The hardware interface modules still need to be added. Check their input
# and output timing using the actual board connections and loads.
