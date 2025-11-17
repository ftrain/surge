# Chapter 2: Core Data Structures

## Introduction: The Data Foundation

In Chapter 1, we explored Surge's high-level architecture—the dual-scene design, block-based processing, and SIMD optimization. Now we descend into the foundational data structures that make it all work.

Three classes form the bedrock of Surge's data model:

1. **Parameter** - The fundamental unit of control, representing everything from oscillator pitch to effect mix levels
2. **SurgeStorage** - The central repository holding all parameters, wavetables, tuning, and configuration
3. **SurgePatch** - The serializable state container that saves and loads your sounds

Understanding these structures is essential because they pervade the entire codebase. Every knob you turn, every preset you load, every modulation you apply—all of it flows through these three classes.

This chapter provides a deep dive into each structure with real code examples, design rationale, and practical implications.

## Part 1: The Parameter System

### The Philosophical Problem

A synthesizer is fundamentally a collection of controllable values. Surge has **766 parameters** spread across oscillators, filters, envelopes, LFOs, effects, and global controls. Each parameter must:

- Store a value (float, int, or bool)
- Have minimum, maximum, and default values
- Display in human-readable formats ("1.23 Hz", "50%", "-6.0 dB")
- Accept modulation from multiple sources
- Support tempo sync, extended ranges, and deactivation
- Serialize to/from patches
- Respond to MIDI CC, MPE, and automation
- Provide metadata for UI rendering

The Parameter class encapsulates all this complexity into a single, reusable structure.

### The Parameter Data Union: pdata

At the heart of the Parameter class is a simple C union that holds the actual value:

```cpp
// From: src/common/Parameter.h (lines 35-40)
union pdata
{
    int i;
    bool b;
    float f;
};
```

**Why a union?** Parameters can represent different types of data:

- **Floats**: Most parameters (pitch, frequency, levels, etc.)
- **Integers**: Discrete selections (oscillator type, filter type)
- **Bools**: On/off switches (mute, keytrack)

A union allows all three types to occupy the same memory location (4 bytes), saving space and simplifying the API. The `valtype` enum tracks which member is active:

```cpp
// From: src/common/Parameter.h (lines 42-47)
enum valtypes
{
    vt_int = 0,
    vt_bool,
    vt_float,
};
```

### Parameter Storage: Four pdatas

Each Parameter doesn't just store the current value—it needs four related values:

```cpp
// From: src/common/Parameter.h (line 509)
pdata val{}, val_default{}, val_min{}, val_max{};
```

- **val**: Current value
- **val_default**: Factory default (for "Initialize" function)
- **val_min**: Minimum allowed value
- **val_max**: Maximum allowed value

Example from oscillator pitch:

```cpp
// From: src/common/Parameter.cpp (lines 598-604)
case ct_pitch:
case ct_pitch_extendable_very_low_minval:
    valtype = vt_float;
    val_min.f = -60;    // 60 semitones down (5 octaves)
    val_max.f = 60;     // 60 semitones up (5 octaves)
    val_default.f = 0;  // Default: no transposition
    break;
```

### Control Types: The Heart of Parameter Behavior

The `ctrltype` enum defines **over 220 different parameter types**, each with unique behavior for display, editing, and modulation. This is where Surge's flexibility comes from.

```cpp
// From: src/common/Parameter.h (lines 49-221)
enum ctrltypes
{
    ct_none,
    ct_percent,                      // 0% to 100%
    ct_percent_deactivatable,        // Can be turned off
    ct_percent_bipolar,              // -100% to +100%
    ct_decibel,                      // Decibel display
    ct_decibel_narrow,               // Narrower dB range
    ct_decibel_attenuation,          // Attenuation only (0 to -∞)
    ct_freq_audible,                 // Frequency in Hz
    ct_freq_audible_deactivatable,   // Frequency that can be disabled
    ct_pitch,                        // Pitch in semitones
    ct_pitch_semi7bp,                // ±7 semitone range
    ct_envtime,                      // Envelope time
    ct_envtime_deactivatable,        // Envelope time that can be disabled
    ct_lforate,                      // LFO rate
    ct_lforate_deactivatable,        // LFO rate that can be disabled
    ct_portatime,                    // Portamento time
    ct_osctype,                      // Oscillator type selector
    ct_fxtype,                       // Effect type selector
    ct_filtertype,                   // Filter type selector
    ct_bool,                         // Boolean on/off
    ct_midikey,                      // MIDI key number
    // ... and 200+ more types

    num_ctrltypes,
};
```

Each control type determines:

1. **Display format**: How the value appears to the user
2. **Edit behavior**: Linear vs. logarithmic response, snap points
3. **Modulation range**: How modulation depth maps to value changes
4. **Capabilities**: Can it tempo sync? Extend range? Be deactivated?

### Example: The Humble ct_percent

Let's trace how `ct_percent` (a basic 0-100% parameter) works:

```cpp
// From: src/common/Parameter.cpp
case ct_percent:
    valtype = vt_float;
    val_min.f = 0.f;
    val_max.f = 1.f;        // Internally 0.0 to 1.0
    val_default.f = 0.f;
    break;
```

Internally stored as 0.0 to 1.0, but displayed as 0% to 100%. The display conversion happens in `get_display()`:

```cpp
// Simplified from Parameter::get_display()
if (ctrltype == ct_percent)
{
    snprintf(txt, TXT_SIZE, "%.2f %%", val.f * 100.f);
}
```

### Example: The Complex ct_freq_audible

Frequency parameters are more sophisticated:

```cpp
case ct_freq_audible:
    valtype = vt_float;
    val_min.f = -60.f;      // MIDI note 0 = 8.176 Hz
    val_max.f = 70.f;       // MIDI note 130 = 11,839 Hz
    val_default.f = 60.f;   // Middle C = 261.6 Hz
    break;
```

**Wait—frequency stored as MIDI notes?** Yes! This is a brilliant design choice:

1. **Tuning independence**: MIDI note to frequency conversion happens in `note_to_pitch()`, which respects custom tuning scales
2. **Modulation consistency**: ±12 semitones is always an octave
3. **Tempo sync compatibility**: Musical intervals map naturally

The conversion from stored value to Hz display:

```cpp
// Simplified display logic
float pitch = storage->note_to_pitch(val.f);  // Uses tuning tables
float freq = 440.0f * pitch;                  // Concert A reference
snprintf(txt, TXT_SIZE, "%.2f Hz", freq);
```

### Special Parameter Capabilities

Parameters aren't just values—they have rich metadata and capabilities:

#### Tempo Sync

Many time-based parameters can sync to host tempo:

```cpp
// From: src/common/Parameter.cpp (lines 252-269)
bool Parameter::can_temposync() const
{
    switch (ctrltype)
    {
    case ct_portatime:
    case ct_lforate:
    case ct_lforate_deactivatable:
    case ct_envtime:
    case ct_envtime_deformable:
    case ct_reverbpredelaytime:
        return true;
    }
    return false;
}
```

When `temposync` is enabled, the parameter interprets its value as a musical division (1/16, 1/4, etc.) rather than absolute time:

```cpp
// From: src/common/Parameter.h (line 536)
bool temposync{}, absolute{}, deactivated{}, extend_range{};
```

#### Extended Range

Some parameters support an extended value range for extreme settings:

```cpp
// From: src/common/Parameter.cpp (lines 271-314)
bool Parameter::can_extend_range() const
{
    switch (ctrltype)
    {
    case ct_percent_with_extend_to_bipolar:       // Extends unipolar to bipolar
    case ct_pitch_semi7bp:                         // Extends ±7 to full range
    case ct_freq_shift:                            // Extends frequency shift range
    case ct_decibel_extendable:                    // More extreme dB values
    case ct_osc_feedback:                          // Higher feedback amounts
    case ct_lfoamplitude:                          // Extends LFO amplitude
        return true;
    }
    return false;
}
```

Example: LFO Rate can extend from normal musical rates to extreme subsonic/audio-rate modulation.

#### Deactivation

Some parameters can be turned off entirely:

```cpp
// From: src/common/Parameter.cpp (lines 329-355)
bool Parameter::can_deactivate() const
{
    switch (ctrltype)
    {
    case ct_percent_deactivatable:
    case ct_freq_audible_deactivatable:
    case ct_freq_audible_deactivatable_hp:    // High-pass filter
    case ct_freq_audible_deactivatable_lp:    // Low-pass filter
    case ct_lforate_deactivatable:
    case ct_envtime_deactivatable:
        return true;
    }
    return false;
}
```

When deactivated, the parameter's effect is completely bypassed—not just set to zero, but removed from the signal path entirely.

### Parameter Assignment and Naming

Parameters are created during SurgePatch construction using a fluent API:

```cpp
// From: src/common/SurgePatch.cpp (lines 69-72)
param_ptr.push_back(volume.assign(
    p_id.next(),                              // Unique ID promise
    0,                                        // Scene-local ID (0 = global)
    "volume",                                 // Internal name
    "Global Volume",                          // Display name
    "global/volume",                          // OSC name
    ct_decibel_attenuation_clipper,           // Control type
    Surge::Skin::Global::master_volume,       // UI position
    0,                                        // Scene (0 = global)
    cg_GLOBAL,                                // Control group
    0,                                        // Group entry
    true,                                     // Modulateable?
    int(kHorizontal) | int(kEasy)             // UI flags
));
```

**The ParameterIDCounter Promise System**

Surge uses a clever linked-list promise system to assign parameter IDs:

```cpp
// From: src/common/Parameter.h (lines 316-363)
struct ParameterIDCounter
{
    struct ParameterIDPromise
    {
        std::shared_ptr<ParameterIDPromise> next;
        long value = -1;
    };

    promise_t head, tail;

    // Get next promise (doesn't assign value yet)
    promise_t next()
    {
        promise_t n(new ParameterIDPromise());
        tail->next = n;
        auto ret = tail;
        tail = n;
        return ret;
    }

    // Resolve all promises to actual IDs
    void resolve() const
    {
        auto h = head;
        int val = 0;
        while (h.get())
        {
            h->value = val++;
            h = h->next;
        }
    }
};
```

**Why promises?** This allows parameters to be defined in logical groups (oscillators together, filters together) while still maintaining a globally unique, sequential ID space. All promises are resolved at the end of patch construction.

### Parameter Metadata and Display

Each parameter carries rich metadata for UI rendering:

```cpp
// From: src/common/Parameter.h (lines 517-539)
class Parameter
{
public:
    int id{};                                  // Globally unique ID
    char name[NAMECHARS]{};                    // Internal name
    char dispname[NAMECHARS]{};                // Display name
    char name_storage[NAMECHARS]{};            // Storage name (for patches)
    char fullname[NAMECHARS]{};                // Full qualified name
    char ui_identifier[NAMECHARS]{};           // UI widget ID

    bool modulateable{};                       // Can be modulated?
    int valtype = 0;                           // vt_int/bool/float
    int scene{};                               // 0=patch, 1=scene A, 2=scene B
    int ctrltype{};                            // ct_percent, ct_freq_audible, etc.

    int posx, posy, posy_offset;               // UI position
    ControlGroup ctrlgroup = cg_GLOBAL;        // Which section (OSC, FILTER, etc.)
    int ctrlgroup_entry = 0;                   // Which instance (Osc 1, Osc 2, etc.)

    bool temposync{}, absolute{}, deactivated{}, extend_range{};
    float moverate{};                          // UI response speed
    bool per_voice_processing{};               // Voice vs. scene processing
};
```

### Control Groups: Organizing Parameters

Parameters belong to logical groups:

```cpp
// From: src/common/Parameter.h (lines 228-238)
enum ControlGroup
{
    cg_GLOBAL = 0,     // Global parameters
    cg_OSC = 2,        // Oscillator parameters
    cg_MIX = 3,        // Mixer parameters
    cg_FILTER = 4,     // Filter parameters
    cg_ENV = 5,        // Envelope parameters
    cg_LFO = 6,        // LFO/modulator parameters
    cg_FX = 7,         // Effect parameters
    endCG
};

const char ControlGroupDisplay[endCG][32] = {
    "Global", "", "Oscillators", "Mixer",
    "Filters", "Envelopes", "Modulators", "FX"
};
```

This grouping determines:
- UI layout (which panel shows the parameter)
- Parameter naming ("Filter 1 Cutoff")
- Help URL routing
- Copy/paste behavior

### Modulation Depth and Ranges

Parameters support modulation through a normalized 0-1 (unipolar) or -1 to +1 (bipolar) depth:

```cpp
// From: src/common/Parameter.h (lines 488-493)
float get_modulation_f01(float mod) const;   // Convert mod depth to 0-1
float set_modulation_f01(float v) const;     // Convert 0-1 to mod depth
```

For a bipolar parameter (like pitch), a modulation depth of +1.0 means "modulate from center to maximum". For unipolar (like a level), +1.0 means "modulate from zero to current value".

The actual modulation application happens in voice processing:

```cpp
// Simplified from SurgeVoice.cpp
float pitch_base = scene->pitch.val.f;
float pitch_modulated = pitch_base +
    (lfo1.output * lfo1_to_pitch_depth) +
    (lfo2.output * lfo2_to_pitch_depth) +
    // ... other modulators
```

### Parameter Smoothing

To avoid audio clicks and zipper noise, parameters are smoothed over time:

```cpp
// From: src/common/Parameter.h (line 533)
float moverate{};  // Smoothing speed multiplier
```

The synthesis engine interpolates parameter changes over multiple blocks:

```cpp
// Simplified smoothing logic
float target = param.val.f;
float current = param_smoothed[param.id];
float rate = param.moverate * BLOCK_SIZE_INV;

current += (target - current) * rate;
param_smoothed[param.id] = current;
```

This creates smooth parameter automation without audible artifacts.

## Part 2: SurgeStorage - The Central Repository

If Parameter is the atom, **SurgeStorage** is the periodic table—it holds all parameters, wavetables, tuning systems, patches, and global configuration.

### The 766-Parameter Array

At the center of SurgeStorage is the parameter array:

```cpp
// From: src/common/SurgePatch.h (lines 1215-1216)
std::vector<Parameter *> param_ptr;
```

This vector holds **pointers** to all 766 parameters in the synth:

```
Index | Parameter
------|--------------------
0     | Send FX 1 Return Level
1     | Send FX 2 Return Level
2     | Send FX 3 Return Level
3     | Send FX 4 Return Level
4     | Global Volume
5     | Scene Active
6     | Scene Mode
7     | Split Point
...
765   | Scene B LFO 6 Release
```

**Why pointers?** The actual Parameter objects live in specialized storage structures (OscillatorStorage, FilterStorage, etc.). The param_ptr array provides fast, indexed access:

```cpp
// Get parameter by global ID
Parameter *p = storage->getPatch().param_ptr[param_id];

// Set value
p->val.f = 0.5f;

// Get display string
char display[256];
p->get_display(display);  // "50.0 %"
```

### The Parameter Count Calculation

Let's verify the 766 total:

```cpp
// From: src/common/SurgeStorage.h (lines 150-154)
const int n_scene_params = 273;     // Parameters per scene
const int n_global_params = 11 +    // Global controls
    n_fx_slots * (n_fx_params + 1); // FX (16 slots × 13 params each)
const int n_global_postparams = 1;  // Character parameter
const int n_total_params = n_global_params +
                           2 * n_scene_params +
                           n_global_postparams;

// n_global_params = 11 + (16 × 13) = 11 + 208 = 219
// n_total_params = 219 + (2 × 273) + 1 = 219 + 546 + 1 = 766
```

### Wavetable Storage

SurgeStorage manages all loaded wavetables:

```cpp
// From: src/common/SurgeStorage.h (lines 1560-1565)
std::vector<Patch> wt_list;                  // All available wavetables
std::vector<PatchCategory> wt_category;      // Wavetable categories
int firstThirdPartyWTCategory;               // Category boundary
int firstUserWTCategory;                     // Category boundary
std::vector<int> wtOrdering;                 // Sorted order
std::vector<int> wtCategoryOrdering;         // Category sort order
```

Wavetable files (.wt, .wav) are scanned at startup:

```cpp
// From: src/common/SurgeStorage.h
void refresh_wtlist();                       // Scan wavetable directories
void load_wt(int id, Wavetable *wt,         // Load wavetable by ID
             OscillatorStorage *);
void load_wt(std::string filename,          // Load by filename
             Wavetable *wt, OscillatorStorage *);
```

### Tuning System

Surge supports arbitrary microtuning via the **Tunings** library:

```cpp
// From: src/common/SurgeStorage.h (lines 1648-1652)
Tunings::Tuning currentTuning;               // Active tuning
Tunings::Scale currentScale;                 // Current scale (.scl)
Tunings::KeyboardMapping currentMapping;     // Current mapping (.kbm)
bool isStandardTuning = true;                // Using 12-TET?
bool isStandardScale = true;
bool isStandardMapping = true;
```

The tuning system converts MIDI notes to frequencies:

```cpp
// From: src/common/SurgeStorage.h (lines 1615-1626)
float note_to_pitch(float x);                      // MIDI note → pitch multiplier
float note_to_pitch_inv(float x);                  // Inverse
float note_to_pitch_ignoring_tuning(float x);      // 12-TET only
void note_to_omega(float note, float &omega_out,   // Note → angular frequency
                   float &omega_out2);
```

Users can load:
- **SCL files** (Scala scale files) - define the intervals in an octave
- **KBM files** (keyboard mapping) - map scale degrees to MIDI keys

### Sample Rate Management

The sample rate is stored and propagated throughout the engine:

```cpp
// From: src/common/SurgeStorage.h (lines 1366-1368)
float samplerate{0}, samplerate_inv{1};           // Float SR
double dsamplerate{0}, dsamplerate_inv{1};        // Double precision
double dsamplerate_os{0}, dsamplerate_os_inv{1};  // Oversampled rate

void setSamplerate(float sr);                      // Update sample rate
```

When sample rate changes:
1. All lookup tables are regenerated (`init_tables()`)
2. Effect states are reset
3. Delay buffer sizes are recalculated

### Lookup Tables for Performance

SurgeStorage maintains pre-computed tables to avoid expensive calculations in the audio thread:

```cpp
// From: src/common/SurgeStorage.h (lines 1363-1365, 1447-1455)
float *sinctable, *sinctable1X;                    // Sinc interpolation
float table_dB[512];                               // dB conversion
float table_envrate_lpf[512];                      // Envelope rates
float table_envrate_linear[512];                   // Linear envelope rates
float table_glide_exp[512];                        // Exponential glide
float table_glide_log[512];                        // Logarithmic glide

static constexpr int tuning_table_size = 512;
float table_pitch[tuning_table_size];              // MIDI note → pitch
float table_pitch_inv[tuning_table_size];          // Inverse
float table_note_omega[2][tuning_table_size];      // Note → omega
```

Example: Converting dB to linear:

```cpp
// Instead of: pow(10.0, db / 20.0)
float linear = storage->table_dB[(int)(db_value * scale_factor)];
```

This turns an expensive `pow()` into a single array lookup.

### Resource Paths

SurgeStorage tracks all file system locations:

```cpp
// From: src/common/SurgeStorage.h (lines 1571-1586)
fs::path datapath;                     // Factory data (read-only)
fs::path userDefaultFilePath;          // User preferences
fs::path userDataPath;                 // User data root
fs::path userPatchesPath;              // User patches
fs::path userWavetablesPath;           // User wavetables
fs::path userModulatorSettingsPath;    // LFO presets
fs::path userFXPath;                   // FX presets
fs::path userSkinsPath;                // Custom skins
fs::path userMidiMappingsPath;         // MIDI learn maps
```

Platform-specific defaults:
- **Windows**: `%APPDATA%\Surge XT\`
- **macOS**: `~/Documents/Surge XT/`
- **Linux**: `~/.local/share/surge-xt/`

### The Patch Database

For fast patch browsing, SurgeStorage maintains an in-memory database:

```cpp
// From: src/common/SurgeStorage.h (lines 1459-1462, 1551-1557)
std::unique_ptr<Surge::PatchStorage::PatchDB> patchDB;
bool patchDBInitialized{false};

std::vector<Patch> patch_list;                     // All patches
std::vector<PatchCategory> patch_category;         // Categories
int firstThirdPartyCategory;                       // Category boundary
int firstUserCategory;                             // Category boundary
std::vector<int> patchOrdering;                    // Sort order
std::vector<int> patchCategoryOrdering;            // Category sort
```

Patches are scanned at startup and organized into a tree:

```
Factory/
├── Bass/
│   ├── Aggressive Bass.fxp
│   └── Sub Bass.fxp
├── Lead/
│   ├── Screaming Lead.fxp
│   └── Smooth Lead.fxp
└── ...
User/
└── My Sounds/
    └── Custom Patch.fxp
Third Party/
└── Downloaded/
    └── ...
```

### Audio I/O Buffers

SurgeStorage holds the audio input buffers (for the Audio Input oscillator):

```cpp
// From: src/common/SurgeStorage.h (lines 1354-1357)
float audio_in alignas(16)[2][BLOCK_SIZE_OS];      // Oversampled input
float audio_in_nonOS alignas(16)[2][BLOCK_SIZE];   // Non-oversampled
float audio_otherscene alignas(16)[2][BLOCK_SIZE_OS]; // Other scene output
```

These are filled by the host and accessed by oscillators/effects needing external audio.

### Random Number Generation

SurgeStorage provides thread-safe RNG for DSP:

```cpp
// From: src/common/SurgeStorage.h (lines 1880-1931)
struct RNGGen
{
    std::minstd_rand g;                            // Generator
    std::uniform_int_distribution<int> d;          // Integer distribution
    std::uniform_real_distribution<float> pm1;     // -1 to +1
    std::uniform_real_distribution<float> z1;      // 0 to 1
    std::uniform_int_distribution<uint32_t> u32;   // 32-bit unsigned
} rngGen;

inline int rand() { return rngGen.d(rngGen.g); }
inline float rand_pm1() { return rngGen.pm1(rngGen.g); }  // ±1
inline float rand_01() { return rngGen.z1(rngGen.g); }    // 0-1
inline uint32_t rand_u32() { return rngGen.u32(rngGen.g); }
```

This RNG is seeded once per session and maintains independent state from the system's `rand()`, ensuring reproducible behavior for testing.

## Part 3: SurgePatch - State Serialization

**SurgePatch** is the serializable container that represents a complete synthesizer state—everything needed to recreate a sound.

### Patch Data Model

```cpp
// From: src/common/SurgePatch.h (lines 1157-1227)
class SurgePatch
{
public:
    // Scene data (2 scenes)
    SurgeSceneStorage scene[n_scenes], morphscene;

    // Effects (16 slots)
    FxStorage fx[n_fx_slots];

    // Global parameters
    Parameter scene_active, scenemode, splitpoint;
    Parameter volume, polylimit, fx_bypass, fx_disable;
    Parameter character;

    // Modulation data
    StepSequencerStorage stepsequences[n_scenes][n_lfos];
    MSEGStorage msegs[n_scenes][n_lfos];
    FormulaModulatorStorage formulamods[n_scenes][n_lfos];

    // Metadata
    std::string name, category, author, license, comment;
    std::vector<Tag> tags;

    // Modulation routing
    std::vector<ModulationRouting> modulation_global;

    // Reference to storage
    SurgeStorage *storage;
};
```

### Patch vs. Storage: A Critical Distinction

- **SurgePatch**: The **state** (parameter values, modulation routing)
- **SurgeStorage**: The **context** (wavetables, tuning, file paths)

When you load a patch:
1. Patch file is read → parameter values extracted
2. Values are written to Parameter objects
3. Wavetable references are resolved via SurgeStorage
4. Modulation routing is established
5. Voice state is reset

### XML-Based Patch Format

Surge patches are XML files with extensive versioning:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<patch revision="28">
    <meta>
        <name>My Awesome Sound</name>
        <category>Bass</category>
        <author>John Doe</author>
    </meta>

    <parameters>
        <p id="0" value="0.75"/>  <!-- Send FX 1 Return -->
        <p id="1" value="0.50"/>  <!-- Send FX 2 Return -->
        <!-- ... 764 more parameters ... -->
    </parameters>

    <modulation>
        <routing source="lfo1" depth="0.5" destination="filter1_cutoff"/>
        <routing source="modwheel" depth="1.0" destination="lfo1_rate"/>
        <!-- ... more routing ... -->
    </modulation>

    <scene id="0">
        <osc id="0" type="wavetable" wavetable="Sawtooth"/>
        <!-- ... oscillator data ... -->
    </scene>
</patch>
```

### The 28 Revisions of History

The `revision` attribute tracks patch format changes over Surge's history:

```cpp
// From: src/common/SurgeStorage.h (lines 88-147)
const int ff_revision = 28;  // Current revision

// XML file format revision history:
// 0 → 1   New filter/amp EG attack shapes
// 1 → 2   New LFO EG stages
// 2 → 3   Filter subtypes added
// 3 → 4   Comb+ and Comb- combined
// 4 → 5   Stereo filter separate pan controls
// 5 → 6   Filter resonance response changed (1.2.0 release)
// 6 → 7   Custom controller state in DAW recall
// 7 → 8   Larger resonance range, Pan 2 → Width
// 8 → 9   Macros extended to 8, macro naming
// 9 → 10  Character parameter added
// 10 → 11 DAW extra state (1.6.2)
// 11 → 12 New Distortion parameters (1.6.3)
// 12 → 13 Slider deactivation, Sine filters, feedback extension (1.7.0)
// 13 → 14 Phaser parameters, Vocoder input config (1.8.0 nightlies)
// 14 → 15 Filter type remapping (1.8.0 release)
// 15 → 16 Oscillator retrigger consistency (1.9.0)
// 16 → 17 Window oscillator, new waveshapers, 2 extra FX slots (XT 1.0)
// 17 → 18 Delay feedback clipping, Phaser tone (XT 1.1 nightlies)
// 18 → 19 String deform, negative delay (XT 1.1 nightlies)
// 19 → 20 Voice envelope mode (XT 1.1)
// 20 → 21 Combulator absolute mode, MTS (XT 1.2)
// 21 → 22 Ring mod modes, Bonsai FX, MIDI mapping (XT 1.3)
// 22 → 23 Tempo parameter, Ensemble output filter (XT 1.3.2)
// 23 → 24 FM2 extend mode fix (XT 1.3.3)
// 24 → 25 Wavetable script state (XT 1.3.4)
// 25 → 26 WT Deform, LFO amplitude extend, Lua editor state (XT 1.4.*)
// 26 → 27 OBXD and BP12 legacy fix, extendable waveshaper (XT 1.4.*)
// 27 → 28 Corrected TX shapes (XT 1.4.*)
```

**Backward Compatibility**: When loading an old patch, migration code runs to update it:

```cpp
// Simplified migration example
if (patch_revision < 8)
{
    // Old patches had "Pan 2", rename to "Width"
    scene[s].width.set_name("Width");
}

if (patch_revision < 15)
{
    // Remap old filter type IDs to new organization
    int old_type = filter.type.val.i;
    filter.type.val.i = legacyFilterTypeRemap[old_type];
}
```

### Patch Metadata

Beyond parameter values, patches store rich metadata:

```cpp
// From: src/common/SurgePatch.h (lines 1226-1234)
std::string name;        // "Aggressive Bass"
std::string category;    // "Bass / Mono"
std::string author;      // "Claes Johanson"
std::string license;     // "CC-BY-SA"
std::string comment;     // "Great for techno!"

struct Tag
{
    std::string tag;     // "dark", "aggressive", etc.
};
std::vector<Tag> tags;
```

This metadata powers the patch browser's search and filtering.

### Loading a Patch: The Complete Flow

When you load a patch, here's what happens:

```cpp
// From: src/common/SurgePatch.cpp
void SurgePatch::load_xml(const void *data, int size, bool preset)
{
    // 1. Parse XML
    TiXmlDocument doc;
    doc.Parse((const char *)data);

    // 2. Read revision number
    int rev = 0;
    root->Attribute("revision", &rev);
    streamingRevision = rev;

    // 3. Read metadata
    TiXmlElement *meta = root->FirstChildElement("meta");
    if (meta)
    {
        name = meta->Attribute("name");
        category = meta->Attribute("category");
        author = meta->Attribute("author");
    }

    // 4. Load parameters
    TiXmlElement *params = root->FirstChildElement("parameters");
    for (TiXmlElement *p = params->FirstChildElement("p");
         p; p = p->NextSiblingElement("p"))
    {
        int id = 0;
        p->Attribute("id", &id);

        Parameter *param = param_ptr[id];

        if (param->valtype == vt_float)
        {
            double v = 0;
            p->Attribute("value", &v);
            param->val.f = v;
        }
        // ... int and bool cases ...
    }

    // 5. Load modulation routing
    TiXmlElement *modulation = root->FirstChildElement("modulation");
    // ... parse routing ...

    // 6. Load scene-specific data (oscillators, LFOs, MSEGs)
    // ...

    // 7. Run migration if needed
    if (streamingRevision < ff_revision)
    {
        // Apply version-specific migrations
    }

    // 8. Rebuild derived state
    update_controls(true);  // Recalculate dependent values
}
```

### Saving a Patch: Serialization

Saving is the inverse:

```cpp
unsigned int SurgePatch::save_xml(void **data)
{
    TiXmlDocument doc;

    // Root element with current revision
    TiXmlElement root("patch");
    root.SetAttribute("revision", ff_revision);

    // Metadata
    TiXmlElement meta("meta");
    meta.SetAttribute("name", name);
    meta.SetAttribute("category", category);
    meta.SetAttribute("author", author);
    root.InsertEndChild(meta);

    // Parameters
    TiXmlElement params("parameters");
    for (int i = 0; i < param_ptr.size(); i++)
    {
        TiXmlElement p("p");
        p.SetAttribute("id", i);

        if (param_ptr[i]->valtype == vt_float)
            p.SetDoubleAttribute("value", param_ptr[i]->val.f);
        // ... other types ...

        params.InsertEndChild(p);
    }
    root.InsertEndChild(params);

    // Modulation
    // Scene data
    // ...

    doc.InsertEndChild(root);

    // Convert to string
    TiXmlPrinter printer;
    doc.Accept(&printer);

    *data = strdup(printer.CStr());
    return printer.Size();
}
```

### DAW Extra State: Session-Specific Data

Some state should persist in your DAW session but **not** in the patch file itself:

```cpp
// From: src/common/SurgeStorage.h (lines 897-1145)
struct DAWExtraStateStorage
{
    bool isPopulated = false;

    struct EditorState
    {
        int instanceZoomFactor = -1;          // UI zoom level
        int current_scene = 0;                // Which scene tab is open
        int current_fx = 0;                   // Which FX is selected
        int current_osc[n_scenes] = {0};      // Which osc is selected
        bool isMSEGOpen = false;              // Is MSEG editor open?

        // Formula editor state
        struct FormulaEditState { /* ... */ } formulaEditState[n_scenes][n_lfos];

        // Wavetable script editor state
        struct WavetableScriptEditState { /* ... */ } wavetableScriptEditState[n_scenes][n_oscs];
    } editor;

    // MPE settings (session-specific, not patch-specific)
    bool mpeEnabled = false;
    int mpePitchBendRange = -1;

    // MIDI controller mappings (learned in the session)
    std::map<int, int> midictrl_map;

    // Tuning (can be session or patch)
    bool hasScale = false;
    std::string scaleContents = "";
    bool hasMapping = false;
    std::string mappingContents = "";
};
```

This is saved in your DAW project file, separate from the .fxp patch.

## Practical Implications for Developers

### Adding a New Parameter

To add a new parameter to Surge:

1. **Define storage** in the appropriate structure (e.g., `OscillatorStorage`)
2. **Assign in SurgePatch constructor**:
   ```cpp
   a->push_back(scene[sc].osc[osc].my_new_param.assign(
       p_id.next(), id_s++, "mynewparam", "My New Param",
       fmt::format("{:c}/osc/{}/mynewparam", 'a' + sc, osc + 1),
       ct_percent,  // Choose appropriate control type
       Surge::Skin::Osc::my_new_param_connector,
       sc_id, cg_OSC, osc, true
   ));
   ```
3. **Use in DSP code**:
   ```cpp
   float value = oscdata->my_new_param.val.f;
   ```
4. **Test** patch save/load
5. **Document** in user manual

### Adding a New Control Type

To add a new `ctrltype`:

1. **Add enum** in `Parameter.h`:
   ```cpp
   enum ctrltypes {
       // ...
       ct_my_new_type,
       num_ctrltypes,
   };
   ```
2. **Define range** in `Parameter::set_type()`:
   ```cpp
   case ct_my_new_type:
       valtype = vt_float;
       val_min.f = 0.f;
       val_max.f = 100.f;
       val_default.f = 50.f;
       break;
   ```
3. **Implement display** in `Parameter::get_display()`:
   ```cpp
   case ct_my_new_type:
       snprintf(txt, TXT_SIZE, "%.1f units", val.f);
       break;
   ```
4. **Test** all parameter operations

### Debugging Parameter Issues

Common issues and solutions:

**Issue**: Parameter doesn't save correctly
- Check `valtype` matches actual data type
- Verify parameter ID is in valid range
- Check XML serialization code

**Issue**: Parameter displays wrong value
- Check `get_display()` has correct case
- Verify min/max ranges are correct
- Check for scaling errors (0-1 vs. display range)

**Issue**: Modulation doesn't work
- Verify `modulateable` is true
- Check modulation depth calculation
- Ensure parameter isn't bypassed or deactivated

## Conclusion

The three core data structures—Parameter, SurgeStorage, and SurgePatch—form the foundation of Surge's flexibility and power.

**Parameter** encapsulates all the complexity of a controllable value: storage, display, modulation, tempo sync, and metadata. Its 220+ control types provide the vocabulary for describing every knob and switch in the synthesizer.

**SurgeStorage** is the central repository, holding all parameters, wavetables, tuning, and configuration in one globally accessible structure. Its lookup tables and caching strategies ensure real-time performance.

**SurgePatch** handles state serialization, preserving your sounds across sessions with careful versioning and backward compatibility spanning 28 revisions of development.

Together, these structures demonstrate professional software engineering:
- **Type safety** with explicit valtypes
- **Memory efficiency** with unions and careful layout
- **Extensibility** through control types and metadata
- **Backward compatibility** through versioned serialization
- **Performance** through lookup tables and smoothing

Understanding these structures is your gateway to understanding Surge itself. Every oscillator, filter, effect, and modulator builds upon this foundation.

In the next chapter, we'll explore how these parameters come alive through modulation, examining the modulation matrix, routing system, and the sources that drive parameter changes.

---

**Next: [The Modulation System](03-modulation-system.md)**

**See Also**:
- Chapter 1: [Architecture Overview](01-architecture-overview.md)
- Chapter 5: [Oscillators Overview](05-oscillators-overview.md)
- Chapter 18: [Modulation Architecture](18-modulation-architecture.md)
