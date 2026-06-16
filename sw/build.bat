@echo off
echo Building ludp_recv for Windows...

if exist "C:\Program Files\mingw-w64\x86_64-8.1.0-posix-seh-rt_v6-rev0\mingw64\bin\gcc.exe" (
    set "GCC=C:\Program Files\mingw-w64\x86_64-8.1.0-posix-seh-rt_v6-rev0\mingw64\bin\gcc.exe"
) else if exist "C:\mingw64\bin\gcc.exe" (
    set "GCC=C:\mingw64\bin\gcc.exe"
) else (
    set "GCC=gcc"
)

"%GCC%" -o ludp_recv.exe ludp_recv.c -lws2_32 -lpthread -O2

if %errorlevel% equ 0 (
    echo Build successful!
    echo Output: ludp_recv.exe
) else (
    echo Build failed!
    pause
)