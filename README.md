# Arduino Nano C++ Build (No Arduino IDE)

Pure **C++** build system for **Arduino Nano (ATmega328P)** using the AVR-GCC toolchain and the Arduino AVR core from your local **Arduino15** cache. No `.ino`, no hidden temp files.

## Layout
```
project/
├─ build.bat          # build / upload / size / clean / where
├─ src/               # your .cpp (must provide setup()/loop() in main.cpp)
├─ include/           # your headers
└─ .nanorc.env        # (optional) defaults as KEY=VALUE lines
```

## Usage
Run from a terminal in the project folder:

```
build.bat [command] [switches]
```

### Commands
- `build`  – compile + link → `.elf` & `.hex` (default)
- `upload` – build then flash via avrdude
- `size`   – print flash/RAM usage
- `clean`  – delete `.build` artifacts
- `where`  – show resolved toolchain + core paths

### Switches
Override defaults without editing the script:
- `/port=COM5` → serial port
- `/oldboot=1` → old bootloader @ 57600 baud
- `/variant=eightanaloginputs` → Nano variant
- `/f_cpu=16000000UL` → CPU frequency
- `/project=MyApp` → project/output name
- `/src=src` → source folder
- `/inc=include` → include folder
- `/pkgs=C:\path\to\Arduino15\packages\arduino` → override Arduino15 root
- `/mcu=atmega328p` → MCU type
- `/baud=115200` → force baud rate

## Examples
```
:: Build with defaults
build.bat

:: Build for COM7, old bootloader
build.bat build /port=COM7 /oldboot=1

:: Upload firmware to COM4
build.bat upload /port=COM4 /project=MyNanoApp

:: Print resolved paths
build.bat where

:: Show size report
build.bat size
```

## .nanorc.env
Optional file in the project root:
```
PORT=COM5
OLD_BOOTLOADER=1
VARIANT=eightanaloginputs
F_CPU=16000000UL
PROJECT=CryptoEmbedV1
```

## Requirements
- Arduino IDE/CLI installed once to populate `%LOCALAPPDATA%\Arduino15\packages`
- Arduino AVR Boards core installed via Board Manager
- Windows with batch shell

## Outputs
- `.build/<Project>.elf` – linked ELF binary
- `.build/<Project>.hex` – Intel HEX for flashing
