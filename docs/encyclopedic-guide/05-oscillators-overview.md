# Chapter 5: Oscillator Theory and Implementation

## The Foundation of Sound

Every synthesizer begins with oscillators - the fundamental sound generators that create the raw waveforms which are then sculpted by filters, shaped by envelopes, and enhanced by effects. Surge XT includes 13 different oscillator types, each representing different approaches to digital sound synthesis.

This chapter explores the theory behind digital oscillators, the challenges of band-limited synthesis, and the elegant architectural solutions Surge employs to create alias-free, high-quality audio.

## Digital Oscillator Fundamentals

### The Analog Ideal

In the analog world, an oscillator is a circuit that produces a periodic voltage signal. A simple 440 Hz sine wave oscillator produces a smoothly varying voltage that completes one full cycle 440 times per second. This continuous signal contains only a single frequency component - perfect and pure.

Other waveforms contain harmonic content:
- **Sawtooth**: Contains all harmonics (1/n amplitude)
- **Square**: Contains only odd harmonics (1/n amplitude)
- **Triangle**: Contains only odd harmonics (1/n² amplitude)
- **Pulse**: Harmonic content depends on pulse width

### The Digital Challenge: Aliasing

When we attempt to synthesize these waveforms digitally, we face a fundamental problem: **aliasing**.

**Nyquist-Shannon Theorem**: To accurately represent a signal digitally, you must sample it at twice its highest frequency component.

At 48kHz sample rate:
- **Nyquist frequency**: 24kHz (half the sample rate)
- Any frequency above 24kHz will **alias** - appear as a lower frequency artifact

**Example: Na&#239;ve Sawtooth Synthesis**

```cpp
// WRONG: This creates terrible aliasing
float naiveSawtooth(float phase)  // phase: 0.0 to 1.0
{
    return 2.0 * phase - 1.0;  // Ramp from -1 to +1
}
```

Why does this fail? A sawtooth wave contains all harmonics:
- Fundamental: 440 Hz
- 2nd harmonic: 880 Hz
- 3rd harmonic: 1320 Hz
- ...
- 54th harmonic: 23,760 Hz (just under Nyquist)
- 55th harmonic: 24,200 Hz ❌ **ALIASES to 23,800 Hz!**
- 56th harmonic: 24,640 Hz ❌ **ALIASES to 23,360 Hz!**

The result: harsh, metallic artifacts that sound like digital trash. This is why digital synthesis is hard.

## Band-Limited Synthesis Techniques

Surge employs several sophisticated techniques to eliminate aliasing:

### 1. BLIT: Band-Limited Impulse Train

The **BLIT** (Band-Limited Impulse Train) technique is the foundation of Surge's classic oscillators.

**Theory:**

Instead of directly generating a sawtooth, generate an impulse train where each impulse is band-limited. The integral of this impulse train is a band-limited sawtooth.

```
Impulse Train → Integration → Sawtooth Wave (band-limited)
Impulse Train → Integration → Differencing → Square Wave (band-limited)
```

**Key Insight:** Rather than outputting sample values directly, we model a DAC (Digital-to-Analog Converter) that reconstructs a continuous signal from discrete impulses.

**Mathematical Foundation:**

A perfect reconstruction filter is a **sinc function**:
```
sinc(x) = sin(πx) / (πx)
```

Properties:
- Value of 1 at x=0
- Zero crossings at all other integers
- Infinite support (extends forever)
- Perfect low-pass filter in frequency domain

Since we can't use infinite support, we use a **windowed sinc** - truncated and smoothed.

### 2. The Convolute Method

From the excellent comment in `ClassicOscillator.cpp` (lines 30-147):

```cpp
/*
** The AbstractBlitOperator handles a model where an oscillator generates
** an impulse buffer, but requires pitch tuning, drift, FM, and DAC emulation.
**
** Overall operating model:
** - The oscillator has a phase pointer (oscstate) which indicates where we are
** - At any given moment, we can generate the next chunk of samples which is done
**   in the 'convolute' method and store them in a buffer
** - We extract those samples from the buffer to the output
** - When we are out of state space, we need to reconvolve and fill our buffer
**
** The convolute method is the heart of the oscillator. It generates the signal
** by simulating a DAC for a voice.
**
** Rather than "output = zero-order samples", we do:
**     output += (change in underlyer) × (windowed sinc)
**
** The windowed sinc function depends on how far between samples you are.
** Surge pre-computes this as a table at 256 steps between 0 and 1 sample.
*/
```

**Pseudo-code for convolution:**

```cpp
while (remaining phase space < needed)
{
    // Figure out next impulse and change in impulse (call it g)
    float impulseChange = calculateNextImpulse();

    // Figure out fractional sample position
    float fracPos = getFractionalPosition();  // 0.0 to 1.0

    // Get windowed sinc coefficients
    int tableIndex = (int)(fracPos * 256.0);  // 0 to 255
    float *sincWindow = &sincTable[tableIndex * FIRipol_N];
    float *dsincWindow = &dsincTable[tableIndex * FIRipol_N];

    // Fill in the buffer with the windowed impulse
    for (int i = 0; i < FIRipol_N; i++)
    {
        oscbuffer[bufferPos + i] += impulseChange *
            (sincWindow[i] + fracPos * dsincWindow[i]);
    }

    // Advance phase
    oscstate += phaseIncrement;
}
```

This is the magic that makes Surge's classic oscillators sound clean across the entire frequency spectrum.

### 3. Oversampling

Surge employs 2x oversampling for oscillators:

```cpp
// From: src/common/globals.h
const int OSC_OVERSAMPLING = 2;
const int BLOCK_SIZE_OS = OSC_OVERSAMPLING * BLOCK_SIZE;  // 64 samples
```

**Why 2x?**

At 48kHz × 2 = 96kHz internal rate:
- Nyquist frequency: 48kHz (well above audible range)
- Harmonics up to 48kHz are preserved perfectly
- Gives "headroom" for non-linear operations

**Downsampling:**

After processing at 96kHz, Surge downsamples to the session rate (48kHz typically) using a high-quality decimation filter. This removes any aliasing that might have occurred at the higher rate.

### 4. Wavetable Interpolation

Wavetable oscillators use different techniques:

**Linear Interpolation** (fast, some aliasing):
```cpp
float lerp = frac;  // Fractional position in wavetable
float sample = table[pos] * (1.0 - lerp) + table[pos+1] * lerp;
```

**Hermite Interpolation** (better, Surge's choice):
```cpp
// 4-point Hermite interpolation
// Uses 4 samples: table[pos-1], table[pos], table[pos+1], table[pos+2]
// Provides smoother interpolation than linear
float hermite(float frac, float xm1, float x0, float x1, float x2)
{
    float c = (x1 - xm1) * 0.5f;
    float v = x0 - x1;
    float w = c + v;
    float a = w + v + (x2 - x0) * 0.5f;
    float b_neg = w + a;

    return ((((a * frac) - b_neg) * frac + c) * frac + x0);
}
```

## Surge's Oscillator Architecture

### The Base Class Hierarchy

```cpp
// From: src/common/dsp/oscillators/OscillatorBase.h:30

class alignas(16) Oscillator  // 16-byte aligned for SSE2
{
public:
    // Output buffers (must be first for alignment)
    float output alignas(16)[BLOCK_SIZE_OS];   // Left/mono output
    float outputR alignas(16)[BLOCK_SIZE_OS];  // Right output (stereo)

    // Constructor
    Oscillator(SurgeStorage *storage,
               OscillatorStorage *oscdata,
               pdata *localcopy);

    virtual ~Oscillator();

    // Initialization
    virtual void init(float pitch,
                      bool is_display = false,
                      bool nonzero_init_drift = true) {};

    virtual void init_ctrltypes() {};
    virtual void init_default_values() {};

    // Main processing method - THE HEART OF THE OSCILLATOR
    virtual void process_block(float pitch,
                               float drift = 0.f,
                               bool stereo = false,
                               bool FM = false,
                               float FMdepth = 0.f)
    {
        // Implemented by subclasses
    }

    // FM assignment (for FM from another oscillator)
    virtual void assign_fm(float *master_osc) { this->master_osc = master_osc; }

    // Gate control (for envelope triggering)
    virtual void setGate(bool g) { gate = g; }

    // Utility functions
    inline double pitch_to_omega(float x)  // Convert MIDI note to angular frequency
    {
        return (2.0 * M_PI * Tunings::MIDI_0_FREQ *
                storage->note_to_pitch(x) *
                storage->dsamplerate_os_inv);
    }

    inline double pitch_to_dphase(float x)  // Convert MIDI note to phase increment
    {
        return (double)(Tunings::MIDI_0_FREQ *
                       storage->note_to_pitch(x) *
                       storage->dsamplerate_os_inv);
    }

protected:
    SurgeStorage *storage;           // Global storage (wavetables, tuning, etc.)
    OscillatorStorage *oscdata;      // This oscillator's parameters
    pdata *localcopy;                // Local parameter copy
    float *__restrict master_osc;    // FM source (if using FM)
    float drift;                     // Analog drift simulation
    int ticker;                      // Internal counter
    bool gate = true;                // Gate state
};
```

**Key Design Decisions:**

1. **Alignment**: `alignas(16)` ensures SSE2 compatibility
2. **Output buffers first**: Guarantees they're at the class start (aligned)
3. **Pure virtual `process_block()`**: Each oscillator implements its own
4. **Pitch helpers**: Convert MIDI notes to frequencies respecting tuning

### The AbstractBlitOscillator

Many classic oscillators inherit from this:

```cpp
// From: src/common/dsp/oscillators/OscillatorBase.h:91

class AbstractBlitOscillator : public Oscillator
{
public:
    AbstractBlitOscillator(SurgeStorage *storage,
                          OscillatorStorage *oscdata,
                          pdata *localcopy);

protected:
    // Ring buffers for BLIT processing
    float oscbuffer alignas(16)[OB_LENGTH + FIRipol_N];
    float oscbufferR alignas(16)[OB_LENGTH + FIRipol_N];
    float dcbuffer alignas(16)[OB_LENGTH + FIRipol_N];

    // SSE2 accumulators
    SIMD_M128 osc_out, osc_out2, osc_outR, osc_out2R;

    // Constants for BLIT processing
    // OB_LENGTH = BLOCK_SIZE_OS << 1 = 128 (at default BLOCK_SIZE=32)
    // FIRipol_N = 12 (FIR filter length)
};
```

**Buffer sizing:**
- `OB_LENGTH` = 128 samples (at default settings)
- `+ FIRipol_N` = Additional 12 samples for FIR filter overlap
- Total: 140 samples per buffer

**Why these sizes?**
- Enough space to hold convolved output
- Room for FIR filter lookahead
- Power-of-2 friendly for efficient wraparound

## The 13 Oscillator Types

Surge XT includes 13 oscillator implementations:

### Category 1: Classic (BLIT-based)

1. **ClassicOscillator** - Traditional analog waveforms
   - Saw, Square, Triangle, Sine
   - Pulse width modulation
   - Hard sync

2. **SampleAndHoldOscillator** - S&H noise
   - Sample and hold of noise
   - Multiple correlation modes

### Category 2: Wavetable

3. **WavetableOscillator** - Classic wavetable synthesis
   - Wavetable scanning
   - Hermite interpolation
   - BLIT-based for clean reproduction

4. **ModernOscillator** - Enhanced wavetable
   - Modern wavetable features
   - Additional morphing capabilities

5. **WindowOscillator** - Window function-based
   - Uses window functions as waveforms
   - Continuous morphing option

### Category 3: FM Synthesis

6. **FM2Oscillator** - 2-operator FM
   - Carrier + Modulator
   - Ratio control
   - Feedback

7. **FM3Oscillator** - 3-operator FM
   - Three operator topology
   - Complex routing options

8. **SineOscillator** - Enhanced sine wave
   - Multiple sine-based synthesis modes
   - Waveshaping variations
   - Quadrant shaping
   - FM feedback

### Category 4: Physical Modeling

9. **StringOscillator** - Karplus-Strong string model
   - Plucked/struck string simulation
   - Stiffness and decay controls
   - Exciter model

### Category 5: Modern/Experimental

10. **TwistOscillator** - Eurorack-inspired
    - Based on Mutable Instruments concepts
    - Multiple synthesis engines in one

11. **AliasOscillator** - Intentional aliasing
    - Lo-fi, digital character
    - Bit crushing effects
    - Mask and bit control

12. **AudioInputOscillator** - External audio
    - Routes external input as oscillator source
    - Useful for vocoding, ring mod, etc.

## Oscillator Parameters: The 7-Parameter System

Each oscillator has 7 parameters:

```cpp
// From: src/common/SurgeStorage.h
const int n_osc_params = 7;
```

These parameters have **type-specific meanings**:

| Param | Classic | Wavetable | FM2 | String |
|-------|---------|-----------|-----|--------|
| 0 | Waveform | Table Select | Ratio | Excitation |
| 1 | Pulse Width | Skew | M1 Offset | Decay |
| 2 | Sync | Saturate | M2 Offset | Stiffness |
| 3 | Unison Detune | Formant | Feedback | ... |
| 4 | Unison Voices | Skew Vertical | - | ... |
| 5 | - | - | - | ... |
| 6 | - | - | - | ... |

**Dynamic Parameter Types:**

The brilliance of Surge's parameter system is that parameter *types* change based on oscillator type:

```cpp
// Simplified example from oscillator initialization
void ClassicOscillator::init_ctrltypes()
{
    oscdata->p[0].set_name("Shape");
    oscdata->p[0].set_type(ct_osctype);  // Waveform selector

    oscdata->p[1].set_name("Width");
    oscdata->p[1].set_type(ct_percent);  // Pulse width (0-100%)

    oscdata->p[2].set_name("Sync");
    oscdata->p[2].set_type(ct_syncpitch);  // Sync frequency
}
```

## Unison: The Power of Supersaw

Most Surge oscillators support **unison** - running multiple slightly detuned copies:

```cpp
// From: src/common/globals.h
const int MAX_UNISON = 16;  // Up to 16 unison voices
```

**Unison Algorithm:**

```cpp
// Simplified unison pitch calculation
for (int u = 0; u < unisonVoices; u++)
{
    float detune = calculateUnisonDetune(u, unisonVoices, detuneAmount);
    float pitch = basePitch + detune;

    // Process this unison voice
    processOscillatorAtPitch(pitch, u);
}

// Mix all unison voices
mixUnisonVoices();
```

**Detune Distribution:**

Surge uses a sophisticated detune curve that spreads voices naturally:
- Center voice(s) at exact pitch
- Outer voices spread progressively
- Stereo spread option for wide sound

**CPU Cost:**
- Unison = 2: ~2x CPU usage
- Unison = 16: ~16x CPU usage

This is why Surge has a polyphony limit!

## Drift: Analog Imperfection

Real analog oscillators drift slightly in pitch due to component variance and temperature. Surge simulates this:

```cpp
// From oscillator process_block signature:
void process_block(float pitch,
                   float drift = 0.f,  // ← Analog drift amount
                   bool stereo = false,
                   bool FM = false,
                   float FMdepth = 0.f)
```

**Drift Implementation:**

```cpp
// Simplified drift calculation (per voice)
class SurgeVoice
{
    float driftLFO[n_oscs];  // Slow random walk per oscillator

    void calculateDrift()
    {
        for (int osc = 0; osc < n_oscs; osc++)
        {
            // Very slow random walk
            driftLFO[osc] += (randomFloat() - 0.5) * 0.0001;
            driftLFO[osc] *= 0.999;  // Decay back toward 0

            // Pass to oscillator
            float drift = driftLFO[osc] * driftAmount;
            oscillators[osc]->process_block(pitch, drift, stereo, fm, fmdepth);
        }
    }
};
```

The result: each voice drifts slightly differently, creating organic movement.

## Practical Implementation Example

Let's look at a simplified ClassicOscillator sawtooth:

```cpp
// HEAVILY simplified for clarity - real code is optimized
void ClassicOscillator::process_block(float pitch, float drift,
                                      bool stereo, bool FM, float FMdepth)
{
    // 1. Calculate base frequency
    double omega = pitch_to_omega(pitch + drift);

    // 2. Process each sample at oversampled rate (BLOCK_SIZE_OS)
    for (int k = 0; k < BLOCK_SIZE_OS; k++)
    {
        // 3. Check if we need to convolve more samples
        if (oscstate < BLOCK_SIZE_OS)
        {
            convolute();  // Generate next chunk using BLIT
        }

        // 4. Extract sample from buffer
        output[k] = oscbuffer[bufpos];

        // 5. Advance pointers
        bufpos++;
        oscstate--;

        // 6. Wrap buffer if needed
        if (bufpos >= OB_LENGTH)
        {
            // Copy FIR tail to buffer start
            memcpy(oscbuffer, &oscbuffer[OB_LENGTH], FIRipol_N * sizeof(float));
            bufpos = 0;
        }
    }

    // 7. Apply character filter (tone control)
    applyCharacterFilter();

    // 8. Downsample from 96kHz to 48kHz (if needed)
    // This happens at voice level, not here
}
```

## Performance Considerations

### SSE2 Optimization

Oscillators are carefully optimized for SIMD:

```cpp
// Example: Process 4 samples at once
__m128 phase = _mm_set1_ps(currentPhase);      // Broadcast phase to 4 lanes
__m128 increment = _mm_set1_ps(phaseInc);      // Broadcast increment

for (int i = 0; i < BLOCK_SIZE_OS; i += 4)
{
    // Process 4 samples simultaneously
    __m128 samples = _mm_sin_ps(phase);  // 4 sines at once
    _mm_store_ps(&output[i], samples);   // Store 4 results

    phase = _mm_add_ps(phase, increment);  // Advance all 4 phases
}
```

### Memory Layout

Critical for cache efficiency:

```cpp
// GOOD: Arrays of structures (AoS)
struct VoiceState
{
    float phase;
    float output[BLOCK_SIZE_OS];
} voices[MAX_VOICES];

// BETTER for SIMD: Structure of arrays (SoA)
struct VoicePool
{
    float phases[MAX_VOICES];
    float outputs[MAX_VOICES][BLOCK_SIZE_OS];
};
```

Surge uses a hybrid approach optimized for its voice architecture.

## Conclusion

Surge's oscillator system represents the state of the art in software synthesis:

1. **Band-Limited Synthesis**: BLIT and other techniques ensure alias-free output
2. **Flexible Architecture**: 13 oscillator types with consistent interface
3. **High Quality**: Windowed sinc convolution for analog-like sound
4. **Performance**: SSE2 optimization and careful memory layout
5. **Creativity**: Unison, drift, and extensive parameters

Understanding these oscillators is key to both using Surge effectively and appreciating the engineering that makes professional software synthesis possible.

In the next chapters, we'll explore each oscillator type in detail, examining their unique algorithms and sonic characteristics.

---

**Next: [Classic Oscillators](06-oscillators-classic.md)**
**See Also: [Wavetable Synthesis](07-oscillators-wavetable.md), [FM Synthesis](08-oscillators-fm.md)**

## Further Reading

**In Codebase:**
- `src/common/dsp/oscillators/OscillatorBase.h` - Base classes
- `src/common/dsp/oscillators/ClassicOscillator.cpp` - Excellent comments on BLIT
- `doc/Adding an Oscillator.md` - Guide to adding new oscillators

**Academic:**
- "Alias-Free Digital Synthesis of Classic Analog Waveforms" - Stilson & Smith (1996)
- "Synthesis of Quasi-Bandlimited Analog Waveforms Using Frequency Modulation" - Lazzarini & Timoney (2010)
- "The Synthesis ToolKit in C++ (STK)" - Perry Cook & Gary Scavone
