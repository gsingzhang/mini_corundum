###################################################################
# 
# Xilinx Vivado FPGA Makefile
# 
# Copyright (c) 2016 Alex Forencich
# 
###################################################################
# 
# Parameters:
# FPGA_TOP - Top module name
# FPGA_FAMILY - FPGA family (e.g. VirtexUltrascale)
# FPGA_DEVICE - FPGA device (e.g. xcvu095-ffva2104-2-e)
# SYN_FILES - space-separated list of source files
# INC_FILES - space-separated list of include files
# XDC_FILES - space-separated list of timing constraint files
# XCI_FILES - space-separated list of IP XCI files
# 
# Example:
# 
# FPGA_TOP = fpga
# FPGA_FAMILY = VirtexUltrascale
# FPGA_DEVICE = xcvu095-ffva2104-2-e
# SYN_FILES = rtl/fpga.v
# XDC_FILES = fpga.xdc
# XCI_FILES = ip/pcspma.xci
# include ../common/vivado.mk
# 
###################################################################

# phony targets
.PHONY: fpga vivado tmpclean clean distclean

# prevent make from deleting intermediate files and reports
.PRECIOUS: %.xpr %.bit %.mcs %.prm
.SECONDARY:

CONFIG ?= config.mk
-include ../$(CONFIG)

FPGA_TOP ?= fpga
PROJECT ?= $(FPGA_TOP)

SYN_FILES_REL = $(foreach p,$(SYN_FILES),$(if $(filter /% ./%,$p),$p,../$p))
INC_FILES_REL = $(foreach p,$(INC_FILES),$(if $(filter /% ./%,$p),$p,../$p))
XCI_FILES_REL = $(foreach p,$(XCI_FILES),$(if $(filter /% ./%,$p),$p,../$p))
IP_TCL_FILES_REL = $(foreach p,$(IP_TCL_FILES),$(if $(filter /% ./%,$p),$p,../$p))
CONFIG_TCL_FILES_REL = $(foreach p,$(CONFIG_TCL_FILES),$(if $(filter /% ./%,$p),$p,../$p))

ifdef XDC_FILES
  XDC_FILES_REL = $(foreach p,$(XDC_FILES),$(if $(filter /% ./%,$p),$p,../$p))
else
  XDC_FILES_REL = $(PROJECT).xdc
endif

###################################################################
# Main Targets
#
# all: build everything
# clean: remove output files and project files
###################################################################

all: fpga

fpga: $(PROJECT).bit

vivado: $(PROJECT).xpr
	vivado $(PROJECT).xpr

tmpclean::
	-rm -rf *.log *.jou *.cache *.gen *.hbs *.hw *.ip_user_files *.runs *.xpr *.html *.xml *.sim *.srcs *.str .Xil defines.v
	-rm -rf create_project.tcl update_config.tcl run_synth.tcl run_impl.tcl generate_bit.tcl

clean:: tmpclean
	-rm -rf *.bit *.ltx program.tcl generate_mcs.tcl *.mcs *.prm flash.tcl
	-rm -rf *_utilization.rpt *_utilization_hierarchical.rpt

distclean:: clean
	-rm -rf rev

###################################################################
# Target implementations
###################################################################

# Vivado project file
create_project.tcl: Makefile $(XCI_FILES_REL) $(IP_TCL_FILES_REL)
	rm -rf defines.v
	touch defines.v
	for x in $(DEFS); do echo '`define' $$x >> defines.v; done
	echo "create_project -force -part $(FPGA_PART) $(PROJECT)" > $@
	echo "add_files -fileset sources_1 defines.v $(SYN_FILES_REL)" >> $@
	echo "set_property top $(FPGA_TOP) [current_fileset]" >> $@
	echo "add_files -fileset constrs_1 $(XDC_FILES_REL)" >> $@
	for x in $(XCI_FILES_REL); do echo "import_ip $$x" >> $@; done
	for x in $(IP_TCL_FILES_REL); do echo "source $$x" >> $@; done
	for x in $(CONFIG_TCL_FILES_REL); do echo "source $$x" >> $@; done

update_config.tcl: $(CONFIG_TCL_FILES_REL) $(SYN_FILES_REL) $(INC_FILES_REL) $(XDC_FILES_REL)
	echo "open_project -quiet $(PROJECT).xpr" > $@
	for x in $(CONFIG_TCL_FILES_REL); do echo "source $$x" >> $@; done

$(PROJECT).xpr: create_project.tcl
	vivado -nojournal -nolog -mode batch -source create_project.tcl

%.xpr: %.tcl
	vivado -nojournal -nolog -mode batch -source $<

run_synth.tcl: $(PROJECT).xpr
	echo "open_project $(PROJECT).xpr" > $@
	echo "reset_run synth_1" >> $@
	echo "launch_runs -jobs 4 synth_1" >> $@
	echo "wait_on_run synth_1" >> $@

synth: run_synth.tcl
	vivado -nojournal -nolog -mode batch -source run_synth.tcl

%.dcp: %.xpr
	echo "open_project $<" > run_synth.tcl
	echo "reset_run synth_1" >> run_synth.tcl
	echo "launch_runs -jobs 4 synth_1" >> run_synth.tcl
	echo "wait_on_run synth_1" >> run_synth.tcl
	vivado -nojournal -nolog -mode batch -source run_synth.tcl
	cp $(PROJECT).runs/synth_1/$(PROJECT).dcp $@

run_impl.tcl: $(PROJECT).xpr
	echo "open_project $(PROJECT).xpr" > $@
	echo "reset_run impl_1" >> $@
	echo "launch_runs -jobs 4 impl_1" >> $@
	echo "wait_on_run impl_1" >> $@

impl: run_impl.tcl
	vivado -nojournal -nolog -mode batch -source run_impl.tcl

%.dcp: %.dcp
	echo "open_project $(PROJECT).xpr" > run_impl.tcl
	echo "reset_run impl_1" >> run_impl.tcl
	echo "launch_runs -jobs 4 impl_1" >> run_impl.tcl
	echo "wait_on_run impl_1" >> run_impl.tcl
	vivado -nojournal -nolog -mode batch -source run_impl.tcl
	cp $(PROJECT).runs/impl_1/$(PROJECT)_routed.dcp $@

generate_bit.tcl: $(PROJECT).xpr
	echo "open_project $(PROJECT).xpr" > $@
	echo "open_run impl_1" >> $@
	echo "write_bitstream -force $(PROJECT).bit" >> $@

$(PROJECT).bit: $(PROJECT).runs/impl_1/$(PROJECT)_routed.dcp
	echo "open_project $(PROJECT).xpr" > generate_bit.tcl
	echo "open_run impl_1" >> generate_bit.tcl
	echo "write_bitstream -force $(PROJECT).bit" >> generate_bit.tcl
	vivado -nojournal -nolog -mode batch -source generate_bit.tcl

create_mcs.tcl: $(PROJECT).bit
	echo "write_cfgmem -force -format mcs -size 32 -interface SPIx4 -loadbit {up 0x0000000 $(PROJECT).bit} $(PROJECT).mcs" > create_mcs.tcl

%.mcs: %.bit
	echo "write_cfgmem -force -format mcs -size 32 -interface SPIx4 -loadbit {up 0x0000000 $<} $@" > create_mcs.tcl
	vivado -nojournal -nolog -mode batch -source create_mcs.tcl

flash.tcl:
	echo "open_hw" > flash.tcl
	echo "connect_hw_server" >> flash.tcl
	echo "open_hw_target" >> flash.tcl
	echo "current_hw_device [lindex [get_hw_devices] 0]" >> flash.tcl
	echo "refresh_hw_device -update_hw_probes false [current_hw_device]" >> flash.tcl
	echo "create_hw_cfgmem -hw_device [current_hw_device] [lindex [get_cfgmem_parts {s25fl256sxxxxxx0-spi-x1_x2_x4}] 0]" >> flash.tcl
	echo "current_hw_cfgmem [get_hw_cfgmems [current_hw_device]]" >> flash.tcl
	echo "set_property PROGRAM.BLANK_CHECK  0 [current_hw_cfgmem]" >> flash.tcl
	echo "set_property PROGRAM.ERASE  1 [current_hw_cfgmem]" >> flash.tcl
	echo "set_property PROGRAM.CFG_PROGRAM  1 [current_hw_cfgmem]" >> flash.tcl
	echo "set_property PROGRAM.VERIFY  1 [current_hw_cfgmem]" >> flash.tcl
	echo "set_property PROGRAM.CHECKSUM  0 [current_hw_cfgmem]" >> flash.tcl
	echo "refresh_hw_device [current_hw_device]" >> flash.tcl
	echo "set_property PROGRAM.ADDRESS_RANGE  {use_file} [current_hw_cfgmem]" >> flash.tcl
	echo "set_property PROGRAM.FILES [list \"$(PROJECT).mcs\"] [current_hw_cfgmem]" >> flash.tcl
	echo "program_hw_cfgmem -hw_cfgmem [current_hw_cfgmem]" >> flash.tcl
	echo "boot_hw_device [current_hw_device]" >> flash.tcl
	echo "exit" >> flash.tcl

flash: $(PROJECT).mcs flash.tcl
	vivado -nojournal -nolog -mode batch -source flash.tcl
