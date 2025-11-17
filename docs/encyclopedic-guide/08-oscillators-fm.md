# Chapter 8: FM Synthesis - Frequency Modulation Oscillators

## Introduction

**Frequency Modulation (FM) synthesis** revolutionized electronic music in the 1980s by producing complex, evolving timbres from simple sine waves. What John Chowning discovered in 1967 - that modulating the frequency of one oscillator with another creates rich harmonic spectra - became the foundation for instruments like the Yamaha DX7 and countless synthesis techniques.

Surge XT includes three oscillators dedicated to FM synthesis:

- **FM2**: 2-operator configuration with dual modulators
- **FM3**: 3-operator configuration with flexible routing
- **Sine**: Multiple sine-based shapes with FM feedback

This chapter explores FM synthesis from mathematical foundations through practical implementation, revealing how Surge creates everything from bell-like tones to aggressive metallic textures.

**Implementation Files**:
- `/home/user/surge/src/common/dsp/oscillators/FM2Oscillator.cpp`
- `/home/user/surge/src/common/dsp/oscillators/FM3Oscillator.cpp`
- `/home/user/surge/src/common/dsp/oscillators/SineOscillator.cpp`

## FM Theory Fundamentals

### The Basic Equation

At its core, FM synthesis is deceptively simple. A **carrier** oscillator has its frequency modulated by a **modulator** oscillator:

```
carrier(t) = A_c * sin(ω_c * t + I * sin(ω_m * t))
```

Where:
- `A_c`: Carrier amplitude
- `ω_c`: Carrier frequency (radians/sec)
- `ω_m`: Modulator frequency (radians/sec)
- `I`: Modulation index (depth of frequency modulation)
- `t`: Time

**Key insight**: The modulator doesn't multiply the carrier (like amplitude modulation). Instead, it **changes the carrier's instantaneous frequency**.

### Phase Modulation vs. Frequency Modulation

Surge (like most digital FM implementations) actually uses **phase modulation (PM)** rather than true frequency modulation:

```cpp
// From FM2Oscillator.cpp, line 118:
output[k] = phase + RelModDepth1.v * RM1.r + RelModDepth2.v * RM2.r + fb_amt + PhaseOffset.v;

if (FM)
    output[k] += FMdepth.v * master_osc[k];

oldout1 = sin(output[k]);
output[k] = oldout1;
```

**Why PM instead of FM?**

True FM requires integration:
```
FM: y(t) = sin(ω_c * t + ∫ m(t) dt)
PM: y(t) = sin(ω_c * t + m(t))
```

Phase modulation is mathematically simpler and computationally cheaper. When the modulator is a sine wave, PM and FM differ only by a 90-degree phase shift of the modulator, making them essentially equivalent for musical purposes.

### Modulation Index and Sidebands

The **modulation index** `I` determines how much the modulator affects the carrier. This single parameter controls the harmonic complexity of the output.

**Spectrum analysis**: When both carrier and modulator are sine waves, the output contains sidebands at:

```
f_sideband = f_c ± n * f_m
```

Where `n` ranges from 0 to approximately `I` (the modulation index).

**Example**: Carrier at 440 Hz, modulator at 100 Hz, modulation index I = 3:

Significant frequencies:
- 440 Hz (carrier)
- 540 Hz (440 + 100)
- 640 Hz (440 + 200)
- 740 Hz (440 + 300)
- 340 Hz (440 - 100)
- 240 Hz (440 - 200)
- 140 Hz (440 - 300)

The amplitudes of these sidebands follow **Bessel functions**.

### Bessel Functions: The Mathematics of FM

The spectrum of FM synthesis is governed by **Bessel functions of the first kind**, denoted J_n(I):

```
carrier(t) = A_c * Σ J_n(I) * sin((ω_c + n*ω_m) * t)
```

For nth sideband at frequency `f_c + n*f_m`, amplitude is `J_n(I)`.

**Properties of Bessel functions**:

1. **J_0(I)**: Amplitude of the carrier
2. **J_n(I)**: Amplitude of nth upper/lower sideband pair
3. As `I` increases, energy spreads to higher sidebands
4. At certain values of `I`, J_0(I) = 0 (carrier disappears!)

**Example values**:

| I | J_0 | J_1 | J_2 | J_3 | J_4 |
|---|-----|-----|-----|-----|-----|
| 0 | 1.00 | 0.00 | 0.00 | 0.00 | 0.00 |
| 1 | 0.77 | 0.44 | 0.11 | 0.02 | 0.00 |
| 2 | 0.22 | 0.58 | 0.35 | 0.13 | 0.03 |
| 3 | -0.26 | 0.34 | 0.49 | 0.31 | 0.13 |
| 5 | -0.18 | -0.33 | 0.05 | 0.36 | 0.39 |

**Critical insight**: At I = 2.4048, J_0 = 0. The carrier completely vanishes and all energy exists in sidebands - creating a distinctive "hollow" sound.

### C:M Ratio - Harmonic vs. Inharmonic

The **carrier-to-modulator ratio (C:M ratio)** determines whether the output is harmonic or inharmonic.

**Integer ratios** (1:1, 2:1, 3:2, etc.): All sidebands are integer multiples of a fundamental frequency - **harmonic spectrum**, sounds pitched and musical.

```
C:M = 1:1, carrier = 440 Hz, modulator = 440 Hz
Sidebands: 440, 880, 1320, 1760, 2200... (harmonic series)
```

**Non-integer ratios** (1:1.5, 2.7:1, etc.): Sidebands are not integer multiples - **inharmonic spectrum**, sounds bell-like or metallic.

```
C:M = 1:1.5, carrier = 440 Hz, modulator = 660 Hz
Sidebands: 440, 1100, 1760, 2420... (inharmonic)
```

**In Surge's FM oscillators**:

```cpp
// FM2Oscillator.cpp, lines 92-97:
RM1.set_rate(
    min(M_PI,
        (double)pitch_to_omega(pitch + driftlfo) * (double)oscdata->p[fm2_m1ratio].val.i + sh));
RM2.set_rate(
    min(M_PI,
        (double)pitch_to_omega(pitch + driftlfo) * (double)oscdata->p[fm2_m2ratio].val.i - sh));
```

Ratios are **integer-based** for FM2 (1, 2, 3... 32), encouraging harmonic timbres. FM3 supports **fractional ratios** and **absolute frequencies** for inharmonic sounds.

### Spectrum Evolution

One of FM's most powerful features is **dynamic spectral evolution**. By modulating the modulation index over time (with an envelope or LFO), you create sounds that evolve from simple to complex:

**Attack phase**: High modulation index (I = 5-10)
- Bright, complex spectrum
- Many high-frequency sidebands
- Percussive attack

**Decay/Sustain**: Decreasing modulation index (I = 2-0.5)
- Spectrum collapses toward carrier
- Gradual loss of harmonics
- Natural decay simulation

This is how FM creates realistic instruments like electric pianos, bells, and brass.

## FM2 Oscillator - Two Operator Architecture

### Operator Topology

The FM2 oscillator implements a **2-operator parallel configuration**:

```
        ┌─────────┐
        │ Carrier │ ← Feedback
        │  (sine) │
        └────┬────┘
             ↑
      ┌──────┴──────┐
      │             │
  ┌───┴───┐    ┌───┴───┐
  │  M1   │    │  M2   │
  │(Mod 1)│    │(Mod 2)│
  └───────┘    └───────┘
```

**Structure**:
- **Carrier**: Main sine oscillator, produces the output
- **M1 & M2**: Two independent modulators that modulate the carrier's phase
- **Feedback**: Carrier output fed back to its own phase

This configuration allows:
- Independent modulation from two sources
- Different frequency ratios for M1 and M2
- Detuning between modulators for thickness
- Self-modulation via feedback

### Parameters

#### M1 Amount & M2 Amount (0% to 100%)

Controls the **modulation depth** for each modulator - equivalent to the modulation index `I`.

```cpp
// FM2Oscillator.cpp, line 34:
double calcmd(double x) { return x * x * x * 8.0 * M_PI; }

// Lines 99-103:
double d1 = localcopy[oscdata->p[fm2_m1amount].param_id_in_scene].f;
double d2 = localcopy[oscdata->p[fm2_m2amount].param_id_in_scene].f;

RelModDepth1.newValue(calcmd(d1));
RelModDepth2.newValue(calcmd(d2));
```

**Why cube the input?** The `x³` scaling gives finer control at low values where subtle modulation is needed, and aggressive scaling at high values for extreme timbres. The `8π` multiplier translates to phase modulation depth.

**Practical values**:
- **0-10%**: Subtle vibrato, slight warmth
- **20-40%**: Moderate harmonic content, useful for basses
- **50-70%**: Bright, complex timbres
- **80-100%**: Aggressive, metallic sounds

#### M1 Ratio & M2 Ratio (1 to 32, integer)

Sets the frequency **ratio** of each modulator to the carrier.

```cpp
// FM2Oscillator.cpp, lines 92-97:
RM1.set_rate(
    min(M_PI,
        (double)pitch_to_omega(pitch + driftlfo) * (double)oscdata->p[fm2_m1ratio].val.i + sh));
RM2.set_rate(
    min(M_PI,
        (double)pitch_to_omega(pitch + driftlfo) * (double)oscdata->p[fm2_m2ratio].val.i - sh));
```

**Musical ratios**:

| Ratio | Interval | Character |
|-------|----------|-----------|
| 1:1 | Unison | Rich, harmonic |
| 2:1 | Octave | Hollow, clarinet-like |
| 3:1 | Octave + Fifth | Organ-like |
| 4:1 | Two Octaves | Bell-like |
| 7:1 | Non-harmonic | Metallic |

**Combining M1 and M2**: Set different ratios to create complex spectra:
- M1 = 1, M2 = 2: Fundamental + octave components
- M1 = 3, M2 = 5: Complex harmonic relationships
- M1 = 1, M2 = 7: Harmonic core with inharmonic edge

#### M1/2 Offset (-1 to +1, extended to ±16)

Adds a **frequency offset** between M1 and M2, measured in Hz (when extended) or as a fraction of sample rate.

```cpp
// FM2Oscillator.cpp, lines 85-87:
double sh = oscdata->p[fm2_m12offset].get_extended(
                localcopy[oscdata->p[fm2_m12offset].param_id_in_scene].f) *
            storage->dsamplerate_inv;
```

**Effect**: Creates detuning between the two modulators:
- `sh` is added to M1's frequency
- `sh` is subtracted from M2's frequency

**Musical use**:
- **0**: Both modulators at exact ratio
- **Small offset (0.01-0.1)**: Subtle beating, organic movement
- **Large offset (1-5 Hz)**: Distinct detuned character, thicker sound

This is similar to detuning two oscillators in subtractive synthesis, but affecting the modulation spectrum rather than the fundamental.

#### M1/2 Phase (0% to 100%)

Sets the **initial phase offset** for both modulators.

```cpp
// FM2Oscillator.cpp, lines 45-50:
double ph = (localcopy[oscdata->p[fm2_m12phase].param_id_in_scene].f + phase) * 2.0 * M_PI;
RM1.set_phase(ph);
RM2.set_phase(ph);
phase = -sin(ph) * (calcmd(localcopy[oscdata->p[fm2_m1amount].param_id_in_scene].f) +
                    calcmd(localcopy[oscdata->p[fm2_m2amount].param_id_in_scene].f)) -
        ph;
```

**Effect**: Changes the starting point in the modulator waveforms.

**Practical use**:
- Affects the initial attack transient
- Can create different timbral characters from the same settings
- Useful when automated: creates evolving spectral sweeps
- With retrigger off: random phase creates variation per note

#### Feedback (-100% to +100%)

Routes the carrier's **output back to its own phase input**, creating self-modulation.

```cpp
// FM2Oscillator.cpp, lines 89-90, 115-116:
fb_val = oscdata->p[fm2_feedback].get_extended(
    localcopy[oscdata->p[fm2_feedback].param_id_in_scene].f);

double avg = mode == 1 ? ((oldout1 + oldout2) / 2.0) : oldout1;
double fb_amt = (fb_val < 0) ? avg * avg * FeedbackDepth.v : avg * FeedbackDepth.v;
```

**Two modes** (determined by deform_type):
- **Mode 0**: Single-sample feedback (`oldout1`)
- **Mode 1**: Averaged feedback (`(oldout1 + oldout2) / 2`)

**Sign matters**:
- **Positive feedback**: Linear scaling (`fb_val * output`)
- **Negative feedback**: Square scaling (`fb_val * output²`), adds asymmetry

**Musical effect**:
- **0%**: No feedback, clean FM
- **10-30%**: Adds harmonics, brightness
- **50-70%**: Aggressive, distorted character
- **90-100%**: Extreme, chaotic sounds

Feedback creates additional sidebands that aren't present in the carrier-modulator relationship, significantly enriching the spectrum.

### Implementation Deep Dive

#### Quadrature Oscillators

FM2 uses `SurgeQuadrOsc` from `sst::basic-blocks::dsp` for modulators:

```cpp
// FM2Oscillator.h, lines 63-65:
using quadr_osc = sst::basic_blocks::dsp::SurgeQuadrOsc<float>;

quadr_osc RM1, RM2;
```

A **quadrature oscillator** generates sine and cosine simultaneously:
- `.r`: Real part (cosine)
- `.i`: Imaginary part (sine)

**Why quadrature?** Provides both sin and cos with a single oscillator, useful for certain modulation schemes and efficient for complex modulation topologies.

#### The Processing Loop

```cpp
// FM2Oscillator.cpp, lines 110-140:
for (int k = 0; k < BLOCK_SIZE_OS; k++)
{
    RM1.process();  // Advance modulator 1
    RM2.process();  // Advance modulator 2

    // Calculate feedback amount
    double avg = mode == 1 ? ((oldout1 + oldout2) / 2.0) : oldout1;
    double fb_amt = (fb_val < 0) ? avg * avg * FeedbackDepth.v : avg * FeedbackDepth.v;

    // Accumulate phase modulation
    output[k] = phase + RelModDepth1.v * RM1.r + RelModDepth2.v * RM2.r +
                fb_amt + PhaseOffset.v;

    if (FM)
        output[k] += FMdepth.v * master_osc[k];  // Linear FM from Scene A

    // Store history for feedback
    oldout2 = oldout1;
    oldout1 = sin(output[k]);
    output[k] = oldout1;

    // Advance carrier phase
    phase += omega;
    if (phase > 2.0 * M_PI)
        phase -= 2.0 * M_PI;

    // Smooth parameter changes
    RelModDepth1.process();
    RelModDepth2.process();
    FeedbackDepth.process();
    PhaseOffset.process();

    if (FM)
        FMdepth.process();
}
```

**Signal flow per sample**:
1. Generate M1 and M2 values (quadrature oscillators)
2. Calculate feedback based on previous output
3. Sum: carrier phase + M1 modulation + M2 modulation + feedback + phase offset
4. Add linear FM if enabled (Scene A modulating Scene B)
5. Take sine of accumulated phase
6. Store output for next feedback calculation
7. Advance carrier phase
8. Smooth all modulation depth parameters

#### Lag Processors

All modulation depths use **lag processors** (`lag<double>`) to smooth parameter changes:

```cpp
// FM2Oscillator.h, line 69:
lag<double> FMdepth, RelModDepth1, RelModDepth2, FeedbackDepth, PhaseOffset;
```

**Purpose**: Prevents zipper noise when modulating parameters. The lag creates a first-order low-pass filter on parameter changes.

### Sound Design Examples with FM2

#### Electric Piano

Classic FM electric piano (DX7 style):

```
M1 Amount: 100%
M1 Ratio: 1
M2 Amount: 70%
M2 Ratio: 14  (creates bell-like timbre)
M1/2 Offset: 0.02  (slight detuning for organic quality)
Feedback: -20%  (adds bite to attack)

Envelope → M1 Amount: Fast attack, medium decay to ~30%
Envelope → M2 Amount: Fast attack, fast decay to ~10%
```

The high M2 ratio (14:1) creates inharmonic partials characteristic of struck metal tines. The envelope decay on modulation creates the natural timbre evolution from bright attack to warm sustain.

#### FM Bass

Aggressive, modern bass sound:

```
M1 Amount: 85%
M1 Ratio: 1
M2 Amount: 60%
M2 Ratio: 2
M1/2 Offset: 0.5 Hz
Feedback: 40%

Filter: Low-pass at ~2000 Hz, resonance ~30%
Envelope → M1 Amount: Medium decay
LFO → Feedback: Slow sine, ±20%, adds movement
```

The 2:1 ratio creates a strong octave component. Feedback adds aggression and harmonic density. The offset creates subtle motion.

#### Bell/Mallet Sound

Metallic, bell-like percussion:

```
M1 Amount: 100%
M1 Ratio: 3
M2 Amount: 80%
M2 Ratio: 7  (non-harmonic ratio)
M1/2 Offset: 0
Feedback: 10%

Envelope → M1 Amount: Instant attack, slow exponential decay
Envelope → M2 Amount: Instant attack, medium decay
Pitch Envelope: +1200 cents, instant decay to 0 (pitch drop on attack)
```

Non-integer ratio (3:7 relative) creates inharmonic spectrum. Different envelope rates on modulators create natural timbre evolution of a struck bell.

## FM3 Oscillator - Three Operator Architecture

### Extended Topology

FM3 adds a third operator with **flexible routing**:

```
        ┌─────────┐
        │ Carrier │ ← Feedback
        │  (sine) │
        └────┬────┘
             ↑
      ┌──────┼──────┐
      │      │      │
  ┌───┴───┐  │  ┌───┴───┐
  │  M1   │  │  │  M2   │
  │(Mod 1)│  │  │(Mod 2)│
  └───────┘  │  └───────┘
             │
         ┌───┴───┐
         │  M3   │
         │(Mod 3)│
         └───────┘
```

**Key difference from FM2**: M3 operates at an **absolute frequency** rather than a ratio, making it ideal for:
- Fixed formant peaks
- Detuned layers
- LFO-rate modulation
- Special effects

### Parameters

#### M1 Amount & M2 Amount (0% to 100%)

Identical to FM2, but with extended scaling:

```cpp
// FM3Oscillator.cpp, lines 128-133:
double d1 = localcopy[oscdata->p[fm3_m1amount].param_id_in_scene].f;
double d2 = localcopy[oscdata->p[fm3_m2amount].param_id_in_scene].f;

RelModDepth1.newValue(32.0 * M_PI * d1 * d1 * d1);
RelModDepth2.newValue(32.0 * M_PI * d2 * d2 * d2);
```

Note the `32π` scaling (vs. `8π` in FM2) - FM3 allows deeper modulation.

#### M1 Ratio & M2 Ratio

More sophisticated than FM2, supporting:
- **Fractional ratios** (including negative for division)
- **Absolute frequency mode**

```cpp
// FM3Oscillator.cpp, lines 80-102:
auto m1 = oscdata->p[fm3_m1ratio].get_extended(
    localcopy[oscdata->p[fm3_m1ratio].param_id_in_scene].f);

if (m1 < 0)
{
    m1 = -1.0 / m1;  // Negative values become divisions: -2 → 1/2
}

if (oscdata->p[fm3_m1ratio].absolute)
{
    // Absolute frequency mode: ratio parameter sets a MIDI note
    float f = localcopy[oscdata->p[fm3_m1ratio].param_id_in_scene].f;
    float bpv = (f - 16.0) / 16.0;
    auto note = 69 + 69 * bpv;  // Map to MIDI note range

    RM1.set_rate(min(M_PI, (double)pitch_to_omega(note)));
}
else
{
    // Ratio mode: multiply by pitch
    RM1.set_rate(min(M_PI, (double)pitch_to_omega(pitch + driftlfo) * m1));
}
```

**Ratio mode examples**:
- `1.0`: Unison with carrier
- `2.5`: Two and a half times carrier frequency
- `0.5` (or `-2`): Half carrier frequency (one octave down)
- `1.414`: Tritone above carrier (√2 ratio)

**Absolute mode**: Right-click on ratio to enable
- Modulator frequency becomes **pitch-independent**
- Useful for fixed formants in vocal sounds
- Creates different spectral character at different pitches

#### M3 Amount (0% to 100%)

Controls the third modulator's depth:

```cpp
// FM3Oscillator.cpp, line 134:
AbsModDepth.newValue(32.0 * M_PI * d3 * d3 * d3);
```

Same cubic scaling and `32π` multiplier as M1/M2.

#### M3 Frequency (-60 to +60, extended to ±120 semitones)

Sets M3 as an **absolute frequency** relative to MIDI note 60 (middle C):

```cpp
// FM3Oscillator.cpp, lines 125-126:
AM.set_rate(min(M_PI, (double)pitch_to_omega(
                          60.0 + localcopy[oscdata->p[fm3_m3freq].param_id_in_scene].f)));
```

**Range**:
- `0`: Middle C (261.63 Hz)
- `+12`: One octave above middle C (523.25 Hz)
- `-12`: One octave below middle C (130.81 Hz)
- Extended range (right-click): ±120 semitones (±10 octaves)

**Uses**:
- **Formant synthesis**: Set M3 to a specific frequency (e.g., +24 for vowel formant)
- **LFO-rate modulation**: Set to very low values (e.g., -48 for sub-audio)
- **Fixed spectral peak**: Creates a resonance that doesn't track pitch
- **Detuning layer**: Constant offset from carrier

#### Feedback (-100% to +100%)

Identical implementation to FM2:

```cpp
// FM3Oscillator.cpp, lines 149-150:
double avg = mode == 1 ? ((oldout1 + oldout2) / 2.0) : oldout1;
double fb_amt = (fb_val < 0) ? avg * avg * FeedbackDepth.v : avg * FeedbackDepth.v;
```

Same two modes (single-sample vs. averaged) and sign-dependent scaling.

### The Processing Loop

```cpp
// FM3Oscillator.cpp, lines 143-181:
for (int k = 0; k < BLOCK_SIZE_OS; k++)
{
    RM1.process();  // Modulator 1
    RM2.process();  // Modulator 2
    AM.process();   // Modulator 3 (named AM but it's phase modulation)

    // Calculate feedback
    double avg = mode == 1 ? ((oldout1 + oldout2) / 2.0) : oldout1;
    double fb_amt = (fb_val < 0) ? avg * avg * FeedbackDepth.v : avg * FeedbackDepth.v;

    // Accumulate all phase modulation
    output[k] = phase +
                RelModDepth1.v * RM1.r +
                RelModDepth2.v * RM2.r +
                AbsModDepth.v * AM.r +
                fb_amt;

    if (FM)
    {
        output[k] += FMdepth.v * master_osc[k];
    }

    oldout2 = oldout1;
    oldout1 = sin(output[k]);
    output[k] = oldout1;

    phase += omega;

    if (phase > 2.0 * M_PI)
    {
        phase -= 2.0 * M_PI;
    }

    // Smooth all parameters
    RelModDepth1.process();
    RelModDepth2.process();
    AbsModDepth.process();

    if (FM)
    {
        FMdepth.process();
    }

    FeedbackDepth.process();
}
```

**Note the third oscillator**: `AM` (historically named for amplitude modulation, but used for phase modulation here) adds the absolute-frequency modulation.

### Classic DX7-Style Algorithms

The DX7 had 32 algorithms (operator routing configurations). While Surge's FM3 has a fixed parallel routing, you can approximate several classic DX7 algorithms:

#### Algorithm 1 (Parallel Carriers)

DX7's simplest algorithm had independent carriers. Approximate with:
```
M1 Amount: 0%
M2 Amount: 0%
M3 Amount: 0%
Feedback: 0%
```

Then route different oscillators to filters for layering (not true parallel FM, but similar effect).

#### Algorithm 4 (Classic Electric Piano)

The famous DX7 E.Piano algorithm used a 1:14 ratio. Approximate with:
```
M1 Ratio: 1 (fundamental)
M1 Amount: 100%
M2 Ratio: 14 (inharmonic overtone)
M2 Amount: 70-90%
M3 Frequency: +36 (3 octaves up for brightness)
M3 Amount: 30%
Feedback: -15%

Envelopes:
- M1 Amount: Fast attack, medium decay
- M2 Amount: Fast attack, fast decay
- M3 Amount: Instant attack, fast decay to 0
```

#### Brass (Algorithm 5 style)

```
M1 Ratio: 1
M1 Amount: 60%
M2 Ratio: 2.5 (non-integer for complexity)
M2 Amount: 40%
M3 Frequency: +19 (creates formant)
M3 Amount: 50%
Feedback: 25%

LFO → M1 Amount: Slow sine for vibrato
Envelope → Feedback: Increases with velocity for brighter attack
```

### Sound Design Examples with FM3

#### Vocal Formant Synthesis

Using M3's absolute frequency for formant:

```
M1 Ratio: 1
M1 Amount: 75%
M2 Ratio: 2
M2 Amount: 40%
M3 Frequency: +28 (creates formant around 1000 Hz)
M3 Amount: 60%
Feedback: 5%

Envelope → M3 Amount: Creates formant sweep
LFO → M3 Frequency: ±2 semitones for vocal character
```

Different M3 frequency values create different vowel sounds:
- +24 to +30: "ah" formant
- +30 to +36: "ee" formant
- +18 to +24: "oh" formant

#### Inharmonic Pad

Combining harmonic and inharmonic elements:

```
M1 Ratio: 1 (harmonic foundation)
M1 Amount: 50%
M2 Ratio: 3.14159 (π ratio, inharmonic)
M2 Amount: 70%
M3 Frequency: -7 (low frequency movement)
M3 Amount: 20%
Feedback: 15%

Slow attack on all amounts
LFO → M2 Ratio: ±0.1, very slow, for evolving timbre
```

#### Percussive Bell

Exploiting all three modulators for complex attack:

```
M1 Ratio: 3.5 (inharmonic)
M1 Amount: 100%
M2 Ratio: 7 (inharmonic)
M2 Amount: 80%
M3 Frequency: +48 (high ringing component)
M3 Amount: 60%
Feedback: -30% (adds metallic edge)

All envelopes: Instant attack, medium-slow decay
Pitch Envelope: +2400 cents instant decay (2 octave drop)
Filter: High-pass at 200 Hz to remove low mud
```

## Sine Oscillator - Waveshaping and Feedback FM

### Beyond Pure Sine

While named "Sine," this oscillator is far more than a simple tone generator. It includes:

- **32 waveshaping modes**: Transform sine/cosine into complex waveforms
- **FM feedback**: Self-modulation for FM-like timbres
- **Unison**: Up to 16 detuned sine voices
- **Quadrant-based processing**: Waveshaping based on sine wave phase

**Why this matters**: The Sine oscillator can do FM-style synthesis through feedback and waveshaping, while being more CPU-efficient than full FM operators.

### Parameters

#### Shape (0-31, 32 modes)

Selects one of 32 **waveshaping functions** applied to the sine wave:

**Mode 0: Pure Sine**
```cpp
// SineOscillator.cpp, lines 218-222:
template <>
inline SIMD_M128 valueFromSinAndCosForMode<0>(SIMD_M128 svaluesse, SIMD_M128 cvaluesse, int maxc)
{
    return svaluesse;  // Just return sine, no modification
}
```

**Mode 1: Triangle-ish (Cosine Double Frequency)**
```cpp
// Lines 225-243:
const auto m2 = SIMD_MM(set1_ps)(2);
const auto m1 = SIMD_MM(set1_ps)(1);

auto c2x = SIMD_MM(sub_ps)(m1, SIMD_MM(mul_ps)(m2, SIMD_MM(mul_ps)(svaluesse, svaluesse)));
// c2x = 1 - 2*sin²(x) = cos(2x)

auto uh = SIMD_MM(mul_ps)(mp5, SIMD_MM(sub_ps)(m1, c2x));  // Upper half
auto lh = SIMD_MM(mul_ps)(mp5, SIMD_MM(sub_ps)(c2x, m1));  // Lower half

auto res = SIMD_MM(add_ps)(SIMD_MM(and_ps)(h1, uh), SIMD_MM(andnot_ps)(h1, lh));
```

Uses **quadrant masking** to create different shapes in positive vs. negative sine regions.

**Mode 2: First Half Sine**
```cpp
// Lines 246-251:
const auto mz = SIMD_MM(setzero_ps)();
return SIMD_MM(and_ps)(svaluesse, SIMD_MM(cmpge_ps)(svaluesse, mz));
```

Zeros out negative half - creates pulse-like waveform.

**Other notable modes**:
- **Mode 4**: Sine 2x in first half (double frequency in first half cycle)
- **Mode 9**: Zero quadrants 1 and 3 (alternating)
- **Mode 12**: Sign flip sine 2x based on cosine
- **Mode 25**: Sine 2x divided by quadrant number
- **Mode 28**: Cosine-based quadrant variations

#### The Quadrant Calculation

Many modes use **quadrant detection**:

```cpp
// SineOscillator.cpp, lines 149-161:
inline int calcquadrant(float sinx, float cosx)
{
    int sxl0 = (sinx <= 0);
    int cxl0 = (cosx <= 0);

    // quadrant numbering:
    // 1: sin > 0, cos > 0 (0 to π/2)
    // 2: sin > 0, cos < 0 (π/2 to π)
    // 3: sin < 0, cos < 0 (π to 3π/2)
    // 4: sin < 0, cos > 0 (3π/2 to 2π)
    int quadrant = 3 * sxl0 + cxl0 - 2 * sxl0 * cxl0 + 1;
    return quadrant;
}
```

**SSE version** for 4-way parallel processing:

```cpp
// Lines 177-194:
inline SIMD_M128 calcquadrantSSE(SIMD_M128 sinx, SIMD_M128 cosx)
{
    const auto mz = SIMD_MM(setzero_ps)();
    const auto m1 = SIMD_MM(set1_ps)(1), m2 = SIMD_MM(set1_ps)(2), m3 = SIMD_MM(set1_ps)(3);
    auto slt = SIMD_MM(and_ps)(SIMD_MM(cmple_ps)(sinx, mz), m1);
    auto clt = SIMD_MM(and_ps)(SIMD_MM(cmple_ps)(cosx, mz), m1);

    auto thsx = SIMD_MM(mul_ps)(m3, slt);
    auto twsc = SIMD_MM(mul_ps)(m2, SIMD_MM(mul_ps)(slt, clt));
    auto r = SIMD_MM(add_ps)(SIMD_MM(add_ps)(thsx, clt), SIMD_MM(sub_ps)(m1, twsc));
    return r;
}
```

#### Feedback (-100% to +100%)

Self-modulation of the sine oscillator:

```cpp
// SineOscillator.cpp, lines 760-776:
auto fbv = SIMD_MM(set1_ps)(std::fabs(FB.v));
auto fbnegmask = SIMD_MM(cmplt_ps)(SIMD_MM(set1_ps)(FB.v), SIMD_MM(setzero_ps)());

auto lv = SIMD_MM(add_ps)(SIMD_MM(mul_ps)(lv0, fb0weight), SIMD_MM(mul_ps)(lv1, fb1weight));
auto fba = SIMD_MM(mul_ps)(
    SIMD_MM(add_ps)(SIMD_MM(and_ps)(fbnegmask, SIMD_MM(mul_ps)(lv, lv)),
                    SIMD_MM(andnot_ps)(fbnegmask, lv)),
    fbv);
auto x = SIMD_MM(add_ps)(SIMD_MM(add_ps)(ph, fba), fmpds);
```

**Two feedback modes** (deform_type):
- **Mode 0**: Uses only most recent output
- **Mode 1**: Averages last two outputs for smoother feedback

**Sign behavior**:
- **Positive**: Linear feedback (output * depth)
- **Negative**: Squared feedback (output² * depth), asymmetric distortion

**Musical effect**: Similar to FM2/FM3 feedback, but applied to shaped waveforms rather than pure sine.

#### Unison Voices (1-16)

Unlike FM2/FM3 (which don't support unison), Sine oscillator implements full unison:

```cpp
// SineOscillator.cpp, lines 85-105:
void SineOscillator::prepare_unison(int voices)
{
    auto us = Surge::Oscillator::UnisonSetup<float>(voices);

    out_attenuation_inv = us.attenuation_inv();
    out_attenuation = 1.0f / out_attenuation_inv;

    detune_bias = us.detuneBias();
    detune_offset = us.detuneOffset();

    for (int v = 0; v < voices; ++v)
    {
        us.panLaw(v, panL[v], panR[v]);
    }
}
```

Each voice gets:
- Independent detuning
- Independent drift LFO
- Stereo panning

#### Unison Detune (0-100 cents, extended to 1200)

Controls spread of unison voices:

```cpp
// Lines 673-691:
if (n_unison > 1)
{
    if (oscdata->p[sine_unison_detune].absolute)
    {
        // Absolute mode: Hz-based detuning
        detune += oscdata->p[sine_unison_detune].get_extended(
                      localcopy[oscdata->p[sine_unison_detune].param_id_in_scene].f) *
                  storage->note_to_pitch_inv_ignoring_tuning(std::min(148.f, pitch)) * 16 /
                  0.9443 * (detune_bias * float(l) + detune_offset);
    }
    else
    {
        // Relative mode: cent-based detuning
        detune += oscdata->p[sine_unison_detune].get_extended(localcopy[id_detune].f) *
                  (detune_bias * float(l) + detune_offset);
    }
}
```

#### Low Cut & High Cut

Built-in filters for each oscillator:

```cpp
// SineOscillator.cpp, lines 829-850:
void SineOscillator::applyFilter()
{
    if (!oscdata->p[sine_lowcut].deactivated)
    {
        auto par = &(oscdata->p[sine_lowcut]);
        auto pv = limit_range(localcopy[par->param_id_in_scene].f, par->val_min.f, par->val_max.f);
        hp.coeff_HP(hp.calc_omega(pv / 12.0) / OSC_OVERSAMPLING, 0.707);
    }

    if (!oscdata->p[sine_highcut].deactivated)
    {
        auto par = &(oscdata->p[sine_highcut]);
        auto pv = limit_range(localcopy[par->param_id_in_scene].f, par->val_min.f, par->val_max.f);
        lp.coeff_LP2B(lp.calc_omega(pv / 12.0) / OSC_OVERSAMPLING, 0.707);
    }

    for (int k = 0; k < BLOCK_SIZE_OS; k += BLOCK_SIZE)
    {
        if (!oscdata->p[sine_lowcut].deactivated)
            hp.process_block(&(output[k]), &(outputR[k]));
        if (!oscdata->p[sine_highcut].deactivated)
            lp.process_block(&(output[k]), &(outputR[k]));
    }
}
```

Both are **2-pole filters** (12 dB/octave) with 0.707 Q (Butterworth response).

### SSE Optimization Strategy

The Sine oscillator uses aggressive SIMD optimization:

```cpp
// From the extensive comment block, lines 31-78:
/*
 * Sine Oscillator Optimization Strategy
 *
 * With Surge 1.9, we undertook a bunch of work to optimize the sine oscillator
 * runtime at high unison count with odd shapes. Basically at high unison we were
 * doing large numbers of loops, branches and so forth...
 *
 * There's two core fixes.
 *
 * First... the inner unison loop of ::process is now SSEified over unison.
 * This means that we use parallel approximations of sine, we use parallel clamps
 * and feedback application, the whole nine yards.
 *
 * But that's not all. The other key trick is that the shape modes added a massive
 * amount of switching to the execution path. So we eliminated that completely.
 * We did that with two tricks:
 *
 * 1: Mode is a template applied at block level so there's no ifs inside the block
 * 2: When possible, shape generation is coded as an SSE instruction.
 */
```

**Template specialization** eliminates runtime branching:

```cpp
// Lines 972-1013:
#define DOCASE(x)                                                                  \
    case x:                                                                        \
        if (stereo)                                                                \
            if (FM)                                                                \
                process_block_internal<x, true, true>(pitch, drift, fmdepth);      \
            else                                                                   \
                process_block_internal<x, true, false>(pitch, drift, fmdepth);     \
        else if (FM)                                                               \
            process_block_internal<x, false, true>(pitch, drift, fmdepth);         \
        else                                                                       \
            process_block_internal<x, false, false>(pitch, drift, fmdepth);        \
        break;

switch (mode)
{
    DOCASE(0)
    DOCASE(1)
    DOCASE(2)
    // ... all 32 modes
}
```

**Processing in blocks of 4** (SSE register width):

```cpp
// Lines 763-801:
for (int u = 0; u < n_unison; u += 4)  // Process 4 voices at once
{
    float fph alignas(16)[4] = {(float)phase[u], (float)phase[u + 1],
                                (float)phase[u + 2], (float)phase[u + 3]};
    auto ph = SIMD_MM(load_ps)(&fph[0]);
    auto lv0 = SIMD_MM(load_ps)(&lastvalue[0][u]);
    auto lv1 = SIMD_MM(load_ps)(&lastvalue[1][u]);

    // ... feedback calculation

    auto sxl = sst::basic_blocks::dsp::fastsinSSE(x);  // 4 sines at once
    auto cxl = sst::basic_blocks::dsp::fastcosSSE(x);  // 4 cosines at once

    auto out_local = valueFromSinAndCosForMode<mode>(sxl, cxl, std::min(n_unison - u, 4));

    // ... pan and output
}
```

**Result**: The Sine oscillator can handle 16 unison voices with complex shaping at minimal CPU cost compared to the non-optimized version.

### Sound Design with Sine Oscillator

#### Thick Detuned Pad

Using unison with waveshaping:

```
Shape: 1 (triangle-ish)
Feedback: 0%
Unison Voices: 7
Unison Detune: 15 cents
Low Cut: Off
High Cut: 8000 Hz

Long attack/release envelopes
Chorus effect after oscillator
Reverb
```

#### FM-Style Lead

Using feedback for FM-like timbres:

```
Shape: 0 (pure sine)
Feedback: 60%
Unison Voices: 3
Unison Detune: 8 cents

Envelope → Feedback: Medium attack, sustain at 40%
Filter: Low-pass, envelope modulation
```

The feedback creates harmonic content similar to FM synthesis but with simpler control.

#### Quadrant-Based Percussion

Exploiting quadrant shapes:

```
Shape: 13 (flip sign of sin2x, zero quadrants)
Feedback: -40% (squared feedback for asymmetry)
Unison Voices: 1

Pitch Envelope: +3600 cents, instant decay
Amplitude Envelope: Instant attack, fast decay
High Cut: 6000 Hz
```

Creates percussive, pitched sounds with unusual timbral character.

## Implementation Deep Dive

### Phase Modulation Math

All three oscillators use the same core algorithm:

```
y(t) = sin(ωt + m(t))
```

Where `m(t)` is the **modulation signal**. The derivative reveals why this works:

```
dy/dt = cos(ωt + m(t)) * (ω + dm/dt)
```

The **instantaneous frequency** is `ω + dm/dt`. So modulating phase is equivalent to modulating frequency (with integration).

**In Surge's implementation**:

```cpp
// Common to all FM oscillators:
output[k] = phase + modulation_sum;
output[k] = sin(output[k]);
```

The `modulation_sum` is the accumulated phase modulation from all sources.

### Feedback Loop Stability

Feedback creates a **recursive equation**:

```
y[n] = sin(phase[n] + feedback * y[n-1])
```

This can be unstable for large feedback amounts. Surge limits this with:

1. **Absolute value**: `abs(fb_val)` prevents negative scaling
2. **Squared scaling**: When fb_val < 0, uses `y[n-1]²`, naturally limiting amplitude
3. **Averaging**: Mode 1 averages two samples, reducing high-frequency instability

```cpp
double avg = mode == 1 ? ((oldout1 + oldout2) / 2.0) : oldout1;
double fb_amt = (fb_val < 0) ? avg * avg * FeedbackDepth.v : avg * FeedbackDepth.v;
```

### Anti-Aliasing Strategies

FM synthesis is **highly prone to aliasing** because modulation creates sidebands that can exceed Nyquist frequency.

**Surge's approach**:

1. **Oversampling**: All oscillators run at `BLOCK_SIZE_OS` (2x sample rate)

```cpp
// Common pattern:
for (int k = 0; k < BLOCK_SIZE_OS; k++)  // OS = OverSampled
```

2. **Rate limiting**: Modulator rates capped at Nyquist:

```cpp
RM1.set_rate(min(M_PI, pitch_to_omega(...)));  // M_PI = Nyquist in radians
```

3. **Sinc interpolation**: Quadrature oscillators use band-limited sine generation

4. **Downsampling**: Output is filtered and decimated back to base sample rate by the oscillator infrastructure

**Why oversampling works**: If a modulator creates sidebands up to 30 kHz at 48 kHz sample rate (already above Nyquist), running at 96 kHz keeps them below the new Nyquist (48 kHz), and downsampling with a low-pass filter removes them.

### Lag Processors and Zipper Noise

All modulation depths use **lag processors** to smooth parameter changes:

```cpp
// Definition: vembertech/lipol.h
template <class T> class lag
{
    T v;  // Current value
    T target;
    T coeff;  // Slew rate coefficient

public:
    void newValue(T nv) { target = nv; }
    void process() { v = v * coeff + target * (1.0 - coeff); }
};
```

**Effect**: First-order low-pass filter on parameter changes.

**Why needed**: Direct parameter jumps create audible clicks ("zipper noise"). Smoothing over ~1ms makes changes inaudible while maintaining responsiveness.

**Example**:

```cpp
RelModDepth1.newValue(calcmd(d1));  // Set new target
// ... later in the loop:
RelModDepth1.process();  // Smooth toward target
```

### Quadrature Oscillators

FM2 and FM3 use `SurgeQuadrOsc` from `sst::basic-blocks::dsp`:

```cpp
using quadr_osc = sst::basic_blocks::dsp::SurgeQuadrOsc<float>;
quadr_osc RM1, RM2;
```

**How it works**: Maintains a **complex phasor** that rotates in the complex plane:

```
z[n] = z[n-1] * e^(jω)
     = z[n-1] * (cos(ω) + j*sin(ω))
```

**Real part**: cos(ωn)
**Imaginary part**: sin(ωn)

**Advantages**:
- Both sin and cos from single oscillator
- No table lookup (pure math)
- Numerically stable with periodic normalization
- Accurate for synthesis use

**Usage in FM**:

```cpp
RM1.process();
float modulation = RelModDepth1.v * RM1.r;  // Use real part (cosine)
```

The cosine is used because it's 90° ahead of sine, which is equivalent to differentiating the sine (converting phase modulation to frequency modulation).

## Sound Design - Complete Patch Examples

### Electric Piano (FM3)

Classic DX-style electric piano:

**Oscillator - FM3**:
```
M1 Ratio: 1 (fundamental)
M1 Amount: 100%
M2 Ratio: 14 (bell-like overtone)
M2 Amount: Start 90%, Decay to 20%
M3 Frequency: +24 (high shimmer)
M3 Amount: Start 70%, Decay to 0%
Feedback: -18%
```

**Envelopes**:
```
Amp Envelope: A=0, D=2.5s, S=0, R=0.5s
M2 Amount Envelope: A=0, D=1.2s, S=0.2, R=0.1s
M3 Amount Envelope: A=0, D=0.4s, S=0, R=0.1s
```

**Effects**:
```
Chorus: Rate 0.3 Hz, Depth 25%
Reverb: Room size, short decay
EQ: Slight low cut at 100 Hz
```

**Playing technique**: Responds to velocity - map velocity to M2/M3 amounts for dynamic brightness.

### Bass (FM2)

Modern, aggressive FM bass:

**Oscillator - FM2**:
```
M1 Ratio: 1
M1 Amount: 90%
M2 Ratio: 2
M2 Amount: 75%
M1/2 Offset: 1.2 Hz (thick detuning)
Feedback: 50%
```

**Filter**:
```
Type: Low-pass, 24dB
Cutoff: 1800 Hz
Resonance: 35%
Envelope → Cutoff: A=0, D=1.0s, S=0.3, R=0.1s, Amount=40%
```

**Modulation**:
```
LFO 1 (Sine, 0.1 Hz) → Feedback, ±15%
LFO 2 (Sine, 4 Hz) → M1 Amount, ±10%
```

**Effects**:
```
Distortion: Soft clip, drive 30%
Compressor: Ratio 4:1, fast attack
```

**Notes**: Works best in lower octaves. The offset creates subtle motion even on sustained notes.

### Brass (FM3)

Realistic brass section:

**Oscillator - FM3**:
```
M1 Ratio: 1
M1 Amount: 70%
M2 Ratio: 2.5 (slightly inharmonic for realism)
M2 Amount: 55%
M3 Frequency: +21 (formant peak at ~1.5kHz)
M3 Amount: 65%
Feedback: 28%
```

**Envelopes**:
```
Amp: A=0.05s, D=0.3s, S=0.7, R=0.4s
M1 Amount: A=0.1s, D=0.5s, S=0.6, R=0.2s
M3 Amount: A=0.05s, D=0.2s, S=0.8, R=0.2s
Pitch: A=0, D=0.1s, S=0, Amount=-200 cents (pitch dip)
```

**Modulation**:
```
LFO (Sine, 5 Hz, delayed 0.5s) → Pitch, ±8 cents (vibrato)
Aftertouch → M3 Amount, +30%
```

**Filter**:
```
Type: Band-pass
Center: 2400 Hz
Resonance: 25%
```

**Effects**:
```
Chorus: Subtle (rate 0.4 Hz, depth 15%)
Reverb: Hall, medium decay
```

**Performance tips**: Use mod wheel to control M3 amount for expressiveness. Aftertouch adds bite.

### Bell/Mallet (FM2)

Tuned percussion, bell-like:

**Oscillator - FM2**:
```
M1 Ratio: 4 (inharmonic)
M1 Amount: Start 100%, long decay
M2 Ratio: 9 (highly inharmonic)
M2 Amount: Start 100%, medium decay
M1/2 Offset: 0 (pure ratios for clarity)
M1/2 Phase: 25% (affects attack timbre)
Feedback: 8%
```

**Envelopes**:
```
Amp: A=0, D=5s, S=0, R=2s (exponential decay)
M1 Amount: A=0, D=4s, S=0, R=1s
M2 Amount: A=0, D=2s, S=0, R=0.5s
Pitch: A=0, D=0.05s, S=0, Amount=+1200 cents (octave drop on attack)
```

**Filter**:
```
Type: High-pass
Cutoff: 150 Hz (remove low mud)
Resonance: 10%
```

**Effects**:
```
Reverb: Large hall, long decay
EQ: Boost at 3-5 kHz for shimmer
```

**Tuning**: Try different M1/M2 ratio combinations:
- 3:7 - Classic bell
- 4:11 - Gamelan-like
- 5:13 - Complex, almost atonal

### Pad (Sine with Unison)

Lush, evolving pad using waveshaping:

**Oscillator - Sine**:
```
Shape: 12 (flip sign of sin2x in quadrant 2 or 3)
Feedback: 35%
Unison Voices: 9
Unison Detune: 18 cents
Low Cut: Off
High Cut: 10000 Hz
```

**Envelopes**:
```
Amp: A=1.5s, D=1s, S=0.8, R=3s
Feedback: A=0.8s, D=2s, S=0.35, R=1s
```

**Modulation**:
```
LFO 1 (Triangle, 0.07 Hz) → Feedback, ±20%
LFO 2 (Sine, 0.13 Hz) → Shape, ±2 modes (slow shape morphing)
LFO 3 (Sine, 0.21 Hz) → High Cut, ±800 Hz
```

**Effects**:
```
Chorus: Depth 35%, Rate 0.25 Hz
Delay: Stereo, 1/4 note, 30% feedback, 20% mix
Reverb: Large hall, long decay, 40% mix
```

**Layer technique**: Stack two instances with different shapes (e.g., Shape 5 and Shape 18) for complex evolution.

### Lead (FM3 with Modulation)

Expressive, evolving lead:

**Oscillator - FM3**:
```
M1 Ratio: 1
M1 Amount: 75%
M2 Ratio: Absolute mode, at A440
M2 Amount: 60%
M3 Frequency: +12
M3 Amount: 50%
Feedback: 40%
```

**Envelopes**:
```
Amp: A=0.01s, D=0.3s, S=0.7, R=0.5s
Feedback: A=0.02s, D=0.8s, S=0.4, R=0.3s
```

**Modulation**:
```
LFO 1 (Sine, 5 Hz, delayed) → Pitch, ±12 cents (vibrato)
LFO 2 (Sine, 0.2 Hz) → M3 Frequency, ±4 semitones
Mod Wheel → M3 Amount, 0% to 80%
Velocity → Feedback, scaled 20-60%
```

**Filter**:
```
Type: Low-pass, 12dB
Cutoff: Start 3000 Hz
Resonance: 25%
Envelope → Cutoff, A=0.01s, D=1.2s, S=0.4, Amount=+4000 Hz
```

**Effects**:
```
Distortion: Soft, 15% drive
Delay: Ping-pong, 1/8 dotted, 35% feedback
Reverb: Medium room
```

**Why M2 in absolute mode**: Creates different harmonic relationships at different pitches - lower notes have higher C:M ratios (more harmonic), higher notes have lower ratios (more inharmonic). This mimics the behavior of real instruments.

## Performance Considerations

### CPU Cost Comparison

**Relative CPU usage** (normalized to Classic oscillator = 1.0):

| Oscillator | Base Cost | With Unison (16) | Notes |
|------------|-----------|------------------|-------|
| Classic | 1.0 | ~16.0 | BLIT convolution expensive |
| FM2 | 0.3 | N/A | No unison support |
| FM3 | 0.4 | N/A | Three operators |
| Sine (1 voice) | 0.2 | ~3.2 | SSE-optimized |
| Sine (16 voices) | ~3.2 | ~3.2 | Already unison |

**Why FM is cheaper**:
- Direct sine calculation vs. BLIT convolution
- No windowed sinc tables
- Simpler feedback than sync
- Lower oversampling requirements (though still 2x)

**Optimization tips**:
1. Use FM2 instead of FM3 if you only need 2 modulators
2. Use Sine oscillator for simple tones (pure sine is cheapest)
3. Limit Sine unison voices based on voice count
4. FM feedback is cheaper than using a third modulator

### Memory Footprint

Per oscillator instance:

**FM2**:
- Phase state: 24 bytes
- Quadrature oscillators (2): ~64 bytes
- Lag processors (5): ~80 bytes
- **Total**: ~170 bytes

**FM3**:
- Phase state: 24 bytes
- Quadrature oscillators (3): ~96 bytes
- Lag processors (6): ~96 bytes
- **Total**: ~220 bytes

**Sine** (16 unison):
- Phase state (16): 384 bytes
- Quadrature oscillators (16): ~1024 bytes
- Drift LFOs (16): ~256 bytes
- Pan/detune arrays: ~256 bytes
- **Total**: ~2000 bytes

**Implication**: Sine with high unison is memory-intensive compared to FM oscillators. For patches with many voices, consider FM for lower memory footprint.

### Aliasing Analysis

**FM synthesis aliasing risk**: Modulation index `I` determines highest sideband:

```
Highest frequency ≈ f_carrier + I * f_modulator
```

**Example risk scenario**:
- Carrier: 8000 Hz
- Modulator ratio: 8:1 → 64000 Hz
- Modulation index: 5
- Highest sideband: 8000 + 5*64000 = 328000 Hz

At 96 kHz oversampling (Nyquist = 48 kHz), this aliases back as:
```
328000 - 6*48000 = 40000 Hz (still above Nyquist)
40000 - 48000 = -8000 Hz (reflected) → 8000 Hz
```

**Surge's mitigation**:
1. Rate limiting to `M_PI` (Nyquist) prevents extreme modulator frequencies
2. 2x oversampling captures first generation of sidebands
3. Downsampling filter removes aliased components
4. User education: Extreme settings will alias, but this can be musical

**Practical guideline**: Keep `modulator_frequency * modulation_index` below `sample_rate / 4` for clean results. Higher values create deliberate aliasing artifacts (which can be desirable for aggressive sounds).

## Comparison to Hardware FM

### Yamaha DX7 Differences

**DX7 characteristics**:
- 6 operators (vs. Surge's 2-3)
- 32 algorithms (fixed routings)
- Discrete envelope generators per operator
- 8-bit sine table (quantization distortion)
- Pitch envelope generator
- 4-operator feedback possible

**Surge advantages**:
- Continuous parameter modulation (vs. stepped)
- Floating-point precision (vs. 8-bit)
- Flexible modulation routing
- Integration with filters and effects
- Extended ranges (negative ratios, absolute frequencies)

**Approximating DX7 in Surge**:
1. Use FM3 for 3-operator patches (many DX algorithms use 3-4 operators)
2. Envelope → modulation amounts for operator level control
3. Pitch envelope (Scene pitch modulation)
4. Layer multiple FM oscillators for 4+ operator algorithms
5. Add slight quantization/bitcrush for vintage character

### Buchla 259 Complex Waveform Generator

The Buchla 259 pioneered **waveshaping + FM** in modular synthesis.

**Buchla approach**:
- Sine core with waveshaping
- Through-zero FM
- Timbre modulation (wavefolder depth)

**Surge equivalent**: **Sine oscillator**
- Shape parameter = Buchla's wavefolding
- Feedback = Self-FM
- FM input = Through-zero capability (via Scene A→B)

**Difference**: Buchla's wavefolder is continuous, Surge's shapes are discrete modes. But similar sonic territory is achievable.

### Native Instruments FM8

**FM8 features**:
- 6 operators
- Complex algorithm matrix
- Per-operator filters
- Modulation matrix

**Surge approach**:
1. Layer multiple oscillators for 4+ operators
2. Use Scene mixing for parallel/series configurations
3. Filter per scene
4. Modulation matrix inherent to Surge

**When to use Surge over FM8**:
- Integration with Surge's filters and effects
- Performance advantages (lighter CPU)
- Open-source, customizable
- MPE support

**When FM8 is better**:
- Need 6+ operators
- Specific DX-style workflow
- Extensive FM-specific presets

## Advanced Techniques

### FM + Filter Combinations

**FM provides the harmonics, filters shape them**:

**High-pass after FM**:
- Removes fundamental, leaves upper harmonics
- Creates hollow, ethereal sounds
- Set cutoff to 2-3x fundamental frequency

**Band-pass after FM**:
- Isolates a specific sideband region
- Useful for formant synthesis (vocal sounds)
- Modulate cutoff to sweep through spectrum

**Comb filter after FM**:
- Reinforces specific harmonics
- Creates metallic, resonant tones
- Combine with feedback for extreme sounds

**Example patch - Formant Vowel**:
```
FM3:
  M1: Ratio 1, Amount 60%
  M2: Ratio 2.5, Amount 40%
  M3: Frequency +18, Amount 80%

Filter: Band-pass, Q=3.5, Cutoff 1200 Hz
LFO → Filter Cutoff: 800-2500 Hz (vowel morphing)
```

### FM + FM: Cascading Oscillators

Surge's **Scene A→B FM** allows using one oscillator's output to modulate another:

**Setup**:
1. Scene A: FM3 oscillator
2. Scene B: FM2 oscillator
3. Enable "Osc B FM from Scene A"
4. Set FM depth on Scene B

**Effect**: Scene A's complex FM spectrum modulates Scene B, creating **second-order FM** with extreme harmonic complexity.

**Warning**: Aliasing can be severe. Use cautiously and monitor spectrum.

**Example - Extreme Bell**:
```
Scene A (FM3):
  M1: Ratio 3, Amount 70%
  M2: Ratio 7, Amount 60%
  Feedback: 20%

Scene B (FM2):
  M1: Ratio 1, Amount 50%
  M2: Ratio 4, Amount 40%
  FM Depth from Scene A: 60%

Result: Incredibly complex inharmonic spectrum, bell/gong-like
```

### Modulating Ratios in Real-Time

While FM2 ratios are integers (can't be modulated continuously), FM3 supports **ratio modulation** in extended mode:

**Technique**:
1. Enable extended range on M1 or M2 ratio
2. Route LFO or envelope to the ratio parameter
3. Slow modulation: ±0.5 ratio creates subtle detuning sweeps
4. Fast modulation: ±5 ratio creates dramatic spectral shifts

**Musical use**:
- Slow sweep: Evolving pad textures
- Envelope-controlled: Attack brightness (high ratio) → warm sustain (low ratio)
- LFO-controlled: Rhythmic timbral changes

**Warning**: Large ratio changes can cause audible pitch shifts (sidebands moving). Use sparingly or as an effect.

### Feedback as a Modulation Destination

**Dynamic feedback control** is incredibly expressive:

**Velocity → Feedback**:
```
Soft notes: Feedback 10% (warm, simple)
Hard notes: Feedback 70% (bright, aggressive)
```

**Envelope → Feedback**:
```
Attack: Feedback 80% (bright transient)
Sustain: Feedback 30% (controlled timbre)
```

**LFO → Feedback** (slow):
```
Creates evolving harmonic motion
Rate 0.1-0.5 Hz for pad movement
```

**LFO → Feedback** (fast audio rate):
```
Becomes secondary modulation source
Similar to adding another operator
CPU-efficient compared to FM3
```

### Microtuning and FM

FM synthesis is **especially sensitive to tuning** due to C:M ratios.

**12-TET** (standard tuning):
- Integer ratios produce harmonic spectra
- Musical intervals reinforced

**Non-12-TET** (Scala, EDO):
- Integer ratios may no longer be harmonic
- Can create exotic, gamelan-like timbres
- Ratio 1:2 might not be an octave!

**Example - 19-EDO tuning**:
```
Load 19-tone equal temperament (.scl file)
FM2: M1 Ratio 1, M2 Ratio 3
Result: "Fifth" is now 11 steps of 19-EDO (694.7 cents vs. 700 cents)
         Creates slightly sharper, brighter character
```

**Workflow**:
1. Load Scala file (Surge menu → Tuning)
2. Design FM patch with integer ratios
3. Listen to how tuning affects harmonic relationships
4. Adjust ratios to taste (non-integer can restore harmony)

### FM as a Filter

**Extreme technique**: Use FM with zero carrier frequency as a **spectral processor**:

**Setup**:
1. Set carrier pitch very low (e.g., -48 semitones)
2. High modulation index
3. Feed audio from Scene A

**Effect**: Input signal is frequency-shifted by the modulator, creating:
- Ring modulation effects
- Frequency shifting (non-harmonic pitch shift)
- Spectral inversion
- Robot voices

**Example - Ring Mod**:
```
FM2:
  M1 Ratio: 1, Amount 100%
  M2 Ratio: 1, Amount 0%
  Feedback: 0%

Pitch: -48 semitones (very low carrier)
Scene A: Any audio source
FM from A: 100%

Result: Classic ring modulation at the modulator frequency
```

## Conclusion

FM synthesis in Surge XT provides a powerful palette of timbres, from realistic electric pianos and brass to aggressive basses and alien soundscapes. The three FM-capable oscillators offer different strengths:

- **FM2**: Fast, efficient, great for classic 2-operator sounds
- **FM3**: Flexible 3-operator configuration with absolute frequency control
- **Sine**: Waveshaping + feedback for FM-like textures with minimal CPU

**Key takeaways**:

1. **Modulation index** controls brightness - use envelopes for natural evolution
2. **C:M ratio** determines harmonic vs. inharmonic character
3. **Feedback** adds complexity and aggression
4. **Phase modulation** is mathematically simpler than true FM but sounds identical
5. **Aliasing** is inevitable at extreme settings - embrace or avoid
6. **Layering FM with filters** creates hybrid synthesis with the best of both worlds

Understanding the mathematics (Bessel functions, sidebands) helps predict results, but **experimentation is key**. FM synthesis rewards exploration - seemingly small parameter changes can yield dramatically different timbres.

**Next steps**:
- Experiment with the patch examples
- Study classic DX7 patches and approximate them
- Combine FM with Surge's extensive modulation system
- Layer FM oscillators with wavetable or classic oscillators
- Explore feedback as a primary sound design tool

## Further Reading

**Previous chapters**:
- Chapter 5: Oscillator Theory and Implementation
- Chapter 6: Classic Oscillators
- Chapter 7: Wavetable Oscillators

**Next chapters**:
- Chapter 9: Window and Modern Oscillators
- Chapter 10: Filter Theory
- Chapter 11: Filter Implementation

**Related chapters**:
- Chapter 18: Modulation Architecture
- Chapter 32: SIMD Optimization

**Source code locations**:
- `/home/user/surge/src/common/dsp/oscillators/FM2Oscillator.cpp`
- `/home/user/surge/src/common/dsp/oscillators/FM2Oscillator.h`
- `/home/user/surge/src/common/dsp/oscillators/FM3Oscillator.cpp`
- `/home/user/surge/src/common/dsp/oscillators/FM3Oscillator.h`
- `/home/user/surge/src/common/dsp/oscillators/SineOscillator.cpp`
- `/home/user/surge/src/common/dsp/oscillators/SineOscillator.h`
- `/home/user/surge/libs/sst/sst-basic-blocks/include/sst/basic-blocks/dsp/QuadratureOscillators.h`

**Academic references**:
- John M. Chowning, "The Synthesis of Complex Audio Spectra by Means of Frequency Modulation", *Journal of the Audio Engineering Society*, 1973
- John M. Chowning and David Bristow, *FM Theory & Applications: By Musicians for Musicians*, Yamaha, 1986
- Julius O. Smith III, "Spectral Audio Signal Processing", online book: https://ccrma.stanford.edu/~jos/sasp/
- Miller Puckette, *The Theory and Technique of Electronic Music*, World Scientific Publishing, 2007
- Dave Benson, *Music: A Mathematical Offering*, Cambridge University Press, 2007 (Chapter on Bessel functions)

**Historical resources**:
- Yamaha DX7 manuals and algorithm charts
- Chowning's original Stanford experiments (CCRMA archives)
- FM synthesis patents (expired, publicly available)

**Online resources**:
- Surge XT manual: https://surge-synthesizer.github.io/manual-xt/
- Surge Discord: https://discord.gg/spGANHw
- FM synthesis tutorials at Sound on Sound and other publications

---

*This document is part of the Surge XT Encyclopedic Guide, an in-depth technical reference covering all aspects of the Surge XT synthesizer architecture.*
