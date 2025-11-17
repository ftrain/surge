# Chapter 33: Plugin Architecture

## Bridging Worlds: From Audio Engine to DAW Integration

A synthesizer plugin exists in two worlds simultaneously: the pristine, deterministic realm of digital signal processing, and the chaotic, host-dependent environment of Digital Audio Workstations (DAWs). Surge XT's plugin architecture acts as a sophisticated bridge between these worlds, translating host automation into parameter changes, converting MIDI messages into note events, and serializing complex synthesizer state into portable chunks that can be saved, recalled, and shared.

This chapter explores how Surge XT integrates with plugin frameworks, manages the delicate dance between audio and UI threads, and implements format-specific features for VST3, Audio Unit, CLAP, and LV2.

## 1. JUCE Plugin Framework

### The AudioProcessor Base Class

JUCE provides the `juce::AudioProcessor` class, an abstraction layer that handles the complexities of different plugin formats. Rather than writing separate code for VST3, AU, CLAP, and standalone, Surge implements a single `SurgeSynthProcessor` that inherits from `AudioProcessor`.

```cpp
// From: src/surge-xt/SurgeSynthProcessor.h
class SurgeSynthProcessor : public juce::AudioProcessor,
                            public juce::VST3ClientExtensions,
#if HAS_CLAP_JUCE_EXTENSIONS
                            public clap_juce_extensions::clap_properties,
                            public clap_juce_extensions::clap_juce_audio_processor_capabilities,
#endif
                            public SurgeSynthesizer::PluginLayer,
                            public juce::MidiKeyboardState::Listener
{
public:
    SurgeSynthProcessor();
    ~SurgeSynthProcessor();

    // Core plugin interface
    void prepareToPlay(double sampleRate, int samplesPerBlock) override;
    void releaseResources() override;
    void processBlock(juce::AudioBuffer<float>&, juce::MidiBuffer&) override;

    // State management
    void getStateInformation(juce::MemoryBlock& destData) override;
    void setStateInformation(const void* data, int sizeInBytes) override;

    // The synthesis engine
    std::unique_ptr<SurgeSynthesizer> surge;
};
```

**Why Multiple Inheritance?**

- `AudioProcessor`: Core JUCE plugin functionality
- `VST3ClientExtensions`: VST3-specific features (context menus, etc.)
- `clap_properties`: CLAP-specific capabilities (note expressions, remote controls)
- `PluginLayer`: Callback interface from SurgeSynthesizer to processor
- `MidiKeyboardState::Listener`: Virtual keyboard integration

### Bus Configuration

Surge XT declares its audio input/output configuration in the constructor:

```cpp
// From: src/surge-xt/SurgeSynthProcessor.cpp
SurgeSynthProcessor::SurgeSynthProcessor()
    : juce::AudioProcessor(BusesProperties()
                               .withOutput("Output", juce::AudioChannelSet::stereo(), true)
                               .withInput("Sidechain", juce::AudioChannelSet::stereo(), true)
                               .withOutput("Scene A", juce::AudioChannelSet::stereo(), false)
                               .withOutput("Scene B", juce::AudioChannelSet::stereo(), false))
{
    // Constructor implementation...
}
```

**Bus Layout:**

1. **Main Output** (required, stereo): Mixed output from both scenes
2. **Sidechain Input** (optional, stereo): For audio input processing
3. **Scene A Output** (optional, stereo): Isolated Scene A signal
4. **Scene B Output** (optional, stereo): Isolated Scene B signal

The `isBusesLayoutSupported()` method validates host configurations:

```cpp
// From: src/surge-xt/SurgeSynthProcessor.cpp
bool SurgeSynthProcessor::isBusesLayoutSupported(const BusesLayout& layouts) const
{
    auto mocs = layouts.getMainOutputChannelSet();
    auto mics = layouts.getMainInputChannelSet();

    // Output must be stereo or disabled
    auto outputValid = (mocs == juce::AudioChannelSet::stereo()) || (mocs.isDisabled());

    // Input can be stereo, mono, or disabled
    auto inputValid = (mics == juce::AudioChannelSet::stereo()) ||
                      (mics == juce::AudioChannelSet::mono()) || (mics.isDisabled());

    // Scene outputs must be 0 or 2 channels each
    auto c1 = layouts.getNumChannels(false, 1);
    auto c2 = layouts.getNumChannels(false, 2);
    auto sceneOut = (c1 == 0 || c1 == 2) && (c2 == 0 || c2 == 2);

    return outputValid && inputValid && sceneOut;
}
```

### The ProcessBlock Contract

The heart of any audio plugin is `processBlock()`, called by the host for each audio buffer:

```cpp
// From: src/surge-xt/SurgeSynthProcessor.cpp
void SurgeSynthProcessor::processBlock(juce::AudioBuffer<float>& buffer,
                                       juce::MidiBuffer& midiMessages)
{
    // FPU state guard for consistent floating-point behavior
    auto fpuguard = sst::plugininfra::cpufeatures::FPUStateGuard();

    if (!surge)
    {
        buffer.clear();
        return;
    }

    // Handle bypass mode
    if (bypassParameter->getValue() > 0.5)
    {
        if (priorCallWasProcessBlockNotBypassed)
        {
            surge->stopSound();
            bypassCountdown = 8; // Fade out gracefully
        }

        if (bypassCountdown == 0)
            return;

        bypassCountdown--;
        surge->audio_processing_active = false;
        priorCallWasProcessBlockNotBypassed = false;
        midiMessages.clear();
    }

    surge->audio_processing_active = true;

    // Extract bus buffers
    auto mainOutput = getBusBuffer(buffer, false, 0);
    auto mainInput = getBusBuffer(buffer, true, 0);
    auto sceneAOutput = getBusBuffer(buffer, false, 1);
    auto sceneBOutput = getBusBuffer(buffer, false, 2);

    // Process sample by sample, calling surge->process() every BLOCK_SIZE samples
    // (Full implementation shown in next section)
}
```

**Critical Details:**

1. **FPU State Guard**: Ensures consistent floating-point rounding modes across platforms
2. **Bypass Handling**: Gracefully stops all voices with a countdown
3. **Bus Buffer Extraction**: Separates main, sidechain, and scene outputs
4. **Block-Size Adaptation**: Bridges between host buffer size and Surge's fixed BLOCK_SIZE

### Parameter Handling

Surge exposes 553+ parameters to the host through JUCE's parameter system. Each parameter is wrapped in an adapter class:

```cpp
// From: src/surge-xt/SurgeSynthProcessor.h
struct SurgeParamToJuceParamAdapter : SurgeBaseParam
{
    explicit SurgeParamToJuceParamAdapter(SurgeSynthProcessor* jp, Parameter* p);

    juce::String getName(int i) const override {
        return SurgeParamToJuceInfo::getParameterName(s, p);
    }

    float getValue() const override {
        return s->getParameter01(s->idForParameter(p));
    }

    void setValue(float f) override {
        if (!inEditGesture)
            s->setParameter01(s->idForParameter(p), f, true);
    }

    juce::String getText(float normalisedValue, int i) const override {
        return p->get_display(true, normalisedValue);
    }

    SurgeSynthesizer* s{nullptr};
    Parameter* p{nullptr};
    std::atomic<bool> inEditGesture{false};
};
```

**Parameter Organization:**

Parameters are grouped into categories for better host integration:

```cpp
// From: src/surge-xt/SurgeSynthProcessor.cpp (constructor)
auto parent = std::make_unique<juce::AudioProcessorParameterGroup>("Root", "Root", "|");
auto macroG = std::make_unique<juce::AudioProcessorParameterGroup>("macros", "Macros", "|");

// Add 8 macro parameters
for (int mn = 0; mn < n_customcontrollers; ++mn)
{
    auto nm = std::make_unique<SurgeMacroToJuceParamAdapter>(this, mn);
    macrosById.push_back(nm.get());
    macroG->addChild(std::move(nm));
}

// Group parameters by clump (Global, Scene A Oscillators, etc.)
std::map<unsigned int, std::vector<std::unique_ptr<juce::AudioProcessorParameter>>> parByGroup;

for (auto par : surge->storage.getPatch().param_ptr)
{
    if (par)
    {
        parametermeta pm;
        surge->getParameterMeta(surge->idForParameter(par), pm);
        auto sja = std::make_unique<SurgeParamToJuceParamAdapter>(this, par);
        paramsByID[surge->idForParameter(par)] = sja.get();
        parByGroup[pm.clump].push_back(std::move(sja));
    }
}
```

**Clump Names** map to user-friendly categories:

```cpp
// From: src/surge-xt/SurgeSynthProcessor.cpp
std::string SurgeSynthProcessor::paramClumpName(int clumpid)
{
    switch (clumpid)
    {
    case 1: return "Macros";
    case 2: return "Global & FX";
    case 3: return "A Common";
    case 4: return "A Oscillators";
    case 5: return "A Mixer";
    case 6: return "A Filters";
    case 7: return "A Envelopes";
    case 8: return "A LFOs";
    case 9: return "B Common";
    case 10: return "B Oscillators";
    case 11: return "B Mixer";
    case 12: return "B Filters";
    case 13: return "B Envelopes";
    case 14: return "B LFOs";
    }
    return "";
}
```

## 2. SurgeSynthProcessor: The Integration Layer

### Architecture Overview

`SurgeSynthProcessor` is the glue between JUCE's plugin framework and Surge's synthesis engine. It handles:

- **Threading**: Bridging between audio thread (processBlock) and UI thread (editor)
- **Buffer Management**: Converting between host buffer sizes and Surge's BLOCK_SIZE
- **MIDI Processing**: Sample-accurate event handling
- **State Serialization**: Saving/loading patches
- **Parameter Automation**: Host → engine parameter flow

```cpp
// From: src/surge-xt/SurgeSynthProcessor.h
class SurgeSynthProcessor : public juce::AudioProcessor,
                            public SurgeSynthesizer::PluginLayer
{
public:
    // The synthesis engine (owned by the processor)
    std::unique_ptr<SurgeSynthesizer> surge;

    // Parameter mappings
    std::unordered_map<SurgeSynthesizer::ID, SurgeParamToJuceParamAdapter*> paramsByID;
    std::vector<SurgeMacroToJuceParamAdapter*> macrosById;

    // MIDI from GUI (virtual keyboard)
    LockFreeStack<midiR, 4096> midiFromGUI;

    // OSC (Open Sound Control) integration
    Surge::OSC::OpenSoundControl oscHandler;
    sst::cpputils::SimpleRingBuffer<oscToAudio, 4096> oscRingBuf;

    // Block processing state
    int blockPos = 0;  // Current position within BLOCK_SIZE
};
```

### Threading Model

Surge XT operates on multiple threads simultaneously:

**1. Audio Thread** (real-time, highest priority):
```cpp
// Called by the host, must never block or allocate
void processBlock(juce::AudioBuffer<float>& buffer, juce::MidiBuffer& midiMessages)
{
    // Sample-accurate processing
    for (int i = 0; i < buffer.getNumSamples(); i++)
    {
        // Apply MIDI events at precise sample positions
        while (i == nextMidi)
        {
            applyMidi(*midiIt);
            midiIt++;
        }

        // Call surge->process() every BLOCK_SIZE samples
        if (blockPos == 0)
        {
            surge->process();
        }

        // Copy output
        *outL = surge->output[0][blockPos];
        *outR = surge->output[1][blockPos];

        blockPos = (blockPos + 1) & (BLOCK_SIZE - 1);
    }
}
```

**2. UI Thread** (message thread, normal priority):
```cpp
// User interactions, parameter changes from GUI
void SurgeGUIEditor::valueChanged(IComponentTagValue* control)
{
    // This runs on the message thread
    // Updates are queued to the audio thread via atomic operations
    synth->setParameter01(paramId, value, true);
}
```

**3. Background Threads** (for non-real-time operations):
- Patch loading from disk
- Wavetable analysis
- Tuning file loading
- OSC message handling

**Thread Safety Mechanisms:**

```cpp
// Lock-free MIDI queue from GUI to audio thread
LockFreeStack<midiR, 4096> midiFromGUI;

// Atomic parameter updates
std::atomic<bool> parameterNameUpdated{false};

// Patch loading mutex
std::mutex patchLoadSpawnMutex;
```

### Buffer Management and Block Size Adaptation

Hosts may call `processBlock()` with any buffer size (64, 128, 512, etc.), but Surge processes audio in fixed BLOCK_SIZE chunks (default: 32 samples). The processor bridges this mismatch:

```cpp
// From: src/surge-xt/SurgeSynthProcessor.cpp
void SurgeSynthProcessor::processBlock(juce::AudioBuffer<float>& buffer,
                                       juce::MidiBuffer& midiMessages)
{
    auto mainOutput = getBusBuffer(buffer, false, 0);
    auto mainInput = getBusBuffer(buffer, true, 0);

    // blockPos tracks position within the current BLOCK_SIZE
    for (int i = 0; i < buffer.getNumSamples(); i++)
    {
        // Every BLOCK_SIZE samples, call surge->process()
        if (blockPos == 0)
        {
            // Handle sidechain input
            if (incL && incR)
            {
                if (inputIsLatent)
                {
                    // Use latent buffer for non-aligned input
                    memcpy(&(surge->input[0][0]), inputLatentBuffer[0],
                           BLOCK_SIZE * sizeof(float));
                    memcpy(&(surge->input[1][0]), inputLatentBuffer[1],
                           BLOCK_SIZE * sizeof(float));
                }
                else
                {
                    // Direct copy for aligned input
                    auto inL = incL + i;
                    auto inR = incR + i;
                    memcpy(&(surge->input[0][0]), inL, BLOCK_SIZE * sizeof(float));
                    memcpy(&(surge->input[1][0]), inR, BLOCK_SIZE * sizeof(float));
                }
                surge->process_input = true;
            }

            // Generate BLOCK_SIZE samples
            surge->process();

            // Update time position
            surge->time_data.ppqPos +=
                (double)BLOCK_SIZE * surge->time_data.tempo /
                (60. * surge->storage.samplerate);
        }

        // Copy from latent buffer if needed
        if (inputIsLatent && incL && incR)
        {
            inputLatentBuffer[0][blockPos] = incL[i];
            inputLatentBuffer[1][blockPos] = incR[i];
        }

        // Copy output sample
        *outL = surge->output[0][blockPos];
        *outR = surge->output[1][blockPos];

        // Handle scene outputs if enabled
        if (surge->activateExtraOutputs)
        {
            if (sceneAOutput.getNumChannels() == 2)
            {
                *sAL = surge->sceneout[0][0][blockPos];
                *sAR = surge->sceneout[0][1][blockPos];
            }
            if (sceneBOutput.getNumChannels() == 2)
            {
                *sBL = surge->sceneout[1][0][blockPos];
                *sBR = surge->sceneout[1][1][blockPos];
            }
        }

        blockPos = (blockPos + 1) & (BLOCK_SIZE - 1);
    }
}
```

**Input Latency Handling:**

When the host buffer size is not a multiple of BLOCK_SIZE, Surge enables "latent input" mode, which delays sidechain input by one block to maintain alignment:

```cpp
// From: src/surge-xt/SurgeSynthProcessor.cpp
auto sc = buffer.getNumSamples();
if (!inputIsLatent && (sc & ~(BLOCK_SIZE - 1)) != sc)
{
    surge->storage.reportError(
        fmt::format("Incoming audio input block is not a multiple of {sz} samples.\n"
                    "If audio input is used, it will be delayed by {sz} samples, "
                    "in order to compensate.",
                    fmt::arg("sz", BLOCK_SIZE)),
        "Audio Input Latency Activated",
        SurgeStorage::AUDIO_INPUT_LATENCY_WARNING, false);
    inputIsLatent = true;
}
```

### Playhead and Timing

The processor synchronizes with the host's transport:

```cpp
// From: src/surge-xt/SurgeSynthProcessor.cpp
void SurgeSynthProcessor::processBlockPlayhead()
{
    auto playhead = getPlayHead();

    if (playhead && !(wrapperType == wrapperType_Standalone))
    {
        juce::AudioPlayHead::CurrentPositionInfo cp;
        playhead->getCurrentPosition(cp);

        surge->time_data.tempo = cp.bpm;

        // Only update position if actually playing
        if (cp.isPlaying || cp.isRecording)
        {
            surge->time_data.ppqPos = cp.ppqPosition;
        }

        surge->time_data.timeSigNumerator = cp.timeSigNumerator;
        surge->time_data.timeSigDenominator = cp.timeSigDenominator;
        surge->resetStateFromTimeData();
    }
    else
    {
        // Standalone mode: use internal tempo
        surge->time_data.tempo = standaloneTempo;
        surge->time_data.timeSigNumerator = 4;
        surge->time_data.timeSigDenominator = 4;
        surge->resetStateFromTimeData();
    }
}
```

**TimeData Structure:**

```cpp
struct TimeData
{
    double tempo{120.0};           // BPM
    double ppqPos{0.0};            // Quarter notes since start
    int timeSigNumerator{4};       // Top number of time signature
    int timeSigDenominator{4};     // Bottom number
};
```

This data drives:
- Tempo-synced LFOs
- Arpeggiator timing
- Delay sync
- Step sequencer playback

## 3. Plugin Formats

### VST3 Integration

VST3 (Virtual Studio Technology 3) is Steinberg's cross-platform plugin standard. JUCE handles most VST3 details, but Surge implements VST3-specific extensions:

```cpp
// From: src/surge-xt/SurgeSynthProcessor.h
class SurgeSynthProcessor : public juce::AudioProcessor,
                            public juce::VST3ClientExtensions
{
    // VST3ClientExtensions provides:
    // - getVST3ClientExtensions() for custom capabilities
};
```

**VST3 Configuration** (from CMakeLists.txt):

```cmake
# From: src/surge-xt/CMakeLists.txt
juce_add_plugin(surge-xt
    VST3_CATEGORIES Instrument Synth
    VST3_AUTO_MANIFEST FALSE

    PLUGIN_MANUFACTURER_CODE VmbA  # Vember Audio
    PLUGIN_CODE SgXT
)
```

**Manufacturer Code**: `VmbA` preserves compatibility with original Surge patches
**Plugin Code**: `SgXT` uniquely identifies Surge XT in VST3 hosts

**VST3 Context Menus:**

Some hosts (like Cubase) support VST3 context menus for parameter editing. Surge detects this capability:

```cpp
#if EXISTS juce_audio_processors/processors/juce_AudioProcessorEditorHostContext.h
  set(SURGE_JUCE_HOST_CONTEXT TRUE)
  message(STATUS "Including JUCE VST3 host-side context menu support...")
#endif
```

### Audio Unit (macOS)

Audio Unit is Apple's native plugin format, deeply integrated with macOS and Logic Pro.

**AU Configuration:**

```cmake
# From: src/surge-xt/CMakeLists.txt
juce_add_plugin(surge-xt
    AU_MAIN_TYPE kAudioUnitType_MusicDevice
    AU_SANDBOX_SAFE TRUE
)
```

**Key AU Details:**

- `kAudioUnitType_MusicDevice`: Identifies Surge as an instrument (not effect)
- `AU_SANDBOX_SAFE`: Complies with macOS sandboxing for App Store distribution

**AU Preset Handling:**

Audio Unit has its own preset format (`.aupreset`). JUCE automatically maps between AU presets and Surge's internal patch format through the `getStateInformation()` / `setStateInformation()` interface.

**AU-Specific Features:**

1. **Parameter Units**: AU supports units (Hz, dB, ms) which JUCE derives from parameter display strings
2. **Manufacturer Preset Bank**: Factory patches appear in Logic's preset browser
3. **AUHostIdentifier**: Logic and GarageBand identification for AU-specific workarounds

### CLAP (CLever Audio Plugin)

CLAP is a modern, open-source plugin format designed by the audio software community to address limitations in VST3 and AU.

**Why CLAP?**

- **Open Source**: No licensing fees or proprietary SDKs
- **Modern Features**: Note expressions, polyphonic modulation, preset discovery
- **Performance**: Direct processing path without JUCE overhead
- **Community-Driven**: Designed by plugin developers for plugin developers

**CLAP Integration:**

Surge uses `clap-juce-extensions` to combine JUCE's cross-platform framework with CLAP's advanced features:

```cpp
// From: src/surge-xt/SurgeSynthProcessor.h
#if HAS_CLAP_JUCE_EXTENSIONS
class SurgeSynthProcessor : public clap_juce_extensions::clap_properties,
                            public clap_juce_extensions::clap_juce_audio_processor_capabilities
{
    // CLAP direct processing (bypasses JUCE)
    bool supportsDirectProcess() override { return true; }
    clap_process_status clap_direct_process(const clap_process* process) noexcept override;

    // CLAP voice info
    bool supportsVoiceInfo() override { return true; }
    bool voiceInfoGet(clap_voice_info* info) override {
        info->voice_capacity = 128;
        info->voice_count = 128;
        info->flags = CLAP_VOICE_INFO_SUPPORTS_OVERLAPPING_NOTES;
        return true;
    }

    // CLAP preset discovery
    bool supportsPresetLoad() const noexcept override { return true; }
    bool presetLoadFromLocation(uint32_t location_kind, const char* location,
                                const char* load_key) noexcept override;
};
#endif
```

**CLAP Configuration:**

```cmake
# From: src/surge-xt/CMakeLists.txt
if(SURGE_BUILD_CLAP)
  clap_juce_extensions_plugin(TARGET surge-xt
      CLAP_ID "org.surge-synth-team.surge-xt"
      CLAP_SUPPORTS_CUSTOM_FACTORY 1
      CLAP_FEATURES "instrument" "synthesizer" "stereo" "free and open source")
endif()
```

**Direct CLAP Processing:**

For optimal performance, Surge implements `clap_direct_process()`, which bypasses JUCE's buffer conversion:

```cpp
// From: src/surge-xt/SurgeSynthProcessor.cpp
#if HAS_CLAP_JUCE_EXTENSIONS
clap_process_status SurgeSynthProcessor::clap_direct_process(const clap_process* process) noexcept
{
    auto fpuguard = sst::plugininfra::cpufeatures::FPUStateGuard();

    if (process->audio_outputs_count == 0 || process->audio_outputs_count > 3)
        return CLAP_PROCESS_ERROR;

    surge->audio_processing_active = true;

    // Get output pointers directly from CLAP
    float* outL{nullptr}, *outR{nullptr};
    outL = process->audio_outputs[0].data32[0];
    outR = outL;
    if (process->audio_outputs[0].channel_count == 2)
        outR = process->audio_outputs[0].data32[1];

    // Process events
    auto ev = process->in_events;
    auto evtsz = ev->size(ev);

    for (int s = 0; s < process->frames_count; ++s)
    {
        // Process CLAP events (notes, parameters, note expressions)
        while (nextevtime >= 0 && nextevtime < s + BLOCK_SIZE && currev < evtsz)
        {
            auto evt = ev->get(ev, currev);
            process_clap_event(evt);
            currev++;
        }

        // Generate audio
        if (blockPos == 0)
        {
            surge->process();
        }

        *outL = surge->output[0][blockPos];
        *outR = surge->output[1][blockPos];
        outL++;
        outR++;

        blockPos = (blockPos + 1) & (BLOCK_SIZE - 1);
    }

    return CLAP_PROCESS_CONTINUE;
}
#endif
```

**CLAP Note Expressions:**

CLAP supports per-note modulation of pitch, volume, pan, pressure, and timbre:

```cpp
// From: src/surge-xt/SurgeSynthProcessor.cpp
case CLAP_EVENT_NOTE_EXPRESSION:
{
    auto pevt = reinterpret_cast<const clap_event_note_expression*>(evt);
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
break;
```

**CLAP Preset Discovery:**

CLAP hosts can discover and index presets without loading the plugin:

```cpp
// From: src/surge-xt/SurgeCLAPPresetDiscovery.cpp
struct PresetProvider
{
    bool init()
    {
        storage = std::make_unique<SurgeStorage>(config);

        // Declare file types
        auto fxp = clap_preset_discovery_filetype{"Surge XT Patch", "", "fxp"};
        indexer->declare_filetype(indexer, &fxp);

        // Declare preset locations
        if (fs::is_directory(storage->datapath / "patches_factory"))
        {
            auto factory = clap_preset_discovery_location{
                CLAP_PRESET_DISCOVERY_IS_FACTORY_CONTENT,
                "Surge XT Factory Presets",
                CLAP_PRESET_DISCOVERY_LOCATION_FILE,
                (storage->datapath / "patches_factory").u8string().c_str()
            };
            indexer->declare_location(indexer, &factory);
        }

        return true;
    }

    bool get_metadata(uint32_t location_kind, const char* location,
                      const clap_preset_discovery_metadata_receiver_t* rcv)
    {
        // Parse FXP file and extract metadata (name, author, category)
        // without loading the entire synthesis engine
    }
};
```

**CLAP Remote Controls:**

CLAP hosts like Bitwig can map hardware controllers to plugin parameters. Surge exposes predefined control pages:

```cpp
// From: src/surge-xt/SurgeSynthProcessor.cpp
uint32_t SurgeSynthProcessor::remoteControlsPageCount() noexcept
{
    return 5; // Macros + Scene A/B Mixer + Scene A/B Filters
}

bool SurgeSynthProcessor::remoteControlsPageFill(
    uint32_t pageIndex, juce::String& sectionName, uint32_t& pageID,
    juce::String& pageName,
    std::array<juce::AudioProcessorParameter*, CLAP_REMOTE_CONTROLS_COUNT>& params) noexcept
{
    switch (pageIndex)
    {
    case 0: // Macros
        sectionName = "Global";
        pageName = "Macros";
        for (int i = 0; i < CLAP_REMOTE_CONTROLS_COUNT && i < macrosById.size(); ++i)
            params[i] = macrosById[i];
        break;

    case 1: // Scene A Mixer
        sectionName = "Scene A";
        pageName = "Scene A Mixer";
        auto& sc = surge->storage.getPatch().scene[0];
        params[0] = paramsByID[surge->idForParameter(&sc.level_o1)];
        params[1] = paramsByID[surge->idForParameter(&sc.level_o2)];
        params[2] = paramsByID[surge->idForParameter(&sc.level_o3)];
        params[4] = paramsByID[surge->idForParameter(&sc.level_noise)];
        // ...
        break;
    }
    return true;
}
```

### LV2 (Linux Audio Plugin)

LV2 is the standard plugin format for Linux audio applications (Ardour, Qtractor, Carla).

**LV2 Configuration:**

```cmake
# From: src/surge-xt/CMakeLists.txt
juce_add_plugin(surge-xt
    LV2_URI https://surge-synthesizer.github.io/lv2/surge-xt
    LV2_SHARED_LIBRARY_NAME SurgeXT
)
```

**LV2 Features:**

JUCE handles most LV2 implementation details, including:
- State serialization (using Turtle RDF)
- MIDI input
- Worker threads for background tasks
- Time/position information from host

**LV2 Challenges:**

Unlike VST3/AU/CLAP, LV2 has limited adoption outside Linux. The main challenges are:
- Inconsistent preset directory standards across hosts
- Varying levels of feature support (some hosts don't support all LV2 extensions)
- Limited debugging tools compared to commercial formats

### Standalone Application

The standalone version wraps Surge in a JUCE application window:

```cpp
// JUCE automatically generates surge-xt_Standalone target
// From: juce_add_plugin() with FORMATS including "Standalone"
```

**Standalone Features:**

1. **Built-in Audio/MIDI Settings**: Device selection, buffer size, sample rate
2. **Virtual Keyboard**: On-screen MIDI input
3. **File Menu**: Save/load patches independently
4. **Integrated CLI**: macOS standalone includes command-line interface

**macOS CLI Integration:**

```cmake
# From: src/surge-xt/CMakeLists.txt (macOS only)
if(APPLE)
  add_dependencies(${PROJECT_NAME}_Standalone ${PROJECT_NAME}-cli)
  add_custom_command(
    TARGET ${PROJECT_NAME}_Standalone
    POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy "${cliexe}"
            "${saname}/Surge XT.app/Contents/MacOS"
  )
endif()
```

Users can run `Surge XT.app/Contents/MacOS/surge-xt-cli` for headless synthesis, testing, and patch conversion.

## 4. Parameter Automation

### Host Automation

DAWs automate parameters by recording and playing back parameter changes over time. Surge exposes 553+ parameters to the host through JUCE's `AudioProcessorParameter` system.

**Parameter Flow:**

```
Host Automation → JUCE Parameter → SurgeParamToJuceParamAdapter →
SurgeSynthesizer → Parameter → DSP Processing
```

**From Host to Engine:**

```cpp
// From: src/surge-xt/SurgeSynthProcessor.cpp
void SurgeParamToJuceParamAdapter::setValue(float f)
{
    auto matches = (f == getValue());
    if (!matches && !inEditGesture)
    {
        s->setParameter01(s->idForParameter(p), f, true);
        ssp->paramChangeToListeners(p);
    }
}
```

**From Engine to Host:**

When parameters change from the UI or modulation, the engine notifies the processor, which updates the host:

```cpp
// From: src/surge-xt/SurgeSynthProcessor.cpp (implements PluginLayer)
void SurgeSynthProcessor::surgeParameterUpdated(const SurgeSynthesizer::ID& id, float f)
{
    auto spar = paramsByID[id];
    if (spar)
    {
        spar->setValueNotifyingHost(f);
    }
}

void SurgeSynthProcessor::surgeMacroUpdated(const long id, float f)
{
    auto spar = macrosById[id];
    if (spar)
        spar->setValueNotifyingHost(f);
}
```

### Parameter Mapping

Each Parameter in Surge has metadata describing how it maps to the normalized [0, 1] range:

```cpp
// From: src/common/Parameter.h
struct Parameter
{
    pdata val;           // Current value (int, float, or bool)
    pdata val_min;       // Minimum value
    pdata val_max;       // Maximum value
    pdata val_default;   // Default value

    int valtype;         // vt_int, vt_float, vt_bool

    // Conversion functions
    float value_to_normalized(float value);
    float normalized_to_value(float normalized);

    // Display formatting
    char* get_display(bool external = false, float ef = 0.f);
};
```

**Mapping Examples:**

**Linear Float** (Filter Cutoff):
```cpp
// Range: -60 to 70 semitones relative to MIDI note
normalized = (value - val_min.f) / (val_max.f - val_min.f);
value = val_min.f + normalized * (val_max.f - val_min.f);
```

**Integer** (Oscillator Type):
```cpp
// Range: 0 to 12 (oscillator algorithms)
normalized = (float)value / (float)val_max.i;
value = (int)(normalized * val_max.i + 0.5);
```

**Boolean** (Temposync):
```cpp
// 0 = off, 1 = on
normalized = value ? 1.0f : 0.0f;
value = normalized > 0.5f;
```

**Special Curves** (Envelope Attack):
```cpp
// Exponential curve for perceptually linear time
// Short attacks need fine control, long attacks less so
float normalized_to_value(float normalized)
{
    // Cubic mapping: normalized^3 for exponential feel
    float cubic = normalized * normalized * normalized;
    return val_min.f + cubic * (val_max.f - val_min.f);
}
```

### Smoothing and Interpolation

To prevent zipper noise (audible stepping when parameters change), Surge smooths parameter changes:

**Block-Rate Smoothing:**

Most parameters update once per block (every 32 samples):

```cpp
// From: src/common/dsp/SurgeVoice.cpp
void SurgeVoice::update_portamento()
{
    // Calculate target pitch from current note
    float target_pitch = /* ... */;

    // Smooth to target over portamento time
    state.pitch += (target_pitch - state.pitch) * portamento_rate;
}
```

**Sample-Accurate Smoothing:**

Critical parameters (like filter cutoff during modulation) use per-sample interpolation:

```cpp
// Linear interpolation between blocks
for (int i = 0; i < BLOCK_SIZE; ++i)
{
    float t = (float)i / BLOCK_SIZE;
    float smoothed = lastValue + (targetValue - lastValue) * t;
    // Use smoothed value for this sample
}
```

**Macro Smoothing:**

Macros use dedicated smoothing to prevent sudden jumps:

```cpp
// From: src/common/SurgeSynthesizer.h
void setMacroParameter01(long macroNum, float value)
{
    // Set target, actual value smooths towards it
    storage.getPatch().param_ptr[n_global_params + macroNum]->set_value_f01(value);
}
```

### Automation Recording

When a host records automation, it captures parameter changes from:

1. **UI Edits**: User dragging sliders, clicking buttons
2. **MIDI CC**: MIDI controllers mapped to parameters
3. **Modulation**: LFO, envelope, or other modulation sources

**Edit Gestures:**

Surge signals when a parameter edit begins and ends:

```cpp
// From: src/surge-xt/gui/widgets/ModulatableSlider.cpp
void ModulatableSlider::mouseDown(const juce::MouseEvent& event)
{
    if (pTag && pTag->isEditable())
    {
        auto sge = firstListenerOfType<SurgeGUIEditor>();
        if (sge)
        {
            sge->sliderBeganEdit(this);  // Tells host: automation started
        }
    }
    // Start dragging...
}

void ModulatableSlider::mouseUp(const juce::MouseEvent& event)
{
    auto sge = firstListenerOfType<SurgeGUIEditor>();
    if (sge)
    {
        sge->sliderEndedEdit(this);  // Tells host: automation ended
    }
}
```

This maps to JUCE's automation system:

```cpp
void beginEdit()  // Start of automation gesture
void endEdit()    // End of automation gesture
void setValue()   // Intermediate values during gesture
```

Hosts use this to:
- Create automation lanes
- Set undo points
- Thin automation data (remove redundant points)

## 5. State Management

### The Patch Format

Surge stores its complete state in a binary format based on the VST2 FXP (preset) and FXB (bank) specification. Each patch contains:

1. **FXP Header** (56 bytes): Magic numbers, version, plugin ID
2. **Patch Header** (8 bytes): XML size and tag
3. **XML Data** (variable): Human-readable parameter values
4. **Stepsequencer Data** (binary): 16-step sequences for 3 scenes × 6 LFOs

**Patch Structure:**

```cpp
// From: libs/surge-juce-extensions/src/common/PatchFileHeaderStructs.h
namespace sst::io
{
    struct fxChunkSetCustom
    {
        int32_t chunkMagic;      // 'CcnK' (0x4B6E6343)
        int32_t byteSize;        // Total size
        int32_t fxMagic;         // 'FPCh' (chunk data follows)
        int32_t version;         // Format version
        int32_t fxID;            // 'cjs3' (Claes Johanson Surge 3)
        int32_t fxVersion;       // Plugin version
        int32_t numPrograms;     // Number of presets (1 for FXP)
        char prgName[28];        // Preset name
        int32_t chunkSize;       // Size of data that follows
        // Followed by chunk data
    };

    struct patch_header
    {
        char tag[4];             // 'sub3'
        int32_t xmlsize;         // Size of XML data
        // Followed by XML string
    };
}
```

### getStateInformation(): Serializing State

When a host saves a project, it calls `getStateInformation()` to get the plugin's complete state:

```cpp
// From: src/surge-xt/SurgeSynthProcessor.cpp
void SurgeSynthProcessor::getStateInformation(juce::MemoryBlock& destData)
{
    if (!surge)
        return;

    // Populate extra state (window position, zoom, etc.)
    surge->populateDawExtraState();

    // If editor exists, capture its state too
    auto sse = dynamic_cast<SurgeSynthEditor*>(getActiveEditor());
    if (sse)
    {
        sse->populateForStreaming(surge.get());
    }

    // Serialize to binary
    void* data = nullptr;  // Surge owns this memory
    unsigned int stateSize = surge->saveRaw(&data);

    // Copy to JUCE MemoryBlock (which will be saved by the host)
    destData.setSize(stateSize);
    destData.copyFrom(data, 0, stateSize);
}
```

**What Gets Saved:**

- All 553+ parameter values
- Modulation routings (source → target → depth)
- Step sequencer patterns
- Wavetable selections
- FX routing
- Tuning scale/keyboard mapping
- Scene mode (single, split, dual, channel split)
- Macro assignments and names
- DAW extra state (zoom level, window size, open overlays)

**saveRaw() Implementation:**

```cpp
// From: src/common/SurgeSynthesizerIO.cpp
unsigned int SurgeSynthesizer::saveRaw(void** data)
{
    // 1. Convert patch to XML
    TiXmlDocument doc;
    auto root = doc.NewElement("patch");
    root->SetAttribute("revision", ff_revision);

    // 2. Save metadata
    auto meta = doc.NewElement("meta");
    meta->SetAttribute("name", storage.getPatch().name.c_str());
    meta->SetAttribute("category", storage.getPatch().category.c_str());
    meta->SetAttribute("author", storage.getPatch().author.c_str());
    root->InsertEndChild(meta);

    // 3. Save all parameters
    for (int i = 0; i < n_total_params; i++)
    {
        if (storage.getPatch().param_ptr[i])
        {
            auto p = doc.NewElement("param");
            p->SetAttribute("id", i);
            p->SetAttribute("value", storage.getPatch().param_ptr[i]->val.i);
            root->InsertEndChild(p);
        }
    }

    // 4. Convert XML to string
    TiXmlPrinter printer;
    doc.Accept(&printer);
    std::string xmlString = printer.CStr();

    // 5. Build FXP structure
    sst::io::fxChunkSetCustom fxp;
    fxp.chunkMagic = 'CcnK';
    fxp.fxMagic = 'FPCh';
    fxp.fxID = 'cjs3';
    // ... fill in other fields

    // 6. Allocate memory and copy data
    int totalSize = sizeof(fxp) + sizeof(patch_header) + xmlString.size() + stepdata;
    *data = malloc(totalSize);
    // ... copy FXP, XML, step data

    return totalSize;
}
```

### setStateInformation(): Deserializing State

When a host loads a project, it calls `setStateInformation()` with the previously saved data:

```cpp
// From: src/surge-xt/SurgeSynthProcessor.cpp
void SurgeSynthProcessor::setStateInformation(const void* data, int sizeInBytes)
{
    if (!surge)
        return;

    // Enqueue patch for loading (thread-safe)
    surge->enqueuePatchForLoad(data, sizeInBytes);

    // If audio thread isn't running, process immediately
    surge->processAudioThreadOpsWhenAudioEngineUnavailable();

    // Set flag to check for OSC startup
    if (surge->audio_processing_active)
    {
        oscCheckStartup = true;
    }
    else
    {
        tryLazyOscStartupFromStreamedState();
    }
}
```

**Thread-Safe Loading:**

Patch loading happens asynchronously to avoid blocking the message thread:

```cpp
// From: src/common/SurgeSynthesizer.cpp
void SurgeSynthesizer::enqueuePatchForLoad(const void* data, int size)
{
    std::lock_guard<std::mutex> mg(patchLoadSpawnMutex);

    // Copy data (it may be freed by the host after this call)
    enqueuedLoadData = std::make_unique<char[]>(size);
    memcpy(enqueuedLoadData.get(), data, size);
    enqueuedLoadSize = size;
}

void SurgeSynthesizer::processEnqueuedPatchIfNeeded()
{
    // Called from audio thread
    if (enqueuedLoadData)
    {
        std::lock_guard<std::mutex> mg(patchLoadSpawnMutex);
        loadRaw(enqueuedLoadData.get(), enqueuedLoadSize, false);
        enqueuedLoadData.reset();
        enqueuedLoadSize = 0;
    }
}
```

**loadRaw() Implementation:**

```cpp
// From: src/common/SurgeSynthesizerIO.cpp
void SurgeSynthesizer::loadRaw(const void* data, int size, bool preset)
{
    // 1. Stop all voices
    stopSound();

    // 2. Parse FXP header
    auto* fxp = reinterpret_cast<const sst::io::fxChunkSetCustom*>(data);
    if (fxp->chunkMagic != 'CcnK' || fxp->fxID != 'cjs3')
    {
        storage.reportError("Invalid patch file format", "Load Error");
        return;
    }

    // 3. Parse patch header
    auto* ph = reinterpret_cast<const sst::io::patch_header*>(
        static_cast<const char*>(data) + sizeof(sst::io::fxChunkSetCustom)
    );

    if (memcmp(ph->tag, "sub3", 4) != 0)
    {
        storage.reportError("Unsupported patch version", "Load Error");
        return;
    }

    // 4. Parse XML
    int xmlsize = ph->xmlsize;
    auto* xmldata = static_cast<const char*>(data) +
                    sizeof(sst::io::fxChunkSetCustom) + sizeof(sst::io::patch_header);

    TiXmlDocument doc;
    doc.Parse(xmldata, nullptr, TIXML_ENCODING_LEGACY);

    // 5. Load parameters from XML
    auto* patch = TINYXML_SAFE_TO_ELEMENT(doc.FirstChild("patch"));
    for (auto* param = patch->FirstChild("param"); param; param = param->NextSibling())
    {
        int id = std::atoi(param->Attribute("id"));
        float value = std::atof(param->Attribute("value"));

        if (id >= 0 && id < n_total_params)
        {
            storage.getPatch().param_ptr[id]->set_value_f01(value);
        }
    }

    // 6. Load step sequencer data
    // (Binary data follows XML)

    // 7. Rebuild voice state
    patchChanged = true;
    refresh_editor = true;
}
```

### Version Compatibility

Surge maintains backward compatibility with patches from all versions since 2004:

**Revision Tracking:**

```cpp
const int ff_revision = 16;  // Current format version

// From patch XML:
<patch revision="16">
```

**Migration Path:**

```cpp
void SurgeSynthesizer::loadRaw(const void* data, int size, bool preset)
{
    // ...after loading...

    int patchRevision = /* extract from XML */;

    if (patchRevision < ff_revision)
    {
        // Migrate old patches
        switch (patchRevision)
        {
        case 1:  // Original Surge 1.0
            migrateFromRev1();
            [[fallthrough]];
        case 2:  // Surge 1.1
            migrateFromRev2();
            [[fallthrough]];
        // ... continue through all revisions
        case 15:
            migrateFromRev15();
            break;
        }
    }
}
```

**Common Migrations:**

- **Rev 1 → 2**: Added wavetable display mode
- **Rev 7 → 8**: Added character parameter to filters
- **Rev 10 → 11**: Modern oscillator additions
- **Rev 14 → 15**: MSEG data format change
- **Rev 15 → 16**: Formula modulator integration

### DAW Extra State

Beyond the patch itself, Surge stores DAW-specific UI state:

```cpp
struct DAWExtraStateStorage
{
    bool isPopulated{false};

    // Window state
    int instanceZoomFactor{100};
    std::pair<int, int> instanceWindowSizeW{-1, -1};
    std::pair<int, int> instanceWindowSizeH{-1, -1};

    // Overlays
    bool activeOverlaysOpenAtStreamTime[n_overlay_types];

    // Modulation editor
    int modulationEditorState{0};

    // Tuning editor
    bool tuningOverlayOpen{false};

    // Patch browser
    bool patchBrowserOpen{false};
};
```

This ensures that when you reopen a project, windows are sized correctly and overlays are in the same state.

## 6. Preset Handling

### Program Change vs. State

Audio plugins support two types of preset systems:

**1. getNumPrograms() / setCurrentProgram():**

```cpp
// From: src/surge-xt/SurgeSynthProcessor.cpp
int SurgeSynthProcessor::getNumPrograms()
{
#ifdef SURGE_EXPOSE_PRESETS
    return presetOrderToPatchList.size() + 1;  // +1 for "INIT"
#else
    return 1;  // Only current state
#endif
}

int SurgeSynthProcessor::getCurrentProgram()
{
#ifdef SURGE_EXPOSE_PRESETS
    return juceSidePresetId;
#else
    return 0;
#endif
}

void SurgeSynthProcessor::setCurrentProgram(int index)
{
#ifdef SURGE_EXPOSE_PRESETS
    if (index > 0 && index <= presetOrderToPatchList.size())
    {
        juceSidePresetId = index;
        surge->patchid_queue = presetOrderToPatchList[index - 1];
    }
#endif
}

const juce::String SurgeSynthProcessor::getProgramName(int index)
{
#ifdef SURGE_EXPOSE_PRESETS
    if (index == 0)
        return "INIT";
    index--;
    if (index < 0 || index >= presetOrderToPatchList.size())
        return "RANGE ERROR";
    auto patch = surge->storage.patch_list[presetOrderToPatchList[index]];
    auto res = surge->storage.patch_category[patch.category].name + "/" + patch.name;
    return res;
#else
    return "";
#endif
}
```

**When SURGE_EXPOSE_PRESETS is Defined:**

- Hosts see all factory presets as "programs"
- Changing programs loads different patches
- Useful for: Standalone app, some hosts without good preset browsers

**When Disabled (Default):**

- Host only sees current state
- Presets managed through Surge's internal browser
- More flexible: user patches, favorites, search, tags

**2. getStateInformation() / setStateInformation():**

This is the modern approach. Presets are just saved states:

- **Factory Presets**: Surge ships with .fxp files on disk
- **User Presets**: Saved to user directory
- **DAW Presets**: Host saves state into project files

### VST3 Presets

VST3 has a `.vstpreset` format, which is essentially a zip file containing:

- `VST3 Preset.fxp`: The plugin state (from getStateInformation)
- `plugin.xml`: Metadata (name, author, category)

JUCE automatically handles the conversion:

```
User clicks "Save VST3 Preset"
  ↓
Host calls getStateInformation()
  ↓
JUCE creates .vstpreset with FXP data
  ↓
Host saves .vstpreset to disk
```

### AU Presets

Audio Unit uses `.aupreset` files (XML property lists):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
    "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>AU version</key>
    <integer>0</integer>
    <key>name</key>
    <string>My Surge Patch</string>
    <key>data</key>
    <data>
        <!-- Base64-encoded result of getStateInformation() -->
    </data>
</dict>
</plist>
```

Logic Pro and GarageBand automatically discover `.aupreset` files in:
- `~/Library/Audio/Presets/Surge Synth Team/Surge XT/`

### Cross-Format Compatibility

All formats ultimately use the same underlying patch format:

```
.fxp (Surge native)
  ↕ (same binary data)
VST3 .vstpreset (FXP wrapped in zip)
  ↕ (same binary data, different encoding)
AU .aupreset (FXP as base64 in XML)
  ↕ (same binary data, different encoding)
CLAP preset load (direct file path)
```

**Converting Between Formats:**

Users can:
1. Save a patch in Surge's browser (creates .fxp)
2. Load that same .fxp in any format (VST3, AU, CLAP, Standalone)
3. Save as host-specific preset if desired

**Preset Metadata:**

```cpp
// From patch XML
<meta
    name="Patch Name"
    category="Lead"
    author="Sound Designer"
    comment="Description of this patch"
    license="CC-BY-4.0"
/>
```

This metadata is preserved across all formats.

## 7. MIDI Routing

### MIDI Input Handling

MIDI events arrive in the `processBlock()` MIDI buffer, timestamped to sample accuracy:

```cpp
// From: src/surge-xt/SurgeSynthProcessor.cpp
void SurgeSynthProcessor::processBlock(juce::AudioBuffer<float>& buffer,
                                       juce::MidiBuffer& midiMessages)
{
    // Find first MIDI event
    auto midiIt = midiMessages.findNextSamplePosition(0);
    int nextMidi = -1;

    if (midiIt != midiMessages.cend())
    {
        nextMidi = (*midiIt).samplePosition;
    }

    for (int i = 0; i < buffer.getNumSamples(); i++)
    {
        // Process all MIDI events at this sample position
        while (i == nextMidi)
        {
            applyMidi(*midiIt);
            midiIt++;

            if (midiIt == midiMessages.cend())
                nextMidi = -1;
            else
                nextMidi = (*midiIt).samplePosition;
        }

        // Generate audio sample...
    }
}
```

**Sample-Accurate Timing:**

If a buffer contains 128 samples and a note-on occurs at sample 64, Surge:
1. Generates samples 0-63 with previous voice state
2. Triggers the note at sample 64
3. Generates samples 64-127 with the new voice

This precision is crucial for:
- Tight rhythmic performance
- Low-latency triggering
- Accurate arpeggiator timing

### applyMidi() Implementation

```cpp
// From: src/surge-xt/SurgeSynthProcessor.cpp
void SurgeSynthProcessor::applyMidi(const juce::MidiMessage& m)
{
    const int ch = m.getChannel() - 1;  // JUCE uses 1-16, Surge uses 0-15

    // Update virtual keyboard state
    juce::ScopedValueSetter<bool> midiAdd(isAddingFromMidi, true);
    midiKeyboardState.processNextMidiEvent(m);

    if (m.isNoteOn())
    {
        if (m.getVelocity() != 0)
            surge->playNote(ch, m.getNoteNumber(), m.getVelocity(), 0, -1);
        else
            surge->releaseNote(ch, m.getNoteNumber(), m.getVelocity(), -1);
    }
    else if (m.isNoteOff())
    {
        surge->releaseNote(ch, m.getNoteNumber(), m.getVelocity());
    }
    else if (m.isChannelPressure())
    {
        int atval = m.getChannelPressureValue();
        surge->channelAftertouch(ch, atval);
    }
    else if (m.isAftertouch())
    {
        int atval = m.getAfterTouchValue();
        surge->polyAftertouch(ch, m.getNoteNumber(), atval);
    }
    else if (m.isPitchWheel())
    {
        int pwval = m.getPitchWheelValue() - 8192;  // Convert to ±8192
        surge->pitchBend(ch, pwval);
    }
    else if (m.isController())
    {
        surge->channelController(ch, m.getControllerNumber(), m.getControllerValue());
    }
    else if (m.isProgramChange())
    {
        surge->programChange(ch, m.getProgramChangeNumber());
    }
}
```

### Sysex Support

System Exclusive messages allow MIDI devices to send custom data. Surge supports:

**Tuning Sysex:**

- **MTS (MIDI Tuning Standard)**: Real-time microtuning
- **Scala scale**: Load .scl files via sysex

```cpp
// MTS messages use specific sysex format:
// F0 7E [device] 08 [format] [data...] F7
```

**MPE Configuration Sysex:**

MPE (MIDI Polyphonic Expression) can be configured via sysex:

```cpp
// MPE Configuration Message (Universal Sysex)
// F0 7E 7F 0D 00 [zone] [channels] F7
//   zone: 0 = lower zone, 1 = upper zone
//   channels: number of member channels
```

### MPE (MIDI Polyphonic Expression)

MPE extends MIDI to allow per-note expression by dedicating each note to its own MIDI channel.

**Traditional MIDI:**
```
Channel 1: [Note On: C4] [CC1: 64] [CC1: 80]
           ^             ^             ^
        All notes       Affects all notes
```

**MPE:**
```
Channel 2: [Note On: C4] [CC74: 64] [Pitch Bend: +100]
Channel 3: [Note On: E4] [CC74: 32] [Pitch Bend: -50]
           ^                ^            ^
        Each note on      Independent    Independent
        own channel       brightness     pitch bend
```

**MPE Dimensions:**

1. **Pitch Bend** (per-note): Fine pitch control (vibrato, bends)
2. **CC74 (Brightness/Timbre)**: Tone color (brightness, filter, etc.)
3. **Channel Pressure**: Per-note pressure (aftertouch)
4. **CC10 (Pan)**: Spatial position (rarely used)

**Surge's MPE Implementation:**

```cpp
// From: src/common/SurgeStorage.h
struct MidiChannelState
{
    float pan;                     // CC10 (MPE pan)
    float timbre;                  // CC74 (MPE timbre/brightness)
    float pressure;                // Channel aftertouch (MPE pressure)
    float pitchBendInSemitones;    // Pitch bend range
};
```

**MPE Note Flow:**

```cpp
// When MPE is enabled:
// 1. Master channel (1 or 16) sends global controls
// 2. Each note gets assigned to a member channel (2-15 or 15-2)
// 3. Per-note expression on member channels modulates the voice

void SurgeSynthesizer::playNote(char channel, char key, char velocity,
                                char detune, int32_t host_noteid)
{
    if (mpeEnabled)
    {
        // Store MPE channel for this voice
        voice->mpe_channel = channel;
        voice->mpe_timbre = channelState[channel].timbre;
        voice->mpe_pressure = channelState[channel].pressure;
        voice->mpe_pan = channelState[channel].pan;
    }
    // ...
}

void SurgeSynthesizer::channelController(char channel, int cc, int value)
{
    if (cc == 74 && mpeEnabled)  // Timbre
    {
        channelState[channel].timbre = value / 127.0f;

        // Update all voices on this channel
        for (auto& voice : voices)
        {
            if (voice.mpe_channel == channel)
            {
                voice.mpe_timbre = channelState[channel].timbre;
            }
        }
    }
}
```

**MPE Controllers (Roli Seaboard, Linnstrument, Osmose):**

These hardware controllers send:
- Pressure per key → Channel aftertouch or Poly aftertouch
- Slide left/right → CC74 (timbre)
- Vertical slide → Pitch bend
- Lift-off velocity → Note-off velocity

Surge routes these to voice-level modulation sources, allowing expressive per-note control of:
- Filter cutoff
- Oscillator detune
- Effect send levels
- Any modulatable parameter

### MIDI CC Learn

Surge allows mapping hardware controllers to any parameter:

**CC Learn Flow:**

```cpp
// 1. User right-clicks parameter, selects "MIDI Learn"
// 2. Surge enters learn mode for that parameter
// 3. User moves a MIDI controller (e.g., knob on keyboard)
// 4. Surge captures the CC number and assigns it

void SurgeSynthesizer::channelController(char channel, int cc, int value)
{
    if (learn_param >= 0)
    {
        // Assign this CC to the parameter waiting for learn
        storage.getPatch().param_ptr[learn_param]->midictrl = cc;
        learn_param = -1;  // Exit learn mode
    }
    else
    {
        // Normal CC processing: find parameters mapped to this CC
        for (int i = 0; i < n_total_params; i++)
        {
            if (storage.getPatch().param_ptr[i]->midictrl == cc)
            {
                // Update parameter from CC value
                float normalized = value / 127.0f;
                setParameter01(i, normalized, false);
            }
        }
    }
}
```

**CC Mappings are Saved:**

MIDI learn assignments are part of the patch, so they persist across sessions.

---

## Conclusion: A Robust Integration Layer

Surge XT's plugin architecture demonstrates the complexity of integrating a sophisticated synthesizer with modern DAWs. From JUCE's cross-platform abstraction to format-specific optimizations like CLAP's direct processing, from sample-accurate MIDI handling to thread-safe state management, every detail contributes to a stable, performant, and expressive instrument.

The architecture's key strengths:

1. **Clean Separation**: DSP engine remains independent of plugin wrapper
2. **Thread Safety**: Lock-free queues and atomic operations prevent audio glitches
3. **Format Flexibility**: Single codebase supports VST3, AU, CLAP, LV2, standalone
4. **Backward Compatibility**: Patches from 2004 still load in 2024
5. **Future-Proof**: CLAP integration positions Surge for next-generation features

Whether you're a user recording automation in a DAW, a sound designer sharing patches across platforms, or a developer exploring plugin architecture, understanding this integration layer reveals the engineering sophistication that makes modern software instruments possible.

---

**Cross-References:**

- Chapter 1: Architecture Overview (block-based processing, SIMD)
- Chapter 4: Voice Architecture (voice allocation, polyphony)
- Chapter 18: Modulation Architecture (automation vs. modulation)
- Chapter 23: GUI Architecture (UI ↔ DSP communication)
- Chapter 31: MIDI and MPE (MPE implementation details)
- Chapter 37: Build System (CMake configuration for plugin formats)

**Further Reading:**

- JUCE Documentation: https://docs.juce.com/
- VST3 SDK: https://steinbergmedia.github.io/vst3_doc/
- CLAP Specification: https://github.com/free-audio/clap
- Audio Unit Programming Guide: https://developer.apple.com/documentation/audiounit
- LV2 Specification: https://lv2plug.in/
