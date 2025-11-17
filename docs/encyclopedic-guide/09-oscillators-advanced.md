# Chapter 9: Advanced Oscillators - Physical Modeling and Digital Experimentation

## Introduction

Surge XT's advanced oscillators represent the cutting edge of synthesis: from physically-modeled strings using Karplus-Strong algorithms to experimental digital designs that embrace aliasing as a creative tool. While Chapters 6-8 covered traditional and wavetable synthesis, this chapter explores oscillators that push boundaries—simulating acoustic instruments, incorporating Eurorack-inspired multi-engine designs, and manipulating audio at the bit level.

These oscillators demonstrate Surge's philosophy of synthesis without limits: authentic physical modeling sits alongside intentionally lo-fi digital artifacts, windowed spectral processing coexists with sample-and-hold noise generation, and external audio routing enables vocoding and sidechaining.

## 1. String Oscillator: Physical Modeling via Karplus-Strong

The **String Oscillator** implements self-oscillating delay lines with sophisticated filtering and feedback, based on the famous Karplus-Strong algorithm for plucked string synthesis. What began as a simple physical modeling technique in 1983 has evolved here into an expressive instrument capable of plucked strings, struck bars, bowed textures, and sustained tones.

**Implementation**: `/home/user/surge/src/common/dsp/oscillators/StringOscillator.cpp` (923 lines)

### Architecture: The Self-Oscillating Delay

The fundamental circuit is elegantly simple yet sonically complex:

```
                    ┌─────────────────┐
                    │  Excitation     │
                    │  (burst/cont.)  │
                    └────────┬────────┘
                             │
                    ┌────────▼────────┐
          ┌────────►│  Delay Line 1   │─────────┐
          │         │  (tap 1)        │         │
          │         └─────────────────┘         │
Feedback──┤                                     ├──► Mix ──► Output
          │         ┌─────────────────┐         │
          └────────►│  Delay Line 2   │─────────┘
                    │  (tap 2)        │
                    └────────┬────────┘
                             │
                    ┌────────▼────────┐
                    │  Tone Filter    │
                    │  Drive/Clip     │
                    └─────────────────┘
```

**Two parallel delay lines** run simultaneously:
- Each seeded with the same excitation signal
- Independent tap points controlled by detune
- Outputs mixed for stereo width and movement
- Feedback through tone filtering and soft clipping

From the source (lines 26-43):
```cpp
/*
 * String oscillator is a self-oscillating delay with various filters and
 * feedback options.
 *
 * At init:
 * - Excite the delay line with an input. In 'chirp' mode this is only pre-play
 *   and in 'continuous' mode it is scaled by the amplitude during play
 *
 * At runtime:
 * - run two delay lines seeded the same and take two taps, tap1 and tap2,
 *   and create an output which is (1-mix) * tap1 + mix * tap2
 * - create a feedback signal fb = tap + excitation in each line
 * - run that feedback signal through a tone filter in each line
 * - drive that feedback signal and run it through a soft clipper in each line
 * - write that feedback signal to the head of the delay line
 */
```

### Excitation Models: Attack Characteristics

The String oscillator provides **15 excitation modes** divided into two categories:

#### Burst Modes (Plucked/Struck Strings)

Excitation happens **only during initialization**, then the delay line resonates freely. Decay is controlled entirely by feedback.

**Available burst modes** (lines 57-86):
1. **Burst Noise**: Random white noise impulse - natural pluck
2. **Burst Pink Noise**: Filtered 1/f noise - warmer pluck
3. **Burst Sine**: Pure tone excitation - pitched strike
4. **Burst Ramp**: Sawtooth impulse - bright attack
5. **Burst Triangle**: Triangle impulse - softer attack
6. **Burst Square**: Square impulse - hollow tone
7. **Burst Sweep**: Chirp from high to low - metallic ping

**Sound design tip**: Burst modes with low Exciter Level create authentic plucked strings. High levels with extended decay make bell-like tones.

#### Continuous Modes (Bowed/Sustained Strings)

Excitation **continues during playback**, mixed with the delay line output. Creates sustained, evolving textures.

**Available continuous modes**:
1. **Constant Noise**: Ongoing white noise - bowed texture
2. **Constant Pink Noise**: Ongoing pink noise - softer bow
3. **Constant Sine**: Pure tone injection - harmonic sustain
4. **Constant Triangle**: Triangle wave - warm sustain
5. **Constant Ramp**: Sawtooth wave - bright sustain
6. **Constant Square**: Square wave - hollow sustain
7. **Constant Sweep**: Ongoing chirp - evolving harmonics
8. **Audio In**: External audio as excitation - vocoder source

**Implementation** (lines 724-800):
```cpp
switch (mode)
{
case constant_noise:
    val[t] += examp.v * (urd(gen) * 2 - 1);
    break;
case constant_sine:
    float sv = std::sin(2.0 * M_PI * *phs);
    val[t] += examp.v * 0.707 * sv;
    *phs += dp;
    *phs -= (*phs > 1);
    break;
case constant_audioin:
    fbNoOutVal[t] = examp.v * storage->audio_in[t][i];
    break;
// ...
}
```

### Parameters Deep Dive

#### Exciter Level (0-100%)

Controls excitation amplitude with **different scaling** for burst vs. continuous:

**Burst modes** (lines 545-554):
```cpp
if (d0 < 0.1) {
    // Linear scaling at low levels for control
    examp.newValue(d0 * 5.6234);
} else {
    // Fourth-root scaling for perceptual evenness
    examp.newValue(powf(d0, 0.25));
}
```

**Continuous modes**:
```cpp
examp.newValue(d0 * d0 * d0 * d0);  // Fourth-power for smooth fade-in
```

**Sound design**:
- Burst modes: 100% = maximum pluck attack, 0% = silent
- Continuous: 100% = full bow pressure, 0% = pure delay line resonance

#### String 1/2 Decay (85-100%, extendable to bipolar)

Controls feedback amount, determining how quickly energy dissipates:

**Standard range** (lines 617-627):
```cpp
if (fbp < 0.2) {
    // 0-20%: map to 0.85-0.95 feedback
    feedback[0].newValue(0.85f + (0.5f * fbp));
} else {
    // 20-100%: map to 0.95-1.0 feedback
    feedback[0].newValue(0.9375f + (0.0625f * fbp));
}
```

At **0.85 feedback**: Sound dies in ~100ms
At **0.95 feedback**: Rings for ~1 second
At **1.0 feedback**: Infinite sustain (oscillator mode)

**Extended range** allows **negative feedback** (lines 599-614), creating inverted phase feedback for metallic, clangorous tones.

#### String 2 Detune (±100 cents, extendable to ±1600 cents)

Detunes the second delay line, creating:
- **Subtle detune (±10 cents)**: Chorusing, subtle movement
- **Musical intervals (±700 cents)**: Perfect fifth drones
- **Wide detune (±1600 cents)**: Two-note clusters

**Absolute mode** available: detune in Hz rather than pitch ratio.

#### String Balance (-100% to +100%)

Crossfades between the two delay line outputs:
- **-100%**: String 1 only (left)
- **0%**: Equal mix (center)
- **+100%**: String 2 only (right)

Creates stereo width and evolving timbral movement as detuned strings phase-cancel and reinforce.

#### Stiffness (-100% to +100%)

The most complex parameter, controlling the **tone filter** in the feedback path.

**Negative values**: Low-pass filter (lines 436-440)
```cpp
auto tv = -tone.v;
lpCutoff = tv * (clo - cmid) + cmid;  // 10 Hz to 100 Hz
```
Creates **warm, dark tones** - wooden instruments, bass strings.

**Positive values**: High-pass filter (lines 432-434)
```cpp
auto tv = tone.v;
hpCutoff = tv * (cmidhi - chi) + chi;  // 60 Hz to -70 Hz
```
Creates **bright, metallic tones** - steel strings, bells, bars.

**Two filter modes**:
1. **Fixed**: Filter cutoff independent of pitch
2. **Tracking**: Filter follows note pitch (compensated for tuning)

**Pitch compensation** (lines 381-415):
The filter affects pitch due to phase shift. Stiffness mode automatically compensates:
```cpp
static constexpr float retunes[] = {-0.0591202, -0.122405, -0.225738,
                                    -0.406056, -0.7590243};
```
These correction values maintain accurate tuning across all stiffness settings.

### Advanced Features

#### Oversampling Control

The Exciter Level parameter's right-click menu offers **1x or 2x oversampling**:
- **1x**: CPU-efficient, slight aliasing on high notes
- **2x**: Cleaner high frequencies, 2x CPU cost

```cpp
int getOversampleLevel() {
    if (oscdata->p[str_exciter_level].deform_type & StringOscillator::os_twox)
        return 2;
    return 1;
}
```

#### Interpolation Modes

Right-click **Stiffness** to select delay line interpolation:

1. **Sinc**: Highest quality, windowed sinc interpolation
2. **Linear**: Faster, slight high-frequency roll-off
3. **ZOH** (Zero-Order Hold): Aliasing artifacts, lo-fi character

```cpp
switch (interp_mode) {
case StringOscillator::interp_sinc:
    val[t] = delayLine[t]->read(v);
    break;
case StringOscillator::interp_lin:
    val[t] = delayLine[t]->readLinear(v);
    break;
case StringOscillator::interp_zoh:
    val[t] = delayLine[t]->readZOH(v);
    break;
}
```

### Sound Design Examples

#### Realistic Acoustic Guitar
- **Exciter**: Burst Noise
- **Exciter Level**: 80%
- **Decay 1/2**: 92%
- **String Balance**: -15% (slight left bias)
- **String 2 Detune**: 8 cents
- **Stiffness**: -30% (warm, wooden tone)

#### Steel String Resonator
- **Exciter**: Burst Sine
- **Exciter Level**: 100%
- **Decay 1/2**: 98%
- **String 2 Detune**: +700 cents (perfect fifth)
- **Stiffness**: +45% (bright, metallic)

#### Bowed Cello
- **Exciter**: Constant Pink Noise
- **Exciter Level**: 65%
- **Decay 1/2**: 90%
- **Stiffness**: -40% (dark, woody)
- **Add**: Slow LFO on Exciter Level for bow pressure

#### Metallic Bell
- **Exciter**: Burst Sweep
- **Exciter Level**: 100%
- **Decay 1/2**: 96% (extended range)
- **String 2 Detune**: +1200 cents (octave)
- **Stiffness**: +70% (very bright)

#### Karplus-Strong Vocoder
- **Exciter**: Audio In
- **Exciter Level**: 50%
- **Decay 1/2**: 95%
- **Route**: External audio (speech, drums) to input
- **Result**: Pitched, resonant version of input

---

## 2. Twist Oscillator: Eurorack Multi-Engine Synthesis

The **Twist Oscillator** brings the spirit of Mutable Instruments' **Plaits** macro-oscillator into Surge, providing **16 distinct synthesis engines** ranging from classic virtual analog to granular clouds, physical modeling, and percussion. Each engine has its own character and parameter mappings, making Twist a synthesizer within a synthesizer.

**Implementation**: `/home/user/surge/src/common/dsp/oscillators/TwistOscillator.cpp` (554 lines)
**Core Engine**: Mutable Instruments Plaits library

### Architecture: The Engine System

Unlike traditional oscillators with fixed algorithms, Twist contains **16 separate synthesis engines**, each with:
- Unique synthesis method (FM, granular, physical model, etc.)
- Four morphing parameters (Harmonics, Timbre, Morph, Aux Mix)
- Main and Aux outputs (can be mixed or panned)

**The data flow**:
```
MIDI Note → Plaits Engine → Main Output
                          ╰→ Aux Output → Mix/Pan → Surge Voice
```

#### Resampling System (lines 283-291)

Plaits runs internally at **48 kHz** regardless of project sample rate. The Twist oscillator uses **Lanczos resampling** to convert between rates:

```cpp
lancRes = std::make_unique<resamp_t>(48000, storage->dsamplerate_os);
fmDownSampler = std::make_unique<resamp_t>(storage->dsamplerate_os, 48000);
```

This maintains Plaits' original character across all sample rates while allowing seamless Surge integration.

### The 16 Synthesis Engines

Each engine transforms the four morphing parameters differently. From lines 76-113:

#### 1. Waveforms - Virtual Analog Pair
**Parameters**:
- **Detune**: Detuning between two oscillators (bipolar)
- **Square Shape**: Pulse width / waveshaping
- **Saw Shape**: Sawtooth variation
- **Sync**: Hard sync amount

Classic two-oscillator VA with cross-modulation and sync. Perfect for fat analog leads and pads.

#### 2. Waveshaper - Wavefolding/Distortion
**Parameters**:
- **Waveshaper**: Folding algorithm selector
- **Fold**: Folding amount
- **Asymmetry**: Waveform bias
- **Variation**: Algorithm variation

Creates harmonically rich tones through iterative wavefolding, inspired by Buchla/Serge designs.

#### 3. 2-Operator FM - Classic FM Synthesis
**Parameters**:
- **Ratio**: Carrier/modulator frequency ratio
- **Amount**: Modulation index
- **Feedback**: Modulator feedback
- **Sub**: Sub-oscillator mix

Clean, digital FM tones from bells to electric pianos.

#### 4. Formant/PD - Formant and Phase Distortion
**Parameters**:
- **Ratio/Type**: Formant spacing or PD ratio
- **Formant**: Formant frequency
- **Shape**: Waveform character
- **PD**: Phase distortion amount

Vocal-like formants or Casio CZ-style phase distortion.

#### 5. Harmonic - Additive Organ Synthesis
**Parameters**:
- **Bump**: Harmonic emphasis position
- **Peak**: Peak sharpness
- **Shape**: Harmonic distribution
- **Organ**: Drawbar-style registration

Additive synthesis with moving harmonic peaks - pipe organs to bell tones.

#### 6. Wavetable - Interpolated Wavetable
**Parameters**:
- **Bank**: Wavetable selection (bipolar for two banks)
- **Morph X**: First-axis scanning
- **Morph Y**: Second-axis scanning
- **Lo-Fi**: Bit reduction/sample rate reduction

2D wavetable navigation with digital degradation.

#### 7. Chords - Chord Generator
**Parameters**:
- **Type**: Chord type (oct, 5, sus4, m, m7, m9, m11, 6/9, M9, M7, M)
- **Inversion**: Chord voicing
- **Shape**: Harmonic balance
- **Root**: Root note offset

Instant polyphony! Creates full chords from single notes. The Type parameter displays actual chord names (line 238-251).

#### 8. Vowels/Speech - Formant Synthesis
**Parameters**:
- **Speak**: Vowel/consonant selection
- **Species**: Male/female/alien formant spacing
- **Segment**: Syllable position
- **Raw**: Excitation vs. formant balance

Speech synthesis from vocal-like pads to robotic voices.

#### 9. Granular Cloud - Granular Synthesis
**Parameters**:
- **Pitch Random**: Grain pitch spread
- **Grain Density**: Grains per second
- **Grain Duration**: Individual grain length
- **Sine**: Sine vs. noise excitation

Atmospheric clouds and textures from granular processing.

#### 10. Filtered Noise - Resonant Noise
**Parameters**:
- **Type**: Filter algorithm
- **Clock Frequency**: Resonance frequency
- **Resonance**: Filter Q
- **Dual Peak**: Twin-peak mode

From white noise through variable resonance - winds, breath, claps.

#### 11. Particle Noise - Dust/Crackle Generator
**Parameters**:
- **Freq Random**: Particle frequency spread
- **Density**: Particles per second
- **Filter Type**: Resonator type
- **Raw**: Filtered vs. raw balance

Digital dust, vinyl crackle, rain sounds.

#### 12. Inharmonic String - Struck String Model
**Parameters**:
- **Inharmonicity**: String stiffness (piano-like)
- **Brightness**: Excitation tone
- **Decay Time**: String damping
- **Exciter**: Attack character

Physical model of struck strings with adjustable inharmonicity - pianos, harps, mallets.

#### 13. Modal Resonator - Struck/Bowed Resonator
**Parameters**:
- **Material**: Resonator type (glass, wood, metal)
- **Brightness**: Tone color
- **Decay Time**: Ring duration
- **Exciter**: Attack type

Bowed/struck bars, bells, bowls - singing wine glasses to timpani.

#### 14. Analog Kick - Kick Drum Synthesis
**Parameters**:
- **Sharpness**: Attack transient
- **Brightness**: Tone color
- **Decay Time**: Sustain length
- **Variation**: Drum character

808/909-style kick synthesis with pitch envelope.

#### 15. Analog Snare - Snare Drum Synthesis
**Parameters**:
- **Tone<>Noise**: Body vs. snares balance (bipolar)
- **Model**: Drum tuning
- **Decay Time**: Ring length
- **Variation**: Snare character

Analog snare synthesis from tight to roomy.

#### 16. Analog Hi-Hat - Hi-Hat Synthesis
**Parameters**:
- **Tone<>Noise**: Metallic vs. noisy (bipolar)
- **Low Cut**: Filter frequency
- **Decay Time**: Closed to open
- **Variation**: Hi-hat type

Closed to open hi-hats, rides, cymbals.

### Parameters: Dynamic Morphing System

The genius of Twist is that **the same four knobs** control vastly different parameters depending on engine selection. This is implemented through dynamic parameter naming and scaling.

#### Dynamic Parameter Names (lines 75-153)

```cpp
static struct EngineDynamicName : public ParameterDynamicNameFunction {
    std::vector<std::vector<std::string>> engineLabels;

    // Each engine has 4 custom labels
    engineLabels.push_back({"Detune", "Square Shape", "Saw Shape", "Sync"});  // Waveforms
    engineLabels.push_back({"Waveshaper", "Fold", "Asymmetry", "Variation"}); // Waveshaper
    // ... etc
};
```

When you change engines, the UI labels update automatically.

#### Dynamic Bipolar State (lines 156-210)

Some parameters are **unipolar** (0-100%), others **bipolar** (-100% to +100%):

```cpp
static struct EngineDynamicBipolar : public ParameterDynamicBoolFunction {
    std::vector<std::vector<bool>> engineBipolars;

    engineBipolars.push_back({true, true, true, true});    // Waveforms - all bipolar
    engineBipolars.push_back({true, false, false, true});  // Waveshaper
    // ...
};
```

#### Aux Mix Parameter

The fourth parameter (**Aux Mix**) has an **extended mode** accessed via right-click:
- **Standard mode**: Mix between Main and Aux outputs
- **Extended mode**: **Pan** Main on one side, Aux on the other

```cpp
if (oscdata->p[twist_aux_mix].extend_range) {
    output[i] = auxmix.v * tL[i] + (1 - auxmix.v) * tR[i];   // L channel
    outputR[i] = auxmix.v * tR[i] + (1 - auxmix.v) * tL[i];  // R channel
} else {
    output[i] = auxmix.v * tR[i] + (1 - auxmix.v) * tL[i];   // Mono mix
    outputR[i] = output[i];
}
```

### LPG (Low-Pass Gate) System

Unique to Twist: an optional **LPG (Low-Pass Gate)** circuit inspired by Buchla designs.

**Parameters**:
- **LPG Response**: Gate sensitivity (deactivate for bypass)
- **LPG Decay**: Release time

When enabled, the oscillator responds to **note gates** with simultaneous amplitude and filter modulation:

```cpp
if (lpgIsOn) {
    mod->trigger = gate ? 1.0 : 0.0;
    mod->trigger_patched = true;
}

patch->decay = lpgdec.v;      // Decay time
patch->lpg_colour = lpgcol.v; // Filter color
```

Creates plucky, organic envelopes without needing separate envelope generators.

### FM and Tuning Integration

#### Tuning-Aware Pitch (lines 294-310)

Unlike most oscillators, Twist respects Surge's **microtuning** in a special way:

```cpp
float tuningAwarePitch(float pitch) {
    if (storage->tuningApplicationMode == SurgeStorage::RETUNE_ALL) {
        // Interpolate between adjacent scale degrees
        auto idx = (int)floor(pitch);
        float frac = pitch - idx;
        float b0 = storage->currentTuning.logScaledFrequencyForMidiNote(idx) * 12;
        float b1 = storage->currentTuning.logScaledFrequencyForMidiNote(idx + 1) * 12;
        return (1.f - frac) * b0 + frac * b1;
    }
    return pitch;
}
```

This ensures smooth pitch sweeps in non-12-TET tunings.

#### FM Depth Scaling (lines 389-394)

```cpp
const float bl = -143.5, bhi = 71.7, oos = 1.0 / (bhi - bl);
float adb = limit_range(amp_to_db(FMdepth), bl, bhi);
float nfm = (adb - bl) * oos;
normFMdepth = limit_range(nfm, 0.f, 1.f);
```

FM depth is converted from amplitude to dB, then normalized to 0-1 range for Plaits' expected scaling.

### Sound Design Examples

#### Vintage FM Electric Piano (Engine 3: 2-Operator FM)
- **Ratio**: 14:1 (bell-like ratio)
- **Amount**: 40%
- **Feedback**: 10%
- **Sub**: 0%
- **LPG Response**: 60%
- **LPG Decay**: 30%

#### Vocal Pad (Engine 8: Vowels/Speech)
- **Speak**: 40% (ah → oh vowels)
- **Species**: 60% (between male and alien)
- **Segment**: Modulate with LFO
- **Raw**: 20% (mostly formants)
- **Add**: Reverb and chorus

#### Granular Ambient (Engine 9: Granular Cloud)
- **Pitch Random**: 80%
- **Grain Density**: 30%
- **Grain Duration**: 70% (long grains)
- **Sine**: 100% (pure sine grains)
- **Add**: Slow pitch modulation

#### 808 Kick (Engine 14: Analog Kick)
- **Sharpness**: 65% (punchy attack)
- **Brightness**: 40%
- **Decay Time**: 45% (tight)
- **Variation**: 30%
- **Note**: C1 (low pitch)

#### Wavetable Sweep (Engine 6: Wavetable)
- **Bank**: 0% (standard wavetables)
- **Morph X**: LFO'd slowly
- **Morph Y**: 50%
- **Lo-Fi**: 25% (slight digital grit)

---

## 3. Alias Oscillator: Lo-Fi Digital Character

Where most oscillators fight aliasing, the **Alias Oscillator** embraces it as an aesthetic. Operating at 8-bit resolution with intentional aliasing, bit crushing, and memory-as-wavetable reading, this oscillator creates everything from vintage video game sounds to glitchy experimental textures.

**Implementation**: `/home/user/surge/src/common/dsp/oscillators/AliasOscillator.cpp` (661 lines)

**Important note** (line 23):
```cpp
// This oscillator is intentionally bad! Not recommended as an example of good DSP!
```

### Architecture: 8-Bit Signal Path

The Alias oscillator operates in **8-bit integer space** for most processing:

```
32-bit Phase → 8-bit Upper Byte → Mask/Wrap → Wavetable Lookup → Bitcrush → Output
```

**Key constants** (lines 271-272):
```cpp
const uint32_t bit_mask = (1 << 8) - 1;           // 0xFF = 255
const float inv_bit_mask = 1.0 / (float)bit_mask; // 1/255 for conversion
```

All waveform generation happens in 8-bit unsigned integer (0-255) with **127 as zero point**.

### Waveform Types

The oscillator provides **18 waveform types** organized into categories:

#### Basic Shapes (lines 136-364)

**1. Sine** - 8-bit sine table lookup:
```cpp
const uint8_t alias_sinetable[256] = {
    0x7F, 0x82, 0x85, 0x88, ... // 256-entry table
};
```

**2. Ramp** - Sawtooth with triangle fold-over:
```cpp
if (upper > threshold) {
    if (ramp_unmasked_after_threshold)
        result = bit_mask - upper;      // Fold from upper byte
    else
        result = bit_mask - masked;     // Fold from masked byte
}
```

**3. Pulse** - Hard-edged square with fake hardsync:
```cpp
// Fake hardsync by wrapping phase
_phase = (uint32_t)((float)phase[u] * wrap);
result = (masked > threshold) ? bit_mask : 0x00;
```

**4. Noise** - 8-bit random number generator with threshold gating:
```cpp
result = urng8[u].stepTo((upper & 0xFF), threshold | 8U);
```

#### Quadrant Shaping (TX Series)

**TX 2-8**: Seven shaped sine variants using quadrant-specific waveshaping:
```cpp
if (i % 2 == 0)
    wf = i / 2 + 28;  // Selects pre-XT 1.4 spiky waveforms
auto r = SineOscillator::valueFromSinAndCos(s, c, wf);
```

Creates harmonically rich variations on the sine wave.

#### Memory-as-Wavetable Modes

The most experimental feature: **reading raw memory as audio**:

**Alias Mem** - Reads the oscillator's own memory:
```cpp
static_assert(sizeof(*this) > 0xFF, "Memory region not large enough");
wavetable = (const uint8_t *)this;
```

**Osc Mem** - Reads oscillator parameter memory:
```cpp
wavetable = (const uint8_t *)oscdata;
```

**Scene Mem** - Reads scene data:
```cpp
wavetable = (const uint8_t *)storage->getPatch().scenedata;
```

**DAW Chunk Mem** - Reads DAW state:
```cpp
wavetable = (const uint8_t *)&storage->getPatch().dawExtraState;
```

**Step Seq Mem** - Reads step sequencer data:
```cpp
wavetable = (const uint8_t *)storage->getPatch().stepsequences;
```

**Audio In** - Reinterprets incoming audio as wavetable (lines 171-196):
```cpp
// Convert audio sample to 8-bit unsigned
auto llong = (uint32_t)(((double)storage->audio_in[0][qs]) * (double)0xFFFFFFFF);
llong = (llong >> 24) & 0xFF;
dynamic_wavetable[4 * qs] = llong;
```

#### Additive Mode

**Additive** - User-programmable additive synthesis (lines 199-259):
```cpp
// 16 harmonic amplitudes set via extraConfig
for (int h = 0; h < n_additive_partials; h++) {
    const int16_t scaled = ((int16_t)alias_sinetable[s * (h + 1) & 0xFF] - 0x7F) * amps[h];
    sample += scaled >> 8;  // Fixed-point accumulation
}
```

Creates custom harmonic spectra with 16 independently-controllable partials.

### Parameters

#### Shape (Waveform Selector)

Organized into **logical groups** (lines 502-522):
- **Basic**: Sine, Ramp, Pulse, Noise, Additive, Audio In
- **Quadrant Shaping**: TX 2 through TX 8
- **Memory From**: Alias Mem, Osc Mem, Step Seq, Scene, DAW Chunk

#### Wrap (0-100%)

Scales the waveform with wraparound:
```cpp
const float wrap = 1.f + (clamp01(localcopy[...].f) * 15.f);  // 1.0 to 16.0
result = (uint8_t)((float)result * wrap);  // Wraps at 255
```

- **0%**: Normal waveform
- **100%**: 16x overdriven with 8-bit wraparound

Creates ring modulation-like effects and harsh harmonics.

#### Mask (0-255)

XORs the upper phase byte before waveform generation:
```cpp
const uint32_t mask = bit_mask * localcopy[...].f;  // 0-255
const uint8_t masked = upper ^ mask;
```

**Example masks**:
- **0**: No effect
- **255 (0xFF)**: Inverts all bits - creates octave jump
- **128 (0x80)**: Inverts MSB - creates subharmonic
- **85 (0x55)**: Alternating bits - creates complex aliasing

**Right-click option**: "Ramp Unmasked After Threshold" - whether fold-over uses masked or unmasked value.

#### Threshold (0-255)

Comparison point for conditional operations:
```cpp
const uint8_t threshold = (uint8_t)(bit_mask * clamp01(localcopy[...].f));
```

- **Ramp mode**: Fold-over point for triangle shaping
- **Pulse mode**: Pulse width (like PWM)
- **Noise mode**: Sample-and-hold trigger level

#### Bitcrush (1-8 bits)

Reduces bit depth from 8-bit down to 1-bit:
```cpp
const float quant = powf(2, crush_bits);    // Quantization levels
const float dequant = 1.f / quant;
out = dequant * (int)(out * quant);         // Truncate
```

**Settings**:
- **8 bits**: No effect (bypassed for efficiency)
- **4 bits**: Mild lo-fi character
- **2 bits**: Severe quantization noise
- **1 bit**: Binary on/off (extreme distortion)

### Unison and Spread

Up to **16 unison voices** with **absolute or relative detuning**.

**Absolute mode** (lines 122-126):
```cpp
if (oscdata->p[ao_unison_detune].absolute) {
    absOff = ud * 16;  // Detune in Hz
    ud = 0;            // Disable relative detune
}
```

Useful for creating **fixed harmonic intervals** that don't track pitch.

### Sound Design Examples

#### Vintage Game Console Lead
- **Shape**: Pulse
- **Wrap**: 0%
- **Mask**: 0
- **Threshold**: 128 (50% PWM)
- **Bitcrush**: 4 bits
- **Unison**: 3 voices, 10 cents

#### Experimental Texture (Memory Reading)
- **Shape**: Scene Mem
- **Wrap**: 60% (moderate overdrive)
- **Mask**: 85 (0x55 - alternating bits)
- **Threshold**: 127
- **Bitcrush**: 6 bits
- **Note**: Changes as you modify scene parameters!

#### Aliased Bass
- **Shape**: Sine
- **Wrap**: 40%
- **Mask**: 128 (subharmonic)
- **Bitcrush**: 3 bits
- **Play**: Low notes (C1-C2)

#### Additive Bells
- **Shape**: Additive
- **Set harmonics**: 1.0, 0.0, 0.0, 0.8, 0.0, 0.6, 0.0, 0.4, 0.0, ...
- **Bitcrush**: 8 bits (clean)
- **Wrap**: 0%

#### Glitch Percussion
- **Shape**: Audio In
- **Route**: Drum loop to audio input
- **Wrap**: 80%
- **Mask**: Modulate with fast LFO
- **Threshold**: 200
- **Bitcrush**: 2 bits

---

## 4. Modern Oscillator: Alias-Free Analog Modeling

The **Modern Oscillator** achieves what many consider impossible: perfectly alias-free analog-style waveforms under **any** modulation—FM, sync, pitch sweeps—using **Differentiated Polynomial Waveforms (DPW)**. This is cutting-edge DSP producing pristine sawtooths, squares, and triangles that remain clean even during extreme modulation.

**Implementation**: `/home/user/surge/src/common/dsp/oscillators/ModernOscillator.cpp` (609 lines)

### Theoretical Foundation: DPW Synthesis

The technique is based on a 2006 research paper (referenced in line 28-31):

**Basic idea**:
1. Create a polynomial that is the **n-th integral** of the desired waveform
2. **Numerically differentiate** it n times
3. The differentiation acts as a perfect anti-aliasing filter

**Example for sawtooth** (lines 59-72):

Desired output: `f(p) = p` (where p is phase from -1 to 1)

Second anti-derivative: `g(p) = p³/6 - p/6`

We need g(-1) = g(1) for continuity:
```
g(-1) = -1/6 + a - b + c
g(1)  =  1/6 + a + b + c

For continuity: a = 0, b = -1/6, c = 0
Therefore: g(p) = (p³ - p) / 6
```

Taking the **numerical second derivative** of this continuous function produces a perfect sawtooth with automatic anti-aliasing!

### Architecture: Real-Time Polynomial Differentiation

Unlike BLIT-based oscillators that use lookup tables, Modern calculates polynomials at every sample:

```
Calculate Phase → Evaluate Polynomial at 3 Points → Numerical 2nd Derivative → Output
                  (p, p-dp, p-2dp)
```

**The second derivative formula** (line 114):
```
d²f/dx² ≈ (f(x) - 2f(x-1) + f(x-2)) / dt²
```

**In code** (lines 342-346):
```cpp
double denom = 0.25 / (dsp * dsp);  // 1 / (4 * dt²)
double saw = (sBuff[0] + sBuff[2] - 2.0 * sBuff[1]);
double tri = (triBuff[0] + triBuff[2] - 2.0 * triBuff[1]);

double res = (sawmix.v * saw + trimix.v * tri + sqrmix.v * sqr) * denom;
```

### Waveform Generation

#### Sawtooth (lines 266-270)

```cpp
double p01 = phases[s];              // Phase in 0-1
double p = (p01 - 0.5) * 2;         // Convert to -1 to 1
double p3 = p * p * p;
double sawcub = (p3 - p) * oneOverSix;  // (p³ - p) / 6

sBuff[s] = sawcub;
```

#### Square (lines 284-288)

For a square wave, we need `g''(p) = sign(p)`, so:

```cpp
double Q = (p < 0) * 2 - 1;          // -1 for p<0, +1 for p≥0
triBuff[s] = p * (Q * p + 1) * 0.5;  // g(p) = (Q*p² + p) / 2
```

#### Triangle (lines 327-333)

Triangle uses a piecewise cubic:

```cpp
double tp = p + 0.5;                 // Shift to 0-1
tp -= (tp > 1.0) * 2;               // Wrap to -1 to 1

double Q = 1 - (tp < 0) * 2;        // Segment selector
triBuff[s] = (2.0 + tp * tp * (3.0 - 2.0 * Q * tp)) * oneOverSix;
```

#### "Sine" (Actually Parabolic, lines 290-325)

The "sine" isn't a true sine but a **pair of parabolas** (faster to compute, still smooth):

```cpp
double modpos = 2.0 * (p < 0) - 1.0;  // Segment selector
double p4 = p3 * p;
triBuff[s] = -(modpos * p4 + 2 * p3 - p) * oo3;
```

Creates a sine-like wave with slightly different harmonic content.

### Pulse Width Modulation

The oscillator generates pulses by **subtracting two phase-shifted sawtooths**:

```cpp
double pwp = p + pwidth.v;           // Offset by pulse width
pwp += (pwp > 1) * -2;              // Wrap
sOffBuff[s] = (pwp * pwp * pwp - pwp) * oneOverSix;

// Later:
double sqr = sawoff - saw;           // Subtract offset saw from main saw
```

**Width parameter** (lines 213-214):
```cpp
// Since we use it multiplied by 2, incorporate that here
pwidth.newValue(2 * limit_range(1.f - localcopy[...].f, 0.01f, 0.99f));
```

Range: 1% to 99% duty cycle.

### Multitype System: Three Waveform Algorithms

The oscillator can operate in **three modes** for the third mix slider:

**Sine/Square/Triangle selector** via right-click on third parameter (lines 498-502):
```cpp
if (oscdata->p[mo_tri_mix].deform_type != cachedDeform) {
    cachedDeform = oscdata->p[mo_tri_mix].deform_type;
    multitype = ((ModernOscillator::mo_multitypes)(cachedDeform & 0xF));
}
```

This changes which polynomial is evaluated for the third waveform.

### Sub-Oscillator

**Sub-one-octave mode** (right-click third parameter):

Runs an independent oscillator at **half frequency** using the selected multitype algorithm:

```cpp
auto dp = subdpbase.v;               // Half the main frequency
auto dsp = subdpsbase.v;

// Evaluate polynomial at sub-octave phase
double sub = (triBuff[0] + triBuff[2] - 2.0 * triBuff[1]) / (4 * dsp * dsp);

vL += trimix.v * sub;                // Add to main output
```

**Sub-sync option**: Sub can either:
- Follow main sync (default)
- Ignore sync (independent sub)

### Hard Sync

The Modern oscillator implements **hard sync** with anti-aliasing compensation (lines 366-387):

```cpp
if (phase[u] > 1) {
    phase[u] -= 1;

    if (sReset[u]) {
        // Reset sync phase to proportional position
        sphase[u] = phase[u] * dsp / dp;
        sphase[u] -= floor(sphase[u]);

        // Crossfade with prior sample to reduce aliasing
        if (sync.v > 1e-4)
            sTurnFrac[u] = 0.5;
        sTurnVal[u] = res + (sprior[u] - res) * dsp;
    }

    sReset[u] = !sReset[u];  // Toggle every cycle
}

// Apply turnover blend
res = res * (1.0 - sTurnFrac[u]) + sTurnFrac[u] * sTurnVal[u];
```

This creates a **single-sample linear crossfade** at the sync point, dramatically reducing aliasing.

### Pitch Lag Filter

To handle rapid pitch changes (lines 127-129):
```cpp
pitchlag.setRate(0.5);
pitchlag.startValue(pitch);
// ... later:
pitchlag.process();  // Smooth pitch changes
```

Without this, the numerical derivative becomes unstable during rapid pitch modulation (e.g., vibrato). The lag filter smooths this out.

### Parameters

#### Sawtooth (-100% to +100%, bipolar)
Mix level of the sawtooth waveform.

#### Pulse (-100% to +100%, bipolar)
Mix level of the pulse/square waveform.

#### Multitype (Square/Sine/Triangle)
Third waveform type with dynamic label. Enabled sub-octave mode adds " Sub" to the name.

#### Width (1% to 99%)
Pulse width / duty cycle. 50% = square wave.

#### Sync (0 to +60 semitones)
Hard sync frequency offset. 12 semitones = octave up sync.

#### Unison Voices (1-16)
Number of unison voices.

#### Unison Detune
Relative or absolute (Hz) detuning.

### Sound Design Examples

#### Perfectly Clean Supersaw
- **Sawtooth**: 100%
- **Pulse**: 0%
- **Triangle**: 0%
- **Width**: 50%
- **Sync**: 0
- **Unison**: 7 voices, 15 cents
- **Result**: Zero aliasing even with modulation

#### Classic Sync Lead
- **Sawtooth**: 100%
- **Pulse**: -50%
- **Sync**: 19 semitones (octave + fifth)
- **Sync modulated**: LFO ±12 semitones
- **Width**: 50%
- **Result**: Clean sync sweep

#### Parabolic Pad
- **Sawtooth**: 0%
- **Sine**: 80%
- **Pulse**: 20%
- **Width**: 30% (slight pulse)
- **Unison**: 5 voices, 8 cents

#### Sub Bass
- **Triangle Sub**: 100%
- **All others**: 0%
- **Sub mode**: Enabled (skip sync)
- **Play**: Low notes

---

## 5. Window Oscillator: Windowed Wavetable Convolution

The **Window Oscillator** performs **spectral convolution** between a wavetable and a selectable window function, creating formant-like filtering and spectral transformations. This unique approach enables vocal character, morphing timbres, and precise harmonic sculpting.

**Implementation**: `/home/user/surge/src/common/dsp/oscillators/WindowOscillator.cpp` (570 lines)

### Architecture: Dual-Table Convolution

The Window oscillator reads from **two tables simultaneously**:

```
Wavetable        Window Function
(user waves)     (9 window types)
    │                   │
    └─────► ✕ ◄─────────┘
            │
         Output
```

**The convolution** (lines 369-392):
```cpp
// Read wavetable with sinc interpolation
SIMD_M128I Wave = SIMD_MM(madd_epi16)(
    SIMD_MM(load_si128)(storage->sinctableI16 + MSPos),
    SIMD_MM(loadu_si128)(&WaveAdr[MPos])
);

// Read window with sinc interpolation
SIMD_M128I Win = SIMD_MM(madd_epi16)(
    SIMD_MM(load_si128)(storage->sinctableI16 + WinSPos),
    SIMD_MM(loadu_si128)(&WinAdr[WinPos])
);

// Multiply wavetable by window
int Out = (iWin[0] * iWave[0]) >> 7;
```

Both tables use **16-bit integer** representation with **windowed sinc interpolation** for mipmap access.

### The Nine Window Functions

Window functions are stored in `storage->WindowWT` (loaded at init). Common windows from DSP:

1. **Triangle**: Linear taper - gentle filtering
2. **Hann (Hanning)**: Cosine taper - smooth filtering
3. **Hamming**: Modified cosine - sharper cutoff
4. **Blackman**: Three-term cosine - very smooth
5. **Kaiser**: Bessel-derived - adjustable rolloff
6. **Rectangular**: No windowing - full spectrum
7. **Blackman-Harris**: Four-term - minimal sidelobes
8. **Bartlett**: Triangular - endpoint zeros
9. **Tukey**: Rectangular with cosine tapers - hybrid

Each window creates different spectral characteristics when multiplied with the wavetable.

### Formant Shifting

The **Formant** parameter shifts the wavetable read position relative to the window position:

```cpp
int FormantMul = (int)(float)(65536.f * storage->note_to_pitch_tuningctr(
    localcopy[oscdata->p[win_formant].param_id_in_scene].f));
```

**Effect**:
- **Positive formant**: Wavetable compressed (higher frequencies emphasized)
- **Negative formant**: Wavetable stretched (lower frequencies emphasized)
- **Pitch stays constant** while timbre shifts

**In the convolution** (line 364):
```cpp
unsigned int FPos = BigMULr16(Window.FormantMul[so], Pos) & SizeMask;
```

Creates **vocal formant** effects: `Pos` advances at fundamental frequency, but wavetable reads at `FormantMul * Pos`, shifting the resonances.

### Morph Parameter: Table Interpolation

**Morph** crossfades between wavetable frames:

```cpp
int Table = limit_range((int)(oscdata->wt.n_tables * l_morph.v), 0, n_tables - 1);
int TablePlusOne = limit_range(Table + 1, 0, n_tables - 1);
float FTable = limit_range(frac - Table, 0.f, 1.f);

// In output:
iWave[0] = (int)((1.f - FTable) * iWave[0] + FTable * iWaveP1[0]);
```

**Behavior**:
- **Standard mode**: Morph snaps to integer tables (no interpolation)
- **Extended mode** (right-click): Smooth interpolation between tables

### Mipmap Selection

The oscillator uses **mipmaps** (pre-filtered octaves) to avoid aliasing at high frequencies:

```cpp
unsigned long MSBpos;
unsigned int bs = BigMULr16(RatioA, 3 * FormantMul);

if (_BitScanReverse(&MSBpos, bs))  // Find highest set bit
    MipMapB = limit_range((int)MSBpos - 17, 0, oscdata->wt.size_po2 - 1);
```

**Effect**: High notes automatically read from low-pass filtered versions of the wavetable, preventing aliasing.

### Parameters

#### Morph (0-100%)
Scans through wavetable frames. Enable "Extended" mode for smooth interpolation.

#### Formant (±60 semitones)
Shifts formant regions up/down independently of pitch.

#### Window (9 types)
Selects window function for spectral shaping.

#### Low Cut / High Cut
Optional filters (deactivatable) for additional tone control.

#### Unison Detune / Voices
Unison with up to 16 voices, absolute or relative detuning.

### Sound Design Examples

#### Vocal Formant Sweep
- **Wavetable**: Harmonic-rich waveform (sawtooth-like)
- **Morph**: 30%
- **Formant**: LFO'd ±24 semitones
- **Window**: Hamming
- **Result**: Vowel-like morphing

#### Spectral Drone
- **Wavetable**: Complex evolving table
- **Morph**: Slow LFO (full range)
- **Formant**: +12 semitones
- **Window**: Blackman
- **Unison**: 7 voices, 20 cents

#### Metallic Bells
- **Wavetable**: Inharmonic table
- **Formant**: +36 semitones
- **Window**: Rectangle (no filtering)
- **Low Cut**: 1000 Hz
- **High Cut**: 8000 Hz

---

## 6. Sample & Hold Oscillator: Stochastic Noise Synthesis

The **Sample & Hold (S&H) Oscillator** generates **sample-and-hold** stepped waveforms and **correlated noise**, creating everything from stepped random melodies to smooth noise textures. Unlike traditional oscillators that generate continuous waveforms, S&H creates **discrete voltage steps** at controllable rates.

**Implementation**: `/home/user/surge/src/common/dsp/oscillators/SampleAndHoldOscillator.cpp` (511 lines)

### Architecture: Windowed Impulse with Random Heights

Like Classic oscillator, S&H inherits from `AbstractBlitOscillator`, but instead of deterministic impulse heights, it uses **random values**:

```
Random Generator → Sample & Hold → Windowed Sinc → Integration → Output
```

**Key difference**: The `convolute()` method (lines 175-323) generates impulses with **random amplitudes** rather than fixed waveform transitions.

### Correlation: The Core Algorithm

The **Correlation** parameter controls how much each new random value **relates to the previous**:

```cpp
float wf = l_shape.v * 0.8 * invertcorrelation;
float wfabs = fabs(wf);
float rand11 = urng();  // Random -1 to +1
float randt = rand11 * (1 - wfabs) - wf * last_level[voice];

randt = randt / (1.0f - wfabs);
randt = min(0.5f, max(-0.5f, randt));
```

**Parameter settings**:

**Correlation = 0%**: Pure white noise (each sample independent)
```
Output: ─┐  ┌──┐     ┌─
         └──┘  └─────┘
```

**Correlation = +100%**: "Drunk walk" (each step adds to previous)
```
Output:     ╱╲
           ╱  ╲╱
          ╱
```

**Correlation = -100%**: Anti-correlated (oscillates around zero)
```
Output: ─┐ ┌─┐ ┌─
         └─┘ └─┘
```

**The math** (line 255):
```cpp
randt = rand11 * (1 - wfabs) - wf * last_level[voice];
```

- `rand11`: Fresh random value
- `(1 - wfabs)`: Scaling of randomness (less correlation = more random)
- `wf * last_level`: Influence of prior sample (more correlation = more influence)

**Bipolar inversion** (line 250):
```cpp
if (state[voice] == 1)
    invertcorrelation = -1.f;
```

Every other step inverts the correlation, creating alternating behavior for certain settings.

### Width: Sample & Hold Rate

The **Width** parameter controls how long each sample is **held** before updating:

```cpp
if (state[voice] & 1)
    rate[voice] = t * (1.0 - pwidth[voice]);
else
    rate[voice] = t * pwidth[voice];
```

**Effect**:
- **Width = 50%**: Even on/off timing - regular S&H rate
- **Width < 50%**: Short holds, fast updates
- **Width > 50%**: Long holds, slow updates

This interacts with the fundamental pitch to create the S&H stepping rate.

### Sync: Hard Sync for Rhythmic Steps

The **Sync** parameter adds a second oscillator running at a different rate (lines 188-211):

```cpp
if (syncstate[voice] < oscstate[voice]) {
    // Sync point reached!
    state[voice] = 0;
    oscstate[voice] = syncstate[voice];
    syncstate[voice] += t;
}
```

Creates **rhythmic resets** of the S&H clock, useful for:
- Polyrhythmic stepped sequences
- Tempo-synced noise bursts
- Cross-modulated random melodies

### Filters: Taming the Noise

The S&H oscillator includes deactivatable **high-pass and low-pass filters** (lines 325-348):

```cpp
if (!oscdata->p[shn_lowcut].deactivated)
    hp.coeff_HP(hp.calc_omega(pv / 12.0) / OSC_OVERSAMPLING, 0.707);

if (!oscdata->p[shn_highcut].deactivated)
    lp.coeff_LP2B(lp.calc_omega(pv / 12.0) / OSC_OVERSAMPLING, 0.707);
```

Essential for:
- **Low Cut**: Removing sub-bass rumble from noise
- **High Cut**: Smoothing harsh stepped transitions

### Integration and DC Blocking

The oscillator output passes through an **integrator with HPF** for DC removal (lines 450-465):

```cpp
auto hpf = SIMD_MM(load_ss)(&hpfblock[k]);
auto ob = SIMD_MM(load_ss)(&oscbuffer[bufpos + k]);
auto a = SIMD_MM(mul_ss)(osc_out, hpf);  // Prior output * HPF coeff
ob = SIMD_MM(sub_ss)(ob, SIMD_MM(mul_ps)(mdc, oa));  // Remove DC
osc_out = SIMD_MM(add_ss)(a, ob);  // Integrate
```

The **HPF coefficient** adapts to pitch (lines 358-362):
```cpp
float invt = 4.f * min(1.0, (8.175798915 * pp * storage->dsamplerate_os_inv));
float hpf2 = min(integrator_hpf, powf(hpf_cycle_loss, invt));
```

This prevents DC buildup while maintaining waveform shape.

### Sound Design Examples

#### Vintage S&H Synth Lead
- **Correlation**: 0% (pure random)
- **Width**: 50%
- **Sync**: 0 (no sync)
- **High Cut**: 5000 Hz
- **Low Cut**: 200 Hz
- **Unison**: 3 voices, 12 cents
- **Add**: Resonant filter sweep

#### Smooth Random Modulation Source
- **Correlation**: +80% (smooth walk)
- **Width**: 30% (slow stepping)
- **High Cut**: 500 Hz
- **Use**: Route to filter cutoff via modulation

#### Rhythmic Gated Noise
- **Correlation**: -50% (anti-correlated)
- **Width**: 20%
- **Sync**: +12 semitones
- **Low Cut**: 2000 Hz
- **Result**: Synced noise bursts

#### Stepping Random Melody
- **Correlation**: +30%
- **Width**: 60%
- **Sync**: +7 semitones
- **Quantize**: Use MIDI processor to quantize to scale
- **Result**: Random melodic patterns

---

## 7. Audio Input Oscillator: External Signal Routing

The **Audio Input Oscillator** routes **external audio** into the synthesis engine, enabling vocoding, sidechaining, creative resampling, and hybrid processing. Unlike traditional oscillators that generate audio, this one becomes a **gateway** for microphones, instruments, or other DAW tracks.

**Implementation**: `/home/user/surge/src/common/dsp/oscillators/AudioInputOscillator.cpp` (209 lines)

### Architecture: Dual-Scene Routing

The oscillator accesses **two potential audio sources**:

1. **Main Input**: `storage->audio_in[0/1][k]` - external audio routed to Surge
2. **Other Scene**: `storage->audio_otherscene[0/1][k]` - audio from the opposite scene

```
External Audio ──► storage->audio_in ──┐
                                        ├──► Mix/Pan ──► Output
Scene A/B Out ──► storage->audio_otherscene ──┘
```

**Scene B special features** (lines 69-77):
If the oscillator is in Scene B, it gains three additional parameters:
- **Scene A Channel**: Pan/mix of Scene A audio
- **Scene A Gain**: Level control for Scene A
- **Scene A Mix**: Blend between external input and Scene A

This enables **scene cross-processing**: Scene B can process Scene A's output, creating layered effects.

### Parameters

#### Audio In Channel (-100% to +100%)

Controls stereo positioning of external input:

```cpp
float l = inGain * (1.f - inChMix);  // Left channel gain
float r = inGain * (1.f + inChMix);  // Right channel gain
```

- **-100%**: Left input only
- **0%**: Stereo (both channels)
- **+100%**: Right input only

#### Audio In Gain (-48 dB to +48 dB)

Input level control:
```cpp
float inGain = storage->db_to_linear(localcopy[...].f);
```

Essential for:
- Matching levels between instruments
- Gain staging before filters/effects
- Creating ducking/sidechaining effects

#### Scene A Channel / Gain / Mix (Scene B only)

Enable **inter-scene routing** (lines 135-140):
```cpp
if (useOtherScene) {
    output[k] = (l * storage->audio_in[0][k] * inverseMix) +
                (sl * storage->audio_otherscene[0][k] * sceneMix);
    outputR[k] = (r * storage->audio_in[1][k] * inverseMix) +
                 (sr * storage->audio_otherscene[1][k] * sceneMix);
}
```

**Scene A Mix** blends:
- **0%**: Only external audio input
- **50%**: Equal mix of input and Scene A
- **100%**: Only Scene A output

#### Low Cut / High Cut

Deactivatable filters (same as other oscillators) for tone shaping.

### Use Cases

#### Classic Vocoder

**Setup**:
1. **Oscillator 1**: Sawtooth (carrier)
2. **Oscillator 2**: Audio Input (modulator)
   - **Input**: Microphone with speech
3. **Filter**: Comb filter or formant filter
4. **Modulation**: Route Audio Input oscillator → Filter Cutoff

**Result**: Speech-imposed-on-synth vocoder effect.

#### Sidechain Compression Simulation

**Setup**:
1. **Scene A**: Main synth pad
2. **Scene B**: Audio Input oscillator
   - **Route**: Kick drum to external input
   - **Scene A Mix**: 80% (mostly Scene A)
3. **Modulation**: Audio Input amplitude → Scene A FEG negative

**Result**: Pad ducks when kick hits.

#### External Filter

**Setup**:
1. **Audio Input** as only oscillator
2. **Route**: Guitar/bass to input
3. **Use**: Surge's filters, effects, modulation

**Result**: Use Surge as an effects processor.

#### Hybrid Synthesis

**Setup**:
1. **Oscillator 1**: Classic sawtooth
2. **Oscillator 2**: Audio Input (acoustic instrument)
3. **Mix**: 50/50

**Result**: Blend synthetic and acoustic timbres.

#### Scene Feedback

**Scene B Setup**:
1. **Audio Input** with **Scene A Mix = 100%**
2. **Add**: Different filters, effects
3. **Route**: Scene B output back to Scene A input (external routing)

**Result**: Feedback processing between scenes.

### Technical Notes

#### Latency Considerations

The Audio Input oscillator operates at **Surge's internal buffer size** with no additional latency. However:
- **DAW routing latency** applies when routing between tracks
- **Hardware interface latency** applies for microphone/line inputs

#### Stereo vs. Mono

The oscillator adapts to voice mode (lines 131-165):

**Stereo mode**:
```cpp
output[k] = l * storage->audio_in[0][k];
outputR[k] = r * storage->audio_in[1][k];
```

**Mono mode**:
```cpp
output[k] = l * storage->audio_in[0][k] + r * storage->audio_in[1][k];
```

Mono voices sum both input channels.

#### Scene Routing

When accessing the other scene (lines 29-40):
```cpp
storage->otherscene_clients++;
```

This increments a counter to inform Surge that inter-scene routing is active, ensuring proper audio flow.

### Sound Design Examples

#### Vocoder Synth
- **Oscillator**: Audio Input
- **Input**: Microphone (speech)
- **Voice**: Modulate Classic oscillator filter
- **Filter**: Multiple bandpass filters
- **Result**: Classic robotic voice

#### Talking Instrument
- **Oscillator 1**: String oscillator
- **Oscillator 2**: Audio Input (speech)
- **Mix**: 70% String / 30% Audio
- **Filter**: Formant filter following Audio Input
- **Result**: Instrument that "speaks"

#### Rhythmic Gate
- **Audio Input**: Ambient pad
- **Modulation**: LFO'd gain for rhythmic gating
- **Filter**: Sync'd to tempo
- **Result**: Rhythmically chopped pad

#### External Effects Chain
- **Input**: Entire drum loop
- **Filter**: Comb filter
- **Effects**: Reverb, chorus
- **Result**: Processed drum loop

---

## Conclusion: The Spectrum of Oscillator Design

This chapter covered seven oscillators that span the full range of synthesis approaches:

**Physical Modeling**: String oscillator simulates acoustic instruments through delay-line resonance.

**Multi-Engine**: Twist packs 16 synthesis engines into one oscillator.

**Lo-Fi Digital**: Alias embraces 8-bit quantization and intentional aliasing.

**Pristine Analog**: Modern achieves perfect anti-aliasing through mathematical polynomial differentiation.

**Spectral**: Window performs wavetable convolution with selectable window functions.

**Stochastic**: Sample & Hold generates correlated random stepping waveforms.

**External**: Audio Input routes external audio into the synthesis engine.

Together with the Classic (Chapter 6), Wavetable (Chapter 7), and FM (Chapter 8) oscillators, Surge XT provides an unparalleled toolkit for sound creation—from mathematically precise to beautifully broken, from physical simulations to abstract digital processes.

The next chapters will explore how these oscillator outputs are shaped by Surge's extensive filter and effect systems, turning raw waveforms into finished sounds.

---

**Chapter word count**: ~6,800 words
**File size**: ~27 KB
