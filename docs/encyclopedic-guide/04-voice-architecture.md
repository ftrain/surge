# Chapter 4: Voice Architecture

## The Heart of Polyphony

In Chapter 1, we traced a MIDI note from the plugin host down to the synthesis engine. Now we dive deep into the most critical component of that chain: the **SurgeVoice**. This is where sound actually happens - where oscillators generate waveforms, filters shape timbre, and envelopes sculpt dynamics.

A voice represents a single note being played. When you press middle C on your keyboard, Surge allocates a voice, initializes its oscillators to the correct pitch, triggers its envelopes, and begins generating audio. When you release the key, the voice enters its release phase, eventually deactivating to make room for new notes.

Understanding voice architecture is essential because:

1. **Performance**: Voice processing is the most CPU-intensive part of synthesis
2. **Polyphony**: Efficient voice management enables 64-voice polyphony
3. **Expressiveness**: Per-voice modulation and MPE support live here
4. **Sound Quality**: The voice architecture determines how pristine or characterful the output sounds

This chapter explores every aspect of the SurgeVoice class, from its memory layout to its real-time processing loop.

## Voice Structure

### SurgeVoiceState: The Voice's Identity

Every voice carries state data that defines its identity - which note it's playing, how loud it is, and where it is in its lifecycle. This data is encapsulated in `SurgeVoiceState`:

```cpp
// From: src/common/dsp/SurgeVoiceState.h
struct SurgeVoiceState
{
    // Gate and lifecycle
    bool gate;                  // True while key is held down
    bool keep_playing;          // False when voice should deactivate
    bool uberrelease;           // Fast release for voice stealing

    // Pitch state
    float pitch;                // Final pitch including all modulations
    float scenepbpitch;         // Pitch without keytracking (for non-kt oscs)
    float pkey;                 // Current pitch during portamento
    float priorpkey;            // Previous quantized pitch (for porta retrigger)
    float tunedkey;             // Initial pitch with tuning applied

    // Velocity
    float fvel;                 // Normalized velocity (0.0 - 1.0)
    int velocity;               // MIDI velocity (0-127)
    float freleasevel;          // Release velocity (normalized)
    int releasevelocity;        // Release velocity (MIDI)

    // Note identity
    int key;                    // MIDI note number (0-127)
    int channel;                // MIDI channel (0-15)
    int scene_id;               // Which scene (0 or 1)

    // Portamento state
    float portasrc_key;         // Source pitch for portamento glide
    float portaphase;           // Portamento progress (0.0 - 1.0+)
    bool porta_doretrigger;     // Retrigger on quantized step

    // Detuning
    float detune;               // Voice detune (for unison)

    // Tuning system support
    float keyRetuning;          // MTS-ESP retuning offset
    int keyRetuningForKey;      // Which key the retuning applies to

    // MIDI state references
    MidiKeyState *keyState;             // Per-key state (mono mode)
    MidiChannelState *mainChannelState;  // Main MIDI channel state
    MidiChannelState *voiceChannelState; // Voice channel (MPE mode)

    // MPE support
    ControllerModulationSource mpePitchBend; // Smoothed per-note pitch bend
    float mpePitchBendRange;                 // Pitch bend range in semitones
    bool mpeEnabled;                         // MPE mode active?
    bool mtsUseChannelWhenRetuning;          // MTS-ESP channel routing

    // Voice allocation tracking
    int64_t voiceOrderAtCreate;  // Timestamp for voice stealing

    // Calculate final pitch with all modulations
    float getPitch(SurgeStorage *storage);
};
```

**Key Insights:**

1. **pitch vs pkey vs tunedkey**: These three pitch values serve different purposes:
   - `tunedkey`: Initial note pitch after microtuning (set once at note-on)
   - `pkey`: Current pitch during portamento glide (interpolates)
   - `pitch`: Final pitch including pitch bend, scene pitch, octave shifts

2. **gate vs keep_playing**: The gate goes false on note-off, but `keep_playing` stays true until the amp envelope completes its release. This allows notes to ring out naturally.

3. **voiceOrderAtCreate**: A monotonically increasing counter used for voice stealing. Older voices (lower numbers) are more likely to be stolen.

### The SurgeVoice Class: A Complete Instrument

The `SurgeVoice` class is a marvel of efficient design - it's a complete monophonic synthesizer packed into an aligned 16-byte structure for SIMD processing:

```cpp
// From: src/common/dsp/SurgeVoice.h
class alignas(16) SurgeVoice
{
public:
    // ===== AUDIO OUTPUT =====
    // Stereo output buffer (2x oversampled)
    float output alignas(16)[2][BLOCK_SIZE_OS];

    // ===== OSCILLATOR LEVELS =====
    // Linear interpolators for smooth level changes
    // [osc1, osc2, osc3, noise, ring12, ring23, pfg]
    lipol_ps osclevels alignas(16)[7];

    // ===== PARAMETER COPIES =====
    // Local copy of scene parameters with modulation applied
    pdata localcopy alignas(16)[n_scene_params];

    // FM buffer for 2+3->1 routing
    float fmbuffer alignas(16)[BLOCK_SIZE_OS];

    // ===== STATE =====
    SurgeVoiceState state;
    int age, age_release;  // Age counters for voice management

    // ===== OSCILLATORS =====
    Oscillator *osc[n_oscs];  // 3 oscillators
    int osctype[n_oscs];      // Current oscillator types

    // ===== ENVELOPES =====
    ADSRModulationSource ampEGSource;     // Amplitude envelope
    ADSRModulationSource filterEGSource;  // Filter envelope

    // ===== VOICE LFOs =====
    LFOModulationSource lfo[n_lfos_voice];  // 6 voice LFOs

    // ===== MODULATION SOURCES =====
    std::array<ModulationSource *, n_modsources> modsources;

    // Per-voice modulation sources
    ControllerModulationSource velocitySource;
    ModulationSource releaseVelocitySource;
    ModulationSource keytrackSource;
    ControllerModulationSource polyAftertouchSource;
    ControllerModulationSource monoAftertouchSource;
    ControllerModulationSource timbreSource;
    ModulationSource rndUni, rndBi, altUni, altBi;

    // ===== FILTER STATE =====
    // Filter coefficient makers (2 filter units)
    sst::filters::FilterCoefficientMaker<SurgeStorage> CM[2];

    // Filter parameter IDs for quick lookup
    int id_cfa, id_cfb;       // Cutoff A/B
    int id_kta, id_ktb;       // Keytrack A/B
    int id_emoda, id_emodb;   // Envelope mod A/B
    int id_resoa, id_resob;   // Resonance A/B
    int id_drive;             // Waveshaper drive
    int id_vca, id_vcavel;    // VCA level and velocity sensitivity
    int id_fbalance;          // Filter balance
    int id_feedback;          // Feedback amount

    // ===== MPE AND NOTE EXPRESSIONS =====
    bool mpeEnabled;
    int32_t host_note_id;     // DAW-provided note ID
    int16_t originating_host_key, originating_host_channel;

    enum NoteExpressionType
    {
        VOLUME,    // 0 < x <= 4, amp = 20 * log(x)
        PAN,       // 0..1 with 0.5 center
        PITCH,     // -120 to 120 in semitones
        TIMBRE,    // 0 .. 1 (maps to MPE CC74)
        PRESSURE,  // 0 .. 1 (channel AT in MPE, poly AT otherwise)
        UNKNOWN
    };
    std::array<float, numNoteExpressionTypes> noteExpressions;

    // ===== POLYPHONIC PARAMETER MODULATION =====
    struct PolyphonicParamModulation
    {
        int32_t param_id{0};
        double value{0};
        valtypes vt_type{vt_float};
        int imin{0}, imax{1};
    };
    static constexpr int maxPolyphonicParamModulations = 64;
    std::array<PolyphonicParamModulation, maxPolyphonicParamModulations>
        polyphonicParamModulations;
    int32_t paramModulationCount{0};
};
```

**Memory Layout Considerations:**

The `alignas(16)` directive ensures the entire voice structure is aligned to 16-byte boundaries, critical for SSE2 SIMD operations. All audio buffers (`output`, `fmbuffer`) and parameter arrays (`localcopy`) are also 16-byte aligned.

**Why 16-byte alignment?**
- SSE2 instructions require aligned memory access
- Unaligned access causes performance penalties or crashes
- Processing 4 voices simultaneously (SIMD) requires proper alignment

### Three Oscillators Per Voice

Each voice has three oscillator slots, each capable of running any of Surge's 13 oscillator types:

```cpp
// From: src/common/dsp/SurgeVoice.cpp (lines 238-242)
for (int i = 0; i < n_oscs; i++)
{
    osctype[i] = -1;  // -1 means uninitialized
}
```

Oscillators are allocated lazily through placement new in `switch_toggled()`:

```cpp
// From: src/common/dsp/SurgeVoice.cpp (lines 524-543)
for (int i = 0; i < n_oscs; i++)
{
    if (osctype[i] != scene->osc[i].type.val.i)
    {
        bool nzid = scene->drift.extend_range;
        osc[i] = spawn_osc(scene->osc[i].type.val.i, storage, &scene->osc[i],
                          localcopy, this->paramptrUnmod, oscbuffer[i]);
        if (osc[i])
        {
            // Calculate initial pitch
            float ktrkroot = 60;
            auto usep = noteShiftFromPitchParam(
                (scene->osc[i].keytrack.val.b ? state.pitch :
                 ktrkroot + state.scenepbpitch) +
                octaveSize * scene->osc[i].octave.val.i,
                0);
            osc[i]->init(usep, false, nzid);
        }
        osctype[i] = scene->osc[i].type.val.i;
    }
}
```

**Key Points:**

1. **spawn_osc()**: Factory function that returns the appropriate oscillator subclass
2. **Placement new**: Oscillators are constructed in pre-allocated `oscbuffer` arrays
3. **Keytracking**: Some oscillators ignore the played key and instead track a fixed root note
4. **Drift**: The `nzid` (non-zero ID) flag enables subtle pitch variation between voices

### Two Filter Units

Surge's filter architecture is one of its most sophisticated features. Each voice has two filter units that can be configured in multiple topologies:

```cpp
// Filter configurations (from SurgeStorage.h)
enum filter_config
{
    fc_serial1,    // Filter A -> Filter B
    fc_serial2,    // Like serial1 with different balance
    fc_serial3,    // Like serial1/2 with different balance
    fc_parallel,   // Filter A + Filter B (mixed)
    fc_stereo,     // Filter A (L) | Filter B (R)
    fc_ring,       // Filter A * Filter B (ring modulation)
    fc_wide,       // Stereo with independent L/R processing

    n_filter_configs,
};
```

The filters are processed via the **QuadFilterChain**, which processes 4 voices simultaneously using SIMD:

```cpp
// From: src/common/dsp/QuadFilterChain.h
struct QuadFilterChainState
{
    sst::filters::QuadFilterUnitState FU[4];  // 4 filter units (2 mono or 4 stereo)
    sst::waveshapers::QuadWaveshaperState WSS[2];  // Stereo waveshaper

    SIMD_M128 Gain, FB, Mix1, Mix2, Drive;
    SIMD_M128 dGain, dFB, dMix1, dMix2, dDrive;  // Deltas for interpolation

    SIMD_M128 wsLPF, FBlineL, FBlineR;  // Waveshaper lowpass and feedback lines

    SIMD_M128 DL[BLOCK_SIZE_OS], DR[BLOCK_SIZE_OS];  // Input wavedata

    SIMD_M128 OutL, OutR, dOutL, dOutR;  // Output levels
    SIMD_M128 Out2L, Out2R, dOut2L, dOut2R;  // Second output (stereo mode)
};
```

**SIMD Processing:**

The QuadFilterChain processes 4 voices in parallel. Each `SIMD_M128` register contains 4 floats:

```
Voice 0: [sample_n_v0, sample_n_v1, sample_n_v2, sample_n_v3]
Voice 1: [sample_n_v0, sample_n_v1, sample_n_v2, sample_n_v3]
Voice 2: [sample_n_v0, sample_n_v1, sample_n_v2, sample_n_v3]
Voice 3: [sample_n_v0, sample_n_v1, sample_n_v2, sample_n_v3]
```

This means one SSE instruction processes the same operation for all 4 voices simultaneously, a massive performance win.

### Two Envelopes: Filter EG and Amp EG

Each voice has two ADSR envelopes:

```cpp
// From: src/common/dsp/SurgeVoice.cpp (lines 305-309)
ampEGSource.init(storage, &scene->adsr[0], localcopy, &state);
filterEGSource.init(storage, &scene->adsr[1], localcopy, &state);

modsources[ms_ampeg] = &ampEGSource;
modsources[ms_filtereg] = &filterEGSource;
```

**Amp Envelope (ADSR 1):**
- Always applied to final voice output
- Controls volume over time
- When idle (reached zero in release), voice is deactivated

**Filter Envelope (ADSR 2):**
- Modulates filter cutoff by default
- Can modulate any parameter via mod matrix
- Independent attack/decay/sustain/release

The envelopes are `ADSRModulationSource` objects that implement the modulation source interface, allowing them to be routed to any parameter.

### Six Voice LFOs

Voice LFOs are instantiated per-voice, allowing independent modulation for each note:

```cpp
// From: src/common/dsp/SurgeVoice.cpp (lines 274-290)
for (int i = 0; i < n_lfos_voice; i++)
{
    lfo[i].assign(storage, &scene->lfo[i], localcopy, &state,
                  &storage->getPatch().stepsequences[state.scene_id][i],
                  &storage->getPatch().msegs[state.scene_id][i],
                  &storage->getPatch().formulamods[state.scene_id][i]);
    lfo[i].setIsVoice(true);

    if (scene->lfo[i].shape.val.i == lt_formula)
    {
        Surge::Formula::setupEvaluatorStateFrom(lfo[i].formulastate,
                                               storage->getPatch(), scene_id);
        Surge::Formula::setupEvaluatorStateFrom(lfo[i].formulastate, this);
    }

    modsources[ms_lfo1 + i] = &lfo[i];
}
```

**Voice LFO Features:**

1. **Per-Voice Independence**: Each voice's LFOs run independently
2. **Multiple Shapes**: Sine, triangle, saw, square, sample & hold, MSEG, formula
3. **Envelope Mode**: Can act as additional envelopes with attack/release
4. **Formula Mode**: Lua-scripted custom LFO shapes with voice-level access

The voice can also access the 6 scene LFOs (shared across all voices):

```cpp
// From: src/common/dsp/SurgeVoice.cpp (lines 320-325)
modsources[ms_slfo1] = oscene->modsources[ms_slfo1];
modsources[ms_slfo2] = oscene->modsources[ms_slfo2];
modsources[ms_slfo3] = oscene->modsources[ms_slfo3];
modsources[ms_slfo4] = oscene->modsources[ms_slfo4];
modsources[ms_slfo5] = oscene->modsources[ms_slfo5];
modsources[ms_slfo6] = oscene->modsources[ms_slfo6];
```

This gives a total of **12 LFOs** available to modulate each voice (6 voice + 6 scene).

## Voice Processing

### The process_block() Method: Real-Time Audio Generation

The `process_block()` method is where audio actually happens. It's called once per BLOCK_SIZE (32 samples at normal rate, 64 at 2x oversample) and must complete within strict real-time deadlines:

```cpp
// From: src/common/dsp/SurgeVoice.cpp (lines 1024-1254)
bool SurgeVoice::process_block(QuadFilterChainState &Q, int Qe)
{
    // Step 1: Update all modulation sources and parameters
    calc_ctrldata<0>(&Q, Qe);

    bool is_wide = scene->filterblock_configuration.val.i == fc_wide;
    float tblock alignas(16)[BLOCK_SIZE_OS], tblock2 alignas(16)[BLOCK_SIZE_OS];
    float *tblockR = is_wide ? tblock2 : tblock;

    float ktrkroot = 60;  // Mysterious override for non-keytracked oscs
    float drift = localcopy[scene->drift.param_id_in_scene].f;

    // Step 2: Clear output buffers
    mech::clear_block<BLOCK_SIZE_OS>(output[0]);
    mech::clear_block<BLOCK_SIZE_OS>(output[1]);

    // Step 3: Update oscillator gate state
    for (int i = 0; i < n_oscs; ++i)
    {
        if (osc[i])
        {
            osc[i]->setGate(state.gate);
        }
    }

    // Step 4: Process oscillators (order matters for FM routing)
    // [Oscillator processing code - detailed below]

    // Step 5: Pre-filter gain
    osclevels[le_pfg].multiply_2_blocks(output[0], output[1], BLOCK_SIZE_OS_QUAD);

    // Step 6: Write to QuadFilterChain input
    for (int i = 0; i < BLOCK_SIZE_OS; i++)
    {
        SIMD_MM(store_ss)(((float *)&Q.DL[i] + Qe), SIMD_MM(load_ss)(&output[0][i]));
        SIMD_MM(store_ss)(((float *)&Q.DR[i] + Qe), SIMD_MM(load_ss)(&output[1][i]));
    }

    // Step 7: Set filter parameters
    SetQFB(&Q, Qe);

    // Step 8: Age the voice
    age++;
    if (!state.gate)
        age_release++;

    return state.keep_playing;
}
```

**Processing Order is Critical:**

1. Update modulation first (envelopes, LFOs change over time)
2. Process oscillators in reverse order (OSC3 -> OSC2 -> OSC1) for FM
3. Mix oscillators with ring modulation
4. Apply pre-filter gain
5. Load samples into filter chain
6. Filters are processed later by QuadFilterChain (4 voices at once)

### Oscillator Processing and Mixing

Oscillators are processed in a specific order to support FM (Frequency Modulation) routing:

```cpp
// From: src/common/dsp/SurgeVoice.cpp (lines 1049-1181)

// OSC 3: Process first (can FM OSC 2 in 3->2->1 mode)
if (osc3 || ring23 || ((osc1 || osc2 || ring12) && (FMmode == fm_3to2to1)) ||
    ((osc1 || ring12) && (FMmode == fm_2and3to1)))
{
    osc[2]->process_block(
        noteShiftFromPitchParam(
            (scene->osc[2].keytrack.val.b ? state.pitch : ktrkroot + state.scenepbpitch) +
                octaveSize * scene->osc[2].octave.val.i,
            2),
        drift, is_wide);

    if (osc3)
    {
        // Scale by oscillator level
        if (is_wide)
        {
            osclevels[le_osc3].multiply_2_blocks_to(osc[2]->output, osc[2]->outputR,
                                                    tblock, tblockR, BLOCK_SIZE_OS_QUAD);
        }
        else
        {
            osclevels[le_osc3].multiply_block_to(osc[2]->output, tblock,
                                                 BLOCK_SIZE_OS_QUAD);
        }

        // Route to filters
        if (route[2] < 2)  // To Filter A
        {
            mech::accumulate_from_to<BLOCK_SIZE_OS>(tblock, output[0]);
        }
        if (route[2] > 0)  // To Filter B
        {
            mech::accumulate_from_to<BLOCK_SIZE_OS>(tblockR, output[1]);
        }
    }
}

// OSC 2: Can be FM'd by OSC 3
if (osc2 || ring12 || ring23 || (FMmode && osc1))
{
    if (FMmode == fm_3to2to1)
    {
        // OSC 3 modulates OSC 2's frequency
        osc[1]->process_block(
            noteShiftFromPitchParam(...), drift, is_wide, true,
            storage->db_to_linear(localcopy[scene->fm_depth.param_id_in_scene].f));
    }
    else
    {
        osc[1]->process_block(..., drift, is_wide);
    }

    // [Mix and route OSC 2 output]
}

// OSC 1: Can be FM'd by OSC 2 (or OSC 2+3)
if (osc1 || ring12)
{
    if (FMmode == fm_2and3to1)
    {
        // OSC 2 and OSC 3 both modulate OSC 1
        mech::add_block<BLOCK_SIZE_OS>(osc[1]->output, osc[2]->output, fmbuffer);
        osc[0]->process_block(..., drift, is_wide, true,
            storage->db_to_linear(localcopy[scene->fm_depth.param_id_in_scene].f));
    }
    else if (FMmode)
    {
        // Only OSC 2 modulates OSC 1
        osc[0]->process_block(..., drift, is_wide, true, ...);
    }
    else
    {
        // No FM
        osc[0]->process_block(..., drift, is_wide);
    }

    // [Mix and route OSC 1 output]
}
```

**FM Routing Modes:**

- `fm_off`: No FM, oscillators run independently
- `fm_2to1`: OSC 2 modulates OSC 1's frequency
- `fm_3to2to1`: OSC 3 -> OSC 2 -> OSC 1 (serial FM)
- `fm_2and3to1`: OSC 2 + OSC 3 -> OSC 1 (parallel FM)

### Ring Modulation: 12 and 23 Routing

Ring modulation multiplies two oscillators together, creating complex harmonic content:

```cpp
// From: src/common/dsp/SurgeVoice.cpp (lines 1183-1213)

// Ring 12: OSC 1 * OSC 2
if (ring12)
{
    all_ring_modes_block(osc[0]->output, osc[1]->output,
                        osc[0]->outputR, osc[1]->outputR,
                        tblock, tblockR, is_wide,
                        scene->level_ring_12.deform_type,
                        osclevels[le_ring12], BLOCK_SIZE_OS_QUAD);

    if (route[3] < 2)
    {
        mech::accumulate_from_to<BLOCK_SIZE_OS>(tblock, output[0]);
    }
    if (route[3] > 0)
    {
        mech::accumulate_from_to<BLOCK_SIZE_OS>(tblockR, output[1]);
    }
}

// Ring 23: OSC 2 * OSC 3
if (ring23)
{
    all_ring_modes_block(osc[1]->output, osc[2]->output,
                        osc[1]->outputR, osc[2]->outputR,
                        tblock, tblockR, is_wide,
                        scene->level_ring_23.deform_type,
                        osclevels[le_ring23], BLOCK_SIZE_OS_QUAD);

    if (route[4] < 2)
    {
        mech::accumulate_from_to<BLOCK_SIZE_OS>(tblock, output[0]);
    }
    if (route[4] > 0)
    {
        mech::accumulate_from_to<BLOCK_SIZE_OS>(tblockR, output[1]);
    }
}
```

**Ring Modulation Modes:**

Beyond classic ring modulation (multiplication), Surge supports multiple "combinator" modes:

```cpp
// From: src/common/dsp/SurgeVoice.cpp (lines 912-1022)
inline void all_ring_modes_block(...)
{
    switch (mode)
    {
    case CombinatorMode::cxm_ring:
        mech::mul_block<BLOCK_SIZE_OS>(src1_l, src2_l, dst_l);
        break;
    case CombinatorMode::cxm_cxor43_0:
        cxor43_0_block(src1_l, src2_l, dst_l, nquads);
        break;
    // ... 11 total combinator modes
    }
    osclevels.multiply_block(dst_l, nquads);
}
```

These modes include mathematical operations like XOR on floating-point bit patterns, creating unique digital artifacts.

### Filter Processing with QuadFilterChain

After oscillators are mixed, the audio is loaded into the `QuadFilterChainState` and processed by the filter chain. The voice itself doesn't run the filters - instead, it populates its slot in the SIMD vectors:

```cpp
// From: src/common/dsp/SurgeVoice.cpp (lines 1242-1248)

// Load samples into Qe'th position of SIMD vectors
for (int i = 0; i < BLOCK_SIZE_OS; i++)
{
    SIMD_MM(store_ss)(((float *)&Q.DL[i] + Qe), SIMD_MM(load_ss)(&output[0][i]));
    SIMD_MM(store_ss)(((float *)&Q.DR[i] + Qe), SIMD_MM(load_ss)(&output[1][i]));
}

SetQFB(&Q, Qe);  // Set filter coefficients for this voice
```

**SetQFB: Filter Coefficient Setup**

This method calculates filter coefficients based on modulated parameters:

```cpp
// From: src/common/dsp/SurgeVoice.cpp (lines 1365-1491)
void SurgeVoice::SetQFB(QuadFilterChainState *Q, int e)
{
    using namespace sst::filters;

    // Calculate filter mix based on configuration
    float FMix1, FMix2;
    switch (scene->filterblock_configuration.val.i)
    {
    case fc_serial1:
    case fc_serial2:
    case fc_serial3:
    case fc_ring:
    case fc_wide:
        FMix1 = min(1.f, 1.f - localcopy[id_fbalance].f);
        FMix2 = min(1.f, 1.f + localcopy[id_fbalance].f);
        break;
    default:
        FMix1 = 0.5f - 0.5f * localcopy[id_fbalance].f;
        FMix2 = 0.5f + 0.5f * localcopy[id_fbalance].f;
        break;
    }

    // Calculate gain, drive, feedback
    float Drive = db_to_linear(scene->wsunit.drive.get_extended(localcopy[id_drive].f));
    float Gain = db_to_linear(localcopy[id_vca].f +
                  localcopy[id_vcavel].f * (1.f - velocitySource.get_output(0))) *
                 modsources[ms_ampeg]->get_output(0);
    float FB = scene->feedback.get_extended(localcopy[id_feedback].f);

    if (Q)
    {
        // Set interpolation deltas for smooth parameter changes
        set1f(Q->Gain, e, FBP.Gain);
        set1f(Q->dGain, e, (Gain - FBP.Gain) * BLOCK_SIZE_OS_INV);
        set1f(Q->Drive, e, FBP.Drive);
        set1f(Q->dDrive, e, (Drive - FBP.Drive) * BLOCK_SIZE_OS_INV);
        set1f(Q->FB, e, FBP.FB);
        set1f(Q->dFB, e, (FB - FBP.FB) * BLOCK_SIZE_OS_INV);
        // ... more parameters

        // Calculate filter cutoffs with keytracking and envelope mod
        float keytrack = state.pitch - (float)scene->keytrack_root.val.i;
        float fenv = modsources[ms_filtereg]->get_output(0);
        float cutoffA =
            localcopy[id_cfa].f + localcopy[id_kta].f * keytrack +
            localcopy[id_emoda].f * fenv;
        float cutoffB =
            localcopy[id_cfb].f + localcopy[id_ktb].f * keytrack +
            localcopy[id_emodb].f * fenv;

        if (scene->f2_cutoff_is_offset.val.b)
            cutoffB += cutoffA;

        // Generate filter coefficients
        CM[0].MakeCoeffs(cutoffA, localcopy[id_resoa].f,
                        static_cast<FilterType>(scene->filterunit[0].type.val.i),
                        static_cast<FilterSubType>(scene->filterunit[0].subtype.val.i),
                        storage, scene->filterunit[0].cutoff.extend_range);
        CM[1].MakeCoeffs(cutoffB,
                        scene->f2_link_resonance.val.b ?
                            localcopy[id_resoa].f : localcopy[id_resob].f,
                        static_cast<FilterType>(scene->filterunit[1].type.val.i),
                        static_cast<FilterSubType>(scene->filterunit[1].subtype.val.i),
                        storage, scene->filterunit[1].cutoff.extend_range);

        // Update state for each filter unit
        for (int u = 0; u < n_filterunits_per_scene; u++)
        {
            if (scene->filterunit[u].type.val.i != 0)
            {
                CM[u].updateState(Q->FU[u], e);
                for (int i = 0; i < n_filter_registers; i++)
                {
                    set1f(Q->FU[u].R[i], e, FBP.FU[u].R[i]);
                }
                // ... more state updates
            }
        }
    }

    // Store state for next block
    FBP.Gain = Gain;
    FBP.Drive = Drive;
    FBP.FB = FB;
    FBP.Mix1 = FMix1;
    FBP.Mix2 = FMix2;
}
```

**Key Insight:** The voice doesn't run the filter - it just sets up the coefficients and state for its slot in the SIMD vector. The actual filtering happens later when `QuadFilterChain` processes all 4 voices together.

### Amp Envelope Application

The final voice gain is calculated by combining:

```cpp
// From: src/common/dsp/SurgeVoice.cpp (lines 1391-1393)
float Gain = db_to_linear(localcopy[id_vca].f +
              localcopy[id_vcavel].f * (1.f - velocitySource.get_output(0))) *
             modsources[ms_ampeg]->get_output(0);
```

Breaking this down:
1. `localcopy[id_vca].f`: Base VCA level parameter
2. `localcopy[id_vcavel].f * (1.f - velocitySource.get_output(0))`: Velocity sensitivity
3. `modsources[ms_ampeg]->get_output(0)`: Amp envelope (0.0 to 1.0)

All multiplied together and converted from dB to linear gain.

## Voice Lifecycle

### Initialization on Note-On

When a MIDI note arrives, the synthesizer allocates a voice and calls its constructor:

```cpp
// From: src/common/dsp/SurgeVoice.cpp (lines 146-384)
SurgeVoice::SurgeVoice(SurgeStorage *storage, SurgeSceneStorage *oscene, pdata *params,
                       pdata *paramsUnmod, int key, int velocity, int channel, int scene_id,
                       float detune, MidiKeyState *keyState, MidiChannelState *mainChannelState,
                       MidiChannelState *voiceChannelState, bool mpeEnabled, int64_t voiceOrder,
                       int32_t host_nid, int16_t host_key, int16_t host_chan,
                       float aegStart, float fegStart)
{
    // Assign pointers
    this->storage = storage;
    this->scene = oscene;
    this->paramptr = params;
    this->paramptrUnmod = paramsUnmod;
    this->mpeEnabled = mpeEnabled;
    this->host_note_id = host_nid;

    // Initialize state
    state.voiceOrderAtCreate = voiceOrder;
    age = 0;
    age_release = 0;

    state.key = key;
    state.channel = channel;
    state.velocity = velocity;
    state.fvel = velocity / 127.f;
    state.scene_id = scene_id;
    state.detune = detune;
    state.uberrelease = false;

    // Calculate tuned pitch
    state.tunedkey = state.getPitch(storage);

    // Set up portamento
    resetPortamentoFrom(storage->last_key[scene_id], channel);
    storage->last_key[scene_id] = key;

    // Initialize note expressions (VST3/CLAP)
    noteExpressions[VOLUME] = 1.0;    // 1 = no amplification
    noteExpressions[PAN] = 0.5;       // 0.5 = center
    noteExpressions[PITCH] = 0.0;
    noteExpressions[TIMBRE] = 0.0;
    noteExpressions[PRESSURE] = 0.0;

    // Set gates
    state.gate = true;
    state.keep_playing = true;

    // Initialize modulation sources
    velocitySource.init(0, state.fvel);
    polyAftertouchSource.init(
        storage->poly_aftertouch[state.scene_id & 1][state.channel & 15][state.key & 127]);
    timbreSource.init(state.voiceChannelState->timbre);
    monoAftertouchSource.init(state.voiceChannelState->pressure);

    // Initialize envelopes
    ampEGSource.init(storage, &scene->adsr[0], localcopy, &state);
    filterEGSource.init(storage, &scene->adsr[1], localcopy, &state);

    // Copy parameters to local buffer
    memcpy(localcopy, paramptr, sizeof(localcopy));

    // Apply modulation
    applyModulationToLocalcopy<true>();

    // Start envelopes from specified levels (for legato/mono modes)
    ampEGSource.attackFrom(aegStart);
    filterEGSource.attackFrom(fegStart);

    // Initialize voice LFOs
    for (int i = 0; i < n_lfos_voice; i++)
    {
        lfo[i].attack();
    }

    // Initialize control interpolators
    calc_ctrldata<true>(0, 0);
    SetQFB(0, 0);  // Initialize filter parameters

    // Create oscillators (must be last - needs modulation state)
    switch_toggled();
}
```

**aegStart and fegStart:**

These parameters support "legato" mode where a new note doesn't restart envelopes from zero but continues from their current level. This creates smooth transitions between notes.

### Attack, Sustain, Release Phases

The voice progresses through standard ADSR phases:

**Attack Phase:**
```cpp
// Envelope in attack when 0.0 <= output < 1.0
// Rising exponentially toward sustain level
```

**Decay Phase:**
```cpp
// After attack peak, envelope decays to sustain level
```

**Sustain Phase:**
```cpp
// Envelope holds at sustain level while gate is true
// Gate is true while MIDI key is held
if (state.gate)
    // Voice in sustain
```

**Release Phase:**
```cpp
// From: src/common/dsp/SurgeVoice.cpp (lines 626-638)
void SurgeVoice::release()
{
    ampEGSource.release();
    filterEGSource.release();

    for (int i = 0; i < n_lfos_voice; i++)
    {
        lfo[i].release();
    }

    state.gate = false;
    releaseVelocitySource.set_output(0, state.releasevelocity / 127.0f);
}
```

When note-off arrives, all envelopes and envelope-mode LFOs are released. The voice continues playing until the amp envelope reaches zero.

### Voice Deactivation

A voice is deactivated when its amp envelope completes release:

```cpp
// From: src/common/dsp/SurgeVoice.cpp (lines 778-781)
if (((ADSRModulationSource *)modsources[ms_ampeg])->is_idle())
{
    state.keep_playing = false;
}
```

The `is_idle()` method returns true when the envelope has reached zero and remained there. The voice manager then reclaims this voice for reuse.

### Uber-Release for Voice Stealing

When polyphony limit is reached, Surge must steal a voice to play a new note. The stolen voice gets an "uber-release" - an extremely fast release:

```cpp
// From: src/common/dsp/SurgeVoice.cpp (lines 640-645)
void SurgeVoice::uber_release()
{
    ampEGSource.uber_release();
    state.gate = false;
    state.uberrelease = true;
}
```

The uber-release causes the amp envelope to drop to zero in just a few milliseconds, freeing the voice with minimal audible artifacts (though still potentially causing clicks if not managed carefully).

## Polyphonic Features

### Per-Voice Modulation

Each voice has its own complete modulation matrix. The modulation sources are either:

**Per-Voice (Independent):**
- 6 voice LFOs
- 2 envelopes (Amp EG, Filter EG)
- Velocity
- Release velocity
- Keytrack
- Poly aftertouch
- Random/Alternate (snapped at voice start)

**Scene-Shared (Same for all voices):**
- 6 scene LFOs
- Mod wheel, breath, expression, sustain
- Channel aftertouch
- Pitch bend
- Timbre (MPE)
- 8 custom controllers
- Lowest/highest/latest key

Modulation is applied in `applyModulationToLocalcopy()`:

```cpp
// From: src/common/dsp/SurgeVoice.cpp (lines 1256-1351)
template <bool noLFOSources> void SurgeVoice::applyModulationToLocalcopy()
{
    vector<ModulationRouting>::iterator iter;
    iter = scene->modulation_voice.begin();
    while (iter != scene->modulation_voice.end())
    {
        int src_id = iter->source_id;
        int dst_id = iter->destination_id;
        float depth = iter->depth;

        if (noLFOSources && isLFO((::modsources)src_id))
        {
            // Skip LFO sources during initialization
        }
        else if (modsources[src_id])
        {
            localcopy[dst_id].f +=
                depth * modsources[src_id]->get_output(iter->source_index) *
                (1.0 - iter->muted);
        }
        iter++;
    }

    // MPE mode: Apply channel aftertouch as per-voice modulation
    if (mpeEnabled)
    {
        iter = scene->modulation_scene.begin();
        while (iter != scene->modulation_scene.end())
        {
            int src_id = iter->source_id;
            if (src_id == ms_aftertouch && modsources[src_id])
            {
                int dst_id = iter->destination_id;
                if (dst_id >= 0 && dst_id < n_scene_params)
                {
                    float depth = iter->depth;
                    localcopy[dst_id].f +=
                        depth * modsources[src_id]->get_output(0) * (1.0 - iter->muted);
                }
            }
            iter++;
        }
    }

    // Apply polyphonic parameter modulations (VST3/CLAP)
    for (int i = 0; i < paramModulationCount; ++i)
    {
        auto &pc = polyphonicParamModulations[i];
        switch (pc.vt_type)
        {
        case vt_float:
            localcopy[pc.param_id].f += pc.value;
            break;
        case vt_int:
            localcopy[pc.param_id].i =
                std::clamp((int)(round)(localcopy[pc.param_id].i + pc.value),
                          pc.imin, pc.imax);
            break;
        case vt_bool:
            if (pc.value > 0.5)
                localcopy[pc.param_id].b = true;
            if (pc.value < 0.5)
                localcopy[pc.param_id].b = false;
            break;
        }
    }
}
```

**Template Parameter noLFOSources:**

The template allows skipping LFO sources during voice initialization (since LFOs haven't been processed yet). After the first block, all sources are included.

### MPE Support: Per-Note Pitch, Pressure, Timbre

MPE (MIDI Polyphonic Expression) allows per-note control of pitch bend, pressure, and timbre. Surge implements full MPE support in the voice:

```cpp
// From: src/common/dsp/SurgeVoice.cpp (lines 206-210, 1277-1314)

// Initialize MPE pitch bend
state.mpePitchBendRange = storage->mpePitchBendRange;
state.mpeEnabled = mpeEnabled;
state.mpePitchBend = ControllerModulationSource(storage->pitchSmoothingMode);
state.mpePitchBend.set_samplerate(storage->samplerate, storage->samplerate_inv);
state.mpePitchBend.init(voiceChannelState->pitchBend / 8192.f);

// During modulation processing:
if (mpeEnabled)
{
    // Smooth MPE pitch bend
    float bendNormalized = state.voiceChannelState->pitchBend / 8192.f;
    state.mpePitchBend.set_target(bendNormalized);
    state.mpePitchBend.process_block();

    // Smooth pressure and timbre
    monoAftertouchSource.set_target(state.voiceChannelState->pressure +
                                   noteExpressions[PRESSURE]);
    timbreSource.set_target(state.voiceChannelState->timbre + noteExpressions[TIMBRE]);

    if (scene->modsource_doprocess[ms_aftertouch])
    {
        monoAftertouchSource.process_block();
    }
    timbreSource.process_block();
}
```

**MPE Pitch Calculation:**

```cpp
// From: src/common/dsp/SurgeVoiceState.h and SurgeVoice.cpp (lines 49-86)
float SurgeVoiceState::getPitch(SurgeStorage *storage)
{
    float mpeBend = mpePitchBend.get_output(0) * mpePitchBendRange;
    auto res = key + mpeBend + detune;

    // Apply microtuning if active
    #ifndef SURGE_SKIP_ODDSOUND_MTS
    if (storage->oddsound_mts_client && storage->oddsound_mts_active_as_client)
    {
        if (storage->oddsoundRetuneMode == SurgeStorage::RETUNE_CONSTANT ||
            key != keyRetuningForKey)
        {
            keyRetuningForKey = key;
            keyRetuning = MTS_RetuningInSemitones(storage->oddsound_mts_client,
                                                 key + mpeBend,
                                                 mtsUseChannelWhenRetuning ? channel : -1);
        }
        res = res + keyRetuning;
    }
    #endif

    return res;
}
```

### Note Expressions (VST3/CLAP)

Modern plugin formats support "note expressions" - per-note automation distinct from MPE:

```cpp
// From: src/common/dsp/SurgeVoice.h (lines 105-117)
enum NoteExpressionType
{
    VOLUME,    // 0 < x <= 4, amp = 20 * log(x)
    PAN,       // 0..1 with 0.5 center
    PITCH,     // -120 to 120 in semitones
    TIMBRE,    // 0 .. 1 (maps to MPE Timbre parameter)
    PRESSURE,  // 0 .. 1 (channel AT in MPE, poly AT otherwise)
    UNKNOWN
};
std::array<float, numNoteExpressionTypes> noteExpressions;

void applyNoteExpression(NoteExpressionType net, float value)
{
    if (net != UNKNOWN)
        noteExpressions[net] = value;
}
```

Note expressions are additive with MPE modulations and are applied during parameter calculation:

```cpp
// From: src/common/dsp/SurgeVoice.cpp (lines 854-862)
float pan1 = limit_range(localcopy[pan_id].f +
                        state.voiceChannelState->pan +
                        state.mainChannelState->pan +
                        (noteExpressions[PAN] * 2 - 1),
                        -1.f, 1.f);

float amp = 0.5f * amp_to_linear(localcopy[volume_id].f);
amp = amp * noteExpressions[VOLUME];  // VOLUME note expression
```

### Legato Mode

Legato mode allows smooth transitions between notes in monophonic play modes:

```cpp
// From: src/common/dsp/SurgeVoice.cpp (lines 394-431)
void SurgeVoice::legato(int key, int velocity, char detune)
{
    // If portamento is done or very close, use current pitch as source
    if (state.portaphase > 1)
        state.portasrc_key = state.getPitch(storage);
    else
    {
        // Portamento in progress - calculate current interpolated position
        float phase;
        switch (scene->portamento.porta_curve)
        {
        case porta_log:
            phase = storage->glide_log(state.portaphase);
            break;
        case porta_lin:
            phase = state.portaphase;
            break;
        case porta_exp:
            phase = storage->glide_exp(state.portaphase);
            break;
        }

        state.portasrc_key = ((1 - phase) * state.portasrc_key +
                             phase * state.getPitch(storage));

        if (scene->portamento.porta_gliss)  // Quantize to keys
            state.pkey = floor(state.pkey + 0.5);

        state.porta_doretrigger = false;
        if (scene->portamento.porta_retrigger)
            retriggerPortaIfKeyChanged();
    }

    // Update to new key
    state.key = key;
    storage->last_key[state.scene_id] = key;
    state.portaphase = 0;  // Restart portamento to new target
}
```

**Legato Features:**

1. **No Retrigger**: Envelopes don't restart (unless porta_retrigger enabled)
2. **Portamento**: Pitch glides smoothly from old to new note
3. **Velocity Update**: New velocity can be applied (mode-dependent)

## Voice Stealing

When the polyphony limit is reached and a new note arrives, Surge must "steal" an existing voice. The voice stealing algorithm balances fairness with musical sensibility.

### Algorithm for Finding Voices to Steal

Voice stealing happens in `SurgeSynthesizer::playVoice()`:

```cpp
// From: src/common/SurgeSynthesizer.cpp (not shown, but algorithm described)

// Voice stealing priority (lowest to highest):
// 1. Released voices (gate = false)
// 2. Quietest voices (lowest amplitude)
// 3. Oldest voices (lowest voiceOrderAtCreate)
// 4. Voices from lower scenes (scene A before scene B)

int SurgeSynthesizer::findVoiceToSteal()
{
    int steal_voice = -1;
    float lowest_priority = 999999.f;

    for (int i = 0; i < MAX_VOICES; i++)
    {
        if (!voices[i].state.keep_playing)
            continue;  // Voice already free

        float priority = calculateVoicePriority(voices[i]);

        if (priority < lowest_priority)
        {
            lowest_priority = priority;
            steal_voice = i;
        }
    }

    return steal_voice;
}

float SurgeSynthesizer::calculateVoicePriority(SurgeVoice &v)
{
    float priority = 0.0f;

    // Released voices: Very low priority (likely to steal)
    if (!v.state.gate)
        priority -= 10000.0f;

    // Add age penalty (older = lower priority)
    priority -= v.age * 0.1f;

    // Add volume penalty (quieter = lower priority)
    float aeg, feg;
    v.getAEGFEGLevel(aeg, feg);
    priority += aeg * 1000.0f;  // Louder voices have higher priority

    return priority;
}
```

### Priority System

The priority calculation ensures:

1. **Released notes are stolen first** - Notes you've released are less important than sustained notes
2. **Quiet voices before loud voices** - A voice in release at -40dB is better to steal than a voice at peak
3. **Old before new** - If all else is equal, steal the oldest voice
4. **Scene A before Scene B** - Minor bias toward keeping Scene B voices

### Fast Release (Uber-Release)

When a voice is stolen, it must deactivate quickly to avoid audible overlap with the new note:

```cpp
// From: src/common/dsp/ADSRModulationSource.cpp (concept)
void ADSRModulationSource::uber_release()
{
    // Set release rate to ~1ms instead of normal release time
    releaseRate = 0.001f * samplerate;
    stage = RELEASE;
}
```

The uber-release causes the envelope to drop exponentially to zero in just 1-2 milliseconds, much faster than the normal release time. This minimizes artifacts while freeing the voice quickly.

**Click Prevention:**

Even with uber-release, stealing a very loud voice can cause clicks. Some strategies:

1. **Prefer quieter voices** - The amplitude check in priority calculation
2. **Apply fast fadeout** - Some implementations multiply by a quick ramp down
3. **Reserve voices** - Never steal the last few voices (some synths do this)

Surge primarily relies on intelligent priority and fast release rather than reserved voices.

## Performance Considerations

### SIMD Processing Throughout

Voice processing is heavily optimized with SSE2 SIMD instructions:

```cpp
// Process 4 voices simultaneously in QuadFilterChain
// Each SIMD register holds samples from 4 different voices
SIMD_M128 input = {voice0_sample, voice1_sample, voice2_sample, voice3_sample};
```

This means processing 1 voice or 4 voices takes roughly the same CPU time - a 4x efficiency gain.

### Block-Based Processing

All voice processing happens in 64-sample blocks (2x oversampled from 32):

```
Block time at 48kHz: 0.67ms
CPU must complete all processing within this deadline
```

Breaking work into blocks allows:
- Amortized parameter updates (calc_ctrldata runs once per block)
- Efficient cache usage (64 samples fit in L1 cache)
- Batched SIMD operations

### Memory Alignment

All audio buffers are 16-byte aligned:

```cpp
float output alignas(16)[2][BLOCK_SIZE_OS];
float fmbuffer alignas(16)[BLOCK_SIZE_OS];
```

Unaligned SSE loads/stores are 2-3x slower, so this alignment is critical for performance.

## Conclusion

The SurgeVoice represents the culmination of synthesis theory and software engineering:

1. **Complete Signal Path**: Oscillators → Ring Mod → Filters → Waveshaper → Amp
2. **Sophisticated Modulation**: 12 LFOs, 2 EGs, velocity, keytrack, MPE, note expressions
3. **SIMD Optimization**: 4 voices processed simultaneously via QuadFilterChain
4. **Real-Time Safety**: No allocations, deterministic processing, strict deadlines
5. **Musical Intelligence**: Smart voice stealing, legato modes, portamento

Understanding voice architecture is essential for:
- **Adding Oscillators**: New oscillator types plug into the voice framework
- **Performance Optimization**: Voice processing is the critical path
- **Musical Features**: MPE, legato, and voice management all live here
- **Debugging**: Most audio issues trace back to voice processing

In the next chapters, we'll explore:
- **Chapter 5**: Oscillator architecture and algorithms
- **Chapter 6**: Filter theory and QuadFilterChain details
- **Chapter 7**: Modulation routing and the modulation matrix

---

**Previous: [Chapter 3: Synthesis Pipeline](03-synthesis-pipeline.md)**
**Next: [Chapter 5: Oscillator Overview](05-oscillators-overview.md)**
