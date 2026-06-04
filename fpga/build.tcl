# FPGA settings
set FPGA_PART "xczu7ev-ffvc1156-2-e"
set FPGA_TOP "fpga"
set PROJECT_NAME "fpga"

# Save initial directory (fpga directory)
set initial_dir [pwd]

# Build directory
set BUILD_DIR [file join $initial_dir "build"]

# mini_corundum root directory
set mini_corundum_root [file dirname $initial_dir]

# corundum root directory
set corundum_root [file dirname $mini_corundum_root]

# Files for synthesis (relative to corundum root)
set SYN_FILES [list \
    "mini_corundum/rtl/fpga.v" \
    "mini_corundum/rtl/fpga_core.v" \
    "mini_corundum/rtl/eth_xcvr_phy_wrapper.v" \
    "mini_corundum/rtl/eth_xcvr_phy_quad_wrapper.v" \
    "mini_corundum/rtl/debounce_switch.v" \
    "mini_corundum/rtl/sync_signal.v" \
    "mini_corundum/rtl/ludp_protocol.sv" \
    "mini_corundum/rtl/icmp_echo_reply.sv" \
    "corundum/fpga/lib/eth/rtl/eth_mac_10g_fifo.v" \
    "corundum/fpga/lib/eth/rtl/eth_mac_10g.v" \
    "corundum/fpga/lib/eth/rtl/axis_xgmii_rx_64.v" \
    "corundum/fpga/lib/eth/rtl/axis_xgmii_tx_64.v" \
    "corundum/fpga/lib/eth/rtl/eth_phy_10g.v" \
    "corundum/fpga/lib/eth/rtl/eth_phy_10g_rx.v" \
    "corundum/fpga/lib/eth/rtl/eth_phy_10g_rx_if.v" \
    "corundum/fpga/lib/eth/rtl/eth_phy_10g_rx_frame_sync.v" \
    "corundum/fpga/lib/eth/rtl/eth_phy_10g_rx_ber_mon.v" \
    "corundum/fpga/lib/eth/rtl/eth_phy_10g_rx_watchdog.v" \
    "corundum/fpga/lib/eth/rtl/eth_phy_10g_tx.v" \
    "corundum/fpga/lib/eth/rtl/eth_phy_10g_tx_if.v" \
    "corundum/fpga/lib/eth/rtl/xgmii_baser_dec_64.v" \
    "corundum/fpga/lib/eth/rtl/xgmii_baser_enc_64.v" \
    "corundum/fpga/lib/eth/rtl/lfsr.v" \
    "corundum/fpga/lib/eth/rtl/eth_axis_rx.v" \
    "corundum/fpga/lib/eth/rtl/eth_axis_tx.v" \
    "corundum/fpga/lib/eth/rtl/udp_complete_64.v" \
    "corundum/fpga/lib/eth/rtl/udp_checksum_gen_64.v" \
    "corundum/fpga/lib/eth/rtl/udp_64.v" \
    "corundum/fpga/lib/eth/rtl/udp_ip_rx_64.v" \
    "corundum/fpga/lib/eth/rtl/udp_ip_tx_64.v" \
    "corundum/fpga/lib/eth/rtl/ip_complete_64.v" \
    "corundum/fpga/lib/eth/rtl/ip_64.v" \
    "corundum/fpga/lib/eth/rtl/ip_eth_rx_64.v" \
    "corundum/fpga/lib/eth/rtl/ip_eth_tx_64.v" \
    "corundum/fpga/lib/eth/rtl/ip_arb_mux.v" \
    "corundum/fpga/lib/eth/rtl/arp.v" \
    "corundum/fpga/lib/eth/rtl/arp_cache.v" \
    "corundum/fpga/lib/eth/rtl/arp_eth_rx.v" \
    "corundum/fpga/lib/eth/rtl/arp_eth_tx.v" \
    "corundum/fpga/lib/eth/rtl/eth_arb_mux.v" \
    "corundum/fpga/lib/eth/lib/axis/rtl/arbiter.v" \
    "corundum/fpga/lib/eth/lib/axis/rtl/priority_encoder.v" \
    "corundum/fpga/lib/eth/lib/axis/rtl/axis_fifo.v" \
    "corundum/fpga/lib/eth/lib/axis/rtl/axis_async_fifo.v" \
    "corundum/fpga/lib/eth/lib/axis/rtl/axis_async_fifo_adapter.v" \
    "corundum/fpga/lib/eth/lib/axis/rtl/sync_reset.v" \
]

# XDC files (relative to corundum root)
set XDC_FILES [list \
    "mini_corundum/fpga.xdc" \
]

# IP TCL files (relative to corundum root)
set IP_TCL_FILES [list \
    "mini_corundum/ip/eth_xcvr_gt.tcl" \
]

# Other TCL constraint files (relative to corundum root)
set CONSTRAINT_TCL_FILES [list \
    "corundum/fpga/lib/eth/syn/vivado/eth_mac_fifo.tcl" \
    "corundum/fpga/lib/eth/lib/axis/syn/vivado/axis_async_fifo.tcl" \
    "corundum/fpga/lib/eth/lib/axis/syn/vivado/sync_reset.tcl" \
]

# Function to get absolute path relative to corundum_root
proc get_abs_path {file} {
    global corundum_root
    return [file normalize [file join $corundum_root $file]]
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
    lappend SYN_FILES_ABS [get_abs_path $file]
}
read_verilog $SYN_FILES_ABS

# Read XDC files
set XDC_FILES_ABS [list]
foreach file $XDC_FILES {
    lappend XDC_FILES_ABS [get_abs_path $file]
}
read_xdc $XDC_FILES_ABS

# Source IP TCL files to create IPs
foreach file $IP_TCL_FILES {
    source [get_abs_path $file]
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
    source [get_abs_path $file]
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
file copy -force "${PROJECT_NAME}.bit" [file join $initial_dir "${PROJECT_NAME}.bit"]

puts "Bitstream copied to fpga directory"

exit
