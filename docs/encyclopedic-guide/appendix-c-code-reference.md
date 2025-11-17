# Appendix C: Code Reference

Quick reference guide to the Surge XT codebase for developers.

## Table of Contents

- [File Organization](#file-organization)
- [Key Classes](#key-classes)
- [Constants Reference](#constants-reference)
- [Enums](#enums)
- [Type System](#type-system)
- [Utility Functions](#utility-functions)
- [Module Interface](#module-interface)

---

## File Organization

### Top-Level Source Structure

```
src/
├── common/              # Core DSP engine and synthesis
│   ├── dsp/            # DSP processing components
│   ├── Parameter.h/cpp # Parameter system
│   ├── SurgeStorage.h  # Data repository and patch storage
│   ├── SurgeSynthesizer.h # Main synthesizer engine
│   └── globals.h       # Global constants and configuration
│
├── surge-xt/           # Plugin and UI implementation
│   ├── gui/           # JUCE-based user interface
│   ├── cli/           # Command-line interface
│   ├── osc/           # OSC (Open Sound Control) support
│   └── util/          # Utility functions
│
├── surge-fx/          # Standalone effect plugin
├── surge-python/      # Python bindings
├── surge-testrunner/  # Test framework
├── lua/               # Lua scripting support
└── platform/          # Platform-specific code
    ├── juce/         # JUCE integration
    └── macos/        # macOS-specific code
```

### DSP Directory Structure

```
src/common/dsp/
├── effects/           # Effect processors (27 effects)
│   ├── airwindows/   # Airwindows effect ports
│   ├── chowdsp/      # ChowDSP effect ports
│   │   ├── bbd_utils/
│   │   ├── exciter/
│   │   ├── spring_reverb/
│   │   └── tape/
│   └── *.h           # Individual effect headers
│
├── filters/          # Filter implementations
│   ├── BiquadFilter.h
│   └── VectorizedSVFilter.h
│
├── modulators/       # Modulation sources
│   ├── ADSRModulationSource.h
│   ├── LFOModulationSource.h
│   ├── MSEGModulationHelper.h
│   └── FormulaModulationHelper.h
│
├── oscillators/      # Oscillator implementations
│   ├── OscillatorBase.h
│   ├── ClassicOscillator.h
│   ├── SineOscillator.h
│   ├── WavetableOscillator.h
│   ├── FM2Oscillator.h
│   ├── FM3Oscillator.h
│   ├── WindowOscillator.h
│   ├── ModernOscillator.h
│   ├── StringOscillator.h
│   ├── TwistOscillator.h
│   ├── AliasOscillator.h
│   ├── SampleAndHoldOscillator.h
│   └── AudioInputOscillator.h
│
├── utilities/        # DSP utilities
│   ├── DSPUtils.h
│   ├── SSEComplex.h
│   └── SSESincDelayLine.h
│
├── vembertech/       # Legacy Vember Audio code
├── Effect.h          # Effect base class
├── Oscillator.h      # Oscillator factory
├── SurgeVoice.h      # Voice processing
└── QuadFilterChain.h # Filter processing
```

### Libraries Directory

```
libs/
├── JUCE/             # JUCE framework
├── sst/              # Surge Synth Team libraries
│   └── sst-basic-blocks/
├── airwindows/       # Airwindows effect library
├── eurorack/         # Mutable Instruments DSP
├── luajitlib/        # LuaJIT library
├── oddsound-mts/     # MTS-ESP microtonal support
├── pffft/            # Fast FFT library
├── simde/            # SIMD Everywhere
├── fmt/              # String formatting
├── PEGTL/            # Parser library
└── catch2_v3/        # Testing framework
```

### Resources Directory

```
resources/
├── data/             # Factory content
│   ├── patches/     # Factory patches
│   ├── wavetables/  # Factory wavetables
│   ├── skins/       # UI skins
│   └── configuration.xml
│
├── fonts/           # UI fonts
├── assets/          # UI graphics and assets
├── classic-skin-svgs/ # SVG graphics
└── test-data/       # Test resources
```

---

## Key Classes

### Core Engine Classes

#### SurgeSynthesizer
**Location:** `/home/user/surge/src/common/SurgeSynthesizer.h`

Main synthesizer engine class. Handles audio processing, voice management, and plugin interface.

```cpp
class alignas(16) SurgeSynthesizer
{
    float output[N_OUTPUTS][BLOCK_SIZE];
    float input[N_INPUTS][BLOCK_SIZE];
    SurgeStorage storage;

    // Note control
    void playNote(char channel, char key, char velocity, char detune,
                  int32_t host_noteid = -1, int32_t forceScene = -1);
    void releaseNote(char channel, char key, char velocity,
                     int32_t host_noteid = -1);

    // Audio processing
    void process();

    // Parameter control
    void setParameter01(long index, float value);
    float getParameter01(long index);
};
```

#### SurgeStorage
**Location:** `/home/user/surge/src/common/SurgeStorage.h`

Central data repository. Manages patches, wavetables, configuration, and provides access to all synth data.

```cpp
class SurgeStorage
{
    // Current patch
    SurgePatch patch;

    // Sample rate and timing
    float samplerate;
    float dsamplerate_inv;  // 1/samplerate
    float dsamplerate_os_inv; // 1/(samplerate * OSC_OVERSAMPLING)

    // Data paths
    std::string datapath;
    std::string userDataPath;

    // Resources
    std::vector<PatchInfo> patch_list;
    std::vector<Wavetable> wt_list;

    // Tuning
    Tunings::Tuning currentTuning;
    Tunings::Scale currentScale;
};
```

#### SurgePatch
**Location:** `/home/user/surge/src/common/SurgeStorage.h` (line 1157)

State container for all patch data. Handles patch loading/saving and parameter values.

```cpp
class SurgePatch
{
    void init_default_values();
    void update_controls(bool init = false, void *init_osc = 0);

    // Serialization
    void load_xml(const void *data, int size, bool preset);
    unsigned int save_xml(void **data);
    unsigned int save_RIFF(void **data);

    // Parameters
    Parameter param[n_total_params];

    // Scene data
    SurgeSceneStorage scene[n_scenes];

    // Global parameters
    float volume;
    int scene_active[n_scenes];
    int scenemode;
    int splitpoint;
};
```

#### SurgeVoice
**Location:** `/home/user/surge/src/common/dsp/SurgeVoice.h`

Voice processing class. Each active note gets a SurgeVoice instance.

```cpp
class alignas(16) SurgeVoice
{
    float output[2][BLOCK_SIZE_OS];
    SurgeVoiceState state;

    bool process_block(QuadFilterChainState &, int);
    void release();
    void uber_release();  // Immediate release
    void legato(int key, int velocity, char detune);

    int age, age_release;
    int key, velocity, channel;
};
```

### Parameter System

#### Parameter
**Location:** `/home/user/surge/src/common/Parameter.h`

Represents a single modulatable parameter.

```cpp
class Parameter
{
    pdata val;              // Current value (union of int/bool/float)
    pdata val_default;      // Default value
    pdata val_min, val_max; // Range

    int valtype;           // vt_int, vt_bool, or vt_float
    int ctrltype;          // Control type (ct_*)
    int scene;             // 0 = A, 1 = B, 2 = global

    // Display
    void get_display(char* txt);
    bool set_value_from_string(std::string s);

    // Modulation
    float get_modulation(float);
    void set_modulation(float);
};
```

#### pdata Union
**Location:** `/home/user/surge/src/common/Parameter.h` (line 35)

```cpp
union pdata
{
    int i;
    bool b;
    float f;
};
```

### DSP Module Base Classes

#### Oscillator
**Location:** `/home/user/surge/src/common/dsp/oscillators/OscillatorBase.h`

Base class for all oscillators.

```cpp
class alignas(16) Oscillator
{
    float output[BLOCK_SIZE_OS];
    float outputR[BLOCK_SIZE_OS];

    virtual void init(float pitch, bool is_display = false,
                     bool nonzero_init_drift = true) = 0;
    virtual void init_ctrltypes() = 0;
    virtual void init_default_values() = 0;

    virtual void process_block(float pitch, float drift = 0.f,
                              bool stereo = false, bool FM = false,
                              float FMdepth = 0.f) = 0;

    // Utility functions
    double pitch_to_omega(float x);
    double pitch_to_dphase(float x);
};
```

Factory function:
```cpp
Oscillator *spawn_osc(int osctype, SurgeStorage *storage,
                     OscillatorStorage *oscdata, pdata *localcopy,
                     pdata *localcopyUnmod, unsigned char *onto);
```

#### Effect
**Location:** `/home/user/surge/src/common/dsp/Effect.h`

Base class for all effects.

```cpp
class alignas(16) Effect
{
    virtual const char *get_effectname() = 0;

    virtual void init() = 0;
    virtual void init_ctrltypes() = 0;
    virtual void init_default_values() = 0;

    virtual void process(float *dataL, float *dataR) = 0;
    virtual void process_only_control();
    virtual bool process_ringout(float *dataL, float *dataR,
                                bool indata_present = true);

    virtual void suspend();
    virtual void sampleRateReset();

    virtual int get_ringout_decay() { return -1; }

    SurgeStorage *storage;
    FxStorage *fxdata;
    pdata *pd;
};
```

---

## Constants Reference

### From globals.h

**File:** `/home/user/surge/src/common/globals.h`

```cpp
// Window size
const int BASE_WINDOW_SIZE_X = 913;
const int BASE_WINDOW_SIZE_Y = 569;

// Audio processing
const int BLOCK_SIZE = SURGE_COMPILE_BLOCK_SIZE;  // Typically 32
const int OSC_OVERSAMPLING = 2;
const int BLOCK_SIZE_OS = OSC_OVERSAMPLING * BLOCK_SIZE;  // 64
const int BLOCK_SIZE_QUAD = BLOCK_SIZE >> 2;  // 8
const int BLOCK_SIZE_OS_QUAD = BLOCK_SIZE_OS >> 2;  // 16
const float BLOCK_SIZE_INV = (1.f / BLOCK_SIZE);
const float BLOCK_SIZE_OS_INV = (1.f / BLOCK_SIZE_OS);

// Oscillator buffer
const int OB_LENGTH = BLOCK_SIZE_OS << 1;  // 128
const int OB_LENGTH_QUAD = OB_LENGTH >> 2;  // 32

// Voice and unison
const int MAX_VOICES = 64;
const int MAX_UNISON = 16;
const int DEFAULT_POLYLIMIT = 16;

// I/O
const int N_OUTPUTS = 2;
const int N_INPUTS = 2;

// Delay line sizes
const int MAX_FB_COMB = 2048;  // Must be 2^n
const int MAX_FB_COMB_EXTENDED = 2048 * 64;  // Combulator only

// Interpolation
const int FIRipol_M = 256;
const int FIRipol_M_bits = 8;
const int FIRipol_N = 12;
const int FIRoffset = FIRipol_N >> 1;
const int FIRipolI16_N = 8;
const int FIRoffsetI16 = FIRipolI16_N >> 1;

// OSC (Open Sound Control)
const int DEFAULT_OSC_PORT_IN = 53280;
const int DEFAULT_OSC_PORT_OUT = 53281;
const std::string DEFAULT_OSC_IPADDR_OUT = "127.0.0.1";

// String length
const int NAMECHARS = 64;
```

### From SurgeStorage.h

**File:** `/home/user/surge/src/common/SurgeStorage.h`

```cpp
// Patch structure
const int n_oscs = 3;                    // Oscillators per scene
const int n_lfos_voice = 6;              // Voice LFOs per scene
const int n_lfos_scene = 6;              // Scene LFOs per scene
const int n_lfos = n_lfos_voice + n_lfos_scene;  // 12 total
const int max_lfo_indices = 8;
const int n_osc_params = 7;              // Parameters per oscillator
const int n_egs = 2;                     // Envelopes per scene (Filter, Amp)

// Effects
const int n_fx_params = 12;              // Parameters per effect
const int n_fx_slots = 16;               // Total effect slots
const int n_fx_chains = 4;               // Effect chains (Scene A, Scene B, Global, Send)
const int n_fx_per_chain = 4;            // Effects per chain
const int n_send_slots = 4;              // Send effect slots

// Parameters
const int n_scene_params = 273;          // Parameters per scene
const int n_global_params = 11 + n_fx_slots * (n_fx_params + 1);
const int n_global_postparams = 1;
const int n_total_params = n_global_params + 2 * n_scene_params + n_global_postparams;

// Scenes and filters
const int n_scenes = 2;                  // Scene A and B
const int n_filterunits_per_scene = 2;   // Filter 1 and 2
const int n_max_filter_subtypes = 16;

// File format
const int ff_revision = 28;              // Current patch format revision
```

### Oscillator Buffer

```cpp
static constexpr size_t oscillator_buffer_size = 16 * 1024;  // 16KB per oscillator
```

---

## Enums

### Oscillator Types

**File:** `/home/user/surge/src/common/SurgeStorage.h` (line 279)

```cpp
enum osc_type
{
    ot_classic = 0,    // Classic virtual analog
    ot_sine,           // Sine with feedback/distortion
    ot_wavetable,      // Wavetable oscillator
    ot_shnoise,        // Sample & Hold noise
    ot_audioinput,     // Audio input
    ot_FM3,            // 3-operator FM
    ot_FM2,            // 2-operator FM
    ot_window,         // Windowed wavetable
    ot_modern,         // Modern aliasing-reduced
    ot_string,         // String physical model
    ot_twist,          // Braids-based oscillator
    ot_alias,          // Aliasing oscillator

    n_osc_types,       // = 12
};

const char osc_type_names[n_osc_types][24] = {
    "Classic", "Sine", "Wavetable", "S&H Noise",
    "Audio Input", "FM3", "FM2", "Window",
    "Modern", "String", "Twist", "Alias"
};
```

### Effect Types

**File:** `/home/user/surge/src/common/SurgeStorage.h` (line 398)

```cpp
enum fx_type
{
    fxt_off = 0,           // No effect
    fxt_delay,             // Delay
    fxt_reverb,            // Reverb 1
    fxt_phaser,            // Phaser
    fxt_rotaryspeaker,     // Rotary Speaker
    fxt_distortion,        // Distortion
    fxt_eq,                // EQ
    fxt_freqshift,         // Frequency Shifter
    fxt_conditioner,       // Conditioner
    fxt_chorus4,           // Chorus
    fxt_vocoder,           // Vocoder
    fxt_reverb2,           // Reverb 2
    fxt_flanger,           // Flanger
    fxt_ringmod,           // Ring Modulator
    fxt_airwindows,        // Airwindows (100+ effects)
    fxt_neuron,            // Neuron
    fxt_geq11,             // Graphic EQ (11-band)
    fxt_resonator,         // Resonator
    fxt_chow,              // CHOW
    fxt_exciter,           // Exciter
    fxt_ensemble,          // Ensemble
    fxt_combulator,        // Combulator
    fxt_nimbus,            // Nimbus (granular)
    fxt_tape,              // Tape
    fxt_treemonster,       // Treemonster
    fxt_waveshaper,        // Waveshaper
    fxt_mstool,            // Mid-Side Tool
    fxt_spring_reverb,     // Spring Reverb
    fxt_bonsai,            // Bonsai
    fxt_audio_input,       // Audio Input
    fxt_floaty_delay,      // Floaty Delay

    n_fx_types,            // = 31
};
```

### Scene Modes

**File:** `/home/user/surge/src/common/SurgeStorage.h` (line 158)

```cpp
enum scene_mode
{
    sm_single = 0,     // Single scene
    sm_split,          // Key split
    sm_dual,           // Dual (layer)
    sm_chsplit,        // Channel split

    n_scene_modes,     // = 4
};

const char scene_mode_names[n_scene_modes][16] = {
    "Single", "Key Split", "Dual", "Channel Split"
};
```

### Play Modes

**File:** `/home/user/surge/src/common/SurgeStorage.h` (line 175)

```cpp
enum play_mode
{
    pm_poly = 0,       // Polyphonic
    pm_mono,           // Mono
    pm_mono_st,        // Mono (Single Trigger)
    pm_mono_fp,        // Mono (Fingered Portamento)
    pm_mono_st_fp,     // Mono (Single Trigger & Fingered Portamento)
    pm_latch,          // Latch (Monophonic)

    n_play_modes,      // = 6
};
```

### Filter Configuration

**File:** `/home/user/surge/src/common/SurgeStorage.h` (line 494)

```cpp
enum filter_config
{
    fc_serial1,        // Serial 1
    fc_serial2,        // Serial 2
    fc_serial3,        // Serial 3
    fc_dual1,          // Dual 1 (parallel)
    fc_dual2,          // Dual 2 (parallel)
    fc_stereo,         // Stereo
    fc_ring,           // Ring
    fc_wide,           // Wide

    n_filter_configs,  // = 8
};
```

### FM Routing

**File:** `/home/user/surge/src/common/SurgeStorage.h` (line 515)

```cpp
enum fm_routing
{
    fm_off = 0,        // Off
    fm_2to1,           // 2 > 1
    fm_3to2to1,        // 3 > 2 > 1
    fm_2and3to1,       // 2 > 1 < 3

    n_fm_routings,     // = 4
};
```

### LFO Types

**File:** `/home/user/surge/src/common/SurgeStorage.h` (line 532)

```cpp
enum lfo_type
{
    lt_sine = 0,       // Sine
    lt_tri,            // Triangle
    lt_square,         // Square
    lt_ramp,           // Sawtooth
    lt_noise,          // Noise
    lt_snh,            // Sample & Hold
    lt_envelope,       // Envelope
    lt_stepseq,        // Step Sequencer
    lt_mseg,           // MSEG
    lt_formula,        // Formula

    n_lfo_types,       // = 10
};
```

### Envelope Modes

**File:** `/home/user/surge/src/common/SurgeStorage.h` (line 571)

```cpp
enum env_mode
{
    emt_digital = 0,   // Digital
    emt_analog,        // Analog

    n_env_modes,       // = 2
};
```

### Portamento Curve

**File:** `/home/user/surge/src/common/SurgeStorage.h` (line 195)

```cpp
enum porta_curve
{
    porta_log = -1,    // Logarithmic
    porta_lin = 0,     // Linear
    porta_exp = 1,     // Exponential
};
```

---

## Type System

### Value Types

**File:** `/home/user/surge/src/common/Parameter.h` (line 42)

```cpp
enum valtypes
{
    vt_int = 0,        // Integer
    vt_bool,           // Boolean
    vt_float,          // Float
};
```

### Control Types

**File:** `/home/user/surge/src/common/Parameter.h` (line 49)

Complete list of all 220 control types that define parameter behavior and display:

```cpp
enum ctrltypes
{
    ct_none,

    // Percentage types
    ct_percent,
    ct_percent_deactivatable,
    ct_percent_with_string_deform_hook,
    ct_dly_fb_clippingmodes,
    ct_percent_bipolar,
    ct_percent_bipolar_deactivatable,
    ct_percent_bipolar_stereo,
    ct_percent_bipolar_stringbal,
    ct_percent_bipolar_with_string_filter_hook,
    ct_percent_bipolar_w_dynamic_unipolar_formatting,
    ct_percent_with_extend_to_bipolar,
    ct_percent_with_extend_to_bipolar_static_default,
    ct_percent200,
    ct_percent_oscdrift,

    // Special percentage types
    ct_noise_color,
    ct_twist_aux_mix,

    // Pitch types
    ct_pitch_octave,
    ct_pitch_semi7bp,
    ct_pitch_semi7bp_absolutable,
    ct_pitch,
    ct_pitch_extendable_very_low_minval,
    ct_pitch4oct,
    ct_syncpitch,
    ct_fmratio,
    ct_fmratio_int,
    ct_pbdepth,

    // Amplitude and level types
    ct_amplitude,
    ct_amplitude_clipper,
    ct_amplitude_ringmod,
    ct_sendlevel,

    // Decibel types
    ct_decibel,
    ct_decibel_narrow,
    ct_decibel_narrow_extendable,
    ct_decibel_narrow_short_extendable,
    ct_decibel_narrow_deactivatable,
    ct_decibel_extra_narrow,
    ct_decibel_extra_narrow_deactivatable,
    ct_decibel_attenuation,
    ct_decibel_attenuation_clipper,
    ct_decibel_attenuation_large,
    ct_decibel_attenuation_plus12,
    ct_decibel_fmdepth,
    ct_decibel_extendable,
    ct_decibel_deactivatable,

    // Frequency types
    ct_freq_audible,
    ct_freq_audible_deactivatable,
    ct_freq_audible_deactivatable_hp,
    ct_freq_audible_deactivatable_lp,
    ct_freq_audible_with_tunability,
    ct_freq_audible_very_low_minval,
    ct_freq_audible_fm3_extendable,
    ct_freq_mod,
    ct_freq_hpf,
    ct_freq_shift,
    ct_freq_fm2_offset,
    ct_freq_vocoder_low,
    ct_freq_vocoder_high,
    ct_freq_ringmod,
    ct_freq_reson_band1,
    ct_freq_reson_band2,
    ct_freq_reson_band3,
    ct_bandwidth,

    // Time types
    ct_envtime,
    ct_envtime_deformable,
    ct_envtime_deactivatable,
    ct_envtime_lfodecay,
    ct_envtime_linkable_delay,
    ct_delaymodtime,
    ct_reverbtime,
    ct_reverbpredelaytime,
    ct_portatime,
    ct_chorusmodtime,
    ct_comp_attack_ms,
    ct_comp_release_ms,

    // Envelope shape
    ct_envshape,
    ct_envshape_attack,
    ct_envmode,

    // LFO types
    ct_lforate,
    ct_lforate_deactivatable,
    ct_lfodeform,
    ct_lfotype,
    ct_lfotrigmode,
    ct_lfoamplitude,
    ct_lfophaseshuffle,

    // Detuning
    ct_detuning,

    // Discrete selector types
    ct_osctype,
    ct_fxtype,
    ct_fxbypass,
    ct_fbconfig,
    ct_fmconfig,
    ct_filtertype,
    ct_filtersubtype,
    ct_wstype,
    ct_wt2window,
    ct_envmode,

    // Oscillator specific
    ct_osccount,
    ct_oscspread,
    ct_oscspread_bipolar,
    ct_oscroute,
    ct_osc_feedback,
    ct_osc_feedback_negative,

    // Scene and play modes
    ct_scenemode,
    ct_scenesel,
    ct_polymode,
    ct_polylimit,

    // MIDI
    ct_midikey,
    ct_midikey_or_channel,

    // Boolean types
    ct_bool,
    ct_bool_relative_switch,
    ct_bool_link_switch,
    ct_bool_keytrack,
    ct_bool_retrigger,
    ct_bool_unipolar,
    ct_bool_mute,
    ct_bool_solo,

    // Special parameter types
    ct_character,
    ct_sineoscmode,
    ct_ringmod_sineoscmode,
    ct_sinefmlegacy,
    ct_countedset_percent,
    ct_countedset_percent_extendable,
    ct_countedset_percent_extendable_wtdeform,
    ct_stereowidth,

    // Filter specific
    ct_filter_feedback,

    // Reverb
    ct_reverbshape,

    // Effect specific - Vocoder
    ct_vocoder_bandcount,
    ct_vocoder_modulator_mode,

    // Effect specific - Distortion
    ct_distortion_waveshape,

    // Effect specific - Flanger
    ct_flangerpitch,
    ct_flangermode,
    ct_flangervoices,
    ct_flangerspacing,

    // Effect specific - Phaser
    ct_phaser_stages,
    ct_phaser_spread,

    // Effect specific - Rotary
    ct_rotarydrive,

    // Effect specific - FX LFO
    ct_fxlfowave,

    // Effect specific - Airwindows
    ct_airwindows_fx,
    ct_airwindows_param,
    ct_airwindows_param_bipolar,
    ct_airwindows_param_integral,

    // Effect specific - Resonator
    ct_reson_mode,
    ct_reson_res_extendable,

    // Effect specific - CHOW
    ct_chow_ratio,

    // Effect specific - Nimbus
    ct_nimbusmode,
    ct_nimbusquality,

    // Effect specific - Ensemble
    ct_ensemble_lforate,
    ct_ensemble_stages,
    ct_ensemble_clockrate,

    // Effect specific - String
    ct_stringosc_excitation_model,

    // Effect specific - Twist
    ct_twist_engine,

    // Effect specific - Alias
    ct_alias_wave,
    ct_alias_mask,
    ct_alias_bits,

    // Effect specific - Tape
    ct_tape_drive,
    ct_tape_microns,
    ct_tape_speed,

    // Effect specific - MS Tool
    ct_mscodec,

    // Effect specific - Spring Reverb
    ct_spring_decay,

    // Effect specific - Bonsai
    ct_bonsai_bass_boost,
    ct_bonsai_sat_filter,
    ct_bonsai_sat_mode,
    ct_bonsai_noise_mode,

    // Effect specific - Floaty Delay
    ct_floaty_warp_time,
    ct_floaty_delay_time,
    ct_floaty_delay_playrate,

    // Ring modulator
    ct_modern_trimix,

    // Miscellaneous
    ct_float_toggle,

    num_ctrltypes,     // = 219
};
```

### Control Groups

**File:** `/home/user/surge/src/common/Parameter.h` (line 228)

```cpp
enum ControlGroup
{
    cg_GLOBAL = 0,
    cg_OSC = 2,
    cg_MIX = 3,
    cg_FILTER = 4,
    cg_ENV = 5,
    cg_LFO = 6,
    cg_FX = 7,
    endCG
};

const char ControlGroupDisplay[endCG][32] = {
    "Global", "", "Oscillators", "Mixer",
    "Filters", "Envelopes", "Modulators", "FX"
};
```

---

## Utility Functions

### DSPUtils.h

**File:** `/home/user/surge/src/common/dsp/utilities/DSPUtils.h`

#### Range Checking

```cpp
inline bool within_range(int lo, int value, int hi)
{
    return ((value >= lo) && (value <= hi));
}
```

#### Amplitude Conversions

```cpp
// Internal gain representation (x^3)
inline float amp_to_linear(float x)
{
    x = std::max(0.f, x);
    return x * x * x;
}

inline float linear_to_amp(float x)
{
    return powf(std::clamp(x, 0.0000000001f, 1.f), 1.f / 3.f);
}
```

#### Decibel Conversions

```cpp
// Amplitude to dB (range: -192 to +96 dB)
inline float amp_to_db(float x)
{
    return std::clamp((float)(18.f * log2(x)), -192.f, 96.f);
}

// dB to amplitude
inline float db_to_amp(float x)
{
    return std::clamp(powf(2.f, x / 18.f), 0.f, 2.f);
}
```

#### Linear Interpolation

```cpp
// SIMD-optimized linear interpolation
template <typename T, bool first = true>
using lipol = sst::basic_blocks::dsp::lipol<T, BLOCK_SIZE, first>;
```

### Oscillator Utility Functions

**File:** `/home/user/surge/src/common/dsp/oscillators/OscillatorBase.h`

#### Pitch to Frequency Conversions

```cpp
class Oscillator
{
    // Convert MIDI pitch to angular frequency (radians/sample)
    inline double pitch_to_omega(float x)
    {
        return (2.0 * M_PI * Tunings::MIDI_0_FREQ *
                storage->note_to_pitch(x) * storage->dsamplerate_os_inv);
    }

    // Convert MIDI pitch to phase increment
    inline double pitch_to_dphase(float x)
    {
        return (double)(Tunings::MIDI_0_FREQ * storage->note_to_pitch(x) *
                       storage->dsamplerate_os_inv);
    }

    // With absolute frequency offset (Hz)
    inline double pitch_to_dphase_with_absolute_offset(float x, float off)
    {
        return (double)(std::max(1.0, Tunings::MIDI_0_FREQ *
                       storage->note_to_pitch(x) + off) *
                       storage->dsamplerate_os_inv);
    }
};
```

Note: `Tunings::MIDI_0_FREQ` = 8.17579891564 Hz (MIDI note 0 = C-1)

### Common DSP Patterns

#### Block Processing Loop

```cpp
for (int k = 0; k < BLOCK_SIZE_OS; k++)
{
    // Process sample
    output[k] = process_sample();
}
```

#### SIMD Processing (SSE/NEON)

```cpp
for (int k = 0; k < BLOCK_SIZE_OS_QUAD; k++)
{
    // Process 4 samples at once using SIMD
    __m128 result = _mm_mul_ps(input, gain);
    _mm_store_ps(&output[k << 2], result);
}
```

---

## Module Interface

### Implementing an Oscillator

To create a new oscillator, inherit from `Oscillator` base class:

#### 1. Header File

```cpp
// MyOscillator.h
#include "OscillatorBase.h"

class MyOscillator : public Oscillator
{
public:
    MyOscillator(SurgeStorage *storage, OscillatorStorage *oscdata,
                 pdata *localcopy);

    // Required overrides
    virtual void init(float pitch, bool is_display = false,
                     bool nonzero_init_drift = true) override;
    virtual void init_ctrltypes() override;
    virtual void init_default_values() override;
    virtual void process_block(float pitch, float drift = 0.f,
                              bool stereo = false, bool FM = false,
                              float FMdepth = 0.f) override;

private:
    // Oscillator state
    double phase;
    float lastoutput;
};
```

#### 2. Implementation

```cpp
// MyOscillator.cpp
MyOscillator::MyOscillator(SurgeStorage *storage,
                           OscillatorStorage *oscdata,
                           pdata *localcopy)
    : Oscillator(storage, oscdata, localcopy)
{
}

void MyOscillator::init(float pitch, bool is_display,
                        bool nonzero_init_drift)
{
    phase = 0.0;
    lastoutput = 0.f;
}

void MyOscillator::init_ctrltypes()
{
    // Set parameter types (ct_* from Parameter.h)
    oscdata->p[0].set_name("Parameter 1");
    oscdata->p[0].set_type(ct_percent);

    oscdata->p[1].set_name("Parameter 2");
    oscdata->p[1].set_type(ct_freq_audible);

    // ... up to n_osc_params (7)
}

void MyOscillator::init_default_values()
{
    // Set default values
    oscdata->p[0].val.f = 0.5f;
    oscdata->p[1].val.f = 0.0f;
}

void MyOscillator::process_block(float pitch, float drift,
                                 bool stereo, bool FM,
                                 float FMdepth)
{
    double omega = pitch_to_omega(pitch);

    for (int k = 0; k < BLOCK_SIZE_OS; k++)
    {
        // Apply FM if enabled
        if (FM)
            phase += omega + FMdepth * master_osc[k];
        else
            phase += omega;

        // Wrap phase
        if (phase > M_PI)
            phase -= 2.0 * M_PI;

        // Generate output
        output[k] = sin(phase);

        // For stereo, fill outputR
        if (stereo)
            outputR[k] = output[k];
    }
}
```

#### 3. Register in Factory

Add to `/home/user/surge/src/common/dsp/Oscillator.cpp`:

```cpp
Oscillator *spawn_osc(int osctype, SurgeStorage *storage,
                     OscillatorStorage *oscdata, pdata *localcopy,
                     pdata *localcopyUnmod, unsigned char *onto)
{
    switch (osctype)
    {
        // ... existing cases ...
        case ot_myoscillator:
            return new (onto) MyOscillator(storage, oscdata, localcopy);
    }
}
```

Add enum to `SurgeStorage.h`:

```cpp
enum osc_type
{
    // ... existing types ...
    ot_myoscillator,
    n_osc_types,
};
```

### Implementing a Filter

Filters use the SST-Filters library. See `/home/user/surge/libs/sst/sst-filters/` for details.

### Implementing an Effect

To create a new effect, inherit from `Effect` base class:

#### 1. Header File

```cpp
// MyEffect.h
#include "Effect.h"

class MyEffect : public Effect
{
public:
    MyEffect(SurgeStorage *storage, FxStorage *fxdata, pdata *pd);
    virtual ~MyEffect();

    // Required overrides
    virtual const char *get_effectname() override { return "My Effect"; }
    virtual void init() override;
    virtual void init_ctrltypes() override;
    virtual void init_default_values() override;
    virtual void process(float *dataL, float *dataR) override;

    // Optional overrides
    virtual void suspend() override;
    virtual int get_ringout_decay() override { return 1000; }  // Blocks

private:
    // Effect state
    float buffer[2][BLOCK_SIZE];
    lag<float, true> mix;
};
```

#### 2. Implementation

```cpp
// MyEffect.cpp
MyEffect::MyEffect(SurgeStorage *storage, FxStorage *fxdata,
                   pdata *pd)
    : Effect(storage, fxdata, pd)
{
}

void MyEffect::init()
{
    // Initialize state
    memset(buffer, 0, sizeof(buffer));
    mix.newValue(1.0f);
}

void MyEffect::init_ctrltypes()
{
    // Effect has 12 parameters (n_fx_params)
    fxdata->p[0].set_name("Mix");
    fxdata->p[0].set_type(ct_percent);

    fxdata->p[1].set_name("Depth");
    fxdata->p[1].set_type(ct_percent);

    // Parameters 2-11 available
    for (int i = 2; i < n_fx_params; i++)
    {
        fxdata->p[i].set_type(ct_none);
    }
}

void MyEffect::init_default_values()
{
    fxdata->p[0].val.f = 1.0f;  // Mix
    fxdata->p[1].val.f = 0.5f;  // Depth
}

void MyEffect::process(float *dataL, float *dataR)
{
    // Get parameter values
    float mixval = *pd_float[0];  // Mix
    float depth = *pd_float[1];   // Depth

    mix.newValue(mixval);

    for (int k = 0; k < BLOCK_SIZE; k++)
    {
        // Process left channel
        float wetL = dataL[k] * depth;
        dataL[k] = mix.v * wetL + (1.0f - mix.v) * dataL[k];

        // Process right channel
        float wetR = dataR[k] * depth;
        dataR[k] = mix.v * wetR + (1.0f - mix.v) * dataR[k];

        mix.process();
    }
}

void MyEffect::suspend()
{
    // Clear state when bypassed
    init();
}
```

#### 3. Register in Factory

Add to effect factory and enum in `SurgeStorage.h`.

### Parameter Access in Modules

#### In Oscillators

```cpp
// Parameter values (with modulation)
float param0 = localcopy[oscdata->p[0].param_id_in_scene].f;
float param1 = localcopy[oscdata->p[1].param_id_in_scene].f;
```

#### In Effects

```cpp
// Direct parameter access
float param0 = *pd_float[0];
int param1 = *pd_int[1];
bool param2 = *pd_bool[2];
```

---

## Quick Reference Tables

### Common Sizes

| Constant | Value | Description |
|----------|-------|-------------|
| `BLOCK_SIZE` | 32 | Audio processing block size |
| `BLOCK_SIZE_OS` | 64 | Oversampled block size |
| `MAX_VOICES` | 64 | Maximum polyphony |
| `MAX_UNISON` | 16 | Maximum unison voices |
| `n_oscs` | 3 | Oscillators per scene |
| `n_lfos` | 12 | LFOs per scene (6 voice + 6 scene) |
| `n_fx_slots` | 16 | Total effect slots |
| `n_scenes` | 2 | Number of scenes (A/B) |

### File Locations Quick Index

| Component | Header File |
|-----------|------------|
| Main engine | `/home/user/surge/src/common/SurgeSynthesizer.h` |
| Storage | `/home/user/surge/src/common/SurgeStorage.h` |
| Parameters | `/home/user/surge/src/common/Parameter.h` |
| Voice | `/home/user/surge/src/common/dsp/SurgeVoice.h` |
| Oscillator base | `/home/user/surge/src/common/dsp/oscillators/OscillatorBase.h` |
| Effect base | `/home/user/surge/src/common/dsp/Effect.h` |
| DSP utilities | `/home/user/surge/src/common/dsp/utilities/DSPUtils.h` |
| Constants | `/home/user/surge/src/common/globals.h` |
| Filter config | `/home/user/surge/src/common/FilterConfiguration.h` |

---

## Additional Resources

- **Main Documentation:** `/home/user/surge/docs/`
- **Encyclopedic Guide Index:** `/home/user/surge/docs/encyclopedic-guide/00-INDEX.md`
- **Architecture Overview:** `/home/user/surge/docs/encyclopedic-guide/01-architecture-overview.md`
- **SST Libraries:** `/home/user/surge/libs/sst/`
- **GitHub:** https://github.com/surge-synthesizer/surge
- **Website:** https://surge-synthesizer.github.io/

---

*Last updated: 2025-11-17*
*Surge XT version: 1.4+ (streaming revision 28)*
