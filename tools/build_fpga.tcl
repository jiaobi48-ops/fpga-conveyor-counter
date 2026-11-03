# Rebuild the integrated Zynq camera and counter project with Vivado 2025.2.
set repo [file normalize [file join [file dirname [info script]] ..]]
source [file join $repo fpga create_project.tcl]
set receipt [open [file join $repo rebuild project_path.txt] w]
puts $receipt [get_property DIRECTORY [current_project]]
close $receipt
set_property AUTO_INCREMENTAL_CHECKPOINT 0 [get_runs impl_1]
set_property INCREMENTAL_CHECKPOINT {} [get_runs impl_1]
set bd_source [file join [get_property DIRECTORY [current_project]] camera_vision_integrated_v14.gen sources_1 bd system synth system.v]
set fd [open $bd_source r];set netlist [read $fd];close $fd
set begin [string first " vision_system_bridge_0\n" $netlist]
if {$begin<0} {error "Algorithm instance missing from generated system"}
set last [string first ");" $netlist $begin]
set instance [string range $netlist $begin $last]
foreach pin {s_axis_tdata s_axis_tvalid s_axis_tuser s_axis_tlast} {
 if {![regexp "\\.$pin\\(\\w" $instance]} {error "Camera pin $pin is not connected to a live net"}
}
puts "PASS GENERATED_CAMERA_STREAM_CONNECTED"
launch_runs impl_1 -to_step write_bitstream -jobs 2
wait_on_run impl_1
source [file join $repo tools export_completed.tcl]
