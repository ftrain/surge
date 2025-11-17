# Appendix A: DSP Mathematics Primer

## Mathematical Foundations for Understanding Surge XT

Digital Signal Processing (DSP) is the mathematical backbone of software synthesis. This appendix provides the essential mathematical concepts, formulas, and algorithms that underpin Surge XT's sound generation and processing capabilities.

Whether you're a student learning DSP, a developer implementing new features, or a musician wanting to understand the theory behind your favorite synthesizer, this primer bridges the gap between abstract mathematics and practical audio synthesis.

---

## Table of Contents

1. [Signals and Systems](#1-signals-and-systems)
2. [Fourier Analysis](#2-fourier-analysis)
3. [Digital Filters](#3-digital-filters)
4. [Common Functions](#4-common-functions)
5. [Interpolation](#5-interpolation)
6. [Windowing Functions](#6-windowing-functions)
7. [Conversions](#7-conversions)

---

## 1. Signals and Systems

### 1.1 Continuous vs. Discrete Signals

**Continuous-time signals** exist at every point in time, represented mathematically as functions:

```
x(t) where t ∈ ℝ (real numbers)
```

Example: A sine wave in the analog domain
```
x(t) = A · sin(2πft + φ)
```

Where:
- `A` = amplitude
- `f` = frequency in Hz
- `t` = time in seconds
- `φ` = phase offset in radians

**Discrete-time signals** exist only at specific time instants (samples), typically represented as sequences:

```
x[n] where n ∈ ℤ (integers)
```

Example: A digital sine wave
```
x[n] = A · sin(2πf·n/fs + φ)
```

Where:
- `n` = sample index (0, 1, 2, 3, ...)
- `fs` = sample rate in Hz

**Visualization: Continuous vs. Discrete**

```
Continuous Signal x(t):
    ╱╲      ╱╲      ╱╲
   ╱  ╲    ╱  ╲    ╱  ╲
  ╱    ╲  ╱    ╲  ╱    ╲
 ╱      ╲╱      ╲╱      ╲
────────────────────────────► time (t)

Discrete Signal x[n]:
    •       •       •
   • •     • •     • •
  •   •   •   •   •   •
 •     • •     • •     •
────────────────────────────► sample index (n)
```

### 1.2 The Sampling Theorem

The **Nyquist-Shannon Sampling Theorem** states that a continuous signal can be perfectly reconstructed from its samples if:

```
fs ≥ 2 · fmax
```

Where:
- `fs` = sampling frequency (sample rate)
- `fmax` = highest frequency component in the signal

**Why This Matters:**

If we sample a 20 kHz audio signal, we need at least 40 kHz sample rate. This is why CD audio uses 44.1 kHz - it captures all frequencies up to approximately 22 kHz (just above human hearing range of 20 Hz - 20 kHz).

**Practical Example in Surge:**

Surge typically operates at 48 kHz sample rate, allowing faithful reproduction of frequencies up to 24 kHz:

```cpp
// From Surge's architecture
const int SAMPLE_RATE = 48000;  // Hz
const float NYQUIST_FREQ = SAMPLE_RATE / 2.0f;  // 24000 Hz
```

### 1.3 Nyquist Frequency

The **Nyquist frequency** is half the sample rate:

```
fN = fs / 2
```

This represents the highest frequency that can be represented in a digital system without aliasing.

**Frequency Spectrum Representation:**

```
Magnitude
    |
    |████████████████╗             Valid frequency range
    |                ╚═════════════  Aliasing region
    |
    └────────────────┬────────────┬─────────────► Frequency
                     0           fN (Nyquist)    fs
```

**In Musical Terms:**

At 48 kHz sample rate:
- MIDI note 136 ≈ 23.68 kHz (highest representable pitch, near Nyquist)
- MIDI note 69 (A4) = 440 Hz (middle of musical range)
- MIDI note 21 (A0) ≈ 27.5 Hz (lowest piano note)

### 1.4 Sample Rate and Period

**Sample Rate** (`fs`): Number of samples per second, measured in Hz (or samples/second).

Common sample rates:
- 44.1 kHz (CD audio)
- 48 kHz (professional audio, Surge default)
- 96 kHz (high-resolution audio)
- 192 kHz (ultra-high resolution)

**Sample Period** (`T`): Time between consecutive samples:

```
T = 1 / fs
```

At 48 kHz:
```
T = 1 / 48000 = 0.0000208333... seconds
  ≈ 20.83 microseconds
```

**Block Processing:**

Surge processes audio in blocks (typically 32 or 64 samples) for efficiency:

```cpp
// From: src/common/globals.h
#define BLOCK_SIZE 32  // or other powers of 2

// Time duration of one block at 48 kHz:
float block_time = BLOCK_SIZE / 48000.0f;
// = 32 / 48000 = 0.000667 seconds ≈ 0.67 milliseconds
```

This block-based architecture balances latency with computational efficiency.

---

## 2. Fourier Analysis

### 2.1 Fundamental Concept

The **Fourier Theorem** states that any periodic waveform can be represented as a sum of sine and cosine waves at different frequencies and amplitudes.

```
x(t) = a₀ + Σ[aₙ·cos(nω₀t) + bₙ·sin(nω₀t)]
       n=1
```

Where:
- `ω₀ = 2πf₀` (fundamental angular frequency)
- `aₙ, bₙ` = Fourier coefficients
- `n` = harmonic number (1, 2, 3, ...)

**Musical Significance:**

A sawtooth wave rich in harmonics can be decomposed into:
```
Sawtooth = fundamental + (1/2)·2nd harmonic + (1/3)·3rd harmonic + ...
```

### 2.2 Fourier Series

For **periodic signals** with period `T₀`, the Fourier series representation is:

**Trigonometric Form:**
```
x(t) = a₀/2 + Σ[aₙ·cos(2πnt/T₀) + bₙ·sin(2πnt/T₀)]
            n=1
```

**Exponential Form (Complex):**
```
x(t) = Σ cₙ·e^(j2πnt/T₀)
     n=-∞
```

Where:
```
cₙ = (1/T₀) ∫[0 to T₀] x(t)·e^(-j2πnt/T₀) dt
```

**Synthesizing a Square Wave:**

```
Square wave ≈ sin(ωt) + (1/3)sin(3ωt) + (1/5)sin(5ωt) + (1/7)sin(7ωt) + ...
```

Visualization with increasing harmonics:

```
1 harmonic:     ╱──╲          (sine wave)
               ╱    ╲
              ╱      ╲

3 harmonics:    ┌──┐          (getting squarer)
               ╱    ╲
              ╱      ╲──

7 harmonics:    ┌──┐          (approaching square)
                │  │
              ──┘  └──
```

### 2.3 Fourier Transform

For **non-periodic signals**, the continuous Fourier Transform (FT) is:

**Forward Transform:**
```
X(f) = ∫[-∞ to ∞] x(t)·e^(-j2πft) dt
```

**Inverse Transform:**
```
x(t) = ∫[-∞ to ∞] X(f)·e^(j2πft) df
```

This transforms a signal from the **time domain** to the **frequency domain**.

**Time-Frequency Duality:**

```
Time Domain          Frequency Domain
x(t)          ←→     X(f)
Amplitude vs. Time   Amplitude vs. Frequency
```

### 2.4 Discrete Fourier Transform (DFT)

For digital signals with `N` samples, the DFT is:

**Forward DFT:**
```
X[k] = Σ x[n]·e^(-j2πkn/N)    for k = 0, 1, ..., N-1
     n=0
```

**Inverse DFT:**
```
x[n] = (1/N) Σ X[k]·e^(j2πkn/N)    for n = 0, 1, ..., N-1
           k=0
```

Where:
- `x[n]` = time-domain samples
- `X[k]` = frequency-domain coefficients
- `N` = number of samples
- `k` = frequency bin index

**Frequency Resolution:**

```
Δf = fs / N
```

Example: With `fs = 48000 Hz` and `N = 1024`:
```
Δf = 48000 / 1024 ≈ 46.875 Hz per bin
```

### 2.5 Fast Fourier Transform (FFT)

The **FFT** is an efficient algorithm for computing the DFT, reducing complexity from O(N²) to O(N log N).

**Computational Savings:**

```
For N = 1024:
DFT operations:  1,024² = 1,048,576
FFT operations:  1,024 × 10 ≈ 10,240   (100× faster!)
```

**FFT Restrictions:**

- Works best when `N` is a power of 2 (512, 1024, 2048, 4096, ...)
- Assumes periodic boundary conditions
- Requires windowing for accurate spectral analysis

**Common FFT Sizes in Audio:**

```
FFT Size    Frequency Resolution @ 48kHz    Time Window
512         93.75 Hz                        10.67 ms
1024        46.88 Hz                        21.33 ms
2048        23.44 Hz                        42.67 ms
4096        11.72 Hz                        85.33 ms
8192        5.86 Hz                         170.67 ms
```

### 2.6 Harmonic Series

The **harmonic series** is fundamental to musical sounds. Harmonics are integer multiples of a fundamental frequency:

```
f₁ = fundamental frequency
f₂ = 2·f₁ (1 octave above)
f₃ = 3·f₁ (octave + fifth)
f₄ = 4·f₁ (2 octaves)
f₅ = 5·f₁ (2 octaves + major third)
...
```

**Example: A440 Hz Harmonic Series**

```
Harmonic  Frequency    Musical Note    Cents from Equal Temperament
1         440 Hz       A4              0
2         880 Hz       A5              0
3         1320 Hz      E6              +2
4         1760 Hz      A6              0
5         2200 Hz      C#7             -14
6         2640 Hz      E7              +2
7         3080 Hz      G7              -31 (very flat!)
8         3520 Hz      A7              0
```

**Harmonic Content of Waveforms:**

```
Sine wave:     Only fundamental (no harmonics)
Sawtooth:      All harmonics (1, 1/2, 1/3, 1/4, ...)
Square wave:   Odd harmonics only (1, 1/3, 1/5, 1/7, ...)
Triangle:      Odd harmonics, decreasing rapidly (1, 1/9, 1/25, 1/49, ...)
Pulse:         All harmonics, modulated by pulse width
```

---

## 3. Digital Filters

### 3.1 Difference Equations

Digital filters are implemented using **difference equations** - discrete-time equivalents of differential equations.

**General Form:**

```
y[n] = Σ bₖ·x[n-k] - Σ aₖ·y[n-k]
      k=0            k=1
```

Where:
- `y[n]` = output at sample `n`
- `x[n]` = input at sample `n`
- `bₖ` = feedforward coefficients
- `aₖ` = feedback coefficients

**First-Order Low-Pass Filter:**

```
y[n] = a·x[n] + (1-a)·y[n-1]
```

Where `a` controls the cutoff frequency (0 < a < 1).

**Implementation Example:**

```cpp
// Simple one-pole low-pass filter
float previousOutput = 0.0f;
float coefficient = 0.1f;  // Determines cutoff frequency

float process(float input)
{
    float output = coefficient * input + (1.0f - coefficient) * previousOutput;
    previousOutput = output;
    return output;
}
```

### 3.2 Transfer Functions

The **transfer function** `H(z)` describes a filter's behavior in the z-domain:

```
H(z) = Y(z)/X(z) = (b₀ + b₁z⁻¹ + b₂z⁻² + ...) / (a₀ + a₁z⁻¹ + a₂z⁻² + ...)
```

**Standard Second-Order (Biquad) Form:**

```
H(z) = (b₀ + b₁z⁻¹ + b₂z⁻²) / (a₀ + a₁z⁻¹ + a₂z⁻²)
```

Usually normalized so `a₀ = 1`:

```
H(z) = (b₀ + b₁z⁻¹ + b₂z⁻²) / (1 + a₁z⁻¹ + a₂z⁻²)
```

This gives the difference equation:

```
y[n] = b₀·x[n] + b₁·x[n-1] + b₂·x[n-2] - a₁·y[n-1] - a₂·y[n-2]
```

### 3.3 Z-Transform Basics

The **z-transform** is the discrete-time equivalent of the Laplace transform.

**Definition:**

```
X(z) = Σ x[n]·z⁻ⁿ
     n=-∞
```

**Key Property - Delay:**

```
If x[n] ←→ X(z)
Then x[n-1] ←→ z⁻¹·X(z)
```

This `z⁻¹` represents a **unit delay** (one sample delay), fundamental to digital filters.

**Frequency Response:**

Evaluate the transfer function on the unit circle (`z = e^(jω)`):

```
H(e^(jω)) = H(z)|_{z=e^(jω)}
```

Where `ω = 2πf/fs` (normalized angular frequency).

### 3.4 Poles and Zeros

**Zeros**: Values of `z` where `H(z) = 0` (numerator = 0)
**Poles**: Values of `z` where `H(z) = ∞` (denominator = 0)

**Pole-Zero Plot:**

```
Imaginary Axis
    ↑
    |     ○ (zero)
    |
    |  ×     (pole)
    |
────┼────────► Real Axis
    |
    |    Unit Circle: |z| = 1
    |   (Frequency response)
```

**Effect on Frequency Response:**

- **Zeros**: Create notches (attenuation) in frequency response
- **Poles**: Create peaks (resonance) in frequency response

**Proximity to Unit Circle:**

- Poles close to unit circle → sharp resonance
- Poles far from unit circle → gentle slopes

### 3.5 Stability

A digital filter is **stable** if and only if all poles lie **inside** the unit circle:

```
|pole| < 1
```

**Unstable Filter:**

```
If |pole| ≥ 1:
- Output can grow unbounded
- System becomes unstable
- Results in audio artifacts (clicks, explosions)
```

**In Surge's Filter Code:**

Coefficient calculations must ensure stability. For example, resonance parameter must be limited:

```cpp
// Conceptual: Ensure resonance doesn't push poles outside unit circle
float resonance = std::clamp(resonance_param, 0.0f, 0.99f);
```

**Biquad Stability Conditions:**

For a biquad filter `H(z) = (b₀ + b₁z⁻¹ + b₂z⁻²) / (1 + a₁z⁻¹ + a₂z⁻²)`:

```
Stable if:
|a₂| < 1
|a₁| < 1 + a₂
```

---

## 4. Common Functions

### 4.1 Trigonometric Functions

**Sine and Cosine:**

```
sin(ωt)  : Oscillates between -1 and +1
cos(ωt)  : Sine shifted by 90° (π/2 radians)
```

**Relationship:**

```
sin(x) = cos(x - π/2)
cos(x) = sin(x + π/2)
sin²(x) + cos²(x) = 1  (Pythagorean identity)
```

**Visualization:**

```
Amplitude
 1.0 |   ╱──╲      ╱──╲      sin(ωt)
     |  ╱    ╲    ╱    ╲
 0.0 | ╱      ╲  ╱      ╲
     |╱        ╲╱        ╲
-1.0 └──────────────────────► time

 1.0 | ──╲      ╱──╲          cos(ωt)
     |    ╲    ╱    ╲    ╱
 0.0 |     ╲  ╱      ╲  ╱
     |      ╲╱        ╲╱
-1.0 └──────────────────────► time
```

**Generating Sine Waves:**

```cpp
// Generate sine wave at frequency f
float phase = 0.0f;
float frequency = 440.0f;  // A4
float sampleRate = 48000.0f;
float phaseIncrement = 2.0f * M_PI * frequency / sampleRate;

for (int n = 0; n < numSamples; n++)
{
    output[n] = amplitude * std::sin(phase);
    phase += phaseIncrement;

    // Wrap phase to avoid overflow
    if (phase >= 2.0f * M_PI)
        phase -= 2.0f * M_PI;
}
```

**Tangent:**

```
tan(x) = sin(x) / cos(x)
```

Rarely used in basic synthesis, but appears in filter coefficient calculations.

### 4.2 Exponential and Logarithmic Functions

**Exponential Function:**

```
y = e^x  (Euler's number e ≈ 2.71828)
```

**Properties:**

```
e^0 = 1
e^(a+b) = e^a · e^b
(e^a)^b = e^(ab)
d/dx(e^x) = e^x  (derivative equals itself!)
```

**Logarithmic Function:**

```
y = ln(x)  (natural logarithm, base e)
y = log₂(x)  (binary logarithm, base 2)
y = log₁₀(x)  (common logarithm, base 10)
```

**Properties:**

```
ln(e^x) = x
e^(ln(x)) = x
ln(ab) = ln(a) + ln(b)
ln(a/b) = ln(a) - ln(b)
ln(a^b) = b·ln(a)
```

**Conversion Between Bases:**

```
log₂(x) = ln(x) / ln(2)
log₁₀(x) = ln(x) / ln(10)
```

**Musical Applications:**

Frequencies and pitches have exponential/logarithmic relationships:

```
f = f₀ · 2^(n/12)  (MIDI note to frequency)
n = 12 · log₂(f/f₀)  (frequency to MIDI note)
```

### 4.3 Decibels

The **decibel (dB)** is a logarithmic unit for expressing ratios.

**Power Ratio:**

```
dB = 10 · log₁₀(P₁/P₀)
```

**Amplitude (Voltage) Ratio:**

Since power is proportional to amplitude squared (`P ∝ V²`):

```
dB = 20 · log₁₀(A₁/A₀)
```

**Common Values:**

```
Amplitude Ratio    dB Value
2.0                +6.02 dB    (double amplitude)
1.414 (√2)         +3.01 dB    (double power)
1.0                0 dB        (unity gain)
0.707 (1/√2)       -3.01 dB    (half power)
0.5                -6.02 dB    (half amplitude)
0.1                -20 dB
0.01               -40 dB
0.001              -60 dB
0.0001             -80 dB      (typical noise floor)
```

**Surge's Implementation:**

From `/home/user/surge/src/common/dsp/utilities/DSPUtils.h`:

```cpp
// Convert amplitude to decibels
inline float amp_to_db(float x)
{
    return std::clamp((float)(18.f * log2(x)), -192.f, 96.f);
}

// Convert decibels to amplitude
inline float db_to_amp(float x)
{
    return std::clamp(powf(2.f, x / 18.f), 0.f, 2.f);
}
```

Note: Surge uses a custom mapping where 18 dB corresponds to one doubling (instead of standard 6.02 dB). This is because Surge stores gain as `x³` internally:

```cpp
// Amplitude parameter to linear gain
inline float amp_to_linear(float x)
{
    x = std::max(0.f, x);
    return x * x * x;  // Cubic mapping
}
```

**Why Decibels?**

1. **Perception**: Human hearing is logarithmic - we perceive ratios, not differences
2. **Dynamic Range**: Can express huge ranges compactly (-∞ to +96 dB vs. 0 to 1,000,000)
3. **Multiplication → Addition**: Gain stages add in dB rather than multiply

### 4.4 MIDI Note to Frequency

**Standard Formula:**

```
f = 440 · 2^((n - 69) / 12)
```

Where:
- `f` = frequency in Hz
- `n` = MIDI note number (0-127)
- 440 Hz = A4 (MIDI note 69)
- 12 semitones per octave

**Example Conversions:**

```
MIDI Note    Frequency        Musical Note
0            8.176 Hz         C-1
21           27.5 Hz          A0 (lowest piano)
60           261.63 Hz        C4 (middle C)
69           440.0 Hz         A4 (concert A)
108          4186.0 Hz        C8 (highest piano)
127          12543.85 Hz      G9
```

**Implementation from Surge:**

From `/home/user/surge/src/common/Parameter.cpp`:

```cpp
// Convert MIDI note to frequency
auto freq = 440.0 * pow(2.0, (note - 69.0) / 12);
```

**Inverse (Frequency to MIDI Note):**

```
n = 69 + 12 · log₂(f / 440)
```

**Pitch Bend:**

MIDI pitch bend typically ranges ±2 semitones:

```
f_bent = f · 2^(bend / (12 · sensitivity))
```

Where `sensitivity` is the pitch bend range (commonly 2 semitones).

---

## 5. Interpolation

Interpolation estimates values between known samples, crucial for:
- Wavetable synthesis (reading between table positions)
- Delay lines (fractional delay times)
- Resampling (sample rate conversion)
- LFO/envelope smoothing

### 5.1 Linear Interpolation

**Definition:**

Estimate a value between two points using a straight line.

```
y = y₀ + (y₁ - y₀) · t
```

Where:
- `y₀` = value at position 0
- `y₁` = value at position 1
- `t` = fractional position (0 ≤ t ≤ 1)
- `y` = interpolated value

**Visualization:**

```
y₁  ×────────────────× (y₁)
    │               ╱
    │             ╱
y   │           ●  ← interpolated point at t=0.6
    │         ╱
    │       ╱
y₀  ×─────╱──────────× (y₀)
    0                1
         t=0.6
```

**From Surge's Code:**

From `/home/user/surge/src/common/dsp/effects/chowdsp/shared/chowdsp_DelayInterpolation.h`:

```cpp
// Linear interpolation for delay lines
template <typename SampleType, typename NumericType>
inline SampleType call(const SampleType *buffer, int delayInt,
                       NumericType delayFrac, const SampleType & /*state*/)
{
    auto index1 = delayInt;
    auto index2 = index1 + 1;

    auto value1 = buffer[index1];
    auto value2 = buffer[index2];

    return value1 + (SampleType)delayFrac * (value2 - value1);
}
```

**Pros:**
- Very fast (2 reads, 1 multiply, 2 adds)
- Simple to implement
- Low memory overhead

**Cons:**
- Introduces high-frequency roll-off
- Not differentiable at sample points
- Audible as slight low-pass filtering

### 5.2 Cubic Interpolation

**Definition:**

Uses four points to fit a cubic polynomial, providing smoother interpolation.

**Catmull-Rom Cubic:**

```
y = (-0.5·y₋₁ + 1.5·y₀ - 1.5·y₁ + 0.5·y₂)·t³
  + (y₋₁ - 2.5·y₀ + 2·y₁ - 0.5·y₂)·t²
  + (-0.5·y₋₁ + 0.5·y₁)·t
  + y₀
```

Where:
- `y₋₁, y₀, y₁, y₂` = four consecutive samples
- `t` = fractional position (0 ≤ t ≤ 1)

**Visualization:**

```
    ×               × (y₂)
     ╲            ╱
      ╲          ╱
       ╲     ●  ╱  ← smooth cubic curve
        ╲   ╱  ╱
         ×─╱──×
        (y₋₁)(y₀)
```

**Pros:**
- Much smoother than linear
- Better high-frequency preservation
- C¹ continuous (smooth first derivative)

**Cons:**
- 4× the memory reads
- More computation (polynomial evaluation)
- Can overshoot (ringing artifacts)

### 5.3 Hermite Interpolation

**Definition:**

Cubic interpolation using values and derivatives, ensuring smooth transitions.

**Formula:**

```
y = (2t³ - 3t² + 1)·y₀
  + (t³ - 2t² + t)·m₀
  + (-2t³ + 3t²)·y₁
  + (t³ - t²)·m₁
```

Where:
- `y₀, y₁` = values at points 0 and 1
- `m₀, m₁` = derivatives (slopes) at points 0 and 1
- `t` = fractional position

**Hermite Basis Functions:**

```
h₀₀(t) = 2t³ - 3t² + 1   (position at 0)
h₁₀(t) = t³ - 2t² + t     (derivative at 0)
h₀₁(t) = -2t³ + 3t²       (position at 1)
h₁₁(t) = t³ - t²          (derivative at 1)
```

**Typical Derivative Estimation:**

```
m₀ = (y₁ - y₋₁) / 2
m₁ = (y₂ - y₀) / 2
```

**Pros:**
- Smooth (C¹ continuous)
- No overshoot if derivatives chosen carefully
- Good for wavetable synthesis

**Cons:**
- Requires derivative calculation
- More computation than linear

### 5.4 Lagrange Interpolation

**Definition:**

Polynomial interpolation through `n+1` points using Lagrange basis polynomials.

**Third-Order Lagrange (4 points):**

```
y = y₀·L₀(t) + y₁·L₁(t) + y₂·L₂(t) + y₃·L₃(t)
```

Where the Lagrange basis polynomials are:

```
L₀(t) = -(t-1)(t-2)(t-3) / 6
L₁(t) = (t)(t-2)(t-3) / 2
L₂(t) = -(t)(t-1)(t-3) / 2
L₃(t) = (t)(t-1)(t-2) / 6
```

**From Surge's Code:**

From `/home/user/surge/src/common/dsp/effects/chowdsp/shared/chowdsp_DelayInterpolation.h`:

```cpp
// Third-order Lagrange interpolation
template <typename SampleType, typename NumericType>
inline SampleType call(const SampleType *buffer, int delayInt,
                       NumericType delayFrac, const SampleType & /*state*/)
{
    auto index1 = delayInt;
    auto index2 = index1 + 1;
    auto index3 = index2 + 1;
    auto index4 = index3 + 1;

    auto value1 = buffer[index1];
    auto value2 = buffer[index2];
    auto value3 = buffer[index3];
    auto value4 = buffer[index4];

    auto d1 = delayFrac - (NumericType)1.0;
    auto d2 = delayFrac - (NumericType)2.0;
    auto d3 = delayFrac - (NumericType)3.0;

    auto c1 = -d1 * d2 * d3 / (NumericType)6.0;
    auto c2 = d2 * d3 * (NumericType)0.5;
    auto c3 = -d1 * d3 * (NumericType)0.5;
    auto c4 = d1 * d2 / (NumericType)6.0;

    return value1 * c1 + (SampleType)delayFrac * (value2 * c2 + value3 * c3 + value4 * c4);
}
```

**Pros:**
- Exact fit through all points
- Can achieve arbitrary accuracy with more points
- Well-understood mathematics

**Cons:**
- Can oscillate between points (Runge's phenomenon)
- Computationally expensive for high orders
- Not always monotonic

---

## 6. Windowing Functions

Window functions taper signals at boundaries to reduce spectral leakage in FFT analysis and for smooth grain synthesis.

### 6.1 Why Window Functions?

**Problem: Spectral Leakage**

When analyzing a finite signal segment with FFT, abrupt boundaries create discontinuities that spread energy across frequency bins.

```
Signal boundary:
    │
    ├─────────┤ Analysis window
    ▲         ▲
Discontinuity causes spreading in frequency domain
```

**Solution: Window Functions**

Taper the signal smoothly to zero at boundaries.

### 6.2 Rectangular Window

**Definition:**

```
w[n] = 1  for 0 ≤ n ≤ N-1
```

**Visualization:**

```
Amplitude
1.0 ├──────────────────┤
    │                  │
0.5 │                  │
    │                  │
0.0 └──────────────────┴─────► sample index
    0                  N-1
```

**Properties:**
- Main lobe width: 4π/N
- Side lobe level: -13 dB
- Equivalent noise bandwidth: 1.0 bins

**Use Cases:**
- When signal naturally has zeros at boundaries
- When maximum frequency resolution is needed
- Not recommended for general spectral analysis (high leakage)

### 6.3 Hann Window

Also called "Hanning window" or "raised cosine window."

**Definition:**

```
w[n] = 0.5 · (1 - cos(2πn / (N-1)))
     = sin²(πn / (N-1))
```

**Visualization:**

```
Amplitude
1.0      ╱────────╲
        ╱          ╲
0.5    ╱            ╲
      ╱              ╲
0.0  ╱                ╲
    └────────────────────► sample index
    0                  N-1
```

**Properties:**
- Main lobe width: 8π/N (2× rectangular)
- Side lobe level: -31 dB (much better than rectangular)
- Equivalent noise bandwidth: 1.5 bins

**Implementation:**

```cpp
// Generate Hann window
void generateHannWindow(float* window, int N)
{
    for (int n = 0; n < N; n++)
    {
        window[n] = 0.5f * (1.0f - std::cos(2.0f * M_PI * n / (N - 1)));
    }
}
```

**Use Cases:**
- General-purpose spectral analysis
- Good balance between frequency resolution and leakage
- Very common in audio FFT applications

### 6.4 Hamming Window

Named after Richard Hamming (not "Hamm-ing").

**Definition:**

```
w[n] = 0.54 - 0.46 · cos(2πn / (N-1))
```

**Visualization:**

```
Amplitude
1.0      ╱────────╲
        ╱          ╲
0.5    ╱            ╲
      │              │
0.08 └┘              └┘  ← Non-zero at endpoints
    └────────────────────► sample index
    0                  N-1
```

**Properties:**
- Main lobe width: 8π/N (same as Hann)
- Side lobe level: -43 dB (better than Hann)
- Equivalent noise bandwidth: 1.36 bins
- Does not go to zero at endpoints (slightly better side lobes)

**Implementation:**

```cpp
// Generate Hamming window
void generateHammingWindow(float* window, int N)
{
    for (int n = 0; n < N; n++)
    {
        window[n] = 0.54f - 0.46f * std::cos(2.0f * M_PI * n / (N - 1));
    }
}
```

**Use Cases:**
- When better side-lobe rejection than Hann is needed
- Spectral analysis where leakage is critical
- Classic choice in speech processing

### 6.5 Blackman Window

Provides excellent side-lobe rejection at the cost of wider main lobe.

**Definition:**

```
w[n] = 0.42 - 0.5 · cos(2πn / (N-1)) + 0.08 · cos(4πn / (N-1))
```

**Visualization:**

```
Amplitude
1.0       ╱───────╲
         ╱         ╲
0.5     ╱           ╲
       ╱             ╲
0.0   ╱               ╲
    └─────────────────────► sample index
    0                   N-1
```

**Properties:**
- Main lobe width: 12π/N (3× rectangular, wider than Hann)
- Side lobe level: -58 dB (excellent rejection)
- Equivalent noise bandwidth: 1.73 bins

**Implementation:**

```cpp
// Generate Blackman window
void generateBlackmanWindow(float* window, int N)
{
    for (int n = 0; n < N; n++)
    {
        float t = 2.0f * M_PI * n / (N - 1);
        window[n] = 0.42f - 0.5f * std::cos(t) + 0.08f * std::cos(2.0f * t);
    }
}
```

**Use Cases:**
- When maximum side-lobe rejection is needed
- High-precision spectral measurements
- When frequency resolution can be sacrificed

### 6.6 Window Comparison Table

```
Window        Main Lobe    Side Lobe    ENBW     Best For
              Width        Level        (bins)
──────────────────────────────────────────────────────────────
Rectangular   4π/N         -13 dB       1.00     Max resolution
Hann          8π/N         -31 dB       1.50     General purpose
Hamming       8π/N         -43 dB       1.36     Low leakage
Blackman      12π/N        -58 dB       1.73     Min leakage
```

**Frequency Domain Comparison:**

```
Magnitude (dB)
  0 ├─┐ Rect  ┌─Hann  ┌──Hamming  ┌───Blackman
    │ │       │       │           │
-20 │ ├─┐     ├──┐    ├───┐       ├────┐
    │ │ │     │  │    │   │       │    │
-40 │ │ ├─┐   │  ├──┐ │   ├───┐   │    ├────┐
    │ │ │ │   │  │  │ │   │   │   │    │    │
-60 │ │ │ ├─┐ │  │  ├─┤   │   ├───┼────┤    ├──
    └─┴─┴─┴─┴─┴──┴──┴─┴───┴───┴───┴────┴────┴──► Frequency
         ↑ narrow but high side lobes
                                   ↑ wide but very low side lobes
```

---

## 7. Conversions

### 7.1 Linear ↔ Decibel Conversions

**Linear to Decibels:**

```
dB = 20 · log₁₀(linear)
   = 20 · ln(linear) / ln(10)
   ≈ 8.686 · ln(linear)
```

**Decibels to Linear:**

```
linear = 10^(dB / 20)
       = e^(dB / 8.686)
```

**Common Conversions:**

```
Linear    Decibels      Change
──────────────────────────────
2.000     +6.02 dB     double
1.414     +3.01 dB     √2
1.000      0.00 dB     unity
0.707     -3.01 dB     1/√2
0.500     -6.02 dB     half
0.316    -10.00 dB
0.100    -20.00 dB     10%
0.010    -40.00 dB     1%
0.001    -60.00 dB     0.1%
```

**Surge's Custom Mapping:**

Surge uses a modified formula for perceptual scaling:

```cpp
// From: src/common/dsp/utilities/DSPUtils.h
inline float amp_to_db(float x)
{
    return std::clamp((float)(18.f * log2(x)), -192.f, 96.f);
}

inline float db_to_amp(float x)
{
    return std::clamp(powf(2.f, x / 18.f), 0.f, 2.f);
}
```

This uses base-2 logarithm with a factor of 18, different from the standard 20·log₁₀.

### 7.2 Frequency ↔ MIDI Note

**Frequency to MIDI Note:**

```
note = 69 + 12 · log₂(freq / 440)
```

**MIDI Note to Frequency:**

```
freq = 440 · 2^((note - 69) / 12)
```

**With Cents (Fine Tuning):**

```
freq = 440 · 2^((note + cents/100 - 69) / 12)
```

**Example Calculations:**

```cpp
// From Surge's codebase
// MIDI note to frequency (standard tuning)
float note_to_freq(float note)
{
    return 440.0f * std::pow(2.0f, (note - 69.0f) / 12.0f);
}

// Frequency to MIDI note
float freq_to_note(float freq)
{
    return 69.0f + 12.0f * std::log2(freq / 440.0f);
}

// Examples:
// note_to_freq(60) = 261.626 Hz (middle C)
// note_to_freq(69) = 440.0 Hz (A4)
// freq_to_note(880.0) = 81.0 (A5)
```

### 7.3 Cents to Frequency Ratio

**Cents** are logarithmic pitch units where 100 cents = 1 semitone.

**Cents to Frequency Ratio:**

```
ratio = 2^(cents / 1200)
```

**Frequency Ratio to Cents:**

```
cents = 1200 · log₂(ratio)
```

**Common Intervals:**

```
Cents    Ratio    Interval
───────────────────────────
0        1.0000   Unison
100      1.0595   Semitone
200      1.1225   Whole tone
700      1.4983   Perfect fifth
1200     2.0000   Octave
```

**Just Intonation Deviations:**

```
Interval           Equal Temp    Just Intonation    Deviation
──────────────────────────────────────────────────────────────
Major third (5/4)  400 cents     386 cents          -14 cents
Perfect fifth(3/2) 700 cents     702 cents          +2 cents
Minor seventh      1000 cents    969 cents          -31 cents
```

**Implementation:**

```cpp
// Detune oscillator by cents
float apply_detune(float frequency, float cents)
{
    return frequency * std::pow(2.0f, cents / 1200.0f);
}

// Example: Detune 440 Hz by +50 cents
// = 440 * 2^(50/1200) ≈ 452.9 Hz
```

### 7.4 Time ↔ Samples

**Time to Samples:**

```
samples = time · sample_rate
```

**Samples to Time:**

```
time = samples / sample_rate
```

**Practical Examples:**

At 48 kHz sample rate:

```
Time          Samples
─────────────────────
1 second      48,000
100 ms        4,800
10 ms         480
1 ms          48
20 μs         0.96  ≈ 1 sample period
```

**Delay Time Conversion:**

```cpp
// Convert milliseconds to samples
float ms_to_samples(float milliseconds, float sampleRate)
{
    return milliseconds * sampleRate / 1000.0f;
}

// Convert samples to milliseconds
float samples_to_ms(float samples, float sampleRate)
{
    return samples * 1000.0f / sampleRate;
}

// Example: 50ms delay at 48kHz
// samples = 50 * 48000 / 1000 = 2400 samples
```

**Frequency to Period:**

```
period_seconds = 1 / frequency
period_samples = sample_rate / frequency
```

**Example:**

```cpp
// For 440 Hz at 48 kHz sample rate:
float frequency = 440.0f;
float sampleRate = 48000.0f;

float period_seconds = 1.0f / frequency;  // = 0.002273 seconds
float period_samples = sampleRate / frequency;  // = 109.09 samples
```

### 7.5 Angular Frequency Conversions

**Linear Frequency to Angular Frequency:**

```
ω = 2πf  (radians/second)
```

**Normalized Angular Frequency** (for digital systems):

```
ω_n = 2πf / fs  (radians/sample)
```

Where:
- `ω_n` ranges from 0 to 2π
- At Nyquist frequency: `ω_n = π`

**Example:**

```cpp
// Convert 440 Hz to normalized angular frequency at 48 kHz
float f = 440.0f;
float fs = 48000.0f;

float omega = 2.0f * M_PI * f / fs;
// = 2π * 440 / 48000 ≈ 0.0576 radians/sample

// To advance a sine oscillator:
float phase = 0.0f;
for (int n = 0; n < numSamples; n++)
{
    output[n] = std::sin(phase);
    phase += omega;  // Advance by angular frequency
}
```

### 7.6 Q Factor ↔ Bandwidth

**Q to Bandwidth (in octaves):**

```
BW_octaves = 1 / Q
```

**More precisely:**

```
BW_octaves = 2 · log₂(sqrt(1 + 1/(2Q²)) + 1/(2Q))
```

**Q to Bandwidth (in Hz):**

```
BW_hz = fc / Q
```

Where `fc` is the center frequency.

**Bandwidth to Q:**

```
Q = fc / BW_hz
```

**Common Q Values:**

```
Q        BW (octaves)    Character
────────────────────────────────────
0.5      2.0             Very wide, gentle
0.707    1.4             Butterworth (flat)
1.0      1.0             Medium
2.0      0.5             Narrow
5.0      0.2             Sharp resonance
10.0     0.1             Very sharp
20.0+    <0.05           Self-oscillation
```

---

## Summary

This appendix has covered the essential mathematical foundations for understanding DSP in Surge XT:

1. **Signals and Systems**: Sampling theory, Nyquist frequency, and the digital representation of audio
2. **Fourier Analysis**: Decomposing signals into frequency components using Fourier transforms and FFT
3. **Digital Filters**: Transfer functions, z-transforms, poles, zeros, and stability
4. **Common Functions**: Trigonometric, exponential, logarithmic functions and their applications
5. **Interpolation**: Linear, cubic, Hermite, and Lagrange methods for smooth signal processing
6. **Windowing Functions**: Rectangular, Hann, Hamming, and Blackman windows for FFT analysis
7. **Conversions**: Essential formulas for translating between different audio representations

These mathematical tools appear throughout Surge's codebase and form the foundation for understanding oscillators, filters, effects, and modulation systems detailed in the main chapters.

---

## Further Reading

**Classic DSP Texts:**
- Oppenheim & Schafer: *Discrete-Time Signal Processing*
- Proakis & Manolakis: *Digital Signal Processing*
- Smith: *The Scientist and Engineer's Guide to Digital Signal Processing*

**Online Resources:**
- Julius O. Smith III: *Mathematics of the DFT* (CCRMA, Stanford)
- DSPRelated.com articles and tutorials
- Surge XT source code: `/home/user/surge/src/common/dsp/`

**Synthesis-Specific:**
- Will Pirkle: *Designing Software Synthesizer Plug-Ins in C++*
- Udo Zölzer: *Digital Audio Signal Processing*
- Välimäki et al.: Papers on virtual analog synthesis

---

**[Return to Index](00-INDEX.md)** | **[Next: Appendix B - Glossary](appendix-b-glossary.md)**
