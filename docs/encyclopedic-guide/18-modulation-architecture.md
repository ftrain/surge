# Chapter 18: Modulation Architecture

## The Heart of Dynamic Sound

If oscillators generate raw sound and filters shape its timbre, modulation breathes life into both. Surge XT's modulation system transforms static sounds into evolving, organic textures through a sophisticated routing matrix that can connect any modulation source to any modulatable parameter.

This chapter explores Surge's modulation architecture: how modulation sources generate control signals, how the routing matrix directs them, and how parameters respond to create movement, expression, and musical evolution.

## Modulation in Synthesis

### What is Modulation?

**Modulation** is using one signal (the modulator) to control a parameter of another (the carrier).

In synthesizers:
- **Audio-rate modulation**: One oscillator modulating another (FM, ring mod)
- **Control-rate modulation**: LFOs and envelopes shaping parameters

Examples:
- LFO → Filter Cutoff = **Filter sweep**
- Envelope → VCA Gain = **Volume contour**
- Velocity → Filter Resonance = **Expressive playing**
- Aftertouch → Vibrato Depth = **Dynamic performance**

### Why Modulation Matters

Without modulation, every note sounds identical:
- No attack/decay envelope
- No vibrato or tremolo
- No filter sweeps
- No evolving textures

Modulation creates:
- **Movement**: Sounds that evolve over time
- **Expression**: Playing dynamics affect tone
- **Complexity**: Multiple modulations create rich, organic textures
- **Musicality**: Dynamic response to performance

## Surge's Modulation Architecture

### Overview

Surge provides:

```cpp
// From: src/common/SurgeStorage.h

const int n_lfos_voice = 6;   // Voice LFOs (per voice, polyphonic)
const int n_lfos_scene = 6;   // Scene LFOs (global to scene)
const int n_lfos = 12;        // Total LFOs per scene

const int n_egs = 2;          // Envelope Generators (Filter EG, Amp EG)

// Plus:
// - 8 Macro controls (user-assignable)
// - MIDI controllers (velocity, aftertouch, modwheel, etc.)
// - Per-note modulation (MPE, note expressions)
// - Formula modulators (Lua-scriptable)
// - MSEG (Multi-Segment Envelope Generator)
```

**Per Scene:**
- 12 LFOs (6 voice + 6 scene)
- 2 Envelope Generators
- 8 Macros
- Unlimited MIDI sources
- Unlimited formula modulators
- Unlimited MSEG instances

**Total available modulation sources:** 40+ per scene!

### Modulation Source Types

#### 1. Envelopes (Per-Voice)

```cpp
enum EnvelopeType
{
    envelope_filter,    // Controls filter cutoff/resonance
    envelope_amp,       // Controls output amplitude
    n_egs = 2
};
```

**ADSR Parameters:**
- **Attack**: Time to reach peak
- **Decay**: Time to fall to sustain
- **Sustain**: Held level while key pressed
- **Release**: Time to silence after key release

**Surge Enhancements:**
- Analog mode (curves similar to analog circuits)
- Digital mode (linear segments)
- Attack/Decay/Release curve shapes
- Tempo sync option

#### 2. LFOs (Low-Frequency Oscillators)

Two types:

**Voice LFOs** (polyphonic):
- One instance per voice
- Each voice has independent phase
- Perfect for stereo detuning, vibrato

**Scene LFOs** (monophonic):
- Shared across all voices
- Synchronized movement
- Perfect for filter sweeps, global effects

**LFO Features:**
- Multiple waveforms (sine, triangle, saw, square, S&H, etc.)
- Tempo sync
- Phase randomization
- Unipolar / Bipolar
- Envelope mode (one-shot)
- Step sequencer mode

#### 3. Macros

8 user-assignable macro controls:

```cpp
// Macros are simple 0-1 value sources
// But they can be:
// - MIDI learned to any CC
// - Modulated by other sources
// - Used to control multiple parameters
```

**Use cases:**
- Map mod wheel → vibrato depth
- Map expression pedal → filter + volume
- Create "Timbre" knob controlling multiple oscillators

#### 4. MIDI Sources

Built-in MIDI sources:
- **Velocity**: Note-on velocity (0-127)
- **Release Velocity**: Note-off velocity
- **Keytrack**: MIDI note number (keyboard position)
- **Aftertouch** (Channel pressure)
- **Polyphonic Aftertouch** (Per-note pressure)
- **Modwheel** (CC1)
- **Breath Controller** (CC2)
- **Expression** (CC11)
- **Sustain Pedal** (CC64)
- **Pitchbend**
- **Any MIDI CC** (learnable)

#### 5. MSEG (Multi-Segment Envelope Generator)

Freeform envelope drawing:
- Unlimited segments
- Multiple curve types
- Looping with various modes
- Can act as LFO or envelope
- Tempo sync

See **[Chapter 21: MSEG](21-mseg.md)** for details.

#### 6. Formula Modulators

Lua-scriptable modulation:

```lua
-- Example: Sine wave with variable phase
function process(phase)
    return math.sin(phase * 2 * math.pi + 0.5)
end
```

See **[Chapter 22: Formula Modulation](22-formula-modulation.md)** for details.

## The Modulation Matrix

### Routing Architecture

Surge uses a **flexible routing matrix** rather than hard-wired modulation paths.

**Traditional synthesizers:**
```
LFO 1 ────────→ Filter Cutoff (fixed)
Envelope 1 ────→ VCA (fixed)
```

**Surge's approach:**
```
Any Modulation Source ──→ Routing Matrix ──→ Any Modulatable Parameter
```

This means:
- LFO 1 can modulate filter cutoff, *and* pitch, *and* pulse width, *and*...
- Filter cutoff can receive modulation from LFO 1, *and* Envelope 1, *and* velocity, *and*...
- Unlimited modulation routings (within reason)

### Creating Modulation Routings

**In the UI:**

1. Click on a modulation source (LFO, envelope, etc.)
2. Adjust a parameter slider
3. Modulation routing is created!
4. Depth is shown in blue (or orange if negative)

**Internally:**

```cpp
// Simplified modulation routing structure
struct ModulationRouting
{
    int source_id;       // Which modulation source
    int dest_param_id;   // Which parameter to modulate
    float depth;         // Modulation amount (-1.0 to +1.0)
    int source_index;    // Which instance (e.g., LFO 1, LFO 2, etc.)
    int source_scene;    // Scene A or B (if applicable)
};
```

### Modulation Application

Each processing block:

```cpp
void SurgeVoice::process_block()
{
    // 1. Calculate modulation source outputs
    float lfo1_output = lfos[0].get_output();
    float filterEG_output = envelopes[envelope_filter].get_output();
    float velocity = state.velocity / 127.0;

    // 2. Apply modulation routings to parameters
    for (auto &route : modulation_routes)
    {
        float mod_value = getModulationSourceValue(route.source_id);
        float modulated = param_base[route.dest_param_id] +
                         mod_value * route.depth * param_range[route.dest_param_id];

        param_effective[route.dest_param_id] = modulated;
    }

    // 3. Use effective parameter values for processing
    float cutoff = param_effective[filtercutoff];
    oscillator->process_block(param_effective[pitch], ...);
    filter->process_block(cutoff, ...);
}
```

## Modulation Source Base Class

All modulation sources inherit from:

```cpp
// From: src/common/ModulationSource.h

class ModulationSource
{
public:
    // Main output (-1.0 to +1.0 bipolar, or 0.0 to 1.0 unipolar)
    virtual float get_output() = 0;

    // Per-sample processing (for audio-rate modulation)
    virtual void process_block() = 0;

    // Attack phase (for retriggering)
    virtual void attack() {}

    // Release phase
    virtual void release() {}

    // Query state
    virtual bool is_active() { return true; }
    virtual bool is_bipolar() { return true; }

protected:
    float output = 0.0;
    SurgeStorage *storage;
};
```

**Key Design Points:**

1. **`get_output()`** - Returns current modulation value
2. **`process_block()`** - Updates internal state
3. **Normalized range** - Always -1 to +1 (bipolar) or 0 to 1 (unipolar)
4. **Storage reference** - Access to sample rate, tempo, etc.

## Voice vs. Scene Modulation

### Voice-Level Modulation (Polyphonic)

Each voice has independent modulation:

```cpp
class SurgeVoice
{
    // Each voice has its own LFOs
    LFOModulationSource voice_lfos[n_lfos_voice];

    // Each voice has its own envelopes
    ADSRModulationSource envelopes[n_egs];

    // Each voice has independent modulation values
    float modulation_values[n_modulation_sources];
};
```

**Example: Vibrato**

With voice LFOs, each note has independent vibrato phase:
```
Note 1: LFO phase = 0.0   → slight pitch bend up
Note 2: LFO phase = 0.5   → slight pitch bend down
Note 3: LFO phase = 0.25  → pitch at center
```

Result: Rich, organic chorus effect (like a string section where each player vibratos slightly out of phase).

### Scene-Level Modulation (Monophonic)

Scene LFOs are shared:

```cpp
class SurgeSynthesizer
{
    // Scene LFOs shared by all voices in a scene
    LFOModulationSource scene_lfos[n_scenes][n_lfos_scene];
};
```

**Example: Filter Sweep**

With scene LFO, all voices move together:
```
All notes: Same LFO phase → all filters sweep together
```

Result: Unified movement (like a single filter sweep on a chord).

## Per-Voice Polyphonic Modulation

Surge supports **per-note modulation** via:

### MPE (MIDI Polyphonic Expression)

Each note can have independent:
- Pitch bend
- Pressure (aftertouch)
- Timbre (CC74)

See **[Chapter 31: MIDI and MPE](31-midi-mpe.md)** for details.

### Note Expressions (VST3, CLAP)

Modern plugin formats allow per-note parameter control:

```cpp
// VST3 note expression
void processNoteExpression(int32 noteId, int32 paramId, double value)
{
    // Apply per-note modulation
    voice[noteId].note_expression[paramId] = value;
}
```

## Modulation Depth and Ranges

### Depth Scaling

Modulation depth is a multiplier:

```
final_value = base_value + (modulation_output × depth × parameter_range)
```

**Example: Filter Cutoff**

```cpp
// Base cutoff: 1000 Hz
// Filter range: 20 Hz to 20,000 Hz (approx 10 octaves)
// LFO output: 0.5 (halfway through sine wave)
// Modulation depth: 50%

float cutoff_base = 1000.0;  // Hz
float mod_output = 0.5;
float depth = 0.5;
float range = 10.0;  // octaves

float cutoff_octaves = log2(cutoff_base / 20.0);  // Base in octaves
cutoff_octaves += mod_output * depth * range;
float cutoff_final = 20.0 * pow(2.0, cutoff_octaves);

// Result: Cutoff sweeps to ~5600 Hz
```

### Negative Modulation

Negative depth inverts modulation:

```
LFO output: 0.0 → 1.0 → 0.0 (rising then falling)

Positive depth (+50%):
  Parameter: moves UP then DOWN

Negative depth (-50%):
  Parameter: moves DOWN then UP
```

Use cases:
- Invert envelope shapes
- Create contrary motion
- Compensate for interactions

## Modulation Visualization

The Surge UI shows modulation in real-time:

### Parameter Slider Visualization

```
Base value:        [====|========]  50%
+ Mod 1 (LFO):    +[===]            +15%
+ Mod 2 (Env):    +[======]         +25%
- Mod 3 (Vel):    -[==]             -10%
                   ─────────────
Effective value:   [==========|==]  80%
```

**Color coding:**
- White: Base value
- Blue: Positive modulation
- Orange: Negative modulation

### Modulation List

Right-click any parameter:
```
Filter Cutoff Modulations:
  ► LFO 1         +45%    [Edit] [Clear]
  ► Filter EG     +80%    [Edit] [Clear]
  ► Velocity      +25%    [Edit] [Clear]
  ► Macro 1       -15%    [Edit] [Clear]
```

### Real-Time Meters

Active modulation sources show activity:
- LFOs: Animated position indicator
- Envelopes: Current stage indicator
- Macros: Current value
- MSEG: Playback position

## Advanced Modulation Techniques

### Modulating Modulators

Surge allows **meta-modulation**: using one modulator to control another.

**Example: Vibrato with varying depth**

```
LFO 1 (vibrato) → Pitch
LFO 2 (slow) → LFO 1 Amplitude

Result: Vibrato that fades in and out
```

**Example: Envelope-controlled filter sweep**

```
LFO 1 → Filter Cutoff
Filter EG → LFO 1 Amplitude

Result: Filter sweep that only happens during attack
```

### Modulation Stacking

Multiple modulations on one parameter:

```cpp
// All modulations sum:
cutoff = base + (mod1 × depth1) + (mod2 × depth2) + (mod3 × depth3)
```

**Example: Expressive filter**

```
Filter Cutoff modulated by:
  + Envelope (large positive) → Opens on attack
  + LFO (medium) → Adds movement
  + Velocity (positive) → Brighter when played hard
  + Keytrack (positive) → Higher notes → brighter

Result: Complex, musical filter response
```

### Sample-Accurate Modulation

For audio-rate modulation:

```cpp
// Process modulation per-sample for smoothness
for (int k = 0; k < BLOCK_SIZE; k++)
{
    float mod = lfo.get_output_sample(k);
    float cutoff = base_cutoff + mod * depth;

    output[k] = filter.process_sample(input[k], cutoff);
}
```

This is essential for FM synthesis and smooth parameter changes.

## Performance Optimization

### Control-Rate Processing

Most modulation doesn't need per-sample updates:

```cpp
void SurgeVoice::process_block()
{
    // Update envelopes once per block
    filter_eg.process_block();
    amp_eg.process_block();

    // Get block-rate output
    float eg_value = filter_eg.get_output();

    // Apply to all samples in block
    for (int k = 0; k < BLOCK_SIZE; k++)
    {
        // Use same eg_value for all 32 samples
        float cutoff = base + eg_value * depth;
        output[k] = filter.process(input[k], cutoff);
    }
}
```

**Savings:** 32x fewer calculations!

**Smoothing:** Interpolate between blocks to avoid stepping:

```cpp
lipol cutoff_smoother;
cutoff_smoother.set_target(eg_value * depth);

for (int k = 0; k < BLOCK_SIZE; k++)
{
    float cutoff = base + cutoff_smoother.v;
    output[k] = filter.process(input[k], cutoff);
    cutoff_smoother.process();  // Interpolate
}
```

## Code Example: Simple LFO Modulation

```cpp
// Simplified LFO modulation
class SimpleLFO : public ModulationSource
{
public:
    void process_block() override
    {
        for (int k = 0; k < BLOCK_SIZE; k++)
        {
            // Generate sine wave
            output_buffer[k] = sin(phase * 2.0 * M_PI);

            // Advance phase
            phase += frequency * sample_rate_inv;
            if (phase >= 1.0)
                phase -= 1.0;
        }

        // Update main output to block average
        output = output_buffer[BLOCK_SIZE - 1];
    }

    float get_output() override
    {
        return output;
    }

    void set_rate(float hz)
    {
        frequency = hz;
    }

private:
    float phase = 0.0;
    float frequency = 1.0;  // Hz
    float sample_rate_inv;
    float output_buffer[BLOCK_SIZE];
};

// Usage in voice processing:
void SurgeVoice::process_block()
{
    lfo.process_block();
    float lfo_out = lfo.get_output();  // -1.0 to +1.0

    float pitch_base = midi_note_to_pitch(state.key);
    float pitch_modulated = pitch_base + lfo_out * vibrato_depth;

    oscillator->process_block(pitch_modulated);
}
```

## Conclusion

Surge's modulation architecture demonstrates:

1. **Flexibility**: Any source can modulate any parameter
2. **Depth**: 40+ modulation sources per scene
3. **Polyphony**: Independent per-voice modulation
4. **Expression**: MIDI, MPE, and note expression support
5. **Performance**: Optimized control-rate processing
6. **Visualization**: Real-time modulation display

The routing matrix transforms Surge from a static sound generator into a dynamic, expressive instrument capable of sounds that evolve, breathe, and respond to musical performance.

In the following chapters, we'll explore specific modulation sources in detail: envelopes, LFOs, MSEG, and formula modulation.

---

**Next: [Envelope Generators](19-envelopes.md)**
**See Also: [LFOs](20-lfos.md), [MSEG](21-mseg.md), [Formula Modulation](22-formula-modulation.md)**
