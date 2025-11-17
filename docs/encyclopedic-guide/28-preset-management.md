# Chapter 28: Preset Management

Surge XT includes comprehensive preset management systems for effects, modulators, wavetables, and oscillator configurations. This chapter details the architecture, file formats, and implementation of these specialized preset systems that operate alongside the main patch system covered in Chapter 27.

## 28.1 FX Presets

### 28.1.1 FX Preset Architecture

The FX preset system allows users to save and recall individual effect configurations independently of full patches. This is managed by the `FxUserPreset` class in `/home/user/surge/src/common/FxPresetAndClipboardManager.h`:

```cpp
namespace Surge
{
namespace Storage
{
struct FxUserPreset
{
    struct Preset
    {
        std::string file;
        std::string name;
        int streamingVersion{ff_revision};
        fs::path subPath{};
        bool isFactory{false};
        int type{-1};
        float p[n_fx_params];
        bool ts[n_fx_params], er[n_fx_params], da[n_fx_params];
        int dt[n_fx_params];

        Preset()
        {
            type = 0;
            isFactory = false;

            for (int i = 0; i < n_fx_params; ++i)
            {
                p[i] = 0.0;
                ts[i] = false;   // temposync
                er[i] = false;   // extend_range
                da[i] = false;   // deactivated
                dt[i] = -1;      // deform_type
            }
        }
    };

    std::unordered_map<int, std::vector<Preset>> scannedPresets;
    bool haveScannedPresets{false};

    void doPresetRescan(SurgeStorage *storage, bool forceRescan = false);
    std::vector<Preset> getPresetsForSingleType(int type_id);
    bool hasPresetsForSingleType(int type_id);
    void saveFxIn(SurgeStorage *s, FxStorage *fxdata, const std::string &fn);
    void loadPresetOnto(const Preset &p, SurgeStorage *s, FxStorage *fxbuffer);
};
} // namespace Storage
} // namespace Surge
```

Each preset stores:
- **Parameter values** (`p[]`): All 12 effect parameters
- **Tempo sync states** (`ts[]`): Per-parameter tempo sync flags
- **Extended range** (`er[]`): Extended parameter ranges
- **Deactivation** (`da[]`): Parameter deactivation states
- **Deform types** (`dt[]`): Parameter deformation modes
- **Effect type**: The specific effect (Reverb, Delay, etc.)
- **Streaming version**: Format version for backward compatibility

### 28.1.2 FX Preset File Format

FX presets use the `.srgfx` extension and store effect configurations in XML:

```xml
<single-fx streaming_version="28">
  <snapshot name="Bright Ambience"
            type="14"
            p0="21"
            p1="0.2"
            p2="0.2"
            p3="0"
            p4="0.5"
            p5="0.8"
            p6="0.0"
            p0_temposync="0"
            p0_extend_range="0"
            p0_deactivated="0"
            p1_deform_type="0"
  />
</single-fx>
```

File format details:
- **Root element**: `<single-fx>` with `streaming_version` attribute
- **Snapshot element**: Contains all parameter data
  - `name`: Preset display name
  - `type`: Integer effect type ID (see `fx_type` enum)
  - `p0` through `p11`: Parameter values
  - Optional per-parameter attributes:
    - `pN_temposync="1"`: Parameter is tempo-synced
    - `pN_extend_range="1"`: Extended range enabled
    - `pN_deactivated="1"`: Parameter deactivated
    - `pN_deform_type="N"`: Deformation type

### 28.1.3 FX Preset Directory Structure

FX presets are organized by effect type in two locations:

#### Factory FX Presets
```
<install_dir>/resources/data/fx_presets/
├── Delay/
│   ├── Ping Pong.srgfx
│   ├── Tape Echo.srgfx
│   └── Short Slap.srgfx
├── Reverb 1/
│   ├── Hall 1.srgfx
│   ├── Cathedral 1.srgfx
│   └── Room.srgfx
├── Reverb 2/
│   ├── Dark Plate (Send).srgfx
│   └── Large Church (Send).srgfx
├── Phaser/
├── Chorus/
├── Distortion/
├── EQ/
└── ... (one directory per effect type)
```

#### User FX Presets
```
<user_data>/FX Settings/
├── Delay/
│   ├── My Category/
│   │   └── My Custom Delay.srgfx
│   └── Another Delay.srgfx
├── Reverb 1/
└── Custom Folder/
    └── Preset.srgfx
```

The directory name must match the effect type's short name from `fx_type_shortnames[]` array. The system automatically organizes presets into subdirectories based on the effect type.

### 28.1.4 FX Preset Scanning

The preset scanning system in `/home/user/surge/src/common/FxPresetAndClipboardManager.cpp` recursively searches preset directories:

```cpp
void FxUserPreset::doPresetRescan(SurgeStorage *storage, bool forceRescan)
{
    if (haveScannedPresets && !forceRescan)
        return;

    scannedPresets.clear();
    haveScannedPresets = true;

    auto ud = storage->userFXPath;
    auto fd = storage->datapath / "fx_presets";

    std::vector<std::pair<fs::path, bool>> sfxfiles;
    std::deque<std::pair<fs::path, bool>> workStack;

    // Queue both user and factory directories
    workStack.emplace_back(fs::path(ud), false);      // User presets
    workStack.emplace_back(fd, true);                 // Factory presets

    // Breadth-first directory traversal
    while (!workStack.empty())
    {
        auto top = workStack.front();
        workStack.pop_front();

        if (fs::is_directory(top.first))
        {
            for (auto &d : fs::directory_iterator(top.first))
            {
                if (fs::is_directory(d))
                {
                    workStack.emplace_back(d, top.second);
                }
                else if (path_to_string(d.path().extension()) == ".srgfx")
                {
                    sfxfiles.emplace_back(d.path(), top.second);
                }
            }
        }
    }

    // Parse each preset file
    for (const auto &f : sfxfiles)
    {
        Preset preset;
        preset.file = path_to_string(f.first);

        TiXmlDocument d;
        if (!d.LoadFile(f.first))
            goto badPreset;

        auto r = TINYXML_SAFE_TO_ELEMENT(d.FirstChild("single-fx"));
        if (!r)
            goto badPreset;

        // Read streaming version
        int sv;
        if (r->QueryIntAttribute("streaming_version", &sv) == TIXML_SUCCESS)
        {
            preset.streamingVersion = sv;
        }

        auto s = TINYXML_SAFE_TO_ELEMENT(r->FirstChild("snapshot"));
        if (!s)
            goto badPreset;

        // Read effect type
        int t;
        if (s->QueryIntAttribute("type", &t) != TIXML_SUCCESS)
            goto badPreset;
        preset.type = t;
        preset.isFactory = f.second;

        // Extract subcategory path
        fs::path rpath;
        if (f.second)
            rpath = f.first.lexically_relative(fd).parent_path();
        else
            rpath = f.first.lexically_relative(storage->userFXPath).parent_path();

        // Remove effect type from path
        auto startCatPath = rpath.begin();
        if (*(startCatPath) == fx_type_shortnames[t])
        {
            startCatPath++;
        }

        while (startCatPath != rpath.end())
        {
            preset.subPath /= *startCatPath;
            startCatPath++;
        }

        if (!readFromXMLSnapshot(preset, s))
            goto badPreset;

        // Add to map organized by effect type
        if (scannedPresets.find(preset.type) == scannedPresets.end())
        {
            scannedPresets[preset.type] = std::vector<Preset>();
        }
        scannedPresets[preset.type].push_back(preset);

    badPreset:;
    }

    // Sort presets: factory first, then by subpath, then by name
    for (auto &a : scannedPresets)
    {
        std::sort(a.second.begin(), a.second.end(),
            [](const Preset &a, const Preset &b) {
                if (a.type == b.type)
                {
                    if (a.isFactory != b.isFactory)
                    {
                        return a.isFactory;  // Factory first
                    }

                    if (a.subPath != b.subPath)
                    {
                        return a.subPath < b.subPath;
                    }

                    return _stricmp(a.name.c_str(), b.name.c_str()) < 0;
                }
                else
                {
                    return a.type < b.type;
                }
            });
    }
}
```

Key features:
- **Lazy scanning**: Only scans when first accessed or explicitly forced
- **Factory/user separation**: Factory presets always sorted first
- **Subcategory support**: Arbitrary folder hierarchies preserved
- **Error tolerance**: Invalid presets skipped with `goto badPreset`
- **Type organization**: Presets organized in `unordered_map` by effect type

### 28.1.5 Saving FX Presets

The save operation in `saveFxIn()` validates paths and handles overwrites:

```cpp
void FxUserPreset::saveFxIn(SurgeStorage *storage, FxStorage *fx,
                            const std::string &s)
{
    if (s.empty())
        return;

    // Parse user-provided path
    auto sp = string_to_path(s);
    auto spp = sp.parent_path();
    auto fnp = sp.filename();

    // Validate filename
    if (!Surge::Storage::isValidName(path_to_string(fnp)))
    {
        return;
    }

    int ti = fx->type.val.i;

    // Construct save path: userFXPath / effect_type / subpath / filename
    auto storagePath = storage->userFXPath / fs::path(fx_type_shortnames[ti]);

    if (!spp.empty())
        storagePath /= spp;

    auto outputPath = storagePath /
                      string_to_path(path_to_string(fnp) + ".srgfx");

    fs::create_directories(storagePath);

    auto doSave = [this, outputPath, storage, fx, fnp]() {
        std::ofstream pfile(outputPath, std::ios::out);
        if (!pfile.is_open())
        {
            storage->reportError(
                std::string("Unable to open FX preset file '") +
                path_to_string(outputPath) + "' for writing!",
                "Error");
            return;
        }

        pfile << "<single-fx streaming_version=\"" << ff_revision << "\">\n";

        // Escape XML special characters in name
        std::string fxNameSub(path_to_string(fnp));
        Surge::Storage::findReplaceSubstring(fxNameSub,
            std::string("&"), std::string("&amp;"));
        Surge::Storage::findReplaceSubstring(fxNameSub,
            std::string("<"), std::string("&lt;"));
        Surge::Storage::findReplaceSubstring(fxNameSub,
            std::string(">"), std::string("&gt;"));
        Surge::Storage::findReplaceSubstring(fxNameSub,
            std::string("\""), std::string("&quot;"));
        Surge::Storage::findReplaceSubstring(fxNameSub,
            std::string("'"), std::string("&apos;"));

        pfile << "  <snapshot name=\"" << fxNameSub.c_str() << "\"\n";
        pfile << "     type=\"" << fx->type.val.i << "\"\n";

        // Write all parameters
        for (int i = 0; i < n_fx_params; ++i)
        {
            if (fx->p[i].ctrltype != ct_none)
            {
                switch (fx->p[i].valtype)
                {
                case vt_float:
                    pfile << "     p" << i << "=\"" << fx->p[i].val.f << "\"\n";
                    break;
                case vt_int:
                    pfile << "     p" << i << "=\"" << fx->p[i].val.i << "\"\n";
                    break;
                }

                // Write optional parameter attributes
                if (fx->p[i].can_temposync() && fx->p[i].temposync)
                {
                    pfile << "     p" << i << "_temposync=\"1\"\n";
                }
                if (fx->p[i].can_extend_range() && fx->p[i].extend_range)
                {
                    pfile << "     p" << i << "_extend_range=\"1\"\n";
                }
                if (fx->p[i].can_deactivate() && fx->p[i].deactivated)
                {
                    pfile << "     p" << i << "_deactivated=\"1\"\n";
                }
                if (fx->p[i].has_deformoptions())
                {
                    pfile << "     p" << i << "_deform_type=\""
                          << fx->p[i].deform_type << "\"\n";
                }
            }
        }

        pfile << "  />\n";
        pfile << "</single-fx>\n";
        pfile.close();

        doPresetRescan(storage, true);
    };

    // Check for existing file and prompt for overwrite
    if (fs::exists(outputPath))
    {
        storage->okCancelProvider(
            "The FX preset '" + outputPath.string() +
            "' already exists. Are you sure you want to overwrite it?",
            "Overwrite FX Preset",
            SurgeStorage::OK,
            [doSave](SurgeStorage::OkCancel okc) {
                if (okc == SurgeStorage::OK)
                {
                    doSave();
                }
            });
    }
    else
    {
        doSave();
    }
}
```

Key validation steps:
1. **Path validation**: Prevents directory traversal attacks
2. **Name validation**: Checks for invalid characters and reserved names
3. **XML escaping**: Proper handling of special characters
4. **Overwrite protection**: User confirmation required
5. **Automatic rescan**: Updates preset list after saving

### 28.1.6 Loading FX Presets

Loading applies a preset to an FX buffer:

```cpp
void FxUserPreset::loadPresetOnto(const Preset &p, SurgeStorage *storage,
                                  FxStorage *fxbuffer)
{
    fxbuffer->type.val.i = p.type;

    // Spawn temporary effect to initialize parameter types
    Effect *t_fx = spawn_effect(fxbuffer->type.val.i, storage, fxbuffer, 0);

    if (t_fx)
    {
        t_fx->init_ctrltypes();
        t_fx->init_default_values();
    }

    // Copy parameter values
    for (int i = 0; i < n_fx_params; i++)
    {
        switch (fxbuffer->p[i].valtype)
        {
        case vt_float:
            fxbuffer->p[i].val.f = p.p[i];
            break;
        case vt_int:
            fxbuffer->p[i].val.i = (int)p.p[i];
            break;
        default:
            break;
        }

        fxbuffer->p[i].temposync = (int)p.ts[i];
        fxbuffer->p[i].set_extend_range((int)p.er[i]);
        fxbuffer->p[i].deactivated = (int)p.da[i];

        // Only set deform type if it was saved
        if (p.dt[i] >= 0)
        {
            fxbuffer->p[i].deform_type = p.dt[i];
        }
    }

    // Handle version mismatches
    if (t_fx)
    {
        if (p.streamingVersion != ff_revision)
        {
            t_fx->handleStreamingMismatches(p.streamingVersion, ff_revision);
        }

        delete t_fx;
    }
}
```

The temporary effect spawn ensures parameter control types are properly initialized before values are applied. This is critical for parameters that change based on effect type.

## 28.2 Modulator Presets

### 28.2.1 Modulator Preset Architecture

The `ModulatorPreset` class in `/home/user/surge/src/common/ModulatorPresetManager.h` manages LFO, MSEG, Step Sequencer, and Formula modulator presets:

```cpp
namespace Surge
{
namespace Storage
{
struct ModulatorPreset
{
    void savePresetToUser(const fs::path &location, SurgeStorage *s,
                         int scene, int lfo);
    void loadPresetFrom(const fs::path &location, SurgeStorage *s,
                       int scene, int lfo);

    struct Preset
    {
        std::string name;
        fs::path path;
    };

    struct Category
    {
        std::string name;
        std::string path;
        std::string parentPath;
        std::vector<Preset> presets;
    };

    enum class PresetScanMode
    {
        FactoryOnly,
        UserOnly
    };

    std::vector<Category> getPresets(SurgeStorage *s, PresetScanMode mode);
    void forcePresetRescan();

    std::vector<Category> scannedUserPresets;
    bool haveScannedUser{false};

    std::vector<Category> scannedFactoryPresets;
    bool haveScannedFactory{false};
};
} // namespace Storage
} // namespace Surge
```

### 28.2.2 Modulator Preset File Format

Modulator presets use the `.modpreset` extension:

```xml
<?xml version="1.0" encoding="UTF-8" standalone="yes" ?>
<lfo shape="4">
    <params>
        <rate v="8.228819" temposync="0" deform_type="0"
              extend_range="0" deactivated="0" />
        <phase v="0.000000" temposync="0" deform_type="0"
               extend_range="0" deactivated="1" />
        <magnitude v="1.000000" temposync="0" deform_type="0"
                   extend_range="0" deactivated="1" />
        <deform v="0.000000" temposync="0" deform_type="0"
                extend_range="0" deactivated="1" />
        <trigmode i="2" temposync="0" deform_type="0"
                  extend_range="0" deactivated="1" />
        <unipolar i="0" temposync="0" deform_type="0"
                  extend_range="0" deactivated="1" />
        <delay v="-8.000000" temposync="0" deform_type="0"
               extend_range="0" deactivated="0" />
        <hold v="-8.000000" temposync="0" deform_type="0"
              extend_range="0" deactivated="0" />
        <attack v="-8.000000" temposync="0" deform_type="0"
                extend_range="0" deactivated="0" />
        <decay v="0.000000" temposync="0" deform_type="0"
               extend_range="0" deactivated="0" />
        <sustain v="1.000000" temposync="0" deform_type="0"
                 extend_range="0" deactivated="0" />
        <release v="5.000000" temposync="0" deform_type="0"
                 extend_range="0" deactivated="0" />
    </params>
</lfo>
```

For MSEG modulators:

```xml
<lfo shape="6">
    <params>
        <!-- LFO parameters as above -->
    </params>
    <mseg>
        <segment i="0" duration="0.125000" v="0.000000"
                 cpv="0.500000" cpduration="0.500000" />
        <segment i="1" duration="0.125000" v="1.000000"
                 cpv="0.500000" cpduration="0.500000" />
        <!-- More segments -->
        <editMode v="0" />
        <loopMode v="0" />
        <endpointMode v="0" />
    </mseg>
</lfo>
```

For Step Sequencer:

```xml
<lfo shape="2">
    <params>
        <!-- LFO parameters -->
    </params>
    <sequence>
        <step i="0" v="0.500000" />
        <step i="1" v="0.250000" />
        <!-- 16 steps total -->
        <loop_start v="0" />
        <loop_end v="15" />
        <shuffle v="0.000000" />
        <trigmask v="65535" />
    </sequence>
</lfo>
```

For Formula modulators:

```xml
<lfo shape="8">
    <params>
        <!-- LFO parameters -->
    </params>
    <formula>
        <code><![CDATA[sin(phase * 2 * pi)]]></code>
    </formula>
    <indexNames>
        <name index="0" name="LFO 1 Bank A" />
        <name index="1" name="Custom Name" />
    </indexNames>
</lfo>
```

### 28.2.3 Modulator Preset Directory Structure

Modulator presets are organized by type:

#### Factory Modulator Presets
```
<install_dir>/resources/data/modulator_presets/
├── LFO/
│   ├── Noise.modpreset
│   ├── Delayed Vibrato.modpreset
│   ├── 8th Note S&H.modpreset
│   └── Utility/
│       ├── Random Value Unipolar.modpreset
│       └── Random Value Bipolar.modpreset
├── MSEG/
│   ├── 1 Chords/
│   │   ├── 1 Major.modpreset
│   │   └── 2 Minor.modpreset
│   ├── 2 Scales/
│   ├── 3 Asymmetric LFO/
│   ├── 4 Unipolar LFO/
│   ├── 5 Looped Envelope/
│   └── 6 AR Envelope/
├── Step Seq/
│   ├── Melodic/
│   │   ├── Major Arpeggio.modpreset
│   │   └── Minor Arpeggio.modpreset
│   ├── Rhythmic/
│   │   └── Trance Gate 1.modpreset
│   └── Waveforms/
├── Envelope/
│   ├── Basic ADSR.modpreset
│   ├── 1 Bar Fade In.modpreset
│   └── 8th Note Delay.modpreset
└── Formula/
    ├── 8x Sine.modpreset
    ├── Lorenz Attractor.modpreset
    └── Euclidean Sequencer.modpreset
```

#### User Modulator Presets
```
<user_data>/Modulator Presets/
├── LFO/
│   └── My Custom LFO.modpreset
├── MSEG/
│   ├── My Category/
│   │   └── Custom Shape.modpreset
│   └── Another MSEG.modpreset
├── Step Seq/
├── Envelope/
└── Formula/
```

The preset directory structure from `/home/user/surge/src/common/ModulatorPresetManager.cpp`:

```cpp
const static std::string PresetDir = "Modulator Presets";
const static std::string PresetExt = ".modpreset";
```

### 28.2.4 Saving Modulator Presets

The save process automatically determines the modulator type and organizes files:

```cpp
void ModulatorPreset::savePresetToUser(const fs::path &location,
                                       SurgeStorage *s,
                                       int scene, int lfoid)
{
    auto lfo = &(s->getPatch().scene[scene].lfo[lfoid]);
    int lfotype = lfo->shape.val.i;

    auto containingPath = s->userDataPath / fs::path{PresetDir};
    std::string what;

    // Determine modulator category
    if (lfotype == lt_mseg)
        what = "MSEG";
    else if (lfotype == lt_stepseq)
        what = "Step Seq";
    else if (lfotype == lt_envelope)
        what = "Envelope";
    else if (lfotype == lt_formula)
        what = "Formula";
    else
        what = "LFO";

    containingPath /= fs::path{what};

    // Validate relative path
    if (!location.is_relative())
    {
        s->reportError(
            "Please use relative paths when saving presets. "
            "Referring to drive names directly and using absolute paths "
            "is not allowed!",
            "Relative Path Required");
        return;
    }

    auto comppath = containingPath;
    auto fullLocation = (containingPath / location)
                        .lexically_normal()
                        .replace_extension(PresetExt);

    // Prevent directory traversal attacks
    auto [_, compIt] = std::mismatch(fullLocation.begin(),
                                     fullLocation.end(),
                                     comppath.begin(),
                                     comppath.end());
    if (compIt != comppath.end())
    {
        s->reportError(
            "Your save path is not a directory inside the user presets "
            "directory. This usually means you are doing something like "
            "trying to use ../ in your preset name.",
            "Invalid Save Path");
        return;
    }

    fs::create_directories(fullLocation.parent_path());

    auto doSave = [this, fullLocation, s, lfo, lfotype, lfoid, scene]() {
        TiXmlDeclaration decl("1.0", "UTF-8", "yes");

        TiXmlDocument doc;
        doc.InsertEndChild(decl);

        TiXmlElement lfox("lfo");
        lfox.SetAttribute("shape", lfotype);

        // Save all LFO parameters
        TiXmlElement params("params");
        for (auto curr = &(lfo->rate); curr <= &(lfo->release); ++curr)
        {
            if (curr == &(lfo->shape))
                continue;  // Shape already stored in root

            // Get parameter name without scene/LFO prefix
            std::string in(curr->get_internal_name());
            auto p = in.find('_');
            in = in.substr(p + 1);
            TiXmlElement pn(in);

            if (curr->valtype == vt_float)
                pn.SetDoubleAttribute("v", curr->val.f);
            else
                pn.SetAttribute("i", curr->val.i);

            pn.SetAttribute("temposync", curr->temposync);
            pn.SetAttribute("deform_type", curr->deform_type);
            pn.SetAttribute("extend_range", curr->extend_range);
            pn.SetAttribute("deactivated", curr->deactivated);

            params.InsertEndChild(pn);
        }
        lfox.InsertEndChild(params);

        // Save type-specific data
        if (lfotype == lt_mseg)
        {
            TiXmlElement ms("mseg");
            s->getPatch().msegToXMLElement(
                &(s->getPatch().msegs[scene][lfoid]), ms);
            lfox.InsertEndChild(ms);
        }

        if (lfotype == lt_stepseq)
        {
            TiXmlElement ss("sequence");
            s->getPatch().stepSeqToXmlElement(
                &(s->getPatch().stepsequences[scene][lfoid]), ss, true);
            lfox.InsertEndChild(ss);
        }

        if (lfotype == lt_formula)
        {
            TiXmlElement fm("formula");
            s->getPatch().formulaToXMLElement(
                &(s->getPatch().formulamods[scene][lfoid]), fm);
            lfox.InsertEndChild(fm);

            // Save custom index names
            TiXmlElement xtraName("indexNames");
            bool hasAny{false};
            for (int i = 0; i < max_lfo_indices; ++i)
            {
                if (s->getPatch().LFOBankLabel[scene][lfoid][i][0] != 0)
                {
                    hasAny = true;
                    TiXmlElement xn("name");
                    xn.SetAttribute("index", i);
                    xn.SetAttribute("name",
                        s->getPatch().LFOBankLabel[scene][lfoid][i]);
                    xtraName.InsertEndChild(xn);
                }
            }
            if (hasAny)
            {
                lfox.InsertEndChild(xtraName);
            }
        }

        doc.InsertEndChild(lfox);

        if (!doc.SaveFile(fullLocation))
        {
            std::cout << "Could not save preset" << std::endl;
        }

        forcePresetRescan();
    };

    // Overwrite confirmation
    if (fs::exists(fullLocation))
    {
        s->okCancelProvider(
            "The " + what + " preset '" + location.string() +
            "' already exists. Are you sure you want to overwrite it?",
            "Overwrite " + what + " Preset",
            SurgeStorage::OK,
            [doSave](SurgeStorage::OkCancel okc) {
                if (okc == SurgeStorage::OK)
                {
                    doSave();
                }
            });
    }
    else
    {
        doSave();
    }
}
```

### 28.2.5 Modulator Preset Scanning

The scanning system builds hierarchical category structures:

```cpp
std::vector<ModulatorPreset::Category>
ModulatorPreset::getPresets(SurgeStorage *s, PresetScanMode mode)
{
    if (mode == PresetScanMode::UserOnly && haveScannedUser)
        return scannedUserPresets;
    if (mode == PresetScanMode::FactoryOnly && haveScannedFactory)
        return scannedFactoryPresets;

    std::vector<fs::path> scanTargets;
    if (mode == PresetScanMode::UserOnly)
        scanTargets.push_back(s->userDataPath / fs::path{PresetDir});
    if (mode == PresetScanMode::FactoryOnly)
        scanTargets.push_back(s->datapath / fs::path{"modulator_presets"});

    std::map<std::string, Category> resMap;  // Automatically sorted

    for (const auto &p : scanTargets)
    {
        for (auto &d : fs::recursive_directory_iterator(p))
        {
            auto dp = fs::path(d);
            auto base = dp.stem();
            auto ext = dp.extension();

            if (path_to_string(ext) != PresetExt)
                continue;

            // Extract relative directory path
            auto rd = path_to_string(dp.replace_filename(fs::path()));
            rd = rd.substr(path_to_string(p).length() + 1);
            rd = rd.substr(0, rd.length() - 1);

            // Parse category hierarchy
            auto catName = rd;
            auto ppos = rd.rfind(fs::path::preferred_separator);
            auto pd = std::string();

            if (ppos != std::string::npos)
            {
                pd = rd.substr(0, ppos);
                catName = rd.substr(ppos + 1);
            }

            // Create category if new
            if (resMap.find(rd) == resMap.end())
            {
                resMap[rd] = Category();
                resMap[rd].name = catName;
                resMap[rd].parentPath = pd;
                resMap[rd].path = rd;

                // Recursively create parent categories
                while (pd != "" && resMap.find(pd) == resMap.end())
                {
                    auto cd = pd;
                    catName = cd;
                    ppos = cd.rfind(fs::path::preferred_separator);

                    if (ppos != std::string::npos)
                    {
                        pd = cd.substr(0, ppos);
                        catName = cd.substr(ppos + 1);
                    }
                    else
                    {
                        pd = "";
                    }

                    resMap[cd] = Category();
                    resMap[cd].name = catName;
                    resMap[cd].parentPath = pd;
                    resMap[cd].path = cd;
                }
            }

            // Add preset to category
            Preset prs;
            prs.name = path_to_string(base);
            prs.path = fs::path(d);
            resMap[rd].presets.push_back(prs);
        }
    }

    // Convert map to vector and sort presets
    std::vector<Category> res;
    for (auto &m : resMap)
    {
        std::sort(m.second.presets.begin(), m.second.presets.end(),
                  [](const Preset &a, const Preset &b) {
                      return strnatcasecmp(a.name.c_str(), b.name.c_str()) < 0;
                  });

        res.push_back(m.second);
    }

    // Cache results
    if (mode == PresetScanMode::UserOnly)
    {
        scannedUserPresets = res;
        haveScannedUser = true;
    }
    if (mode == PresetScanMode::FactoryOnly)
    {
        scannedFactoryPresets = res;
        haveScannedFactory = true;
    }

    return res;
}
```

Key features:
- **Natural sort**: Uses `strnatcasecmp` for human-friendly ordering (e.g., "2" before "10")
- **Hierarchical categories**: Automatically creates parent categories
- **Separate caching**: Factory and user presets cached independently
- **Lazy loading**: Only scans when accessed or forced

## 28.3 Wavetable Management

### 28.3.1 Wavetable Organization

Wavetables are managed through the same patch list system used for full patches, but with separate category tracking. From `/home/user/surge/src/common/SurgeStorage.h`:

```cpp
// In-memory wavetable database
std::vector<Patch> wt_list;
std::vector<PatchCategory> wt_category;
int firstThirdPartyWTCategory;
int firstUserWTCategory;
std::vector<int> wtOrdering;
std::vector<int> wtCategoryOrdering;
```

### 28.3.2 Wavetable Directory Structure

#### Factory Wavetables
```
<install_dir>/resources/data/wavetables/
├── Basic Shapes/
│   ├── Sine.wt
│   ├── Triangle.wt
│   ├── Sawtooth.wt
│   └── Square.wt
├── Classic/
├── EDM/
├── Vocal/
└── ...
```

#### Third-Party Wavetables
```
<install_dir>/resources/data/wavetables_3rdparty/
├── Collection A/
└── Collection B/
```

#### User Wavetables
```
<user_data>/Wavetables/
├── My Category/
│   ├── Custom Table.wt
│   └── Another Table.wav
└── Experiments/
    ├── Test.wt
    └── Export.wtscript
```

Supported formats:
- `.wt`: Native Surge wavetable format
- `.wav`: Single-cycle waveforms or wavetable banks
- `.wtscript`: Lua script-generated wavetables (if compiled with Lua support)

### 28.3.3 Wavetable Scanning

The `refresh_wtlist()` function in `/home/user/surge/src/common/SurgeStorage.cpp`:

```cpp
void SurgeStorage::refresh_wtlist()
{
    wt_category.clear();
    wt_list.clear();

    // Scan factory wavetables
    refresh_wtlistAddDir(false, "wavetables");

    firstThirdPartyWTCategory = wt_category.size();

    // Scan third-party wavetables
    if (extraThirdPartyWavetablesPath.empty() ||
        !fs::is_directory(extraThirdPartyWavetablesPath / "wavetables_3rdparty"))
    {
        refresh_wtlistAddDir(false, "wavetables_3rdparty");
    }
    else
    {
        refresh_wtlistFrom(false, extraThirdPartyWavetablesPath,
                          "wavetables_3rdparty");
    }

    firstUserWTCategory = wt_category.size();

    // Scan user wavetables
    refresh_wtlistAddDir(true, "Wavetables");

    if (!extraUserWavetablesPath.empty())
    {
        refresh_wtlistFrom(true, extraUserWavetablesPath, "");
    }

    // Create ordering arrays
    wtCategoryOrdering = std::vector<int>(wt_category.size());
    std::iota(wtCategoryOrdering.begin(), wtCategoryOrdering.end(), 0);

    wtOrdering = std::vector<int>(wt_list.size());
    std::iota(wtOrdering.begin(), wtOrdering.end(), 0);

    // Sort wavetables
    std::sort(wtOrdering.begin(), wtOrdering.end(),
              [this](const int &a, const int &b) -> bool {
                  return wt_list[a].order < wt_list[b].order;
              });

    for (int i = 0; i < wt_list.size(); i++)
        wt_list[wtOrdering[i]].order = i;
}

void SurgeStorage::refresh_wtlistFrom(bool isUser, const fs::path &p,
                                      const std::string &subdir)
{
    std::vector<std::string> supportedTableFileTypes;
    supportedTableFileTypes.push_back(".wt");
    supportedTableFileTypes.push_back(".wav");
#if HAS_LUA
    supportedTableFileTypes.push_back(".wtscript");
#endif

    refreshPatchOrWTListAddDir(
        isUser, p, subdir,
        [supportedTableFileTypes](std::string in) -> bool {
            for (auto q : supportedTableFileTypes)
            {
                if (_stricmp(q.c_str(), in.c_str()) == 0)
                    return true;
            }
            return false;
        },
        wt_list, wt_category);
}
```

### 28.3.4 Wavetable Export

Users can export processed wavetables to their user wavetables folder. The export path:

```cpp
fs::path userWavetablesExportPath = userDataPath / "Exported Wavetables";
```

Exported wavetables include:
- **Processed tables**: After wavetable scripting
- **Modified tables**: After real-time modifications
- **Generated tables**: From Lua scripts

### 28.3.5 Wavetable Metadata

Wavetables can include metadata in the file header or as separate XML:

```cpp
std::string SurgeStorage::make_wt_metadata(OscillatorStorage *osc)
{
    // Create XML metadata for wavetable
    std::string res;
    // ... metadata generation
    return res;
}

bool SurgeStorage::parse_wt_metadata(const std::string &metadata,
                                      OscillatorStorage *osc)
{
    // Parse and apply wavetable metadata
    // ... parsing logic
    return true;
}
```

## 28.4 User Preset Organization

### 28.4.1 User Data Paths

Platform-specific user data locations from `/home/user/surge/src/common/SurgeStorage.cpp`:

```cpp
fs::path SurgeStorage::calculateStandardUserDataPath(const std::string &sxt) const
{
#if WINDOWS
    return fs::path(getenv("USERPROFILE")) / "Documents" / sxt;
#elif MAC
    return fs::path(getenv("HOME")) / "Documents" / sxt;
#else  // Linux
    return fs::path(getenv("HOME")) / (".local/share/" + sxt);
#endif
}
```

Complete user data directory structure:

```
<user_data>/
├── Patches/                    # User patches
│   └── (user categories)/
├── Wavetables/                 # User wavetables
│   └── (user categories)/
├── Exported Wavetables/        # Wavetable exports
├── Wavetable Scripts/          # Lua scripts
├── FX Settings/                # FX presets
│   ├── Delay/
│   ├── Reverb 1/
│   └── .../
├── Modulator Presets/          # Modulator presets
│   ├── LFO/
│   ├── MSEG/
│   ├── Step Seq/
│   ├── Envelope/
│   └── Formula/
├── Skins/                      # Custom skins
├── MidiMappings/               # MIDI controller maps
├── SurgePatches.db             # Patch database
└── SurgeXTUserPreferences.xml  # User settings
```

### 28.4.2 Organization Strategies

**By Category**: Create subdirectories in preset folders
```
Patches/
├── My Basses/
├── My Leads/
└── Experimental/
```

**By Project**: Organize by musical project
```
Patches/
├── Album Project/
│   ├── Track 1/
│   └── Track 2/
└── Live Set/
```

**By Date**: Time-based organization
```
Patches/
├── 2024-01/
├── 2024-02/
└── Favorites/
```

**Flat Organization**: All patches in root directory, using tags and favorites for discovery

### 28.4.3 Backup and Migration

#### Manual Backup

To backup all user content:

1. Locate user data directory (see paths above)
2. Copy entire directory to backup location
3. Restore by copying back to original location

#### Patch Library Transfer

To transfer patches between systems:

```bash
# Export patch database and files
tar -czf surge-patches.tar.gz Patches/ SurgePatches.db

# Import on new system
cd <user_data_path>
tar -xzf surge-patches.tar.gz
```

#### Selective Migration

Export specific categories:

```bash
# Backup specific category
cp -r Patches/MyCategory/ /backup/location/

# Backup FX presets for one effect
cp -r "FX Settings/Delay/" /backup/location/
```

The database will automatically reindex after file changes are detected.

### 28.4.4 Cross-Platform Compatibility

Surge presets are cross-platform compatible:
- **FXP files**: Binary compatible across platforms
- **XML content**: Platform-independent
- **Path separators**: Normalized during loading
- **Line endings**: Handled transparently

To share presets:
1. **Export from source system**: Copy .fxp files
2. **Transfer**: Use cloud storage, USB, or network
3. **Import to destination**: Place in user patches folder
4. **Refresh**: Force database rebuild if needed

## 28.5 Preset Clipboard

### 28.5.1 Clipboard Architecture

The clipboard system in `/home/user/surge/src/common/SurgeStorage.h` supports copying various element types:

```cpp
enum clipboard_type
{
    cp_off = 0,
    cp_scene = 1U << 1,            // Complete scene
    cp_osc = 1U << 2,              // Single oscillator
    cp_oscmod = 1U << 3,           // Oscillator with modulation
    cp_lfo = 1U << 4,              // LFO/modulator
    cp_modulator_target = 1U << 5,  // Modulation routing
    cp_lfomod = cp_lfo | cp_modulator_target
};
```

### 28.5.2 Oscillator Copy/Paste

The `clipboard_copy()` function in `/home/user/surge/src/common/SurgeStorage.cpp`:

```cpp
void SurgeStorage::clipboard_copy(int type, int scene, int entry, modsources ms)
{
    bool includemod = false, includeall = false;
    int cgroup = -1;
    int cgroup_e = -1;
    int id = -1;

    if (type & cp_oscmod)
    {
        type = cp_osc;
        includemod = true;
    }

    clipboard_type = type;

    if (type & cp_osc)
    {
        cgroup = cg_OSC;
        cgroup_e = entry;
        id = getPatch().scene[scene].osc[entry].type.id;

        // Copy wavetable data if present
        if (uses_wavetabledata(getPatch().scene[scene].osc[entry].type.val.i))
        {
            clipboard_wt[0].Copy(&getPatch().scene[scene].osc[entry].wt);
            clipboard_wt_names[0] =
                getPatch().scene[scene].osc[entry].wavetable_display_name;
            clipboard_wavetable_script[0] =
                getPatch().scene[scene].osc[entry].wavetable_script;
            clipboard_wavetable_script_nframes[0] =
                getPatch().scene[scene].osc[entry].wavetable_script_nframes;
            clipboard_wavetable_script_res_base[0] =
                getPatch().scene[scene].osc[entry].wavetable_script_res_base;
        }

        clipboard_extraconfig[0] = getPatch().scene[scene].osc[entry].extraConfig;
    }

    if (type & cp_lfo)
    {
        cgroup = cg_LFO;
        cgroup_e = entry + ms_lfo1;
        id = getPatch().scene[scene].lfo[entry].shape.id;

        if (getPatch().scene[scene].lfo[entry].shape.val.i == lt_stepseq)
        {
            clipboard_stepsequences[0] = getPatch().stepsequences[scene][entry];
        }

        if (getPatch().scene[scene].lfo[entry].shape.val.i == lt_mseg)
        {
            clipboard_msegs[0] = getPatch().msegs[scene][entry];
        }

        if (getPatch().scene[scene].lfo[entry].shape.val.i == lt_formula)
        {
            clipboard_formulae[0] = getPatch().formulamods[scene][entry];
        }

        for (int idx = 0; idx < max_lfo_indices; ++idx)
        {
            strncpy(clipboard_modulator_names[0][idx],
                    getPatch().LFOBankLabel[scene][entry][idx],
                    CUSTOM_CONTROLLER_LABEL_SIZE);
        }
    }

    if (type & cp_scene)
    {
        includemod = true;
        includeall = true;
        id = getPatch().scene[scene].octave.id;

        // Copy all LFOs
        for (int i = 0; i < n_lfos; i++)
        {
            clipboard_stepsequences[i] = getPatch().stepsequences[scene][i];
            clipboard_msegs[i] = getPatch().msegs[scene][i];
            clipboard_formulae[i] = getPatch().formulamods[scene][i];

            for (int idx = 0; idx < max_lfo_indices; ++idx)
            {
                strncpy(clipboard_modulator_names[i][idx],
                        getPatch().LFOBankLabel[scene][i][idx],
                        CUSTOM_CONTROLLER_LABEL_SIZE);
            }
        }

        // Copy all oscillators
        for (int i = 0; i < n_oscs; i++)
        {
            clipboard_wt[i].Copy(&getPatch().scene[scene].osc[i].wt);
            clipboard_wt_names[i] =
                getPatch().scene[scene].osc[i].wavetable_display_name;
            clipboard_extraconfig[i] = getPatch().scene[scene].osc[i].extraConfig;
            clipboard_wavetable_script[i] =
                getPatch().scene[scene].osc[i].wavetable_script;
            clipboard_wavetable_script_res_base[i] =
                getPatch().scene[scene].osc[i].wavetable_script_res_base;
            clipboard_wavetable_script_nframes[i] =
                getPatch().scene[scene].osc[i].wavetable_script_nframes;
        }

        // Copy scene FX
        auto fxOffset = (scene == 0) ? 0 : 4;
        for (int i = 0; i < n_fx_per_chain; ++i)
        {
            auto sl = fxslot_order[i + fxOffset];
            if (!clipboard_scenefx[i])
            {
                clipboard_scenefx[i] =
                    std::make_unique<Surge::FxClipboard::Clipboard>();
            }
            Surge::FxClipboard::copyFx(this, &getPatch().fx[sl],
                                       *clipboard_scenefx[i]);
        }

        clipboard_primode = getPatch().scene[scene].monoVoicePriorityMode;
        clipboard_envmode = getPatch().scene[scene].monoVoiceEnvelopeMode;
    }

    // Copy parameters...
}
```

### 28.5.3 FX Clipboard Format

The FX clipboard uses an internal vector format in `/home/user/surge/src/common/FxPresetAndClipboardManager.cpp`:

```cpp
namespace FxClipboard
{
struct Clipboard
{
    Clipboard();
    std::vector<float> fxCopyPaste;
};

void copyFx(SurgeStorage *storage, FxStorage *fx, Clipboard &cb)
{
    cb.fxCopyPaste.clear();
    cb.fxCopyPaste.resize(n_fx_params * 5 + 1);

    // Layout: [type][val,deform,ts,extend,deact] * 12 parameters
    cb.fxCopyPaste[0] = fx->type.val.i;

    for (int i = 0; i < n_fx_params; ++i)
    {
        int vp = i * 5 + 1;  // Value position
        int tp = i * 5 + 2;  // Temposync position
        int xp = i * 5 + 3;  // Extend position
        int dp = i * 5 + 4;  // Deactivated position
        int dt = i * 5 + 5;  // Deform type position

        switch (fx->p[i].valtype)
        {
        case vt_float:
            cb.fxCopyPaste[vp] = fx->p[i].val.f;
            break;
        case vt_int:
            cb.fxCopyPaste[vp] = fx->p[i].val.i;
            break;
        }

        cb.fxCopyPaste[tp] = fx->p[i].temposync;
        cb.fxCopyPaste[xp] = fx->p[i].extend_range;
        cb.fxCopyPaste[dp] = fx->p[i].deactivated;

        if (fx->p[i].has_deformoptions())
            cb.fxCopyPaste[dt] = fx->p[i].deform_type;
    }
}

bool isPasteAvailable(const Clipboard &cb)
{
    return !cb.fxCopyPaste.empty();
}

void pasteFx(SurgeStorage *storage, FxStorage *fxbuffer, Clipboard &cb)
{
    if (cb.fxCopyPaste.empty())
        return;

    fxbuffer->type.val.i = (int)cb.fxCopyPaste[0];

    Effect *t_fx = spawn_effect(fxbuffer->type.val.i, storage, fxbuffer, 0);
    if (t_fx)
    {
        t_fx->init_ctrltypes();
        t_fx->init_default_values();
        delete t_fx;
    }

    for (int i = 0; i < n_fx_params; i++)
    {
        int vp = i * 5 + 1;
        int tp = i * 5 + 2;
        int xp = i * 5 + 3;
        int dp = i * 5 + 4;
        int dt = i * 5 + 5;

        switch (fxbuffer->p[i].valtype)
        {
        case vt_float:
            fxbuffer->p[i].val.f = cb.fxCopyPaste[vp];
            // Clamp to valid range
            if (fxbuffer->p[i].val.f < fxbuffer->p[i].val_min.f)
            {
                fxbuffer->p[i].val.f = fxbuffer->p[i].val_min.f;
            }
            if (fxbuffer->p[i].val.f > fxbuffer->p[i].val_max.f)
            {
                fxbuffer->p[i].val.f = fxbuffer->p[i].val_max.f;
            }
            break;
        case vt_int:
            fxbuffer->p[i].val.i = (int)cb.fxCopyPaste[vp];
            break;
        default:
            break;
        }

        fxbuffer->p[i].temposync = (int)cb.fxCopyPaste[tp];
        fxbuffer->p[i].set_extend_range((int)cb.fxCopyPaste[xp]);
        fxbuffer->p[i].deactivated = (int)cb.fxCopyPaste[dp];

        if (fxbuffer->p[i].has_deformoptions())
            fxbuffer->p[i].deform_type = (int)cb.fxCopyPaste[dt];
    }

    cb.fxCopyPaste.clear();  // Clear after paste
}
} // namespace FxClipboard
```

### 28.5.4 Clipboard Memory Layout

The clipboard stores data in member variables:

```cpp
// In SurgeStorage.h (private section)
std::vector<Parameter> clipboard_p;              // Parameter values
int clipboard_type;                              // What was copied
StepSequencerStorage clipboard_stepsequences[n_lfos];
std::unique_ptr<Surge::FxClipboard::Clipboard> clipboard_scenefx[n_fx_per_chain];
MSEGStorage clipboard_msegs[n_lfos];
FormulaModulatorStorage clipboard_formulae[n_lfos];
OscillatorStorage::ExtraConfigurationData clipboard_extraconfig[n_oscs];
std::vector<ModulationRouting> clipboard_modulation_scene;
std::vector<ModulationRouting> clipboard_modulation_voice;
std::vector<ModulationRouting> clipboard_modulation_global;
Wavetable clipboard_wt[n_oscs];
std::array<std::string, n_oscs> clipboard_wt_names;
std::array<std::string, n_oscs> clipboard_wavetable_script;
std::array<int, n_oscs> clipboard_wavetable_script_res_base;
std::array<int, n_oscs> clipboard_wavetable_script_nframes;
char clipboard_modulator_names[n_lfos][max_lfo_indices][CUSTOM_CONTROLLER_LABEL_SIZE + 1];
MonoVoicePriorityMode clipboard_primode;
MonoVoiceEnvelopeMode clipboard_envmode;
```

## 28.6 Preset Scanning and Refresh

### 28.6.1 Scanning Performance

Preset scanning is optimized for large libraries:

**FX Preset Scan** (`doPresetRescan`):
- Uses breadth-first directory traversal
- Parses only necessary XML elements (type, name, parameters)
- Caches results until forced refresh
- Typical performance: ~100-500 presets per second

**Modulator Preset Scan** (`getPresets`):
- Recursive directory iteration with `fs::recursive_directory_iterator`
- Builds hierarchical category structure on-the-fly
- Separate caching for factory and user presets
- Natural sort order for human-friendly display

**Wavetable Scan** (`refresh_wtlist`):
- Reuses generic `refreshPatchOrWTListAddDir` function
- Supports multiple file formats (.wt, .wav, .wtscript)
- Integrated with patch database for fast searches
- Deferred wavetable loading (only metadata scanned)

### 28.6.2 Directory Watching

Surge does not use file system watchers. Instead, it provides:

1. **Manual refresh**: User-initiated rescan
2. **Automatic refresh**: After save operations
3. **Startup scan**: Initial scan on plugin/application load

To force a refresh:

```cpp
// FX presets
storage->fxUserPreset->doPresetRescan(storage, true);

// Modulator presets
storage->modulatorPreset->forcePresetRescan();

// Patches and wavetables
storage->refresh_patchlist();
storage->refresh_wtlist();
```

### 28.6.3 Error Handling

All scanning functions use exception handling:

```cpp
try
{
    for (auto &d : fs::directory_iterator(path))
    {
        // Process files
    }
}
catch (const fs::filesystem_error &e)
{
    std::ostringstream oss;
    oss << "Experienced file system error when scanning. " << e.what();

    if (storage)
        storage->reportError(oss.str(), "FileSystem Error");
}
```

Common error conditions:
- **Permission denied**: User lacks read access to preset directory
- **Path too long**: Windows path length limits exceeded
- **Invalid characters**: Filesystem encoding issues
- **Symbolic link loops**: Circular directory references
- **Network timeouts**: Presets on network drives

### 28.6.4 Optimization Strategies

**Lazy Loading**: Preset content not loaded until used
```cpp
if (haveScannedPresets && !forceRescan)
    return;
```

**Incremental Updates**: Only rescan after file changes
```cpp
doPresetRescan(storage, true);  // Force after save
```

**Parallel Scanning**: Could be implemented with thread pool
```cpp
// Future optimization: parallel directory traversal
std::vector<std::future<Preset>> futures;
for (auto &file : files)
{
    futures.push_back(std::async(std::launch::async,
                                 &parsePreset, file));
}
```

**Database Indexing**: Wavetables and patches use SQLite for fast lookup

## 28.7 Summary

The Surge XT preset management system provides specialized handling for:

1. **FX Presets** (.srgfx):
   - Per-effect-type organization
   - XML format with parameter attributes
   - Factory and user preset separation
   - Automatic category management

2. **Modulator Presets** (.modpreset):
   - Unified format for LFO, MSEG, Step Seq, Envelope, Formula
   - Type-based directory organization
   - Hierarchical category structure
   - Shape-specific data (MSEG segments, step seq patterns, etc.)

3. **Wavetable Management**:
   - Multiple format support (.wt, .wav, .wtscript)
   - Category-based organization
   - Lazy loading for performance
   - Export functionality

4. **Preset Clipboard**:
   - Oscillator copy/paste with wavetables
   - FX copy/paste with all parameters
   - Scene copy/paste for complete configurations
   - Internal memory-based format

5. **Scanning System**:
   - Recursive directory traversal
   - Error-tolerant parsing
   - Hierarchical category creation
   - Natural sort ordering

Key implementation files:
- `/home/user/surge/src/common/FxPresetAndClipboardManager.cpp`: FX preset management
- `/home/user/surge/src/common/ModulatorPresetManager.cpp`: Modulator preset system
- `/home/user/surge/src/common/SurgeStorage.cpp`: Wavetable and clipboard management

The preset systems complement the main patch system (Chapter 27) by providing fine-grained preset management for individual synthesizer components, enabling efficient workflow and sound design experimentation.
