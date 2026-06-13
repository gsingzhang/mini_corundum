# FPGA settings
FPGA_PART = xczu7ev-ffvc1156-2-e
FPGA_TOP = fpga
FPGA_ARCH = zynquplus

# Files for synthesis
SYN_FILES = rtl/fpga.v
SYN_FILES += rtl/fpga_core.v
SYN_FILES += rtl/eth_xcvr_phy_wrapper.v
SYN_FILES += rtl/eth_xcvr_phy_quad_wrapper.v
SYN_FILES += rtl/debounce_switch.v
SYN_FILES += rtl/sync_signal.v
SYN_FILES += rtl/ludp_protocol.sv
SYN_FILES += rtl/ludp_protocol_rx.sv
SYN_FILES += rtl/ludp_protocol_tx.sv
SYN_FILES += rtl/ludp_tx_buffer.sv
SYN_FILES += rtl/icmp_echo_reply.sv
SYN_FILES += rtl/taxi_axis_if.sv
SYN_FILES += rtl/taxi_axis_arb_mux.sv
SYN_FILES += rtl/taxi_arbiter.sv
SYN_FILES += rtl/taxi_penc.sv
SYN_FILES += rtl/lib_eth/eth_mac_10g_fifo.v
SYN_FILES += rtl/lib_eth/eth_mac_10g.v
SYN_FILES += rtl/lib_eth/axis_xgmii_rx_64.v
SYN_FILES += rtl/lib_eth/axis_xgmii_tx_64.v
SYN_FILES += rtl/lib_eth/eth_phy_10g.v
SYN_FILES += rtl/lib_eth/eth_phy_10g_rx.v
SYN_FILES += rtl/lib_eth/eth_phy_10g_rx_if.v
SYN_FILES += rtl/lib_eth/eth_phy_10g_rx_frame_sync.v
SYN_FILES += rtl/lib_eth/eth_phy_10g_rx_ber_mon.v
SYN_FILES += rtl/lib_eth/eth_phy_10g_rx_watchdog.v
SYN_FILES += rtl/lib_eth/eth_phy_10g_tx.v
SYN_FILES += rtl/lib_eth/eth_phy_10g_tx_if.v
SYN_FILES += rtl/lib_eth/xgmii_baser_dec_64.v
SYN_FILES += rtl/lib_eth/xgmii_baser_enc_64.v
SYN_FILES += rtl/lib_eth/lfsr.v
SYN_FILES += rtl/lib_eth/eth_axis_rx.v
SYN_FILES += rtl/lib_eth/eth_axis_tx.v
SYN_FILES += rtl/lib_eth/udp_complete_64.v
SYN_FILES += rtl/lib_eth/udp_checksum_gen_64.v
SYN_FILES += rtl/lib_eth/udp_64.v
SYN_FILES += rtl/lib_eth/udp_ip_rx_64.v
SYN_FILES += rtl/lib_eth/udp_ip_tx_64.v
SYN_FILES += rtl/lib_eth/ip_complete_64.v
SYN_FILES += rtl/lib_eth/ip_64.v
SYN_FILES += rtl/lib_eth/ip_eth_rx_64.v
SYN_FILES += rtl/lib_eth/ip_eth_tx_64.v
SYN_FILES += rtl/lib_eth/ip_arb_mux.v
SYN_FILES += rtl/lib_eth/arp.v
SYN_FILES += rtl/lib_eth/arp_cache.v
SYN_FILES += rtl/lib_eth/arp_eth_rx.v
SYN_FILES += rtl/lib_eth/arp_eth_tx.v
SYN_FILES += rtl/lib_eth/eth_arb_mux.v
SYN_FILES += rtl/lib_axis/arbiter.v
SYN_FILES += rtl/lib_axis/priority_encoder.v
SYN_FILES += rtl/lib_axis/axis_fifo.v
SYN_FILES += rtl/lib_axis/axis_async_fifo.v
SYN_FILES += rtl/lib_axis/axis_async_fifo_adapter.v
SYN_FILES += rtl/lib_axis/sync_reset.v

# Taxi RAM module (copied locally)
SYN_FILES += rtl/taxi_prim/taxi_ram_1r1w_1c.sv

# XDC files
XDC_FILES = fpga.xdc
XDC_FILES += fpga/syn/eth_mac_fifo.tcl
XDC_FILES += fpga/syn/axis_async_fifo.tcl
XDC_FILES += fpga/syn/sync_reset.tcl

# IP
IP_TCL_FILES += ip/eth_xcvr_gt.tcl

include ../common/vivado.mk

program: $(FPGA_TOP).bit
	echo "open_hw" > program.tcl
	echo "connect_hw_server" >> program.tcl
	echo "open_hw_target" >> program.tcl
	echo "current_hw_device [lindex [get_hw_devices] 0]" >> program.tcl
	echo "refresh_hw_device -update_hw_probes false [current_hw_device]" >> program.tcl
	echo "set_property PROGRAM.FILE {$(FPGA_TOP).bit} [current_hw_device]" >> program.tcl
	echo "program_hw_devices [current_hw_device]" >> program.tcl
	echo "exit" >> program.tcl
	vivado -nojournal -nolog -mode batch -source program.tcl
