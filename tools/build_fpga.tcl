# Vivado 2025.2; creates a NEW local project and does not access a board.
set repo [file normalize [file join [file dirname [info script]] ..]]
source [file join $repo fpga create_project.tcl]
launch_runs impl_1 -to_step write_bitstream -jobs 1
wait_on_run impl_1
if {![string match {*write_bitstream Complete*} [get_property STATUS [get_runs impl_1]]]} {error "Implementation incomplete"}
open_run impl_1
set out [file join $repo fpga generated]
file mkdir $out
report_timing_summary -file [file join $out timing.rpt]
report_drc -file [file join $out drc.rpt]
report_cdc -file [file join $out cdc.rpt]
report_utilization -file [file join $out utilization.rpt]
foreach option {-setup -hold} {
 set p [get_timing_paths -quiet -max_paths 1 $option]
 if {[llength $p]==0 || [get_property SLACK $p]<0} {error "Timing failed; inspect generated reports"}
}
file copy -force [file join [get_property DIRECTORY [get_runs impl_1]] system_wrapper.bit] [file join $out rebuilt.bit]
write_hw_platform -fixed -include_bit -force -file [file join $out rebuilt.xsa]
puts "REBUILT_ARTIFACTS_SEPARATE -- review before replacing a sealed release; no board download"
