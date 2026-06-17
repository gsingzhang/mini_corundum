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

# Verify paths
puts "Script directory : $script_dir"
puts "Working directory: $initial_dir"
puts "Project directory: $BUILD_DIR"
puts "mini_corundum    : $mini_corundum_root"

# Files for synthesis (relative to mini_corundum_root)
set SYN_FILES [list \
    "rtl/fpga.v" \
    "rtl/fpga_core.sv" \
    "rtl/eth_xcvr_phy_wrapper.v" \
    "rtl/eth_xcvr_phy_quad_wrapper.v" \
    "rtl/debounce_switch.v" \
    "rtl/sync_signal.v" \
    "rtl/ludp_protocol.sv" \
    "rtl/ludp_protocol_rx.sv" \
    "rtl/ludp_protocol_tx.sv" \
    "rtl/ludp_tx_buffer.sv" \
    "rtl/ludp_tx_dma_axi.sv" \
    "rtl/ludp_tx_scheduler.sv" \
    "rtl/lib_axi/taxi_axi_if.sv" \
    "rtl/lib_axi/taxi_axi_ram.sv" \
    "rtl/icmp_echo_reply.sv" \
    "rtl/taxi_axis_if.sv" \
    "rtl/taxi_axis_arb_mux.sv" \
    "rtl/taxi_arbiter.sv" \
    "rtl/taxi_penc.sv" \
    "rtl/taxi_prim/taxi_ram_1r1w_1c.sv" \
    "rtl/lib_eth/eth_mac_10g_fifo.v" \
    "rtl/lib_eth/eth_mac_10g.v" \
    "rtl/lib_eth/axis_xgmii_rx_64.v" \
    "rtl/lib_eth/axis_xgmii_tx_64.v" \
    "rtl/lib_eth/eth_phy_10g.v" \
    "rtl/lib_eth/eth_phy_10g_rx.v" \
    "rtl/lib_eth/eth_phy_10g_rx_if.v" \
    "rtl/lib_eth/eth_phy_10g_rx_frame_sync.v" \
    "rtl/lib_eth/eth_phy_10g_rx_ber_mon.v" \
    "rtl/lib_eth/eth_phy_10g_rx_watchdog.v" \
    "rtl/lib_eth/eth_phy_10g_tx.v" \
    "rtl/lib_eth/eth_phy_10g_tx_if.v" \
    "rtl/lib_eth/xgmii_baser_dec_64.v" \
    "rtl/lib_eth/xgmii_baser_enc_64.v" \
    "rtl/lib_eth/lfsr.v" \
    "rtl/lib_eth/eth_axis_rx.v" \
    "rtl/lib_eth/eth_axis_tx.v" \
    "rtl/lib_eth/udp_complete_64.v" \
    "rtl/lib_eth/udp_checksum_gen_64.v" \
    "rtl/lib_eth/udp_64.v" \
    "rtl/lib_eth/udp_ip_rx_64.v" \
    "rtl/lib_eth/udp_ip_tx_64.v" \
    "rtl/lib_eth/ip_complete_64.v" \
    "rtl/lib_eth/ip_64.v" \
    "rtl/lib_eth/ip_eth_rx_64.v" \
    "rtl/lib_eth/ip_eth_tx_64.v" \
    "rtl/lib_eth/ip_arb_mux.v" \
    "rtl/lib_eth/arp.v" \
    "rtl/lib_eth/arp_cache.v" \
    "rtl/lib_eth/arp_eth_rx.v" \
    "rtl/lib_eth/arp_eth_tx.v" \
    "rtl/lib_eth/eth_arb_mux.v" \
    "rtl/lib_axis/arbiter.v" \
    "rtl/lib_axis/priority_encoder.v" \
    "rtl/lib_axis/axis_fifo.v" \
    "rtl/lib_axis/axis_async_fifo.v" \
    "rtl/lib_axis/axis_async_fifo_adapter.v" \
    "rtl/lib_axis/sync_reset.v" \
]

# External library files (copied locally)

# XDC files (relative to mini_corundum_root)
set XDC_FILES [list \
    "fpga.xdc" \
]

# IP TCL files (relative to mini_corundum_root)
set IP_TCL_FILES [list \
    "ip/eth_xcvr_gt.tcl" \
    "ip/ddr4_0.tcl" \
]

# Other TCL constraint files (relative to script/FPGA directory)
# These require an open design, so they should be sourced after synthesis
set CONSTRAINT_TCL_FILES [list \
    "syn/eth_mac_fifo.tcl" \
    "syn/axis_async_fifo.tcl" \
    "syn/sync_reset.tcl" \
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

# Create project
create_project -force $PROJECT_NAME $BUILD_DIR -part $FPGA_PART

# Set project properties
set_property "part" $FPGA_PART [current_project]
set_property "top" $FPGA_TOP [current_fileset]
set_property "target_language" "Verilog" [current_project]
set_property "simulator_language" "Mixed" [current_project]

# Add verilog files
set SYN_FILES_ABS [list]
foreach file $SYN_FILES {
    set abs_path [get_abs_path $file]
    if {![file exists $abs_path]} {
        puts "WARNING: Source file not found: $abs_path — skipping"
        continue
    }
    lappend SYN_FILES_ABS $abs_path
}
add_files -norecurse $SYN_FILES_ABS

# Add XDC files
set XDC_FILES_ABS [list]
foreach file $XDC_FILES {
    set abs_path [get_abs_path $file]
    if {![file exists $abs_path]} {
        puts "WARNING: XDC file not found: $abs_path — skipping"
        continue
    }
    lappend XDC_FILES_ABS $abs_path
}
add_files -fileset constrs_1 -norecurse $XDC_FILES_ABS

# Source IP TCL files to create IPs
foreach file $IP_TCL_FILES {
    set abs_path [get_abs_path $file]
    if {![file exists $abs_path]} {
        puts "WARNING: IP TCL file not found: $abs_path — skipping"
        continue
    }
    source $abs_path
}

# Generate IP output products
generate_target all [get_ips]

puts "Project created successfully at [file normalize "${PROJECT_NAME}.xpr"]"
puts "You can open the project with: vivado [file normalize "${PROJECT_NAME}.xpr"]"

exit
