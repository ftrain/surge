# Chapter 29: Resource Management

Surge XT's resource management system orchestrates the loading, caching, and organization of audio data, configuration files, visual assets, and user preferences. This sophisticated infrastructure supports both factory content shipped with the synthesizer and user-generated content, all while maintaining cross-platform compatibility and performance.

## 29.1 Resource Directory Structure

### 29.1.1 Factory Resources Architecture

The factory resource tree resides in `resources/data/` and contains all content shipped with Surge XT. The `SurgeStorage` constructor in `/home/user/surge/src/common/SurgeStorage.cpp` establishes this path on initialization:

```cpp
// Platform-specific path resolution
if (fs::exists(userdp / "SurgeXT"))
    datapath = userdp;
else if (fs::exists(shareddp / "SurgeXT"))
    datapath = shareddp;
else
    datapath = sst::plugininfra::paths::bestLibrarySharedFolderPathFor("SurgeXT");
```

**Factory Directory Tree**:
```
resources/data/
├── configuration.xml              # Default controller mappings and snapshots
├── wavetables/                    # Factory wavetable library
│   ├── Basic/                     # Fundamental waveforms
│   ├── Generated/                 # Algorithmically generated tables
│   ├── Oneshot/                   # Single-cycle samples
│   ├── Rhythmic/                  # Percussion and rhythmic content
│   ├── Sampled/                   # Sampled instruments
│   ├── Scripted/                  # Lua-generated wavetables
│   │   └── Additive/              # Additive synthesis scripts
│   └── Waldorf/                   # Waldorf-style wavetables
├── wavetables_3rdparty/           # Community-contributed wavetables
├── patches_factory/               # Factory patch library
│   ├── Arpeggios/                 # Arpeggiated sequences
│   ├── Bass/                      # Bass sounds
│   ├── Keys/                      # Keyboard sounds
│   ├── Leads/                     # Lead synthesizer sounds
│   ├── Pads/                      # Atmospheric pads
│   ├── Plucks/                    # Plucked sounds
│   └── Templates/                 # Starting point patches
├── patches_3rdparty/              # Community-contributed patches
├── tuning_library/                # Microtuning scales and mappings
│   ├── SCL/                       # 182 Scala scale files
│   ├── KBM Concert Pitch/         # 14 keyboard mapping files
│   ├── Equal Linear Temperaments 17-71/  # Extended equal temperaments
│   └── Documentation.txt          # Tuning documentation
├── skins/                         # Factory skin library
│   ├── Tutorials/                 # Tutorial skins
│   └── dark-mode.surge-skin/      # Dark mode skin
├── fx_presets/                    # Factory FX preset library
│   ├── Airwindows/                # Airwindows effect presets
│   ├── Delay/                     # Delay presets
│   ├── Reverb/                    # Reverb presets
│   └── [other effect types]/
└── modulator_presets/             # Modulator preset library
    ├── LFO/                       # LFO presets
    ├── Envelope/                  # Envelope presets
    └── MSEG/                      # MSEG presets
```

The data path is stored in `SurgeStorage::datapath`:

```cpp
// From SurgeStorage.h
class SurgeStorage
{
public:
    bool datapathOverriden{false};
    fs::path datapath;              // Factory resources path
    fs::path userDataPath;          // User content path
    // ...
};
```

### 29.1.2 User Data Path Resolution

User-generated content lives in a platform-specific location determined by `calculateStandardUserDataPath()`:

**Platform-Specific User Paths**:
- **Windows**: `%USERPROFILE%\Documents\Surge XT\`
- **macOS**: `~/Documents/Surge XT/`
- **Linux**: `~/.local/share/Surge XT/`

The user data path can be overridden via a separate configuration file, supporting portable installations and custom workflows. The `SurgeStorage` constructor resolves this hierarchy:

```cpp
// User path resolution with override support
userDataPath = getOverridenUserPath();

if (userDataPath.empty())
    userDataPath = calculateStandardUserDataPath("SurgeXT");

// Subdirectory setup
userPatchesPath = userDataPath / "Patches";
userWavetablesPath = userDataPath / "Wavetables";
userWavetablesExportPath = userWavetablesPath / "Exported";
userWavetableScriptsPath = userWavetablesPath / "Scripted";
userFXPath = userDataPath / "FX Presets";
userModulatorSettingsPath = userDataPath / "Modulator Presets";
userSkinsPath = userDataPath / "Skins";
userMidiMappingsPath = userDataPath / "MIDI Mappings";
userDefaultFilePath = userDataPath;
```

### 29.1.3 User Directory Creation

The `createUserDirectory()` function in `/home/user/surge/src/common/SurgeStorage.cpp` ensures all required directories exist:

```cpp
void SurgeStorage::createUserDirectory()
{
    auto p = userDataPath;
    auto needToBuild = false;

    if (!fs::is_directory(p) || !fs::is_directory(userPatchesPath))
    {
        needToBuild = true;

        // Create directory tree
        fs::create_directories(userDataPath);
        fs::create_directories(userPatchesPath);
        fs::create_directories(userWavetablesPath);
        fs::create_directories(userFXPath);
        fs::create_directories(userModulatorSettingsPath);
        fs::create_directories(userSkinsPath);
        fs::create_directories(userMidiMappingsPath);

        userDataPathValid = true;
    }
    catch (const fs::filesystem_error &e)
    {
        userDataPathValid = false;
        reportError(std::string() + "User directory is non-writable. " + e.what(),
                    "User Directory Error");
    }
}
```

The `userDataPathValid` atomic boolean tracks whether the user directory is accessible, preventing operations that would fail on read-only filesystems.

## 29.2 Wavetable Resources

### 29.2.1 Wavetable File Format

Surge XT supports two wavetable formats: native `.wt` files and `.wav` files. The `.wt` format provides optimal performance with metadata support.

**Binary .wt File Structure**:

```cpp
// From Wavetable.h
#pragma pack(push, 1)
struct wt_header
{
    char tag[4];              // "vawt"
    unsigned int n_samples;   // Samples per frame (64-4096)
    unsigned short n_tables;  // Number of frames (1-512)
    unsigned short flags;     // Feature flags
};
#pragma pack(pop)

enum wtflags
{
    wtf_is_sample = 1,        // Sample mode (not wavetable)
    wtf_loop_sample = 2,      // Loop the sample
    wtf_int16 = 4,            // 16-bit integer data
    wtf_int16_is_16 = 8,      // 16-bit range (0-65535 vs 0-32767)
    wtf_has_metadata = 0x10,  // Null-terminated XML metadata
};
```

**File Layout**:
1. **Header** (12 bytes): Magic tag, dimensions, flags
2. **Sample Data**: Float32 or Int16 wavetable frames
3. **Mipmap Data**: Pre-computed band-limited versions
4. **Metadata** (optional): Null-terminated XML string

The wavetable data structure in `/home/user/surge/src/common/dsp/Wavetable.h`:

```cpp
class Wavetable
{
public:
    bool everBuilt = false;
    int size;                   // Frame size (power of 2)
    unsigned int n_tables;      // Number of frames
    int size_po2;               // log2(size)
    int flags;                  // Wavetable flags
    float dt;                   // 1.0 / size

    // Mipmap pyramid for band-limiting
    float *TableF32WeakPointers[max_mipmap_levels][max_subtables];
    short *TableI16WeakPointers[max_mipmap_levels][max_subtables];

    size_t dataSizes;
    float *TableF32Data;        // Contiguous float data
    short *TableI16Data;        // Contiguous int16 data

    // Display and loading state
    int current_id, queue_id;
    bool refresh_display;
    std::string queue_filename;
    std::string current_filename;
};
```

### 29.2.2 Wavetable Categories

The wavetable library organizes content into hierarchical categories. The `refresh_wtlist()` function in `SurgeStorage.cpp` scans both factory and user directories:

```cpp
void SurgeStorage::refresh_wtlist()
{
    wt_list.clear();
    wt_category.clear();

    // Scan factory wavetables
    refresh_wtlistAddDir(false, "wavetables");

    // Scan third-party wavetables
    if (!config.scanWavetableAndPatches)
        refresh_wtlistAddDir(false, "wavetables_3rdparty");

    // Scan user wavetables
    refresh_wtlistAddDir(true, "Wavetables");

    // Build category hierarchy
    std::sort(wt_category.begin(), wt_category.end(), ...);
}
```

**Category Structure**:
```cpp
struct PatchCategory
{
    std::string name;                           // "Basic", "Sampled", etc.
    int order;                                  // Display order
    std::vector<PatchCategory> children;        // Subcategories
    bool isRoot;                                // Top-level category
    bool isFactory;                             // Factory vs user
    int internalid;                             // Unique identifier
    int numberOfPatchesInCategory;              // Direct children count
    int numberOfPatchesInCategoryAndChildren;   // Recursive count
};
```

### 29.2.3 Lazy Wavetable Loading

Wavetables use a queue-based lazy loading system to minimize initialization time. When an oscillator requests a wavetable, it's queued rather than loaded immediately:

```cpp
void SurgeStorage::load_wt(int id, Wavetable *wt, OscillatorStorage *osc)
{
    if (id >= 0 && id < wt_list.size())
    {
        wt->queue_id = id;
        wt->queue_filename = path_to_string(wt_list[id].path);
    }

    wt->current_id = id;
}
```

The actual loading happens during `perform_queued_wtloads()`, called during audio processing:

```cpp
void SurgeStorage::perform_queued_wtloads()
{
    for (int sc = 0; sc < n_scenes; sc++)
    {
        for (int o = 0; o < n_oscs; o++)
        {
            if (patch.scene[sc].osc[o].wt.queue_id != -1)
            {
                load_wt(patch.scene[sc].osc[o].wt.queue_id,
                        &patch.scene[sc].osc[o].wt,
                        &patch.scene[sc].osc[o]);
            }
        }
    }
}
```

### 29.2.4 Wavetable Loading Implementation

The `load_wt_wt()` function in `SurgeStorage.cpp` handles binary `.wt` file loading:

```cpp
bool SurgeStorage::load_wt_wt(string filename, Wavetable *wt, std::string &metadata)
{
    std::ifstream file(filename, std::ios::binary);
    if (!file)
    {
        reportError("Unable to open wavetable file: " + filename,
                    "Wavetable Loading Error");
        return false;
    }

    // Read header
    wt_header wh;
    file.read(reinterpret_cast<char *>(&wh), sizeof(wh));

    // Validate header
    if (strncmp(wh.tag, "vawt", 4) != 0)
    {
        reportError("Invalid wavetable format", "Wavetable Loading Error");
        return false;
    }

    // Read sample data
    size_t dataSize = wh.n_samples * wh.n_tables * sizeof(float);
    std::vector<char> data(dataSize);
    file.read(data.data(), dataSize);

    // Build wavetable structure
    wt->BuildWT(data.data(), wh, false);

    // Read optional metadata
    if (wh.flags & wtf_has_metadata)
    {
        std::getline(file, metadata, '\0');
    }

    return true;
}
```

WAV files are loaded via `load_wt_wav_portable()`, which analyzes the file to determine if it contains:
- **Single-cycle waveform**: One cycle for wavetable synthesis
- **Multi-frame wavetable**: Concatenated single cycles
- **Sample**: Non-periodic audio for one-shot playback

## 29.3 Tuning Resources

### 29.3.1 Tuning Library Organization

Surge XT ships with 182 Scala scale files (`.scl`) and 14 keyboard mapping files (`.kbm`) in `/home/user/surge/resources/data/tuning_library/`. This comprehensive collection covers:

**Scale Categories**:
- **SCL/**: 182 base scales
  - 12-tone equal temperament
  - Historical temperaments (Pythagorean, meantone, well-temperaments)
  - Microtonal equal divisions (5-71 EDO)
  - Just intonation scales (harmonic series, subharmonic series)
  - Non-octave systems (Bohlen-Pierce, Carlos Alpha/Beta/Gamma)
  - World music scales (Arabic maqamat, Indonesian gamelan)

- **Equal Linear Temperaments 17-71/**: Extended equal temperaments with precise frequency specifications

- **KBM Concert Pitch/**: 14 keyboard mapping files defining:
  - Reference pitch (A4 = 440 Hz standard and alternatives)
  - Middle note mapping
  - Scale degree mappings to MIDI notes

### 29.3.2 Scala File Format

Scala files use a simple text format defined by the Scala software. Example from `12 Tone Equal Temperament.scl`:

```
! 12 Tone Equal Temperament.scl
!
12 Tone Equal Temperament | ED2-12 - Equal division of harmonic 2 into 12 parts
 12
!
 100.00000
 200.00000
 300.00000
 400.00000
 500.00000
 600.00000
 700.00000
 800.00000
 900.00000
 1000.00000
 1100.00000
 2/1
```

**Format Structure**:
1. **Description line**: `! [filename]`
2. **Comment line**: Additional description
3. **Note count**: Number of notes per octave
4. **Scale degrees**: Either cents values or frequency ratios
   - Cents: `100.00000` (decimal number)
   - Ratios: `2/1` or `3/2` (fraction)

The tuning system integrates with the `Tunings` library (from `sst-tuning`), which provides the `Tunings::Scale` and `Tunings::KeyboardMapping` classes:

```cpp
// From SurgeStorage.h
class SurgeStorage
{
public:
    Tunings::Tuning twelveToneStandardMapping;
    Tunings::Tuning currentTuning;
    Tunings::Scale currentScale;
    Tunings::KeyboardMapping currentMapping;

    bool isStandardTuning = true;
    bool isStandardScale = true;
    bool isStandardMapping = true;

    // Tuning state management
    bool retuneToScale(const Tunings::Scale &s);
    bool remapToKeyboard(const Tunings::KeyboardMapping &k);
    bool retuneAndRemapToScaleAndMapping(const Tunings::Scale &s,
                                         const Tunings::KeyboardMapping &k);
};
```

### 29.3.3 Tuning Loading

The `loadTuningFromSCL()` and `loadMappingFromKBM()` functions load tuning resources:

```cpp
void SurgeStorage::loadTuningFromSCL(const fs::path &p)
{
    try
    {
        auto scale = Tunings::readSCLFile(path_to_string(p));
        retuneToScale(scale);
    }
    catch (const Tunings::TuningError &e)
    {
        reportError(e.what(), "Tuning Loading Error");
    }
}

void SurgeStorage::loadMappingFromKBM(const fs::path &p)
{
    try
    {
        auto mapping = Tunings::readKBMFile(path_to_string(p));
        remapToKeyboard(mapping);
    }
    catch (const Tunings::TuningError &e)
    {
        reportError(e.what(), "Mapping Loading Error");
    }
}
```

### 29.3.4 Tuning Application Modes

Surge XT supports two tuning application modes:

```cpp
enum TuningApplicationMode
{
    RETUNE_ALL = 0,        // Retune pitch tables globally
    RETUNE_MIDI_ONLY = 1   // Retune at MIDI layer only
} tuningApplicationMode = RETUNE_MIDI_ONLY;
```

**RETUNE_ALL**: Modifies the global pitch tables used by all oscillators:
```cpp
bool SurgeStorage::resetToCurrentScaleAndMapping()
{
    currentTuning = Tunings::Tuning(currentScale, currentMapping);

    if (!tuningTableIs12TET())
    {
        // Rebuild pitch tables with microtuning
        for (int i = 0; i < tuning_table_size; ++i)
        {
            table_pitch[i] = currentTuning.frequencyForMidiNote(i) / MIDI_0_FREQ;
            table_pitch_inv[i] = 1.0f / table_pitch[i];
        }
    }

    tuningUpdates++;  // Notify listeners of tuning change

    if (onTuningChanged)
        onTuningChanged();

    return true;
}
```

**RETUNE_MIDI_ONLY**: Applies tuning at the keyboard layer, leaving pitch tables in 12-TET for modulation and internal calculations.

## 29.4 Configuration Files

### 29.4.1 configuration.xml Structure

The `configuration.xml` file in `/home/user/surge/resources/surge-shared/` provides default settings for oscillator snapshots, effect presets, and MIDI controller mappings:

```xml
<?xml version="1.0" encoding="UTF-8" standalone="yes" ?>
<autometa name="" comment=""/>
<osc>
  <type i="0" name="Classic">
    <snapshot name="Sawtooth" p0="0.0" p1="0.5" p2="0.5"
              p3="0.0" p4="0.0" p5="0.1" p6="1" retrigger="0"/>
    <snapshot name="Square" p0="-1.0" p1="0.5" p2="0.5"
              p3="0.0" p4="0.0" p5="0.1" p6="1" retrigger="0"/>
  </type>
  <type i="8" name="Modern">
    <snapshot name="Sawtooth" p0="1.0" p1="0.0" p2="0.0"
              p3="0.5" p4="0.0" p5="0.1" p6="1" retrigger="0"/>
  </type>
  <!-- Additional oscillator types and snapshots -->
</osc>
<fx>
  <type i="1" name="Delay">
    <snapshot name="Init (Dry)" p0="-1.0" p1="-1.0"
              p0_temposync="1" p1_temposync="1" p10="0.25"/>
    <snapshot name="Init (Send)" p0="-1.0" p1="-1.0"
              p0_temposync="1" p1_temposync="1" p10="1.0"/>
  </type>
  <!-- Additional effect types and snapshots -->
</fx>
<customctrl>
  <entry p="0" ctrl="41" chan="-1"/>  <!-- Macro 1 -> CC 41 -->
  <entry p="1" ctrl="42" chan="-1"/>  <!-- Macro 2 -> CC 42 -->
  <!-- Additional custom controller mappings -->
</customctrl>
<midictrl/>
```

The configuration is loaded during `SurgeStorage` initialization:

```cpp
// Load configuration.xml
std::string cxmlData;
if (fs::exists(datapath / "configuration.xml"))
{
    std::ifstream ifs(datapath / "configuration.xml");
    std::stringstream buffer;
    buffer << ifs.rdbuf();
    cxmlData = buffer.str();
}

if (!snapshotloader.Parse(cxmlData.c_str()))
{
    reportError("Cannot parse 'configuration.xml' from memory. Internal Software Error.",
                "Surge Incorrectly Built");
}

load_midi_controllers();
```

### 29.4.2 UserDefaults System

The `UserDefaults` system in `/home/user/surge/src/common/UserDefaults.h` provides persistent key-value storage for user preferences:

```cpp
namespace Surge::Storage
{
enum DefaultKey
{
    DefaultZoom,                    // UI zoom level
    DefaultSkin,                    // Active skin name
    DefaultSkinRootType,            // Skin root type
    MenuLightness,                  // Menu brightness
    HighPrecisionReadouts,          // Display precision
    ModWindowShowsValues,           // Modulation window mode
    MiddleC,                        // Middle C notation (C3/C4/C5)
    UserDataPath,                   // Custom user data location
    DefaultPatchAuthor,             // Patch metadata default
    OverrideTuningOnPatchLoad,      // Tuning behavior
    RememberTabPositionsPerScene,   // UI state persistence
    MPEPitchBendRange,              // MPE configuration
    SmoothingMode,                  // Parameter smoothing

    // Overlay window positions
    TuningOverlayLocation,
    MSEGOverlayLocation,
    FormulaOverlayLocation,

    // OSC (Open Sound Control) settings
    StartOSCIn,
    StartOSCOut,
    OSCPortIn,
    OSCPortOut,

    nKeys  // Total count
};

typedef sst::plugininfra::defaults::Provider<DefaultKey, DefaultKey::nKeys>
    UserDefaultsProvider;

// Get/set functions
std::string getUserDefaultValue(SurgeStorage *storage, const DefaultKey &key,
                                const std::string &valueIfMissing);
int getUserDefaultValue(SurgeStorage *storage, const DefaultKey &key,
                       int valueIfMissing);
bool updateUserDefaultValue(SurgeStorage *storage, const DefaultKey &key,
                            const std::string &value);
}
```

The defaults are stored in an XML file at `userDataPath/SurgeXT/SurgeXTUserDefaults.xml`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<defaults>
  <default key="DefaultZoom" value="100"/>
  <default key="DefaultSkin" value="dark-mode.surge-skin"/>
  <default key="HighPrecisionReadouts" value="1"/>
  <default key="MiddleC" value="1"/>
  <default key="MPEPitchBendRange" value="48"/>
  <default key="TuningOverlayLocation" value="400,300"/>
  <!-- Additional preferences -->
</defaults>
```

The system uses the `sst::plugininfra::defaults::Provider` template for cross-platform storage:

```cpp
SurgeStorage::SurgeStorage(const SurgeStorageConfig &config)
{
    // Initialize UserDefaults provider
    userDefaultsProvider = std::make_unique<UserDefaultsProvider>(
        userDataPath,
        "SurgeXT",
        Surge::Storage::defaultKeyToString,
        Surge::Storage::defaultKeyToString
    );
}
```

## 29.5 Skin Resources

### 29.5.1 Skin Directory Structure

Skins are organized in self-contained `.surge-skin` directories containing XML configuration and image assets. From `/home/user/surge/resources/data/skins/`:

```
skins/
├── Tutorials/                      # Factory tutorial skins
│   ├── simple-skin/
│   │   ├── skin.xml                # Skin configuration
│   │   └── images/                 # PNG/SVG assets
│   └── advanced-skin/
└── dark-mode.surge-skin/           # Factory dark mode
    ├── skin.xml                    # Skin definition
    └── SVG/                        # Vector graphics
        ├── bmp00102.svg            # Background
        ├── bmp00105.svg            # Sliders
        ├── bmp00112.svg            # Buttons
        └── [additional assets]
```

User skins reside in `userDataPath/Skins/` and follow the same structure.

### 29.5.2 Skin Configuration Format

The `skin.xml` file defines visual properties and component overrides. See Chapter 26 for complete details. Brief example:

```xml
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<surge-skin name="Dark Mode" category="Factory" author="Surge Synth Team"
            version="2">
  <globals>
    <image resource="bmp00102" file="SVG/bmp00102.svg"/>
    <image resource="bmp00105" file="SVG/bmp00105.svg"/>
  </globals>

  <component-classes>
    <class name="slider.horizontal"
           slider_tray="bmp00105"
           handle_image="bmp00106"
           handle_hover_image="bmp00107"/>
  </component-classes>

  <colors>
    <color id="lfo.waveform.background" value="#1A1A1E"/>
    <color id="lfo.waveform.wave" value="#FF9000"/>
  </colors>

  <controls>
    <control ui_identifier="filter.cutoff_1" x="310" y="223"/>
    <control ui_identifier="filter.resonance_1" x="310" y="248"/>
  </controls>
</surge-skin>
```

### 29.5.3 Skin Resource Loading

Skin assets are loaded on-demand by the `Skin` class in `/home/user/surge/src/common/gui/Skin.cpp`:

```cpp
namespace Surge::GUI
{
class Skin
{
    // Image resource cache
    std::unordered_map<std::string, VSTGUI::CBitmap *> bitmapCache;

    // Lazy-load bitmap from skin
    VSTGUI::CBitmap *getBitmap(const std::string &id)
    {
        // Check cache first
        auto it = bitmapCache.find(id);
        if (it != bitmapCache.end())
            return it->second;

        // Load from disk
        auto path = skinRootPath / imageResources[id].file;
        auto bitmap = loadBitmapFromFile(path);

        // Cache for reuse
        bitmapCache[id] = bitmap;
        return bitmap;
    }
};
}
```

SVG files are rasterized to the current zoom level, providing resolution-independent UI scaling. PNG files are loaded directly and scaled as needed.

### 29.5.4 Skin Asset Types

Skins can reference several asset types:

**Image Resources**:
- **Background**: Main UI background (typically `bmp00102.svg`)
- **Sliders**: Tray and handle images for various slider types
- **Buttons**: Multi-frame button states
- **Displays**: Oscilloscope, waveform, and visualization backgrounds
- **Controls**: Switches, knobs, and specialized UI elements

**Vector vs Raster**:
- **SVG**: Preferred for scalable UI, rasterized at runtime to current zoom
- **PNG**: Faster loading, fixed resolution, scaled with filtering

The skin system integrates with the three-layer architecture (compiled defaults → skin XML → runtime) described in Chapter 26.

## 29.6 Window State Persistence

### 29.6.1 DAWExtraStateStorage

Window positions, overlay states, and UI preferences persist across sessions via `DAWExtraStateStorage` in `/home/user/surge/src/common/SurgeStorage.h`:

```cpp
struct DAWExtraStateStorage
{
    bool isPopulated = false;

    struct EditorState
    {
        int instanceZoomFactor = -1;      // UI zoom (100%, 125%, etc.)
        int current_scene = 0;            // Active scene (A or B)
        int current_fx = 0;               // Active FX slot
        int current_osc[n_scenes] = {0};  // Active oscillator per scene

        bool isMSEGOpen = false;
        modsources modsource = ms_lfo1;
        modsources modsource_editor[n_scenes] = {ms_lfo1, ms_lfo1};

        // Overlay window states
        struct OverlayState
        {
            int whichOverlay{-1};             // Overlay type identifier
            bool isTornOut{false};            // Torn out to separate window
            std::pair<int, int> tearOutPosition{-1, -1};  // Window position
        };
        std::vector<OverlayState> activeOverlays;

        // Formula editor state per LFO
        struct FormulaEditState
        {
            int codeOrPrelude{0};             // Code/prelude tab
            bool debuggerOpen{false};         // Debug panel toggle
            bool debuggerUserVariablesOpen{true};
            bool debuggerBuiltInVariablesOpen{true};

            struct CodeEditorState
            {
                int scroll{0};                // Scroll position
                int caretPosition{0};         // Cursor position
                int selectStart{0};           // Selection range
                int selectEnd{0};

                bool popupOpen{false};        // Find/replace popup
                int popupType{0};
                std::string popupText1{""};
            } codeEditor;
        } formulaEditState[n_scenes][n_lfos];

        // Wavetable script editor state per oscillator
        struct WavetableScriptEditState
        {
            int codeOrPrelude{0};
            CodeEditorState codeEditor;
        } wavetableScriptEditState[n_scenes][n_oscs];

        // Oscilloscope overlay state
        struct OscilloscopeOverlayState
        {
            int mode = 0;                     // 0=waveform, 1=spectrum
            float trigger_speed = 0.5f;
            float trigger_level = 0.5f;
            float time_window = 0.5f;
            bool dc_kill = false;
        } oscilloscopeOverlayState;

        // Tuning overlay state
        struct TuningOverlayState
        {
            int editMode = 0;                 // Tuning edit mode
        } tuningOverlayState;

        // Modulation editor state
        struct ModulationEditorState
        {
            int sortOrder = 0;                // Modulation list sort
            int filterOn = 0;                 // Filter active
            std::string filterString{""};    // Filter text
        } modulationEditorState;

    } editor;

    // MPE configuration
    bool mpeEnabled = false;
    int mpePitchBendRange = -1;
    bool mpeTimbreIsUnipolar = false;

    // Tuning state
    bool hasScale = false;
    std::string scaleContents = "";
    bool hasMapping = false;
    std::string mappingContents = "";

    // MIDI mappings
    std::map<int, int> midictrl_map;      // param -> CC
    std::map<int, int> midichan_map;      // param -> channel

    // OSC (Open Sound Control) state
    int oscPortIn{DEFAULT_OSC_PORT_IN};
    int oscPortOut{DEFAULT_OSC_PORT_OUT};
    std::string oscIPAddrOut{DEFAULT_OSC_IPADDR_OUT};
    bool oscStartIn{false};
    bool oscStartOut{false};

    fs::path lastLoadedPatch{};
};
```

### 29.6.2 State Persistence Flow

The DAW extra state is saved and restored through the plugin's state mechanism:

**Save Flow**:
1. `SurgeGUIEditor::populateDawExtraState()` - Collects current UI state
2. `SurgePatch::save_xml()` - Serializes state to XML within patch
3. Plugin host saves patch state to project file

**Restore Flow**:
1. Plugin host loads patch state from project
2. `SurgePatch::load_xml()` - Deserializes DAW extra state
3. `SurgeGUIEditor::loadFromDawExtraState()` - Applies state to UI

Example serialization (from `SurgePatch::save_xml()`):

```cpp
void SurgePatch::save_xml(void **data)
{
    // ... main patch data ...

    if (dawExtraState.isPopulated)
    {
        TiXmlElement dawExtra("dawextra");

        // Save editor state
        dawExtra.SetAttribute("instanceZoomFactor",
                             dawExtraState.editor.instanceZoomFactor);
        dawExtra.SetAttribute("current_scene",
                             dawExtraState.editor.current_scene);
        dawExtra.SetAttribute("current_fx",
                             dawExtraState.editor.current_fx);

        // Save overlay states
        for (auto &overlay : dawExtraState.editor.activeOverlays)
        {
            TiXmlElement ov("overlay");
            ov.SetAttribute("which", overlay.whichOverlay);
            ov.SetAttribute("isTornOut", overlay.isTornOut);
            ov.SetAttribute("x", overlay.tearOutPosition.first);
            ov.SetAttribute("y", overlay.tearOutPosition.second);
            dawExtra.InsertEndChild(ov);
        }

        // ... additional state ...
        root.InsertEndChild(dawExtra);
    }
}
```

### 29.6.3 Window Position Management

Overlay windows (MSEG editor, Formula editor, etc.) store their position via the UserDefaults system for tear-out windows and DAWExtraState for embedded overlays:

**Tear-Out Windows** (separate OS windows):
```cpp
// Save position to UserDefaults
void saveTearOutPosition(int overlayType, int x, int y)
{
    auto key = overlayTypeToLocationKey(overlayType);
    updateUserDefaultValue(storage, key, std::make_pair(x, y));
}

// Restore position from UserDefaults
std::pair<int, int> loadTearOutPosition(int overlayType)
{
    auto key = overlayTypeToLocationKey(overlayType);
    return getUserDefaultValue(storage, key, std::make_pair(100, 100));
}
```

**Embedded Overlays** (within main window):
```cpp
// Stored in DAWExtraState for session persistence
dawExtraState.editor.activeOverlays.push_back({
    whichOverlay: MSEG_EDITOR,
    isTornOut: false,
    tearOutPosition: {-1, -1}
});
```

## 29.7 Resource Loading Strategies

### 29.7.1 Lazy Loading Architecture

Surge XT employs lazy loading to minimize startup time and memory footprint. Resources load on-demand rather than at initialization.

**Wavetable Queue System**:
```cpp
// Request wavetable (queues for later loading)
void load_wt(int id, Wavetable *wt, OscillatorStorage *osc)
{
    wt->queue_id = id;
    wt->queue_filename = wt_list[id].path;
    wt->current_id = id;
}

// Process queue during audio callback preparation
void perform_queued_wtloads()
{
    for (int sc = 0; sc < n_scenes; sc++)
    {
        for (int o = 0; o < n_oscs; o++)
        {
            if (patch.scene[sc].osc[o].wt.queue_id != -1)
            {
                // Load now, during audio-safe time
                auto &wt = patch.scene[sc].osc[o].wt;
                std::string metadata;

                if (load_wt_wt(wt.queue_filename, &wt, metadata))
                {
                    wt.current_filename = wt.queue_filename;
                }

                wt.queue_id = -1;  // Clear queue
            }
        }
    }
}
```

**Skin Asset Caching**:
```cpp
// Skins cache loaded bitmaps to avoid redundant disk access
std::unordered_map<std::string, VSTGUI::CBitmap *> bitmapCache;

VSTGUI::CBitmap *getBitmap(const std::string &id)
{
    // Check cache first
    auto it = bitmapCache.find(id);
    if (it != bitmapCache.end())
        return it->second;

    // Load and cache
    auto bitmap = loadBitmapFromFile(skinRootPath / imageResources[id].file);
    bitmapCache[id] = bitmap;
    return bitmap;
}
```

### 29.7.2 Directory Scanning

Patch and wavetable libraries scan directories once at startup, building in-memory databases:

```cpp
void SurgeStorage::refresh_wtlist()
{
    wt_list.clear();
    wt_category.clear();

    // Scan factory content
    refresh_wtlistFrom(false, datapath / "wavetables", "wavetables");
    refresh_wtlistFrom(false, datapath / "wavetables_3rdparty", "wavetables_3rdparty");

    // Scan user content
    refresh_wtlistFrom(true, userWavetablesPath, "");

    // Build category hierarchy and sort
    buildCategoryHierarchy(wt_category);
    sortWavetableList(wt_list, wt_category);
}
```

The scan results populate vectors:
```cpp
std::vector<Patch> wt_list;              // All wavetable entries
std::vector<PatchCategory> wt_category;  // Category hierarchy
std::vector<int> wtOrdering;             // Display order indices
```

### 29.7.3 Caching Strategies

**Wavetable Mipmap Caching**:
Wavetables pre-compute band-limited mipmaps during loading to avoid runtime computation:

```cpp
void Wavetable::MipMapWT()
{
    // Generate band-limited versions for different pitches
    for (int mipmap = 1; mipmap < max_mipmap_levels; mipmap++)
    {
        int samples = size >> mipmap;  // Half samples per mipmap

        for (int table = 0; table < n_tables; table++)
        {
            // Low-pass filter to prevent aliasing
            applyBandlimitFilter(TableF32WeakPointers[mipmap-1][table],
                                TableF32WeakPointers[mipmap][table],
                                samples * 2, samples);
        }
    }
}
```

**Tuning Table Caching**:
The pitch table cache avoids recalculating frequency-to-pitch conversions:

```cpp
static constexpr int tuning_table_size = 512;
float table_pitch[tuning_table_size];         // MIDI note to pitch
float table_pitch_inv[tuning_table_size];     // Inverse for fast division
float table_note_omega[2][tuning_table_size]; // Pre-computed omega values
```

Tables update only when tuning changes, tracked by `std::atomic<uint64_t> tuningUpdates`.

### 29.7.4 Error Handling

Resource loading employs comprehensive error handling via `reportError()`:

```cpp
void SurgeStorage::reportError(const std::string &msg, const std::string &title,
                               const ErrorType errorType, bool reportToStdout)
{
    if (reportToStdout)
        std::cerr << title << ": " << msg << std::endl;

    // Notify registered error listeners
    if (!errorListeners.empty())
    {
        for (auto *listener : errorListeners)
            listener->onSurgeError(msg, title, errorType);
    }
    else
    {
        // Queue for later if no listeners registered yet
        std::lock_guard<std::mutex> g(preListenerErrorMutex);
        preListenerErrors.push_back({msg, title, errorType});
    }
}
```

The `ErrorListener` interface allows the GUI to display errors to users:

```cpp
struct ErrorListener
{
    virtual void onSurgeError(const std::string &msg,
                             const std::string &title,
                             const ErrorType &errorType) = 0;
};
```

**Error Categories**:
```cpp
enum ErrorType
{
    GENERAL_ERROR = 1,              // Generic errors
    AUDIO_INPUT_LATENCY_WARNING = 2 // Audio-specific warnings
};
```

Common error scenarios:
- **File Not Found**: Invalid wavetable/patch paths
- **Parse Errors**: Malformed XML or binary data
- **Permission Denied**: Read-only user directories
- **Format Errors**: Invalid file formats or corrupted data
- **Out of Memory**: Large wavetable allocations

### 29.7.5 Thread Safety

Resource loading operations must be thread-safe as they occur from both UI and audio threads:

**Mutex Protection**:
```cpp
class SurgeStorage
{
    std::mutex waveTableDataMutex;      // Protects wavetable operations
    std::recursive_mutex modRoutingMutex; // Protects modulation routing

    // Safe wavetable loading
    void load_wt_threadsafe(int id, Wavetable *wt)
    {
        std::lock_guard<std::mutex> lock(waveTableDataMutex);
        load_wt(id, wt, nullptr);
    }
};
```

**Atomic Flags**:
```cpp
std::atomic<bool> userDataPathValid{false};  // User directory accessibility
std::atomic<uint64_t> tuningUpdates{2};      // Tuning change notifications
```

The queue-based wavetable loading ensures thread safety by deferring actual file I/O to a controlled point in the audio processing cycle.

## 29.8 Resource Management Best Practices

### 29.8.1 Adding New Resource Types

When adding new resource types to Surge XT:

1. **Define storage location**:
   ```cpp
   fs::path userNewResourcePath = userDataPath / "New Resources";
   ```

2. **Create directory during initialization**:
   ```cpp
   void createUserDirectory()
   {
       fs::create_directories(userNewResourcePath);
   }
   ```

3. **Implement scanning function**:
   ```cpp
   void refresh_newresource_list()
   {
       newresource_list.clear();
       scanDirectory(datapath / "new_resources", false);  // Factory
       scanDirectory(userNewResourcePath, true);          // User
   }
   ```

4. **Use lazy loading where appropriate**:
   ```cpp
   void load_newresource(int id)
   {
       queue_id = id;  // Queue for later
   }

   void perform_queued_newresource_loads()
   {
       // Load during safe time
   }
   ```

5. **Add error handling**:
   ```cpp
   try {
       loadResource(path);
   } catch (const std::exception &e) {
       reportError(e.what(), "Resource Loading Error");
   }
   ```

### 29.8.2 Performance Considerations

**Minimize Startup Scanning**:
- Limit directory depth during scans
- Use file system iteration rather than recursive scanning
- Cache scan results in memory

**Optimize File I/O**:
- Load resources asynchronously when possible
- Use memory-mapped files for large resources
- Batch multiple small reads into single operations

**Memory Management**:
- Release unused resources promptly
- Use weak pointers for cached data
- Implement resource limits for large collections

### 29.8.3 Cross-Platform Compatibility

Resource paths must work across Windows, macOS, and Linux:

```cpp
// Use fs::path for automatic separator handling
fs::path resourcePath = datapath / "wavetables" / "Basic" / "Sine.wt";

// NOT: std::string path = datapath + "/wavetables/Basic/Sine.wt";
```

String conversion helpers ensure proper encoding:
```cpp
std::string path_to_string(const fs::path &p)
{
    return p.u8string();  // UTF-8 encoding
}

fs::path string_to_path(const std::string &s)
{
    return fs::u8path(s);  // UTF-8 interpretation
}
```

## 29.9 Future Directions

The resource management system continues to evolve:

**Database-Backed Catalogs**: Replace file scanning with SQLite databases for instant startup with thousands of patches and wavetables.

**Cloud Resource Sync**: Sync user content across devices via cloud storage integration.

**Asset Compression**: Support compressed wavetable and skin formats to reduce disk footprint.

**Incremental Loading**: Load patch/wavetable metadata separately from full content, enabling faster browser population.

**Resource Validation**: Checksum verification for factory content to detect corruption.

---

This chapter has explored Surge XT's comprehensive resource management infrastructure, from directory organization and file formats to lazy loading and caching strategies. The system balances immediate responsiveness with memory efficiency, supporting both factory content and unlimited user expansion while maintaining cross-platform compatibility and thread safety.

The next chapter examines the microtuning system in detail, building on the tuning resource infrastructure covered here to explore the mathematical and musical theory behind Surge XT's advanced intonation capabilities.
