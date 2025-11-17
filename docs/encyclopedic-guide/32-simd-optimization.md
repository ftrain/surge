# Chapter 32: SIMD Optimization

## The Parallel Advantage: Processing Four Voices at Once

SIMD (Single Instruction Multiple Data) is one of the foundational performance optimizations in Surge XT. By processing multiple data elements simultaneously with a single CPU instruction, Surge achieves the throughput necessary for real-time audio synthesis with potentially 64 voices, each with complex filters, oscillators, and effects.

This chapter explores how Surge uses SSE2 SIMD instructions throughout its DSP pipeline to maximize performance while maintaining code clarity through careful abstraction.

## Part 1: SIMD Fundamentals

### What is SIMD?

**SIMD (Single Instruction Multiple Data)** is a parallel computing architecture where one instruction operates on multiple data points simultaneously. Modern CPUs include specialized SIMD registers and instruction sets designed for this purpose.

**The Serial Problem:**

Traditional scalar processing handles one value at a time:

```cpp
// Scalar processing - 4 separate operations
float voice1_out = voice1_in * 0.5f;
float voice2_out = voice2_in * 0.5f;
float voice3_out = voice3_in * 0.5f;
float voice4_out = voice4_in * 0.5f;
```

This requires 4 load operations, 4 multiply operations, and 4 store operations = 12 CPU operations total.

**The SIMD Solution:**

With SIMD, we pack 4 floats into a single register and process them with one instruction:

```cpp
// SIMD processing - 1 operation for 4 values
__m128 voices_in = _mm_set_ps(voice4_in, voice3_in, voice2_in, voice1_in);
__m128 scale = _mm_set1_ps(0.5f);
__m128 voices_out = _mm_mul_ps(voices_in, scale);
```

This requires 1 load, 1 multiply, 1 store = 3 operations for the same work. The theoretical speedup is 4x for computation-bound algorithms.

### SSE2: The 128-Bit Register Set

Surge uses **SSE2** (Streaming SIMD Extensions 2) as its baseline SIMD instruction set. SSE2 was introduced with the Pentium 4 in 2001 and is guaranteed to be present on all x86-64 processors.

**SSE2 Registers:**

- **16 registers**: XMM0 through XMM15
- **128 bits wide**: Can hold 4 × 32-bit floats or 2 × 64-bit doubles
- **Alignment requirement**: Data should be 16-byte aligned for optimal performance

**Visual representation of an XMM register:**

```
┌──────────┬──────────┬──────────┬──────────┐
│  Float 3 │  Float 2 │  Float 1 │  Float 0 │  128-bit XMM register
└──────────┴──────────┴──────────┴──────────┘
   32 bits    32 bits    32 bits    32 bits
```

### Common SSE2 Intrinsics

SSE2 intrinsics are C functions that map directly to assembly instructions. The naming convention is:

```
_mm_<operation>_<type>

Examples:
_mm_add_ps    - add packed single-precision (4 floats)
_mm_mul_ps    - multiply packed single-precision
_mm_set1_ps   - set all 4 floats to one value
_mm_load_ps   - load 4 aligned floats
_mm_loadu_ps  - load 4 unaligned floats
_mm_store_ps  - store 4 aligned floats
```

**Basic Operations:**

```cpp
#include <emmintrin.h>  // SSE2 intrinsics

// Create SIMD values
__m128 a = _mm_set_ps(4.0f, 3.0f, 2.0f, 1.0f);  // Set individual values
__m128 b = _mm_set1_ps(2.0f);                    // Set all to 2.0

// Arithmetic operations
__m128 sum = _mm_add_ps(a, b);      // [6, 5, 4, 3]
__m128 product = _mm_mul_ps(a, b);  // [8, 6, 4, 2]
__m128 diff = _mm_sub_ps(a, b);     // [2, 1, 0, -1]

// Fused multiply-add: (a * b) + c
__m128 c = _mm_set1_ps(1.0f);
__m128 result = _mm_add_ps(_mm_mul_ps(a, b), c);

// Load/store from memory
float aligned_data[4] __attribute__((aligned(16))) = {1, 2, 3, 4};
__m128 loaded = _mm_load_ps(aligned_data);

float output[4] __attribute__((aligned(16)));
_mm_store_ps(output, result);
```

### Alignment Requirements

SSE2 aligned load/store instructions (`_mm_load_ps`, `_mm_store_ps`) require data to be aligned on 16-byte boundaries. Accessing unaligned data with these instructions causes a crash.

**Why alignment matters:**

1. **Performance**: Aligned loads/stores are faster on most CPUs
2. **Correctness**: Some SIMD instructions require alignment
3. **Cache efficiency**: Aligned data fits better in cache lines

**Ensuring alignment in C++:**

```cpp
// Method 1: alignas specifier (C++11)
float buffer alignas(16)[BLOCK_SIZE];

// Method 2: Compiler attribute (GCC/Clang)
float buffer[BLOCK_SIZE] __attribute__((aligned(16)));

// Method 3: For class members
class alignas(16) AlignedClass {
    float data[4];
};
```

**In Surge:**

Throughout the Surge codebase, you'll see alignment specified for DSP buffers:

```cpp
// From src/common/dsp/effects/ChorusEffectImpl.h
float tbufferL alignas(16)[BLOCK_SIZE];
float tbufferR alignas(16)[BLOCK_SIZE];
```

## Part 2: SIMD in Surge's Architecture

### The SIMD Abstraction Layer

Surge abstracts SIMD operations through a portability layer located in `/home/user/surge/src/common/dsp/vembertech/portable_intrinsics.h`. This provides cross-platform SIMD support.

**File: src/common/dsp/vembertech/portable_intrinsics.h**

```cpp
#define vFloat SIMD_M128

#define vZero SIMD_MM(setzero_ps)()

#define vAdd SIMD_MM(add_ps)
#define vSub SIMD_MM(sub_ps)
#define vMul SIMD_MM(mul_ps)
#define vMAdd(a, b, c) SIMD_MM(add_ps)(SIMD_MM(mul_ps)(a, b), c)
#define vNMSub(a, b, c) SIMD_MM(sub_ps)(c, SIMD_MM(mul_ps)(a, b))
#define vNeg(a) vSub(vZero, a)

#define vAnd SIMD_MM(and_ps)
#define vOr SIMD_MM(or_ps)

#define vCmpGE SIMD_MM(cmpge_ps)

#define vMax SIMD_MM(max_ps)
#define vMin SIMD_MM(min_ps)

#define vLoad SIMD_MM(load_ps)

inline vFloat vLoad1(float f) { return SIMD_MM(load1_ps)(&f); }

inline vFloat vSqrtFast(vFloat v) {
    return SIMD_MM(rcp_ps)(SIMD_MM(rsqrt_ps)(v));
}

inline float vSum(vFloat x)
{
    auto a = SIMD_MM(add_ps)(x, SIMD_MM(movehl_ps)(x, x));
    a = SIMD_MM(add_ss)(a, SIMD_MM(shuffle_ps)(a, a, SIMD_MM_SHUFFLE(0, 0, 0, 1)));
    float f;
    SIMD_MM(store_ss)(&f, a);
    return f;
}
```

**Why abstract?**

1. **Readability**: `vMul(a, b)` is clearer than `_mm_mul_ps(a, b)`
2. **Portability**: SIMD_M128 can map to different types on different platforms
3. **Maintainability**: Change underlying implementation without touching DSP code

### SIMD_M128: The Core Type

The `SIMD_M128` type is defined in the sst-basic-blocks library header `sst/basic-blocks/simd/setup.h`:

```cpp
#include "sst/basic-blocks/simd/setup.h"
```

This header provides the platform-appropriate definition:

- **On x86-64**: `SIMD_M128` = `__m128` (native SSE2)
- **On ARM**: `SIMD_M128` = `simde__m128` (via SIMDE library)
- **SIMD_MM(op)**: Expands to appropriate intrinsic prefix

This abstraction allows Surge to compile and run efficiently on both x86-64 (Intel/AMD) and ARM (Apple Silicon) platforms.

### Why SSE2 as the Baseline?

Surge chooses SSE2 as its minimum SIMD requirement for several reasons:

1. **Universal x86-64 support**: Every 64-bit x86 CPU has SSE2
2. **Sufficient for audio**: 4-way parallelism matches common voice counts
3. **Compatibility**: Ensures Surge runs on all modern computers
4. **Simplicity**: No runtime CPU detection needed

While newer instruction sets exist (AVX, AVX2, AVX-512), they offer limited benefits for audio DSP where 4-way parallelism is often sufficient, and they would exclude older CPUs.

## Part 3: QuadFilterChain - The SIMD Showcase

The `QuadFilterChain` is Surge's primary example of SIMD optimization. It processes filters for **4 voices simultaneously** using SSE2 instructions.

### The Voice Parallelism Concept

Surge's architecture processes voices in groups of 4. Each scene maintains filter banks that process 4 voices at a time:

```
Scene Voice Processing:
┌─────────────────────────────────────────┐
│  Voice 0    Voice 1    Voice 2    Voice 3  │ ← Quad 0
│  Voice 4    Voice 5    Voice 6    Voice 7  │ ← Quad 1
│  Voice 8    Voice 9    Voice 10   Voice 11 │ ← Quad 2
│  ...                                        │
└─────────────────────────────────────────┘

Each quad is processed with SIMD in one QuadFilterChainState
```

### QuadFilterChainState Structure

**File: src/common/dsp/QuadFilterChain.h**

```cpp
struct QuadFilterChainState
{
    sst::filters::QuadFilterUnitState FU[4];      // 2 filters left and right
    sst::waveshapers::QuadWaveshaperState WSS[2]; // 1 shaper left and right

    SIMD_M128 Gain, FB, Mix1, Mix2, Drive;
    SIMD_M128 dGain, dFB, dMix1, dMix2, dDrive;

    SIMD_M128 wsLPF, FBlineL, FBlineR;

    SIMD_M128 DL[BLOCK_SIZE_OS], DR[BLOCK_SIZE_OS]; // wavedata

    SIMD_M128 OutL, OutR, dOutL, dOutR;
    SIMD_M128 Out2L, Out2R, dOut2L, dOut2R; // fc_stereo only
};
```

**Key observations:**

1. **All parameters are SIMD_M128**: Each `SIMD_M128` holds 4 values (one per voice)
2. **Delta values (dGain, dFB, etc.)**: Enable smooth interpolation across the block
3. **Data arrays (DL, DR)**: Each element is SIMD_M128, holding 4 voices' samples
4. **Multiple filter units**: FU[0-3] for up to 4 filter stages in stereo

**Parameter organization:**

```
Gain SIMD_M128:
┌──────────┬──────────┬──────────┬──────────┐
│ Voice 3  │ Voice 2  │ Voice 1  │ Voice 0  │
│  Gain    │  Gain    │  Gain    │  Gain    │
└──────────┴──────────┴──────────┴──────────┘
```

Each voice can have different cutoff, resonance, feedback, etc., but they're processed in parallel.

### Filter Processing Example

Let's examine a simplified filter chain processing loop:

**File: src/common/dsp/QuadFilterChain.cpp**

```cpp
template <int config, bool A, bool WS, bool B>
void ProcessFBQuad(QuadFilterChainState &d, fbq_global &g,
                   float *OutL, float *OutR)
{
    const auto hb_c = SIMD_MM(set1_ps)(0.5f);
    const auto one = SIMD_MM(set1_ps)(1.0f);

    // Example: fc_serial1 configuration (no feedback)
    for (int k = 0; k < BLOCK_SIZE_OS; k++)
    {
        auto input = d.DL[k];  // Load 4 voices' input samples
        auto x = input, y = d.DR[k];
        auto mask = SIMD_MM(load_ps)((float *)&d.FU[0].active);

        // Filter A processing (if enabled)
        if (A)
            x = g.FU1ptr(&d.FU[0], x);  // Process 4 voices through filter

        // Waveshaper processing (if enabled)
        if (WS)
        {
            // Low-pass filter for waveshaper input
            d.wsLPF = SIMD_MM(mul_ps)(hb_c,
                      SIMD_MM(add_ps)(d.wsLPF, SIMD_MM(and_ps)(mask, x)));

            // Increment drive with delta
            d.Drive = SIMD_MM(add_ps)(d.Drive, d.dDrive);

            // Apply waveshaper to 4 voices
            x = g.WSptr(&d.WSS[0], d.wsLPF, d.Drive);
        }

        // Mix filter output with input
        if (A || WS)
        {
            d.Mix1 = SIMD_MM(add_ps)(d.Mix1, d.dMix1);
            x = SIMD_MM(add_ps)(
                    SIMD_MM(mul_ps)(input, SIMD_MM(sub_ps)(one, d.Mix1)),
                    SIMD_MM(mul_ps)(x, d.Mix1));
        }

        // Combine left and right
        y = SIMD_MM(add_ps)(x, y);

        // Filter B processing (if enabled)
        if (B)
            y = g.FU2ptr(&d.FU[1], y);

        // Final mix
        d.Mix2 = SIMD_MM(add_ps)(d.Mix2, d.dMix2);
        x = SIMD_MM(add_ps)(
                SIMD_MM(mul_ps)(x, SIMD_MM(sub_ps)(one, d.Mix2)),
                SIMD_MM(mul_ps)(y, d.Mix2));

        d.Gain = SIMD_MM(add_ps)(d.Gain, d.dGain);
        auto out = SIMD_MM(and_ps)(mask, SIMD_MM(mul_ps)(x, d.Gain));

        // Output stage: sum SIMD voices to mono output
        MWriteOutputs(out)
    }
}
```

### Coefficient Interpolation

One critical optimization in QuadFilterChain is **coefficient interpolation**. Rather than recalculating filter coefficients every sample, Surge calculates them once per block and interpolates:

```cpp
// At block start:
d.Gain = current_gain;
d.dGain = (target_gain - current_gain) / BLOCK_SIZE_OS;

// Each sample:
d.Gain = SIMD_MM(add_ps)(d.Gain, d.dGain);  // Interpolate
auto out = SIMD_MM(mul_ps)(x, d.Gain);       // Apply
```

This provides smooth parameter changes while avoiding expensive coefficient calculations per-sample.

### Memory Layout for SIMD

The QuadFilterChain's memory layout is carefully designed for SIMD efficiency:

**Interleaved storage:**

```cpp
// Four voices' data for one sample:
SIMD_M128 sample_data = {voice0, voice1, voice2, voice3};

// Array of samples for a block:
SIMD_M128 DL[BLOCK_SIZE_OS];  // Each element = 4 voices for 1 sample
```

This is often called **SoA (Structure of Arrays)** layout, contrasted with **AoS (Array of Structures)**:

```
AoS (less efficient for SIMD):
[V0_S0][V1_S0][V2_S0][V3_S0][V0_S1][V1_S1]...

SoA (Surge's approach):
[V0_S0, V1_S0, V2_S0, V3_S0][V0_S1, V1_S1, V2_S1, V3_S1]...
     One SIMD load                  One SIMD load
```

## Part 4: Oscillator SIMD Optimization

### SineOscillator SIMD Strategy

The SineOscillator demonstrates SIMD optimization at the unison level. When using multiple unison voices, it processes them with SIMD.

**File: src/common/dsp/oscillators/SineOscillator.cpp**

The comments describe the optimization strategy:

```cpp
/*
 * Sine Oscillator Optimization Strategy
 *
 * There's two core fixes.
 *
 * First, the inner unison loop of ::process is now SSEified over unison.
 * This means that we use parallel approximations of sine, we use parallel
 * clamps and feedback application, the whole nine yards.
 *
 * Second, the shape modes are templated at compile time to eliminate
 * branching inside the processing loop.
 */
```

### Processing Four Unison Voices Simultaneously

Here's a conceptual example of how the sine oscillator processes 4 unison voices:

```cpp
// Process 4 unison voices in parallel
template <int mode>
void process_block_internal(...)
{
    for (int s = 0; s < BLOCK_SIZE; ++s)
    {
        // Load 4 unison voices' phase values
        SIMD_M128 phase = SIMD_MM(set_ps)(
            unison_phase[3], unison_phase[2],
            unison_phase[1], unison_phase[0]
        );

        // Advance all 4 phases in parallel
        SIMD_M128 phase_inc = SIMD_MM(set_ps)(
            unison_detune[3], unison_detune[2],
            unison_detune[1], unison_detune[0]
        );
        phase = SIMD_MM(add_ps)(phase, phase_inc);

        // Compute sine for all 4 phases simultaneously
        SIMD_M128 sine_val = fastsinSSE(phase);

        // Apply shape mode (templated, no branching)
        SIMD_M128 shaped = valueFromSineForMode<mode>(sine_val);

        // Accumulate to output
        output[s] += sum_ps_to_float(shaped);
    }
}
```

### Fast Math Functions

Surge includes SIMD versions of expensive math functions:

```cpp
// From sst/basic-blocks/dsp/FastMath.h
SIMD_M128 fastsinSSE(SIMD_M128 x);   // Fast sine approximation
SIMD_M128 fastcosSSE(SIMD_M128 x);   // Fast cosine approximation
SIMD_M128 fastexpSSE(SIMD_M128 x);   // Fast exponential
SIMD_M128 fasttanhSSE(SIMD_M128 x);  // Fast tanh (for waveshaping)
```

These use polynomial approximations that trade a small amount of accuracy for significant performance gains. For audio applications, the approximation error is typically below audible thresholds.

### Output Buffer Alignment

Oscillators ensure their output buffers are aligned:

```cpp
class alignas(16) SurgeVoice
{
    float output alignas(16)[2][BLOCK_SIZE_OS];
    // ...
};
```

This alignment enables efficient SIMD stores when accumulating oscillator outputs.

## Part 5: Effect Processing with SIMD

### Block-wise SIMD Operations

Effects often use SIMD for block-wise processing utilities from `sst::basic_blocks::mechanics`:

```cpp
namespace mech = sst::basic_blocks::mechanics;

// Clear a buffer (set to zero)
float buffer alignas(16)[BLOCK_SIZE];
mech::clear_block<BLOCK_SIZE>(buffer);

// Copy a buffer
float source alignas(16)[BLOCK_SIZE];
float dest alignas(16)[BLOCK_SIZE];
mech::copy_block<BLOCK_SIZE>(source, dest);

// Scale a buffer by a constant
mech::scale_block<BLOCK_SIZE>(buffer, 0.5f);

// Accumulate (add) one buffer to another
mech::accumulate_block<BLOCK_SIZE>(source, dest);
```

These operations use SIMD internally for efficiency.

### Delay Line Interpolation with SIMD

The Chorus effect demonstrates SIMD interpolation in delay lines:

**File: src/common/dsp/effects/ChorusEffectImpl.h**

```cpp
template <int v>
void ChorusEffect<v>::process(float *dataL, float *dataR)
{
    float tbufferL alignas(16)[BLOCK_SIZE];
    float tbufferR alignas(16)[BLOCK_SIZE];

    mech::clear_block<BLOCK_SIZE>(tbufferL);
    mech::clear_block<BLOCK_SIZE>(tbufferR);

    for (int k = 0; k < BLOCK_SIZE; k++)
    {
        auto L = SIMD_MM(setzero_ps)(), R = SIMD_MM(setzero_ps)();

        // Process multiple chorus voices in SIMD
        for (int j = 0; j < v; j++)
        {
            // Calculate delay time and buffer position
            float vtime = time[j].v;
            int i_dtime = max(BLOCK_SIZE, min((int)vtime,
                              max_delay_length - FIRipol_N - 1));
            int rp = ((wpos - i_dtime + k) - FIRipol_N) &
                     (max_delay_length - 1);

            // Select FIR interpolation coefficients
            int sinc = FIRipol_N * limit_range(
                (int)(FIRipol_M * (float(i_dtime + 1) - vtime)),
                0, FIRipol_M - 1);

            // FIR interpolation using SIMD
            SIMD_M128 vo;
            vo = SIMD_MM(mul_ps)(
                SIMD_MM(load_ps)(&storage->sinctable1X[sinc]),
                SIMD_MM(loadu_ps)(&buffer[rp])
            );
            vo = SIMD_MM(add_ps)(vo, SIMD_MM(mul_ps)(
                SIMD_MM(load_ps)(&storage->sinctable1X[sinc + 4]),
                SIMD_MM(loadu_ps)(&buffer[rp + 4])
            ));
            vo = SIMD_MM(add_ps)(vo, SIMD_MM(mul_ps)(
                SIMD_MM(load_ps)(&storage->sinctable1X[sinc + 8]),
                SIMD_MM(loadu_ps)(&buffer[rp + 8])
            ));

            // Apply pan and accumulate
            L = SIMD_MM(add_ps)(L, SIMD_MM(mul_ps)(vo, voicepanL4[j]));
            R = SIMD_MM(add_ps)(R, SIMD_MM(mul_ps)(vo, voicepanR4[j]));
        }

        // Horizontal sum to get final output
        L = mech::sum_ps_to_ss(L);
        R = mech::sum_ps_to_ss(R);
        SIMD_MM(store_ss)(&tbufferL[k], L);
        SIMD_MM(store_ss)(&tbufferR[k], R);
    }
}
```

**What's happening:**

1. **FIR interpolation**: Uses 4 tap points multiplied by coefficients
2. **SIMD multiply-add**: Processes all 4 taps in parallel
3. **Horizontal sum**: Combines the 4 SIMD lanes into a single float
4. **Pan application**: Each chorus voice has SIMD pan coefficients

### SSEComplex for Frequency-Domain Processing

Some effects (like the vocoder) use complex number arithmetic. Surge provides an SSEComplex class:

**File: src/common/dsp/utilities/SSEComplex.h**

```cpp
struct SSEComplex
{
    typedef SIMD_M128 T;
    T _r, _i;  // Real and imaginary parts as SIMD vectors

    // Constructor
    constexpr SSEComplex(const T &r = SIMD_MM(setzero_ps)(),
                        const T &i = SIMD_MM(setzero_ps)())
        : _r(r), _i(i) {}

    inline SIMD_M128 real() const { return _r; }
    inline SIMD_M128 imag() const { return _i; }

    // Operators
    inline SSEComplex &operator+=(const SSEComplex &o)
    {
        _r = SIMD_MM(add_ps)(_r, o._r);
        _i = SIMD_MM(add_ps)(_i, o._i);
        return *this;
    }
};

// Complex multiplication
inline SSEComplex operator*(const SSEComplex &a, const SSEComplex &b)
{
    // (a.r + a.i*j) * (b.r + b.i*j) =
    // (a.r*b.r - a.i*b.i) + (a.r*b.i + a.i*b.r)*j
    return {
        SIMD_MM(sub_ps)(SIMD_MM(mul_ps)(a._r, b._r),
                       SIMD_MM(mul_ps)(a._i, b._i)),  // Real part
        SIMD_MM(add_ps)(SIMD_MM(mul_ps)(a._r, b._i),
                       SIMD_MM(mul_ps)(a._i, b._r))   // Imaginary part
    };
}

// Fast complex exponential (for phasor generation)
inline static SSEComplex fastExp(SIMD_M128 angle)
{
    angle = sst::basic_blocks::dsp::clampToPiRangeSSE(angle);
    return {
        sst::basic_blocks::dsp::fastcosSSE(angle),
        sst::basic_blocks::dsp::fastsinSSE(angle)
    };
}
```

This allows effects to process 4 complex values simultaneously, useful for:

- FFT-based effects (vocoder)
- Frequency shifter
- Complex oscillator banks

### WDF Elements with SIMD

Wave Digital Filters in the Chowdsp effects use SIMD versions:

**File: src/common/dsp/effects/chowdsp/shared/wdf_sse.h**

```cpp
class WDF
{
public:
    virtual void incident(SIMD_M128 x) noexcept = 0;
    virtual SIMD_M128 reflected() noexcept = 0;

    inline SIMD_M128 voltage() const noexcept {
        return vMul(vAdd(a, b), vLoad1(0.5f));
    }

    inline SIMD_M128 current() const noexcept {
        return vMul(vSub(a, b), vMul(vLoad1(0.5f), G));
    }

    SIMD_M128 R; // impedance
    SIMD_M128 G; // admittance

protected:
    SIMD_M128 a = vZero; // incident wave
    SIMD_M128 b = vZero; // reflected wave
};
```

This enables processing 4 WDF instances in parallel, used in the spring reverb and BBD effects.

## Part 6: Performance Guidelines

### When to Use SIMD

**Good candidates for SIMD:**

1. **Parallel data processing**: Processing multiple independent voices/samples
2. **Regular operations**: Same operation applied to many values
3. **No data dependencies**: Each output doesn't depend on previous outputs
4. **Compute-bound code**: Where arithmetic is the bottleneck

**Poor candidates:**

1. **Highly branching code**: Different voices need different operations
2. **Irregular memory access**: Scattered reads/writes
3. **Data-dependent algorithms**: Each step depends on the previous
4. **Already I/O-bound**: Where memory access dominates

**Example - Good for SIMD:**

```cpp
// All voices get the same operation
for (int v = 0; v < 4; v++)
    output[v] = input[v] * gain[v] + offset[v];

// SIMD version:
SIMD_M128 out = vMAdd(input, gain, offset);
```

**Example - Poor for SIMD:**

```cpp
// Different operation per voice
for (int v = 0; v < 4; v++) {
    if (voice_type[v] == SAW)
        output[v] = sawtooth(phase[v]);
    else if (voice_type[v] == SINE)
        output[v] = sine(phase[v]);
    // ...
}
```

### Avoiding Serial Dependencies

Serial dependencies prevent SIMD parallelization:

**Bad - Serial dependency:**

```cpp
// Each sample depends on previous (can't SIMD across samples)
for (int i = 0; i < BLOCK_SIZE; i++)
    output[i] = input[i] + 0.5f * output[i-1];  // Feedback
```

**Good - Parallel across voices:**

```cpp
// Each voice independent (can SIMD across voices)
for (int sample = 0; sample < BLOCK_SIZE; sample++) {
    SIMD_M128 in = load_4_voices(sample);
    SIMD_M128 out = process_4_voices(in);
    store_4_voices(sample, out);
}
```

Surge's QuadFilterChain uses this pattern: serial in time (sample-by-sample), parallel across voices.

### Memory Access Patterns

Efficient SIMD requires good memory access patterns:

**Aligned sequential access (best):**

```cpp
float data alignas(16)[N];
for (int i = 0; i < N; i += 4) {
    SIMD_M128 v = _mm_load_ps(&data[i]);  // Fast aligned load
    // process v
    _mm_store_ps(&data[i], v);            // Fast aligned store
}
```

**Unaligned sequential access (slower):**

```cpp
float data[N];  // Not aligned
for (int i = 0; i < N; i += 4) {
    SIMD_M128 v = _mm_loadu_ps(&data[i]);  // Slower unaligned load
    // process v
    _mm_storeu_ps(&data[i], v);
}
```

**Scattered access (worst for SIMD):**

```cpp
float data[N];
int indices[4] = {10, 45, 2, 99};
// Must load individually, defeating SIMD purpose
for (int j = 0; j < 4; j++)
    values[j] = data[indices[j]];
```

**Surge's approach:**

Surge structures data to enable sequential SIMD access:

```cpp
// Good: Sequential in memory, aligned
SIMD_M128 DL[BLOCK_SIZE_OS];  // Each SIMD value = 4 voices, 1 sample

// Access pattern:
for (int k = 0; k < BLOCK_SIZE_OS; k++) {
    auto input = d.DL[k];  // Load 4 voices efficiently
    // process
}
```

### Benchmarking SIMD Code

To verify SIMD improvements, Surge uses several techniques:

**1. Compiler optimization reports:**

```bash
# GCC
g++ -O3 -march=native -fopt-info-vec-optimized file.cpp

# Clang
clang++ -O3 -Rpass=loop-vectorize file.cpp
```

**2. Assembly inspection:**

Check generated assembly to ensure SIMD instructions are used:

```bash
# Generate assembly
g++ -S -O3 -msse2 file.cpp

# Look for SSE instructions in file.s:
# mulps, addps, movaps, etc.
```

**3. Runtime profiling:**

Surge's unit tests include performance benchmarks for DSP code. The build system includes performance tests that can measure SIMD effectiveness.

**4. Voice count testing:**

A practical test: run many voices and measure CPU usage:

```cpp
// Without SIMD: CPU grows linearly with voices
// With SIMD: CPU grows in steps of 4 voices
```

### Practical SIMD Tips

**1. Use helper functions for horizontal operations:**

```cpp
// Sum all 4 lanes to a single float
inline float vSum(vFloat x)
{
    auto a = SIMD_MM(add_ps)(x, SIMD_MM(movehl_ps)(x, x));
    a = SIMD_MM(add_ss)(a, SIMD_MM(shuffle_ps)(a, a,
                        SIMD_MM_SHUFFLE(0, 0, 0, 1)));
    float f;
    SIMD_MM(store_ss)(&f, a);
    return f;
}
```

**2. Mask inactive voices:**

```cpp
auto mask = SIMD_MM(load_ps)((float *)&d.FU[0].active);
auto out = SIMD_MM(and_ps)(mask, result);  // Zero inactive voices
```

**3. Prefer fused operations:**

```cpp
// Good: Fused multiply-add
auto result = vMAdd(a, b, c);  // One operation: a*b + c

// Less good: Separate multiply and add
auto temp = vMul(a, b);
auto result = vAdd(temp, c);   // Two operations
```

**4. Watch out for denormals:**

Denormal (very small) floating-point numbers can cause severe performance degradation. Surge sets the CPU to flush denormals to zero:

```cpp
// Set FTZ (Flush To Zero) and DAZ (Denormals Are Zero)
_MM_SET_FLUSH_ZERO_MODE(_MM_FLUSH_ZERO_ON);
_MM_SET_DENORMALS_ZERO_MODE(_MM_DENORMALS_ZERO_ON);
```

## Part 7: Cross-Platform Portability

### The SIMDE Library

To support ARM processors (like Apple Silicon), Surge uses the **SIMDE** (SIMD Everywhere) library, located at `/home/user/surge/libs/simde`.

**What is SIMDE?**

SIMDE provides portable implementations of x86 SIMD intrinsics on other architectures:

- **On x86-64**: SIMDE is a thin wrapper around native intrinsics (zero overhead)
- **On ARM**: SIMDE translates SSE2 intrinsics to equivalent NEON instructions
- **On other platforms**: SIMDE provides scalar fallbacks

**Example translation:**

```cpp
// Your code (using SSE2 intrinsics):
__m128 a = _mm_set1_ps(1.0f);
__m128 b = _mm_set1_ps(2.0f);
__m128 c = _mm_add_ps(a, b);

// On x86-64: Compiles to native SSE2 instructions
// On ARM: SIMDE translates to:
float32x4_t a = vdupq_n_f32(1.0f);    // NEON equivalent
float32x4_t b = vdupq_n_f32(2.0f);
float32x4_t c = vaddq_f32(a, b);       // NEON equivalent
```

### SIMD_M128 and SIMD_MM Macros

Surge's abstraction layer uses macros that adapt to the platform:

```cpp
// From sst/basic-blocks/simd/setup.h

#if defined(__SSE2__) || defined(_M_X64) || defined(_M_AMD64)
    // Native x86-64 SSE2
    #define SIMD_M128 __m128
    #define SIMD_MM(op) _mm_##op
#else
    // Use SIMDE for other platforms
    #define SIMDE_ENABLE_NATIVE_ALIASES
    #include <simde/x86/sse2.h>
    #define SIMD_M128 simde__m128
    #define SIMD_MM(op) simde_mm_##op
#endif
```

This means the same code works everywhere:

```cpp
SIMD_M128 a = SIMD_MM(set1_ps)(1.0f);  // Works on x86, ARM, etc.
```

### Cross-Platform Considerations

**1. Alignment differences:**

While x86-64 typically requires 16-byte alignment for SSE2, ARM NEON is more flexible. However, Surge maintains 16-byte alignment everywhere for consistency:

```cpp
float buffer alignas(16)[BLOCK_SIZE];  // Works on all platforms
```

**2. Denormal handling:**

Different platforms handle denormals differently. Surge explicitly sets flush-to-zero mode when available:

```cpp
#if defined(__SSE2__)
    _MM_SET_FLUSH_ZERO_MODE(_MM_FLUSH_ZERO_ON);
    _MM_SET_DENORMALS_ZERO_MODE(_MM_DENORMALS_ZERO_ON);
#elif defined(__ARM_NEON)
    // ARM NEON denormal handling
    // (typically handled differently)
#endif
```

**3. Performance characteristics:**

While SIMDE provides correct functionality, performance may vary:

- **x86-64 SSE2**: Baseline performance
- **ARM NEON**: Often comparable or better (ARM NEON is quite efficient)
- **Scalar fallback**: Much slower, but ensures correctness

**4. Testing across platforms:**

Surge's CI system tests on multiple platforms:

- Linux (x86-64)
- macOS (x86-64 and ARM64)
- Windows (x86-64)

This ensures SIMD code works correctly everywhere.

## Part 8: Real-World SIMD Examples

### Example 1: Simple Gain Application

The simplest SIMD pattern - apply gain to 4 voices:

```cpp
void apply_gain_simd(QuadFilterChainState &state, float gain_db)
{
    // Convert dB to linear (scalar operation, once)
    float gain_linear = pow(10.0f, gain_db / 20.0f);

    // Broadcast to all 4 voices
    SIMD_M128 gain = SIMD_MM(set1_ps)(gain_linear);

    // Process entire block
    for (int k = 0; k < BLOCK_SIZE_OS; k++)
    {
        // Load 4 voices' samples
        SIMD_M128 input = state.DL[k];

        // Multiply all 4 by gain
        SIMD_M128 output = SIMD_MM(mul_ps)(input, gain);

        // Store back
        state.DL[k] = output;
    }
}
```

**Benefits:**
- 4 voices processed in one multiply
- Simple, readable code
- 4x throughput improvement

### Example 2: Stereo Panning

Pan 4 voices to stereo outputs with different pan positions:

```cpp
void pan_voices_simd(SIMD_M128 input, SIMD_M128 pan,
                     float *outL, float *outR)
{
    // pan ranges from 0.0 (left) to 1.0 (right)
    // Use constant-power panning

    const float pi_over_2 = 1.57079632679f;
    SIMD_M128 angle = SIMD_MM(mul_ps)(pan,
                      SIMD_MM(set1_ps)(pi_over_2));

    // Left gain = cos(angle), Right gain = sin(angle)
    SIMD_M128 gainL = sst::basic_blocks::dsp::fastcosSSE(angle);
    SIMD_M128 gainR = sst::basic_blocks::dsp::fastsinSSE(angle);

    // Apply panning
    SIMD_M128 left = SIMD_MM(mul_ps)(input, gainL);
    SIMD_M128 right = SIMD_MM(mul_ps)(input, gainR);

    // Sum to stereo outputs (horizontal sum)
    *outL = vSum(left);
    *outR = vSum(right);
}
```

### Example 3: Simple One-Pole Filter

A one-pole lowpass filter processing 4 voices:

```cpp
struct OnePoleFilterSIMD
{
    SIMD_M128 state;  // Filter state for 4 voices
    SIMD_M128 coeff;  // Filter coefficient for 4 voices

    void process_block(SIMD_M128 *input, SIMD_M128 *output, int num_samples)
    {
        for (int i = 0; i < num_samples; i++)
        {
            // y[n] = y[n-1] + coeff * (x[n] - y[n-1])
            // This is: y[n] = (1-coeff)*y[n-1] + coeff*x[n]

            SIMD_M128 x = input[i];
            SIMD_M128 diff = SIMD_MM(sub_ps)(x, state);
            SIMD_M128 delta = SIMD_MM(mul_ps)(coeff, diff);
            state = SIMD_MM(add_ps)(state, delta);
            output[i] = state;
        }
    }

    void set_cutoff(float cutoff_hz, float sample_rate)
    {
        float omega = 2.0f * M_PI * cutoff_hz / sample_rate;
        float coeff_val = 1.0f - exp(-omega);
        coeff = SIMD_MM(set1_ps)(coeff_val);
    }
};
```

### Example 4: Soft Clipping Waveshaper

Apply soft clipping to 4 voices using tanh:

```cpp
SIMD_M128 soft_clip_simd(SIMD_M128 input, SIMD_M128 drive)
{
    // Apply drive
    SIMD_M128 driven = SIMD_MM(mul_ps)(input, drive);

    // Fast tanh approximation for soft clipping
    SIMD_M128 clipped = sst::basic_blocks::dsp::fasttanhSSE(driven);

    // Compensate for drive in output level
    SIMD_M128 inv_drive = SIMD_MM(rcp_ps)(drive);  // Approximate 1/drive
    SIMD_M128 output = SIMD_MM(mul_ps)(clipped, inv_drive);

    return output;
}
```

## Conclusion: SIMD as a Foundation

SIMD optimization is woven throughout Surge XT's architecture, enabling it to achieve professional performance standards. Key takeaways:

1. **4-way voice parallelism**: QuadFilterChain processes voices in groups of 4
2. **Abstraction for portability**: SIMD_M128 and macros enable cross-platform SIMD
3. **Alignment matters**: 16-byte alignment enables fast SIMD memory operations
4. **Coefficient interpolation**: Smooth parameter changes without per-sample cost
5. **SIMDE for ARM**: Transparent support for Apple Silicon and other platforms

The SIMD approach allows Surge to process complex patches with many voices while maintaining real-time performance on typical CPUs. Understanding these patterns is essential for:

- **Adding features**: New oscillators and effects should follow SIMD patterns
- **Optimizing code**: Identify opportunities for SIMD parallelization
- **Debugging performance**: Profile SIMD effectiveness in voice processing
- **Cross-platform development**: Ensure code works on x86-64 and ARM

As you explore Surge's codebase, you'll see these SIMD patterns repeatedly. They represent decades of accumulated knowledge about real-time audio DSP optimization, now available as free and open-source reference implementations.

---

**Key Files Referenced:**

- `/home/user/surge/src/common/dsp/vembertech/portable_intrinsics.h` - SIMD macro definitions
- `/home/user/surge/src/common/dsp/QuadFilterChain.h` - Quad filter state structure
- `/home/user/surge/src/common/dsp/QuadFilterChain.cpp` - SIMD filter processing
- `/home/user/surge/src/common/dsp/utilities/SSEComplex.h` - Complex SIMD operations
- `/home/user/surge/src/common/dsp/oscillators/SineOscillator.cpp` - Oscillator SIMD
- `/home/user/surge/src/common/dsp/effects/ChorusEffectImpl.h` - Effect SIMD
- `/home/user/surge/src/common/globals.h` - Includes SIMD setup
- `/home/user/surge/libs/simde` - SIMDE portability library

**Further Reading:**

- Intel Intrinsics Guide: https://software.intel.com/sites/landingpage/IntrinsicsGuide/
- ARM NEON Programmer's Guide
- "Digital Signal Processing on Modern CPUs" - considerations for real-time audio
- Surge XT source code - the best reference for practical SIMD usage
