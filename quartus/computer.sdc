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

# Reset synchronizers assert asynchronously but release through clocked stages.
# Exempt only their asynchronous control pins; stage-to-stage paths stay timed.
foreach reset_sync_instance {u_reset_50 u_reset_pixel} {
  set reset_sync_aclr_pins [get_pins -compatibility_mode -nocase -nowarn "*${reset_sync_instance}|*|aclr"]
  set reset_sync_clrn_pins [get_pins -compatibility_mode -nocase -nowarn "*${reset_sync_instance}|*|clrn"]

  if {[get_collection_size $reset_sync_aclr_pins] > 0} {
    set_false_path -to $reset_sync_aclr_pins
  }

  if {[get_collection_size $reset_sync_clrn_pins] > 0} {
    set_false_path -to $reset_sync_clrn_pins
  }

  if {[get_collection_size $reset_sync_aclr_pins] == 0 &&
      [get_collection_size $reset_sync_clrn_pins] == 0} {
    post_message -type critical_warning "No asynchronous-control pins matched for $reset_sync_instance"
  }
}
