# Chapter 23: GUI Architecture

## The Visual Interface to a Complex Synthesizer

Surge XT's graphical user interface represents one of the most sophisticated open-source synthesizer GUIs, built entirely on the JUCE framework. With over 553 parameters, multiple modulation routing displays, real-time waveform visualization, and an extensible overlay system, the GUI architecture must balance performance, maintainability, and user experience.

This chapter explores the architecture that makes it all work: how JUCE components are organized, how the UI communicates with the DSP engine, and how graphics are rendered efficiently at high frame rates.

## 1. JUCE Framework Foundation

### What is JUCE?

**JUCE** (Jules' Utility Class Extensions) is a cross-platform C++ framework for building audio applications. Surge XT uses JUCE for:

- **UI components** - Windows, buttons, sliders, menus
- **Graphics rendering** - 2D vector graphics, image handling
- **Plugin wrapper** - VST3, AU, CLAP integration
- **Cross-platform abstractions** - File I/O, threading, timers

```cpp
// From: src/surge-xt/gui/SurgeGUIEditor.h
#include "juce_gui_basics/juce_gui_basics.h"

class SurgeGUIEditor : public Surge::GUI::IComponentTagValue::Listener,
                       public SurgeStorage::ErrorListener,
                       public juce::KeyListener,
                       public juce::FocusChangeListener,
                       public SurgeSynthesizer::ModulationAPIListener
{
    // The editor integrates with multiple JUCE systems
};
```

**Why JUCE?**

1. **Cross-platform**: Single codebase for Windows, macOS, Linux
2. **Plugin formats**: Built-in VST3, AU, CLAP support
3. **Modern C++**: Uses C++17 features, smart pointers
4. **Graphics**: Hardware-accelerated rendering
5. **Accessibility**: Built-in screen reader support
6. **Mature**: Battle-tested in thousands of audio applications

**Surge's JUCE Usage:**

```cpp
// JUCE is used throughout the GUI layer
// - All widgets inherit from juce::Component
// - Graphics rendering uses juce::Graphics
// - Menus use juce::PopupMenu
// - File dialogs use juce::FileChooser
// - Timers use juce::Timer
// - Keyboard/mouse events use juce::MouseEvent, juce::KeyPress
```

### Component Hierarchy

JUCE uses a tree-based component hierarchy, similar to DOM in web browsers:

```
SurgeSynthEditor (juce::AudioProcessorEditor)
  └─> MainFrame (juce::Component)
        ├─> Background image
        ├─> Parameter widgets (sliders, switches, buttons)
        ├─> Modulation source buttons
        ├─> Oscillator display
        ├─> LFO display
        ├─> VU meters
        ├─> Effect chooser
        ├─> Patch selector
        ├─> Control group overlays
        └─> Overlay wrappers (MSEG editor, etc.)
```

**Component Ownership:**

```cpp
// From: src/surge-xt/gui/widgets/MainFrame.h
struct MainFrame : public juce::Component
{
    SurgeGUIEditor *editor{nullptr};

    // Control group layers
    std::array<std::unique_ptr<juce::Component>, endCG> cgOverlays;
    std::unique_ptr<juce::Component> modGroup, synthControls;

    // Background
    SurgeImage *bg{nullptr};
};
```

Children are added using:

```cpp
// Add component as child
frame->addAndMakeVisible(widget);

// Set bounds (position and size)
widget->setBounds(x, y, width, height);

// Children are automatically:
// - Repainted when parent repaints
// - Destroyed when parent is destroyed
// - Clipped to parent bounds
```

### Event Handling

JUCE uses virtual methods for event handling:

```cpp
class MyWidget : public juce::Component
{
    void mouseDown(const juce::MouseEvent &event) override
    {
        if (event.mods.isRightButtonDown())
            showContextMenu();
    }

    void mouseMove(const juce::MouseEvent &event) override
    {
        // Hover feedback
        isHovered = getBounds().contains(event.getPosition());
        repaint();
    }

    void mouseDrag(const juce::MouseEvent &event) override
    {
        // Drag interaction
        float delta = event.getDistanceFromDragStartY();
        adjustValue(delta);
    }

    bool keyPressed(const juce::KeyPress &key) override
    {
        if (key.getKeyCode() == juce::KeyPress::returnKey)
        {
            activateWidget();
            return true; // Event handled
        }
        return false; // Pass to parent
    }
};
```

**Event Propagation:**

1. Event arrives at top-level component
2. JUCE finds the target component under mouse/focus
3. Component's event handler is called
4. If handler returns `false`, event bubbles to parent
5. Process continues until handled or reaches root

### Graphics Context

JUCE provides a `Graphics` object for drawing:

```cpp
// From: src/surge-xt/gui/widgets/VuMeter.cpp (example)
void VuMeter::paint(juce::Graphics &g)
{
    // Fill background
    g.fillAll(juce::Colour(20, 20, 25));

    // Draw rectangles
    g.setColour(juce::Colours::green);
    g.fillRect(x, y, width, height);

    // Draw text
    g.setColour(juce::Colours::white);
    g.setFont(12.0f);
    g.drawText("VU Meter", bounds, juce::Justification::centred);

    // Draw lines
    g.drawLine(x1, y1, x2, y2, lineThickness);

    // Draw images
    if (image)
        g.drawImage(*image, bounds);
}
```

**Graphics Features:**

- **Antialiased rendering** - Smooth lines and curves
- **Transforms** - Rotation, scaling, translation
- **Clipping** - Restrict drawing to regions
- **Gradients** - Linear and radial fills
- **Text rendering** - Fonts, alignment, wrapping
- **Image compositing** - Alpha blending, filters

**Performance:** Graphics are hardware-accelerated where possible (OpenGL/Metal/Direct2D backends available).

## 2. SurgeGUIEditor: The Main Editor Class

### Overview

`SurgeGUIEditor` is the central coordinator for Surge's entire UI:

```cpp
// From: src/surge-xt/gui/SurgeGUIEditor.h
class SurgeGUIEditor : public Surge::GUI::IComponentTagValue::Listener,
                       public SurgeStorage::ErrorListener,
                       public juce::KeyListener,
                       public juce::FocusChangeListener,
                       public SurgeSynthesizer::ModulationAPIListener
{
public:
    SurgeGUIEditor(SurgeSynthEditor *juceEditor, SurgeSynthesizer *synth);
    virtual ~SurgeGUIEditor();

    // Main UI container
    std::unique_ptr<Surge::Widgets::MainFrame> frame;

    // Synthesis engine reference
    SurgeSynthesizer *synth = nullptr;

    // Current skin
    Surge::GUI::Skin::ptr_t currentSkin;

    // Idle loop (called ~60 times per second)
    void idle();

    // Parameter modification callbacks
    void valueChanged(Surge::GUI::IComponentTagValue *control) override;
    void controlBeginEdit(Surge::GUI::IComponentTagValue *control) override;
    void controlEndEdit(Surge::GUI::IComponentTagValue *control) override;

    // Modulation API
    void modSet(long ptag, modsources modsource, int scene, int index,
                float value, bool isNew) override;
    void modMuted(long ptag, modsources modsource, int scene, int index,
                  bool mute) override;
    void modCleared(long ptag, modsources modsource, int scene, int index) override;
};
```

**SurgeGUIEditor is NOT a JUCE Component.** It's a controller that manages JUCE components. The actual JUCE component is `MainFrame`.

### Responsibilities

1. **Widget Management**
   - Creates and positions all UI widgets
   - Routes events to appropriate handlers
   - Updates widget states from DSP

2. **State Synchronization**
   - Keeps UI in sync with synthesis engine
   - Handles parameter changes from automation
   - Updates modulation displays

3. **Overlay Coordination**
   - Manages modal/non-modal overlays
   - Handles MSEG editor, Formula editor, etc.
   - Tear-out window management

4. **Menu Systems**
   - Context menus for parameters
   - Main menu construction
   - MIDI learn, modulation, presets

5. **Accessibility**
   - Screen reader support
   - Keyboard navigation
   - Announcements

### Component Layout

The GUI is built in `openOrRecreateEditor()`:

```cpp
// From: src/surge-xt/gui/SurgeGUIEditor.cpp (simplified)
void SurgeGUIEditor::openOrRecreateEditor()
{
    // 1. Create main frame
    frame = std::make_unique<Surge::Widgets::MainFrame>();
    frame->setSurgeGUIEditor(this);

    // 2. Set background
    auto bg = bitmapStore->getImage(IDB_MAIN_BG);
    frame->setBackground(bg);

    // 3. Create all widgets from skin definition
    for (auto &skinCtrl : currentSkin->getControls())
    {
        auto widget = layoutComponentForSkinSession(skinCtrl, tag, paramIndex);
        // Position and add widget
    }

    // 4. Create specialized displays
    oscWaveform = std::make_unique<OscillatorWaveformDisplay>();
    lfoDisplay = std::make_unique<LFOAndStepDisplay>(this);
    vu = std::make_unique<VuMeter>();

    // 5. Setup overlay system
    // (Overlays created on-demand)

    editor_open = true;
}
```

**Skin-Driven Layout:**

Surge's UI layout is defined in XML skin files:

```xml
<!-- From a skin.xml file -->
<control ui_identifier="scene.osc1.pitch"
         x="23" y="62" w="60" h="18"
         style="slider_horizontal" />
```

Each control is matched to a parameter and widget type, positioned automatically.

### Lifecycle

```cpp
// 1. Construction
SurgeGUIEditor::SurgeGUIEditor(SurgeSynthEditor *jEd, SurgeSynthesizer *synth)
{
    // Load skin
    currentSkin = Surge::GUI::SkinDB::get()->defaultSkin(&synth->storage);

    // Initialize zoom
    setZoomFactor(initialZoomFactor);

    // Setup keyboard shortcuts
    setupKeymapManager();

    // Create UI (deferred until open())
}

// 2. Opening
bool SurgeGUIEditor::open(void *parent)
{
    openOrRecreateEditor();
    // UI is now visible
}

// 3. Idle loop (60 Hz)
void SurgeGUIEditor::idle()
{
    // Update VU meters
    // Process queued patch loads
    // Refresh modulation displays
    // Handle async operations
}

// 4. Destruction
SurgeGUIEditor::~SurgeGUIEditor()
{
    // Save state
    populateDawExtraState(synth);

    // Cleanup listeners
    synth->removeModulationAPIListener(this);

    // JUCE components auto-deleted via unique_ptr
}
```

### Widget Tracking

Surge maintains a component registry:

```cpp
// From: src/surge-xt/gui/SurgeGUIEditor.h
private:
    // Session-based component cache (keyed by skin session ID)
    std::unordered_map<Surge::GUI::Skin::Control::sessionid_t,
                       std::unique_ptr<juce::Component>> juceSkinComponents;

    // Parameter widgets (indexed by parameter tag)
    static const int n_paramslots = 1024;
    Surge::Widgets::ModulatableControlInterface *param[n_paramslots] = {};
    Surge::GUI::IComponentTagValue *nonmod_param[n_paramslots] = {};

    // Modulation source buttons
    std::array<std::unique_ptr<Surge::Widgets::ModulationSourceButton>,
               n_modsources> gui_modsrc;
```

**Purpose:**
- Quickly find widgets by parameter ID
- Update multiple widgets when patch changes
- Rebuild UI when skin changes

## 3. GUI-DSP Communication

### The Thread Safety Challenge

```
┌──────────────────┐         ┌──────────────────┐
│   GUI Thread     │         │   Audio Thread   │
│  (UI updates)    │  ◀───▶  │  (DSP processing)│
│  Non-realtime    │         │  Realtime-safe   │
└──────────────────┘         └──────────────────┘
```

**Constraints:**

- **Audio thread:** Must NEVER block, allocate, or lock
- **GUI thread:** Can do slow operations (file I/O, rendering)
- **Communication:** Must be lock-free or carefully synchronized

### Parameter Callbacks

When a user moves a slider:

```cpp
// From: src/surge-xt/gui/SurgeGUIEditorValueCallbacks.cpp
void SurgeGUIEditor::valueChanged(Surge::GUI::IComponentTagValue *control)
{
    if (!frame || !synth)
        return;

    long tag = control->getTag();

    // Special handling for non-parameter controls
    if (tag == tag_mp_category)
    {
        // Patch browser category changed
        return;
    }

    // Most controls are parameters
    auto *p = synth->storage.getPatch().param_ptr[tag - start_paramtags];

    if (p)
    {
        // Set parameter value in DSP engine
        setParameter(tag - start_paramtags, control->getValue());
    }
}
```

**Parameter Change Flow:**

```
1. User drags slider
   ↓
2. Widget calls valueChanged()
   ↓
3. SurgeGUIEditor::valueChanged()
   ↓
4. setParameter(id, value)
   ↓
5. SurgeSynthesizer::setParameter01()
   ↓
6. Parameter.set_value_f01(value)  [ATOMIC]
   ↓
7. Audio thread reads new value on next block
```

**Thread Safety:**

```cpp
// Parameters use atomic reads/writes
void Parameter::set_value_f01(float v, bool force_integer)
{
    // Atomic write - safe from audio thread
    val.f = limit_range(v, 0.0f, 1.0f);
}

// Audio thread reads without locks
float pitch = oscdata->pitch.get_extended(localcopy[oscdata->pitch.param_id_in_scene].f);
```

### Begin/End Edit

**Purpose:** Tell the host DAW when automation is being recorded:

```cpp
void SurgeGUIEditor::controlBeginEdit(Surge::GUI::IComponentTagValue *control)
{
    long tag = control->getTag();

    // Notify plugin host
    juceEditor->beginParameterEdit(tag);

    // Push undo state
    undoManager()->pushParameterChange(tag, target);
}

void SurgeGUIEditor::controlEndEdit(Surge::GUI::IComponentTagValue *control)
{
    long tag = control->getTag();

    // Notify plugin host
    juceEditor->endParameterEdit(tag);
}
```

**Why This Matters:**

- DAWs need to know when to start/stop recording automation
- Undo/redo needs to capture parameter changes as single actions
- Performance: Avoid sending automation for every mouse pixel

### Async Updates

Some updates can't happen in the audio callback:

```cpp
void SurgeGUIEditor::idle()
{
    // Check for queued patch loads
    if (synth->patchid_queue >= 0)
    {
        // Load patch on UI thread
        int patchid = synth->patchid_queue;
        synth->patchid_queue = -1;
        synth->loadPatch(patchid);

        // Rebuild entire UI
        queue_refresh = true;
    }

    // Refresh UI if needed
    if (queue_refresh || synth->refresh_editor)
    {
        // Update all widgets from current patch
        for (auto &param : param)
        {
            if (param)
                param->setValue(getParameterValue(param->getTag()));
        }

        queue_refresh = false;
        synth->refresh_editor = false;
    }
}
```

**Idle Loop Rate:** ~60 Hz (called by JUCE timer)

### Thread Safety Patterns

**1. Atomic Flags:**

```cpp
// Signal from audio → GUI
std::atomic<bool> synth->refresh_editor{false};

// Audio thread sets flag
if (patch_loaded)
    refresh_editor = true;

// GUI thread checks flag
if (synth->refresh_editor)
    rebuildUI();
```

**2. Lock-Free Queues:**

```cpp
// For error messages
std::deque<std::tuple<std::string, std::string, SurgeStorage::ErrorType>> errorItems;
std::mutex errorItemsMutex;
std::atomic<int> errorItemCount{0};

// Audio thread (or any thread)
{
    std::lock_guard<std::mutex> g(errorItemsMutex);
    errorItems.push_back({message, title, type});
    errorItemCount++;
}

// GUI thread
if (errorItemCount)
{
    std::lock_guard<std::mutex> g(errorItemsMutex);
    auto error = errorItems.front();
    errorItems.pop_front();
    errorItemCount--;
    showErrorDialog(error);
}
```

**3. Double-Buffering:**

For expensive computations (waveform rendering):

```cpp
// Render in background, swap on completion
std::unique_ptr<juce::Image> backingImage;

void paint(juce::Graphics &g) override
{
    if (!backingImage || paramsChanged())
    {
        renderToBackingImage();
    }

    g.drawImage(*backingImage, bounds);
}
```

## 4. Menu System

### Context Menus

Right-clicking on any parameter shows a context menu:

```cpp
// From: src/surge-xt/gui/SurgeGUIEditorValueCallbacks.cpp
int32_t SurgeGUIEditor::controlModifierClicked(
    Surge::GUI::IComponentTagValue *control,
    const juce::ModifierKeys &button,
    bool isDoubleClickEvent)
{
    if (!synth)
        return 0;

    long tag = control->getTag();

    // Right-click shows context menu
    if (button.isRightButtonDown())
    {
        auto contextMenu = juce::PopupMenu();

        // Standard parameter menu items
        contextMenu.addItem("Edit Value", [this, control]() {
            promptForUserValueEntry(control->getTag(), control);
        });

        contextMenu.addItem("Set to Default", [this, tag]() {
            auto *p = synth->storage.getPatch().param_ptr[tag - start_paramtags];
            setParameter(tag - start_paramtags, p->get_default_value_f01());
        });

        // Modulation submenu
        if (isModulatableParameter(tag))
        {
            auto modMenu = juce::PopupMenu();
            // Add modulation options
            contextMenu.addSubMenu("Modulate", modMenu);
        }

        // MIDI learn
        createMIDILearnMenuEntries(contextMenu, param_cc, ccid, control);

        // Show menu
        auto result = contextMenu.show();

        return 1; // Handled
    }

    return 0; // Not handled
}
```

**Menu Construction Pattern:**

```cpp
auto menu = juce::PopupMenu();

// Simple item
menu.addItem("Action Name", [this]() {
    performAction();
});

// Item with checkmark
menu.addItem("Option", true, isEnabled, [this]() {
    toggleOption();
});

// Submenu
auto submenu = juce::PopupMenu();
submenu.addItem("Subitem", []() {});
menu.addSubMenu("Category", submenu);

// Separator
menu.addSeparator();

// Custom component
menu.addCustomItem(-1, std::move(customComponent));

// Show menu
menu.show();
```

### Right-Click Actions

Different widgets have different context menus:

**Modulatable Parameters:**
- Edit Value
- Set to Default
- Modulate by... (lists all modulation sources)
- Clear Modulation
- MIDI Learn
- Tempo Sync (if applicable)
- Extend Range (if applicable)
- Absolute/Relative toggle

**Oscillator Display:**
- Load Wavetable
- Export Wavetable (WAV, .wt, Serum)
- Previous/Next Wavetable
- Edit Wavetable Script
- Refresh Wavetables

**LFO Display:**
- Load LFO Preset
- Save LFO Preset
- Copy/Paste MSEG
- Step Sequencer options

**Effect Chooser:**
- Select Effect Type
- Copy/Paste FX
- Save FX Preset
- Load FX Preset

### Menu Structure Generators

Menus are generated programmatically:

```cpp
// From: src/surge-xt/gui/SurgeGUIEditorMenuStructures.cpp
juce::PopupMenu SurgeGUIEditor::makeZoomMenu(const juce::Point<int> &where,
                                             bool showhelp)
{
    auto zoomMenu = juce::PopupMenu();

    // Add header
    if (showhelp)
    {
        auto hu = helpURLForSpecial("zoom-menu");
        addHelpHeaderTo("Zoom", fullyResolvedHelpURL(hu), zoomMenu);
        zoomMenu.addSeparator();
    }

    // Current zoom level
    int currentZoom = getZoomFactor();

    // Zoom options
    std::vector<int> zoomLevels = {50, 75, 100, 125, 150, 175, 200};

    for (int zoom : zoomLevels)
    {
        bool isChecked = (zoom == currentZoom);

        zoomMenu.addItem(
            fmt::format("{}%", zoom),
            true,  // enabled
            isChecked,
            [this, zoom]() { setZoomFactor(zoom); }
        );
    }

    // Separator and additional options
    zoomMenu.addSeparator();

    zoomMenu.addItem("Zoom to Default", [this]() {
        setZoomFactor(100);
    });

    return zoomMenu;
}
```

**Menu Features:**

- **Dynamic generation** - Menus built on-demand based on current state
- **Checkmarks** - Show current selection
- **Keyboard shortcuts** - Displayed in menu text
- **Hierarchical** - Submenus for organization
- **Custom components** - Rich content (help headers, separators)

## 5. Overlay Management

### Overlay System Architecture

Overlays are floating windows/dialogs for editors:

```cpp
// From: src/surge-xt/gui/SurgeGUIEditor.h
enum OverlayTags
{
    NO_EDITOR,
    MSEG_EDITOR,           // Multi-segment envelope editor
    SAVE_PATCH,            // Patch save dialog
    PATCH_BROWSER,         // Patch browser
    MODULATION_EDITOR,     // Modulation matrix
    FORMULA_EDITOR,        // Lua formula editor
    WTS_EDITOR,            // Wavetable script editor
    TUNING_EDITOR,         // Tuning/scales editor
    WAVESHAPER_ANALYZER,   // Waveshaper visualization
    FILTER_ANALYZER,       // Filter frequency response
    OSCILLOSCOPE,          // Audio scope
    KEYBINDINGS_EDITOR,    // Keyboard shortcuts
    ACTION_HISTORY,        // Undo/redo history
    OPEN_SOUND_CONTROL_SETTINGS,  // OSC configuration

    n_overlay_tags,
};

std::unordered_map<OverlayTags, std::unique_ptr<Surge::Overlays::OverlayWrapper>>
    juceOverlays;
```

### Creating Overlays

```cpp
// From: src/surge-xt/gui/SurgeGUIEditorOverlays.cpp
void SurgeGUIEditor::showOverlay(OverlayTags olt)
{
    // Check if already open
    if (isAnyOverlayPresent(olt))
    {
        // Bring to front
        auto wrapper = juceOverlays[olt].get();
        wrapper->toFront(true);
        return;
    }

    // Create overlay content
    auto overlayContent = createOverlay(olt);

    if (!overlayContent)
        return;

    // Wrap in overlay wrapper
    auto wrapper = addJuceEditorOverlay(
        std::move(overlayContent),
        "Editor Title",
        olt,
        bounds,
        showCloseButton
    );

    // Store for later access
    juceOverlays[olt].reset(wrapper);
}

std::unique_ptr<Surge::Overlays::OverlayComponent>
SurgeGUIEditor::createOverlay(OverlayTags olt)
{
    switch (olt)
    {
    case MSEG_EDITOR:
    {
        auto lfo_id = modsource_editor[current_scene] - ms_lfo1;
        auto lfodata = &synth->storage.getPatch().scene[current_scene].lfo[lfo_id];
        auto ms = &synth->storage.getPatch().msegs[current_scene][lfo_id];

        auto mse = std::make_unique<Surge::Overlays::MSEGEditor>(
            &synth->storage, lfodata, ms,
            &msegEditState[current_scene][lfo_id],
            currentSkin, bitmapStore, this
        );

        mse->setEnclosingParentTitle("MSEG Editor");
        mse->setCanTearOut({true, /* user default keys for position */});

        return mse;
    }

    case FORMULA_EDITOR:
    {
        auto lfo_id = modsource_editor[current_scene] - ms_lfo1;
        auto fs = &synth->storage.getPatch().formulamods[current_scene][lfo_id];

        auto fme = std::make_unique<Surge::Overlays::FormulaModulatorEditor>(
            this, &synth->storage,
            &synth->storage.getPatch().scene[current_scene].lfo[lfo_id],
            fs, lfo_id, current_scene, currentSkin
        );

        return fme;
    }

    // ... other overlay types
    }
}
```

### Modal vs. Non-Modal

**Modal overlays** (block interaction with main UI):
- Save Patch dialog
- Alert messages
- Confirmation dialogs

**Non-modal overlays** (can interact with both):
- MSEG Editor
- Formula Editor
- Oscilloscope
- Filter Analyzer

```cpp
Surge::Overlays::OverlayWrapper *SurgeGUIEditor::addJuceEditorOverlay(
    std::unique_ptr<juce::Component> c,
    std::string editorTitle,
    OverlayTags editorTag,
    const juce::Rectangle<int> &containerBounds,
    bool showCloseButton,
    std::function<void()> onClose,
    bool forceModal)
{
    auto ow = new Surge::Overlays::OverlayWrapper();
    ow->setContent(std::move(c));
    ow->setTitle(editorTitle);
    ow->setBounds(containerBounds);

    if (forceModal)
    {
        ow->enterModalState(true);
    }
    else
    {
        frame->addAndMakeVisible(ow);
    }

    return ow;
}
```

### Tear-Out Windows

Some overlays can be "torn out" into separate windows:

```cpp
// MSEG editor can be torn out
mse->setCanTearOut({
    true,  // Can tear out
    Surge::Storage::MSEGOverlayLocationTearOut,  // Position key
    Surge::Storage::MSEGOverlayTearOutAlwaysOnTop,  // Always on top key
    Surge::Storage::MSEGOverlayTearOutAlwaysOnTop_Plugin  // Plugin variant
});

mse->setCanTearOutResize({
    true,  // Can resize
    Surge::Storage::MSEGOverlaySizeTearOut  // Size key
});

mse->setMinimumSize(600, 250);
```

**Tear-Out Features:**

- **Persistent position** - Saved to user preferences
- **Resizable** - Min/max size constraints
- **Always on top** - Optional setting
- **Multiple monitors** - Can drag to any screen
- **Restore on load** - Reopens torn-out editors

### Overlay Communication

Overlays communicate back to the editor:

```cpp
// MSEG editor notifies on changes
mse->onModelChanged = [this]() {
    // Mark LFO display for repaint
    if (lfoDisplayRepaintCountdown == 0)
        lfoDisplayRepaintCountdown = 2;
};

// Patch store dialog saves patch
patchStoreDialog->onSave = [this](const std::string &name,
                                  const std::string &category) {
    savePatch(name, category);
    closeOverlay(SAVE_PATCH);
};
```

## 6. Graphics and Rendering

### Custom Drawing

Widgets override `paint()` to draw themselves:

```cpp
// From: src/surge-xt/gui/widgets/VuMeter.cpp
void VuMeter::paint(juce::Graphics &g)
{
    // 1. Fill background
    g.fillAll(skin->getColor(Colors::VuMeter::Background));

    // 2. Draw VU bars
    float barHeight = getHeight();
    float leftLevel = limit_range(vL, 0.f, 1.f);
    float rightLevel = limit_range(vR, 0.f, 1.f);

    // Left channel
    g.setColour(getLevelColor(leftLevel));
    g.fillRect(0.f, barHeight * (1.f - leftLevel),
               getWidth() / 2.f, barHeight * leftLevel);

    // Right channel
    g.setColour(getLevelColor(rightLevel));
    g.fillRect(getWidth() / 2.f, barHeight * (1.f - rightLevel),
               getWidth() / 2.f, barHeight * rightLevel);

    // 3. Draw scale markings
    drawScaleMarkings(g);

    // 4. Draw peak hold indicators
    if (showPeakHold)
        drawPeakHold(g);
}

juce::Colour VuMeter::getLevelColor(float level)
{
    if (level > 0.95f)
        return juce::Colours::red;      // Clipping
    else if (level > 0.8f)
        return juce::Colours::yellow;   // Hot
    else
        return juce::Colours::green;    // Normal
}
```

### Waveform Displays

The oscillator display renders waveforms:

```cpp
// From: src/surge-xt/gui/widgets/OscillatorWaveformDisplay.cpp
void OscillatorWaveformDisplay::paint(juce::Graphics &g)
{
    // 1. Setup oscillator
    auto osc = setupOscillator();

    // 2. Generate waveform samples
    const int numSamples = getWidth();
    float samples[numSamples];

    for (int i = 0; i < numSamples; ++i)
    {
        float phase = (float)i / numSamples;
        osc->process_block(phase);
        samples[i] = osc->output[0];
    }

    // 3. Draw waveform
    g.setColour(skin->getColor(Colors::Osc::Display::Wave));

    juce::Path wavePath;
    wavePath.startNewSubPath(0, centerY);

    for (int i = 0; i < numSamples; ++i)
    {
        float x = i;
        float y = centerY - samples[i] * amplitude;
        wavePath.lineTo(x, y);
    }

    g.strokePath(wavePath, juce::PathStrokeType(1.5f));

    // 4. Draw wavetable name if applicable
    if (isWavetable(oscdata))
    {
        g.setFont(11.0f);
        g.drawText(getCurrentWavetableName(), waveTableName,
                   juce::Justification::centred);
    }
}
```

### Modulation Visualization

Modulation depth is shown on parameters:

```cpp
// From: src/surge-xt/gui/widgets/ModulatableSlider.cpp
void ModulatableSlider::paint(juce::Graphics &g)
{
    // 1. Draw base slider
    drawSliderBackground(g);

    // 2. Get parameter value
    float baseValue = getValue();
    float displayValue = baseValue;

    // 3. Show modulation if active
    if (isEditingModulation())
    {
        auto modDepth = getModulationDepth();

        // Draw modulation range
        float modMin = baseValue - modDepth;
        float modMax = baseValue + modDepth;

        g.setColour(skin->getColor(Colors::Modulation::Positive));
        if (modDepth < 0)
            g.setColour(skin->getColor(Colors::Modulation::Negative));

        drawModulationRange(g, modMin, modMax);

        // Draw current modulated value
        displayValue = baseValue + getCurrentModulation();
    }

    // 4. Draw slider thumb
    drawSliderThumb(g, displayValue);

    // 5. Draw value text
    g.drawText(getDisplayValue(), textBounds, juce::Justification::centred);
}
```

### VU Meters

Real-time audio level display:

```cpp
// Updated from idle loop
void SurgeGUIEditor::idle()
{
    // Get levels from synth
    float left = synth->vu_peak[0];
    float right = synth->vu_peak[1];

    // Update VU meter
    if (vu)
    {
        vu->setValueL(left);
        vu->setValueR(right);
        vu->repaint();
    }

    // Decay peaks
    synth->vu_peak[0] *= 0.95f;
    synth->vu_peak[1] *= 0.95f;
}
```

**VU Meter Types:**

```cpp
enum VUType
{
    vut_off = 0,       // No VU display
    vut_vu,            // Classic VU meter
    vut_vu_stereo,     // Stereo VU meter
    vut_gain_reduction // Compressor GR meter
};
```

### Performance Optimizations

**1. Backing Images (Cached Rendering):**

```cpp
// From: src/surge-xt/gui/widgets/LFOAndStepDisplay.cpp
void LFOAndStepDisplay::paint(juce::Graphics &g)
{
    // Check if we need to regenerate
    if (!backingImage || paramsHasChanged() || forceRepaint)
    {
        // Render to backing image
        backingImage = std::make_unique<juce::Image>(
            juce::Image::ARGB,
            getWidth() * zoomFactor / 100,
            getHeight() * zoomFactor / 100,
            true
        );

        juce::Graphics bg(*backingImage);

        // Expensive rendering to backing image
        paintWaveform(bg);

        forceRepaint = false;
    }

    // Fast blit from backing image
    g.drawImage(*backingImage, getLocalBounds().toFloat());
}
```

**2. Dirty Flags:**

Only repaint when needed:

```cpp
void repaintIfIdIsInRange(int id)
{
    auto *firstParam = &lfodata->rate;
    auto *lastParam = &lfodata->release;

    bool needsRepaint = false;

    while (firstParam <= lastParam && !needsRepaint)
    {
        if (firstParam->id == id)
            needsRepaint = true;
        firstParam++;
    }

    if (needsRepaint)
        repaint();
}
```

**3. Repaint Throttling:**

```cpp
// Avoid repainting every frame
int lfoDisplayRepaintCountdown{0};

void idle()
{
    if (lfoDisplayRepaintCountdown > 0)
    {
        lfoDisplayRepaintCountdown--;
        if (lfoDisplayRepaintCountdown == 0)
            lfoDisplay->repaint();
    }
}
```

## 7. Accessibility

### Screen Reader Support

Surge provides comprehensive accessibility:

```cpp
// From: src/surge-xt/gui/AccessibleHelpers.h
template <typename T>
struct DiscreteAH : public juce::AccessibilityHandler
{
    struct DAHValue : public juce::AccessibilityValueInterface
    {
        bool isReadOnly() const override { return false; }

        double getCurrentValue() const override
        {
            return comp->getValue();
        }

        void setValue(double newValue) override
        {
            comp->notifyBeginEdit();
            comp->setValue(newValue);
            comp->notifyValueChanged();
            comp->notifyEndEdit();
        }

        juce::String getCurrentValueAsString() const override
        {
            auto sge = comp->firstListenerOfType<SurgeGUIEditor>();
            if (sge)
                return sge->getDisplayForTag(comp->getTag());
            return std::to_string(getCurrentValue());
        }

        AccessibleValueRange getRange() const override
        {
            return {{comp->iMin, comp->iMax}, 1};
        }
    };
};
```

**Accessible Widget Example:**

```cpp
std::unique_ptr<juce::AccessibilityHandler>
ModulatableSlider::createAccessibilityHandler() override
{
    return std::make_unique<SliderAH>(this);
}

// Now screen readers can:
// - Read the parameter name
// - Read the current value
// - Read the value range
// - Announce value changes
```

### Keyboard Navigation

Full keyboard control:

```cpp
// From: src/surge-xt/gui/AccessibleHelpers.h
inline std::tuple<AccessibleKeyEditAction, AccessibleKeyModifier>
accessibleEditAction(const juce::KeyPress &key, SurgeStorage *storage)
{
    if (key.getKeyCode() == juce::KeyPress::upKey)
    {
        if (key.getModifiers().isShiftDown())
            return {Increase, Fine};       // Fine adjustment
        if (key.getModifiers().isCommandDown())
            return {Increase, Quantized};  // Quantized steps
        return {Increase, NoModifier};     // Normal step
    }

    if (key.getKeyCode() == juce::KeyPress::downKey)
        return {Decrease, ...};

    if (key.getKeyCode() == juce::KeyPress::homeKey)
        return {ToMax, NoModifier};

    if (key.getKeyCode() == juce::KeyPress::endKey)
        return {ToMin, NoModifier};

    if (key.getKeyCode() == juce::KeyPress::deleteKey)
        return {ToDefault, NoModifier};

    // Shift+F10 or context menu key
    if (key.getKeyCode() == juce::KeyPress::F10Key &&
        key.getModifiers().isShiftDown())
        return {OpenMenu, NoModifier};

    return {None, NoModifier};
}
```

**Keyboard Shortcuts:**

- **Arrow Up/Down**: Adjust value
- **Shift+Arrow**: Fine adjustment (0.1x speed)
- **Ctrl/Cmd+Arrow**: Quantized steps
- **Home**: Set to maximum
- **End**: Set to minimum
- **Delete**: Set to default
- **Shift+F10**: Open context menu
- **Return**: Type-in editor
- **Tab**: Navigate to next control
- **Shift+Tab**: Navigate to previous

### Focus Management

```cpp
// From: src/surge-xt/gui/widgets/MainFrame.cpp
std::unique_ptr<juce::ComponentTraverser>
MainFrame::createFocusTraverser() override
{
    // Custom traverser respects control groups
    return std::make_unique<GroupTagTraverser>(this);
}

// Focus order:
// 1. Scene A controls (ordered by control group)
// 2. Scene B controls
// 3. FX controls
// 4. Global controls
// 5. Modulation sources
// 6. Main menu
```

### Announcements

Screen readers are notified of important events:

```cpp
void SurgeGUIEditor::enqueueAccessibleAnnouncement(const std::string &s)
{
    // Queue announcement with delay
    accAnnounceStrings.push_back({s, 10});
}

void SurgeGUIEditor::idle()
{
    if (!accAnnounceStrings.empty())
    {
        auto h = frame->getAccessibilityHandler();

        if (h && accAnnounceStrings.front().second == 0)
        {
            h->postAnnouncement(
                accAnnounceStrings.front().first,
                juce::AccessibilityHandler::AnnouncementPriority::high
            );
        }

        accAnnounceStrings.front().second--;
        if (accAnnounceStrings.front().second < 0)
            accAnnounceStrings.pop_front();
    }
}

// Usage
enqueueAccessibleAnnouncement("Patch loaded: Lead Pluck");
enqueueAccessibleAnnouncement("Modulation routed: LFO 1 to Filter Cutoff");
```

### Zoom Levels

Surge supports multiple zoom levels for accessibility:

```cpp
void SurgeGUIEditor::setZoomFactor(float zf, bool resizeWindow)
{
    // Constrain zoom
    zf = std::clamp(zf, 25.f, 500.f);

    // Check skin constraints
    if (currentSkin->hasFixedZooms())
    {
        auto fixedZooms = currentSkin->getFixedZooms();
        // Snap to nearest allowed zoom
        zf = findNearestZoom(zf, fixedZooms);
    }

    // Apply zoom
    zoomFactor = zf;

    // Resize window
    if (resizeWindow)
    {
        int w = BASE_WINDOW_SIZE_X * zf / 100;
        int h = BASE_WINDOW_SIZE_Y * zf / 100;
        juceEditor->setSize(w, h);
    }

    // Rezoom all overlays
    rezoomOverlays();

    // Notify skin components
    for (auto &[id, comp] : juceSkinComponents)
    {
        if (auto *widget = dynamic_cast<WidgetBaseMixin<> *>(comp.get()))
            widget->setZoomFactor(zf);
    }
}
```

**Zoom Range:** 25% to 500% (some skins constrain this)

**Zoom Persistence:** Saved to user preferences per instance

## Summary

Surge XT's GUI architecture demonstrates sophisticated engineering:

**JUCE Integration:**
- Clean component hierarchy
- Hardware-accelerated graphics
- Cross-platform consistency
- Built-in accessibility

**Editor Architecture:**
- Separation of UI and DSP concerns
- Thread-safe parameter updates
- Async operations in idle loop
- Skin-driven layout system

**User Experience:**
- Rich context menus
- Flexible overlay system
- Real-time modulation visualization
- Comprehensive keyboard navigation

**Performance:**
- Backing image caching
- Dirty flag optimization
- Repaint throttling
- Efficient event handling

The GUI architecture enables Surge XT to present 553 parameters, complex modulation routing, and real-time visualizations while maintaining smooth 60 FPS performance and full accessibility support.

## Further Reading

- **[Chapter 24: Widget Details]** - Individual widget implementations
- **[Chapter 27: Patch System]** - Patch loading and persistence
- **[JUCE Documentation]** - https://docs.juce.com/
- **[Surge Skin Engine]** - XML-based theming system
