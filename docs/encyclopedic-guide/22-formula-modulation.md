# Chapter 22: Formula Modulation

## Introduction

Formula Modulation is one of Surge XT's most powerful and flexible features, allowing users to create custom modulation sources using Lua scripting. Unlike traditional LFOs and envelopes that are limited to predefined shapes and behaviors, Formula modulators enable you to define arbitrary mathematical functions, implement complex stateful behaviors, and even create entirely new modulation paradigms limited only by your creativity and programming skill.

This chapter provides an encyclopedic reference to Surge XT's Formula Modulation system, covering everything from basic concepts to advanced implementation details.

## 22.1 Formula Modulation Basics

### What is Formula Modulation?

Formula Modulation transforms any LFO slot into a programmable modulation source powered by Lua scripting. Instead of selecting from predefined waveform shapes, you write code that computes modulation values on a per-block basis. This approach offers several advantages:

- **Unlimited flexibility**: Create any waveform shape or modulation behavior imaginable
- **Stateful computation**: Maintain variables across processing blocks for complex behaviors
- **Mathematical precision**: Access the full Lua math library for advanced functions
- **Multiple outputs**: Generate up to 8 independent modulation streams simultaneously
- **Dynamic behavior**: Respond to tempo, velocity, key position, macros, and more
- **Shared state**: Communicate between multiple formula modulators via shared tables

### When to Use Formula Modulation

Formula modulators excel in scenarios where traditional modulators fall short:

1. **Custom waveforms**: Generate mathematical functions not available as built-in shapes (tan, log, bessel, etc.)
2. **Algorithmic modulation**: Implement generative or stochastic behaviors
3. **Complex envelopes**: Create multi-stage envelopes with custom curves and trigger logic
4. **Musical patterns**: Build rhythm generators, chord arpeggios, or melodic sequences
5. **Advanced LFO shapes**: Implement sample-and-hold, triggered envelopes, or clock dividers
6. **Interactive modulation**: Create modulators that respond to playing technique
7. **Cross-modulation**: Build modulators that read and respond to other modulation sources

### Advantages Over Traditional Modulators

**Precision and Control**
Formula modulators give you exact mathematical control over every sample. Need a waveform that's `sin(x) * exp(-x)`? Just write it.

**Stateful Behavior**
Unlike traditional LFOs that reset on each cycle, formula modulators can accumulate state, count events, implement filters, or maintain any arbitrary data structure across their lifetime.

**Multiple Outputs**
A single formula modulator can output up to 8 independent signals, effectively replacing multiple LFO slots with one programmable unit.

**Performance**
Despite being scripted, formula modulators use LuaJIT's just-in-time compilation to achieve performance comparable to compiled C++ code. The system includes intelligent caching and compilation strategies to minimize overhead.

## 22.2 Lua Integration

### LuaJIT in Surge XT

Surge XT embeds LuaJIT, a Just-In-Time Compiler for Lua that provides significant performance advantages over standard Lua:

- **JIT compilation**: Lua bytecode is compiled to native machine code at runtime
- **Efficient execution**: Performance approaches hand-written C code for numeric computations
- **Low latency**: Sub-millisecond execution times for typical formula modulators
- **Standard compliance**: Full Lua 5.1 compatibility with extensions

The Lua environment in Surge XT is specifically configured for audio processing, with optimizations for the types of operations common in modulation tasks.

### Sandboxed Execution

For security and stability, formula modulators run in a sandboxed Lua environment with restricted capabilities:

**Allowed Operations:**
- Mathematical computations (all standard math library functions)
- Table creation and manipulation
- String operations (limited set)
- Bitwise operations (via the `bit` library)
- Control flow (if/then, loops, functions)

**Restricted Operations:**
- File I/O (no file access)
- Network operations (no sockets)
- Operating system commands (no os.execute)
- Dynamic code loading (no loadstring for user code)
- Dangerous functions (no debug library access)

This sandboxing ensures that formula modulators cannot compromise system security or stability while still providing full computational power for modulation tasks.

### Performance Characteristics

Formula modulators are evaluated per-audio-block (typically 32 samples at 48kHz) rather than per-sample, balancing CPU efficiency with responsiveness:

**Timing:**
- Block size: 32 samples (default at 48kHz)
- Evaluation rate: ~1.5kHz at 48kHz sample rate
- Typical execution time: 10-100 microseconds per block
- Maximum formula complexity: Thousands of operations per block

**Optimization Strategies:**
- **Compilation caching**: Formulas are compiled once and cached by hash
- **State reuse**: The Lua state persists across blocks, avoiding reinitialization
- **Minimal overhead**: Only changed formulas trigger recompilation
- **Shared state**: Audio and display threads maintain separate Lua states

**Memory Usage:**
- Base overhead: ~50KB per Lua state (one for audio, one for display)
- Per-formula storage: ~1-2KB for typical formulas
- State variables: User-defined, typically <1KB

The performance overhead of formula modulation is negligible on modern CPUs, with a single formula modulator typically consuming less than 0.1% CPU time.

## 22.3 Formula Syntax

Formula modulators consist of two Lua functions: `init()` and `process()`. Both functions receive a `state` table containing modulation parameters and must return the modified state table.

### Function Structure

```lua
function init(state)
    -- Called once when the modulator is created
    -- Initialize custom variables, constants, or objects
    -- state contains: samplerate, block_size, macros, envelope params

    -- Add your custom variables to state
    state.my_variable = initial_value

    return state
end

function process(state)
    -- Called every audio block during playback
    -- state contains: phase, tempo, songpos, envelope params, custom variables

    -- Compute your modulation output
    state.output = computed_value  -- Range: -1.0 to 1.0

    return state
end
```

### Available State Variables

The `state` table is populated with numerous variables that provide information about the current musical and synthesis context:

#### Phase and Timing
- **`phase`** (float, 0.0-1.0): Current position within the LFO cycle
- **`intphase`** or **`cycle`** (int): Integer cycle count since start
- **`tempo`** (float): Current tempo in BPM
- **`songpos`** (float): DAW playback position in beats

#### LFO Parameters
- **`rate`** (float): LFO rate parameter value
- **`startphase`** (float): LFO start phase setting
- **`amplitude`** (float): LFO amplitude parameter
- **`deform`** (float): LFO deform parameter

#### Envelope Parameters
- **`delay`** (float): Envelope delay time
- **`attack`** (float): Envelope attack time
- **`hold`** (float): Envelope hold time
- **`decay`** (float): Envelope decay time
- **`sustain`** (float): Envelope sustain level
- **`release`** (float): Envelope release time
- **`released`** (bool): Whether the note has been released

#### System Information
- **`samplerate`** (float): Audio sample rate (init only)
- **`block_size`** (int): Processing block size (init only)
- **`voice_count`** (int): Number of currently active voices
- **`is_rendering_to_ui`** (bool): True when rendering for display

#### Voice-Specific (when `is_voice` is true)
- **`is_voice`** (bool): True for voice LFOs, false for scene LFOs
- **`key`** (int, 0-127): MIDI note number
- **`channel`** (int, 0-15): MIDI channel
- **`velocity`** (int, 0-127): Note-on velocity
- **`rel_velocity`** (int, 0-127): Note-off velocity
- **`voice_id`** (int): Unique voice identifier
- **`tuned_key`** (float): Key number including tuning adjustments

#### MIDI Controllers
- **`pb`** (float): Pitch bend value
- **`pb_range_up`** (float): Pitch bend range up (semitones)
- **`pb_range_dn`** (float): Pitch bend range down (semitones)
- **`chan_at`** (float): Channel aftertouch
- **`poly_at`** (float): Polyphonic aftertouch (voice only)
- **`cc_mw`** (float): Modulation wheel (CC#1)
- **`cc_breath`** (float): Breath controller (CC#2)
- **`cc_expr`** (float): Expression (CC#11)
- **`cc_sus`** (float): Sustain pedal (CC#64)

#### MPE (MIDI Polyphonic Expression)
- **`mpe_enabled`** (bool): Whether MPE mode is active
- **`mpe_bend`** (float): Per-note pitch bend (voice only)
- **`mpe_timbre`** (float): MPE timbre/CC74 (voice only)
- **`mpe_pressure`** (float): Per-note pressure (voice only)
- **`mpe_bendrange`** (int): MPE pitch bend range (voice only)

#### Voice Management
- **`lowest_key`** (float): Lowest currently-held key
- **`highest_key`** (float): Highest currently-held key
- **`latest_key`** (float): Most recently pressed key
- **`poly_limit`** (int): Voice polyphony limit
- **`play_mode`** (int): Playback mode (poly/mono/etc.)
- **`scene_mode`** (int): Scene mode (single/split/dual)
- **`split_point`** (int): Key split point

#### Macros
- **`macros`** (table): Array of 8 macro values (1-indexed)
  - Access via: `state.macros[1]` through `state.macros[8]`
  - Range: 0.0 to 1.0 (normalized)

#### Control Flags
- **`use_envelope`** (bool): Whether the envelope should modulate amplitude
- **`clamp_output`** (bool): Whether output should be clamped to [-1, 1]
- **`retrigger_AEG`** (bool): Trigger amp envelope on new cycle
- **`retrigger_FEG`** (bool): Trigger filter envelope on new cycle

### Math Library Functions

Surge XT's formula modulators have access to the complete Lua math library:

#### Trigonometric Functions
```lua
math.sin(x)     -- Sine
math.cos(x)     -- Cosine
math.tan(x)     -- Tangent
math.asin(x)    -- Arc sine
math.acos(x)    -- Arc cosine
math.atan(x)    -- Arc tangent
math.atan2(y,x) -- Arc tangent of y/x
```

#### Exponential and Logarithmic
```lua
math.exp(x)     -- e^x
math.log(x)     -- Natural logarithm
math.log10(x)   -- Base-10 logarithm
math.pow(x,y)   -- x^y (also: x^y)
math.sqrt(x)    -- Square root
```

#### Rounding and Limits
```lua
math.floor(x)   -- Round down
math.ceil(x)    -- Round up
math.abs(x)     -- Absolute value
math.min(x,y,...)  -- Minimum
math.max(x,y,...)  -- Maximum
math.fmod(x,y)  -- Modulo (remainder)
math.modf(x)    -- Integer and fractional parts
```

#### Random Numbers
```lua
math.random()      -- Random float [0,1)
math.random(n)     -- Random int [1,n]
math.random(m,n)   -- Random int [m,n]
math.randomseed(x) -- Set random seed (init only)
```

#### Constants
```lua
math.pi    -- π (3.14159...)
math.huge  -- Infinity
```

### Helper Functions from Prelude

The formula prelude (automatically loaded) provides additional helper functions:

#### Mathematical Helpers
```lua
math.parity(x)          -- 0 for even, 1 for odd
math.sgn(x)             -- -1, 0, or 1 (signum)
math.sign(x)            -- -1 or 1 (sign without zero)
math.rescale(v, in_min, in_max, out_min, out_max)  -- Linear interpolation
math.norm(a, b)         -- Hypotenuse: sqrt(a² + b²)
math.range(a, b)        -- abs(a - b)
math.gcd(a, b)          -- Greatest common divisor
math.lcm(a, b)          -- Least common multiple
```

#### Music Functions
```lua
math.note_to_freq(note, ref)  -- MIDI note to frequency (ref=A440 default)
math.freq_to_note(freq, ref)  -- Frequency to MIDI note
```

### Return Value

The `process()` function must return the state table with the `output` field set:

**Single Output:**
```lua
state.output = value  -- Single modulation value (-1.0 to 1.0)
return state
```

**Multiple Outputs (Vector):**
```lua
state.output = { value1, value2, value3, ... }  -- Up to 8 values
return state
```

**Alternative (direct return):**
```lua
return value  -- For simple cases, return value directly
```

The output is automatically clamped to [-1.0, 1.0] unless `state.clamp_output = false`.

## 22.4 FormulaModulationHelper

The `FormulaModulationHelper` module (`src/common/dsp/modulators/FormulaModulationHelper.cpp`) provides the core implementation of the formula modulation system.

### Architecture Overview

The helper manages the complete lifecycle of formula modulator execution:

1. **Initialization**: Creates Lua states for audio and display threads
2. **Compilation**: Parses and compiles formula strings into functions
3. **Caching**: Stores compiled functions by hash to avoid recompilation
4. **Evaluation**: Executes formulas per-block during synthesis
5. **Cleanup**: Manages memory and removes unused functions

### Compilation and Caching

Formula compilation uses a sophisticated hash-based caching system to minimize overhead:

#### Hash-Based Lookup
```cpp
auto h = fs->formulaHash;  // Hash of formula string
auto pvn = std::string("pvn") + std::to_string(is_display) + "_" + std::to_string(h);
auto pvf = pvn + "_f";      // Process function name
auto pvfInit = pvn + "_fInit";  // Init function name
```

Each formula is hashed, and the compiled functions are stored globally with names derived from the hash. When a formula is re-encountered, the system checks if compiled functions already exist:

**Cache Hit:**
- Retrieve existing compiled functions
- Validate against stored formula string (detect hash collisions)
- Skip compilation entirely

**Cache Miss:**
- Parse formula string to extract `init()` and `process()` functions
- Compile both functions using `parseStringDefiningMultipleFunctions()`
- Store in global Lua state with hash-derived names
- Set restricted execution environment
- Mark formula as valid

#### Environment Restriction

Compiled functions execute in a restricted environment to prevent access to dangerous Lua features:

```cpp
Surge::LuaSupport::setSurgeFunctionEnvironment(s.L, formulaFeatures);
```

The `formulaFeatures` constant specifies which Lua libraries and functions are available (only BASE features: core math, table operations, and safe string functions).

### Error Handling

The system implements multiple layers of error detection and reporting:

#### Compilation Errors
- **Syntax errors**: Detected during parsing
- **Missing functions**: If `init()` or `process()` not found
- **Invalid structure**: Functions with wrong signature

#### Runtime Errors
- **Execution failures**: Lua errors during `process()` evaluation
- **Invalid returns**: Non-numeric or non-table returns
- **NaN/Infinity**: Non-finite outputs are clamped to zero
- **Out-of-bounds vectors**: Array indices outside [1,8]

Error messages are stored in `EvaluatorState.error` and displayed in the UI. Functions that error repeatedly are added to a "known bad" list to prevent infinite error loops:

```cpp
stateData.knownBadFunctions.insert(s.funcName);
```

#### Safe Fallback

When a formula errors, it's replaced with a stub function that returns zero:

```cpp
function surge_reserved_formula_error_stub(m)
    return 0;
end
```

This ensures that synthesis continues even if a formula has errors, preventing audio dropouts or crashes.

### Per-Voice vs. Per-Scene

Formula modulators can run in two contexts:

**Voice Mode (LFO 1-6):**
- One instance per voice
- Has access to voice-specific parameters (key, velocity, channel, etc.)
- `state.is_voice = true`
- Independent phase for each note

**Scene Mode (LFO 7-12):**
- One instance shared across all voices in the scene
- No voice-specific parameters available
- `state.is_voice = false`
- Single phase synchronized across all voices

The system automatically populates the state table with appropriate variables based on the context:

```cpp
if (s.isVoice) {
    addi("channel", s.channel);
    addi("key", s.key);
    addi("velocity", s.velocity);
    addi("voice_id", s.voiceOrderAtCreate);
    addn("tuned_key", s.tunedkey);
}
```

### Dual Lua States

The formula system maintains separate Lua states for audio and display:

**Audio State:**
- Used during synthesis for actual modulation
- Processes at audio block rate
- High-performance critical path
- No random seed (uses hardware random)

**Display State:**
- Used for UI rendering in the LFO display
- Processes at display refresh rate (~30-60Hz)
- Deterministic random seed (8675309) for consistent visualization
- Independent from audio processing

This separation ensures that UI rendering never interferes with audio synthesis and that the display shows a consistent, repeatable waveform.

## 22.5 Formula Editor

The Formula Editor (`src/surge-xt/gui/overlays/LuaEditors.cpp`) provides a comprehensive integrated development environment for creating and testing formula modulators.

### Editor Features

The Formula Editor is a specialized code editor built on JUCE's `CodeEditorComponent` with custom enhancements for Lua development:

#### Syntax Highlighting

Custom Lua tokenizer (`src/surge-xt/gui/util/LuaTokeniserSurge.h`) provides:
- **Keywords**: Lua keywords (function, return, if, then, etc.) in distinct color
- **Comments**: Single-line (`--`) and block comments (`--[[ ]]--`)
- **Strings**: String literals with escape sequence support
- **Numbers**: Integer and floating-point literals
- **Operators**: Mathematical and logical operators
- **Identifiers**: Variable and function names

The color scheme integrates with Surge XT's skinning system, respecting the current skin's syntax colors.

#### Line Numbers and Gutters

- Line numbers displayed in left gutter
- Current line highlighting
- Error indicators (red markers on problematic lines)

#### Code Completion Hints

The editor provides contextual hints for:
- Available state variables
- Lua math functions
- Prelude helper functions
- Macro access syntax

### Error Display

Compilation and runtime errors are displayed prominently:

**Compilation Errors:**
- Shown immediately when editing stops
- Display Lua parser error messages
- Highlight problematic line
- Prevent formula from running until fixed

**Runtime Errors:**
- Displayed during playback
- Show line number and error description
- Formula replaced with zero-output stub
- Allow continued synthesis without crashes

Error messages appear in a dedicated error panel below the editor, with clear formatting and context.

### Presets and Examples

The editor includes access to preset formulas:

**Built-in Presets:**
- Basic waveforms (saw, square, triangle, sine)
- Mathematical functions (exponential, logarithmic)
- Envelope followers
- Clock dividers
- Random modulators
- Step sequencers
- Musical patterns

**Tutorial Patches:**
Surge XT includes 13 tutorial patches demonstrating formula modulation:
1. A Simple Formula
2. Interacting With LFO Parameters
3. The Init Function And State
4. Vector Valued Formulae
5. The Envelope And Its Parameters
6. Macros And Voice Parameters
7. The Prelude
8. Quis Modulatiet Ipsos Modulates
9. Example - Crossfading Oscillators
10. Example - Both Time And Space
11. Example - Reich - Piano Phase
12. Example - Slew Limiter
13. Duophony

These patches provide working examples of various techniques and serve as learning resources.

### Editor Controls

**File Operations:**
- Load formula from file
- Save formula to file
- Import examples and presets

**Editing:**
- Standard text editor shortcuts (Ctrl+C/V/X, Ctrl+Z/Y)
- Find and replace (Ctrl+F)
- Go to line (Ctrl+G)
- Multi-level undo/redo

**Evaluation:**
- Apply formula (immediately compiles and activates)
- Revert to previous version
- Clear/reset editor

## 22.6 Example Formulas

This section provides working formula examples demonstrating various techniques and use cases.

### Example 1: Basic Sawtooth

The simplest formula: a bipolar sawtooth from -1 to +1.

```lua
function process(state)
    -- Linear ramp from -1 to 1
    state.output = state.phase * 2 - 1
    return state
end
```

**Explanation:**
- `state.phase` runs from 0 to 1 over one cycle
- Multiply by 2: range becomes 0 to 2
- Subtract 1: range becomes -1 to 1

### Example 2: Square Wave

Generate a square wave using conditional logic.

```lua
function process(state)
    if state.phase < 0.5 then
        state.output = 1.0
    else
        state.output = -1.0
    end
    return state
end
```

**Explanation:**
- First half of cycle: output +1
- Second half of cycle: output -1
- Creates a bipolar square wave

**Advanced variant with pulse width:**
```lua
function process(state)
    local pw = state.deform  -- Use deform parameter for pulse width
    pw = (pw + 1) * 0.5      -- Convert -1..1 to 0..1
    state.output = (state.phase < pw) and 1.0 or -1.0
    return state
end
```

### Example 3: Exponential Envelope

Create a custom exponential attack/decay envelope.

```lua
function init(state)
    state.curve = 3.0  -- Exponential curve factor
    return state
end

function process(state)
    local env
    if state.phase < 0.5 then
        -- Attack (exponential rise)
        env = (math.exp(state.phase * 2 * state.curve) - 1) / (math.exp(state.curve) - 1)
    else
        -- Decay (exponential fall)
        local p = (state.phase - 0.5) * 2
        env = math.exp(-p * state.curve)
    end

    state.output = env * 2 - 1  -- Convert to bipolar
    return state
end
```

**Explanation:**
- Uses `math.exp()` for exponential curves
- Normalized to 0-1 range then converted to bipolar
- Curve factor controls steepness

### Example 4: Tempo-Synced Clock Divider

Divide the LFO rate by an integer factor.

```lua
function init(state)
    state.division = 4  -- Divide by 4
    state.last_cycle = -1
    state.out = 0
    return state
end

function process(state)
    local current_cycle = state.intphase

    -- Check if we've entered a new cycle
    if current_cycle ~= state.last_cycle then
        if current_cycle % state.division == 0 then
            state.out = 1  -- Trigger on divided beats
        else
            state.out = 0
        end
        state.last_cycle = current_cycle
    end

    state.output = state.out * 2 - 1
    return state
end
```

**Explanation:**
- `intphase` increments on each cycle
- Modulo division creates rhythmic subdivisions
- Maintains state across blocks for gate behavior

### Example 5: Random Sample & Hold

Generate random values that hold for one cycle.

```lua
function init(state)
    state.last_cycle = -1
    state.value = 0
    return state
end

function process(state)
    if state.intphase ~= state.last_cycle then
        -- New cycle: generate new random value
        state.value = math.random() * 2 - 1  -- Bipolar random
        state.last_cycle = state.intphase
    end

    state.output = state.value
    return state
end
```

**Explanation:**
- Uses `state.intphase` to detect new cycles
- `math.random()` generates values 0-1
- Value persists until next cycle begins

### Example 6: Logarithmic Modulation

Apply logarithmic scaling for musical frequency sweeps.

```lua
function process(state)
    local p = state.phase

    -- Logarithmic curve (fast to slow)
    local log_val = math.log(1 + p * 9) / math.log(10)

    state.output = log_val * 2 - 1
    return state
end
```

**Explanation:**
- `log(1 + p * 9)` creates log curve from 0 to 1
- Division by `log(10)` normalizes to 0-1 range
- Useful for exponential filter sweeps

### Example 7: Multi-Output Vector

Generate multiple independent modulation streams.

```lua
function process(state)
    local p = state.phase

    local outputs = {}
    outputs[1] = math.sin(p * 2 * math.pi)           -- Sine
    outputs[2] = p * 2 - 1                           -- Saw
    outputs[3] = (p < 0.5) and 1 or -1               -- Square
    outputs[4] = math.abs(p * 4 - 2) - 1             -- Triangle

    state.output = outputs
    return state
end
```

**Explanation:**
- Returns table with up to 8 independent values
- Each output can modulate a different parameter
- All share the same phase but can have different shapes

### Example 8: Velocity-Sensitive Modulation

Scale modulation depth by MIDI velocity.

```lua
function process(state)
    local base_wave = math.sin(state.phase * 2 * math.pi)

    -- Scale by velocity (0-127 → 0-1)
    local vel_scale = 1.0
    if state.is_voice then
        vel_scale = state.velocity / 127.0
    end

    state.output = base_wave * vel_scale
    return state
end
```

**Explanation:**
- Checks `is_voice` to ensure velocity is available
- Normalizes velocity to 0-1 range
- Multiplies waveform by velocity

### Example 9: Macro-Controlled Wave Morphing

Morph between waveforms using a macro.

```lua
function process(state)
    local p = state.phase
    local morph = state.macros[1]  -- Use Macro 1 for morphing

    -- Generate multiple waveforms
    local saw = p * 2 - 1
    local square = (p < 0.5) and 1 or -1
    local sine = math.sin(p * 2 * math.pi)
    local tri = math.abs(p * 4 - 2) - 1

    -- Morph through waveforms based on macro value
    local output
    if morph < 0.33 then
        -- Morph between saw and square
        local blend = morph * 3
        output = saw * (1 - blend) + square * blend
    elseif morph < 0.66 then
        -- Morph between square and sine
        local blend = (morph - 0.33) * 3
        output = square * (1 - blend) + sine * blend
    else
        -- Morph between sine and triangle
        local blend = (morph - 0.66) * 3
        output = sine * (1 - blend) + tri * blend
    end

    state.output = output
    return state
end
```

**Explanation:**
- Divides macro range into three zones
- Each zone crossfades between two waveforms
- Creates smooth morphing across four shapes

### Example 10: Tangent Function Modulation

Use mathematical functions not available in standard LFOs.

```lua
function process(state)
    local p = state.phase

    -- Tangent function creates interesting asymmetric curves
    -- Limit input to avoid discontinuity at π/2
    local x = (p - 0.5) * 1.5  -- Range: -0.75 to 0.75
    local tan_val = math.tan(x)

    -- Clamp extreme values
    if tan_val > 10 then tan_val = 10 end
    if tan_val < -10 then tan_val = -10 end

    -- Normalize to -1..1
    state.output = tan_val / 10

    return state
end
```

**Explanation:**
- `math.tan()` creates steep curves near π/2
- Input range limited to avoid discontinuity
- Output clamped and normalized

### Example 11: Attack-Hold-Decay Envelope with State

Custom envelope using the prelude's AHD helper.

```lua
function init(state)
    surge = require('surge')

    state.env = surge.mod.AHDEnvelope:new({
        a = 0.2,   -- Attack time (proportion of cycle)
        h = 0.3,   -- Hold time
        d = 0.5    -- Decay time
    })

    return state
end

function process(state)
    local env_val = state.env:at(state.phase)
    state.output = env_val * 2 - 1  -- Convert to bipolar
    return state
end
```

**Explanation:**
- Uses prelude's built-in AHD envelope object
- Cleaner than implementing envelope math manually
- Parameters can be adjusted dynamically

### Example 12: Polynomial Wave Shaping

Apply polynomial transformation for complex harmonic content.

```lua
function init(state)
    state.order = 3  -- Polynomial order
    return state
end

function process(state)
    local x = state.phase * 2 - 1  -- Bipolar input

    -- Apply polynomial: x^3 creates odd harmonics
    local shaped = x ^ state.order

    -- Mix with original for more control
    local mix = state.deform  -- -1 to 1
    mix = (mix + 1) * 0.5     -- 0 to 1

    state.output = x * (1 - mix) + shaped * mix
    return state
end
```

**Explanation:**
- Polynomial shaping adds harmonics
- Odd exponents preserve wave symmetry
- Deform parameter controls effect amount

### Example 13: Phase-Locked Harmonics

Generate harmonics locked to the fundamental phase.

```lua
function process(state)
    local fundamental = math.sin(state.phase * 2 * math.pi)
    local second = math.sin(state.phase * 4 * math.pi) * 0.5
    local third = math.sin(state.phase * 6 * math.pi) * 0.33
    local fourth = math.sin(state.phase * 8 * math.pi) * 0.25

    -- Sum harmonics with decreasing amplitude
    local sum = fundamental + second + third + fourth

    -- Normalize
    state.output = sum / 2.08
    return state
end
```

**Explanation:**
- Each harmonic uses integer multiple of phase
- Amplitudes follow 1/n pattern
- Creates rich, harmonically complex modulation

## 22.7 Advanced Techniques

### Multiple Outputs for Complex Routing

Vector outputs enable sophisticated modulation routing strategies:

**Example: Quadrature Outputs**
```lua
function process(state)
    local phase = state.phase * 2 * math.pi

    state.output = {
        math.sin(phase),           -- 0°
        math.cos(phase),           -- 90°
        -math.sin(phase),          -- 180°
        -math.cos(phase)           -- 270°
    }

    return state
end
```

Route each output to different parameters for phase-related effects like stereo widening or spatialisation.

**Example: Rhythm Pattern Generator**
```lua
function init(state)
    state.pattern = {1, 0, 1, 1, 0, 1, 0, 0}  -- 8-step pattern
    return state
end

function process(state)
    local step = (state.intphase % 8) + 1
    local gate = state.pattern[step]

    -- Generate multiple related outputs
    state.output = {
        gate * 2 - 1,              -- Gate signal
        (step / 8) * 2 - 1,        -- Step position
        math.random() * 2 - 1,     -- Random per step
        gate * (0.5 + state.velocity / 254)  -- Velocity-scaled gate
    }

    return state
end
```

### Sample-Accurate Modulation

While formula evaluation occurs per-block, you can implement sample-accurate behaviors:

**Example: Zero-Crossing Detector**
```lua
function init(state)
    state.last_phase = 0
    state.crossing = false
    return state
end

function process(state)
    -- Detect if we crossed zero this block
    if (state.last_phase > 0.5 and state.phase < 0.5) then
        state.crossing = true
    end

    state.last_phase = state.phase

    state.output = state.crossing and 1 or -1

    return state
end
```

**Limitations:**
- Block-rate quantization (~32 samples)
- Phase delta limited to block size
- Sub-block events invisible

### Integration with Other Modulators

Formula modulators can read (but not write) other modulation sources through creative use of available state:

**Example: Envelope Follower**
```lua
function init(state)
    state.follower = 0
    state.attack_coef = 0.9
    state.release_coef = 0.99
    return state
end

function process(state)
    -- Use macro as input signal
    local input = math.abs(state.macros[1])

    -- Simple envelope follower
    if input > state.follower then
        -- Attack
        state.follower = state.follower * state.attack_coef +
                        input * (1 - state.attack_coef)
    else
        -- Release
        state.follower = state.follower * state.release_coef
    end

    state.output = state.follower * 2 - 1
    return state
end
```

**Indirect Modulation Reading:**
Since formulas can't directly read other modulation sources, use intermediate parameters:
1. Route source modulator to macro
2. Read macro value in formula
3. Process and output result
4. Route formula output to final destination

### Shared State Between Formulators

Use the `shared` table to communicate between multiple formula modulators:

**Formula 1 (Writer):**
```lua
function process(state)
    -- Compute something interesting
    local value = math.sin(state.phase * 2 * math.pi)

    -- Write to shared table
    shared.signal = value

    state.output = value
    return state
end
```

**Formula 2 (Reader):**
```lua
function process(state)
    -- Read from shared table
    local input = shared.signal or 0

    -- Process it differently
    state.output = input * 0.5 + state.phase * 2 - 1
    return state
end
```

**Caveats:**
- Shared state is global across all formula modulators
- No guaranteed evaluation order
- Race conditions possible in voice mode
- Best for scene-level coordination

### Advanced Envelope Control

Formula modulators can override envelope behavior:

**Example: Multi-Segment Custom Envelope**
```lua
function init(state)
    -- Define envelope segments (time, level)
    state.segments = {
        {0.0, 0.0},    -- Start
        {0.1, 1.0},    -- Attack to peak
        {0.2, 0.7},    -- Decay to sustain
        {0.6, 0.7},    -- Hold at sustain
        {1.0, 0.0}     -- Release to zero
    }
    state.use_envelope = false  -- Disable automatic envelope
    return state
end

function process(state)
    local t = state.phase
    local output = 0

    -- Linear interpolation between segments
    for i = 1, #state.segments - 1 do
        local seg1 = state.segments[i]
        local seg2 = state.segments[i + 1]

        if t >= seg1[1] and t <= seg2[1] then
            local segment_phase = (t - seg1[1]) / (seg2[1] - seg1[1])
            output = seg1[2] + (seg2[2] - seg1[2]) * segment_phase
            break
        end
    end

    state.output = output * 2 - 1
    return state
end
```

**Envelope Trigger Control:**
```lua
function init(state)
    state.retrigger_AEG = true   -- Retrigger amp envelope each cycle
    state.retrigger_FEG = false  -- Don't retrigger filter envelope
    return state
end
```

### Performance Optimization Tips

**1. Minimize Table Creation:**
```lua
-- Bad: Creates new table every block
function process(state)
    local output = {0, 0, 0, 0}
    -- ... populate output ...
    state.output = output
    return state
end

-- Good: Reuse table
function init(state)
    state.output_buffer = {0, 0, 0, 0}
    return state
end

function process(state)
    state.output_buffer[1] = value1
    state.output_buffer[2] = value2
    state.output = state.output_buffer
    return state
end
```

**2. Cache Computed Values:**
```lua
function init(state)
    state.two_pi = 2 * math.pi  -- Compute once
    return state
end

function process(state)
    -- Use cached value
    state.output = math.sin(state.phase * state.two_pi)
    return state
end
```

**3. Avoid Expensive Functions in Tight Loops:**
```lua
-- Bad: Repeated expensive calls
function process(state)
    local sum = 0
    for i = 1, 100 do
        sum = sum + math.sin(i * state.phase)
    end
    state.output = sum / 100
    return state
end

-- Good: Minimize loop iterations or cache results
function init(state)
    state.lookup = {}
    for i = 1, 100 do
        state.lookup[i] = math.sin(i / 100)
    end
    return state
end

function process(state)
    local idx = math.floor(state.phase * 100) + 1
    state.output = state.lookup[idx]
    return state
end
```

**4. Use Local Variables:**
```lua
-- Local variable access is faster than table access
function process(state)
    local p = state.phase  -- Copy to local
    local output = math.sin(p * 2 * math.pi)
    state.output = output
    return state
end
```

## 22.8 Debugging and Testing

### Using the Debugger

The Formula Editor includes a built-in debugger for inspecting state:

**View State Variables:**
- Open the debugger panel (button in editor)
- Displays all state variables
- Shows user-defined variables separately from built-in ones
- Updates in real-time during playback

**Filter Variables:**
- Type in filter box to search
- Shows only matching variables and their children
- Helpful for complex state structures

**Groups:**
- User variables (your custom data)
- Built-in variables (phase, tempo, etc.)
- Shared state (global shared table)

### Common Errors and Solutions

**Error: "The init() function must return a table"**
- Cause: Forgot `return state` in init()
- Solution: Ensure init() returns the state table

**Error: "The return of your Lua function must be a number or table"**
- Cause: process() returned wrong type
- Solution: Return either a number or state table with output set

**Error: "output field must be a number or float array"**
- Cause: state.output set to wrong type
- Solution: Ensure output is number or table of numbers

**Error: "attempt to call a nil value"**
- Cause: Calling undefined function
- Solution: Check function name spelling, ensure prelude is loaded

**Error: "Hash collision in function!"**
- Cause: Extremely rare hash collision
- Solution: Modify formula slightly (add comment) to change hash

**NaN or Infinity Output:**
- Cause: Division by zero, invalid math operations
- Solution: Add bounds checking, use math.abs() or conditionals

**Formula Doesn't Update:**
- Cause: Cached bad version
- Solution: Clear cache by modifying formula or reloading patch

### Testing Strategies

**1. Start Simple:**
Begin with minimal formula and add complexity gradually:
```lua
-- Start here
function process(state)
    state.output = state.phase * 2 - 1
    return state
end

-- Then add features incrementally
```

**2. Use Print for Debugging:**
While `print()` doesn't work in Surge, you can use output routing:
```lua
function process(state)
    -- Route debug value to output 2
    state.output = {
        actual_output,
        debug_value  -- Monitor this in LFO display
    }
    return state
end
```

**3. Test in Isolation:**
Create test patches with single note, simple routing
Monitor LFO display to visualize output
Use slow LFO rates to see behavior clearly

**4. Check Edge Cases:**
- Phase = 0, 0.5, 1.0
- Released = true/false
- Velocity = 0, 127
- intphase wraparound
- Macro at extremes (0.0, 1.0)

**5. Performance Testing:**
Monitor CPU usage with Activity Monitor/Task Manager
Compare formula modulator CPU vs. standard LFO
Simplify if formula uses >1% CPU

## 22.9 Best Practices

### Code Organization

**Use Clear Variable Names:**
```lua
-- Bad
function process(s)
    local x = s.p * 2 - 1
    s.o = x
    return s
end

-- Good
function process(state)
    local bipolar_phase = state.phase * 2 - 1
    state.output = bipolar_phase
    return state
end
```

**Document Complex Logic:**
```lua
function init(state)
    -- AHD envelope with exponential curves
    -- Attack: 20% of cycle, Hold: 30%, Decay: 50%
    state.env_attack = 0.2
    state.env_hold = 0.3
    state.env_decay = 0.5
    state.curve_factor = 3.0  -- Higher = more exponential
    return state
end
```

**Separate Concerns:**
```lua
function process(state)
    local base_waveform = generate_waveform(state.phase)
    local scaled = apply_velocity(base_waveform, state)
    local filtered = apply_smoothing(scaled, state)
    state.output = filtered
    return state
end

function generate_waveform(phase)
    return math.sin(phase * 2 * math.pi)
end

function apply_velocity(value, state)
    if state.is_voice then
        return value * (state.velocity / 127.0)
    end
    return value
end

function apply_smoothing(value, state)
    -- One-pole lowpass
    local alpha = 0.8
    state.smoothed = state.smoothed or 0
    state.smoothed = state.smoothed * alpha + value * (1 - alpha)
    return state.smoothed
end
```

### Modulation Design Philosophy

**1. Consider Musical Context:**
Formula modulators are most powerful when they respond to musical parameters:
- Velocity dynamics
- Key position (low notes vs. high notes)
- Tempo and rhythm
- Performance controllers

**2. Design for Exploration:**
Use parameters (deform, macros) to make formula behavior adjustable:
```lua
function process(state)
    -- Use deform for continuously variable behavior
    local mix = (state.deform + 1) * 0.5
    local wav1 = math.sin(state.phase * 2 * math.pi)
    local wav2 = state.phase * 2 - 1
    state.output = wav1 * (1 - mix) + wav2 * mix
    return state
end
```

**3. Predictability vs. Surprise:**
Balance deterministic and random elements:
- Deterministic: Musical, repeatable, controllable
- Random: Organic, evolving, surprising
- Use both strategically

**4. CPU Consciousness:**
While LuaJIT is fast, respect the audio thread:
- Avoid nested loops where possible
- Cache computations in init()
- Use lookup tables for complex functions
- Test CPU usage with voice polyphony

### Patch Design Integration

**Name Your Formulas:**
Use comments at the top of your formula to describe purpose:
```lua
-- PULSE WIDTH MODULATION LFO
-- Controls oscillator pulse width with smoothed square wave
-- Macro 1: Pulse width (0-100%)
-- Deform: Smoothing amount

function process(state)
    -- ... implementation ...
end
```

**Document Macro Usage:**
Clearly indicate which macros are used and their purpose
Include expected ranges
Describe interaction with other parameters

**Version Your Complex Formulas:**
```lua
-- v1.2 - Added velocity scaling and tempo sync
-- v1.1 - Fixed phase discontinuity at cycle boundary
-- v1.0 - Initial implementation
```

**Save Reusable Formulas:**
Build a library of useful formulas
Store in text files for easy reuse
Share with community

## 22.10 Limitations and Workarounds

### Block-Rate Evaluation

Formula modulators evaluate per-block (~32 samples), not per-sample:

**Limitation:**
Events occurring within a block are not detected
Sub-block timing precision impossible

**Workaround:**
- Design modulators that work at block rate
- Use phase-based triggering (cycle boundaries)
- Accept quantization for rhythmic applications

### No Direct Modulation Reading

Formulas cannot directly read other modulation sources:

**Workaround:**
1. Route source modulation to macro parameter
2. Read macro in formula: `state.macros[1]`
3. Process and output result

**Example Chain:**
```
LFO 2 → Macro 1 → Formula reads Macro 1 → Processes → Output to Parameter
```

### Memory Constraints

Each Lua state consumes memory; complex formulas with large tables can add up:

**Best Practices:**
- Limit table sizes in init()
- Reuse tables rather than creating new ones
- Clear unused data
- Monitor memory usage with many voices

### Shared State Synchronization

The `shared` table has no locking mechanism:

**Limitation:**
Race conditions possible with voice-mode formulas
Unpredictable read/write order

**Workaround:**
- Use shared state primarily for scene-level coordination
- Avoid dependencies on precise shared state values
- Design for eventual consistency

### UI Render vs. Audio

Display rendering uses a separate Lua state:

**Limitation:**
Random values differ between display and audio
State variables in audio don't affect display

**Implication:**
- Display is approximate visualization
- Random modulators look different than they sound
- Focus on audio output as ground truth

## 22.11 Future Possibilities

Formula modulation represents a powerful and evolving feature. Potential future enhancements might include:

- **Sample-rate evaluation**: Per-sample formula processing for ultimate precision
- **Direct modulation reading**: Access to other modulators' values
- **Extended prelude**: Additional helper functions and objects
- **Debugging tools**: Breakpoints, step execution, variable watching
- **Formula marketplace**: Community sharing of formulas
- **Visual formula programming**: Node-based programming interface
- **DSP primitives**: Built-in filters, delays, oscillators as Lua objects
- **Inter-formula routing**: Direct connections between formulas
- **C++ hybrid formulas**: Mix Lua scripting with compiled code sections

## Conclusion

Formula Modulation in Surge XT represents a paradigm shift in synthesizer modulation, offering programmers and sound designers unprecedented control and flexibility. By combining the expressive power of Lua scripting with the performance of LuaJIT and the careful design of the surrounding infrastructure, Surge XT delivers a system that is both accessible to beginners and infinitely deep for experts.

Whether you're creating simple custom waveforms, implementing complex algorithmic modulation, or pushing the boundaries of what's possible in a software synthesizer, Formula Modulation provides the tools and freedom to realize your vision. The 13 tutorial patches, extensive documentation, and active community ensure that help is always available as you explore this powerful feature.

As you develop your skills with formula modulators, remember that the best results often come from experimentation and iteration. Start with simple ideas, test them in musical contexts, and gradually build complexity. The combination of immediate feedback, real-time editing, and comprehensive error reporting makes the development process smooth and rewarding.

Formula Modulation is more than a feature—it's an invitation to become a co-designer of Surge XT itself, extending the synthesizer's capabilities in directions its original creators never imagined. We look forward to hearing what you create.

---

**Related Chapters:**
- Chapter 18: Modulation Architecture (modulation routing fundamentals)
- Chapter 19: Envelopes (traditional envelope generators)
- Chapter 20: LFOs (standard LFO shapes and parameters)
- Chapter 21: MSEG (graphical envelope editing)

**External Resources:**
- Tutorial Patches: `resources/data/patches_factory/Tutorials/Formula Modulator/`
- Lua Reference: https://www.lua.org/manual/5.1/
- LuaJIT: https://luajit.org/
- Surge Community Discord: https://discord.gg/surge-synth-team

---

*This chapter is part of the Surge XT Encyclopedic Guide, a comprehensive technical reference for developers, sound designers, and advanced users. For user-facing documentation, please refer to the Surge XT User Manual.*
