set_param general.maxThreads 4
set native_ooc_xdc [file normalize [file join [file dirname [info script]] .. fpga constraints vision_ooc.xdc]]
read_xdc -mode out_of_context $native_ooc_xdc
puts "NATIVE_SYNTH_CLOCK_BUDGET 12ns-margin/40ns; implemented clocks 75MHz/25MHz"

