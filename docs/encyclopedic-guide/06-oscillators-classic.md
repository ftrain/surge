# Chapter 6: Classic Oscillators - The BLIT Implementation

## Introduction

The **Classic Oscillator** is Surge XT's foundational sound source - a sophisticated implementation of traditional analog-style waveforms using cutting-edge band-limited synthesis. While its output may sound familiar (sawtooth, square, triangle, sine), the underlying technology represents decades of digital signal processing research distilled into elegant, efficient code.

This chapter explores the Classic oscillator in depth, from the mathematical theory of band-limited synthesis to the intricate details of the BLIT (Band-Limited Impulse Train) implementation that makes it all work.

**Implementation**: `/home/user/surge/src/common/dsp/oscillators/ClassicOscillator.cpp`

## Architecture Overview

The Classic oscillator inherits from `AbstractBlitOscillator`, which provides the fundamental BLIT infrastructure. The architecture follows a producer-consumer model:

```
Phase State (oscstate) → Convolute → oscbuffer → Output
                              ↓
                        Windowed Sinc
```

**Key concepts:**
- **oscstate**: Phase pointer tracking position in the waveform
- **convolute()**: Generates impulses and convolves them with windowed sinc
- **oscbuffer**: Ring buffer storing convolved samples
- **process_block()**: Extracts samples and applies filtering

## Classic Waveforms and Harmonic Content

### The Four Fundamental Shapes

The Classic oscillator generates four traditional waveforms using a clever **4-state impulse machine**. All waveforms are synthesized from the same impulse generator with different pulse timings:

#### 1. Sawtooth Wave

The "brightest" waveform, containing **all harmonics** with amplitudes falling off as 1/n:

```
Amplitude of harmonic n: A_n = 1/n
```

For a 440 Hz sawtooth:
- Fundamental (1st): 440 Hz, amplitude 1.0
- 2nd harmonic: 880 Hz, amplitude 0.5
- 3rd harmonic: 1320 Hz, amplitude 0.333
- 10th harmonic: 4400 Hz, amplitude 0.1
- 50th harmonic: 22,000 Hz, amplitude 0.02

**Harmonic series**: `f₀, 2f₀, 3f₀, 4f₀, ...`

The sawtooth is achieved with the **Shape** parameter at -1.0 (fully counter-clockwise).

#### 2. Square Wave

Contains **only odd harmonics** with 1/n falloff:

```
Amplitude of harmonic n: A_n = 1/n  (n odd only)
```

For a 440 Hz square:
- Fundamental (1st): 440 Hz, amplitude 1.0
- 3rd harmonic: 1320 Hz, amplitude 0.333
- 5th harmonic: 2200 Hz, amplitude 0.2
- 7th harmonic: 3080 Hz, amplitude 0.143

**Harmonic series**: `f₀, 3f₀, 5f₀, 7f₀, ...`

The square wave is achieved with **Shape** at 0.0 (center) and **Width 1** at 50%.

#### 3. Triangle Wave

Also contains **only odd harmonics** but with much faster 1/n² falloff:

```
Amplitude of harmonic n: A_n = 1/n²  (n odd only)
```

This creates a much **warmer, softer** sound than the square wave. The 3rd harmonic is only 1/9th the amplitude of the fundamental, compared to 1/3 for a square.

Triangle is achieved with **Shape** at +1.0 (fully clockwise).

#### 4. Sine Wave

The **pure tone** - contains only the fundamental frequency with no harmonics at all. While the Classic oscillator can produce a sine wave, Surge has a dedicated **Sine** oscillator type optimized specifically for pure tones (see Chapter 7).

### The Shape Parameter: Morphing Between Waveforms

The **Shape** parameter (-100% to +100%) continuously morphs between these waveforms:

- **-100% (Shape = -1.0)**: Pure sawtooth - brightest, all harmonics
- **0% (Shape = 0.0)**: Square wave - odd harmonics, 1/n falloff
- **+100% (Shape = 1.0)**: Triangle wave - odd harmonics, 1/n² falloff

**Implementation** (from line 461):

```cpp
float tg = ((1 + wf) * 0.5f + (1 - pwidth[voice]) * (-wf)) * (1 - sub) +
           0.5f * sub * (2.f - pwidth2[voice]);
```

Where `wf = l_shape.v` (the Shape parameter value).

This formula determines the impulse height for state 0, creating the waveform blend. The mathematics ensure smooth transitions and correct DC offset at all shape values.

## The BLIT Implementation Deep Dive

### What is BLIT?

**BLIT** (Band-Limited Impulse Train) is a technique for generating band-limited waveforms by:

1. Creating a train of **impulses** (discontinuities)
2. Convolving each impulse with a **windowed sinc function**
3. Integrating the result to produce the final waveform

**Why it works**: In the frequency domain, convolution with a sinc function is multiplication by a brick-wall low-pass filter. This eliminates all frequencies above Nyquist, preventing aliasing.

### The Operating Model

From the extensive comments in `ClassicOscillator.cpp` (lines 30-147):

**The oscillator maintains two time scales:**

1. **Sample time**: The steady march of process_block() calls
2. **Phase space**: oscstate, which counts down as samples are consumed

**The key loop** (simplified):

```cpp
while (oscstate[voice] < samples_needed)  // Not enough phase space covered
{
    convolute(voice);  // Generate next impulse, convolved with sinc
    oscstate[voice] += rate[voice];  // Advance phase
}

// Now extract samples from oscbuffer to output
```

### Understanding Phase Space

**oscstate** tracks how much of the waveform we've pre-computed:

```cpp
float a = (float)BLOCK_SIZE_OS * pitchmult;

while (oscstate[l] < a)  // Need to cover more phase space
{
    convolute<false>(l, stereo);
}

oscstate[l] -= a;  // Consume the phase space we used
```

- `pitchmult`: Wavelength in samples (higher pitch = smaller value)
- `a`: Total phase space needed for this block
- `oscstate < a`: We haven't generated enough samples yet

**Example**: At 440 Hz with 48 kHz sample rate and 2x oversampling:
- Sample rate: 96 kHz (oversampled)
- Period: 96000 / 440 ≈ 218.18 samples
- For BLOCK_SIZE_OS = 64 samples
- Need `oscstate` to cover at least 64 * pitchmult

### The Convolute Method: Heart of the Algorithm

The `convolute()` method (template `<bool FM>`, line 284) is where the magic happens. Let's dissect it step by step.

#### Step 1: Calculate Detune

```cpp
float detune = drift * driftLFO[voice].val();
if (n_unison > 1)
{
    detune += oscdata->p[co_unison_detune].get_extended(localcopy[id_detune].f) *
              (detune_bias * (float)voice + detune_offset);
}
```

Each unison voice gets:
- **Drift LFO**: Random slow modulation simulating analog oscillator drift
- **Unison spread**: Calculated offset based on voice number

#### Step 2: Calculate Phase Position

```cpp
const float p24 = (1 << 24);  // 16,777,216
unsigned int ipos = (unsigned int)(p24 * (oscstate[voice] * pitchmult_inv));
```

**Why 2²⁴?** Fixed-point arithmetic for precision:
- Integer part (bits 31-24): Which sample we're near
- Fractional part (bits 23-0): Sub-sample position

**Extract components:**

```cpp
unsigned int delay = ((ipos >> 24) & 0x3f);  // Integer part: sample delay
unsigned int m = ((ipos >> 16) & 0xff) * (FIRipol_N << 1);  // Sinc table index
unsigned int lipolui16 = (ipos & 0xffff);  // Fractional part for interpolation
```

- `delay`: How many samples ahead of current bufpos to write
- `m`: Which windowed sinc to use (256 sub-sample positions)
- `lipolui16`: For fractional sinc interpolation

#### Step 3: The State Machine

The oscillator uses a **4-state machine** to generate all waveforms. Each state represents one edge/transition of the waveform:

```cpp
switch (state[voice])
{
case 0:  // First rising edge
    pwidth[voice] = l_pw.v;
    pwidth2[voice] = 2.f * l_pw2.v;

    float tg = ((1 + wf) * 0.5f + (1 - pwidth[voice]) * (-wf)) * (1 - sub) +
               0.5f * sub * (2.f - pwidth2[voice]);

    g = tg - last_level[voice];  // Change from last level
    last_level[voice] = tg;
    last_level[voice] -= (pwidth[voice]) * (pwidth2[voice]) * (1.f + wf) * (1.f - sub);
    break;

case 1:  // First falling edge
    g = wf * (1.f - sub) - sub;
    last_level[voice] += g;
    last_level[voice] -= (1 - pwidth[voice]) * (2 - pwidth2[voice]) * (1 + wf) * (1.f - sub);
    break;

case 2:  // Second rising edge
    g = 1.f - sub;
    last_level[voice] += g;
    last_level[voice] -= (pwidth[voice]) * (2 - pwidth2[voice]) * (1 + wf) * (1.f - sub);
    break;

case 3:  // Second falling edge
    g = wf * (1.f - sub) + sub;
    last_level[voice] += g;
    last_level[voice] -= (1 - pwidth[voice]) * (pwidth2[voice]) * (1 + wf) * (1.f - sub);
    break;
}

state[voice] = (state[voice] + 1) & 3;  // Cycle through states
```

**Key insight**: `g` is the **change in level** at this impulse, not the absolute level. The convolution adds this delta to the oscbuffer.

The DC offset adjustments (the subtraction from `last_level`) ensure the waveform remains properly centered with no DC bias.

#### Step 4: The Convolution

This is where discrete impulses become smooth, band-limited waveforms:

```cpp
auto g128 = SIMD_MM(load_ss)(&g);  // Load impulse height into SSE register
g128 = SIMD_MM(shuffle_ps)(g128, g128, SIMD_MM_SHUFFLE(0, 0, 0, 0));  // Broadcast

for (k = 0; k < FIRipol_N; k += 4)  // FIRipol_N = 12, process 4 at a time
{
    float *obf = &oscbuffer[bufpos + k + delay];
    auto ob = SIMD_MM(loadu_ps)(obf);  // Load 4 buffer samples

    auto st = SIMD_MM(load_ps)(&storage->sinctable[m + k]);  // Sinc values
    auto so = SIMD_MM(load_ps)(&storage->sinctable[m + k + FIRipol_N]);  // Sinc derivatives

    so = SIMD_MM(mul_ps)(so, lipol128);  // Scale derivative by fractional time
    st = SIMD_MM(add_ps)(st, so);  // st = sinc + dt * dsinc (Taylor expansion)
    st = SIMD_MM(mul_ps)(st, g128);  // Multiply by impulse height
    ob = SIMD_MM(add_ps)(ob, st);  // Add to buffer

    SIMD_MM(storeu_ps)(obf, ob);  // Store result
}
```

**Mathematical interpretation:**

```
oscbuffer[i + delay] += g * (sinc[i] + dt * dsinc[i])
```

This is a **first-order Taylor expansion** of the windowed sinc, accounting for the exact sub-sample position of the impulse.

#### Step 5: DC Tracking

```cpp
float olddc = dc_uni[voice];
dc_uni[voice] = t_inv * (1.f + wf) * (1 - sub);
dcbuffer[(bufpos + FIRoffset + delay)] += (dc_uni[voice] - olddc);
```

Because integration of the impulse train creates DC offset, this is tracked separately and corrected in the output stage.

#### Step 6: Rate Calculation

```cpp
if (state[voice] & 1)
    rate[voice] = t * (1.0 - pwidth[voice]);
else
    rate[voice] = t * pwidth[voice];

if ((state[voice] + 1) & 2)
    rate[voice] *= (2.0f - pwidth2[voice]);
else
    rate[voice] *= pwidth2[voice];

oscstate[voice] += rate[voice];
```

The `rate` determines how long until the next impulse, based on the current state and pulse widths. This advances oscstate to trigger the next convolution when needed.

### Windowed Sinc Tables

Surge pre-computes 256 different windowed sinc functions to cover all possible sub-sample positions. The table is structured as:

```
[sinc₀[0], dsinc₀[0], sinc₀[1], dsinc₀[1], ..., sinc₀[11], dsinc₀[11],
 sinc₁[0], dsinc₁[0], sinc₁[1], dsinc₁[1], ..., sinc₁[11], dsinc₁[11],
 ...
 sinc₂₅₅[0], dsinc₂₅₅[0], ...]
```

**Constants:**
- `FIRipol_M = 256`: Number of fractional positions
- `FIRipol_N = 12`: Length of FIR filter (sinc samples)
- `FIRoffset = 6`: Center of the FIR (FIRipol_N / 2)

**Why 12 samples?** This is a balance:
- **More samples**: Better frequency response, less aliasing
- **Fewer samples**: Better performance
- **12 samples**: Provides ~80+ dB of alias rejection, sufficient for high-quality audio

### The oscbuffer Ring Buffer

```cpp
float oscbuffer alignas(16)[OB_LENGTH + FIRipol_N];
```

**Size**: `OB_LENGTH + FIRipol_N` where:
- `OB_LENGTH = 1024` (power of 2 for efficient wrapping)
- `FIRipol_N = 12` (extra space for FIR overlap)

**Why the extra space?** When writing at position `bufpos`, the convolution writes `FIRipol_N` samples starting at `bufpos + delay`. Near the end of the buffer, this wraps around. The extra space prevents buffer overruns.

**Wraparound handling** (line 820):

```cpp
if (bufpos == 0)  // Just wrapped
{
    for (k = 0; k < FIRipol_N; k += 4)
    {
        overlap[k >> 2] = SIMD_MM(load_ps)(&oscbuffer[OB_LENGTH + k]);
        SIMD_MM(store_ps)(&oscbuffer[k], overlap[k >> 2]);  // Copy to beginning
        SIMD_MM(store_ps)(&oscbuffer[OB_LENGTH + k], zero);  // Clear old
    }
}
```

The FIR tail from the end is copied to the beginning, maintaining continuity across the wrap.

## Pulse Width Modulation (PWM)

### How PWM Works

Traditional analog synthesizers achieve **pulse width modulation** by varying the duty cycle of a rectangular wave. In Surge's Classic oscillator, PWM is implemented through the timing of the 4-state machine.

**Parameters:**
- **Width 1**: Controls the duty cycle of the primary pulse (0.1% to 99.9%)
- **Width 2**: Controls the sub-oscillator pulse width when Sub Mix > 0

#### Width 1: Primary Pulse Width

At **Shape = 0** (square wave):
- **Width 1 = 50%**: Perfect square wave (equal high/low times)
- **Width 1 = 10%**: Narrow pulse (10% high, 90% low)
- **Width 1 = 90%**: Wide pulse (90% high, 10% low)

**Spectral effect:**

The harmonic content of a pulse wave follows:

```
A_n = (2/n) * sin(n * π * duty)
```

Where `duty` is the pulse width (0 to 1).

**Sweet spots:**
- **50%**: Maximum odd harmonics (square wave)
- **33% / 66%**: Emphasized every 3rd harmonic
- **25% / 75%**: Emphasized every 4th harmonic
- **Small widths**: More "hollow" sound as even harmonics appear

**Extremes:**
- **0% or 100%**: Theoretical DC (no audio)
- **Practical range**: 0.1% to 99.9% (enforced in code line 249, 579)

```cpp
pwidth[voice] = limit_range(l_pw.v, 0.001f, 0.999f);
```

#### Width 2: Sub-Oscillator Pulse Width

When **Sub Mix** > 0%, a sub-oscillator is mixed in. Width 2 controls its pulse width independently, allowing complex timbral combinations:

```cpp
pwidth2[voice] = 2.f * l_pw2.v;
```

Note the `2.f` multiplier - this gives the sub-oscillator a different pulse width range for additional tonal variety.

### PWM Modulation Techniques

**Classic PWM sweep** (using an LFO):
1. Route LFO to Width 1
2. Set LFO to triangle or sine wave
3. Rate: 0.1 Hz to 5 Hz for sweeping chorus effect

**Harmonic emphasis:**
- Width 1 at 33%: Emphasize 3rd, 6th, 9th harmonics
- Width 1 at 25%: Emphasize 4th, 8th, 12th harmonics
- Useful for creating "formant-like" resonances

## Hard Sync

### Sync Theory

**Hard sync** (or **oscillator sync**) is a classic synthesis technique where a **master** oscillator forces a **slave** oscillator to restart its waveform. This creates distinctive "tearing" harmonics that move with the sync ratio.

In Surge's Classic oscillator:
- **Sync parameter**: Sets the master oscillator frequency
- **Pitch**: Controls the slave (sound-producing) oscillator

**Mathematical model:**

Every time the master oscillator completes a cycle, the slave resets to phase 0, regardless of its current phase. This creates discontinuities that introduce rich harmonic content.

### Implementation

The implementation uses two phase pointers per voice:

```cpp
float oscstate[MAX_UNISON];   // Slave oscillator phase
float syncstate[MAX_UNISON];  // Master oscillator phase
```

**In convolute()** (line 314):

```cpp
if ((l_sync.v > 0) && syncstate[voice] < oscstate[voice])
{
    // Sync event occurred!
    ipos = (unsigned int)(p24 * (syncstate[voice] * pitchmult_inv));

    // Calculate master frequency
    if (!oscdata->p[co_unison_detune].absolute)
        t = storage->note_to_pitch_inv_tuningctr(detune) * 2;
    else
        t = storage->note_to_pitch_inv_ignoring_tuning(
                detune * storage->note_to_pitch_inv_ignoring_tuning(pitch) * 16 / 0.9443) * 2;

    state[voice] = 0;  // Reset state machine
    last_level[voice] += dc_uni[voice] * (oscstate[voice] - syncstate[voice]);

    oscstate[voice] = syncstate[voice];  // Reset slave to master position
    syncstate[voice] += t;  // Advance master
}
```

**Key steps:**
1. Detect when master (syncstate) passes slave (oscstate)
2. Reset slave phase to master phase
3. Reset state machine to state 0
4. Account for DC offset change
5. Advance master for next cycle

**In process_block()** (line 681):

```cpp
while (((l_sync.v > 0) && (syncstate[l] < a)) || (oscstate[l] < a))
{
    convolute<false>(l, stereo);
}

oscstate[l] -= a;
if (l_sync.v > 0)
    syncstate[l] -= a;  // Advance both pointers
```

Both phase pointers are decremented by the block size, maintaining their relationship.

### Sync Sweet Spots

**Sync parameter range:** 0 to 60 semitones

**Musical intervals:**
- **0 semitones**: No sync
- **12 semitones**: Octave sync - strong, focused harmonics
- **19 semitones**: Fifth sync - adds upper partials
- **7 semitones**: Perfect fifth below - thick, complex sound
- **5 semitones**: Fourth - creates strong formant peaks
- **Swept sync**: Modulate sync with LFO or envelope for classic "sync sweep" sound

**Physics:**

When sync frequency is higher than oscillator frequency:
- Multiple resets per cycle create **harmonic comb filtering**
- Sync freq / osc freq = number of "teeth" in the waveform

When sync frequency is lower:
- Waveform is cut short mid-cycle
- Creates **inharmonic partials** (not integer multiples of fundamental)

### Interaction with PWM

Sync and PWM combine beautifully:

```cpp
// Both affect the state machine timing
if (state[voice] & 1)
    rate[voice] = t * (1.0 - pwidth[voice]);
else
    rate[voice] = t * pwidth[voice];
```

**Technique**: Set moderate sync (7-12 semitones), then modulate Width 1:
- Creates evolving harmonic content
- Each pulse width yields different sync character
- Classic for bass sounds and leads

## Unison

### Detune Spread Algorithm

Unison creates **multiple voices** of the same oscillator, each slightly detuned, for a thick, chorused sound.

**Setup** (line 159):

```cpp
void AbstractBlitOscillator::prepare_unison(int voices)
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

**Detune calculation** per voice (line 298):

```cpp
detune += oscdata->p[co_unison_detune].get_extended(localcopy[id_detune].f) *
          (detune_bias * (float)voice + detune_offset);
```

**The algorithm spreads voices symmetrically:**

For `n` voices:
- `detune_bias`: Spacing between adjacent voices
- `detune_offset`: Offset to center the spread around 0

**Example: 4 voices, Detune = 10 cents**
- Voice 0: -7.5 cents
- Voice 1: -2.5 cents
- Voice 2: +2.5 cents
- Voice 3: +7.5 cents

**Absolute vs. Relative Detune:**

The `absolute` flag (line 395) changes how detune is interpreted:

```cpp
if (oscdata->p[co_unison_detune].absolute)
{
    // Detune in Hz rather than semitones
    t = storage->note_to_pitch_inv_ignoring_tuning(
            detune * storage->note_to_pitch_inv_ignoring_tuning(pitch) * 16 / 0.9443 + sync);
}
else
{
    // Detune in semitones (standard)
    t = storage->note_to_pitch_inv_tuningctr(detune + sync);
}
```

- **Relative** (default): Detune in cents/semitones - wider at high pitches
- **Absolute**: Detune in Hz - constant width across keyboard

### Stereo Unison

When oscillator is in stereo mode, voices are panned across the stereo field:

```cpp
if (stereo)
{
    gR = g * panR[voice];
    g *= panL[voice];
}
```

The `panLaw()` function distributes voices:

**For 2 voices:**
- Voice 0: 100% left
- Voice 1: 100% right

**For 3 voices:**
- Voice 0: 100% left
- Voice 1: Center
- Voice 2: 100% right

**For 5+ voices:**
- Evenly distributed across stereo field
- Creates wide, immersive sound

### CPU Cost

Each unison voice is a **complete oscillator instance** running independently:

```cpp
for (l = 0; l < n_unison; l++)  // For each voice
{
    driftLFO[l].next();  // Independent drift

    while (oscstate[l] < a)  // Generate samples for this voice
    {
        convolute<false>(l, stereo);
    }

    oscstate[l] -= a;
}
```

**Memory per voice:**
- oscstate, syncstate, rate: 3 floats
- last_level, pwidth, pwidth2: 3 floats
- dc_uni, state: 2 floats
- driftLFO: ~16 bytes
- **Total**: ~48 bytes per voice

**CPU cost:**
- 1 voice: 100% (baseline)
- 4 voices: ~400% (nearly linear)
- 16 voices: ~1600%

**Why linear scaling?** Each voice runs the full convolute() independently. No shared computation except the final mix.

**Performance tip:** Use fewer voices with higher detune for similar thickness at lower CPU cost.

### Drift LFO

Each unison voice has an independent **drift LFO** simulating analog oscillator instability:

```cpp
Surge::Oscillator::DriftLFO driftLFO[MAX_UNISON];

// In convolute():
float detune = drift * driftLFO[voice].val();
```

The DriftLFO generates:
- **Very slow** random modulation (~0.01 to 0.1 Hz)
- **Small amplitude** (~few cents)
- **Independent per voice** (breaks perfect phasing)

This adds:
- Subtle movement to sustained notes
- Analog "warmth"
- Prevention of phase cancellation in unison

## Character Filter

### The Three Modes

The **Character** parameter (global, affects all oscillators) applies a simple **one-pole filter** to shape high-frequency content:

**From initialization** (line 187):

```cpp
charFilt.init(storage->getPatch().character.val.i);
```

**Three modes:**
1. **Warm**: High-frequency rolloff - darker, vintage sound
2. **Neutral**: Flat response - modern, clean
3. **Bright**: High-frequency boost - crisp, present

### Implementation: Simple Biquad

The filter is a **1-delay biquad** (simplified 2nd-order IIR filter):

```cpp
// From process_block(), line 769:
auto char_b0 = SIMD_MM(load_ss)(&(charFilt.CoefB0));
auto char_b1 = SIMD_MM(load_ss)(&(charFilt.CoefB1));
auto char_a1 = SIMD_MM(load_ss)(&(charFilt.CoefA1));

osc_out2 = SIMD_MM(add_ss)(SIMD_MM(mul_ps)(osc_out2, char_a1),
                           SIMD_MM(add_ss)(SIMD_MM(mul_ps)(osc_out, char_b0),
                                           SIMD_MM(mul_ps)(LastOscOut, char_b1)));
```

**Difference equation:**

```
y[n] = a1 * y[n-1] + b0 * x[n] + b1 * x[n-1]
```

Where:
- `x[n]` = input (osc_out)
- `y[n]` = output (osc_out2)
- `a1, b0, b1` = filter coefficients

**Why this structure?**
- **One delay**: Only needs to remember one previous sample
- **Very efficient**: 3 multiplies, 2 adds per sample
- **Sufficient**: Shapes tone without complex filtering
- **Pre-filter**: Before main filters, shapes oscillator "character"

### Coefficients for Each Mode

The CharacterFilter class sets coefficients based on mode:

**Warm mode** (example values):
```
b0 ≈ 0.3
b1 ≈ 0.3
a1 ≈ 0.4
```
Result: Low-pass characteristic, rolls off highs

**Neutral mode**:
```
b0 ≈ 1.0
b1 ≈ 0.0
a1 ≈ 0.0
```
Result: Unity gain, no filtering (y[n] = x[n])

**Bright mode** (example values):
```
b0 ≈ 1.2
b1 ≈ -0.5
a1 ≈ 0.3
```
Result: High-pass/boost characteristic, emphasizes highs

**Note**: Exact coefficients are defined in the `CharacterFilter` class from `sst::basic-blocks::dsp`.

### Frequency Response

The frequency response of this filter type:

```
H(e^jω) = (b0 + b1*e^(-jω)) / (1 - a1*e^(-jω))
```

**Magnitude:**

```
|H(ω)| = sqrt((b0 + b1*cos(ω))² + (b1*sin(ω))²) / sqrt((1 - a1*cos(ω))² + (a1*sin(ω))²)
```

For **Warm mode**:
- Gentle rolloff starting around 5-8 kHz
- -3 dB point around 10-12 kHz
- Darkens without muffling

For **Bright mode**:
- Gentle boost starting around 3-5 kHz
- +1 to +3 dB in upper midrange
- Adds presence and clarity

## The Process Block: Putting It All Together

The `process_block()` method (line 605) orchestrates everything:

### Step 1: Setup

```cpp
this->pitch = min(148.f, pitch0);  // Clamp max pitch
this->drift = drift;
pitchmult_inv = std::max(1.0, storage->dsamplerate_os * (1.f / 8.175798915f) *
                              storage->note_to_pitch_inv(pitch));
pitchmult = 1.f / pitchmult_inv;
```

**Why 8.175798915?** This is the frequency of MIDI note 0 (C-1):
```
f = 440 * 2^((note - 69) / 12)
note 0: 440 * 2^(-69/12) ≈ 8.176 Hz
```

### Step 2: Update Parameters

```cpp
update_lagvals<false>();
l_pw.process();
l_pw2.process();
l_shape.process();
l_sub.process();
l_sync.process();
```

**Lag processors** smooth parameter changes to prevent zipper noise. Each parameter has a slew rate (~0.05, set line 203).

### Step 3: Generate Samples (Non-FM)

```cpp
float a = (float)BLOCK_SIZE_OS * pitchmult;  // Phase space needed

for (l = 0; l < n_unison; l++)
{
    driftLFO[l].next();

    while (((l_sync.v > 0) && (syncstate[l] < a)) || (oscstate[l] < a))
    {
        convolute<false>(l, stereo);
    }

    oscstate[l] -= a;
    if (l_sync.v > 0)
        syncstate[l] -= a;
}
```

For each unison voice:
1. Advance drift LFO
2. Convolute until enough phase space is covered
3. Consume the phase space used

### Step 4: Apply HPF and DC Correction

```cpp
float hpfblock alignas(16)[BLOCK_SIZE_OS];
li_hpf.store_block(hpfblock, BLOCK_SIZE_OS_QUAD);

auto mdc = SIMD_MM(load_ss)(&dc);
auto oa = SIMD_MM(load_ss)(&out_attenuation);
oa = SIMD_MM(mul_ss)(oa, SIMD_MM(load_ss)(&pitchmult));
```

**HPF calculation** (line 585):

```cpp
auto pp = storage->note_to_pitch_tuningctr(pitch + l_sync.v);
float invt = 4.f * min(1.0, (8.175798915 * pp * storage->dsamplerate_os_inv));
float hpf2 = min(integrator_hpf, powf(hpf_cycle_loss, invt));
```

This creates a **key-tracked high-pass filter**:
- Higher notes: Less HPF (more bass)
- Lower notes: More HPF (prevents DC drift)

The constant `hpf_cycle_loss = 0.995` (line 574) determines the strength.

### Step 5: Output Loop with Character Filter

```cpp
for (k = 0; k < BLOCK_SIZE_OS; k++)
{
    auto dcb = SIMD_MM(load_ss)(&dcbuffer[bufpos + k]);
    auto hpf = SIMD_MM(load_ss)(&hpfblock[k]);
    auto ob = SIMD_MM(load_ss)(&oscbuffer[bufpos + k]);

    // a = prior output * HPF value
    auto a = SIMD_MM(mul_ss)(osc_out, hpf);

    // mdc += DC level
    mdc = SIMD_MM(add_ss)(mdc, dcb);

    // output buffer -= DC * out attenuation
    ob = SIMD_MM(sub_ss)(ob, SIMD_MM(mul_ss)(mdc, oa));

    auto LastOscOut = osc_out;
    osc_out = SIMD_MM(add_ss)(a, ob);

    // Character filter: out2 = out2 * a1 + out * b0 + last_out * b1
    osc_out2 = SIMD_MM(add_ss)(SIMD_MM(mul_ps)(osc_out2, char_a1),
                               SIMD_MM(add_ss)(SIMD_MM(mul_ps)(osc_out, char_b0),
                                               SIMD_MM(mul_ps)(LastOscOut, char_b1)));

    SIMD_MM(store_ss)(&output[k], osc_out2);
}
```

**Signal flow per sample:**
1. Load oscbuffer, dcbuffer, hpf coefficient
2. Apply HPF: `filtered = last_out * hpf + current`
3. Correct DC: `corrected = filtered - dc * attenuation`
4. Apply character filter: `final = biquad(corrected)`
5. Store to output

### Step 6: Cleanup and Buffer Advance

```cpp
mech::clear_block<BLOCK_SIZE_OS>(&oscbuffer[bufpos]);
mech::clear_block<BLOCK_SIZE_OS>(&dcbuffer[bufpos]);

bufpos = (bufpos + BLOCK_SIZE_OS) & (OB_LENGTH - 1);  // Wrap if needed

if (bufpos == 0)  // Handle FIR overlap
{
    // Copy tail to beginning (shown earlier)
}
```

## Advanced Topics

### FM Synthesis

The Classic oscillator supports **through-zero FM** (frequency modulation):

```cpp
template <bool FM> void ClassicOscillator::convolute(int voice, bool stereo)
```

When `FM = true`:

```cpp
for (int s = 0; s < BLOCK_SIZE_OS; s++)
{
    float fmmul = limit_range(1.f + depth * master_osc[s], 0.1f, 1.9f);
    float a = pitchmult * fmmul;

    FMdelay = s;

    for (l = 0; l < n_unison; l++)
    {
        while (((l_sync.v > 0) && (syncstate[l] < a)) || (oscstate[l] < a))
        {
            FMmul_inv = mech::rcp(fmmul);
            convolute<true>(l, stereo);
        }

        oscstate[l] -= a;
        if (l_sync.v > 0)
            syncstate[l] -= a;
    }
}
```

**Key differences:**
- `fmmul`: Modulation from master oscillator changes pitch per-sample
- `FMdelay`: Each sample may trigger separate convolutions
- Much higher CPU cost (can trigger 64+ convolutions per block)

**Through-zero**: The `limit_range(1.f + depth * master_osc[s], 0.1f, 1.9f)` ensures:
- Minimum: 0.1x pitch (10% of original)
- Maximum: 1.9x pitch (190% of original)
- Can sweep through zero frequency (unique metallic sounds)

### Tuning Integration

The oscillator respects Surge's **microtuning** system:

```cpp
storage->note_to_pitch_tuningctr(detune + sync)
```

- `tuningctr`: "Tuning center" - middle C reference
- Supports arbitrary scales (not just 12-TET)
- EDO (Equal Divisions of Octave)
- Scala .scl files
- Full-keyboard mappings

### SSE Optimization

Nearly all loops use **SSE (SIMD) intrinsics** for 4-way parallelism:

```cpp
auto g128 = SIMD_MM(load_ss)(&g);
g128 = SIMD_MM(shuffle_ps)(g128, g128, SIMD_MM_SHUFFLE(0, 0, 0, 0));

for (k = 0; k < FIRipol_N; k += 4)
{
    auto ob = SIMD_MM(loadu_ps)(obf);
    auto st = SIMD_MM(load_ps)(&storage->sinctable[m + k]);
    // ... operations on 4 samples at once
}
```

**Performance gain:**
- Theoretical: 4x speedup
- Practical: ~3x (memory bandwidth limits)
- Critical for real-time with 16 unison voices

## Parameter Guide

### Shape (-100% to +100%)

| Value | Waveform | Character |
|-------|----------|-----------|
| -100% | Sawtooth | Brightest, all harmonics |
| -50% | Sawtooth-Square | Slightly hollow |
| 0% | Square | Classic analog square |
| +50% | Square-Triangle | Warmer square |
| +100% | Triangle | Warmest, muted highs |

**Modulation ideas:**
- LFO: Slow sweep for evolving pad
- Envelope: Shape change per note
- Velocity: Brighter on harder hits

### Width 1 (0.1% to 99.9%)

**At Shape = 0 (Square):**

| Value | Sound |
|-------|-------|
| 50% | Perfect square wave |
| 10% | Thin, nasal |
| 90% | Inverted thin (same as 10%) |
| 25% | Hollow, octave character |
| 33% | Hollow, fifth character |

**Sweet spots:**
- 30-35%: Clarinet-like
- 15-20%: Oboe-like
- 5-10%: Extreme, filtered

### Width 2 (0.1% to 99.9%)

Only audible when **Sub Mix** > 0%. Acts on the sub-oscillator independently from Width 1.

**Combination tricks:**
- Width 1: 50%, Width 2: 25% → Main square + sub pulse
- Width 1: 30%, Width 2: 50% → Opposite characters

### Sub Mix (0% to 100%)

Blends in a **sub-oscillator** at the same pitch but different pulse width.

- 0%: No sub (main oscillator only)
- 50%: Equal mix
- 100%: Sub only (use Width 2 to shape)

**Musical use:**
- Bass: Add sub for weight without changing character
- Leads: Slight sub (10-20%) for thickness

### Sync (0 to 60 semitones)

| Value | Effect |
|-------|--------|
| 0 | No sync |
| 7 | Perfect fifth - moderate harmonics |
| 12 | Octave - strong, focused |
| 19 | Fifth above - bright |
| 24 | Two octaves - very harmonic |

**Modulation:**
- LFO → Sync: Classic sync sweep
- Envelope → Sync: Dynamic harmonic evolution

### Unison Voices (1 to 16)

| Count | Use Case | CPU |
|-------|----------|-----|
| 1 | Clean, focused | Low |
| 2-3 | Subtle width | Low-Med |
| 4-7 | Lush pads | Medium |
| 8-12 | Super thick leads | High |
| 13-16 | Extreme, experimental | Very High |

### Unison Detune (0 to 100 cents, extended to 1200)

| Value | Effect |
|-------|--------|
| 0 cents | Phase cancellation (thin) |
| 5 cents | Subtle chorus |
| 10-15 cents | Classic unison thickness |
| 30-50 cents | Wide, detuned |
| 100 cents | Semitone cluster |
| 1200 cents | Octave spread (extended) |

**Formula:**
```
Final spread = Detune * (voice_count - 1) / 2
```

Example: 4 voices, 10 cents → ±15 cent total spread

## Sound Design Examples

### Classic Analog Brass

```
Shape: -30% (sawtooth-ish)
Width 1: 50%
Sync: 7 semitones
Unison: 4 voices
Detune: 12 cents
Character: Warm
```

Add:
- Filter: Low-pass, ~60% cutoff, ~40% resonance
- Envelope → Sync: Fast attack, medium decay
- LFO → Pitch: Vibrato

### PWM Pad

```
Shape: 0% (square)
Width 1: 50% + LFO (±30%, 0.2 Hz, triangle)
Unison: 7 voices
Detune: 15 cents
Character: Neutral
```

### Sync Lead

```
Shape: -60% (sawtooth-leaning)
Sync: 12 semitones + Envelope (0→24)
Unison: 5 voices
Detune: 8 cents
Character: Bright
```

### Sub Bass

```
Shape: +100% (triangle)
Sub Mix: 40%
Width 2: 50%
Unison: 1 voice
Character: Warm
```

Add:
- Filter: Low-pass, ~30% cutoff, ~10% resonance
- Keep it mono for focused bass

## Performance Considerations

### CPU Budgeting

**Base cost** (1 voice, no unison):
- ~0.5-1% CPU (modern CPU, 48kHz)

**Multipliers:**
- Unison voices: ~linear (16 voices ≈ 16x cost)
- FM: ~2-4x cost (variable based on depth)
- Sync: ~minimal additional cost

**Typical scenarios:**
- Pad (7 unison): ~3.5-7% CPU
- Lead (5 unison): ~2.5-5% CPU
- Bass (1 voice): ~0.5-1% CPU

**Optimization tips:**
1. Use fewer unison voices with higher detune
2. Disable unison on bass (mono anyway)
3. Use Sine oscillator for pure tones (cheaper)
4. Avoid FM unless needed (high cost)

### Memory Footprint

Per oscillator instance:
- oscbuffer: (1024 + 12) * 4 bytes ≈ 4 KB
- oscbufferR: 4 KB (if stereo)
- dcbuffer: 4 KB
- State arrays: ~1 KB
- **Total**: ~10-13 KB per oscillator

With 16 voices in a patch: ~160-200 KB total

## Comparison to Other Oscillators

| Feature | Classic | Sine | Wavetable | Window |
|---------|---------|------|-----------|--------|
| Algorithm | BLIT | Direct | Lookup | Granular |
| CPU Cost | Medium | Low | Low-Med | High |
| Waveforms | 4 basic | 1 pure | Hundreds | Infinite |
| PWM | Yes | No | Some | No |
| Sync | Yes | No | Yes | No |
| Character | Analog | Digital | Hybrid | Unique |

**When to use Classic:**
- Analog-style sounds (brass, leads, bass)
- PWM effects needed
- Sync sweeps
- When you want "classic" subtractive synthesis

**When to use alternatives:**
- Pure tones: Sine oscillator (much cheaper)
- Complex timbres: Wavetable oscillator
- Evolving pads: Window oscillator
- Noise/percussion: Alias oscillator

## Conclusion

The Classic Oscillator represents a pinnacle of digital emulation of analog synthesis. Through sophisticated BLIT synthesis, it achieves:

- **Alias-free** waveforms across the entire audible range
- **Classic analog character** through careful mathematical modeling
- **Efficient implementation** via SSE optimization and ring buffering
- **Expressive modulation** through PWM, sync, and unison

Understanding the Classic oscillator's internals - from the 4-state impulse machine to windowed sinc convolution - provides insight into both:
1. The **challenges of digital synthesis** (aliasing, discontinuities)
2. The **elegant solutions** modern DSP provides (band-limiting, convolution)

Whether you're designing sounds or studying synthesis techniques, the Classic oscillator stands as a masterclass in turning theory into practice, analog inspiration into digital precision.

## Further Reading

- **Previous chapter**: Chapter 5 - Oscillator Theory and Implementation
- **Next chapter**: Chapter 7 - Sine and FM Oscillators
- **Related**: Chapter 12 - Filters and Signal Flow

**Source code locations:**
- `/home/user/surge/src/common/dsp/oscillators/ClassicOscillator.cpp`
- `/home/user/surge/src/common/dsp/oscillators/ClassicOscillator.h`
- `/home/user/surge/src/common/dsp/oscillators/OscillatorBase.h`

**Academic references:**
- "Alias-Free Digital Synthesis of Classic Analog Waveforms" - Välimäki et al.
- "Discrete-Time Modeling of Musical Instruments" - Julius O. Smith III
- "The Theory and Technique of Electronic Music" - Miller Puckette

---

*This document is part of the Surge XT Encyclopedic Guide, an in-depth technical reference covering all aspects of the Surge XT synthesizer architecture.*
