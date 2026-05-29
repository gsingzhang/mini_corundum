# Debug script to check paths
puts "Current directory: [pwd]"
puts "Script info: [info script]"
set script_dir [file dirname [info script]]
puts "Script dir: $script_dir"
set mini_corundum_root [file dirname $script_dir]
puts "mini_corundum root: $mini_corundum_root"
set corundum_root [file dirname $mini_corundum_root]
puts "corundum root: $corundum_root"

# Check if paths exist
puts "\nChecking paths:"
set test_path [file join $corundum_root "mini_corundum/rtl/fpga.v"]
puts "Test path 1: $test_path - exists? [file exists $test_path]"
set test_path2 [file join $corundum_root "corundum/fpga/lib/eth/rtl/eth_mac_10g_fifo.v"]
puts "Test path 2: $test_path2 - exists? [file exists $test_path2]"
