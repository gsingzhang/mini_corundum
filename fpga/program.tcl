# Cross-platform FPGA programming script
# Resolves bitstream path relative to script location

# Determine script directory
set script_dir [file normalize [file dirname [info script]]]
set initial_dir [file normalize [pwd]]

# Look for bitstream - prefer script directory, then working directory
set bitstream_path [file normalize [file join $script_dir "fpga.bit"]]
if {![file exists $bitstream_path]} {
    set bitstream_path [file normalize [file join $initial_dir "fpga.bit"]]
}
if {![file exists $bitstream_path]} {
    puts "ERROR: Bitstream not found at:"
    puts "  $script_dir/fpga.bit"
    puts "  $initial_dir/fpga.bit"
    puts "Please run build.tcl first to generate the bitstream."
    exit 1
}

puts "Bitstream path: $bitstream_path"

open_hw_manager
connect_hw_server -allow_non_jtag
open_hw_target
current_hw_device [lindex [get_hw_devices] 0]
set_property PROGRAM.FILE $bitstream_path [current_hw_device]
program_hw_devices [current_hw_device]
close_hw_manager

puts "FPGA programming completed successfully."

exit
