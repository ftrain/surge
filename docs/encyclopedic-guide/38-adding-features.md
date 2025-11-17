# Chapter 38: Adding Features to Surge

## Introduction

This chapter provides a practical guide for developers who want to extend Surge XT by adding new oscillators, filters, and effects. Surge's architecture is designed to be extensible, with clear patterns for adding new DSP components. This guide walks through the complete process, from understanding the code structure to submitting a pull request.

Whether you're adding a new oscillator type, implementing a novel filter design, or creating a unique effect, you'll follow similar patterns: create the DSP implementation, register the component with the system, define parameters, and integrate with the UI. This chapter provides concrete examples and step-by-step instructions for each component type.

## Adding an Oscillator

Oscillators are the primary sound sources in Surge. The architecture supports multiple oscillator types, from classic analog-style waveforms to complex digital synthesis algorithms.

### Oscillator Architecture Overview

All oscillators inherit from the `Oscillator` base class defined in `/home/user/surge/src/common/dsp/oscillators/OscillatorBase.h`:

```cpp
class alignas(16) Oscillator
{
  public:
    float output alignas(16)[BLOCK_SIZE_OS];
    float outputR alignas(16)[BLOCK_SIZE_OS];

    Oscillator(SurgeStorage *storage, OscillatorStorage *oscdata, pdata *localcopy);
    virtual ~Oscillator();
    virtual void init(float pitch, bool is_display = false, bool nonzero_init_drift = true){};
    virtual void init_ctrltypes(int scene, int oscnum) { init_ctrltypes(); };
    virtual void init_ctrltypes(){};
    virtual void init_default_values(){};
    virtual void process_block(float pitch, float drift = 0.f, bool stereo = false,
                               bool FM = false, float FMdepth = 0.f) {}

  protected:
    SurgeStorage *storage;
    OscillatorStorage *oscdata;
    pdata *localcopy;
    float *__restrict master_osc;
};
```

Key points:
- **Memory alignment**: Output buffers must be 16-byte aligned for SIMD operations
- **Block processing**: Oscillators generate `BLOCK_SIZE_OS` samples at once (default: 64 samples with 2x oversampling)
- **Parameter system**: Parameters are defined through `init_ctrltypes()` and `init_default_values()`
- **Stereo support**: Both mono and stereo output are supported

### Step-by-Step: Adding a New Oscillator

Let's walk through adding a hypothetical "Phase Distortion" oscillator as an example.

#### 1. Create the Header and Implementation Files

Create two files in `/home/user/surge/src/common/dsp/oscillators/`:
- `PhaseDistortionOscillator.h`
- `PhaseDistortionOscillator.cpp`

**PhaseDistortionOscillator.h:**

```cpp
#ifndef SURGE_SRC_COMMON_DSP_OSCILLATORS_PHASEDISTORTIONOSCILLATOR_H
#define SURGE_SRC_COMMON_DSP_OSCILLATORS_PHASEDISTORTIONOSCILLATOR_H

#include "OscillatorBase.h"
#include "DSPUtils.h"

class PhaseDistortionOscillator : public Oscillator
{
  public:
    enum pd_params
    {
        pd_shape,          // Shape parameter
        pd_distortion,     // Distortion amount
        pd_feedback,       // Feedback amount
        pd_unison_detune,
        pd_unison_voices,
    };

    PhaseDistortionOscillator(SurgeStorage *storage, OscillatorStorage *oscdata,
                              pdata *localcopy);
    virtual ~PhaseDistortionOscillator();

    virtual void init(float pitch, bool is_display = false,
                      bool nonzero_init_drift = true) override;
    virtual void process_block(float pitch, float drift = 0.f, bool stereo = false,
                               bool FM = false, float FMdepth = 0.f) override;
    virtual void init_ctrltypes() override;
    virtual void init_default_values() override;

  private:
    double phase[MAX_UNISON];
    float fb_val;
    int n_unison;
    float out_attenuation;
    float panL[MAX_UNISON], panR[MAX_UNISON];

    void prepare_unison(int voices);
};

#endif
```

**PhaseDistortionOscillator.cpp:**

```cpp
#include "PhaseDistortionOscillator.h"
#include <cmath>

PhaseDistortionOscillator::PhaseDistortionOscillator(SurgeStorage *storage,
                                                      OscillatorStorage *oscdata,
                                                      pdata *localcopy)
    : Oscillator(storage, oscdata, localcopy)
{
}

PhaseDistortionOscillator::~PhaseDistortionOscillator() {}

void PhaseDistortionOscillator::init(float pitch, bool is_display, bool nonzero_init_drift)
{
    n_unison = limit_range(oscdata->p[pd_unison_voices].val.i, 1, MAX_UNISON);

    if (is_display)
    {
        n_unison = 1;
    }

    prepare_unison(n_unison);

    for (int i = 0; i < n_unison; i++)
    {
        phase[i] = (oscdata->retrigger.val.b || is_display)
                   ? 0.0
                   : 2.0 * M_PI * storage->rand_01();
    }

    fb_val = 0.f;
}

void PhaseDistortionOscillator::prepare_unison(int voices)
{
    auto us = Surge::Oscillator::UnisonSetup<float>(voices);
    out_attenuation = 1.0f / us.attenuation_inv();

    for (int v = 0; v < voices; ++v)
    {
        us.panLaw(v, panL[v], panR[v]);
    }
}

void PhaseDistortionOscillator::process_block(float pitch, float drift, bool stereo,
                                               bool FM, float FMdepth)
{
    // Calculate frequency
    double omega = pitch_to_omega(pitch);

    // Get parameter values
    float shape = localcopy[oscdata->p[pd_shape].param_id_in_scene].f;
    float distortion = localcopy[oscdata->p[pd_distortion].param_id_in_scene].f;
    float feedback = localcopy[oscdata->p[pd_feedback].param_id_in_scene].f;

    // Process each sample in the block
    for (int k = 0; k < BLOCK_SIZE_OS; k++)
    {
        output[k] = 0.f;
        outputR[k] = 0.f;

        // Process each unison voice
        for (int u = 0; u < n_unison; u++)
        {
            // Apply feedback
            double p = phase[u] + feedback * fb_val;

            // Phase distortion algorithm
            double distorted_phase = p + distortion * std::sin(p * shape);

            // Generate output
            float sample = std::sin(distorted_phase);

            // Accumulate with pan law
            output[k] += sample * panL[u];
            if (stereo)
                outputR[k] += sample * panR[u];

            // Store for feedback
            if (u == 0)
                fb_val = sample;

            // Advance phase
            phase[u] += omega;
            if (phase[u] > 2.0 * M_PI)
                phase[u] -= 2.0 * M_PI;
        }

        // Apply unison attenuation
        output[k] *= out_attenuation;
        if (stereo)
            outputR[k] *= out_attenuation;
    }
}

void PhaseDistortionOscillator::init_ctrltypes()
{
    oscdata->p[pd_shape].set_name("Shape");
    oscdata->p[pd_shape].set_type(ct_percent);

    oscdata->p[pd_distortion].set_name("Distortion");
    oscdata->p[pd_distortion].set_type(ct_percent);

    oscdata->p[pd_feedback].set_name("Feedback");
    oscdata->p[pd_feedback].set_type(ct_osc_feedback);

    oscdata->p[pd_unison_detune].set_name("Unison Detune");
    oscdata->p[pd_unison_detune].set_type(ct_oscspread);

    oscdata->p[pd_unison_voices].set_name("Unison Voices");
    oscdata->p[pd_unison_voices].set_type(ct_osccount);
}

void PhaseDistortionOscillator::init_default_values()
{
    oscdata->p[pd_shape].val.f = 0.5f;
    oscdata->p[pd_distortion].val.f = 0.5f;
    oscdata->p[pd_feedback].val.f = 0.0f;
    oscdata->p[pd_unison_detune].val.f = 0.1f;
    oscdata->p[pd_unison_voices].val.i = 1;
}
```

#### 2. Register in SurgeStorage.h

Add your oscillator to the `osc_type` enum in `/home/user/surge/src/common/SurgeStorage.h`:

```cpp
enum osc_type
{
    ot_classic = 0,
    ot_sine,
    ot_wavetable,
    ot_shnoise,
    ot_audioinput,
    ot_FM3,
    ot_FM2,
    ot_window,
    ot_modern,
    ot_string,
    ot_twist,
    ot_alias,
    ot_phasedist,  // Add your oscillator here

    n_osc_types,
};
```

**Important**: Add new oscillator types at the end before `n_osc_types` to maintain backward compatibility with existing patches.

#### 3. Register in Oscillator.cpp

In `/home/user/surge/src/common/dsp/Oscillator.cpp`, add the include and spawn case:

**Add include at top:**
```cpp
#include "PhaseDistortionOscillator.h"
```

**Add to spawn_osc() function:**
```cpp
Oscillator *spawn_osc(int osctype, SurgeStorage *storage, OscillatorStorage *oscdata,
                      pdata *localcopy, pdata *localcopyUnmod, unsigned char *onto)
{
    // ... existing size checks ...

    Oscillator *osc = 0;
    switch (osctype)
    {
    case ot_classic:
        return new (onto) ClassicOscillator(storage, oscdata, localcopy);
    // ... other cases ...
    case ot_phasedist:
        return new (onto) PhaseDistortionOscillator(storage, oscdata, localcopy);
    case ot_sine:
    default:
        return new (onto) SineOscillator(storage, oscdata, localcopy);
    }
}
```

Also add the size check:
```cpp
S(PhaseDistortionOscillator);
```

#### 4. Add to CMakeLists.txt

In `/home/user/surge/src/common/CMakeLists.txt`, add your files in alphabetical order:

```cmake
add_library(${PROJECT_NAME}
  # ... existing files ...
  dsp/oscillators/PhaseDistortionOscillator.cpp
  dsp/oscillators/PhaseDistortionOscillator.h
  # ... more files ...
)
```

#### 5. Add to configuration.xml

In `/home/user/surge/resources/surge-shared/configuration.xml`, add your oscillator to the `<osc>` section:

```xml
<osc>
  <!-- ... existing oscillators ... -->
  <type i="12" name="Phase Distortion" retrigger="1" p5_extend_range="0">
    <snapshot name="Init" p0="0.5" p1="0.5" p2="0.0" p3="0.1" p4="1" retrigger="1"/>
  </type>
</osc>
```

The `i` value corresponds to the enum value (ot_phasedist = 12 in our example).

#### 6. Build and Test

```bash
cd /home/user/surge
cmake --build build --config Release
```

Test your oscillator:
1. Launch Surge XT
2. Select your new oscillator from the oscillator type menu
3. Play notes and adjust parameters
4. Check for audio artifacts, CPU usage, and parameter behavior

### Oscillator Best Practices

**Performance Considerations:**
- Use SIMD operations where possible for unison processing
- Avoid branches inside the sample loop
- Use template specialization for mode switching
- Pre-calculate values outside the sample loop

**Parameter Design:**
- Use appropriate control types (ct_percent, ct_freq_audible, etc.)
- Provide sensible default values
- Consider extended range parameters for advanced users
- Document parameter interactions

**Unison Support:**
- Use `UnisonSetup` helper for proper voice spreading
- Apply correct pan laws for stereo width
- Calculate proper attenuation based on voice count
- Support up to MAX_UNISON voices

**Display Mode:**
- Ensure `is_display` mode works correctly (single voice, deterministic)
- Display rendering should be efficient for real-time waveform updates

## Adding a Filter

Filters in Surge are integrated into the `QuadFilterChain`, which processes up to 4 voices in parallel using SIMD instructions. The filter system is highly optimized for performance.

### Filter Architecture Overview

Surge's filter architecture separates coefficient calculation from processing:
- **Coefficient calculation** (`makeCoefficients()`): Called when parameters change
- **Processing** (`process()`): Called every audio block, uses pre-calculated coefficients

This separation allows expensive calculations to happen infrequently while maintaining efficient audio processing.

### Step-by-Step: Adding a New Filter

Based on `/home/user/surge/doc/Adding a Filter.md`, here's the complete process.

#### 1. Create Filter Implementation Files

Create `/home/user/surge/src/common/dsp/filters/MyFilter.h` and `MyFilter.cpp`. Look at existing filters for reference.

**MyFilter.h:**
```cpp
#ifndef SURGE_SRC_COMMON_DSP_FILTERS_MYFILTER_H
#define SURGE_SRC_COMMON_DSP_FILTERS_MYFILTER_H

#include "QuadFilterUnit.h"

namespace MyFilter
{
    // Calculate filter coefficients based on frequency and resonance
    void makeCoefficients(FilterCoefficientMaker *cm, float freq, float reso,
                         int type, int subtype, SurgeStorage *storage);

    // Process audio through the filter
    __m128 process(QuadFilterUnitState * __restrict f, __m128 in);
}

#endif
```

**MyFilter.cpp:**
```cpp
#include "MyFilter.h"
#include <cmath>

namespace MyFilter
{
    void makeCoefficients(FilterCoefficientMaker *cm, float freq, float reso,
                         int type, int subtype, SurgeStorage *storage)
    {
        // freq: Filter frequency in MIDI note units
        // reso: Resonance (0 to 1)
        // Coefficients are stored in cm->C[0] through cm->C[7]

        // Convert MIDI note to omega (angular frequency)
        float omega = cm->calc_omega(freq / 12.0);

        // Calculate Q from resonance
        float Q = std::max(0.5f, reso * 10.0f);

        // Example: Simple 2-pole lowpass coefficients
        float alpha = std::sin(omega) / (2.0f * Q);
        float cos_omega = std::cos(omega);

        float a0 = 1.0f + alpha;
        float b0 = (1.0f - cos_omega) / (2.0f * a0);
        float b1 = (1.0f - cos_omega) / a0;
        float b2 = b0;
        float a1 = (-2.0f * cos_omega) / a0;
        float a2 = (1.0f - alpha) / a0;

        // Store in coefficient array
        cm->C[0] = b0;
        cm->C[1] = b1;
        cm->C[2] = b2;
        cm->C[3] = a1;
        cm->C[4] = a2;

        // C[5-7] available for additional coefficients
    }

    __m128 process(QuadFilterUnitState * __restrict f, __m128 in)
    {
        // f->C[]: Coefficients (SSE vectors containing 4 values for 4 voices)
        // f->R[]: Registers for state storage (use as needed)
        // f->active[]: Which voices are active (0-3)
        // in: Input samples for 4 voices

        // Load coefficients
        __m128 b0 = f->C[0];
        __m128 b1 = f->C[1];
        __m128 b2 = f->C[2];
        __m128 a1 = f->C[3];
        __m128 a2 = f->C[4];

        // Load state (previous samples and outputs)
        __m128 x1 = f->R[0];  // Input t-1
        __m128 x2 = f->R[1];  // Input t-2
        __m128 y1 = f->R[2];  // Output t-1
        __m128 y2 = f->R[3];  // Output t-2

        // Direct Form II Biquad
        __m128 out = _mm_mul_ps(b0, in);
        out = _mm_add_ps(out, _mm_mul_ps(b1, x1));
        out = _mm_add_ps(out, _mm_mul_ps(b2, x2));
        out = _mm_sub_ps(out, _mm_mul_ps(a1, y1));
        out = _mm_sub_ps(out, _mm_mul_ps(a2, y2));

        // Update state
        f->R[1] = x1;
        f->R[0] = in;
        f->R[3] = y2;
        f->R[2] = out;

        return out;
    }
}
```

#### 2. Register in FilterConfiguration.h

In `/home/user/surge/src/common/FilterConfiguration.h`:

**Add enum value:**
```cpp
enum fu_type
{
    fut_none = 0,
    fut_lp12,
    fut_lp24,
    // ... existing types ...
    fut_myfilter,  // Add at the very end!

    n_fu_types
};
```

**Add display names:**
```cpp
const char fut_names[n_fu_types][32] = {
    "Off",
    "LP 12dB",
    // ... existing names ...
    "My Filter",  // Match your enum order
};

const char fut_menu_names[n_fu_types][32] = {
    "Off",
    "Low Pass 12dB",
    // ... existing names ...
    "My Custom Filter",
};
```

**Add subtype count:**
```cpp
const int fut_subcount[n_fu_types] = {
    0,  // fut_none
    3,  // fut_lp12 has 3 subtypes
    // ... existing counts ...
    1,  // fut_myfilter has 1 subtype
};
```

**Add to FilterSelectorMapper:**
```cpp
inline int FilterSelectorMapper(int i)
{
    switch (i)
    {
        case 0: return fut_none;
        case 1: return fut_lp12;
        // ... existing mappings ...
        case 15: return fut_myfilter;
    }
    return fut_none;
}
```

**Add glyph index:**
```cpp
const int fut_glyph_index[n_fu_types][n_max_filter_subtypes] = {
    {0, 0, 0},  // fut_none
    // ... existing glyphs ...
    {0, 0, 0},  // fut_myfilter - you may define custom glyphs
};
```

#### 3. Add Coefficient Maker in FilterCoefficientMaker.h

In `/home/user/surge/src/common/dsp/FilterCoefficientMaker.h`, find `MakeCoeffs()` and add your case:

```cpp
void FilterCoefficientMaker::MakeCoeffs()
{
    // ... existing code ...

    switch (type)
    {
        case fut_lp12:
            // ... existing cases ...
        case fut_myfilter:
            MyFilter::makeCoefficients(this, Freq, Reso, type, subtype, storage);
            break;
    }
}
```

Also add the include at the top:
```cpp
#include "filters/MyFilter.h"
```

#### 4. Add Processing Function in QuadFilterUnit.cpp

In `/home/user/surge/src/common/dsp/QuadFilterUnit.cpp`, find `GetQFPtrFilterUnit()` and add your case:

```cpp
#include "filters/MyFilter.h"

FilterUnitQFPtr GetQFPtrFilterUnit(FilterType type, FilterSubType subtype)
{
    switch (type)
    {
        // ... existing cases ...
        case fut_myfilter:
            return MyFilter::process;
    }
    return 0;
}
```

#### 5. Add Subtype Names (if applicable)

If your filter has subtypes, add string representations in `/home/user/surge/src/common/Parameter.cpp`:

```cpp
std::string get_filtersubtype_label(int type, int subtype)
{
    switch (type)
    {
        // ... existing cases ...
        case fut_myfilter:
            if (subtype == 0) return "Mode A";
            if (subtype == 1) return "Mode B";
            break;
    }
    return "";
}
```

#### 6. Add to CMakeLists.txt

```cmake
add_library(${PROJECT_NAME}
  # ... existing files ...
  dsp/filters/MyFilter.cpp
  dsp/filters/MyFilter.h
  # ... more files ...
)
```

#### 7. Build and Test

```bash
cmake --build build --config Release
```

### Filter Best Practices

**SIMD Processing:**
- All 4 SSE channels may be populated (check `f->active[]`)
- Coefficients are SSE-wide arrays
- Use SSE intrinsics for parallel processing
- See existing filters for SIMD patterns

**Coefficient Calculation:**
- Called at most once every BLOCK_SIZE_OS samples
- Only called when frequency or resonance changes
- Can do expensive calculations here
- Store results in `C[0]` through `C[7]`

**State Management:**
- Use `R[]` registers for filter state
- Each R register is an SSE vector (4 voices)
- Properly initialize state in coefficient maker
- Handle denormals appropriately

**Frequency and Resonance:**
- Frequency is in MIDI note units (use `calc_omega()` to convert)
- Resonance ranges from 0 to 1
- Consider self-oscillation at high resonance
- Ensure stability across the frequency range

## Adding an Effect

Effects in Surge process the final audio output. The effect system supports various routing configurations and parameter automation.

### Effect Architecture Overview

All effects inherit from the `Effect` base class. Key concepts:
- **Effect slots**: 8 effect slots (A1, A2, B1, B2) plus 4 send effects
- **Parameter system**: Up to 12 parameters per effect
- **Lifecycle**: Init → Process → Suspend cycle
- **Bypass**: Effects can be bypassed or disabled

### Step-by-Step: Adding a New Effect

Based on `/home/user/surge/doc/Adding an FX.md` and `/home/user/surge/doc/FX Lifecycle.md`.

#### 1. Create Effect Implementation Files

Create `/home/user/surge/src/common/dsp/effects/MyEffect.h` and `MyEffect.cpp`.

**MyEffect.h:**
```cpp
#ifndef SURGE_SRC_COMMON_DSP_EFFECTS_MYEFFECT_H
#define SURGE_SRC_COMMON_DSP_EFFECTS_MYEFFECT_H

#include "Effect.h"

class MyEffect : public Effect
{
  public:
    enum my_params
    {
        my_mix = 0,
        my_parameter1,
        my_parameter2,
        my_feedback,

        my_num_params,
    };

    MyEffect(SurgeStorage *storage, FxStorage *fxdata, pdata *pd);
    virtual ~MyEffect();

    virtual const char *get_effectname() override { return "MyEffect"; }

    virtual void init() override;
    virtual void process(float *dataL, float *dataR) override;
    virtual void suspend() override;

    virtual void init_ctrltypes() override;
    virtual void init_default_values() override;

    virtual int get_ringout_decay() override { return 500; }  // milliseconds

  private:
    // Effect state variables
    float buffer[2][max_delay_length];
    int write_pos;
    float feedback_val;

    // Parameter smoothing
    lag<float> mix;
};

#endif
```

**MyEffect.cpp:**
```cpp
#include "MyEffect.h"
#include <algorithm>

MyEffect::MyEffect(SurgeStorage *storage, FxStorage *fxdata, pdata *pd)
    : Effect(storage, fxdata, pd), mix(0.5f)
{
    write_pos = 0;
    feedback_val = 0.0f;

    // Initialize buffers
    memset(buffer, 0, sizeof(buffer));
}

MyEffect::~MyEffect() {}

void MyEffect::init()
{
    // Called when effect is enabled or patch changes
    write_pos = 0;
    feedback_val = 0.0f;
    memset(buffer, 0, sizeof(buffer));

    // Reset parameter smoothing
    mix.newValue(*pd_float[my_mix]);
    mix.instantize();
}

void MyEffect::process(float *dataL, float *dataR)
{
    // dataL and dataR contain BLOCK_SIZE samples
    // Process the audio in place

    // Get current parameter values
    float mix_amount = *pd_float[my_mix];
    float param1 = *pd_float[my_parameter1];
    float param2 = *pd_float[my_parameter2];
    float feedback = *pd_float[my_feedback];

    // Smooth mix parameter
    mix.newValue(mix_amount);

    for (int k = 0; k < BLOCK_SIZE; k++)
    {
        // Read input
        float inL = dataL[k];
        float inR = dataR[k];

        // Your DSP algorithm here
        float processedL = inL * param1 + feedback_val * feedback;
        float processedR = inR * param1 + feedback_val * feedback;

        // Apply some processing
        processedL = std::tanh(processedL * param2);
        processedR = std::tanh(processedR * param2);

        // Store for feedback
        feedback_val = (processedL + processedR) * 0.5f;

        // Mix dry/wet
        float m = mix.v;
        dataL[k] = inL * (1.0f - m) + processedL * m;
        dataR[k] = inR * (1.0f - m) + processedR * m;

        mix.process();
    }
}

void MyEffect::suspend()
{
    // Called when effect is bypassed
    // Clear state to prevent clicks when re-enabled
    init();
}

void MyEffect::init_ctrltypes()
{
    // Define parameter types and names
    fxdata->p[my_mix].set_name("Mix");
    fxdata->p[my_mix].set_type(ct_percent);
    fxdata->p[my_mix].posy_offset = 1;

    fxdata->p[my_parameter1].set_name("Parameter 1");
    fxdata->p[my_parameter1].set_type(ct_percent);
    fxdata->p[my_parameter1].posy_offset = 3;

    fxdata->p[my_parameter2].set_name("Parameter 2");
    fxdata->p[my_parameter2].set_type(ct_decibel);
    fxdata->p[my_parameter2].posy_offset = 3;

    fxdata->p[my_feedback].set_name("Feedback");
    fxdata->p[my_feedback].set_type(ct_percent_bipolar);
    fxdata->p[my_feedback].posy_offset = 5;
}

void MyEffect::init_default_values()
{
    // Set default parameter values
    fxdata->p[my_mix].val.f = 0.5f;
    fxdata->p[my_parameter1].val.f = 0.5f;
    fxdata->p[my_parameter2].val.f = 0.0f;
    fxdata->p[my_feedback].val.f = 0.0f;
}
```

#### 2. Register in Effect.cpp

In `/home/user/surge/src/common/dsp/Effect.cpp`:

**Add include:**
```cpp
#include "effects/MyEffect.h"
```

**Add spawn case:**
```cpp
Effect *spawn_effect(int id, SurgeStorage *storage, FxStorage *fxdata, pdata *pd)
{
    switch (id)
    {
        case fxt_delay:
            return new Delay(storage, fxdata, pd);
        // ... existing cases ...
        case fxt_myeffect:
            return new MyEffect(storage, fxdata, pd);
    }
    return nullptr;
}
```

#### 3. Register in SurgeStorage.h

In `/home/user/surge/src/common/SurgeStorage.h`:

**Add enum:**
```cpp
enum fx_type
{
    fxt_off = 0,
    fxt_delay,
    fxt_reverb,
    // ... existing types ...
    fxt_myeffect,

    n_fx_types,
};
```

**Add names:**
```cpp
const char fx_type_names[n_fx_types][32] = {
    "Off",
    "Delay",
    // ... existing names ...
    "My Effect",
};

const char fx_type_shortnames[n_fx_types][16] = {
    "",
    "Delay",
    // ... existing short names ...
    "MyEffect",  // Keep it short for the GUI
};

const char fx_type_acronyms[n_fx_types][8] = {
    "",
    "DLY",
    // ... existing acronyms ...
    "MYEF",  // 3-4 characters
};
```

#### 4. Add to configuration.xml

In `/home/user/surge/resources/surge-shared/configuration.xml`, add your effect to the `<fx>` section:

```xml
<fx>
  <!-- ... existing effects ... -->
  <type i="30" name="My Effect">
    <snapshot name="Init" p0="0.5" p1="0.5" p2="0.0" p3="0.0"/>
  </type>
</fx>
```

The snapshot defines the "Init" preset with default parameter values.

#### 5. Add to CMakeLists.txt

In `/home/user/surge/src/common/CMakeLists.txt`:

```cmake
add_library(${PROJECT_NAME}
  # ... existing files ...
  dsp/effects/MyEffect.cpp
  dsp/effects/MyEffect.h
  # ... more files (alphabetical order) ...
)
```

#### 6. Build and Test

```bash
cmake --build build --config Release
```

The configuration file now automatically reloads when you compile, though a full build may be required.

### Effect Best Practices

**Audio Processing:**
- Process in-place (modify dataL and dataR directly)
- Handle both stereo and mono input gracefully
- Use BLOCK_SIZE (32 samples by default)
- Avoid allocations in process()

**Parameter Smoothing:**
- Use `lag<>` template for smooth parameter changes
- Call `.newValue()` and `.process()` each block
- Prevents zippering and clicks

**State Management:**
- Initialize all state in `init()`
- Clear state in `suspend()` to prevent artifacts
- Handle ringout properly (return correct decay time)

**Parameter Layout:**
- Use `posy_offset` to position parameters in GUI
- Group related parameters together
- First parameter often mix/amount
- Consider extended range parameters

**Effect Presets:**
- Create an "Init" preset in configuration.xml
- Add additional presets in `/home/user/surge/resources/data/fx_presets/`
- Presets should demonstrate the effect's capabilities

## Code Style Guidelines

Following Surge's coding conventions ensures your code will be accepted and maintainable. The project uses automated formatting and has clear naming conventions.

### clang-format

Surge uses `clang-format` to automatically format code. All pull requests are verified against these formatting rules by the CI system.

**Setup:**
```bash
# macOS
brew install clang-format

# The .clang-format file in the repo root defines the style
```

**Usage:**
```bash
# Format before commit (after git add)
git clang-format

# Format all changes from main
git clang-format main

# Then commit the formatting changes
```

**IDE Integration:**
- Most IDEs have clang-format plugins
- Configure to format on save
- Use the project's `.clang-format` file

### Naming Conventions

**Constants and Defines:**
```cpp
// Prefer constexpr over #define
static constexpr int BLOCK_SIZE = 32;
static constexpr float MAX_GAIN = 1.0f;

// Old style (still in some code)
#define MAX_VOICES 64
```

**Classes:**
```cpp
class MyFilterClass  // CamelCase with capital first letter
{
};

class SineOscillator  // Use full descriptive names
{
};
```

**Functions:**
```cpp
void processAudioBlock()  // camelCase with lowercase first letter
{
}

float calculateFrequency()
{
}
```

**Variables:**
```cpp
// No Hungarian notation (no s_, m_, etc.)
int voiceCount;
float sampleRate;
bool isActive;

// Member variables look like local variables
class Example
{
    int count;  // Not m_count or mCount
    float value;
};
```

**Namespaces:**
```cpp
// Full namespace names preferred
std::vector<float> buffer;  // Not: using namespace std

// Namespace aliases for long names are OK
namespace mech = sst::basic_blocks::mechanics;

// Never use "using namespace" in headers
```

**Long Names Are Good:**
```cpp
// Good
float userMessageDeliveryPipe;

// Bad
float umdp;
```

### Comments and Documentation

**Function Documentation (Doxygen style):**
```cpp
/**
 * Calculate the filter frequency from MIDI note
 * @param note MIDI note number (0-127)
 * @param detune Detune amount in cents
 *
 * Converts MIDI note to frequency in Hz accounting
 * for the current tuning system.
 */
float calculateFrequency(int note, float detune);
```

**Code Block Comments:**
```cpp
// ... some code ...
x = 3 + y;

/*
** Now we have to implement the nasty search
** across the entire set of the maps of sets
** and there is no natural index, so use this
** full loop
*/
for (auto q : mapOfSets)
{
    // ...
}
```

**Single Line Comments:**
```cpp
float omega = 2.0f * M_PI * freq;  // Angular frequency
```

**General Guidelines:**
- Comment your code! Future you will thank you
- Explain "why", not "what"
- Complex algorithms need explanation
- Document assumptions and limitations
- Reference papers or algorithms by name

### Formatting Guidelines

**Indentation:**
```cpp
// 4 spaces, not tabs
void function()
{
    if (condition)
    {
        doSomething();
    }
}
```

**Braces:**
```cpp
// Opening brace on same line for short statements
// New line for functions and classes
class Example
{
    void shortFunction() { return; }

    void longerFunction()
    {
        // Multiple statements
        doThis();
        doThat();
    }
};
```

**Line Length:**
- No hard limit, but be reasonable
- Break long lines logically
- Consider readability

**Platform-Specific Code:**
```cpp
// Use #if for entire different implementations
#if MAC
void platformFunction()
{
    // Mac implementation
}
#endif

// Or separate files in src/mac, src/windows, src/linux
// and let CMake choose the right one
```

### Miscellaneous Style Rules

**Numbers in Code:**
```cpp
// The only numbers that make sense are 0, 1, n, and infinity
for (int i = 0; i < count; ++i)  // Good

float scale = 0.5f;  // Consider: explain why 0.5

float magic = 3.14159f;  // Better: static constexpr float PI = 3.14159f;
```

**String Formatting:**
```cpp
// Prefer C++ streams over sprintf
std::ostringstream oss;
oss << "Value: " << value;
std::string result = oss.str();

// Not: sprintf(buffer, "Value: %f", value);
```

**Header Guards:**
```cpp
// Use #pragma once (yes, not standard, but we use it)
#pragma once

// Not: #ifndef SURGE_MYHEADER_H
```

### The Campground Rule

**"Leave the code better than you found it"**

When editing existing code:
- Clean up naming if you can
- Add comments where needed
- Fix obvious issues nearby
- But don't go overboard - small changes are best
- If a variable name is used in 30 places, maybe don't rename it

## Testing

Surge has a comprehensive test suite to ensure code quality and prevent regressions. Tests are built with Catch2 and cover DSP algorithms, parameter behavior, and system integration.

### Test Structure

Tests are located in:
- `/home/user/surge/src/surge-xt/xt-tests/` - Main test suite
- `/home/user/surge/src/surge-testrunner/` - Headless test runner

Key test files:
- `XTTestOSC.cpp` - Oscillator tests
- `main.cpp` - Test runner entry point

### Writing Unit Tests

Tests use the Catch2 framework with this structure:

```cpp
#include "catch2/catch_amalgamated.hpp"
#include "SurgeSynthProcessor.h"

TEST_CASE("Test My New Feature", "[myfeature]")
{
    // Setup
    auto mm = juce::MessageManager::getInstance();
    auto synth = SurgeSynthProcessor();

    // Test assertions
    REQUIRE(synth.supportsMPE());

    // Cleanup
    juce::MessageManager::deleteInstance();
}
```

**Basic Test Example:**
```cpp
TEST_CASE("Phase Distortion Oscillator Outputs Audio", "[oscillator]")
{
    auto mm = juce::MessageManager::getInstance();
    auto synth = SurgeSynthProcessor();

    // Set up patch with phase distortion oscillator
    synth.surge->storage.getPatch().scene[0].osc[0].type.val.i = ot_phasedist;

    // Generate audio
    auto buffer = juce::AudioBuffer<float>(2, 512);
    auto midi = juce::MidiBuffer();

    // Send note on
    midi.addEvent(juce::MidiMessage::noteOn(1, 60, 0.8f), 0);
    synth.processBlock(buffer, midi);

    // Verify audio was generated
    bool hasAudio = false;
    for (int i = 0; i < buffer.getNumSamples(); ++i)
    {
        if (std::abs(buffer.getSample(0, i)) > 0.0001f)
        {
            hasAudio = true;
            break;
        }
    }

    REQUIRE(hasAudio);

    juce::MessageManager::deleteInstance();
}
```

**Testing DSP Algorithms:**
```cpp
TEST_CASE("Filter Stability at High Resonance", "[filter]")
{
    auto mm = juce::MessageManager::getInstance();
    auto synth = SurgeSynthProcessor();

    // Set up filter
    synth.surge->storage.getPatch().scene[0].filterunit[0].type.val.i = fut_myfilter;
    synth.surge->storage.getPatch().scene[0].filterunit[0].cutoff.val.f = 60.0f;
    synth.surge->storage.getPatch().scene[0].filterunit[0].resonance.val.f = 0.95f;

    // Process multiple blocks
    auto buffer = juce::AudioBuffer<float>(2, 512);
    auto midi = juce::MidiBuffer();
    midi.addEvent(juce::MidiMessage::noteOn(1, 60, 0.8f), 0);

    bool stable = true;
    for (int block = 0; block < 100; ++block)
    {
        synth.processBlock(buffer, midi);

        // Check for NaN or Inf
        for (int i = 0; i < buffer.getNumSamples(); ++i)
        {
            float sample = buffer.getSample(0, i);
            if (std::isnan(sample) || std::isinf(sample))
            {
                stable = false;
                break;
            }
        }

        if (!stable) break;
    }

    REQUIRE(stable);

    juce::MessageManager::deleteInstance();
}
```

**Parameter Range Tests:**
```cpp
TEST_CASE("Effect Parameters Stay in Range", "[effect]")
{
    auto mm = juce::MessageManager::getInstance();
    auto synth = SurgeSynthProcessor();

    // Create effect
    auto storage = synth.surge->storage;
    FxStorage fxdata;
    pdata pd[n_fx_params];

    auto effect = new MyEffect(&storage, &fxdata, pd);
    effect->init_ctrltypes();
    effect->init_default_values();

    // Verify parameter ranges
    for (int i = 0; i < my_num_params; ++i)
    {
        float val = fxdata.p[i].val.f;
        float min = fxdata.p[i].val_min.f;
        float max = fxdata.p[i].val_max.f;

        REQUIRE(val >= min);
        REQUIRE(val <= max);
    }

    delete effect;
    juce::MessageManager::deleteInstance();
}
```

### Running Tests

**Build tests:**
```bash
cd /home/user/surge
cmake --build build --config Debug --target surge-xt-tests
```

**Run all tests:**
```bash
./build/surge-xt-tests
```

**Run specific tests:**
```bash
# Run tests matching tag
./build/surge-xt-tests "[oscillator]"

# Run specific test case
./build/surge-xt-tests "Phase Distortion Oscillator"

# Run with verbose output
./build/surge-xt-tests -s
```

**Headless testing:**
```bash
cmake --build build --config Debug --target surge-headless
./build/surge-headless
```

### Test Best Practices

**What to Test:**
- New oscillators produce audio
- Filters remain stable at parameter extremes
- Effects handle silence and full-scale input
- Parameters stay within valid ranges
- No NaN or Inf values in output
- Memory is properly initialized
- State is correctly saved/restored

**Test Structure:**
- One feature per test case
- Clear test names describing what is tested
- Setup, exercise, verify, cleanup pattern
- Use REQUIRE for critical assertions
- Use CHECK for non-critical assertions

**Performance Tests:**
- Verify CPU usage is reasonable
- Test worst-case scenarios (high unison, extreme parameters)
- Compare against baseline if optimizing

**Regression Tests:**
- Add tests for fixed bugs
- Ensure bugs don't reappear
- Document the original issue in comments

## Pull Request Process

Contributing to Surge follows standard GitHub workflow: fork, branch, commit, and pull request. The Surge team uses code review and continuous integration to maintain code quality.

### Forking and Branching

Based on `/home/user/surge/doc/How to Git.md`:

**1. Fork the Repository:**
- Go to https://github.com/surge-synthesizer/surge
- Click "Fork" in the top-right corner
- This creates your personal copy at `https://github.com/yourusername/surge`

**2. Clone Your Fork:**
```bash
git clone https://github.com/yourusername/surge.git
cd surge
git remote add upstream https://github.com/surge-synthesizer/surge
git remote -v
```

You should see:
```
origin    https://github.com/yourusername/surge.git (fetch)
origin    https://github.com/yourusername/surge.git (push)
upstream  https://github.com/surge-synthesizer/surge (fetch)
upstream  https://github.com/surge-synthesizer/surge (push)
```

**3. Create a Feature Branch:**

**GOLDEN RULE: Never develop in main!**

```bash
# Make sure main is up to date
git fetch upstream
git checkout main
git reset upstream/main --hard

# Create feature branch with descriptive name
git checkout -b add-phasedist-oscillator-1234

# Or with issue number:
git checkout -b fix-filter-instability-567
```

Branch naming conventions:
- `add-feature-name-issue#` for new features
- `fix-bug-description-issue#` for bug fixes
- Use descriptive names, include issue number

**4. Keep Your Branch Updated:**
```bash
# While developing, periodically sync with upstream
git fetch upstream
git rebase upstream/main

# If conflicts occur, resolve them and continue
git rebase --continue
```

### Making Commits

**Commit Message Format:**
```
Short one-line summary (50 chars or less)

More detailed explanation of the change. Wrap at 72 characters.
Explain what changed and why, not how (code shows how).

Can have multiple paragraphs if needed. Use bullet points:
- First improvement
- Second improvement
- Third change

Closes #123
```

**Tags:**
- `Closes #123` - Automatically closes issue when merged
- `Related #456` - Links to related issue
- `Addresses #789` - Partial progress on issue

**Good Commit Examples:**
```
Add Phase Distortion oscillator

Implements a new oscillator based on Casio CZ synthesis.
Features shape control, feedback, and unison support.
Includes parameter smoothing and proper voice allocation.

Closes #1234
```

```
Fix filter instability at high resonance

VintageLadder filter could produce NaN values when
resonance exceeded 0.95 and frequency was below 100Hz.
Added coefficient clamping and stability check.

Fixes #567
```

**Commit Best Practices:**
- Make atomic commits (one logical change)
- Commit working code (builds and passes tests)
- Use present tense ("Add feature" not "Added feature")
- Reference issues in commit messages
- Format code before committing

### Code Review

Surge maintainers carefully review all pull requests. Code review ensures quality and consistency.

**What Reviewers Look For:**
- **Correctness**: Does the code work as intended?
- **Performance**: Is it efficient? Any unnecessary allocations?
- **Style**: Does it follow Surge's conventions?
- **Testing**: Are there tests? Do existing tests pass?
- **Documentation**: Is the code commented appropriately?
- **Compatibility**: Does it work on all platforms?
- **Patch compatibility**: Will existing patches still work?

**Responding to Review:**
- Reviews are professional, not personal
- Questions are about understanding, not criticism
- Address all review comments
- Push new commits or amend existing ones
- Use `git push origin branch-name --force` after rebase

**Iterating on Feedback:**
```bash
# Make changes based on review
# Edit files...

# Commit the changes
git add .
git commit -m "Address code review feedback from @reviewer"

# Or amend the previous commit
git add .
git commit --amend

# Push (force if you amended or rebased)
git push origin your-branch-name --force
```

### CI Checks

Surge uses GitHub Actions for continuous integration. All PRs must pass:

**1. Build Checks:**
- Linux build (Ubuntu)
- macOS build (x64 and ARM)
- Windows build (MSVC)

**2. Code Quality:**
- `clang-format` verification
- No compiler warnings
- Static analysis (if applicable)

**3. Tests:**
- All existing tests pass
- New tests for new features

**CI Workflow Files:**
- `/home/user/surge/.github/workflows/build-pr.yml` - PR builds
- `/home/user/surge/.github/workflows/code-checks.yml` - Code quality

**If CI Fails:**
1. Check the logs to identify the failure
2. Fix locally and verify
3. Commit the fix
4. Push to update the PR
5. CI will automatically re-run

**Common CI Failures:**
```bash
# clang-format failure
git clang-format main
git commit -am "Fix code formatting"
git push

# Build failure on specific platform
# Test on that platform or ask maintainers for help

# Test failure
# Run tests locally, fix the issue
cmake --build build --target surge-xt-tests
./build/surge-xt-tests
```

### Squashing Commits

Maintainers prefer clean history with one or few commits per PR.

**Interactive Rebase:**
```bash
# Squash all commits since branching from main
git rebase -i main

# Editor opens showing commits:
# pick abc1234 Add phase distortion oscillator
# pick def5678 Fix parameter initialization
# pick ghi9012 Add tests
# pick jkl3456 Fix clang-format

# Change to:
# pick abc1234 Add phase distortion oscillator
# squash def5678 Fix parameter initialization
# squash ghi9012 Add tests
# squash jkl3456 Fix clang-format

# Save and close editor
# New editor opens for commit message - rewrite it
# Save and close

# Force push
git push origin your-branch-name --force
```

**When to Squash:**
- Before requesting review
- After addressing review feedback
- Before merge (maintainer may do this)

**Exceptions:**
- Multiple logical changes can be multiple commits
- Example: "Add feature" + "Add documentation" = 2 commits OK

### Creating the Pull Request

**1. Push Your Branch:**
```bash
git push origin your-branch-name
```

**2. Create PR on GitHub:**
- Go to https://github.com/yourusername/surge
- Click "Pull Request"
- Base: `surge-synthesizer/surge` main
- Compare: `your-branch-name`
- Click "Create Pull Request"

**3. PR Title and Description:**

**Title:** Clear, concise description
```
Add Phase Distortion oscillator
```

**Description Template:**
```markdown
## Summary
- Adds new Phase Distortion oscillator type
- Implements shape control and feedback parameters
- Includes unison support and stereo width

## Implementation Details
Based on Casio CZ synthesis technique. Uses phase modulation
to create harmonically rich timbres. Optimized for SIMD
processing at high unison counts.

## Testing
- Tested across all platforms (macOS, Windows, Linux)
- Verified parameter ranges and stability
- Checked CPU usage at extreme settings
- Added unit tests for audio generation

## Related Issues
Closes #1234

## Screenshots
[Optional: Add screenshots of the new feature in the UI]
```

**4. Request Review:**
- Tag relevant maintainers if appropriate
- Link to any discussions or issues
- Be patient - reviews take time

### After Merge

**1. Update Your Fork:**
```bash
git fetch upstream
git checkout main
git reset upstream/main --hard
git push origin main
```

**2. Delete Feature Branch:**
```bash
# Local
git branch -d your-branch-name

# Remote
git push origin --delete your-branch-name
```

**3. Celebrate:**
Your code is now part of Surge! Check the next release notes.

### PR Best Practices

**Before Submitting:**
- [ ] Code follows style guidelines
- [ ] clang-format applied
- [ ] Builds on all platforms (or note limitations)
- [ ] All tests pass
- [ ] New tests added for new features
- [ ] Documentation updated if needed
- [ ] Patch compatibility maintained
- [ ] No unnecessary changes (diffs match intent)

**During Review:**
- Respond promptly to questions
- Be open to suggestions
- Ask questions if unclear
- Update PR based on feedback
- Keep discussion professional and friendly

**General Guidelines:**
- Small PRs are easier to review
- One feature per PR
- Include context in description
- Link to relevant issues
- Update PR if main changes significantly

## Summary

Adding features to Surge follows clear patterns:

**Oscillators:**
1. Create header/cpp files inheriting from `Oscillator`
2. Register in `SurgeStorage.h` enum
3. Add spawn case in `Oscillator.cpp`
4. Define in `configuration.xml`
5. Add to `CMakeLists.txt`

**Filters:**
1. Create header/cpp with `makeCoefficients()` and `process()`
2. Register in `FilterConfiguration.h`
3. Add coefficient maker case
4. Add processing function in `QuadFilterChain`
5. Add to `CMakeLists.txt`

**Effects:**
1. Create header/cpp inheriting from `Effect`
2. Register in `SurgeStorage.h` enum
3. Add spawn case in `Effect.cpp`
4. Define in `configuration.xml`
5. Add to `CMakeLists.txt`

**For All Components:**
- Follow code style guidelines (use clang-format)
- Write tests for new features
- Create feature branch, never work in main
- Make clean, focused commits
- Create clear pull request with description
- Respond to code review professionally
- Ensure CI passes before merge

The Surge community welcomes contributions! Whether adding a new oscillator, implementing a novel filter, or creating a unique effect, following these guidelines ensures your contribution integrates smoothly into this powerful open-source synthesizer.

For questions, visit the Surge Discord server or open an issue on GitHub. Happy coding!
