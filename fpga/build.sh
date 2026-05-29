#!/bin/bash

# Shell script to run Vivado build for FPGA project
# Usage: ./build.sh

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Check if Vivado is available
if ! command -v vivado &> /dev/null; then
    echo "Error: Vivado not found in PATH. Please add Vivado to your system PATH."
    exit 1
fi

echo "Found Vivado, starting build..."

# Run the TCL build script
vivado -nojournal -nolog -mode batch -source build.tcl

# Check build result
if [ $? -eq 0 ]; then
    echo "Build completed successfully!"
else
    echo "Build failed with exit code $?"
    exit $?
fi
