@echo off
REM Windows batch file to run Vivado build or create project
REM Usage: build.bat [build|project]
REM   build    - Run non-project mode synthesis and bitstream generation (default)
REM   project  - Create Vivado project file (.xpr)

setlocal

REM Get script directory
set SCRIPT_DIR=%~dp0
cd /d %SCRIPT_DIR%

REM Check parameter
set MODE=build
if "%~1"=="project" set MODE=project
if "%~1"=="help" (
    echo Usage: build.bat [build|project]
    echo   build    - Run non-project mode synthesis and bitstream generation ^(default^)
    echo   project  - Create Vivado project file ^(.xpr^)
    exit /b 0
)

REM Setup Vivado PATH if not already available
where vivado >nul 2>&1
if errorlevel 1 (
    REM Try common Vivado installation locations on Windows
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
    echo Example: set PATH=C:\Xilinx\Vivado\^<version^>\bin;%%PATH%%
    exit /b 1
)

if "%MODE%"=="build" (
    echo Found Vivado, starting build ^(non-project mode^)...
) else (
    echo Found Vivado, creating project...
)

REM Run the appropriate TCL script
if "%MODE%"=="build" (
    vivado -nojournal -nolog -mode batch -source build.tcl
) else (
    vivado -nojournal -nolog -mode batch -source create_project.tcl
)

if %ERRORLEVEL% equ 0 (
    if "%MODE%"=="build" (
        echo Build completed successfully!
    ) else (
        echo Project created successfully!
    )
) else (
    if "%MODE%"=="build" (
        echo Build failed with exit code %ERRORLEVEL%
    ) else (
        echo Project creation failed with exit code %ERRORLEVEL%
    )
    exit /b %ERRORLEVEL%
)

endlocal
