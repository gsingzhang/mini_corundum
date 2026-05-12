# Makefile for mini_corundum

CORUNDUM_DIR = /home/gxzhang/gx/prj/corundum
ETH_LIB = $(CORUNDUM_DIR)/fpga/lib/eth/rtl
AXI_LIB = $(CORUNDUM_DIR)/fpga/lib/axi/rtl
AXIS_LIB = $(CORUNDUM_DIR)/fpga/lib/axis/rtl

SRC = rtl/mini_corundum_top.v \
      rtl/cmd_stream_app.v \
      rtl/host_network_stack.v \
      rtl/udp_complete_64_local.v \
      rtl/ip_complete_64_local.v \
      $(ETH_LIB)/eth_axis_rx.v \
      $(ETH_LIB)/eth_axis_tx.v \
      $(ETH_LIB)/udp_complete_64.v \
      $(ETH_LIB)/udp_64.v \
      $(ETH_LIB)/udp_ip_rx_64.v \
      $(ETH_LIB)/udp_ip_tx_64.v \
      $(ETH_LIB)/udp_arb_mux.v \
      $(ETH_LIB)/udp_demux.v \
      $(ETH_LIB)/ip_complete_64.v \
      $(ETH_LIB)/ip_64.v \
      $(ETH_LIB)/ip_eth_rx_64.v \
      $(ETH_LIB)/ip_eth_tx_64.v \
      $(ETH_LIB)/ip_arb_mux.v \
      $(ETH_LIB)/ip_demux.v \
      $(ETH_LIB)/arp.v \
      $(ETH_LIB)/arp_cache.v \
      $(ETH_LIB)/arp_eth_rx.v \
      $(ETH_LIB)/arp_eth_tx.v \
      $(ETH_LIB)/eth_mac_10g_fifo.v \
      $(ETH_LIB)/eth_mac_10g.v \
      $(ETH_LIB)/eth_arb_mux.v \
      $(ETH_LIB)/axis_xgmii_rx_64.v \
      $(ETH_LIB)/axis_xgmii_tx_64.v \
      $(ETH_LIB)/xgmii_baser_dec_64.v \
      $(ETH_LIB)/xgmii_baser_enc_64.v \
      $(ETH_LIB)/lfsr.v \
      $(ETH_LIB)/ptp_clock_cdc.v \
      $(ETH_LIB)/axis_eth_fcs_check_64.v \
      $(ETH_LIB)/axis_eth_fcs_insert_64.v \
      $(ETH_LIB)/eth_mac_phy_10g.v \
      $(ETH_LIB)/eth_mac_phy_10g_rx.v \
      $(ETH_LIB)/eth_mac_phy_10g_tx.v \
      $(ETH_LIB)/eth_phy_10g_rx_if.v \
      $(ETH_LIB)/eth_phy_10g_tx_if.v \
      $(ETH_LIB)/eth_phy_10g_rx_ber_mon.v \
      $(ETH_LIB)/eth_phy_10g_rx_frame_sync.v \
      $(ETH_LIB)/eth_phy_10g_rx_watchdog.v \
      $(ETH_LIB)/axis_baser_rx_64.v \
      $(ETH_LIB)/axis_baser_tx_64.v \
      $(ETH_LIB)/udp_checksum_gen_64.v \
      $(AXIS_LIB)/axis_fifo.v \
      $(AXIS_LIB)/axis_async_fifo.v \
      $(AXIS_LIB)/axis_async_fifo_adapter.v \
      $(AXIS_LIB)/axis_adapter.v \
      $(AXIS_LIB)/arbiter.v \
      $(AXIS_LIB)/priority_encoder.v

TB_SRC = tb/tb_mini_corundum_top.v

# Vivado targets
check:
	xvlog -sv -i $(ETH_LIB) -i $(AXI_LIB) -i $(AXIS_LIB) $(SRC)
	xelab -debug typical mini_corundum_top -s mini_corundum_top_sim

sim:
	xvlog -sv -i $(ETH_LIB) -i $(AXI_LIB) -i $(AXIS_LIB) $(SRC) $(TB_SRC)
	xelab -debug typical tb_mini_corundum_top -s tb_sim
	xsim tb_sim -R

# VCS targets
vcs:
	vcs -full64 -sverilog -timescale=1ns/1ps -debug_access+all -kdb -lca \
	    +incdir+rtl +incdir+$(ETH_LIB) +incdir+$(AXI_LIB) +incdir+$(AXIS_LIB) \
	    $(SRC) $(TB_SRC)

vcs_sim: vcs
	./simv -ucli -do vcs_run.tcl

verdi:
	verdi -ssf tb.fsdb &

clean:
	rm -rf xsim.dir *.log *.pb *.jou *.vcd simv* csrc *.key *.fsdb verdiLog novas* DVEfiles
