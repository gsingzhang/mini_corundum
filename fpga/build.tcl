# FPGA settings
set FPGA_PART "xczu7ev-ffvc1156-2-e"
set FPGA_TOP "fpga"
set PROJECT_NAME "fpga"

# Determine script directory (works on both Linux and Windows)
set script_dir [file normalize [file dirname [info script]]]

# Determine initial directory
set initial_dir [file normalize [pwd]]

# Build directory
set BUILD_DIR [file normalize [file join $initial_dir "build"]]

# mini_corundum root directory
set mini_corundum_root [file normalize [file dirname $initial_dir]]

# taxi library root directory (sibling to mini_corundum)
set taxi_root [file normalize [file join [file dirname $mini_corundum_root] "taxi"]]

# Verify paths
puts "Script directory : $script_dir"
puts "Working directory: $initial_dir"
puts "Build directory  : $BUILD_DIR"
puts "mini_corundum    : $mini_corundum_root"
puts "taxi library     : $taxi_root"

# Verify taxi RAM file exists
set taxi_ram_file [file normalize [file join $taxi_root "src" "prim" "rtl" "taxi_ram_1r1w_1c.sv"]]
if {![file exists $taxi_ram_file]} {
    puts "WARNING: taxi_ram_1r1w_1c.sv not found at $taxi_ram_file"
} else {
    puts "taxi RAM file    : OK"
}

# Files for synthesis (relative to mini_corundum_root)
set SYN_FILES [list \
    "rtl/fpga.v" \
    "rtl/fpga_core.v" \
    "rtl/eth_xcvr_phy_wrapper.v" \
    "rtl/eth_xcvr_phy_quad_wrapper.v" \
    "rtl/debounce_switch.v" \
    "rtl/sync_signal.v" \
    "rtl/ludp_protocol.sv" \
    "rtl/ludp_protocol_rx.sv" \
    "rtl/ludp_protocol_tx.sv" \
    "rtl/ludp_unified_buffer.sv" \
    "rtl/icmp_echo_reply.sv" \
    "rtl/taxi_axis_if.sv" \
    "rtl/taxi_axis_arb_mux.sv" \
    "rtl/taxi_arbiter.sv" \
    "rtl/taxi_penc.sv" \
    "lib/eth/rtl/eth_mac_10g_fifo.v" \
    "lib/eth/rtl/eth_mac_10g.v" \
    "lib/eth/rtl/axis_xgmii_rx_64.v" \
    "lib/eth/rtl/axis_xgmii_tx_64.v" \
    "lib/eth/rtl/eth_phy_10g.v" \
    "lib/eth/rtl/eth_phy_10g_rx.v" \
    "lib/eth/rtl/eth_phy_10g_rx_if.v" \
    "lib/eth/rtl/eth_phy_10g_rx_frame_sync.v" \
    "lib/eth/rtl/eth_phy_10g_rx_ber_mon.v" \
    "lib/eth/rtl/eth_phy_10g_rx_watchdog.v" \
    "lib/eth/rtl/eth_phy_10g_tx.v" \
    "lib/eth/rtl/eth_phy_10g_tx_if.v" \
    "lib/eth/rtl/xgmii_baser_dec_64.v" \
    "lib/eth/rtl/xgmii_baser_enc_64.v" \
    "lib/eth/rtl/lfsr.v" \
    "lib/eth/rtl/eth_axis_rx.v" \
    "lib/eth/rtl/eth_axis_tx.v" \
    "lib/eth/rtl/udp_complete_64.v" \
    "lib/eth/rtl/udp_checksum_gen_64.v" \
    "lib/eth/rtl/udp_64.v" \
    "lib/eth/rtl/udp_ip_rx_64.v" \
    "lib/eth/rtl/udp_ip_tx_64.v" \
    "lib/eth/rtl/ip_complete_64.v" \
    "lib/eth/rtl/ip_64.v" \
    "lib/eth/rtl/ip_eth_rx_64.v" \
    "lib/eth/rtl/ip_eth_tx_64.v" \
    "lib/eth/rtl/ip_arb_mux.v" \
    "lib/eth/rtl/arp.v" \
    "lib/eth/rtl/arp_cache.v" \
    "lib/eth/rtl/arp_eth_rx.v" \
    "lib/eth/rtl/arp_eth_tx.v" \
    "lib/eth/rtl/eth_arb_mux.v" \
    "lib/eth/lib/axis/rtl/arbiter.v" \
    "lib/eth/lib/axis/rtl/priority_encoder.v" \
    "lib/eth/lib/axis/rtl/axis_fifo.v" \
    "lib/eth/lib/axis/rtl/axis_async_fifo.v" \
    "lib/eth/lib/axis/rtl/axis_async_fifo_adapter.v" \
    "lib/eth/lib/axis/rtl/sync_reset.v" \
]

# External library files (absolute path)
set EXT_FILES [list \
    $taxi_ram_file \
]

# XDC files (relative to mini_corundum_root)
set XDC_FILES [list \
    "fpga.xdc" \
]

# IP TCL files (relative to mini_corundum_root)
set IP_TCL_FILES [list \
    "ip/eth_xcvr_gt.tcl" \
]

# Other TCL constraint files (relative to mini_corundum_root)
set CONSTRAINT_TCL_FILES [list \
    "lib/eth/syn/vivado/eth_mac_fifo.tcl" \
    "lib/eth/lib/axis/syn/vivado/axis_async_fifo.tcl" \
    "lib/eth/lib/axis/syn/vivado/sync_reset.tcl" \
]

# Function to get absolute path relative to mini_corundum_root
proc get_abs_path {file} {
    global mini_corundum_root
    return [file normalize [file join $mini_corundum_root $file]]
}

# Clean and create build directory
file delete -force $BUILD_DIR
file mkdir $BUILD_DIR
cd $BUILD_DIR

# Set part first
set_part $FPGA_PART

# Read verilog files
set SYN_FILES_ABS [list]
foreach file $SYN_FILES {
    set abs_path [get_abs_path $file]
    if {![file exists $abs_path]} {
        puts "WARNING: Source file not found: $abs_path"
    }
    lappend SYN_FILES_ABS $abs_path
}
foreach file $EXT_FILES {
    if {![file exists $file]} {
        puts "WARNING: External file not found: $file"
    }
    lappend SYN_FILES_ABS $file
}
read_verilog $SYN_FILES_ABS

# Read XDC files
set XDC_FILES_ABS [list]
foreach file $XDC_FILES {
    set abs_path [get_abs_path $file]
    if {![file exists $abs_path]} {
        puts "WARNING: XDC file not found: $abs_path"
    }
    lappend XDC_FILES_ABS $abs_path
}
read_xdc $XDC_FILES_ABS

# Source IP TCL files to create IPs
foreach file $IP_TCL_FILES {
    set abs_path [get_abs_path $file]
    if {![file exists $abs_path]} {
        puts "WARNING: IP TCL file not found: $abs_path"
    }
    source $abs_path
}

# Generate IP output products
generate_target all [get_ips]

# Synthesize IPs
synth_ip [get_ips]

# Set top module
set_property top $FPGA_TOP [current_fileset]

# Synthesis
synth_design -top $FPGA_TOP -part $FPGA_PART

# Source constraint TCL files after synthesis
foreach file $CONSTRAINT_TCL_FILES {
    set abs_path [get_abs_path $file]
    if {![file exists $abs_path]} {
        puts "WARNING: Constraint TCL file not found: $abs_path"
    }
    source $abs_path
}

# Optimization
opt_design

# Placement
place_design

# Physical optimization
phys_opt_design

# Routing
route_design

# Write checkpoints
write_checkpoint -force "${PROJECT_NAME}_post_route.dcp"

# Generate bitstream
write_bitstream -force "${PROJECT_NAME}.bit"

puts "Bitstream generated successfully at [file normalize "${PROJECT_NAME}.bit"]"

# Copy bitstream to fpga directory
set copy_target [file normalize [file join $initial_dir "${PROJECT_NAME}.bit"]]
file copy -force "${PROJECT_NAME}.bit" $copy_target

puts "Bitstream copied to fpga directory: $copy_target"

exit
