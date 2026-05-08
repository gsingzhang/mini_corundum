# FPGA settings
FPGA_PART = xczu7ev-ffvc1156-2-e
FPGA_TOP = fpga
FPGA_ARCH = zynquplus

# Files for synthesis
SYN_FILES = rtl/fpga.v
SYN_FILES += ../rtl/mini_corundum_top.v
SYN_FILES += ../rtl/cmd_stream_app.v
SYN_FILES += $(CORUNDUM_DIR)/fpga/lib/eth/rtl/eth_axis_rx.v
SYN_FILES += $(CORUNDUM_DIR)/fpga/lib/eth/rtl/eth_axis_tx.v
SYN_FILES += $(CORUNDUM_DIR)/fpga/lib/eth/rtl/udp_complete_64.v
SYN_FILES += $(CORUNDUM_DIR)/fpga/lib/eth/rtl/udp_64.v
SYN_FILES += $(CORUNDUM_DIR)/fpga/lib/eth/rtl/udp_ip_rx_64.v
SYN_FILES += $(CORUNDUM_DIR)/fpga/lib/eth/rtl/udp_ip_tx_64.v
SYN_FILES += $(CORUNDUM_DIR)/fpga/lib/eth/rtl/udp_arb_mux.v
SYN_FILES += $(CORUNDUM_DIR)/fpga/lib/eth/rtl/udp_demux.v
SYN_FILES += $(CORUNDUM_DIR)/fpga/lib/eth/rtl/ip_complete_64.v
SYN_FILES += $(CORUNDUM_DIR)/fpga/lib/eth/rtl/ip_64.v
SYN_FILES += $(CORUNDUM_DIR)/fpga/lib/eth/rtl/ip_eth_rx_64.v
SYN_FILES += $(CORUNDUM_DIR)/fpga/lib/eth/rtl/ip_eth_tx_64.v
SYN_FILES += $(CORUNDUM_DIR)/fpga/lib/eth/rtl/ip_arb_mux.v
SYN_FILES += $(CORUNDUM_DIR)/fpga/lib/eth/rtl/ip_demux.v
SYN_FILES += $(CORUNDUM_DIR)/fpga/lib/eth/rtl/arp.v
SYN_FILES += $(CORUNDUM_DIR)/fpga/lib/eth/rtl/arp_cache.v
SYN_FILES += $(CORUNDUM_DIR)/fpga/lib/eth/rtl/arp_eth_rx.v
SYN_FILES += $(CORUNDUM_DIR)/fpga/lib/eth/rtl/arp_eth_tx.v
SYN_FILES += $(CORUNDUM_DIR)/fpga/lib/eth/rtl/eth_mac_10g_fifo.v
SYN_FILES += $(CORUNDUM_DIR)/fpga/lib/eth/rtl/eth_mac_10g.v
SYN_FILES += $(CORUNDUM_DIR)/fpga/lib/eth/rtl/eth_arb_mux.v
SYN_FILES += $(CORUNDUM_DIR)/fpga/lib/eth/rtl/axis_xgmii_rx_64.v
SYN_FILES += $(CORUNDUM_DIR)/fpga/lib/eth/rtl/axis_xgmii_tx_64.v
SYN_FILES += $(CORUNDUM_DIR)/fpga/lib/eth/rtl/xgmii_baser_dec_64.v
SYN_FILES += $(CORUNDUM_DIR)/fpga/lib/eth/rtl/xgmii_baser_enc_64.v
SYN_FILES += $(CORUNDUM_DIR)/fpga/lib/eth/rtl/lfsr.v
SYN_FILES += $(CORUNDUM_DIR)/fpga/lib/eth/rtl/ptp_clock_cdc.v
SYN_FILES += $(CORUNDUM_DIR)/fpga/lib/eth/rtl/axis_eth_fcs_check_64.v
SYN_FILES += $(CORUNDUM_DIR)/fpga/lib/eth/rtl/axis_eth_fcs_insert_64.v
SYN_FILES += $(CORUNDUM_DIR)/fpga/lib/eth/rtl/eth_mac_phy_10g.v
SYN_FILES += $(CORUNDUM_DIR)/fpga/lib/eth/rtl/eth_mac_phy_10g_rx.v
SYN_FILES += $(CORUNDUM_DIR)/fpga/lib/eth/rtl/eth_mac_phy_10g_tx.v
SYN_FILES += $(CORUNDUM_DIR)/fpga/lib/eth/rtl/eth_phy_10g_rx_if.v
SYN_FILES += $(CORUNDUM_DIR)/fpga/lib/eth/rtl/eth_phy_10g_tx_if.v
SYN_FILES += $(CORUNDUM_DIR)/fpga/lib/eth/rtl/eth_phy_10g_rx_ber_mon.v
SYN_FILES += $(CORUNDUM_DIR)/fpga/lib/eth/rtl/eth_phy_10g_rx_frame_sync.v
SYN_FILES += $(CORUNDUM_DIR)/fpga/lib/eth/rtl/eth_phy_10g_rx_watchdog.v
SYN_FILES += $(CORUNDUM_DIR)/fpga/lib/eth/rtl/axis_baser_rx_64.v
SYN_FILES += $(CORUNDUM_DIR)/fpga/lib/eth/rtl/axis_baser_tx_64.v
SYN_FILES += $(CORUNDUM_DIR)/fpga/lib/eth/rtl/udp_checksum_gen_64.v
SYN_FILES += $(CORUNDUM_DIR)/fpga/lib/axis/rtl/axis_fifo.v
SYN_FILES += $(CORUNDUM_DIR)/fpga/lib/axis/rtl/axis_async_fifo.v
SYN_FILES += $(CORUNDUM_DIR)/fpga/lib/axis/rtl/axis_async_fifo_adapter.v
SYN_FILES += $(CORUNDUM_DIR)/fpga/lib/axis/rtl/axis_adapter.v
SYN_FILES += $(CORUNDUM_DIR)/fpga/lib/axis/rtl/arbiter.v
SYN_FILES += $(CORUNDUM_DIR)/fpga/lib/axis/rtl/priority_encoder.v

SYN_FILES += $(CORUNDUM_DIR)/fpga/common/rtl/eth_xcvr_phy_10g_gty_wrapper.v
SYN_FILES += $(CORUNDUM_DIR)/fpga/common/rtl/eth_xcvr_phy_10g_gty_quad_wrapper.v

# XDC files
XDC_FILES = fpga.xdc
XDC_FILES += $(CORUNDUM_DIR)/fpga/common/syn/vivado/eth_xcvr_phy_10g_gty_wrapper.tcl

# IP
IP_TCL_FILES = ip/eth_xcvr_gth.tcl

# Corundum Path
CORUNDUM_DIR ?= /home/gxzhang/gx/prj/corundum

include $(CORUNDUM_DIR)/fpga/common/vivado.mk

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
