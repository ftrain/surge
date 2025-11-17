# Chapter 13: Time-Based Effects

## Introduction

Time-based effects form the sonic foundation of spatial depth, movement, and texture in electronic music. From the rhythmic pulse of a delay to the shimmering complexity of a chorus, these effects manipulate the temporal relationship between signals to create everything from subtle enhancement to otherworldly transformation.

Surge XT implements six sophisticated time-based effects that represent decades of digital signal processing evolution: classic stereo delay, floating modulated delay, bucket-brigade chorus, through-zero flanger, multi-stage phaser, and Leslie rotary speaker simulation. Each effect embodies careful attention to aliasing prevention, modulation quality, and musical usability.

This chapter explores the implementation, mathematics, and sonic characteristics of each effect, revealing how careful DSP design creates the movement and space that brings synthesized sounds to life.

## Fundamental Concepts

### Delay Lines and Circular Buffers

All time-based effects rely on **delay lines** - buffers that store audio samples for later playback. Surge uses **circular buffers** for efficient implementation:

```cpp
// From: src/common/dsp/Effect.h:126
const int max_delay_length = 1 << 18;  // 262,144 samples
```

**Why 2^18?**
- Power of 2 enables fast modulo via bitwise AND: `pos & (max_delay_length - 1)`
- At 48 kHz: 262,144 / 48,000 ≈ 5.46 seconds maximum delay
- At 96 kHz: 262,144 / 96,000 ≈ 2.73 seconds maximum delay

**Circular buffer implementation:**

```cpp
float buffer[max_delay_length];
int writePos = 0;

// Write sample
buffer[writePos] = inputSample;
writePos = (writePos + 1) & (max_delay_length - 1);  // Wrap efficiently

// Read delayed sample
int readPos = (writePos - delaySamples) & (max_delay_length - 1);
float delayedSample = buffer[readPos];
```

The bitwise AND with `(max_delay_length - 1)` wraps the position: when `writePos` reaches 262,144, it wraps to 0 without expensive modulo division.

### Fractional Delay Interpolation

When delay times modulate, we need **sub-sample accuracy**. Reading at position 100.7 requires interpolation between samples 100 and 101.

**Surge uses FIR sinc interpolation** for highest quality:

```cpp
// From: src/common/dsp/effects/ChorusEffectImpl.h:127

int i_dtime = max(BLOCK_SIZE, min((int)vtime, max_delay_length - FIRipol_N - 1));
int rp = ((wpos - i_dtime + k) - FIRipol_N) & (max_delay_length - 1);
int sinc = FIRipol_N * limit_range((int)(FIRipol_M * (float(i_dtime + 1) - vtime)),
                                   0, FIRipol_M - 1);

SIMD_M128 vo;
vo = SIMD_MM(mul_ps)(SIMD_MM(load_ps)(&storage->sinctable1X[sinc]),
                     SIMD_MM(loadu_ps)(&buffer[rp]));
vo = SIMD_MM(add_ps)(vo,
                     SIMD_MM(mul_ps)(SIMD_MM(load_ps)(&storage->sinctable1X[sinc + 4]),
                                     SIMD_MM(loadu_ps)(&buffer[rp + 4])));
vo = SIMD_MM(add_ps)(vo,
                     SIMD_MM(mul_ps)(SIMD_MM(load_ps)(&storage->sinctable1X[sinc + 8]),
                                     SIMD_MM(loadu_ps)(&buffer[rp + 8])));
```

**FIRipol (FIR interpolation) constants:**
- `FIRipol_N = 12`: Number of FIR coefficients
- `FIRipol_M = 256`: Number of fractional positions (8-bit precision)
- Total sinc table: 12 × 256 = 3,072 pre-computed coefficients

**The algorithm:**
1. Split delay time into integer (`i_dtime`) and fractional parts
2. Select sinc coefficients based on fractional position
3. Convolve 12 samples with windowed sinc kernel
4. Uses SSE to process 4 samples at once (12 coefficients = 3 SSE operations)

**Why sinc interpolation?**
- Linear interpolation: -40 dB aliasing
- Cubic interpolation: -60 dB aliasing
- Sinc interpolation: -96 dB aliasing (16-bit clean)

### Time-to-Samples Conversion

Surge provides sophisticated time conversion for musical delays:

```cpp
// From delay time parameter processing
float tm = storage->note_to_pitch_ignoring_tuning(12 * time_param) *
           (fxdata->p[dly_time].temposync ? storage->temposyncratio_inv : 1.f);
float delaySamples = storage->samplerate * tm;
```

**Conversion chain:**

1. **Parameter range**: -11 to +3 (14 semitones range)
   - -11: Very short (0.06 ms at 48kHz)
   - 0: Moderate (1 ms)
   - +3: Long (1.68 seconds)

2. **Note-to-pitch conversion**: `2^(time_param)`
   - Each unit = 1 octave (doubling)
   - 12 steps = 12 octaves of range

3. **Tempo sync adjustment**:
   - `temposyncratio_inv`: Adjusts to host tempo
   - At 120 BPM: Quarter note = 0.5 seconds
   - Enables musical delays (1/4, 1/8, 1/16, etc.)

4. **Sample rate conversion**: Multiply by `samplerate`

**Example calculations at 48 kHz:**

```
Parameter = -2.0 (no tempo sync):
  note_to_pitch(12 × -2.0) = note_to_pitch(-24) = 2^(-24/12) = 2^-2 = 0.25
  delaySamples = 48000 × 0.25 = 12,000 samples = 250 ms

Parameter = 0.0:
  note_to_pitch(0) = 2^0 = 1.0
  delaySamples = 48000 × 1.0 = 48,000 samples = 1 second
```

### Modulation and LFOs

Time-based effects use modulation to create movement. The standard LFO pattern:

```cpp
// From: src/common/dsp/effects/ChorusEffectImpl.h:83

float rate = storage->envelope_rate_linear(-*pd_float[ch_rate]) *
             (fxdata->p[ch_rate].temposync ? storage->temposyncratio : 1.f);

lfophase[i] += rate;
if (lfophase[i] > 1)
    lfophase[i] -= 1;

// Triangle LFO (typical for chorus/flanger)
float lfoout = (2.f * fabs(2.f * lfophase[i] - 1.f) - 1.f) * depth;
```

**Triangle wave generation:**
```
lfophase: 0.0 → 0.25 → 0.5 → 0.75 → 1.0 (wraps)

2 × lfophase:        0.0 → 0.5 → 1.0 → 1.5 → 2.0
2 × lfophase - 1:   -1.0 → -0.5 → 0.0 → 0.5 → 1.0
abs():               1.0 → 0.5 → 0.0 → 0.5 → 1.0
2 × abs() - 1:       1.0 → 0.0 → -1.0 → 0.0 → 1.0  (triangle)
```

This creates a triangle from -1 to +1, scaled by depth.

**Rate calculation:**
- `envelope_rate_linear()`: Converts parameter to Hz
- Tempo sync multiplies by `temposyncratio` for musical rates
- Result: Phase increment per sample (Hz / samplerate)

## Delay Effect

The **Delay Effect** is Surge's classic stereo delay with extensive filtering and routing options.

**Implementation**: Uses SST effects library (`sst::effects::delay::Delay`)
**Source wrapper**: `/home/user/surge/src/common/dsp/effects/DelayEffect.cpp`

### Parameters

```cpp
// From: src/common/dsp/effects/DelayEffect.cpp:79

enum delay_params {
    dly_time_left,      // Left channel delay time
    dly_time_right,     // Right channel delay time (linkable)
    dly_feedback,       // Feedback amount with clipping modes
    dly_crossfeed,      // L→R and R→L feedback routing
    dly_lowcut,         // High-pass filter in feedback path
    dly_highcut,        // Low-pass filter in feedback path
    dly_mod_rate,       // LFO rate for time modulation
    dly_mod_depth,      // LFO depth (detuning amount)
    dly_input_channel,  // Stereo/mono input selection
    dly_mix,            // Dry/wet mix
    dly_width,          // Stereo width of wet signal
};
```

### Parameter Groups

The UI organizes parameters into logical groups:

```cpp
// From: src/common/dsp/effects/DelayEffect.cpp:44

group_label(0): "Input"          // Input channel selection
group_label(1): "Delay Time"     // Left/Right time parameters
group_label(2): "Feedback/EQ"    // Feedback, crossfeed, filters
group_label(3): "Modulation"     // Rate and depth
group_label(4): "Output"         // Mix and width
```

### Stereo Delay Architecture

**Signal flow:**

```
Input L ──┬──────────────────────────► Mix ──► Output L
          │                             ▲
          └──► Delay L ──► Filter ──────┤
                  ▲          │          │
                  │          ├─────► Feedback L
                  │          │          │
                  │          └─────► Crossfeed ──┐
                  │                              │
                  └──────────────────────────────┤
                                                 │
Input R ──┬──────────────────────────► Mix ──► Output R
          │                             ▲
          └──► Delay R ──► Filter ──────┤
                  ▲          │          │
                  │          ├─────► Feedback R
                  │          │          │
                  │          └─────► Crossfeed ──┘
                  │
                  └─────────────────────┘
```

### Feedback with Clipping Modes

The `dly_feedback` parameter uses `ct_dly_fb_clippingmodes` type:

```cpp
// From: src/common/dsp/effects/DelayEffect.cpp:86
fxdata->p[dly_feedback].set_type(ct_dly_fb_clippingmodes);
```

**Clipping modes** (selectable via deform_type):
1. **Soft clip**: Smooth saturation, analog-style warmth
2. **Hard clip**: Digital limiting, retains brightness
3. **Asymmetric**: Adds harmonic character
4. **Digital**: Clean feedback with no coloration

**Why clip feedback?**

When feedback approaches 100%, tiny imperfections can cause exponential growth:
```
Sample 0: 1.0
After delay: 1.0 × 0.99 = 0.99
Round 2: 0.99 × 0.99 = 0.98...
```

But with numerical error or modulation:
```
Sample 0: 1.0
After delay: 1.0 × 1.01 = 1.01  (slightly over unity)
Round 2: 1.01 × 1.01 = 1.0201
Round 10: 1.01^10 = 1.1046
Round 100: Explosion!
```

Clipping prevents runaway:
```cpp
float feedback_sample = delay_output * feedback_amount;
feedback_sample = soft_clip(feedback_sample);  // Keep ≤ ±1.0
write_to_buffer(input + feedback_sample);
```

### Crossfeed Routing

**Crossfeed** creates ping-pong and complex stereo effects:

```cpp
// From parameter type
fxdata->p[dly_crossfeed].set_type(ct_percent_with_extend_to_bipolar);
```

**Routing logic:**

```
Crossfeed = 0%:   No cross-coupling (independent L/R delays)
Crossfeed = 50%:  Equal direct and cross feedback
Crossfeed = 100%: Full ping-pong (L feeds only R, R feeds only L)
```

**Implementation concept:**
```cpp
float direct_fb = (1.0 - crossfeed) * feedback;
float cross_fb = crossfeed * feedback;

delay_L_input = input_L + delay_L_out * direct_fb + delay_R_out * cross_fb;
delay_R_input = input_R + delay_R_out * direct_fb + delay_L_out * cross_fb;
```

At 100% crossfeed with 70% feedback:
- Left delay output feeds right delay input at 0.7
- Right delay output feeds left delay input at 0.7
- Creates classic ping-pong delay

### Filters in Feedback Path

**Both high-pass and low-pass** filters shape the feedback:

```cpp
// From: src/common/dsp/effects/DelayEffect.cpp:88

fxdata->p[dly_lowcut].set_type(ct_freq_audible_deactivatable_hp);
fxdata->p[dly_highcut].set_type(ct_freq_audible_deactivatable_lp);
```

**Why filter feedback?**

1. **Low cut (high-pass)**: Removes rumble, prevents bass buildup
   - Default: -24 semitones below A-440 ≈ 55 Hz
   - Each repeat loses low-frequency energy
   - Creates "thin, airy" long delays like tape echo

2. **High cut (low-pass)**: Darkens repeats, vintage character
   - Default: +30 semitones above A-440 ≈ 7 kHz
   - Simulates tape/analog delay bandwidth limits
   - Each repeat gets darker (realistic decay)

**Combined effect:**
```
Repeat 1: Full bandwidth
Repeat 2: 55 Hz to 7 kHz
Repeat 3: 55 Hz to 7 kHz (further rolled off)
Repeat 4: Increasingly dark and thin
```

This matches the behavior of vintage tape delays and creates musical, non-fatiguing repeats.

### Modulation Section

**Time modulation** adds chorus-like movement:

```cpp
fxdata->p[dly_mod_rate].set_type(ct_lforate);
fxdata->p[dly_mod_depth].set_type(ct_detuning);
```

**How it works:**

1. LFO runs at `mod_rate` (Hz or tempo-synced)
2. LFO output modulates delay time by ±`mod_depth` semitones
3. Creates pitch shifting as delay time changes

**Pitch shifting from delay modulation:**

When delay time increases:
- Samples spread out in time
- Waveform stretches → pitch drops

When delay time decreases:
- Samples compress in time
- Waveform contracts → pitch rises

**Example:**

Delay time modulating ±5% at 1 Hz creates vibrato-like pitch variation in the delayed signal, adding width and movement to the repeats.

### Default Values

```cpp
// From: src/common/dsp/effects/DelayEffect.cpp:116

fxdata->p[dly_time_left].val.f = -2.f;      // ~250 ms
fxdata->p[dly_time_right].val.f = -2.f;     // ~250 ms
fxdata->p[dly_feedback].val.f = 0.5f;       // 50% feedback
fxdata->p[dly_crossfeed].val.f = 0.0f;      // No crossfeed
fxdata->p[dly_lowcut].val.f = -24.f;        // ~55 Hz
fxdata->p[dly_highcut].val.f = 30.f;        // ~7 kHz
fxdata->p[dly_mod_rate].val.f = -2.f;       // Slow LFO
fxdata->p[dly_mod_depth].val.f = 0.f;       // No modulation
fxdata->p[dly_mix].val.f = 0.5f;            // 50/50 mix
fxdata->p[dly_width].val.f = 0.f;           // Natural width
```

## Floaty Delay Effect

The **Floaty Delay** is a modulated delay with extensive "warp" controls for lo-fi, tape-like, and otherworldly effects.

**Implementation**: SST effects library (`sst::effects::floatydelay::FloatyDelay`)
**Source**: `/home/user/surge/src/common/dsp/effects/FloatyDelayEffect.cpp`

### Parameters

```cpp
// From: src/common/dsp/effects/FloatyDelayEffect.cpp:71

enum floatydelay_params {
    fld_time,              // Delay time
    fld_playrate,          // Playback rate (pitch shift)
    fld_feedback,          // Feedback amount
    fld_cutoff,            // Filter cutoff in feedback
    fld_resonance,         // Filter resonance
    fld_warp_rate,         // Warp LFO rate
    fld_warp_width,        // Warp LFO waveform
    fld_pitch_warp_depth,  // Pitch warp amount
    fld_filt_warp_depth,   // Filter warp amount
    fld_HP_freq,           // Output high-pass filter
    fld_mix,               // Dry/wet mix
};
```

### Unique Features

#### 1. Playback Rate Control

```cpp
fxdata->p[fld_playrate].set_type(ct_floaty_delay_playrate);
```

**Playback rate** changes the speed of delay buffer playback:

- **1.0**: Normal playback (no pitch shift)
- **0.5**: Half speed (one octave down)
- **2.0**: Double speed (one octave up)

**Implementation concept:**

```cpp
// Normal delay read
readPos = (writePos - delaySamples) & (max_delay_length - 1);

// Floaty delay with playback rate
float phaseIncrement = playbackRate;  // Samples per output sample
delayPhase += phaseIncrement;
readPos = (writePos - delayPhase) & (max_delay_length - 1);
```

When `playbackRate = 0.5`:
- Read pointer advances half as fast
- Takes twice as long to traverse delay time
- Output pitch is halved (one octave down)
- Creates tape-slowdown effects

#### 2. Warp Modulation System

The "warp" controls create complex, interrelated modulation:

```cpp
fxdata->p[fld_warp_rate].set_type(ct_floaty_warp_time);
fxdata->p[fld_warp_width].set_type(ct_percent);
fxdata->p[fld_pitch_warp_depth].set_type(ct_percent);
fxdata->p[fld_filt_warp_depth].set_type(ct_percent);
```

**Warp LFO** simultaneously modulates:

1. **Pitch** (via delay time modulation)
   - `pitch_warp_depth`: How much LFO affects delay time
   - Creates vibrato, chorus, detuning effects

2. **Filter** (via filter cutoff modulation)
   - `filt_warp_depth`: How much LFO affects cutoff
   - Creates wah-like sweeps through delay repeats

**Warp width** changes LFO waveform:
- 0%: Smooth sine wave
- 50%: Triangle wave
- 100%: Square wave (abrupt changes)

**Musical applications:**

```cpp
// Lo-fi tape flutter
warp_rate = 6 Hz
warp_width = 20%  (smooth)
pitch_warp_depth = 5%
filt_warp_depth = 10%

// Aggressive modulation
warp_rate = 1 Hz
warp_width = 80%  (choppy)
pitch_warp_depth = 30%
filt_warp_depth = 50%
```

#### 3. Filter in Feedback

Unlike regular Delay's dual filters, Floaty has a **resonant filter**:

```cpp
fxdata->p[fld_cutoff].set_type(ct_freq_audible);
fxdata->p[fld_resonance].set_type(ct_percent);
```

High resonance at moderate feedback creates:
- Self-oscillation at filter frequency
- Harmonic emphasis with each repeat
- Dub-style filter delay effects

**Runaway prevention:**

When feedback + resonance both high, filter can add energy:
```
Input: 0.7
After delay × 0.8 feedback: 0.56
After resonant filter boost at peak: 0.84  (gained energy!)
Next iteration: 0.84 × 0.8 = 0.67
```

The implementation includes **soft clipping** to prevent oscillation.

### Parameter Groups

```cpp
// From: src/common/dsp/effects/FloatyDelayEffect.cpp:40

group_label(0): "Delay"          // Time, playrate
group_label(1): "Feedback"       // Feedback, cutoff, resonance
group_label(2): "Warp"           // All warp parameters
group_label(3): "Output"         // HP filter, mix
```

### Default Values

```cpp
// From: src/common/dsp/effects/FloatyDelayEffect.cpp:108

fxdata->p[fld_time].val.f = -1.73697f;      // ~300 ms
fxdata->p[fld_playrate].val.f = 1.f;        // Normal speed
fxdata->p[fld_feedback].val.f = .5f;        // 50%
fxdata->p[fld_cutoff].val.f = 0.f;          // Mid frequency
fxdata->p[fld_resonance].val.f = .5f;       // Moderate Q
fxdata->p[fld_warp_rate].val.f = 0.f;       // No warp
fxdata->p[fld_pitch_warp_depth].val.f = 0.f;
fxdata->p[fld_filt_warp_depth].val.f = 0.f;
fxdata->p[fld_warp_width].val.f = 0.f;
fxdata->p[fld_HP_freq].val.f = -60.f;       // ~20 Hz (off)
fxdata->p[fld_mix].val.f = .3f;             // 30% wet
```

## Chorus Effect

The **Chorus Effect** simulates bucket-brigade delay (BBD) chips used in classic analog chorus pedals. Surge implements this as a **template-based multi-voice chorus** with sophisticated interpolation.

**Implementation**: Direct implementation in Surge (not SST library)
**Source**: `/home/user/surge/src/common/dsp/effects/ChorusEffectImpl.h`

### Template Architecture

```cpp
// From: src/common/dsp/effects/ChorusEffect.h:31

template <int v> class ChorusEffect : public Effect
{
    // v = number of voices (4 in practice)
};
```

The chorus is **instantiated with 4 voices**, creating a lush ensemble effect. Each voice:
- Has its own LFO phase (evenly distributed)
- Reads from shared delay buffer at different modulated positions
- Has its own stereo pan position
- Contributes to final stereo output

### Parameters

```cpp
// From: src/common/dsp/effects/ChorusEffectImpl.h:39

enum chorus_params {
    ch_time,      // Base delay time (very short)
    ch_rate,      // LFO rate
    ch_depth,     // LFO depth (modulation amount)
    ch_feedback,  // Feedback amount
    ch_lowcut,    // High-pass filter
    ch_highcut,   // Low-pass filter
    ch_mix,       // Dry/wet mix
    ch_width,     // Stereo width
};
```

### BBD (Bucket Brigade Delay) Simulation

**What is BBD?**

Bucket-brigade delay chips (like MN3007, SAD1024) were analog ICs that:
- Passed signal through chain of capacitors (the "buckets")
- Each capacitor sampled and held the signal briefly
- Clock rate determined delay time
- Inherent bandwidth limiting and noise created the "analog" sound

**Surge's BBD simulation approach:**

1. **Very short delays** (1-40 ms typical)
   - Default: -6.0 semitones = ~15.6 ms at 48 kHz
   - BBD chips typically 5-50 ms range

2. **Multiple modulated voices**
   - Real BBD choruses often used 2-3 chips in parallel
   - Each at slightly different rate/depth
   - Surge uses 4 voices for richer sound

3. **Bandwidth limiting**
   - High-pass and low-pass filters simulate BBD frequency response
   - Default high cut: +3 octaves ≈ 3.5 kHz
   - BBD chips typically had 3-5 kHz bandwidth

### Multi-Voice Architecture

#### Voice Initialization

```cpp
// From: src/common/dsp/effects/ChorusEffectImpl.h:47

template <int v> void ChorusEffect<v>::init()
{
    const float gainscale = 1 / sqrt((float)v);  // Prevent gain buildup

    for (int i = 0; i < v; i++)
    {
        // Distribute LFO phases evenly
        float x = i / (float)(v - 1);
        lfophase[i] = x;

        // Calculate stereo pan
        x = 2.f * x - 1.f;  // Map to -1..+1
        voicepan[i][0] = sqrt(0.5 - 0.5 * x) * gainscale;  // Left
        voicepan[i][1] = sqrt(0.5 + 0.5 * x) * gainscale;  // Right

        // Store as SIMD for efficiency
        voicepanL4[i] = SIMD_MM(set1_ps)(voicepan[i][0]);
        voicepanR4[i] = SIMD_MM(set1_ps)(voicepan[i][1]);
    }
}
```

**With 4 voices:**

```
Voice 0: phase = 0.000, pan = full left  (L=0.5, R=0.0)
Voice 1: phase = 0.333, pan = left-ish   (L=0.433, R=0.25)
Voice 2: phase = 0.666, pan = right-ish  (L=0.25, R=0.433)
Voice 3: phase = 1.000, pan = full right (L=0.0, R=0.5)
```

**Gain scaling:**

```cpp
gainscale = 1 / sqrt(4) = 0.5
```

With 4 uncorrelated voices, RMS sum is `sqrt(4) = 2×` the individual level. Dividing by `sqrt(v)` prevents gain buildup.

#### Per-Voice Delay Modulation

```cpp
// From: src/common/dsp/effects/ChorusEffectImpl.h:83

for (int i = 0; i < v; i++)
{
    lfophase[i] += rate;
    if (lfophase[i] > 1)
        lfophase[i] -= 1;

    // Triangle LFO
    float lfoout = (2.f * fabs(2.f * lfophase[i] - 1.f) - 1.f) * depth;

    // Calculate delay time for this voice
    time[i].newValue(storage->samplerate * tm * (1 + lfoout));
}
```

**Delay time calculation:**

```
Base delay (tm) = 0.01 seconds (10 ms)
Depth = 0.3 (30%)
LFO output = -1 to +1

Voice delays:
  LFO at -1.0: time = 0.01 × (1 + 0.3×(-1)) = 0.01 × 0.7 = 7 ms
  LFO at  0.0: time = 0.01 × (1 + 0.3×0) = 0.01 × 1.0 = 10 ms
  LFO at +1.0: time = 0.01 × (1 + 0.3×1) = 0.01 × 1.3 = 13 ms
```

Each voice sweeps 7-13 ms, but at different phases, creating complex modulation.

### SIMD Processing Loop

The core processing uses SSE for efficiency:

```cpp
// From: src/common/dsp/effects/ChorusEffectImpl.h:119

for (int k = 0; k < BLOCK_SIZE; k++)
{
    auto L = SIMD_MM(setzero_ps)(), R = SIMD_MM(setzero_ps)();

    // Process all 4 voices
    for (int j = 0; j < v; j++)
    {
        time[j].process();  // Update delay time
        float vtime = time[j].v;

        // Calculate read position
        int i_dtime = max(BLOCK_SIZE, min((int)vtime,
                                          max_delay_length - FIRipol_N - 1));
        int rp = ((wpos - i_dtime + k) - FIRipol_N) & (max_delay_length - 1);
        int sinc = FIRipol_N * limit_range((int)(FIRipol_M *
                                                 (float(i_dtime + 1) - vtime)),
                                           0, FIRipol_M - 1);

        // FIR interpolation (12-point sinc)
        SIMD_M128 vo;
        vo = SIMD_MM(mul_ps)(SIMD_MM(load_ps)(&storage->sinctable1X[sinc]),
                             SIMD_MM(loadu_ps)(&buffer[rp]));
        vo = SIMD_MM(add_ps)(vo,
                             SIMD_MM(mul_ps)(SIMD_MM(load_ps)(&storage->sinctable1X[sinc + 4]),
                                             SIMD_MM(loadu_ps)(&buffer[rp + 4])));
        vo = SIMD_MM(add_ps)(vo,
                             SIMD_MM(mul_ps)(SIMD_MM(load_ps)(&storage->sinctable1X[sinc + 8]),
                                             SIMD_MM(loadu_ps)(&buffer[rp + 8])));

        // Pan voice to stereo
        L = SIMD_MM(add_ps)(L, SIMD_MM(mul_ps)(vo, voicepanL4[j]));
        R = SIMD_MM(add_ps)(R, SIMD_MM(mul_ps)(vo, voicepanR4[j]));
    }

    // Horizontal sum of SSE vectors
    L = mech::sum_ps_to_ss(L);
    R = mech::sum_ps_to_ss(R);
    SIMD_MM(store_ss)(&tbufferL[k], L);
    SIMD_MM(store_ss)(&tbufferR[k], R);
}
```

**What this does:**

1. For each sample `k` in the block:
   - Accumulate all 4 voices into SSE vectors `L` and `R`
   - Each voice reads from delay buffer with sinc interpolation
   - Pan each voice according to pre-computed positions

2. The sinc interpolation uses **3 SSE multiply-add operations**:
   - First 4 FIR taps: `buffer[rp..rp+3]` × `sinctable[sinc..sinc+3]`
   - Next 4 taps: `buffer[rp+4..rp+7]` × `sinctable[sinc+4..sinc+7]`
   - Last 4 taps: `buffer[rp+8..rp+11]` × `sinctable[sinc+8..sinc+11]`
   - Sum all = 12-point convolution

3. Sum across SSE vector to scalar for each channel

### Feedback Processing

```cpp
// From: src/common/dsp/effects/ChorusEffectImpl.h:161

mech::add_block<BLOCK_SIZE>(tbufferL, tbufferR, fbblock);  // Sum L+R
feedback.multiply_block(fbblock, BLOCK_SIZE_QUAD);          // Scale
sdsp::hardclip_block<BLOCK_SIZE>(fbblock);                  // Prevent runaway
mech::accumulate_from_to<BLOCK_SIZE>(dataL, fbblock);       // Add to input
mech::accumulate_from_to<BLOCK_SIZE>(dataR, fbblock);
```

**Feedback implementation:**

1. **Sum stereo to mono**: `fbblock = L + R`
2. **Scale by feedback amount**: `fbblock *= 0.5 * amp_to_linear(feedback_param)`
3. **Hard clip**: Limit to ±1.0
4. **Add to both input channels**: Mono feedback to stereo input

**Why mono feedback?**

Chorus feedback is typically mono to:
- Simplify processing
- Prevent stereo buildup issues
- Match classic analog chorus behavior (single BBD chip with mono feedback)

### Filter Processing

```cpp
// From: src/common/dsp/effects/ChorusEffectImpl.h:151

if (!fxdata->p[ch_highcut].deactivated)
{
    lp.process_block(tbufferL, tbufferR);
}

if (!fxdata->p[ch_lowcut].deactivated)
{
    hp.process_block(tbufferL, tbufferR);
}
```

Both filters process the **delayed (wet) signal before mixing**, simulating BBD frequency response.

**Filter coefficients:**

```cpp
// From: src/common/dsp/effects/ChorusEffectImpl.h:75

hp.coeff_HP(hp.calc_omega(lowcut_param / 12.0), 0.707);
lp.coeff_LP2B(lp.calc_omega(highcut_param / 12.0), 0.707);
```

- **Q = 0.707**: Butterworth response (maximally flat)
- **calc_omega()**: Converts semitones to radians/sample
- **HP and LP2B**: 2-pole filters (-12 dB/octave rolloff)

### Default Values

```cpp
// From: src/common/dsp/effects/ChorusEffectImpl.h:262

fxdata->p[ch_time].val.f = -6.f;        // ~15.6 ms delay
fxdata->p[ch_rate].val.f = -2.f;        // Slow LFO (~1 Hz)
fxdata->p[ch_depth].val.f = 0.3f;       // 30% depth
fxdata->p[ch_feedback].val.f = 0.5f;    // 50% feedback
fxdata->p[ch_lowcut].val.f = -3.f * 12.f;   // -36 semitones (~110 Hz)
fxdata->p[ch_highcut].val.f = 3.f * 12.f;   // +36 semitones (~3.5 kHz)
fxdata->p[ch_mix].val.f = 1.f;          // 100% wet
fxdata->p[ch_width].val.f = 0.f;        // Natural stereo width
```

## Flanger Effect

The **Flanger Effect** creates a sweeping, "jet plane" comb filter effect through very short modulated delays with feedback. Surge implements sophisticated **through-zero flanging** with multiple voices.

**Implementation**: SST effects library (`sst::effects::flanger::Flanger`)
**Source**: `/home/user/surge/src/common/dsp/effects/FlangerEffect.cpp`

### Theory of Flanging

Flanging creates a **comb filter** by mixing a signal with a very short delayed copy:

```
Output = Input + Delayed(Input)
```

When delay time sweeps, the comb frequencies move, creating the characteristic sweep.

**Comb filter math:**

```
Delay time: τ seconds
Frequency response has nulls at: f = (2n+1)/(2τ) for n = 0, 1, 2, ...
Peaks at: f = n/τ
```

**Example with 1 ms delay (τ = 0.001):**

```
Nulls at: 500 Hz, 1500 Hz, 2500 Hz, 3500 Hz, ...
Peaks at: 0 Hz, 1000 Hz, 2000 Hz, 3000 Hz, ...
```

As delay sweeps from 0.5 ms to 5 ms, these notches sweep down:

```
At 0.5 ms: First null at 1000 Hz
At 1.0 ms: First null at 500 Hz
At 2.0 ms: First null at 250 Hz
At 5.0 ms: First null at 100 Hz
```

### Through-Zero Flanging

**Through-zero** allows the delay time to cross 0, creating inverted comb filters:

**Positive delay:**
```
Output = Input + Delayed(Input)
Peaks at 0 Hz, 1 kHz, 2 kHz, ...
```

**Negative delay (future samples):**
```
Output = Input + Advanced(Input)
      = Input + (Input - Delayed(-Input))
Nulls at 0 Hz, 1 kHz, 2 kHz, ... (inverted response)
```

**Implementation** requires buffering input to access "future" samples:

```cpp
// Simplified concept
float buffer[LOOKAHEAD];
int writePos = 0;

// Write with lookahead
buffer[(writePos + LOOKAHEAD/2) % LOOKAHEAD] = input;

// Read can go "backwards" from center
int readPos = (writePos + LOOKAHEAD/2 + delaySamples) % LOOKAHEAD;
float output = buffer[readPos];
```

This allows `delaySamples` to be negative (reading from before the center point).

### Parameters

```cpp
// From: src/common/dsp/effects/FlangerEffect.cpp:58

enum flanger_params {
    fl_mode,             // Flanger algorithm mode
    fl_wave,             // LFO waveform
    fl_rate,             // LFO rate
    fl_depth,            // LFO depth
    fl_voices,           // Number of voices (1-4)
    fl_voice_basepitch,  // Base delay time (as pitch)
    fl_voice_spacing,    // Spacing between voices
    fl_feedback,         // Feedback amount
    fl_damping,          // HF damping in feedback
    fl_width,            // Stereo width
    fl_mix,              // Dry/wet mix (bipolar!)
};
```

### Flanger Modes

```cpp
fxdata->p[fl_mode].set_type(ct_flangermode);
```

Surge's flanger offers multiple algorithms:
1. **Classic**: Traditional comb filtering
2. **Doppler**: Physical doppler shift simulation
3. **Arpeggio**: Quantized, musical interval flanging
4. **Stepped**: Discrete, rhythmic movements

Each mode interprets the LFO differently to create distinct characters.

### Multi-Voice Combs

```cpp
fxdata->p[fl_voices].set_type(ct_flangervoices);  // 1 to 4 voices
fxdata->p[fl_voice_basepitch].set_type(ct_flangerpitch);
fxdata->p[fl_voice_spacing].set_type(ct_flangerspacing);
```

**Multi-voice architecture:**

Instead of a single sweeping comb, Surge uses **multiple voices** at different base delay times:

```
Voice 1: 0.5 ms sweeping ±0.2 ms → 0.3 to 0.7 ms
Voice 2: 0.7 ms sweeping ±0.2 ms → 0.5 to 0.9 ms
Voice 3: 1.0 ms sweeping ±0.2 ms → 0.8 to 1.2 ms
Voice 4: 1.4 ms sweeping ±0.2 ms → 1.2 to 1.6 ms
```

Each creates a comb filter at different frequencies, resulting in:
- More complex spectral movement
- Richer, thicker flanging
- Less pronounced individual notches (smoother sound)

**Voice spacing** controls the interval between voice base pitches:
- Linear: Equal spacing in milliseconds
- Logarithmic: Musical intervals (octaves, fifths)
- Harmonic: Integer ratios

### LFO Waveforms

```cpp
fxdata->p[fl_wave].set_type(ct_fxlfowave);
```

Available waveforms:
- **Sine**: Smooth, classic flanging
- **Triangle**: Linear sweep, slightly sharper
- **Sawtooth**: Rapid rise, slow fall (or vice versa)
- **Square**: Abrupt jumps (stepped effect)
- **Sample & Hold**: Random values (chaotic flanging)

### Feedback and Damping

```cpp
fxdata->p[fl_feedback].set_type(ct_percent);
fxdata->p[fl_damping].set_type(ct_percent);
```

**Feedback** intensifies the comb filter:
- 0%: Subtle comb filtering
- 50%: Moderate resonance
- 95%: Extreme, metallic resonance

**Damping** prevents harsh high-frequency buildup:

```cpp
// Conceptual feedback with damping
float feedback_signal = delay_output * feedback_amount;
feedback_signal = one_pole_lowpass(feedback_signal, damping);
delay_input = input + feedback_signal;
```

Higher damping = more high-frequency rolloff in feedback path.

### Bipolar Mix

```cpp
fxdata->p[fl_mix].set_type(ct_percent_bipolar);
```

**Bipolar mix** allows phase inversion:

```
Mix = -100%: Output = Input - Delayed (inverted comb)
Mix =    0%: Output = Input (dry)
Mix = +100%: Output = Delayed (wet)
```

Negative mix creates **complementary comb filters**:
- Positive mix: Peaks at 0, 1k, 2k Hz
- Negative mix: Nulls at 0, 1k, 2k Hz (inverted)

### Parameter Groups

```cpp
// From: src/common/dsp/effects/FlangerEffect.cpp:27

group_label(0): "Modulation"     // Wave, rate, depth
group_label(1): "Combs"          // Voices, base pitch, spacing
group_label(2): "Feedback"       // Feedback, damping
group_label(3): "Output"         // Width, mix, mode
```

## Phaser Effect

The **Phaser Effect** creates sweeping notches using **all-pass filters** instead of delay lines. This produces a different character than flanging - smoother, more vocal-like filtering.

**Implementation**: SST effects library (`sst::effects::phaser::Phaser`)
**Source**: `/home/user/surge/src/common/dsp/effects/PhaserEffect.cpp`

### Theory of Phasing

**All-pass filters** have flat magnitude response but frequency-dependent phase shift:

```
Magnitude: |H(f)| = 1 for all frequencies (no amplitude change)
Phase: ∠H(f) varies with frequency
```

When an all-pass filtered signal mixes with the dry signal:

```
Output = Dry + AllPass(Dry)
```

Frequencies where phase shift = 180° **cancel** (destructive interference)
Frequencies where phase shift = 0° **reinforce** (constructive interference)

**Why this creates notches:**

At frequency f where all-pass causes 180° shift:
```
Dry: sin(2πft)
AllPass: sin(2πft + 180°) = -sin(2πft)
Sum: sin(2πft) + (-sin(2πft)) = 0  (cancellation!)
```

### Multi-Stage Phasing

Each **all-pass stage** creates one notch. Multiple stages create multiple notches:

```
1 stage:  1 notch
2 stages: 2 notches
4 stages: 4 notches
8 stages: 8 notches
```

**Surge supports 1-16 stages** for progressively more complex filtering.

**All-pass filter transfer function:**

```
H(z) = (z^-1 - a) / (1 - a×z^-1)

where: a = (1 - tan(π×fc/fs)) / (1 + tan(π×fc/fs))
       fc = cutoff frequency
       fs = sample rate
```

The cutoff determines where the 90° phase shift occurs (and thus the notch location when mixed).

### Parameters

```cpp
// From: src/common/dsp/effects/PhaserEffect.cpp:31

enum phaser_params {
    ph_mod_wave,      // LFO waveform
    ph_mod_rate,      // LFO rate
    ph_mod_depth,     // LFO depth (filter sweep range)
    ph_stereo,        // LFO stereo offset
    ph_stages,        // Number of all-pass stages (2-16)
    ph_spread,        // Frequency spread between stages
    ph_center,        // Center frequency
    ph_sharpness,     // Notch Q factor
    ph_feedback,      // Feedback amount
    ph_tone,          // Tilt EQ
    ph_width,         // Stereo width
    ph_mix,           // Dry/wet mix
};
```

### Stage Configuration

```cpp
fxdata->p[ph_stages].set_type(ct_phaser_stages);  // 1, 2, 4, 8, or 16 stages
```

**Stage count affects:**

1. **Number of notches**: n stages = n notches
2. **CPU usage**: 16 stages = 8× the processing of 2 stages
3. **Depth of notches**: More stages = deeper, sharper notches

**Why even numbers?**

Pairs of stages create deeper notches:
- 2 stages at same frequency: −∞ dB null (perfect cancellation)
- 4 stages (2 pairs): Two perfect nulls
- 8 stages (4 pairs): Four perfect nulls

### Spread and Sharpness

```cpp
fxdata->p[ph_spread].set_type(ct_percent);
fxdata->p[ph_sharpness].set_type(ct_percent_bipolar);
```

**Spread** spaces the notch frequencies:

```
Spread = 0%:   All stages at same frequency (one deep notch)
Spread = 50%:  Stages moderately spaced (harmonic series)
Spread = 100%: Stages widely spaced (linear spacing)
```

**Example with 8 stages, center = 1 kHz, spread = 50%:**

```
Stage 1: 1000 Hz
Stage 2: 1000 Hz (paired)
Stage 3: 1414 Hz  (×√2)
Stage 4: 1414 Hz
Stage 5: 2000 Hz  (×2)
Stage 6: 2000 Hz
Stage 7: 2828 Hz  (×2√2)
Stage 8: 2828 Hz
```

Creates 4 notches at 1k, 1.4k, 2k, 2.8k Hz.

**Sharpness** controls the notch Q:

```cpp
// All-pass coefficient with sharpness
a = (1 - Q×tan(π×fc/fs)) / (1 + Q×tan(π×fc/fs))
```

- **Sharpness = -100%**: Wide, gentle notches (low Q)
- **Sharpness = 0%**: Moderate notches
- **Sharpness = +100%**: Narrow, sharp notches (high Q)

### Stereo Modulation

```cpp
fxdata->p[ph_stereo].set_type(ct_percent);
```

**Stereo offset** phase-shifts the LFO between channels:

```cpp
// Left channel LFO
lfo_L = sin(2π × rate × t)

// Right channel LFO
lfo_R = sin(2π × rate × t + stereo × π)
```

**Stereo parameter:**
- 0%: LFOs in phase (mono sweep)
- 50%: LFOs 90° apart (quadrature)
- 100%: LFOs 180° apart (opposite sweep)

**Musical effect:**

```
Stereo = 0%:   Notches sweep together (focused, mono)
Stereo = 50%:  Notches sweep perpendicular (wide, spatial)
Stereo = 100%: Notches sweep oppositely (maximum width)
```

### Feedback

```cpp
fxdata->p[ph_feedback].set_type(ct_percent_bipolar);
```

Phaser feedback routes output back through the all-pass chain:

```
Input → AllPass1 → AllPass2 → ... → AllPassN → Output
           ↑                                       │
           └───────────── Feedback ────────────────┘
```

**Bipolar feedback:**
- **Positive**: Resonant peaks (emphasis)
- **Negative**: Anti-resonance (extra notching)
- **High amounts**: Can self-oscillate

**Feedback equation:**

```cpp
allpass_input = dry_input + feedback × allpass_output
```

At 90% feedback, the signal circles through the all-pass chain 10 times, creating extreme resonance at the notch boundaries.

### Tone Control

```cpp
fxdata->p[ph_tone].set_type(ct_percent_bipolar_deactivatable);
```

The **tone** parameter applies a gentle tilt EQ:
- **Negative**: Emphasize lows, reduce highs (darker)
- **0%**: Flat response
- **Positive**: Emphasize highs, reduce lows (brighter)

This shapes the overall character without affecting the phaser notches directly.

### Dynamic Deactivation

```cpp
// From: src/common/dsp/effects/PhaserEffect.cpp:33

static struct PhaserDeactivate : public ParameterDynamicDeactivationFunction
{
    bool getValue(const Parameter *p) const override
    {
        auto fx = &(p->storage->getPatch().fx[p->ctrlgroup_entry]);
        if (p - fx->p == ph_spread)
        {
            return fx->p[ph_stages].val.i == 1;  // Disable spread with 1 stage
        }
        return false;
    }
} phGroupDeact;
```

**Smart parameter management:**

When stages = 1, the spread parameter is **automatically disabled** (grayed out) since spread only makes sense with multiple stages.

### Parameter Groups

```cpp
// From: src/common/dsp/effects/PhaserEffect.cpp:100

group_label(0): "Modulation"     // Waveform, rate, depth, stereo
group_label(1): "Stages"         // Count, spread, center, sharpness
group_label(2): "Filter"         // Feedback, tone
group_label(3): "Output"         // Width, mix
```

## Rotary Speaker Effect

The **Rotary Speaker Effect** simulates a **Leslie speaker cabinet** - the rotating speaker system made famous by Hammond organs and widely used for guitar and vocals.

**Implementation**: SST effects library (`sst::effects::rotaryspeaker::RotarySpeaker`)
**Source**: `/home/user/surge/src/common/dsp/effects/RotarySpeakerEffect.cpp`

### Leslie Speaker Physics

A Leslie cabinet contains two rotating elements:

1. **Horn (Treble)**: High-frequency driver mounted on rotating baffle
   - Rotates at 40-400 RPM
   - Projects sound in one direction
   - Creates amplitude and pitch modulation

2. **Drum/Rotor (Bass)**: Low-frequency woofer in rotating drum
   - Rotates at 30-340 RPM (typically slower than horn)
   - Large drum with acoustic reflections
   - Deeper, slower modulation

**Physical effects:**

#### 1. Doppler Shift

As speaker rotates toward you: **pitch rises** (compressed wavelength)
As speaker rotates away: **pitch falls** (stretched wavelength)

**Doppler equation:**

```
f_perceived = f_source × (v_sound) / (v_sound - v_speaker)

For rotation:
v_speaker = 2π × radius × rpm / 60

Typical horn: radius = 0.2m, rpm = 400
v_speaker = 2π × 0.2 × 400 / 60 ≈ 8.4 m/s

At f_source = 1000 Hz, v_sound = 343 m/s:
  Approaching: f = 1000 × 343/(343-8.4) = 1025 Hz (+25 Hz)
  Receding:    f = 1000 × 343/(343+8.4) = 976 Hz (-24 Hz)

Total swing: ±2.5% pitch deviation
```

#### 2. Amplitude Modulation

When speaker faces you: **louder**
When speaker faces away: **quieter**

The rotating baffle acts like a directional beam:
- On-axis: Full level (0 dB)
- 90° off-axis: Reduced (-6 dB typical)
- 180° off-axis: Minimum (-12 dB typical)

**Tremolo waveform:**

The amplitude varies roughly sinusoidally at rotation rate:
```
Amplitude = 1.0 + tremolo_depth × sin(2π × rotation_rate × t)
```

#### 3. Frequency-Dependent Radiation

High frequencies are more directional:
- Treble horn: Tight beam (±30°)
- Bass drum: Wide dispersion (±180°)

This is why horn and drum rotate at different speeds - the bass doesn't need fast rotation since it radiates widely anyway.

### Parameters

```cpp
// From: src/common/dsp/effects/RotarySpeakerEffect.cpp:57

enum rotary_params {
    rot_horn_rate,    // Horn rotation speed
    rot_rotor_rate,   // Drum rotation speed (% of horn)
    rot_drive,        // Drive/distortion amount
    rot_waveshape,    // Distortion character
    rot_doppler,      // Doppler shift intensity
    rot_tremolo,      // Amplitude modulation intensity
    rot_width,        // Stereo width
    rot_mix,          // Dry/wet mix
};
```

### Dual Rotation System

```cpp
fxdata->p[rot_horn_rate].set_type(ct_lforate);
fxdata->p[rot_rotor_rate].set_type(ct_percent200);
```

**Two independent rotation rates:**

1. **Horn rate**: Main rotation speed (Hz or tempo-synced)
   - Chorale (slow): ~0.8 Hz (~48 RPM)
   - Tremolo (fast): ~6.7 Hz (~400 RPM)
   - Classic Leslie has mechanical switch between speeds

2. **Rotor rate**: Percentage of horn rate (0-200%)
   - Default: 70% (rotor spins slower than horn)
   - Classic ratio: Rotor ≈ 60-80% of horn speed
   - Can exceed 100% for unnatural effects

**Example:**

```
Horn rate: 5 Hz (300 RPM)
Rotor rate: 70%
Actual rotor: 5 × 0.7 = 3.5 Hz (210 RPM)
```

### Drive and Waveshaping

```cpp
fxdata->p[rot_drive].set_type(ct_rotarydrive);
fxdata->p[rot_waveshape].set_type(ct_distortion_waveshape);
```

Leslie speakers naturally distort, especially with organs:

**Drive** controls input gain before waveshaper:
- 0%: Clean (no distortion)
- 50%: Mild warmth
- 100%: Tube-like overdrive

**Waveshape** selects distortion algorithm:
- Soft: Smooth tube saturation
- Hard: Transistor-like clipping
- Asymmetric: Even-harmonic distortion
- Digital: Bit reduction effects

**Processing order:**

```
Input → Drive (gain) → Waveshaper → Rotary simulation → Output
```

### Doppler and Tremolo Controls

```cpp
fxdata->p[rot_doppler].set_type(ct_percent);
fxdata->p[rot_tremolo].set_type(ct_percent);
```

These scale the **intensity of the physical effects:**

**Doppler (0-100%):**
- 0%: No pitch modulation (just filtering)
- 50%: Reduced doppler (subtle)
- 100%: Full physical doppler shift (~±2.5%)

**Tremolo (0-100%):**
- 0%: No amplitude modulation
- 50%: Moderate tremolo
- 100%: Full amplitude sweep (~12 dB range)

**Why separate controls?**

Allows non-physical but musical settings:
- High doppler, low tremolo: Pitch vibrato only
- Low doppler, high tremolo: Classic tremolo effect
- Both high: Full Leslie simulation
- Both low: Mostly filtering/spatial

### Stereo Image

Classic Leslie has **two microphones** (or is stereo-miked):
- Left mic near one side of cabinet
- Right mic near other side

As speakers rotate, the sound pans between mics creating stereo movement.

**Implementation:**

```cpp
// Conceptual stereo positioning
float horn_angle = 2π × horn_rate × time;
float drum_angle = 2π × drum_rate × time;

// Horn contribution to stereo
horn_L = horn_signal × (0.5 + 0.5 × cos(horn_angle));
horn_R = horn_signal × (0.5 - 0.5 × cos(horn_angle));

// Drum contribution
drum_L = drum_signal × (0.5 + 0.5 × cos(drum_angle));
drum_R = drum_signal × (0.5 - 0.5 × cos(drum_angle));

output_L = horn_L + drum_L;
output_R = horn_R + drum_R;
```

The different rotation rates create complex, evolving stereo image.

### Crossover Network

A real Leslie splits audio into frequency bands:

```
Input ──┬──► High-pass ──► Horn (rotation)
        │
        └──► Low-pass ──► Drum (rotation)
```

Typical crossover: ~800 Hz

High frequencies go to fast horn, low frequencies to slower drum, matching the physical speaker arrangement.

### Default Values

```cpp
// From: src/common/dsp/effects/RotarySpeakerEffect.cpp:78

fxdata->p[rot_horn_rate].val_default.f = 2.f;        // ~2 Hz (120 RPM)
fxdata->p[rot_rotor_rate].val_default.f = 0.7f;      // 70% of horn
fxdata->p[rot_drive].val.f = 0.f;                    // No distortion
fxdata->p[rot_waveshape].val.i = 0;                  // Soft clipping
fxdata->p[rot_doppler].val.f = 1.0f;                 // Full doppler
fxdata->p[rot_tremolo].val.f = 1.0f;                 // Full tremolo
fxdata->p[rot_width].val.f = 1.f;                    // Natural width
fxdata->p[rot_mix].val.f = 1.f;                      // 100% wet
```

### Historical Context

```cpp
// From: src/common/dsp/effects/RotarySpeakerEffect.cpp:95

void RotarySpeakerEffect::handleStreamingMismatches(int streamingRevision,
                                                    int currentSynthStreamingRevision)
{
    if (streamingRevision <= 12)
    {
        // Old patches didn't have these parameters
        fxdata->p[rot_rotor_rate].val.f = 0.7;
        fxdata->p[rot_drive].val.f = 0.f;
        fxdata->p[rot_drive].deactivated = true;
        fxdata->p[rot_waveshape].val.i = 0;
        fxdata->p[rot_width].val.f = 1.f;
        fxdata->p[rot_mix].val.f = 1.f;
    }
}
```

This ensures patches created before streaming revision 12 load with appropriate defaults for the newer parameters.

### Parameter Groups

```cpp
// From: src/common/dsp/effects/RotarySpeakerEffect.cpp:26

group_label(0): "Speaker"        // Horn rate, rotor rate
group_label(1): "Amp"            // Drive, waveshape
group_label(2): "Modulation"     // Doppler, tremolo
group_label(3): "Output"         // Width, mix
```

## Advanced Topics

### Control Rate vs. Audio Rate

Surge processes effect parameters at **control rate** (1/8th audio rate):

```cpp
// From: src/common/dsp/Effect.h:127
const int slowrate = 8;  // Update controls every 8 samples
```

**Why?**

```cpp
void process(float *dataL, float *dataR)
{
    for (int k = 0; k < BLOCK_SIZE; k++)
    {
        if ((k & slowrate_m1) == 0)  // Every 8 samples
        {
            // Expensive operations
            updateLFOPhase();
            calculateFilterCoefficients();
            computeDelayTime();
        }

        // Audio processing every sample
        float delayed = readDelay(delayTime);
        output[k] = process(input[k], delayed);
    }
}
```

**Benefits:**
- CPU reduction: 87.5% fewer control calculations
- Aliasing prevention: Slow parameter changes naturally band-limited
- Smooth sound: Parameter smoothing interpolates between updates

**Trade-offs:**
- Maximum modulation rate: ~6 kHz (48 kHz ÷ 8)
- Fine enough for LFOs (usually < 100 Hz)
- Not suitable for audio-rate modulation

### Memory Layout and Alignment

```cpp
// From: src/common/dsp/effects/ChorusEffect.h:33

template <int v> class ChorusEffect : public Effect
{
    lipol_ps_blocksz feedback alignas(16), mix alignas(16), width alignas(16);
    SIMD_M128 voicepanL4 alignas(16)[v], voicepanR4 alignas(16)[v];
    float buffer alignas(16)[max_delay_length + FIRipol_N];
```

**16-byte alignment** for SSE operations:

SSE instructions require aligned memory:
```cpp
_mm_load_ps(&data[i]);   // Requires 16-byte alignment (fast)
_mm_loadu_ps(&data[i]);  // Unaligned load (slower)
```

**Why `max_delay_length + FIRipol_N`?**

FIR interpolation reads 12 samples ahead. Adding `FIRipol_N` padding at the end prevents wraparound issues:

```cpp
// Without padding
readPos = max_delay_length - 2;  // Near end
// Read positions: ..., max-2, max-1, max, (wrap to 0), 1, 2, ...
// Requires complex wraparound logic!

// With padding
// Read positions: ..., max-2, max-1, max, max+1, max+2, ...
// Can read linearly, copy wrapped data to padding
```

### Tempo Synchronization

Most modulation effects support tempo sync:

```cpp
// From tempo sync calculation
float rate = base_rate * (temposync ? temposyncratio : 1.f);
```

**`temposyncratio`** converts note values to Hz:

```
At 120 BPM:
  Quarter note = 120 / 60 = 2 Hz
  Eighth note = 4 Hz
  Sixteenth note = 8 Hz
  Dotted quarter = 1.33 Hz

temposyncratio scales parameter to match host tempo
```

**Musical delay times:**

```cpp
// From delay time with tempo sync
float tm = storage->note_to_pitch_ignoring_tuning(12 * time_param) *
           (temposync ? temposyncratio_inv : 1.f);
```

**Example at 140 BPM, eighth note delay:**

```
temposyncratio_inv = 60 / (140 × 4) ≈ 0.107 seconds
Parameter = 0.0 → tm = 1.0 × 0.107 = 0.107 s
Actual delay = 0.107 × 48000 = 5,143 samples ≈ 107 ms
```

Perfect eighth note timing regardless of tempo changes!

### Preventing Denormals

Very small floating-point numbers (denormals) cause severe CPU slowdown. Time-based effects prevent this:

```cpp
// Add tiny DC offset to prevent denormals
const float anti_denormal = 1e-18f;

for (int k = 0; k < BLOCK_SIZE; k++)
{
    float signal = delayBuffer[readPos];
    signal += anti_denormal;  // Prevent denormal
    delayBuffer[writePos] = signal;
}
```

**Why denormals are slow:**

Normal float: `1.23 × 10^-3` (fast hardware path)
Denormal: `1.23 × 10^-40` (slow microcode path, 100× slower)

Adding `1e-18` keeps numbers above denormal threshold without audible effect.

## Practical Applications

### Creating Space with Delays

**Stereo delay for width:**
```
Left delay:  250 ms
Right delay: 375 ms (1.5× ratio)
Feedback: 40%
Crossfeed: 20%
Result: Wide, rhythmic space
```

**Slapback echo (classic rockabilly):**
```
Time: 80-120 ms (both channels)
Feedback: 0-10%
Mix: 30-40%
Result: Thickening doubling effect
```

**Dub delay:**
```
Time: 1/4 note (tempo-synced)
Feedback: 70-80%
High cut: 2 kHz (dark repeats)
Low cut: 100 Hz (thin repeats)
Result: Infinite dub echo
```

### Chorus and Ensemble

**Subtle double-tracking:**
```
Chorus rate: 0.3 Hz
Depth: 10%
Mix: 20%
Voices: 4
Result: Natural thickening
```

**Lush pad widening:**
```
Chorus rate: 0.8 Hz
Depth: 40%
Mix: 60%
Feedback: 30%
Result: Shimmering ensemble
```

### Flanger Techniques

**Jet plane sweep:**
```
Rate: 0.2 Hz (slow sweep)
Depth: 100%
Feedback: 80% (resonant)
Voices: 1
Result: Classic jet whoosh
```

**Through-zero flanging:**
```
Mode: Doppler
Base pitch: Very short
Depth: Maximum
Feedback: 50%
Result: Barber pole flanging
```

### Phaser Settings

**Vocal phasing (talk box style):**
```
Stages: 4
Rate: 0.5 Hz
Center: 800 Hz
Sharpness: 60%
Feedback: -40% (negative)
Result: Vowel-like sweeps
```

**Extreme phase distortion:**
```
Stages: 16
Rate: 2 Hz
Spread: 80%
Feedback: 90%
Result: Metallic, robotic texture
```

### Rotary Speaker

**Classic organ (slow):**
```
Horn rate: 0.8 Hz (~48 RPM)
Rotor rate: 70%
Doppler: 100%
Tremolo: 100%
Drive: 20%
Result: Chorale Leslie
```

**Fast Leslie (tremolo):**
```
Horn rate: 6.7 Hz (~400 RPM)
Rotor rate: 70%
Doppler: 100%
Tremolo: 100%
Drive: 40%
Result: Full-speed Leslie
```

## Conclusion

Surge XT's time-based effects represent the culmination of decades of DSP research and musical refinement. From the pristine sinc interpolation in the Chorus effect to the sophisticated through-zero flanging and physical modeling in the Rotary Speaker, each effect demonstrates careful attention to both technical excellence and musical usability.

**Key architectural achievements:**

1. **Efficient delay lines**: Power-of-2 circular buffers with fast wraparound
2. **High-quality interpolation**: FIR sinc filtering for alias-free modulation
3. **SIMD optimization**: SSE processing for multi-voice effects
4. **Musical tempo sync**: Perfect rhythmic timing across all delay-based effects
5. **Flexible routing**: Feedback, crossfeed, and filtering for complex textures

**The SST effects library integration** provides professional-grade implementations while maintaining Surge's parameter system and SIMD optimizations. The Chorus effect's template-based design showcases how careful C++ programming creates both flexibility and performance.

Whether creating subtle space with a stereo delay, lush movement with multi-voice chorus, or the iconic swirl of a Leslie speaker, Surge's time-based effects provide the temporal and spatial dimensions that transform static synthesizer patches into living, breathing sounds.

---

**Next: [Reverb Effects](14-effects-reverb.md)**
**See Also: [Effects Architecture](12-effects-architecture.md), [Distortion Effects](15-effects-distortion.md)**
