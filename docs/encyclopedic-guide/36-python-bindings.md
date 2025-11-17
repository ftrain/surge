# Chapter 36: Python Bindings

Surge XT provides Python bindings through `surgepy`, enabling programmatic control of the synthesis engine for batch processing, automated analysis, machine learning dataset generation, and research applications. This chapter explores the Python API, building process, and practical use cases for integrating Surge XT into Python-based audio workflows.

---

## 36.1 Python Bindings Overview

### 36.1.1 What is surgepy?

`surgepy` is a Python module that exposes the core Surge XT synthesis engine through a C++ extension built with pybind11. Unlike the plugin versions (VST3, AU, CLAP) that run within a DAW, surgepy provides direct programmatic access to:

- **Synthesis engine**: Create and control SurgeSynthesizer instances
- **Parameter manipulation**: Read and write all synthesis parameters
- **Patch management**: Load, modify, and save .fxp patches
- **Audio rendering**: Generate audio buffers for offline processing
- **Modulation matrix**: Configure and query modulation routings
- **MIDI control**: Trigger notes and send MIDI messages programmatically
- **Tuning systems**: Load SCL/KBM files and control microtuning

The bindings expose the same synthesis engine that powers the plugin, ensuring identical audio output and parameter behavior.

```python
import surgepy
import numpy as np

# Create a Surge instance at 44.1 kHz
surge = surgepy.createSurge(44100)

# Play a note
surge.playNote(channel=0, midiNote=60, velocity=127, detune=0)

# Process audio blocks
surge.process()
output = surge.getOutput()  # Returns 2 x 32 numpy array
```

### 36.1.2 Use Cases

**Batch Audio Rendering**: Generate audio from multiple patches automatically for sample library creation, preset previewing, or A/B comparison testing.

```python
# Render all factory patches playing middle C
import os

surge = surgepy.createSurge(44100)
factory_path = surge.getFactoryDataPath()
patches_dir = os.path.join(factory_path, "patches_factory")

for root, dirs, files in os.walk(patches_dir):
    for file in files:
        if file.endswith(".fxp"):
            patch_path = os.path.join(root, file)
            surge.loadPatch(patch_path)
            # Render and save audio...
```

**Parameter Exploration**: Systematically sweep parameters to analyze their effect on timbre, create morphing sequences, or discover interesting parameter combinations.

**Machine Learning Datasets**: Generate labeled audio datasets for training neural networks, audio feature extractors, or synthesis parameter prediction models.

**Automated Testing**: Validate synthesis behavior, test parameter ranges, verify patch compatibility across versions, and perform regression testing.

**Sound Design Research**: Explore synthesis algorithms, analyze modulation behaviors, study filter responses, and prototype new features before implementing them in C++.

**Scientific Analysis**: Study wavetable interpolation methods, measure filter frequency responses, analyze envelope shapes, or investigate aliasing artifacts.

### 36.1.3 Architecture

The Python bindings live in `/home/user/surge/src/surge-python/`:

```
src/surge-python/
├── surgepy.cpp              # Main pybind11 bindings
├── CMakeLists.txt          # Build configuration
├── setup.py                # Python package setup (scikit-build)
├── pyproject.toml          # Package metadata
├── surgepy/                # Python package
│   ├── __init__.py         # Module initialization
│   ├── __init__.pyi        # Type stubs
│   └── _surgepy/
│       ├── __init__.pyi    # Type hints
│       └── constants.pyi   # Constants type hints
└── tests/
    ├── test_surgepy.py     # Unit tests
    └── write_wavetable.py  # Example script
```

The binding layer consists of:

1. **C++ wrapper classes**: Extend `SurgeSynthesizer` with Python-friendly methods
2. **pybind11 bindings**: Expose C++ classes and functions to Python
3. **NumPy integration**: Zero-copy audio buffer exchange using numpy arrays
4. **Constants module**: Exposes Surge enums (oscillator types, filter types, etc.)

---

## 36.2 Building surgepy

### 36.2.1 Build Requirements

**Prerequisites:**
- CMake 3.15+ (3.21+ recommended)
- Python 3.7 or higher
- C++20 compatible compiler (GCC 10+, Clang 11+, MSVC 2019+)
- NumPy (automatically installed as dependency)
- Git submodules initialized (`git submodule update --init --recursive`)

**Build dependencies** (automatically fetched by CMake):
- pybind11 (Python/C++ binding library)
- surge-common (core synthesis library)
- All standard Surge dependencies (JUCE, SST libraries, etc.)

### 36.2.2 Manual Build with CMake

The Python bindings are **disabled by default** and must be explicitly enabled with `-DSURGE_BUILD_PYTHON_BINDINGS=ON`:

```bash
cd surge

# Configure build with Python bindings enabled
cmake -Bbuildpy \
  -DSURGE_BUILD_PYTHON_BINDINGS=ON \
  -DCMAKE_BUILD_TYPE=Release

# Build the surgepy target
cmake --build buildpy --config Release --target surgepy --parallel
```

**Build output locations:**
- **macOS**: `buildpy/src/surge-python/surgepy.cpython-311-darwin.so`
- **Linux**: `buildpy/src/surge-python/surgepy.cpython-311-x86_64-linux-gnu.so`
- **Windows**: `buildpy/src/surge-python/Release/surgepy.cp312-win_amd64.pyd`

The exact filename depends on your Python version (e.g., `cpython-311` for Python 3.11).

### 36.2.3 CMake Configuration Details

The `src/surge-python/CMakeLists.txt` configures the build:

```cmake
project(surgepy)

# Add pybind11 from libs/pybind11 submodule
add_subdirectory(${CMAKE_SOURCE_DIR}/libs/pybind11 pybind11)
pybind11_add_module(${PROJECT_NAME})

target_sources(${PROJECT_NAME} PRIVATE surgepy.cpp)

# Link against core synthesis engine
target_link_libraries(${PROJECT_NAME} PRIVATE
  surge::surge-common
)

# Platform-specific configuration
if(UNIX AND NOT APPLE)
  find_package(Threads REQUIRED)
  target_link_libraries(${PROJECT_NAME} PRIVATE Threads::Threads)
endif()
```

**Key build flags** in `src/CMakeLists.txt`:

```cmake
option(SURGE_BUILD_PYTHON_BINDINGS "Build Surge Python bindings with pybind11" OFF)

if(SURGE_BUILD_PYTHON_BINDINGS)
  add_subdirectory(surge-python)
endif()
```

When Python bindings are enabled, VST2 support is automatically disabled to avoid licensing conflicts.

### 36.2.4 Installing as a Python Package

For easier integration, surgepy can be installed as a proper Python package using `pip` and `scikit-build`:

```bash
# Install from source directory
python3 -m pip install ./src/surge-python

# Or in editable mode for development
python3 -m pip install -e ./src/surge-python
```

The `setup.py` uses scikit-build to invoke CMake automatically:

```python
# From: src/surge-python/setup.py
from skbuild import setup

setup(
    name="surgepy",
    version="0.1.0",
    description="Python bindings for Surge XT synth",
    license="GPLv3",
    python_requires=">=3.7",
    install_requires=["numpy"],
    packages=["surgepy"],
    cmake_source_dir="../..",
    cmake_args=[
        "-DSURGE_BUILD_PYTHON_BINDINGS=TRUE",
        "-DSURGE_SKIP_JUCE_FOR_RACK=TRUE",
        "-DSURGE_SKIP_VST3=TRUE",
        "-DSURGE_SKIP_ALSA=TRUE",
        "-DSURGE_SKIP_STANDALONE=TRUE",
    ],
)
```

This approach:
- Builds only the Python bindings (skips plugins and standalone)
- Installs surgepy into Python's site-packages
- Makes surgepy importable from any directory
- Handles platform-specific binary naming

### 36.2.5 Using the Built Module

**Method 1: Add to Python path** (manual build):

```python
import sys
sys.path.append('/path/to/surge/buildpy/src/surge-python')
import surgepy

print(surgepy.getVersion())  # '1.3.main.850bd53b'
```

**Method 2: Use installed package** (pip install):

```python
import surgepy  # Works from any directory

surge = surgepy.createSurge(44100)
```

**Method 3: Run Python in build directory**:

```bash
cd buildpy/src/surge-python
python3
>>> import surgepy
>>> surgepy.getVersion()
```

---

## 36.3 Python API Reference

### 36.3.1 Module-Level Functions

**surgepy.createSurge(sampleRate: float) → SurgeSynthesizer**

Creates a new Surge XT synthesizer instance at the specified sample rate.

```python
surge = surgepy.createSurge(44100)  # 44.1 kHz
# surge = surgepy.createSurge(48000)  # 48 kHz
```

**Important**: Creating multiple Surge instances with different sample rates in a single process is not supported and may cause undefined behavior.

**surgepy.getVersion() → str**

Returns the Surge XT version string (same as shown in the About screen):

```python
version = surgepy.getVersion()  # '1.3.main.850bd53b'
```

### 36.3.2 SurgeSynthesizer Class

#### Engine Information

```python
surge.getNumInputs()        # → 2 (stereo input for FX)
surge.getNumOutputs()       # → 2 (stereo output)
surge.getBlockSize()        # → 32 (samples per process() call)
surge.getSampleRate()       # → 44100.0
surge.getFactoryDataPath()  # → '/path/to/surge/resources/data'
surge.getUserDataPath()     # → '/path/to/user/Surge XT'
```

#### Audio Processing

**process()**

Processes one block (32 samples) of audio. Updates internal buffers with the result of all active voices, effects, and modulations.

```python
surge.playNote(0, 60, 127, 0)
surge.process()  # Generate 32 samples
output = surge.getOutput()  # Retrieve them
```

**getOutput() → numpy.ndarray**

Returns the most recent audio block as a 2 × 32 numpy float32 array:

```python
output = surge.getOutput()
# output.shape == (2, 32)
# output[0] = left channel
# output[1] = right channel
```

**createMultiBlock(blockCapacity: int) → numpy.ndarray**

Creates a pre-allocated numpy array suitable for multi-block rendering:

```python
# Allocate space for 1000 blocks (32,000 samples = ~0.73 seconds at 44.1kHz)
buffer = surge.createMultiBlock(1000)
# buffer.shape == (2, 32000)
```

**processMultiBlock(buffer: ndarray, startBlock: int = 0, nBlocks: int = -1)**

Renders audio into a pre-allocated buffer. Much more efficient than repeatedly calling `process()` and `getOutput()` in Python loops.

```python
# Render 5 seconds of audio
sample_rate = surge.getSampleRate()
block_size = surge.getBlockSize()
blocks_needed = int(5 * sample_rate / block_size)

buffer = surge.createMultiBlock(blocks_needed)
surge.playNote(0, 60, 127, 0)
surge.processMultiBlock(buffer)  # Render all blocks

# Or render into a subsection:
surge.processMultiBlock(buffer, startBlock=100, nBlocks=200)
```

**processMultiBlockWithInput(input: ndarray, output: ndarray, startBlock: int = 0, nBlocks: int = -1)**

Processes audio with an input signal (for effects processing):

```python
# Load a WAV file into input_audio (numpy array)
input_audio = surge.createMultiBlock(1000)
output_audio = surge.createMultiBlock(1000)

# Load input_audio with external audio...
# Configure Surge FX...

surge.processMultiBlockWithInput(input_audio, output_audio)
```

#### MIDI Control

**playNote(channel: int, midiNote: int, velocity: int, detune: int = 0)**

Triggers a note-on event:

```python
surge.playNote(0, 60, 127, 0)    # Channel 0, middle C, max velocity
surge.playNote(0, 64, 100, 0)    # E4, velocity 100
surge.playNote(1, 67, 80, 0)     # G4 on channel 1
```

- **channel**: MIDI channel (0-15)
- **midiNote**: Note number (0-127, where 60 = middle C)
- **velocity**: Strike velocity (0-127)
- **detune**: Microtonal detune in cents (typically 0)

**releaseNote(channel: int, midiNote: int, releaseVelocity: int = 0)**

Triggers a note-off event:

```python
surge.releaseNote(0, 60, 0)  # Release middle C
```

**allNotesOff()**

Immediately silences all playing notes:

```python
surge.allNotesOff()
```

**pitchBend(channel: int, bend: int)**

Sets pitch bend for a channel (-8192 to +8191, 0 = no bend):

```python
surge.pitchBend(0, 8191)   # Max pitch bend up
surge.pitchBend(0, -8192)  # Max pitch bend down
surge.pitchBend(0, 0)      # Center (no bend)
```

**channelController(channel: int, cc: int, value: int)**

Sends a MIDI CC message:

```python
surge.channelController(0, 1, 127)   # Mod wheel to max
surge.channelController(0, 64, 127)  # Sustain pedal on
surge.channelController(0, 64, 0)    # Sustain pedal off
```

**polyAftertouch(channel: int, key: int, value: int)**

Sends polyphonic aftertouch:

```python
surge.polyAftertouch(0, 60, 100)  # Aftertouch for middle C
```

**channelAftertouch(channel: int, value: int)**

Sends channel aftertouch:

```python
surge.channelAftertouch(0, 80)
```

### 36.3.3 Parameter System

#### Control Groups and Parameters

Surge organizes parameters into **control groups** (OSC, FILTER, LFO, FX, etc.), each containing multiple **entries** (e.g., OSC has 6 entries: 3 oscillators × 2 scenes).

```python
from surgepy import constants as sc

# Get oscillator control group
cg_osc = surge.getControlGroup(sc.cg_OSC)
print(cg_osc.getName())  # 'cg_OSC'

# Get entries (oscillators)
entries = cg_osc.getEntries()
# entries[0] = Osc 1, Scene A
# entries[1] = Osc 1, Scene B
# entries[2] = Osc 2, Scene A
# ...

# Get parameters for Osc 1, Scene A
osc1_params = entries[0].getParams()
# List of SurgeNamedParamId objects
```

**Available control groups** (from `surgepy.constants`):
- `cg_GLOBAL`: Master volume, scene mode, polylimit
- `cg_OSC`: Oscillator parameters
- `cg_MIX`: Oscillator levels, mute, solo, routing
- `cg_FILTER`: Filter cutoff, resonance, type
- `cg_ENV`: ADSR envelope parameters
- `cg_LFO`: LFO rate, shape, modulation
- `cg_FX`: Effect parameters

#### Parameter Queries

```python
# Get a parameter
osc_type = osc1_params[0]  # Oscillator type parameter

# Query parameter properties
surge.getParamMin(osc_type)      # → 0.0 (Classic)
surge.getParamMax(osc_type)      # → 7.0 (Window)
surge.getParamDef(osc_type)      # → 0.0 (default: Classic)
surge.getParamVal(osc_type)      # → current value
surge.getParamValType(osc_type)  # → 'int', 'float', or 'bool'
surge.getParamDisplay(osc_type)  # → 'Classic' (formatted string)

# Comprehensive info
print(surge.getParamInfo(osc_type))
# Parameter name: Osc 1 Type
# Parameter value: 0.0
# Parameter min: 0.0
# Parameter max: 7.0
# Parameter default: 0.0
# Parameter value type: int
# Parameter display value: Classic
```

#### Setting Parameters

```python
# Set oscillator type to Wavetable
surge.setParamVal(osc_type, sc.ot_wavetable)

# Set filter cutoff
cg_filter = surge.getControlGroup(sc.cg_FILTER)
filter_params = cg_filter.getEntries()[0].getParams()
cutoff = filter_params[2]  # Cutoff parameter
surge.setParamVal(cutoff, 5000)  # 5000 Hz
```

### 36.3.4 Patch Management

**loadPatch(path: str) → bool**

Loads a Surge .fxp patch file:

```python
factory_path = surge.getFactoryDataPath()
patch = f"{factory_path}/patches_factory/Keys/DX EP.fxp"
surge.loadPatch(patch)
```

Raises `InvalidArgumentError` if the file doesn't exist.

**savePatch(path: str)**

Saves the current state as a .fxp file:

```python
surge.savePatch("/tmp/my_patch.fxp")
```

**getPatch() → dict**

Returns the entire patch as a nested Python dictionary:

```python
patch = surge.getPatch()

# Access patch structure
scene_a = patch["scene"][0]
osc1 = scene_a["osc"][0]
osc1_type = osc1["type"]  # SurgeNamedParamId

# Access FX
fx_slot_1 = patch["fx"][0]
fx_type = fx_slot_1["type"]
```

The dictionary structure mirrors the C++ `SurgePatch` class, providing programmatic access to all parameters organized hierarchically.

### 36.3.5 Modulation System

**getModSource(modId: int) → SurgeModSource**

Retrieves a modulation source by ID:

```python
from surgepy import constants as sc

lfo1 = surge.getModSource(sc.ms_lfo1)
velocity = surge.getModSource(sc.ms_velocity)
modwheel = surge.getModSource(sc.ms_modwheel)
```

**Available modulation sources** (from `surgepy.constants`):
- **Voice sources**: `ms_velocity`, `ms_releasevelocity`, `ms_keytrack`, `ms_polyaftertouch`
- **MIDI sources**: `ms_modwheel`, `ms_breath`, `ms_expression`, `ms_sustain`, `ms_pitchbend`, `ms_aftertouch`
- **LFOs**: `ms_lfo1` through `ms_lfo6` (voice), `ms_slfo1` through `ms_slfo6` (scene)
- **Envelopes**: `ms_ampeg`, `ms_filtereg`
- **Random**: `ms_random_bipolar`, `ms_random_unipolar`, `ms_alternate_bipolar`, `ms_alternate_unipolar`
- **Key tracking**: `ms_lowest_key`, `ms_highest_key`, `ms_latest_key`
- **Macros**: `ms_ctrl1` through `ms_ctrl8`

**setModDepth01(target: SurgeNamedParamId, source: SurgeModSource, depth: float, scene: int = 0, index: int = 0)**

Establishes or modifies a modulation routing:

```python
# Modulate filter cutoff with LFO 1
cg_filter = surge.getControlGroup(sc.cg_FILTER)
cutoff = cg_filter.getEntries()[0].getParams()[2]
lfo1 = surge.getModSource(sc.ms_lfo1)

surge.setModDepth01(cutoff, lfo1, 0.5)  # 50% modulation depth
```

- **depth**: Normalized modulation amount (0.0 to 1.0)
- **scene**: Scene index (0 or 1) for scene-specific modulators
- **index**: Modulator instance (e.g., for multiple LFO routings)

**getModDepth01(target: SurgeNamedParamId, source: SurgeModSource, scene: int = 0, index: int = 0) → float**

Queries existing modulation depth:

```python
depth = surge.getModDepth01(cutoff, lfo1)  # → 0.5
```

**isValidModulation(target: SurgeNamedParamId, source: SurgeModSource) → bool**

Checks if a modulation routing is possible:

```python
# Voice LFOs can modulate scene parameters
surge.isValidModulation(cutoff, lfo1)  # → True

# Scene LFOs can't modulate themselves
slfo1 = surge.getModSource(sc.ms_slfo1)
lfo1_rate = surge.getControlGroup(sc.cg_LFO).getEntries()[0].getParams()[0]
surge.isValidModulation(lfo1_rate, slfo1)  # → False (different scene)
```

**isActiveModulation(target: SurgeNamedParamId, source: SurgeModSource, scene: int = 0, index: int = 0) → bool**

Checks if a modulation routing is currently established:

```python
surge.isActiveModulation(cutoff, lfo1)  # → True (we set it above)
```

**isBipolarModulation(source: SurgeModSource) → bool**

Checks if a modulation source is bipolar (±) or unipolar (+):

```python
surge.isBipolarModulation(lfo1)       # → True (ranges -1 to +1)
surge.isBipolarModulation(velocity)   # → False (ranges 0 to 1)
```

**getAllModRoutings() → dict**

Returns the entire modulation matrix:

```python
routings = surge.getAllModRoutings()

# Structure:
# {
#   'global': [list of global modulations],
#   'scene': [
#     {
#       'scene': [list of scene modulations for scene 0],
#       'voice': [list of voice modulations for scene 0]
#     },
#     { ... scene 1 ... }
#   ]
# }

for mod in routings['global']:
    print(f"{mod.getSource().getName()} → {mod.getDest().getName()}: {mod.getDepth()}")
```

Each routing is a `SurgeModRouting` object with:
- `getSource()`: Modulation source
- `getDest()`: Destination parameter
- `getDepth()`: Raw depth value
- `getNormalizedDepth()`: Normalized depth (0.0 to 1.0)
- `getSourceScene()`: Source scene index
- `getSourceIndex()`: Source instance index

### 36.3.6 Wavetable Loading

**loadWavetable(scene: int, osc: int, path: str) → bool**

Loads a wavetable file directly into an oscillator:

```python
# Load a wavetable into Scene A, Oscillator 1
factory_path = surge.getFactoryDataPath()
wt_path = f"{factory_path}/wavetables_3rdparty/A.Liv/Droplet/Droplet 2.wav"

surge.loadWavetable(0, 0, wt_path)  # scene=0, osc=0
```

Raises `InvalidArgumentError` if:
- Scene or oscillator index is out of range
- File doesn't exist

Supported formats: `.wav` (standard wavetable), `.wt` (Surge format)

### 36.3.7 Microtuning

**loadSCLFile(path: str)**

Loads a Scala scale file:

```python
surge.loadSCLFile("/path/to/tuning.scl")
```

**loadKBMFile(path: str)**

Loads a Scala keyboard mapping file:

```python
surge.loadKBMFile("/path/to/mapping.kbm")
```

**retuneToStandardTuning()**

Returns to 12-TET with standard Concert C mapping:

```python
surge.retuneToStandardTuning()
```

**retuneToStandardScale()**

Returns to 12-TET scale but keeps keyboard mapping:

```python
surge.retuneToStandardScale()
```

**remapToStandardKeyboard()**

Returns to Concert C keyboard mapping but keeps scale:

```python
surge.remapToStandardKeyboard()
```

**tuningApplicationMode** (property)

Controls how tuning is applied:

```python
# Apply tuning only to MIDI notes
surge.tuningApplicationMode = surgepy.TuningApplicationMode.RETUNE_MIDI_ONLY

# Apply tuning to all pitch sources (oscillators, LFOs, etc.)
surge.tuningApplicationMode = surgepy.TuningApplicationMode.RETUNE_ALL
```

### 36.3.8 MPE Support

**mpeEnabled** (property)

Enables or disables MPE (MIDI Polyphonic Expression):

```python
surge.mpeEnabled = True   # Enable MPE
surge.mpeEnabled = False  # Disable MPE

if surge.mpeEnabled:
    print("MPE is active")
```

When MPE is enabled:
- Channel 0 is the master channel
- Channels 1-15 carry individual note data
- Per-note pitch bend, pressure, and timbre are supported

---

## 36.4 Example Scripts

### 36.4.1 Simple Note Rendering

```python
"""
Render a simple note to a WAV file.
"""
import surgepy
import numpy as np
import scipy.io.wavfile as wav

# Create synthesizer
surge = surgepy.createSurge(44100)

# Calculate buffer size for 3 seconds
sample_rate = surge.getSampleRate()
block_size = surge.getBlockSize()
duration = 3.0
num_blocks = int(duration * sample_rate / block_size)

# Create buffer and render
buffer = surge.createMultiBlock(num_blocks)
surge.playNote(0, 60, 127, 0)  # Middle C
surge.processMultiBlock(buffer, startBlock=0, nBlocks=int(num_blocks * 0.8))
surge.releaseNote(0, 60, 0)
surge.processMultiBlock(buffer, startBlock=int(num_blocks * 0.8), nBlocks=int(num_blocks * 0.2))

# Convert to int16 and save
audio = np.int16(buffer.T * 32767)
wav.write("middle_c.wav", int(sample_rate), audio)
```

### 36.4.2 Batch Patch Rendering

```python
"""
Render all factory patches to individual WAV files.
"""
import surgepy
import numpy as np
import scipy.io.wavfile as wav
import os
from pathlib import Path

surge = surgepy.createSurge(44100)
factory_path = Path(surge.getFactoryDataPath())
patches_dir = factory_path / "patches_factory"
output_dir = Path("rendered_patches")
output_dir.mkdir(exist_ok=True)

def render_patch(surge, duration=2.0):
    """Render a patch playing C major chord."""
    sr = surge.getSampleRate()
    bs = surge.getBlockSize()
    blocks = int(duration * sr / bs)

    buffer = surge.createMultiBlock(blocks)

    # Play C major chord
    surge.playNote(0, 60, 100, 0)  # C
    surge.playNote(0, 64, 100, 0)  # E
    surge.playNote(0, 67, 100, 0)  # G

    # Render 80% with notes held
    surge.processMultiBlock(buffer, 0, int(blocks * 0.8))

    # Release notes
    surge.releaseNote(0, 60, 0)
    surge.releaseNote(0, 64, 0)
    surge.releaseNote(0, 67, 0)

    # Render remaining 20% (release tail)
    surge.processMultiBlock(buffer, int(blocks * 0.8), int(blocks * 0.2))

    return buffer

# Process all .fxp files
for patch_file in patches_dir.rglob("*.fxp"):
    try:
        print(f"Rendering: {patch_file.name}")
        surge.loadPatch(str(patch_file))

        audio = render_patch(surge)
        audio_int16 = np.int16(audio.T * 32767)

        output_name = patch_file.stem + ".wav"
        output_path = output_dir / output_name
        wav.write(str(output_path), 44100, audio_int16)

    except Exception as e:
        print(f"Error with {patch_file.name}: {e}")

print(f"Rendered patches saved to {output_dir}")
```

### 36.4.3 Parameter Sweep

```python
"""
Sweep filter cutoff to demonstrate parameter automation.
"""
import surgepy
from surgepy import constants as sc
import numpy as np
import scipy.io.wavfile as wav

surge = surgepy.createSurge(44100)

# Get filter cutoff parameter
cg_filter = surge.getControlGroup(sc.cg_FILTER)
filter_params = cg_filter.getEntries()[0].getParams()
cutoff = filter_params[2]  # Cutoff parameter

# Get range
min_cutoff = surge.getParamMin(cutoff)
max_cutoff = surge.getParamMax(cutoff)

# Set up rendering
duration = 10.0
sr = surge.getSampleRate()
bs = surge.getBlockSize()
total_blocks = int(duration * sr / bs)

buffer = surge.createMultiBlock(total_blocks)

# Play a note
surge.playNote(0, 36, 127, 0)  # Low C for better filter effect

# Sweep cutoff while rendering
for block_idx in range(total_blocks):
    # Linear sweep from min to max
    progress = block_idx / total_blocks
    cutoff_val = min_cutoff + progress * (max_cutoff - min_cutoff)
    surge.setParamVal(cutoff, cutoff_val)

    # Render one block
    surge.processMultiBlock(buffer, block_idx, 1)

# Save result
audio = np.int16(buffer.T * 32767)
wav.write("filter_sweep.wav", int(sr), audio)
print(f"Filter sweep from {min_cutoff} to {max_cutoff} Hz saved")
```

### 36.4.4 Modulation Matrix Analysis

```python
"""
Analyze all modulation routings in factory patches.
"""
import surgepy
from pathlib import Path
import json

surge = surgepy.createSurge(44100)
factory_path = Path(surge.getFactoryDataPath())
patches_dir = factory_path / "patches_factory"

modulation_stats = {
    "total_patches": 0,
    "patches_with_modulation": 0,
    "most_common_sources": {},
    "most_common_targets": {},
}

for patch_file in patches_dir.rglob("*.fxp"):
    modulation_stats["total_patches"] += 1

    try:
        surge.loadPatch(str(patch_file))
        routings = surge.getAllModRoutings()

        has_mod = False

        # Analyze global modulations
        for mod in routings["global"]:
            has_mod = True
            source_name = mod.getSource().getName()
            dest_name = mod.getDest().getName()

            modulation_stats["most_common_sources"][source_name] = \
                modulation_stats["most_common_sources"].get(source_name, 0) + 1
            modulation_stats["most_common_targets"][dest_name] = \
                modulation_stats["most_common_targets"].get(dest_name, 0) + 1

        # Analyze scene modulations
        for scene_data in routings["scene"]:
            for mod in scene_data["scene"]:
                has_mod = True
                source_name = mod.getSource().getName()
                dest_name = mod.getDest().getName()
                modulation_stats["most_common_sources"][source_name] = \
                    modulation_stats["most_common_sources"].get(source_name, 0) + 1
                modulation_stats["most_common_targets"][dest_name] = \
                    modulation_stats["most_common_targets"].get(dest_name, 0) + 1

            for mod in scene_data["voice"]:
                has_mod = True
                source_name = mod.getSource().getName()
                dest_name = mod.getDest().getName()
                modulation_stats["most_common_sources"][source_name] = \
                    modulation_stats["most_common_sources"].get(source_name, 0) + 1
                modulation_stats["most_common_targets"][dest_name] = \
                    modulation_stats["most_common_targets"].get(dest_name, 0) + 1

        if has_mod:
            modulation_stats["patches_with_modulation"] += 1

    except Exception as e:
        print(f"Error analyzing {patch_file.name}: {e}")

# Sort by frequency
modulation_stats["most_common_sources"] = dict(
    sorted(modulation_stats["most_common_sources"].items(),
           key=lambda x: x[1], reverse=True)[:10]
)
modulation_stats["most_common_targets"] = dict(
    sorted(modulation_stats["most_common_targets"].items(),
           key=lambda x: x[1], reverse=True)[:10]
)

print(json.dumps(modulation_stats, indent=2))
```

### 36.4.5 Wavetable Generator

```python
"""
Generate a custom wavetable and load it into Surge.
"""
import surgepy
from surgepy import constants as sc
import numpy as np
import scipy.io.wavfile as wav

def generate_wavetable(num_frames=256, frame_size=2048):
    """
    Generate a morphing wavetable from sine to square.
    """
    wavetable = np.zeros((num_frames, frame_size), dtype=np.float32)

    for frame_idx in range(num_frames):
        # Morph from sine to square wave
        morph = frame_idx / num_frames

        # Generate waveform
        for i in range(frame_size):
            phase = 2 * np.pi * i / frame_size

            # Sine component
            sine = np.sin(phase)

            # Square component (using harmonics)
            square = 0
            for harmonic in range(1, 10, 2):
                square += np.sin(harmonic * phase) / harmonic
            square *= 4 / np.pi

            # Morph between them
            wavetable[frame_idx, i] = sine * (1 - morph) + square * morph

    return wavetable

# Generate and save wavetable
wt = generate_wavetable()
wt_flat = wt.flatten()
wt_int16 = np.int16(wt_flat * 32767)

wt_path = "/tmp/sine_to_square.wav"
wav.write(wt_path, 48000, wt_int16)  # Surge detects wavetables by structure

# Load into Surge
surge = surgepy.createSurge(44100)

# Set oscillator to wavetable mode
patch = surge.getPatch()
osc1 = patch["scene"][0]["osc"][0]
osc_type = osc1["type"]
surge.setParamVal(osc_type, sc.ot_wavetable)

# Load our custom wavetable
surge.loadWavetable(0, 0, wt_path)

# Render a note
duration = 3.0
num_blocks = int(duration * 44100 / 32)
buffer = surge.createMultiBlock(num_blocks)

surge.playNote(0, 60, 127, 0)
surge.processMultiBlock(buffer)

audio = np.int16(buffer.T * 32767)
wav.write("custom_wavetable_test.wav", 44100, audio)
print("Custom wavetable rendered to custom_wavetable_test.wav")
```

### 36.4.6 ML Dataset Generation

```python
"""
Generate a labeled dataset for machine learning.
Creates audio samples with different parameter settings.
"""
import surgepy
from surgepy import constants as sc
import numpy as np
import scipy.io.wavfile as wav
import json
from pathlib import Path

surge = surgepy.createSurge(44100)

# Output directory
dataset_dir = Path("ml_dataset")
dataset_dir.mkdir(exist_ok=True)
audio_dir = dataset_dir / "audio"
audio_dir.mkdir(exist_ok=True)

metadata = []

# Get control groups
cg_osc = surge.getControlGroup(sc.cg_OSC)
cg_filter = surge.getControlGroup(sc.cg_FILTER)
osc_params = cg_osc.getEntries()[0].getParams()
filter_params = cg_filter.getEntries()[0].getParams()

osc_type_param = osc_params[0]
filter_cutoff_param = filter_params[2]
filter_resonance_param = filter_params[3]

# Parameter ranges to explore
oscillator_types = [sc.ot_classic, sc.ot_sine, sc.ot_wavetable]
cutoff_values = np.linspace(100, 10000, 5)
resonance_values = np.linspace(0, 0.9, 3)

sample_idx = 0

for osc_type in oscillator_types:
    for cutoff in cutoff_values:
        for resonance in resonance_values:
            # Configure patch
            surge.setParamVal(osc_type_param, osc_type)
            surge.setParamVal(filter_cutoff_param, cutoff)
            surge.setParamVal(filter_resonance_param, resonance)

            # Render audio
            num_blocks = int(2.0 * 44100 / 32)
            buffer = surge.createMultiBlock(num_blocks)

            surge.playNote(0, 60, 100, 0)
            surge.processMultiBlock(buffer, 0, int(num_blocks * 0.8))
            surge.releaseNote(0, 60, 0)
            surge.processMultiBlock(buffer, int(num_blocks * 0.8), int(num_blocks * 0.2))

            # Save audio
            audio_file = f"sample_{sample_idx:04d}.wav"
            audio_path = audio_dir / audio_file
            audio = np.int16(buffer.T * 32767)
            wav.write(str(audio_path), 44100, audio)

            # Save metadata
            metadata.append({
                "file": audio_file,
                "oscillator_type": int(osc_type),
                "filter_cutoff": float(cutoff),
                "filter_resonance": float(resonance),
                "note": 60,
                "velocity": 100
            })

            sample_idx += 1

            # Reset for next iteration
            surge.allNotesOff()

# Save metadata JSON
with open(dataset_dir / "metadata.json", "w") as f:
    json.dump(metadata, f, indent=2)

print(f"Generated {sample_idx} samples in {dataset_dir}")
print(f"Metadata saved to {dataset_dir / 'metadata.json'}")
```

---

## 36.5 Use Cases and Applications

### 36.5.1 Automated Testing

Surgepy enables comprehensive automated testing of synthesis behavior, parameter validation, and regression testing:

```python
"""
Test that all parameters are within valid ranges.
"""
import surgepy
from surgepy import constants as sc

def test_parameter_ranges():
    surge = surgepy.createSurge(44100)

    control_groups = [
        sc.cg_GLOBAL, sc.cg_OSC, sc.cg_MIX,
        sc.cg_FILTER, sc.cg_ENV, sc.cg_LFO
    ]

    for cg_id in control_groups:
        cg = surge.getControlGroup(cg_id)
        for entry in cg.getEntries():
            for param in entry.getParams():
                min_val = surge.getParamMin(param)
                max_val = surge.getParamMax(param)
                def_val = surge.getParamDef(param)
                cur_val = surge.getParamVal(param)

                # Validate ranges
                assert min_val <= max_val, f"Invalid range for {param.getName()}"
                assert min_val <= def_val <= max_val, \
                    f"Default out of range for {param.getName()}"
                assert min_val <= cur_val <= max_val, \
                    f"Current value out of range for {param.getName()}"

    print("All parameter ranges valid!")

test_parameter_ranges()
```

### 36.5.2 Sound Design Exploration

Systematically explore parameter spaces to discover interesting sounds:

```python
"""
Random patch generator using genetic algorithm concepts.
"""
import surgepy
from surgepy import constants as sc
import numpy as np
import random

def randomize_parameters(surge, mutation_rate=0.3):
    """Randomize parameters with specified mutation rate."""
    control_groups = [sc.cg_OSC, sc.cg_FILTER, sc.cg_ENV, sc.cg_LFO]

    for cg_id in control_groups:
        cg = surge.getControlGroup(cg_id)
        for entry in cg.getEntries():
            for param in entry.getParams():
                if random.random() < mutation_rate:
                    min_val = surge.getParamMin(param)
                    max_val = surge.getParamMax(param)
                    val_type = surge.getParamValType(param)

                    if val_type == "int":
                        new_val = random.randint(int(min_val), int(max_val))
                    else:
                        new_val = random.uniform(min_val, max_val)

                    surge.setParamVal(param, new_val)

surge = surgepy.createSurge(44100)

# Generate 10 random patches
for i in range(10):
    randomize_parameters(surge, mutation_rate=0.3)
    surge.savePatch(f"/tmp/random_patch_{i:02d}.fxp")
    print(f"Generated random_patch_{i:02d}.fxp")
```

### 36.5.3 Preset Generation

Create preset variations programmatically:

```python
"""
Generate a family of related presets by varying specific parameters.
"""
import surgepy
from surgepy import constants as sc

def create_preset_family(base_patch, output_dir, param_variations):
    """
    Create variations of a base patch.

    Args:
        base_patch: Path to base .fxp file
        output_dir: Where to save variations
        param_variations: Dict of {param_name: [values]}
    """
    surge = surgepy.createSurge(44100)
    surge.loadPatch(base_patch)

    # Get parameter references
    # (This example assumes you know which parameters to vary)
    cg_filter = surge.getControlGroup(sc.cg_FILTER)
    filter_params = cg_filter.getEntries()[0].getParams()
    cutoff = filter_params[2]

    # Generate variations
    for idx, cutoff_val in enumerate([1000, 3000, 6000, 10000]):
        surge.loadPatch(base_patch)  # Reset to base
        surge.setParamVal(cutoff, cutoff_val)
        output_path = f"{output_dir}/variation_{idx:02d}_cutoff_{int(cutoff_val)}.fxp"
        surge.savePatch(output_path)
        print(f"Created {output_path}")

# Usage
create_preset_family(
    "base.fxp",
    "/tmp/preset_family",
    {"filter_cutoff": [1000, 3000, 6000, 10000]}
)
```

### 36.5.4 Audio Analysis

Analyze synthesis output for research or quality assurance:

```python
"""
Analyze spectral content of patches.
"""
import surgepy
import numpy as np
import matplotlib.pyplot as plt
from scipy import signal

def analyze_spectrum(surge, duration=2.0):
    """Render audio and compute spectrum."""
    sr = surge.getSampleRate()
    num_blocks = int(duration * sr / 32)
    buffer = surge.createMultiBlock(num_blocks)

    surge.playNote(0, 60, 100, 0)
    surge.processMultiBlock(buffer)

    # Compute FFT
    audio = buffer[0]  # Left channel
    freqs, psd = signal.welch(audio, sr, nperseg=2048)

    return freqs, psd

surge = surgepy.createSurge(44100)

# Analyze Init Saw patch
freqs, psd_saw = analyze_spectrum(surge)

# Load different patch
surge.loadPatch(f"{surge.getFactoryDataPath()}/patches_factory/Bass/Acid Bleep.fxp")
freqs, psd_acid = analyze_spectrum(surge)

# Plot comparison
plt.figure(figsize=(12, 6))
plt.semilogy(freqs, psd_saw, label="Init Saw")
plt.semilogy(freqs, psd_acid, label="Acid Bleep")
plt.xlabel("Frequency (Hz)")
plt.ylabel("Power Spectral Density")
plt.legend()
plt.grid(True)
plt.savefig("spectrum_comparison.png")
print("Spectrum analysis saved to spectrum_comparison.png")
```

### 36.5.5 Batch Processing

Process large numbers of patches for quality control or catalog generation:

```python
"""
Validate that all factory patches load and render without errors.
"""
import surgepy
from pathlib import Path

def validate_patches(patches_dir):
    """Test that all patches load and render."""
    surge = surgepy.createSurge(44100)
    results = {"success": 0, "failed": []}

    for patch_file in Path(patches_dir).rglob("*.fxp"):
        try:
            surge.loadPatch(str(patch_file))

            # Try to render a note
            buffer = surge.createMultiBlock(100)
            surge.playNote(0, 60, 100, 0)
            surge.processMultiBlock(buffer)

            # Check for NaN or Inf
            if np.isnan(buffer).any() or np.isinf(buffer).any():
                raise ValueError("Audio contains NaN or Inf")

            results["success"] += 1
            surge.allNotesOff()

        except Exception as e:
            results["failed"].append({
                "patch": patch_file.name,
                "error": str(e)
            })

    return results

# Run validation
surge = surgepy.createSurge(44100)
factory_path = surge.getFactoryDataPath()
results = validate_patches(f"{factory_path}/patches_factory")

print(f"Successful: {results['success']}")
print(f"Failed: {len(results['failed'])}")
for failure in results["failed"]:
    print(f"  - {failure['patch']}: {failure['error']}")
```

---

## 36.6 Advanced Topics

### 36.6.1 Type Stubs and IDE Support

Surgepy includes Python type stubs (.pyi files) for IDE autocomplete and type checking:

```python
# Located in: src/surge-python/surgepy/__init__.pyi
# Provides type hints for all classes and methods

from typing import List
import surgepy

# IDEs can now provide autocomplete and type checking
surge: surgepy.SurgeSynthesizer = surgepy.createSurge(44100)
version: str = surgepy.getVersion()
```

Generate updated stubs after modifying bindings:

```bash
pip install pybind11-stubgen
pybind11-stubgen surgepy
# Copy output from stubs/ to src/surge-python/surgepy/
```

### 36.6.2 Constants Reference

All Surge enums are exposed in `surgepy.constants`:

**Oscillator Types:**
- `ot_classic`, `ot_sine`, `ot_wavetable`, `ot_shnoise`
- `ot_audioinput`, `ot_FM3`, `ot_FM2`, `ot_window`

**Filter Types:**
- `fut_lp12`, `fut_lp24`, `fut_hp12`, `fut_hp24`
- `fut_bp12`, `fut_notch12`, `fut_lpmoog`
- `fut_vintageladder`, `fut_k35_lp`, `fut_diode`
- And 20+ more filter types

**Effect Types:**
- `fxt_off`, `fxt_delay`, `fxt_reverb`, `fxt_phaser`
- `fxt_chorus4`, `fxt_distortion`, `fxt_eq`, `fxt_vocoder`
- `fxt_airwindows`, `fxt_neuron`

**LFO Shapes:**
- `lt_sine`, `lt_tri`, `lt_square`, `lt_ramp`
- `lt_noise`, `lt_snh`, `lt_envelope`, `lt_mseg`, `lt_formula`

**Play Modes:**
- `pm_poly`, `pm_mono`, `pm_mono_st`, `pm_mono_fp`, `pm_latch`

**Scene Modes:**
- `sm_single`, `sm_split`, `sm_dual`, `sm_chsplit`

See `/home/user/surge/src/surge-python/surgepy/_surgepy/constants.pyi` for the complete list.

### 36.6.3 Performance Considerations

**Block-based rendering** is significantly faster than individual process() calls:

```python
# SLOW: Python loop overhead
for i in range(10000):
    surge.process()
    output = surge.getOutput()

# FAST: Single C++ loop
buffer = surge.createMultiBlock(10000)
surge.processMultiBlock(buffer)
```

**Pre-allocate buffers** when rendering multiple times:

```python
# Reuse the same buffer for multiple renders
buffer = surge.createMultiBlock(5000)

for patch in patches:
    surge.loadPatch(patch)
    surge.playNote(0, 60, 100, 0)
    surge.processMultiBlock(buffer)
    # Process buffer...
```

**Avoid excessive parameter queries** in tight loops:

```python
# SLOW: Query parameter object every iteration
for i in range(1000):
    param = surge.getControlGroup(sc.cg_FILTER).getEntries()[0].getParams()[2]
    surge.setParamVal(param, i)

# FAST: Query once, reuse reference
cutoff = surge.getControlGroup(sc.cg_FILTER).getEntries()[0].getParams()[2]
for i in range(1000):
    surge.setParamVal(cutoff, i)
```

### 36.6.4 Error Handling

Surgepy raises Python exceptions for error conditions:

```python
import surgepy

surge = surgepy.createSurge(44100)

try:
    # Invalid file path
    surge.loadPatch("/nonexistent/patch.fxp")
except Exception as e:
    print(f"Load failed: {e}")  # "File not found: /nonexistent/patch.fxp"

try:
    # Out of range scene/oscillator
    surge.loadWavetable(5, 10, "wavetable.wav")
except Exception as e:
    print(f"Invalid indices: {e}")  # "OSC and SCENE out of range"

try:
    # Invalid SCL file
    surge.loadSCLFile("invalid.scl")
except Exception as e:
    print(f"Tuning error: {e}")
```

### 36.6.5 Threading Considerations

**Surge instances are not thread-safe.** Each thread should have its own SurgeSynthesizer instance:

```python
from concurrent.futures import ThreadPoolExecutor
import surgepy

def render_patch(patch_path):
    # Create surge instance per thread
    surge = surgepy.createSurge(44100)
    surge.loadPatch(patch_path)

    buffer = surge.createMultiBlock(1000)
    surge.playNote(0, 60, 100, 0)
    surge.processMultiBlock(buffer)

    return buffer

# Parallel rendering
with ThreadPoolExecutor(max_workers=4) as executor:
    results = executor.map(render_patch, patch_list)
```

---

## 36.7 Comparison with Plugin Usage

| Feature | Plugin (VST3/AU/CLAP) | surgepy |
|---------|----------------------|---------|
| Audio rendering | Real-time | Offline |
| Parameter control | GUI + automation | Programmatic API |
| Patch loading | File browser | `loadPatch()` |
| MIDI input | Hardware/DAW | `playNote()` calls |
| Batch processing | Manual or DAW-specific | Python loops |
| Analysis | External tools | NumPy/SciPy |
| Automation | Limited to host | Full Python access |
| Use case | Music production | Research, testing, ML |

---

## 36.8 Further Resources

**Source Code:**
- Bindings implementation: `/home/user/surge/src/surge-python/surgepy.cpp`
- Build configuration: `/home/user/surge/src/surge-python/CMakeLists.txt`
- Test suite: `/home/user/surge/src/surge-python/tests/test_surgepy.py`

**Documentation:**
- Jupyter notebook: `/home/user/surge/scripts/ipy/Demonstrate Surge in Python.ipynb`
- Main README: `/home/user/surge/README.md` (Python section)
- Type stubs: `/home/user/surge/src/surge-python/surgepy/__init__.pyi`

**Example Scripts:**
- `/home/user/surge/src/surge-python/tests/write_wavetable.py`
- Additional examples in the Jupyter notebook

**Community:**
- Surge Synth Team Discord: https://discord.gg/surge-synth-team
- GitHub Issues: https://github.com/surge-synthesizer/surge/issues
- GitHub Discussions: https://github.com/surge-synthesizer/surge/discussions

---

## Summary

The surgepy Python bindings provide powerful programmatic access to the Surge XT synthesis engine. By exposing the core synthesizer, parameter system, modulation matrix, and audio rendering capabilities, surgepy enables use cases far beyond traditional music production: automated testing, batch processing, parameter exploration, machine learning dataset generation, and scientific research.

The binding layer uses pybind11 to wrap the C++ `SurgeSynthesizer` class with Python-friendly methods, integrating seamlessly with NumPy for efficient audio buffer handling. With comprehensive parameter access, patch management, and modulation control, surgepy provides everything needed to script complex synthesis workflows in Python.

Whether you're generating thousands of audio samples for machine learning, exploring synthesis algorithms, or building automated testing infrastructure, surgepy brings the power and flexibility of Surge XT to Python's rich ecosystem of scientific and audio processing libraries.
