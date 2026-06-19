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
puts "Build directory  : $BUILD_DIR"
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
    "rtl/ludp_tx_scheduler.sv" \
    "rtl/lib_axi/taxi_axi_if.sv" \
    "rtl/lib_axi/taxi_axi_ram.sv" \
    "rtl/lib_dma/axi_dma_wr.v" \
    "rtl/lib_dma/axi_dma_rd.v" \
    "rtl/lib_dma/ludp_dma_wrapper.sv" \
    "rtl/lib_axis/taxi_axis_async_fifo.sv" \
    "rtl/lib_sync/taxi_sync_reset.sv" \
    "rtl/lib_sync/taxi_sync_signal.sv" \
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

# Set part first
set_part $FPGA_PART

# Read verilog files
set SYN_FILES_ABS [list]
foreach file $SYN_FILES {
    set abs_path [get_abs_path $file]
    if {![file exists $abs_path]} {
        puts "WARNING: Source file not found: $abs_path — skipping"
        continue
    }
    lappend SYN_FILES_ABS $abs_path
}
read_verilog $SYN_FILES_ABS

# Read XDC files
set XDC_FILES_ABS [list]
foreach file $XDC_FILES {
    set abs_path [get_abs_path $file]
    if {![file exists $abs_path]} {
        puts "WARNING: XDC file not found: $abs_path — skipping"
        continue
    }
    lappend XDC_FILES_ABS $abs_path
}
read_xdc $XDC_FILES_ABS

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

# Synthesize IPs
synth_ip [get_ips]

# Set top module
set_property top $FPGA_TOP [current_fileset]

# Synthesis
synth_design -top $FPGA_TOP -part $FPGA_PART

# Source constraint TCL files after synthesis
foreach file $CONSTRAINT_TCL_FILES {
    set abs_path [file normalize [file join $initial_dir $file]]
    if {![file exists $abs_path]} {
        puts "WARNING: Constraint TCL file not found: $abs_path — skipping"
        continue
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

# Write project for GUI review
write_project -force "${PROJECT_NAME}"

puts "Bitstream generated successfully at [file normalize "${PROJECT_NAME}.bit"]"

# Copy bitstream to fpga directory
set copy_target [file normalize [file join $initial_dir "${PROJECT_NAME}.bit"]]
file copy -force "${PROJECT_NAME}.bit" $copy_target

puts "Bitstream copied to fpga directory: $copy_target"

set xpr_path [file normalize [file join $BUILD_DIR "${PROJECT_NAME}.xpr"]]
puts ""
puts "========================================"
puts " Project file: $xpr_path"
puts " Review with: vivado $xpr_path"
puts "========================================"

exit
