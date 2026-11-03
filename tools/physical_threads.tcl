# Vivado supports up to eight implementation worker threads on this platform.
set_param general.maxThreads 8
puts "IMPLEMENTATION_THREADS [get_param general.maxThreads]"
