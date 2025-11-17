# Chapter 11: Filter Implementation

## From Theory to Silicon: Building High-Performance Filters

In **[Chapter 10](10-filter-theory.md)**, we explored the mathematical foundations of digital filtering. Now we examine how Surge implements these theories in high-performance C++ code that processes 64 voices simultaneously with minimal CPU usage.

Surge's filter architecture balances competing demands:
- **Performance**: SIMD processing of multiple voices
- **Quality**: Pristine audio fidelity
- **Flexibility**: 30+ distinct filter types
- **Modulatability**: Smooth parameter changes every sample

The solution is a sophisticated architecture built around **SIMD parallelism**, where four voices process simultaneously using SSE2 vector instructions.

## Part 1: QuadFilterChain Architecture

### SIMD: Processing Four Voices at Once

The core insight: instead of processing voices sequentially, pack four voices into 128-bit SSE registers and process them simultaneously:

```
Sequential:  Voice 1 → Voice 2 → Voice 3 → Voice 4  (16 cycles)
SIMD:       Voices [1,2,3,4] together              (4 cycles)
```

This 4× speedup enables Surge's impressive polyphony.

### QuadFilterChainState: The Voice Container

Every group of up to 4 voices shares a `QuadFilterChainState`:

```cpp
// From: src/common/dsp/QuadFilterChain.h
struct QuadFilterChainState
{
    // Filter units: 4 total (2 per channel for stereo)
    sst::filters::QuadFilterUnitState FU[4];

    // Waveshaper states: 2 (one per channel)
    sst::waveshapers::QuadWaveshaperState WSS[2];

    // Configuration parameters (SIMD vectors - 4 floats each)
    SIMD_M128 Gain, FB, Mix1, Mix2, Drive;
    SIMD_M128 dGain, dFB, dMix1, dMix2, dDrive;  // Derivatives

    // Feedback state
    SIMD_M128 wsLPF, FBlineL, FBlineR;

    // Audio data buffers (oversampled)
    SIMD_M128 DL[BLOCK_SIZE_OS], DR[BLOCK_SIZE_OS];

    // Output accumulators
    SIMD_M128 OutL, OutR, dOutL, dOutR;
    SIMD_M128 Out2L, Out2R, dOut2L, dOut2R;  // Stereo mode
};
```

**Key points:**
- Every parameter is `SIMD_M128` (`__m128`) - 4 floats
- Derivatives enable smooth interpolation
- Four filter units support stereo operation

### Filter Topologies

Surge supports eight routing topologies:

```cpp
enum FilterConfiguration
{
    fc_serial1,  // F1 → WS → F2 (no feedback)
    fc_serial2,  // F1 → WS → F2 (with feedback)
    fc_serial3,  // F1 → WS, F2 in feedback only
    fc_dual1,    // (F1 + F2) → WS
    fc_dual2,    // F1 → WS, F2 parallel
    fc_ring,     // (F1 × F2) → WS (ring mod)
    fc_stereo,   // F1 left, F2 right
    fc_wide      // Stereo with independent feedback
};
```

**Serial 1 implementation:**

```cpp
// From: src/common/dsp/QuadFilterChain.cpp
template <int config, bool A, bool WS, bool B>
void ProcessFBQuad(QuadFilterChainState &d, fbq_global &g,
                   float *OutL, float *OutR)
{
    const auto one = SIMD_MM(set1_ps)(1.0f);

    for (int k = 0; k < BLOCK_SIZE_OS; k++)
    {
        auto input = d.DL[k];
        auto x = input;
        auto mask = SIMD_MM(load_ps)((float *)&d.FU[0].active);

        if (A)
            x = g.FU1ptr(&d.FU[0], x);  // Filter 1

        if (WS)
        {
            d.Drive = SIMD_MM(add_ps)(d.Drive, d.dDrive);
            x = g.WSptr(&d.WSS[0], x, d.Drive);  // Waveshaper
        }

        if (A || WS)
        {
            d.Mix1 = SIMD_MM(add_ps)(d.Mix1, d.dMix1);
            x = SIMD_MM(add_ps)(
                SIMD_MM(mul_ps)(input, SIMD_MM(sub_ps)(one, d.Mix1)),
                SIMD_MM(mul_ps)(x, d.Mix1)
            );
        }

        if (B)
            x = g.FU2ptr(&d.FU[1], x);  // Filter 2

        d.Gain = SIMD_MM(add_ps)(d.Gain, d.dGain);
        auto out = SIMD_MM(and_ps)(mask, SIMD_MM(mul_ps)(x, d.Gain));

        // Accumulate to output
        MWriteOutputs(out)
    }
}
```

### Template Specialization for Performance

The compiler generates 64 versions (8 configs × 2^3 enable states), eliminating runtime branches:

```cpp
template <int config> FBQFPtr GetFBQPointer2(bool A, bool WS, bool B)
{
    if (A)
    {
        if (B)
            return WS ? ProcessFBQuad<config,1,1,1> : ProcessFBQuad<config,1,0,1>;
        else
            return WS ? ProcessFBQuad<config,1,1,0> : ProcessFBQuad<config,1,0,0>;
    }
    else
    {
        if (B)
            return WS ? ProcessFBQuad<config,0,1,1> : ProcessFBQuad<config,0,0,1>;
        else
            return WS ? ProcessFBQuad<config,0,1,0> : ProcessFBQuad<config,0,0,0>;
    }
}
```

**Why this matters:**

Traditional runtime branching:
```cpp
if (filterAEnabled) { /* code */ }  // Branch prediction, pipeline flush
```

Template specialization at compile-time:
```cpp
template <bool A>
void process() {
    if (A) { /* code */ }  // Compiler completely removes this block if A=false
}
```

The result: **zero-cost abstraction** - the generated assembly is identical to hand-writing each configuration separately.

### Feedback and Feedback Lines

The feedback mechanism deserves special attention. In `fc_serial2` and beyond:

```cpp
case fc_serial2:
    for (int k = 0; k < BLOCK_SIZE_OS; k++)
    {
        d.FB = SIMD_MM(add_ps)(d.FB, d.dFB);  // Interpolate feedback amount

        // Soft-clip feedback to prevent instability
        auto input = vMul(d.FB, d.FBlineL);
        input = vAdd(d.DL[k], sdsp::softclip_ps(input));

        // ... process filters ...

        d.FBlineL = out;  // Store for next sample
    }
    break;
```

**Soft clipping** is crucial - without it, high resonance would cause the filter to explode into infinity. The soft clipper function:

```cpp
inline SIMD_M128 softclip_ps(SIMD_M128 x)
{
    // Approximation of tanh(x) for soft saturation
    // Fast rational polynomial approximation
    auto x2 = _mm_mul_ps(x, x);
    auto x3 = _mm_mul_ps(x2, x);
    return _mm_div_ps(x3, _mm_add_ps(_mm_set1_ps(3.0f), x2));
}
```

This creates the characteristic "self-oscillation" when resonance approaches maximum - the filter rings at its cutoff frequency even with no input.

### Voice Masking

The `active` mask determines which voices are playing:

```cpp
auto mask = SIMD_MM(load_ps)((float *)&d.FU[0].active);
auto out = SIMD_MM(and_ps)(mask, SIMD_MM(mul_ps)(x, d.Gain));
```

If only voices 0 and 2 are active:
```
mask = [0xFFFFFFFF, 0x00000000, 0xFFFFFFFF, 0x00000000]
out  = [voice0_out,  0.0,        voice2_out,  0.0]
```

This prevents inactive voices from contaminating the output with denormals or stale state.

## Part 2: SST Filters Library

### Library Integration

Filter implementations live in `libs/sst/sst-filters`, providing:
- Code reuse across SST projects
- Independent testing
- Clear API boundaries

```cpp
// Integration
#include "sst/filters.h"

namespace sst::filters
{
    struct QuadFilterUnitState
    {
        SIMD_M128 C[n_cm_coeffs];   // Coefficients (usually 8)
        SIMD_M128 R[n_filter_regs]; // State registers (8-16)
        unsigned int active[4];      // Active voice mask
        int subtype;
        void *extraState;
    };
}
```

**Coefficient registers (C[])**: Filter parameters calculated per-block
**State registers (R[])**: Internal state updated per-sample

### FilterCoefficientMaker: The Coefficient Engine

The `FilterCoefficientMaker` is the bridge between user-facing parameters (cutoff frequency in Hz, resonance 0-1) and the mathematical coefficients filters need. It's called at most once per block (typically 32 or 64 samples) when parameters change.

```cpp
// Conceptual interface (actual implementation in sst-filters)
template <typename Storage>
class FilterCoefficientMaker
{
public:
    void MakeCoeffs(float cutoff, float resonance, int type, int subtype,
                   SurgeStorage *storage, QuadFilterUnitState *state);

    // Direct coefficient setting (for simple cases)
    void FromDirect(float b0, float b1, float b2, float a1, float a2);

    // Reset state
    void Reset();

    // Coefficient storage (broadcast to all 4 voices)
    SIMD_M128 C[n_cm_coeffs];  // Usually 8 coefficients
};
```

**Typical coefficient calculation flow:**

```cpp
void MakeCoeffs(float cutoff, float resonance, int type, int subtype,
               SurgeStorage *storage, QuadFilterUnitState *state)
{
    switch (type)
    {
    case fut_lp12:  // 12dB lowpass
        {
            // Convert cutoff parameter (0-127) to frequency (Hz)
            float cutoff_hz = 440.0f * pow(2.0f, (cutoff - 69.0f) / 12.0f);

            // Nyquist limiting
            cutoff_hz = std::min(cutoff_hz, storage->samplerate * 0.49f);

            // Calculate normalized angular frequency
            float omega = 2.0f * M_PI * cutoff_hz / storage->samplerate;

            // Bilinear transform for biquad
            float K = tan(omega / 2.0f);
            float Q = std::max(0.5f, resonance * 20.0f);  // Map 0-1 to 0.5-20
            float norm = 1.0f / (1.0f + K / Q + K * K);

            // Calculate biquad coefficients
            float b0 = K * K * norm;
            float b1 = 2.0f * K * K * norm;
            float b2 = K * K * norm;
            float a1 = 2.0f * (K * K - 1.0f) * norm;
            float a2 = (1.0f - K / Q + K * K) * norm;

            // Broadcast to all 4 voices
            state->C[0] = SIMD_MM(set1_ps)(b0);
            state->C[1] = SIMD_MM(set1_ps)(b1);
            state->C[2] = SIMD_MM(set1_ps)(b2);
            state->C[3] = SIMD_MM(set1_ps)(a1);
            state->C[4] = SIMD_MM(set1_ps)(a2);
        }
        break;

    case fut_lpmoog:  // Moog ladder
        {
            // Different calculation for ladder filters
            float cutoff_hz = 440.0f * pow(2.0f, (cutoff - 69.0f) / 12.0f);
            float omega = 2.0f * M_PI * cutoff_hz / storage->samplerate;
            float g = tan(omega / 2.0f);  // One-pole coefficient

            // Resonance compensation
            float k = resonance * 4.0f;  // 0-4 range

            state->C[0] = SIMD_MM(set1_ps)(g);
            state->C[1] = SIMD_MM(set1_ps)(k);
            state->C[2] = SIMD_MM(set1_ps)(getCompensation(g, k));
        }
        break;

    // ... 30+ other filter types ...
    }
}
```

**Key design decisions:**

1. **Broadcast coefficients**: Since all 4 voices use the same filter type, coefficients are identical across lanes: `set1_ps(value)` replicates to all 4 floats

2. **Expensive math once**: `tan()`, `pow()`, divisions happen once per block, not per sample

3. **Smooth interpolation**: The voice processing loop interpolates between old and new coefficients to avoid zipper noise

**Per-Voice Coefficient Variation:**

Some filters allow per-voice coefficient variation (e.g., for keytracking):

```cpp
// Example: Per-voice cutoff based on note pitch
void MakeCoeffsWithKeytrack(float baseCutoff[4], float resonance, ...)
{
    float omega[4];
    for (int v = 0; v < 4; v++)
    {
        float cutoff_hz = 440.0f * pow(2.0f, (baseCutoff[v] - 69.0f) / 12.0f);
        omega[v] = calculateOmega(cutoff_hz);
    }

    // Load per-voice coefficients
    state->C[0] = SIMD_MM(set_ps)(omega[3], omega[2], omega[1], omega[0]);
    // Note: set_ps() takes arguments in reverse order!
}
```

### Filter Type Registry

```cpp
namespace sst::filters
{
    enum FilterType
    {
        fut_none = 0,

        // Lowpass
        fut_lp12, fut_lp24, fut_lpmoog, fut_vintageladder,
        fut_k35_lp, fut_diode, fut_obxd_4pole,

        // Bandpass
        fut_bp12, fut_bp24,

        // Highpass
        fut_hp12, fut_hp24, fut_k35_hp,

        // Notch
        fut_notch12, fut_notch24,

        // Multi-mode
        fut_cytomic_svf, fut_tripole,

        // Effects
        fut_apf, fut_comb_pos, fut_comb_neg, fut_SNH,

        num_filter_types
    };
}
```

## Part 3: Biquad Implementation

### The Biquad: Foundation of IIR Filtering

Transfer function:
```
H(z) = (b0 + b1·z⁻¹ + b2·z⁻²) / (1 + a1·z⁻¹ + a2·z⁻²)
```

Difference equation:
```
y[n] = b0·x[n] + b1·x[n-1] + b2·x[n-2] - a1·y[n-1] - a2·y[n-2]
```

### Direct Form II Transposed

```cpp
// More efficient than Direct Form I
float process_DF2T(float input)
{
    float output = b0 * input + reg0;
    reg0 = b1 * input - a1 * output + reg1;
    reg1 = b2 * input - a2 * output;
    return output;
}
```

**Advantages:**
- Only 2 state registers (vs. 4 for DF1)
- Better numerical properties
- Easier coefficient modulation

### Coefficient Calculation

```cpp
void BiquadFilter::coeff_LP(float cutoff_hz, float Q)
{
    float omega = 2.0f * M_PI * cutoff_hz / sampleRate;
    float sin_omega = sin(omega);
    float cos_omega = cos(omega);
    float alpha = sin_omega / (2.0f * Q);

    // RBJ cookbook formulas
    float a0 = 1.0f + alpha;
    b0 = ((1.0f - cos_omega) / 2.0f) / a0;
    b1 = (1.0f - cos_omega) / a0;
    b2 = ((1.0f - cos_omega) / 2.0f) / a0;
    a1 = (-2.0f * cos_omega) / a0;
    a2 = (1.0f - alpha) / a0;
}
```

### Smooth Modulation

```cpp
void process_block_to(float *data, float target_cutoff, float target_Q)
{
    // Calculate target coefficients
    calculateCoeffs(target_cutoff, target_Q, /* ... */);

    // Per-sample increments for interpolation
    float da1 = (target_a1 - a1) / BLOCK_SIZE;
    float db0 = (target_b0 - b0) / BLOCK_SIZE;
    // ... etc

    for (int i = 0; i < BLOCK_SIZE; i++)
    {
        a1 += da1; b0 += db0;  // Interpolate

        float output = b0 * data[i] + reg0;
        reg0 = b1 * data[i] - a1 * output + reg1;
        reg1 = b2 * data[i] - a2 * output;

        data[i] = output;
    }
}
```

This eliminates zipper noise from parameter changes.

## Part 4: State Variable Filters

### Chamberlin SVF

Computes LP, BP, HP simultaneously:

```
highpass = input - Q * bandpass - lowpass
bandpass = F * highpass + bandpass_prev
lowpass  = F * bandpass + lowpass_prev
```

Where `F = 2 * sin(π * fc / fs)`

### VectorizedSVFilter

```cpp
// From: src/common/dsp/filters/VectorizedSVFilter.h
class VectorizedSVFilter
{
    inline vFloat CalcBPF(vFloat In)
    {
        // Stage 1
        L1 = vMAdd(F1, B1, L1);
        vFloat H1 = vNMSub(Q, B1, vSub(vMul(In, Q), L1));
        B1 = vMAdd(F1, H1, B1);

        // Stage 2 (cascade)
        L2 = vMAdd(F2, B2, L2);
        vFloat H2 = vNMSub(Q, B2, vSub(vMul(B1, Q), L2));
        B2 = vMAdd(F2, H2, B2);

        return B2;
    }

private:
    vFloat L1, B1, L2, B2;  // State
    vFloat F1, F2, Q;       // Coefficients
};
```

**Features:**
- Cascaded for 4-pole response
- SIMD processes 4 channels
- Fused multiply-add operations

### Cytomic SVF: Topology-Preserving Transform

Solves frequency warping with pre-warping:

```cpp
float g = tan(M_PI * cutoff / sampleRate);  // Pre-warped
float k = 1.0f / Q;

// Process
float v1 = (ic1eq + g * (input - ic2eq)) / (1.0f + g * (g + k));
float v2 = ic2eq + g * v1;

ic1eq = 2.0f * v1 - ic1eq;  // Update state
ic2eq = 2.0f * v2 - ic2eq;

lowpass  = v2;
bandpass = v1;
highpass = input - k * v1 - v2;
```

Accurate frequency response up to Nyquist.

## Part 5: Ladder Filters

### The Moog Ladder

Four cascaded one-pole stages with global feedback:

```
Input → ⊕ → [Pole1] → [Pole2] → [Pole3] → [Pole4] → Output
        ↑                                              ↓
        └──────────── Feedback ←────────────────────┘
```

### Digital Implementation

```cpp
SIMD_M128 processLadder(QuadFilterUnitState *state, SIMD_M128 input)
{
    auto g = state->C[0];     // Frequency
    auto k = state->C[1];     // Resonance

    auto s1 = state->R[0];    // Stage states
    auto s2 = state->R[1];
    auto s3 = state->R[2];
    auto s4 = state->R[3];

    // Feedback
    auto fb = vMul(k, s4);
    auto x = vSub(input, fb);
    x = softclip_ps(x);  // Nonlinearity

    // Four one-pole stages
    s1 = vMAdd(g, vSub(x, s1), s1);
    s1 = softclip_ps(s1);

    s2 = vMAdd(g, vSub(s1, s2), s2);
    s2 = softclip_ps(s2);

    s3 = vMAdd(g, vSub(s2, s3), s3);
    s3 = softclip_ps(s3);

    s4 = vMAdd(g, vSub(s3, s4), s4);

    state->R[0] = s1;
    state->R[1] = s2;
    state->R[2] = s3;
    state->R[3] = s4;

    return s4;
}
```

**Key elements:**
- Global feedback creates resonance
- Per-stage saturation adds warmth
- One-pole integration: `s += F * (in - s)`

### Diode Ladder: The TB-303 Sound

The **diode ladder** (inspired by Roland TB-303) uses diodes instead of transistors, creating a different nonlinear characteristic that produces the classic "acid" sound.

**Circuit difference:**
- Moog: Transistor-based clipping (soft, smooth)
- Diode: Asymmetric diode clipping (sharper, more aggressive)

```cpp
SIMD_M128 processDiodeLadder(QuadFilterUnitState *state, SIMD_M128 input)
{
    auto g = state->C[0];     // Frequency coefficient
    auto k = state->C[1];     // Resonance
    auto gamma = state->C[2]; // Diode characteristic

    // Load state
    auto s1 = state->R[0];
    auto s2 = state->R[1];
    auto s3 = state->R[2];
    auto s4 = state->R[3];

    // Feedback with diode nonlinearity
    auto fb = vMul(k, diode_clipper(s4, gamma));
    auto u = vSub(input, fb);

    // Four stages with diode clipping at each stage
    s1 = vAdd(s1, vMul(g, diode_clipper(vSub(u, s1), gamma)));
    s2 = vAdd(s2, vMul(g, diode_clipper(vSub(s1, s2), gamma)));
    s3 = vAdd(s3, vMul(g, diode_clipper(vSub(s2, s3), gamma)));
    s4 = vAdd(s4, vMul(g, diode_clipper(vSub(s3, s4), gamma)));

    // Update state
    state->R[0] = s1;
    state->R[1] = s2;
    state->R[2] = s3;
    state->R[3] = s4;

    return s4;
}
```

**Diode clipper function:**

```cpp
inline SIMD_M128 diode_clipper(SIMD_M128 x, SIMD_M128 gamma)
{
    // Diode equation: I = Is * (exp(V/Vt) - 1)
    // Approximated with rational function for speed

    auto abs_x = _mm_andnot_ps(_mm_set1_ps(-0.0f), x);  // fabs
    auto sign = _mm_and_ps(x, _mm_set1_ps(-0.0f));       // sign bit

    // Rational approximation of diode curve
    auto numerator = _mm_mul_ps(abs_x, gamma);
    auto denominator = _mm_add_ps(_mm_set1_ps(1.0f),
                                  _mm_mul_ps(abs_x, gamma));
    auto clipped = _mm_div_ps(numerator, denominator);

    // Restore sign
    return _mm_or_ps(clipped, sign);
}
```

This creates **asymmetric clipping** - different response for positive and negative signals - which adds even harmonics and a distinctive character.

### K35 Filter: The Korg Inspiration

The **Korg 35** filter (from the MS-20 synthesizer) uses a different topology:

```cpp
SIMD_M128 processK35(QuadFilterUnitState *state, SIMD_M128 input)
{
    auto alpha = state->C[0];  // Cutoff
    auto k = state->C[1];      // Resonance

    auto lpf1 = state->R[0];
    auto lpf2 = state->R[1];

    // First stage with feedback
    auto u = vSub(input, vMul(k, lpf2));
    lpf1 = vAdd(vMul(alpha, u), vMul(vSub(_mm_set1_ps(1.0f), alpha), lpf1));
    lpf1 = fast_tanh(lpf1);  // Saturation

    // Second stage
    lpf2 = vAdd(vMul(alpha, lpf1), vMul(vSub(_mm_set1_ps(1.0f), alpha), lpf2));

    state->R[0] = lpf1;
    state->R[1] = lpf2;

    // Can output highpass, bandpass, or lowpass
    switch (subtype)
    {
    case K35_LP:
        return lpf2;
    case K35_HP:
        return vSub(input, lpf2);
    case K35_BP:
        return vSub(lpf1, lpf2);
    }
}
```

**Characteristics:**
- Only 2 poles (12dB/octave)
- Aggressive resonance with strong self-oscillation
- Distinctive "screaming" quality at high resonance

## Part 6: Adding Custom Filters

### Step-by-Step Process

From `/home/user/surge/doc/Adding a Filter.md`:

**1. Create source files** (`src/common/dsp/filters/MyFilter.h/.cpp`):

```cpp
// MyFilter.h
namespace MyFilter
{
    void makeCoefficients(FilterCoefficientMaker *cm,
                         float cutoff, float resonance,
                         int subtype, SurgeStorage *storage);

    SIMD_M128 process(QuadFilterUnitState *state, SIMD_M128 input);
}

// MyFilter.cpp
void MyFilter::makeCoefficients(/* ... */)
{
    float omega = 2.0f * M_PI * cutoff / storage->samplerate;
    cm->C[0] = _mm_set1_ps(omega);
    cm->C[1] = _mm_set1_ps(resonance);
}

SIMD_M128 MyFilter::process(QuadFilterUnitState *state, SIMD_M128 input)
{
    auto freq = state->C[0];
    auto z1 = state->R[0];

    auto output = _mm_add_ps(
        _mm_mul_ps(freq, input),
        _mm_mul_ps(_mm_sub_ps(_mm_set1_ps(1.0f), freq), z1)
    );

    state->R[0] = output;
    return output;
}
```

**2. Register in FilterConfiguration.h:**

```cpp
enum FilterType {
    // ... existing
    fut_my_filter,  // ADD AT END
};

const char *filter_menu_names[] = {
    // ... existing
    "My Filter",
};
```

**3. Wire up FilterCoefficientMaker:**

```cpp
void MakeCoeffs(/* ... */)
{
    switch (type)
    {
    case fut_my_filter:
        MyFilter::makeCoefficients(this, cutoff, resonance, subtype, storage);
        break;
    }
}
```

**4. Return process function:**

```cpp
FilterUnitQFPtr GetQFPtrFilterUnit(int type, int subtype)
{
    switch (type)
    {
    case fut_my_filter:
        return MyFilter::process;
    }
}
```

### Common Pitfalls

- **Denormals**: Use `_mm_set_flush_zero_mode()`
- **NaN/Inf**: Clamp feedback and resonance
- **Zipper noise**: Interpolate coefficients
- **Alignment**: Ensure 16-byte boundaries

### Complete Example: Simple Resonant Lowpass

```cpp
namespace SimpleLP
{
    void makeCoefficients(FilterCoefficientMaker *cm, float cutoff,
                         float reso, int, SurgeStorage *s)
    {
        float freq = 440.0f * pow(2.0f, (cutoff - 69) / 12.0f);
        float omega = freq / s->samplerate;
        float F = 2.0f * sin(M_PI * omega);

        cm->C[0] = _mm_set1_ps(F);
        cm->C[1] = _mm_set1_ps(1.0f - reso);
    }

    __m128 process(QuadFilterUnitState *state, __m128 input)
    {
        auto F = state->C[0];
        auto damp = state->C[1];
        auto lp = state->R[0];

        auto hp = _mm_sub_ps(input, lp);
        lp = _mm_add_ps(lp, _mm_mul_ps(F, _mm_mul_ps(hp, damp)));

        state->R[0] = lp;
        return lp;
    }
}
```

## Conclusion: Real-Time Excellence

Surge's filter architecture demonstrates:

1. **SIMD Parallelism**: 4 voices per instruction
2. **Template Specialization**: Zero-cost abstractions
3. **Coefficient Interpolation**: Zipper-free modulation
4. **Modular Design**: Reusable components

**Performance (approximate):**
- QuadFilterChain overhead: ~5% per voice
- Simple biquad: ~10 cycles/sample (4 voices)
- Complex ladder: ~40 cycles/sample (4 voices)

This enables 64-voice polyphony with 30+ filter types in real-time.

### Next Steps

Chapter 12 explores **[Effects Architecture](12-effects-architecture.md)**, where filters combine with other processors.

---

**Further Reading:**
- RBJ Audio EQ Cookbook
- Cytomic SVF papers: https://cytomic.com
- Intel Intrinsics Guide

**Key Files:**
- `/home/user/surge/src/common/dsp/QuadFilterChain.h` - Architecture
- `/home/user/surge/src/common/FilterConfiguration.h` - Registry
- `/home/user/surge/doc/Adding a Filter.md` - Developer guide
