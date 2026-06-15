# VCS Makefile for fpga_core testbench (UVM-like layered architecture)
#
# Usage:
#   make sim        - Run all tests (batch simulation)
#   make sim TEST=1 - Run specific test (1-7 or name)
#   make sim-vcd    - Run with VCD waveform
#   make clean      - Remove build artifacts

TB_TOP = tb_fpga_core
DUT = fpga_core

RTL_DIR = ../rtl
LIB_ETH_DIR = $(RTL_DIR)/lib_eth
LIB_AXIS_DIR = $(RTL_DIR)/lib_axis
TB_DIR = .
TB_LUDP_DIR = ./ludp_tb

VERILOG_SOURCES += $(RTL_DIR)/taxi_axis_if.sv
VERILOG_SOURCES += $(RTL_DIR)/taxi_axis_arb_mux.sv
VERILOG_SOURCES += $(RTL_DIR)/taxi_arbiter.sv
VERILOG_SOURCES += $(RTL_DIR)/taxi_penc.sv
VERILOG_SOURCES += $(RTL_DIR)/ludp_protocol.sv
VERILOG_SOURCES += $(RTL_DIR)/ludp_protocol_rx.sv
VERILOG_SOURCES += $(RTL_DIR)/ludp_protocol_tx.sv
VERILOG_SOURCES += $(RTL_DIR)/ludp_tx_dma.sv
VERILOG_SOURCES += $(RTL_DIR)/ludp_tx_scheduler.sv
VERILOG_SOURCES += $(RTL_DIR)/icmp_echo_reply.sv
VERILOG_SOURCES += $(RTL_DIR)/$(DUT).v
VERILOG_SOURCES += $(RTL_DIR)/taxi_prim/taxi_ram_1r1w_1c.sv
VERILOG_SOURCES += $(LIB_ETH_DIR)/eth_mac_10g_fifo.v
VERILOG_SOURCES += $(LIB_ETH_DIR)/eth_mac_10g.v
VERILOG_SOURCES += $(LIB_ETH_DIR)/axis_xgmii_rx_64.v
VERILOG_SOURCES += $(LIB_ETH_DIR)/axis_xgmii_tx_64.v
VERILOG_SOURCES += $(LIB_ETH_DIR)/eth_phy_10g.v
VERILOG_SOURCES += $(LIB_ETH_DIR)/eth_phy_10g_rx.v
VERILOG_SOURCES += $(LIB_ETH_DIR)/eth_phy_10g_rx_if.v
VERILOG_SOURCES += $(LIB_ETH_DIR)/eth_phy_10g_rx_frame_sync.v
VERILOG_SOURCES += $(LIB_ETH_DIR)/eth_phy_10g_rx_ber_mon.v
VERILOG_SOURCES += $(LIB_ETH_DIR)/eth_phy_10g_rx_watchdog.v
VERILOG_SOURCES += $(LIB_ETH_DIR)/eth_phy_10g_tx.v
VERILOG_SOURCES += $(LIB_ETH_DIR)/eth_phy_10g_tx_if.v
VERILOG_SOURCES += $(LIB_ETH_DIR)/xgmii_baser_dec_64.v
VERILOG_SOURCES += $(LIB_ETH_DIR)/xgmii_baser_enc_64.v
VERILOG_SOURCES += $(LIB_ETH_DIR)/lfsr.v
VERILOG_SOURCES += $(LIB_ETH_DIR)/eth_axis_rx.v
VERILOG_SOURCES += $(LIB_ETH_DIR)/eth_axis_tx.v
VERILOG_SOURCES += $(LIB_ETH_DIR)/udp_complete_64.v
VERILOG_SOURCES += $(LIB_ETH_DIR)/udp_checksum_gen_64.v
VERILOG_SOURCES += $(LIB_ETH_DIR)/udp_64.v
VERILOG_SOURCES += $(LIB_ETH_DIR)/udp_ip_rx_64.v
VERILOG_SOURCES += $(LIB_ETH_DIR)/udp_ip_tx_64.v
VERILOG_SOURCES += $(LIB_ETH_DIR)/ip_complete_64.v
VERILOG_SOURCES += $(LIB_ETH_DIR)/ip_64.v
VERILOG_SOURCES += $(LIB_ETH_DIR)/ip_eth_rx_64.v
VERILOG_SOURCES += $(LIB_ETH_DIR)/ip_eth_tx_64.v
VERILOG_SOURCES += $(LIB_ETH_DIR)/ip_arb_mux.v
VERILOG_SOURCES += $(LIB_ETH_DIR)/arp.v
VERILOG_SOURCES += $(LIB_ETH_DIR)/arp_cache.v
VERILOG_SOURCES += $(LIB_ETH_DIR)/arp_eth_rx.v
VERILOG_SOURCES += $(LIB_ETH_DIR)/arp_eth_tx.v
VERILOG_SOURCES += $(LIB_ETH_DIR)/eth_arb_mux.v
VERILOG_SOURCES += $(LIB_AXIS_DIR)/arbiter.v
VERILOG_SOURCES += $(LIB_AXIS_DIR)/priority_encoder.v
VERILOG_SOURCES += $(LIB_AXIS_DIR)/axis_fifo.v
VERILOG_SOURCES += $(LIB_AXIS_DIR)/axis_async_fifo.v
VERILOG_SOURCES += $(LIB_AXIS_DIR)/axis_async_fifo_adapter.v
VERILOG_SOURCES += $(LIB_AXIS_DIR)/sync_reset.v

# UVM-like testbench components (order matters for package compilation)
VERILOG_SOURCES += $(TB_LUDP_DIR)/ludp_tb_pkg.sv
VERILOG_SOURCES += $(TB_LUDP_DIR)/xgmii_if.sv
VERILOG_SOURCES += $(TB_LUDP_DIR)/dut_ctrl_if.sv
VERILOG_SOURCES += $(TB_LUDP_DIR)/ludp_driver.sv
VERILOG_SOURCES += $(TB_LUDP_DIR)/ludp_monitor.sv
VERILOG_SOURCES += $(TB_LUDP_DIR)/ludp_sequencer.sv
VERILOG_SOURCES += $(TB_LUDP_DIR)/ludp_scoreboard.sv
VERILOG_SOURCES += $(TB_LUDP_DIR)/ludp_coverage.sv
VERILOG_SOURCES += $(TB_LUDP_DIR)/ludp_env.sv
VERILOG_SOURCES += $(TB_LUDP_DIR)/ludp_test_lib.sv

# Top-level testbench
VERILOG_SOURCES += $(TB_DIR)/tb_fpga_core.sv

VCS = vcs
VCS_BASE_FLAGS = -full64 -sverilog -timescale=1ns/1ps \
    -debug_access+all -kdb \
    +v2k \
    +v2k_generate \
    +libext+.v+.sv \
    -ignore initializer_driver_checks \
    -CFLAGS "-DVCS" \
    -f filelist.f \
    -top $(TB_TOP) \
    -o simv

SIMV = ./simv

TEST_ARGS =

.PHONY: all compile compile-vcd sim sim-vcd clean distclean help

all: sim

help:
	@echo "VCS Makefile for fpga_core testbench (UVM-like architecture)"
	@echo ""
	@echo "Targets:"
	@echo "  make sim        - Run all tests"
	@echo "  make sim TEST=1 - Run test 1 (protocol_basics)"
	@echo "  make sim TEST=2 - Run test 2 (cmd_lifecycle)"
	@echo "  make sim TEST=3 - Run test 3 (credit_flow)"
	@echo "  make sim TEST=4 - Run test 4 (data_integrity)"
	@echo "  make sim TEST=5 - Run test 5 (retransmission)"
	@echo "  make sim TEST=6 - Run test 6 (error_resilience)"
	@echo "  make sim TEST=7 - Run test 7 (internal_mechanisms)"
	@echo "  make sim-vcd    - Run with VCD waveform"
	@echo "  make clean      - Remove build artifacts"

filelist.f: Makefile
	@echo "Generating filelist..."
	@rm -f filelist.f
	@for f in $(VERILOG_SOURCES); do echo "$$f" >> filelist.f; done

compile: filelist.f
	$(VCS) $(VCS_BASE_FLAGS)

compile-vcd: filelist.f
	$(VCS) $(VCS_BASE_FLAGS) +define+VCD_DUMP

sim: compile
	$(SIMV) -no_save $(TEST_ARGS)

sim-test: compile
	$(SIMV) -no_save +TEST=$(TEST)

sim-vcd: compile-vcd
	@echo ""
	@echo "========================================"
	@echo "Running with VCD waveform..."
	@echo "========================================"
	$(SIMV) -no_save -l sim-vcd.log $(TEST_ARGS)
	@echo ""
	@echo "========================================"
	@if [ -f $(TB_TOP).vcd ]; then \
		echo "VCD waveform generated: $(TB_TOP).vcd"; \
		echo "View with: gtkwave $(TB_TOP).vcd &"; \
	else \
		echo "WARNING: VCD file not generated."; \
	fi
	@echo "========================================"

sim-dve: filelist.f
	$(VCS) $(VCS_BASE_FLAGS) +define+VPD_DUMP
	$(SIMV) -no_save -l sim-dve.log $(TEST_ARGS)

sim-verdi: filelist.f
	$(VCS) $(VCS_BASE_FLAGS) +define+FSDB_DUMP
	$(SIMV) -no_save -l sim-verdi.log $(TEST_ARGS)

clean:
	rm -rf simv simv.daidir csrc
	rm -rf vc_hdrs.h .vlogansetup.args .vlogansetup.env
	rm -f filelist.f
	rm -f *.vpd *.vcd *.fsdb
	rm -rf verdiLog novas* *.rc
	rm -f ucli.key
	rm -rf AN.DB
	rm -f sim-*.log
	rm -f dve.ucli
	rm -rf DVEfiles

distclean: clean
	rm -rf DVEfiles
	rm -rf verdiLog
