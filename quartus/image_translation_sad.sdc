# Estimate the image-shift module using a 50 MHz clock.
# Data pins are virtual. Timing at the real board pins still needs checking.
create_clock -name processing -period 20.000 [get_ports {clk}]
derive_clock_uncertainty
