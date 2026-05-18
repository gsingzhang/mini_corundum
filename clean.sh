#!/bin/bash
# Clean script for mini_corundum FPGA project
# Removes all Vivado generated files while preserving source RTL and configs

set -e

echo "Cleaning mini_corundum project..."

# Clean fpga directory (where Vivado build artifacts are)
if [ -d "fpga" ]; then
    echo "  Cleaning fpga/ build artifacts..."
    cd fpga

    # Remove Vivado project files
    rm -rf *.xpr *.cache *.gen *.hw *.ip_user_files *.runs *.sim *.srcs
    rm -rf .Xil defines.v

    # Remove log and journal files
    rm -rf *.log *.jou *.str

    # Remove generated tcl scripts
    rm -rf create_project.tcl update_config.tcl run_synth.tcl run_impl.tcl generate_bit.tcl program.tcl

    # Remove output files
    rm -rf *.bit *.ltx *.mcs *.prm
    rm -rf *_utilization.rpt *_utilization_hierarchical.rpt

    cd ..
fi

# Clean any generated files at top level
rm -rf *.log *.jou

echo "Clean complete."
echo ""
echo "Preserved files:"
echo "  - RTL source files in rtl/"
echo "  - Constraint files (*.xdc)"
echo "  - Makefile build system"
echo "  - IP configuration (*.tcl)"
echo "  - README.md"
