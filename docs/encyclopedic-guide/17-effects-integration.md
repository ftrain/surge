# Chapter 17: Integration Effects

## Introduction

Surge XT extends its effect arsenal through strategic integrations with renowned third-party developers. These integrations bring over 200 Airwindows effects, multiple Chowdsp processors, and specialized sst-effects into Surge's unified infrastructure.

Rather than linking external plugins, Surge deeply integrates these effects at source level, adapting their DSP cores to Surge's parameter system, modulation infrastructure, and optimization framework.

## Integration Architecture Patterns

### The Adapter Pattern

Surge employs three distinct adapter strategies:

**1. Direct Adapter (Airwindows)**
- Minimal wrapper around existing implementations
- Dynamic parameter mapping
- Runtime effect selection from 200+ processors

**2. Template Adapter (sst-effects)**
- Compile-time configuration via templates
- Type-safe access to Surge infrastructure
- Shared between Surge and standalone usage

**3. Inline Integration (Chowdsp)**
- Direct implementation in Surge namespace
- Full access to Surge utilities
- Specialized for vintage emulation

### Parameter System Bridging

```cpp
// From: src/common/dsp/effects/SurgeSSTFXAdapter.h:86

struct SurgeFXConfig
{
    static constexpr uint16_t blockSize{BLOCK_SIZE};
    using BaseClass = Effect;
    using GlobalStorage = SurgeStorage;
    using EffectStorage = FxStorage;
    using ValueStorage = pdata;

    static inline float floatValueAt(const Effect *const e,
                                     const ValueStorage *const v, int idx)
    {
        return *(e->pd_float[idx]);
    }

    static inline float floatValueExtendedAt(const Effect *const e,
                                            const ValueStorage *const v, int idx)
    {
        if (e->fxdata->p[idx].extend_range)
            return e->fxdata->p[idx].get_extended(*(e->pd_float[idx]));
        return *(e->pd_float[idx]);
    }
};
```

## Airwindows Integration

### Base Architecture

Chris Johnson's Airwindows collection provides 200+ processors. Surge integrates them through a sophisticated adapter:

```cpp
// From: src/common/dsp/effects/airwindows/AirWindowsEffect.h:33

class alignas(16) AirWindowsEffect : public Effect
{
public:
    virtual const char *get_effectname() override { return "Airwindows"; }

    lag<float, true> param_lags[n_fx_params - 1];
    std::unique_ptr<AirWinBaseClass> airwin;
    int lastSelected = -1;

    static std::vector<AirWinBaseClass::Registration> fxreg;
    static std::vector<int> fxregOrdering;
};
```

### Base Class

```cpp
// From: libs/airwindows/include/airwindows/AirWinBaseClass.h:23

struct AirWinBaseClass {
    virtual void processReplacing(float **in, float **out,
                                  VstInt32 sampleFrames) = 0;
    virtual float getParameter(VstInt32 index) = 0;
    virtual void setParameter(VstInt32 index, float value) = 0;
    virtual void getParameterName(VstInt32 index, char *text) = 0;
    virtual bool isParameterBipolar(VstInt32 index) { return false; }
    virtual bool isParameterIntegral(VstInt32 index) { return false; }

    double sr = 0;
    int paramCount = 0;
};
```

**Design Philosophy:**
- Minimal API for audio processing only
- No VST dependencies
- Direct access without plugin hosting
- Virtual functions only where necessary

### Effect Registration

```cpp
// From: libs/airwindows/src/AirWinBaseClass_pluginRegistry.cpp

std::vector<AirWinBaseClass::Registration> AirWinBaseClass::pluginRegistry()
{
    return {
        Registration(&ADClip7::create, 0, 0, "Clipping", "ADClip7"),
        Registration(&Air::create, 1, 1, "Filter", "Air"),
        Registration(&BassDrive::create, 3, 3, "Saturation", "BassDrive"),
        Registration(&ButterComp2::create, 26, 26, "Dynamics", "ButterComp2"),
        // ... 200+ registrations
    };
}
```

**Categories:**
- Saturation: BassDrive, Density, Drive, Spiral
- Dynamics: ButterComp2, Compresaturator, PurestGain
- EQ/Filter: Air, Channel, MackEQ, Precious
- Reverb: MV, MV2, Room
- Modulation: Chorus, ChorusEnsemble, Vibrato
- Utility: BussColors4, ToTape6, ToVinyl4

### Dynamic Parameter Mapping

```cpp
// From: src/common/dsp/effects/airwindows/AirWindowsEffect.cpp:134

void AirWindowsEffect::resetCtrlTypes(bool useStreamedValues)
{
    fxdata->p[0].set_type(ct_airwindows_fx);

    if (airwin)
    {
        for (int i = 0; i < airwin->paramCount && i < n_fx_params - 1; ++i)
        {
            char txt[1024];
            airwin->getParameterName(i, txt);
            fxdata->p[i + 1].set_name(txt);

            if (airwin->isParameterIntegral(i))
            {
                fxdata->p[i + 1].set_type(ct_airwindows_param_integral);
                fxdata->p[i + 1].val_max.i =
                    airwin->parameterIntegralUpperBound(i);
            }
            else if (airwin->isParameterBipolar(i))
            {
                fxdata->p[i + 1].set_type(ct_airwindows_param_bipolar);
            }
            else
            {
                fxdata->p[i + 1].set_type(ct_airwindows_param);
            }
        }
    }
}
```

### Sub-block Processing

```cpp
// From: src/common/dsp/effects/airwindows/AirWindowsEffect.cpp:203

constexpr int subblock_factor = 3;  // Divide by 8

void AirWindowsEffect::process(float *dataL, float *dataR)
{
    constexpr int QBLOCK = BLOCK_SIZE >> subblock_factor;  // 4 samples

    for (int subb = 0; subb < 1 << subblock_factor; ++subb)
    {
        // Update parameters once per sub-block
        for (int i = 0; i < airwin->paramCount && i < n_fx_params - 1; ++i)
        {
            param_lags[i].newValue(clamp01(*pd_float[i + 1]));
            airwin->setParameter(i, param_lags[i].v);
            param_lags[i].process();
        }

        float *in[2] = {dataL + subb * QBLOCK, dataR + subb * QBLOCK};
        float *out[2] = {&(outL[0]) + subb * QBLOCK, &(outR[0]) + subb * QBLOCK};

        airwin->processReplacing(in, out, QBLOCK);
    }
}
```

Reduces parameter overhead by 87.5% while maintaining smooth changes.

## Chowdsp Effects

### Tape Effect

Research-grade analog tape emulation based on hysteresis modeling:

```cpp
// From: src/common/dsp/effects/chowdsp/TapeEffect.h:44

class TapeEffect : public Effect
{
public:
    enum tape_params
    {
        tape_drive, tape_saturation, tape_bias, tape_tone,
        tape_speed, tape_gap, tape_spacing, tape_thickness,
        tape_degrade_depth, tape_degrade_amount, tape_degrade_variance,
        tape_mix,
    };

private:
    HysteresisProcessor hysteresis;  // Jiles-Atherton model
    ToneControl toneControl;
    LossFilter lossFilter;
    DegradeProcessor degrade;
    ChewProcessor chew;
};
```

**Signal Chain:**

```
Input → Hysteresis → Tone → Loss Filter → Degrade → Chew → Output
```

**Hysteresis:** Models magnetic domain behavior using Jiles-Atherton equations
**Loss Filter:** Gap loss, spacing loss, thickness effects
**Degrade:** Dropout, noise, azimuth error
**Chew:** Physical damage simulation

### Spring Reverb

Physical spring modeling based on Välimäki/Parker/Abel research:

```cpp
// From: src/common/dsp/effects/chowdsp/SpringReverbEffect.h:47

class SpringReverbEffect : public Effect
{
public:
    enum spring_reverb_params
    {
        spring_reverb_size, spring_reverb_decay,
        spring_reverb_reflections, spring_reverb_damping,
        spring_reverb_spin, spring_reverb_chaos, spring_reverb_knock,
        spring_reverb_mix,
    };

private:
    SpringReverbProc proc;
};
```

**Physical Properties:**
- **Dispersion**: Different frequencies travel at different speeds
- **Reflections**: End reflections create feedback matrix
- **Damping**: Energy loss through vibration
- **Chaos/Knock**: Physical impacts create "boing" sounds

### Exciter Effect

Aphex Aural Exciter-style harmonic enhancement:

```cpp
// From: src/common/dsp/effects/chowdsp/ExciterEffect.h:71

inline void process_sample(float &l, float &r)
{
    toneFilter.process_sample(l, r, l, r);  // HPF
    auto levelL = levelDetector.process_sample(l, 0);
    auto levelR = levelDetector.process_sample(r, 0);
    l = std::tanh(l) * levelL;  // Harmonic generation + dynamic scaling
    r = std::tanh(r) * levelR;
}
```

**Signal Path:** Input → HPF → Drive → tanh() → Level Detection → Mix

### Neuron Effect

GRU-based adaptive distortion:

```cpp
// From: src/common/dsp/effects/chowdsp/NeuronEffect.h:90

inline float processSample(float x, float yPrev) noexcept
{
    float f = sigmoid(Wf * x + Uf * yPrev + bf);  // Forget gate
    return f * yPrev + (1.0f - f) * std::tanh(Wh * x + Uh * f * yPrev);
}
```

Uses Gated Recurrent Unit for distortion with memory.

### CHOW Effect

Truculent distortion with compressor-like controls:

```cpp
// From: src/common/dsp/effects/chowdsp/CHOWEffect.h:40

class CHOWEffect : public Effect
{
    enum chow_params { chow_thresh, chow_ratio, chow_flip, chow_mix };

    Oversampling<2, BLOCK_SIZE> os;
    SmoothedValue<float> thresh_smooth, ratio_smooth;
};
```

## Utility Effects

### Conditioner

Mastering-grade limiting and EQ:

```cpp
// From: src/common/dsp/effects/ConditionerEffect.h:34

class ConditionerEffect : public Effect
{
public:
    enum cond_params
    {
        cond_bass, cond_treble, cond_width, cond_balance,
        cond_threshold, cond_attack, cond_release, cond_gain, cond_hpwidth,
    };

    float vu[3][2];  // Input, gain reduction, output

private:
    BiquadFilter band1, band2, hp;

    const int lookahead = 128;  // Samples
    float lamax[256];
    float delayed[2][128];
    float filtered_lamax, gain;
};
```

**Lookahead Limiting:**

```cpp
// Peak detection over 128-sample window
for (int i = 0; i < lookahead; i++)
    peaklevel = std::max(peaklevel, lamax[bufpos + i]);

// Calculate gain reduction
float targetGain = (peaklevel > threshold) ? threshold / peaklevel : 1.0f;

// Apply to delayed signal
dataL[k] = delayed[0][bufpos] * targetGain * makeup;
```

### Mid-Side Tool

Advanced M/S processing:

```cpp
// From: src/common/dsp/effects/MSToolEffect.h:30

class MSToolEffect : public Effect
{
public:
    enum mstl_params
    {
        mstl_matrix,  // Stereo matrix mode
        mstl_hpm, mstl_pqm, mstl_freqm, mstl_lpm,  // Mid EQ
        mstl_hps, mstl_pqs, mstl_freqs, mstl_lps,  // Side EQ
        mstl_mgain, mstl_sgain, mstl_outgain,
    };

private:
    BiquadFilter hpm, hps, lpm, lps, bandm, bands;
};
```

Independent filtering on Mid (center) and Side (stereo) channels.

## Specialized Effects

### Combulator

Multi-mode comb filter:

```cpp
// From: src/common/dsp/effects/CombulatorEffect.h:39

enum combulator_params
{
    combulator_noise_mix,
    combulator_freq1, combulator_freq2, combulator_freq3,
    combulator_feedback, combulator_tone,
    combulator_gain1, combulator_gain2, combulator_gain3,
    combulator_pan2, combulator_pan3,
    combulator_mix,
};
```

**Architecture:**

```
           Noise Mix
                ↓
Input → Comb1 → Gain1 ┐
      → Comb2 → Gain2 ├→ Pan → Output
      → Comb3 → Gain3 ┘
         ↑
      Feedback
```

Three parallel combs with noise excitation, 2× oversampling.

### Resonator

Multi-band resonant filter:

```cpp
// From: src/common/dsp/effects/ResonatorEffect.h:39

enum resonator_params
{
    resonator_freq1, resonator_res1, resonator_gain1,
    resonator_freq2, resonator_res2, resonator_gain2,
    resonator_freq3, resonator_res3, resonator_gain3,
    resonator_mode, resonator_gain, resonator_mix,
};

enum resonator_modes
{
    rm_lowpass, rm_bandpass, rm_bandpass_n, rm_highpass,
};
```

**Processing:**

```cpp
// Upsample to 2× sample rate
halfbandIN.process_block_U2(dataL, dataR, dataOS[0], dataOS[1]);

// Three parallel filters
for (int b = 0; b < 3; ++b)
{
    coeff[b][c].MakeCoeffs(cutoff[b].v, resonance[b].v, filterType);
    auto output = coeff[b][c].process_quad(input, Reg[b][c]);
}

// Downsample back
halfbandOUT.process_block_D2(dataOS[0], dataOS[1]);
```

### Treemonster

Pitch-tracking ring modulator using sst-effects adapter:

```cpp
// From: src/common/dsp/effects/TreemonsterEffect.h:36

class TreemonsterEffect :
    public surge::sstfx::SurgeSSTFXBase<
        sst::effects::treemonster::TreeMonster<surge::sstfx::SurgeFXConfig>>
{
    // Template adapter provides:
    // - init() → initialize()
    // - process() → processBlock()
    // - suspend() → suspendProcessing()
};
```

**Signal Flow:** Input → Pitch Detection → Oscillator → Ring Mod → Mix

## Integration Patterns Summary

| Aspect | Airwindows | Chowdsp | sst-effects |
|--------|-----------|---------|-------------|
| **Method** | Runtime selection | Direct namespace | Template adapter |
| **Mapping** | Dynamic | Static | Static validated |
| **Count** | 200+ | 5 | Growing |
| **Location** | `libs/airwindows/` | `src/.../chowdsp/` | `libs/sst-effects/` |
| **Overhead** | Registry + active | Direct | Template expansion |

### Parameter Type Reference

```cpp
// Airwindows
ct_airwindows_fx              // Effect selector
ct_airwindows_param           // 0-1 float
ct_airwindows_param_bipolar   // -1 to +1
ct_airwindows_param_integral  // Discrete

// Standard Surge types (Chowdsp)
ct_percent                    // 0-100%
ct_percent_bipolar            // -100% to +100%
ct_decibel                    // dB scaled
ct_freq_audible               // Hz

// sst-effects metadata
ParamMetaData::Type::FLOAT
ParamMetaData::Type::INT
ParamMetaData::Type::BOOL
```

## Conclusion

Surge's integration effects demonstrate three sophisticated DSP integration approaches:

**Airwindows**: Maximum variety through runtime-selectable 200+ effect registry
**Chowdsp**: Maximum quality via research-grade physical modeling
**sst-effects**: Maximum modularity with template-based code sharing

Together, these expand Surge from comprehensive to encyclopedic, providing professional processing for every sound design stage. Adapter patterns ensure consistent parameter behavior, modulation compatibility, and performance across all integrated effects.

---

**Next: [Effects Implementation](18-effects-implementation.md)**
**Previous: [Distortion Effects](16-effects-distortion.md)**
**See Also: [Effects Architecture](12-effects-architecture.md)**
