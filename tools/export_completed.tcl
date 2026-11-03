if {![string match {*write_bitstream Complete*} [get_property STATUS [get_runs impl_1]]]} {error "Implementation incomplete"}
open_run impl_1
set margin_restored 0
set margin_receipt [file join $repo fpga generated implementation_margin.txt]
if {[file exists $margin_receipt]} {
 set receipt_input [open $margin_receipt r]
 set margin_project [gets $receipt_input]
 close $receipt_input
 if {![string equal -nocase [file normalize $margin_project] [file normalize [get_property DIRECTORY [get_runs impl_1]]]]} {
  error "Implementation-margin receipt belongs to a different project"
 }
 set algorithm_clock [get_clocks clk_fpga_0]
 if {abs([get_property PERIOD $algorithm_clock]-10.000)>0.001} {error "Expected original 100MHz clock"}
 set_clock_uncertainty -setup -from $algorithm_clock -to $algorithm_clock 0.000
 set margin_restored 1
 puts "IMPLEMENTATION_SETUP_MARGIN_RESTORED original_user_uncertainty_ns=0.000"
}
# Export timing, methodology, initialized ROMs and the implemented platform.
set out [file join $repo fpga generated]
file mkdir $out
foreach {name period} {clk_fpga_0 13.333 clk_fpga_1 10.000 clk_out1_system_clk_wiz_0_0 40.000} {
 set actual [get_clocks -quiet $name]
 if {[llength $actual]!=1 || abs([get_property PERIOD $actual]-$period)>0.001} {
  error "Unexpected implemented clock $name; required period $period ns"
 }
}
report_clocks -file [file join $out clock_periods.rpt]
report_timing_summary -file [file join $out timing.rpt]
report_drc -file [file join $out drc.rpt]
report_cdc -file [file join $out cdc.rpt]
report_utilization -file [file join $out utilization.rpt]
report_utilization -hierarchical -hierarchical_depth 8 -file [file join $out hierarchy.rpt]
report_methodology -file [file join $out methodology.rpt]
report_clock_interaction -file [file join $out clocks.rpt]
report_timing -max_paths 20 -file [file join $out paths.rpt]
write_xdc -force -exclude_physical [file join $out constraints.xdc]
set timing_status PASS
foreach option {-setup -hold} {
 set p [get_timing_paths -quiet -max_paths 1 $option]
 if {[llength $p]==0} {error "Missing timing paths; inspect generated reports"}
 if {[get_property SLACK $p]<0} {set timing_status VIOLATIONS_RECORDED}
}
puts "TIMING_RESULT $timing_status setup_ns=[get_property SLACK [get_timing_paths -quiet -max_paths 1 -setup]] hold_ns=[get_property SLACK [get_timing_paths -quiet -max_paths 1 -hold]]"
if {$margin_restored} {
 set run_dir [get_property DIRECTORY [get_runs impl_1]]
 write_checkpoint -force [file join $run_dir system_wrapper_postroute_physopt.dcp]
 report_timing_summary -file [file join $run_dir system_wrapper_timing_summary_routed.rpt]
 write_bitstream -force [file join $run_dir system_wrapper.bit]
}
set rom_report [open [file join $out rom_init.txt] w]
set rom_count 0
set rom_initialized_words 0
foreach cell [get_cells -hierarchical -filter {REF_NAME =~ RAMB*}] {
 if {![string match {*static_test_source/rom/*} $cell]} {continue}
 incr rom_count
 set nonzero 0
 foreach property [list_property $cell] {
  if {![regexp {^INIT_[0-9A-F]{2}$} $property]} {continue}
  set value [get_property $property $cell]
  regsub {^[0-9]+'[hHbB]} $value {} payload
  if {[regexp {[1-9a-fA-F]} $payload]} {incr nonzero}
 }
 puts $rom_report "$cell NONZERO_INIT_WORDS=$nonzero"
 incr rom_initialized_words $nonzero
}
close $rom_report
if {$rom_count==0 || $rom_initialized_words==0} {error "Initialized scene ROM missing from implemented netlist"}
file copy -force [file join [get_property DIRECTORY [get_runs impl_1]] system_wrapper.bit] [file join $out rebuilt.bit]
write_hw_platform -fixed -include_bit -force -file [file join $out rebuilt.xsa]
puts "PASS ABC_V14_ARTIFACTS ROM=PASS bit_xsa=EXPORTED"

