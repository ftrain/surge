# Chapter 14: Reverb Effects

## Introduction

Reverberation is the soul of spatial audio - the complex acoustic phenomenon that tells us whether we're in a cathedral or a closet, a concert hall or a cave. Unlike simple delays that produce discrete echoes, reverb creates the dense, time-smeared reflection patterns that define real acoustic spaces.

Surge XT provides four sophisticated reverb algorithms, each with distinct characteristics and applications: **Reverb1** (classic algorithmic reverb), **Reverb2** (enhanced FDN architecture), **Spring Reverb** (physical spring simulation), and **Nimbus** (granular cloud reverb). Together, they span from pristine hall simulation to otherworldly textures.

This chapter explores the mathematics, implementation, and sonic character of each reverb, revealing how careful DSP design transforms dry signals into lush, three-dimensional soundscapes.

## Fundamental Reverb Theory

### The Anatomy of Reverberation

When sound propagates in an enclosed space, it undergoes complex reflection patterns that our ears perceive as reverb. This process divides into distinct temporal regions:

**1. Direct Sound** (0 ms)
The original sound reaching the listener without reflection. This provides source localization and timbral identity.

**2. Early Reflections** (0-80 ms)
The first few discrete reflections from nearby surfaces (walls, ceiling, floor). These:
- Define the perceived room size and geometry
- Provide spatial information about source location
- Remain somewhat distinct and separable by the ear
- Typically number 10-50 discrete echoes

**3. Late Reverberation** (80+ ms)
As reflections multiply exponentially, individual echoes blur into a dense, continuous wash:
- Reflections occur so rapidly they blend into smooth decay
- Loses directional information
- Characterized by exponential decay envelope
- Creates sense of envelopment and space

```
Amplitude
    |
    |  Direct  Early Reflections      Late Reverb (exponential decay)
    |   ↓      ↓ ↓  ↓ ↓ ↓ ↓          ↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓↓
    |   █      █ █  █ █ █ █          ░░░░░░░░░░░░░░░░░░░░░░
    |
    |                                 ░░░░░░░░░░
    |                                           ░░░░░
    |_________________________________________________ Time
    0ms     20ms    50ms   80ms              500ms      1000ms
```

### Key Reverb Parameters

**Decay Time (RT60)**

The time required for reverb to decay by 60 dB (1/1000th of original amplitude). This is the single most important reverb characteristic:

```
RT60 = decay time in seconds
Feedback gain g = 10^(-3T / (RT60 × fs))

Where:
  T = delay length in samples
  fs = sample rate
```

**Example calculation:**
```
Room with RT60 = 2.0 seconds
Delay line = 10,000 samples at 48 kHz
T = 10,000 / 48,000 = 0.208 seconds

g = 10^(-3 × 0.208 / 2.0) = 10^(-0.312) = 0.488
```

After each trip through the 10,000-sample delay:
- Signal amplitude multiplies by 0.488
- After ~13 cycles: signal reduced to 0.001 (-60 dB)
- Total time: 13 × 0.208s ≈ 2.7 seconds (approximately RT60)

**Diffusion**

The density of reflections in the reverb tail. High diffusion creates smooth, continuous reverb; low diffusion produces discrete echoes:

```
Low Diffusion:   █  █  █   █   █    █     █      █       █        (discrete)
High Diffusion:  ████████████████████████████████████████████████  (smooth)
```

Implemented via cascaded all-pass filters that scatter energy without changing spectrum.

**Pre-Delay**

Time delay before reverb onset, simulating distance from nearest reflective surface:

```
Short pre-delay (0-10 ms):  Small room, source near walls
Medium pre-delay (20-40 ms): Medium room or distant source
Long pre-delay (50-100 ms):  Large hall or very distant source
```

Pre-delay also separates dry signal from reverb, maintaining clarity.

**Damping**

Frequency-dependent absorption. High frequencies decay faster than lows, simulating:
- Air absorption (HF loss)
- Surface materials (carpet, curtains absorb HF more than LF)
- Natural acoustic behavior of all real spaces

Implemented as low-pass filtering in the feedback path.

### Building Blocks: Comb Filters

The **comb filter** is the fundamental reverb building block - a delay line with feedback:

```cpp
// Basic comb filter structure
float buffer[DELAY_LENGTH];
int writePos = 0;

float processComb(float input, float feedbackGain)
{
    // Read delayed sample
    float delayed = buffer[writePos];

    // Mix input with feedback
    float combined = input + feedbackGain * delayed;

    // Write to buffer
    buffer[writePos] = combined;

    // Advance write position (circular)
    writePos = (writePos + 1) % DELAY_LENGTH;

    return delayed;  // Output is the delayed signal
}
```

**Frequency response:**

Comb filters create evenly-spaced peaks and notches in the spectrum:

```
Peak spacing = fs / delay_length

Example: 1000-sample delay at 48 kHz
  Peak spacing = 48000 / 1000 = 48 Hz
  Peaks at: 48 Hz, 96 Hz, 144 Hz, 192 Hz, ...
  Notches at: 24 Hz, 72 Hz, 120 Hz, 168 Hz, ...
```

The "comb" name comes from the teeth-like frequency response.

**Multiple parallel combs** with different delay lengths create denser, more natural-sounding reverb by filling in the spectral gaps.

### Building Blocks: All-Pass Filters

**All-pass filters** pass all frequencies equally (flat magnitude response) but introduce frequency-dependent phase shifts. This scatters temporal energy without coloring the spectrum:

```cpp
// Schroeder all-pass filter
// From: src/common/dsp/effects/chowdsp/spring_reverb/SchroederAllpass.h:59

inline T processSample(T x) noexcept
{
    auto delayOut = delay.popSample(0);
    x += g * delayOut;              // Feedforward
    delay.pushSample(0, x);
    return delayOut - g * x;        // Feedback
}
```

**Transfer function:**

```
H(z) = (g + z^-M) / (1 + g × z^-M)

Where:
  M = delay length in samples
  g = feedback/feedforward coefficient (-1 < g < 1)
```

**Why all-pass?**

```
|H(f)| = 1 for all frequencies  (flat magnitude)
∠H(f) = phase varies with frequency (disperses reflections)
```

All-pass filters provide **diffusion** - they increase reflection density without changing timbre. Cascading multiple all-pass stages creates very dense reverb tails.

### Feedback Delay Networks (FDN)

A **Feedback Delay Network** connects multiple delay lines in a matrix topology, allowing energy to circulate and exchange between channels:

```
         ┌──────────────────────────────┐
Input ──→│                              │
         │  ┌─────┐    ┌─────┐         │
         │  │ D1  │───→│     │         │──→ Output L
         │  └─────┘    │     │         │
         │             │  M  │         │
         │  ┌─────┐    │  I  │         │
         │  │ D2  │───→│  X  │         │──→ Output R
         │  └─────┘    │     │         │
         │             │  M  │         │
         │  ┌─────┐    │  A  │         │
         │  │ D3  │───→│  T  │         │
         │  └─────┘    │  R  │         │
         │             │  I  │         │
         │  ┌─────┐    │  X  │         │
         │  │ D4  │───→│     │         │
         │  └─────┘    └─────┘         │
         │      ↑                       │
         └──────┴───────────────────────┘
              Feedback
```

**The mixing matrix** redistributes energy between delay lines, preventing periodic buildup and creating natural-sounding diffusion.

**Householder matrix** (used in Spring Reverb reflection network):

```cpp
// From: src/common/dsp/effects/chowdsp/spring_reverb/ReflectionNetwork.h:81

constexpr auto householderFactor = -2.0f / (float)4;
const auto sumXhh = vSum(outVec) * householderFactor;
outVec = SIMD_MM(add_ps)(outVec, SIMD_MM(load1_ps)(&sumXhh));
```

The Householder matrix is **unitary** (preserves energy) and **diffusive** (scatters reflections evenly), making it ideal for reverb networks.

### Preventing Resonance and Flutter

Simple delay networks can produce unnatural **ringing** at their resonant frequencies. Mitigation strategies:

1. **Prime-number delay lengths** - Prevents harmonic alignment
   ```cpp
   delayLengths = {1009, 1997, 2503, 3001};  // All prime
   ```

2. **Slight modulation** - Breaks up static resonances
   ```cpp
   delayTime = baseDelay + LFO() * modulationDepth;
   ```

3. **Damping filters** - Frequency-dependent decay suppresses resonance
   ```cpp
   feedback = lowpass(feedback, cutoffFreq);
   ```

4. **All-pass diffusion** - Scatters energy temporally

## Reverb1 Effect

Surge's **Reverb1** is a classic algorithmic reverb based on the time-tested architecture pioneered by Schroeder and Moorer. It provides pristine, transparent reverberation suitable for everything from subtle room ambience to cathedral-sized halls.

### Architecture Overview

Reverb1 uses the **sst-effects** library implementation:

```cpp
// From: src/common/dsp/effects/Reverb1Effect.h:30
class Reverb1Effect : public surge::sstfx::SurgeSSTFXBase<
                          sst::effects::reverb1::Reverb1<surge::sstfx::SurgeFXConfig>>
```

The effect processes in this signal flow:

```
Input → Pre-Delay → Early Reflections → FDN Core → Damping → EQ → Width → Mix → Output
```

**Key architectural features:**

1. **Variable pre-delay** (up to ~1 second)
2. **Shapeable room character** (via Shape parameter)
3. **FDN core** with multiple delay lines
4. **Frequency-dependent damping**
5. **3-band EQ** in reverb path
6. **Stereo width control**

### Parameter Reference

Reverb1 provides 11 parameters organized into 4 groups:

#### Pre-Delay Group

**Pre-Delay** (`rev1_predelay`)
- **Type**: `ct_envtime` (envelope time)
- **Range**: Short (a few ms) to long (~1 second)
- **Default**: -4 (approximately 20 ms)
- **Function**: Delays reverb onset, simulating distance to first reflection

```cpp
// From: src/common/dsp/effects/Reverb1Effect.cpp:71
fxdata->p[rev1_predelay].set_type(ct_envtime);
fxdata->p[rev1_predelay].val.f = -4.f;
```

Time conversion uses exponential scaling:
```
actualTime = 2^(parameter/12) seconds
Example: -4 → 2^(-4/12) = 0.794 × base = ~20 ms
```

**Usage tips:**
- 0-10 ms: Small rooms, tight spaces
- 20-40 ms: Medium rooms, preserves clarity
- 50-100 ms: Large halls, dramatic separation
- 100+ ms: Special effects, obvious delay

#### Reverb Group

**Shape** (`rev1_shape`)
- **Type**: `ct_reverbshape` (reverb shape selector)
- **Range**: Multiple shape options
- **Default**: 0
- **Function**: Selects fundamental reverb character/algorithm variant

```cpp
fxdata->p[rev1_shape].set_type(ct_reverbshape);
```

Different shapes adjust the internal delay line topology and feedback routing, providing distinct reverb characters from tight and focused to diffuse and expansive.

**Room Size** (`rev1_roomsize`)
- **Type**: `ct_percent` (0-100%)
- **Range**: 0% (small) to 100% (huge)
- **Default**: 50%
- **Function**: Scales all delay lines proportionally

```cpp
fxdata->p[rev1_roomsize].set_type(ct_percent);
fxdata->p[rev1_roomsize].val.f = 0.5f;
```

Room size affects delay lengths in the FDN:
```
actualDelay = baseDelay × (roomSize + minScale)
```

Larger rooms = longer delays = lower modal density = more spacious character.

**Decay Time** (`rev1_decaytime`)
- **Type**: `ct_reverbtime` (reverb decay time)
- **Range**: 0.1 seconds to 10+ seconds
- **Default**: 1.0 second
- **Function**: RT60 decay time

```cpp
fxdata->p[rev1_decaytime].set_type(ct_reverbtime);
fxdata->p[rev1_decaytime].val.f = 1.f;
```

Directly controls feedback gain in delay lines:
```
feedbackGain = 10^(-3 × delayTime / (RT60 × sampleRate))
```

**Damping** (`rev1_damping`)
- **Type**: `ct_percent` (0-100%)
- **Range**: 0% (bright, no damping) to 100% (dark, heavy damping)
- **Default**: 20%
- **Function**: High-frequency absorption via low-pass filtering

```cpp
fxdata->p[rev1_damping].set_type(ct_percent);
fxdata->p[rev1_damping].val.f = 0.2f;
```

Higher damping = lower cutoff frequency = faster HF decay, simulating absorptive materials.

#### EQ Group

Reverb1 includes a flexible EQ section to shape the reverb spectrum independently from the dry signal:

**Low Cut** (`rev1_lowcut`)
- **Type**: `ct_freq_audible_deactivatable_hp` (deactivatable high-pass)
- **Range**: 20 Hz to 20 kHz (or deactivated)
- **Default**: -24 dB (~80 Hz)
- **Function**: High-pass filter removes low-frequency rumble

```cpp
fxdata->p[rev1_lowcut].set_type(ct_freq_audible_deactivatable_hp);
fxdata->p[rev1_lowcut].val.f = -24.0f;
fxdata->p[rev1_lowcut].deactivated = false;
```

**Frequency 1** (`rev1_freq1`)
- **Type**: `ct_freq_audible` (20 Hz - 20 kHz)
- **Range**: Full audible spectrum
- **Default**: 0.0 (center frequency, ~1 kHz)
- **Function**: Center frequency for parametric bell/shelf

**Gain 1** (`rev1_gain1`)
- **Type**: `ct_decibel` (-48 dB to +48 dB)
- **Range**: Cut or boost
- **Default**: 0 dB (no change)
- **Function**: Gain at Frequency 1

These form a parametric EQ band:
```
Boost at 200 Hz: Warm, full reverb
Cut at 500 Hz: Reduce boxiness
Boost at 4 kHz: Bright, airy reverb
```

**High Cut** (`rev1_highcut`)
- **Type**: `ct_freq_audible_deactivatable_lp` (deactivatable low-pass)
- **Range**: 20 Hz to 20 kHz (or deactivated)
- **Default**: 72 dB (~16 kHz)
- **Function**: Low-pass filter tames excessive brightness

```cpp
fxdata->p[rev1_highcut].set_type(ct_freq_audible_deactivatable_lp);
fxdata->p[rev1_highcut].val.f = 72.0f;
```

#### Output Group

**Mix** (`rev1_mix`)
- **Type**: `ct_percent` (0-100%)
- **Range**: 0% (dry only) to 100% (wet only)
- **Default**: 50% (equal mix)
- **Function**: Dry/wet balance

```cpp
fxdata->p[rev1_mix].set_type(ct_percent);
fxdata->p[rev1_mix].val.f = 0.5f;
```

For send/return chains, set Mix to 100% (pure wet).

**Width** (`rev1_width`)
- **Type**: `ct_decibel_narrow` (±12 dB range)
- **Range**: Narrow to wide stereo
- **Default**: 0 dB (original width)
- **Function**: Stereo width control via Mid/Side processing

```cpp
fxdata->p[rev1_width].set_type(ct_decibel_narrow);
fxdata->p[rev1_width].val.f = 0.0f;
```

Positive values increase width; negative values narrow toward mono.

### Using Reverb1

**Classic Hall Reverb:**
```
Pre-Delay:  40 ms
Shape:      Type 2 (diffuse)
Room Size:  75%
Decay Time: 2.5 seconds
Damping:    30%
Low Cut:    100 Hz
High Cut:   14 kHz
Mix:        25%
Width:      +3 dB
```

**Tight Room Ambience:**
```
Pre-Delay:  10 ms
Shape:      Type 0 (focused)
Room Size:  25%
Decay Time: 0.8 seconds
Damping:    50%
Low Cut:    200 Hz
High Cut:   10 kHz
Mix:        15%
Width:      0 dB
```

**Shimmer/Special FX:**
```
Pre-Delay:  80 ms
Shape:      Type 3
Room Size:  90%
Decay Time: 8 seconds
Damping:    5%
Freq 1:     4 kHz
Gain 1:     +6 dB (boost highs)
High Cut:   Deactivated
Mix:        40%
Width:      +6 dB
```

## Reverb2 Effect

**Reverb2** is an enhanced reverb algorithm with more control over the reverb's internal structure. It provides deeper parameter access to the FDN core, offering more surgical control over room character and decay behavior.

### Architecture Overview

Like Reverb1, Reverb2 uses the sst-effects library:

```cpp
// From: src/common/dsp/effects/Reverb2Effect.h:36
struct Reverb2Effect : public surge::sstfx::SurgeSSTFXBase<
                           sst::effects::reverb2::Reverb2<surge::sstfx::SurgeFXConfig>>
```

**Key differences from Reverb1:**

1. **Bipolar Room Size** - Negative values provide alternative delay line ratios
2. **Explicit Diffusion control** - Direct control over all-pass density
3. **Buildup parameter** - Controls early reflection density
4. **Modulation** - Internal chorus-like modulation of delay lines
5. **Dual damping** - Separate HF and LF damping controls
6. **No shape selector** - More continuous, parametric control

### Parameter Reference

Reverb2 provides 10 parameters across 4 groups:

#### Pre-Delay Group

**Pre-Delay** (`rev2_predelay`)
- **Type**: `ct_reverbpredelaytime` (reverb pre-delay time)
- **Range**: Short to long (similar to Reverb1)
- **Function**: Initial delay before reverb

```cpp
// From: src/common/dsp/effects/Reverb2Effect.cpp:68
fxdata->p[rev2_predelay].set_name("Pre-Delay");
fxdata->p[rev2_predelay].set_type(ct_reverbpredelaytime);
```

#### Reverb Group

**Room Size** (`rev2_room_size`)
- **Type**: `ct_percent_bipolar` (-100% to +100%)
- **Range**: Bipolar control
- **Default**: 0% (medium)
- **Function**: Bipolar room size control

```cpp
fxdata->p[rev2_room_size].set_name("Room Size");
fxdata->p[rev2_room_size].set_type(ct_percent_bipolar);
```

**Bipolar behavior:**
- Negative values: Shorter delays, tighter ratios, focused character
- Zero: Balanced delay lengths
- Positive values: Longer delays, wider ratios, spacious character

This provides fundamentally different room topologies beyond just scaling.

**Decay Time** (`rev2_decay_time`)
- **Type**: `ct_reverbtime` (0.1 to 10+ seconds)
- **Function**: RT60 decay time

```cpp
fxdata->p[rev2_decay_time].set_name("Decay Time");
fxdata->p[rev2_decay_time].set_type(ct_reverbtime);
```

**Diffusion** (`rev2_diffusion`)
- **Type**: `ct_percent` (0-100%)
- **Range**: 0% (discrete echoes) to 100% (smooth reverb)
- **Default**: 50-70% typical
- **Function**: Controls all-pass filter density and feedback

```cpp
fxdata->p[rev2_diffusion].set_name("Diffusion");
fxdata->p[rev2_diffusion].set_type(ct_percent);
```

Low diffusion creates **plate reverb**-like character with audible discrete echoes. High diffusion creates smooth, hall-like tails.

**Buildup** (`rev2_buildup`)
- **Type**: `ct_percent` (0-100%)
- **Range**: Fast to slow buildup
- **Default**: ~50%
- **Function**: Controls early reflection density and attack

```cpp
fxdata->p[rev2_buildup].set_name("Buildup");
fxdata->p[rev2_buildup].set_type(ct_percent);
```

- Low values: Fast buildup, immediate full reverb
- High values: Gradual buildup, reverb "blooms" slowly

This affects the early-to-late reverb transition character.

**Modulation** (`rev2_modulation`)
- **Type**: `ct_percent` (0-100%)
- **Range**: None to heavy modulation
- **Default**: Low (5-15%)
- **Function**: Internal LFO modulation of delay lines

```cpp
fxdata->p[rev2_modulation].set_name("Modulation");
fxdata->p[rev2_modulation].set_type(ct_percent);
```

Adds subtle chorus-like movement to the reverb tail:
- 0%: Static, pristine (can sound slightly metallic)
- 5-15%: Natural movement, reduces metallic artifacts
- 30%+: Obvious chorus/shimmer effect

#### EQ Group

**HF Damping** (`rev2_hf_damping`)
- **Type**: `ct_percent` (0-100%)
- **Range**: Bright to dark
- **Function**: High-frequency absorption (low-pass filtering)

```cpp
fxdata->p[rev2_hf_damping].set_name("HF Damping");
fxdata->p[rev2_hf_damping].set_type(ct_percent);
```

**LF Damping** (`rev2_lf_damping`)
- **Type**: `ct_percent` (0-100%)
- **Range**: Full bass to reduced bass
- **Function**: Low-frequency absorption (high-pass filtering)

```cpp
fxdata->p[rev2_lf_damping].set_name("LF Damping");
fxdata->p[rev2_lf_damping].set_type(ct_percent);
```

Dual damping provides independent control over bass and treble decay:
```
HF Damping = 70%, LF Damping = 30%:
  High frequencies decay quickly (dark reverb)
  Low frequencies decay slowly (warm, full tail)

HF Damping = 10%, LF Damping = 60%:
  High frequencies sustain (bright reverb)
  Low frequencies decay quickly (thin, clear tail)
```

#### Output Group

**Width** (`rev2_width`)
- **Type**: `ct_decibel_narrow` (±12 dB)
- **Function**: Stereo width control

**Mix** (`rev2_mix`)
- **Type**: `ct_percent` (0-100%)
- **Function**: Dry/wet balance

### Using Reverb2

**Natural Concert Hall:**
```
Pre-Delay:    50 ms
Room Size:    +40%
Decay Time:   3.0 seconds
Diffusion:    75%
Buildup:      60%
Modulation:   8%
HF Damping:   40%
LF Damping:   20%
Width:        +4 dB
Mix:          30%
```

**Plate Reverb Simulation:**
```
Pre-Delay:    5 ms
Room Size:    -30% (tight ratios)
Decay Time:   2.0 seconds
Diffusion:    35% (low for discrete echoes)
Buildup:      20% (fast attack)
Modulation:   2%
HF Damping:   15%
LF Damping:   50% (thin out lows)
Width:        +6 dB
Mix:          25%
```

**Ambient Wash:**
```
Pre-Delay:    100 ms
Room Size:    +70%
Decay Time:   6.0 seconds
Diffusion:    90%
Buildup:      80% (slow bloom)
Modulation:   25% (obvious shimmer)
HF Damping:   10% (bright)
LF Damping:   40%
Width:        +8 dB
Mix:          45%
```

## Spring Reverb (Chowdsp)

The **Spring Reverb** is a physically-informed model of the classic electromechanical spring reverb found in guitar amplifiers and vintage effects units. Unlike algorithmic reverbs that use abstract delay networks, Spring Reverb models the actual physical behavior of vibrating springs.

### Physical Spring Behavior

Real spring reverbs work by converting audio into mechanical vibrations:

1. **Transducer** converts electrical signal to mechanical energy
2. **Spring(s)** propagate vibrations with frequency-dependent dispersion
3. **Pickup** converts mechanical vibrations back to electrical signal

**Key physical characteristics:**

- **Dispersion**: High frequencies travel faster than low frequencies through the spring
- **Modal resonances**: Springs have natural resonant frequencies
- **Non-linear behavior**: Springs can saturate and distort
- **Transients**: "Boing" sound when struck (spring shake/knock)

### Architecture Overview

The Spring Reverb implementation is based on research papers by Välimäki, Parker, and Abel:

```cpp
// From: src/common/dsp/effects/chowdsp/SpringReverbEffect.h:34-44
/*
** SpringReverb is a spring reverb emulation, based loosely
** on the reverb structures described in the following papers:
** -  V. Valimaki, J. Parker, and J. S. Abel, "Parametric spring
**    reverberation effect," Journal of the Audio Engineering Society, 2010
**
** - Parker, Julian, "Efficient Dispersion Generation Structures for
**   Spring Reverb Emulation", EURASIP, 2011
*/
```

**Signal flow:**

```
Input → Reflection Network → Delay + Feedback → Allpass Cascade → Damping → Output
           (early echoes)         (spring)        (dispersion)      (HF loss)
```

**Core components:**

1. **Reflection Network**: Early reflections simulating spring mounting hardware
2. **Main delay line**: Core spring propagation delay
3. **16-stage Schroeder all-pass cascade**: Creates frequency-dependent dispersion
4. **Feedback path**: Sustains reverb with controllable decay
5. **Low-pass filter**: Simulates high-frequency damping
6. **Shake/knock generator**: Transient excitation

### Implementation Details

**Schroeder All-Pass Cascade**

The dispersion (frequency-dependent delay) is created using 16 nested all-pass filters:

```cpp
// From: src/common/dsp/effects/chowdsp/spring_reverb/SpringReverbProc.h:65-67
static constexpr int allpassStages = 16;
using VecType = sst::basic_blocks::simd::F32x4;
using APFCascade = std::array<SchroederAllpass<VecType, 2>, allpassStages>;
```

Each stage uses **2nd-order nested all-pass** filters, processed with SIMD for efficiency:

```cpp
// From: src/common/dsp/effects/chowdsp/spring_reverb/SchroederAllpass.h:35
template <typename T = float, int order = 1> class SchroederAllpass
{
  public:
    inline T processSample(T x) noexcept
    {
        auto delayOut = nestedAllpass.processSample(delay.popSample(0));
        x += g * delayOut;              // Feedforward
        delay.pushSample(0, x);
        return delayOut - g * x;        // Feedback
    }

  private:
    DelayLine<T, DelayLineInterpolationTypes::Thiran> delay{1 << 18};
    SchroederAllpass<T, order - 1> nestedAllpass;  // Recursive nesting
    T g;  // Feedback coefficient
};
```

**Why 16 stages?**
- More stages = better dispersion approximation
- 16 provides excellent spring-like character without excessive CPU
- Uses Thiran interpolation for fractional delays

**Reflection Network**

The reflection network simulates early echoes from spring mounting hardware:

```cpp
// From: src/common/dsp/effects/chowdsp/spring_reverb/ReflectionNetwork.h:55
constexpr float baseDelaysSec[4] = {0.07f, 0.17f, 0.23f, 0.29f};
```

Four parallel delay lines with:
- Different lengths (prime-like ratios)
- Feedback with decay
- Householder matrix mixing for diffusion
- Shelf filter for tonal shaping

```cpp
// Householder reflection matrix
constexpr auto householderFactor = -2.0f / (float)4;
const auto sumXhh = vSum(outVec) * householderFactor;
outVec = SIMD_MM(add_ps)(outVec, SIMD_MM(load1_ps)(&sumXhh));
```

The Householder matrix ensures energy conservation and even diffusion.

**Spring Shake/Knock**

The iconic "boing" transient when springs are struck:

```cpp
// From: src/common/dsp/effects/chowdsp/spring_reverb/SpringReverbProc.cpp:76-87
if (params.shake && shakeCounter < 0) // start shaking
{
    float shakeAmount = urng01();
    float shakeSeconds =
        smallShakeSeconds + (largeShakeSeconds - smallShakeSeconds) * shakeAmount;
    shakeSeconds *= 1.0f + 0.5f * params.size;
    shakeCounter = int(fs * shakeSeconds);

    // Generate shake waveform
    for (int i = 0; i < shakeCounter; ++i)
        shakeBuffer[i] =
            2.0f * std::sin(2.0f * M_PI * i / (2.0f * shakeCounter));
}
```

Creates a sine-based transient injected into the spring feedback path.

**Decay Time Calculation**

The decay time is carefully modeled based on spring size:

```cpp
// From: src/common/dsp/effects/chowdsp/spring_reverb/SpringReverbProc.cpp:94-104
constexpr float lowT60 = 0.5f;
constexpr float highT60 = 4.5f;
const auto decayCorr = 0.7f * (1.0f - params.size * params.size);
float t60Seconds = lowT60 * std::pow(highT60 / lowT60, 0.95f * params.decay - decayCorr);

float delaySamples = 1000.0f + std::pow(params.size * 0.099f, 1.0f) * fs;
chaosSmooth.setTargetValue(urng01() * delaySamples * 0.07f);
delaySamples += std::pow(params.chaos, 3.0f) * chaosSmooth.skip(numSamples);

feedbackGain = std::pow(0.001f, delaySamples / (t60Seconds * fs));
```

Size affects both delay length and decay correction factor, creating authentic spring scaling.

### Parameter Reference

Spring Reverb provides 8 parameters across 3 groups:

#### Reverb Group

**Size** (`spring_reverb_size`)
- **Type**: `ct_percent` (0-100%)
- **Range**: Short spring to long spring
- **Default**: 50%
- **Function**: Physical spring length

```cpp
// From: src/common/dsp/effects/chowdsp/SpringReverbEffect.cpp:72-75
fxdata->p[spring_reverb_size].set_name("Size");
fxdata->p[spring_reverb_size].set_type(ct_percent);
fxdata->p[spring_reverb_size].val_default.f = 0.5f;
```

Size affects:
- Main delay length
- Decay time correction
- Shake duration
- Overall "weight" of spring character

**Decay** (`spring_reverb_decay`)
- **Type**: `ct_spring_decay` (special spring decay type)
- **Range**: Fast to slow decay
- **Default**: 50%
- **Function**: Spring resonance/feedback amount

```cpp
fxdata->p[spring_reverb_decay].set_name("Decay");
fxdata->p[spring_reverb_decay].set_type(ct_spring_decay);
```

Interacts with Size to determine final RT60.

**Reflections** (`spring_reverb_reflections`)
- **Type**: `ct_percent` (0-100%)
- **Range**: Minimal to prominent early reflections
- **Default**: 100%
- **Function**: Early reflection amount from mounting hardware

```cpp
fxdata->p[spring_reverb_reflections].set_name("Reflections");
fxdata->p[spring_reverb_reflections].set_type(ct_percent);
fxdata->p[spring_reverb_reflections].val_default.f = 1.0f;
```

Higher values create denser early echoes, simulating complex spring mounting.

**HF Damping** (`spring_reverb_damping`)
- **Type**: `ct_percent` (0-100%)
- **Range**: Bright to dark
- **Default**: 50%
- **Function**: High-frequency loss in spring

```cpp
fxdata->p[spring_reverb_damping].set_name("HF Damping");
fxdata->p[spring_reverb_damping].set_type(ct_percent);
```

Cutoff frequency range: 4 kHz (high damping) to 18 kHz (low damping):

```cpp
// From: src/common/dsp/effects/chowdsp/spring_reverb/SpringReverbProc.cpp:112-115
constexpr float dampFreqLow = 4000.0f;
constexpr float dampFreqHigh = 18000.0f;
auto dampFreq = dampFreqLow * std::pow(dampFreqHigh / dampFreqLow, 1.0f - params.damping);
lpf.setCutoffFrequency(dampFreq);
```

#### Modulation Group

**Spin** (`spring_reverb_spin`)
- **Type**: `ct_percent` (0-100%)
- **Range**: Focused to dispersed
- **Default**: 50%
- **Function**: All-pass feedback coefficient (dispersion amount)

```cpp
fxdata->p[spring_reverb_spin].set_name("Spin");
fxdata->p[spring_reverb_spin].set_type(ct_percent);
fxdata->p[spring_reverb_spin].val_default.f = 0.5f;
```

Controls all-pass gain:
```cpp
auto apfG = 0.5f - 0.4f * params.spin;  // Range: 0.1 to 0.9
```

Higher Spin = more dispersion = wider frequency spread = more "springy" character.

**Chaos** (`spring_reverb_chaos`)
- **Type**: `ct_percent` (0-100%)
- **Range**: Clean to chaotic
- **Default**: 0%
- **Function**: Random delay modulation

```cpp
fxdata->p[spring_reverb_chaos].set_name("Chaos");
fxdata->p[spring_reverb_chaos].set_type(ct_percent);
fxdata->p[spring_reverb_chaos].val_default.f = 0.0f;
```

Adds smoothed random variation to delay length:
```cpp
chaosSmooth.setTargetValue(urng01() * delaySamples * 0.07f);
delaySamples += std::pow(params.chaos, 3.0f) * chaosSmooth.skip(numSamples);
```

Creates instability and warble, simulating imperfect springs.

**Knock** (`spring_reverb_knock`)
- **Type**: `ct_float_toggle` (on/off, modulatable)
- **Range**: Off / On
- **Default**: Off
- **Function**: Trigger spring transient "boing"

```cpp
fxdata->p[spring_reverb_knock].set_name("Knock");
fxdata->p[spring_reverb_knock].set_type(ct_float_toggle);
```

When triggered, injects a sine-based transient into the feedback path. Can be modulated by LFOs for rhythmic "boings."

#### Output Group

**Mix** (`spring_reverb_mix`)
- **Type**: `ct_percent` (0-100%)
- **Range**: Dry to wet
- **Default**: 50%
- **Function**: Dry/wet balance

### Using Spring Reverb

**Classic Guitar Amp Spring:**
```
Size:        40%
Decay:       45%
Reflections: 80%
HF Damping:  60% (dark, vintage character)
Spin:        50%
Chaos:       0%
Knock:       Off
Mix:         30%
```

**Surf Reverb (intense springs):**
```
Size:        70%
Decay:       70%
Reflections: 90%
HF Damping:  40% (brighter)
Spin:        70% (more dispersion)
Chaos:       10%
Knock:       Occasional (for "boing" FX)
Mix:         50%
```

**Experimental Spring Shimmer:**
```
Size:        85%
Decay:       80%
Reflections: 100%
HF Damping:  20% (very bright)
Spin:        90%
Chaos:       35% (unstable, warbling)
Knock:       LFO-modulated (rhythmic)
Mix:         60%
```

**Lo-Fi Spring Character:**
```
Size:        25% (short, tight)
Decay:       35%
Reflections: 50%
HF Damping:  75% (dark, telephone-like)
Spin:        30%
Chaos:       50% (very unstable)
Knock:       Off
Mix:         35%
```

## Nimbus Effect

**Nimbus** is not a traditional reverb - it's a **granular processor** and **cloud generator** based on Mutable Instruments' Clouds module, ported to Surge XT. While it can function as reverb, Nimbus excels at creating textures, granular delays, pitch-shifted clouds, and otherworldly ambient processing.

### Architecture Overview

Nimbus is a port of Emilie Gillet's Clouds Eurorack module:

```cpp
// From: src/common/dsp/effects/NimbusEffect.h:39-40
struct NimbusEffect
    : public surge::sstfx::SurgeSSTFXBase<sst::effects::nimbus::Nimbus<surge::sstfx::SurgeFXConfig>>
```

The module uses a **granular buffer** where incoming audio is:
1. Recorded into a buffer
2. Split into overlapping grains
3. Grains are played back with:
   - Position/timing variations
   - Pitch shifting
   - Amplitude envelopes
   - Randomization parameters

**Four distinct modes:**

1. **Granular** - Classic granular synthesis/processing
2. **Pitch Shifter** - Harmonizer-style pitch shifting
3. **Looping Delay** - Time-stretching delay
4. **Spectral** - FFT-based spectral processing

### Nimbus Modes

The **Mode** parameter dramatically changes Nimbus's behavior and parameter meanings:

#### Mode 0: Granular

Classic granular processing - chops audio into grains and reconstructs with variations:

```
Parameter mapping (Mode 0):
  Density  → Grain density (sparse to dense)
  Texture  → Grain texture/overlap
  Size     → Grain size
```

**Behavior:**
- Low density: Discrete, separated grains
- High density: Smooth, continuous texture
- Texture affects grain envelope shape and overlap
- Size determines grain length (short = rhythmic, long = smooth)

**Use cases:**
- Granular clouds
- Texture generation
- Rhythmic grain effects
- Time-stretching artifacts

#### Mode 1 & 2: Pitch Shifter / Looping Delay

Harmonizer-style processing with pitch shifting:

```
Parameter mapping (Modes 1 & 2):
  Diffusion → Diffusion amount (reverb-like)
  Filter    → Spectral filtering
  Size      → Buffer size/latency
```

**Mode 1 vs Mode 2:**
- Mode 1: Shorter buffer, tighter response
- Mode 2: Longer buffer, more "reverb-like"

**Behavior:**
- Pitch parameter shifts grain playback speed
- Diffusion creates reverb-like tail
- Filter provides spectral shaping

**Use cases:**
- Harmonizer
- Pitch-shifted delays
- Shimmer reverb
- Detuned doubling

#### Mode 3: Spectral

FFT-based spectral processing:

```
Parameter mapping (Mode 3):
  Smear   → Spectral smearing/blur
  Texture → Spectral texture
  Warp    → Frequency warping
```

**Behavior:**
- Operates in frequency domain
- Smear creates spectral blur
- Warp shifts spectral content
- Texture adds randomization

**Use cases:**
- Spectral freeze
- Frequency smearing
- Atonal textures
- Experimental effects

### Parameter Reference

Nimbus provides 12 parameters across 4 groups. **Many parameters have mode-dependent names and functions.**

#### Configuration Group

**Mode** (`nmb_mode`)
- **Type**: `ct_nimbusmode` (mode selector)
- **Range**: 0 (Granular), 1 (Pitch Shifter), 2 (Looping Delay), 3 (Spectral)
- **Function**: Selects processing algorithm

```cpp
// From: src/common/dsp/effects/NimbusEffect.cpp:157-159
fxdata->p[nmb_mode].set_name("Mode");
fxdata->p[nmb_mode].set_type(ct_nimbusmode);
fxdata->p[nmb_mode].posy_offset = ypos;
```

**Quality** (`nmb_quality`)
- **Type**: `ct_nimbusquality` (quality selector)
- **Range**: Multiple quality levels
- **Function**: Processing quality vs. CPU trade-off

```cpp
fxdata->p[nmb_quality].set_name("Quality");
fxdata->p[nmb_quality].set_type(ct_nimbusquality);
```

Higher quality = more grains/voices, lower aliasing, higher CPU.

#### Grain Group

**Position** (`nmb_position`)
- **Type**: `ct_percent` (0-100%)
- **Range**: Buffer start to end
- **Default**: Variable
- **Function**: Playback position in buffer

```cpp
fxdata->p[nmb_position].set_name("Position");
fxdata->p[nmb_position].set_type(ct_percent);
```

Determines where in the recorded buffer grains are extracted.

**Size** (`nmb_size`)
- **Type**: `ct_percent_bipolar_w_dynamic_unipolar_formatting`
- **Range**: Depends on mode (unipolar or bipolar)
- **Default**: 0.5 (50%)
- **Function**: Mode-dependent (grain size, reverb size, or warp)

```cpp
// From: src/common/dsp/effects/NimbusEffect.cpp:169-175
fxdata->p[nmb_size].set_name("Size");
fxdata->p[nmb_size].set_type(ct_percent_bipolar_w_dynamic_unipolar_formatting);
fxdata->p[nmb_size].dynamicName = &dynTexDynamicNameBip;
fxdata->p[nmb_size].dynamicBipolar = &dynTexDynamicNameBip;
fxdata->p[nmb_size].val_default.f = 0.5;
```

The `dynamicName` and `dynamicBipolar` mean this parameter changes name and range based on mode:

```cpp
// From: src/common/dsp/effects/NimbusEffect.cpp:85-110
switch (mode)
{
case 0:  // Granular
    if (idx == nmb_size) res = "Size";
    break;
case 1:  // Pitch Shifter
case 2:  // Looping Delay
    if (idx == nmb_size) res = "Size";
    break;
case 3:  // Spectral
    if (idx == nmb_size) res = "Warp";
    break;
}
```

**Pitch** (`nmb_pitch`)
- **Type**: `ct_pitch4oct` (±4 octaves)
- **Range**: -48 to +48 semitones
- **Function**: Grain/playback pitch shift

```cpp
fxdata->p[nmb_pitch].set_name("Pitch");
fxdata->p[nmb_pitch].set_type(ct_pitch4oct);
```

Shifts grain playback speed, creating harmonizer-style effects.

**Density** (`nmb_density`)
- **Type**: `ct_percent_bipolar_w_dynamic_unipolar_formatting`
- **Range**: Mode-dependent
- **Function**: Grain density (Mode 0) or Diffusion (Modes 1-3)

```cpp
fxdata->p[nmb_density].set_name("Density");
fxdata->p[nmb_density].set_type(ct_percent_bipolar_w_dynamic_unipolar_formatting);
fxdata->p[nmb_density].dynamicName = &dynTexDynamicNameBip;
```

Dynamic naming:
- Mode 0: "Density" (unipolar) - Grain density
- Modes 1-2: "Diffusion" (unipolar) - Reverb-like diffusion
- Mode 3: "Smear" (bipolar) - Spectral smearing

**Texture** (`nmb_texture`)
- **Type**: `ct_percent_bipolar_w_dynamic_unipolar_formatting`
- **Range**: Mode-dependent
- **Function**: Grain texture (Mode 0), Filter (Modes 1-2), or Texture (Mode 3)

```cpp
fxdata->p[nmb_texture].set_name("Texture");
fxdata->p[nmb_texture].set_type(ct_percent_bipolar_w_dynamic_unipolar_formatting);
fxdata->p[nmb_texture].dynamicName = &dynTexDynamicNameBip;
```

**Spread** (`nmb_spread`)
- **Type**: `ct_percent` (0-100%)
- **Range**: Tight to wide
- **Function**: Stereo spread of grains
- **Note**: Only active in Mode 0 (Granular)

```cpp
// From: src/common/dsp/effects/NimbusEffect.cpp:192-194
fxdata->p[nmb_spread].set_name("Spread");
fxdata->p[nmb_spread].set_type(ct_percent);
fxdata->p[nmb_spread].dynamicDeactivation = &spreadDeact;
```

The `spreadDeact` function disables this parameter in modes 1-3:

```cpp
// From: src/common/dsp/effects/NimbusEffect.cpp:145-154
static struct SpreadDeactivator : public ParameterDynamicDeactivationFunction
{
    bool getValue(const Parameter *p) const
    {
        auto fx = &(p->storage->getPatch().fx[p->ctrlgroup_entry]);
        auto mode = fx->p[nmb_mode].val.i;
        return mode != 0;  // Deactivated unless mode 0
    }
} spreadDeact;
```

#### Playback Group

**Freeze** (`nmb_freeze`)
- **Type**: `ct_float_toggle` (on/off, modulatable)
- **Range**: Off / On
- **Function**: Freeze buffer recording, loop current content

```cpp
fxdata->p[nmb_freeze].set_name("Freeze");
fxdata->p[nmb_freeze].set_type(ct_float_toggle);
```

When active, buffer recording stops and Nimbus processes only the frozen audio.

**Feedback** (`nmb_feedback`)
- **Type**: `ct_percent` (0-100%)
- **Range**: No feedback to infinite
- **Function**: Feedback amount

```cpp
fxdata->p[nmb_feedback].set_name("Feedback");
fxdata->p[nmb_feedback].set_type(ct_percent);
```

Creates repeating, building textures.

**Reverb** (`nmb_reverb`)
- **Type**: `ct_percent` (0-100%)
- **Range**: Dry to reverb-soaked
- **Function**: Internal reverb amount

```cpp
fxdata->p[nmb_reverb].set_name("Reverb");
fxdata->p[nmb_reverb].set_type(ct_percent);
```

Nimbus includes a built-in simple reverb for extra spaciousness.

#### Output Group

**Mix** (`nmb_mix`)
- **Type**: `ct_percent` (0-100%)
- **Range**: Dry to wet
- **Default**: 50%
- **Function**: Dry/wet balance

```cpp
fxdata->p[nmb_mix].set_name("Mix");
fxdata->p[nmb_mix].set_type(ct_percent);
fxdata->p[nmb_mix].val_default.f = 0.5;
```

### Using Nimbus

**Shimmer Reverb (Mode 1):**
```
Mode:       1 (Pitch Shifter)
Quality:    High
Position:   50%
Size:       60%
Pitch:      +12 semitones (octave up)
Diffusion:  70%
Filter:     30%
Spread:     (disabled in mode 1)
Freeze:     Off
Feedback:   50%
Reverb:     40%
Mix:        35%
```

**Granular Texture (Mode 0):**
```
Mode:       0 (Granular)
Quality:    High
Position:   25%
Size:       40%
Pitch:      0 (no shift)
Density:    -30% (sparse, bipolar)
Texture:    60%
Spread:     80% (wide stereo)
Freeze:     Off
Feedback:   30%
Reverb:     20%
Mix:        50%
```

**Spectral Freeze (Mode 3):**
```
Mode:       3 (Spectral)
Quality:    Medium
Position:   50%
Warp:       +20%
Pitch:      0
Smear:      80%
Texture:    50%
Spread:     (disabled)
Freeze:     On (frozen buffer)
Feedback:   70%
Reverb:     60%
Mix:        80%
```

**Detuned Cloud (Mode 2):**
```
Mode:       2 (Looping Delay)
Quality:    High
Position:   70%
Size:       75%
Pitch:      -7 semitones (perfect fifth down)
Diffusion:  85%
Filter:     +10%
Spread:     (disabled)
Freeze:     Off
Feedback:   60%
Reverb:     50%
Mix:        45%
```

## Reverb Design Principles

### Choosing the Right Reverb

Each of Surge's four reverbs excels in specific scenarios:

**Reverb1: Transparent, Musical Reverb**
- **Best for**: General-purpose reverb, vocals, instruments, mix bus
- **Character**: Clean, transparent, predictable
- **Strengths**: Flexible EQ, simple interface, low CPU
- **When to use**: Need a "standard" reverb that doesn't color sound

**Reverb2: Surgical Control**
- **Best for**: Sound design, custom room simulation, experimental
- **Character**: More diffuse and customizable than Reverb1
- **Strengths**: Diffusion control, buildup, modulation, dual damping
- **When to use**: Need precise control over reverb structure

**Spring Reverb: Vintage Character**
- **Best for**: Guitars, drums, lo-fi production, surf music
- **Character**: Gritty, metallic, distinctive "boing"
- **Strengths**: Physical realism, unique timbral character
- **When to use**: Want authentic spring character or retro vibe

**Nimbus: Experimental/Textural**
- **Best for**: Pads, ambient, sound design, special effects
- **Character**: Granular, shimmer, clouds, textures
- **Strengths**: Pitch shifting, freeze, granular control, otherworldly
- **When to use**: Need more than reverb - want texture generation

### Hall vs. Plate vs. Room vs. Chamber

Approximating classic reverb types with Surge's algorithms:

**Concert Hall** (Reverb1 or Reverb2)
```
Characteristics:
  Long decay (2-4 seconds)
  Smooth, diffuse tail
  Natural HF damping
  Medium pre-delay (30-50 ms)

Reverb1 Settings:
  Pre-Delay:  40 ms
  Room Size:  75%
  Decay:      3.0 sec
  Damping:    35%
  Low Cut:    80 Hz
  High Cut:   14 kHz
  Mix:        25%

Reverb2 Settings:
  Pre-Delay:  50 ms
  Room Size:  +50%
  Decay:      3.0 sec
  Diffusion:  80%
  Modulation: 10%
  HF Damping: 40%
  Mix:        25%
```

**Plate Reverb** (Reverb2 or Spring)
```
Characteristics:
  Medium decay (1.5-2.5 seconds)
  Bright, dense early reflections
  Reduced low frequencies
  Minimal pre-delay

Reverb2 Settings:
  Pre-Delay:  5 ms
  Room Size:  -20% (tight ratios)
  Decay:      2.0 sec
  Diffusion:  35% (lower = more discrete)
  Buildup:    20%
  HF Damping: 10% (bright)
  LF Damping: 60% (thin lows)
  Mix:        30%

Spring Alternative:
  Size:       40%
  Decay:      50%
  Reflections: 70%
  HF Damping: 40%
  Mix:        35%
```

**Room/Chamber** (Reverb1)
```
Characteristics:
  Short decay (0.5-1.5 seconds)
  Clear early reflections
  Small room size
  Short pre-delay

Reverb1 Settings:
  Pre-Delay:  10 ms
  Room Size:  30%
  Decay:      1.0 sec
  Damping:    50%
  Low Cut:    150 Hz
  High Cut:   12 kHz
  Mix:        15-20%
```

**Ambience/Early Reflections** (Reverb1 or Reverb2)
```
Characteristics:
  Very short decay (0.3-0.6 seconds)
  Minimal tail
  Adds space without obvious reverb

Reverb1 Settings:
  Pre-Delay:  5 ms
  Room Size:  15%
  Decay:      0.4 sec
  Damping:    60%
  Mix:        10-15%
```

### Practical Mixing Tips

**Pre-Delay for Clarity**

Pre-delay separates direct sound from reverb, maintaining intelligibility:

```
Vocals:        20-40 ms (keeps lyrics clear)
Snare/Drums:   10-30 ms (preserves transient punch)
Pads:          50-100 ms (creates depth without mud)
Lead Synth:    30-50 ms (maintains presence)
```

Rule of thumb: Longer pre-delay = more separation = clearer mix (but less realistic space).

**Frequency-Dependent Decay**

Use damping and EQ to create natural frequency behavior:

```
Natural acoustic spaces:
  High frequencies decay fastest (air absorption, soft surfaces)
  Mid frequencies sustain
  Low frequencies decay slowly (pass through walls)

Reverb1 approach:
  Damping:  50% (reduces HF tail)
  Low Cut:  100-200 Hz (clean up low-end mud)
  Freq 1:   Cut 400-800 Hz (reduce boxiness)
  High Cut: 10-14 kHz (natural HF rolloff)

Reverb2 approach:
  HF Damping: 50-70% (natural HF decay)
  LF Damping: 20-40% (control low-end bloom)
```

**Mono vs. Stereo Sources**

Reverb affects mono and stereo sources differently:

```
Mono source (e.g., vocal):
  Use wide reverb (Width +3 to +6 dB)
  Creates stereo field from mono input
  Place source in center, reverb panned wide

Stereo source (e.g., pad):
  Use moderate width (Width 0 to +3 dB)
  Avoid excessive width (can sound diffuse)
  Match reverb width to source width
```

**Series vs. Parallel Processing**

```
Series (Insert):
  Effect slot directly on channel
  Dry/wet mix controls balance
  Good for: Guitars, drums, instruments

Parallel (Send/Return):
  Send amount controls signal to reverb chain
  Reverb mix at 100% (pure wet)
  Good for: Shared reverb, mix bus, blending
```

**CPU Management**

Reverb is CPU-intensive. Optimization strategies:

```
1. Use quality settings appropriately
   - Nimbus Quality: High for final mix, Low for draft

2. Freeze reverb tails during composition
   - Render reverb to audio track
   - Disable effect during playback

3. Use sends for multiple sources
   - One reverb instance serving many tracks
   - Much more efficient than per-track reverbs

4. Reduce reverb count
   - 2-3 reverbs maximum in typical mix
   - "Room" reverb for tight sources
   - "Hall" reverb for ambient sources
   - Special effect reverb (Spring/Nimbus) as needed
```

### Creating Custom Reverb Characters

**Reverse Reverb Effect**

While Surge doesn't have dedicated reverse reverb, approximate it:

```
1. Use Nimbus in Granular mode (Mode 0)
   Position:    Modulated by LFO (sweep buffer)
   Size:        Large grains
   Density:     High
   Pitch:       -12 (octave down, slower)
   Feedback:    60%
   Freeze:      Triggered at phrase end

2. Or: Render reverb, reverse audio externally, reimport
```

**Gated Reverb** (Classic 80s effect)

```
External approach (recommended):
1. Insert Reverb1 or Reverb2
2. Follow with gate/envelope follower
3. Fast attack, immediate release

Approximation with Nimbus:
  Mode:     1 (Pitch Shifter)
  Feedback: 0% (no sustain)
  Reverb:   30%
  Mix:      High

Result: Reverb cuts off sharply rather than decaying
```

**Shimmer Reverb**

Use Nimbus or Reverb2 with feedback and pitch shift:

```
Nimbus Shimmer:
  Mode:       1 (Pitch Shifter)
  Pitch:      +12 or +7 semitones
  Feedback:   50-70%
  Reverb:     50%
  Diffusion:  70%
  Mix:        40%

Reverb2 + External Pitch:
1. Reverb2 with long decay (4+ seconds)
2. Send reverb output to pitch shifter (+octave)
3. Mix pitched signal back into reverb input
```

**Lo-Fi/Vintage Reverb**

```
Spring Reverb approach:
  Size:       Small (25-40%)
  HF Damping: High (70-80%)
  Chaos:      Medium (40-60%)
  Knock:      Occasional (modulated)

Reverb1 approach:
  Decay:      Short (0.5-1.0 sec)
  Damping:    High (70%)
  High Cut:   6-8 kHz
  Width:      Narrow (-3 dB, more mono)
```

## Conclusion

Surge XT's four reverb effects span the full spectrum of spatial processing, from pristine algorithmic halls to granular cloud generators:

**Reverb1**: The reliable workhorse - transparent, musical, CPU-efficient. Perfect for traditional reverb tasks where clarity and control matter.

**Reverb2**: The customizable architect - precise diffusion, buildup, and damping controls for sculpting unique spaces.

**Spring Reverb**: The vintage character box - physically-informed spring simulation with authentic "boing," dispersion, and grit.

**Nimbus**: The experimental cloud generator - granular processor, shimmer reverb, and texture synthesizer in one.

Together, they provide tools for every scenario: natural room simulation, vintage character, modern shimmer, and avant-garde sound design. Understanding the underlying mathematics - comb filters, all-pass networks, FDN topology, and physical modeling - empowers you to shape space with intention.

Reverb is not just "adding space" - it's sculpting the three-dimensional acoustic environment where your sounds live. Choose wisely, listen carefully, and let your ears guide you through the infinite possibilities of spatial design.

---

**Previous: [Time-Based Effects](13-effects-time-based.md)**
**Next: [Distortion and Waveshaping Effects](15-effects-distortion.md)**
**See Also: [Effects Architecture](12-effects-architecture.md), [Formula Modulation](22-formula-modulation.md)**
