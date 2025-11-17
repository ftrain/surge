# Chapter 19: Envelope Generators

## The Contour of Sound

If oscillators provide the raw material of sound and filters shape its tone, envelope generators define its evolution over time. An envelope is the **dynamic contour** that transforms a static waveform into a living, breathing musical event. Without envelopes, every note would play at constant volume and brightness, sounding mechanical and lifeless. With them, sounds attack, evolve, sustain, and fade naturally.

This chapter explores Surge's envelope generators in depth: the theory behind ADSR envelopes, Surge's dual-envelope architecture, analog versus digital modes, and the sophisticated implementation that brings these time-varying control signals to life.

## Envelope Theory

### What is an Envelope?

An **envelope generator** (EG) produces a control signal that changes over time in response to note events. Unlike oscillators which cycle continuously, envelopes are **one-shot** or **sustained** contours triggered by MIDI note-on and released by note-off.

**Key characteristics:**

- **Triggered**: Starts when a key is pressed
- **Shaped**: Follows a predefined contour (ADSR stages)
- **Sustained**: Can hold at a level while key is pressed
- **Time-based**: Stages measured in seconds (or tempo-synced beats)
- **Control-rate**: Typically updated per-block, not per-sample

### The ADSR Model

**ADSR** stands for **Attack, Decay, Sustain, Release** - a four-stage envelope model developed in the 1960s that has become the synthesis industry standard.

```
Amplitude
    1.0 ┤     ╱╲
        │    ╱  ╲___________
        │   ╱       S       ╲
    0.5 │  ╱                 ╲
        │ ╱                   ╲
        │╱                     ╲___
    0.0 └────────────────────────────→ Time
         A  D    Sustain        R

         ↑              ↑      ↑
      Note On       Key Held  Note Off
```

**The Four Stages:**

1. **Attack (A)**: Time to rise from 0 to peak (1.0)
   - Controls how quickly the sound "strikes"
   - Short: Percussive (drums, plucks)
   - Long: Soft, swelling (pads, strings)

2. **Decay (D)**: Time to fall from peak to sustain level
   - Creates initial brightness that fades
   - Works with filter cutoff for "pluck" sounds

3. **Sustain (S)**: **Level** held while key is pressed
   - **Note**: This is a LEVEL (0.0-1.0), not a time!
   - 1.0 = held at peak
   - 0.0 = silent after decay
   - 0.5 = held at half amplitude

4. **Release (R)**: Time to fall from current level to silence after note-off
   - Controls the "tail" of the sound
   - Short: Staccato, tight
   - Long: Reverberant, sustained

### ADSR in Synthesis

Envelopes modulate multiple aspects of sound:

#### Amplitude Envelope (Amp EG)

Controls the **loudness** of the sound over time:

```cpp
// Basic amplitude envelope application
float sample = oscillator.process();
float envelope = amp_eg.get_output();  // 0.0 to 1.0
float output = sample * envelope;
```

**Timbral implications:**
- **Percussive** (Attack: fast, Decay: medium, Sustain: 0, Release: short)
  - Drums, plucks, mallet instruments
- **Sustained** (Attack: medium, Decay: short, Sustain: high, Release: medium)
  - Organs, strings, wind instruments
- **Swelling** (Attack: slow, Decay: 0, Sustain: 1.0, Release: medium)
  - Pads, string swells, reverse effects

#### Filter Envelope (Filter EG)

Modulates **filter cutoff** to create timbral evolution:

```cpp
// Filter envelope modulation
float base_cutoff = 1000.0;  // Hz
float eg_amount = 5.0;       // octaves of modulation
float envelope = filter_eg.get_output();
float cutoff = base_cutoff * pow(2.0, envelope * eg_amount);

filter.set_cutoff(cutoff);
```

**Classic uses:**
- **TB-303 Bass**: High envelope amount, medium decay, zero sustain
  - Cutoff sweeps down creating "squelch"
- **Funky Clavinet**: Fast attack, fast decay, medium sustain
  - Initial brightness that mellows
- **Brass Swell**: Slow attack on both amp and filter
  - Sound "blooms" like a real brass section

### Analog vs. Digital Envelopes

Surge implements both **analog-style** and **digital** envelope behaviors:

#### Analog Envelopes

Classic analog synthesizers used **charging and discharging capacitors** to generate envelope voltages:

```
    V_cc ─┬─── R (Resistor) ───┬─── Output
          │                     │
         SW (Gate)              C (Capacitor)
          │                     │
         GND                   GND
```

**Characteristics:**
- **Exponential curves**: Capacitors charge/discharge exponentially
- **Natural feel**: Matches acoustic instrument dynamics
- **Parameter interaction**: Sustain level affects decay time
- **Smooth**: No stepping or zipper noise

**The math:**

```
V(t) = V_target + (V_initial - V_target) × e^(-t / RC)
```

Where:
- `V_target` = Voltage we're approaching (sustain level or zero)
- `V_initial` = Starting voltage
- `RC` = Time constant (controls rate)
- `t` = Time elapsed

#### Digital Envelopes

Software synthesizers can use **linear segments** for precise control:

**Characteristics:**
- **Linear ramps**: Straight lines between stages
- **Predictable**: Easy to calculate and visualize
- **Tempo-syncable**: Exact beat divisions
- **Curve-shapeable**: Can still add exponential curves via shaping

**The math:**

```
// Linear attack
phase += rate;  // rate = 1.0 / attack_time
output = phase;
```

Surge offers both modes, letting users choose between vintage character (analog) and modern precision (digital).

## ADSR Parameters in Depth

### Attack Time

**Range**: Typically 0 ms to 10 seconds
**Parameter space**: Logarithmic (more resolution at short times)

```cpp
// From: src/common/dsp/modulators/ADSRModulationSource.h (Digital mode)

case (s_attack):
{
    phase += storage->envelope_rate_linear_nowrap(lc[a].f) *
             (adsr->a.temposync ? storage->temposyncratio : 1.f);

    if (phase >= 1)
    {
        phase = 1;
        envstate = s_decay;  // Transition to decay
    }

    // Apply curve shaping
    switch (lc[a_s].i)
    {
    case 0:
        output = sqrt(phase);      // Exponential (fast start, slow end)
        break;
    case 1:
        output = phase;            // Linear
        break;
    case 2:
        output = phase * phase;    // Logarithmic (slow start, fast end)
        break;
    }
}
```

**Curve shapes** (controlled by `a_s` parameter):

```
Exponential (0):    Linear (1):      Logarithmic (2):
    ╱                  ╱                    ╱
   ╱                  ╱                   ╱
  ╱                  ╱                 ╱╱
 ╱                  ╱               ╱╱
╱___              ╱___          ___╱
```

**Musical applications:**
- **0 ms**: Instant attack (organ, synth bass)
- **5-20 ms**: Percussive (piano, plucked strings)
- **50-200 ms**: Soft attack (woodwinds, mellow synths)
- **500+ ms**: Slow swell (pads, reverse effects)

### Decay Time

**Range**: 0 ms to 10+ seconds
**Behavior**: Time to fall from peak (1.0) to sustain level

```cpp
// From: src/common/dsp/modulators/ADSRModulationSource.h

case (s_decay):
{
    float rate = storage->envelope_rate_linear_nowrap(lc[d].f) *
                 (adsr->d.temposync ? storage->temposyncratio : 1.f);

    // Decay with curve shaping
    switch (lc[d_s].i)
    {
    case 1:
    {
        float sx = sqrt(phase);
        l_lo = phase - 2 * sx * rate + rate * rate;
        l_hi = phase + 2 * sx * rate + rate * rate;

        // Handle edge cases for low sustain values
        if ((lc[s].f < 1e-3 && phase < 1e-4) || (lc[s].f == 0 && lc[d].f < -7))
        {
            l_lo = 0;
        }
    }
    break;
    // ... other curve shapes
    }

    phase = limit_range(lc[s].f, l_lo, l_hi);
    output = phase;
}
```

**Interaction with Sustain:**

If sustain = 0.0 (like a drum envelope):
- Decay time is the total "tail" duration
- Creates percussive, one-shot sounds

If sustain = 1.0:
- Decay has no effect (no fall to occur)
- Sound jumps to full level and holds

### Sustain Level

**CRITICAL**: Sustain is a **LEVEL** (0.0 to 1.0), NOT a time!

This is a common point of confusion. All other ADSR parameters are times, but sustain is the **held amplitude** during the note.

```cpp
// From: src/common/SurgeStorage.h
struct ADSRStorage
{
    Parameter a, d, s, r;  // s is level, not time!
    Parameter a_s, d_s, r_s;
    Parameter mode;
};
```

**Values:**
- **1.0**: Hold at peak (organ-like)
- **0.7**: Moderate sustain (piano-ish after initial brightness)
- **0.0**: No sustain (drums, plucks)

**Analog mode quirk:**

In analog mode, sustain interacts with the capacitor discharge circuit:

```cpp
// Sustain affects decay behavior in analog mode
float S = sparm;
float normD = std::max(0.05f, 1 - S);
coef_D /= normD;  // Decay rate compensated by sustain level
```

### Release Time

**Range**: 0 ms to 10+ seconds
**Triggered by**: MIDI note-off

```cpp
void ADSRModulationSource::release() override
{
    scalestage = output;  // Remember current output level
    phase = 1;
    envstate = s_release;
}
```

**Note**: Release starts from the **current envelope level**, not from 1.0:

```
If released during:
  Attack:  Releases from current attack level
  Decay:   Releases from current decay level
  Sustain: Releases from sustain level
```

This creates natural-sounding releases regardless of when the key is lifted.

**Special case: Uber-release**

Surge has a fast emergency release for voice stealing:

```cpp
void uber_release()
{
    scalestage = output;
    phase = 1;
    envstate = s_uberrelease;
}

// Ultra-fast release (-6.5 = very fast)
phase -= storage->envelope_rate_linear_nowrap(-6.5);
```

### Curve Shape Parameters

Surge provides **three curve shapers**:

```cpp
Parameter a_s;  // Attack shape (0=exponential, 1=linear, 2=logarithmic)
Parameter d_s;  // Decay shape (0=linear, 1=exponential, 2=cubic)
Parameter r_s;  // Release shape (0-3, number of multiplications for curve steepness)
```

**Release curve implementation:**

```cpp
case (s_release):
{
    phase -= storage->envelope_rate_linear_nowrap(lc[r].f);

    output = phase;

    // Apply curve by repeated multiplication
    for (int i = 0; i < lc[r_s].i; i++)
    {
        output *= phase;
    }

    output *= scalestage;  // Scale by level at release start
}
```

Effect of `r_s` values:
- **0**: Linear decay
- **1**: `output = phase²` (exponential)
- **2**: `output = phase³` (more curved)
- **3**: `output = phase⁴` (very curved, natural tail)

## Surge's Two Envelopes

Surge provides **two independent ADSR envelopes per scene**:

```cpp
// From: src/common/SurgeStorage.h
const int n_egs = 2;  // Envelope generators per scene

enum EnvelopeType
{
    envelope_filter = 0,
    envelope_amp = 1,
};
```

### Filter Envelope (Filter EG)

**Default routing**: Modulates filter cutoff frequency

**Purpose**: Create timbral evolution and movement

**Classic patches:**

1. **Acid Bass** (TB-303 style)
   ```
   Attack:  0 ms
   Decay:   400 ms
   Sustain: 0.0
   Release: 50 ms

   Filter Cutoff: ~500 Hz base
   EG Amount: +4 octaves
   Resonance: 70%

   Result: "Squelchy" sweep from bright to muted
   ```

2. **Plucked String**
   ```
   Attack:  1 ms
   Decay:   800 ms
   Sustain: 0.3
   Release: 200 ms

   Filter Cutoff: ~800 Hz
   EG Amount: +3 octaves

   Result: Initial "pluck" brightness that mellows
   ```

**Not limited to filters!** Despite its name, Filter EG can modulate any parameter via the modulation matrix.

### Amplitude Envelope (Amp EG)

**Default routing**: Controls voice output level (VCA)

**Purpose**: Shape the loudness contour

**Hard-wired behavior:**

```cpp
// From: src/common/dsp/SurgeVoice.cpp
// Amp envelope is always applied to voice output
float amp_env = envelopes[envelope_amp].get_output();
output_L *= amp_env;
output_R *= amp_env;
```

**Classic patches:**

1. **Organ**
   ```
   Attack:  0 ms
   Decay:   0 ms
   Sustain: 1.0
   Release: 10 ms

   Result: Instant on, instant off (like key contacts)
   ```

2. **Pad**
   ```
   Attack:  800 ms
   Decay:   500 ms
   Sustain: 0.8
   Release: 2000 ms

   Result: Slow swell, long tail, lush
   ```

3. **Percussive Hit**
   ```
   Attack:  1 ms
   Decay:   300 ms
   Sustain: 0.0
   Release: 50 ms

   Result: Sharp strike, quick fade
   ```

### Independent Control

Because Surge has **two independent envelopes**, you can create complex timbral evolution:

**Example: Evolving Pad**

```
Filter EG:
  Attack:  2000 ms (slow brightness increase)
  Decay:   1000 ms
  Sustain: 0.6
  Release: 3000 ms

Amp EG:
  Attack:  1000 ms (faster volume rise)
  Decay:   500 ms
  Sustain: 0.9
  Release: 2500 ms

Result: Volume rises quickly, but brightness swells slowly behind it,
        creating depth and movement
```

## Envelope Modes: Analog vs. Digital

Surge offers two envelope processing modes:

```cpp
Parameter mode;  // false = Digital, true = Analog
```

### Digital Mode (Default)

**Implementation**: Linear segments with optional curve shaping

```cpp
// Digital mode state machine
switch (envstate)
{
case (s_attack):
    phase += rate;
    if (phase >= 1) envstate = s_decay;
    break;

case (s_decay):
    phase = limit_range(sustain_level, phase - rate, phase + rate);
    break;

case (s_sustain):
    // Hold at sustain level
    break;

case (s_release):
    phase -= rate;
    if (phase <= 0) envstate = s_idle;
    break;
}
```

**Advantages:**
- Predictable, linear behavior
- Exact tempo sync
- Precise control
- Low CPU usage

**Use for:**
- Modern electronic music
- Tempo-synced patches
- Rhythmic modulation
- Gate sequences

### Analog Mode

**Implementation**: Capacitor charge/discharge simulation with SSE2 SIMD

```cpp
// From: src/common/dsp/modulators/ADSRModulationSource.h
// Analog mode capacitor simulation

const float v_cc = 1.5f;  // Supply voltage

auto v_c1 = SIMD_MM(load_ss)(&_v_c1);           // Capacitor voltage
auto discharge = SIMD_MM(load_ss)(&_discharge); // Discharge state

bool gate = (envstate == s_attack) || (envstate == s_decay);
auto v_gate = gate ? SIMD_MM(set_ss)(v_cc) : SIMD_MM(set_ss)(0.f);

// Attack voltage target: v_cc (when not discharging)
auto v_attack = SIMD_MM(andnot_ps)(discharge, v_gate);

// Decay voltage target: sustain level (when discharging)
auto v_decay = SIMD_MM(or_ps)(
    SIMD_MM(andnot_ps)(discharge, v_cc_vec),
    SIMD_MM(and_ps)(discharge, S)
);

// Release voltage target: 0V
auto v_release = v_gate;

// Calculate voltage differences
auto diff_v_a = SIMD_MM(max_ss)(SIMD_MM(setzero_ps)(),
                                SIMD_MM(sub_ss)(v_attack, v_c1));
auto diff_v_d = /* ... complex decay difference calculation ... */;
auto diff_v_r = SIMD_MM(min_ss)(SIMD_MM(setzero_ps)(),
                                SIMD_MM(sub_ss)(v_release, v_c1));

// Apply RC time constants
v_c1 = SIMD_MM(add_ss)(v_c1, SIMD_MM(mul_ss)(diff_v_a, coef_A));
v_c1 = SIMD_MM(add_ss)(v_c1, SIMD_MM(mul_ss)(diff_v_d, coef_D));
v_c1 = SIMD_MM(add_ss)(v_c1, SIMD_MM(mul_ss)(diff_v_r, coef_R));
```

**RC Time Constant Calculation:**

```cpp
const float coeff_offset = 2.f - log(storage->samplerate / BLOCK_SIZE) / log(2.f);

float coef_A = powf(2.f, std::min(0.f, coeff_offset - lc[a].f));
float coef_D = powf(2.f, std::min(0.f, coeff_offset - lc[d].f));
float coef_R = powf(2.f, std::min(0.f, coeff_offset - lc[r].f));
```

**Advantages:**
- Warm, vintage character
- Natural-sounding curves
- Parameter interdependence (like real circuits)
- Smooth, organic feel

**Use for:**
- Vintage synth emulation
- Classic bass and lead sounds
- Organic pads and textures
- Recreating analog warmth

### Choosing a Mode

**Use Digital when:**
- You need precise, repeatable timing
- Tempo sync is important
- You want linear or custom curves
- You're making modern EDM or electronic music

**Use Analog when:**
- You want vintage character
- Emulating classic synths (Minimoog, Jupiter, Prophet)
- Creating warm, organic sounds
- You prefer "feel" over precision

## State Machine Implementation

ADSR envelopes are implemented as **finite state machines**:

```cpp
// From: src/common/dsp/modulators/ADSRModulationSource.h

enum ADSRState
{
    s_attack = 0,
    s_decay,
    s_sustain,
    s_release,
    s_uberrelease,  // Fast voice-stealing release
    s_idle_wait1,   // Waiting before going idle
    s_idle,         // Inactive, ready for retrigger
};
```

### State Transitions

```
IDLE ──note_on──> ATTACK ──peak──> DECAY ──sustain──> SUSTAIN
                                                          │
                                                      note_off
                                                          │
                                                          ▼
                                                       RELEASE ──silence──> IDLE
```

**Voice stealing path:**

```
ANY_STATE ──steal──> UBERRELEASE ──silence──> IDLE
```

### Initialization

```cpp
void ADSRModulationSource::init(SurgeStorage *storage,
                                ADSRStorage *adsr,
                                pdata *localcopy,
                                SurgeVoiceState *state)
{
    this->storage = storage;
    this->adsr = adsr;
    this->state = state;
    this->lc = localcopy;

    // Get parameter IDs for fast access
    a = adsr->a.param_id_in_scene;
    d = adsr->d.param_id_in_scene;
    s = adsr->s.param_id_in_scene;
    r = adsr->r.param_id_in_scene;

    envstate = s_attack;
    phase = 0;
    output = 0;
}
```

### Attack Triggering

```cpp
virtual void attackFrom(float start)
{
    phase = 0;
    output = 0;

    if (start > 0)
    {
        output = start;
        // Adjust phase based on curve shape to match output
        switch (lc[a_s].i)
        {
        case 0:  // Exponential: output = sqrt(phase)
            phase = output * output;
            break;
        case 1:  // Linear: output = phase
            phase = output;
            break;
        case 2:  // Logarithmic: output = phase²
            phase = sqrt(output);
            break;
        }
    }

    envstate = s_attack;

    // Handle instant attack (attack time near minimum)
    if ((lc[a].f - adsr->a.val_min.f) < 0.01)
    {
        envstate = s_decay;
        output = 1;
        phase = 1;
    }
}
```

### Release Triggering

```cpp
void release() override
{
    scalestage = output;  // Remember current level
    phase = 1;            // Start from top of release phase
    envstate = s_release;
}
```

**Key insight**: `scalestage` stores the envelope level at release time, allowing natural decay from any point in the envelope.

## Per-Sample vs. Per-Block Processing

Surge uses **per-block** (control-rate) envelope processing for efficiency:

```cpp
virtual void process_block() override
{
    // Called once per BLOCK_SIZE samples (typically 32)
    // Updates internal state and sets 'output' member variable

    // ... state machine logic ...

    output = calculated_value;  // Single value for entire block
}
```

**Efficiency gain:**

```
Per-sample:  48,000 Hz × 1 update = 48,000 calculations/sec
Per-block:   48,000 Hz ÷ 32 = 1,500 calculations/sec

Savings: 32× reduction!
```

**Smoothing:**

To avoid stepping artifacts, parameter changes are smoothed:

```cpp
// Envelope output changes are small enough per-block
// that they don't cause audible stepping
// (32 samples @ 48kHz = 0.67ms steps)
```

For critical paths (like cutoff modulation), Surge uses **lipol** (linear interpolation):

```cpp
lipol<float, true> cutoff_interpolator;
cutoff_interpolator.set_target(new_cutoff);

for (int k = 0; k < BLOCK_SIZE; k++)
{
    float smooth_cutoff = cutoff_interpolator.v;
    output[k] = filter.process(input[k], smooth_cutoff);
    cutoff_interpolator.process();  // Interpolate
}
```

## Advanced Features

### Tempo Sync

All envelope stages can be **tempo-synced** to the host DAW:

```cpp
// From: src/common/dsp/modulators/ADSRModulationSource.h

phase += storage->envelope_rate_linear_nowrap(lc[a].f) *
         (adsr->a.temposync ? storage->temposyncratio : 1.f);
```

**Use cases:**

```
Tempo: 120 BPM (0.5 sec per beat)

Attack = 1 beat  → 500 ms
Decay  = 1/2 beat → 250 ms
Release = 2 beats → 1000 ms
```

Perfect for:
- Rhythmic modulation
- Sync'd filter sweeps
- Tempo-locked arpeggiation
- Sequenced patches

### Deformable Envelopes (Curve Shapes)

The curve shape parameters (`a_s`, `d_s`, `r_s`) allow **continuous deformation** of envelope curves:

```cpp
// Attack curve shaping
switch (lc[a_s].i)
{
case 0:  // Exponential
    output = sqrt(phase);        // Quick start, slow finish
    break;
case 1:  // Linear
    output = phase;              // Constant rate
    break;
case 2:  // Logarithmic
    output = phase * phase;      // Slow start, quick finish
    break;
}
```

**Musical applications:**

- **Exponential attack**: Natural for percussive sounds
- **Linear attack**: Mechanical, precise
- **Logarithmic attack**: "Bowed" feel, slow emergence

### Velocity Sensitivity

Envelopes can be **velocity-modulated** via the modulation matrix:

```
Velocity → Filter EG Attack Time (negative modulation)
Result: Harder hits = faster attack = more percussive
```

```
Velocity → Amp EG Sustain Level (positive modulation)
Result: Harder hits = louder sustain = more dynamic
```

This creates **expressive, performance-responsive** patches.

### Gated Release Mode

Surge supports **gated release** where the release stage only occurs when the gate is closed:

```cpp
const bool r_gated = adsr->r.deform_type;

if (!r_gated)
{
    output = phase;  // Normal release decay
}
else
{
    output = _ungateHold;  // Hold at gate-off level
}
```

**Use for:**
- Hold pedal simulation
- Sustain-pedal-controlled release
- "Freeze" effects

## Idle Detection

Voices must be efficiently detected as **idle** to free them for new notes:

```cpp
bool is_idle() { return (envstate == s_idle) && (idlecount > 0); }
```

**Digital mode:**

```cpp
case s_release:
    phase -= rate;
    if (phase < 0)
    {
        envstate = s_idle;
        output = 0;
    }
    break;

case s_idle:
    idlecount++;  // Count idle blocks
    break;
```

**Analog mode:**

```cpp
const float SILENCE_THRESHOLD = 1e-6;

if (!gate && _discharge == 0.f && _v_c1 < SILENCE_THRESHOLD)
{
    envstate = s_idle;
    output = 0;
    idlecount++;
}
```

Once `idlecount > 0`, the voice can be reallocated.

## Complete Code Example: Digital ADSR

Here's a simplified, educational ADSR implementation:

```cpp
class SimpleADSR
{
public:
    void trigger()
    {
        state = ATTACK;
        phase = 0.0f;
        output = 0.0f;
    }

    void release()
    {
        state = RELEASE;
        release_level = output;  // Remember where we released from
    }

    void process_block(float sample_rate)
    {
        float rate;

        switch (state)
        {
        case ATTACK:
            rate = 1.0f / (attack_time * sample_rate / BLOCK_SIZE);
            phase += rate;

            if (phase >= 1.0f)
            {
                phase = 1.0f;
                output = 1.0f;
                state = DECAY;
            }
            else
            {
                output = phase;  // Linear for simplicity
            }
            break;

        case DECAY:
            rate = 1.0f / (decay_time * sample_rate / BLOCK_SIZE);
            output -= rate;

            if (output <= sustain_level)
            {
                output = sustain_level;
                state = SUSTAIN;
            }
            break;

        case SUSTAIN:
            output = sustain_level;
            // Wait for release
            break;

        case RELEASE:
            rate = 1.0f / (release_time * sample_rate / BLOCK_SIZE);
            output -= release_level * rate;

            if (output <= 0.0f)
            {
                output = 0.0f;
                state = IDLE;
            }
            break;

        case IDLE:
            output = 0.0f;
            break;
        }
    }

    float get_output() { return output; }

    // Parameters
    float attack_time = 0.01f;   // seconds
    float decay_time = 0.1f;
    float sustain_level = 0.7f;  // 0.0 to 1.0
    float release_time = 0.2f;

private:
    enum State { IDLE, ATTACK, DECAY, SUSTAIN, RELEASE };
    State state = IDLE;
    float phase = 0.0f;
    float output = 0.0f;
    float release_level = 0.0f;
};
```

**Usage:**

```cpp
SimpleADSR envelope;
envelope.attack_time = 0.005f;   // 5 ms attack
envelope.decay_time = 0.2f;      // 200 ms decay
envelope.sustain_level = 0.5f;   // 50% sustain
envelope.release_time = 0.5f;    // 500 ms release

// Note on
envelope.trigger();

// Process audio blocks
for (int block = 0; block < num_blocks; block++)
{
    envelope.process_block(48000.0f);
    float env_value = envelope.get_output();

    for (int i = 0; i < BLOCK_SIZE; i++)
    {
        output[i] = oscillator[i] * env_value;
    }
}

// Note off
envelope.release();
```

## Performance Characteristics

**Memory footprint:**

```cpp
sizeof(ADSRModulationSource) ≈ 100 bytes per envelope

Per voice (2 envelopes):  ~200 bytes
64 voices × 200 bytes = ~12.8 KB total
```

**CPU usage** (approximate, x86-64):

```
Digital mode:   ~50 cycles per process_block()
Analog mode:    ~200 cycles per process_block() (SIMD)

Per voice per second (48kHz, BLOCK_SIZE=32):
  48000 / 32 = 1500 blocks/sec
  1500 × 200 = 300,000 cycles/voice/sec

64 voices: ~19.2 million cycles/sec (~5 ms on 3.5 GHz CPU)
```

Envelopes are **cheap** compared to oscillators and filters!

## Conclusion

Surge's ADSR envelope generators demonstrate:

1. **Dual Architecture**: Filter EG and Amp EG provide independent timbral and amplitude control
2. **Flexibility**: Analog and digital modes offer vintage character or modern precision
3. **Curve Shaping**: Deformable attack, decay, and release curves
4. **Tempo Sync**: Musical timing locked to DAW tempo
5. **Performance**: Efficient per-block processing with SIMD optimization
6. **Expressiveness**: Velocity sensitivity and gated release modes

Envelopes transform static tones into dynamic, evolving sounds. Understanding ADSR parameters—and the critical distinction that sustain is a level, not a time—unlocks expressive sound design. Surge's implementation provides the vintage warmth of analog circuits alongside the precision of digital control, giving sound designers the best of both worlds.

In the next chapter, we'll explore LFOs (Low-Frequency Oscillators), which complement envelopes by providing cyclic, repeating modulation for vibrato, tremolo, and evolving textures.

---

**Next: [LFOs (Low-Frequency Oscillators)](20-lfos.md)**
**See Also: [Modulation Architecture](18-modulation-architecture.md), [MSEG](21-mseg.md), [Filters](10-filters.md)**
