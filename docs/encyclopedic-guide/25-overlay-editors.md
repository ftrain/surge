# Chapter 25: Overlay Editors

Surge XT features a sophisticated system of modal overlay dialogs that provide specialized editing and analysis tools. These overlays are implemented as JUCE components extending the `OverlayComponent` base class, providing full-screen or large windowed editing environments for complex synthesis parameters. This chapter explores the UI implementation of these overlays, complementing the DSP discussions in previous chapters.

## 25.1 Overlay Architecture

All Surge overlays inherit from `OverlayComponent` (`/home/user/surge/src/surge-xt/gui/OverlayComponent.h`), which provides:

- Modal presentation over the main synthesizer UI
- Skin support through `SkinConsumingComponent`
- Common lifecycle management (show/hide/close)
- Optional "tear-out" functionality for separate windows
- Keyboard focus management and accessibility support

The main overlay implementations are:

```
src/surge-xt/gui/overlays/
├── MSEGEditor.cpp (128KB)       - Multi-segment envelope editor
├── LuaEditors.cpp (141KB)       - Lua code editors
├── ModulationEditor.cpp (63KB)  - Modulation routing matrix
├── TuningOverlays.cpp (112KB)   - Tuning/scale editor
├── Oscilloscope.cpp (56KB)      - Audio visualization
├── FilterAnalysis.cpp           - Filter frequency response
├── WaveShaperAnalysis.cpp       - Waveshaper transfer curves
├── AboutScreen.cpp              - System information
└── KeyBindingsOverlay.cpp       - Keyboard shortcut editor
```

## 25.2 MSEG Editor

The MSEG editor (detailed in Chapter 21) provides interactive node editing for multi-segment envelope generators.

### Component Structure

**MSEGEditor** consists of three main components:

1. **MSEGCanvas**: Primary drawing and interaction surface
2. **MSEGControlRegion**: Control panel with editing parameters
3. **Hotzone System**: Mouse interaction regions

The canvas maintains a `std::vector<hotzone>` defining interactive regions:

```cpp
struct hotzone {
    juce::Rectangle<float> rect;        // Hit test area
    int associatedSegment;               // Segment index
    Type type;                           // MOUSABLE_NODE, INACTIVE_NODE, LOOPMARKER
    ZoneSubType zoneSubType;             // SEGMENT_ENDPOINT, SEGMENT_CONTROL, etc.
    SegmentControlDirection segmentDirection; // VERTICAL_ONLY, HORIZONTAL_ONLY, BOTH
    std::function<void(float, float, const juce::Point<float>&)> onDrag;
};
```

Hotzones are recalculated on mouse events, creating clickable regions around nodes (±6.5 pixel radius) with drag callbacks.

### Time Editing Modes

Three modes control how time adjustments propagate:

- **SINGLE**: Movement constrained between neighboring nodes
- **SHIFT**: Adjusts all subsequent nodes, extending total duration
- **DRAW**: Only modifies amplitude as cursor moves horizontally

### Coordinate Transforms

The canvas implements functional transforms:

```cpp
auto valToPx = [vscale, drawArea](float vp) -> float {
    float v = 1 - (vp + 1) * 0.5;  // Map [-1,1] to [1,0]
    return v * vscale + drawArea.getY();
};

auto timeToPx = [tscale, drawArea](float t) {
    return (t - ms->axisStart) * tscale + drawArea.getX();
};
```

These handle zoom/pan via `ms->axisStart` and `ms->axisWidth`.

### Snap System

Both horizontal (time) and vertical (value) snap implemented with a `SnapGuard`:

```cpp
struct SnapGuard {
    SnapGuard(MSEGCanvas *c) : c(c) {
        hSnapO = c->ms->hSnap;
        vSnapO = c->ms->vSnap;
    }
    ~SnapGuard() {
        c->ms->hSnap = hSnapO;
        c->ms->vSnap = vSnapO;
    }
};
```

Holding Shift temporarily disables snap via `std::shared_ptr<SnapGuard>`.

## 25.3 Lua Editors

Surge XT provides two Lua-based editing environments: Formula Modulation and Wavetable Scripting.

### Code Editor Infrastructure

**CodeEditorContainerWithApply** base class provides:

- JUCE `CodeDocument` management
- Syntax-highlighted `SurgeCodeEditorComponent`
- Apply button with dirty state tracking
- Document change listeners
- State persistence to DAWExtraState

### Syntax Highlighting

**LuaTokeniserSurge** extends JUCE's `CodeTokeniser` to recognize:

- Standard Lua keywords: `function`, `end`, `if`, `for`, `while`, `return`
- Math functions: `sin`, `cos`, `exp`, `log`, `sqrt`, `abs`
- Surge extensions: `process`, `init`, `generate`, `phase`

Token types map to skin colors for visual feedback.

### Search and Navigation

**CodeEditorSearch** provides floating search UI with:

- Find/Replace functionality
- Case sensitivity toggle (SVG icon button)
- Whole word matching
- Regex support
- Results counter and navigation
- Replace one/all operations

**GotoLine** offers quick line navigation:

```cpp
bool keyPressed(const juce::KeyPress &key, Component *originatingComponent) {
    int line = std::max(0, textfield->getText().getIntValue() - 1);
    line = std::min(document.getNumLines(), line);

    int numLines = editor->getNumLinesOnScreen();
    editor->scrollToLine(std::max(0, line - int(numLines * 0.5)));

    auto pos = juce::CodeDocument::Position(document, line, 0);
    editor->moveCaretTo(pos, false);
}
```

**TextfieldPopup** base class uses inline SVG for button icons:

```cpp
createButton({R"(
<svg width="24" height="24" fill="#ffffff">
    <path d="m 1.766,... [coordinates] ..."/>
</svg>)"}, 0);
```

### Formula Modulator Editor

**FormulaModulatorEditor** specialized for formula LFOs with:

- Main code editor for formula implementation
- Read-only prelude display (standard math functions)
- Expandable debugger panel showing phase/output values
- Control area for frame/resolution settings

Updates at 30Hz (every other frame):

```cpp
void updateDebuggerIfNeeded() {
    if (updateDebuggerCounter++ % 2 == 0) {
        debugPanel->updateValues(formulastorage->output,
                                formulastorage->phase);
    }
}
```

### Wavetable Script Editor

**WavetableScriptEditor** provides:

- **WavetablePreviewComponent**: 3D wavetable visualization
- **WavetableScriptControlArea**: Resolution/frame count controls
- Generation pipeline:

```cpp
void generateWavetable() {
    setupEvaluator();  // Initialize Lua state

    auto res = evaluator->generate(lastRes, lastFrames, lastRm);

    if (res.isSuccess()) {
        osc->wt.Copy(&res.wavetable);
        rendererComponent->setWavetable(&osc->wt);
    }
}
```

### Prelude System

Both editors support "prelude" code—library functions loaded before user code, including:

- Mathematical constants (π, e, φ)
- Common waveform functions (saw, square, triangle)
- Interpolation utilities
- DSP helpers (clamp, wrap, fold)

### Auto-completion

Bracket/quote auto-completion:

```cpp
bool autoCompleteDeclaration(juce::KeyPress key, std::string start, std::string end) {
    if (key.getTextCharacter() == start[0]) {
        auto pos = mainEditor->getCaretPos();
        mainDocument->insertText(pos, start + end);
        mainEditor->moveCaretTo(pos.movedBy(1), false);
        return true;
    }
    return false;
}
```

Supports: `()`, `[]`, `{}`, `""`, `''`

## 25.4 Modulation Editor

Comprehensive view of all modulation routings in the patch.

### Structure

```
┌─────────────────────────────────────────┐
│  [Side Controls]  │  [List Contents]   │
│  - Sort By        │  ┌──────────────┐  │
│  - Filter By      │  │  Mod Rows    │  │
│  - Add Modulation │  │  (scrollable) │  │
│  - Value Display  │  │              │  │
└─────────────────────────────────────────┘
```

### Data Model

**Datum Structure**:

```cpp
struct Datum {
    int source_scene, source_id, source_index;  // Modulation source
    int destination_id, inScene, idBase;        // Target parameter
    std::string pname, sname, moddepth;         // Display names
    bool isBipolar, isPerScene, isMuted;        // States
    float moddepth01;                           // Normalized depth
    ModulationDisplayInfoWindowStrings mss;     // Value strings
};
```

All modulations collected into `std::vector<Datum> dataRows`.

### Sorting and Filtering

**Two sort orders**:

- **BY_SOURCE**: Group by modulation source (LFO, Envelope, etc.)
- **BY_TARGET**: Group by destination parameter

**Filter modes**:

- **NONE**: Show all modulations
- **SOURCE**: Single source (e.g., "LFO 1 (A)")
- **TARGET**: Single target (e.g., "Filter 1 Cutoff")
- **TARGET_CG**: Control group (all Oscillator parameters)
- **TARGET_SCENE**: Scene scope (Global/Scene A/Scene B)

### Row Rendering

**DataRowEditor** contains:

1. **Clear button** (X icon): Removes modulation
2. **Mute button** (M icon): Toggles modulation on/off
3. **Edit button** (pencil icon): Opens value entry dialog
4. **Modulation slider**: Bipolar depth control (-1 to +1)

Visual connection arrows indicate sort order (horizontal for BY_SOURCE, vertical for BY_TARGET).

### Value Display Modes

```cpp
enum ValueDisplay {
    NOMOD = 0,           // No values shown
    MOD_ONLY = 1,        // Only modulation depths
    CTR = 2,             // Center (base) values
    EXTRAS = 4,          // Min/max range
    CTR_PLUS_MOD = MOD_ONLY | CTR,
    ALL = CTR_PLUS_MOD | EXTRAS
};
```

### Adding Modulations

Two-step process:

1. **Select Source**: Hierarchical menu organized by scope (Global/Scene A/Scene B)
2. **Select Target**: Organized by control group, validates `synth->isValidModulation()`

### Subscription Model

Implements `SurgeSynthesizer::ModulationAPIListener`:

```cpp
void modSet(long ptag, modsources modsource, int modsourceScene,
           int index, float value, bool isNew) override {
    if (!selfModulation) {
        if (isNew || value == 0)
            needsModUpdate = true;      // Full rebuild
        else
            needsModValueOnlyUpdate = true;  // Just update values
    }
}
```

`SelfModulationGuard` prevents feedback loops.

## 25.5 Tuning Editor

Detailed customization of Surge's tuning system using Scala files.

### Components

1. **TuningTableListBoxModel**: 128 MIDI notes with frequency/cents
2. **SCLKBMDisplay**: Text editor for scale/mapping files
3. **RadialScaleGraph**: Circular pitch visualization
4. **IntervalMatrix**: Matrix of all interval ratios

### Keyboard Mapping Table

Displays for each MIDI note:

- Note number (0-127)
- Note name (C-1 through G9)
- Frequency in Hz
- Cents deviation from 12-TET
- Scale degree mapping

### SCL/KBM Editors

**SCL (Scale) File**:
```
! example.scl
12 tone equal temperament
12
!
100.0
200.0
...
```

**KBM (Keyboard Mapping) File**:
```
! example.kbm
12              ! Map size
0               ! First MIDI note
127             ! Last MIDI note
60              ! Middle note
```

Features syntax validation, error reporting, preview, and undo/redo.

### Radial Scale Graph

Circular visualization:

```cpp
void paint(juce::Graphics &g) override {
    for (int i = 0; i < tuning.scale.count; ++i) {
        auto cents = tuning.scale.tones[i].cents;
        auto angle = cents / 1200.0 * 2.0 * M_PI;  // Full circle = octave

        auto x = center.x + radius * std::sin(angle);
        auto y = center.y - radius * std::cos(angle);

        g.fillEllipse(x - 3, y - 3, 6, 6);
    }
}
```

### Scale Operations

**Rescale by Factor**:
```cpp
void onScaleRescaled(double scaledBy) {
    for (auto &tone : tuning.scale.tones)
        tone.cents *= scaledBy;
}
```

**Stretch to Target**:
```cpp
void onScaleRescaledAbsolute(double setRITo) {
    auto currentRI = tuning.scale.tones[count - 1].cents;
    auto factor = setRITo / currentRI;
    onScaleRescaled(factor);
}
```

### MTS-ESP Integration

When MTS-ESP is active, tuning sourced externally with editing disabled:

```cpp
void setMTSMode(bool isMTSOn) {
    mtsMode = isMTSOn;
    if (isMTSOn)
        controlArea->setEnabled(false);
}
```

## 25.6 Oscilloscope

Real-time audio visualization with waveform and spectrum displays.

### Waveform Display

**Features**:
- Time window: 10μs to 1s (logarithmic)
- Amplitude: ±48dB gain range
- Triggering: Free, Rising, Falling, Internal
- DC filter and freeze options

**Rendering**:

```cpp
void process(std::vector<float> data) {
    for (float &sample : data) {
        // DC filter
        dcKill = sample - dcFilterTemp + R * dcKill;
        sample = params_.dc_kill ? dcKill : sample;

        // Apply gain
        sample = juce::jlimit(-1.f, 1.f, sample * params_.gain());

        // Trigger detection
        bool trigger = detectTrigger(sample);

        // Peak tracking
        max = std::max(max, sample);
        min = std::min(min, sample);

        counter += params_.counterSpeed();

        if (counter >= 1.0) {
            peaks[index * 2].y = juce::jmap<float>(max, -1, 1, height, 0);
            peaks[index * 2 + 1].y = juce::jmap<float>(min, -1, 1, height, 0);
            index++;
            counter -= 1.0;
            max = -∞; min = +∞;
        }
    }
}
```

### Spectrum Display

**FFT Analysis**:
- Window size: 4096 samples
- Window function: Hann
- Update rate: 20 Hz
- Frequency range: 20 Hz to 20 kHz

**Processing**:

```cpp
void process(std::vector<float> data) {
    for (float sample : data) {
        incoming_scope_data_[scope_data_pos_++] = sample;

        if (scope_data_pos_ >= 4096) {
            // Apply Hann window
            for (int i = 0; i < 4096; ++i) {
                float window = 0.5f * (1.f - std::cos(2.f * M_PI * i / 4095.f));
                fft_data_[i] = incoming_scope_data_[i] * window;
            }

            // FFT and convert to dB
            fft_.performRealOnlyForwardTransform(fft_data_);
        }
    }
}
```

Exponential smoothing reduces flicker:

```cpp
for (int i = 0; i < 2048; ++i) {
    display_data_[i] = 0.1f * new_scope_data_[i] +
                      0.9f * display_data_[i];
}
```

## 25.7 Filter Analysis

Interactive frequency response visualization using background thread evaluation.

### Architecture

```cpp
struct FilterAnalysisEvaluator {
    std::unique_ptr<std::thread> analysisThread;
    std::mutex dataLock;
    std::condition_variable cv;

    void runThread() {
        auto fp = sst::filters::FilterPlotter(15);  // 2^15 points

        while (continueWaiting) {
            cv.wait(lock);

            auto data = fp.plotFilterMagnitudeResponse(
                type, subtype, cutoff, resonance, params);

            dataCopy = data;
            juce::MessageManager::callAsync([this] {
                editor->repaint();
            });
        }
    }
};
```

### Interactive Cursor

Shows cutoff/resonance position with tooltip:

```cpp
const double freq = std::pow(2, cutoff / 12.0) * 440.0;
const double res = resonance;

g.drawVerticalLine(freqToX(freq), 0, height);
g.drawHorizontalLine(height - res * height, 0, width);
g.fillEllipse(xPos - radius/2, yPos - radius/2, radius, radius);
```

When pressed displays: `Cut: 1234.56 Hz / Res: 67.89 %`

### Grid System

Logarithmic frequency, linear dB axis:

```cpp
for (float freq : {100, 1000, 10000})  // Bold
    g.setColour(primaryGridColor);

for (float dB : {-36, -24, -12, 0, 6, 12})
    g.drawHorizontalLine(dbToY(dB, height), 0, width);
```

## 25.8 WaveShaper Analysis

Transfer curve visualization for waveshaper effects.

### Curve Calculation

Uses SST Waveshapers library:

```cpp
void recalcFromSlider() {
    sst::waveshapers::QuadWaveshaperState wss;
    auto wsop = sst::waveshapers::GetQuadWaveshaper(wstype);
    auto amp = powf(2.f, getDbValue() / 18.f);
    auto pfg = powf(2.f, getPFG() / 18.f);

    for (int i = 0; i < npts; i++) {
        float x = i / float(npts - 1);
        float inval = pfg * std::sin(x * 4.0 * M_PI);  // Test signal

        auto output = wsop(&wss, SIMD_MM(set1_ps)(inval),
                          SIMD_MM(set1_ps)(amp));

        sliderDrivenCurve.emplace_back(x, inval, output[0]);
    }
}
```

Test signal is 4 cycles of sine showing harmonic generation and clipping.

## 25.9 About Screen

Displays version, build details, and system configuration.

### Data Population

```cpp
void populateData() {
    std::string version = "Surge XT " + Surge::Build::FullVersionStr;
    auto ramsize = juce::SystemStats::getMemorySizeInMegabytes();
    auto system = fmt::format("{} {}-bit {} on {}, {} RAM",
                             platform, bitness, wrapper,
                             sst::plugininfra::cpufeatures::brand(),
                             ramsize >= 1024 ? "GB" : "MB");

    lowerLeft.emplace_back("Version:", version, "");
    lowerLeft.emplace_back("System Info:", system, "");
    lowerLeft.emplace_back("Host:", host + " @ " + samplerate, "");
    // ... paths, skin info
}
```

### Interactive Elements

- **Social Icons**: Clickable SVG sprites linking to Discord/GitHub/Website
- **Hyperlinks**: Hover-highlight labels opening URLs/paths
- **Copy Button**: Exports all info to clipboard

## 25.10 KeyBindings Overlay

Customizable keyboard shortcut editor.

### Data Model

```cpp
struct KeyMapManager {
    struct Binding {
        bool active{true};
        std::vector<juce::KeyPress> keys;
    };

    std::array<Binding, numFuncs> bindings;          // Current state
    std::array<Binding, numFuncs> defaultBindings;   // Factory defaults
};
```

### UI Structure

Each row contains:

```cpp
struct KeyBindingsListRow {
    std::unique_ptr<juce::ToggleButton> active;      // Enable/disable
    std::unique_ptr<juce::Label> name;               // Action name
    std::unique_ptr<juce::Label> keyDesc;            // Current binding
    std::unique_ptr<SelfDrawButton> reset;           // Reset to default
    std::unique_ptr<SelfDrawToggleButton> learn;     // Learn mode
};
```

### Learning Mode

When "Learn" activated:

```cpp
bool keyPressed(const juce::KeyPress &key) override {
    if (overlay->isLearning) {
        keyMapManager->bindings[overlay->learnAction].keys = {key};
        overlay->isLearning = false;
        overlay->refreshRow();
        return true;
    }
    // Normal handling...
}
```

### Persistence

Saved to XML on OK:

```cpp
okButton->onClick = [this]() {
    editor->keyMapManager->streamToXML();  // Write to UserSettings.xml
    editor->setupKeymapManager();
    editor->closeOverlay(KEYBINDINGS_EDITOR);
};
```

## 25.11 Overlay Management

### Lifecycle

**Opening**:

```cpp
void SurgeGUIEditor::showOverlay(int which) {
    if (currentOverlay)
        currentOverlay->setVisible(false);

    currentOverlay = createOverlay(which);
    currentOverlay->setSkin(currentSkin);
    currentOverlay->setBounds(getLocalBounds());
    addAndMakeVisible(*currentOverlay);
}
```

**Closing with confirmation**:

```cpp
void closeOverlay(int which) {
    auto msg = currentOverlay->getPreCloseChickenBoxMessage();
    if (msg) {
        auto [title, message] = *msg;
        showYesNoDialog(title, message, [this](bool confirmed) {
            if (confirmed)
                currentOverlay.reset();
        });
    } else {
        currentOverlay.reset();
    }
}
```

### State Persistence

Overlay state saved to `DAWExtraStateStorage`:

```cpp
struct DAWExtraStateStorage {
    struct EditorState {
        struct MSEGState { int timeEditMode; } msegEditState[];
        struct FormulaEditState { std::string code; } formulaEditState[];
        struct ModulationEditorState { int sortOrder; } modulationEditorState;
    } editor;
};
```

## 25.12 Common UI Patterns

### Skin Integration

```cpp
void onSkinChanged() override {
    setBackgroundColor(skin->getColor(Colors::Dialog::Background));
    label->setFont(skin->fontManager->getLatoAtSize(10));

    for (auto *child : getChildren()) {
        if (auto *sc = dynamic_cast<SkinConsumingComponent*>(child))
            sc->setSkin(skin, associatedBitmapStore);
    }
}
```

### Accessibility

```cpp
button->setAccessible(true);
button->setTitle("Reset to Default");
button->setWantsKeyboardFocus(true);

std::unique_ptr<juce::AccessibilityHandler> createAccessibilityHandler() {
    return std::make_unique<juce::AccessibilityHandler>(
        *this, juce::AccessibilityRole::button,
        juce::AccessibilityActions()
            .addAction(juce::AccessibilityActionType::press,
                      [this]() { onClick(); })
    );
}
```

### Performance

**Lazy Evaluation**:
```cpp
void paint(juce::Graphics &g) override {
    if (needsRecalculation) {
        recalculateData();
        needsRecalculation = false;
    }
    drawCachedData(g);
}
```

**Background Threading**:
```cpp
struct BackgroundEvaluator {
    std::unique_ptr<std::thread> thread;
    std::atomic<bool> hasWork{false};

    void workerThread() {
        while (keepRunning) {
            cv.wait(lock, [this]{ return hasWork.load(); });
            auto result = expensiveCalculation();
            juce::MessageManager::callAsync([result]() {
                updateDisplay(result);
            });
        }
    }
};
```

## Summary

Surge XT's overlay system demonstrates sophisticated UI engineering:

- **Modal Architecture**: Focused editing without main UI clutter
- **Specialized Editors**: Purpose-built interfaces for complex parameters
- **Real-Time Visualization**: Live audio/spectrum analysis
- **Deep Accessibility**: Comprehensive keyboard/screen reader support
- **Performant Implementation**: Background threading, lazy evaluation
- **Consistent Patterns**: Shared infrastructure (skins, undo, state)

These overlays transform Surge from a traditional synthesizer into a comprehensive sound design workstation, enabling advanced techniques while maintaining responsive user experience.
