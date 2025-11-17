# Chapter 3: The Synthesis Pipeline

## Introduction: From MIDI to Audio

When you press a key on your MIDI controller, what happens inside Surge XT? This chapter follows the complete signal path from MIDI note-on to final stereo output, examining every stage of Surge's synthesis pipeline.

Understanding this pipeline is essential for:
- **Performance Optimization**: Knowing where CPU cycles are spent
- **Architecture Comprehension**: Understanding how components interact
- **Extension Development**: Building new oscillators, filters, or effects
- **Debugging**: Tracing signal flow when things go wrong

The synthesis pipeline operates at two distinct rates:

**Control Rate** (~1.5kHz at 48kHz sample rate):
- Parameter updates
- Modulation calculations
- MIDI controller interpolation
- Scene mode evaluation

**Audio Rate** (Sample rate, typically 44.1-192kHz):
- Voice rendering
- Filter processing
- Effect processing
- Final output mixing

## The Main Processing Loop

### The `process()` Method

Every audio plugin host (DAW) calls the synthesizer's `process()` method repeatedly to generate audio. In Surge, this happens in fixed-size blocks of 32 samples (configurable at compile time).

```cpp
// From: src/common/SurgeSynthesizer.cpp
void SurgeSynthesizer::process()
{
    // At 48kHz, this is called ~1500 times per second
    // Each call generates 32 samples (~0.67ms of audio)

    if (halt_engine)
    {
        mech::clear_block<BLOCK_SIZE>(output[0]);
        mech::clear_block<BLOCK_SIZE>(output[1]);
        return;  // Silent output during patch loading
    }

    // Process inputs (upsample to 2x for oscillators)
    if (process_input)
    {
        halfbandIN.process_block_U2(input[0], input[1],
                                     storage.audio_in[0], storage.audio_in[1],
                                     BLOCK_SIZE_OS);
    }

    // Clear scene outputs
    mech::clear_block<BLOCK_SIZE_OS>(sceneout[0][0]);
    mech::clear_block<BLOCK_SIZE_OS>(sceneout[0][1]);
    mech::clear_block<BLOCK_SIZE_OS>(sceneout[1][0]);
    mech::clear_block<BLOCK_SIZE_OS>(sceneout[1][1]);

    // Process control rate updates (once per block)
    storage.modRoutingMutex.lock();
    processControl();

    // Process all active voices
    for (int s = 0; s < n_scenes; s++)
    {
        for (auto v : voices[s])
        {
            bool resume = v->process_block(...);
            if (!resume)
                freeVoice(v);  // Voice finished
        }
    }

    // Apply effects and mix to output
    // ... (detailed later in this chapter)

    storage.modRoutingMutex.unlock();
}
```

### The Processing Pipeline

The complete signal flow looks like this:

```
                    SURGE XT SYNTHESIS PIPELINE
                    ===========================

MIDI Input
    │
    ├──→ Note On/Off Events
    ├──→ MIDI Controllers
    ├──→ Pitch Bend
    └──→ Channel/Poly Aftertouch
              │
              ↓
    ┌─────────────────────┐
    │  processControl()   │  ← Control Rate (once per block)
    │  - Update params    │
    │  - Run modulators   │
    │  - MIDI smoothing   │
    └─────────────────────┘
              │
              ↓
    ┌─────────────────────────────────────────────┐
    │           Voice Processing                   │
    │  (Audio Rate, 2x Oversampled = 64 samples)  │
    │                                              │
    │  Scene A Voices        Scene B Voices       │
    │  ┌──────────┐          ┌──────────┐        │
    │  │ Voice 1  │          │ Voice 1  │        │
    │  │ Voice 2  │          │ Voice 2  │        │
    │  │   ...    │          │   ...    │        │
    │  │ Voice N  │          │ Voice N  │        │
    │  └──────────┘          └──────────┘        │
    │       │                     │               │
    │       ↓                     ↓               │
    │  QuadFilter             QuadFilter          │
    │  Processing             Processing          │
    │       │                     │               │
    │       ↓                     ↓               │
    │  [Hardclip]            [Hardclip]          │
    │       │                     │               │
    │       ↓                     ↓               │
    │  Downsample 2x         Downsample 2x       │
    │       │                     │               │
    │       ↓                     ↓               │
    │  Scene Lowcut          Scene Lowcut         │
    └───────┼─────────────────────┼───────────────┘
            │                     │
            ↓                     ↓
    ┌──────────────┐      ┌──────────────┐
    │  Scene A FX  │      │  Scene B FX  │
    │  (Insert)    │      │  (Insert)    │
    └──────┬───────┘      └──────┬───────┘
           │                     │
           └──────────┬──────────┘
                      │
                      ↓
              ┌───────────────┐
              │   Scene Mix   │  ← Mix both scenes
              └───────┬───────┘
                      │
          ┌───────────┼───────────┐
          │           │           │
          ↓           ↓           ↓
    ┌─────────┐ ┌─────────┐ ┌─────────┐
    │ Send 1  │ │ Send 2  │ │ Send 3/4│
    │ (Delay) │ │(Reverb) │ │  (FX)   │
    └────┬────┘ └────┬────┘ └────┬────┘
         │           │           │
         └───────────┼───────────┘
                     │
                     ↓
            ┌────────────────┐
            │   Global FX    │
            │ (Master Chain) │
            └────────┬───────┘
                     │
                     ↓
            ┌────────────────┐
            │ Master Volume  │
            │   & Limiter    │
            └────────┬───────┘
                     │
                     ↓
              Stereo Output
```

### Block Size and Timing

```cpp
// From: src/common/globals.h
const int BLOCK_SIZE = 32;              // Samples per block
const int OSC_OVERSAMPLING = 2;         // 2x oversampling for oscillators
const int BLOCK_SIZE_OS = 64;           // Oversampled block size
const int BLOCK_SIZE_QUAD = 8;          // SIMD quads (4 samples each)
```

At 48kHz sample rate:
- **Block duration**: 32 samples ÷ 48,000 Hz = **0.67 milliseconds**
- **Control rate**: 48,000 ÷ 32 = **1,500 Hz** (modulation updates)
- **Oversampled rate**: 96 kHz (for anti-aliasing oscillators)

This means Surge calls `process()` approximately **1,500 times per second**, generating 32 samples each time.

## Control Rate Processing

Before generating audio, Surge updates all control-rate parameters once per block via `processControl()`.

### The `processControl()` Method

```cpp
// From: src/common/SurgeSynthesizer.cpp
void SurgeSynthesizer::processControl()
{
    // Load any enqueued patch
    processEnqueuedPatchIfNeeded();

    // Perform any queued wavetable loads
    storage.perform_queued_wtloads();

    // Determine which scenes are active
    int sm = storage.getPatch().scenemode.val.i;
    bool playA = (sm == sm_split) || (sm == sm_dual) ||
                 (sm == sm_chsplit) ||
                 (storage.getPatch().scene_active.val.i == 0);
    bool playB = (sm == sm_split) || (sm == sm_dual) ||
                 (sm == sm_chsplit) ||
                 (storage.getPatch().scene_active.val.i == 1);

    // Update tempo and song position
    storage.songpos = time_data.ppqPos;
    storage.temposyncratio = time_data.tempo / 120.f;
    storage.temposyncratio_inv = 1.f / storage.temposyncratio;

    // Interpolate MIDI controllers smoothly
    for (int i = 0; i < num_controlinterpolators; i++)
    {
        if (mControlInterpolatorUsed[i])
        {
            ControllerModulationSource *mc = &mControlInterpolator[i];
            bool cont = mc->process_block_until_close(0.001f);
            int id = mc->id;
            storage.getPatch().param_ptr[id]->set_value_f01(mc->get_output(0));
            if (!cont)
                mControlInterpolatorUsed[i] = false;
        }
    }

    // Prepare modulation sources
    prepareModsourceDoProcess((playA ? 1 : 0) | (playB ? 2 : 0));

    // Process all modulators for active scenes
    for (int s = 0; s < n_scenes; s++)
    {
        if ((s == 0 && playA) || (s == 1 && playB))
        {
            // Voice LFOs are per-voice, but scene LFOs run here
            for (int i = 0; i < n_lfos_scene; i++)
            {
                storage.getPatch().scene[s].modsources[ms_slfo1 + i]
                    ->process_block();
            }
        }
    }

    // Apply global modulations
    int n = storage.getPatch().modulation_global.size();
    for (int i = 0; i < n; i++)
    {
        int src_id = storage.getPatch().modulation_global[i].source_id;
        int src_index = storage.getPatch().modulation_global[i].source_index;
        int dst_id = storage.getPatch().modulation_global[i].destination_id;
        float depth = storage.getPatch().modulation_global[i].depth;
        int source_scene = storage.getPatch().modulation_global[i].source_scene;

        storage.getPatch().globaldata[dst_id].f +=
            depth * storage.getPatch().scene[source_scene]
                        .modsources[src_id]->get_output(src_index) *
            (1 - storage.getPatch().modulation_global[i].muted);
    }

    // Load effects if needed
    if (load_fx_needed)
        loadFx(false, false);
}
```

### MIDI Controller Smoothing

To avoid zipper noise and clicks, Surge smoothly interpolates MIDI controller changes:

```cpp
// When a MIDI CC is received:
ControllerModulationSource *mc = AddControlInterpolator(cc_num, alreadyExists);
mc->set_target(new_value);

// Then in processControl(), it smooths toward the target:
mc->process_block_until_close(0.001f);  // Approach within 0.1%
```

This creates smooth parameter sweeps even when MIDI data arrives at irregular intervals.

## Voice Management

Voice management is one of the most complex aspects of any polyphonic synthesizer. Surge must:
1. Allocate voices when notes are pressed
2. Steal voices when the polyphony limit is reached
3. Track voice lifecycle (attack → sustain → release)
4. Free voices when they finish their release phase

### Voice Allocation

Each scene maintains its own voice pool:

```cpp
// From: src/common/SurgeSynthesizer.h
std::array<std::array<SurgeVoice, MAX_VOICES>, 2> voices_array;
unsigned int voices_usedby[2][MAX_VOICES];  // 0=unused, 1=scene A, 2=scene B

std::list<SurgeVoice *> voices[n_scenes];  // Active voices per scene
```

**Why Two Arrays?**
- `voices_array`: Pre-allocated memory (no runtime allocation)
- `voices`: Active voice tracking (efficient iteration)

### The Voice Lifecycle

```
  Note On          Gate Open       Gate Closed      Voice Silent
     │                  │                │                 │
     ↓                  ↓                ↓                 ↓
┌─────────┐      ┌──────────┐     ┌──────────┐      ┌─────────┐
│ ATTACK  │─────→│ SUSTAIN  │────→│ RELEASE  │─────→│  FREE   │
└─────────┘      └──────────┘     └──────────┘      └─────────┘
     │                                    │
     │                                    │
     └────────── voice->age ──────────────┘
                                          │
                                          └─── voice->age_release
```

State tracking in `SurgeVoiceState`:

```cpp
// From: src/common/dsp/SurgeVoiceState.h
struct SurgeVoiceState
{
    bool gate;              // True during attack/sustain, false during release
    bool keep_playing;      // Force voice to continue (used by some modes)
    bool uberrelease;       // Ultra-fast release for voice stealing

    int key, velocity, channel, scene_id;
    float pitch, fvel, detune;

    // State for polyphonic/MPE control
    MidiKeyState *keyState;
    MidiChannelState *mainChannelState;
    MidiChannelState *voiceChannelState;

    // Portamento state
    float portasrc_key, portaphase;
    bool porta_doretrigger;

    // MPE support
    ControllerModulationSource mpePitchBend;
    float mpePitchBendRange;
    bool mpeEnabled;

    int64_t voiceOrderAtCreate;  // For voice stealing algorithms
};
```

### Getting an Unused Voice

```cpp
// From: src/common/SurgeSynthesizer.cpp
SurgeVoice *SurgeSynthesizer::getUnusedVoice(int scene)
{
    for (int i = 0; i < MAX_VOICES; i++)
    {
        if (!voices_usedby[scene][i])
        {
            voices_usedby[scene][i] = scene + 1;  // Mark as used
            return &voices_array[scene][i];
        }
    }
    return nullptr;  // All voices in use!
}
```

### Voice Stealing: When Polyphony is Exceeded

When all voices are in use and a new note arrives, Surge must **steal** a voice:

```cpp
// From: src/common/SurgeSynthesizer.cpp
void SurgeSynthesizer::softkillVoice(int s)
{
    list<SurgeVoice *>::iterator iter, max_playing, max_released;
    int max_age = -1, max_age_release = -1;

    iter = voices[s].begin();

    while (iter != voices[s].end())
    {
        SurgeVoice *v = *iter;

        // Prefer stealing released voices
        if (v->state.gate)  // Still playing (attack/sustain)
        {
            if (v->age > max_age)
            {
                max_age = v->age;
                max_playing = iter;
            }
        }
        else if (!v->state.uberrelease)  // In release
        {
            if (v->age_release > max_age_release)
            {
                max_age_release = v->age_release;
                max_released = iter;
            }
        }
        iter++;
    }

    // Steal the oldest released voice, or oldest playing voice
    if (max_age_release >= 0)
        (*max_released)->uber_release();  // Force immediate fadeout
    else if (max_age >= 0)
        (*max_playing)->uber_release();
}
```

**Voice Stealing Priority:**
1. **Released voices**: Steal the oldest voice in release phase
2. **Playing voices**: If no released voices, steal the oldest playing voice
3. **Uber-release**: Fade out quickly (10ms) to avoid clicks

### Enforcing Polyphony Limits

```cpp
// From: src/common/SurgeSynthesizer.cpp
void SurgeSynthesizer::enforcePolyphonyLimit(int s, int margin)
{
    int paddedPoly = std::min(
        (storage.getPatch().polylimit.val.i + margin),
        MAX_VOICES - 1
    );

    if (voices[s].size() > paddedPoly)
    {
        int excess_voices = max(0, (int)voices[s].size() - paddedPoly);
        auto iter = voices[s].begin();

        while (iter != voices[s].end())
        {
            if (excess_voices < 1)
                break;

            SurgeVoice *v = *iter;
            if (v->state.uberrelease)  // Already being killed
            {
                excess_voices--;
                freeVoice(v);
                iter = voices[s].erase(iter);
            }
            else
                iter++;
        }
    }
}
```

The `margin` parameter (typically 3) provides headroom to avoid aggressive stealing on every note.

### Playing a New Voice

```cpp
// From: src/common/SurgeSynthesizer.cpp (simplified)
void SurgeSynthesizer::playVoice(int scene, char channel, char key,
                                  char velocity, char detune,
                                  int32_t host_noteid, ...)
{
    // Trigger scene LFOs if this is the first note
    if (getNonReleasedVoices(scene) == 0)
    {
        for (int l = 0; l < n_lfos_scene; l++)
        {
            storage.getPatch().scene[scene].modsources[ms_slfo1 + l]->attack();
        }
    }

    // Trigger random/alternate modulators
    for (int i = ms_random_bipolar; i <= ms_alternate_unipolar; ++i)
    {
        storage.getPatch().scene[scene].modsources[i]->attack();
    }

    // Voice stealing if needed
    int excessVoices = max(0, (int)getNonUltrareleaseVoices(scene) -
                           storage.getPatch().polylimit.val.i + 1);
    for (int i = 0; i < excessVoices; i++)
    {
        softkillVoice(scene);
    }
    enforcePolyphonyLimit(scene, 3);

    // Get an unused voice
    SurgeVoice *nvoice = getUnusedVoice(scene);

    if (nvoice)
    {
        // Reconstruct the voice (calls destructor then constructor)
        nvoice->~SurgeVoice();
        voices[scene].push_back(nvoice);

        new (nvoice) SurgeVoice(
            &storage,
            &storage.getPatch().scene[scene],
            storage.getPatch().scenedata[scene],
            storage.getPatch().scenedataOrig[scene],
            key, velocity, channel, scene, detune,
            &channelState[channel].keyState[key],
            &channelState[mpeMainChannel],
            &channelState[channel],
            mpeEnabled,
            voiceCounter++,  // Unique voice ID
            host_noteid,
            host_originating_key,
            host_originating_channel,
            0.f, 0.f  // AEG/FEG start levels
        );
    }
}
```

### Freeing a Voice

```cpp
// From: src/common/SurgeSynthesizer.cpp
void SurgeSynthesizer::freeVoice(SurgeVoice *v)
{
    // Notify host that note has ended (for MPE, etc.)
    if (v->host_note_id >= 0)
    {
        bool used_away = false;
        // Check if another voice still uses this note ID (unison, etc.)
        for (int s = 0; s < n_scenes; ++s)
        {
            for (auto vo : voices[s])
            {
                if (vo != v && vo->host_note_id == v->host_note_id)
                    used_away = true;
            }
        }
        if (!used_away)
            notifyEndedNote(v->host_note_id, v->originating_host_key,
                           v->originating_host_channel);
    }

    // Find the voice in the array
    int foundScene{-1}, foundIndex{-1};
    for (int i = 0; i < MAX_VOICES; i++)
    {
        if (voices_usedby[0][i] && (v == &voices_array[0][i]))
        {
            foundScene = 0;
            foundIndex = i;
            voices_usedby[0][i] = 0;  // Mark as free
        }
        if (voices_usedby[1][i] && (v == &voices_array[1][i]))
        {
            foundScene = 1;
            foundIndex = i;
            voices_usedby[1][i] = 0;
        }
    }

    // Free any allocated resources
    v->freeAllocatedElements();

    // Call destructor and reconstruct
    v->~SurgeVoice();
    v = new (&voices_array[foundScene][foundIndex]) SurgeVoice();
}
```

## Scene Processing

Surge's dual-scene architecture allows two complete synthesizers to run simultaneously. Each scene can have different oscillators, filters, envelopes, and modulation routings.

### Scene Modes

```cpp
// From: src/common/dsp/SurgeStorage.h
enum scene_mode
{
    sm_single = 0,   // Only Scene A is active
    sm_split,        // Key split: notes below splitpoint → A, above → B
    sm_dual,         // Both scenes play all notes (layer)
    sm_chsplit,      // MIDI channel split: channels 1-8 → A, 9-16 → B

    n_scene_modes,
};
```

**Scene Mode Routing:**

```
sm_single (Scene A only):
    MIDI → Scene A → Output

sm_split (Key split at C3):
    MIDI < C3 → Scene A ┐
    MIDI ≥ C3 → Scene B ┼→ Mix → Output
                        ┘

sm_dual (Layer):
    MIDI → Scene A ┐
    MIDI → Scene B ┼→ Mix → Output
                   ┘

sm_chsplit (Channel split):
    MIDI Ch 1-8  → Scene A ┐
    MIDI Ch 9-16 → Scene B ┼→ Mix → Output
                           ┘
```

### Per-Scene Processing

Each scene processes its voices independently at 2x oversampling:

```cpp
// From: src/common/SurgeSynthesizer.cpp
for (int s = 0; s < n_scenes; s++)
{
    // Process all voices in this scene
    iter = voices[s].begin();
    while (iter != voices[s].end())
    {
        SurgeVoice *v = *iter;

        // Process one block (64 samples at 2x oversampling)
        bool resume = v->process_block(FBQ[s][FBentry[s] >> 2],
                                       FBentry[s] & 3);
        FBentry[s]++;

        if (!resume)  // Voice finished
        {
            freeVoice(v);
            iter = voices[s].erase(iter);
        }
        else
            iter++;
    }

    // Unlock modulation routing for QuadFilterChain processing
    storage.modRoutingMutex.unlock();

    // Get filter function pointers for this scene
    using sst::filters::FilterType, sst::filters::FilterSubType;
    fbq_global g;

    g.FU1ptr = sst::filters::GetQFPtrFilterUnit(
        static_cast<FilterType>(storage.getPatch().scene[s].filterunit[0].type.val.i),
        static_cast<FilterSubType>(storage.getPatch().scene[s].filterunit[0].subtype.val.i)
    );

    g.FU2ptr = sst::filters::GetQFPtrFilterUnit(
        static_cast<FilterType>(storage.getPatch().scene[s].filterunit[1].type.val.i),
        static_cast<FilterSubType>(storage.getPatch().scene[s].filterunit[1].subtype.val.i)
    );

    g.WSptr = sst::waveshapers::GetQuadWaveshaper(
        static_cast<sst::waveshapers::WaveshaperType>(
            storage.getPatch().scene[s].wsunit.type.val.i)
    );

    // Get the quad filter processing function
    FBQFPtr ProcessQuadFB = GetFBQPointer(
        storage.getPatch().scene[s].filterblock_configuration.val.i,
        g.FU1ptr != 0, g.WSptr != 0, g.FU2ptr != 0
    );

    // Process filters for all voices (4 at a time in SIMD)
    for (int e = 0; e < FBentry[s]; e += 4)
    {
        ProcessQuadFB(FBQ[s][e >> 2], g, sceneout[s][0], sceneout[s][1]);
    }

    // Save filter state back to voices
    iter = voices[s].begin();
    while (iter != voices[s].end())
    {
        SurgeVoice *v = *iter;
        v->GetQFB();  // Save filter registers
        iter++;
    }

    storage.modRoutingMutex.lock();
}
```

### Quad Filter Processing

Surge processes filters **4 voices at a time** using SIMD:

```
  Voice 1 ┐
  Voice 2 ├─→ QuadFilterChain ──→ SIMD Filter Processing ──→ Scene Output
  Voice 3 │   (4 voices × 2     (SSE2: 4 samples parallel)
  Voice 4 ┘    filters)
```

This is dramatically more efficient than processing each voice individually.

### Scene Output Processing

After voice and filter processing, each scene's output goes through:

```cpp
// 1. Hard clipping (if enabled)
if (play_scene[s])
{
    switch (storage.sceneHardclipMode[s])
    {
    case SurgeStorage::HARDCLIP_TO_18DBFS:
        sdsp::hardclip_block8<BLOCK_SIZE_OS>(sceneout[s][0]);
        sdsp::hardclip_block8<BLOCK_SIZE_OS>(sceneout[s][1]);
        break;
    case SurgeStorage::HARDCLIP_TO_0DBFS:
        sdsp::hardclip_block<BLOCK_SIZE_OS>(sceneout[s][0]);
        sdsp::hardclip_block<BLOCK_SIZE_OS>(sceneout[s][1]);
        break;
    }

    // 2. Downsample from 2x to 1x
    halfbandA.process_block_D2(sceneout[s][0], sceneout[s][1], BLOCK_SIZE_OS);
}

// 3. Scene lowcut filter (high-pass)
if (!storage.getPatch().scene[s].lowcut.deactivated)
{
    auto freq = storage.getPatch().scenedata[s][
        storage.getPatch().scene[s].lowcut.param_id_in_scene].f;
    auto slope = storage.getPatch().scene[s].lowcut.deform_type;

    for (int i = 0; i <= slope; i++)
    {
        hpA[i].coeff_HP(hpA[i].calc_omega(freq / 12.0), 0.4);
        hpA[i].process_block(sceneout[s][0], sceneout[s][1]);
    }
}
```

## Effect Chain Processing

Surge has a sophisticated **16-slot effect system** organized into 4 chains:

```
┌──────────────────────────────────────────────────────┐
│                  EFFECT CHAINS                       │
│                                                      │
│  Scene A Insert FX    Scene B Insert FX             │
│  ┌────┬────┬────┬────┐ ┌────┬────┬────┬────┐       │
│  │ A1 │ A2 │ A3 │ A4 │ │ B1 │ B2 │ B3 │ B4 │       │
│  └────┴────┴────┴────┘ └────┴────┴────┴────┘       │
│         │                     │                     │
│         └──────────┬──────────┘                     │
│                    │                                │
│         ┌──────────┴──────────┐                    │
│         │                     │                     │
│         ↓                     ↓                     │
│  Send FX Chains         Global FX Chain            │
│  ┌────┬────┬────┬────┐ ┌────┬────┬────┬────┐      │
│  │ S1 │ S2 │ S3 │ S4 │ │ G1 │ G2 │ G3 │ G4 │      │
│  └────┴────┴────┴────┘ └────┴────┴────┴────┘      │
│    ↓    ↓    ↓    ↓         ↓                      │
│    └────┴────┴────┴─────────┘                      │
│                  │                                  │
│                  ↓                                  │
│              Output                                 │
└──────────────────────────────────────────────────────┘
```

### Effect Slot Organization

```cpp
// From: src/common/dsp/SurgeStorage.h
enum fx_type
{
    fxslot_ains1 = 0,   // Scene A Insert 1
    fxslot_ains2,       // Scene A Insert 2
    fxslot_ains3,       // Scene A Insert 3
    fxslot_ains4,       // Scene A Insert 4

    fxslot_bins1,       // Scene B Insert 1
    fxslot_bins2,       // Scene B Insert 2
    fxslot_bins3,       // Scene B Insert 3
    fxslot_bins4,       // Scene B Insert 4

    fxslot_send1,       // Send FX 1
    fxslot_send2,       // Send FX 2
    fxslot_send3,       // Send FX 3
    fxslot_send4,       // Send FX 4

    fxslot_global1,     // Global FX 1 (Master)
    fxslot_global2,     // Global FX 2
    fxslot_global3,     // Global FX 3
    fxslot_global4,     // Global FX 4

    n_fx_slots = 16
};
```

### Insert Effects (Per-Scene)

Insert effects process **only their scene's output** in series:

```cpp
// From: src/common/SurgeSynthesizer.cpp
// Apply Scene A insert effects
for (auto v : {fxslot_ains1, fxslot_ains2, fxslot_ains3, fxslot_ains4})
{
    if (fx[v] && !(storage.getPatch().fx_disable.val.i & (1 << v)))
    {
        sc_state[0] = fx[v]->process_ringout(
            sceneout[0][0],  // Left input/output
            sceneout[0][1],  // Right input/output
            sc_state[0]      // Is scene active?
        );
    }
}

// Apply Scene B insert effects
for (auto v : {fxslot_bins1, fxslot_bins2, fxslot_bins3, fxslot_bins4})
{
    if (fx[v] && !(storage.getPatch().fx_disable.val.i & (1 << v)))
    {
        sc_state[1] = fx[v]->process_ringout(
            sceneout[1][0], sceneout[1][1], sc_state[1]
        );
    }
}
```

**`process_ringout()`**: Returns `true` if the effect is still producing sound (e.g., reverb tail), `false` when silent.

### Mixing Scenes

After insert effects, the scenes are summed:

```cpp
// Sum both scenes to main output
mech::copy_from_to<BLOCK_SIZE>(sceneout[0][0], output[0]);
mech::copy_from_to<BLOCK_SIZE>(sceneout[0][1], output[1]);
mech::accumulate_from_to<BLOCK_SIZE>(sceneout[1][0], output[0]);
mech::accumulate_from_to<BLOCK_SIZE>(sceneout[1][1], output[1]);
```

### Send Effects (Send/Return)

Send effects use a **send/return** topology:

```cpp
// For each send effect (typically reverb, delay, chorus, etc.)
for (auto si : sendToIndex)  // Send 1-4
{
    auto slot = si[0];  // Effect slot
    auto idx = si[1];   // Send index

    if (fx[slot] && !(storage.getPatch().fx_disable.val.i & (1 << slot)))
    {
        // Mix scene A with send level into send buffer
        send[idx][0].MAC_2_blocks_to(
            sceneout[0][0], sceneout[0][1],  // Scene A L/R
            fxsendout[idx][0], fxsendout[idx][1],  // Send buffer L/R
            BLOCK_SIZE_QUAD
        );

        // Mix scene B with send level into send buffer
        send[idx][1].MAC_2_blocks_to(
            sceneout[1][0], sceneout[1][1],  // Scene B L/R
            fxsendout[idx][0], fxsendout[idx][1],  // Send buffer L/R
            BLOCK_SIZE_QUAD
        );

        // Process the send buffer through the effect
        sendused[idx] = fx[slot]->process_ringout(
            fxsendout[idx][0], fxsendout[idx][1],
            sc_state[0] || sc_state[1]
        );

        // Mix effect output back to main output with return level
        FX[idx].MAC_2_blocks_to(
            fxsendout[idx][0], fxsendout[idx][1],  // Effect output
            output[0], output[1],  // Main output
            BLOCK_SIZE_QUAD
        );
    }
}
```

**Send/Return Flow:**

```
Scene A ──┬──→ Send Level ──┬──→ Effect ──┬──→ Return Level ──→ Output
          │                  │             │
Scene B ──┘                  │             │
                             │             │
                      (dry signal continues to output)
```

### Global Effects (Master Chain)

Global effects process the **final mixed output** serially:

```cpp
// Apply global effects (master chain)
bool glob = sc_state[0] || sc_state[1];
for (int i = 0; i < n_send_slots; ++i)
    glob = glob || sendused[i];

for (auto v : {fxslot_global1, fxslot_global2, fxslot_global3, fxslot_global4})
{
    if (fx[v] && !(storage.getPatch().fx_disable.val.i & (1 << v)))
    {
        glob = fx[v]->process_ringout(
            output[0], output[1],  // Process main output in-place
            glob
        );
    }
}
```

Typical global chain:
- **Global 1**: EQ or multiband compression
- **Global 2**: Stereo enhancement
- **Global 3**: Limiter or maximizer
- **Global 4**: Final color/saturation

### Effect Bypass Modes

```cpp
enum fx_bypass
{
    fxb_all_fx = 0,     // All effects active (normal)
    fxb_no_sends,       // Bypass send effects only
    fxb_no_fx,          // Bypass all effects
    fxb_scene_fx_only,  // Only scene insert effects
};
```

This allows quick A/B comparison and CPU saving.

## Output Stage

The final stage applies master volume, optional limiting, and routes to the DAW.

### Master Volume

```cpp
// Set target smoothly to avoid clicks
amp.set_target_smoothed(
    storage.db_to_linear(storage.getPatch().globaldata[
        storage.getPatch().volume.id].f)
);

// Apply to output
amp.multiply_2_blocks(output[0], output[1], BLOCK_SIZE_QUAD);
```

The `set_target_smoothed()` uses linear interpolation across the block to smoothly ramp volume changes.

### Fade for Patch Changes

```cpp
amp_mute.set_target(mfade);  // Fade to 0 during patch load
amp_mute.multiply_2_blocks(output[0], output[1], BLOCK_SIZE_QUAD);
```

When loading a new patch, `masterfade` ramps from 1.0 → 0.0 over several blocks to avoid clicks.

### Hard Clipping (Output Protection)

```cpp
switch (storage.hardclipMode)
{
case SurgeStorage::HARDCLIP_TO_18DBFS:
    sdsp::hardclip_block8<BLOCK_SIZE>(output[0]);  // ±8.0 (~18dBFS)
    sdsp::hardclip_block8<BLOCK_SIZE>(output[1]);
    break;

case SurgeStorage::HARDCLIP_TO_0DBFS:
    sdsp::hardclip_block<BLOCK_SIZE>(output[0]);   // ±1.0 (0dBFS)
    sdsp::hardclip_block<BLOCK_SIZE>(output[1]);
    break;

case SurgeStorage::BYPASS_HARDCLIP:
    // No limiting (can exceed 0dBFS)
    break;
}
```

**Why 18dBFS?**
- Provides headroom for inter-sample peaks
- Prevents DAC clipping on some hardware
- Allows "hot" mixing into effects

### VU Metering

```cpp
// VU falloff
float a = storage.vu_falloff;
vu_peak[0] = min(2.f, a * vu_peak[0]);
vu_peak[1] = min(2.f, a * vu_peak[1]);

// Update with current block peaks
vu_peak[0] = max(vu_peak[0], mech::blockAbsMax<BLOCK_SIZE>(output[0]));
vu_peak[1] = max(vu_peak[1], mech::blockAbsMax<BLOCK_SIZE>(output[1]));
```

The VU meters decay exponentially between updates, creating the characteristic ballistic behavior.

### CPU Usage Monitoring

```cpp
auto process_start = std::chrono::high_resolution_clock::now();

// ... entire process() ...

auto process_end = std::chrono::high_resolution_clock::now();
auto duration_usec = std::chrono::duration_cast<std::chrono::microseconds>(
    process_end - process_start
);

auto max_duration_usec = BLOCK_SIZE * storage.dsamplerate_inv * 1000000;
float ratio = duration_usec.count() / max_duration_usec;

// Exponential moving average
float c = cpu_level.load();
int window = max_duration_usec;
auto smoothed_ratio = (c * (window - 1) + ratio) / window;
c = c * storage.cpu_falloff;
cpu_level.store(max(c, smoothed_ratio));
```

This tracks **what percentage of available time** is used for processing. Values approaching 100% indicate potential dropouts.

## Summary: The Complete Pipeline

Let's trace a single MIDI note through the entire pipeline:

```
1. MIDI Note On (C4, velocity 100)
       ↓
2. playNote() called
       ↓
3. Voice Allocation
   - Check polyphony limit (16 voices)
   - getUnusedVoice(scene)
   - Construct new SurgeVoice
       ↓
4. processControl() [once per 32 samples]
   - Update tempo, song position
   - Run Scene LFOs
   - Interpolate MIDI controllers
   - Apply global modulations
       ↓
5. Voice Processing [64 samples, 2x oversampled]
   - Generate oscillator waveforms (Osc1 + Osc2 + Osc3)
   - Mix oscillators with ring modulation
   - Apply filter envelopes
   - Process through QuadFilterChain (4 voices in parallel)
       ↓
6. Scene Processing
   - Hard clip (if enabled)
   - Downsample 2x → 1x (64 samples → 32 samples)
   - Scene lowcut filter
   - Scene insert effects (A1 → A2 → A3 → A4)
       ↓
7. Scene Mixing
   - Sum Scene A + Scene B → output[]
       ↓
8. Send Effects
   - Send to reverb (Send 1)
   - Send to delay (Send 2)
   - Mix returns back to output[]
       ↓
9. Global Effects
   - EQ (Global 1)
   - Limiter (Global 2)
       ↓
10. Output Stage
    - Master volume
    - Hard clip to 0dBFS
    - Update VU meters
    - Calculate CPU usage
        ↓
11. Stereo Output [32 samples]
    - Sent to DAW
```

**Timing at 48kHz:**
- **processControl()**: 0.67ms (once per block)
- **Voice processing**: ~0.1-0.5ms (varies with voice count)
- **Effect processing**: ~0.05-0.2ms (varies with effect count)
- **Total**: Typically 5-30% CPU usage

## Performance Considerations

### Memory Layout

All audio buffers are **16-byte aligned** for SIMD:

```cpp
float output alignas(16)[N_OUTPUTS][BLOCK_SIZE];
float sceneout alignas(16)[n_scenes][N_OUTPUTS][BLOCK_SIZE_OS];
```

Misaligned access causes 50% performance loss or crashes.

### Voice Pooling

Pre-allocating 64 voices avoids real-time memory allocation:

```cpp
std::array<std::array<SurgeVoice, MAX_VOICES>, 2> voices_array;
```

Voices are constructed/destructed in-place using placement new.

### Lock-Free where Possible

```cpp
std::atomic<unsigned int> processRunning{0};
std::atomic<bool> halt_engine;
```

Atomics minimize mutex contention between audio and UI threads.

### The Modulation Routing Mutex

One critical mutex protects modulation routing:

```cpp
storage.modRoutingMutex.lock();
processControl();
// ... voice processing ...
storage.modRoutingMutex.unlock();
```

This ensures modulation changes from the UI thread don't corrupt the audio thread.

## Debugging the Pipeline

### Voice Debugging

```cpp
// Print active voices
for (int s = 0; s < n_scenes; s++)
{
    std::cout << "Scene " << s << ": " << voices[s].size() << " voices\n";
    for (auto v : voices[s])
    {
        std::cout << "  Voice " << v->host_note_id
                  << " key=" << (int)v->state.key
                  << " gate=" << v->state.gate
                  << " age=" << v->age << "\n";
    }
}
```

### Effect Chain Debugging

```cpp
// Print effect routing
for (int i = 0; i < n_fx_slots; i++)
{
    if (fx[i])
    {
        std::cout << "FX " << i << ": "
                  << fx[i]->get_effectname() << "\n";
    }
}
```

### CPU Profiling Hooks

```cpp
auto start = std::chrono::high_resolution_clock::now();
// ... process section ...
auto end = std::chrono::high_resolution_clock::now();
auto us = std::chrono::duration_cast<std::chrono::microseconds>(end - start);
std::cout << "Section took " << us.count() << "µs\n";
```

## Conclusion

The synthesis pipeline is the beating heart of Surge XT. Understanding its flow—from `process()` through voice management, scene processing, effects, and output—is essential for:

- **Optimizing Performance**: Knowing where CPU time goes
- **Extending Functionality**: Adding oscillators, filters, effects
- **Debugging Issues**: Tracing signal flow
- **Sound Design**: Understanding the architecture's capabilities

**Key Takeaways:**

1. **Block-based processing** (32 samples) balances latency and efficiency
2. **Dual-scene architecture** enables complex layering and splits
3. **Voice stealing** ensures graceful polyphony limiting
4. **QuadFilterChain** processes 4 voices in parallel with SIMD
5. **Effect chains** provide flexible routing (insert, send, global)
6. **Oversampling** at oscillators reduces aliasing
7. **Lock-free design** minimizes thread contention

In the next chapter, we'll dive deep into **oscillator architecture**, exploring how Surge generates its rich variety of waveforms using the infrastructure we've examined here.

---

**Further Reading:**
- Chapter 1: Architecture Overview
- Chapter 5: Oscillators Overview
- Chapter 12: Effects Architecture
- Chapter 18: Modulation Architecture

**Source Files Referenced:**
- `/home/user/surge/src/common/SurgeSynthesizer.cpp` - Main processing loop
- `/home/user/surge/src/common/SurgeSynthesizer.h` - Synthesizer class
- `/home/user/surge/src/common/dsp/SurgeVoice.h` - Voice class
- `/home/user/surge/src/common/dsp/SurgeVoiceState.h` - Voice state
- `/home/user/surge/src/common/globals.h` - Global constants
