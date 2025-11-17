# Chapter 20: Low-Frequency Oscillators (LFOs)

## The Pulse of Movement

If envelopes provide the contour of individual notes, Low-Frequency Oscillators (LFOs) provide the heartbeat of continuous motion. An LFO is a **cyclic modulator** that oscillates below the audio range (typically 0.01 Hz to 20 Hz), creating repeating patterns that add vibrato, tremolo, filter sweeps, rhythmic pulsing, and evolving textures to static sounds.

This chapter explores Surge's sophisticated LFO system in depth: the theory behind LFOs, Surge's extensive waveform library, the distinction between voice and scene LFOs, the powerful step sequencer mode, and the implementation details that make Surge's LFOs exceptionally flexible and musical.

## LFO Theory

### What is an LFO?

A **Low-Frequency Oscillator** generates a **sub-audio rate control signal** that repeats cyclically. Unlike audio-rate oscillators (which you hear as pitched tones), LFOs operate slowly enough that you perceive them as rhythmic modulation rather than pitch.

**Key characteristics:**

- **Cyclic**: Repeats continuously (unlike one-shot envelopes)
- **Sub-audio**: Typically 0.01 Hz to 20 Hz (not heard as pitch)
- **Bipolar or Unipolar**: Oscillates around zero (-1 to +1) or from zero to positive (0 to +1)
- **Tempo-syncable**: Can lock to musical divisions (1/4 note, 1/8 note, etc.)
- **Control-rate**: Updated per-block for efficiency

### Frequency Ranges

```
Audio Range (Oscillators):
  20 Hz - 20,000 Hz     → Perceived as pitch

LFO Range:
  0.01 Hz - 20 Hz       → Perceived as modulation
  0.01 Hz = one cycle every 100 seconds
  1 Hz = one cycle per second
  20 Hz = flutter/borderline audio
```

**Examples:**

```
0.1 Hz  = Slow pad evolution (10 sec cycle)
0.5 Hz  = Gentle vibrato (2 sec cycle)
2 Hz    = Moderate tremolo
5 Hz    = Fast vibrato (5 cycles/sec)
10 Hz   = Trill-like modulation
```

### Classic LFO Applications

#### Vibrato (Pitch Modulation)

```cpp
// LFO modulating pitch creates vibrato
float lfo = sine_lfo.get_output();  // -1 to +1
float pitch_offset = lfo * 0.05;    // ±5 cents
float freq = base_freq * pow(2.0, pitch_offset);
```

**Musical context:**
- **Slow/Shallow**: Classical string vibrato (5-6 Hz, ±10 cents)
- **Fast/Deep**: Dramatic vibrato (7-8 Hz, ±50 cents)
- **Random**: Organic, imperfect pitch drift

#### Tremolo (Amplitude Modulation)

```cpp
// LFO modulating volume creates tremolo
float lfo = sine_lfo.get_output();  // -1 to +1
lfo = (lfo + 1.0) * 0.5;            // Convert to 0-1 (unipolar)
float output = audio_signal * lfo;
```

**Musical context:**
- **Guitar amp tremolo**: 3-5 Hz sine wave
- **Helicopter effect**: Fast square wave (10+ Hz)
- **Pulsing pads**: Slow triangle (0.5-2 Hz)

#### Filter Sweeps

```cpp
// LFO sweeping filter cutoff
float lfo = saw_lfo.get_output();           // -1 to +1
float cutoff = 500 * pow(2.0, lfo * 3.0);  // 62 Hz to 4 kHz
filter.set_cutoff(cutoff);
```

**Musical context:**
- **Wah-wah**: Slow sine or triangle (0.5-2 Hz)
- **Rhythmic filter**: Tempo-synced saw (1/4 note, 1/8 note)
- **Evolving pads**: Very slow noise LFO (0.1 Hz)

#### Stereo Panning

```cpp
// LFO creating stereo movement
float lfo = sine_lfo.get_output();  // -1 to +1
float pan = (lfo + 1.0) * 0.5;      // 0 (left) to 1 (right)
output_L = signal * (1.0 - pan);
output_R = signal * pan;
```

**Musical context:**
- **Auto-pan**: Slow sine (0.2-1 Hz)
- **Rotary speaker**: Faster movement (2-5 Hz)
- **Stereo widening**: Two LFOs at different phases

## Surge's LFO System

### Voice LFOs vs. Scene LFOs

Surge provides **12 LFOs per scene**: 6 voice LFOs and 6 scene LFOs.

```cpp
// From: src/common/SurgeStorage.h

const int n_lfos_voice = 6;  // Voice LFOs (polyphonic)
const int n_lfos_scene = 6;  // Scene LFOs (monophonic)
const int n_lfos = n_lfos_voice + n_lfos_scene;  // 12 total
```

#### Voice LFOs (Polyphonic)

**Behavior**: Each voice gets its own independent LFO instance.

```
Key pressed: C3 → Voice 1 → Voice LFO 1 (instance A)
Key pressed: E3 → Voice 2 → Voice LFO 1 (instance B)
Key pressed: G3 → Voice 3 → Voice LFO 1 (instance C)

Each instance runs independently with its own phase!
```

**Use cases:**

1. **Stereo Detuning/Width**
   ```
   Voice LFO 1 → Oscillator Pitch (small amount)
   Trigger Mode: Random Phase

   Result: Each note has slightly different vibrato phase,
           creating natural chorusing and stereo width
   ```

2. **Per-Note Vibrato**
   ```
   Voice LFO 1 → Pitch
   Trigger Mode: Key Trigger (starts at phase 0)

   Result: Vibrato starts from same point for each note,
           like a solo violinist
   ```

3. **Polyphonic Filter Movement**
   ```
   Voice LFO 2 → Filter Cutoff
   Each note has independent filter sweep
   ```

**Phase relationships:**

```cpp
// From: src/common/dsp/modulators/LFOModulationSource.cpp

switch (lfo->trigmode.val.i)
{
case lm_keytrigger:
    phase = phaseslider;  // All voices start at same phase
    break;

case lm_random:
    phase = storage->rand_01();  // Each voice random phase
    break;

case lm_freerun:
    // Phase based on song position (synchronized)
    double timePassed = storage->songpos * storage->temposyncratio_inv * 0.5;
    phase = fmod(timePassed * rate, 1.0);
    break;
}
```

#### Scene LFOs (Monophonic)

**Behavior**: One global instance shared by all voices in the scene.

```
All voices share the same Scene LFO 1 instance
→ All notes affected identically
→ Single unified movement
```

**Use cases:**

1. **Global Filter Sweep**
   ```
   Scene LFO 1 → Filter 1 Cutoff
   All voices swept together (classic synth sound)
   ```

2. **Rhythmic Pulsing**
   ```
   Scene LFO 2 → Scene Output Level
   Tempo-synced square wave creates gating effect
   ```

3. **Unified Modulation**
   ```
   Scene LFO 3 → FM Amount
   All voices modulated together for coherent texture
   ```

4. **Master Effects Modulation**
   ```
   Scene LFO 4 → Delay Feedback
   Scene LFO 5 → Chorus Rate
   Global effect parameter sweeps
   ```

**Memory efficiency:**

```
Voice LFO memory usage:
  16 voices × 6 voice LFOs = 96 LFO instances

Scene LFO memory usage:
  6 scene LFOs = 6 LFO instances (regardless of voice count!)

Use Scene LFOs when polyphonic variation isn't needed.
```

### When to Use Which

| Application | LFO Type | Trigger Mode | Why |
|------------|----------|--------------|-----|
| Global filter sweep | Scene | Freerun | Unified movement |
| Per-note vibrato | Voice | Keytrigger | Independent per note |
| Stereo chorusing | Voice | Random | Random phase variety |
| Rhythmic gating | Scene | Freerun | Locked to tempo |
| Pitch drift (all notes) | Scene | Freerun | Synchronized drift |
| Pitch drift (per note) | Voice | Random | Independent drift |

## LFO Waveforms

Surge offers **10 waveform types** for LFOs:

```cpp
// From: src/common/SurgeStorage.h

enum lfo_type
{
    lt_sine = 0,      // Smooth sinusoidal
    lt_tri,           // Triangle (linear rise/fall)
    lt_square,        // Square (hard on/off)
    lt_ramp,          // Sawtooth (linear ramp)
    lt_noise,         // Smoothed random
    lt_snh,           // Sample & Hold (stepped random)
    lt_envelope,      // One-shot ADSR
    lt_stepseq,       // 16-step sequencer
    lt_mseg,          // Multi-Segment Envelope Generator
    lt_formula,       // Lua-scriptable custom waveforms

    n_lfo_types,
};
```

### 1. Sine (lt_sine)

**Description**: Smooth, continuous oscillation.

```
Waveform:
    1.0 ┤       ╱‾‾‾╲
        │      ╱     ╲
    0.0 ┼─────╯       ╰─────
        │
   -1.0 ┤
        └───────────────────→ Time
```

**Implementation:**

```cpp
// From: src/common/dsp/modulators/LFOModulationSource.cpp
case lt_sine:
{
    constexpr auto wst_sine = sst::waveshapers::WaveshaperType::wst_sine;

    iout = bend1(storage->lookup_waveshape_warp(wst_sine, 2.f - 4.f * phase));
    break;
}
```

**Deform effects** (3 types):

- **Type 1**: Skew the waveform (more time rising vs. falling)
- **Type 2**: Add harmonics (moves toward triangle)
- **Type 3**: Phase distortion

**Musical uses:**
- Vibrato (smooth pitch modulation)
- Tremolo (smooth volume pulsing)
- Filter sweeps (no abrupt jumps)
- Natural, organic modulation

### 2. Triangle (lt_tri)

**Description**: Linear rise and fall (sharper than sine).

```
Waveform:
    1.0 ┤      ╱╲
        │     ╱  ╲
    0.0 ┼────╯    ╰────
        │
   -1.0 ┤
        └───────────────→ Time
```

**Implementation:**

```cpp
case lt_tri:
{
    iout = bend1(-1.f + 4.f * ((phase > 0.5) ? (1 - phase) : phase));
    break;
}
```

**Characteristics:**
- Constant rate of change (linear slopes)
- Brighter than sine (odd harmonics)
- Symmetrical rise/fall

**Musical uses:**
- Vibrato with more "edge" than sine
- Rhythmic filter sweeps
- Modular-style modulation

### 3. Square (lt_square)

**Description**: Abrupt switching between two states.

```
Waveform:
    1.0 ┤  ‾‾‾‾‾    ‾‾‾‾‾
        │
    0.0 ┤        ────────
        │  ─────┘        └─────
   -1.0 ┤
        └───────────────────────→ Time
```

**Implementation:**

```cpp
case lt_square:
{
    iout = (phase > (0.5f + 0.5f * localcopy[ideform].f)) ? -1.f : 1.f;
    break;
}
```

**Deform parameter**: Controls pulse width (duty cycle)

```
Deform = -1.0:  Very narrow pulse
Deform =  0.0:  50% duty cycle (square)
Deform = +1.0:  Very wide pulse
```

**Musical uses:**
- Trance gates (rhythmic on/off)
- Hard tremolo (helicopter effect)
- Sync'd rhythmic gating
- Arpeggiator-like effects

### 4. Sawtooth/Ramp (lt_ramp)

**Description**: Linear ramp from high to low.

```
Waveform:
    1.0 ┤╲     ╲     ╲
        │ ╲     ╲     ╲
    0.0 ┼  ╲     ╲     ╲
        │   ╲     ╲     ╲
   -1.0 ┤    ╲_____╲_____╲___
        └───────────────────────→ Time
```

**Implementation:**

```cpp
case lt_ramp:
{
    iout = bend1(1.f - 2.f * phase);
    break;
}
```

**Characteristics:**
- Ramps down linearly
- Discontinuous jump at cycle boundary
- Rich in harmonics

**Musical uses:**
- Classic filter sweeps (downward swoosh)
- Sequenced-style modulation
- Rhythmic pitch drops
- Analog sequencer feel

### 5. Noise (lt_noise)

**Description**: Smoothly interpolated random values.

```
Waveform:
    1.0 ┤  ╱‾╲  ╱╲ ╱ ‾╲╱‾
        │ ╱   ╲╱  ╲   ╱
    0.0 ┼╯         ╲ ╱
        │           ╲╱
   -1.0 ┤
        └───────────────────→ Time
```

**Implementation:**

```cpp
case lt_noise:
{
    // Generate new random value each cycle
    wf_history[0] = sdsp::correlated_noise_o2mk2_suppliedrng(
        target, noised1,
        limit_range(localcopy[ideform].f, -1.f, 1.f),
        urng
    );

    // Cubic interpolation between values
    iout = sdsp::cubic_ipol(wf_history[3], wf_history[2],
                            wf_history[1], wf_history[0], phase);
    break;
}
```

**Deform parameter**: Controls correlation (smoothness)

```
Deform = -1.0:  Highly correlated (smooth, slow changes)
Deform =  0.0:  Uncorrelated (white noise, filtered)
Deform = +1.0:  Anti-correlated (rapid oscillations)
```

**Musical uses:**
- Organic pitch drift (detune slowly)
- Evolving filter movement
- Randomized panning
- Simulating analog instability
- Creating "living" textures

### 6. Sample & Hold (lt_snh)

**Description**: Random stepped values (classic analog sequencer sound).

```
Waveform:
    1.0 ┤  ‾‾‾┐
        │     │ ‾‾‾┐
    0.0 ┼─────┘    └────┐
        │               └───
   -1.0 ┤
        └───────────────────→ Time
```

**Implementation:**

```cpp
case lt_snh:
{
    // Generate new random value each cycle
    if (phase_wrapped)
    {
        iout = sdsp::correlated_noise_o2mk2_suppliedrng(
            target, noised1,
            limit_range(localcopy[ideform].f, -1.f, 1.f),
            urng
        );
    }
    // Hold value until next cycle
    break;
}
```

**Deform types:**

- **Type 1**: Controls correlation (like noise)
- **Type 2**: Interpolation amount (S&H → smoothed → fully interpolated)

**Musical uses:**
- Random pitch sequences (classic analog)
- Stepped filter movement
- Rhythmic random modulation
- Sci-fi effects
- Generative melodies (when modulating pitch)

### 7. Envelope (lt_envelope)

**Description**: One-shot ADSR envelope (non-looping).

```
Envelope:
    1.0 ┤     ╱╲
        │    ╱  ╲___________
        │   ╱       S       ╲
    0.5 │  ╱                 ╲
        │ ╱                   ╲
        │╱                     ╲___
    0.0 └────────────────────────────→ Time
         A  D    Sustain        R
```

**Parameters:**
- **Delay**: Time before envelope starts
- **Attack**: Rise time to peak
- **Hold**: Time at peak before decay
- **Decay**: Fall time to sustain level
- **Sustain**: Held level
- **Release**: Fall time to zero after note-off

**Use cases:**

1. **Slower Envelopes** (beyond normal Amp/Filter EG)
   ```
   Envelope LFO → Oscillator Mix
   Attack: 5 seconds → Slow crossfade between oscillators
   ```

2. **Multi-Stage Modulation**
   ```
   Envelope LFO → Filter Cutoff
   D-H-D envelope for complex filter evolution
   ```

3. **One-Shot Effects**
   ```
   Envelope LFO → FM Amount
   Initial FM brightness that fades
   ```

### 8. Step Sequencer (lt_stepseq)

**Description**: 16-step programmable sequencer.

```
Step Sequencer:
    1.0 ┤ █     █     █
        │ █   █ █   █ █ █
    0.5 ┼ █ █ █ █ █ █ █ █
        │ █ █ █ █ █ █ █ █
    0.0 └─┴─┴─┴─┴─┴─┴─┴─┴─→ Steps
         1 2 3 4 5 6 7 8...
```

**Features:**
- **16 steps** with independent values (-1 to +1, or 0 to +1 in unipolar)
- **Loop start/end** points (can loop shorter than 16 steps)
- **Per-step trigger masks** (trigger envelopes on specific steps)
- **Shuffle** (swing timing via phase parameter)
- **Deform parameter**: Interpolation smoothing

See **Step Sequencer** section below for full details.

### 9. MSEG (lt_mseg)

**Multi-Segment Envelope Generator**: Freeform drawable envelopes.

See **[Chapter 21: MSEG](21-mseg.md)** for comprehensive coverage.

### 10. Formula (lt_formula)

**Lua-scriptable modulation**: Custom waveforms via code.

See **[Chapter 22: Formula Modulation](22-formula-modulation.md)** for details.

## LFO Parameters

Surge's LFOs have extensive control parameters:

```cpp
// From: src/common/SurgeStorage.h

struct LFOStorage
{
    Parameter rate;         // Speed (Hz or tempo-synced)
    Parameter shape;        // Waveform selection
    Parameter start_phase;  // Initial phase (0-1)
    Parameter magnitude;    // Amplitude/depth
    Parameter deform;       // Shape morphing parameter
    Parameter trigmode;     // Trigger mode (freerun/keytrigger/random)
    Parameter unipolar;     // Bipolar (-1 to +1) or Unipolar (0 to +1)

    // Envelope (for controlling LFO amplitude over time)
    Parameter delay;        // Time before LFO starts
    Parameter hold;         // Hold at zero before attack
    Parameter attack;       // Rise time to full amplitude
    Parameter decay;        // Fall time to sustain level
    Parameter sustain;      // Held amplitude level
    Parameter release;      // Fade time after note-off
};
```

### Rate

**Range**:
- **Non-synced**: -7 to +9 (logarithmic) ≈ 0.008 Hz to 512 Hz
- **Tempo-synced**: 64 bars to 1/512 note

```cpp
// From: src/common/dsp/modulators/LFOModulationSource.cpp

if (!lfo->rate.temposync)
{
    // Hz mode: exponential scaling
    frate = storage->envelope_rate_linear_nowrap(-localcopy[rate].f);
}
else
{
    // Tempo-synced: locked to DAW tempo
    frate = (double)BLOCK_SIZE_OS * storage->dsamplerate_os_inv *
            pow(2.0, localcopy[rate].f);
    frate *= storage->temposyncratio;
}

phase += frate * ratemult;
```

**Tempo-sync divisions:**

```
64 bars       Very slow evolving textures
32 bars       Slow pad movement
16 bars
8 bars
4 bars        Slow filter sweep
2 bars
1 bar
1/2 note
1/4 note      Common rhythmic rate
1/8 note      Faster rhythm
1/16 note     Fast pulsing
1/32 note     Very fast (trill-like)
1/64 note
1/128 note
1/256 note    Approaching audio rate
```

**Musical applications:**

```
0.1 Hz:   Slow pad evolution
0.5 Hz:   Gentle vibrato
2 Hz:     Moderate tremolo
5 Hz:     Fast vibrato
10 Hz:    Trill effect
20 Hz:    Audio-rate tremolo (AM synthesis)
```

### Magnitude (Amplitude)

**Range**: -3 to +3 (exponential scaling)

Controls the **depth** of modulation:

```cpp
// Applied to final LFO output
auto magnf = limit_range(lfo->magnitude.get_extended(localcopy[magn].f),
                         -3.f, 3.f);
output = magnf * lfo_value;
```

**Examples:**

```
Magnitude = 0.1:  Subtle vibrato (±10 cents)
Magnitude = 0.5:  Moderate modulation
Magnitude = 1.0:  Full-range modulation
Magnitude = 2.0:  Extended range (can push parameters beyond normal limits)
```

**Negative magnitude**: Inverts the waveform

```
Positive: Saw wave ramps down
Negative: Saw wave ramps up
```

### Start Phase

**Range**: 0.0 to 1.0 (one full cycle)

Sets the **initial phase** when the LFO is triggered.

```
Phase = 0.00:  Start at zero crossing (rising)
Phase = 0.25:  Start at peak
Phase = 0.50:  Start at zero crossing (falling)
Phase = 0.75:  Start at trough
```

**Visualization:**

```
Sine wave with different start phases:

Phase = 0.00:         Phase = 0.25:
    ╱‾╲                   ‾╲     ╱‾
───╯   ╰───           ───   ╰───╯

Phase = 0.50:         Phase = 0.75:
   ╲     ╱                ╲     ╱‾
────╰───╯              ‾╲ ╰───╯
```

**Special use for Step Sequencer**: Shuffle/swing parameter

```cpp
// In step sequencer mode, start_phase becomes shuffle
auto shuffle_val = limit_range(
    lfo->start_phase.get_extended(localcopy[startphase].f),
    -1.99f, 1.99f
);

// Alternates step timing: long-short-long-short
if (shuffle_id)
    ratemult = 1.f / (1.f - 0.5f * shuffle_val);
else
    ratemult = 1.f / (1.f + 0.5f * shuffle_val);
```

### Deform

**Purpose**: Morphs the waveform shape (varies by waveform type).

**Sine wave deform** (Type 1):

```cpp
float bend1(float x)
{
    float a = 0.5f * limit_range(localcopy[ideform].f, -3.f, 3.f);

    // Apply twice for "extra pleasure"
    x = x - a * x * x + a;
    x = x - a * x * x + a;

    return x;
}
```

**Effect:**
- Negative: Sharpens the peak
- Zero: Pure sine
- Positive: Fattens the trough

**Square wave deform**: Pulse width modulation

```cpp
iout = (phase > (0.5f + 0.5f * localcopy[ideform].f)) ? -1.f : 1.f;
```

```
Deform = -1.0:  10% duty cycle  ─╮_________╯─
Deform =  0.0:  50% duty cycle  ──╮____╯────
Deform = +1.0:  90% duty cycle  ───╮_╯──────
```

**Noise/S&H deform**: Correlation (smoothness)

**Step Sequencer deform** (Type 1): Interpolation amount

```
Deform = -1.0:  Sharp steps (no interpolation)
Deform =  0.0:  Linear interpolation
Deform = +1.0:  Cubic interpolation (smooth curves)
```

**Step Sequencer deform** (Type 2): Quadratic B-spline interpolation

### Trigger Mode

**Three modes** control how the LFO phase initializes:

```cpp
// From: src/common/SurgeStorage.h

enum lfo_trigger_mode
{
    lm_freerun = 0,     // Synchronized to song position
    lm_keytrigger,      // Reset on each note
    lm_random,          // Random phase on each note

    n_lfo_trigger_modes,
};
```

#### Freerun Mode

**Behavior**: LFO runs continuously, synchronized to song position.

```cpp
case lm_freerun:
{
    // Calculate phase based on song position
    double timePassed = storage->songpos * storage->temposyncratio_inv * 0.5;
    float totalPhase = startPhase + timePassed * lrate;
    phase = fmod(totalPhase, 1.0);
    break;
}
```

**Result:**
- All voices share the same LFO phase
- Pressing a key at different times = different LFO positions
- Perfect for tempo-locked effects

**Use cases:**
- Global filter sweeps (all notes swept together)
- Rhythmic gating (locked to DAW tempo)
- Synchronized effects

#### Keytrigger Mode

**Behavior**: LFO resets to start phase on every note-on.

```cpp
case lm_keytrigger:
    phase = phaseslider;  // Reset to start_phase parameter
    step = 0;
    break;
```

**Result:**
- Predictable, repeatable modulation
- Every note starts at the same LFO position
- Independent per voice (Voice LFOs only)

**Use cases:**
- Per-note vibrato (starts after delay)
- Consistent filter sweeps per note
- Predictable modulation patterns

#### Random Mode

**Behavior**: LFO starts at a random phase on each note-on.

```cpp
case lm_random:
    phase = storage->rand_01();  // Random 0.0-1.0
    step = (storage->rand() % ss->loop_end) & (n_stepseqsteps - 1);
    break;
```

**Result:**
- Organic, non-repetitive modulation
- Each voice has different LFO phase
- Creates natural stereo width

**Use cases:**
- Stereo detuning (voices drift differently)
- Chorusing effect
- Organic, "human" modulation
- Avoiding phase-cancellation issues

### Unipolar vs. Bipolar

**Bipolar** (default): Output ranges from -1 to +1

```
    1.0 ┤    ╱‾‾‾╲
    0.0 ┼───╯     ╰───  ← Oscillates around zero
   -1.0 ┤
```

**Unipolar**: Output ranges from 0 to +1

```
    1.0 ┤    ╱‾‾‾╲
    0.5 ┼───╯     ╰───
    0.0 ┤               ← Never goes negative
```

**Implementation:**

```cpp
if (lfo->unipolar.val.b)
{
    io2 = 0.5f + 0.5f * io2;  // Convert -1..+1 to 0..+1
}
```

**When to use:**

- **Bipolar**: Vibrato, filter sweeps (modulate around base value)
- **Unipolar**: Volume/gain, mix amounts, gate effects (0 = off, 1 = full)

### LFO Envelope (Delay, Attack, Hold, Decay, Sustain, Release)

LFOs have their own **amplitude envelope** separate from the waveform itself:

```
LFO Envelope (controls LFO amplitude over time):

    1.0 ┤     ╱╲____________
Amp     │    ╱  ╲    S      ╲
    0.5 │   ╱                ╲
        │  ╱                  ╲
    0.0 └─┴───────────────────┴───→ Time
         D A H D    Sustain    R

LFO Waveform (oscillates, scaled by envelope):

       ╱‾╲        ╱‾╲ ╱‾╲ ╱‾╲      ╱
    ──╯   ╰──────╯   ╰   ╰   ╰────╯
    ↑     ↑      ↑              ↑
  Quiet  Loud   Full Amp     Fading
```

**Parameters:**

- **Delay**: Time before LFO starts (useful for delayed vibrato)
- **Attack**: Time for LFO to reach full amplitude
- **Hold**: Time at full amplitude before decay
- **Decay**: Time to fall to sustain level
- **Sustain**: Held amplitude level (0-1)
- **Release**: Fade time after note-off

**Example: Delayed Vibrato**

```
Sine LFO → Pitch
Rate: 5 Hz
Magnitude: 0.2 (subtle vibrato)

Envelope:
  Delay:   500 ms  ← No vibrato at start
  Attack:  200 ms  ← Gradual onset
  Hold:    0 ms
  Decay:   0 ms
  Sustain: 1.0     ← Full vibrato while held
  Release: 100 ms  ← Quick fade

Result: Classic "delayed vibrato" like a violinist
        Note starts straight, vibrato fades in
```

**Implementation:**

```cpp
// Calculate envelope value
float useenvval = env_val;  // 0.0 to 1.0

// Apply to LFO output
output = useenvval * magnf * lfo_waveform;
```

## Step Sequencer

The **Step Sequencer** mode transforms the LFO into a programmable 16-step sequencer.

### Structure

```cpp
// From: src/common/SurgeStorage.h

const int n_stepseqsteps = 16;

struct StepSequencerStorage
{
    float steps[n_stepseqsteps];  // Value for each step (-1 to +1)
    int loop_start, loop_end;      // Loop boundaries
    float shuffle;                 // Swing/shuffle amount
    uint64_t trigmask;            // Per-step trigger gates
};
```

### Step Values

Each of 16 steps stores a value:

```
Step:   1    2    3    4    5    6    7    8    ...
Value: 0.5  0.7  1.0  0.3 -0.2 -0.8 -0.5  0.0  ...
```

**Editing:**
- Click and drag to set step values
- Unipolar mode: 0.0 to +1.0
- Bipolar mode: -1.0 to +1.0

### Loop Points

Control which steps play:

```cpp
loop_start = 0;   // First step to play
loop_end = 7;     // Last step to play (inclusive)

// Sequence plays steps 0-7, then loops back to 0
```

**Examples:**

```
loop_start = 0, loop_end = 15:  All 16 steps
loop_start = 0, loop_end = 7:   First 8 steps only
loop_start = 4, loop_end = 11:  Middle 8 steps
loop_start = 0, loop_end = 2:   3-step sequence
```

### Step Sequencer Timing

Rate parameter controls **step advancement speed**:

```
Rate = 1/16 note:  One step per 16th note
Rate = 1/8 note:   One step per 8th note
Rate = 1/4 note:   One step per quarter note

At 120 BPM:
  1/16 note = 125 ms per step
  1/8 note  = 250 ms per step
  1/4 note  = 500 ms per step
```

### Shuffle/Swing

The **start_phase** parameter becomes **shuffle** in step sequencer mode:

```cpp
// Alternates step timing
shuffle_id = (shuffle_id + 1) & 1;  // Toggles 0/1

if (shuffle_id)
    ratemult = 1.f / (1.f - 0.5f * shuffle_val);
else
    ratemult = 1.f / (1.f + 0.5f * shuffle_val);
```

**Effect:**

```
Shuffle = 0:   Even timing
               ┌─┬─┬─┬─┬─┬─┬─┬─┐
               1 2 3 4 5 6 7 8

Shuffle = 0.5: Swing (long-short pattern)
               ┌──┬┬──┬┬──┬┬──┬┐
               1  23  45  67  8

Shuffle = -0.5: Reverse swing (short-long)
               ┌┬──┬┬──┬┬──┬┬──┐
               12  34  56  78
```

### Interpolation (Deform Parameter)

Controls smoothness between steps:

**Type 1 Deform:**

```
Deform = -1.0:  Sharp steps (no interpolation)
    1.0 ┤ ─┐     ┌───
        │  │  ┌──┘
    0.0 └──┘──┴─────

Deform = 0.0:   Linear interpolation
    1.0 ┤  ╱╲    ╱
        │ ╱  ╲  ╱
    0.0 └╯    ╲╱

Deform = +1.0:  Cubic interpolation (smooth curves)
    1.0 ┤  ╱‾╲  ╱‾
        │ ╱   ╲╱
    0.0 └╯
```

**Type 2 Deform**: Quadratic B-spline interpolation (even smoother)

**Implementation:**

```cpp
case lt_stepseq:
{
    float df = localcopy[ideform].f;

    if (df > 0.5f)
    {
        // Blend between linear and cubic interpolation
        float linear = (1.f - phase) * wf_history[2] + phase * wf_history[1];
        float cubic = sdsp::cubic_ipol(wf_history[3], wf_history[2],
                                       wf_history[1], wf_history[0], phase);

        iout = (2.f - 2.f * df) * linear + (2.f * df - 1.0f) * cubic;
    }
    // ... other interpolation modes
}
```

### Trigger Gates

Each step can trigger envelopes:

```cpp
uint64_t trigmask;  // 64-bit mask

// Bits 0-15:  Trigger both Filter EG and Amp EG
// Bits 16-31: Trigger Filter EG only
// Bits 32-47: Trigger Amp EG only
```

**Example:**

```
Steps:      1  2  3  4  5  6  7  8
Both EGs:   X     X     X     X      (kick pattern)
Filter EG:     X     X     X     X   (hi-hat pattern)
Amp EG:     X           X            (accent pattern)
```

**Implementation:**

```cpp
if (ss->trigmask & (UINT64_C(1) << step))
{
    retrigger_FEG = true;
    retrigger_AEG = true;
}

if (ss->trigmask & (UINT64_C(1) << (16 + step)))
{
    retrigger_FEG = true;
}

if (ss->trigmask & (UINT64_C(1) << (32 + step)))
{
    retrigger_AEG = true;
}
```

**Musical use case:**

```
Step Sequencer → Filter Cutoff
  Steps create rhythmic filter pattern

Trigger gates on steps 1, 5, 9, 13:
  Retrigger Amp EG on those steps

Result: Rhythmic gated filter with envelope accents
        (classic techno/trance sound)
```

### Zero-Rate Scrubbing

When **rate = 0**, the step sequencer can be scrubbed manually:

```cpp
if (frate == 0)
{
    // Phase now scrubs through all 16 steps
    float p16 = phase * n_stepseqsteps;
    int pstep = ((int)p16) & (n_stepseqsteps - 1);

    // Can modulate phase parameter to "play" the sequence
}
```

**Use case:**

```
Step Sequencer → Wavetable Position
Rate: 0 (disabled)
LFO 2 (Sine) → Step Sequencer Phase

Result: Sine LFO scans through the 16 step values,
        which control wavetable position.
        Meta-modulation!
```

## Implementation Details

### Class Structure

```cpp
// From: src/common/dsp/modulators/LFOModulationSource.h

class LFOModulationSource : public ModulationSource
{
public:
    void assign(SurgeStorage *storage,
                LFOStorage *lfo,
                pdata *localcopy,
                SurgeVoiceState *state,
                StepSequencerStorage *ss,
                MSEGStorage *ms,
                FormulaModulatorStorage *fs,
                bool is_display = false);

    virtual void attack() override;
    virtual void release() override;
    virtual void process_block() override;

    float get_output(int which) const override;

private:
    float phase;              // Current phase (0.0 to 1.0)
    int unwrappedphase_intpart;  // Integer phase (for MSEG, Formula)
    float env_val;            // Envelope amplitude (0.0 to 1.0)
    int env_state;            // Envelope state machine
    float output_multi[3];    // Output channels

    float wf_history[4];      // History for interpolation
    int step;                 // Current step (step sequencer)
    float ratemult;           // Rate multiplier (shuffle)
};
```

### Process Block

The main processing function:

```cpp
void LFOModulationSource::process_block()
{
    // 1. Calculate rate (Hz or tempo-synced)
    float frate = /* ... calculate rate ... */;

    // 2. Advance phase
    phase += frate * ratemult;

    // 3. Wrap phase (0.0 to 1.0)
    if (phase >= 1.0)
    {
        phase -= 1.0;
        unwrappedphase_intpart++;

        // Generate new values for random waveforms
        // Advance step sequencer
        // ...
    }

    // 4. Calculate waveform output
    switch (lfo->shape.val.i)
    {
    case lt_sine:
        iout = /* sine calculation */;
        break;
    case lt_tri:
        iout = /* triangle calculation */;
        break;
    // ... other waveforms
    }

    // 5. Process envelope
    env_val = /* calculate envelope stage */;

    // 6. Apply envelope and magnitude
    output = env_val * magnf * iout;
}
```

### Phase Management

Phase is the core state variable:

```cpp
float phase;  // 0.0 to 1.0 (one full cycle)
int unwrappedphase_intpart;  // Integer part (counts cycles)

// Example: phase = 2.7
// →  phase = 0.7, unwrappedphase_intpart = 2

// MSEG and Formula modulators need the integer part
// to handle multi-cycle envelopes
```

### Envelope State Machine

```cpp
enum LFOEG_state
{
    lfoeg_off = 0,
    lfoeg_delay,
    lfoeg_attack,
    lfoeg_hold,
    lfoeg_decay,
    lfoeg_release,
    lfoeg_msegrelease,
    lfoeg_stuck,
};
```

Transition diagram:

```
OFF ──attack()──> DELAY ──time──> ATTACK ──peak──> HOLD ──time──> DECAY ──sustain──> STUCK
                                                                                        ↑
                                                                                        │
   ←──release()────────────────────────────────────────────────────────RELEASE ←──────┘
```

### Output Channels

LFOs provide **3 output channels**:

```cpp
output_multi[0] = (useenvval) * magnf * iout;  // Main output (with envelope)
output_multi[1] = iout;                         // Raw waveform (no envelope)
output_multi[2] = useenvval;                    // Envelope only
```

**Use cases:**

- **Channel 0**: Normal use (waveform × envelope)
- **Channel 1**: Waveform without envelope influence
- **Channel 2**: Use LFO envelope as a modulation source itself

## Musical Applications and Patch Ideas

### Classic Vibrato

```
Voice LFO 1:
  Shape: Sine
  Rate: 5-6 Hz
  Magnitude: 0.1-0.3
  Trigger: Keytrigger

  Envelope:
    Delay: 300-500 ms
    Attack: 200 ms
    Sustain: 1.0

Route: Voice LFO 1 → All Oscillators Pitch
Amount: 0.2-0.5 (20-50 cents)

Result: Natural string/vocal vibrato that fades in
```

### Rhythmic Filter Sweep

```
Scene LFO 1:
  Shape: Sawtooth
  Rate: 1/4 note (tempo-synced)
  Trigger: Freerun
  Magnitude: 1.0

Route: Scene LFO 1 → Filter 1 Cutoff
Amount: 3-5 octaves

Result: Classic techno filter sweep locked to beat
```

### Stereo Auto-Pan

```
Scene LFO 2:
  Shape: Sine
  Rate: 0.5-2 Hz
  Unipolar: Yes
  Magnitude: 1.0

Route: Scene LFO 2 → Scene Output Pan
Amount: 0.8-1.0

Result: Smooth stereo panning movement
```

### Evolving Pad Texture

```
Voice LFO 1:
  Shape: Noise
  Rate: 0.1 Hz (very slow)
  Deform: -0.5 (smooth changes)
  Trigger: Random

Voice LFO 2:
  Shape: Sine
  Rate: 0.3 Hz
  Trigger: Random

Scene LFO 1:
  Shape: Triangle
  Rate: 0.05 Hz (extremely slow)

Routes:
  Voice LFO 1 → Oscillator 1 Pitch: 0.1 (subtle drift)
  Voice LFO 2 → Filter Cutoff: 1.0 octave
  Scene LFO 1 → Oscillator Mix: 0.3 (slow crossfade)

Result: Rich, evolving, organic pad that never repeats
```

### Step-Sequenced Bass

```
Scene LFO 3:
  Shape: Step Sequencer
  Rate: 1/16 note
  Trigger: Freerun
  Loop: 0-7 (8 steps)
  Shuffle: 0.3 (swing)

  Steps: Program a bass line pattern

Route: Scene LFO 3 → Oscillator Pitch
Amount: 24 semitones (2 octaves)

Add trigger gates on steps 1, 5:
  Retrigger Amp EG for accents

Result: Sequenced bassline with swing, triggered envelopes
```

### Trance Gate

```
Scene LFO 4:
  Shape: Square
  Rate: 1/16 note
  Deform: -0.3 (narrow pulses)
  Unipolar: Yes
  Trigger: Freerun

Route: Scene LFO 4 → Scene Output Level
Amount: 1.0

Result: Rhythmic gating effect (stuttering sound)
```

### FM Bell with Decay

```
Voice LFO 3:
  Shape: Envelope

  Envelope:
    Delay: 0
    Attack: 5 ms
    Hold: 0
    Decay: 2000 ms
    Sustain: 0.0 (one-shot)
    Release: 0

Route: Voice LFO 3 → FM Amount
Amount: 0.8

Result: Initial FM brightness that decays
        (bell-like timbre evolution)
```

## Performance Characteristics

### CPU Usage

```
Per LFO per process_block():
  Sine:          ~80 cycles
  Triangle:      ~60 cycles
  Square:        ~40 cycles
  Sawtooth:      ~50 cycles
  Noise:         ~120 cycles (random generation + interpolation)
  S&H:           ~100 cycles
  Envelope:      ~70 cycles
  Step Seq:      ~150 cycles (interpolation)
  MSEG:          ~300 cycles (segment traversal)
  Formula:       ~500-5000 cycles (depends on script complexity)

Envelope processing: +~80 cycles per LFO
```

### Memory Footprint

```cpp
sizeof(LFOModulationSource) ≈ 200 bytes

Per scene:
  6 Voice LFOs × max_voices (16-64) = 19.2 KB to 76.8 KB
  6 Scene LFOs = 1.2 KB

Step Sequencer storage:
  16 floats × 12 LFOs × 2 scenes = 1.5 KB

MSEG storage:
  Variable (depends on segment count)
```

### Efficiency Tips

1. **Use Scene LFOs** when polyphonic variation isn't needed (saves memory)
2. **Simpler waveforms** (square, triangle) are cheaper than noise/step sequencer
3. **Formula modulators** are most expensive (use sparingly)
4. **Disable unused LFO envelopes** (set delay to minimum if not needed)

## Advanced Techniques

### Meta-Modulation (LFO of LFO)

```
Scene LFO 1 (Slow Sine, 0.1 Hz)
  ↓
Voice LFO 1 Rate parameter
  ↓
Voice LFO 1 (Fast Sine) → Pitch

Result: Vibrato speed itself oscillates
          (slow vibrato → fast vibrato → slow)
```

### Crossfading Oscillators

```
Scene LFO 2 (Triangle, 0.2 Hz, Unipolar)
  → Oscillator 1 Level: -0.5
  → Oscillator 2 Level: +0.5

Result: As LFO sweeps:
  LFO = 0:   Osc 1 full, Osc 2 silent
  LFO = 0.5: Both at 50%
  LFO = 1:   Osc 1 silent, Osc 2 full

Creates smooth timbral crossfade
```

### Polyrhythmic Modulation

```
Scene LFO 1: 1/4 note (4 beats)
Scene LFO 2: 1/6 note (6 beats per bar = triplets)
Scene LFO 3: 1/8 note dotted (3 beats)

→ Different parameters
→ Creates complex, non-repeating rhythmic patterns
→ Pattern repeats every LCM(4,6,3) = 12 beats = 3 bars
```

### Random Sample & Hold Quantizer

```
Scene LFO 4:
  Shape: Sample & Hold
  Rate: 1/8 note
  Unipolar: Yes

Route: Scene LFO 4 → Oscillator Pitch
Amount: 12 semitones (1 octave)

Result: Random note selection from 1-octave range
        Changes every 8th note
        (generative melody)
```

## Conclusion

Surge XT's LFO system demonstrates:

1. **Dual Architecture**: 6 voice LFOs (polyphonic) + 6 scene LFOs (monophonic) per scene
2. **Waveform Variety**: 10 waveform types from simple sine to programmable step sequencer
3. **Flexible Triggering**: Freerun, keytrigger, and random phase modes
4. **Envelope Control**: Full DAHDSR envelope for LFO amplitude over time
5. **Tempo Synchronization**: Lock to DAW tempo for rhythmic effects
6. **Deformable Shapes**: Morphable waveforms via deform parameter
7. **Step Sequencer**: 16-step programmable sequencer with interpolation and trigger gates
8. **Implementation Efficiency**: Per-block processing with optimized waveform generation

LFOs complement envelopes by providing cyclic, repeating modulation. Where envelopes shape individual notes, LFOs create ongoing movement: vibrato, tremolo, filter sweeps, rhythmic pulsing, and evolving textures. The distinction between voice and scene LFOs—polyphonic versus monophonic modulation—enables both per-note variation and unified global movement.

Surge's LFO implementation balances power with performance, offering extensive control while maintaining efficient CPU usage through per-block processing and optimized waveform algorithms. From subtle vibrato to complex polyrhythmic modulation, Surge's LFOs provide the rhythmic pulse that brings static sounds to life.

---

**Next: [MSEG (Multi-Segment Envelope Generator)](21-mseg.md)**
**See Also: [Envelopes](19-envelopes.md), [Modulation Architecture](18-modulation-architecture.md), [Formula Modulation](22-formula-modulation.md)**
