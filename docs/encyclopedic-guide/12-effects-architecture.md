# Chapter 12: Effects Architecture

## The Art of Audio Processing

If oscillators are the raw canvas and filters provide the initial shaping, effects are where sound truly comes alive. Surge XT includes over 30 effect types across 4 parallel effect chains, offering unprecedented creative possibilities for sound design.

This chapter explores how Surge's effect system is architected, from the base Effect class to the sophisticated routing and processing pipeline.

## Effect Chain Architecture

### The 4 x 4 Grid

Surge provides a powerful effect routing system:

```cpp
// From: src/common/SurgeStorage.h
const int n_fx_slots = 16;       // Total effect slots
const int n_fx_chains = 4;       // Number of chains
const int n_fx_per_chain = 4;    // Effects per chain
const int n_fx_params = 12;      // Parameters per effect
```

**Four Parallel Chains:**

1. **Chain A**: Scene A post-filter effects
2. **Chain B**: Scene B post-filter effects
3. **Send 1**: Send/return chain (can receive from A and/or B)
4. **Send 2**: Second send/return chain

**Routing Diagram:**

```
┌─────────────┐
│   Scene A   │
│  3 Oscs     │
│  → Filters  │
└──────┬──────┘
       │
       ├──────────► Chain A (4 FX) ──┬──► Output
       │                              │
       └──► Send 1 ──► Chain Send1 (4 FX) ──┘
            Send 2 ──► Chain Send2 (4 FX) ──┘

┌─────────────┐
│   Scene B   │
│  3 Oscs     │
│  → Filters  │
└──────┬──────┘
       │
       ├──────────► Chain B (4 FX) ──┬──► Output
       │                              │
       └──► Send 1 ──► Chain Send1 (4 FX) ──┘
            Send 2 ──► Chain Send2 (4 FX) ──┘
```

Each slot can hold any effect type, and effects can be bypassed or swapped in real-time.

## The Effect Base Class

All Surge effects inherit from the Effect base class:

```cpp
// From: src/common/dsp/Effect.h:41

class alignas(16) Effect  // 16-byte aligned for SSE2
{
public:
    // Constructor
    Effect(SurgeStorage *storage, FxStorage *fxdata, pdata *pd);
    virtual ~Effect();

    // Effect identification
    virtual const char *get_effectname() { return 0; }

    // Initialization methods
    virtual void init() {}                    // Initialize state
    virtual void init_ctrltypes();            // Set parameter types
    virtual void init_default_values() {}     // Set default parameter values
    virtual void updateAfterReload() {}       // Called after patch load

    // Grouping (for UI organization)
    virtual const char *group_label(int id) { return 0; }
    virtual int group_label_ypos(int id) { return 0; }

    // Ringout behavior
    virtual int get_ringout_decay() { return -1; }  // -1 = instant, else block count

    // Main processing
    virtual void process(float *dataL, float *dataR) { return; }
    virtual void process_only_control() { return; }  // Update without audio
    virtual bool process_ringout(float *dataL, float *dataR,
                                 bool indata_present = true);

    // State management
    virtual void suspend() { return; }  // Called when effect bypassed
    virtual void sampleRateReset() {}   // Called when sample rate changes

    // Parameter storage
    float *pd_float[n_fx_params];  // Float parameter pointers
    int *pd_int[n_fx_params];      // Int parameter pointers

    // VU meters (for UI feedback)
    enum { KNumVuSlots = 24 };

protected:
    SurgeStorage *storage;  // Global storage
    FxStorage *fxdata;      // Effect configuration
    pdata *pd;              // Parameter data
    int ringout;            // Ringout counter
    bool hasInvalidated{false};  // UI invalidation flag
};
```

**Key Design Aspects:**

1. **Virtual methods**: Each effect implements its own processing
2. **Parameter system**: 12 parameters with flexible types
3. **Ringout handling**: Effects can tail off gracefully when bypassed
4. **VU metering**: 24 meter slots for visual feedback

### Effect Constants

```cpp
// From: src/common/dsp/Effect.h:136

const int max_delay_length = 1 << 18;  // 262,144 samples (~5.5 seconds at 48kHz)
const int slowrate = 8;                // Control rate divider
const int slowrate_m1 = slowrate - 1;  // Slowrate minus 1
```

**Why slowrate?**

Many effects don't need to update control parameters every sample. By processing control updates every 8 samples, CPU usage drops dramatically:

```cpp
void SomeEffect::process(float *dataL, float *dataR)
{
    // Update control parameters at 1/8th sample rate
    for (int k = 0; k < BLOCK_SIZE; k++)
    {
        if ((k & slowrate_m1) == 0)  // Every 8 samples
        {
            // Update filter coefficients, LFO, etc.
            updateControlParameters();
        }

        // Process audio every sample
        dataL[k] = processAudioL(dataL[k]);
        dataR[k] = processAudioR(dataR[k]);
    }
}
```

This is safe because:
- Control changes are smoothed (interpolated)
- Audio rate processing is unaffected
- Saves 87.5% of control calculation CPU

## Effect Categories

Surge's 30+ effects fall into several categories:

### Time-Based Effects

**Delays:**
- `DelayEffect` - Classic stereo delay
- `FloatyDelayEffect` - Modulated delay with drift

**Modulation:**
- `ChorusEffect` - Chorus with BBD simulation
- `FlangerEffect` - Flanger with feedback
- `PhaserEffect` - Multi-stage phaser
- `RotarySpeakerEffect` - Leslie speaker simulation

**Reverbs:**
- `Reverb1Effect` - Classic algorithmic reverb
- `Reverb2Effect` - Enhanced reverb algorithm
- `SpringReverbEffect` - Physical spring reverb model (Chowdsp)
- `NimbusEffect` - Granular reverb/cloud generator

### Frequency-Domain Effects

**Equalizers:**
- `GraphicEQ11BandEffect` - 11-band graphic EQ
- `ParametricEQ3BandEffect` - 3-band parametric EQ

**Frequency Shifters:**
- `FrequencyShifterEffect` - True frequency shifting (not pitch)
- `RingModulatorEffect` - Ring modulation

**Vocoder:**
- `VocoderEffect` - Classic vocoder with carrier/modulator

### Distortion & Waveshaping

- `DistortionEffect` - Multi-mode distortion
- `WaveShaperEffect` - Waveshaping with extensive shapes
- `BonsaiEffect` - Saturation and bass enhancement

### Spatial & Utility

- `MSToolEffect` - Mid/Side processing and manipulation
- `ConditionerEffect` - Limiting, filtering, stereo width

### Specialized

- `CombulatorEffect` - Comb filtering effects
- `ResonatorEffect` - Multiple resonant filters
- `TreemonsterEffect` - Multi-stage ring modulation
- `BBDEnsembleEffect` - Bucket-brigade delay ensemble

### External Integration

- **Airwindows** - Over 100 Airwindows ports
- **Chowdsp** - High-quality tape, BBD, spring reverb

## Effect Lifecycle

### 1. Creation and Initialization

```cpp
// From effect spawning system
Effect *spawn_effect(int id, SurgeStorage *storage,
                     FxStorage *fxdata, pdata *pd)
{
    Effect *fx = nullptr;

    switch (id)
    {
    case fxt_delay:
        fx = new DelayEffect(storage, fxdata, pd);
        break;
    case fxt_reverb:
        fx = new Reverb1Effect(storage, fxdata, pd);
        break;
    case fxt_chorus:
        fx = new ChorusEffect(storage, fxdata, pd);
        break;
    // ... many more cases
    }

    if (fx)
    {
        fx->init();              // Initialize state
        fx->init_ctrltypes();    // Configure parameters
        fx->init_default_values();  // Set defaults
    }

    return fx;
}
```

### 2. Parameter Configuration

Each effect defines its parameters:

```cpp
// Example from DelayEffect
void DelayEffect::init_ctrltypes()
{
    // Parameter 0: Left delay time
    fxdata->p[0].set_name("Left");
    fxdata->p[0].set_type(ct_envtime);  // Envelope time type (ms to seconds)

    // Parameter 1: Right delay time
    fxdata->p[1].set_name("Right");
    fxdata->p[1].set_type(ct_envtime);

    // Parameter 2: Feedback
    fxdata->p[2].set_name("Feedback");
    fxdata->p[2].set_type(ct_dly_fb_clippingmodes);  // Feedback with clipping

    // Parameter 3: Crossfeed (left → right, right → left)
    fxdata->p[3].set_name("Crossfeed");
    fxdata->p[3].set_type(ct_percent);  // 0-100%

    // Parameter 4: Low cut filter
    fxdata->p[4].set_name("Low Cut");
    fxdata->p[4].set_type(ct_freq_audible_deactivatable);

    // Parameter 5: High cut filter
    fxdata->p[5].set_name("High Cut");
    fxdata->p[5].set_type(ct_freq_audible_deactivatable);

    // Parameter 6: Mix (dry/wet)
    fxdata->p[6].set_name("Mix");
    fxdata->p[6].set_type(ct_percent);

    // Remaining parameters...
}
```

### 3. Processing Loop

```cpp
// Main processing in SurgeSynthesizer
void SurgeSynthesizer::processFXChains()
{
    // Process each of the 4 chains
    for (int chain = 0; chain < n_fx_chains; chain++)
    {
        // Get input for this chain
        float *dataL = getChainInput(chain, 0);  // Left
        float *dataR = getChainInput(chain, 1);  // Right

        // Process 4 effects in series
        for (int slot = 0; slot < n_fx_per_chain; slot++)
        {
            Effect *fx = fxChain[chain][slot];

            if (fx && !fx->is_bypassed())
            {
                fx->process(dataL, dataR);
            }
        }

        // Mix chain output to master
        mixChainToOutput(chain, dataL, dataR);
    }
}
```

### 4. Bypass and Ringout

When an effect is bypassed:

```cpp
void Effect::suspend()
{
    // Reset internal state
    // Clear buffers
    // Stop reverb tails
}
```

For reverbs and delays with tails:

```cpp
int get_ringout_decay() override
{
    return 32;  // Process 32 blocks (~1 second) after bypass
}

bool process_ringout(float *dataL, float *dataR, bool indata_present)
{
    if (!indata_present)
    {
        // No input, but we have reverb tail
        if (ringout > 0)
        {
            // Continue processing with zero input
            float silence[BLOCK_SIZE] = {0};
            process(silence, silence);
            memcpy(dataL, silence, BLOCK_SIZE * sizeof(float));
            // ... copy to dataR
            ringout--;
            return true;  // Still producing output
        }
        return false;  // Fully decayed
    }
    else
    {
        // Normal processing
        process(dataL, dataR);
        return true;
    }
}
```

## Parameter System Integration

Effects use the same powerful parameter system as the rest of Surge:

```cpp
class Effect
{
    float *pd_float[n_fx_params];  // Pointers to parameter values
    int *pd_int[n_fx_params];

    void process(float *dataL, float *dataR)
    {
        // Access parameters efficiently
        float mixAmount = *pd_float[6];  // Mix parameter
        int filterType = *pd_int[7];     // Filter type selector

        // Use parameter smoothing for audio-rate changes
        lipol_ps mix;
        mix.set_target(mixAmount);

        for (int k = 0; k < BLOCK_SIZE; k++)
        {
            float wet = processWet(dataL[k]);
            float dry = dataL[k];

            // Smooth crossfade
            dataL[k] = dry + (wet - dry) * mix.v;
            mix.process();
        }
    }
};
```

**Parameter Smoothing with `lipol_ps`:**

```cpp
// Linear interpolation for smooth parameter changes
class lipol_ps  // "_ps" = per-sample
{
    float v;        // Current value
    float target;   // Target value
    float dv;       // Delta per sample

    void set_target(float t)
    {
        target = t;
        dv = (target - v) / BLOCK_SIZE;  // Ramp over block
    }

    inline void process()
    {
        v += dv;
    }
};
```

This prevents zipper noise when parameters change.

## Memory Management

Effects must carefully manage memory for delay lines, buffers, etc.:

```cpp
class DelayEffect : public Effect
{
public:
    DelayEffect(SurgeStorage *storage, FxStorage *fxdata, pdata *pd)
        : Effect(storage, fxdata, pd)
    {
        // Allocate delay buffers (large!)
        delayBufferL.resize(max_delay_length);
        delayBufferR.resize(max_delay_length);

        // Clear to silence
        std::fill(delayBufferL.begin(), delayBufferL.end(), 0.f);
        std::fill(delayBufferR.begin(), delayBufferR.end(), 0.f);
    }

    ~DelayEffect()
    {
        // Automatic cleanup with std::vector
    }

private:
    std::vector<float> delayBufferL;
    std::vector<float> delayBufferR;
    int writePos{0};
};
```

**Memory Considerations:**

- Max delay line: 262,144 samples × 4 bytes = 1 MB per channel
- Reverbs can use multiple MB
- 16 effects × several MB each = significant RAM usage
- This is why plugin RAM can be 50+ MB even before audio processing

## Send/Return Chains

Send chains enable parallel processing:

```cpp
// Routing sends to chains
void SurgeSynthesizer::processFXChains()
{
    // Scene A sends
    float sendAmt1 = sceneSend[0][0];  // Scene A → Send 1
    float sendAmt2 = sceneSend[0][1];  // Scene A → Send 2

    // Add to send chain inputs
    for (int k = 0; k < BLOCK_SIZE; k++)
    {
        sendChainInput1L[k] += sceneAOutputL[k] * sendAmt1;
        sendChainInput1R[k] += sceneAOutputR[k] * sendAmt1;

        sendChainInput2L[k] += sceneAOutputL[k] * sendAmt2;
        sendChainInput2R[k] += sceneAOutputR[k] * sendAmt2;
    }

    // Similar for Scene B...

    // Process send chains
    fxChain[2][0]->process(sendChainInput1L, sendChainInput1R);  // Send 1
    fxChain[3][0]->process(sendChainInput2L, sendChainInput2R);  // Send 2

    // Mix send chain outputs back to master
}
```

This allows:
- Shared reverb on multiple sources
- Parallel processing paths
- Complex routing scenarios

## Stereo Width Processing

Many effects provide stereo width control:

```cpp
// From Effect.h:114
inline void applyStereoWidth(float *__restrict L, float *__restrict R,
                             lipol_ps_blocksz &width)
{
    namespace sdsp = sst::basic_blocks::dsp;

    // Encode to Mid/Side
    float M alignas(16)[BLOCK_SIZE];  // Mid (L+R)
    float S alignas(16)[BLOCK_SIZE];  // Side (L-R)
    sdsp::encodeMS<BLOCK_SIZE>(L, R, M, S);

    // Scale side channel (width control)
    width.multiply_block(S, BLOCK_SIZE_QUAD);

    // Decode back to Left/Right
    sdsp::decodeMS<BLOCK_SIZE>(M, S, L, R);
}
```

**Mid/Side Encoding:**

```
Mid = (L + R) / 2    // Center information
Side = (L - R) / 2   // Stereo information

// Width control scales Side:
Side' = Side × width

// Then decode:
L = Mid + Side'
R = Mid - Side'
```

**Width values:**
- 0%: Mono (no Side)
- 100%: Original stereo
- 200%: Enhanced stereo (doubles Side)

## VU Meters

Effects can provide visual feedback:

```cpp
class Effect
{
    enum { KNumVuSlots = 24 };
    float vu[KNumVuSlots];  // VU meter values

    void updateVU()
    {
        // Example: Show input level
        vu[0] = calculateRMS(inputL, BLOCK_SIZE);
        vu[1] = calculateRMS(inputR, BLOCK_SIZE);

        // Show output level
        vu[2] = calculateRMS(outputL, BLOCK_SIZE);
        vu[3] = calculateRMS(outputR, BLOCK_SIZE);

        // Effect-specific meters
        // Vocoder: One meter per band (up to 20 bands)
        // Compressor: Gain reduction meter
        // Limiter: Peak level meter
    }
};
```

The UI reads these values and displays graphical meters.

## Effect Presets

Effects support preset saving/loading:

```cpp
// Save effect preset
void saveEffectPreset(Effect *fx, const std::string &name)
{
    // Serialize parameter values
    TiXmlElement root("effectpreset");
    root.SetAttribute("type", fx->get_effectname());

    for (int i = 0; i < n_fx_params; i++)
    {
        TiXmlElement param("param");
        param.SetAttribute("id", i);
        param.SetAttribute("value", *fx->pd_float[i]);
        root.InsertEndChild(param);
    }

    // Save to file
    TiXmlDocument doc;
    doc.InsertEndChild(root);
    doc.SaveFile(filename);
}
```

Factory presets are stored in:
```
resources/data/fx_presets/
```

## Performance Optimization

### SIMD Usage

Effects use SSE2 where applicable:

```cpp
void ChorusEffect::process(float *dataL, float *dataR)
{
    // Process 4 samples at once
    for (int k = 0; k < BLOCK_SIZE; k += 4)
    {
        __m128 input = _mm_load_ps(&dataL[k]);
        __m128 delayed = interpolateDelay4(delaytime);
        __m128 output = _mm_add_ps(input, delayed);
        _mm_store_ps(&dataL[k], output);
    }
}
```

### Buffer Reuse

Effects reuse buffers to minimize allocation:

```cpp
class ReverbEffect : public Effect
{
    // Pre-allocated buffers
    float buffer1[BLOCK_SIZE];
    float buffer2[BLOCK_SIZE];
    float buffer3[BLOCK_SIZE];

    void process(float *dataL, float *dataR)
    {
        // Reuse these buffers throughout processing
        memcpy(buffer1, dataL, BLOCK_SIZE * sizeof(float));
        applyEarlyReflections(buffer1, buffer2);
        applyLateReverb(buffer2, buffer3);
        memcpy(dataL, buffer3, BLOCK_SIZE * sizeof(float));
    }
};
```

## Adding New Effects

See `doc/Adding an FX.md` for a complete guide, but the process is:

1. **Create effect class** inheriting from `Effect`
2. **Implement virtual methods**: `init()`, `process()`, etc.
3. **Define parameters** in `init_ctrltypes()`
4. **Register in spawn_effect()** function
5. **Add to effect type enum**
6. **Test thoroughly**

```cpp
// Minimal effect skeleton
class MyNewEffect : public Effect
{
public:
    MyNewEffect(SurgeStorage *storage, FxStorage *fxdata, pdata *pd)
        : Effect(storage, fxdata, pd)
    {
    }

    const char *get_effectname() override { return "MyEffect"; }

    void init() override
    {
        // Initialize state
        memset(buffer, 0, sizeof(buffer));
    }

    void init_ctrltypes() override
    {
        fxdata->p[0].set_name("Parameter 1");
        fxdata->p[0].set_type(ct_percent);
        // Define up to 12 parameters
    }

    void process(float *dataL, float *dataR) override
    {
        // Process audio
        for (int k = 0; k < BLOCK_SIZE; k++)
        {
            dataL[k] = processL(dataL[k]);
            dataR[k] = processR(dataR[k]);
        }
    }

private:
    float buffer[BLOCK_SIZE];
};
```

## Conclusion

Surge's effect architecture demonstrates:

1. **Flexibility**: Any effect in any slot, flexible routing
2. **Performance**: Control-rate optimization, SIMD processing
3. **Quality**: Proper ringout, smooth parameter changes
4. **Extensibility**: Easy to add new effects
5. **Integration**: Shares parameter system with rest of synth

The 4×4 grid with sends provides professional-level routing, while the effect base class makes implementation straightforward. From simple distortion to complex granular reverbs, Surge's effect system brings sounds to life.

---

**Next: [Time-Based Effects](13-effects-time-based.md)**
**See Also: [Reverb Effects](14-effects-reverb.md), [Distortion](15-effects-distortion.md)**
