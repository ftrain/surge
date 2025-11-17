# Chapter 26: Skinning System

Surge XT's powerful skinning engine provides complete control over the visual appearance of the synthesizer interface. From simple color changes to complete UI redesigns, the skin system allows users and developers to customize every visual aspect while maintaining functional consistency.

## 26.1 Skin Architecture

### 26.1.1 Design Philosophy

The skin architecture separates visual presentation from functional logic, enabling complete UI customization without modifying core synthesizer code. This design achieves several goals:

- **Separation of Concerns**: UI data lives in `/home/user/surge/src/common/SkinModel.h` and `.cpp`, completely free of rendering code
- **Parameter-Centric Design**: UI elements bind to parameters at creation time, with each parameter carrying reasonable defaults
- **Override Capability**: Default compiled layouts can be completely overridden via XML
- **VSTGUI Independence**: Core skin model has no dependencies on the rendering framework

### 26.1.2 SkinModel Overview

The `SkinModel` system (`/home/user/surge/src/common/SkinModel.h`) defines the foundational architecture:

**Component** - Base description of UI element types:
```cpp
namespace Surge::Skin::Components {
    Component Slider, MultiSwitch, Switch, FilterSelector,
              LFODisplay, OscMenu, FxMenu, NumberField,
              VuMeter, Custom, Group, Label, WaveShaperSelector;
}
```

Each component type supports specific properties:
```cpp
enum Properties {
    X, Y, W, H,                              // Position and size
    BACKGROUND, HOVER_IMAGE, IMAGE,          // Images
    ROWS, COLUMNS, FRAMES, FRAME_OFFSET,     // Multi-state controls
    SLIDER_TRAY, HANDLE_IMAGE,               // Slider-specific
    TEXT_COLOR, FONT_SIZE, FONT_STYLE,       // Typography
    BACKGROUND_COLOR, FRAME_COLOR            // Colors
    // ... and many more
};
```

**Connector** - Binds components to parameters or UI functions:
```cpp
// Parameter-connected example
Connector cutoff_1 = Connector("filter.cutoff_1", 310, 223)
    .asHorizontal()
    .asWhite();

// Non-parameter example
Connector osc_display = Connector("osc.display", 4, 81, 141, 99,
    Components::Custom,
    Connector::OSCILLATOR_DISPLAY);
```

Connectors provide the default layout, which XML can override.

### 26.1.3 Three-Layer Architecture

**Layer 1: Compiled Defaults** - `/home/user/surge/src/common/SkinModel.cpp` defines positions, sizes, and component types:
```cpp
namespace Scene {
    Connector volume = Connector("scene.volume", 606, 78)
        .asHorizontal()
        .asWhite()
        .inParent("scene.output.panel");
}
```

**Layer 2: Skin XML** - Overrides compiled defaults with custom values, images, and colors

**Layer 3: Runtime Skin** - `/home/user/surge/src/common/gui/Skin.*` combines layers to produce renderable components

## 26.2 Skin Components

### 26.2.1 Colors (SkinColors.h/.cpp)

Colors use hierarchical naming with full override capability.

**Color Definition**:
```cpp
namespace Surge::Skin {
    struct Color {
        std::string name;
        uint8_t r, g, b, a;

        Color(const std::string &name, int r, int g, int b);
        Color(const std::string &name, int r, int g, int b, int a);
        Color(const std::string &name, uint32_t argb);
    };
}
```

**Hierarchical Organization** (`/home/user/surge/src/common/SkinColors.cpp`):
```cpp
namespace Colors {
    namespace LFO {
        namespace Waveform {
            const Color Background("lfo.waveform.background", 0xFF9000);
            const Color Wave("lfo.waveform.wave", 0xFFFFFF);
            const Color Envelope("lfo.waveform.envelope", 0x6D6D7D);
            const Color Dots("lfo.waveform.dots", 0x000000);
        }
        namespace StepSeq {
            const Color Background("lfo.stepseq.background", 0xFF9000);
            const Color Wave("lfo.stepseq.wave", 0xFFFFFF);
        }
    }

    namespace Slider {
        namespace Label {
            const Color Light("slider.light.label", 0x000000);
            const Color Dark("slider.dark.label", 0xFFFFFF);
        }
        namespace Modulation {
            const Color Positive("slider.modulation.positive", 0x5088C5);
            const Color Negative("slider.modulation.negative", 0x000000);
        }
    }

    namespace Effect::Grid {
        namespace Selected {
            const Color Background("effect.grid.selected.background", 0xFFFFFF);
            const Color Border("effect.grid.selected.border", 0x000000);
            const Color Text("effect.grid.selected.text", 0x202020);
        }
        namespace Bypassed {
            const Color Background("effect.grid.bypassed.background", 0x393B45);
            const Color Border("effect.grid.bypassed.border", 0x000000);
        }
    }
}
```

**Key Color Namespaces**:
- `lfo.*` - LFO display colors (waveform, stepseq, type selector)
- `osc.*` - Oscillator display and controls
- `filter.*` - Filter visualization
- `effect.*` - FX grid and labels
- `slider.*` - Slider labels and modulation indicators
- `dialog.*` - Dialog boxes, buttons, text fields
- `menu.*` - Context menus
- `modsource.*` - Modulation source buttons (unused, used, armed, selected)
- `msegeditor.*` - MSEG editor colors
- `formulaeditor.*` - Formula editor and syntax highlighting
- `patchbrowser.*` - Patch browser and type-ahead
- `vumeter.*` - VU meter levels and notches

### 26.2.2 Fonts (SkinFonts.h/.cpp)

Font system supports TTF files and flexible styling.

**Font Descriptor** (`/home/user/surge/src/common/SkinFonts.h`):
```cpp
namespace Surge::Skin {
    struct FontDesc {
        enum FontStyleFlags {
            plain = 0,
            bold = 1,
            italic = 2
        };

        enum DefaultFamily {
            SANS,    // Default to sans-serif (Lato)
            MONO,    // Monospace
            NO_DEFAULT
        };

        std::string id;
        std::string family;
        int size;
        int style;
        DefaultFamily defaultFamily;
    };
}
```

**Predefined Font Descriptors**:
```cpp
namespace Fonts {
    namespace System {
        const FontDesc Display("fonts.system.display", SANS, 10);
    }

    namespace Widgets {
        const FontDesc NumberField("fonts.widgets.numberfield", SANS, 9);
        const FontDesc EffectLabel("fonts.widgets.effectlabel", SANS, 8);
        const FontDesc ModButtonFont("fonts.widgets.modbutton", SANS, 7);
    }

    namespace LuaEditor {
        const FontDesc Code("fonts.luaeditor.code", MONO, 12);
    }
}
```

### 26.2.3 Images and SVGs

Images are referenced by ID and can be SVG or PNG format.

**Image ID Types**:

1. **Numeric IDs**: `bmp00153.svg` - Five-digit bitmap resource IDs
2. **String IDs**: Semantic names like `SLIDER_HORIZ_HANDLE`
3. **User IDs**: Custom IDs defined in skin XML

**Common Image IDs**:
- `SLIDER_HORIZ_HANDLE` - Horizontal slider handle
- `SLIDER_VERT_HANDLE` - Vertical slider handle
- `TEMPOSYNC_HORIZONTAL_OVERLAY` - Tempo sync indicator overlay
- `TEMPOSYNC_VERTICAL_OVERLAY` - Vertical tempo sync overlay
- Various `IDB_*` constants for built-in controls

**Image Properties**:
- Multi-state images stack frames vertically or in a grid
- Hover images provide mouse-over feedback
- Handle images can differ for normal vs. tempo-synced states

### 26.2.4 Component Positioning

Components support absolute and relative positioning:

**Absolute Positioning**:
```xml
<control ui_identifier="filter.cutoff_1" x="310" y="223" w="56" h="62"/>
```

**Relative Positioning** (within groups):
```xml
<group x="310" y="220">
    <control ui_identifier="filter.cutoff_1" x="0" y="3"/>
    <control ui_identifier="filter.resonance_1" x="15" y="18"/>
</group>
```

**Parent Groups**:
```xml
<!-- Child positioned relative to parent -->
<control ui_identifier="scene.volume" x="0" y="0"
         parent="scene.output.panel"/>
```

## 26.3 Skin XML Format

### 26.3.1 Skin Bundle Structure

A skin bundle is a directory with `.surge-skin` extension:

```
MyCustomSkin.surge-skin/
├── skin.xml              # Main skin definition (required)
├── SVG/                  # SVG image assets
│   ├── bmp00153.svg
│   ├── custom_handle.svg
│   └── ...
├── PNG/                  # PNG image assets
│   └── background.png
└── fonts/                # Custom TTF fonts
    └── CustomFont.ttf
```

**Installation Locations**:
- Factory skins: Surge data directory (installation folder)
- User skins: Surge documents directory (shown via "Show User Folder" menu)
- Recursive search through both locations

### 26.3.2 skin.xml Root Structure

```xml
<surge-skin name="My Custom Skin"
            category="Custom"
            author="Your Name"
            authorURL="https://example.com/"
            version="2">
    <globals>
        <!-- Global settings -->
    </globals>
    <component-classes>
        <!-- Custom component classes -->
    </component-classes>
    <controls>
        <!-- Control overrides -->
    </controls>
</surge-skin>
```

**Root Attributes**:
- `name`: Display name in skin selector
- `category`: Organizational category
- `author`: Creator name
- `authorURL`: Link to author website
- `version`: Skin format version (currently "2")

### 26.3.3 Globals Section

Define colors, images, fonts, and global settings.

**Window Size**:
```xml
<window-size x="904" y="569"/>
```

**Default Image Directory**:
```xml
<defaultimage directory="SVG/"/>
```

**Color Definitions**:
```xml
<!-- Named color for reuse -->
<color id="hotpink" value="#FF69B4"/>

<!-- Direct assignment to system color -->
<color id="lfo.waveform.background" value="#242424"/>

<!-- Reference to named color -->
<color id="patchbrowser.text" value="hotpink"/>

<!-- RGBA format -->
<color id="surgebluetrans" value="#005CB680"/>
```

**Color Formats**:
- `#RRGGBB` - Standard hex RGB
- `#RRGGBBAA` - Hex RGBA with alpha
- Named colors (predefined or user-defined)

**Image Definitions**:
```xml
<!-- Replace built-in image ID -->
<image id="SLIDER_HORIZ_HANDLE" resource="SVG/my_handle.svg"/>

<!-- Define custom image ID -->
<image id="my_custom_image" resource="SVG/custom.svg"/>

<!-- Reference to PNG -->
<image id="background_texture" resource="PNG/texture.png"/>
```

**Font Definitions**:
```xml
<!-- Set default font family -->
<default-font family="Lobster-Regular"/>

<!-- Override specific font -->
<font id="fonts.widgets.modbutton" family="PlayfairDisplay" size="8"/>
```

### 26.3.4 Component Classes Section

Define reusable component configurations (similar to CSS classes).

```xml
<component-classes>
    <!-- Slider class with custom handles -->
    <class name="mod-hslider"
           parent="CSurgeSlider"
           handle_image="mod-norm-h"
           handle_hover_image="mod-hover-h"
           handle_temposync_image="mod-ts-h"/>

    <!-- Vertical slider variant -->
    <class name="mod-vslider"
           parent="CSurgeSlider"
           handle_image="mod-norm-v"
           handle_hover_image="mod-hover-v"
           handle_temposync_image="mod-ts-v"/>

    <!-- Switch with custom images -->
    <class name="loud-prev-next"
           parent="CHSwitch2"
           image="loud_pn"
           hover_image="loud_pn_hover"/>
</component-classes>
```

**Parent Classes** (built-in C++ classes):
- `CSurgeSlider` - Standard sliders
- `CHSwitch2` - Multi-state switches
- `CSwitchControl` - Binary switches
- `CNumberField` - Numeric text fields
- `COSCMenu` - Oscillator menus
- `CFXMenu` - FX menus
- `FilterSelector` - Filter type selector
- `CLFOGui` - LFO display
- `CVuMeter` - VU meter

### 26.3.5 Controls Section

Override individual control properties.

**Basic Property Override**:
```xml
<control ui_identifier="filter.balance" x="446" y="214"/>
```

**Apply Custom Class**:
```xml
<control ui_identifier="lfo.rate" class="mod-hslider"/>
```

**Multiple Properties**:
```xml
<control ui_identifier="osc.param_1"
         x="10" y="100"
         handle_image="custom_handle"
         font_family="CustomFont"
         font_size="13"
         hide_slider_label="true"/>
```

**Number Field Control**:
```xml
<control ui_identifier="scene.pbrange_dn"
         x="157" y="112" w="30" h="13"
         text_color="#FFFFFF"
         text_color.hover="#FF9000"/>
```

**Groups**:
```xml
<group x="310" y="220">
    <control ui_identifier="filter.cutoff_1" x="0" y="0"/>
    <control ui_identifier="filter.resonance_1" x="15" y="15"/>
</group>
```

**Labels**:
```xml
<!-- Custom text label -->
<label x="10" y="30" w="150" h="30"
       font_size="24"
       font_style="bold"
       color="#004400"
       bg_color="#AAFFAA"
       frame_color="#FFFFFF"
       text="Custom Label"/>

<!-- Parameter-bound label -->
<label x="10" y="80" w="150" h="30"
       font_size="24"
       color="#00FF00"
       control_text="osc.param_1"/>

<!-- Image label -->
<label x="140" y="10" w="40" h="40" image="my_icon"/>
```

### 26.3.6 Control Properties Reference

**Position and Size**:
- `x`, `y` - Position in pixels (absolute or relative to parent)
- `w`, `h` - Width and height in pixels

**Images**:
- `image`, `bg_resource`, `bg_id` - Base image
- `hover_image` - Hover state image
- `hover_on_image` - Hover on selected state
- `handle_image` - Slider handle
- `handle_hover_image` - Slider handle hover
- `handle_temposync_image` - Tempo-synced handle
- `slider_tray` - Slider background groove

**Multi-State Controls**:
- `rows` - Number of rows in sprite grid
- `cols`, `columns` - Number of columns
- `frames` - Total number of frames
- `frame_offset` - Starting frame offset
- `draggable` - Allow mouse dragging (true/false)
- `mousewheelable` - Allow mouse wheel (true/false)

**Typography**:
- `font_size` - Font size in points (integer)
- `font_family` - Font family name
- `font_style` - "normal", "bold", "italic", "underline", "strikethrough"
- `text_align` - "left", "center", "right"
- `text_allcaps` - Force uppercase (true/false)
- `text_hoffset` - Horizontal text offset
- `text_voffset` - Vertical text offset

**Colors**:
- `text_color` - Text color
- `text_color.hover` - Hover text color
- `bg_color` - Background color
- `frame_color` - Border/frame color

**Filter Selector**:
- `glyph_active` - Show filter type icons (true/false)
- `glyph_image` - Glyph sprite sheet
- `glyph_hover_image` - Glyph hover sprites
- `glyph_placement` - "above", "below", "left", "right"
- `glyph_w`, `glyph_h` - Individual glyph dimensions

**Slider-Specific**:
- `hide_slider_label` - Hide parameter name (true/false)

## 26.4 Creating Custom Skins

### 26.4.1 Skin Development Workflow

**Phase 1: Setup**

1. Create skin bundle directory:
   ```
   MyCustomSkin.surge-skin/
   ```

2. Create minimal `skin.xml`:
   ```xml
   <surge-skin name="My Custom Skin"
               category="Custom"
               author="Your Name"
               version="2">
       <globals></globals>
       <component-classes></component-classes>
       <controls></controls>
   </surge-skin>
   ```

3. Place in Surge user folder (Menu → "Show User Folder")

4. Restart Surge or reload skins (Menu → Skins → Rescan)

**Phase 2: Use Skin Inspector**

Access via Menu → Skins → "Show Skin Inspector...":

- Lists all UI elements with their `ui_identifier` names
- Shows current position (x, y), size (w, h)
- Displays component type and parent groups
- Lists available color IDs
- Shows image resource IDs

**Phase 3: Iterative Development**

1. Make changes to `skin.xml`
2. Save file
3. In Surge: Menu → Skins → Reload current skin
4. Test changes
5. Repeat

**Phase 4: Asset Creation**

- Export SVG files at exact sizes needed (check original assets)
- Maintain frame counts for multi-state controls
- Keep file naming consistent with resource IDs
- Test on different zoom levels

### 26.4.2 Simple Color Scheme Skin

Create a dark theme by recoloring without changing layout:

```xml
<surge-skin name="Simple Dark" category="Custom"
            author="You" version="2">
    <globals>
        <!-- Define color palette -->
        <color id="almostblack" value="#050505"/>
        <color id="bggray" value="#242424"/>
        <color id="lightgray" value="#B4B4B4"/>
        <color id="surgeblue" value="#005CB6"/>
        <color id="modblue" value="#2E86FE"/>

        <!-- Apply to UI elements -->
        <color id="lfo.waveform.background" value="bggray"/>
        <color id="lfo.waveform.wave" value="modblue"/>
        <color id="lfo.waveform.bounds" value="almostblack"/>

        <color id="slider.light.label" value="lightgray"/>
        <color id="slider.dark.label" value="lightgray"/>

        <color id="patchbrowser.text" value="lightgray"/>

        <color id="effect.grid.selected.background" value="bggray"/>
        <color id="effect.grid.selected.border" value="surgeblue"/>
    </globals>
    <component-classes></component-classes>
    <controls></controls>
</surge-skin>
```

### 26.4.3 Custom Layout Example

Rearrange major UI sections:

```xml
<surge-skin name="Rearranged Layout" category="Custom"
            author="You" version="2">
    <globals>
        <!-- Larger window -->
        <window-size x="1000" y="600"/>
    </globals>
    <component-classes></component-classes>
    <controls>
        <!-- Move oscillator section -->
        <control ui_identifier="osc.display" x="20" y="100"/>
        <control ui_identifier="osc.param.panel" x="170" y="100"/>

        <!-- Relocate filter section -->
        <control ui_identifier="filter.cutoff_1" x="400" y="100"/>
        <control ui_identifier="filter.resonance_1" x="460" y="100"/>

        <!-- Move LFO panel -->
        <control ui_identifier="lfo.main.panel" x="20" y="450"/>

        <!-- Reposition FX section -->
        <control ui_identifier="fx.selector" x="800" y="80"/>
        <control ui_identifier="fx.param.panel" x="750" y="120"/>
    </controls>
</surge-skin>
```

### 26.4.4 Custom Slider Handles

Create distinctive sliders using component classes:

```xml
<surge-skin name="Custom Handles" category="Custom"
            author="You" version="2">
    <globals>
        <defaultimage directory="SVG/"/>

        <!-- Load custom handle images -->
        <image id="round_handle_h" resource="SVG/round_horiz.svg"/>
        <image id="round_handle_h_hover" resource="SVG/round_horiz_hover.svg"/>
        <image id="round_handle_h_ts" resource="SVG/round_horiz_ts.svg"/>

        <image id="diamond_handle_v" resource="SVG/diamond_vert.svg"/>
        <image id="diamond_handle_v_hover" resource="SVG/diamond_vert_hover.svg"/>
    </globals>

    <component-classes>
        <!-- Define horizontal slider class -->
        <class name="round-hslider"
               parent="CSurgeSlider"
               handle_image="round_handle_h"
               handle_hover_image="round_handle_h_hover"
               handle_temposync_image="round_handle_h_ts"/>

        <!-- Define vertical slider class -->
        <class name="diamond-vslider"
               parent="CSurgeSlider"
               handle_image="diamond_handle_v"
               handle_hover_image="diamond_handle_v_hover"/>
    </component-classes>

    <controls>
        <!-- Apply to horizontal sliders -->
        <control ui_identifier="filter.cutoff_1" class="round-hslider"/>
        <control ui_identifier="filter.resonance_1" class="round-hslider"/>
        <control ui_identifier="osc.param_1" class="round-hslider"/>

        <!-- Apply to vertical sliders -->
        <control ui_identifier="lfo.delay" class="diamond-vslider"/>
        <control ui_identifier="lfo.attack" class="diamond-vslider"/>
        <control ui_identifier="scene.gain" class="diamond-vslider"/>
    </controls>
</surge-skin>
```

### 26.4.5 Testing and Debugging

**Common Issues**:

1. **Skin not appearing**: Check file placement and `.surge-skin` extension
2. **XML parse errors**: Validate XML syntax (unmatched tags, quotes)
3. **Images not loading**: Verify paths, check `defaultimage` directory
4. **Colors not applying**: Confirm color ID names match SkinColors.h
5. **Controls misaligned**: Check parent groups, absolute vs. relative positioning

**Debug Strategies**:

- Start minimal, add incrementally
- Use Skin Inspector to verify IDs
- Test reload after each change
- Check Surge console/log for error messages
- Compare against working tutorial skins
- Validate image sizes match originals for multi-state controls

**Best Practices**:

- Comment your XML with `<!-- explanation -->`
- Use named colors for consistency
- Group related controls with `<group>`
- Test at different UI zoom levels (50%, 100%, 200%)
- Provide hover states for interactive elements
- Maintain aspect ratios for resized windows

## 26.5 Factory Skins

### 26.5.1 Default Classic

The built-in Surge Classic skin, compiled into the binary:

- Orange and white color scheme
- Compact 904×569 layout
- All controls with default positions from SkinModel.cpp
- Full hover feedback on interactive elements
- SVG-based graphics for clean scaling

Location: Internal (compiled default)

### 26.5.2 Surge Dark

Modern dark theme (`/home/user/surge/resources/data/skins/dark-mode.surge-skin`):

**Color Palette**:
```xml
<color id="bggray" value="#242424"/>
<color id="bordergray" value="#0F0F0F"/>
<color id="lightgray" value="#B4B4B4"/>
<color id="surgeblue" value="#005CB6"/>
<color id="modblue" value="#2E86FE"/>
<color id="surgeorange" value="#ff9300"/>
```

**Key Features**:
- Dark gray backgrounds (#242424)
- Blue modulation indicators (#2E86FE)
- Orange highlights for selected elements
- Custom slider handles with dark theme
- Full color overrides for all UI sections
- Same layout as Classic (904×569)

**Applied Color Scheme**:
- LFO displays: Dark gray background, blue waveforms
- Sliders: Light gray labels, blue mod indicators
- Effect grid: Transparent backgrounds, colored borders
- Dialogs: Dark theme with light text
- Formula editor: Dark code editor with syntax highlighting

### 26.5.3 Tutorial Skins

Located in `/home/user/surge/resources/data/skins/Tutorials/`, these educational skins demonstrate specific features:

**01 Intro to Skins** - Minimal valid skin, empty overrides

**02 Changing Images and Colors**:
- Color assignment techniques
- Image replacement via `defaultimage` directory
- Direct image ID replacement
- Named color definitions

**03 Moving Your First Control**:
- Absolute positioning
- Parent group manipulation
- Custom group creation
- Relative positioning within groups

**04 Control Classes and User Controls**:
- Component class definition
- Property inheritance
- Class application to controls

**05 Labels And Modulators**:
- Custom text labels
- Parameter-bound labels
- Image labels
- Modulation panel positioning

**06 Using PNG**:
- PNG image assets
- Mixed SVG/PNG usage

**07 The FX Section**:
- FX grid customization
- Effect selector positioning
- FX parameter layout

**08 Hiding Controls**:
- Visibility control
- Layout without controls

**09 Skin Version 2 Expansion**:
- Version 2 features
- Advanced capabilities

**10 Adding Fonts**:
- TTF font inclusion
- Font family assignment
- Per-control font overrides
- Global font defaults

### 26.5.4 Community Skins

Users can create and share custom skins:

**Installation**:
1. Download `.surge-skin` bundle
2. Place in Surge documents folder (Menu → Show User Folder)
3. Restart Surge or Menu → Skins → Rescan
4. Select from Menu → Skins

**Sharing Skins**:
- Package entire `.surge-skin` directory
- Include all assets (SVG, PNG, fonts)
- Document any requirements or notes
- Consider licensing (MIT, CC, etc.)

**Resources**:
- Surge community forums
- GitHub surge-synthesizer organization
- Discord community channels

## 26.6 Advanced Skinning Techniques

### 26.6.1 Stacked Groups

Some controls stack in the same position but display based on context:

```cpp
// In SkinModel.cpp
Connector send_fx_1 = Connector("scene.send_fx_1", 0, 63)
    .asStackedGroupLeader();

Connector send_fx_3 = Connector("scene.send_fx_3", 0, 63)
    .inStackedGroup(send_fx_1);
```

FX sends 1/3 and 2/4 occupy the same space, switching based on FX routing.

### 26.6.2 Multi-State Control Images

Multi-state controls (switches, buttons) use sprite sheets:

**Horizontal Layout** (most common):
```
[State 0][State 1][State 2][State 3]...
```
Frames arranged in rows × columns grid.

**Properties**:
```xml
<control ui_identifier="scene.playmode"
         image="bmp_playmode"
         frames="6"
         rows="6"
         columns="1"/>
```

- 6 play modes (poly, mono, mono ST, etc.)
- 6 frames stacked vertically
- Image height = frame_height × rows

**With Hover States**:
```xml
<control ui_identifier="global.scene_mode"
         image="bmp_scene_mode"
         hover_image="bmp_scene_mode_hover"
         frames="4"
         rows="4"
         columns="1"/>
```

### 26.6.3 Filter Selector Glyphs

Filter selector supports icon glyphs beside menu:

```xml
<control ui_identifier="filter.type_1"
         glyph_active="true"
         glyph_image="filter_glyphs"
         glyph_hover_image="filter_glyphs_hover"
         glyph_placement="left"
         glyph_w="18"
         glyph_h="18"/>
```

Glyph sprite sheet contains icon for each filter type.

### 26.6.4 Window Size Customization

Resize entire UI:

```xml
<globals>
    <window-size x="1200" y="700"/>
</globals>
```

Then reposition all controls proportionally, or redesign layout entirely.

### 26.6.5 Overlay Windows

Position overlay editors (MSEG, Formula, etc.):

```xml
<control ui_identifier="msegeditor.window"
         x="100" y="50" w="750" h="450"/>

<control ui_identifier="formulaeditor.window"
         x="150" y="60" w="700" h="400"/>

<control ui_identifier="tuningeditor.window"
         x="120" y="40" w="760" h="520"/>
```

### 26.6.6 Property Cascading

Properties cascade from defaults → component class → control:

```xml
<component-classes>
    <class name="base-slider" parent="CSurgeSlider"
           font_size="9" font_style="bold"/>

    <class name="large-slider" parent="base-slider"
           font_size="12"/>  <!-- Overrides base-slider -->
</component-classes>

<controls>
    <control ui_identifier="filter.cutoff_1" class="large-slider"
             font_style="italic"/>  <!-- Overrides large-slider -->
</controls>
```

Final result: font_size=12, font_style="italic"

## 26.7 Skin XML Complete Example

Comprehensive skin demonstrating major features:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<surge-skin name="Complete Example"
            category="Documentation"
            author="Surge Synth Team"
            authorURL="https://surge-synthesizer.github.io/"
            version="2">

    <globals>
        <!-- Window customization -->
        <window-size x="950" y="600"/>

        <!-- Asset directories -->
        <defaultimage directory="SVG/"/>

        <!-- Color palette -->
        <color id="dark_bg" value="#1A1A1A"/>
        <color id="light_text" value="#E0E0E0"/>
        <color id="accent_blue" value="#4A90E2"/>
        <color id="accent_orange" value="#FF8C00"/>
        <color id="mod_green" value="#50C878"/>

        <!-- Apply colors to UI -->
        <color id="lfo.waveform.background" value="dark_bg"/>
        <color id="lfo.waveform.wave" value="accent_blue"/>
        <color id="slider.light.label" value="light_text"/>
        <color id="slider.modulation.positive" value="mod_green"/>
        <color id="effect.grid.selected.border" value="accent_orange"/>

        <!-- Custom images -->
        <image id="custom_h_handle" resource="SVG/handle_h.svg"/>
        <image id="custom_h_handle_hover" resource="SVG/handle_h_hover.svg"/>
        <image id="custom_h_handle_ts" resource="SVG/handle_h_ts.svg"/>

        <!-- Fonts -->
        <default-font family="Lato"/>
        <font id="fonts.widgets.modbutton" family="Lato" size="8"/>
    </globals>

    <component-classes>
        <!-- Custom horizontal slider class -->
        <class name="custom-hslider"
               parent="CSurgeSlider"
               handle_image="custom_h_handle"
               handle_hover_image="custom_h_handle_hover"
               handle_temposync_image="custom_h_handle_ts"
               font_size="9"
               font_style="bold"/>

        <!-- Vertical variant -->
        <class name="custom-vslider"
               parent="CSurgeSlider"
               font_size="8"/>
    </component-classes>

    <controls>
        <!-- Reposition major sections -->
        <control ui_identifier="osc.display" x="10" y="85"/>
        <control ui_identifier="osc.param.panel" x="160" y="85"/>

        <!-- Apply custom classes -->
        <control ui_identifier="filter.cutoff_1" class="custom-hslider"/>
        <control ui_identifier="filter.resonance_1" class="custom-hslider"/>

        <control ui_identifier="scene.gain" class="custom-vslider"/>

        <!-- Custom label -->
        <label x="20" y="20" w="200" h="25"
               font_size="18"
               font_style="bold"
               color="accent_orange"
               text="Complete Example Skin"/>

        <!-- Move overlay windows -->
        <control ui_identifier="msegeditor.window"
                 x="120" y="60" w="760" h="480"/>
    </controls>
</surge-skin>
```

## 26.8 Color Reference

Essential color IDs for common skinning tasks:

**LFO Display**:
- `lfo.waveform.background` - Waveform display background
- `lfo.waveform.wave` - Main waveform line
- `lfo.waveform.envelope` - Envelope overlay
- `lfo.waveform.bounds` - Boundary lines
- `lfo.stepseq.background` - Step sequencer background
- `lfo.stepseq.step.fill` - Active step color

**Oscillator**:
- `osc.waveform` - Oscillator waveform display
- `osc.wavename.frame.hover` - Wavetable name frame on hover
- `osc.wavename.text.hover` - Wavetable name text on hover

**Sliders**:
- `slider.light.label` - Label on light backgrounds
- `slider.dark.label` - Label on dark backgrounds
- `slider.modulation.positive` - Positive modulation indicator
- `slider.modulation.negative` - Negative modulation indicator

**Effects**:
- `effect.grid.selected.background/border/text` - Selected FX slot
- `effect.grid.unselected.*` - Unselected FX slot
- `effect.grid.bypassed.*` - Bypassed FX slot
- `effect.label.text` - FX label text

**Menus**:
- `menu.name` - Menu item name
- `menu.value` - Menu item value
- `menu.name.hover` - Hovered menu item

**Dialogs**:
- `dialog.background` - Dialog background
- `dialog.button.background/border/text` - Button states
- `dialog.textfield.*` - Text entry fields

**MSEG Editor**:
- `msegeditor.background` - Editor background
- `msegeditor.curve` - Main curve
- `msegeditor.grid.primary` - Major grid lines

**Formula Editor**:
- `formulaeditor.background` - Code background
- `formulaeditor.lua.keyword` - Lua keywords
- `formulaeditor.lua.string` - String literals
- `formulaeditor.lua.comment` - Comments

## 26.9 Control Identifier Reference

Common `ui_identifier` values for control positioning:

**Global**:
- `global.volume` - Master volume
- `global.active_scene` - Scene A/B selector
- `global.scene_mode` - Scene mode (single/split/dual)
- `global.fx_bypass` - Global FX bypass
- `controls.vu_meter` - Main VU meter

**Scene**:
- `scene.volume`, `scene.pan`, `scene.width` - Output controls
- `scene.send_fx_1/2/3/4` - FX send levels
- `scene.pitch`, `scene.octave` - Pitch controls
- `scene.portamento` - Portamento time
- `scene.playmode` - Poly/mono mode selector

**Oscillator**:
- `osc.display` - Waveform display
- `osc.select` - Oscillator selector (1/2/3)
- `osc.type` - Oscillator type menu
- `osc.pitch` - Pitch slider
- `osc.param_1` through `osc.param_7` - Oscillator parameters

**Mixer**:
- `mixer.level_o1/o2/o3` - Oscillator levels
- `mixer.level_ring12/ring23` - Ring mod levels
- `mixer.level_noise` - Noise level
- `mixer.mute_*`, `mixer.solo_*` - Mute/solo buttons

**Filter**:
- `filter.cutoff_1/2` - Filter cutoffs
- `filter.resonance_1/2` - Filter resonance
- `filter.type_1/2` - Filter type selector
- `filter.config` - Filter routing
- `filter.balance` - Filter balance
- `filter.waveshaper_type` - Waveshaper selector

**Envelopes**:
- `aeg.attack/decay/sustain/release` - Amp envelope
- `feg.attack/decay/sustain/release` - Filter envelope
- `aeg.attack_shape/decay_shape/release_shape` - AEG shapes

**LFO**:
- `lfo.rate`, `lfo.phase`, `lfo.amplitude`, `lfo.deform` - Main params
- `lfo.delay`, `lfo.attack`, `lfo.hold`, `lfo.decay`, `lfo.sustain`, `lfo.release` - EG
- `lfo.shape` - LFO type selector
- `lfo.main.panel` - Entire LFO section

**FX**:
- `fx.selector` - FX grid selector
- `fx.type` - FX type menu
- `fx.param.panel` - FX parameters section
- `fx.preset.name` - FX preset name

**Overlays**:
- `msegeditor.window` - MSEG editor
- `formulaeditor.window` - Formula editor
- `tuningeditor.window` - Tuning editor
- `wtseditor.window` - Wavetable editor
- `modlist.window` - Modulation list

## 26.10 Summary

Surge XT's skinning system provides comprehensive visual customization through a well-architected, XML-based approach:

- **Flexible Architecture**: Separation of visual data (SkinModel) from rendering logic enables complete UI customization without code changes
- **Hierarchical Colors**: Named color system with namespaced IDs allows precise theming
- **Component System**: Reusable component classes with property inheritance streamline skin development
- **Inspector Tool**: Built-in skin inspector reveals all IDs, positions, and properties for easy development
- **Asset Support**: SVG and PNG images, custom TTF fonts, multi-state sprites
- **Tutorial Skins**: Comprehensive examples demonstrate all features progressively

The skin system balances power and usability—simple color changes require minimal XML, while complete redesigns have full control over every pixel. Whether creating subtle variations or radical new interfaces, Surge's skinning engine provides the tools for professional-quality results.

**Key Files**:
- `/home/user/surge/src/common/SkinModel.h/.cpp` - Core architecture and defaults
- `/home/user/surge/src/common/SkinColors.h/.cpp` - Color definitions
- `/home/user/surge/src/common/SkinFonts.h/.cpp` - Font system
- `/home/user/surge/resources/data/skins/` - Factory and tutorial skins
- User skins folder - Custom skin installation location

**Next Steps**: Chapter 27 explores the Wavetable Editor, which can be skinned using the techniques described here, particularly overlay window positioning and color theming.
