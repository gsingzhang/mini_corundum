# PowerShell script to run Vivado build for FPGA project
# Usage: .\build.ps1

# Get script directory
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ScriptDir

# Check if Vivado is available
try {
    $VivadoVersion = vivado -version 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Error: Vivado not found in PATH. Please add Vivado to your system PATH or run this script from Vivado Tcl Console." -ForegroundColor Red
        exit 1
    }
    Write-Host "Found Vivado, starting build..." -ForegroundColor Green
} catch {
    Write-Host "Error: Could not execute Vivado. Please ensure Vivado is installed and in your PATH." -ForegroundColor Red
    exit 1
}

# Run the TCL build script
vivado -nojournal -nolog -mode batch -source build.tcl

# Check build result
if ($LASTEXITCODE -eq 0) {
    Write-Host "Build completed successfully!" -ForegroundColor Green
} else {
    Write-Host "Build failed with exit code $LASTEXITCODE" -ForegroundColor Red
    exit $LASTEXITCODE
}
