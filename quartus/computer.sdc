# Create Clock
create_clock -period "50MHz" [get_ports CLOCK0_50]
#create_clock -period "50MHz" [get_ports CLOCK1_50]
#create_clock -period "50MHz" [get_ports CLOCK2_50]
#create_clock -period "50MHz" [get_ports CLOCK3_50]

# Set Clock Uncertainty
derive_clock_uncertainty