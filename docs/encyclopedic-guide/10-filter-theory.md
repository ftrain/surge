# Chapter 10: Filter Theory

## The Art of Selective Attenuation

If oscillators are the voice of a synthesizer, filters are its character. They shape raw harmonic-rich waveforms into the myriad timbres we associate with classic and modern synthesis. A simple sawtooth wave becomes a warm analog pad, a percussive pluck, or a screaming lead - all through the application of filters.

Surge XT includes over 30 distinct filter types, each with unique sonic characteristics. This chapter explores the mathematical and conceptual foundations of digital filtering, preparing you for Chapter 11's deep dive into implementation details.

## Part 1: Filter Basics

### What Filters Do: Frequency Response

A filter is fundamentally a **frequency-selective attenuator**. It modifies the amplitude and phase of different frequency components of an input signal.

**Frequency Response** describes how a filter affects each frequency:

```
Input Signal (all frequencies)
        ↓
    [FILTER]
        ↓
Output Signal (some frequencies attenuated)
```

Consider a complex input signal containing three sine waves:
- 100 Hz (fundamental)
- 200 Hz (2nd harmonic)
- 400 Hz (4th harmonic)

A low-pass filter with cutoff at 250 Hz would:
- **Pass**: 100 Hz (below cutoff) → full amplitude
- **Pass**: 200 Hz (near cutoff) → partial amplitude
- **Reject**: 400 Hz (above cutoff) → greatly reduced amplitude

**Visualization: Frequency Response Curve**

```
Amplitude
    |
1.0 |████████╗
    |         ╚═╗
0.7 |           ╚═╗
    |             ╚═╗
0.5 |               ╚═╗
    |                 ╚═╗        (Low-pass Filter)
0.0 |___________________╚═══════════════════
    0   100  200  300  400  500  600  700   Frequency (Hz)
                  ↑
              Cutoff (300 Hz)
```

### Cutoff Frequency

The **cutoff frequency** (also called **corner frequency** or **-3dB point**) is where the filter's output drops to approximately 70.7% (-3dB) of its input amplitude.

**Why -3dB?**

In terms of power (energy), -3dB represents exactly half:
```
Power_ratio = 10^(-3/10) = 0.5
Amplitude_ratio = sqrt(0.5) = 0.707
```

At the cutoff frequency:
- **Amplitude**: 0.707 × input (70.7%)
- **Power**: 0.5 × input (50%)
- **Decibels**: -3dB

**Mathematical Definition**

For a simple first-order low-pass filter, the magnitude response at frequency ω is:

```
|H(ω)| = 1 / sqrt(1 + (ω/ωc)²)
```

Where:
- `H(ω)` = frequency response
- `ω` = angular frequency (2πf)
- `ωc` = cutoff angular frequency

At the cutoff frequency (ω = ωc):
```
|H(ωc)| = 1 / sqrt(1 + 1) = 1/sqrt(2) = 0.707
```

**In Surge XT:**

The cutoff frequency parameter typically ranges from ~14 Hz to ~25 kHz, providing musical control over timbral brightness. In the code, cutoff is often stored as a pitch value for exponential scaling:

```cpp
// Conceptual: Cutoff parameter to frequency conversion
float cutoff_hz = 440.0f * pow(2.0f, (cutoff_param - 69.0f) / 12.0f);
```

This gives 1 octave per 12 semitones, matching musical intuition.

### Resonance (Q Factor)

**Resonance** creates a peak in the frequency response at the cutoff frequency, emphasizing frequencies near the cutoff before attenuation begins.

**Q Factor** (Quality Factor) quantifies resonance:
```
Q = fc / Δf
```

Where:
- `fc` = center/cutoff frequency
- `Δf` = bandwidth (between -3dB points)

**Higher Q** = narrower peak, more pronounced resonance
**Lower Q** = broader response, gentler slope

**Visualization: Varying Resonance**

```
         Q = 10 (High Resonance)
           ╱╲
          ╱  ╲
         ╱    ╲________

         Q = 2 (Medium)
          ╱──╲
         ╱    ╲
        ╱      ╲______

         Q = 0.707 (Butterworth - No peak)
         ╱─╲
        ╱   ╲
       ╱     ╲________

    Frequency (Hz) →
```

**The Magic of Q = 0.707**

A Q of **0.707** (1/√2) is called a **Butterworth response** - maximally flat in the passband with no resonant peak. This is often the neutral, "musical" setting.

**Self-Oscillation**

At very high Q values (typically Q > 10-20), the filter's feedback becomes strong enough to create **self-oscillation** - the filter produces a sine wave at its cutoff frequency even with no input signal.

```cpp
// Conceptual: Resonance can make filter output exceed input
if (Q > self_oscillation_threshold)
{
    // Filter behaves as a sine wave oscillator
    // Output amplitude grows with each feedback cycle
}
```

This transforms the filter from a passive processor into an active sound source.

### Filter Slopes: Understanding Poles

The **slope** or **roll-off** of a filter describes how quickly it attenuates frequencies beyond the cutoff. This is measured in **decibels per octave (dB/oct)**.

**Filter Order and Poles**

Each **pole** in a filter contributes approximately **6 dB/octave** of attenuation:
- **1-pole** (1st order): ~6 dB/oct slope
- **2-pole** (2nd order): ~12 dB/oct slope
- **4-pole** (4th order): ~24 dB/oct slope

**Visualization: Filter Slopes**

```
 dB
  0 |████████╗
    |         ╚══╗ -6dB/oct (1-pole)
-12 |            ╚══╗
    |         ╚══╗   ╚══╗
-24 |      -12dB/oct  ╚══╗
    |         (2-pole)   ╚══╗
-36 |               ╚══╗    ╚══╗
    |            -24dB/oct   ╚══╗
-48 |               (4-pole)     ╚══╗
    |_________________________________
     fc   2fc  4fc   8fc  16fc      Frequency
         (1 octave increments)
```

**What "Poles" Mean**

A **pole** is a mathematical singularity in the filter's transfer function. Each pole represents:
- One **integrator** in analog circuits
- One **feedback delay** in digital implementations
- One **storage element** (capacitor/inductor in analog, memory in digital)

**Classic Filter Slopes in Synthesis:**

- **12 dB/oct (2-pole)**: Smooth, musical, vintage character
  - Examples: Many classic synths, the original Minimoog filter

- **24 dB/oct (4-pole)**: Sharp, aggressive, modern sound
  - Examples: Moog ladder filter, TB-303 filter
  - Doubles the attenuation speed compared to 12 dB/oct

**Trade-offs:**

| Aspect | 6-12 dB/oct | 24 dB/oct |
|--------|-------------|-----------|
| **Sound** | Gentle, transparent | Sharp, colored |
| **CPU** | Lighter | Heavier |
| **Resonance** | Subtle | Can be extreme |
| **Character** | Hi-fi, clean | Vintage, aggressive |

In Surge XT, you can choose between multiple slopes depending on the filter type, with some filters offering both 12 dB/oct and 24 dB/oct variants.

## Part 2: Filter Types

### Low-Pass Filters: Removing Highs

A **low-pass filter (LPF)** attenuates frequencies above its cutoff, allowing low frequencies to pass through.

**Frequency Response:**

```
Amplitude
    |
1.0 |████████╗
    |         ╚═══════╗
0.5 |                ╚═══════╗
    |                        ╚═══════╗
0.0 |________________________________╚═══════
    |        ↑
    0       fc      2fc      4fc     8fc   Frequency
                PASS  |  TRANSITION  | STOP
```

**Sound Character:**
- **High cutoff**: Bright, full-spectrum
- **Mid cutoff**: Warm, focused
- **Low cutoff**: Dark, muffled, sub-bass only

**Use Cases:**
- Synthesizer bass lines (cutting highs for warmth)
- Pad sounds (smooth, mellow timbres)
- Subtractive synthesis (starting with bright sawtooth, filtering down)
- Removing unwanted high-frequency noise

**In Analog:**
A simple RC (Resistor-Capacitor) circuit creates a 1-pole low-pass filter. Cascading multiple stages or using operational amplifiers creates steeper slopes.

**In Digital (difference equation for 1-pole LPF):**

```cpp
// Simple 1-pole low-pass filter
float lpf_1pole(float input, float &state, float coefficient)
{
    state = state + coefficient * (input - state);
    return state;
}

// coefficient = 1 - exp(-2π * cutoff_hz / sample_rate)
// Higher coefficient = higher cutoff frequency
```

### High-Pass Filters: Removing Lows

A **high-pass filter (HPF)** attenuates frequencies below its cutoff, allowing high frequencies to pass through.

**Frequency Response:**

```
Amplitude
    |                                    ████
1.0 |                             ╔══════
    |                      ╔═══════
0.5 |              ╔═══════
    |      ╔═══════
0.0 |══════
    |  ↑
    0  fc     2fc     4fc     8fc        Frequency
       STOP | TRANSITION |     PASS
```

**Sound Character:**
- **Low cutoff**: Full-range, only removes sub-bass rumble
- **Mid cutoff**: Thin, hollow, lacking body
- **High cutoff**: Clicks and transients only

**Use Cases:**
- Removing low-frequency rumble or DC offset
- Creating thin, telephone-like effects
- Emphasizing transients (e.g., drum snares)
- Bass management (cutting low end before mixing)

**Complementary Relationship:**

Low-pass and high-pass filters are **complementary** - if you sum the outputs of an LPF and HPF with the same cutoff and Q, you get the original signal (ideally).

```
LPF(signal) + HPF(signal) = original signal
```

**In Digital (1-pole HPF):**

```cpp
// Simple 1-pole high-pass filter
float hpf_1pole(float input, float &state, float coefficient)
{
    state = state + coefficient * (input - state);
    return input - state;  // Output is difference (high frequencies)
}
```

The high-pass output is simply the **difference** between input and low-pass output!

### Band-Pass Filters: Only the Middle

A **band-pass filter (BPF)** only passes frequencies within a specific band, attenuating both lower and higher frequencies.

**Frequency Response:**

```
Amplitude
    |
1.0 |              ╱──╲
    |             ╱    ╲
0.5 |            ╱      ╲
    |          ╱          ╲
0.0 |═════════            ═══════════
    |         ↑            ↑
    0        f1   fc      f2         Frequency
       STOP  | PASS |  STOP

    Bandwidth = f2 - f1
    Q = fc / (f2 - f1)
```

**Properties:**
- **Center frequency** (fc): The peak of the response
- **Bandwidth**: The range of passed frequencies (f2 - f1)
- **Q factor**: fc / bandwidth (higher Q = narrower band)

**Sound Character:**
- **Narrow bandwidth (high Q)**: Vocal, nasal, "formant-like" qualities
- **Wide bandwidth (low Q)**: Smooth, balanced midrange
- **Swept BPF**: Classic "wah" pedal effect

**Use Cases:**
- Isolating specific frequency ranges
- Vocal formant synthesis
- Creating resonant, hollow timbres
- Wah-wah and auto-wah effects

**Two Approaches:**

1. **Cascaded HPF + LPF**: High-pass then low-pass (or vice versa)
   - Simple but less efficient
   - Q is harder to control

2. **State Variable Filter**: Generates BPF directly from internal states
   - More efficient
   - Precise Q control
   - All three outputs (LP, BP, HP) available simultaneously

```cpp
// Conceptual: Band-pass as combination
float lpf_output = lowpass(input);
float bpf_output = highpass(lpf_output);

// Or equivalently:
float hpf_output = highpass(input);
float bpf_output = lowpass(hpf_output);
```

### Notch (Band-Reject) Filters

A **notch filter** (also called **band-reject** or **band-stop**) does the opposite of a band-pass: it attenuates a narrow band of frequencies while passing everything else.

**Frequency Response:**

```
Amplitude
    |
1.0 |████████╗           ╔════████
    |         ╚╗         ╔╝
0.5 |          ╚╗       ╔╝
    |           ╚╗     ╔╝
0.0 |            ╚═════╝
    |              ↓
    0             fc              Frequency
         PASS   REJECT   PASS
```

**Sound Character:**
- Creates a "hole" in the frequency spectrum
- Can make sounds feel hollow, phasey, or robotic
- Very narrow notches can remove specific problem frequencies

**Use Cases:**
- Removing 50/60 Hz AC hum
- Creating flanging/phasing effects (moving notch)
- Formant shifting
- Sound design: hollow, nasal, or telephone-like effects

**Mathematical Relationship:**

```
Notch(f) = Input - BandPass(f)
```

A notch filter is literally the input signal minus what a band-pass would extract!

```cpp
// Conceptual notch filter
float bandpass_out = bandpass(input, fc, Q);
float notch_out = input - bandpass_out;
```

**Comb Filtering Connection:**

Multiple notches spaced at harmonic intervals create a **comb filter** (see below).

### All-Pass Filters: Phase Without Amplitude

An **all-pass filter (APF)** is unique: it passes all frequencies at the same amplitude but shifts their **phase**.

**Frequency Response (Magnitude):**

```
Amplitude
    |
1.0 |████████████████████████████████
    |  (Flat - all frequencies pass equally)
0.0 |________________________________
    0                                Frequency
```

**Phase Response:**

```
Phase (degrees)
  0° |╗
     | ╚╗
-90° |  ╚╗
     |   ╚╗
-180°|    ╚══════
     |_____________________________
     0            fc               Frequency
```

**Why Is This Useful?**

Phase shifts create time delays that vary with frequency. When you mix an all-pass filtered signal with the original, the varying phase relationships cause **cancellation** and **reinforcement** at different frequencies, creating:

- **Phaser effects**: Multiple all-pass filters → swooshing, spacey sounds
- **Dispersion**: Simulating how sound travels through air or materials
- **Reverb**: Complex phase relationships mimic room acoustics
- **Stereo widening**: Phase differences between L/R channels

**Conceptual Code:**

```cpp
// All-pass filter maintains amplitude but shifts phase
float allpass_1pole(float input, float &state, float coefficient)
{
    float v = input - coefficient * state;
    float output = state + coefficient * v;
    state = v;
    return output;
}

// |output| = |input| for all frequencies
// But phase relationship varies with frequency
```

**Multiple All-Pass Stages:**

Cascading multiple all-pass filters with different cutoff frequencies creates the characteristic swooshing sound of a phaser:

```
Input → APF₁ → APF₂ → APF₃ → APF₄ → Mix with Input → Phaser Output
```

### Comb Filters: Harmonic Teeth

A **comb filter** creates a series of evenly-spaced peaks and notches in the frequency response, resembling a comb's teeth.

**Frequency Response:**

```
Amplitude
    |
1.0 |█╗ ╔█╗ ╔█╗ ╔█╗ ╔█╗ ╔█╗ ╔█
    | ╚╗╔╝╚╗╔╝╚╗╔╝╚╗╔╝╚╗╔╝╚╗╔╝
0.5 |  ╚╝  ╚╝  ╚╝  ╚╝  ╚╝  ╚╝
    |
0.0 |_____________________________
    0  f₀ 2f₀ 3f₀ 4f₀ 5f₀ 6f₀    Frequency

    Peaks at harmonics of fundamental f₀
```

**Two Types:**

1. **Feedforward Comb** (FIR - Finite Impulse Response):
   ```
   output = input + gain × delay(input, time)
   ```
   - Peaks at f₀, 2f₀, 3f₀...
   - Stable, no resonance buildup

2. **Feedback Comb** (IIR - Infinite Impulse Response):
   ```
   output = input + gain × delay(output, time)
   ```
   - Can resonate and ring
   - Used in reverb algorithms

**Sound Character:**
- **Metallic, resonant** timbres
- **Flanging effect** when delay time is modulated
- **Robotic or synthetic** vocal qualities
- **Pitched resonances** based on delay time

**Musical Application:**

When the delay time corresponds to a musical pitch:
```
delay_time = 1 / frequency
```

For example, 440 Hz (A4) requires a delay of:
```
delay = 1 / 440 Hz ≈ 2.27 milliseconds
```

The comb filter emphasizes that pitch and its harmonics, creating a tonal quality.

**In Surge XT:**

Surge includes both positive and negative comb filters (`fut_comb_pos` and `fut_comb_neg`):
- **Positive comb**: Emphasizes harmonics (peaks at harmonics)
- **Negative comb**: Cancels harmonics (notches at harmonics)

```cpp
// Conceptual comb filter
float comb_filter(float input, float *delay_line, int delay_samples, float gain)
{
    float delayed = delay_line[delay_samples];
    float output = input + gain * delayed;

    // Shift delay line and store new input
    shift_delay_line(delay_line, input);

    return output;
}
```

## Part 3: Digital Filter Mathematics

### From Analog to Digital: The Fundamental Challenge

Analog filters operate in **continuous time** - they process an infinite stream of voltage values. Digital filters work with **discrete samples** taken at regular intervals (e.g., 48,000 times per second).

The challenge: How do we translate analog filter designs (differential equations, Laplace transforms) into digital form (difference equations, Z-transforms)?

### Difference Equations: The Digital Filter Blueprint

A **difference equation** describes how a filter's output at time `n` depends on current/past inputs and outputs.

**General form:**

```
y[n] = b₀·x[n] + b₁·x[n-1] + b₂·x[n-2] + ...
       - a₁·y[n-1] - a₂·y[n-2] - ...
```

Where:
- `y[n]` = output at sample n (what we're calculating)
- `x[n]` = input at sample n
- `x[n-1], x[n-2]` = past input samples (feed-forward)
- `y[n-1], y[n-2]` = past output samples (feedback)
- `a₁, a₂, b₀, b₁, b₂` = filter coefficients (define frequency response)

**Example: Simple 1-Pole Low-Pass Filter**

```
y[n] = b₀·x[n] + b₁·x[n-1] - a₁·y[n-1]
```

More commonly written as:
```
y[n] = (1 - α)·y[n-1] + α·x[n]
```

Where `α` is the smoothing coefficient (0 to 1):
- `α = 0`: Output never changes (infinite smoothing)
- `α = 1`: Output = input (no filtering)
- `α = 0.1`: Smooth, gentle filtering
- `α = 0.9`: Fast response, minimal filtering

**In C++:**

```cpp
class OnePoleLP
{
    float y_prev = 0.0f;  // y[n-1]: previous output

public:
    float process(float input, float alpha)
    {
        // y[n] = (1 - α)·y[n-1] + α·x[n]
        float output = (1.0f - alpha) * y_prev + alpha * input;
        y_prev = output;  // Store for next iteration
        return output;
    }
};
```

**Calculating Alpha from Cutoff Frequency:**

```cpp
float calculate_alpha(float cutoff_hz, float sample_rate)
{
    float omega = 2.0f * M_PI * cutoff_hz / sample_rate;
    return 1.0f - expf(-omega);
}

// Example: 1 kHz cutoff at 48 kHz sample rate
// omega = 2π · 1000 / 48000 ≈ 0.1309
// alpha = 1 - exp(-0.1309) ≈ 0.1227
```

### Z-Transform Basics: The Digital Domain's Laplace

The **Z-transform** is to digital filters what the **Laplace transform** is to analog filters - a mathematical tool for analyzing system behavior in the frequency domain.

**Time Domain vs. Z-Domain:**

Time domain (difference equation):
```
y[n] = x[n] - x[n-1]
```

Z-domain (transfer function):
```
H(z) = Y(z)/X(z) = 1 - z⁻¹
```

**What is `z`?**

`z` represents a **one-sample delay**:
- `z⁻¹` = delay by 1 sample
- `z⁻²` = delay by 2 samples
- `z⁻ⁿ` = delay by n samples

**Why Use Z-Transform?**

1. **Converts difference equations into algebra**: Easier to manipulate
2. **Reveals stability**: Pole locations determine if filter is stable
3. **Shows frequency response**: Evaluate on the unit circle (`z = e^(jω)`)
4. **Facilitates design**: Transform analog designs to digital

**Example: 1-Pole Low-Pass in Z-Domain**

Time domain:
```
y[n] = α·x[n] + (1-α)·y[n-1]
```

Apply Z-transform:
```
Y(z) = α·X(z) + (1-α)·z⁻¹·Y(z)
```

Solve for transfer function:
```
H(z) = Y(z)/X(z) = α / (1 - (1-α)·z⁻¹)
```

**Pole location**: `z = (1-α)`, which is inside the unit circle (0 < α < 1), so the filter is **stable**.

**Frequency Response from Z-Transform:**

To get the frequency response, substitute `z = e^(jω)`:

```
H(e^(jω)) = α / (1 - (1-α)·e^(-jω))
```

The magnitude `|H(e^(jω))|` gives the amplitude response, and the angle gives the phase response.

**Key Concepts:**

- **Poles**: Values of z where H(z) → ∞ (determine resonance, stability)
- **Zeros**: Values of z where H(z) = 0 (determine notches)
- **Unit Circle**: |z| = 1 (represents all possible frequencies from DC to Nyquist)
- **Stability**: All poles must be inside the unit circle (|pole| < 1)

### Biquad Filters: The Workhorse Structure

The **biquad** (bi-quadratic) filter is the fundamental building block of most digital audio filters. It's called biquad because it has:
- **2 poles** (denominator is quadratic in z)
- **2 zeros** (numerator is quadratic in z)

**Biquad Difference Equation:**

```
y[n] = b₀·x[n] + b₁·x[n-1] + b₂·x[n-2]
       - a₁·y[n-1] - a₂·y[n-2]
```

**Z-Domain Transfer Function:**

```
         b₀ + b₁·z⁻¹ + b₂·z⁻²
H(z) = ───────────────────────
         1 + a₁·z⁻¹ + a₂·z⁻²
```

**Why Biquads Are Popular:**

1. **Versatile**: Can create LP, HP, BP, notch, allpass, peaking, shelving...
2. **Efficient**: Only 4 multiplies, 2 adds per sample (very CPU-friendly)
3. **Well-understood**: Decades of research, stable coefficient calculation
4. **Cascadable**: Multiple biquads in series create steeper slopes
5. **Numerically stable**: Direct Form I/II implementations work well

**Biquad Implementation (Direct Form I):**

```cpp
class Biquad
{
    // Coefficients (set by coefficient calculation)
    float b0, b1, b2;  // Feedforward (zeros)
    float a1, a2;      // Feedback (poles)

    // State (previous samples)
    float x1 = 0, x2 = 0;  // Previous inputs
    float y1 = 0, y2 = 0;  // Previous outputs

public:
    float process(float x0)  // x0 = current input
    {
        // Calculate output
        float y0 = b0*x0 + b1*x1 + b2*x2 - a1*y1 - a2*y2;

        // Update state (shift pipeline)
        x2 = x1; x1 = x0;  // Input history
        y2 = y1; y1 = y0;  // Output history

        return y0;
    }
};
```

**Direct Form II (Canonical Form):**

This form uses only **2 state variables** instead of 4, saving memory:

```cpp
class BiquadDF2
{
    float b0, b1, b2, a1, a2;
    float s1 = 0, s2 = 0;  // Only 2 state variables!

public:
    float process(float x0)
    {
        // Combined feedback and feedforward
        float s0 = x0 - a1*s1 - a2*s2;
        float y0 = b0*s0 + b1*s1 + b2*s2;

        // Update state
        s2 = s1; s1 = s0;

        return y0;
    }
};
```

**Coefficient Calculations for Different Filter Types:**

**Low-Pass Biquad:**

```cpp
void calculate_lowpass_coeffs(float fc, float Q, float fs,
                              float &b0, float &b1, float &b2,
                              float &a1, float &a2)
{
    float omega = 2.0f * M_PI * fc / fs;
    float sin_w = sinf(omega);
    float cos_w = cosf(omega);
    float alpha = sin_w / (2.0f * Q);

    float a0 = 1.0f + alpha;
    b0 = (1.0f - cos_w) / (2.0f * a0);
    b1 = (1.0f - cos_w) / a0;
    b2 = (1.0f - cos_w) / (2.0f * a0);
    a1 = (-2.0f * cos_w) / a0;
    a2 = (1.0f - alpha) / a0;
}
```

**High-Pass Biquad:**

```cpp
void calculate_highpass_coeffs(float fc, float Q, float fs,
                               float &b0, float &b1, float &b2,
                               float &a1, float &a2)
{
    float omega = 2.0f * M_PI * fc / fs;
    float sin_w = sinf(omega);
    float cos_w = cosf(omega);
    float alpha = sin_w / (2.0f * Q);

    float a0 = 1.0f + alpha;
    b0 = (1.0f + cos_w) / (2.0f * a0);
    b1 = -(1.0f + cos_w) / a0;
    b2 = (1.0f + cos_w) / (2.0f * a0);
    a1 = (-2.0f * cos_w) / a0;
    a2 = (1.0f - alpha) / a0;
}
```

**Band-Pass Biquad:**

```cpp
void calculate_bandpass_coeffs(float fc, float Q, float fs,
                               float &b0, float &b1, float &b2,
                               float &a1, float &a2)
{
    float omega = 2.0f * M_PI * fc / fs;
    float sin_w = sinf(omega);
    float cos_w = cosf(omega);
    float alpha = sin_w / (2.0f * Q);

    float a0 = 1.0f + alpha;
    b0 = alpha / a0;
    b1 = 0.0f;
    b2 = -alpha / a0;
    a1 = (-2.0f * cos_w) / a0;
    a2 = (1.0f - alpha) / a0;
}
```

**Creating Steeper Slopes:**

To create a 4-pole (24 dB/oct) filter, cascade two 2-pole (12 dB/oct) biquads:

```
Input → Biquad₁ → Biquad₂ → Output
       (2-pole)   (2-pole)
       = 4 poles total = 24 dB/oct
```

### State Variable Filters: The Swiss Army Knife

**State variable filters (SVF)** are a powerful alternative to biquads. They simultaneously generate **low-pass, band-pass, and high-pass outputs** from the same internal structure.

**The Classic Analog SVF Topology:**

```
        ┌─────────────────┐
Input ──┤ Integrator 1    ├─→ BP Output
        │  (creates LP    │
        │   from HP)      │
        └────────┬────────┘
                 ↓
        ┌────────┴────────┐
        │ Integrator 2    ├─→ LP Output
        │  (creates LP    │
        │   from BP)      │
        └─────────────────┘

HP Output = Input - Q·BP - LP
```

**Why SVF is Elegant:**

1. **Multiple outputs**: LP, BP, HP available simultaneously (no extra computation)
2. **Orthogonal control**: Cutoff and Q are independent
3. **Better at high Q**: More stable than biquads at extreme resonance
4. **Musical**: Smooth parameter changes, less "zipper noise"
5. **Self-oscillation**: Can easily be pushed into oscillation at high Q

**Difference Equations for Digital SVF:**

```
hp[n] = (input[n] - (1/Q)·bp[n-1] - lp[n-1]) / (1 + g/Q + g²)
bp[n] = g·hp[n] + bp[n-1]
lp[n] = g·bp[n] + lp[n-1]
```

Where:
- `g` = tan(π·fc/fs) ≈ frequency parameter
- `Q` = resonance parameter

**Implementation:**

```cpp
class StateVariableFilter
{
    float lp_state = 0;  // Low-pass integrator state
    float bp_state = 0;  // Band-pass integrator state

public:
    struct Outputs {
        float lp, bp, hp;
    };

    Outputs process(float input, float g, float Q_inv)  // Q_inv = 1/Q
    {
        // Calculate high-pass first (depends on previous states)
        float hp = (input - Q_inv * bp_state - lp_state) / (1.0f + g * Q_inv + g * g);

        // Integrate high-pass to get band-pass
        float bp = g * hp + bp_state;
        bp_state = bp;  // Update state

        // Integrate band-pass to get low-pass
        float lp = g * bp + lp_state;
        lp_state = lp;  // Update state

        return {lp, bp, hp};
    }
};
```

**Simplified Usage (Trapezoidal Integration):**

Chamberlin's digital SVF uses a simpler, more intuitive form:

```cpp
class ChamberlinSVF
{
    float lp = 0, bp = 0;

public:
    void process(float input, float f, float q)
    {
        // f = 2 * sin(π * fc / fs)  [frequency parameter]
        // q = resonance (higher = more resonance)

        lp = lp + f * bp;
        float hp = input - lp - q * bp;
        bp = bp + f * hp;

        // lp, bp, hp now contain the three filter outputs
    }
};
```

This is **two integrators in a feedback loop** - the essence of state variable filtering.

**Surge's VectorizedSVFilter:**

In `/home/user/surge/src/common/dsp/filters/VectorizedSVFilter.h`, Surge implements a SIMD-optimized SVF that processes 4 voices simultaneously:

```cpp
// From VectorizedSVFilter.h (conceptual)
inline vFloat CalcBPF(vFloat In)
{
    L1 = vMAdd(F1, B1, L1);  // L1 += F1 * B1 (integrator 1)
    vFloat H1 = vNMSub(Q, B1, vSub(vMul(In, Q), L1));  // Highpass calculation
    B1 = vMAdd(F1, H1, B1);  // B1 += F1 * H1 (integrator 1 output)

    L2 = vMAdd(F2, B2, L2);  // L2 += F2 * B2 (integrator 2)
    vFloat H2 = vNMSub(Q, B2, vSub(vMul(B1, Q), L2));  // Second stage HP
    B2 = vMAdd(F2, H2, B2);  // B2 += F2 * H2 (integrator 2 output)

    return B2;  // Band-pass output
}
```

This processes **4 voices in parallel** using SSE/SIMD instructions, achieving massive performance gains.

## Part 4: Resonance and Self-Oscillation

### Feedback: The Source of Resonance

**Resonance** arises from **positive feedback** in a filter. A portion of the output is fed back to the input, reinforcing certain frequencies.

**Block Diagram:**

```
         ┌─────────────┐
Input ───┤   Filter    ├─── Output
    ↑    └──────┬──────┘      │
    │           │             │
    │    ┌──────┴──────┐      │
    └────┤  Feedback   │←─────┘
         │  (×gain)    │
         └─────────────┘
```

**Feedback Loop Equation:**

```
output = filter(input + feedback_gain × output)
```

If `feedback_gain` is small, we get gentle resonance. As gain increases:
1. **Mild resonance**: Slight peak at cutoff
2. **Strong resonance**: Pronounced peak, ringing on transients
3. **Critical resonance**: At threshold of oscillation
4. **Self-oscillation**: Filter produces tone without input

**Mathematical Perspective:**

Feedback reduces the filter's damping, moving poles closer to the unit circle (in Z-domain) or imaginary axis (in Laplace domain):

```
H_with_feedback(z) = H(z) / (1 - k·H(z))
```

Where `k` is feedback gain. As `k` approaches certain critical values, the denominator approaches zero at specific frequencies, creating resonance.

### The Onset of Self-Oscillation

**Self-oscillation** occurs when the filter's feedback loop has:
- **Gain ≥ 1** at some frequency
- **Phase shift = 360°** (or 0°, equivalently)

These conditions satisfy the **Barkhausen criterion** for oscillation - the loop becomes a self-sustaining oscillator.

**In Practical Terms:**

At high Q values (typically Q > 10-20), the filter becomes unstable in a controlled way:
- It produces a **sine wave** at its cutoff frequency
- The amplitude depends on Q and any input signal
- The pitch tracks the cutoff frequency parameter

**Why This Is Musically Useful:**

1. **Extra oscillator**: The filter becomes a tunable sine wave source
2. **Animated drones**: Self-oscillating filter sweeps create evolving textures
3. **Classic acid sounds**: TB-303 style basslines rely on resonant filter sweeps
4. **Pitched resonance**: Even below full oscillation, high Q creates pitched character

**Implementation Challenges:**

```cpp
// Naïve implementation can explode at high Q!
float svf_with_resonance(float input, float cutoff, float Q)
{
    // If Q is too high, output can grow unbounded
    float hp = input - (1.0f / Q) * bp - lp;

    // Feedback: bp and lp depend on previous hp
    bp += cutoff * hp;
    lp += cutoff * bp;

    // Problem: At high Q, hp magnitude increases each iteration
    // Solution: Careful coefficient calculation and soft-clipping

    return lp;
}
```

**Stabilization Techniques:**

1. **Coefficient limiting**: Cap Q at reasonable maximum (Q = 100 typical)
2. **Soft-clipping**: Gently compress filter internals to prevent explosion
   ```cpp
   hp = tanhf(hp);  // Soft-clip highpass to [-1, +1]
   ```
3. **Normalized feedback**: Scale feedback to maintain unity gain at resonance
4. **Input attenuation**: Reduce input amplitude at high Q to prevent overload

**Surge's Approach:**

Most Surge filters include resonance limiting and optional soft-clipping to ensure stability even at extreme settings, while still allowing self-oscillation for creative use.

### Musical Applications of Self-Oscillation

**1. Classic Acid Basslines (TB-303 style):**

```
Sawtooth Oscillator → Resonant LP Filter (Q = 15) → Output
                      ↑
                      Envelope modulates cutoff

As envelope sweeps cutoff, filter adds pitched resonance
At high Q, creates signature "squelch" and "screaming" sounds
```

**2. Resonant Filter Sweeps:**

Automate cutoff frequency while maintaining high Q:
```
Cutoff: 100 Hz → 2000 Hz → 100 Hz (over 4 bars)
Q: 20 (constant)
Input: Any sound source (or even silence!)

Result: Sweeping sine wave that tracks the cutoff parameter
```

**3. Formant Synthesis:**

Multiple band-pass filters at high Q tuned to vowel formants:
```
Input → BP₁ (800 Hz, Q=10) ─┐
      → BP₂ (1200 Hz, Q=10) ─┼─→ "Ah" vowel sound
      → BP₃ (2500 Hz, Q=10) ─┘
```

**4. "Playing" the Filter:**

Map MIDI notes to filter cutoff frequency, use filter as a sine oscillator:
```
MIDI Note → Frequency → Filter Cutoff (Q = max)
No oscillator input needed!
Filter itself produces pitched sine tones
```

## Part 5: Surge's Filter Topology Overview

Surge XT includes **36 distinct filter types** (as of version 1.3+), each with unique sonic character and mathematical implementation. Let's explore the categories and key examples.

### Filter Categories (From FilterConfiguration.h)

From `/home/user/surge/src/common/FilterConfiguration.h`, Surge organizes filters into six groups:

1. **Lowpass** - 10 types
2. **Bandpass** - 5 types
3. **Highpass** - 6 types
4. **Notch** - 5 types
5. **Multi** - 3 types (selectable response)
6. **Effect** - 6 types (phase, comb, special)

### Complete Filter Type List

```cpp
// From FilterConfiguration.h, lines 92-143
enum FilterType
{
    fut_none = 0,           // No filtering

    // Lowpass Filters (10 types)
    fut_lp12,               // 12 dB/oct (2-pole)
    fut_lp24,               // 24 dB/oct (4-pole)
    fut_lpmoog,             // Moog ladder (4-pole)
    fut_vintageladder,      // Vintage ladder with nonlinearity
    fut_k35_lp,             // Korg 35 lowpass
    fut_diode,              // Diode ladder (TB-303 style)
    fut_obxd_2pole_lp,      // OB-Xd 2-pole lowpass
    fut_obxd_4pole,         // OB-Xd 4-pole multimode
    fut_cutoffwarp_lp,      // Cutoff warp lowpass
    fut_resonancewarp_lp,   // Resonance warp lowpass

    // Bandpass Filters (5 types)
    fut_bp12,               // 12 dB/oct (2-pole)
    fut_bp24,               // 24 dB/oct (4-pole)
    fut_obxd_2pole_bp,      // OB-Xd 2-pole bandpass
    fut_cutoffwarp_bp,      // Cutoff warp bandpass
    fut_resonancewarp_bp,   // Resonance warp bandpass

    // Highpass Filters (6 types)
    fut_hp12,               // 12 dB/oct (2-pole)
    fut_hp24,               // 24 dB/oct (4-pole)
    fut_k35_hp,             // Korg 35 highpass
    fut_obxd_2pole_hp,      // OB-Xd 2-pole highpass
    fut_cutoffwarp_hp,      // Cutoff warp highpass
    fut_resonancewarp_hp,   // Resonance warp highpass

    // Notch Filters (5 types)
    fut_notch12,            // 12 dB/oct (2-pole)
    fut_notch24,            // 24 dB/oct (4-pole)
    fut_obxd_2pole_n,       // OB-Xd 2-pole notch
    fut_cutoffwarp_n,       // Cutoff warp notch
    fut_resonancewarp_n,    // Resonance warp notch

    // Multi-Mode Filters (3 types)
    fut_cytomic_svf,        // Cytomic SVF (selectable mode)
    fut_tripole,            // Three-pole OTA filter
    fut_obxd_xpander,       // OB-Xpander multimode

    // Effect Filters (6 types)
    fut_apf,                // All-pass filter
    fut_cutoffwarp_ap,      // Cutoff warp allpass
    fut_resonancewarp_ap,   // Resonance warp allpass
    fut_comb_pos,           // Comb filter (positive)
    fut_comb_neg,           // Comb filter (negative)
    fut_SNH,                // Sample & Hold
};
```

### Key Filter Families

#### 1. Standard Biquad Filters

The foundation: clean, efficient, CPU-friendly filters based on biquad topology.

**Types**: `fut_lp12`, `fut_lp24`, `fut_hp12`, `fut_hp24`, `fut_bp12`, `fut_bp24`, `fut_notch12`, `fut_notch24`

**Characteristics:**
- **Transparent**: Minimal coloration, faithful to input
- **Efficient**: Optimized coefficient calculation
- **Predictable**: Standard frequency response
- **Stable**: Well-behaved at all settings

**Use cases:**
- General-purpose filtering
- Hi-fi sound design
- When CPU efficiency matters
- Stacking multiple filter stages

**Under the hood:**
Implemented using standard biquad difference equations with carefully calculated coefficients from the cookbook formulas (Robert Bristow-Johnson).

#### 2. Ladder Filters (Moog-Style)

Emulations of the iconic **Moog ladder filter** - the sound of countless classic synthesizers.

**Types**: `fut_lpmoog`, `fut_vintageladder`, `fut_diode`

**The Moog Ladder Topology:**

```
Input → [Stage 1] → [Stage 2] → [Stage 3] → [Stage 4] → Output
         (LP)        (LP)        (LP)        (LP)          ↓
          ↑                                                 │
          │                 Feedback (resonance)           │
          └─────────────────────────────────────────────────┘

Four cascaded 1-pole lowpass filters with global feedback
= 4 poles = 24 dB/oct rolloff
```

**Characteristics:**
- **Warm, musical**: Natural saturation and nonlinearity
- **Strong resonance**: Can self-oscillate beautifully
- **Low-end emphasis**: Slightly peaked bass response
- **Classic sound**: The sound of the Minimoog, Voyager, etc.

**Differences between types:**

- **`fut_lpmoog`**: Clean digital emulation, no saturation
- **`fut_vintageladder`**: Adds nonlinear saturation, more "analog" dirt
- **`fut_diode`**: Models transistor diodes instead of transistor ladder (TB-303 style)

**Why the ladder sounds special:**

Each stage contributes subtle nonlinearity. When driven hard, the filter gently saturates, adding harmonics. The global feedback path creates strong, musical resonance.

**Conceptual structure:**

```cpp
class LadderFilter
{
    float stage[4] = {0, 0, 0, 0};  // Four 1-pole stages

public:
    float process(float input, float cutoff, float resonance)
    {
        // Global feedback: output → input
        float feedback = resonance * stage[3];
        input -= feedback * 4.0f;  // High resonance = strong feedback

        // Cascade four 1-pole lowpass stages
        for (int i = 0; i < 4; i++)
        {
            stage[i] += cutoff * (input - stage[i]);
            input = stage[i];  // Output of this stage → input of next

            // Optional: Add saturation for vintage character
            input = tanhf(input);
        }

        return stage[3];  // Output of final stage
    }
};
```

#### 3. State Variable Filters (SVF)

Elegant, versatile filters that generate multiple outputs simultaneously.

**Types**: `fut_cytomic_svf`, `fut_tripole`

**`fut_cytomic_svf`** - Based on Andrew Simper's research at Cytomic:
- Topology-preserving transform (TPT) method
- Highly stable even at extreme settings
- Selectable filter mode via subtype parameter
- Excellent for modulation (smooth parameter changes)

**Cytomic SVF Structure:**

```
            ┌──────────────┐
Input ──────┤  Integrator  ├──→ Band-Pass
            └──────┬───────┘
                   ↓
            ┌──────┴───────┐
            │  Integrator  ├──→ Low-Pass
            └──────────────┘

High-Pass = Input - Q·BP - LP
Notch = LP + HP
All-Pass = LP - BP + HP
```

All five responses (LP, BP, HP, Notch, AP) are available from the same structure!

**`fut_tripole`** - A three-pole (18 dB/oct) OTA-style filter:
- Asymmetric slope (between 12 and 24 dB/oct)
- Unique character from odd-order response
- Modes available via subtype

**Why SVF is powerful:**

1. **No cookbook formulas needed**: Direct frequency and Q parameters
2. **Orthogonal control**: Changing frequency doesn't affect Q
3. **Smooth modulation**: Parameters can be changed without discontinuities
4. **Multiple outputs**: "Free" LP/BP/HP from same computation

#### 4. OB-Xd Filters (Oberheim Xpander Emulation)

Modeled after the legendary **Oberheim Xpander** synthesizer filters.

**Types**: `fut_obxd_2pole_lp`, `fut_obxd_2pole_hp`, `fut_obxd_2pole_bp`, `fut_obxd_2pole_n`, `fut_obxd_4pole`, `fut_obxd_xpander`

**Characteristics:**
- **Rich, complex response**: Non-standard topology
- **Multimode capability**: Many modes available
- **Vintage character**: Emulates analog circuit behavior
- **Flexible**: Great for both subtle and extreme sounds

The Oberheim filters use a state variable topology with additional mixing and feedback paths, creating a distinctive, slightly asymmetric response.

#### 5. Korg 35 Filters

Based on the **MS-20's** iconic filters.

**Types**: `fut_k35_lp`, `fut_k35_hp`

**Characteristics:**
- **Aggressive resonance**: Can be very harsh and screaming
- **High-pass is unique**: Very sharp, distinctive character
- **Sallen-Key topology**: Different from ladder and SVF
- **Excellent for aggressive sounds**: Industrial, acid, harsh leads

The Korg 35 high-pass filter is particularly famous for its extreme resonance and aggressive character when pushed hard.

#### 6. Warp Filters

Modern filter designs with extended parameter ranges and creative flexibility.

**Types**: `fut_cutoffwarp_*`, `fut_resonancewarp_*`

**Cutoff Warp Filters:**
- Extended cutoff range
- Can go below and above standard limits
- Useful for extreme sound design

**Resonance Warp Filters:**
- Extended resonance range
- More controllable self-oscillation
- Better for extreme feedback effects

These are enhanced versions of standard filter types, optimized for parameter modulation and extreme settings.

#### 7. Effect Filters

Special-purpose filters for creative effects rather than traditional synthesis.

**`fut_apf` (All-Pass):**
- Passes all frequencies equally (flat amplitude response)
- Shifts phase relationships
- Used for phaser effects, dispersion, stereo imaging

**`fut_comb_pos` and `fut_comb_neg` (Comb Filters):**
- Creates harmonic peaks/notches
- **Positive comb**: Feedforward (emphasizes harmonics)
- **Negative comb**: Feedback inverted (cancels harmonics)
- Metallic, resonant character
- Delay time sets fundamental frequency

**`fut_SNH` (Sample & Hold):**
- Not a traditional filter!
- Samples input at irregular intervals
- Creates stepped, "digital" artifacts
- Great for glitchy, lo-fi effects
- Responds to cutoff parameter as sample rate

### Filter Subtypes and Variations

Many Surge filters offer **subtypes** - variations accessed through the filter subtype parameter:

**Example: OB-Xd 4-Pole (`fut_obxd_4pole`)**
- Subtype 0: Standard 4-pole lowpass
- Subtype 1: With half-ladder feedback
- Subtype 2: With notch mixing
- Subtype 3: Bandpass variation
- ... (up to 7 subtypes)

Each subtype represents a different internal routing or mixing strategy, giving dozens of variations from a single filter type.

### Choosing the Right Filter

**For warm, vintage bass:**
- `fut_lpmoog` (Moog ladder)
- `fut_vintageladder` (with saturation)
- Q around 3-5, moderate cutoff

**For aggressive, screaming leads:**
- `fut_k35_hp` (Korg 35 highpass)
- `fut_diode` (TB-303 style)
- High Q (8-15), swept cutoff

**For clean, transparent filtering:**
- `fut_lp12` or `fut_lp24` (standard biquad)
- `fut_cytomic_svf` (state variable)
- Lower Q (0.707 to 2)

**For special effects:**
- `fut_comb_pos` or `fut_comb_neg` (metallic tones)
- `fut_apf` (phaser building block)
- `fut_SNH` (lo-fi, digital artifacts)

**For modulation and animation:**
- `fut_cytomic_svf` (smooth parameter changes)
- `fut_resonancewarp_*` (extended modulation range)
- Any filter with high Q for self-oscillation

### The Quad Filter Chain

In Surge's voice architecture, filters are processed through the **QuadFilterChain** - a SIMD-optimized structure that processes **4 voices simultaneously**.

**Why "Quad"?**

Modern CPUs have SIMD (Single Instruction, Multiple Data) instructions that operate on 4 floats at once:

```
Standard Processing (4x slower):
Voice 1: process_filter()
Voice 2: process_filter()
Voice 3: process_filter()
Voice 4: process_filter()

SIMD Quad Processing (4x faster):
Voices [1,2,3,4]: process_filter_quad()  // All four at once!
```

This is why Surge can achieve such high polyphony - filters (the most CPU-intensive part of synthesis) are vectorized using SSE/AVX instructions.

**Conceptual structure:**

```cpp
// Simplified conceptual view (actual code in SST library)
class QuadFilterChain
{
    // Each variable holds 4 values (one per voice)
    __m128 state_lp[4];  // Lowpass states for 4 voices
    __m128 state_bp[4];  // Bandpass states for 4 voices

public:
    __m128 process(__m128 input_quad, __m128 cutoff_quad, __m128 res_quad)
    {
        // Process 4 voices worth of filtering in one operation
        // Using SSE intrinsics for parallelism
        return filtered_output_quad;
    }
};
```

This is covered in detail in **Chapter 11: Filter Implementation**.

## Conclusion: The Palette of Timbre

Filters are the paintbrush of subtractive synthesis. With Surge's 36 filter types spanning:
- Clean digital precision (biquads)
- Warm analog emulation (ladder filters)
- Mathematical elegance (state variable)
- Vintage character (Oberheim, Korg)
- Creative effects (comb, all-pass)

...you have an unprecedented palette for sculpting sound. Understanding the theory behind frequency response, resonance, poles and zeros, and digital filter mathematics empowers you to choose the right tool and use it expressively.

In **Chapter 11: Filter Implementation**, we'll dive into the code - examining how these theoretical concepts are realized in high-performance C++, exploring the SST filter library, and learning how to add custom filters to Surge.

**Key Takeaways:**

1. **Filters are frequency-selective attenuators** - they shape spectra
2. **Cutoff frequency** defines the transition point (-3dB)
3. **Resonance (Q factor)** creates emphasis at the cutoff
4. **Filter slopes** (6/12/24 dB/oct) determine attenuation steepness
5. **Biquad filters** (2 poles, 2 zeros) are the digital workhorse
6. **State variable filters** generate multiple outputs elegantly
7. **Self-oscillation** transforms filters into oscillators at high Q
8. **Surge offers 36+ filter types** covering every synthesis need
9. **Ladder filters** (Moog-style) provide classic analog warmth
10. **Quad processing** achieves 4× performance through SIMD

---

**Next: [Chapter 11: Filter Implementation](11-filter-implementation.md)** - From theory to code: exploring Surge's filter architecture, the SST library, QuadFilterChain SIMD optimization, and implementing custom filters.

**Previous: [Chapter 9: Advanced Oscillators](09-oscillators-advanced.md)**

---

## References and Further Reading

**Classic Papers:**
- Robert Bristow-Johnson, "Cookbook Formulae for Audio EQ Biquad Filter Coefficients" (1994)
- Andrew Simper, "Cytomic SVF" topology-preserving transform method
- Hal Chamberlin, "Musical Applications of Microprocessors" (1980) - Digital SVF

**Books:**
- Julius O. Smith III, "Introduction to Digital Filters with Audio Applications"
- Will Pirkle, "Designing Audio Effect Plugins in C++"
- Udo Zölzer, "Digital Audio Signal Processing"

**Online Resources:**
- musicdsp.org - Archive of DSP algorithms and discussions
- kvraudio.com DSP forum - Active community of filter designers
- Cytomic technical papers (cytomic.com) - Modern filter design

**Historical Synthesizers:**
- Minimoog Model D - Iconic 4-pole ladder filter
- TB-303 - Diode ladder filter (acid bass)
- Oberheim Xpander - Complex multimode state variable filters
- Korg MS-20 - Aggressive Sallen-Key filters

---

**File Reference:**
- `/home/user/surge/src/common/FilterConfiguration.h` - Filter type definitions and organization
- `/home/user/surge/src/common/dsp/filters/BiquadFilter.h` - Biquad implementation wrapper
- `/home/user/surge/src/common/dsp/filters/VectorizedSVFilter.h` - SIMD state variable filter
- `/home/user/surge/libs/sst/sst-filters/` - SST filter library (implementation in Chapter 11)

---

*This chapter is part of the Surge XT Encyclopedic Guide. © 2025 Surge Synth Team. Licensed under GPL-3.0.*
