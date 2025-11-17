# Chapter 35: Open Sound Control (OSC)

**Part VIII: Advanced Topics**

Open Sound Control (OSC) provides Surge XT with a powerful network-based protocol for remote control, automation, and integration with external applications. This chapter explores Surge's comprehensive OSC implementation, which enables bidirectional communication for real-time parameter control, note triggering, modulation routing, and performance feedback.

## 35.1 OSC Basics

### What is OSC?

Open Sound Control is a modern network protocol designed for musical and multimedia applications. Created as a successor to MIDI, OSC provides:

- **Human-readable addressing**: Parameters use hierarchical paths like `/param/a/osc/1/pitch`
- **Network transport**: Communication over UDP/IP enables both local and networked control
- **Type safety**: Messages carry type-tagged data (floats, integers, strings)
- **Bundle support**: Multiple messages can be sent atomically as OSC bundles
- **Bidirectional communication**: Surge can both receive commands and report state changes

The protocol's flexibility makes it ideal for:
- Integration with DAWs and control software (Max/MSP, Pure Data, TouchDesigner)
- Hardware controllers (TouchOSC, Lemur)
- Custom automation scripts (Python, JavaScript)
- Multi-instance synchronization
- Headless operation via command-line tools

### OSC vs. MIDI

While MIDI remains the standard for musical device communication, OSC offers several advantages for software synthesis:

| Feature | MIDI | OSC |
|---------|------|-----|
| **Address Space** | 128 CC values | Unlimited hierarchical paths |
| **Data Resolution** | 7-bit (0-127) | 32-bit float precision |
| **Latency** | Hardware-dependent | Network-dependent (~1-5ms local) |
| **Bidirectional** | Limited | Full duplex |
| **Parameter Names** | Numeric IDs | Human-readable strings |
| **Transport** | Serial/USB | Network (UDP/TCP) |

For Surge XT, OSC complements MIDI rather than replacing it. MIDI excels at real-time note performance, while OSC provides comprehensive parameter control and state querying.

### Network Protocol

Surge's OSC implementation uses UDP (User Datagram Protocol) for low-latency message transport:

```
┌─────────────┐         UDP Port 53280          ┌─────────────┐
│             │ ───────────────────────────────> │             │
│  OSC Client │                                  │  Surge XT   │
│  (Control)  │                                  │ (Synth)     │
│             │ <─────────────────────────────── │             │
└─────────────┘         UDP Port 53281          └─────────────┘
```

**Key characteristics:**

- **Connectionless**: No handshake or persistent connection required
- **Unidirectional channels**: Separate ports for input (53280) and output (53281)
- **Fire-and-forget**: No delivery guarantee (trade-off for low latency)
- **Local or networked**: Works on localhost (127.0.0.1) or across networks

The implementation in `/home/user/surge/src/surge-xt/osc/OpenSoundControl.cpp` uses JUCE's OSC library to handle message parsing, validation, and thread-safe communication.

## 35.2 OSC in Surge XT

### Architecture Overview

Surge's OSC system consists of three primary components:

1. **OpenSoundControl Class** (`OpenSoundControl.h/.cpp`)
   - Inherits from `juce::OSCReceiver` and `juce::OSCReceiver::Listener`
   - Implements `SurgeSynthesizer::ModulationAPIListener` for modulation feedback
   - Manages incoming message parsing and outgoing message generation

2. **OpenSoundControlSettings Overlay** (`OpenSoundControlSettings.h/.cpp`)
   - GUI for configuring OSC ports and IP addresses
   - Validates port numbers and IPv4 addresses
   - Persists settings in patch extra state

3. **Ring Buffer Communication** (in `SurgeSynthProcessor`)
   - Thread-safe queue for passing OSC commands to audio thread
   - Prevents real-time thread blocking during message processing

```cpp
// File: src/surge-xt/osc/OpenSoundControl.h
class OpenSoundControl : public juce::OSCReceiver,
                         public SurgeSynthesizer::ModulationAPIListener,
                         juce::OSCReceiver::Listener<juce::OSCReceiver::RealtimeCallback>
{
  public:
    void oscMessageReceived(const juce::OSCMessage &message) override;
    void oscBundleReceived(const juce::OSCBundle &bundle) override;
    void send(juce::OSCMessage om, bool needsMessageThread);

    int iportnum = DEFAULT_OSC_PORT_IN;   // 53280
    int oportnum = DEFAULT_OSC_PORT_OUT;  // 53281
    std::string outIPAddr = DEFAULT_OSC_IPADDR_OUT; // "127.0.0.1"
    bool listening = false;
    bool sendingOSC = false;
};
```

### Default Ports and Configuration

Surge XT uses standardized default ports defined in `/home/user/surge/src/common/globals.h`:

```cpp
const int DEFAULT_OSC_PORT_IN = 53280;
const int DEFAULT_OSC_PORT_OUT = 53281;
const inline std::string DEFAULT_OSC_IPADDR_OUT = "127.0.0.1";
```

**Port 53280 (Input)**: Surge listens for incoming OSC commands
- Parameter changes
- Note triggers
- Modulation routing
- Patch loading
- Query requests

**Port 53281 (Output)**: Surge sends state updates to external clients
- Parameter value changes (with display strings)
- Modulation routing changes
- Patch load notifications
- Query responses
- Error messages (`/error`)

The choice of ports above 49152 (dynamic/private port range) avoids conflicts with well-known services while remaining outside the typical DAW automation port range.

### OSC Address Space

Surge organizes OSC messages into a hierarchical namespace:

```
/
├── mnote              # MIDI-style notes
├── fnote              # Frequency notes
├── ne/                # Note expressions
│   ├── pitch
│   ├── volume
│   ├── pan
│   ├── timbre
│   └── pressure
├── pbend              # Pitch bend
├── cc                 # Control change
├── chan_at            # Channel aftertouch
├── poly_at            # Polyphonic aftertouch
├── allnotesoff
├── allsoundoff
├── param/             # Parameters (main namespace)
│   ├── macro/1-8      # Macro controls
│   ├── a/             # Scene A parameters
│   ├── b/             # Scene B parameters
│   ├── global/        # Global parameters
│   └── fx/            # Effects parameters
├── mod/               # Modulation routing
│   ├── [a|b]/         # Scene-specific modulators
│   ├── mute/          # Modulation mute controls
│   └── {modulator}/   # Modulator-specific paths
├── patch/             # Patch management
│   ├── load
│   ├── save
│   ├── incr/decr
│   └── random
├── tuning/            # Microtuning
│   ├── scl
│   └── kbm
├── wavetable/         # Wavetable selection
│   └── {scene}/osc/{n}/
└── q/                 # Query prefix
    ├── all_params
    └── all_mods
```

Each parameter in Surge has a unique OSC name generated from its position in the parameter hierarchy. For example:
- `/param/a/osc/1/pitch` - Scene A, Oscillator 1, Pitch parameter
- `/param/global/volume` - Global output volume
- `/param/fx/send/a/1` - FX Send level for Scene A to FX slot 1

## 35.3 Parameter Control

### The /param/ Namespace

Parameter control forms the heart of Surge's OSC implementation. Every modulatable parameter is accessible via a unique OSC address.

**Basic parameter syntax:**
```
/param/{scope}/{category}/{subcategory}/{parameter}
```

**Examples:**
```osc
/param/a/osc/1/pitch 0.5          # Set Scene A Osc 1 pitch to center
/param/b/filter/1/cutoff 0.75     # Set Scene B Filter 1 cutoff to 75%
/param/global/fx/1/param/0 0.3    # Set FX slot 1 parameter 0 to 30%
```

### Parameter Addressing

Parameters are addressed using their `oscName` property, which is constructed during initialization:

```cpp
// File: src/common/Parameter.cpp
void Parameter::create_fullname(std::string pre, std::string subname, ControlGroup cg)
{
    char txt[TXT_SIZE];
    // Construct hierarchical OSC path from parameter metadata
    snprintf(txt, TXT_SIZE, "/param/%s%s/%s", pre.c_str(),
             ctrlgroup_names[cg], subname.c_str());
    oscName = txt;
}
```

The system supports several addressing modes:

1. **Direct parameter access**: Standard parameter values (0.0 - 1.0)
2. **Extended parameter options**: Control parameter modifiers with `+` suffix
3. **Macro controls**: Simplified access to the 8 macro parameters
4. **FX deactivation**: Special handling for effect slot enable/disable

### Value Ranges and Normalization

All OSC parameter values are normalized to the range **0.0 to 1.0**, regardless of the parameter's internal representation:

- **Integer parameters**: 0.0 = min value, 1.0 = max value
- **Boolean parameters**: 0.0 = false, 1.0 = true
- **Float parameters**: Normalized through `value_to_normalized()` and `normalized_to_value()`

```cpp
// File: src/surge-xt/osc/OpenSoundControl.cpp
void OpenSoundControl::sendParameter(const Parameter *p, bool needsMessageThread,
                                     std::string extension)
{
    float val01 = 0.0;
    switch (p->valtype)
    {
    case vt_float:
        val01 = p->value_to_normalized(p->val.f);
        break;
    case vt_int:
        val01 = float(p->val.i);
        break;
    case vt_bool:
        val01 = float(p->val.b);
        break;
    }

    juce::OSCMessage om = juce::OSCMessage(
        juce::OSCAddressPattern(juce::String(p->oscName)));
    om.addFloat32(val01);
    om.addString(p->get_display(false, 0.0)); // Human-readable value
    send(om, needsMessageThread);
}
```

Output messages include both the normalized value and a formatted display string:
```
/param/a/osc/1/pitch 0.500000 "0.00 semitones"
```

### Extended Parameter Options

Parameters can have additional properties controlled via OSC using the `+` suffix notation:

```osc
/param/a/filter/1/cutoff/tempo_sync+ 1.0    # Enable tempo sync
/param/a/lfo/1/rate/abs+ 1.0                # Enable absolute mode
/param/a/env/1/attack/extend+ 1.0           # Enable extended range
/param/a/filter/1/resonance/enable+ 0.0     # Disable parameter
```

Supported extended options:
- `abs+` - Absolute/relative mode (for bipolar parameters)
- `enable+` - Enable/disable parameter (0.0 or 1.0)
- `tempo_sync+` - Tempo synchronization
- `extend+` - Extended range mode
- `deform+` - Deform type (integer selection)
- `const_rate+` / `gliss+` / `retrig+` / `curve+` - Portamento options

### Bidirectional Communication

One of OSC's key advantages is bidirectional feedback. When parameters change (via GUI, MIDI, or OSC), Surge broadcasts updates to OSC output:

**Scenario 1: User adjusts GUI slider**
```
User drags slider → GUI updates parameter → OSC sends update
                                          ↓
                    /param/a/osc/1/pitch 0.635 "7.62 semitones"
```

**Scenario 2: OSC client sets parameter**
```
Client sends: /param/a/osc/1/pitch 0.5
                    ↓
Surge receives → Updates internal state → GUI reflects change
                                        ↓
                    Surge broadcasts: /param/a/osc/1/pitch 0.500 "0.00 semitones"
```

**Scenario 3: MIDI CC learned parameter**
```
MIDI CC received → Parameter changes on audio thread
                                ↓
                    Async callback to message thread
                                ↓
                    /param/global/volume 0.785 "-2.1 dB"
```

The implementation uses listener patterns to observe changes:

```cpp
// Parameter changes on GUI thread
sspPtr->addParamChangeListener("OSC_OUT",
    [ssp = sspPtr](auto str1, auto numvals, auto float0, auto float1,
                   auto float2, auto str2) {
        ssp->param_change_to_OSC(str1, numvals, float0, float1, float2, str2);
    });

// Audio thread parameter changes (e.g., MIDI learn)
synth->addAudioParamListener("OSC_OUT",
    [this, ssp = sspPtr](std::string oname, float fval, std::string valstr) {
        juce::MessageManager::getInstanceWithoutCreating()->callAsync([...]() {
            ssp->param_change_to_OSC(oname, 1, fval, 0., 0., valstr);
        });
    });
```

### Query System

The `/q/` prefix enables parameter state queries without modifying values:

```osc
# Query a single parameter
/q/param/a/osc/1/pitch

# Response (sent to OSC output):
/param/a/osc/1/pitch 0.500000 "0.00 semitones"
/doc/param/a/osc/1/pitch "Pitch" "float" "-96.000000" "96.000000"
/doc/param/a/osc/1/pitch/ext "tempo_sync" "abs" "extend"

# Query all parameters (bulk dump)
/q/all_params

# Query all modulation routings
/q/all_mods
```

Query responses include:
- Current normalized value
- Display string
- Parameter documentation (name, type, min/max)
- Available extended options

This enables clients to:
- Discover Surge's parameter space
- Build dynamic UIs based on current patch
- Synchronize external state on connection
- Validate parameter ranges before sending

## 35.4 Configuration

### Enabling OSC

OSC can be enabled in two ways:

1. **Via GUI Settings Overlay**
   - Menu: **Workflow → Open Sound Control Settings**
   - Toggle "OSC In" and "OSC Out" checkboxes
   - Configure ports and IP address
   - Settings persist in patch extra state

2. **Programmatically via DAW Automation**
   - OSC can auto-start based on saved patch settings
   - Controlled by `dawExtraState.oscStartIn` / `oscStartOut`

```cpp
// File: src/surge-xt/osc/OpenSoundControl.cpp
void OpenSoundControl::tryOSCStartup()
{
    bool startOSCInNow = synth->storage.getPatch().dawExtraState.oscStartIn;
    if (startOSCInNow)
    {
        int defaultOSCInPort = synth->storage.getPatch().dawExtraState.oscPortIn;
        if (defaultOSCInPort > 0)
        {
            if (!initOSCIn(defaultOSCInPort))
                sspPtr->initOSCError(defaultOSCInPort);
        }
    }
    // Similar logic for OSC output...
}
```

### Port Configuration

**Input Port (Default 53280)**
- Valid range: 1-65535
- Must not conflict with output port
- Listens on all network interfaces (0.0.0.0)
- Validation prevents startup errors

**Output Port (Default 53281)**
- Valid range: 1-65535
- Must not conflict with input port
- Sends to specified IP address
- Supports both localhost and network addresses

Port validation logic from `/home/user/surge/src/surge-xt/gui/overlays/OpenSoundControlSettings.cpp`:

```cpp
int OpenSoundControlSettings::validPort(std::string portStr, std::string type)
{
    if (!is_number(portStr))
    {
        storage->reportError(type + " port number must be between 1 and 65535!",
                           "Port Number Error");
        return 0;
    }

    int newPort = std::stoi(portStr);
    if (newPort > 65535 || newPort < 1)
    {
        storage->reportError(type + " port number must be between 1 and 65535!",
                           "Port Number Error");
        return 0;
    }

    return newPort;
}
```

### IP Address Setup

**Output IP Address (Default 127.0.0.1)**
- Supports IPv4 addresses only (current implementation)
- Common configurations:
  - `127.0.0.1` - Localhost (same machine)
  - `192.168.x.x` - Local network
  - `10.0.x.x` - Internal network

IP validation uses regex pattern matching:

```cpp
bool OpenSoundControlSettings::validateIPString(std::string ipStr)
{
    // IPv4 pattern: four numbers (0-255) separated by periods
    std::regex ipPattern("^((25[0-5]|(2[0-4]|1[0-9]|[1-9]|)[0-9])(\\.(?!$)|$)){4}$");

    if (!std::regex_match(ipStr, ipPattern))
    {
        storage->reportError(
            "Please enter a valid IPv4 address, which consists of "
            "four numbers between 0 and 255,\nseparated by periods.",
            "IP Address Error");
        return false;
    }
    return true;
}
```

**Network security considerations:**
- Binding to `0.0.0.0` accepts connections from any interface
- Firewall configuration may be required for network use
- No authentication or encryption (use VPN for sensitive networks)
- Consider localhost-only for security-critical scenarios

### Settings Overlay Interface

The OSC Settings overlay provides:

- **Enable Toggles**: Separate checkbox for input/output
- **Port Fields**: Numeric entry with validation
- **IP Address Field**: Text entry with IPv4 validation
- **Reset Buttons**: Restore factory default values
- **Apply Button**: Activate changes without closing
- **Help Button**: Access OSC specification documentation

The interface updates in real-time:
```cpp
void OpenSoundControlSettings::setAllEnableds()
{
    apply->setEnabled(isInputChanged() || isOutputChanged());
    inPort->setEnabled(enableIn->getToggleState());
    outPort->setEnabled(enableOut->getToggleState());
    outIP->setEnabled(enableOut->getToggleState());

    // Visual feedback for enabled/disabled states
    auto color = skin->getColor(Colors::Dialog::Label::Text);
    inPort->applyColourToAllText(
        color.withAlpha(0.5f + (enableIn->getToggleState() * 0.5f)));
}
```

## 35.5 Use Cases

### Live Performance Control

OSC enables real-time parameter control from touch interfaces and custom controllers:

**TouchOSC Example:**
```osc
# Macro controls on faders
/param/macro/1 0.65
/param/macro/2 0.32
/param/macro/3 0.88

# Performance controls
/param/global/fx/1/param/0 0.5   # Reverb mix
/param/global/volume 0.75         # Master volume
/patch/incr                       # Next patch
```

**Benefits:**
- Low latency (~1-5ms on local network)
- Multitouch support
- Custom layouts per patch
- Visual feedback from Surge

### Hardware Controllers

Integration with hardware like Lemur, Monome, or custom Arduino/Raspberry Pi controllers:

```python
# Python example using python-osc
from pythonosc import udp_client
import time

client = udp_client.SimpleUDPClient("127.0.0.1", 53280)

def control_filter_sweep():
    """Automate filter cutoff sweep"""
    for i in range(100):
        value = i / 100.0
        client.send_message("/param/a/filter/1/cutoff", value)
        time.sleep(0.01)  # 100 steps over 1 second
```

**Hardware advantages:**
- Physical tactile control
- Lower latency than MIDI over USB
- Simultaneous parameter changes via bundles
- Network distribution (multiple controllers)

### Max/MSP Integration

Max/MSP and Pure Data use OSC extensively for inter-application communication:

```maxpat
[udpsend 127.0.0.1 53280]
|
[prepend /param/a/osc/1/pitch]
|
[scale 0. 127. 0. 1.]  # Convert MIDI range to OSC
|
[ctlin 1]  # MIDI CC 1 (mod wheel)
```

**Advanced Max use cases:**
- Algorithmic composition controlling Surge parameters
- Multi-instance synchronization
- Real-time granular control mapping
- Integration with sensor data (motion, video, etc.)

### TouchOSC/Lemur Templates

Custom control surfaces optimized for Surge's architecture:

**Layout considerations:**
- Group by scene (A/B pages)
- Macro controls always visible
- Effect send mixing
- Modulation depth controls
- Patch browser

**Example Lemur script:**
```javascript
// Auto-refresh parameter from Surge
if (oscIn == '/param/a/osc/1/pitch')
{
    Fader1.x = getArgument(0);  // Set fader to OSC value
    Label1.content = getArgument(1);  // Display string
}
```

### DAW Automation and Scripting

OSC enables headless operation and batch processing:

```python
# Automated sound design exploration
import random
from pythonosc import udp_client

client = udp_client.SimpleUDPClient("127.0.0.1", 53280)

def random_patch_exploration(iterations=10):
    """Generate random parameter variations"""
    params = [
        "/param/a/osc/1/pitch",
        "/param/a/filter/1/cutoff",
        "/param/a/lfo/1/rate",
    ]

    for i in range(iterations):
        client.send_message("/patch/random", [])
        time.sleep(0.5)

        for param in params:
            value = random.random()
            client.send_message(param, value)

        # Record or analyze result
        time.sleep(2)
```

**Batch processing scenarios:**
- Preset randomization and curation
- Automated A/B testing of settings
- Parameter space exploration
- Regression testing
- Wavetable audition scripts

## 35.6 OSC Message Format

### Address Patterns

OSC addresses follow a hierarchical URL-like syntax:

```
/namespace/[scope]/category/subcategory/parameter[/option+]
```

**Rules:**
- Must start with `/`
- Case-sensitive
- Use lowercase for consistency
- Slashes separate hierarchy levels
- No spaces (use underscores if needed)

**Pattern matching (in implementations supporting wildcards):**
```osc
/param/a/osc/*/pitch       # All oscillator pitches in Scene A
/param/*/filter/1/*        # All Filter 1 parameters, both scenes
```

Note: Surge currently uses exact address matching, not wildcards.

### Type Tags and Value Marshalling

OSC messages carry type-tagged values. Surge primarily uses:

**Float (f)**: Most common for continuous parameters
```osc
/param/a/osc/1/pitch ,f 0.5
                     ↑  ↑
                   type value
```

**String (s)**: For file paths and display strings
```osc
/patch/load ,s "/path/to/patch"
```

**Multiple arguments**: Notes and MIDI messages
```osc
/mnote ,fff 60.0 100.0 12345.0
       ↑    ↑    ↑     ↑
      type note vel  noteID
```

**Important constraint from OSC specification:**
> All numeric values must be sent as floating-point numbers, even for parameters that represent integers or booleans internally.

```cpp
// File: src/surge-xt/osc/OpenSoundControl.cpp
void OpenSoundControl::oscMessageReceived(const juce::OSCMessage &message)
{
    if (!message[0].isFloat32())
    {
        sendNotFloatError("param", "");
        return;
    }
    float val = message[0].getFloat32();
    // Process normalized value...
}
```

### Message Examples

**Note triggering:**
```osc
# MIDI-style note on
/mnote 60.0 127.0 1001.0

# Frequency note on (440 Hz A4)
/fnote 440.0 100.0 2001.0

# Note release with velocity
/mnote/rel 60.0 64.0 1001.0

# All notes off
/allnotesoff
```

**Parameter control:**
```osc
# Set Scene A Oscillator 1 pitch to +12 semitones
/param/a/osc/1/pitch 0.625

# Enable Scene B Filter 2 tempo sync
/param/b/filter/2/cutoff/tempo_sync+ 1.0

# Set Macro 3 to 50%
/param/macro/3 0.5
```

**Modulation routing:**
```osc
# Route LFO 1 to filter cutoff with 50% depth (Scene A)
/mod/a/lfo1 /param/a/filter/1/cutoff 0.5

# Mute a modulation routing
/mod/mute/a/lfo1 /param/a/filter/1/resonance 1.0

# Query modulation depth
/q/mod/b/env1 /param/b/osc/2/pitch
```

**Patch management:**
```osc
# Load absolute path patch
/patch/load /home/user/Documents/mysound

# Load from user patches directory
/patch/load_user Leads/MyLead

# Save to absolute path
/patch/save /tmp/experiment

# Navigate patches
/patch/incr
/patch/decr
/patch/random
```

**Tuning and wavetables:**
```osc
# Load Scala tuning file
/tuning/scl 22edo

# Select wavetable by ID for Scene A, Oscillator 2
/wavetable/a/osc/2/id 42.0

# Increment wavetable selection
/wavetable/b/osc/1/incr
```

### Error Handling

Surge reports errors to `/error` when OSC output is enabled:

```osc
# Invalid parameter address
→ /param/invalid/path 0.5
← /error "No parameter with OSC address of /param/invalid/path"

# Out of range value (clipped automatically)
→ /param/a/osc/1/pitch 1.5
← (Value clamped to 1.0, no error)

# Wrong data type
→ /param/a/osc/1/pitch "hello"
← /error "/param data value '' is not expressed as a float..."

# Invalid note range
→ /fnote 50000.0 100.0
← /error "Frequency '50000.000000' is out of range. (8.176 - 12543.854)"
```

Error messages are sent asynchronously to avoid blocking the audio thread. Clients should monitor `/error` to detect and handle issues.

## 35.7 Advanced Topics

### Thread Safety

OSC communication operates across multiple threads:

1. **Network Thread** (JUCE OSC receiver): Receives UDP packets
2. **Message Thread** (JUCE): Processes non-realtime operations
3. **Audio Thread**: Synthesizes audio, processes modulation

The implementation uses a lock-free ring buffer to communicate between threads:

```cpp
// File: SurgeSynthProcessor.h
struct oscToAudio {
    enum Type { PARAM, MNOTE, FREQNOTE, MOD, /* ... */ };
    Type type;
    Parameter *param;
    float fval;
    // Additional fields for different message types...
};

// Thread-safe queue
moodycamel::ReaderWriterQueue<oscToAudio> oscRingBuf;
```

Messages are queued on the network thread and consumed by the audio thread:
```cpp
void OpenSoundControl::oscMessageReceived(const juce::OSCMessage &message)
{
    // Parse message, validate, then queue:
    sspPtr->oscRingBuf.push(SurgeSynthProcessor::oscToAudio(
        SurgeSynthProcessor::PARAM, parameter, value, /* ... */));

    // If audio not running, process immediately on this thread
    if (!synth->audio_processing_active)
        sspPtr->processBlockOSC();
}
```

### Bundle Support

OSC bundles allow atomic execution of multiple messages:

```python
# Python example with python-osc
from pythonosc import osc_bundle_builder
from pythonosc import osc_message_builder
import time

bundle = osc_bundle_builder.OscBundleBuilder(
    osc_bundle_builder.IMMEDIATELY)

# Add multiple messages to bundle
bundle.add_content(osc_message_builder.OscMessageBuilder(
    address="/param/a/osc/1/pitch").add_arg(0.5).build())
bundle.add_content(osc_message_builder.OscMessageBuilder(
    address="/param/a/osc/2/pitch").add_arg(0.5).build())

client.send(bundle.build())
```

Bundles are processed atomically in Surge's bundle handler:
```cpp
void OpenSoundControl::oscBundleReceived(const juce::OSCBundle &bundle)
{
    for (int i = 0; i < bundle.size(); ++i)
    {
        auto elem = bundle[i];
        if (elem.isMessage())
            oscMessageReceived(elem.getMessage());
        else if (elem.isBundle())
            oscBundleReceived(elem.getBundle()); // Nested bundles
    }
}
```

### Performance Considerations

**Latency factors:**
- Network stack: ~0.5-2ms (localhost)
- OSC parsing: ~10-50μs per message
- Ring buffer: Lock-free, ~1-5μs
- Audio thread processing: Next buffer boundary

**Best practices:**
- Batch parameter changes in bundles
- Limit update rates (avoid >100 msg/sec per parameter)
- Use local connections when possible
- Monitor `/error` for validation issues
- Query parameter space once, cache addresses

**Bandwidth estimation:**
```
Single parameter message: ~50 bytes
100 parameters/sec: ~5 KB/sec (negligible)
```

Even intensive use (1000 msg/sec) consumes <100 KB/sec, well within network capacity.

## 35.8 Summary

Open Sound Control provides Surge XT with a modern, flexible protocol for remote control and integration:

**Key capabilities:**
- Comprehensive parameter access (all 600+ parameters)
- Note triggering with MPE-like expressions
- Modulation routing manipulation
- Bidirectional communication and feedback
- Query system for state discovery
- Patch and tuning management

**Implementation highlights:**
- JUCE OSC library for cross-platform support
- Thread-safe message queuing
- Normalized value ranges (0.0-1.0)
- Human-readable addressing scheme
- Extensive validation and error reporting

**Common applications:**
- Live performance with touch controllers
- DAW automation scripts
- Multi-instance synchronization
- Batch processing and sound design exploration
- Integration with creative coding environments

The OSC implementation in `/home/user/surge/src/surge-xt/osc/OpenSoundControl.cpp` serves as a reference for adding network control to audio plugins, demonstrating clean separation between protocol handling, parameter management, and real-time audio processing.

For the complete OSC specification, see `/home/user/surge/resources/surge-shared/oscspecification.html` or access it via the Help menu in Surge's OSC Settings dialog.

---

**Next:** [Chapter 36: Python Bindings](36-python-bindings.md) explores programmatic control via the surgepy module.

**Previous:** [Chapter 34: Testing Framework](34-testing.md) covered unit tests and validation.
