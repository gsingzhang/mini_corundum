# PowerShell script to run Vivado build or create project for FPGA project
# Usage: .\build.ps1 [build|project]
#   build    - Run non-project mode synthesis and bitstream generation (default)
#   project  - Create Vivado project file (.xpr)

# Get script directory
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ScriptDir

# Check parameter
$Mode = "build"
if ($args.Count -gt 0) {
    if ($args[0] -eq "project") {
        $Mode = "project"
    } elseif ($args[0] -ne "build") {
        Write-Host "Usage: .\build.ps1 [build|project]" -ForegroundColor Yellow
        Write-Host "  build    - Run non-project mode synthesis and bitstream generation (default)"
        Write-Host "  project  - Create Vivado project file (.xpr)"
        exit 1
    }
}

# Check if Vivado is available
try {
    $VivadoVersion = vivado -version 2>$null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Error: Vivado not found in PATH. Please add Vivado to your system PATH or run this script from Vivado Tcl Console." -ForegroundColor Red
        exit 1
    }
    if ($Mode -eq "build") {
        Write-Host "Found Vivado, starting build (non-project mode)..." -ForegroundColor Green
    } else {
        Write-Host "Found Vivado, creating project..." -ForegroundColor Green
    }
} catch {
    Write-Host "Error: Could not execute Vivado. Please ensure Vivado is installed and in your PATH." -ForegroundColor Red
    exit 1
}

# Run the appropriate TCL script
if ($Mode -eq "build") {
    vivado -nojournal -nolog -mode batch -source build.tcl
} else {
    vivado -nojournal -nolog -mode batch -source create_project.tcl
}

# Check result
if ($LASTEXITCODE -eq 0) {
    if ($Mode -eq "build") {
        Write-Host "Build completed successfully!" -ForegroundColor Green
    } else {
        Write-Host "Project created successfully!" -ForegroundColor Green
    }
} else {
    if ($Mode -eq "build") {
        Write-Host "Build failed with exit code $LASTEXITCODE" -ForegroundColor Red
    } else {
        Write-Host "Project creation failed with exit code $LASTEXITCODE" -ForegroundColor Red
    }
    exit $LASTEXITCODE
}
