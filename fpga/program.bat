@echo off
REM Windows batch file to program FPGA with generated bitstream

setlocal

REM Get script directory
set SCRIPT_DIR=%~dp0
cd /d %SCRIPT_DIR%

REM Setup Vivado PATH if not already available
where vivado >nul 2>&1
if errorlevel 1 (
    set "VIVADO_FOUND="
    for %%d in (C: D: E:) do (
        for /f "delims=" %%v in ('dir /b /ad /o-n "%%d\Xilinx\Vivado" 2^>nul') do (
            if exist "%%d\Xilinx\Vivado\%%v\bin\vivado.bat" (
                set "PATH=%%d\Xilinx\Vivado\%%v\bin;%PATH%"
                echo Added Vivado to PATH: %%d\Xilinx\Vivado\%%v\bin
                set VIVADO_FOUND=1
                goto :vivado_check_done
            )
        )
    )
) else (
    set VIVADO_FOUND=1
)
:vivado_check_done

if not defined VIVADO_FOUND (
    echo Error: Vivado not found in PATH. Please add Vivado to your system PATH.
    exit /b 1
)

echo Programming FPGA...
vivado -nojournal -nolog -mode batch -source program.tcl

if %ERRORLEVEL% equ 0 (
    echo FPGA programming completed successfully!
) else (
    echo FPGA programming failed with exit code %ERRORLEVEL%
    exit /b %ERRORLEVEL%
)

endlocal
