# Chapter 27: Patch System

The patch system in Surge XT handles all aspects of preset management, from low-level binary file formats to high-level patch browsing and organization. This chapter provides a comprehensive look at how patches are stored, loaded, saved, and managed.

## 27.1 Patch File Format

### 27.1.1 FXP Container Format

Surge XT uses the FXP (VST 2.x preset) file format for patch storage. Each .fxp file contains:

1. **FXP Chunk Header** (`fxChunkSetCustom` struct):
   - `chunkMagic`: 'CcnK' (VST chunk identifier)
   - `fxMagic`: 'FPCh' (VST chunk preset type)
   - `fxID`: 'cjs3' (Surge's unique identifier, Claes Johanson Surge 3)
   - `version`: Always 1
   - `numPrograms`: Always 1
   - `prgName`: 28-byte patch name
   - `chunkSize`: Size of the data following this header

2. **Patch Header** (`patch_header` struct):
   - `tag`: "sub3" (4 bytes)
   - `xmlsize`: Size of XML data in bytes
   - `wtsize[2][3]`: Wavetable sizes for each oscillator in each scene

3. **XML Data**: The complete patch state in XML format

4. **Wavetable Data**: Binary wavetable data for each oscillator using wavetables

### 27.1.2 Binary Structure

```
+------------------+
| fxChunkSetCustom |  60 bytes
| - 'CcnK' magic   |
| - 'FPCh' type    |
| - 'cjs3' id      |
+------------------+
| patch_header     |  52 bytes
| - "sub3" tag     |
| - XML size       |
| - WT sizes[2][3] |
+------------------+
| XML Data         |  Variable size
| (UTF-8 encoded)  |
+------------------+
| Wavetable 1      |  If present
+------------------+
| Wavetable 2      |  If present
+------------------+
| ... up to 6 WTs  |
+------------------+
```

### 27.1.3 XML Patch Structure (Revision 28)

The current patch format uses revision 28, defined by `ff_revision` in `/home/user/surge/src/common/SurgeStorage.h`:

```c++
const int ff_revision = 28;
```

#### Complete Patch XML Example

```xml
<?xml version="1.0" encoding="UTF-8" standalone="yes" ?>
<patch revision="28">
  <meta name="Bass Patch"
        category="Basses"
        comment="A deep bass sound"
        author="Surge Synth Team"
        license="CC0">
    <tags>
      <tag tag="bass" />
      <tag tag="analog" />
    </tags>
  </meta>

  <parameters>
    <!-- Global parameters -->
    <volume_FX1 type="2" value="1.000000" />
    <volume type="2" value="-2.025745" />
    <scenemode type="0" value="0" />
    <splitkey type="0" value="60" />
    <polylimit type="0" value="16" />

    <!-- Scene A oscillator 1 -->
    <a_osc1_type type="0" value="0" />
    <a_osc1_pitch type="2" value="0.000000" extend_range="0" />
    <a_osc1_param0 type="2" value="0.000000" />
    <a_osc1_param1 type="2" value="0.500000" extend_range="1" />

    <!-- Modulation routing -->
    <a_filter1_cutoff type="2" value="3.000000">
      <modrouting source="1" depth="0.750000"
                  muted="0" source_index="0" />
    </modrouting>

    <!-- Parameters with special attributes -->
    <a_portamento type="2" value="-8.000000"
                  porta_const_rate="0"
                  porta_gliss="0"
                  porta_retrigger="0"
                  porta_curve="0" />

    <a_volume type="2" value="0.890899" deactivated="0" />
    <a_lowcut type="2" value="-72.000000" deactivated="0" deform_type="0" />
  </parameters>

  <nonparamconfig>
    <monoVoicePrority_0 v="1" />
    <monoVoicePrority_1 v="1" />
    <monoVoiceEnvelope_0 v="0" />
    <monoVoiceEnvelope_1 v="0" />
    <polyVoiceRepeatedKeyMode_0 v="0" />
    <polyVoiceRepeatedKeyMode_1 v="0" />
    <hardclipmodes global="1" sc0="1" sc1="1" />
    <tuningApplicationMode v="1" />
  </nonparamconfig>

  <extraoscdata>
    <osc_extra_sc0_osc0 scene="0" osc="0"
                        wavetable_display_name="Basic Shapes"
                        wavetable_script=""
                        wavetable_script_nframes="10"
                        wavetable_script_res_base="5"
                        extra_n="0" />
  </extraoscdata>

  <stepsequences>
    <sequence scene="0" i="0">
      <step i="0" v="0.500000" />
      <step i="1" v="0.250000" />
      <!-- ... -->
      <loop_start v="0" />
      <loop_end v="15" />
      <shuffle v="0.000000" />
      <trigmask v="65535" />
    </sequence>
  </stepsequences>

  <msegs>
    <mseg scene="0" i="0">
      <segment i="0" duration="0.125000" v="0.000000"
               cpv="0.500000" cpduration="0.500000" />
      <!-- ... -->
      <editMode v="0" />
      <loopMode v="0" />
      <endpointMode v="0" />
    </mseg>
  </msegs>

  <formulae>
    <formula scene="0" i="0">
      <code><![CDATA[sin(phase * 2 * pi)]]></code>
    </formula>
  </formulae>

  <extralfo>
    <lfo scene="0" i="0" extraAmplitude="0" />
  </extralfo>

  <customcontroller>
    <entry i="0" bipolar="1" v="0.000000" label="Macro 1" />
  </customcontroller>

  <lfobanklabels>
    <label lfo="0" idx="0" scene="0" v="LFO 1 Bank A" />
  </lfobanklabels>

  <modwheel s0="0.000000" s1="0.000000" />

  <compatability>
    <correctlyTunedCombFilter v="1" />
  </compatability>

  <patchTuning v="base64_encoded_scale_data"
               m="base64_encoded_mapping_data"
               mname="12-TET" />

  <tempoOnSave v="120.000000" />

  <dawExtraState populated="1">
    <instanceZoomFactor v="100" />
    <editor current_scene="0" current_fx="0" modsource="1">
      <overlays>
        <overlay whichOverlay="1" isTornOut="0"
                 tearOut_x="0" tearOut_y="0" />
      </overlays>
    </editor>
  </dawExtraState>
</patch>
```

#### Parameter Attributes

Each parameter element can have these attributes:

- `type`: `0` for int, `2` for float
- `value`: The parameter value as string
- `temposync`: `"1"` if tempo-synced
- `extend_range`: `"1"` if extended range is enabled
- `absolute`: `"1"` if absolute mode is active
- `deactivated`: `"1"` if parameter is deactivated
- `deform_type`: Integer specifying the deform type
- `porta_const_rate`, `porta_gliss`, `porta_retrigger`, `porta_curve`: Portamento options

## 27.2 Patch Loading

### 27.2.1 Loading Pipeline

The patch loading process in `/home/user/surge/src/common/SurgePatch.cpp`:

```cpp
void SurgePatch::load_xml(const void *data, int datasize, bool is_preset)
{
    TiXmlDocument doc;

    // 1. Size validation
    if (datasize >= (1 << 22))  // 4 MB limit
    {
        storage->reportError("Patch header too large", "Patch Load Error");
        return;
    }

    // 2. Parse XML with TinyXML
    char *temp = (char *)malloc(datasize + 1);
    memcpy(temp, data, datasize);
    *(temp + datasize) = 0;
    doc.Parse(temp, nullptr, TIXML_ENCODING_LEGACY);
    free(temp);

    // 3. Clear existing modulation routings
    for (int sc = 0; sc < n_scenes; sc++)
    {
        scene[sc].modulation_scene.clear();
        scene[sc].modulation_voice.clear();
    }
    modulation_global.clear();

    // 4. Get patch root element
    TiXmlElement *patch = TINYXML_SAFE_TO_ELEMENT(doc.FirstChild("patch"));
    if (!patch) return;

    // 5. Version checking
    int revision = 0;
    patch->QueryIntAttribute("revision", &revision);
    streamingRevision = revision;

    if (revision > ff_revision)
    {
        storage->reportError(
            "Patch was created with newer version",
            "Patch Version Mismatch");
    }

    // 6. Load metadata
    TiXmlElement *meta = TINYXML_SAFE_TO_ELEMENT(patch->FirstChild("meta"));
    if (meta)
    {
        name = meta->Attribute("name");
        category = meta->Attribute("category");
        author = meta->Attribute("author");
        // ... load other metadata
    }

    // 7. Load parameters
    TiXmlElement *parameters =
        TINYXML_SAFE_TO_ELEMENT(patch->FirstChild("parameters"));
    // ... parameter loading loop
}
```

### 27.2.2 Parameter Population

For each parameter:

```cpp
for (int i = 0; i < n; i++)
{
    TiXmlElement *p = /* find parameter element */;

    if (p)
    {
        int type;
        if (p->QueryIntAttribute("type", &type) == TIXML_SUCCESS)
        {
            if (type == vt_float)
            {
                double d;
                p->QueryDoubleAttribute("value", &d);
                param_ptr[i]->set_storage_value((float)d);
            }
            else  // vt_int
            {
                int j;
                p->QueryIntAttribute("value", &j);
                param_ptr[i]->set_storage_value(j);
            }
        }

        // Load modulation routings
        TiXmlElement *mr = p->FirstChild("modrouting");
        while (mr)
        {
            int modsource;
            double depth;
            mr->QueryIntAttribute("source", &modsource);
            mr->QueryDoubleAttribute("depth", &depth);

            ModulationRouting t;
            t.depth = (float)depth;
            t.source_id = modsource;
            t.destination_id = /* ... */;
            modlist->push_back(t);

            mr = mr->NextSibling("modrouting");
        }
    }
}
```

### 27.2.3 Wavetable Loading

After XML parsing, wavetables are loaded from binary data:

```cpp
unsigned int SurgePatch::save_patch(void **data)
{
    wt_header wth[n_scenes][n_oscs];

    for (int sc = 0; sc < n_scenes; sc++)
    {
        for (int osc = 0; osc < n_oscs; osc++)
        {
            if (uses_wavetabledata(scene[sc].osc[osc].type.val.i))
            {
                wth[sc][osc].n_samples = scene[sc].osc[osc].wt.size;
                wth[sc][osc].n_tables = scene[sc].osc[osc].wt.n_tables;
                wth[sc][osc].flags = scene[sc].osc[osc].wt.flags | wtf_int16;

                // Store 16-bit wavetable data
                unsigned int wtsize =
                    wth[sc][osc].n_samples *
                    scene[sc].osc[osc].wt.n_tables *
                    sizeof(short) + sizeof(wt_header);
            }
        }
    }
}
```

### 27.2.4 Version Migration

Surge includes extensive backward compatibility code for older patch revisions:

```cpp
// Revision-specific migrations
if (revision < 1)
{
    // Fix envelope shapes
    scene[sc].adsr[0].a_s.val.i =
        limit_range(scene[sc].adsr[0].a_s.val.i + 1, 0, 2);
}

if (revision < 6)
{
    // Adjust resonance for filter changes
    u.resonance.val.f = convert_v11_reso_to_v12_2P(u.resonance.val.f);
}

if (revision < 15)
{
    // The Great Filter Remap (GitHub issue #3006)
    // Remap filter types and subtypes
}

if (revision < 21)
{
    // Skip modulations to volume parameter (issue #6424)
}
```

### 27.2.5 Error Handling

Multiple error conditions are handled:

1. **Oversized patches**: Reject patches > 4 MB
2. **Invalid XML**: TinyXML parsing failures
3. **Missing elements**: Graceful degradation when elements are absent
4. **Invalid revision**: Warning when patch is from newer version
5. **Corrupt wavetable data**: Size validation before loading

## 27.3 Patch Saving

### 27.3.1 Serialization Process

From `/home/user/surge/src/common/SurgeSynthesizerIO.cpp`:

```cpp
void SurgeSynthesizer::savePatchToPath(fs::path filename, bool refreshPatchList)
{
    using namespace sst::io;

    std::ofstream f(filename, std::ios::out | std::ios::binary);

    // Create FXP header
    fxChunkSetCustom fxp;
    fxp.chunkMagic = mech::endian_write_int32BE('CcnK');
    fxp.fxMagic = mech::endian_write_int32BE('FPCh');
    fxp.fxID = mech::endian_write_int32BE('cjs3');
    fxp.numPrograms = mech::endian_write_int32BE(1);
    fxp.version = mech::endian_write_int32BE(1);
    fxp.fxVersion = mech::endian_write_int32BE(1);
    strncpy(fxp.prgName, storage.getPatch().name.c_str(), 28);

    // Get patch data
    void *data;
    unsigned int datasize = storage.getPatch().save_patch(&data);

    fxp.chunkSize = mech::endian_write_int32BE(datasize);
    fxp.byteSize = 0;

    // Write to file
    f.write((char *)&fxp, sizeof(fxChunkSetCustom));
    f.write((char *)data, datasize);
    f.close();

    // Refresh patch list and database
    if (refreshPatchList)
    {
        storage.refresh_patchlist();
        storage.initializePatchDb(true);
    }
}
```

### 27.3.2 XML Generation

The `save_xml()` method creates the XML structure:

```cpp
size_t SurgePatch::save_xml(void **xmldata)
{
    TiXmlDocument doc;
    TiXmlElement patch("patch");
    patch.SetAttribute("revision", ff_revision);

    // Metadata
    TiXmlElement meta("meta");
    meta.SetAttribute("name", this->name);
    meta.SetAttribute("category", this->category);
    meta.SetAttribute("comment", comment);
    meta.SetAttribute("author", author);
    meta.SetAttribute("license", license);

    // Tags
    TiXmlElement tagsX("tags");
    for (auto t : tags)
    {
        TiXmlElement tx("tag");
        tx.SetAttribute("tag", t.tag);
        tagsX.InsertEndChild(tx);
    }
    meta.InsertEndChild(tagsX);
    patch.InsertEndChild(meta);

    // Parameters
    TiXmlElement parameters("parameters");
    for (int i = 0; i < param_ptr.size(); i++)
    {
        TiXmlElement p(param_ptr[i]->get_storage_name());

        if (param_ptr[i]->valtype == vt_float)
        {
            p.SetAttribute("type", vt_float);
            p.SetAttribute("value", param_ptr[i]->get_storage_value(tempstr));
        }
        else
        {
            p.SetAttribute("type", vt_int);
            p.SetAttribute("value", param_ptr[i]->get_storage_value(tempstr));
        }

        // Modulation routings
        if (sceneId > 0)
        {
            for (auto &routing : modulation_scene)
            {
                if (routing.destination_id == param_id)
                {
                    TiXmlElement mr("modrouting");
                    mr.SetAttribute("source", routing.source_id);
                    mr.SetAttribute("depth", routing.depth);
                    mr.SetAttribute("muted", routing.muted);
                    p.InsertEndChild(mr);
                }
            }
        }

        parameters.InsertEndChild(p);
    }
    patch.InsertEndChild(parameters);

    // ... add other sections (stepsequences, msegs, etc.)

    // Convert to string
    TiXmlPrinter printer;
    doc.Accept(&printer);
    return printer.CStr();
}
```

### 27.3.3 No Compression

Surge does not use compression for patch files. The XML is stored as plain UTF-8 text. This design choice provides:

- **Readability**: Patches can be inspected and edited in text editors
- **Version Control**: Git-friendly diff-able format
- **Debugging**: Easy to diagnose issues
- **Size Trade-off**: Patches typically range from 30 KB to 500 KB

## 27.4 Default Patch

### 27.4.1 Init Patch Structure

The `init_default_values()` function in `/home/user/surge/src/common/SurgePatch.cpp` defines the default patch state:

```cpp
void SurgePatch::init_default_values()
{
    // Reset all parameters to defaults
    for (int i = 0; i < param_ptr.size(); i++)
    {
        if ((i != volume.id) && (i != fx_bypass.id) && (i != polylimit.id))
        {
            param_ptr[i]->val.i = param_ptr[i]->val_default.i;
            param_ptr[i]->clear_flags();
        }

        if (i == polylimit.id)
        {
            param_ptr[i]->val.i = DEFAULT_POLYLIMIT;  // 16
        }
    }

    character.val.i = 1;  // Modern character

    for (int sc = 0; sc < n_scenes; sc++)
    {
        // Oscillator defaults
        for (auto &osc : scene[sc].osc)
        {
            osc.type.val.i = 0;  // Classic oscillator
            osc.keytrack.val.b = true;
            osc.retrigger.val.b = false;
        }

        // Scene parameters
        scene[sc].fm_depth.val.f = -24.f;
        scene[sc].portamento.val.f = scene[sc].portamento.val_min.f;
        scene[sc].keytrack_root.val.i = 60;  // Middle C
        scene[sc].volume.val.f = 0.890899f;  // ~-1 dB
        scene[sc].width.val.f = 1.f;

        // Mixer routing - only OSC 1 active by default
        scene[sc].mute_o2.val.b = true;
        scene[sc].mute_o3.val.b = true;
        scene[sc].mute_noise.val.b = true;
        scene[sc].mute_ring_12.val.b = true;
        scene[sc].mute_ring_23.val.b = true;

        scene[sc].route_o1.val.i = 1;  // Filter 1

        // Pitch bend
        scene[sc].pbrange_up.val.i = 2.f;
        scene[sc].pbrange_dn.val.i = 2.f;

        // Highpass filter
        scene[sc].lowcut.val.f = scene[sc].lowcut.val_min.f;
        scene[sc].lowcut.deactivated = false;

        // Envelope defaults
        for (int i = 0; i < n_egs; i++)
        {
            scene[sc].adsr[i].a.val.f = scene[sc].adsr[i].a.val_min.f;
            scene[sc].adsr[i].d.val.f = -2;
            scene[sc].adsr[i].r.val.f = -5;
            scene[sc].adsr[i].s.val.f = 1;
            scene[sc].adsr[i].a_s.val.i = 1;  // Log curve
            scene[sc].adsr[i].d_s.val.i = 1;
            scene[sc].adsr[i].r_s.val.i = 2;  // Exponential
        }

        // LFO defaults
        for (int l = 0; l < n_lfos; l++)
        {
            scene[sc].lfo[l].rate.deactivated = false;
            scene[sc].lfo[l].magnitude.val.f = 1.f;
            scene[sc].lfo[l].trigmode.val.i = 1;  // Keytriggered
            scene[sc].lfo[l].delay.val.f =
                scene[sc].lfo[l].delay.val_min.f;
            // ... more LFO defaults
        }

        // Step sequencer defaults
        for (int l = 0; l < n_lfos; l++)
        {
            for (int i = 0; i < n_stepseqsteps; i++)
            {
                stepsequences[sc][l].steps[i] = 0.f;
            }
            stepsequences[sc][l].loop_start = 0;
            stepsequences[sc][l].loop_end = 15;
        }
    }

    // Custom controller labels
    for (int i = 0; i < n_customcontrollers; i++)
    {
        strxcpy(CustomControllerLabel[i], "-",
                CUSTOM_CONTROLLER_LABEL_SIZE);
    }
}
```

### 27.4.2 Init Patch Templates

Surge ships with multiple init patches in `/home/user/surge/resources/data/patches_factory/Templates/`:

- **Init Saw**: Basic saw wave patch
- **Init Sine**: Pure sine wave
- **Init Square**: Square wave
- **Init Wavetable**: Wavetable oscillator (largest at ~416 KB due to embedded wavetable)
- **Init Modern**: Modern oscillator
- **Init FM2**: FM synthesis starting point
- **Init Paraphonic**: Paraphonic voice mode
- **Init Duophonic**: Duophonic voice mode
- **Audio In templates**: For using external audio input

## 27.5 Patch Categories and Tags

### 27.5.1 Category System

Categories are hierarchical and directory-based:

```
patches_factory/
├── Basses/
├── Leads/
├── Pads/
├── Keys/
├── FX/
└── ...
```

The PatchDB stores category metadata:

```sql
CREATE TABLE Category (
    id integer primary key,
    name varchar(2048),
    leaf_name varchar(256),
    isroot int,
    type int,
    parent_id int
);
```

Category types:
- `FACTORY = 0`: Factory patches
- `THIRD_PARTY = 1`: Third-party content
- `USER = 2`: User-created patches

### 27.5.2 Tag Metadata

Tags are stored within the patch XML:

```xml
<meta name="Bass Patch" category="Basses" author="...">
  <tags>
    <tag tag="bass" />
    <tag tag="analog" />
    <tag tag="warm" />
  </tags>
</meta>
```

Tags are extracted during database indexing:

```cpp
auto tags = TINYXML_SAFE_TO_ELEMENT(meta->FirstChild("tags"));
if (tags)
{
    auto tag = tags->FirstChildElement();
    while (tag)
    {
        res.emplace_back("TAG", STRING, 0, tag->Attribute("tag"));
        tag = tag->NextSiblingElement();
    }
}
```

### 27.5.3 User Organization

Users can organize patches by:

1. **Creating subdirectories** in the user patches folder
2. **Adding tags** to patch metadata
3. **Marking favorites** (stored in database)
4. **Setting categories** when saving

## 27.6 Patch Browser Integration

### 27.6.1 PatchDB SQLite Database

The patch database is located at `userDataPath/SurgePatches.db` and uses schema version 14.

#### Database Schema

```sql
-- Version tracking
CREATE TABLE Version (
    id integer primary key,
    schema_version varchar(256)
);

-- Main patches table
CREATE TABLE Patches (
    id integer primary key,
    path varchar(2048),
    name varchar(256),
    search_over varchar(1024),
    category varchar(2048),
    category_type int,
    last_write_time big int
);

-- Patch features (tags, effects, filters, etc.)
CREATE TABLE PatchFeature (
    id integer primary key,
    patch_id integer,
    feature varchar(64),
    feature_type int,
    feature_ivalue int,
    feature_svalue varchar(64)
);

-- Category hierarchy
CREATE TABLE Category (
    id integer primary key,
    name varchar(2048),
    leaf_name varchar(256),
    isroot int,
    type int,
    parent_id int
);

-- User favorites
CREATE TABLE Favorites (
    id integer primary key,
    path varchar(2048)
);
```

### 27.6.2 Feature Extraction

From `/home/user/surge/src/common/PatchDB.cpp`, features extracted for searching:

```cpp
std::vector<feature> extractFeaturesFromXML(const char *xml)
{
    std::vector<feature> res;
    TiXmlDocument doc;
    doc.Parse(xml);

    auto patch = doc.FirstChild("patch");

    // Revision
    int rev;
    patch->QueryIntAttribute("revision", &rev);
    res.emplace_back("REVISION", INT, rev, "");

    // Author
    auto meta = patch->FirstChild("meta");
    if (meta->Attribute("author"))
    {
        res.emplace_back("AUTHOR", STRING, 0,
                        meta->Attribute("author"));
    }

    // Tags
    auto tags = meta->FirstChild("tags");
    auto tag = tags->FirstChildElement();
    while (tag)
    {
        res.emplace_back("TAG", STRING, 0,
                        tag->Attribute("tag"));
        tag = tag->NextSiblingElement();
    }

    // Scene mode
    auto parameters = patch->FirstChild("parameters");
    auto par = parameters->FirstChildElement();
    while (par)
    {
        if (strcmp(par->Value(), "scenemode") == 0)
        {
            int sm;
            par->QueryIntAttribute("value", &sm);
            res.emplace_back("SCENE_MODE", STRING, 0,
                            scene_mode_names[sm]);
        }

        // FX types
        std::string s = par->Value();
        if (s.find("fx") == 0 && s.find("_type") != std::string::npos)
        {
            int fx_type;
            par->QueryIntAttribute("value", &fx_type);
            if (fx_type != 0)
            {
                res.emplace_back("FX", STRING, 0,
                                fx_type_shortnames[fx_type]);
            }
        }

        // Filter types
        if (s.find("_filter") != std::string::npos &&
            s.find("_type") != std::string::npos)
        {
            int filter_type;
            par->QueryIntAttribute("value", &filter_type);
            if (filter_type != 0)
            {
                res.emplace_back("FILTER", STRING, 0,
                                filter_type_names[filter_type]);
            }
        }

        par = par->NextSiblingElement();
    }

    return res;
}
```

### 27.6.3 Searching and Filtering

#### Simple Search

```cpp
std::vector<patchRecord> rawQueryForNameLike(const std::string &name)
{
    std::string query =
        "SELECT p.id, p.path, p.category, p.name, pf.feature_svalue "
        "FROM Patches as p, PatchFeature as pf "
        "WHERE pf.patch_id == p.id "
        "  AND pf.feature LIKE 'AUTHOR' "
        "  AND p.name LIKE ? "
        "ORDER BY p.category_type, p.category, p.name";

    auto q = SQL::Statement(conn, query);
    std::string nameLike = "%" + name + "%";
    q.bind(1, nameLike);

    while (q.step())
    {
        int id = q.col_int(0);
        auto path = q.col_str(1);
        auto cat = q.col_str(2);
        auto name = q.col_str(3);
        auto auth = q.col_str(4);
        results.emplace_back(id, path, cat, name, auth);
    }
}
```

#### Advanced Query Parser

The PatchDBQueryParser supports complex queries:

```
bass AND (analog OR warm)
author:Surge category:Leads
tag:pluck -tag:short
```

Query syntax:
- `AND`, `OR`: Boolean operators
- `author:name`: Search by author
- `category:name`: Filter by category
- Implicit AND between terms

### 27.6.4 Favorites

User favorites are stored separately:

```cpp
void PatchDB::setUserFavorite(const std::string &path, bool isIt)
{
    if (isIt)
    {
        auto stmt = SQL::Statement(dbh,
            "INSERT INTO Favorites (\"path\") VALUES (?1)");
        stmt.bind(1, path);
        stmt.step();
    }
    else
    {
        auto stmt = SQL::Statement(dbh,
            "DELETE FROM Favorites WHERE path = ?1");
        stmt.bind(1, path);
        stmt.step();
    }
}

std::vector<std::string> PatchDB::readUserFavorites()
{
    std::vector<std::string> res;
    auto st = SQL::Statement(conn, "SELECT path FROM Favorites;");

    while (st.step())
    {
        res.push_back(st.col_str(0));
    }

    return res;
}
```

### 27.6.5 Asynchronous Database Updates

The PatchDB uses a background worker thread to avoid blocking the UI:

```cpp
struct WriterWorker
{
    std::thread qThread;
    std::mutex qLock;
    std::condition_variable qCV;
    std::deque<EnQAble *> pathQ;
    std::atomic<bool> keepRunning{true};

    void loadQueueFunction()
    {
        while (keepRunning)
        {
            std::vector<EnQAble *> doThis;

            // Wait for work
            {
                std::unique_lock<std::mutex> lk(qLock);
                while (keepRunning && pathQ.empty())
                {
                    qCV.wait(lk);
                }

                // Grab up to 10 items
                auto b = pathQ.begin();
                auto e = (pathQ.size() < 10) ?
                         pathQ.end() : pathQ.begin() + 10;
                std::copy(b, e, std::back_inserter(doThis));
                pathQ.erase(b, e);
            }

            // Process in transaction
            SQL::TxnGuard tg(dbh);
            for (auto *p : doThis)
            {
                p->go(*this);
                delete p;
            }
            tg.end();
        }
    }
};
```

## 27.7 User vs. Factory Patches

### 27.7.1 File System Organization

Patches are organized in three main locations:

#### Factory Patches
```
<install_dir>/resources/data/patches_factory/
├── Basses/
│   ├── Attacky.fxp
│   ├── Bass 1.fxp
│   └── ...
├── Leads/
├── Pads/
├── Keys/
├── Plucks/
├── Sequences/
├── FX/
└── Templates/
    ├── Init Saw.fxp
    ├── Init Sine.fxp
    └── ...
```

#### Third-Party Patches
```
<install_dir>/resources/data/patches_3rdparty/
├── A.Liv/
│   ├── Basses/
│   ├── Keys/
│   └── Leads/
├── Altenberg/
├── Argitoth/
└── Black Sided Sun/
```

#### User Patches
```
<user_data>/Patches/
├── My Category/
│   ├── My Patch 1.fxp
│   └── My Patch 2.fxp
└── Experiments/
```

Platform-specific user data locations:
- **Windows**: `%USERPROFILE%\Documents\Surge XT\Patches\`
- **macOS**: `~/Documents/Surge XT/Patches/`
- **Linux**: `~/.local/share/Surge XT/Patches/`

### 27.7.2 Patch Type Detection

From `/home/user/surge/src/common/SurgeStorage.cpp`:

```cpp
userPatchesPath = userDataPath / "Patches";

// During patch scanning:
fs::path pTmp = patch.parent_path();
while ((pTmp != storage->userPatchesPath) &&
       (pTmp != storage->datapath / "patches_factory") &&
       (pTmp != storage->datapath / "patches_3rdparty"))
{
    parentFiles.push_back(pTmp.filename());
    pTmp = pTmp.parent_path();
}
```

### 27.7.3 Category Hierarchy

The PatchDB creates separate category trees for each type:

```cpp
void PatchDB::addRootCategory(const std::string &name, CatType type)
{
    auto add = SQL::Statement(dbh,
        "INSERT INTO Category "
        "(\"name\", \"leaf_name\", \"isroot\", \"type\", \"parent_id\") "
        "VALUES (?1, ?1, 1, ?2, -1)");
    add.bind(1, name);
    add.bind(2, (int)type);
    add.step();
}

void PatchDB::addSubCategory(const std::string &name,
                              const std::string &leafname,
                              const std::string &parentName,
                              CatType type)
{
    // Find parent ID
    int parentId = -1;
    auto par = SQL::Statement(dbh,
        "SELECT id FROM Category "
        "WHERE Category.name LIKE ?1 AND Category.type = ?2");
    par.bind(1, parentName);
    par.bind(2, (int)type);
    if (par.step())
        parentId = par.col_int(0);

    // Insert child
    auto add = SQL::Statement(dbh,
        "INSERT INTO Category "
        "(\"name\", \"leaf_name\", \"isroot\", \"type\", \"parent_id\") "
        "VALUES (?1, ?2, 0, ?3, ?4)");
    add.bind(1, name);
    add.bind(2, leafname);
    add.bind(3, (int)type);
    add.bind(4, parentId);
    add.step();
}
```

### 27.7.4 Patch Saving Location

When saving a patch:

```cpp
void SurgeSynthesizer::savePatch(bool factoryInPlace, bool skipOverwrite)
{
    fs::path savepath = storage.userPatchesPath;

    if (factoryInPlace)
    {
        // Save in same location as current patch
        savepath = fs::path{storage.patch_list[patchid].path}.parent_path();
    }

    // Get filename from user
    std::string filename = /* dialog result */;
    fs::path fpath = savepath / (filename + ".fxp");

    if (!skipOverwrite && fs::exists(fpath))
    {
        // Confirm overwrite
        storage.userDefaultsProvider->promptForUserValueString(
            /* ... overwrite confirmation ... */);
    }

    savePatchToPath(fpath);
}
```

## 27.8 Patch Conversion and Import

### 27.8.1 Legacy Format Support

Surge can load patches from:

- **Surge Classic** (revisions 1-8): Full backward compatibility
- **Surge 1.6.x** (revisions 9-15): Filter remapping applied
- **Surge 1.7-1.8** (revisions 16-17): Minor parameter adjustments
- **Surge 1.9** (revision 18-21): Most features compatible
- **Surge XT 1.0-1.2** (revisions 22-27): Recent versions
- **Current** (revision 28): Latest format

### 27.8.2 Future Compatibility

The revision system allows:

1. **Forward warnings**: Patches from newer versions show warnings
2. **Graceful degradation**: Unknown features are ignored
3. **Metadata preservation**: Future data is passed through unchanged
4. **Version tracking**: Both patch revision and synth revision stored

```cpp
streamingRevision = revision;  // Patch version
currentSynthStreamingRevision = ff_revision;  // Synth version (28)
```

## 27.9 Performance Considerations

### 27.9.1 Database Indexing

The patch database is rebuilt when:
- First launched after installation
- Patches are added/removed
- User forces refresh
- Schema version changes

Index time scales with patch count:
- ~1000 patches: 2-5 seconds
- ~5000 patches: 10-20 seconds
- ~10000 patches: 30-60 seconds

### 27.9.2 Lazy Loading

Wavetables are not loaded until needed:

```cpp
if (osc.wt.queue_id >= 0)
{
    // Load wavetable on demand
    storage->load_wt(osc.wt.queue_id, &osc.wt);
}
```

### 27.9.3 Memory Footprint

Typical patch memory usage:
- XML data in memory: 10-50 KB per patch
- Database entry: <1 KB per patch
- Loaded wavetables: 512 KB - 4 MB per oscillator
- Total for 1000 patches in database: ~10 MB

## 27.10 Advanced Topics

### 27.10.1 Embedded Tuning Data

Patches can embed custom tuning scales:

```xml
<patchTuning v="base64_encoded_scale_data"
             m="base64_encoded_mapping_data"
             mname="19-TET" />
```

The tuning data is base64-encoded SCL/KBM format.

### 27.10.2 DAW State Persistence

Editor state can be saved with patches:

```xml
<dawExtraState populated="1">
  <instanceZoomFactor v="100" />
  <editor current_scene="0" current_fx="0" modsource="1">
    <overlays>
      <overlay whichOverlay="1" isTornOut="0"
               tearOut_x="100" tearOut_y="100" />
    </overlays>
  </editor>
</dawExtraState>
```

This preserves:
- UI zoom level
- Active scene/FX
- Selected modulation source
- Torn-out overlays and positions

### 27.10.3 Patch Validation

Before loading, patches are validated:

```cpp
// Size check
if (datasize >= (1 << 22))  // 4 MB
{
    storage->reportError("Patch too large", "Patch Load Error");
    return;
}

// FXP header validation
if ((fxp->chunkMagic != 'CcnK') ||
    (fxp->fxMagic != 'FPCh') ||
    (fxp->fxID != 'cjs3'))
{
    storage->reportError("Invalid patch format", "Patch Load Error");
    return;
}

// Patch header validation
if (!memcpy(ph->tag, "sub3", 4) ||
    xmlSz < 0 ||
    xmlSz > 1024 * 1024 * 1024)
{
    std::cerr << "Skipping invalid patch" << std::endl;
    return;
}
```

### 27.10.4 Thread Safety

The PatchDB worker thread handles all database writes:

```cpp
void PatchDB::considerFXPForLoad(const fs::path &fxp,
                                  const std::string &name,
                                  const std::string &catName,
                                  const CatType type)
{
    // Enqueue for background processing
    worker->enqueueWorkItem(
        new WriterWorker::EnQPatch(fxp, name, catName, type));
}
```

This prevents:
- UI blocking during patch scans
- Database lock contention
- File I/O stalls

Database locking with retry logic:

```cpp
catch (SQL::LockedException &le)
{
    lock_retries++;
    if (lock_retries < 10)
    {
        // Re-queue and wait
        std::this_thread::sleep_for(
            std::chrono::seconds(lock_retries * 3));
    }
    else
    {
        storage->reportError(
            "Database locked after multiple retries",
            "Patch Database Error");
    }
}
```

## 27.11 Summary

The Surge XT patch system provides:

1. **Robust format**: FXP container with XML payload
2. **Backward compatibility**: Migrations for all previous versions
3. **Rich metadata**: Tags, categories, author information
4. **Powerful search**: SQLite-backed database with feature extraction
5. **User-friendly**: Favorites, categories, and hierarchical organization
6. **Performance**: Asynchronous indexing and lazy loading
7. **Extensibility**: Forward-compatible design for future features

Key files:
- `/home/user/surge/src/common/SurgePatch.cpp`: Core patch I/O
- `/home/user/surge/src/common/PatchDB.cpp`: Database management
- `/home/user/surge/src/common/SurgeSynthesizerIO.cpp`: High-level save/load
- `/home/user/surge/src/common/PatchFileHeaderStructs.h`: Binary structures

The system balances simplicity (human-readable XML), performance (binary wavetables, database indexing), and robustness (extensive error handling and version migration).
