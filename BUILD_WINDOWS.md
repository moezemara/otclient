# Windows Build Guide

## Prerequisites
- Visual Studio 2022
- CMake 3.22+
- vcpkg at `C:\vcpkg`

## First-Time Setup
1. Open **"x64 Native Tools Command Prompt for VS 2022"** from the Start menu
   - On ARM64 Windows, use **"x64 Cross Tools Command Prompt for VS 2022"** instead
2. Run:
```cmd
set VCPKG_ROOT=C:\vcpkg
cd C:\Users\moeze\Desktop\tibia-development\otclient
cmake --preset windows-release
cmake --build --preset windows-release
```

## Rebuilding After Code Changes
```cmd
cmake --build --preset windows-release
```

## Reconfigure (only needed if CMakeLists.txt or vcpkg.json changed)
```cmd
cmake --preset windows-release
cmake --build --preset windows-release
```

## Notes
- Always build from **x64 Native Tools Command Prompt for VS 2022**, not regular cmd or PowerShell
- `set VCPKG_ROOT=C:\vcpkg` must be set each time you open a new prompt
- Output binary: `build/windows-release/otclient.exe`
- Tests are built to `build/windows-release/tests/`
