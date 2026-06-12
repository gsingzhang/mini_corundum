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

# Setup Vivado PATH if not already available
$VivadoFound = $false
try {
    $null = Get-Command vivado -ErrorAction Stop
    $VivadoFound = $true
} catch {
    $VivadoFound = $false
}

if (-not $VivadoFound) {
    # Try common Vivado installation locations on Windows
    $VivadoCandidates = @(
        "C:\Xilinx\Vivado\2025.2\bin"
        "C:\Xilinx\Vivado\2024.2\bin"
        "C:\Xilinx\Vivado\2024.1\bin"
        "C:\Xilinx\Vivado\2023.2\bin"
        "D:\Xilinx\Vivado\2025.2\bin"
        "D:\Xilinx\Vivado\2024.2\bin"
    )

    # Also search Xilinx directory for any installed version
    foreach ($drive in @("C:", "D:")) {
        $xilinxDir = "$drive\Xilinx\Vivado"
        if (Test-Path $xilinxDir) {
            $versions = Get-ChildItem $xilinxDir -Directory | Sort-Object Name -Descending
            foreach ($ver in $versions) {
                $binDir = Join-Path $ver.FullName "bin"
                if (Test-Path (Join-Path $binDir "vivado.bat")) {
                    $VivadoCandidates = @($binDir) + $VivadoCandidates
                    break
                }
            }
        }
    }

    foreach ($candidate in $VivadoCandidates) {
        $vivadoExe = Join-Path $candidate "vivado.bat"
        if (Test-Path $vivadoExe) {
            $env:PATH = "$candidate;$env:PATH"
            Write-Host "Added Vivado to PATH: $candidate" -ForegroundColor Cyan
            $VivadoFound = $true
            break
        }
    }
}

if (-not $VivadoFound) {
    Write-Host "Error: Vivado not found. Please add Vivado to your system PATH." -ForegroundColor Red
    Write-Host "Example: `$env:PATH = 'C:\Xilinx\Vivado\<version>\bin;' + `$env:PATH" -ForegroundColor Yellow
    exit 1
}

if ($Mode -eq "build") {
    Write-Host "Found Vivado, starting build (non-project mode)..." -ForegroundColor Green
} else {
    Write-Host "Found Vivado, creating project..." -ForegroundColor Green
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
