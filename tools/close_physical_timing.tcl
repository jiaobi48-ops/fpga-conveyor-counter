# Post-route physical optimization and checkpoint export.
proc save_closed_physical_design {setup hold} {
 set run_dir [get_property DIRECTORY [get_runs impl_1]]
 write_checkpoint -force [file join $run_dir system_wrapper_postroute_physopt.dcp]
 report_timing_summary -file [file join $run_dir system_wrapper_timing_summary_routed.rpt]
 write_bitstream -force [file join $run_dir system_wrapper.bit]
 puts "PASS BOUNDED_PHYSICAL_REFINEMENT setup_ns=$setup hold_ns=$hold"
}
proc close_small_setup_miss {root} {
 set setup_path [get_timing_paths -quiet -setup -max_paths 1]
 set hold_path [get_timing_paths -quiet -hold -max_paths 1]
 if {[llength $setup_path]!=1 || [llength $hold_path]!=1} {return}
 set setup [get_property SLACK $setup_path]
 set hold [get_property SLACK $hold_path]
 if {$setup>=0 || $setup < -0.600 || $hold<0} {return}
 if {abs([get_property PERIOD [get_clocks clk_fpga_0]]-10.000)>0.001} {
  error "Physical refinement requires the actual 100 MHz algorithm clock"
 }
 set out [file join $root fpga generated]
 file mkdir $out
 set receipt [open [file join $out physical_closure.txt] w]
 puts $receipt "BEFORE setup_ns=$setup hold_ns=$hold"
 close $receipt
 foreach directive {AggressiveFanoutOpt AlternateFlowWithRetiming} {
  puts "BOUNDED_POST_ROUTE_REFINEMENT $directive setup_ns=$setup hold_ns=$hold"
  phys_opt_design -directive $directive
  set setup [get_property SLACK [get_timing_paths -quiet -setup -max_paths 1]]
  set hold [get_property SLACK [get_timing_paths -quiet -hold -max_paths 1]]
  set receipt [open [file join $out physical_closure.txt] a]
  puts $receipt "$directive setup_ns=$setup hold_ns=$hold"
  close $receipt
  if {$setup>=0 && $hold>=0} {
   save_closed_physical_design $setup $hold
   return
  }
 }
 # Apply temporary setup margin when user uncertainty is unset;
 # restore the default user uncertainty before reporting setup and hold.
 set original_xdc [file join $out before_physical_margin.xdc]
 write_xdc -force -exclude_physical $original_xdc
 set input [open $original_xdc r]
 set original_constraints [read $input]
 close $input
 if {![regexp -line {^\s*set_clock_uncertainty\s} $original_constraints]} {
  set algorithm_clock [get_clocks clk_fpga_0]
  puts "BOUNDED_POST_ROUTE_SETUP_MARGIN additional_ns=0.200"
  set_clock_uncertainty -setup -from $algorithm_clock -to $algorithm_clock 0.200
  set result [catch {phys_opt_design -directive AggressiveExplore} message options]
  set_clock_uncertainty -setup -from $algorithm_clock -to $algorithm_clock 0.000
  if {$result} {return -options $options $message}
  set setup [get_property SLACK [get_timing_paths -quiet -setup -max_paths 1]]
  set hold [get_property SLACK [get_timing_paths -quiet -hold -max_paths 1]]
  set receipt [open [file join $out physical_closure.txt] a]
  puts $receipt "AdditionalSetupMargin=0.200 restored_user_uncertainty=0.000 actual_setup_ns=$setup actual_hold_ns=$hold"
  close $receipt
  if {$setup>=0 && $hold>=0} {save_closed_physical_design $setup $hold;return}
 }
 # The exporter records the resulting setup and hold slack.
}
