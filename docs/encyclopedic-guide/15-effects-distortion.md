# Chapter 15: Distortion and Waveshaping

## The Art of Controlled Chaos

Distortion and waveshaping represent some of the most visceral and creative tools in sound design. From gentle tube warmth to aggressive fuzz, these effects reshape the fundamental character of sound by applying nonlinear transformations to the audio signal. Unlike time-based or frequency-domain effects that reorganize or redistribute existing harmonics, waveshaping generates entirely new harmonic content through mathematical transfer functions.

Surge XT provides three dedicated distortion effects (Distortion, WaveShaper, and Bonsai) along with integration of the SST waveshapers library and Chowdsp's sophisticated tape saturation algorithms. Each offers distinct sonic characteristics and use cases, from surgical harmonic addition to vintage analog warmth.

This chapter explores the theory of waveshaping, examines Surge's distortion implementations, and reveals the mathematics behind harmonic generation and saturation.

## Waveshaping Theory

### Transfer Functions

At its core, waveshaping applies a **transfer function** to map input values to output values. Unlike linear operations (gain, filtering) where output is proportional to input, waveshaping uses nonlinear functions that change the relationship between input and output amplitudes.

**Linear vs. Nonlinear:**

```
Linear (gain):     y = a × x
Nonlinear (cubic): y = x - (x³/3)
```

The nonlinear function reshapes the waveform, creating harmonic distortion:

```cpp
// Simple waveshaping example
float waveshape_cubic(float x)
{
    return x - (x * x * x) / 3.0f;  // Cubic soft saturation
}

// Input: sine wave → Output: sine with added odd harmonics
```

**Transfer Function Visualization:**

```
Output
  1.0 ┤        ┌──
      │       ╱
  0.5 ┤      ╱
      │     ╱
  0.0 ┼────╱────────── Input
      │   ╱
 -0.5 ┤  ╱
      │ ╱
 -1.0 ┤╱──
```

Linear transfer (gain): Straight line
Soft clipping: Gentle curve toward limits
Hard clipping: Sharp corners at limits

### Harmonic Generation

Waveshaping creates harmonics through the mathematical property that nonlinear functions generate frequency components not present in the input signal.

**Fourier Series Expansion:**

When you apply a polynomial waveshaper to a sinusoid:

```
Input:  x(t) = sin(ωt)
Output: y(t) = a₁·sin(ωt) + a₂·sin(2ωt) + a₃·sin(3ωt) + ...
```

Each term represents a harmonic:
- `a₁·sin(ωt)`: Fundamental (original frequency)
- `a₂·sin(2ωt)`: 2nd harmonic (octave up)
- `a₃·sin(3ωt)`: 3rd harmonic (octave + fifth)

**Polynomial Waveshaping:**

Different polynomials generate different harmonic series:

```cpp
// From Chebyshev polynomials (used in SST waveshapers)
// T₁(x) = x              → 1st harmonic only (no distortion)
// T₂(x) = 2x² - 1        → 2nd harmonic (even)
// T₃(x) = 4x³ - 3x       → 3rd harmonic (odd)
// T₄(x) = 8x⁴ - 8x² + 1  → 4th harmonic (even)
```

**Why Chebyshev polynomials?**
- Each polynomial generates exactly one harmonic
- Can be combined to sculpt precise harmonic spectra
- Used in additive waveshaping (wst_add12, wst_add13, etc.)

**Example - 3rd Harmonic Generation:**

```cpp
// From FilterConfiguration.h:267
p(sst::waveshapers::WaveshaperType::wst_cheby3, "Harmonic");

// Chebyshev T₃: Generates pure 3rd harmonic
// Input: 440 Hz sine → Output: 440 Hz + 1320 Hz (3rd harmonic)
```

### Symmetric vs. Asymmetric Distortion

Waveshapers fall into two categories based on their symmetry:

**Symmetric (Odd Function):**
```
f(-x) = -f(x)
```

Symmetric functions generate only **odd harmonics** (1st, 3rd, 5th, 7th...):
- More "musical" sound (fundamental + octave + fifth pattern)
- Examples: Soft saturation, tube distortion, most analog circuits

```cpp
// Symmetric waveshaper example
float symmetric(float x)
{
    return x - (x * x * x) / 3.0f;  // f(-x) = -f(x)
}
```

**Asymmetric (Even Function or Mixed):**
```
f(-x) ≠ -f(x)
```

Asymmetric functions generate **even harmonics** (2nd, 4th, 6th...) or mixed:
- Adds brightness and "edge"
- Can sound harsher
- Examples: Full-wave rectifiers, asymmetric clipping

```cpp
// From FilterConfiguration.h:260
p(sst::waveshapers::WaveshaperType::wst_asym, "Saturator");

// Asymmetric waveshaper - different curves for positive/negative
float asymmetric(float x)
{
    if (x > 0.0f)
        return x / (1.0f + x);      // Gentle saturation
    else
        return x / (1.0f - 0.5f * x);  // Harder clipping
}
```

**Harmonic Spectra Comparison:**

```
Input: 100 Hz sine wave

Symmetric (cubic):
  100 Hz ████████████████  (fundamental)
  300 Hz ███████           (3rd harmonic)
  500 Hz ████              (5th harmonic)
  700 Hz ██                (7th harmonic)

Asymmetric:
  100 Hz ████████████████  (fundamental)
  200 Hz ██████            (2nd harmonic)
  300 Hz ███████           (3rd harmonic)
  400 Hz ████              (4th harmonic)
  500 Hz ███               (5th harmonic)
```

### Oversampling and Aliasing

Waveshaping generates high-frequency harmonics that can exceed the Nyquist frequency (half the sample rate), causing **aliasing** - false frequencies that fold back into the audible range.

**The Aliasing Problem:**

```
Sample rate: 48 kHz
Nyquist freq: 24 kHz

Input: 10 kHz sine
After 5th harmonic generation:
  10 kHz - fundamental ✓
  20 kHz - 2nd harmonic ✓
  30 kHz - 3rd harmonic ✗ → aliases to 18 kHz (48 - 30)
  40 kHz - 4th harmonic ✗ → aliases to 8 kHz (48 - 40)
```

**Surge's Solution: Oversampling**

Both Distortion and WaveShaper effects use **4× oversampling**:

```cpp
// From: src/common/dsp/effects/DistortionEffect.cpp:27
const int dist_OS_bits = 2;
const int distortion_OS = 1 << dist_OS_bits;  // 1 << 2 = 4

// From: src/common/dsp/effects/WaveShaperEffect.cpp:145
halfbandIN.process_block_U2(wetL, wetR, dataOS[0], dataOS[1], BLOCK_SIZE_OS);
```

**Oversampling Process:**

1. **Upsample**: Interpolate 4× more samples (48 kHz → 192 kHz)
2. **Process**: Apply waveshaping at high sample rate
3. **Downsample**: Filter and decimate back to original rate

```
Original:    |—|—|—|—|  (48 kHz, 64 samples per block)
                ↓ Upsample 4×
Oversampled: |-|-|-|-|-|-|-|-|  (192 kHz, 256 samples per block)
                ↓ Waveshape
Harmonics:   [Safe up to 96 kHz - no aliasing]
                ↓ Downsample 4×
Final:       |—|—|—|—|  (48 kHz, aliasing suppressed)
```

**Half-Band Filters:**

Surge uses **half-band filters** for efficient upsampling/downsampling:

```cpp
// From: src/common/dsp/effects/DistortionEffect.h:36
sst::filters::HalfRate::HalfRateFilter hr_a alignas(16), hr_b alignas(16);

// Usage in processing:
hr_a.process_block_D2(bL, bR, BLOCK_SIZE * 4);  // Downsample 2×
hr_b.process_block_D2(bL, bR, BLOCK_SIZE * 2);  // Downsample 2× again
```

Half-band filters are optimized for 2× decimation with:
- Every other coefficient = 0 (50% fewer calculations)
- Linear phase response
- Steep cutoff at Fs/4

## Distortion Effect

The **Distortion** effect is Surge's classic multi-mode distortion with sophisticated pre/post EQ and 8 waveshaping models.

**Implementation**: `/home/user/surge/src/common/dsp/effects/DistortionEffect.cpp`

### Architecture

```cpp
// From: src/common/dsp/effects/DistortionEffect.h:60
enum dist_params
{
    dist_preeq_gain = 0,     // Pre-distortion EQ gain
    dist_preeq_freq,         // Pre-EQ center frequency
    dist_preeq_bw,           // Pre-EQ bandwidth
    dist_preeq_highcut,      // Pre-distortion low-pass filter
    dist_drive,              // Drive amount (input gain)
    dist_feedback,           // Feedback amount
    dist_posteq_gain,        // Post-distortion EQ gain
    dist_posteq_freq,        // Post-EQ center frequency
    dist_posteq_bw,          // Post-EQ bandwidth
    dist_posteq_highcut,     // Post-distortion low-pass filter
    dist_gain,               // Output gain
    dist_model,              // Waveshaper model (0-7)
};
```

**Signal Flow:**

```
Input → Pre-EQ (peak) → Pre-Highcut (LP) → Drive → Waveshaper
                                                        ↓
Output ← Post-EQ (peak) ← Post-Highcut (LP) ← Gain ← Feedback
```

### Pre/Post Filtering

The Pre-EQ shapes the frequency content before distortion, affecting which harmonics are emphasized:

```cpp
// From: src/common/dsp/effects/DistortionEffect.cpp:64
band1.coeff_peakEQ(band1.calc_omega(fxdata->p[dist_preeq_freq].val.f / 12.f),
                   fxdata->p[dist_preeq_bw].val.f, pregain);
```

**Pre-EQ Strategy:**

```
Boost bass before distortion:
  Input: 100 Hz boosted → drives waveshaper harder at low frequencies
  → generates strong low-frequency harmonics (300 Hz, 500 Hz)
  = Thick, warm distortion

Boost treble before distortion:
  Input: 3 kHz boosted → drives high frequencies harder
  → generates bright, edgy harmonics
  = Harsh, aggressive distortion
```

**High-Cut Filters:**

Optional low-pass filters prevent excessive high-frequency content:

```cpp
// From: src/common/dsp/effects/DistortionEffect.cpp:80
lp1.coeff_LP2B(lp1.calc_omega((*pd_float[dist_preeq_highcut] / 12.0) - 2.f), 0.707);
lp2.coeff_LP2B(lp2.calc_omega((*pd_float[dist_posteq_highcut] / 12.0) - 2.f), 0.707);
```

These are **Butterworth 2-pole** (12 dB/oct) filters:
- Pre-highcut: Tames input before distortion (prevents harsh aliasing)
- Post-highcut: Smooths output (vintage analog character)

### Feedback Path

Feedback creates complex, intermodulated distortion:

```cpp
// From: src/common/dsp/effects/DistortionEffect.cpp:139
for (int s = 0; s < distortion_OS; s++)
{
    L = Lin + fb * L;  // Add previous output to input
    R = Rin + fb * R;

    // ... apply waveshaping ...
}
```

**Feedback Behavior:**

```
fb = 0.0:    No feedback (standard distortion)
fb = 0.3:    Mild resonance and harmonic emphasis
fb = 0.7:    Strong intermodulation, metallic character
fb = -0.5:   Inverted feedback, thinning effect
```

Positive feedback emphasizes certain frequencies, creating resonant peaks. At high levels, it can produce oscillation and chaotic behavior.

### Distortion Models

The effect offers 8 waveshaping models from the SST library:

```cpp
// From: src/common/FilterConfiguration.h:235
static constexpr std::array<sst::waveshapers::WaveshaperType, n_fxws> FXWaveShapers = {
    sst::waveshapers::WaveshaperType::wst_soft,       // Soft saturation
    sst::waveshapers::WaveshaperType::wst_hard,       // Hard clipping
    sst::waveshapers::WaveshaperType::wst_asym,       // Asymmetric saturation
    sst::waveshapers::WaveshaperType::wst_sine,       // Sine waveshaping
    sst::waveshapers::WaveshaperType::wst_digital,    // Digital/bitcrushing
    sst::waveshapers::WaveshaperType::wst_ojd,        // Orange Juice Drink (smooth)
    sst::waveshapers::WaveshaperType::wst_fwrectify,  // Full-wave rectifier
    sst::waveshapers::WaveshaperType::wst_fuzzsoft    // Soft fuzz
};
```

**Model Characteristics:**

**1. Soft (wst_soft):**
- Gentle saturation curve
- Smooth transition to clipping
- Musical, warm character
- Use: Subtle thickening, analog warmth

**2. Hard (wst_hard):**
- Sharp clipping at ±1.0
- Generates strong odd harmonics
- Aggressive, bright tone
- Use: Aggressive synth leads, digital character

**3. Asymmetric (wst_asym):**
- Different curves for positive/negative
- Generates even harmonics
- Adds "edge" and brightness
- Use: Emulating tube asymmetry

**4. Sine (wst_sine):**
- Sine-based transfer function
- Smooth harmonic generation
- Gentle, musical distortion
- Use: Clean harmonic enrichment

**5. Digital (wst_digital):**
- Bit reduction and sample rate reduction simulation
- Adds aliasing artifacts (intentionally)
- Lo-fi character
- Use: Retro digital effects, degradation

**6. OJD (Orange Juice Drink) (wst_ojd):**
- Custom saturation curve
- Named after developer's favorite beverage
- Balanced warmth and clarity
- Use: General-purpose saturation

**7. Full-Wave Rectify (wst_fwrectify):**
- Flips negative values to positive
- Generates strong even harmonics (2nd, 4th)
- Octave-up character
- Use: Ring mod effects, extreme transformation

**8. Soft Fuzz (wst_fuzzsoft):**
- Fuzz-pedal style distortion
- Multiple stages of soft clipping
- Thick, compressed character
- Use: Guitar-style fuzz tones

### Processing Implementation

The core processing loop uses 4× oversampling:

```cpp
// From: src/common/dsp/effects/DistortionEffect.cpp:112
float bL alignas(16)[BLOCK_SIZE << dist_OS_bits];  // 64 << 2 = 256 samples
float bR alignas(16)[BLOCK_SIZE << dist_OS_bits];

drive.multiply_2_blocks(dataL, dataR, BLOCK_SIZE_QUAD);  // Apply drive

for (int k = 0; k < BLOCK_SIZE; k++)
{
    float Lin = dataL[k];
    float Rin = dataR[k];

    for (int s = 0; s < distortion_OS; s++)  // 4 iterations per sample
    {
        L = Lin + fb * L;  // Feedback
        R = Rin + fb * R;

        if (!fxdata->p[dist_preeq_highcut].deactivated)
        {
            lp1.process_sample_nolag(L, R);  // Pre-highcut
        }

        // Apply waveshaper (SSE2 optimized)
        if (useSSEShaper)
        {
            float sb alignas(16)[4];
            auto dInv = 1.f / dNow;
            sb[0] = L * dInv;
            sb[1] = R * dInv;
            auto lr128 = SIMD_MM(load_ps)(sb);
            auto wsres = wsop(&wsState, lr128, SIMD_MM(set1_ps)(dNow));
            SIMD_MM(store_ps)(sb, wsres);
            L = sb[0];
            R = sb[1];
            dNow += dD;  // Smoothly interpolate drive changes
        }

        if (!fxdata->p[dist_posteq_highcut].deactivated)
        {
            lp2.process_sample_nolag(L, R);  // Post-highcut
        }

        bL[s + (k << dist_OS_bits)] = L;
        bR[s + (k << dist_OS_bits)] = R;
    }
}

// Downsample back to original rate
hr_a.process_block_D2(bL, bR, BLOCK_SIZE * 4);  // 256 → 128
hr_b.process_block_D2(bL, bR, BLOCK_SIZE * 2);  // 128 → 64
```

**Key Optimization:**

The drive parameter is smoothly interpolated during the oversampled loop:

```cpp
dD = (dE - dS) / (BLOCK_SIZE * dist_OS_bits);  // Delta per oversample
dNow += dD;  // Increment each iteration
```

This prevents zipper noise while allowing drive to be modulated.

## WaveShaper Effect

The **WaveShaper** effect provides access to the complete SST waveshapers library (43+ waveshape types) with comprehensive pre/post filtering and bias control.

**Implementation**: `/home/user/surge/src/common/dsp/effects/WaveShaperEffect.cpp`

### Architecture

```cpp
// From: src/common/dsp/effects/WaveShaperEffect.h:55
enum wsfx_params
{
    ws_prelowcut,      // Pre-shaper high-pass filter
    ws_prehighcut,     // Pre-shaper low-pass filter
    ws_shaper,         // Waveshaper type selection
    ws_bias,           // DC bias (asymmetry control)
    ws_drive,          // Drive amount
    ws_postlowcut,     // Post-shaper high-pass filter
    ws_posthighcut,    // Post-shaper low-pass filter
    ws_postboost,      // Output gain boost
    ws_mix             // Dry/wet mix
};
```

**Signal Flow:**

```
Input → Pre-Lowcut (HP) → Pre-Highcut (LP) → Add Bias → Drive
                                                           ↓
Output ← Mix ← Post-Boost ← Post-Highcut (LP) ← Post-Lowcut (HP) ← Waveshaper
```

### Waveshaper Library

Unlike Distortion's 8 models, WaveShaper provides the **complete SST library**:

```cpp
// From: src/common/FilterConfiguration.h:225
const char wst_ui_names[(int)sst::waveshapers::WaveshaperType::n_ws_types][16] = {
    "Off",     "Soft",     "Hard",     "Asym",     "Sine",    "Digital",
    "Harm 2",  "Harm 3",   "Harm 4",   "Harm 5",   "FullRect", "HalfPos",
    "HalfNeg", "SoftRect", "1Fold",    "2Fold",    "WCFold",   "Add12",
    "Add13",   "Add14",    "Add15",    "Add1-5",   "AddSaw3",  "AddSqr3",
    "Fuzz",    "SoftFz",   "HeavyFz",  "CenterFz", "EdgeFz",   "Sin+x",
    "Sin2x+x", "Sin3x+x",  "Sin7x+x",  "Sin10x+x", "2Cycle",   "7Cycle",
    "10Cycle", "2CycleB",  "7CycleB",  "10CycleB", "Medium",   "OJD",
    "Sft1Fld"
};
```

**Categories** (from FilterConfiguration.h:244+):

**Saturators:**
- Soft, Hard, Asym, OJD, Zamsat
- Gentle to aggressive saturation
- Tube and transistor emulations

**Harmonic (Chebyshev):**
- Harm 2, Harm 3, Harm 4, Harm 5
- Add12, Add13, Add14, Add15, Add1-5
- Precise harmonic control using Chebyshev polynomials
- AddSaw3, AddSqr3: Simulate sawtooth/square waveforms

**Rectifiers:**
- FullRect: Full-wave rectification (flips negative)
- HalfPos: Half-wave positive (zeros negative)
- HalfNeg: Half-wave negative (zeros positive)
- SoftRect: Smooth rectification

**Wavefolders:**
- 1Fold, 2Fold: Single and double folding
- WCFold: West Coast style folder
- Sft1Fld: Soft single fold
- Creates complex harmonic spectra through reflection

**Fuzz:**
- Fuzz, SoftFz, HeavyFz, CenterFz, EdgeFz
- Vintage pedal emulations
- Various clipping characteristics

**Trigonometric:**
- Sin+x, Sin2x+x, Sin3x+x, Sin7x+x, Sin10x+x
- Sine-based harmonic generators
- Adds specific harmonics mathematically

**Effect:**
- Sine, Digital
- Special-purpose transformations

**Cyclic:**
- 2Cycle, 7Cycle, 10Cycle (and B variants)
- Repeating waveform patterns

### Bias Control

The **bias** parameter adds DC offset before waveshaping, creating asymmetry:

```cpp
// From: src/common/dsp/effects/WaveShaperEffect.cpp:153
din[0] = hbfComp * scalef * dataOS[0][i] + bias.v;
din[1] = hbfComp * scalef * dataOS[1][i] + bias.v;
```

**Why Bias Matters:**

Symmetric waveshapers become asymmetric when DC bias is added:

```
No bias (bias = 0.0):
  Input centered at 0 → symmetric distortion → odd harmonics

Positive bias (bias = 0.3):
  Input shifted up → asymmetric distortion → even + odd harmonics
  Waveform clipping occurs earlier on positive side

Negative bias (bias = -0.3):
  Input shifted down → asymmetric distortion → even + odd harmonics
  Waveform clipping occurs earlier on negative side
```

**Practical Use:**

```
Bias = 0.0, Soft saturation:
  Rich odd harmonics, musical, warm

Bias = 0.3, Soft saturation:
  Adds 2nd harmonic (octave), brightens
  Similar to tube "bias shift" in guitar amps

Bias = -0.5, Full-wave rectifier:
  Extreme transformation, ring-mod character
```

### Oversampling and Scaling

The WaveShaper uses 2× oversampling with careful signal scaling:

```cpp
// From: src/common/dsp/effects/WaveShaperEffect.cpp:100
const auto scalef = 3.f, oscalef = 1.f / 3.f, hbfComp = 2.f;

auto x = scalef * fxdata->p[ws_drive].get_extended(fxdata->p[ws_drive].val.f);
auto dnv = limit_range(powf(2.f, x / 18.f), 0.f, 8.f);
```

**Scaling Explanation:**

1. **scalef = 3.0**: Compensates for filter attenuation and provides headroom
2. **hbfComp = 2.0**: Compensates for half-band filter gain loss
3. **oscalef = 1/3**: Scales output back to unity

This ensures that the WaveShaper in an FX slot behaves identically to the waveshaper in the oscillator section at the same drive settings.

### Processing Loop

```cpp
// From: src/common/dsp/effects/WaveShaperEffect.cpp:144
float dataOS alignas(16)[2][BLOCK_SIZE_OS];
halfbandIN.process_block_U2(wetL, wetR, dataOS[0], dataOS[1], BLOCK_SIZE_OS);

if (wsptr)
{
    for (int i = 0; i < BLOCK_SIZE_OS; ++i)
    {
        din[0] = hbfComp * scalef * dataOS[0][i] + bias.v;
        din[1] = hbfComp * scalef * dataOS[1][i] + bias.v;

        auto dat = SIMD_MM(load_ps)(din);
        auto drv = SIMD_MM(set1_ps)(drive.v);

        dat = wsptr(&wss, dat, drv);  // Apply waveshaper (SSE2)

        SIMD_MM(store_ps)(res, dat);

        dataOS[0][i] = res[0] * oscalef;
        dataOS[1][i] = res[1] * oscalef;

        bias.process();
        drive.process();
    }
}

halfbandOUT.process_block_D2(dataOS[0], dataOS[1], BLOCK_SIZE_OS);
```

### Pre/Post Filtering Strategy

**Pre-Filtering:**
- Shape frequency content before waveshaping
- Emphasize or de-emphasize frequency ranges
- Control which harmonics are generated

**Post-Filtering:**
- Sculpt the distorted output
- Remove excessive high frequencies
- Shape the final tonal character

**Common Strategies:**

```
Bass Saturation:
  Pre-Lowcut: 200 Hz (remove rumble)
  Pre-Highcut: 5 kHz (focus on bass/mids)
  → Drive hard → rich bass harmonics
  Post-Lowcut: 100 Hz
  Post-Highcut: 8 kHz (smooth top end)

Bright Distortion:
  Pre-Lowcut: 1 kHz (emphasize highs)
  Pre-Highcut: off
  → Generate bright harmonics
  Post-Highcut: 12 kHz (prevent harshness)

Telephone Effect:
  Pre-Lowcut: 500 Hz
  Pre-Highcut: 3 kHz (narrow band)
  → Heavy drive → classic lo-fi sound
```

## Bonsai Effect

The **Bonsai** effect combines saturation, bass boost, and tape-style noise simulation for vintage character.

**Implementation**: `/home/user/surge/src/common/dsp/effects/BonsaiEffect.cpp`

### Architecture

The Bonsai uses the SST effects library as its engine:

```cpp
// From: src/common/dsp/effects/BonsaiEffect.h:30
class BonsaiEffect
    : public surge::sstfx::SurgeSSTFXBase<
        sst::effects::bonsai::Bonsai<surge::sstfx::SurgeFXConfig>>
```

**Parameter Groups:**

```cpp
// From: src/common/dsp/effects/BonsaiEffect.cpp:27
group_label(0): "Input"        // Input gain
group_label(1): "Bass Boost"   // Bass enhancement and distortion
group_label(2): "Saturation"   // Tape saturation modes
group_label(3): "Noise"        // Tape noise simulation
group_label(4): "Output"       // Output processing
```

### Bass Boost Section

The bass boost is a shelving filter with optional distortion:

**Parameters:**
- `b_bass_boost`: Amount of bass boost (shelving filter)
- `b_bass_distort`: Distortion applied to boosted bass

**Use Cases:**
- Add warmth and thickness to thin sounds
- Emulate tape low-frequency saturation
- Enhance kick drums and bass synths

### Saturation Modes

Bonsai offers multiple saturation algorithms:

**Filter Modes (`b_tape_bias_mode`):**
- Different pre-saturation filtering
- Shapes frequency response before distortion

**Distortion Modes (`b_tape_dist_mode`):**
- Various saturation transfer functions
- From gentle to aggressive

**Saturation Amount (`b_tape_sat`):**
- Controls intensity of saturation
- 0% = clean, 100% = heavy saturation

### Noise Simulation

Tape noise adds vintage character:

**Parameters:**
- `b_noise_sensitivity`: How much noise responds to signal level
- `b_noise_gain`: Overall noise level

**Behavior:**
```
Low sensitivity:
  Constant noise floor (like tape hiss)

High sensitivity:
  Noise increases with signal level
  Emulates tape compression artifacts
```

### Output Section

**Parameters:**
- `b_dull`: High-frequency roll-off (tape age simulation)
- `b_gain_out`: Output level
- `b_mix`: Dry/wet balance

The "dull" control simulates aged tape by progressively rolling off high frequencies, adding vintage warmth.

## SST Waveshapers Integration

Surge integrates the **SST Waveshapers** library, a comprehensive collection developed by the Surge Synth Team.

### Library Architecture

The SST library provides:

1. **Transfer functions**: Mathematical waveshaping algorithms
2. **SIMD optimization**: SSE2/AVX implementations
3. **State management**: Registers for stateful shapers
4. **Quality focus**: Aliasing-suppressed designs

### Waveshaper State

Many waveshapers maintain internal state:

```cpp
// From: src/common/dsp/effects/DistortionEffect.h:38
sst::waveshapers::QuadWaveshaperState wsState alignas(16);

// From: src/common/dsp/effects/DistortionEffect.cpp:53
for (int i = 0; i < sst::waveshapers::n_waveshaper_registers; ++i)
    wsState.R[i] = SIMD_MM(setzero_ps)();
```

**Why State?**
- Some shapers use feedback or integration
- Avoids discontinuities between blocks
- Enables more complex algorithms

### Waveshaper Categories Deep-Dive

**Additive Waveshapers (Add12, Add13, etc.):**

These use Chebyshev polynomials to add specific harmonics:

```
Add12: Fundamental + 2nd harmonic (octave)
Add13: Fundamental + 3rd harmonic (octave + fifth)
Add14: Fundamental + 4th harmonic (2 octaves)
Add15: Fundamental + 5th harmonic (2 octaves + major third)
Add1-5: All harmonics 1-5 combined
```

**Use Case:**
```
Starting with 200 Hz sine:

Add13:
  200 Hz (fundamental)
  600 Hz (3rd harmonic - perfect fifth above octave)
  = Musical, organ-like sound

Add1-5:
  200 Hz, 400 Hz, 600 Hz, 800 Hz, 1000 Hz
  = Rich, sawtooth-like spectrum
```

**Wavefolder Mathematics:**

Wavefolders reflect the signal when it exceeds a threshold:

```
Single Fold (1Fold):
  If x > 1.0:  y = 2.0 - x  (fold down from 1.0)
  If x < -1.0: y = -2.0 - x (fold up from -1.0)
  Else:        y = x

Double Fold (2Fold):
  Apply folding twice with different thresholds
  Creates more complex harmonic patterns
```

**Spectral Result:**

```
Input: Triangle wave at 100 Hz

After 1Fold:
  Adds many harmonics
  100, 300, 500, 700, 900... (odd harmonics emphasized)

After 2Fold:
  Even more complex spectrum
  Both odd and even harmonics
  Brighter, more aggressive sound
```

### SIMD Processing

All SST waveshapers support quad (4-channel) SIMD processing:

```cpp
// From: src/common/dsp/effects/DistortionEffect.cpp:155
auto wsop = sst::waveshapers::GetQuadWaveshaper(ws);
auto lr128 = SIMD_MM(load_ps)(sb);
auto wsres = wsop(&wsState, lr128, SIMD_MM(set1_ps)(dNow));
```

**Performance Benefit:**

```
Scalar processing: 1 sample per operation
SIMD processing:   4 samples per operation (4× faster)

In practice:
  64 sample block = 16 SIMD operations vs. 64 scalar operations
  Significant CPU savings for real-time audio
```

## Chowdsp Tape Simulation

The **Tape** effect (from Chowdsp) provides physically-modeled tape saturation using hysteresis simulation.

**Implementation**: `/home/user/surge/src/common/dsp/effects/chowdsp/TapeEffect.cpp`

### Hysteresis Model

Tape hysteresis is the nonlinear magnetic property of tape:

**Physical Behavior:**
- Magnetic particles on tape don't respond instantly
- Previous magnetization affects current state
- Creates characteristic tape "warmth" and compression

```cpp
// From: src/common/dsp/effects/chowdsp/TapeEffect.cpp:77
hysteresis.set_params(thd, ths, thb);
hysteresis.set_solver(hysteresisMode);
hysteresis.process_block(L, R);
```

**Parameters:**
- `tape_drive`: Input level (how hard tape is driven)
- `tape_saturation`: Amount of magnetic saturation
- `tape_bias`: Tape bias (asymmetry in magnetic response)
- `tape_tone`: Pre-emphasis/de-emphasis tone control

**Solver Types:**

Multiple numerical solvers for hysteresis differential equations:
- RK4 (Runge-Kutta 4th order): High accuracy, more CPU
- Simpler solvers: Faster, less precise

**User chooses accuracy vs. CPU trade-off**

### Loss Filters

Tape exhibits frequency-dependent losses:

```cpp
// From: src/common/dsp/effects/chowdsp/TapeEffect.cpp:89
lossFilter.set_params(tls, tlsp, tlg, tlt);
lossFilter.process(L, R);
```

**Physical Parameters:**
- `tape_speed`: Tape speed (IPS - inches per second)
- `tape_spacing`: Distance between tape and head (microns)
- `tape_gap`: Tape head gap width (microns)
- `tape_thickness`: Tape thickness (microns)

**Physical Modeling:**

Higher tape speed = less high-frequency loss (better fidelity)
Larger spacing/gap = more high-frequency loss
Thicker tape = different frequency response

```
30 IPS (studio tape):
  Excellent high-frequency response
  Clean, professional sound

7.5 IPS (consumer tape):
  Rolled-off highs
  Warmer, more colored sound

Increased spacing:
  Simulates worn tape machine
  Muffled, vintage character
```

### Degradation Effects

The degrade section simulates tape wear and dropouts:

```cpp
// From: src/common/dsp/effects/chowdsp/TapeEffect.cpp:103
chew.set_params(chew_freq, chew_depth, tdv);
chew.process_block(L, R);

degrade.set_params(tdd, tda, tdv);
degrade.process_block(L, R);
```

**Parameters:**
- `tape_degrade_depth`: Amount of degradation
- `tape_degrade_amount`: Type/severity of degradation
- `tape_degrade_variance`: Randomness in degradation

**Effects:**
- Random volume fluctuations (tape flutter)
- Dropouts (tape damage)
- Wow and flutter (speed variations)
- Adds character and "vibe"

### Tape Effect Signal Flow

```
Input → Tone Control → Hysteresis → Makeup Gain
                           ↓
        Chew ← Degrade ← Loss Filter
           ↓
        Output Mix
```

**Tone Control:**

Pre-emphasis filter before hysteresis:

```cpp
// From: src/common/dsp/effects/chowdsp/TapeEffect.cpp:79
toneControl.set_params(tht);
toneControl.processBlockIn(L, R);
```

Shapes frequency response entering tape simulation. Positive values emphasize highs (brighter), negative values emphasize lows (warmer).

**Makeup Gain:**

Hysteresis reduces level, so makeup gain compensates:

```cpp
// From: src/common/dsp/effects/chowdsp/TapeEffect.cpp:51
makeup.set_target(std::pow(10.0f, 9.0f / 20.0f));  // +9 dB
```

## Practical Applications

### Harmonic Thickening

**Goal:** Add richness without obvious distortion

**Recipe:**
1. WaveShaper effect
2. Shape: "Soft" or "OJD"
3. Drive: 6-12 dB
4. Bias: 0-15% (adds subtle 2nd harmonic)
5. Mix: 30-50%

**Result:** Subtle harmonic enrichment, analog warmth

### Aggressive Lead

**Goal:** Cutting, aggressive synth lead

**Recipe:**
1. Distortion effect
2. Pre-EQ: Boost 2-4 kHz (+6 dB)
3. Model: "Hard"
4. Drive: 12-18 dB
5. Feedback: 20-40%
6. Post-EQ: Cut 6-8 kHz (-3 dB) to tame harshness

**Result:** Bright, aggressive distortion with controlled harshness

### Vintage Tape Warmth

**Goal:** Analog tape character

**Recipe:**
1. Tape effect (Chowdsp)
2. Drive: 70-85%
3. Saturation: 50%
4. Speed: 15-30 IPS
5. Degrade Depth: 10-20% (subtle wear)

**Result:** Warm saturation with tape compression and subtle flutter

### Bass Enhancement

**Goal:** Thick, powerful bass

**Recipe:**
1. Bonsai effect
2. Bass Boost: 60-80%
3. Bass Distort: 30-50%
4. Saturation: 40-60%
5. Dull: 20% (warm top end)

**Result:** Enhanced low end with controlled saturation

### Wavefolder Textures

**Goal:** Complex, evolving timbres

**Recipe:**
1. WaveShaper effect
2. Shape: "WCFold" or "2Fold"
3. Drive: Modulate with LFO (0-24 dB)
4. Bias: Modulate with slow LFO (-50% to +50%)
5. Pre-Highcut: 8 kHz (focus folding on mids)

**Result:** Evolving, complex harmonic movement

## Advanced Techniques

### Parallel Distortion

Use Send effects for parallel processing:

```
Scene A → Send 1 → Heavy Distortion
   ↓
  Mix with clean signal
```

**Advantage:** Maintain clean low end while adding distorted harmonics on top

### Serial Waveshaping

Stack multiple waveshapers:

```
Slot 1: WaveShaper (Add13) - adds 3rd harmonic
Slot 2: WaveShaper (Soft) - saturates the result
Slot 3: Distortion (OJD) - final polish
```

**Result:** Complex harmonic interactions not possible with single stage

### Modulated Distortion

Modulate drive with envelope or LFO:

```
LFO → Drive parameter
  Shape: Triangle
  Rate: 1/4 note
  Depth: 50%
```

**Result:** Rhythmic distortion intensity changes, dynamic movement

### Frequency-Selective Distortion

Use filtering to distort only specific frequencies:

```
Pre-Lowcut: 2 kHz
Pre-Highcut: 6 kHz
  → Only distorts 2-6 kHz range
Post: Full-range mix
```

**Result:** Distorted mids, clean bass and extreme highs

## Conclusion

Distortion and waveshaping transform sound through nonlinear mathematics, generating harmonics and shaping timbre in ways impossible with linear processing. Surge XT's distortion effects offer:

1. **Multiple algorithms**: 43+ waveshape types across 3 effects
2. **Quality implementation**: Oversampling prevents aliasing
3. **Flexible routing**: Pre/post filtering, bias control, feedback
4. **Physical modeling**: Tape saturation with real-world parameters
5. **SIMD optimization**: Efficient processing for real-time performance

From subtle analog warmth to extreme sonic destruction, these tools provide comprehensive control over harmonic content and saturation character.

**Key Takeaways:**

- Waveshaping generates harmonics through nonlinear transfer functions
- Symmetric shapers create odd harmonics (musical)
- Asymmetric shapers create even harmonics (bright)
- Oversampling prevents aliasing artifacts
- Pre/post filtering shapes which frequencies are distorted
- Bias control adds asymmetry to symmetric shapers
- Tape simulation models physical magnetic hysteresis
- Parallel and serial processing enable complex textures

**Further Reading:**

- Zölzer, U. "DAFX - Digital Audio Effects" (2nd ed.), Chapter 4: Nonlinear Processing
- Smith, J.O. "Physical Audio Signal Processing", Chapter on Waveshaping
- SST Waveshapers library documentation
- Chowdsp tape model paper (implemented in Surge)

---

**Next: [Chapter 16: Effects - Modulation](16-effects-modulation.md)**
**See Also: [Chapter 12: Effects Architecture](12-effects-architecture.md), [Chapter 13: Time-Based Effects](13-effects-time-based.md)**
