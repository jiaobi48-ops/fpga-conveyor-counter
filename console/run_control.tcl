set lcd_root [file normalize [file dirname [info script]]]
if {[info exists ::env(FPGA_PYTHON)]} {set lcd_python $::env(FPGA_PYTHON)} else {set lcd_python {python}}
puts [exec $lcd_python -I -X utf8 [file join $lcd_root verify_download.py]]
namespace eval xsdb {
    set existing {}
    catch {set existing [targets -target-properties -nocase -filter {name =~ "ARM*#0"}]}
    if {[llength $existing]==0} {connect -url tcp:127.0.0.1:3121}
    set cpus [targets -target-properties -nocase -filter {name =~ "ARM*#0"}]
    set pls [targets -target-properties -nocase -filter {name =~ "*xc7z015*"}]
    if {[llength $cpus]!=1 || [llength $pls]!=1} {error "Expected exactly one Z15 with ARM core0; no programming performed"}
    targets -set -nocase -filter {name =~ "ARM*#0"}
    rst -system
    after 1000
    targets -set -nocase -filter {name =~ "*xc7z015*"}
    fpga -file [file join $::lcd_root hardware camera_vision_integrated_v14.bit]
    targets -set -nocase -filter {name =~ "ARM*#0"}
    source [file join $::lcd_root hardware ps7_init.tcl]
    ps7_init
    ps7_post_config
    dow [file join $::lcd_root build camera_control_console.elf]
    con
}
puts "CAMERA_CONTROL_CONSOLE_STARTED -- fixed manual controls, starts paused; UART 115200"
