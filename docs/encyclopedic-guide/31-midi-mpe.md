# Chapter 31: MIDI and MPE

## From Keyboards to Controllers: The Language of Musical Expression

MIDI (Musical Instrument Digital Interface) has been the backbone of digital music for over 40 years. It's a simple yet powerful protocol that transmits performance data - which keys are pressed, how hard, what pedals are down - from controllers to synthesizers. Surge XT implements comprehensive MIDI support, from basic note-on messages to advanced MPE (MIDI Polyphonic Expression) for per-note control.

This chapter explores how Surge processes MIDI messages, implements MPE for expressive controllers, and extends beyond traditional MIDI with VST3 and CLAP note expressions.

## MIDI Fundamentals

### The MIDI Protocol

MIDI messages are compact, efficient packets of performance data. A typical note-on message contains just three bytes:
- **Status byte**: Message type and channel (0x90-0x9F for note-on)
- **Data byte 1**: Note number (0-127, where 60 = middle C)
- **Data byte 2**: Velocity (0-127, how hard the key was struck)

MIDI operates on 16 channels (0-15), allowing multiple instruments to share a single cable. Traditionally, channel 0 carries the main performance data, while other channels can control additional parts or parameters.

### Core MIDI Message Types

**Note Messages:**
```cpp
// From: src/common/SurgeSynthesizer.h
void playNote(char channel, char key, char velocity, char detune,
              int32_t host_noteid = -1, int32_t forceScene = -1);
void releaseNote(char channel, char key, char velocity, int32_t host_noteid = -1);
void chokeNote(int16_t channel, int16_t key, char velocity, int32_t host_noteid = -1);
```

**Note-on** (0x90-0x9F): Triggers a new voice with the specified pitch and velocity. Surge allocates a voice, initializes oscillators, triggers envelopes, and begins audio generation.

**Note-off** (0x80-0x8F): Releases a note, transitioning the voice to its release phase. The voice continues sounding until the amplitude envelope completes.

**Continuous Controllers:**
```cpp
// From: src/common/SurgeSynthesizer.h
void channelController(char channel, int cc, int value);
void pitchBend(char channel, int value);
void channelAftertouch(char channel, int value);
void polyAftertouch(char channel, int key, int value);
```

**Control Change (CC)** (0xB0-0xBF): Modifies continuous parameters like modulation wheel (CC1), expression (CC11), or sustain pedal (CC64). Surge supports all 128 standard CCs plus NRPN/RPN for extended control.

**Pitch Bend** (0xE0-0xEF): Smoothly detunes all notes on a channel, typically controlled by a wheel or joystick. Range is configurable (commonly ±2 semitones).

**Aftertouch**: Pressure applied after a key is struck. Channel aftertouch (0xD0-0xDF) affects all notes; polyphonic aftertouch (0xA0-0xAF) controls individual keys.

### Channel State Management

Surge maintains per-channel state to track ongoing MIDI data:

```cpp
// From: src/common/SurgeStorage.h
struct MidiChannelState
{
    MidiKeyState keyState[128];     // Per-key state (gate, velocity, etc.)
    int nrpn[2], nrpn_v[2];        // NRPN message assembly
    int rpn[2], rpn_v[2];          // RPN message assembly
    int pitchBend;                  // Current pitch bend value
    bool nrpn_last;                 // Last parameter type (NRPN vs RPN)
    bool hold;                      // Sustain pedal state
    float pan;                      // MPE pan (CC10)
    float pitchBendInSemitones;     // Pitch bend range
    float pressure;                 // Channel aftertouch value
    float timbre;                   // MPE timbre (CC74)
};
```

Each channel tracks:
- **128 keys**: Whether pressed, last velocity, last note ID
- **NRPN/RPN assembly**: Multi-message parameter changes
- **Pitch bend**: Current detune amount
- **MPE dimensions**: Pan, pressure, timbre (when MPE is enabled)

## MIDI Processing in Surge

### The MIDI Event Queue

Surge processes MIDI events sample-accurately within audio blocks. Events arrive with timestamps indicating their precise position within the current audio buffer:

```cpp
// From: src/surge-xt/SurgeSynthProcessor.cpp (processBlock)
// Events are processed in timestamp order:
// 1. Read MIDI buffer
// 2. Sort by sample position
// 3. Process audio up to each event
// 4. Apply event
// 5. Continue audio processing
```

This ensures that a note-on at sample 37 of a 64-sample block triggers the voice at exactly the right moment, maintaining rhythmic precision even at high tempos.

### Note-On Processing

When a note-on message arrives, Surge executes this sequence:

```cpp
// From: src/common/SurgeSynthesizer.cpp
void SurgeSynthesizer::playNote(char channel, char key, char velocity, char detune,
                                int32_t host_noteid, int32_t forceScene)
{
    // 1. Determine scene routing (single/split/dual/channel split)
    int scene = calculateChannelMask(channel, key);

    // 2. Track MIDI key state
    midiKeyPressedForScene[scene][key] = ++orderedMidiKey;
    channelState[channel].keyState[key].keystate = velocity;
    channelState[channel].keyState[key].lastNoteIdForKey = host_noteid;

    // 3. Update modulation sources (highest/lowest/latest key)
    updateHighLowKeys(scene);

    // 4. Allocate and initialize voice
    playVoice(scene, channel, key, velocity, detune, host_noteid);
}
```

**Scene Routing**: Surge supports four scene modes:
- **Single**: All notes go to the active scene
- **Split**: Notes below/above split point route to Scene A/B
- **Dual**: Both scenes play simultaneously
- **Channel Split**: MIDI channels route to different scenes

**Voice Allocation**: The `playVoice` function handles polyphony modes:
- **Poly**: Each note gets a new voice (up to polyphony limit)
- **Mono**: Single voice with portamento and priority rules
- **Mono ST**: Single voice with sub-oscillator portamento
- **Latch**: Notes sustain until explicitly cleared

### Pitch Bend Implementation

Pitch bend deserves special attention because it behaves differently in MPE vs. standard mode:

```cpp
// From: src/common/SurgeSynthesizer.cpp
void SurgeSynthesizer::pitchBend(char channel, int value)
{
    // MPE mode: per-channel pitch bend (ignore channel 0)
    if (mpeEnabled && channel != 0)
    {
        channelState[channel].pitchBend = value;
        // Each voice reads its channel's pitch bend in process_block
        return;
    }

    // Standard mode: global pitch bend (affects all voices)
    if (!mpeEnabled || channel == 0)
    {
        storage.pitch_bend = value / 8192.f;  // Normalize to -1.0 to 1.0
        pitchbendMIDIVal = value;

        // Update pitch bend modulation source for both scenes
        for (int sc = 0; sc < n_scenes; sc++)
        {
            ((ControllerModulationSource *)storage.getPatch().scene[sc].modsources[ms_pitchbend])
                ->set_target(storage.pitch_bend);
        }
    }
}
```

**Standard Mode**: A single pitch bend value affects all voices globally. Pitch wheel movements modulate a scene-level source that can be routed to any parameter.

**MPE Mode**: Each channel maintains its own pitch bend, applied per-voice. Channel 0 is reserved as a "manager" channel and ignored for per-note pitch bend.

### Control Change Processing

CC messages can:
1. **Modulate parameters directly** (via MIDI learn)
2. **Control modulation sources** (mod wheel, breath, etc.)
3. **Trigger system functions** (sustain pedal, all notes off)
4. **Configure MPE dimensions** (pan, timbre in MPE mode)

```cpp
// From: src/common/SurgeSynthesizer.cpp
void SurgeSynthesizer::channelController(char channel, int cc, int value)
{
    float fval = (float)value * (1.f / 127.f);

    switch (cc)
    {
    case 1:  // Mod wheel
        for (int sc = 0; sc < n_scenes; sc++)
        {
            ((ControllerModulationSource *)storage.getPatch().scene[sc].modsources[ms_modwheel])
                ->set_target(fval);
        }
        modwheelCC = value;
        hasUpdatedMidiCC = true;
        break;

    case 10: // Pan (MPE only)
        if (mpeEnabled)
        {
            channelState[channel].pan = int7ToBipolarFloat(value);
            return;  // Don't process further in MPE mode
        }
        break;

    case 64: // Sustain pedal
        channelState[channel].hold = value > 63;
        purgeHoldbuffer(scene);  // Release held notes if pedal lifted
        return;

    case 74: // Timbre (MPE only)
        if (mpeEnabled)
        {
            // Unipolar (0-1) or bipolar (-1 to 1) based on user preference
            channelState[channel].timbre =
                mpeTimbreIsUnipolar ? (value / 127.f) : int7ToBipolarFloat(value);
            return;
        }
        break;
    }

    // Check MIDI learn mappings
    // ... (parameter and macro control)
}
```

### CC Smoothing

Abrupt CC changes can create audible zipper noise. Surge applies smoothing via **ControllerModulationSource**:

```cpp
// From: src/common/ModulationSource.h
class ControllerModulationSource : public ModulationSource
{
    float target;      // Destination value
    float value;       // Current smoothed value
    bool changed;      // Target recently updated?

    void process_block() {
        // Smooth from current value toward target
        // Smoothing rate depends on smoothingMode:
        // - LEGACY: Fast (compatible with original Surge)
        // - SLOW: Gentle (reduces zipper noise)
        // - FAST: Immediate (for precise control)
    }
};
```

This interpolation happens every audio block, ensuring smooth parameter transitions even with low MIDI resolution (7-bit = 128 steps).

### MIDI Learn

Surge allows mapping any CC to any parameter:

**Learning Mode**:
1. Right-click a parameter → "MIDI Learn"
2. Move a controller (e.g., knob or slider)
3. Surge captures the CC number and channel
4. Future messages on that CC/channel control the parameter

**Soft Takeover**: When `midiSoftTakeover` is enabled, learned parameters won't jump until the controller value passes near the current parameter value, preventing jarring leaps when switching presets.

```cpp
// Soft takeover prevents jumps
if (midiSoftTakeover && p->miditakeover_status != sts_locked)
{
    const auto pval = p->get_value_f01();
    static constexpr float buffer = {1.5f / 127.f};  // Hysteresis zone

    // Wait for controller to approach current value before taking control
    if (fval < pval - buffer)
        p->miditakeover_status = sts_waiting_below;
    else if (fval > pval + buffer)
        p->miditakeover_status = sts_waiting_above;
    else
        p->miditakeover_status = sts_locked;  // Take control!
}
```

### Standard MIDI CC Mappings

Common controllers in Surge:

| CC  | Name              | Purpose                          |
|-----|-------------------|----------------------------------|
| 0   | Bank Select MSB   | Bank selection (with PC)         |
| 1   | Mod Wheel         | Vibrato, filter sweep, etc.      |
| 2   | Breath Controller | Expression via breath            |
| 6   | Data Entry MSB    | NRPN/RPN value                   |
| 10  | Pan               | MPE per-note pan                 |
| 11  | Expression        | Volume/dynamics                  |
| 32  | Bank Select LSB   | Bank selection (with PC)         |
| 38  | Data Entry LSB    | NRPN/RPN value fine              |
| 64  | Sustain Pedal     | Hold notes after release         |
| 74  | Timbre            | MPE per-note brightness          |
| 98  | NRPN LSB          | Non-registered parameter number  |
| 99  | NRPN MSB          | Non-registered parameter number  |
| 100 | RPN LSB           | Registered parameter number      |
| 101 | RPN MSB           | Registered parameter number      |
| 120 | All Sound Off     | Immediate silence                |
| 123 | All Notes Off     | Release all notes                |

## MPE: MIDI Polyphonic Expression

### The Limitations of Traditional MIDI

Standard MIDI has a fundamental constraint: controllers operate at the **channel level**. A pitch bend wheel affects *all* notes on that channel simultaneously. This makes polyphonic expression impossible - you can't bend one note while holding another steady.

This limitation shaped keyboard playing technique for decades. But with modern controllers offering per-note control (Roli Seaboard, LinnStrument, Haken Continuum), we need a protocol to transmit that expressiveness.

### The MPE Solution

**MPE (MIDI Polyphonic Expression)** cleverly solves this by dedicating one MIDI channel per voice:

```
Traditional MIDI:         MPE:
Channel 0: All voices     Channel 0: Manager (control data)
                         Channel 1: Voice 1
                         Channel 2: Voice 2
                         Channel 3: Voice 3
                         ... (up to 15 voices)
```

Each note plays on its own channel, so pitch bend, CC74 (timbre), and CC10 (pan) control that note independently.

### MPE Configuration

MPE controllers send an **RPN (Registered Parameter Number)** to configure the synth:

```cpp
// From: src/common/SurgeSynthesizer.cpp
void SurgeSynthesizer::onRPN(int channel, int lsbRPN, int msbRPN, int lsbValue, int msbValue)
{
    // MPE Configuration Message: RPN 6
    if (lsbRPN == 6 && msbRPN == 0)
    {
        // Channel 0 = lower zone, Channel 15 = upper zone
        mpeEnabled = msbValue > 0;
        mpeVoices = msbValue & 0xF;  // Number of member channels (1-15)

        // Set default pitch bend range if not already configured
        if (storage.mpePitchBendRange < 0.0f)
        {
            storage.mpePitchBendRange =
                Surge::Storage::getUserDefaultValue(&storage,
                    Surge::Storage::MPEPitchBendRange, 48);
        }

        mpeGlobalPitchBendRange = 0;
        return;
    }

    // Pitch Bend Range: RPN 0
    else if (lsbRPN == 0 && msbRPN == 0)
    {
        if (channel == 1)
            storage.mpePitchBendRange = msbValue;  // Member channels
        else if (channel == 0)
            mpeGlobalPitchBendRange = msbValue;    // Manager channel
    }
}
```

**MPE Zones**:
- **Lower Zone**: Manager on channel 0, members on channels 1-N
- **Upper Zone**: Manager on channel 15, members on channels 15-N (down)

Most single-MPE controllers use the lower zone. Multi-zone devices can split the keyboard, sending each half to a different synth on different zones.

### MPE Dimensions

MPE defines five dimensions of per-note control:

**1. Pitch Bend** (per-channel): Detunes the note
```cpp
// Applied in voice processing:
float pitch_bend_in_semitones = channelState[voice->state.channel].pitchBend *
                                storage.mpePitchBendRange / 8192.f;
```

**2. Pressure** (channel aftertouch): Applied pressure after note-on
```cpp
void SurgeSynthesizer::channelAftertouch(char channel, int value)
{
    float fval = (float)value / 127.f;
    channelState[channel].pressure = fval;

    // In MPE mode, pressure is per-note (per-channel)
    // In standard mode, it's a global modulation source
    if (!mpeEnabled || channel == 0)
    {
        for (int sc = 0; sc < n_scenes; sc++)
        {
            ((ControllerModulationSource *)storage.getPatch().scene[sc].modsources[ms_aftertouch])
                ->set_target(fval);
        }
    }
}
```

**3. Timbre** (CC74): Brightness/filter control
```cpp
// CC74 in MPE mode stores per-channel timbre
// Can be unipolar (0-1) or bipolar (-1 to 1) based on user preference
channelState[channel].timbre =
    mpeTimbreIsUnipolar ? (value / 127.f) : int7ToBipolarFloat(value);
```

**4. Pan** (CC10): Left-right position
```cpp
// Stored as bipolar (-1 to 1) with center at 64
channelState[channel].pan = int7ToBipolarFloat(value);

// Conversion from 7-bit MIDI:
float int7ToBipolarFloat(int x)
{
    if (x > 64)
        return (x - 64) * (1.f / 63.f);   // 64-127 → 0.0 to 1.0
    else if (x < 64)
        return (x - 64) * (1.f / 64.f);   // 0-63 → -1.0 to 0.0
    return 0.f;                           // 64 → 0.0 (center)
}
```

**5. Stroke/Initial Timbre** (CC70): Attack brightness (optional, not always used)

### MPE in the Voice

Each `SurgeVoice` maintains references to MIDI channel state:

```cpp
// From: src/common/dsp/SurgeVoiceState.h
struct SurgeVoiceState
{
    MidiKeyState *keyState;              // Per-key state (note number, velocity)
    MidiChannelState *mainChannelState;  // Manager channel (channel 0 in MPE)
    MidiChannelState *voiceChannelState; // Voice channel (1-15 in MPE)

    ControllerModulationSource mpePitchBend;  // Smoothed pitch bend
    float mpePitchBendRange;                  // Range in semitones
    bool mpeEnabled;                          // MPE mode active?
};
```

During voice processing, the voice reads its channel's state:

```cpp
// From: src/common/dsp/SurgeVoice.cpp (process_block)
if (state.mpeEnabled && state.voiceChannelState)
{
    // Apply per-note pitch bend
    float pb = state.voiceChannelState->pitchBend;
    state.mpePitchBend.set_target(pb / 8192.f);
    state.mpePitchBend.process_block();

    // Read timbre and pressure
    float timbre = state.voiceChannelState->timbre;
    float pressure = state.voiceChannelState->pressure;

    // These values can be routed to any parameter via modulation routing
}
```

**Smoothing**: MPE pitch bend uses a dedicated `ControllerModulationSource` to smooth rapid changes, preventing zipper noise while maintaining expressive response.

### MPE Voice Allocation

MPE challenges polyphony management because each voice needs its own channel:

```cpp
// From: src/common/SurgeSynthesizer.cpp
void SurgeSynthesizer::playVoice(int scene, char channel, char key, char velocity,
                                 char detune, int32_t host_noteid)
{
    // ... voice allocation ...

    int mpeMainChannel = getMpeMainChannel(channel, key);

    // Construct voice with MPE state
    new (nvoice) SurgeVoice(
        &storage, &storage.getPatch().scene[scene],
        storage.getPatch().scenedata[scene],
        storage.getPatch().scenedataOrig[scene],
        key, velocity, channel, scene, detune,
        &channelState[channel].keyState[key],        // Key state
        &channelState[mpeMainChannel],               // Manager channel
        &channelState[channel],                      // Voice channel (MPE)
        mpeEnabled, voiceCounter++, host_noteid,
        host_originating_key, host_originating_channel,
        0.f, 0.f
    );
}
```

**Channel Rotation**: When voices exceed available MPE channels, Surge intelligently reuses channels, preventing stuck notes and maintaining expressiveness.

### MPE and Scene Modes

MPE interacts with Surge's scene modes:

**Split Mode**: The split point still applies, but each scene can have independent MPE zones if the controller supports multi-zone MPE.

**Channel Split Mode**: With MPE enabled, you can route MPE channels to different scenes:
```cpp
// Channel 1-8 → Scene A
// Channel 9-15 → Scene B
```

This enables layering two different sounds with independent MPE control - for example, a soft pad on the left hand and a lead on the right.

### Compatible MPE Controllers

Surge works with all standard MPE controllers:

**Roli Seaboard**: Soft, continuous playing surface. Excels at pitch glides and pressure dynamics.

**LinnStrument**: Grid-based with per-note pitch bend via horizontal movement. Excellent for precise playing.

**Haken Continuum**: Continuous playing surface with extremely fine control resolution. Professional-grade expressiveness.

**Expressive E Osmose**: Acoustic-style keyboard with per-note control. Familiar form factor with MPE capabilities.

**Sensel Morph**: Pressure-sensitive pad with MPE firmware. Versatile controller for various playing styles.

**Madrona Labs Soundplane**: Wooden surface with capacitive sensing. Organic feel with MPE output.

## Note Expressions: Beyond MIDI

### The Next Evolution

While MPE extends MIDI's expressiveness, it still has limitations:
- Limited to 15 voices (14 + manager)
- Still uses 7-bit (0-127) or 14-bit resolution
- Requires complex channel management

Modern plugin formats (VST3 and CLAP) introduce **Note Expressions** - a native, high-resolution, polyphonic modulation system that transcends MIDI.

### VST3 Note Expressions

VST3 provides note-expressions via the `INoteExpressionController` interface:

```cpp
// VST3 defines note expression types:
enum NoteExpressionTypeIDs
{
    kVolumeTypeID = 0,          // Volume (gain)
    kPanTypeID,                 // Pan position
    kTuningTypeID,              // Fine tuning
    kVibratoTypeID,             // Vibrato amount
    kExpressionTypeID,          // Expression (dynamics)
    kBrightnessTypeID,          // Brightness (timbre)
    kTextTypeID,                // Text annotation (unused in Surge)
    kPhonemeTypeID              // Phoneme (unused in Surge)
};
```

These are transmitted with floating-point precision and sample-accurate timing, avoiding MIDI's quantization and latency issues.

### CLAP Note Expressions

CLAP (CLever Audio Plugin) offers an even richer expression system:

```cpp
// From: src/surge-xt/SurgeSynthProcessor.cpp (CLAP event handling)
enum clap_note_expression
{
    CLAP_NOTE_EXPRESSION_VOLUME,        // 0..4 (linear), amp = 20 * log10(x)
    CLAP_NOTE_EXPRESSION_PAN,           // -1..1 (left to right)
    CLAP_NOTE_EXPRESSION_TUNING,        // -120..120 semitones
    CLAP_NOTE_EXPRESSION_VIBRATO,       // 0..1
    CLAP_NOTE_EXPRESSION_EXPRESSION,    // 0..1 (dynamics)
    CLAP_NOTE_EXPRESSION_BRIGHTNESS,    // 0..1 (timbre)
    CLAP_NOTE_EXPRESSION_PRESSURE       // 0..1 (aftertouch)
};
```

CLAP expressions are processed in Surge's CLAP event handler:

```cpp
// From: src/surge-xt/SurgeSynthProcessor.cpp
if (pevt->header.type == CLAP_EVENT_NOTE_EXPRESSION)
{
    SurgeVoice::NoteExpressionType net = SurgeVoice::UNKNOWN;

    switch (pevt->expression_id)
    {
        case CLAP_NOTE_EXPRESSION_VOLUME:
            net = SurgeVoice::VOLUME;
            break;
        case CLAP_NOTE_EXPRESSION_PAN:
            net = SurgeVoice::PAN;
            break;
        case CLAP_NOTE_EXPRESSION_TUNING:
            net = SurgeVoice::PITCH;
            break;
        case CLAP_NOTE_EXPRESSION_BRIGHTNESS:
            net = SurgeVoice::TIMBRE;
            break;
        case CLAP_NOTE_EXPRESSION_PRESSURE:
            net = SurgeVoice::PRESSURE;
            break;
    }

    if (net != SurgeVoice::UNKNOWN)
        surge->setNoteExpression(net, pevt->note_id, pevt->key,
                                 pevt->channel, pevt->value);
}
```

### Note Expression Implementation

Surge maps note expressions to per-voice state:

```cpp
// From: src/common/dsp/SurgeVoice.h
class SurgeVoice
{
    enum NoteExpressionType
    {
        VOLUME,    // 0 < x <= 4, amp in dB = 20 * log10(x)
        PAN,       // 0..1 with 0.5 center
        PITCH,     // -120..120 semitones (fine tuning)
        TIMBRE,    // 0..1 (maps to MPE timbre parameter)
        PRESSURE,  // 0..1 (channel AT in MPE, poly AT otherwise)
        UNKNOWN
    };

    std::array<float, numNoteExpressionTypes> noteExpressions;

    void applyNoteExpression(NoteExpressionType net, float value)
    {
        if (net != UNKNOWN)
            noteExpressions[net] = value;
    }
};
```

During voice processing, these values are applied:

```cpp
// From: src/common/dsp/SurgeVoice.cpp (process_block)

// Volume expression (affects amplitude)
float volume_expression = noteExpressions[VOLUME];
if (volume_expression > 0.f)
{
    // Convert from linear (0-4) to dB: 20 * log10(x)
    float gain_db = 20.f * log10(volume_expression);
    float gain_linear = db_to_linear(gain_db);
    // Apply to voice output
}

// Pan expression (affects stereo placement)
float pan_expression = noteExpressions[PAN];  // 0..1, center = 0.5
// Apply to voice panning

// Pitch expression (fine tuning)
float pitch_expression = noteExpressions[PITCH];  // -120..120 semitones
// Add to voice pitch

// Timbre and pressure feed modulation matrix
```

### Advantages Over MPE

**Higher Resolution**: Floating-point values instead of 7-bit or 14-bit integers.

**No Channel Limits**: Unlimited polyphony without channel rotation.

**Lower Latency**: Direct plugin communication without MIDI serialization.

**Richer Semantics**: More expression types (volume, vibrato, text annotations).

**Host Integration**: DAWs can record, edit, and automate note expressions as naturally as MIDI notes.

### Hybrid Operation

Surge supports all three systems simultaneously:
- **MIDI/MPE**: For hardware controllers and DAW compatibility
- **VST3 Note Expressions**: For VST3 hosts that support them
- **CLAP Note Expressions**: For CLAP hosts with advanced expression routing

A note played via MIDI MPE can coexist with CLAP-expressed notes, each maintaining independent control over their sonic parameters.

## Practical MIDI Mapping Examples

### Example 1: Filter Cutoff via Mod Wheel

**Goal**: Control Scene A filter cutoff with mod wheel (CC1).

**Steps**:
1. Right-click Scene A Filter 1 Cutoff
2. Select "MIDI Learn Parameter"
3. Move mod wheel
4. Surge learns CC1 → Filter Cutoff

**Under the Hood**:
```cpp
storage.getPatch().scene[0].filterunit[0].cutoff.midictrl = 1;  // CC1
storage.getPatch().scene[0].filterunit[0].cutoff.midichan = 0;  // Channel 0
```

Now CC1 messages modulate cutoff directly, bypassing the modulation matrix.

### Example 2: Macro Control via Expression Pedal

**Goal**: Assign Macro 1 to expression pedal (CC11).

**Steps**:
1. Right-click Macro 1
2. Select "MIDI Learn Macro"
3. Move expression pedal
4. Macro 1 now responds to CC11

**Result**: Any parameters modulated by Macro 1 will respond to the expression pedal, enabling complex layered control with a single pedal movement.

### Example 3: MPE Performance Routing

**Goal**: Route MPE timbre to filter resonance.

**Steps**:
1. Enable MPE in Surge menu
2. Click Filter 1 Resonance → Modulation
3. Select "MPE Timbre" as source
4. Adjust amount slider

**Result**: Sliding your finger forward/back on an MPE controller (CC74) now morphs the filter resonance per note, enabling expressive timbral shifts.

### Example 4: Velocity to Filter and Amplitude

**Goal**: Harder key strikes open the filter and increase volume.

**Steps**:
1. Click Filter 1 Cutoff → Modulation → Velocity
2. Set amount to +40%
3. Click Voice Amplitude → Modulation → Velocity
4. Set amount to +60%

**Result**: Velocity dynamically shapes both timbre (filter) and loudness (amp) on a per-note basis, creating natural, acoustic-like response.

## MIDI Processing Performance

### Sample-Accurate Timing

Surge processes MIDI events at their precise sample positions:

```cpp
// Pseudocode for block processing with MIDI events:
void processBlock(int numSamples)
{
    int currentSample = 0;

    for (auto& event : midiEvents)
    {
        // Process audio up to this event
        synthesize(currentSample, event.sampleOffset);

        // Apply MIDI event
        handleMidiEvent(event);

        currentSample = event.sampleOffset;
    }

    // Process remaining samples
    synthesize(currentSample, numSamples);
}
```

This ensures rhythmically tight performance even at high polyphony.

### CC Smoothing Trade-offs

**LEGACY Mode**: Fast response, potential zipper noise on abrupt CC changes.

**SLOW Mode**: Smooth interpolation, slight latency in parameter response. Good for filter sweeps and slow modulations.

**FAST Mode**: Minimal smoothing, near-immediate response. Best for MIDI-controlled switches and fast modulations.

Users can select smoothing modes in Preferences → MIDI Settings.

## Summary

Surge XT implements a comprehensive MIDI system:

**Traditional MIDI**: Full support for note messages, CCs, pitch bend, aftertouch, program changes, and NRPN/RPN parameters.

**MPE**: Per-note pitch bend, pressure, timbre, and pan for expressive controllers, with intelligent channel management and zone support.

**Note Expressions**: High-resolution polyphonic control via VST3 and CLAP, transcending MIDI's limitations with floating-point precision and unlimited voice control.

**MIDI Learn**: Flexible mapping of any CC to any parameter, with soft takeover to prevent parameter jumps.

**Smoothing**: Configurable CC smoothing prevents zipper noise while maintaining responsive control.

From a simple mod wheel to a Continuum's continuous surface to CLAP's note-expression automation, Surge translates every nuance of performance into sonic expression.

**Next**: **[Chapter 32: SIMD Optimization](32-simd-optimization.md)** explores how Surge leverages CPU vector instructions to process multiple voices simultaneously, achieving the performance necessary for 64-voice polyphony with complex signal chains.
