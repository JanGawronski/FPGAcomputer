# Create Clock
create_clock -period "50MHz" [get_ports CLOCK0_50]
#create_clock -period "50MHz" [get_ports CLOCK1_50]
#create_clock -period "50MHz" [get_ports CLOCK2_50]
#create_clock -period "50MHz" [get_ports CLOCK3_50]

# Set Clock Uncertainty
derive_clock_uncertainty

# These are the first stages of two-flop synchronizers. Their inputs cross
# from the 50 MHz domain, so only the source-to-first-stage paths are exempt.
# The first-to-second-stage paths remain timed by the pixel clock.
set_false_path -from [get_clocks {CLOCK0_50}] -to [get_registers {*|enable_meta}]
set_false_path -from [get_clocks {CLOCK0_50}] -to [get_registers {*|clear_meta}]
