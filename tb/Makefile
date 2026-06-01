# VCS Makefile for fpga_core testbench
# Supports both DVE and Verdi waveform viewing
#
# IMPORTANT NOTE ABOUT WAVEFORMS:
# This environment runs in a sandboxed/containerized setting where /proc
# access is restricted. VPD (DVE) and FSDB (Verdi) waveform dumping both
# require /proc for memory mapping and will segfault in this environment.
#
# WORKAROUND: Use 'make sim' for reliable batch simulation. To view
# waveforms, copy the compiled simv to a non-sandboxed machine and run
# with waveform dumping there.
#
# Alternatively, you can generate VCD format (which uses simpler I/O)
# by running: make sim-vcd
#
# Usage:
#   make sim        - Batch simulation without waveform (RELIABLE)
#   make sim-vcd    - Batch simulation with VCD waveform (may work)
#   make sim-dve    - Simulation with DVE/VPD waveform (WILL SEGFAULT)
#   make sim-verdi  - Simulation with Verdi/FSDB waveform (WILL SEGFAULT)
#   make clean      - Remove build artifacts

# Testbench settings
TB_TOP = tb_fpga_core
DUT = fpga_core

# Directories
RTL_DIR = ../rtl
LIB_DIR = ../lib
ETH_RTL_DIR = $(LIB_DIR)/eth/rtl
AXIS_RTL_DIR = $(LIB_DIR)/eth/lib/axis/rtl

# Source files
VERILOG_SOURCES += $(RTL_DIR)/ludp_protocol.sv
VERILOG_SOURCES += $(RTL_DIR)/$(DUT).v
VERILOG_SOURCES += $(ETH_RTL_DIR)/eth_mac_10g_fifo.v
VERILOG_SOURCES += $(ETH_RTL_DIR)/eth_mac_10g.v
VERILOG_SOURCES += $(ETH_RTL_DIR)/axis_xgmii_rx_64.v
VERILOG_SOURCES += $(ETH_RTL_DIR)/axis_xgmii_tx_64.v
VERILOG_SOURCES += $(ETH_RTL_DIR)/eth_phy_10g.v
VERILOG_SOURCES += $(ETH_RTL_DIR)/eth_phy_10g_rx.v
VERILOG_SOURCES += $(ETH_RTL_DIR)/eth_phy_10g_rx_if.v
VERILOG_SOURCES += $(ETH_RTL_DIR)/eth_phy_10g_rx_frame_sync.v
VERILOG_SOURCES += $(ETH_RTL_DIR)/eth_phy_10g_rx_ber_mon.v
VERILOG_SOURCES += $(ETH_RTL_DIR)/eth_phy_10g_rx_watchdog.v
VERILOG_SOURCES += $(ETH_RTL_DIR)/eth_phy_10g_tx.v
VERILOG_SOURCES += $(ETH_RTL_DIR)/eth_phy_10g_tx_if.v
VERILOG_SOURCES += $(ETH_RTL_DIR)/xgmii_baser_dec_64.v
VERILOG_SOURCES += $(ETH_RTL_DIR)/xgmii_baser_enc_64.v
VERILOG_SOURCES += $(ETH_RTL_DIR)/lfsr.v
VERILOG_SOURCES += $(ETH_RTL_DIR)/eth_axis_rx.v
VERILOG_SOURCES += $(ETH_RTL_DIR)/eth_axis_tx.v
VERILOG_SOURCES += $(ETH_RTL_DIR)/udp_complete_64.v
VERILOG_SOURCES += $(ETH_RTL_DIR)/udp_checksum_gen_64.v
VERILOG_SOURCES += $(ETH_RTL_DIR)/udp_64.v
VERILOG_SOURCES += $(ETH_RTL_DIR)/udp_ip_rx_64.v
VERILOG_SOURCES += $(ETH_RTL_DIR)/udp_ip_tx_64.v
VERILOG_SOURCES += $(ETH_RTL_DIR)/ip_complete_64.v
VERILOG_SOURCES += $(ETH_RTL_DIR)/ip_64.v
VERILOG_SOURCES += $(ETH_RTL_DIR)/ip_eth_rx_64.v
VERILOG_SOURCES += $(ETH_RTL_DIR)/ip_eth_tx_64.v
VERILOG_SOURCES += $(ETH_RTL_DIR)/ip_arb_mux.v
VERILOG_SOURCES += $(ETH_RTL_DIR)/arp.v
VERILOG_SOURCES += $(ETH_RTL_DIR)/arp_cache.v
VERILOG_SOURCES += $(ETH_RTL_DIR)/arp_eth_rx.v
VERILOG_SOURCES += $(ETH_RTL_DIR)/arp_eth_tx.v
VERILOG_SOURCES += $(ETH_RTL_DIR)/eth_arb_mux.v
VERILOG_SOURCES += $(AXIS_RTL_DIR)/arbiter.v
VERILOG_SOURCES += $(AXIS_RTL_DIR)/priority_encoder.v
VERILOG_SOURCES += $(AXIS_RTL_DIR)/axis_fifo.v
VERILOG_SOURCES += $(AXIS_RTL_DIR)/axis_async_fifo.v
VERILOG_SOURCES += $(AXIS_RTL_DIR)/axis_async_fifo_adapter.v
VERILOG_SOURCES += $(AXIS_RTL_DIR)/sync_reset.v

# Testbench
VERILOG_SOURCES += $(TB_TOP).v

# VCS settings
VCS = vcs
VCS_BASE_FLAGS = -full64 -sverilog -timescale=1ns/1ps \
    -debug_access+all -kdb \
    +v2k \
    +libext+.v+.sv \
    -CFLAGS "-DVCS" \
    -f filelist.f \
    -top $(TB_TOP) \
    -o simv

# Simulation executable
SIMV = ./simv

# Targets
.PHONY: all compile compile-vcd compile-dve compile-verdi \
        sim sim-vcd sim-dve sim-verdi clean distclean help

all: sim

help:
	@echo "VCS Makefile for fpga_core testbench"
	@echo ""
	@echo "Reliable targets:"
	@echo "  make sim        - Run batch simulation (no waveform)"
	@echo "  make sim-vcd    - Run with VCD waveform (simple format, may work)"
	@echo ""
	@echo "Waveform targets (require non-sandboxed environment):"
	@echo "  make sim-dve    - Run with DVE/VPD waveform"
	@echo "  make sim-verdi  - Run with Verdi/FSDB waveform"
	@echo ""
	@echo "Other targets:"
	@echo "  make clean      - Remove build artifacts"
	@echo "  make distclean  - Remove build artifacts + waveform files"
	@echo ""
	@echo "NOTE: VPD/FSDB dumping segfaults in this sandboxed environment."
	@echo "      Use 'make sim' for reliable simulation, or run on a"
	@echo "      machine with full /proc access for waveforms."

# Generate filelist
filelist.f: Makefile
	@echo "Generating filelist..."
	@rm -f filelist.f
	@for f in $(VERILOG_SOURCES); do echo "$$f" >> filelist.f; done

# Compile for batch mode (no waveform dump defines)
compile: filelist.f
	$(VCS) $(VCS_BASE_FLAGS)

# Compile for VCD waveform (simple format, may work in sandbox)
compile-vcd: filelist.f
	$(VCS) $(VCS_BASE_FLAGS) +define+VCD_DUMP

# Compile for VPD/DVE waveform
compile-dve: filelist.f
	$(VCS) $(VCS_BASE_FLAGS) +define+VPD_DUMP

# Compile for FSDB/Verdi waveform
compile-verdi: filelist.f
	$(VCS) $(VCS_BASE_FLAGS) +define+FSDB_DUMP

# Run simulation (batch mode, no waveform)
sim: compile
	$(SIMV) -no_save

# Run simulation with VCD waveform
sim-vcd: compile-vcd
	@echo ""
	@echo "========================================"
	@echo "Running with VCD waveform..."
	@echo "========================================"
	@echo ""
	$(SIMV) -no_save -l sim-vcd.log
	@echo ""
	@echo "========================================"
	@if [ -f $(TB_TOP).vcd ]; then \
		echo "VCD waveform generated: $(TB_TOP).vcd"; \
		echo "View with: gtkwave $(TB_TOP).vcd &"; \
	else \
		echo "WARNING: VCD file not generated."; \
	fi
	@echo "========================================"

# Run simulation with DVE waveform (VPD format)
# NOTE: This will likely segfault in sandboxed environments.
# The simulation binary can be copied to a non-sandboxed machine
# and run there to generate the VPD file.
sim-dve: compile-dve
	@echo ""
	@echo "========================================"
	@echo "WARNING: VPD dumping typically fails"
	@echo "in sandboxed environments due to"
	@echo "restricted /proc access."
	@echo ""
	@echo "If this segfaults, use 'make sim' for"
	@echo "batch mode, or copy simv to a machine"
	@echo "with full /proc access."
	@echo "========================================"
	@echo ""
	$(SIMV) -no_save -l sim-dve.log || \
		(echo ""; \
		 echo "========================================"; \
		 echo "VPD dumping failed due to sandbox"; \
		 echo "restrictions. This is expected."; \
		 echo ""; \
		 echo "To get waveforms, either:"; \
		 echo "  1. Run 'make sim-vcd' for VCD format"; \
		 echo "  2. Copy simv to non-sandboxed machine"; \
		 echo "     and run: ./simv +vcdplusfile=out.vpd"; \
		 echo "========================================"; \
		 exit 1)
	@echo ""
	@echo "========================================"
	@if [ -f $(TB_TOP).vpd ]; then \
		echo "DVE waveform generated: $(TB_TOP).vpd"; \
		echo "View with: dve -vpd $(TB_TOP).vpd &"; \
	else \
		echo "VPD file not generated."; \
	fi
	@echo "========================================"

# Run simulation with Verdi waveform (FSDB format)
# NOTE: This will likely segfault in sandboxed environments.
sim-verdi: compile-verdi
	@echo ""
	@echo "========================================"
	@echo "WARNING: FSDB dumping typically fails"
	@echo "in sandboxed environments due to"
	@echo "restricted /proc access."
	@echo "========================================"
	@echo ""
	$(SIMV) -no_save -l sim-verdi.log || \
		(echo ""; \
		 echo "========================================"; \
		 echo "FSDB dumping failed due to sandbox"; \
		 echo "restrictions. This is expected."; \
		 echo ""; \
		 echo "To get waveforms, either:"; \
		 echo "  1. Run 'make sim-vcd' for VCD format"; \
		 echo "  2. Copy simv to non-sandboxed machine"; \
		 echo "     and run with +fsdbfile+out.fsdb"; \
		 echo "========================================"; \
		 exit 1)
	@echo ""
	@echo "========================================"
	@if [ -f $(TB_TOP).fsdb ]; then \
		echo "Verdi waveform generated: $(TB_TOP).fsdb"; \
		echo "View with: verdi -ssf $(TB_TOP).fsdb -dbdir simv.daidir &"; \
	else \
		echo "FSDB file not generated."; \
	fi
	@echo "========================================"

# Run simulation and auto-launch DVE
dve: compile-dve
	$(SIMV) -no_save &
	dve -vpd $(TB_TOP).vpd &

# Run simulation and auto-launch Verdi
verdi: compile-verdi
	$(SIMV) -no_save &
	verdi -ssf $(TB_TOP).fsdb -dbdir simv.daidir &

# Clean
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

# Ultra clean (including DVE/Verdi files)
distclean: clean
	rm -rf DVEfiles
	rm -rf verdiLog
