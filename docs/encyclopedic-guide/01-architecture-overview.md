# Chapter 1: Introduction to Surge XT Architecture

## The Philosophy of Surge

Surge XT represents a unique fusion of commercial-grade audio software architecture and open-source community development. Originally designed by Claes Johanson as a commercial synthesizer from 2004-2018, its architecture reflects professional audio software development practices: clean separation of concerns, performance-critical SIMD optimization, and extensible design patterns.

When Surge was open-sourced in 2018, it evolved dramatically. The Surge Synth Team has expanded it from roughly 7 oscillator types to 13, added dozens of effects, introduced MSEG and formula modulation, and modernized the codebase to C++20 while maintaining backward compatibility with thousands of user patches.

This chapter explores the fundamental architectural decisions that make Surge both performant and maintainable.

## Core Architectural Principles

### 1. Separation of DSP and UI

Surge maintains strict separation between its synthesis engine and user interface:

**DSP Engine** (`src/common/`):
- Platform-independent
- Real-time safe (no allocations in audio thread)
- SIMD-optimized processing
- Deterministic behavior for testing

**User Interface** (`src/surge-xt/gui/`):
- JUCE-based cross-platform GUI
- Asynchronous communication with engine
- Non-real-time thread
- Skinnable and customizable

This separation enables:
- Headless testing without GUI dependencies
- Python bindings to the synthesis engine
- Multiple front-ends (plugin GUI, CLI, programmatic control)
- Independent optimization of DSP and UI

### 2. Scene-Based Architecture

Surge uses a **dual-scene architecture**, a distinctive design decision that significantly impacts the entire codebase.

```cpp
// From: src/common/SurgeStorage.h
const int n_scenes = 2;

enum scene_mode
{
    sm_single = 0,     // Only Scene A is active
    sm_split,          // Keyboard split between A and B
    sm_dual,           // Both scenes layer
    sm_chsplit,        // MIDI channel split

    n_scene_modes,
};
```

Each scene is a complete synthesizer:
- 3 oscillators
- 2 filter units
- 2 envelope generators (Filter EG, Amp EG)
- 6 voice LFOs
- 6 scene LFOs
- Independent mixer with ring modulation
- Separate output routing

**Why Dual Scenes?**

1. **Sound Design Flexibility**: Layer two completely different sounds
2. **Live Performance**: Split keyboard for bass/lead
3. **Timbral Complexity**: Create sounds impossible with a single signal path
4. **Educational Value**: Learn synthesis by comparing scene settings

### 3. Block-Based Processing

Surge processes audio in fixed-size blocks, a fundamental architectural choice that pervades the entire codebase.

```cpp
// From: src/common/globals.h
#if !defined(SURGE_COMPILE_BLOCK_SIZE)
#error You must compile with -DSURGE_COMPILE_BLOCK_SIZE=32 (or whatnot)
#endif

const int BLOCK_SIZE = SURGE_COMPILE_BLOCK_SIZE;  // Default: 32 samples
const int OSC_OVERSAMPLING = 2;                   // 2x oversampling
const int BLOCK_SIZE_OS = OSC_OVERSAMPLING * BLOCK_SIZE;  // 64 samples
const int BLOCK_SIZE_QUAD = BLOCK_SIZE >> 2;      // 8 quads (for SSE)
const int BLOCK_SIZE_OS_QUAD = BLOCK_SIZE_OS >> 2; // 16 quads
```

**Why 32 Samples?**

The block size represents a careful balance:

**Smaller blocks (e.g., 16)**:
- ✅ Lower latency
- ✅ More precise automation
- ❌ Higher CPU overhead (more function calls)
- ❌ Less efficient SIMD utilization

**Larger blocks (e.g., 64, 128)**:
- ✅ Better CPU efficiency
- ✅ Better cache utilization
- ❌ Higher latency
- ❌ Coarser automation resolution

**32 samples is the sweet spot:**
- At 44.1kHz: ~0.7ms latency per block
- At 48kHz: ~0.67ms latency per block
- Efficient SIMD processing (8 quad-floats)
- Good automation resolution (48 times per second at 48kHz)

### 4. SIMD Optimization Throughout

Surge makes extensive use of **SSE2 SIMD** (Single Instruction, Multiple Data) to process 4 samples simultaneously.

```cpp
// From: src/common/globals.h
#include "sst/basic-blocks/simd/setup.h"

// SSE2 processes 4 floats at once (128-bit registers)
// This is why many structures are "quad" variants
const int BLOCK_SIZE_QUAD = BLOCK_SIZE >> 2;  // 32 / 4 = 8 iterations

// Voice processing: Process 4 voices simultaneously
// Filter processing: Process filter coefficients for 4 voices at once
```

**SIMD Permeates the Architecture:**

1. **Voice Processing**: `QuadFilterChain` processes 4 voices in parallel
2. **Oscillators**: Generate 4 samples per iteration
3. **Filters**: Calculate coefficients for 4 voices simultaneously
4. **Effects**: Use SIMD where applicable

**Memory Alignment Requirements:**

```cpp
// All DSP buffers must be 16-byte aligned for SSE2
float __attribute__((aligned(16))) buffer[BLOCK_SIZE];

// Or using the provided macro:
alignas(16) float output[BLOCK_SIZE_OS];
```

Misaligned memory access can cause:
- Performance degradation (50% or more)
- Crashes on some platforms
- Undefined behavior

### 5. Voice Allocation and Polyphony

Surge supports up to 64 simultaneous voices with sophisticated voice management.

```cpp
// From: src/common/globals.h
const int MAX_VOICES = 64;
const int MAX_UNISON = 16;  // Up to 16 unison voices per note
const int DEFAULT_POLYLIMIT = 16;  // Default polyphony limit
```

**Voice Lifecycle:**

```
MIDI Note On → Voice Allocation → Attack Phase → Sustain →
MIDI Note Off → Release Phase → Voice Deactivation
```

**Voice Stealing:**

When polyphony limit is reached and a new note arrives:
1. Find the quietest voice
2. If no quiet voice, steal oldest voice
3. Fast release the stolen voice
4. Activate new voice

**MPE Support:**

Surge implements full MPE (MIDI Polyphonic Expression):
- Per-note pitch bend
- Per-note pressure
- Per-note timbre (CC74)
- Per-voice modulation routing

## System Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                         SURGE XT ARCHITECTURE                        │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│                        USER INTERFACE (JUCE)                         │
│  ┌──────────────┐  ┌──────────────┐  ┌────────────────────────┐    │
│  │ Main Editor  │  │   Overlays   │  │  Menus & Dialogs       │    │
│  │ - Parameters │  │ - MSEG Edit  │  │  - Patch Browser       │    │
│  │ - Modulation │  │ - Lua Edit   │  │  - Tuning              │    │
│  │ - Meters     │  │ - Oscope     │  │  - Settings            │    │
│  └──────┬───────┘  └──────┬───────┘  └────────┬───────────────┘    │
└─────────┼──────────────────┼───────────────────┼────────────────────┘
          │                  │                   │
          └─────────┬────────┴──────────┬────────┘
                    ▼                   ▼
    ┌───────────────────────────────────────────────────────┐
    │         Parameter Change / Patch Load Events          │
    └───────────────────────────────────────────────────────┘
                               │
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│                      SYNTHESIS ENGINE LAYER                          │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │                   SurgeSynthesizer                          │   │
│  │  - Main audio processing loop                              │   │
│  │  - Voice allocation                                         │   │
│  │  - MIDI event handling                                      │   │
│  │  - Effect chain processing                                  │   │
│  └────────────────────┬─────────────────┬──────────────────────┘   │
│                       │                 │                           │
│       ┌───────────────┴─────┐    ┌─────┴────────────┐             │
│       │   Scene A           │    │   Scene B        │             │
│       │  ┌───────────────┐  │    │  ┌─────────────┐ │             │
│       │  │ Voice Pool    │  │    │  │ Voice Pool  │ │             │
│       │  │ (32 voices)   │  │    │  │ (32 voices) │ │             │
│       │  └───────┬───────┘  │    │  └──────┬──────┘ │             │
│       │          │          │    │         │        │             │
│       │  ┌───────▼───────┐  │    │  ┌──────▼──────┐ │             │
│       │  │ SurgeVoice    │  │    │  │ SurgeVoice  │ │             │
│       │  │ - 3 Oscs      │  │    │  │ - 3 Oscs    │ │             │
│       │  │ - Filters     │  │    │  │ - Filters   │ │             │
│       │  │ - Modulators  │  │    │  │ - Modulators│ │             │
│       │  └───────────────┘  │    │  └─────────────┘ │             │
│       └─────────────────────┘    └──────────────────┘             │
│                       │                 │                           │
│                       └────────┬────────┘                           │
│                                ▼                                    │
│                    ┌───────────────────────┐                        │
│                    │   Effect Chains       │                        │
│                    │  - Chain A (4 FX)     │                        │
│                    │  - Chain B (4 FX)     │                        │
│                    │  - Send 1 (4 FX)      │                        │
│                    │  - Send 2 (4 FX)      │                        │
│                    └───────────────────────┘                        │
└─────────────────────────────────────────────────────────────────────┘
                               │
                               ▼
                    ┌──────────────────────┐
                    │   Audio Output       │
                    │   MIDI Out (OSC)     │
                    └──────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│                         DATA LAYER                                   │
│  ┌──────────────┐  ┌────────────────┐  ┌──────────────────────┐    │
│  │ SurgeStorage │  │  SurgePatch    │  │   Resources          │    │
│  │ - Parameters │  │  - XML I/O     │  │   - Wavetables       │    │
│  │ - Wavetables │  │  - Versioning  │  │   - Factory Patches  │    │
│  │ - Tuning     │  │  - Migration   │  │   - Skins            │    │
│  └──────────────┘  └────────────────┘  └──────────────────────┘    │
└─────────────────────────────────────────────────────────────────────┘
```

## Critical Data Structures

### The Trinity: Storage, Synthesizer, Patch

Surge's architecture revolves around three fundamental classes:

#### 1. SurgeStorage: The Data Repository

```cpp
// From: src/common/SurgeStorage.h
class SurgeStorage
{
public:
    // Central parameter array - the heart of the synth
    Parameter param_ptr[n_total_params];

    // Wavetable storage
    std::vector<Wavetable> wt;

    // Patch database for browsing
    std::unique_ptr<PatchDB> patchDB;

    // Tuning system
    Tunings::Tuning currentTuning;

    // Resource paths
    fs::path datapath;      // Factory data
    fs::path userDataPath;  // User patches/wavetables

    // Sample rate (entire engine runs at this rate)
    float samplerate{44100.0};
    float samplerate_inv{1.0 / 44100.0};
};
```

**SurgeStorage** is the "bag of stuff" - it holds:
- All 553 parameters (n_total_params)
- Wavetables loaded into memory
- Tuning information
- File system paths
- Global configuration

**Key Insight:** SurgeStorage is **NOT** real-time safe. It performs file I/O, allocations, and other operations unsuitable for the audio thread. The synthesizer reads from it but doesn't modify it during processing.

#### 2. SurgeSynthesizer: The Engine

```cpp
// From: src/common/SurgeSynthesizer.h
class SurgeSynthesizer
{
public:
    // Main audio processing - called by plugin host
    void process();

    // Process a single block (32 samples default)
    void processControl();  // Update modulation, envelopes
    void processAudio();    // Generate audio

    // Voice management
    std::array<SurgeVoice, MAX_VOICES> voices;
    int64_t voiceCounter{0};  // For voice stealing priority

    // Scene state
    std::array<int, n_scenes> polyphonyLimit{DEFAULT_POLYLIMIT, DEFAULT_POLYLIMIT};

    // MIDI event queue
    std::vector<MIDIEvent> midiEvents;

    // Reference to storage
    SurgeStorage *storage{nullptr};
};
```

**SurgeSynthesizer** is the main engine:
- Processes audio blocks
- Allocates and manages voices
- Handles MIDI events
- Runs the modulation matrix
- Processes effect chains

**Real-Time Safety:** SurgeSynthesizer's `process()` method is real-time safe. No allocations, no file I/O, no locks (except very carefully placed lock-free structures).

#### 3. SurgePatch: The State Container

```cpp
// From: src/common/SurgePatch.h
class SurgePatch
{
public:
    // Patch metadata
    char name[NAMECHARS];
    char author[NAMECHARS];
    char category[NAMECHARS];

    // Parameter storage (copies of Parameter objects)
    // This is the "saved state" of the synth

    // Patch I/O
    void loadPatch(const fs::path &filename);
    void savePatch(const fs::path &filename);

    // XML parsing and generation
    TiXmlElement *streamToXML();
    void streamFromXML(TiXmlElement *root);
};
```

**SurgePatch** represents serializable state:
- Current values of all parameters
- Modulation routing
- Wavetable references
- Custom names, colors, etc.

**File Format:** XML-based with extensive versioning (currently revision 28). See lines 88-146 of SurgeStorage.h for the complete revision history.

## Memory Layout and Performance

### Constants and Configuration

```cpp
// From: src/common/globals.h

// Window size (before scaling)
const int BASE_WINDOW_SIZE_X = 913;
const int BASE_WINDOW_SIZE_Y = 569;

// Audio processing blocks
const int BLOCK_SIZE = SURGE_COMPILE_BLOCK_SIZE;     // 32 samples
const int OSC_OVERSAMPLING = 2;                      // 2x for oscillators
const int BLOCK_SIZE_OS = OSC_OVERSAMPLING * BLOCK_SIZE;  // 64 samples

// SIMD processing (4 samples per SSE2 register)
const int BLOCK_SIZE_QUAD = BLOCK_SIZE >> 2;         // 8 quads
const int BLOCK_SIZE_OS_QUAD = BLOCK_SIZE_OS >> 2;   // 16 quads

// Inverse values (multiply instead of divide)
const float BLOCK_SIZE_INV = (1.f / BLOCK_SIZE);
const float BLOCK_SIZE_OS_INV = (1.f / BLOCK_SIZE_OS);

// Maximum values
const int MAX_FB_COMB = 2048;                        // Comb filter delay
const int MAX_FB_COMB_EXTENDED = 2048 * 64;          // Combulator extended
const int MAX_VOICES = 64;                           // Total polyphony
const int MAX_UNISON = 16;                           // Unison voices per note

// I/O configuration
const int N_OUTPUTS = 2;                             // Stereo out
const int N_INPUTS = 2;                              // Stereo in

// Defaults
const int DEFAULT_POLYLIMIT = 16;

// OSC (Open Sound Control) network ports
const int DEFAULT_OSC_PORT_IN = 53280;
const int DEFAULT_OSC_PORT_OUT = 53281;
```

**Performance Implications:**

1. **Compile-time BLOCK_SIZE**: Allows aggressive compiler optimization
2. **Inverse constants**: Multiplying by `BLOCK_SIZE_INV` is faster than dividing by `BLOCK_SIZE`
3. **QUAD constants**: Pre-computed for SIMD loop iteration counts

### Parameter System

```cpp
// From: src/common/SurgeStorage.h

const int n_oscs = 3;                    // Oscillators per scene
const int n_lfos_voice = 6;              // Voice LFOs
const int n_lfos_scene = 6;              // Scene LFOs
const int n_lfos = n_lfos_voice + n_lfos_scene;  // Total: 12

const int n_egs = 2;                     // Envelope generators (Filter, Amp)
const int n_osc_params = 7;              // Parameters per oscillator

// Effects system
const int n_fx_slots = 16;               // Total effect slots
const int n_fx_chains = 4;               // Chains: A, B, Send1, Send2
const int n_fx_per_chain = 4;            // 4 effects per chain
const int n_fx_params = 12;              // Parameters per effect

// Total parameter counts
const int n_scene_params = 273;          // Parameters per scene
const int n_global_params = 11 + n_fx_slots * (n_fx_params + 1);
const int n_global_postparams = 1;
const int n_total_params = n_global_params + 2 * n_scene_params + n_global_postparams;
// Result: 11 + 16 * 13 + 1 + 2 * 273 = 11 + 208 + 1 + 546 = 766 parameters total
```

**766 Parameters!**

This is why Surge is so flexible - nearly every aspect is parameterized and modulatable. The challenge: managing this many parameters efficiently.

## File Organization

### Source Tree Structure

```
surge/
├── src/
│   ├── common/                    # Platform-independent DSP engine
│   │   ├── dsp/                  # Digital signal processing
│   │   │   ├── oscillators/      # 13 oscillator implementations
│   │   │   ├── filters/          # Filter types and QuadFilterChain
│   │   │   ├── effects/          # 30+ effect implementations
│   │   │   ├── modulators/       # LFO, MSEG, Formula modulators
│   │   │   ├── Wavetable.cpp     # Wavetable engine
│   │   │   └── SurgeVoice.cpp    # Voice processing
│   │   │
│   │   ├── SurgeSynthesizer.cpp  # Main synthesis engine
│   │   ├── SurgeStorage.cpp      # Data storage and management
│   │   ├── SurgePatch.cpp        # Patch loading/saving
│   │   ├── Parameter.cpp         # Parameter system
│   │   └── ModulationSource.cpp  # Modulation base class
│   │
│   ├── surge-xt/                 # Plugin/standalone application
│   │   ├── gui/                  # User interface
│   │   │   ├── widgets/          # UI widgets (40+ types)
│   │   │   ├── overlays/         # Dialog windows
│   │   │   └── SurgeGUIEditor.cpp # Main editor
│   │   │
│   │   ├── SurgeSynthProcessor.cpp # JUCE plugin wrapper
│   │   └── osc/                  # Open Sound Control
│   │
│   ├── surge-fx/                 # Effects-only plugin
│   ├── surge-testrunner/         # Headless test suite
│   └── surge-python/             # Python bindings
│
├── libs/                         # Third-party libraries (submodules)
│   ├── JUCE/                     # Plugin framework
│   ├── sst/                      # SST libraries (filters, effects, etc.)
│   ├── airwindows/               # Airwindows ports
│   ├── LuaJIT/                   # Lua scripting
│   └── ...
│
└── resources/
    └── data/
        ├── patches_factory/      # Factory presets
        ├── wavetables/           # Wavetable files
        ├── skins/                # GUI skins
        └── configuration.xml     # Default configuration
```

## Build System Architecture

Surge uses **CMake** for cross-platform builds, supporting:
- Windows (Visual Studio, MSYS2)
- macOS (Xcode, clang)
- Linux (gcc, clang)
- Cross-compilation (ARM, macOS from Linux)

### Key Build Targets

```cmake
# From CMakeLists.txt

# Main synthesizer plugins
surge-xt_VST3          # VST3 plugin
surge-xt_AU            # Audio Unit (macOS)
surge-xt_CLAP          # CLAP plugin
surge-xt_LV2           # LV2 plugin (optional)
surge-xt_Standalone    # Standalone application

# Effects-only plugins
surge-fx_VST3
surge-fx_AU
surge-fx_CLAP
surge-fx_Standalone

# Development targets
surge-testrunner       # Headless test suite
surgepy                # Python bindings

# Meta-targets
surge-staged-assets    # Build all with staging
surge-xt-distribution  # Create installer
```

### Compile-Time Configuration

```cmake
# Critical defines
-DSURGE_COMPILE_BLOCK_SIZE=32      # Can be tuned for different systems
-DCMAKE_BUILD_TYPE=Release         # Release, Debug, RelWithDebInfo
-DSURGE_BUILD_PYTHON_BINDINGS=ON   # Optional Python support
-DSURGE_BUILD_LV2=TRUE             # Optional LV2 format
```

## Data Flow: From MIDI to Audio

Let's trace a note through the system:

### 1. MIDI Input (Plugin Host → Surge)

```cpp
// SurgeSynthProcessor.cpp (JUCE plugin wrapper)
void processBlock(AudioBuffer<float>& buffer, MidiBuffer& midiMessages)
{
    for (const auto metadata : midiMessages)
    {
        auto message = metadata.getMessage();

        if (message.isNoteOn())
        {
            surge->playNote(channel, note, velocity, 0);
        }
    }
}
```

### 2. Voice Allocation

```cpp
// SurgeSynthesizer.cpp
void SurgeSynthesizer::playNote(char channel, char key, char velocity, char detune)
{
    // Find free voice or steal one
    int voice_id = findFreeVoice();

    if (voice_id < 0)
        voice_id = stealVoice();  // No free voices - steal quietest

    // Initialize voice
    voices[voice_id].init(key, velocity, scene_id);
    voices[voice_id].state.gate = true;
}
```

### 3. Block Processing Loop

```cpp
// SurgeSynthesizer.cpp
void SurgeSynthesizer::process()
{
    // Process in BLOCK_SIZE chunks (32 samples)
    processControl();  // Update modulation, envelopes (slow rate)

    // Process all active voices
    for (int i = 0; i < MAX_VOICES; i++)
    {
        if (voices[i].state.active)
        {
            voices[i].process_block();  // Generate audio
        }
    }

    // Mix voices and process effects
    processFXChains();
}
```

### 4. Voice Processing

```cpp
// SurgeVoice.cpp
void SurgeVoice::process_block()
{
    // 1. Generate oscillator output (3 oscillators)
    for (int osc = 0; osc < n_oscs; osc++)
        oscillators[osc]->process_block();

    // 2. Mix oscillators with ring modulation
    mixOscillators();

    // 3. Filter processing (quad-processing for SIMD)
    filterChain.process_block(input);

    // 4. Apply amp envelope
    applyAmpEnvelope();

    // 5. Output to voice accumulator
}
```

### 5. Effect Processing

```cpp
// Process 4 parallel effect chains
for (int chain = 0; chain < n_fx_chains; chain++)
{
    for (int slot = 0; slot < n_fx_per_chain; slot++)
    {
        if (fx[chain][slot])
            fx[chain][slot]->process(dataL, dataR);
    }
}
```

### 6. Audio Output

```cpp
// Copy to plugin host's buffer
for (int i = 0; i < BLOCK_SIZE; i++)
{
    buffer.setSample(0, i, outputL[i]);
    buffer.setSample(1, i, outputR[i]);
}
```

## Thread Safety and Real-Time Considerations

### Audio Thread (Real-Time Critical)

**MUST NOT:**
- Allocate or free memory
- Perform file I/O
- Wait on locks (except lock-free structures)
- Call system functions with unbounded time

**MUST:**
- Complete processing within deadline (BLOCK_SIZE / samplerate)
- Use pre-allocated buffers
- Access shared data through lock-free queues or atomics

### UI Thread (Non-Real-Time)

**Can:**
- Allocate memory
- Load files (patches, wavetables)
- Perform complex calculations
- Block on user input

**Communication:** Parameter changes from UI are communicated to audio thread via:
```cpp
std::atomic<bool> parameterChanged[n_total_params];
// Audio thread checks these atomics each block
```

## Conclusion

Surge XT's architecture reflects professional audio software engineering:

1. **Clean Separation**: DSP engine independent of UI
2. **Performance**: SIMD optimization, block processing, careful memory management
3. **Flexibility**: 766 parameters, dual scenes, extensive modulation
4. **Extensibility**: New oscillators, filters, effects can be added without architectural changes
5. **Maintainability**: Clear file organization, consistent patterns

Understanding this architecture is essential for:
- Contributing new features
- Optimizing performance
- Debugging issues
- Designing your own synthesizers

In the next chapter, we'll explore the core data structures in detail, examining how Parameters, Storage, and Patches work together to create a flexible, powerful synthesis platform.

---

**Next: [Core Data Structures](02-core-data-structures.md)**
