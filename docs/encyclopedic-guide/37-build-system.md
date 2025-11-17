# Chapter 37: Build System

Surge XT uses CMake as its build system to manage compilation across Windows, macOS, and Linux platforms. The build system handles multiple plugin formats (VST3, AU, CLAP, LV2), standalone applications, effects plugins, test runners, Python bindings, and automated installers.

---

## 37.1 CMake Overview

### 37.1.1 Why CMake?

Surge XT requires a sophisticated build system that can:

1. **Cross-platform support**: Generate native build files for Visual Studio (Windows), Xcode (macOS), Ninja, and Unix Makefiles
2. **Multiple toolchains**: Support MSVC, Clang, GCC, and cross-compilation toolchains
3. **Complex dependencies**: Manage 20+ submodule dependencies including JUCE, SST libraries, LuaJIT, and more
4. **Multiple targets**: Build synth, effects, standalone, CLI, test runner, and Python bindings from a single source tree
5. **Plugin formats**: Generate VST3, AU, CLAP, LV2, and legacy VST2 simultaneously
6. **Conditional compilation**: Handle platform-specific code, optional features, and build variants

CMake version 3.15 or higher is required, with 3.21+ recommended for CLAP support.

### 37.1.2 Main CMakeLists.txt Structure

The root `/home/user/surge/CMakeLists.txt` establishes global build configuration:

```cmake
cmake_minimum_required(VERSION 3.15)
cmake_policy(SET CMP0091 NEW)
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
set(CMAKE_OSX_DEPLOYMENT_TARGET 10.13 CACHE STRING "Minimum macOS version")
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

project(Surge VERSION 1.4.0 LANGUAGES C CXX ASM)
```

**Key features:**

- **Runtime library**: Static linking of MSVC runtime for Windows
- **macOS deployment**: Targets macOS 10.13+ (High Sierra) for compatibility
- **Position-independent code**: Required for plugin formats
- **Compile commands**: Exports `compile_commands.json` for IDE integration and clang-tidy

The build system enforces:
- C++20 standard (`CMAKE_CXX_STANDARD 20`)
- 64-bit builds (with experimental 32-bit Windows support)
- Release builds by default with optional LTO (Link-Time Optimization)
- Submodule validation (fails if `libs/tuning-library/README.md` missing)

### 37.1.3 Directory Structure

```
surge/
├── CMakeLists.txt              # Root configuration
├── cmake/                      # Build utilities
│   ├── versiontools.cmake      # Version string generation
│   ├── stage-extra-content.cmake  # Extra content downloads
│   ├── x86_64-w64-mingw32.cmake   # Cross-compile toolchains
│   └── linux-aarch64-ubuntu-crosscompile-toolchain.cmake
├── src/
│   ├── CMakeLists.txt          # Plugin/target configuration
│   ├── cmake/lib.cmake         # Helper functions
│   ├── common/CMakeLists.txt   # Core library
│   ├── surge-xt/CMakeLists.txt # Synth plugin
│   ├── surge-fx/CMakeLists.txt # Effects plugin
│   ├── surge-testrunner/CMakeLists.txt
│   └── surge-python/CMakeLists.txt
├── resources/CMakeLists.txt    # Resource installation
└── libs/                       # Git submodules (JUCE, SST, etc.)
```

---

## 37.2 Build Targets

The build system generates multiple targets from shared source code.

### 37.2.1 surge-common

The core library containing DSP, synthesis, modulation, and patch management:

```cmake
add_library(surge-common
  SurgeSynthesizer.cpp
  SurgeStorage.cpp
  Parameter.cpp
  dsp/Effect.cpp
  dsp/Oscillator.cpp
  dsp/SurgeVoice.cpp
  # ... 200+ source files
)
```

**Links against:**
- `airwindows` - Additional effects algorithms
- `eurorack` - Mutable Instruments DSP
- `fmt` - Formatting library
- `oddsound-mts` - MTS-ESP microtonal support
- `pffft` - Fast FFT implementation
- `tuning-library` - SCL/KBM tuning support
- `luajit-5.1` - Lua scripting (optional with `SURGE_SKIP_LUA`)
- SST libraries: `sst-basic-blocks`, `sst-filters`, `sst-waveshapers`, `sst-effects`, `sst-plugininfra`, `sst-jucegui`
- `sqlite-3.23.3` - Patch database
- `PEGTL` - Parser library

**Compile definition:**
```cmake
target_compile_definitions(surge-common PUBLIC
  SURGE_COMPILE_BLOCK_SIZE=${SURGE_COMPILE_BLOCK_SIZE})
```

Default block size is 32 samples (configurable via `-DSURGE_COMPILE_BLOCK_SIZE`).

### 37.2.2 surge-xt (Synthesizer Plugin)

Full-featured synthesizer with 8 oscillators, filters, effects, and modulation:

```cmake
juce_add_plugin(surge-xt
  PRODUCT_NAME "Surge XT"
  COMPANY_NAME "Surge Synth Team"
  BUNDLE_ID "org.surge-synth-team.surge-xt"
  PLUGIN_MANUFACTURER_CODE VmbA
  PLUGIN_CODE SgXT

  IS_SYNTH TRUE
  NEEDS_MIDI_INPUT TRUE

  VST3_CATEGORIES Instrument Synth
  AU_MAIN_TYPE kAudioUnitType_MusicDevice

  FORMATS ${SURGE_JUCE_FORMATS}
)
```

**Generates targets:**
- `surge-xt_VST3` - VST3 plugin
- `surge-xt_AU` - Audio Unit (macOS only)
- `surge-xt_CLAP` - CLAP plugin
- `surge-xt_LV2` - LV2 plugin (optional)
- `surge-xt_Standalone` - Standalone application with JACK/ALSA (Linux)
- `surge-xt_Packaged` - Meta-target that builds all formats

**CLAP support** (requires CMake 3.21+):
```cmake
if(SURGE_BUILD_CLAP)
  clap_juce_extensions_plugin(TARGET surge-xt
    CLAP_ID "org.surge-synth-team.surge-xt"
    CLAP_FEATURES "instrument" "synthesizer" "stereo")
endif()
```

**Includes CLI tool** (`surge-xt-cli`):
On macOS, the CLI is automatically embedded in the Standalone app bundle at `Surge XT.app/Contents/MacOS/surge-xt-cli`.

### 37.2.3 surge-fx (Effects Plugin)

Standalone effects plugin exposing Surge's 30+ effects:

```cmake
juce_add_plugin(surge-fx
  PRODUCT_NAME "Surge XT Effects"
  BUNDLE_ID "org.surge-synth-team.surge-xt-fx"
  PLUGIN_CODE SFXT

  IS_SYNTH FALSE
  NEEDS_MIDI_INPUT FALSE

  VST3_CATEGORIES Fx
  AU_MAIN_TYPE kAudioUnitType_Effect

  FORMATS ${SURGE_JUCE_FORMATS}
)
```

**Generates:** `surge-fx_VST3`, `surge-fx_AU`, `surge-fx_CLAP`, `surge-fx_Standalone`, `surge-fx_Packaged`

### 37.2.4 surge-testrunner

Comprehensive unit test suite using Catch2 v3:

```cmake
add_executable(surge-testrunner
  UnitTests.cpp
  UnitTestsDSP.cpp
  UnitTestsFLT.cpp
  UnitTestsFX.cpp
  UnitTestsINFRA.cpp
  UnitTestsIO.cpp
  UnitTestsLUA.cpp
  UnitTestsMIDI.cpp
  UnitTestsMOD.cpp
  UnitTestsMSEG.cpp
  UnitTestsNOTEID.cpp
  UnitTestsPARAM.cpp
  UnitTestsQUERY.cpp
  UnitTestsTUN.cpp
  UnitTestsVOICE.cpp
)
```

**Test discovery:**
```cmake
catch_discover_tests(surge-testrunner WORKING_DIRECTORY ${SURGE_SOURCE_DIR})
```

Tests are automatically discovered and can be run via CTest:
```bash
cd build
ctest -j 4 || ctest --rerun-failed --output-on-failure
```

### 37.2.5 surgepy (Python Bindings)

Python bindings using pybind11 for headless synthesis and DSP scripting:

```cmake
pybind11_add_module(surgepy surgepy.cpp)
target_link_libraries(surgepy PRIVATE surge::surge-common)
```

**Build with:**
```bash
cmake -Bbuild -DSURGE_BUILD_PYTHON_BINDINGS=TRUE
cmake --build build --target surgepy
```

**Usage:**
```python
import surgepy
synth = surgepy.createSurge(44100)
synth.playNote(0, 60, 127, 0)
```

### 37.2.6 surge-xt-distribution

Meta-target that builds all plugins, packages them, and creates installers:

```bash
cmake --build build --target surge-xt-distribution
```

**Generates:**
- **macOS**: `.pkg` installer + `surge-xt-macos-VERSION-pluginsonly.zip`
- **Linux**: `.deb`, `.rpm` packages + `surge-xt-linux-VERSION-pluginsonly.tar.gz` + portable archive
- **Windows**: `.exe` Inno Setup installer

Outputs appear in `build/surge-xt-dist/`.

---

## 37.3 Dependencies

All dependencies are managed via Git submodules in `libs/`.

### 37.3.1 Core Dependencies

```bash
git submodule update --init --recursive
```

**Primary dependencies:**

| Library | Purpose | Location |
|---------|---------|----------|
| **JUCE** | Audio plugin framework | `libs/JUCE` (custom fork) |
| **clap-juce-extensions** | CLAP plugin support | `libs/clap-juce-extensions` |
| **eurorack** | Mutable Instruments DSP | `libs/eurorack/eurorack` |
| **fmt** | String formatting | `libs/fmt` |
| **LuaJIT** | Wavetable scripting | `libs/luajitlib/LuaJIT` |
| **simde** | SIMD portability (ARM) | `libs/simde` |
| **tuning-library** | Microtonal support | `libs/tuning-library` |
| **MTS-ESP** | MTS-ESP protocol | `libs/oddsound-mts/MTS-ESP` |
| **PEGTL** | Parser library | `libs/PEGTL` |
| **pffft** | Fast FFT | `libs/pffft` |
| **pybind11** | Python bindings | `libs/pybind11` |

### 37.3.2 SST Libraries

Surge Synth Team shared libraries:

- **sst-basic-blocks**: SIMD wrappers, utility functions
- **sst-cpputils**: C++ utilities
- **sst-effects**: Shared effects DSP
- **sst-filters**: Filter implementations
- **sst-plugininfra**: Plugin infrastructure helpers
- **sst-waveshapers**: Waveshaping algorithms
- **sst-jucegui**: JUCE GUI utilities

All SST libraries support ARM64 via SIMDE (`SST_BASIC_BLOCKS_SIMD_OMIT_NATIVE_ALIASES`).

### 37.3.3 Optional Dependencies

**VST2 SDK** (if available):
```bash
export VST2SDK_DIR=/path/to/VST_SDK/VST2_SDK
```

CMake will detect and enable VST2 builds if the environment variable is set.

**ASIO SDK** (Windows):
Located at `libs/sst/sst-plugininfra/libs/asiosdk`. Automatically detected and enables ASIO support in standalone builds.

**Melatonin Inspector** (debug builds):
```bash
cmake -DSURGE_INCLUDE_MELATONIN_INSPECTOR=ON
```

---

## 37.4 Platform-Specific Configuration

### 37.4.1 Windows

**Visual Studio (Primary):**
```bash
cmake -Bbuild -G "Visual Studio 17 2022" -A x64
cmake --build build --config Release --parallel
```

**Architectures:**
- **x64**: Standard 64-bit Intel/AMD
- **arm64**: Native ARM64 (Windows on ARM)
- **arm64ec**: ARM64 Emulation Compatible (hybrid mode)

**ARM64 builds:**
```bash
cmake -Bbuild -G "Visual Studio 17 2022" -A arm64 -DSURGE_SKIP_LUA=TRUE
```

Note: LuaJIT is not yet available for Windows ARM64, so `-DSURGE_SKIP_LUA=TRUE` is required.

**MSVC-specific flags:**
- `/WX` - Warnings as errors
- `/MP` - Multi-processor compilation
- `/utf-8` - UTF-8 source/execution charset
- `/bigobj` - Large object files
- `/Zc:char8_t-` - Disable C++20 char8_t

**Clang-CL (experimental):**
```bash
cmake -Bbuild -GNinja -DCMAKE_CXX_COMPILER=clang++ -DCMAKE_C_COMPILER=clang
```

**MSYS2/MinGW:**
Not officially supported but possible with custom toolchain files.

### 37.4.2 macOS

**Xcode:**
```bash
cmake -Bbuild -GXcode -DCMAKE_OSX_ARCHITECTURES="x86_64;arm64"
open build/Surge.xcodeproj
```

**Ninja (recommended for CI):**
```bash
cmake -Bbuild -GNinja -DCMAKE_OSX_ARCHITECTURES="x86_64;arm64"
cmake --build build --parallel
```

**Universal binaries** (x86_64 + arm64):
```bash
-DCMAKE_OSX_ARCHITECTURES="x86_64;arm64"
```

**Code signing** (for distribution):
```bash
export MAC_SIGNING_CERT="Developer ID Application: ..."
export MAC_SIGNING_ID="team_id"
export MAC_SIGNING_1UPW="app-specific password"
export MAC_SIGNING_TEAM="team_id"

cmake --build build --target surge-xt-distribution
```

The build system automatically signs and notarizes macOS builds when environment variables are set (CI only).

**Platform-specific flags:**
- `-faligned-allocation` - C++17 aligned new
- `-fasm-blocks` - Apple assembly syntax
- Objective-C/C++ enabled automatically

### 37.4.3 Linux

**Ubuntu/Debian:**
```bash
sudo apt install build-essential libxcb-cursor-dev libxcb-keysyms1-dev \
  libxcb-util-dev libxkbcommon-x11-dev libasound2-dev libjack-jackd2-dev \
  libfreetype6-dev libfontconfig1-dev

cmake -Bbuild -GNinja
cmake --build build --parallel
```

**JACK/ALSA support** (standalone only):
```cmake
if (UNIX AND NOT APPLE)
  set(SURGE_USE_ALSA TRUE)
  set(SURGE_USE_JACK TRUE)
endif()
```

Disable with:
```bash
cmake -DSURGE_SKIP_ALSA=TRUE -DSURGE_SKIP_JACK=TRUE
```

**LV2 support:**
```bash
cmake -DSURGE_BUILD_LV2=TRUE
```

LV2 is off by default due to CI instability but works fine for local builds.

**Installation:**
```bash
cmake --install build --prefix /usr/local
```

Installs to:
- Plugins: `/usr/local/lib/vst3/`, `/usr/local/lib/clap/`, `/usr/local/lib/lv2/`
- Standalone: `/usr/local/bin/surge-xt_Standalone`
- CLI: `/usr/local/bin/surge-xt-cli`
- Resources: `/usr/local/share/surge-xt/`

**Compiler support:**
- **GCC 9+**: Primary Linux compiler
- **Clang 10+**: Fully supported

**Linux-specific flags:**
- `-no-pie` - Position-independent executable disabled (overridable via `SURGE_SKIP_PIE_CHANGE`)
- `-fvisibility=hidden` - Symbol visibility
- `-msse2 -mfpmath=sse` - SSE2 on 32-bit x86

### 37.4.4 Cross-Compilation

**Windows from Linux (MinGW):**
```bash
cmake -Bbuild \
  -DCMAKE_TOOLCHAIN_FILE=cmake/x86_64-w64-mingw32.cmake \
  -DCMAKE_BUILD_TYPE=Release

cmake --build build
```

**ARM64 Linux from x86_64:**
```bash
sudo apt install gcc-aarch64-linux-gnu g++-aarch64-linux-gnu

cmake -Bbuild \
  -DCMAKE_TOOLCHAIN_FILE=cmake/linux-aarch64-ubuntu-crosscompile-toolchain.cmake

cmake --build build
```

**Toolchain file structure:**
```cmake
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)
set(CMAKE_C_COMPILER aarch64-linux-gnu-gcc)
set(CMAKE_CXX_COMPILER aarch64-linux-gnu-g++)
```

**Available toolchains:**
- `cmake/x86_64-w64-mingw32.cmake` - Windows x64 from Linux
- `cmake/i686-w64-mingw32.cmake` - Windows x86 from Linux
- `cmake/linux-aarch64-ubuntu-crosscompile-toolchain.cmake` - ARM64 Linux
- `cmake/linux-arm-ubuntu-crosscompile-toolchain.cmake` - ARM32 Linux
- `cmake/arm-native.cmake` - Native ARM builds

---

## 37.5 CMake Configuration Options

### 37.5.1 Build Targets Control

```cmake
option(SURGE_BUILD_XT "Build Surge XT synth" ON)
option(SURGE_BUILD_FX "Build Surge FX bank" ON)
option(SURGE_BUILD_TESTRUNNER "Build Surge unit test runner" ON)
option(SURGE_BUILD_PYTHON_BINDINGS "Build Surge Python bindings" OFF)
```

**Examples:**
```bash
# Build only effects plugin
cmake -Bbuild -DSURGE_BUILD_XT=OFF -DSURGE_BUILD_FX=ON

# Build Python bindings only
cmake -Bbuild -DSURGE_BUILD_PYTHON_BINDINGS=ON \
               -DSURGE_BUILD_XT=OFF -DSURGE_BUILD_FX=OFF
```

### 37.5.2 Plugin Format Control

```cmake
option(SURGE_BUILD_CLAP "Build Surge as a CLAP" ON)
option(SURGE_BUILD_LV2 "Build Surge as an LV2" OFF)
```

**Internal skip options:**
- `SURGE_SKIP_VST3` - Skip VST3 builds
- `SURGE_SKIP_STANDALONE` - Skip standalone builds
- `SURGE_SKIP_JUCE_FOR_RACK` - Skip JUCE entirely (for VCV Rack port)

**Example:**
```bash
# Build VST3 and CLAP only (no standalone)
cmake -Bbuild -DSURGE_SKIP_STANDALONE=ON
```

### 37.5.3 DSP Configuration

```cmake
set(SURGE_COMPILE_BLOCK_SIZE 32)
```

**Block size options:**
- **16**: Lower latency, more CPU overhead
- **32**: Default, balanced performance
- **64**: Higher throughput, higher latency
- **128**: Maximum efficiency for offline rendering

**Example:**
```bash
cmake -Bbuild -DSURGE_COMPILE_BLOCK_SIZE=64
```

### 37.5.4 Optional Features

```cmake
option(SURGE_SKIP_LUA "Skip LuaJIT (no wavetable scripting)" OFF)
option(SURGE_SKIP_ODDSOUND_MTS "Skip MTS-ESP support" OFF)
option(SURGE_EXPOSE_PRESETS "Expose presets via JUCE Program API" OFF)
option(SURGE_INCLUDE_MELATONIN_INSPECTOR "Include GUI inspector" OFF)
```

**Example:**
```bash
# ARM64 build without Lua
cmake -Bbuild -DSURGE_SKIP_LUA=TRUE

# Debug build with GUI inspector
cmake -Bbuild -DCMAKE_BUILD_TYPE=Debug \
               -DSURGE_INCLUDE_MELATONIN_INSPECTOR=ON
```

### 37.5.5 Development Options

```cmake
option(SURGE_COPY_TO_PRODUCTS "Copy to products directory" ON)
option(SURGE_COPY_AFTER_BUILD "Copy to system plugin directory" OFF)
option(ENABLE_LTO "Link-time optimization" ON)
option(SURGE_SANITIZE "Enable address/undefined sanitizers" OFF)
```

**Example:**
```bash
# Install plugins to system directories automatically
cmake -Bbuild -DSURGE_COPY_AFTER_BUILD=ON

# Sanitizer build for debugging
cmake -Bbuild -DCMAKE_BUILD_TYPE=Debug -DSURGE_SANITIZE=ON
```

### 37.5.6 Path Configuration

```cmake
set(SURGE_JUCE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/../libs/JUCE"
    CACHE STRING "Path to JUCE library")
set(SURGE_SIMDE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/../libs/simde"
    CACHE STRING "Path to simde library")
```

**Override for custom JUCE:**
```bash
cmake -Bbuild -DSURGE_JUCE_PATH=/custom/juce/path
```

---

## 37.6 Build Process

### 37.6.1 Standard Build

**1. Initialize submodules:**
```bash
git submodule update --init --recursive
```

**2. Configure:**
```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
```

**3. Build:**
```bash
cmake --build build --config Release --parallel
```

**4. Test:**
```bash
cd build
ctest -j 4
```

**5. Install (Linux):**
```bash
sudo cmake --install build
```

### 37.6.2 Quick Builds

**Build specific target:**
```bash
# Just the VST3
cmake --build build --target surge-xt_VST3

# Just the test runner
cmake --build build --target surge-testrunner

# Run tests immediately
cmake --build build --target surge-testrunner && cd build && ctest
```

**Incremental builds:**
```bash
# Only rebuild changed files
cmake --build build
```

### 37.6.3 Clean Builds

```bash
# Clean build artifacts
cmake --build build --target clean

# Complete rebuild
rm -rf build
cmake -Bbuild
cmake --build build
```

### 37.6.4 Generator Selection

**Ninja (fastest):**
```bash
cmake -Bbuild -GNinja
ninja -C build
```

**Make (Unix):**
```bash
cmake -Bbuild -G "Unix Makefiles"
make -C build -j$(nproc)
```

**Visual Studio:**
```bash
cmake -Bbuild -G "Visual Studio 17 2022" -A x64
cmake --build build --config Release
# Or open: build/Surge.sln
```

**Xcode:**
```bash
cmake -Bbuild -GXcode
open build/Surge.xcodeproj
```

### 37.6.5 Build Outputs

**Plugin locations:**
```
build/surge_xt_products/
├── surge-xt-cli               # CLI tool (Linux/macOS)
├── surge-xt-cli.exe           # CLI tool (Windows)
├── Surge XT.app/              # Standalone (macOS)
├── Surge XT.exe               # Standalone (Windows)
├── surge-xt_Standalone        # Standalone (Linux)
├── Surge XT.vst3/             # VST3 bundle
├── Surge XT.component/        # AU bundle (macOS)
├── Surge XT.clap              # CLAP plugin
└── Surge XT.lv2/              # LV2 bundle (Linux)
```

---

## 37.7 CI/CD Infrastructure

### 37.7.1 GitHub Actions

**PR validation** (`.github/workflows/build-pr.yml`):

```yaml
jobs:
  build_plugin:
    strategy:
      matrix:
        include:
          - name: "Windows MSVC"
            os: windows-latest
            target: surge-xt_Standalone
            cmakeConfig: -A x64

          - name: "macOS standalone"
            os: macos-latest
            target: surge-xt_Standalone
            cmakeConfig: -DCMAKE_OSX_ARCHITECTURES="x86_64;arm64"

          - name: "Linux test runner"
            os: ubuntu-latest
            target: surge-testrunner
            runTests: true
```

**Runs on every PR:**
- Windows: MSVC x64, ARM64, ARM64EC, JUCE 7 compatibility
- macOS: Universal binary, test runner
- Linux: Native build, Docker (Ubuntu 20), test runner
- Python: SurgePy on Windows and Linux

**Release builds** (`.github/workflows/build-release.yml`):

Triggered on:
- Push to `main` (nightly builds)
- Tags matching `release_xt_*` (stable releases)

**Generates:**
- Windows installers (.exe) for x64, ARM64, ARM64EC
- macOS installers (.pkg) + universal binaries
- Linux packages (.deb, .rpm, .tar.gz)
- Plugin-only archives for all platforms

**Automated tasks:**
1. Version calculation from Git branch/tag
2. Code signing (macOS) and notarization
3. Installer creation (Inno Setup on Windows, pkgbuild on macOS)
4. Upload to GitHub Releases
5. Discord notifications
6. Website update notifications

### 37.7.2 Build Matrix

**Platforms tested:**

| OS | Compiler | Architectures | CI |
|----|----------|---------------|-----|
| Windows 10+ | MSVC 2022 | x64, ARM64, ARM64EC | ✓ |
| Windows 10+ | Clang-CL | x64 | Experimental |
| macOS 11+ | AppleClang | x86_64, arm64, Universal | ✓ |
| Ubuntu 20.04+ | GCC 11 | x86_64 | ✓ (Docker) |
| Ubuntu 22.04+ | GCC | x86_64 | ✓ |
| Ubuntu | Clang | x86_64 | Manual |
| Linux | GCC | aarch64, armv7 | Cross-compile |

### 37.7.3 Code Quality Checks

**clang-format validation:**
```bash
cmake --build build --target code-quality-pipeline-checks
```

Runs on all PR builds to enforce code style:
```cmake
add_custom_command(TARGET code-quality-pipeline-checks
  COMMAND git ls-files -- ':(glob)src/**/*.cpp' ':(glob)src/**/*.h'
    | xargs clang-format-12 --dry-run --Werror
)
```

### 37.7.4 Version Generation

**Version calculation** (`cmake/versiontools.cmake`):

```cmake
execute_process(
  COMMAND ${GIT_EXECUTABLE} rev-parse --abbrev-ref HEAD
  OUTPUT_VARIABLE GIT_BRANCH
)
execute_process(
  COMMAND ${GIT_EXECUTABLE} rev-parse --short HEAD
  OUTPUT_VARIABLE GIT_COMMIT_HASH
)
```

**Version strings:**
- **main branch**: `1.4.0.nightly.abc1234` (CI) or `1.4.0.main.abc1234` (local)
- **Release branch** (`release-xt/1.4.5`): `1.4.0.5.abc1234`
- **Feature branch**: `1.4.0.branch-name.abc1234`

Generated into `build/geninclude/version.cpp`:
```cpp
const char* Build::FullVersionStr = "1.4.0.nightly.8e1508d";
const char* Build::BuildDate = "2025-11-17";
const char* Build::BuildTime = "14:23:45";
```

---

## 37.8 Advanced Topics

### 37.8.1 Custom Toolchain Files

Create `cmake/my-toolchain.cmake`:
```cmake
set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_C_COMPILER /opt/custom/bin/gcc)
set(CMAKE_CXX_COMPILER /opt/custom/bin/g++)
add_compile_options(-march=native)
```

Use with:
```bash
cmake -Bbuild -DCMAKE_TOOLCHAIN_FILE=cmake/my-toolchain.cmake
```

### 37.8.2 Extra Content

Download optional skins and content:
```bash
cmake --build build --target download-extra-content
cmake --build build --target stage-extra-content
```

Clones `surge-extra-content` repository and copies skins to `resources/data/skins/`.

### 37.8.3 Pluginval Integration

JUCE plugin validator integration:
```bash
cmake --build build --target surge-xt-pluginval
```

Automatically downloads pluginval and validates all built plugins.

### 37.8.4 Compile Commands Database

Exported automatically to `build/compile_commands.json` for:
- clangd language server
- Visual Studio Code
- CLion
- clang-tidy static analysis

Symlink to project root:
```bash
ln -s build/compile_commands.json .
```

---

## 37.9 Troubleshooting

### 37.9.1 Common Issues

**Submodule not initialized:**
```
CMake Error: Cannot find the contents of the tuning-library submodule
```
Solution: `git submodule update --init --recursive`

**JUCE version mismatch:**
```
CMake Error: You must build against at least JUCE 6.1
```
Solution: Update JUCE submodule or set `SURGE_JUCE_PATH`

**CMake too old for CLAP:**
```
CMake version less than 3.21. Skipping clap builds.
```
Solution: Upgrade CMake or disable CLAP with `-DSURGE_BUILD_CLAP=OFF`

**32-bit Linux build:**
```
Error: 32-bit builds are only available on Windows
```
Solution: Use 64-bit OS or override with `-DSURGE_BUILD_32BIT_LINUX=ON` (unsupported)

### 37.9.2 Clean State

Complete build system reset:
```bash
git submodule foreach --recursive git clean -ffdx
git clean -ffdx
rm -rf build
git submodule update --init --recursive
cmake -Bbuild
cmake --build build
```

### 37.9.3 Verbose Builds

Debug CMake configuration:
```bash
cmake -Bbuild --debug-output
cmake -Bbuild --trace
```

Verbose compilation:
```bash
cmake --build build --verbose
make -C build VERBOSE=1
```

---

## 37.10 Summary

The Surge XT build system demonstrates modern CMake best practices:

1. **Cross-platform**: Unified build system for Windows, macOS, Linux
2. **Modular**: Separate targets for synth, effects, tests, Python
3. **Flexible**: 20+ configuration options for customization
4. **Automated**: Full CI/CD with installers and code signing
5. **Maintainable**: Clear structure, helper functions, documentation
6. **Performance**: LTO, parallel builds, incremental compilation
7. **Developer-friendly**: IDE integration, sanitizers, code quality checks

**Essential commands:**
```bash
# Standard build
git submodule update --init --recursive
cmake -Bbuild -DCMAKE_BUILD_TYPE=Release
cmake --build build --parallel

# Run tests
cd build && ctest

# Build installers
cmake --build build --target surge-xt-distribution
```

**Key configuration options:**
- `-DCMAKE_BUILD_TYPE=Release|Debug`
- `-DSURGE_COMPILE_BLOCK_SIZE=32`
- `-DSURGE_BUILD_PYTHON_BINDINGS=ON`
- `-DSURGE_BUILD_LV2=ON`
- `-DCMAKE_OSX_ARCHITECTURES="x86_64;arm64"`

The build system evolves with each release, balancing backward compatibility with modern CMake features.

---

**Next Chapter:** [38: Debugging and Profiling →](38-debugging-profiling.md)

**Previous Chapter:** [← 36: Previous Chapter](36-previous-chapter.md)

**[Return to Index](00-INDEX.md)**
