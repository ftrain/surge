# Chapter 21: MSEG - Multi-Segment Envelope Generator

## The Art of Freeform Modulation

If traditional ADSR envelopes are like drawing with a ruler and compass, the **Multi-Segment Envelope Generator (MSEG)** is like drawing freehand with complete artistic control. MSEG allows you to design arbitrary modulation contours by connecting segments of different types—linear ramps, smooth curves, steps, holds, and even oscillating waveforms—into complex, evolving shapes that would be impossible with conventional envelopes.

This chapter explores Surge's powerful MSEG system in depth: the theory behind multi-segment envelopes, the rich palette of segment types, the flexible loop and playback modes, the sophisticated graphical editor, and the implementation details that make MSEG one of Surge's most creative modulation sources.

## MSEG Fundamentals

### What is MSEG?

A **Multi-Segment Envelope Generator** is a modulation source that produces a control signal defined by a sequence of user-drawn **segments**. Each segment represents a portion of the envelope with its own:

- **Duration**: How long the segment lasts
- **Start value**: The level at the segment's beginning
- **End value**: The level at the segment's end
- **Curve type**: How the segment interpolates between start and end
- **Control parameters**: Additional shaping controls specific to the curve type

**Key characteristics:**

- **Arbitrary shapes**: Not limited to ADSR contours
- **Visual editing**: Draw envelopes graphically in real-time
- **Flexible timing**: Each segment can have independent duration
- **Rich curves**: Multiple interpolation types (linear, bezier, s-curve, etc.)
- **Dual modes**: Works as one-shot envelope or looping LFO
- **Tempo sync**: All timings can lock to host tempo

### MSEG vs. ADSR: When to Use Each

**Use ADSR when you want:**
- Classic, predictable envelope shapes
- Fast workflow with familiar parameters
- Analog-style exponential curves
- Standard attack-decay-sustain-release behavior

**Use MSEG when you want:**
- Complex, multi-stage envelopes
- Custom modulation shapes that don't fit ADSR
- Rhythmic sequences and step patterns
- LFO replacement with custom waveforms
- Generative, evolving modulation

**Example comparison:**

```
ADSR Envelope:
    ╱╲___
   ╱  S  ╲___

MSEG Can Do:
    ╱╲  ╱╲
   ╱  ╲╱  ╲___╱╲___
  Complex multi-peak envelope
```

### Common MSEG Use Cases

#### 1. Complex Filter Sweeps

Create multi-stage filter movements that evolve through different timbral regions:

```
Cutoff (Hz)
  8000┤    ╱╲
      │   ╱  ╲___
  2000│  ╱       ╲___
      │ ╱            ╲___
   500└─────────────────────→ Time
     Initial    Sustain    Release
     bright     mellow     dark
```

#### 2. Rhythmic Gating

Design tempo-synced amplitude patterns for rhythmic effects:

```
Amplitude
    1┤ ┌─┐ ┌─┐   ┌─┐
     │ │ │ │ │   │ │
    0└─┘ └─┘ └───┘ └─
     1/16 note pattern
```

#### 3. Generative Sequences

Use MSEG as a melodic sequencer by modulating pitch:

```
Pitch
  +12┤     ╱──╲
      │    ╱    ╲
   +7 │   ╱      ╲──
      │  ╱          ╲
    0 └──────────────╲
     Pentatonic melody
```

#### 4. LFO Replacement with Custom Waveforms

Create unique oscillating shapes impossible with standard LFO waveforms:

```
Custom LFO
    1┤  ╱╲    ╱╲
     │ ╱  ╲  ╱  ╲
    0├─    ╲╱    ─
     │
   -1│
     └──────────────→
     Asymmetric vibrato
```

## MSEG Segment Types

Surge provides thirteen distinct segment types, each with unique interpolation characteristics. Understanding these types is key to mastering MSEG.

### Linear

The simplest segment type: a straight line from start to end.

**Characteristics:**
- Constant rate of change
- Predictable, precise
- No overshoot or bounce
- Good for direct, mechanical movements

**Mathematical definition:**

```cpp
// File: src/common/dsp/modulators/MSEGModulationHelper.cpp
case MSEGStorage::segment::LINEAR:
{
    float frac = timeAlongSegment / r.duration;
    res = lv0 + frac * (lv1 - lv0);  // Simple linear interpolation
    break;
}
```

**Visual representation:**

```
  1.0┤        ╱
     │       ╱
  0.5│      ╱
     │     ╱
  0.0└────┴────────→ Time
     0   0.5   1.0
```

**Use cases:**
- Percussive attacks
- Precise ramps
- Step sequencer bases

### Bezier Curves (Quadratic Bezier)

Smooth curves with adjustable control points, borrowed from vector graphics.

**Characteristics:**
- Smooth, natural curves
- User-adjustable curvature via control point
- No hard corners
- Control point position affects shape dramatically

**Mathematical definition:**

A quadratic Bezier curve uses three points:
- P0 (start): `lv0`
- P1 (control): `cpv` at time `cpduration`
- P2 (end): `lv1`

```cpp
// Bezier evaluation (simplified)
// B(t) = (1-t)² × P0 + 2(1-t)t × P1 + t² × P2

case MSEGStorage::segment::QUAD_BEZIER:
{
    float cpv = lcpv;  // Control point value
    float cpt = r.cpduration * r.duration;  // Control point time

    // Solve for t given the time target
    // Then evaluate Bezier curve at that t
    float py0 = lv0;
    float py1 = cpv;
    float py2 = lv1;

    res = (1 - t) * (1 - t) * py0 + 2 * (1 - t) * t * py1 + t * t * py2;
    break;
}
```

**Visual representation:**

```
Control point high:
  1.0┤        ┌───╮
     │      ╱      ╲
  0.5│   cp         ╲
     │  ╱            ╲
  0.0└──              ─→

Control point low:
  1.0┤  ╱──────────╮
     │╱            │
  0.5│             cp
     │              ╲
  0.0└               ╲→
```

**Use cases:**
- Natural filter sweeps
- Organic modulation curves
- Easing in/out transitions
- Vocal-like formant movements

### S-Curve

An S-shaped curve that starts slow, accelerates, then slows again—perfect for smooth transitions.

**Characteristics:**
- Symmetric acceleration/deceleration
- Smooth at both endpoints
- Deform parameter controls steepness
- Musical, organic feel

**Mathematical definition:**

```cpp
case MSEGStorage::segment::SCURVE:
{
    float frac = timeAlongSegment / r.duration;

    // S-Curve is implemented as two mirrored deformed lines
    // Split at the midpoint
    if (frac < 0.5)
        frac = frac * 2;  // First half
    else
        frac = (frac - 0.5) * 2;  // Second half (mirrored)

    // Apply exponential deform for S-shape
    // (Actual implementation uses exponential curves)
    res = lv0 + curve * (lv1 - lv0);
    break;
}
```

**Deform parameter effect:**

```
Deform = 0 (linear):
  1.0┤       ╱
     │      ╱
  0.5│     ╱
     │    ╱
  0.0└───┴─────→

Deform > 0 (steep):
  1.0┤     ╱──
     │    ╱
  0.5│   │
     │ ──╯
  0.0└─────────→

Deform < 0 (gentle):
  1.0┤   ╭───
     │  ╱
  0.5│ │
     │ ╰╮
  0.0└──╯──────→
```

**Use cases:**
- Smooth parameter transitions
- Realistic pitch bends
- Gentle amplitude swells
- Crossfades

### Bump (Gaussian)

A bell-shaped curve that peaks in the middle, based on the Gaussian function.

**Characteristics:**
- Symmetric bump centered at segment midpoint
- Control point sets the peak height
- Deform parameter controls width/sharpness
- Always returns to the linear interpolation line

**Mathematical definition:**

```cpp
// File: src/common/dsp/modulators/MSEGModulationHelper.cpp
case MSEGStorage::segment::BUMP:
{
    auto t = timeAlongSegment / r.duration;

    // Deform controls the "sharpness" of the Gaussian
    auto d = (-df * 0.5) + 0.5;
    auto deform = 20.f + ((d * d * d) * 500.f);

    // Gaussian: e^(-k(t-0.5)²)
    auto g = exp(-deform * (t - 0.5) * (t - 0.5));

    // Linear baseline
    auto l = ((lv1 - lv0) * t) + lv0;

    // Control point defines peak height above/below baseline
    auto q = c - ((lv0 + lv1) * 0.5);

    res = l + (q * g);  // Add Gaussian bump to linear baseline
    break;
}
```

**Visual representation:**

```
Positive bump (cpv > midpoint):
  1.5┤      ╱╲
     │     ╱  ╲
  1.0│    ╱    ╲
     │ ──╯      ╰──
  0.5└─────────────→

Negative bump (cpv < midpoint):
  1.0┤ ──╮      ╭──
     │    ╲    ╱
  0.5│     ╲  ╱
     │      ╲╱
  0.0└─────────────→

Deform controls width:
Sharp (df > 0):     Gentle (df < 0):
    ╱╲                  ╱───╲
   ╱  ╲               ╱      ╲
```

**Use cases:**
- Accent notes in sequences
- Emphasis on specific beats
- Formant-like resonance sweeps
- Decorative modulation flourishes

### Step (Stairs)

Quantized steps that jump between discrete values.

**Characteristics:**
- Hard transitions (no interpolation)
- Control point determines number of steps
- Deform parameter affects step distribution
- Perfect for sample-and-hold effects

**Mathematical definition:**

```cpp
case MSEGStorage::segment::STAIRS:
{
    auto pct = (r.cpv + 1) * 0.5;  // Control point → 0..1
    auto scaledpct = (exp(5.0 * pct) - 1) / (exp(5.0) - 1);  // Exponential scaling
    auto steps = (int)(scaledpct * 100) + 2;  // 2 to 102 steps

    // Quantize time to step boundaries
    auto frac = (float)((int)(steps * timeAlongSegment / r.duration)) / (steps - 1);

    // Deform applies power curve to step distribution
    if (df < 0)
        frac = pow(frac, 1.0 + df * 0.7);
    else if (df > 0)
        frac = pow(frac, 1.0 + df * 3.0);

    res = frac * lv1 + (1 - frac) * lv0;
    break;
}
```

**Visual representation:**

```
Few steps (cpv low):
  1.0┤    ┌────┐
     │    │    │
  0.5│ ───┘    │
     │         │
  0.0└─────────┴──→

Many steps (cpv high):
  1.0┤  ┌┐┌┐┌┐
     │  ││││││
  0.5│ ─┘└┘└┘└─
     │
  0.0└──────────→

Deform distribution:
Linear (df=0)    Exponential (df>0)
┌──┬──┬──┐       ┌┬┬───┐
│  │  │  │       │││   │
└──┴──┴──┘       └┴┴───┘
```

**Use cases:**
- Bit-crushed modulation
- Stepped filter sequences
- Digital/glitch effects
- Sample-and-hold LFO replacement

### Smooth Stairs

Like stairs, but with smoothed transitions between steps.

**Characteristics:**
- Steps with rounded corners
- Cubic interpolation between levels
- More musical than hard steps
- Still tempo-quantized

**Mathematical definition:**

```cpp
case MSEGStorage::segment::SMOOTH_STAIRS:
{
    auto steps = (int)(scaledpct * 100) + 2;
    auto frac = timeAlongSegment / r.duration;

    // Apply deform power curve
    auto c = df < 0.f ? 1.0 + df * 0.7 : 1.0 + df * 3.0;
    auto z = pow(frac, c);

    // Quantize to step
    auto q = floor(z * steps) / steps;

    // Smooth interpolation within step
    auto r = ((z - q) * steps);
    auto b = r * 2 - 1;

    // Cubic easing: (b³ + 1) / 2
    res = ((((b * b * b) + 1) / (2 * steps)) + q);
    res = (res * (lv1 - lv0)) + lv0;
    break;
}
```

**Visual representation:**

```
  1.0┤   ╭────╮
     │  ╱      ╲
  0.5│ ╱        ╲
     │╱          ╲
  0.0└────────────╮
     Smooth transitions
     between quantized levels
```

**Use cases:**
- Musical step sequences
- Quantized but organic modulation
- Melodic pitch sequences
- Rhythmic but smooth movements

### Hold

Maintains the start value throughout the segment duration—a horizontal line.

**Characteristics:**
- No change over time
- Creates plateaus in envelopes
- Duration still matters for timing
- Useful for sustain stages

**Mathematical definition:**

```cpp
case MSEGStorage::segment::HOLD:
{
    res = lv0;  // Simply output the start value
    break;
}
```

**Visual representation:**

```
  1.0┤ ───────
     │
  0.5│
     │
  0.0└────────────→
     Flat line at v0
```

**Use cases:**
- Sustain sections
- Gates and holds
- Creating rhythmic gaps
- Sample-and-hold simulation

### Oscillating Segments (Sine, Triangle, Sawtooth, Square)

These segments contain complete oscillating waveforms, effectively embedding an LFO within a segment.

**Characteristics:**
- Multiple cycles within one segment
- Control point determines number of oscillations
- Deform parameter applies waveform shaping
- Start and end values define the amplitude range

**Mathematical definition (Sine example):**

```cpp
case MSEGStorage::segment::SINE:
{
    float pct = (r.cpv + 1) * 0.5;  // Control point
    float scaledpct = (exp(5.0 * pct) - 1) / (exp(5.0) - 1);
    int steps = (int)(scaledpct * 100);  // Number of cycles
    auto frac = timeAlongSegment / r.duration;

    // Generate oscillation
    // Use cosine to ensure endpoints match lv0 and lv1
    float mul = (1 + 2 * steps) * M_PI;
    float kernel = cos(mul * frac);

    // Apply bend3 waveshaping (from LFO)
    float a = -0.5f * limit_range(df, -3.f, 3.f);
    kernel = kernel - a * kernel * kernel + a;
    kernel = kernel - a * kernel * kernel + a;

    // Map to value range
    res = (lv0 - lv1) * ((kernel + 1) * 0.5) + lv1;
    break;
}
```

**Visual representations:**

```
SINE (1 cycle):           TRIANGLE (2 cycles):
  1┤  ╱──╲                  1┤ ╱╲  ╱╲
   │ ╱    ╲                  │╱  ╲╱  ╲
  0├─      ─                0└────────→
   │        ╲  ╱
 -1└─────────╲╱

SAWTOOTH (3 cycles):      SQUARE (2 cycles):
  1┤ ╱╲ ╱╲ ╱╲               1┤ ┌─┐ ┌─┐
   │╱ ╲  ╲  ╲               │ │ │ │ │
  0└───╲──╲──╲             0└─┘ └─┘ └→
```

**Control point effect (number of oscillations):**

```
cpv = -1 (minimum):       cpv = 0 (medium):         cpv = +1 (maximum):
  ╱─╲                      ╱╲╱╲╱╲                    ╱╲╱╲╱╲╱╲╱╲╱╲
 ╱   ╲                    ╱      ╲                  ╱          ╲
 1 cycle                  ~5 cycles                 ~100 cycles
```

**Use cases:**
- Vibrato within envelope stages
- Tremolo effects
- Complex rhythmic patterns
- Trill-like ornamentations
- Generative textures

### Brownian (Random Walk)

A pseudo-random walk that creates organic, unpredictable movement.

**Characteristics:**
- Non-deterministic (different each time)
- Smooth random variation
- Control point affects step rate
- Starts at segment start value

**Mathematical definition:**

```cpp
case MSEGStorage::segment::BROWNIAN:
{
    if (segInit)  // Initialize at segment start
    {
        es->msegState[validx] = lv0;
        es->msegState[outidx] = lv0;
    }

    // Determine step timing based on control point
    auto pct = (r.cpv + 1) * 0.5;
    auto steps = (int)(scaledpct * 100) + 2;

    // Random walk: take random steps up or down
    float randomStep = es->urd(es->gen);  // -1 to +1
    float stepSize = (lv1 - lv0) / steps;

    value += randomStep * stepSize * df;  // Deform controls step size
    value = clamp(value, min(lv0, lv1), max(lv0, lv1));

    res = smoothed(value);  // Low-pass filter for smoothness
    break;
}
```

**Visual representation:**

```
  1.0┤   ╱╲ ╱─╲  ╱╲
     │  ╱  ╲   ╲╱  ╲╱╲
  0.5│ ╱    ─╮      ╱
     │╱      ╰╮    ╱
  0.0└─────────╰───────→
     Organic random movement
     (different each note)
```

**Use cases:**
- Organic modulation variation
- Humanization
- Evolving textures
- Generative sequences
- Natural imperfection

## MSEG Parameters and Controls

### Segment Duration

Each segment has an independent duration measured in time units or tempo-synced divisions.

**Duration modes:**

```cpp
// Time mode (seconds)
segment.duration = 0.5;  // 500 milliseconds

// Tempo sync mode (musical divisions)
segment.duration = 0.25;  // Quarter note (in phase units)
```

**Duration constraints:**

```cpp
// File: src/common/SurgeStorage.h
struct MSEGStorage
{
    static constexpr float minimumDuration = 0.001;  // 1 millisecond minimum
    float totalDuration;  // Sum of all segment durations
};
```

**Practical ranges:**
- **Envelope mode**: No upper limit (can be hours long)
- **LFO mode**: Total duration = 1.0 phase unit (segments must sum to 1.0)
- **Minimum**: 0.001 per segment (prevents zero-duration segments)

### Value/Level Control

Each segment has a start value (`v0`) and an end value (next segment's `v0`).

**Value range:**
- `-1.0` to `+1.0` (bipolar)
- Displayed as -100% to +100% in UI
- Quantizable to grid for precise values

**Endpoint modes:**

```cpp
enum EndpointMode
{
    LOCKED = 1,   // Last segment connects back to first (closed loop)
    FREE = 2      // Last segment can end at any value
} endpointMode = FREE;
```

**Example:**

```
FREE mode:                LOCKED mode:
  ╱╲                       ╱╲
 ╱  ╲                     ╱  ╲
─    ╲___                ─    ╲___
       ↑                        ╰──→ connects to start
    Can end anywhere            (forces loop closure)
```

### Control Point (cpv, cpduration)

Segments with control points (Bezier, Bump, Oscillating types) have additional parameters:

**Control point value (cpv):**
- Vertical position of the control point
- Range: -1.0 to +1.0
- Meaning varies by segment type:
  - **Bezier**: Pull point for curve
  - **Bump**: Peak height
  - **Oscillating**: Number of cycles (exponentially scaled)
  - **Stairs**: Number of steps

**Control point duration (cpduration):**
- Horizontal position along the segment
- Range: 0.0 to 1.0 (fraction of segment duration)
- Only used for Bezier curves
- Default: 0.5 (midpoint)

**Example (Bezier):**

```
cpduration = 0.25:        cpduration = 0.5:         cpduration = 0.75:
    ╭───                      ╱──╮                     ╱─╮
   ╱                         ╱    ╲                   ╱   ╲
  ╱                        ╱       ╲                ╱      ──
 cp early                cp midpoint              cp late
```

### Deform Parameter

The deform parameter provides per-segment modulation, allowing real-time control over segment shape.

**Deform behavior by segment type:**

| Segment Type | Deform Effect |
|--------------|---------------|
| Linear | Exponential curve (positive = convex, negative = concave) |
| S-Curve | Steepness of S-shape |
| Bezier | (Deform not used—shape controlled by control point) |
| Bump | Width/sharpness of Gaussian |
| Stairs | Distribution of steps (linear vs. exponential) |
| Oscillating | Waveform shaping (via bend3 algorithm) |

**Deform as modulation target:**

```cpp
// Deform can be modulated by other sources
segment.useDeform = true;      // Enable deform modulation
segment.invertDeform = false;  // Optionally invert
```

This allows **dynamic envelope shaping**:
- LFO modulating deform → breathing envelopes
- Velocity modulating deform → harder/softer attacks
- Random modulating deform → organic variation

**Visual example:**

```
Linear segment with deform:

df = -0.5 (concave):    df = 0 (linear):      df = +0.5 (convex):
  ╭──                      ╱                      ╱──╮
 ╱                        ╱                      ╱    ╲
╱                        ╱                      ╱      ╰
```

### Retrigger Flags

Each segment can optionally retrigger the envelope generators when it begins:

```cpp
bool retriggerFEG = false;  // Retrigger filter envelope
bool retriggerAEG = false;  // Retrigger amplitude envelope
```

**Use cases:**
- Create sub-envelopes within the MSEG
- Rhythmic filter pings on specific beats
- Accent patterns in sequences
- Complex multi-layer modulation

**Example:**

```
MSEG modulating pitch:
  5 ┤ ─╮ ╭─╮ ╭─
    │  │ │ │ │
  0 └──╯ ╯ ╯ ╯
        ↑   ↑
      retrigger FEG → filter ping on each note
```

## Loop Modes and Playback

MSEG can operate in multiple playback modes, making it versatile as both an envelope and an LFO.

### Loop Mode: ONESHOT

The MSEG plays from start to end once, then holds the final value.

**Characteristics:**
- Traditional envelope behavior
- Plays through all segments sequentially
- Stops at the last segment's end value
- Note-off has no effect after completion

**Timing diagram:**

```
Note On                                    Note Off (no effect)
   ↓                                              ↓
   ╱╲      ╱╲
  ╱  ╲____╱  ╲________________ ← holds final value
  │←  totalDuration  →│
```

**Implementation:**

```cpp
// File: src/common/dsp/modulators/MSEGModulationHelper.cpp
if (up >= ms->totalDuration && ms->loopMode == MSEGStorage::LoopMode::ONESHOT)
{
    return ms->segments[ms->n_activeSegments - 1].nv1;  // Return final value
}
```

**Use cases:**
- One-shot envelopes
- Timed automation
- Intro swoops that don't repeat
- Triggered effects

### Loop Mode: LOOP

The MSEG repeats continuously from loop start to loop end.

**Characteristics:**
- Cyclic behavior (like an LFO)
- Wraps from loop end back to loop start
- Loop points can be set to any segments
- Default: loops entire MSEG (start=-1, end=-1)

**Loop point options:**

```cpp
int loop_start = -1;  // -1 = beginning
int loop_end = -1;    // -1 = end

// Example: Loop only segments 2-4
loop_start = 2;
loop_end = 4;
```

**Timing diagram:**

```
Full loop (default):
   ╱╲  ╱╲  ╱╲  ╱╲
  ╱  ╲╱  ╲╱  ╲╱  ╲
  │←→│ loops forever

Partial loop:
   ╱╲┌─╮┌─╮┌─╮
  ╱  └╯ └╯ └╯
  │ ↑     ↑
  │ loop loop
  │ start end
  played once
```

**Implementation:**

```cpp
// Calculate loop duration
ms->durationLoopStartToLoopEnd =
    ms->segmentEnd[(loop_end >= 0 ? loop_end : n_activeSegments - 1)] -
    ms->segmentStart[(loop_start >= 0 ? loop_start : 0)];

// Wrap phase when reaching loop end
if (phase >= loopEndTime)
    phase = loopStartTime + (phase - loopEndTime) % loopDuration;
```

**Use cases:**
- Custom LFO waveforms
- Repeating sequences
- Rhythmic modulation
- Cyclic filter sweeps

### Loop Mode: GATED_LOOP (Loop with Release)

The MSEG loops while the note is held, then plays the release section on note-off.

**Characteristics:**
- Loops from start to loop end while gate is on
- On note-off, jumps to segment after loop end
- Plays remaining segments as release
- Ideal for sustaining envelopes

**Timing diagram:**

```
Note On                            Note Off
   ↓                                  ↓
   ╱╲┌─╮┌─╮┌─╮┌─╮ ← loops while held  ╲
  ╱  └╯ └╯ └╯ └╯                      ╲___
  │ ↑     ↑                             ↑
  │ loop  loop                        release
  │ start end                         segment
  attack
```

**State management:**

```cpp
enum LoopState
{
    PLAYING,    // Note on, looping
    RELEASING   // Note off, playing release
};

if (es->loopState == EvaluatorState::PLAYING && es->released)
{
    es->releaseStartPhase = currentPhase;
    es->releaseStartValue = currentOutput;
    es->loopState = EvaluatorState::RELEASING;
}
```

**Release behavior:**

When note-off occurs:
1. Remember current output value
2. Jump to segment after loop end
3. Adjust first release segment to start from current value
4. Play through to end

**Use cases:**
- Sustaining pads with release tail
- Looping filter sweeps with note-off decay
- Rhythmic patterns that gracefully end
- Emulating analog envelope behavior

### Edit Mode: ENVELOPE vs. LFO

MSEG has two fundamental edit modes that affect timing constraints:

#### ENVELOPE Mode

```cpp
editMode = MSEGStorage::EditMode::ENVELOPE;
```

**Characteristics:**
- No time limit (can be arbitrarily long)
- Segments can have any duration
- totalDuration = sum of all segment durations
- Typical for one-shot and gated envelopes

**Example:**

```
Envelope mode (total = 3.5 seconds):
   ╱╲
  ╱  ╲________╲___
  0.5  1.0  1.5  0.5
  │←    3.5s    →│
```

#### LFO Mode

```cpp
editMode = MSEGStorage::EditMode::LFO;
```

**Characteristics:**
- Total duration locked to 1.0 phase unit
- Segments must sum to exactly 1.0
- Useful for single-cycle waveform design
- Constrains editing to one cycle

**Example:**

```
LFO mode (total = 1.0 phase):
   ╱╲  ╱╲
  ╱  ╲╱  ╲
  0.25 0.25 0.25 0.25
  │←     1.0     →│
```

**Why the distinction?**

LFO mode enables tempo-synced modulation where one complete cycle corresponds to musical divisions:

```
If LFO rate = 1/4 note:
  1.0 phase = one quarter note
  0.25 phase = one sixteenth note

  ╱╲  ╱╲    ← one quarter note
 ╱  ╲╱  ╲
 1/16 note segments
```

## The MSEG Editor

Surge provides a sophisticated graphical editor for designing MSEG shapes. The editor is one of the most complex UI components in Surge, implemented in `/home/user/surge/src/surge-xt/gui/overlays/MSEGEditor.cpp` (over 4000 lines of code).

### Editor Components

The MSEG editor consists of two main regions:

```cpp
// File: src/surge-xt/gui/overlays/MSEGEditor.h
struct MSEGEditor : public OverlayComponent
{
    std::unique_ptr<MSEGControlRegion> controls;  // Top panel: buttons, options
    std::unique_ptr<MSEGCanvas> canvas;           // Main area: graphical editing
};
```

#### Control Region (Top Panel)

Contains:
- **Segment type selector**: Choose curve type for selected segment
- **Loop mode buttons**: ONESHOT / LOOP / GATED_LOOP
- **Edit mode toggle**: ENVELOPE / LFO
- **Snap controls**: Grid snap for time and value
- **Action menu**: Operations like quantize, mirror, scale
- **Movement mode**: Time editing modes (shift subsequent vs. constant total)

#### Canvas (Drawing Area)

The interactive editing surface:
- **Node editing**: Drag segment endpoints vertically
- **Duration editing**: Drag segments horizontally
- **Control point editing**: Adjust bezier/bump control points
- **Multi-select**: Shift-click to select multiple nodes
- **Context menu**: Right-click for segment operations
- **Visual feedback**: Real-time preview of changes

### Editing Workflow

#### Creating Segments

**Method 1: Insert After**
- Right-click a segment
- Choose "Insert After"
- New segment inherits previous endpoint value

**Method 2: Split Segment**
- Right-click on a segment
- Choose "Split"
- Segment divides at click position
- Useful for adding detail to existing shapes

**Method 3: Extend**
- Drag the final node to the right
- MSEG automatically creates a new segment

#### Editing Segment Duration

Two time-editing modes control how duration changes propagate:

**Mode 1: Shift Subsequent Segments**

```cpp
void adjustDurationShiftingSubsequent(MSEGStorage *ms, int idx, float dx)
{
    ms->segments[idx].duration += dx;
    // All segments after idx stay at their absolute times
    // Total duration changes
}
```

**Visual:**

```
Before:             After dragging segment 1 right:
 ╱─╮╱╲               ╱───╮╱╲
 0 1 2               0  1  2
                     │← longer total duration
```

**Mode 2: Constant Total Duration**

```cpp
void adjustDurationConstantTotalDuration(MSEGStorage *ms, int idx, float dx)
{
    ms->segments[idx].duration += dx;
    ms->segments[idx + 1].duration -= dx;  // Compensate
    // Total duration remains constant
}
```

**Visual:**

```
Before:             After dragging segment 1 right:
 ╱─╮╱╲               ╱──╮╲
 0 1 2               0  1 2
                     │← same total duration
```

#### Editing Values

**Vertical dragging:**
- Click and drag a node up/down
- Snaps to grid if enabled
- Shift+drag for fine control
- Adjacent segments update automatically

**Value quantization:**
- Enable vertical snap grid
- Nodes snap to divisions: 1/2, 1/4, 1/8, 1/16, etc.
- Useful for precise modulation amounts

**Example:**

```
Without snap:           With 1/4 snap:
  0.73 ┤  •               1.00 ┤  •
       │                       │
  0.27 ┤    •             0.50 │
       │      •           0.25 ┤    •
  0.12 ┤        •         0.00 └      •
                          Perfect quarters
```

#### Snap to Grid

MSEG provides both horizontal (time) and vertical (value) snap grids.

**Horizontal snap (time):**

```cpp
// Default snap divisions
float hSnapDefault = 0.125;  // 1/8 note in LFO mode, 125ms in envelope mode
```

**Quantize all durations:**

```cpp
// Menu: Actions → Quantize Nodes to Snap Divisions
Surge::MSEG::setAllDurationsTo(ms, ms->hSnapDefault);
```

**Vertical snap (value):**

```cpp
// Snap to divisions: 0, 0.25, 0.5, 0.75, 1.0
float vSnapDiv = 4;  // 1/4 increments
```

**Use cases for snap:**
- **Rhythmic sequences**: Snap time to 1/16 notes
- **Chord modulation**: Snap values to semitones
- **Step sequencers**: Both time and value quantized
- **Precise automation**: Exact mathematical values

#### Control Point Editing

For segments with control points (Bezier, Bump):

**Bezier control points:**
- Small handle appears on segment
- Drag handle to adjust curve shape
- Horizontal: control point time (cpduration)
- Vertical: control point value (cpv)

**Bump control points:**
- Drag vertically to set peak height
- Drag horizontally to adjust peak time
- Deform parameter adjusts width

**Visual representation:**

```
Bezier curve editing:
    • ← control point handle
   ╱ ╲
  •   •
 start end

Dragging control point:
       •
      ╱╲
     ╱  ╲
    •    •
  Higher, later control point
  = slower start, faster end
```

#### Multi-Segment Operations

**Select multiple segments:**
- Shift+click nodes to build selection
- Or drag selection rectangle

**Operations on selection:**
- **Scale durations**: Proportionally adjust timing
- **Scale values**: Increase/decrease amplitude
- **Delete**: Remove selected segments
- **Change type**: Convert all to same curve type

**Example: Scale values to 50%**

```
Before:             After scale 0.5x:
  1.0┤ ╱╲             0.5┤ ╱╲
     │╱  ╲               │╱  ╲
  0.0└    ╲          0.0└    ╲
```

### Preset Shapes

The editor provides preset starting points:

**createInitVoiceMSEG**: Default voice envelope

```cpp
void createInitVoiceMSEG(MSEGStorage *ms)
{
    ms->editMode = ENVELOPE;
    ms->loopMode = GATED_LOOP;
    ms->n_activeSegments = 4;

    // Attack
    ms->segments[0].duration = 1.f;
    ms->segments[0].v0 = 0.f;

    // Decay
    ms->segments[1].duration = 1.f;
    ms->segments[1].v0 = 1.f;

    // Sustain (loop section)
    ms->segments[2].duration = 1.f;
    ms->segments[2].v0 = 0.8f;

    // Release
    ms->segments[3].duration = 1.f;
    ms->segments[3].v0 = 0.8f;

    ms->loop_start = 2;  // Sustain point
    ms->loop_end = 2;
}
```

**Visual:**

```
  1.0┤  ╱╲
     │ ╱  ╲
  0.8│    ─── ← loops here
     │       ╲
  0.0└────────╲___
     A D  S    R
```

**createInitSceneMSEG**: Default LFO shape

```cpp
void createInitSceneMSEG(MSEGStorage *ms)
{
    ms->editMode = LFO;
    ms->loopMode = LOOP;
    ms->n_activeSegments = 4;

    // Triangle wave (4 segments summing to 1.0)
    ms->segments[0].duration = 0.25f;  ms->segments[0].v0 = 0.f;
    ms->segments[1].duration = 0.25f;  ms->segments[1].v0 = 1.f;
    ms->segments[2].duration = 0.25f;  ms->segments[2].v0 = 0.f;
    ms->segments[3].duration = 0.25f;  ms->segments[3].v0 = -1.f;
}
```

**Visual:**

```
  1.0┤   ╱╲
     │  ╱  ╲
  0.0├──    ──
     │        ╲╱
 -1.0└─────────
     0.25 each = 1.0 total
```

**Other presets:**
- **createStepseqMSEG**: Step sequencer template
- **createSawMSEG**: Sawtooth wave with adjustable curve
- **createSinLineMSEG**: Approximated sine using linear segments

### Action Menu

The MSEG editor provides powerful batch operations:

**Quantize Operations:**
- **Quantize to Snap Divisions**: All segments → snap grid duration
- **Quantize to Whole Units**: All segments → 1.0 duration
- **Quantize Values**: Snap all values to grid

**Transform Operations:**
- **Mirror**: Flip MSEG horizontally (reverse time)
- **Flip Vertically**: Invert all values (multiply by -1)
- **Scale Durations**: Multiply all durations by factor
- **Scale Values**: Multiply all values by factor

**Example transforms:**

```
Original:           Mirror:              Flip Vertically:
  ╱╲                    ╱╲                    ╲___
 ╱  ╲___             ___╱  ╲                    ╱╲
                     time reversed           values negated
```

## MSEG Implementation Deep-Dive

Understanding the implementation reveals how MSEG achieves its flexibility and performance.

### Core Data Structure

The complete MSEG storage structure:

```cpp
// File: src/common/SurgeStorage.h
struct MSEGStorage
{
    static constexpr int max_msegs = 128;  // Maximum segments

    struct segment
    {
        float duration;        // Segment length
        float v0;              // Start value
        float nv1;             // Next segment's v0 (cached)

        float cpv;             // Control point value
        float cpduration;      // Control point time (0..1)

        bool useDeform;        // Enable deform modulation
        bool invertDeform;     // Invert deform sign

        bool retriggerFEG;     // Retrigger filter envelope
        bool retriggerAEG;     // Retrigger amplitude envelope

        Type type;             // Segment curve type
    };

    enum LoopMode { ONESHOT, LOOP, GATED_LOOP } loopMode;
    enum EditMode { ENVELOPE, LFO } editMode;
    enum EndpointMode { LOCKED, FREE } endpointMode;

    int n_activeSegments;
    std::array<segment, max_msegs> segments;

    // Cached values (rebuilt by rebuildCache)
    float totalDuration;
    std::array<float, max_msegs> segmentStart;  // Cumulative start times
    std::array<float, max_msegs> segmentEnd;    // Cumulative end times

    int loop_start, loop_end;  // -1 = full range
    float durationToLoopEnd;
    float durationLoopStartToLoopEnd;
};
```

### Cache Rebuilding

After any edit, cached values must be rebuilt:

```cpp
// File: src/common/dsp/modulators/MSEGModulationHelper.cpp
void rebuildCache(MSEGStorage *ms)
{
    float totald = 0;

    // Calculate cumulative times
    for (int i = 0; i < ms->n_activeSegments; ++i)
    {
        ms->segmentStart[i] = totald;
        totald += ms->segments[i].duration;
        ms->segmentEnd[i] = totald;

        // Cache next segment's start value
        int nextseg = i + 1;
        if (nextseg >= ms->n_activeSegments)
        {
            if (ms->endpointMode == LOCKED)
                ms->segments[i].nv1 = ms->segments[0].v0;
            else
                ms->segments[i].nv1 = ms->segments[i].v0;  // No change
        }
        else
        {
            ms->segments[i].nv1 = ms->segments[nextseg].v0;
        }

        // Calculate control point ratio for Bezier
        if (ms->segments[i].nv1 != ms->segments[i].v0)
        {
            ms->segments[i].dragcpratio =
                (ms->segments[i].cpv - ms->segments[i].v0) /
                (ms->segments[i].nv1 - ms->segments[i].v0);
        }
    }

    ms->totalDuration = totald;

    // Handle LFO mode constraint
    if (ms->editMode == LFO && totald != 1.0)
    {
        ms->totalDuration = 1.0;
        ms->segmentEnd[ms->n_activeSegments - 1] = 1.0;
    }

    // Calculate loop durations
    ms->durationToLoopEnd = ms->totalDuration;
    if (ms->loop_end >= 0)
        ms->durationToLoopEnd = ms->segmentEnd[ms->loop_end];

    ms->durationLoopStartToLoopEnd =
        ms->segmentEnd[(ms->loop_end >= 0 ? ms->loop_end : ms->n_activeSegments - 1)] -
        ms->segmentStart[(ms->loop_start >= 0 ? ms->loop_start : 0)];
}
```

**Why cache?**
- Segment lookup by time is O(1) instead of O(n)
- Avoids recalculating cumulative sums every sample
- Critical for real-time performance

### Evaluation State

Each MSEG instance (per voice) maintains evaluation state:

```cpp
// File: src/common/dsp/modulators/MSEGModulationHelper.h
struct EvaluatorState
{
    int lastEval = -1;         // Last evaluated segment index
    float lastOutput = 0;       // Previous output value
    float msegState[6];         // Per-segment state (for Brownian, etc.)

    bool released = false;      // Has note-off occurred?
    bool retrigger_FEG = false; // Trigger filter envelope this block?
    bool retrigger_AEG = false; // Trigger amp envelope this block?
    bool has_triggered = false; // Did we wrap/retrigger?

    enum LoopState { PLAYING, RELEASING } loopState;

    double releaseStartPhase;   // Phase when note-off occurred
    float releaseStartValue;    // Output when note-off occurred
    double timeAlongSegment;    // Current position in segment

    // Random number generator for Brownian
    std::minstd_rand gen;
    std::uniform_real_distribution<float> urd;
};
```

### Segment Lookup

Finding which segment corresponds to a given phase:

```cpp
int timeToSegment(MSEGStorage *ms, double t, bool ignoreLoops, float &timeAlongSegment)
{
    // Handle looping
    if (!ignoreLoops && ms->loopMode != ONESHOT)
    {
        int loopStart = (ms->loop_start >= 0 ? ms->loop_start : 0);
        int loopEnd = (ms->loop_end >= 0 ? ms->loop_end : ms->n_activeSegments - 1);

        if (t >= ms->segmentEnd[loopEnd])
        {
            // Wrap phase back to loop start
            float loopDur = ms->durationLoopStartToLoopEnd;
            float loopStartTime = ms->segmentStart[loopStart];
            t = loopStartTime + fmod(t - ms->segmentEnd[loopEnd], loopDur);
        }
    }

    // Binary search would be faster, but with max 128 segments, linear is fine
    for (int i = 0; i < ms->n_activeSegments; ++i)
    {
        if (ms->segmentStart[i] <= t && ms->segmentEnd[i] > t)
        {
            timeAlongSegment = t - ms->segmentStart[i];
            return i;
        }
    }

    return ms->n_activeSegments - 1;  // Past end
}
```

### Value Evaluation

The main evaluation function that outputs MSEG values:

```cpp
float valueAt(int ip, float fup, float df, MSEGStorage *ms,
              EvaluatorState *es, bool forceOneShot)
{
    if (ms->n_activeSegments <= 0)
        return df;  // Empty MSEG returns deform parameter

    double phase = (double)ip + fup;

    // Handle ONESHOT completion
    if (phase >= ms->totalDuration &&
        (ms->loopMode == ONESHOT || forceOneShot))
    {
        return ms->segments[ms->n_activeSegments - 1].nv1;
    }

    // Handle gated loop release transition
    if (es->loopState == PLAYING && es->released)
    {
        es->releaseStartPhase = phase;
        es->releaseStartValue = es->lastOutput;
        es->loopState = RELEASING;
    }

    // Find current segment
    float timeAlongSegment = 0;
    int idx = timeToSegment(ms, phase,
                            forceOneShot || ms->loopMode == ONESHOT,
                            timeAlongSegment);

    if (idx < 0 || idx >= ms->n_activeSegments)
        return 0;

    // Detect segment initialization
    bool segInit = (idx != es->lastEval);
    if (segInit)
    {
        es->lastEval = idx;
        es->retrigger_FEG = ms->segments[idx].retriggerFEG;
        es->retrigger_AEG = ms->segments[idx].retriggerAEG;
    }

    // Apply deform
    float deform = df;
    if (!ms->segments[idx].useDeform)
        deform = 0;
    if (ms->segments[idx].invertDeform)
        deform = -deform;

    // Evaluate segment-specific curve
    float result = evaluateSegment(ms->segments[idx], timeAlongSegment,
                                    deform, es, segInit);

    es->lastOutput = result;
    es->timeAlongSegment = timeAlongSegment;

    return result;
}
```

**Key details:**

1. **Phase handling**: Integer + fractional parts for long envelopes
2. **Loop state machine**: Separate PLAYING and RELEASING states
3. **Segment initialization**: Detect transitions for Brownian and retriggering
4. **Deform application**: Per-segment enable/invert flags
5. **Result caching**: Remember last output for release transitions

### Performance Considerations

MSEG evaluation happens at **control rate** (once per block, typically 32-64 samples):

**Computational cost:**
- Segment lookup: O(n) but n ≤ 128
- Curve evaluation: O(1) per segment type
- Total: ~few hundred CPU cycles per block

**Optimization strategies:**

```cpp
// Cache cumulative times → O(1) lookup instead of O(n)
ms->segmentStart[i];
ms->segmentEnd[i];

// Precompute control point ratios
ms->segments[i].dragcpratio;

// Early exit for empty MSEG
if (ms->n_activeSegments <= 0)
    return df;

// Early exit for completed ONESHOT
if (phase >= ms->totalDuration && ms->loopMode == ONESHOT)
    return finalValue;
```

**Memory footprint:**

```cpp
sizeof(MSEGStorage) ≈
    128 segments × ~64 bytes/segment = ~8 KB per MSEG
```

Surge has 12 LFOs (6 per scene), so ~96 KB total for all MSEGs.

## Creative Applications

MSEG's flexibility enables sound design techniques impossible with traditional modulators.

### Application 1: Complex Filter Sweeps

**Goal**: Create a multi-stage filter envelope that evolves through distinct timbral regions.

**Design:**

```
Cutoff
8000 Hz┤  ╱╲ ← peak (1)
       │ ╱  ╲
2000 Hz│╱    ╲___ ← sustain (2)
       │        ╲
 500 Hz└─────────╲___ ← release (3)
       A D  S      R
```

**Segment breakdown:**
1. **Attack (Linear)**: 0→8000 Hz in 50ms (bright strike)
2. **Decay (S-Curve)**: 8000→2000 Hz in 200ms (smooth mellowing)
3. **Sustain (Hold)**: 2000 Hz (loops while held)
4. **Release (Bezier)**: 2000→500 Hz in 1s (natural fade)

**MSEG settings:**
- Loop mode: GATED_LOOP
- Loop start: Segment 2 (sustain)
- Loop end: Segment 2
- Modulation target: Filter cutoff, amount = +4 octaves

**Result**: Piano-like timbre with initial brightness that settles into warm sustain, then darkens naturally on release.

### Application 2: Rhythmic Gating

**Goal**: Create a tempo-synced rhythmic gate pattern for a pad sound.

**Design:**

```
Amplitude
  1┤ ┌─┐   ┌─┐ ┌─┐
   │ │ │   │ │ │ │
  0└─┘ └───┘ └─┘ └─
    1 2  3  4 1 2 3
    Sixteenth note pattern
```

**Segment configuration:**
- Edit mode: LFO
- Total duration: 1.0 (one quarter note)
- Segment types: HOLD (on) and HOLD (off)
- Durations: [0.0625, 0.0625, 0.125, 0.0625, 0.0625, 0.0625, 0.0625]
  = [1/16, 1/16, 1/8, 1/16, 1/16, 1/16, 1/16]
- Values: [1, 0, 1, 0, 1, 0, 1, 0]

**MSEG settings:**
- Loop mode: LOOP
- LFO rate: 1/4 note (tempo-synced)
- Modulation target: Amplitude, amount = 100%

**Result**: Rhythmic stuttering pad that syncs perfectly to host tempo.

### Application 3: Generative Melodic Sequences

**Goal**: Create a pseudo-random melodic sequence for pitch modulation.

**Design:**

```
Pitch (semitones)
 +12┤     ╱──     ╱╲
    │    ╱  ╲   ╱  │
  +7│   ╱    ─ ╱   │
    │  ╱      ╲    ╰─
   0└──
    Pentatonic scale steps
```

**Technique:**
1. Use 8-16 segments of varying duration
2. Set values to pentatonic scale degrees: 0, +2, +4, +7, +9, +12
3. Use LINEAR or STAIRS for discrete pitches
4. Use SMOOTH_STAIRS for glides
5. Vary segment durations for rhythmic interest

**Enhanced variation:**
- Add BROWNIAN segments for unpredictable jumps
- Use BUMP segments for pitch wobbles
- Modulate MSEG deform with LFO for evolving randomness

**MSEG settings:**
- Loop mode: LOOP
- Modulation target: Osc pitch, amount = 1 octave
- Modulation target: Filter cutoff (same MSEG) for timbral tracking

**Result**: Generative melodic sequences that change with each loop cycle, perfect for ambient/evolving patches.

### Application 4: Custom LFO Waveforms

**Goal**: Replace standard LFO waveforms with custom shapes for unique modulation.

**Examples:**

#### Asymmetric Vibrato

```
Pitch
  +20¢┤  ╱╲
      │ ╱  ╲___
    0├─
      │
  -20¢└─────────
     Fast up, slow down
```

**Configuration:**
- Segment 1 (Linear): 0→+20¢ in 25% of cycle
- Segment 2 (S-Curve): +20→0¢ in 50% of cycle
- Segment 3 (Hold): 0¢ for 25% of cycle

**Result**: Vocal-like pitch inflection, more expressive than sine wave.

#### Stepped Random LFO

```
Value
  1┤ ┌────┐ ┌──┐
   │ │    │ │  │
  0├─┘    └─┘  │
   │           │
 -1└───────────┘
    Sample & hold with smooth transitions
```

**Configuration:**
- 8-16 SMOOTH_STAIRS segments
- Random values per segment
- Equal or varied durations

**Result**: Smooth random modulation, like sample-and-hold but without hard steps.

### Application 5: Attack Variation via Deform

**Goal**: Use a single MSEG with deform modulation for varying attack characteristics.

**MSEG design:**

```
Basic shape (df = 0):
  1┤   ╱───
   │  ╱
  0└──

Deform > 0 (velocity→deform):
  1┤  ╱────  ← fast attack (hard hit)
   │ ╱
  0└──

Deform < 0 (velocity→deform):
  1┤    ╭──  ← slow attack (soft touch)
   │  ╱
  0└──
```

**Implementation:**
1. Design MSEG with S-CURVE attack segment
2. Route Velocity→MSEG Deform, amount = 100%
3. Segment deform affects attack curve steepness

**MSEG segment settings:**
- Segment 0: S-CURVE, duration = 200ms
- useDeform = true
- Positive deform = faster attack (velocity > 64)
- Negative deform = slower attack (velocity < 64)

**Result**: Single patch responds dynamically to playing velocity, from gentle swells to percussive strikes.

### Application 6: Multi-Stage Resonance Sweeps

**Goal**: Create evolving filter resonance that tracks a cutoff MSEG.

**Design:**

```
Cutoff (MSEG 1):        Resonance (MSEG 2):
8000 Hz┤ ╱╲              0.9┤ ╱╲
       │╱  ╲                │╱  ╰──
2000 Hz│    ╰───          0.3└───────
       Sweeps up/down       Peaks at sweep peak
```

**Configuration:**
- MSEG 1 → Filter cutoff (main sweep)
- MSEG 2 → Filter resonance (same timing, different shape)
- Both use GATED_LOOP
- Synchronized loop points

**Result**: Resonance emphasizes the filter sweep peak, then settles into safe sustain range, avoiding self-oscillation during sustain.

### Patch Example: "Evolving Bell"

Complete patch demonstrating multiple MSEG techniques:

**Oscillators:**
- Osc 1: Sine wave
- Osc 2: FM2 (operator ratio 3.5)

**MSEGs:**

**MSEG 1 (Amp Envelope):**
```
  1┤ ╱╲
   │╱  ╲___
  0└──────╲___
   A D S   R
```
- Attack: 5ms LINEAR
- Decay: 300ms BEZIER (curved)
- Sustain: 0.3 HOLD (loops)
- Release: 2s S-CURVE
- Loop mode: GATED_LOOP

**MSEG 2 (FM Amount):**
```
  1┤ ╱╲  ╱╲  ╱╲
   │╱  ╲╱  ╲╱  ╰───
  0└────────────
   Oscillating decay
```
- Segments: SINE × 3, then HOLD
- Loop mode: ONESHOT
- Modulates FM depth: initial harmonics that fade

**MSEG 3 (Filter Cutoff):**
```
8000┤ ╱╲
    │╱  ╰╮ ╭╮ ╭───
2000└────╰─╰╯
    Initial brightness + wobbles
```
- Attack: LINEAR to 8kHz
- Decay: BEZIER to 3kHz
- Wobbles: BUMP segments
- Sustain: HOLD at 2.5kHz
- Loop mode: GATED_LOOP

**MSEG 4 (Stereo Width - Scene LFO):**
```
  1┤ ╱╲  ╱╲
   │╱  ╲╱  ╲
  0└─────────
    Slow triangle
```
- Edit mode: LFO
- 4 segments: triangle wave
- Loop mode: LOOP
- Rate: 8 bars
- Modulates oscillator pan for slow stereo movement

**Result**: Metallic bell-like sound with:
- Natural decay envelope
- Evolving harmonic content (via FM)
- Bright attack that mellows
- Subtle resonance wobbles
- Gentle stereo animation

## Advanced Techniques

### Retriggering Sub-Envelopes

Use segment retrigger flags to create complex rhythmic modulation:

```cpp
// Segment 0, 4, 8, 12: retriggerFEG = true
// Creates filter "ping" on each beat
```

**Visual:**

```
MSEG (Pitch):
  5┤ ╱╮ ╱╮ ╱╮ ╱╮
   │╱ ╰╯ ╰╯ ╰╯
  0└──────────────

Filter Envelope (retriggered):
    ╱╲ ╱╲ ╱╲ ╱╲
   ╱  ╰  ╰  ╰  ╰
   ↑  ↑  ↑  ↑
  Retriggers on beat
```

### Morphing Between Shapes

Modulate MSEG deform with another modulator to morph between variations:

```cpp
// LFO → MSEG Deform
// Slow LFO morphs attack curve cyclically
```

**Effect:**

```
Time 0 (LFO = -1):    Time 0.5 (LFO = 0):   Time 1 (LFO = +1):
    ╭───                  ╱───                 ╱────
  ╱                      ╱                    ╱
 ╱                      ╱                    ╱
Gentle attack          Linear attack        Percussive attack
```

### Randomization via Brownian

Use Brownian segments for controlled chaos:

```cpp
// Segment types: [LINEAR, BROWNIAN, LINEAR]
// Brownian in middle creates unpredictable variation
```

**Applications:**
- Random pitch drift during sustain
- Evolving filter movement
- Humanized modulation
- Generative textures

### MSEG as Step Sequencer

Quantize both time and value for classic step sequencing:

```
Horizontal snap: 1/16 note
Vertical snap: Semitone

Pitch
 +12┤ ──┐  ┌──┐
    │   │  │  │
  +7│   └──┘  └──
    │
   0└────────────
    16th note melody
```

**Workflow:**
1. Set edit mode: LFO
2. Enable snap: Time = 1/16, Value = 1/12 (semitone)
3. Draw steps
4. Modulate pitch with 100% amount

## Comparison with Other Modulators

### MSEG vs. ADSR

| Feature | ADSR | MSEG |
|---------|------|------|
| Stages | 4 (fixed) | 1-128 (arbitrary) |
| Curves | Exponential/Linear | 13 types |
| Visual editing | Sliders | Graphical drawing |
| Complexity | Simple | Complex |
| CPU usage | Minimal | Low |
| Workflow | Fast | Detailed |
| Best for | Standard envelopes | Custom shapes |

### MSEG vs. Step Sequencer

| Feature | Step Sequencer | MSEG (in step mode) |
|---------|----------------|---------------------|
| Step count | Fixed (usually 16) | Variable (1-128) |
| Values | Quantized | Quantized or smooth |
| Shapes | Steps only | Steps + curves + holds |
| Editing | Step matrix | Graphical canvas |
| Per-step timing | Equal or swing | Arbitrary durations |
| Best for | Rhythmic sequences | Complex evolving sequences |

### MSEG vs. Standard LFO

| Feature | LFO | MSEG (LFO mode) |
|---------|-----|-----------------|
| Waveforms | Preset (sine, saw, etc.) | Custom drawn |
| Tempo sync | Yes | Yes |
| Phase offset | Yes | Yes (via segment timing) |
| Complexity | Simple waveforms | Arbitrary waveforms |
| Workflow | Select + adjust | Draw + edit |
| Best for | Standard modulation | Unique modulation |

## Conclusion

The Multi-Segment Envelope Generator represents the pinnacle of modulation flexibility in Surge XT. By combining:

- **Freeform drawing**: Arbitrary shapes limited only by imagination
- **Rich segment types**: 13 distinct interpolation methods
- **Flexible playback**: Envelope, LFO, and hybrid modes
- **Sophisticated editor**: Visual, real-time editing with snap and quantize
- **Performance**: Efficient evaluation suitable for real-time synthesis
- **Deep integration**: Modulates any parameter, responds to modulation itself

MSEG enables sound design techniques that would be impossible or impractical with traditional modulators. From complex filter evolutions to generative melodic sequences, from rhythmic gates to organic random walks, MSEG transforms Surge from a powerful synthesizer into an instrument for sonic sculpture.

**Key takeaways:**

1. **Start simple**: Begin with basic LINEAR/HOLD shapes, add complexity gradually
2. **Use presets**: Analyze factory MSEGs to learn techniques
3. **Combine with other mods**: Layer MSEG with LFOs and envelopes for depth
4. **Experiment with segment types**: Each type has unique musical character
5. **Leverage loop modes**: GATED_LOOP bridges envelope and LFO paradigms
6. **Modulate deform**: Dynamic envelope shaping via velocity, LFO, or macros
7. **Think musically**: Technology serves expression—design MSEGs that enhance your sound

In the next chapter, we'll explore **Formula Modulation**, where Lua scripting provides algorithmic control over modulation sources, complementing MSEG's graphical approach with mathematical precision.

---

**Related chapters:**
- **[Chapter 19: Envelope Generators](19-envelopes.md)** - ADSR theory and implementation
- **[Chapter 20: Low-Frequency Oscillators](20-lfos.md)** - Standard LFO system
- **[Chapter 22: Formula Modulation](22-formula-modulation.md)** - Lua-based modulation (upcoming)
- **[Chapter 18: Modulation Architecture](18-modulation-architecture.md)** - How modulation routing works

**File references:**
- `/home/user/surge/src/common/SurgeStorage.h` - MSEGStorage structure
- `/home/user/surge/src/common/dsp/modulators/MSEGModulationHelper.h` - Evaluation API
- `/home/user/surge/src/common/dsp/modulators/MSEGModulationHelper.cpp` - Core evaluation (1400+ lines)
- `/home/user/surge/src/surge-xt/gui/overlays/MSEGEditor.h` - Editor interface
- `/home/user/surge/src/surge-xt/gui/overlays/MSEGEditor.cpp` - Editor implementation (4000+ lines)
