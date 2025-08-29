@echo off
setlocal EnableExtensions EnableDelayedExpansion

REM ============================================================
REM  Arduino Nano (ATmega328P) pure C++ build with Arduino core
REM  Layout:
REM    project\
REM      build.bat
REM      src\*.cpp      (provide setup()/loop() in main.cpp)
REM      include\*.h
REM  Usage:
REM    build.bat [command] [switches]
REM
REM  Commands:
REM    build (default) | upload | size | clean | where
REM
REM  Switches (override defaults):
REM    /port=COM5        serial port
REM    /oldboot=0|1      1 => 57600 baud (old Nano bootloader)
REM    /variant=eightanaloginputs
REM    /f_cpu=16000000UL
REM    /project=CryptoEmbedV1
REM    /src=src          sources dir
REM    /inc=include      headers dir
REM    /pkgs=C:\path\to\Arduino15\packages\arduino
REM    /mcu=atmega328p
REM    /baud=115200      (overrides oldboot-derived baud)
REM
REM  Optional: .nanorc.env file with lines KEY=VALUE (same names as above)
REM ============================================================

REM -------- defaults -------------
set "PORT=COM3"
set "OLD_BOOTLOADER=0"
set "VARIANT=eightanaloginputs"
set "F_CPU=16000000UL"
set "PROJECT=CryptoEmbedV1"
set "SRC_DIR=src"
set "INC_DIR=include"
set "BUILD_DIR=.build"
set "MCU=atmega328p"
set "BAUD_UPLOAD="        REM computed from oldboot unless /baud= is given
set "PKG="                REM default resolved from %LOCALAPPDATA%
REM --------------------------------

REM ---- optional env file overrides (.nanorc.env) ----
if exist ".nanorc.env" (
  for /f "usebackq eol=# tokens=1* delims==" %%K in (".nanorc.env") do (
    if not "%%~K"=="" if not "%%~L"=="" set "%%~K=%%~L"
  )
)

REM ---- parse CLI: first non-switch = command; switches as /key=value ----
set "CMD="
for %%A in (%*) do (
  set "ARG=%%~A"
  if defined ARG (
    if /i "!ARG:~0,1!"=="/" (call :HANDLE_SWITCH "!ARG:~1!")
    else if /i "!ARG:~0,1!"=="-" (call :HANDLE_SWITCH "!ARG:~1!")
    else if not defined CMD (set "CMD=!ARG!")
  )
)
if not defined CMD set "CMD=build"

REM ---- resolve Arduino15 roots ----
if not defined PKG set "PKG=%LOCALAPPDATA%\Arduino15\packages\arduino"
if not exist "%PKG%" (
  echo [ERR] Arduino15 packages not found under "%PKG%".
  exit /b 1
)

for /f "usebackq delims=" %%D in (`dir /b /ad "%PKG%\tools\avr-gcc" ^| sort /r`) do (
  if not defined AVR_GCC_RT set "AVR_GCC_RT=%PKG%\tools\avr-gcc\%%D"
)
for /f "usebackq delims=" %%D in (`dir /b /ad "%PKG%\tools\avrdude" ^| sort /r`) do (
  if not defined AVRDUDE_RT set "AVRDUDE_RT=%PKG%\tools\avrdude\%%D"
)
for /f "usebackq delims=" %%D in (`dir /b /ad "%PKG%\hardware\avr" ^| sort /r`) do (
  if not defined HARDWARE_RT set "HARDWARE_RT=%PKG%\hardware\avr\%%D"
)

if not exist "%AVR_GCC_RT%\bin\avr-gcc.exe" (
  echo [ERR] avr-gcc not found: "%AVR_GCC_RT%\bin\avr-gcc.exe"
  exit /b 1
)
if not exist "%AVRDUDE_RT%\bin\avrdude.exe" (
  echo [ERR] avrdude not found: "%AVRDUDE_RT%\bin\avrdude.exe"
  exit /b 1
)
if not exist "%HARDWARE_RT%\cores\arduino" (
  echo [ERR] Arduino AVR core not found under "%HARDWARE_RT%\cores\arduino"
  exit /b 1
)

set "AVR_BIN=%AVR_GCC_RT%\bin"
set "AVR_ETC=%AVRDUDE_RT%\etc"
set "CORE_PATH=%HARDWARE_RT%\cores\arduino"
set "VARIANT_PATH=%HARDWARE_RT%\variants\%VARIANT%"

REM ---- tool binaries ----
set "CC=%AVR_BIN%\avr-gcc.exe"
set "CXX=%AVR_BIN%\avr-g++.exe"
set "AR=%AVR_BIN%\avr-ar.exe"
set "OBJCOPY=%AVR_BIN%\avr-objcopy.exe"
set "SIZE=%AVR_BIN%\avr-size.exe"
set "AVRDUDE=%AVRDUDE_RT%\bin\avrdude.exe"

REM ---- flags ----
if not defined BAUD_UPLOAD (
  if "%OLD_BOOTLOADER%"=="1" ( set "BAUD_UPLOAD=57600" ) else ( set "BAUD_UPLOAD=115200" )
)

set "COMMON_DEFS=-DF_CPU=%F_CPU% -DARDUINO_AVR_NANO -DARDUINO_ARCH_AVR -DARDUINO=10819"
set "CFLAGS=-Os -mmcu=%MCU% -ffunction-sections -fdata-sections -MMD -MP %COMMON_DEFS%"
set "CXXFLAGS=%CFLAGS% -std=gnu++17 -fno-exceptions -fno-rtti"
set "LDFLAGS=-Wl,--gc-sections -mmcu=%MCU%"
set "INCFLAGS=-I%CORE_PATH% -I%VARIANT_PATH% -I%INC_DIR% -I%SRC_DIR%"

set "ELF=%BUILD_DIR%\%PROJECT%.elf"
set "HEX=%BUILD_DIR%\%PROJECT%.hex"
set "COREA=%BUILD_DIR%\core\core.a"

if /i "%CMD%"=="where"  goto :PRINT_PATHS
if /i "%CMD%"=="clean"  goto :CLEAN
if /i "%CMD%"=="size"   goto :SIZE_ONLY
if /i "%CMD%"=="upload" goto :UPLOAD
if /i "%CMD%"=="build"  goto :BUILD

echo Unknown command "%CMD%". Use: build ^| upload ^| size ^| clean ^| where
exit /b 1

:BUILD
call :ENSURE_DIRS

echo.
echo === Compile Arduino core (C) ===
for %%F in ("%CORE_PATH%\*.c") do (
  echo [CC ] core\%%~nxF
  "%CC%" %CFLAGS% %INCFLAGS% -c "%%F" -o "%BUILD_DIR%\core\%%~nF.o"
  if errorlevel 1 exit /b 1
)

echo.
echo === Compile Arduino core (C++) ===
for %%F in ("%CORE_PATH%\*.cpp") do (
  echo [CXX] core\%%~nxF
  "%CXX%" %CXXFLAGS% %INCFLAGS% -c "%%F" -o "%BUILD_DIR%\core\%%~nF.o"
  if errorlevel 1 exit /b 1
)

echo.
echo === Archive core ===
if exist "%COREA%" del "%COREA%"
for %%F in ("%BUILD_DIR%\core\*.o") do (
  "%AR%" rcs "%COREA%" "%%~fF"
  if errorlevel 1 exit /b 1
)

echo.
echo === Compile app sources ===
for %%F in ("%SRC_DIR%\*.cpp") do (
  echo [CXX] app\%%~nxF
  "%CXX%" %CXXFLAGS% %INCFLAGS% -c "%%F" -o "%BUILD_DIR%\app\%%~nF.o"
  if errorlevel 1 exit /b 1
)

echo.
echo === Link ===
set "APP_LINK="
for %%F in ("%BUILD_DIR%\app\*.o") do (
  set "APP_LINK=!APP_LINK! "app\%%~nxF""
)
pushd "%BUILD_DIR%"
  "%CXX%" %LDFLAGS% -o "%PROJECT%.elf" !APP_LINK! "core\core.a"
  if errorlevel 1 (popd & exit /b 1)
  "%SIZE%" "%PROJECT%.elf"
popd

echo.
echo === Objcopy (HEX) ===
"%OBJCOPY%" -O ihex -R .eeprom "%ELF%" "%HEX%"
if errorlevel 1 exit /b 1

echo.
echo Done: "%HEX%"
exit /b 0

:UPLOAD
call :BUILD || exit /b 1
echo.
echo === Upload ===
"%AVRDUDE%" -C"%AVR_ETC%\avrdude.conf" -v -p %MCU% -c arduino -P %PORT% -b %BAUD_UPLOAD% -D -U flash:w:"%HEX%":i
exit /b %ERRORLEVEL%

:SIZE_ONLY
if not exist "%ELF%" (
  echo [INFO] No ELF found; building first...
  call :BUILD || exit /b 1
)
echo.
"%SIZE%" "%ELF%"
exit /b 0

:CLEAN
echo Deleting "%BUILD_DIR%" ...
rmdir /s /q "%BUILD_DIR%" 2>nul
echo Done.
exit /b 0

:ENSURE_DIRS
if not exist "%BUILD_DIR%" mkdir "%BUILD_DIR%"
if not exist "%BUILD_DIR%\core" mkdir "%BUILD_DIR%\core"
if not exist "%BUILD_DIR%\app"  mkdir "%BUILD_DIR%\app"
exit /b 0

:PRINT_PATHS
echo AVR_GCC_RT = %AVR_GCC_RT%
echo AVRDUDE_RT = %AVRDUDE_RT%
echo HARDWARE_RT= %HARDWARE_RT%
echo CORE_PATH  = %CORE_PATH%
echo VARIANT    = %VARIANT%  (path: %VARIANT_PATH%)
echo PORT       = %PORT%
echo OLD_BOOT   = %OLD_BOOTLOADER%  (BAUD=%BAUD_UPLOAD%)
echo MCU        = %MCU%
echo PROJECT    = %PROJECT%
echo SRC_DIR    = %SRC_DIR%
echo INC_DIR    = %INC_DIR%
echo PKG ROOT   = %PKG%
exit /b 0

:HANDLE_SWITCH
REM %~1 is key=value (case-insensitive keys)
for /f "tokens=1* delims==" %%k in ("%~1") do (
  set "K=%%~k"
  set "V=%%~l"
)
if /i "%K%"=="port"       set "PORT=%V%"
if /i "%K%"=="oldboot"    set "OLD_BOOTLOADER=%V%"
if /i "%K%"=="variant"    set "VARIANT=%V%"
if /i "%K%"=="f_cpu"      set "F_CPU=%V%"
if /i "%K%"=="project"    set "PROJECT=%V%"
if /i "%K%"=="src"        set "SRC_DIR=%V%"
if /i "%K%"=="inc"        set "INC_DIR=%V%"
if /i "%K%"=="pkgs"       set "PKG=%V%"
if /i "%K%"=="mcu"        set "MCU=%V%"
if /i "%K%"=="baud"       set "BAUD_UPLOAD=%V%"
exit /b 0
