# Chapter 16: Frequency-Domain Effects

## The Spectral Toolkit

While time-based effects manipulate when signals occur, frequency-domain effects transform *what frequencies* are present and *how they interact*. From surgical equalization to exotic frequency shifting, these processors reshape the harmonic content of sound in ways impossible through pure time-domain manipulation.

Surge XT implements five sophisticated frequency processors that span the spectrum from corrective to creative: dual equalizers for precise tonal shaping, a frequency shifter employing Hilbert transforms for inharmonic shifting, a diode ring modulator for metallic timbres, a classic vocoder for robotic voices, and a harmonic exciter for presence enhancement. Each represents a distinct approach to frequency manipulation.

This chapter explores the mathematics, implementation strategies, and sonic characteristics of these frequency-domain tools, revealing how careful spectral processing creates everything from transparent correction to radical transformation.

## Fundamental Concepts

### Filter Banks and Parallelism

Many frequency-domain effects use **filter banks** - arrays of bandpass filters that divide the spectrum into discrete bands:

```cpp
// From: src/common/dsp/effects/VocoderEffect.h:33
const int n_vocoder_bands = 20;
const int voc_vector_size = n_vocoder_bands >> 2;  // Divide by 4 for SIMD

// Array of vectorized filters
VectorizedSVFilter mCarrierL alignas(16)[voc_vector_size];
VectorizedSVFilter mModulator alignas(16)[voc_vector_size];
```

**SIMD optimization:** Processing 4 bands simultaneously using SSE2:

```
Band 0-3:   [BP1] [BP2] [BP3] [BP4] ──► SSE register 1
Band 4-7:   [BP5] [BP6] [BP7] [BP8] ──► SSE register 2
Band 8-11:  [BP9] [BP10][BP11][BP12] ──► SSE register 3
...
```

Each `VectorizedSVFilter` processes 4 adjacent frequency bands in parallel, reducing CPU overhead by 75% compared to scalar processing.

### Biquad Peak Filters

Equalizers use **biquad peaking filters** - second-order IIR filters with adjustable frequency, bandwidth, and gain:

```cpp
// From: src/common/dsp/effects/ParametricEQ3BandEffect.cpp:73
band1.coeff_peakEQ(band1.calc_omega(*pd_float[eq3_freq1] * (1.f / 12.f)),
                   *pd_float[eq3_bw1],
                   *pd_float[eq3_gain1]);
```

**Transfer function:**

```
H(z) = (b0 + b1*z^-1 + b2*z^-2) / (1 + a1*z^-1 + a2*z^-2)
```

**Coefficient calculation** for peak EQ:

```cpp
float omega = 2 * π * fc / fs;     // Angular frequency
float alpha = sin(omega) / (2 * Q); // Bandwidth factor
float A = sqrt(gainLinear);         // Amplitude

b0 = 1 + alpha * A;
b1 = -2 * cos(omega);
b2 = 1 - alpha * A;
a0 = 1 + alpha / A;
a1 = -2 * cos(omega);
a2 = 1 - alpha / A;

// Normalize
b0 /= a0;
b1 /= a0;
b2 /= a0;
a1 /= a0;
a2 /= a0;
```

The resulting filter provides:
- **Flat response** at gain = 1.0 (0 dB)
- **Boost** at gain > 1.0
- **Cut** at gain < 1.0
- **Bandwidth** controlled by Q (higher Q = narrower)

### Hilbert Transforms

The **Hilbert transform** creates a 90° phase-shifted version of a signal, essential for single-sideband modulation and frequency shifting:

```cpp
// From: src/common/dsp/effects/FrequencyShifterEffect.cpp:146
fr.process_block(Lr, Rr, BLOCK_SIZE);  // Real component
fi.process_block(Li, Ri, BLOCK_SIZE);  // Imaginary (90° shifted)
```

**Mathematical relationship:**

For signal `x(t)`, its Hilbert transform `H{x(t)}` satisfies:
- Delays all frequencies by 90° (π/2 radians)
- Maintains amplitude constant across all frequencies
- Creates analytic signal: `z(t) = x(t) + j·H{x(t)}`

**Implementation:** Surge uses **halfband filters** cascaded 6 times to approximate the ideal 90° phase shift across the audio band. This FIR approach provides:
- Flat amplitude response (±0.01 dB)
- Constant 90° phase shift (±0.5°)
- Linear phase (no phase distortion)

## Equalizers

Surge provides two complementary equalizer designs: a graphic EQ with fixed bands for quick tonal shaping, and a parametric EQ with adjustable centers for surgical control.

### Graphic EQ (11-Band)

The **GraphicEQ11BandEffect** implements an 11-band graphic equalizer with ISO-standard frequency centers:

```cpp
// From: src/common/dsp/effects/GraphicEQ11BandEffect.cpp:69-79
band1.coeff_peakEQ(band1.calc_omega_from_Hz(30.f), 0.5, *pd_float[geq11_30]);
band2.coeff_peakEQ(band2.calc_omega_from_Hz(60.f), 0.5, *pd_float[geq11_60]);
band3.coeff_peakEQ(band3.calc_omega_from_Hz(120.f), 0.5, *pd_float[geq11_120]);
band4.coeff_peakEQ(band4.calc_omega_from_Hz(250.f), 0.5, *pd_float[geq11_250]);
band5.coeff_peakEQ(band5.calc_omega_from_Hz(500.f), 0.5, *pd_float[geq11_500]);
band6.coeff_peakEQ(band6.calc_omega_from_Hz(1000.f), 0.5, *pd_float[geq11_1k]);
band7.coeff_peakEQ(band7.calc_omega_from_Hz(2000.f), 0.5, *pd_float[geq11_2k]);
band8.coeff_peakEQ(band8.calc_omega_from_Hz(4000.f), 0.5, *pd_float[geq11_4k]);
band9.coeff_peakEQ(band9.calc_omega_from_Hz(8000.f), 0.5, *pd_float[geq11_8k]);
band10.coeff_peakEQ(band10.calc_omega_from_Hz(12000.f), 0.5, *pd_float[geq11_12k]);
band11.coeff_peakEQ(band11.calc_omega_from_Hz(16000.f), 0.5, *pd_float[geq11_16k]);
```

**Frequency centers** (Hz):
```
30, 60, 120, 250, 500, 1k, 2k, 4k, 8k, 12k, 16k
```

These frequencies follow a quasi-logarithmic spacing that covers the critical regions:
- **30-250 Hz**: Sub-bass and bass fundamentals
- **500-2000 Hz**: Vocal presence and instrument body
- **4000-16000 Hz**: Clarity, air, and brilliance

**Fixed Q = 0.5** provides gentle, musical curves with minimal inter-band interaction.

**Processing architecture:**

```cpp
// From: src/common/dsp/effects/GraphicEQ11BandEffect.cpp:113-144
void GraphicEQ11BandEffect::process(float *dataL, float *dataR)
{
    if (bi == 0)
        setvars(false);
    bi = (bi + 1) & slowrate_m1;  // Update coefficients every 8 samples

    // Serial processing through all active bands
    if (!fxdata->p[geq11_30].deactivated)
        band1.process_block(dataL, dataR);
    if (!fxdata->p[geq11_60].deactivated)
        band2.process_block(dataL, dataR);
    // ... (bands 3-11)

    // Apply output gain
    gain.set_target_smoothed(storage->db_to_linear(*pd_float[geq11_gain]));
    gain.multiply_2_blocks(dataL, dataR, BLOCK_SIZE_QUAD);
}
```

**Key features:**
1. **Deactivatable bands**: Any band can be bypassed to save CPU
2. **Serial topology**: Signal flows through bands sequentially
3. **Output gain**: Final gain stage for level matching
4. **Control rate optimization**: Coefficients update at slowrate (every 8 samples)

**Phase characteristics:**

Each biquad introduces **phase shift** near its center frequency:
- Maximum phase shift: ±90° at center frequency
- Phase shift spread: ±1 octave at Q=0.5
- Total delay: ~0.5 ms at 48kHz (group delay peak)

With 11 bands, cumulative phase shift can reach several hundred degrees, creating audible **pre-ringing** on transients when multiple bands are heavily adjusted. This is inherent to minimum-phase EQs and contributes to their "musical" character.

### Parametric EQ (3-Band)

The **ParametricEQ3BandEffect** provides three fully adjustable bands with frequency, bandwidth, and gain control:

```cpp
// From: src/common/dsp/effects/ParametricEQ3BandEffect.cpp:73-78
band1.coeff_peakEQ(band1.calc_omega(*pd_float[eq3_freq1] * (1.f / 12.f)),
                   *pd_float[eq3_bw1], *pd_float[eq3_gain1]);
band2.coeff_peakEQ(band2.calc_omega(*pd_float[eq3_freq2] * (1.f / 12.f)),
                   *pd_float[eq3_bw2], *pd_float[eq3_gain2]);
band3.coeff_peakEQ(band3.calc_omega(*pd_float[eq3_freq3] * (1.f / 12.f)),
                   *pd_float[eq3_bw3], *pd_float[eq3_gain3]);
```

**Parameter ranges:**

| Parameter | Range | Default |
|-----------|-------|---------|
| Frequency 1 | 13.75 Hz - 25.1 kHz | 55 Hz |
| Frequency 2 | 13.75 Hz - 25.1 kHz | 698 Hz |
| Frequency 3 | 13.75 Hz - 25.1 kHz | 7.9 kHz |
| Bandwidth | 0.125 - 8 octaves | 2 octaves |
| Gain | -96 dB to +96 dB | 0 dB |

**Frequency encoding:** Parameters use **semitone offset** for musical tuning:

```cpp
// freq_param = -2.5 * 12 = -30 semitones below A440
// A440 * 2^(-30/12) = 440 * 0.125 = 55 Hz

float hz = 440.f * pow(2.f, freq_param_semitones / 12.f);
```

This provides:
- Musical interval control (easy octave/fifth spacing)
- Exponential frequency distribution (matches perception)
- Integration with Surge's tuning system

**Bandwidth (Q) relationships:**

```cpp
float Q_from_bandwidth(float bw_octaves)
{
    // Q = 1 / (2 * sinh(ln(2)/2 * BW))
    return 1.0f / (2.0f * sinhf(0.34657359f * bw_octaves));
}
```

| Bandwidth (oct) | Q value | Character |
|-----------------|---------|-----------|
| 0.125 | 11.1 | Extremely narrow, surgical |
| 0.5 | 2.87 | Narrow, focused |
| 1.0 | 1.41 | Moderate |
| 2.0 | 0.67 | Broad, gentle |
| 4.0 | 0.32 | Very broad |
| 8.0 | 0.16 | Extremely broad |

**Dry/wet mixing:**

Unlike the graphic EQ, the parametric EQ includes **parallel processing** capability:

```cpp
// From: src/common/dsp/effects/ParametricEQ3BandEffect.cpp:82-103
void ParametricEQ3BandEffect::process(float *dataL, float *dataR)
{
    // Copy dry signal
    mech::copy_from_to<BLOCK_SIZE>(dataL, L);
    mech::copy_from_to<BLOCK_SIZE>(dataR, R);

    // Process through active bands
    if (!fxdata->p[eq3_gain1].deactivated)
        band1.process_block(L, R);
    if (!fxdata->p[eq3_gain2].deactivated)
        band2.process_block(L, R);
    if (!fxdata->p[eq3_gain3].deactivated)
        band3.process_block(L, R);

    // Apply output gain
    gain.set_target_smoothed(storage->db_to_linear(*pd_float[eq3_gain]));
    gain.multiply_2_blocks(L, R, BLOCK_SIZE_QUAD);

    // Dry/wet crossfade
    mix.set_target_smoothed(clamp1bp(*pd_float[eq3_mix]));
    mix.fade_2_blocks_inplace(dataL, L, dataR, R, BLOCK_SIZE_QUAD);
}
```

**Mix parameter interpretation:**

```cpp
// -100%: Full dry (unprocessed)
//    0%: Balanced 50/50 blend
// +100%: Full wet (EQ only)

output = dry * (1 - |mix|) + wet * (0.5 + mix/2)
```

This allows:
- **Parallel EQ:** Blend EQ with dry for gentle correction
- **Shelving emulation:** Low mix with extreme boost = subtle lift
- **Special effects:** 100% wet with inverted EQ = notch filter bank

### EQ Design Considerations

**Serial vs. Parallel Topology:**

Surge's EQs use **serial (cascaded) topology:**

```
Input ──[Band1]──[Band2]──[Band3]── ... ──[BandN]── Output
```

**Advantages:**
- Simple implementation
- Each band's gain multiplies (combines naturally)
- Familiar to analog EQ users
- Lower memory usage

**Disadvantages:**
- Phase accumulation through cascade
- Order matters (low bands affect high bands' phase)
- Potential numerical precision issues with extreme settings

**Parallel topology** (not used in Surge EQs, but common in FFT EQs):

```
        ┌─[Band1]─┐
Input ──┼─[Band2]─┼── Sum ── Output
        ├─[Band3]─┤
        └─ ... ───┘
```

**Why serial?**
- Real-time coefficient updates without FFT overhead
- Zero latency (no FFT window delay)
- Musical phase response (minimum-phase)
- Lower CPU for small band counts

**Coefficient update rate:**

```cpp
bi = (bi + 1) & slowrate_m1;  // & 7 = modulo 8
```

Updating every 8 samples (166 Hz at 48kHz) provides:
- Smooth parameter changes without zipper noise
- 87.5% CPU reduction in coefficient calculation
- Fast enough for modulation (no audible stepping)

**Practical EQ usage:**

1. **Graphic EQ:** Quick broad strokes, "smiley curve" bass/treble boost
2. **Parametric EQ:** Surgical notching, precise resonance control
3. **Combining both:** Use graphic for overall tone, parametric for problem frequencies

## Frequency Shifter

The **FrequencyShifterEffect** implements true **frequency shifting** using single-sideband (SSB) modulation - shifting all frequencies by a fixed amount in Hz, not scaling by ratio like a pitch shifter.

### SSB Modulation Theory

**Frequency shifting vs. Pitch shifting:**

```
Original:    100 Hz, 200 Hz, 300 Hz (harmonic series)

Pitch shift +7 semitones (×1.5):
Result:      150 Hz, 300 Hz, 450 Hz (still harmonic)

Frequency shift +100 Hz:
Result:      200 Hz, 300 Hz, 400 Hz (INHARMONIC!)
```

Frequency shifting **destroys harmonic relationships**, creating bell-like, metallic, or alien timbres.

**Mathematical basis:**

Standard amplitude modulation (ring modulation):
```
y(t) = x(t) · cos(ωc·t)
     = x(t) · cos(2πfc·t)
```

Creates **both upper and lower sidebands:**
```
Input: x(t) = cos(ωs·t)
Carrier: c(t) = cos(ωc·t)

Output: y(t) = 0.5·cos((ωc + ωs)·t) + 0.5·cos((ωc - ωs)·t)
              └─── upper sideband ──┘   └─── lower sideband ──┘
```

**Single-sideband modulation** suppresses one sideband, producing pure frequency shift.

### Hilbert Transform Implementation

To generate SSB, we need signal's **analytic representation**:

```
z(t) = x(t) + j·H{x(t)}
     = I(t) + j·Q(t)     (In-phase + Quadrature)
```

Where `H{·}` is the Hilbert transform (90° phase shifter).

**Weaver method (used by Surge):**

```cpp
// From: src/common/dsp/effects/FrequencyShifterEffect.cpp:136-159

// Step 1: Modulate with quadrature oscillators
for (k = 0; k < BLOCK_SIZE; k++)
{
    o1L.process();  // Quadrature oscillator (I and Q outputs)
    Lr[k] = L[k] * o1L.r;  // Real component
    Li[k] = L[k] * o1L.i;  // Imaginary component (90° shifted)
}

// Step 2: Hilbert transform both components
fr.process_block(Lr, Rr, BLOCK_SIZE);  // Transform real
fi.process_block(Li, Ri, BLOCK_SIZE);  // Transform imaginary

// Step 3: Second modulation and combination
for (k = 0; k < BLOCK_SIZE; k++)
{
    o2L.process();
    Lr[k] *= o2L.r;
    Li[k] *= o2L.i;

    L[k] = 2 * (Lr[k] + Li[k]);  // Combine for single sideband
}
```

**Quadrature oscillator implementation:**

```cpp
// From: src/common/dsp/effects/FrequencyShifterEffect.h:70
using quadr_osc = sst::basic_blocks::dsp::SurgeQuadrOsc<float>;
```

The quadrature oscillator generates:
```cpp
r = cos(ωt)     // Real (in-phase)
i = sin(ωt)     // Imaginary (quadrature)
```

Using **coupled oscillator** approach:

```cpp
void process()
{
    float new_r = r * cos(dω) - i * sin(dω);
    float new_i = i * cos(dω) + r * sin(dω);
    r = new_r;
    i = new_i;
}
```

This rotation matrix provides:
- Perfect 90° phase relationship
- Numerically stable (normalized regularly)
- Efficient (no transcendental functions per sample)

### Halfband Hilbert Filters

```cpp
// From: src/common/dsp/effects/FrequencyShifterEffect.h:36
sst::filters::HalfRate::HalfRateFilter fr alignas(16), fi alignas(16);
```

**Halfband filter cascade:**

Surge uses **6-stage cascaded halfband filters** to approximate ideal Hilbert transform:

```
Input ──[HB1]──[HB2]──[HB3]──[HB4]──[HB5]──[HB6]── 90° shifted
```

Each stage contributes ~15° of phase shift, accumulating to ~90° total.

**Properties:**
- FIR implementation (linear phase in passband)
- Flat amplitude response (±0.01 dB, 20 Hz - 20 kHz)
- Phase accuracy: ±0.5° across audio band
- Delay: ~6 samples (compensated in both paths)

### Frequency Shifter Parameters

```cpp
// From: src/common/dsp/effects/FrequencyShifterEffect.cpp:73
double shift = *pd_float[freq_shift] * (extend_range ? 1000.0 : 10.0);
double omega = shift * M_PI * 2.0 * storage->dsamplerate_inv;
```

**Shift amount:**
- Normal range: ±10 Hz (subtle detuning)
- Extended range: ±1000 Hz (radical transformation)

**Oscillator frequencies:**

```cpp
// For positive shift (+f Hz):
o1L.set_rate(M_PI * 0.5 - min(0.0, omega));  // π/2 (no adjustment)
o2L.set_rate(M_PI * 0.5 + max(0.0, omega));  // π/2 + ω

// For negative shift (-f Hz):
o1L.set_rate(M_PI * 0.5 - min(0.0, omega));  // π/2 + |ω|
o2L.set_rate(M_PI * 0.5 + max(0.0, omega));  // π/2 (no adjustment)
```

The π/2 term represents the base quadrature relationship; the omega adjustment selects upper or lower sideband.

**Stereo operation:**

```cpp
// From: src/common/dsp/effects/FrequencyShifterEffect.cpp:79-91
if (*pd_float[freq_rmult] == 1.f)
{
    // Phase lock mode: right tracks left
    const double a = 0.01;
    o1R.r = a * o1L.r + (1 - a) * o1R.r;
    o1R.i = a * o1L.i + (1 - a) * o1R.i;
    o2R.r = a * o2L.r + (1 - a) * o2R.r;
    o2R.i = a * o2L.i + (1 - a) * o2R.i;
}
else
{
    omega *= *pd_float[freq_rmult];  // Independent right channel
}
```

**Right channel multiplier:**
- 1.0: Phase-locked stereo (both channels identical shift)
- -1.0: Opposite phase (creates wide stereo)
- 0.0: Right channel unshifted
- Other values: Independent right shift amount

### Feedback and Delay

The frequency shifter includes **delay line with feedback** for resonance effects:

```cpp
// From: src/common/dsp/effects/FrequencyShifterEffect.cpp:59-68
time.newValue((fxdata->p[freq_delay].temposync ? storage->temposyncratio_inv : 1.f) *
              storage->samplerate *
              storage->note_to_pitch_ignoring_tuning(12 * *pd_float[freq_delay]) -
              FIRoffset);
```

**Delay encoding:** Uses note-to-pitch for musical time intervals:
- Parameter -8: ~0.25 ms (very short, comb filtering)
- Parameter 0: ~1 ms (moderate delay)
- Parameter +3: ~2.8 ms (longer delay)

**Feedback with saturation:**

```cpp
// From: src/common/dsp/effects/FrequencyShifterEffect.cpp:165-170
buffer[0][wp] = dataL[k] + (float)storage->lookup_waveshape(
    sst::waveshapers::WaveshaperType::wst_soft,
    (L[k] * feedback.v));
```

The `wst_soft` waveshaper prevents runaway feedback:
```
f(x) = tanh(x) for soft clipping
```

**Musical applications:**

1. **Subtle detuning:** ±1-5 Hz creates chorus-like movement
2. **Harmonic destruction:** ±50-100 Hz on chords creates dissonance
3. **Barber-pole effect:** Slowly sweep shift amount for endless rise/fall
4. **Comb filtering:** Short delay + feedback = resonant comb
5. **Stereo width:** Opposite L/R shift creates pseudo-stereo

## Ring Modulator

The **RingModulatorEffect** implements **diode ring modulation** - the classic technique for creating metallic, inharmonic timbres through nonlinear multiplication.

### Ring Modulation Theory

**Ideal ring modulation** multiplies two signals:

```
y(t) = x(t) · c(t)
```

Where:
- `x(t)` = input signal (modulator)
- `c(t)` = carrier signal (usually oscillator)
- `y(t)` = output (sum and difference frequencies)

**Frequency domain result:**

For sinusoidal input and carrier:
```
x(t) = A·cos(ω₁t)
c(t) = B·cos(ω₂t)

y(t) = (AB/2)·[cos((ω₁+ω₂)t) + cos((ω₁-ω₂)t)]
       └─── sum frequency ──┘   └─ difference ──┘
```

**Complex spectra:** For input with multiple partials:

```
Input partials:    f₁, f₂, f₃, ...
Carrier:           fc

Output contains:   fc±f₁, fc±f₂, fc±f₃, ...
                  (sum AND difference of every combination)
```

This creates **inharmonic** spectra - the hallmark of metallic, bell-like timbres.

### Diode Ring Modulator

Surge implements a **diode ring modulator** that models the behavior of a four-diode ring:

```
         D1
         ↓
    A ───┴─── B
         ↑
         D2

    C ───┬─── D
         ↓
         D3
         ↑
         D4
```

**Transfer function** (simplified):

```cpp
// From: src/common/dsp/effects/RingModulatorEffect.cpp:179-189
auto A = 0.5 * vin + vc;
auto B = vc - 0.5 * vin;

float dPA = diode_sim(A);
float dMA = diode_sim(-A);
float dPB = diode_sim(B);
float dMB = diode_sim(-B);

float res = dPA + dMA - dPB - dMB;
```

**Diode characteristic:**

```cpp
// From: src/common/dsp/effects/RingModulatorEffect.cpp:355-372
float RingModulatorEffect::diode_sim(float v)
{
    auto vb = *(pd_float[rm_diode_fwdbias]);      // Forward bias voltage
    auto vl = *(pd_float[rm_diode_linregion]);    // Linear region voltage

    vl = std::max(vl, vb + 0.02f);

    if (v < vb)
        return 0;  // Below forward bias: no conduction

    if (v < vl)
    {
        // Exponential region (parabolic approximation)
        auto vvb = v - vb;
        return h * vvb * vvb / (2.f * vl - 2.f * vb);
    }

    // Linear region
    auto vlvb = vl - vb;
    return h * v - h * vl + h * vlvb * vlvb / (2.f * vl - 2.f * vb);
}
```

**Diode regions:**

```
Current
  ↑
  │        ┌─────── Linear region (v > vl)
  │       ╱
  │      ╱
  │    ╱╱ ← Exponential region (vb < v < vl)
  │   ╱
  │  ╱
  │ ╱
  └─────────────► Voltage
    vb   vl
```

**Parameters:**
- **Forward Bias (vb):** Voltage before conduction starts (0-100%)
- **Linear Region (vl):** Voltage where exponential becomes linear (0-100%)

**Effects on timbre:**
- Low bias, low linear: Sharp, aggressive, more harmonics
- High bias, high linear: Soft, gentle, fewer harmonics
- Bias near linear: Approaches ideal multiplication

### Carrier Generation

```cpp
// From: src/common/dsp/effects/RingModulatorEffect.cpp:159-165
vc[0] = SineOscillator::valueFromSinAndCos(
    sst::basic_blocks::dsp::fastsin(2.0 * M_PI * (phase[u] - 0.5)),
    sst::basic_blocks::dsp::fastcos(2.0 * M_PI * (phase[u] - 0.5)),
    *pd_int[rm_carrier_shape]);

phase[u] += dphase[u];
```

**Carrier shapes** (from SineOscillator):

| Shape | Waveform | Harmonics |
|-------|----------|-----------|
| 0 | Sine | Fundamental only |
| 1-24 | Various | Increasing harmonic content |
| 25 | Audio Input | External carrier |

Using `valueFromSinAndCos()` allows generating complex waveforms from simple sine/cosine pairs through waveshaping.

**Frequency calculation:**

```cpp
// From: src/common/dsp/effects/RingModulatorEffect.cpp:130-142
if (fxdata->p[rm_unison_detune].absolute)
{
    dphase[u] = storage->note_to_pitch(
        *pd_float[rm_carrier_freq] +
        fxdata->p[rm_unison_detune].get_extended(
            *pd_float[rm_unison_detune] * detune_offset[u])
    ) * sri;
}
else
{
    dphase[u] = storage->note_to_pitch(
        *pd_float[rm_carrier_freq] + ...
    ) * Tunings::MIDI_0_FREQ * sri;
}
```

**Absolute vs. Relative detune:**
- **Absolute:** Detune in Hz (maintains interval at all carrier frequencies)
- **Relative:** Detune in cents (interval grows with carrier frequency)

### Unison Mode

Multiple detuned carriers create **chorus-like thickening**:

```cpp
// From: src/common/dsp/effects/RingModulatorEffect.cpp:80-103
if (uni == 1)
{
    detune_offset[0] = 0;
    panL[0] = 1.f;
    panR[0] = 1.f;
}
else
{
    float detune_bias = (float)2.f / (uni - 1.f);

    for (auto u = 0; u < uni; ++u)
    {
        phase[u] = u * 1.f / (uni);              // Spread initial phases
        detune_offset[u] = -1.f + detune_bias * u;  // Spread detuning

        panL[u] = u / (uni - 1.f);               // Pan across stereo field
        panR[u] = (uni - 1.f - u) / (uni - 1.f);
    }
}
```

**With 4 voices:**
```
Voice 1: detune -1.0, pan 0% L / 100% R
Voice 2: detune -0.33, pan 33% L / 67% R
Voice 3: detune +0.33, pan 67% L / 33% R
Voice 4: detune +1.0, pan 100% L / 0% R
```

This creates:
- Chorused carrier (beating between voices)
- Wide stereo image (voices panned across field)
- Thick, complex texture

**Gain compensation:**

```cpp
float gscale = 0.4 + 0.6 * (1.f / sqrtf(uni));
```

Reduces output by `1/√N` to prevent clipping as voices accumulate.

### Oversampling

Ring modulation generates **aliasing** due to nonlinear multiplication:

```cpp
// From: src/common/dsp/effects/RingModulatorEffect.cpp:111-120
#if OVERSAMPLE
    // Upsample to 2x
    float dataOS alignas(16)[2][BLOCK_SIZE_OS];
    halfbandIN.process_block_U2(dataL, dataR, dataOS[0], dataOS[1], BLOCK_SIZE_OS);
    sri = storage->dsamplerate_os_inv;
    ub = BLOCK_SIZE_OS;
#endif

// ... process at 2x rate ...

#if OVERSAMPLE
    // Downsample back to 1x
    halfbandOUT.process_block_D2(dataOS[0], dataOS[1], BLOCK_SIZE_OS);
#endif
```

**Why 2x oversampling?**

Ring mod produces sum and difference frequencies:
```
fc = 10 kHz, fin = 15 kHz
→ sum = 25 kHz, difference = 5 kHz
```

At 48 kHz sample rate, 25 kHz aliases to 23 kHz (48-25).
At 96 kHz sample rate (2x oversample), 25 kHz is properly captured, then filtered before downsampling.

**Aliasing reduction:** ~40 dB with 2x oversampling

### Post-Processing Filters

```cpp
// From: src/common/dsp/effects/RingModulatorEffect.cpp:210-221
hp.coeff_HP(hp.calc_omega(*pd_float[rm_lowcut] / 12.0), 0.707);
lp.coeff_LP2B(lp.calc_omega(*pd_float[rm_highcut] / 12.0), 0.707);

if (!fxdata->p[rm_highcut].deactivated)
    lp.process_block(wetL, wetR);

if (!fxdata->p[rm_lowcut].deactivated)
    hp.process_block(wetL, wetR);
```

**Purpose:**
- Remove excessive low-frequency rumble from difference tones
- Tame harsh high-frequency aliasing artifacts
- Shape output spectrum for musical results

**Filter types:**
- **High-pass:** 2nd-order Butterworth (12 dB/oct), Q=0.707
- **Low-pass:** 2nd-order Butterworth (12 dB/oct), Q=0.707

## Vocoder

The **VocoderEffect** implements a classic **channel vocoder** - the technique that creates robotic voices by imposing one sound's spectral envelope onto another.

### Vocoder Principles

**Basic concept:**

1. **Modulator** (usually voice): Provides spectral envelope
2. **Carrier** (usually synth): Provides harmonic content
3. **Filter banks** analyze modulator and filter carrier
4. Result: Carrier with modulator's spectral shape

**Signal flow:**

```
Modulator ──┬─[BP1]──[ENV1]──┬─╳──[BP1]── Carrier
            ├─[BP2]──[ENV2]──┤  ╳
            ├─[BP3]──[ENV3]──┤   ╳
            ├─ ...  ─ ...  ─┤    ╳
            └─[BPn]──[ENVn]─┴────╳

             Analysis        Synthesis
            (envelope       (amplitude
             followers)      modulation)
```

### Filter Bank Design

```cpp
// From: src/common/dsp/effects/VocoderEffect.cpp:42-44
const float vocoder_freq_vsm201[n_vocoder_bands] = {
    180,  219,  266,  324,  394,  480,  584,  711,  865,  1053,
    1281, 1559, 1898, 2309, 2810, 3420, 4162, 5064, 6163, 7500
};
```

These frequencies provide:
- **Quasi-logarithmic spacing** matching critical bands
- **180-7500 Hz range** covering speech fundamentals and formants
- **20 bands** for high spectral resolution

**Dynamic frequency allocation:**

```cpp
// From: src/common/dsp/effects/VocoderEffect.cpp:90-134
float flo = limit_range(*pd_float[voc_minfreq], -36.f, 36.f);
float fhi = limit_range(*pd_float[voc_maxfreq], 0.f, 60.f);
float df = (fhi - flo) / (active_bands - 1);

float hzlo = 440.f * pow(2.f, flo / 12.f);
float dhz = pow(2.f, df / 12.f);

float fb = hzlo;
for (int i = 0; i < active_bands && i < n_vocoder_bands; i++)
{
    Freq[i & 3] = fb * storage->samplerate_inv;

    if ((i & 3) == 3)  // Every 4 bands
    {
        int j = i >> 2;
        mCarrierL[j].SetCoeff(Freq, Q, Spread);
        mModulator[j].SetCoeff(FreqM, Q, Spread);
    }

    fb *= dhz;  // Geometric spacing
}
```

**Separate modulator frequency range:**

```cpp
auto mMid = fDistHalf + flo + 0.3 * mC * fDistHalf;
auto mLo = mMid - fDistHalf * (1 + 0.7 * mX);
```

Parameters:
- **Mod Center:** Shifts modulator bands up/down
- **Mod Range:** Expands/compresses modulator band spacing

This allows:
- Gender change (shift formants up/down)
- Emphasis change (compress range for focus)
- Special effects (extreme mismatch for weirdness)

### Vectorized Processing

```cpp
// From: src/common/dsp/effects/VocoderEffect.h:88-92
VectorizedSVFilter mCarrierL alignas(16)[voc_vector_size];
VectorizedSVFilter mCarrierR alignas(16)[voc_vector_size];
VectorizedSVFilter mModulator alignas(16)[voc_vector_size];
VectorizedSVFilter mModulatorR alignas(16)[voc_vector_size];
```

**VectorizedSVFilter** processes **4 bands simultaneously** using SSE:

```cpp
class VectorizedSVFilter
{
    vFloat ic1eq[4], ic2eq[4];  // 4 parallel state variables

    vFloat CalcBPF(vFloat input)
    {
        // Processes 4 filters at once
        vFloat v0 = vSub(input, ic2eq);
        vFloat v1 = vMAdd(ic1eq, g, vMul(v0, k));
        vFloat v2 = vMAdd(ic2eq, g, v1);

        ic1eq = vMul(vAdd(v1, v1), gComp);
        ic2eq = vMul(vAdd(v2, v2), gComp);

        return v1;  // Bandpass output (4 samples)
    }
};
```

This provides **4x speedup** compared to scalar processing.

### Envelope Followers

```cpp
// From: src/common/dsp/effects/VocoderEffect.cpp:190
float EnvFRate = 0.001f * powf(2.f, 4.f * *pd_float[voc_envfollow]);
```

**Envelope following** extracts amplitude contour:

```cpp
// From: src/common/dsp/effects/VocoderEffect.cpp:268-272
vFloat Mod = mModulator[j].CalcBPF(In);
Mod = vMin(vMul(Mod, Mod), MaxLevel);            // Square (full-wave rectify)
Mod = vAnd(Mod, vCmpGE(Mod, GateLevel));         // Gate out noise
mEnvF[j] = vMAdd(mEnvF[j], Ratem1, vMul(Rate, Mod));  // Smooth
Mod = vSqrtFast(mEnvF[j]);                       // Back to linear
```

**Process breakdown:**

1. **Filter modulator:** Extract energy in band
2. **Square:** Full-wave rectification (|x|²)
3. **Gate:** Remove signals below threshold
4. **Smooth:** Low-pass filter (exponential averaging)
5. **Square root:** Convert power back to amplitude

**Time constant control:**

```cpp
EnvFRate = 0.001f * powf(2.f, 4.f * parameter);  // 0.001 to 16
```

| Parameter | Rate | Time Constant | Character |
|-----------|------|---------------|-----------|
| 0% | 0.001 | ~1000 samples | Slow, smooth |
| 25% | 0.002 | ~500 samples | Moderate |
| 50% | 0.063 | ~16 samples | Fast |
| 75% | 2.0 | <1 sample | Very fast |
| 100% | 16.0 | Instant | No smoothing |

Faster tracking preserves transients (consonants in speech); slower tracking creates smoother, more musical results.

### Input Gating

```cpp
// From: src/common/dsp/effects/VocoderEffect.cpp:217-218
float Gate = storage->db_to_linear(*pd_float[voc_input_gate] + Gain);
vFloat GateLevel = vLoad1(Gate * Gate);
```

**Purpose:** Suppress noise floor in quiet sections

```cpp
Mod = vAnd(Mod, vCmpGE(Mod, GateLevel));
```

This uses SIMD comparison to zero out bands below gate threshold:
```
If Mod >= GateLevel: Keep Mod
If Mod < GateLevel:  Set to 0
```

**Dynamic range improvement:**
- Without gate: -40 dB noise floor
- With -40 dB gate: -80 dB effective noise floor

### Stereo Modes

```cpp
// From: src/common/dsp/effects/VocoderEffect.h:40-45
enum vocoder_input_modes
{
    vim_mono,    // Sum L+R modulator
    vim_left,    // Use only left modulator
    vim_right,   // Use only right modulator
    vim_stereo,  // Independent L/R processing
};
```

**Mono mode** (most common):

```cpp
// From: src/common/dsp/effects/VocoderEffect.cpp:196-199
if (modulator_mode == vim_mono)
{
    mech::add_block<BLOCK_SIZE>(storage->audio_in_nonOS[0],
                                storage->audio_in_nonOS[1],
                                modulator_in);
}
```

Sums L+R modulator channels, applies same envelope to both carrier channels.

**Stereo mode:**

```cpp
// From: src/common/dsp/effects/VocoderEffect.cpp:284-316
vFloat ModL = mModulator[j].CalcBPF(InL);
vFloat ModR = mModulatorR[j].CalcBPF(InR);

mEnvF[j] = vMAdd(mEnvF[j], Ratem1, vMul(Rate, ModL));
mEnvFR[j] = vMAdd(mEnvFR[j], Ratem1, vMul(Rate, ModR));

LeftSum = vAdd(LeftSum, mCarrierL[j].CalcBPF(vMul(Left, ModL)));
RightSum = vAdd(RightSum, mCarrierR[j].CalcBPF(vMul(Right, ModR)));
```

Independent L/R envelope followers preserve stereo imaging from modulator.

**Musical applications:**

1. **Robot voices:** Carrier = saw wave, Modulator = speech
2. **Talking synth:** Carrier = chord, Modulator = voice
3. **Rhythmic texture:** Carrier = pad, Modulator = drums
4. **Formant shifting:** Adjust Mod Center to change perceived gender
5. **Harmonic vocoding:** Carrier = input, creates resonant filtering

## Exciter

The **ExciterEffect** implements **harmonic exciter** processing - adding harmonically-related content to enhance presence and clarity without simply boosting EQ.

### Exciter Principles

**Problem:** Simple EQ boosts noise along with signal
**Solution:** Generate new harmonics correlated with signal

**Psychoacoustic basis:**

Human hearing perceives pitch primarily from fundamental, but timbral **brightness** and **presence** come from harmonic content. An exciter:
1. Filters input to target frequency range
2. Generates harmonics through nonlinearity
3. Mixes generated harmonics back with dry signal

**Compared to distortion:**
- Distortion: Processes full spectrum (can muddy lows)
- Exciter: Processes only highs (preserves clean lows)

### Implementation Architecture

```cpp
// From: src/common/dsp/effects/chowdsp/ExciterEffect.cpp:60-79
void ExciterEffect::process(float *dataL, float *dataR)
{
    set_params();

    // Save dry signal
    mech::copy_from_to<BLOCK_SIZE>(dataL, dryL);
    mech::copy_from_to<BLOCK_SIZE>(dataR, dryR);

    // Apply drive
    drive_gain.multiply_2_blocks(dataL, dataR, BLOCK_SIZE_QUAD);

    // Oversample
    os.upsample(dataL, dataR);

    // Process at 2x rate
    for (int k = 0; k < os.getUpBlockSize(); k++)
        process_sample(os.leftUp[k], os.rightUp[k]);

    // Downsample
    os.downsample(dataL, dataR);

    // Parallel mix
    wet_gain.multiply_2_blocks(dataL, dataR, BLOCK_SIZE_QUAD);
    mech::add_block<BLOCK_SIZE>(dataL, dryL);
    mech::add_block<BLOCK_SIZE>(dataR, dryR);
}
```

**Signal flow:**

```
                      ┌─ Dry ────────────────┐
                      │                       │
Input ── Drive ── Upsample ── Filter ── NL ──┼── Downsample ── Mix ── Output
                                              │
                                         Wet Gain
```

### Tone Filter

```cpp
// From: src/common/dsp/effects/chowdsp/ExciterEffect.cpp:85-88
auto cutoff = low_freq * std::pow(high_freq / low_freq, clamp01(*pd_float[exciter_tone]));
cutoff = limit_range(cutoff, 10.0, storage->samplerate * 0.48);
auto omega_factor = storage->samplerate_inv * 2.0 * M_PI / (double)os.getOSRatio();
toneFilter.coeff_HP(cutoff * omega_factor, q_val);
```

**Frequency range:**
- low_freq = 500 Hz
- high_freq = 10,000 Hz
- Tone parameter maps exponentially between them

**Example cutoffs:**

| Tone | Cutoff | Effect |
|------|--------|--------|
| 0% | 500 Hz | Wide range, warmer |
| 25% | 1122 Hz | Upper mids |
| 50% | 2518 Hz | Presence |
| 75% | 5649 Hz | High clarity |
| 100% | 10 kHz | Air, brilliance |

**Q = 0.7071** (Butterworth): Maximally flat passband, gentle rolloff

The high-pass filter removes low frequencies before nonlinearity, preventing:
- Intermodulation distortion with bass
- Mud in midrange
- Wasted processing on inaudible sub-harmonics

### Nonlinearity and Level Detection

```cpp
// From: src/common/dsp/effects/chowdsp/ExciterEffect.h:71-78
inline void process_sample(float &l, float &r)
{
    toneFilter.process_sample(l, r, l, r);
    auto levelL = levelDetector.process_sample(l, 0);
    auto levelR = levelDetector.process_sample(r, 0);
    l = std::tanh(l) * levelL;
    r = std::tanh(r) * levelR;
}
```

**Tanh saturation:**

```
       1 ┤     ╭─────
         │   ╱
         │ ╱
    ───0─┼╱─────────
         │ ╲
        -1 ┤   ╲
         │     ╰─────
```

Properties:
- **Soft clipping:** Smooth transition to saturation
- **Odd harmonics:** tanh(x) ≈ x - x³/3 + x⁵/15 - ...
- **Bounded output:** Never exceeds ±1

**Harmonic generation:**

For input `x = A·sin(ωt)`:
```
tanh(x) ≈ x - x³/3
       ≈ A·sin(ωt) - (A³/3)·sin³(ωt)
       ≈ A·sin(ωt) - (A³/12)·sin(3ωt) + ...
                     └── 3rd harmonic ──┘
```

Higher drive → larger A → more harmonics.

### Level Detection

**Purpose:** Prevent pumping/breathing artifacts

Without level detection:
```
Loud signal → Heavy saturation → Low output (compressed)
Quiet signal → Light saturation → Proportional output
Result: Unnatural dynamics
```

With level detection:
```cpp
// Pseudo-code for level detector
envelope = attack/release_filter(abs(input));
gain = 1.0 / max(envelope, threshold);
output = saturate(input) * gain;
```

**Implementation:**

```cpp
// From: src/common/dsp/effects/chowdsp/ExciterEffect.cpp:96-104
auto attack_ms = std::pow(2.0f, fxdata->p[exciter_att].displayInfo.b *
                         *pd_float[exciter_att]);
auto release_ms = 10.0f * std::pow(2.0f, fxdata->p[exciter_rel].displayInfo.b *
                                   *pd_float[exciter_rel]);

attack_ms = limit_range(attack_ms, 2.5f, 40.0f);
release_ms = limit_range(release_ms, 25.0f, 400.0f);

levelDetector.set_attack_time(attack_ms);
levelDetector.set_release_time(release_ms);
```

**Attack/release ranges:**
- Attack: 2.5 - 40 ms
- Release: 25 - 400 ms

Fast attack preserves transients; slower release provides smooth gain recovery.

**Effect on harmonics:**

The level detector creates **dynamic harmonic generation**:
- Loud passages: More saturation, richer harmonics, but normalized level
- Quiet passages: Less saturation, cleaner tone
- Maintains consistent loudness while varying harmonic content

### Drive and Makeup Gain

```cpp
// From: src/common/dsp/effects/chowdsp/ExciterEffect.cpp:91-93
auto drive_makeup = std::pow(0.2f, 1.f - clamp01(*pd_float[exciter_tone]));
auto drive = 8.f * std::pow(clamp01(*pd_float[exciter_drive]), 1.5f) * drive_makeup;
drive_gain.set_target_smoothed(drive);
```

**Drive scaling:**
- Base: 8× maximum drive
- Exponent 1.5: Emphasizes lower drive values (finer control)
- Makeup gain: Compensates for tone filter attenuation

**Makeup calculation:**

```cpp
drive_makeup = pow(0.2, 1 - tone)
```

| Tone | Makeup | Reason |
|------|--------|--------|
| 0% (500 Hz) | 0.2× | Much signal passes filter → reduce |
| 50% (2.5 kHz) | 0.45× | Moderate |
| 100% (10 kHz) | 1.0× | Little signal passes → boost |

This provides **perceptually consistent drive** across tone settings.

### Oversampling

```cpp
// From: src/common/dsp/effects/chowdsp/ExciterEffect.h:80
Oversampling<1, BLOCK_SIZE> os;
```

**Why oversample?**

Tanh nonlinearity generates harmonics that can alias:

```
Input:    8 kHz fundamental
Tanh 3rd: 24 kHz (would alias to 24 kHz at 48 kHz SR)

At 2x (96 kHz):  24 kHz properly captured
After downsample: Anti-alias filter removes >24 kHz
Result: Clean 3rd harmonic without aliasing
```

**2x oversampling** reduces aliasing by ~40 dB - sufficient for most musical applications.

### Musical Applications

**Typical uses:**

1. **Vocal presence:** Tone 40-60%, Drive 30%, Mix 30%
   - Adds clarity and intelligibility
   - Cuts through dense mixes

2. **Bass definition:** Tone 20-30%, Drive 40%, Mix 20%
   - Adds harmonic content audible on small speakers
   - Preserves low-end punch

3. **Acoustic guitar air:** Tone 70-90%, Drive 25%, Mix 25%
   - Enhances string detail
   - Adds studio sheen

4. **Synthesizer bite:** Tone 50-70%, Drive 50%, Mix 40%
   - Adds edge to pads
   - Increases perceived brightness

**Comparison to EQ:**

| Technique | Pros | Cons |
|-----------|------|------|
| EQ Boost | Simple, predictable | Boosts noise, narrow band |
| Exciter | Adds harmonics, dynamic | More complex, can sound artificial |

**Best practice:** Use both - exciter for harmonic generation, EQ for final spectral shaping.

## Advanced Topics

### FFT-Based Processing

While Surge's frequency effects use **filter banks** (parallel IIR), **FFT-based** processing offers different tradeoffs:

**Filter bank approach (Surge):**
- Pro: Low latency (no window delay)
- Pro: Real-time coefficient updates
- Pro: Minimum-phase response (musical)
- Con: Limited frequency resolution
- Con: Fixed bands (less flexible)

**FFT approach:**
- Pro: Arbitrary frequency resolution
- Pro: Linear-phase possible
- Pro: Efficient for many bands (N·log(N))
- Con: Latency from window size
- Con: Block-based (harder to modulate)
- Con: Spectral leakage artifacts

**When to use FFT:**
- Graphic EQs with 30+ bands
- Spectral compression/expansion
- Precise notch filtering
- Scientific analysis

**When to use filter banks:**
- Vocoders (musical phase response)
- Real-time control (no latency)
- Moderate band counts (<20)
- Standard audio effects

### Phase Linearity Considerations

All IIR filters introduce **phase distortion**:

```cpp
// Biquad phase response
phase(f) = atan2(b1·sin(ω) + b2·sin(2ω),
                 b0 + b1·cos(ω) + b2·cos(2ω))
         - atan2(a1·sin(ω) + a2·sin(2ω),
                 1 + a1·cos(ω) + a2·cos(2ω))
```

**Effects of phase distortion:**

1. **Transient smearing:** Different frequencies delayed differently
2. **Pre-ringing:** High-Q filters "predict" transients
3. **Stereo imaging:** L/R phase differences affect localization

**Mitigation strategies:**

1. **Low Q:** Broader filters have less phase shift
   - Surge's graphic EQ uses Q=0.5 (gentle)

2. **Moderate boost/cut:** Extreme gain increases phase shift
   - Limit adjustments to ±12 dB

3. **Serial order:** Process low to high frequency
   - Minimizes phase accumulation effects

**Linear-phase alternative:**

FIR filters can be linear-phase but require:
- Much higher order (100s of taps vs. 2nd-order IIR)
- Latency (half filter length)
- Higher CPU usage

Surge prioritizes **zero latency** over linear phase for musical applications.

### Frequency Shifter vs. Pitch Shifter

**Fundamental difference:**

```
Frequency Shifter: f_out = f_in + shift  (additive)
Pitch Shifter:     f_out = f_in × ratio  (multiplicative)
```

**Harmonic series example:**

```
Input:     100, 200, 300, 400, 500 Hz

+50 Hz shift:  150, 250, 350, 450, 550 Hz (inharmonic!)
×1.5 pitch:    150, 300, 450, 600, 750 Hz (harmonic)
```

**When to use each:**

| Task | Use | Reason |
|------|-----|--------|
| Transpose melody | Pitch shifter | Preserves harmonic relationships |
| Detune chorusing | Pitch shifter | Musical intervals |
| Create dissonance | Frequency shifter | Destroys harmonics |
| Barber-pole effect | Frequency shifter | Continuous rise/fall |
| Bell/metallic sounds | Frequency shifter | Inharmonic spectra |

**Combined use:**

```
Input ── Pitch Shift (×1.5) ── Frequency Shift (+7 Hz) ── Output
         └── harmonically shifted ──┘  └── slightly detuned ──┘
```

Creates ensemble effect with tuned harmonics but slight beating.

### Vocoder Band Count Optimization

**Perceptual considerations:**

Human hearing has ~24 **critical bands** (Bark scale), but vocoder quality vs. CPU is a tradeoff:

| Bands | CPU | Intelligibility | Character |
|-------|-----|-----------------|-----------|
| 4-8 | Low | Poor | Robotic, harsh |
| 10-16 | Medium | Good | Classic vocoder |
| 20+ | High | Excellent | Natural, detailed |

**Surge's choice:** 20 bands (adjustable down) balances quality and performance.

**SIMD advantage:**

Processing 4 bands simultaneously means:
- 4 bands: 1 SIMD operation
- 8 bands: 2 SIMD operations
- 20 bands: 5 SIMD operations

**Optimal counts:** 4, 8, 12, 16, 20 (multiples of 4 for SSE)

**Variable band count:**

```cpp
active_bands = *pd_int[voc_num_bands];
active_bands = active_bands - (active_bands % 4);  // Round down to multiple of 4
```

User can reduce band count for:
- Lower CPU usage
- Vintage lo-fi vocoder sound
- Artistic effect (coarser spectral resolution)

## Conclusion

Surge XT's frequency-domain effects demonstrate sophisticated DSP engineering:

1. **Equalizers:** Efficient biquad cascades with deactivatable bands
2. **Frequency Shifter:** True SSB modulation via Hilbert transforms
3. **Ring Modulator:** Physical diode modeling with oversampling
4. **Vocoder:** 20-band SIMD filter banks with flexible routing
5. **Exciter:** Level-detected harmonic enhancement with oversampling

**Common themes:**

- **SIMD optimization:** All effects use SSE2 for 4x speedup
- **Oversampling:** Nonlinear effects use 2x to prevent aliasing
- **Control rate:** Coefficient updates at 1/8 sample rate saves CPU
- **Deactivation:** Unused bands/parameters bypass processing
- **Musical focus:** Phase response, gain staging favor musicality

**Performance characteristics:**

| Effect | CPU (relative) | Latency | Main Use |
|--------|----------------|---------|----------|
| Graphic EQ | Low | None | Quick tonal shaping |
| Parametric EQ | Low | None | Surgical correction |
| Freq Shifter | Medium | ~6 samples | Detuning, special FX |
| Ring Modulator | Medium | ~32 samples | Metallic timbres |
| Vocoder | High | None | Robotic voices |
| Exciter | Medium | ~16 samples | Harmonic enhancement |

These frequency-domain tools, combined with Surge's time-based and distortion effects, provide comprehensive spectral manipulation capabilities - from transparent correction to radical transformation.

---

**Next: [Chapter 17: Distortion and Waveshaping Effects](17-effects-distortion.md)**
**See Also: [Chapter 12: Effects Architecture](12-effects-architecture.md), [Chapter 13: Time-Based Effects](13-effects-time-based.md)**
**References:**
- Zölzer, U. (2011). *DAFX: Digital Audio Effects*. Wiley. (Vocoder, SSB modulation)
- Pirkle, W. (2019). *Designing Audio Effect Plugins in C++*. Focal Press. (Biquad filters)
- Smith, J.O. (2007). *Introduction to Digital Filters*. W3K Publishing. (Phase response, Hilbert transforms)
- https://jatinchowdhury18.medium.com/complex-nonlinearities-episode-2-harmonic-exciter-cd883d888a43 (Exciter design)
