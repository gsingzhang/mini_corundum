# VCS Makefile for fpga_core testbench (UVM architecture)
#
# Usage:
#   make sim        - Run all tests (batch simulation)
#   make sim TEST=1 - Run specific test by UVM_TESTNAME
#   make sim-vcd    - Run with VCD waveform
#   make clean      - Remove build artifacts

TB_TOP = tb_fpga_core
DUT = fpga_core

RTL_DIR = ../rtl
LIB_ETH_DIR = $(RTL_DIR)/lib_eth
LIB_AXIS_DIR = $(RTL_DIR)/lib_axis
LIB_AXI_DIR = $(RTL_DIR)/lib_axi
TB_DIR = .
TB_LUDP_DIR = ./ludp_tb

VERILOG_SOURCES += $(RTL_DIR)/taxi_axis_if.sv
VERILOG_SOURCES += $(RTL_DIR)/taxi_axis_arb_mux.sv
VERILOG_SOURCES += $(RTL_DIR)/taxi_arbiter.sv
VERILOG_SOURCES += $(RTL_DIR)/taxi_penc.sv
VERILOG_SOURCES += $(RTL_DIR)/ludp_protocol.sv
VERILOG_SOURCES += $(RTL_DIR)/ludp_protocol_rx.sv
VERILOG_SOURCES += $(RTL_DIR)/ludp_protocol_tx.sv
VERILOG_SOURCES += $(RTL_DIR)/ludp_tx_dma_axi.sv
VERILOG_SOURCES += $(RTL_DIR)/ludp_tx_scheduler.sv
VERILOG_SOURCES += $(RTL_DIR)/icmp_echo_reply.sv
VERILOG_SOURCES += $(RTL_DIR)/$(DUT).sv
VERILOG_SOURCES += $(RTL_DIR)/taxi_prim/taxi_ram_1r1w_1c.sv
VERILOG_SOURCES += $(LIB_AXI_DIR)/taxi_axi_if.sv
VERILOG_SOURCES += $(LIB_AXI_DIR)/taxi_axi_ram.sv
VERILOG_SOURCES += $(RTL_DIR)/lib_dma/axi_dma_wr.v
VERILOG_SOURCES += $(RTL_DIR)/lib_dma/axi_dma_rd.v
VERILOG_SOURCES += $(RTL_DIR)/lib_dma/ludp_dma_wrapper.sv
VERILOG_SOURCES += $(RTL_DIR)/lib_axis/taxi_axis_async_fifo.sv
VERILOG_SOURCES += $(RTL_DIR)/lib_sync/taxi_sync_reset.sv
VERILOG_SOURCES += $(RTL_DIR)/lib_sync/taxi_sync_signal.sv
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

VERILOG_SOURCES += $(TB_LUDP_DIR)/ludp_tb_pkg.sv
VERILOG_SOURCES += $(TB_LUDP_DIR)/xgmii_if.sv
VERILOG_SOURCES += $(TB_LUDP_DIR)/dut_ctrl_if.sv

VERILOG_SOURCES += $(TB_DIR)/tb_fpga_core.sv

VCS = vcs
VCS_BASE_FLAGS = -full64 -sverilog -timescale=1ns/1ps \
    -debug_access+r -kdb \
    +v2k \
    +v2k_generate \
    +libext+.v+.sv \
    -ignore initializer_driver_checks \
    -ntb_opts uvm-1.2 \
    -CFLAGS "-DVCS" \
    +define+SIMULATION \
    -f filelist.f \
    -top $(TB_TOP) \
    -o simv \
    -no_stack_annotator

VCS_COV_FLAGS = -cm line+cond+fsm+tgl+branch \
    -cm_dir simv.cm

VCS_COV_BASE_FLAGS = -full64 -sverilog -timescale=1ns/1ps \
    +v2k \
    +v2k_generate \
    +libext+.v+.sv \
    -ignore initializer_driver_checks \
    -ntb_opts uvm-1.2 \
    -CFLAGS "-DVCS" \
    -f filelist.f \
    -top $(TB_TOP) \
    -o simv \
    -no_stack_annotator \
    -cm line+cond+branch \
    -cm_dir simv.cm \
    -lca

SIMV = ./simv

UVM_TEST_NAME = ludp_test_base

ifeq ($(TEST),cmd)
UVM_VSEQ = cmd_lifecycle_vseq
else ifeq ($(TEST),credit)
UVM_VSEQ = credit_flow_vseq
else ifeq ($(TEST),data)
UVM_VSEQ = data_integrity_vseq
else ifeq ($(TEST),retx)
UVM_VSEQ = retransmission_vseq
else ifeq ($(TEST),error)
UVM_VSEQ = error_resilience_vseq
else ifeq ($(TEST),mech)
UVM_VSEQ = internal_mechanisms_vseq
else ifeq ($(TEST),basics)
UVM_VSEQ = protocol_basics_vseq
else ifeq ($(TEST),cov)
UVM_VSEQ = coverage_enhance_vseq
else ifeq ($(TEST),reset)
UVM_VSEQ = reset_and_init_vseq
else ifeq ($(TEST),)
UVM_VSEQ = test_all_vseq
else
UVM_VSEQ = $(TEST)
endif

.PHONY: all compile compile-vcd sim sim-vcd clean distclean help

all: sim

help:
	@echo "VCS Makefile for fpga_core testbench (UVM architecture)"
	@echo ""
	@echo "Targets:"
	@echo "  make sim                    - Run test_all_vseq (complete regression)"
	@echo "  make sim TEST=basics       - Run protocol_basics_vseq"
	@echo "  make sim TEST=cmd          - Run cmd_lifecycle_vseq"
	@echo "  make sim TEST=credit       - Run credit_flow_vseq"
	@echo "  make sim TEST=data         - Run data_integrity_vseq"
	@echo "  make sim TEST=retx         - Run retransmission_vseq"
	@echo "  make sim TEST=error        - Run error_resilience_vseq"
	@echo "  make sim TEST=mech         - Run internal_mechanisms_vseq"
	@echo "  make sim TEST=cov          - Run coverage_enhance_vseq"
	@echo "  make sim TEST=reset        - Run reset_and_init_vseq"
	@echo "  make sim TEST=<vseq_name>  - Run any *_vseq by factory name"
	@echo "  make sim-vcd                - Run with VCD waveform"
	@echo "  make clean                  - Remove build artifacts"

filelist.f: Makefile
	@echo "Generating filelist..."
	@rm -f filelist.f
	@for f in $(VERILOG_SOURCES); do echo "$$f" >> filelist.f; done

compile: filelist.f
	$(VCS) $(VCS_BASE_FLAGS)

compile-cov: filelist.f
	$(VCS) $(VCS_COV_BASE_FLAGS)

compile-vcd: filelist.f
	$(VCS) $(VCS_BASE_FLAGS) +define+VCD_DUMP

sim: compile
	setarch x86_64 -R $(SIMV) -no_save +UVM_TESTNAME=$(UVM_TEST_NAME) +UVM_VSEQ=$(UVM_VSEQ) +UVM_VERBOSITY=UVM_LOW -suppress=ASLR_DETECTED_INFO

sim-cov: compile-cov
	setarch x86_64 -R $(SIMV) +UVM_TESTNAME=$(UVM_TEST_NAME) +UVM_VSEQ=$(UVM_VSEQ) +UVM_VERBOSITY=UVM_LOW -cm line+cond+branch -cm_dir simv.cm -cm_name $(UVM_VSEQ) -cm_log coverage.log 2>&1 | tee sim_output.log
	@echo ""
	@echo "========================================"
	@echo "Code Coverage Summary"
	@echo "========================================"
	@LD_LIBRARY_PATH=/home/gxzhang/gx/gxprogram/synopsys/vcs/W-2024.09-SP1/vcfca/auxx/monet/lintllm/_internal:$$LD_LIBRARY_PATH urg -dir simv.cm -report coverage_report -format text 2>&1 | grep -E "ludp|fpga_core|SCORE|Line|Cond|Branch|total|covered" | head -30 || true
	@echo ""
	@echo "========================================"
	@echo "Code Coverage Report"
	@echo "========================================"
	urg -dir simv.cm -report coverage_report

sim-test: compile
	$(SIMV) -no_save +UVM_TESTNAME=$(UVM_TEST_NAME) +UVM_VSEQ=$(UVM_VSEQ) +UVM_VERBOSITY=UVM_LOW

sim-vcd: compile-vcd
	@echo ""
	@echo "========================================"
	@echo "Running with VCD waveform..."
	@echo "========================================"
	$(SIMV) -no_save +UVM_TESTNAME=$(UVM_TEST_NAME) +UVM_VSEQ=$(UVM_VSEQ) +UVM_VERBOSITY=UVM_LOW -l sim-vcd.log
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
	$(SIMV) -no_save +UVM_TESTNAME=$(UVM_TEST_NAME) +UVM_VSEQ=$(UVM_VSEQ) +UVM_VERBOSITY=UVM_LOW -l sim-dve.log

sim-verdi: filelist.f
	$(VCS) $(VCS_BASE_FLAGS) +define+FSDB_DUMP
	$(SIMV) -no_save +UVM_TESTNAME=$(UVM_TEST_NAME) +UVM_VSEQ=$(UVM_VSEQ) +UVM_VERBOSITY=UVM_LOW -l sim-verdi.log

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
	# Coverage databases
	rm -rf simv.cm simv.cm.vdb simv.vdb
	rm -rf simv_*.vdb simv_*.daidir
	# Coverage report and debug XML
	rm -rf coverage_report
	rm -f *.fsm.sch.verilog.xml
	rm -f tr_db.log
	# All log files
	rm -f *.log
	# UVM DPI
	rm -f uvm_dpi.cc

distclean: clean
	rm -rf DVEfiles
	rm -rf verdiLog
