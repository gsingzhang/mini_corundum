#!/bin/bash

# Shell script to run Vivado build or create project for FPGA project
# Usage: ./build.sh [build|project]
#   build    - Run non-project mode synthesis and bitstream generation (default)
#   project  - Create Vivado project file (.xpr)

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Check parameter
MODE="build"
if [ $# -gt 0 ]; then
    if [ "$1" = "project" ]; then
        MODE="project"
    elif [ "$1" != "build" ]; then
        echo "Usage: ./build.sh [build|project]"
        echo "  build    - Run non-project mode synthesis and bitstream generation (default)"
        echo "  project  - Create Vivado project file (.xpr)"
        exit 1
    fi
fi

# Setup Vivado PATH if not already available
if ! command -v vivado &> /dev/null; then
    # Try common Vivado installation locations
    VIVADO_CANDIDATES=(
        "$HOME/gx/gxprogram/xilinx/2025.2.1/Vivado/bin"
        "/tools/Xilinx/Vivado/2025.2/bin"
        "/opt/Xilinx/Vivado/2025.2/bin"
        "/tools/Xilinx/Vivado/2024.2/bin"
        "/opt/Xilinx/Vivado/2024.2/bin"
    )
    for candidate in "${VIVADO_CANDIDATES[@]}"; do
        if [ -x "$candidate/vivado" ]; then
            export PATH="$candidate:$PATH"
            echo "Added Vivado to PATH: $candidate"
            break
        fi
    done
fi

# Check if Vivado is available
if ! command -v vivado &> /dev/null; then
    echo "Error: Vivado not found in PATH. Please add Vivado to your system PATH."
    echo "Example: export PATH=/path/to/Vivado/bin:\$PATH"
    exit 1
fi

if [ "$MODE" = "build" ]; then
    echo "Found Vivado, starting build (non-project mode)..."
else
    echo "Found Vivado, creating project..."
fi

# Run the appropriate TCL script
if [ "$MODE" = "build" ]; then
    vivado -nojournal -nolog -mode batch -source build.tcl
else
    vivado -nojournal -nolog -mode batch -source create_project.tcl
fi

# Check result
EXIT_CODE=$?
if [ $EXIT_CODE -eq 0 ]; then
    if [ "$MODE" = "build" ]; then
        echo "Build completed successfully!"
    else
        echo "Project created successfully!"
    fi
else
    if [ "$MODE" = "build" ]; then
        echo "Build failed with exit code $EXIT_CODE"
    else
        echo "Project creation failed with exit code $EXIT_CODE"
    fi
    exit $EXIT_CODE
fi
