# Chapter 7: Wavetable Synthesis - Morphing Spectral Landscapes

## Introduction

The **Wavetable Oscillator** is one of Surge XT's most versatile sound sources, offering a journey through morphing timbres that would be impossible with traditional analog synthesis. While the Classic oscillator excels at familiar analog waveforms, the Wavetable oscillator opens a sonic universe where sawtooth transforms into sine, harmonic structures evolve frame by frame, and a single parameter sweep can traverse entirely different timbral spaces.

This chapter explores wavetable synthesis in depth - from the fundamental theory of what a wavetable actually is, through the elegant file format Surge uses, to the sophisticated interpolation algorithms that make seamless morphing possible. We'll examine the BLIT-based implementation that ensures alias-free reproduction, dive into the powerful Lua scripting system for generating wavetables programmatically, and survey the extensive library of factory wavetables.

**Implementation**: `/home/user/surge/src/common/dsp/oscillators/WavetableOscillator.cpp`

## What is a Wavetable?

### Conceptual Foundation

A **wavetable** is fundamentally different from what many musicians assume:

**What it is NOT:**
- A single waveform
- A single-cycle wave stored in a table
- Just "a synthesizer that uses lookup tables"

**What it ACTUALLY is:**
- A collection of many different waveforms (called **frames** or **tables**)
- Each frame is a complete single-cycle waveform (typically 128-4096 samples)
- The oscillator scans through these frames, morphing between them
- Think of it as a "filmstrip" of evolving waveforms

**Visual Analogy:**

```
Frame 0:  ∿∿∿∿∿∿∿∿∿∿  (Sine wave)
Frame 1:  ∿∿∿∿∿∿∿∿∿∿  (Sine with 2nd harmonic)
Frame 2:  ⌢⌢⌢⌢⌢⌢⌢⌢⌢⌢  (More harmonics added)
Frame 3:  /\/\/\/\/\  (Triangle-like)
...
Frame 99: /|/|/|/|/|  (Sawtooth)

Morph parameter → Scans through frames
```

### Wavetable vs. Single-Cycle Waveforms

**Single-cycle waveform** (traditional wavetable synthesis, 1980s samplers):
- ONE waveform, usually 256 or 512 samples
- Played back at different rates for different pitches
- Example: Sampling one cycle of a sawtooth
- Limited timbral variation

**Modern Wavetable** (Surge, Serum, Vital, etc.):
- 10-256 different waveforms in one wavetable
- Each frame is a complete single-cycle wave
- Morph/scan parameter interpolates between frames
- Each frame can have completely different harmonic content
- Enables evolving, dynamic timbres

### Frame Scanning and Morphing

The magic of wavetable synthesis comes from **continuous morphing** between frames:

```cpp
// Conceptual morphing
Frame position: 0.0  → Pure frame 0
Frame position: 0.5  → 50% frame 0, 50% frame 1 (interpolated)
Frame position: 1.0  → Pure frame 1
Frame position: 23.7 → 30% frame 23, 70% frame 24
```

**2D Interpolation:**

Wavetable playback requires interpolation in **two dimensions**:

1. **Horizontal (intra-frame)**: Interpolating between samples *within* a frame
   - Needed because the playback frequency rarely aligns perfectly with sample boundaries
   - Example: Playing middle C (261.63 Hz) from a 128-sample table at 96kHz requires reading samples at fractional positions

2. **Vertical (inter-frame)**: Interpolating *between* frames
   - Controlled by the Morph parameter
   - Creates smooth transitions between different harmonic structures
   - Example: Morphing from frame 23 to frame 24

**The result**: Smooth, alias-free playback with continuous timbral evolution.

## The Surge Wavetable File Format

### Structure Overview

Surge uses a custom `.wt` format - a simple, efficient binary format documented in `/home/user/surge/resources/data/wavetables/WT fileformat.txt`.

**Format specification:**

```
Byte Range   | Content
-------------|----------------------------------------------------------
0-3          | 'vawt' (magic number, big-endian text identifier)
4-7          | wave_size: samples per frame (2-4096, power of 2)
8-9          | wave_count: number of frames (1-512)
10-11        | flags (16-bit bitfield)
12+          | wave data (float32 or int16 format)
End          | optional metadata (null-terminated XML)
```

### Header Structure

From `/home/user/surge/src/common/dsp/Wavetable.h` (lines 30-40):

```cpp
#pragma pack(push, 1)
struct wt_header
{
    // This struct can only contain scalar data that can be memcpy'd.
    // It's read directly from data on the disk.
    char tag[4];              // 'vawt' as big-endian text
    unsigned int n_samples;   // Samples per frame (power of 2)
    unsigned short n_tables;  // Number of frames
    unsigned short flags;     // Configuration bitfield
};
#pragma pack(pop)
```

**Key points:**
- `#pragma pack(push, 1)`: Ensures no padding between fields
- Read directly from disk with `memcpy()` - no parsing needed
- Simple, efficient, platform-independent (with endianness handling)

### Flag Bits Explained

From `Wavetable.h` (lines 76-84):

```cpp
enum wtflags
{
    wtf_is_sample = 1,        // 0x01: File is a sample, not a wavetable
    wtf_loop_sample = 2,      // 0x02: Sample should loop
    wtf_int16 = 4,            // 0x04: Data is int16 (not float32)
    wtf_int16_is_16 = 8,      // 0x08: int16 uses full 16-bit range
    wtf_has_metadata = 0x10,  // 0x10: Metadata XML at end of file
};
```

**Flag combinations:**

1. **Standard wavetable** (flags = 0x00):
   - Not a sample
   - Data in float32 format (-1.0 to +1.0)
   - No metadata

2. **Compressed wavetable** (flags = 0x04):
   - Data in int16 format
   - Uses 15-bit range by default (peak at 2^14 = 16384)
   - Saves 50% disk space

3. **Full-range int16** (flags = 0x0C):
   - Data in int16 format
   - Uses full 16-bit range (peak at 2^15 = 32768)
   - Slightly higher resolution

4. **With metadata** (flags = 0x10):
   - Includes XML metadata after wave data
   - Can store wavetable name, author, description
   - Application-specific data allowed

### Wave Data Layout

**Float32 format** (flags & 0x04 == 0):

```
Size: 4 * wave_size * wave_count bytes
Layout: [frame0_sample0, frame0_sample1, ..., frame0_sampleN,
         frame1_sample0, frame1_sample1, ..., frame1_sampleN,
         ...]
```

**Int16 format** (flags & 0x04 == 1):

```
Size: 2 * wave_size * wave_count bytes
Layout: Same as float32, but 16-bit signed integers
Conversion: float = int16 / (flags & 0x08 ? 32768.0 : 16384.0)
```

**Example**: A wavetable with 100 frames of 2048 samples each:
- Float32: 4 × 2048 × 100 = 819,200 bytes (~800 KB)
- Int16: 2 × 2048 × 100 = 409,600 bytes (~400 KB)

### Metadata Block (Optional)

If `flags & wtf_has_metadata` is set, a null-terminated XML string follows the wave data:

```xml
<wtmeta>
    <name>Cool Wavetable</name>
    <author>Surge User</author>
    <description>A morphing lead sound</description>
    <!-- Application-specific tags allowed -->
</wtmeta>
```

### Resolution and Frame Count Constraints

From `Wavetable.h` (lines 26-27):

```cpp
const int max_wtable_size = 4096;  // Maximum samples per frame
const int max_subtables = 512;     // Maximum number of frames
```

**Common resolutions:**
- 128 samples: Fast, low memory, slight aliasing at high frequencies
- 256 samples: Good balance
- 512 samples: High quality, standard for many commercial wavetables
- 1024 samples: Very high quality
- 2048 samples: Excellent quality, larger file size
- 4096 samples: Maximum quality, 2x memory vs. 2048

**Frame counts:**
- 1 frame: Just a single-cycle waveform (why?)
- 10-50 frames: Typical for simple morphing wavetables
- 100 frames: Smooth morphing with fine control
- 256+ frames: Very smooth morphing, large files

## The Wavetable Class

### Data Structure

From `Wavetable.h` (lines 42-74):

```cpp
class Wavetable
{
public:
    Wavetable();
    ~Wavetable();
    void Copy(Wavetable *wt);
    bool BuildWT(void *wdata, wt_header &wh, bool AppendSilence);
    void MipMapWT();

    void allocPointers(size_t newSize);

public:
    bool everBuilt = false;
    int size;              // Samples per frame (power of 2)
    unsigned int n_tables; // Number of frames
    int size_po2;          // log2(size) - for bit shifting
    int flags;             // wtflags
    float dt;              // Time delta between samples

    // The actual wavetable data - organized as mipmaps × frames
    float *TableF32WeakPointers[max_mipmap_levels][max_subtables];
    short *TableI16WeakPointers[max_mipmap_levels][max_subtables];

    // Backing storage
    size_t dataSizes;
    float *TableF32Data;
    short *TableI16Data;

    // Queue management for thread-safe loading
    int current_id, queue_id;
    bool refresh_display;
    bool force_refresh_display;
    bool refresh_script_editor;
    std::string queue_filename;
    std::string current_filename;
    int frame_size_if_absent{-1};
};
```

### Mipmap System

**What are mipmaps?**

Mipmaps are **pre-calculated downsampled versions** of each frame, used for high frequencies where the full resolution would cause aliasing:

```
Mipmap 0: Full resolution (e.g., 2048 samples)
Mipmap 1: Half resolution (1024 samples)
Mipmap 2: Quarter resolution (512 samples)
Mipmap 3: 1/8 resolution (256 samples)
Mipmap 4: 1/16 resolution (128 samples)
Mipmap 5: 1/32 resolution (64 samples)
Mipmap 6: 1/64 resolution (32 samples)
```

From `Wavetable.h` (line 28):

```cpp
const int max_mipmap_levels = 16;
```

**Why mipmaps?**

When playing high notes, you don't need full wavetable resolution:
- Playing C8 (4186 Hz) at 96 kHz: Only ~23 samples per cycle
- Using a 2048-sample wavetable would **massively oversample**
- Better: Use mipmap level 5 or 6 (32-64 samples)

**Benefits:**
1. **Prevents aliasing**: Lower resolution = fewer high harmonics
2. **Saves CPU**: Fewer samples to read and interpolate
3. **Saves cache**: Smaller data fits in L1/L2 cache

### Mipmap Selection

From `WavetableOscillator.cpp` (lines 336-352):

```cpp
int ts = oscdata->wt.size;
float a = oscdata->wt.dt * pitchmult_inv;

const float wtbias = 1.8f;

mipmap[voice] = 0;

if ((a < 0.015625 * wtbias) && (ts >= 128))
    mipmap[voice] = 6;  // 1/64 resolution
else if ((a < 0.03125 * wtbias) && (ts >= 64))
    mipmap[voice] = 5;  // 1/32 resolution
else if ((a < 0.0625 * wtbias) && (ts >= 32))
    mipmap[voice] = 4;  // 1/16 resolution
else if ((a < 0.125 * wtbias) && (ts >= 16))
    mipmap[voice] = 3;  // 1/8 resolution
else if ((a < 0.25 * wtbias) && (ts >= 8))
    mipmap[voice] = 2;  // 1/4 resolution
else if ((a < 0.5 * wtbias) && (ts >= 4))
    mipmap[voice] = 1;  // 1/2 resolution
```

**The variable `a`:**
- `a = oscdata->wt.dt * pitchmult_inv`
- `dt`: Delta time between samples in the wavetable
- `pitchmult_inv`: Inverse of pitch multiplier (wavelength in samples)
- `a`: Effective fraction of wavetable traversed per sample

**Logic:**
- Higher pitch → smaller `a` → higher mipmap level → lower resolution
- `wtbias = 1.8f`: Tuning parameter for mipmap selection threshold
- Only use higher mipmaps if wavetable has sufficient resolution

**Example** (2048-sample wavetable at 96 kHz):
- C3 (130.81 Hz): `a` ≈ 0.136 → mipmap 0 or 1 (full or half resolution)
- C5 (523.25 Hz): `a` ≈ 0.034 → mipmap 4 (1/16 resolution)
- C7 (2093 Hz): `a` ≈ 0.0085 → mipmap 6 (1/64 resolution)

### Mipmap Offset Calculation

From `WavetableOscillator.cpp` (lines 353-355):

```cpp
mipmap_ofs[voice] = 0;
for (int i = 0; i < mipmap[voice]; i++)
    mipmap_ofs[voice] += (ts >> i);
```

**What is mipmap_ofs?**

The offset into the data array where this mipmap level starts.

**Example** (2048-sample wavetable):
- Mipmap 0 offset: 0 (starts at beginning)
- Mipmap 1 offset: 2048 (after full resolution)
- Mipmap 2 offset: 2048 + 1024 = 3072
- Mipmap 3 offset: 2048 + 1024 + 512 = 3584
- Mipmap 4 offset: 2048 + 1024 + 512 + 256 = 3840

The formula `ts >> i` is equivalent to `ts / (2^i)`, computing the size of each mipmap level.

## WavetableOscillator Implementation

### Class Structure

From `WavetableOscillator.h` (lines 31-98):

```cpp
class WavetableOscillator : public AbstractBlitOscillator
{
public:
    enum wt_params
    {
        wt_morph = 0,       // Table scan/morph position
        wt_skewv,           // Vertical skew (wave shaping)
        wt_saturate,        // Saturation/clipping
        wt_formant,         // Formant shift (time-domain stretching)
        wt_skewh,           // Horizontal skew (phase distortion)
        wt_unison_detune,   // Unison spread amount
        wt_unison_voices,   // Number of unison voices
    };

    enum FeatureDeform
    {
        XT_134_EARLIER = 0,  // Legacy interpolation mode (pre-1.3.5)
        XT_14 = 1 << 0       // Modern continuous interpolation (1.4+)
    };

    // ... member variables
private:
    float (WavetableOscillator::*deformSelected)(float, int);

    float tableipol, last_tableipol;  // Frame interpolation position
    int tableid, last_tableid;         // Current frame ID
    int mipmap[MAX_UNISON];            // Mipmap level per voice
    int mipmap_ofs[MAX_UNISON];        // Mipmap offset per voice
    float formant_t, formant_last;     // Formant parameter
    float hskew, last_hskew;           // Horizontal skew
    int nointerp;                      // Disable frame interpolation?

    // ... more members
};
```

**Inheritance:**
- Extends `AbstractBlitOscillator` to get BLIT infrastructure
- Uses the same convolution and impulse generation as Classic oscillator
- But reads impulse heights from wavetable data instead of calculating them

### Deform Types: Legacy vs. Modern

Surge has **two interpolation modes** for backward compatibility:

**XT_134_EARLIER** (legacy, pre-1.3.5):
- Interpolates between frame N and frame N+1
- Morph parameter directly controls interpolation amount
- Last frame doesn't interpolate (suddenly jumps)
- Used for patches created before version 1.3.5

**XT_14** (modern, 1.4+):
- Continuous interpolation across all frames
- Morph parameter can access the entire frame range smoothly
- No sudden jumps at edges
- Default for new patches

From `WavetableOscillator.cpp` (lines 99-114):

```cpp
nointerp = !oscdata->p[wt_morph].extend_range;

float shape;
float intpart;
if (deformType == XT_134_EARLIER)
{
    shape = oscdata->p[wt_morph].val.f;
}
else
{
    shape = getMorph();
}

shape *= ((float)oscdata->wt.n_tables - 1.f + nointerp) * 0.99999f;
tableipol = modff(shape, &intpart);
if (deformType != XT_134_EARLIER)
    tableipol = shape;
tableid = limit_range((int)intpart, 0, std::max((int)oscdata->wt.n_tables - 2 + nointerp, 0));
```

**The `nointerp` flag:**
- `nointerp = !extend_range`
- If `extend_range = true`: Interpolate between all frames
- If `extend_range = false`: Each morph position selects one discrete frame (no blending)

### Frame Interpolation Methods

The oscillator supports multiple interpolation strategies via function pointers:

```cpp
float (WavetableOscillator::*deformSelected)(float, int);
```

This pointer can point to:
1. `deformLegacy()` - Legacy interpolation (XT_134_EARLIER)
2. `deformContinuous()` - Modern continuous interpolation (XT_14)
3. `deformMorph()` - Alternative morphing algorithm

### The deformLegacy Method

From `WavetableOscillator.cpp` (lines 554-569):

```cpp
float WavetableOscillator::deformLegacy(float block_pos, int voice)
{
    float tblip_ipol = (1 - block_pos) * last_tableipol + block_pos * tableipol;

    // In Continuous Morph mode tblip_ipol gives us position between current and next frame
    // When not in Continuous Morph mode, we don't interpolate so this position should be zero
    float lipol = (1 - nointerp) * tblip_ipol;

    // That 1 - nointerp makes sure we don't read the table off memory, keeps us bounded
    // and since it gets multiplied by lipol, in morph mode ends up being zero - no sweat!
    return (oscdata->wt.TableF32WeakPointers[mipmap[voice]][tableid][state[voice]] *
            (1.f - lipol)) +
           (oscdata->wt.TableF32WeakPointers[mipmap[voice]][tableid + 1 - nointerp][state[voice]] *
            lipol);
}
```

**Breakdown:**

1. **Block position interpolation:**
   ```cpp
   float tblip_ipol = (1 - block_pos) * last_tableipol + block_pos * tableipol;
   ```
   - `block_pos`: Position within current audio block (0.0 to 1.0)
   - Smoothly interpolates from last block's frame position to current

2. **Apply nointerp flag:**
   ```cpp
   float lipol = (1 - nointerp) * tblip_ipol;
   ```
   - If `nointerp = 1`: `lipol = 0` (no interpolation)
   - If `nointerp = 0`: `lipol = tblip_ipol` (full interpolation)

3. **2D lookup and blend:**
   ```cpp
   return (table[mipmap][tableid][state] * (1 - lipol)) +
          (table[mipmap][tableid+1][state] * lipol);
   ```
   - Read from two adjacent frames
   - `state[voice]`: Current sample position within frame (horizontal)
   - `mipmap[voice]`: Selected mipmap level
   - Blend based on `lipol`

**Example:**
- 100 frames, morph = 35.7%
- `tableid = 35`, `tableipol = 0.7`
- `lipol = 0.7`
- Output = 30% of frame 35 + 70% of frame 36

### The deformContinuous Method

From `WavetableOscillator.cpp` (lines 571-585):

```cpp
float WavetableOscillator::deformContinuous(float block_pos, int voice)
{
    block_pos = nointerp ? 1 : block_pos;
    float tblip_ipol = (1 - block_pos) * last_tableipol + block_pos * tableipol;

    int tempTableId = floor(tblip_ipol);
    int targetTableId = min((int)(tempTableId + 1), (int)(oscdata->wt.n_tables - 1));

    float interpolationProc = (tblip_ipol - tempTableId) * (1 - nointerp);

    return (oscdata->wt.TableF32WeakPointers[mipmap[voice]][tempTableId][state[voice]] *
            (1.f - interpolationProc)) +
           (oscdata->wt.TableF32WeakPointers[mipmap[voice]][targetTableId][state[voice]] *
            interpolationProc);
}
```

**Key differences from legacy:**

1. **Continuous frame addressing:**
   ```cpp
   int tempTableId = floor(tblip_ipol);
   int targetTableId = min(tempTableId + 1, n_tables - 1);
   ```
   - `tblip_ipol` can be any value from 0 to n_tables-1
   - No sudden jump at the end

2. **Fractional calculation:**
   ```cpp
   float interpolationProc = (tblip_ipol - tempTableId) * (1 - nointerp);
   ```
   - Pure fractional part of frame position
   - Interpolates smoothly to the last frame

**Example** (100 frames, morph = 99.3%):
- Legacy: Jump from frame 98 to frame 99 (no interpolation at end)
- Continuous: `tempTableId = 99`, `targetTableId = 99`, smooth output

### The Convolute Method: BLIT Integration

The wavetable oscillator uses the same BLIT convolution as the Classic oscillator, but instead of calculating impulse heights mathematically, it **reads them from the wavetable**.

From `WavetableOscillator.cpp` (lines 274-475), the `convolute()` method:

**Step 1: Determine sample to read:**

```cpp
int wtsize = oscdata->wt.size >> mipmap[voice];
state[voice] = state[voice] & (wtsize - 1);
```
- `wtsize`: Size of current mipmap level
- `state[voice]`: Sample index within frame
- `& (wtsize - 1)`: Wrap around (power-of-2 optimization for modulo)

**Step 2: Read level from wavetable:**

```cpp
float newlevel;
newlevel = distort_level((this->*deformSelected)(block_pos, voice));
```
- Call the selected deform function (legacy or continuous)
- Apply vertical distortion (skew, saturation)
- This is the impulse height for the BLIT

**Step 3: Calculate impulse delta:**

```cpp
g = newlevel - last_level[voice];
last_level[voice] = newlevel;

g *= out_attenuation;
```
- `g`: Change in level since last impulse
- This delta is what gets convolved with the windowed sinc
- `out_attenuation`: Normalize output based on unison count

**Step 4: Convolve with windowed sinc:**

```cpp
// Get windowed sinc coefficients
unsigned int m = ((ipos >> 16) & 0xff) * (FIRipol_N << 1);
auto lipol128 = /* ... fractional position ... */;

for (int k = 0; k < FIRipol_N; k += 4)
{
    float *obf = &oscbuffer[bufpos + k + delay];
    auto ob = SIMD_MM(loadu_ps)(obf);
    auto st = SIMD_MM(load_ps)(&storage->sinctable[m + k]);
    auto so = SIMD_MM(load_ps)(&storage->sinctable[m + k + FIRipol_N]);
    so = SIMD_MM(mul_ps)(so, lipol128);
    st = SIMD_MM(add_ps)(st, so);
    st = SIMD_MM(mul_ps)(st, g128);
    ob = SIMD_MM(add_ps)(ob, st);
    SIMD_MM(storeu_ps)(obf, ob);
}
```

This is identical to the Classic oscillator's BLIT implementation (see Chapter 6), but the impulse heights come from wavetable data instead of being calculated.

**The brilliance:**
- Wavetable provides the spectral content (which harmonics, at what levels)
- BLIT ensures band-limited reproduction (no aliasing)
- Best of both worlds: flexibility of wavetables, quality of BLIT

### Formant Processing

The **Formant** parameter implements time-domain stretching/compression:

From `WavetableOscillator.cpp` (lines 403-410):

```cpp
float ft = block_pos * formant_t + (1.f - block_pos) * formant_last;
float formant = storage->note_to_pitch_tuningctr(-ft);
dt *= formant * xt;

int wtsize = oscdata->wt.size >> mipmap[voice];

if (state[voice] >= (wtsize - 1))
    dt += (1 - formant);
```

**What does Formant do?**

It changes the **playback speed** of the wavetable without changing the oscillator pitch:
- Positive formant: Read wavetable faster → higher frequencies in spectrum
- Negative formant: Read wavetable slower → lower frequencies in spectrum
- Pitch stays the same (controlled by BLIT phase)

**The term "formant":**

In speech synthesis, formants are resonant peaks in the spectrum that define vowel sounds. By shifting these peaks up/down (formant shifting), you can change "ah" to "ee" while keeping the pitch constant.

The wavetable Formant parameter does this: shifts the harmonic content up/down while maintaining the fundamental frequency.

**Implementation:**
```cpp
float formant = storage->note_to_pitch_tuningctr(-ft);
dt *= formant;
```
- Convert formant parameter to pitch ratio
- Multiply delta-time by this ratio
- Speeds up or slows down wavetable traversal

### Horizontal Skew

The **Horizontal Skew** parameter applies phase distortion:

From `WavetableOscillator.cpp` (lines 390-395):

```cpp
float xt = ((float)state[voice] + 0.5f) * dt;
const float taylorscale = sqrt((float)27.f / 4.f);
xt = 1.f + hskew * 4.f * xt * (xt - 1.f) * (2.f * xt - 1.f) * taylorscale;
```

**What is this formula?**

It's a **cubic polynomial** that warps the phase:
```
xt = 1 + hskew × 4 × xt × (xt-1) × (2×xt-1) × √(27/4)
```

**Properties:**
- When `hskew = 0`: `xt = 1` (no effect)
- When `hskew > 0`: Early samples compressed, late samples expanded
- When `hskew < 0`: Early samples expanded, late samples compressed

**Visual effect:**

```
hskew = 0:   ___/‾‾‾___   (symmetric)
hskew > 0:   __/‾‾‾‾___   (skewed right)
hskew < 0:   ___/‾‾‾‾__   (skewed left)
```

This creates interesting harmonic changes without changing the wavetable data.

## Wavetable Parameters

### Parameter Overview

From `WavetableOscillator.cpp` (lines 150-167):

```cpp
void WavetableOscillator::init_ctrltypes()
{
    oscdata->p[wt_morph].set_name("Morph");
    oscdata->p[wt_morph].set_type(ct_countedset_percent_extendable_wtdeform);
    oscdata->p[wt_morph].set_user_data(oscdata);

    oscdata->p[wt_skewv].set_name("Skew Vertical");
    oscdata->p[wt_skewv].set_type(ct_percent_bipolar);

    oscdata->p[wt_saturate].set_name("Saturate");
    oscdata->p[wt_saturate].set_type(ct_percent);

    oscdata->p[wt_formant].set_name("Formant");
    oscdata->p[wt_formant].set_type(ct_syncpitch);

    oscdata->p[wt_skewh].set_name("Skew Horizontal");
    oscdata->p[wt_skewh].set_type(ct_percent_bipolar);

    oscdata->p[wt_unison_detune].set_name("Unison Detune");
    oscdata->p[wt_unison_detune].set_type(ct_oscspread);

    oscdata->p[wt_unison_voices].set_name("Unison Voices");
    oscdata->p[wt_unison_voices].set_type(ct_osccount);
}
```

### 1. Morph (Frame Position)

**Purpose:** Scans through wavetable frames

**Range:** 0-100% (maps to frame 0 to frame N-1)

**Type:** `ct_countedset_percent_extendable_wtdeform`
- "Counted set": Knows how many frames exist
- "Extendable": Can access full range with extend_range flag
- "wtdeform": Supports different deform modes

**Default:** 0% (first frame)

**Modulation:**
- LFO: Create evolving timbres
- Envelope: Timbral change over note duration
- Velocity: Brighter sound for harder hits

### 2. Skew Vertical (Wave Shaping)

**Purpose:** Vertical distortion of waveform

**Range:** -100% to +100%

**Implementation** from `WavetableOscillator.cpp` (lines 182-191):

```cpp
float WavetableOscillator::distort_level(float x)
{
    float a = l_vskew.v * 0.5;
    float clip = l_clip.v;

    x = x - a * x * x + a;

    x = limit_range(x * (1 - clip) + clip * x * x * x, -1.f, 1.f);

    return x;
}
```

**The math:**

1. **Skew component:**
   ```cpp
   x = x - a × x² + a
   ```
   - Parabolic distortion
   - Shifts DC offset and adds even harmonics
   - Asymmetric waveform

2. **Combined with saturation:**
   ```cpp
   x = x × (1 - clip) + clip × x³
   ```
   - Linear interpolation between clean and cubic
   - Adds odd harmonics
   - Soft saturation

**Effect:**
- Negative skew: Waveform pushed down
- Positive skew: Waveform pushed up
- Combined with saturation: Rich harmonic distortion

### 3. Saturate

**Purpose:** Soft clipping/saturation

**Range:** 0-100%

**Implementation** (same as above, `distort_level()`):

```cpp
x = limit_range(x * (1 - clip) + clip * x * x * x, -1.f, 1.f);
```

**Behavior:**
- 0%: Clean signal (linear)
- 100%: Full cubic saturation `x³`
- Intermediate: Blend of linear and cubic

**Cubic saturation characteristics:**
- Adds odd harmonics (3rd, 5th, 7th, ...)
- Soft clipping (no harsh edges)
- Classic tube-style distortion

**Processing applied:** After reading from wavetable, before BLIT convolution

### 4. Formant

**Purpose:** Time-domain stretching (spectral shift)

**Range:** -60 semitones to +60 semitones

**Type:** `ct_syncpitch` (same as hard sync parameter)

**Effect:**
- Positive: Harmonics shift up, "brighter" sound
- Negative: Harmonics shift down, "darker" sound
- Does NOT change fundamental pitch

**Use cases:**
- Vocal formant simulation
- "Chipmunk" effect (positive)
- "Monster" effect (negative)
- Spectral animation via modulation

### 5. Skew Horizontal (Phase Distortion)

**Purpose:** Non-linear phase progression

**Range:** -100% to +100%

**Implementation:** Cubic polynomial (described earlier)

**Effect:**
- Changes harmonic balance
- Similar to phase distortion synthesis (Casio CZ series)
- Creates metallic, bell-like tones at extreme settings

**For display** (lines 222-260), uses a pre-computed phase response table:

```cpp
double WavetableOscillator::skewHPhaseResponse[SAMPLES_FOR_DISPLAY] = {
    0.00, 0.00, 0.01, 0.02, 0.03, 0.03, 0.04, 0.05, 0.06, 0.07, 0.07, 0.08,
    /* ... 60 values total ... */
    0.49, 0.54, 0.70, 0.84, 0.92, 0.97
};
```

This table defines the non-linear phase mapping for visual display.

### 6. Unison Detune

**Purpose:** Spread amount for unison voices

**Range:** 0-100 cents (default)
- Can be extended to absolute frequency mode

**Type:** `ct_oscspread`

**Implementation:** Same as Classic oscillator (see Chapter 6)

```cpp
if (n_unison > 1)
    detune += oscdata->p[wt_unison_detune].get_extended(localcopy[id_detune].f) *
              (detune_bias * float(voice) + detune_offset);
```

Each unison voice gets a calculated detune amount based on:
- Voice number
- Detune amount parameter
- Detune bias and offset (spread curve)

### 7. Unison Voices

**Purpose:** Number of unison voices

**Range:** 1-16

**Type:** `ct_osccount`

**Default:** 1

**CPU cost:** Approximately linear with voice count
- 1 voice: 1x CPU
- 4 voices: 4x CPU
- 16 voices: 16x CPU

## Lua Scripting for Wavetables

### Overview

Surge XT includes a powerful **Lua scripting system** for generating wavetables programmatically. Instead of recording samples or using external tools, you can write mathematical formulas to create wavetables.

**Implementation:** `/home/user/surge/src/common/dsp/WavetableScriptEvaluator.cpp`

**Format:** `.wtscript` files (XML containing base64-encoded Lua)

### The WavetableScriptEvaluator

From `WavetableScriptEvaluator.cpp` (lines 39-61):

```cpp
struct LuaWTEvaluator::Details
{
    SurgeStorage *storage{nullptr};
    std::string script{};
    size_t resolution{2048};      // Samples per frame
    size_t frameCount{10};        // Number of frames

    bool isValid{false};
    std::vector<std::optional<frame_t>> frameCache;
    std::string wtName{"Scripted Wavetable"};

    lua_State *L{nullptr};        // Lua state

    void invalidate() { /* ... */ }
    void makeEmptyState(bool pushToGlobal) { /* ... */ }
    frame_t generateScriptAtFrame(size_t frame) { /* ... */ }
    void callInitFn() { /* ... */ }
    bool makeValid() { /* ... */ }
};
```

**Key components:**
- `lua_State *L`: Lua interpreter instance
- `frameCache`: Cached generated frames (lazy evaluation)
- `resolution`: Samples per frame (32, 64, 128, ..., 4096)
- `frameCount`: Number of frames to generate

### Script Structure: init() and generate()

Every wavetable script must define **two functions:**

1. **`init(wt)`**: Called once at script load
   - Receives wavetable metadata
   - Returns state table with persistent data
   - Optional: Can set wavetable name

2. **`generate(wt)`**: Called for each frame
   - Receives state from init() plus current frame number
   - Returns array of samples for this frame
   - Must return `resolution` samples

**Example** - Default Script (lines 566-606):

```lua
function init(wt)
    -- wt will have frame_count and sample_count defined
    wt.name = "Fourier Saw"
    wt.phase = math.linspace(0, 1, wt.sample_count)
    return wt
end

function generate(wt)
    -- wt will have frame_count, sample_count, frame, and any item from init defined
    local res = {}

    for i, x in ipairs(wt.phase) do
        local val = 0
        for n = 1, wt.frame do
            val = val + 2 * sin(2 * pi * n * x) / (pi * n)
        end
        res[i] = val * 0.8
    end
    return res
end
```

**Breakdown:**

1. **init():**
   - Sets `wt.name = "Fourier Saw"` (displayed in UI)
   - Creates phase array: [0, 1/N, 2/N, ..., (N-1)/N]
   - Returns modified `wt` table

2. **generate():**
   - `wt.frame`: Current frame (1-indexed)
   - `wt.frame_count`: Total frames
   - `wt.phase`: Phase array from init()
   - Loops through each sample position `x`
   - Calculates Fourier series sawtooth: `∑(2 sin(2πnx) / (πn))`
   - Number of harmonics increases with frame number
   - Returns array of samples

**Result:** Smooth morph from sine (frame 1) to sawtooth (frame 100)

### The State Table (wt)

The `wt` table passed to functions contains:

**In init():**
- `wt.frame_count`: Total number of frames
- `wt.sample_count`: Samples per frame (resolution)

**In generate():**
- `wt.frame`: Current frame number (1 to frame_count)
- `wt.frame_count`: Total frames
- `wt.sample_count`: Samples per frame
- Plus any custom fields added in init()

**Persistence:**

Data added to `wt` in `init()` is available in all `generate()` calls:

```lua
function init(wt)
    wt.my_custom_data = {1, 2, 3, 4, 5}
    return wt
end

function generate(wt)
    -- wt.my_custom_data is available here
    local val = wt.my_custom_data[wt.frame]
    -- ...
end
```

### Lua Helper Functions

Surge provides mathematical helpers:

**From Lua prelude:**
- `math.linspace(start, stop, count)`: Linear spacing
- `math.logspace(start, stop, count)`: Logarithmic spacing
- `surge.mod.normalize_peaks(array)`: Normalize to ±1.0

**Built-in math:**
- `sin()`, `cos()`, `tan()`: Trig functions (radians)
- `pi`: π constant
- `abs()`, `sqrt()`, `pow()`: Math functions
- `min()`, `max()`: Comparisons

### Real-World Example: Hard Sync Saw

From `/home/user/surge/resources/data/wavetables/Scripted/Additive/Hard Sync Saw.wtscript`:

```lua
function init(wt)
    --- Config ---
    wt.name = "Hard Sync Saw"
    wt.morph_curve = 0.5  -- Exponent: 1=linear, <1=ease-out, >1=ease-in
    wt.wave_cycles = 4    -- Number of oscillator cycles at last frame
    wt.num_harmonics = wt.sample_count / 2

    wt.phase = math.linspace(0, 1, wt.sample_count)
    return wt
end

function generate(wt)
    local mod = pow((wt.frame - 1) / (wt.frame_count - 1), wt.morph_curve)
    local cycle_length = 1 / wt.wave_cycles + (1 - 1 / wt.wave_cycles) * (1 - mod)
    local res = {}

    for i, x in ipairs(wt.phase) do
        local val = 0
        local local_phase = (x % cycle_length) / cycle_length

        for n = 1, wt.num_harmonics do
            local coeff = 2 / (math.pi * n)
            val = val + coeff * math.sin(2 * math.pi * n * local_phase)
        end
        res[i] = val
    end

    res = surge.mod.normalize_peaks(res)
    return res
end
```

**What does this create?**

- **Frame 1:** Single sawtooth cycle (cycle_length = 1)
- **Frame 100:** 4 sawtooth cycles (hard sync effect)
- **Morph:** Smooth transition with ease-out curve

**Hard sync simulation:**
- `local_phase = (x % cycle_length) / cycle_length`
- Wraps phase at `cycle_length` intervals
- Creates the characteristic "sync sweep" sound

### The .wtscript File Format

Wavetable scripts are stored as XML with base64-encoded Lua:

```xml
<?xml version="1.0" encoding="UTF-8" standalone="yes" ?>
<wtscript>
    <script lua="[base64-encoded Lua code]"
            frames="100"
            samples="7" />
</wtscript>
```

**Attributes:**
- `lua`: Base64-encoded Lua script
- `frames`: Number of frames (frameCount)
- `samples`: Resolution base (2^samples samples per frame)
  - `samples="5"`: 2^5 = 32 samples
  - `samples="7"`: 2^7 = 128 samples
  - `samples="9"`: 2^9 = 512 samples
  - `samples="11"`: 2^11 = 2048 samples

**Why base64?**
- Lua code can contain characters that break XML (quotes, angle brackets)
- Base64 ensures safe encoding in XML attributes
- Decoded at load time

### Script Evaluation Flow

From `WavetableScriptEvaluator.cpp` (lines 74-168):

1. **Parse and load script:**
   ```cpp
   lua_State *L = luaL_newstate();
   luaL_openlibs(L);
   Surge::LuaSupport::parseStringDefiningMultipleFunctions(
       L, script, {"init", "generate"}, emsg);
   ```

2. **Call init():**
   ```cpp
   lua_getglobal(L, "init");
   makeEmptyState(false);  // Create wt table
   lua_pcall(L, 1, 1, 0);  // Call init(wt)
   lua_setglobal(L, statetable);  // Save result
   ```

3. **For each frame, call generate():**
   ```cpp
   lua_getglobal(L, "generate");
   // Create wt table with frame info
   lua_pushinteger(L, frame + 1);
   lua_setfield(L, tidx, "frame");
   // Call generate(wt)
   lua_pcall(L, 1, 1, 0);
   // Extract samples from returned table
   ```

4. **Cache results:**
   ```cpp
   frameCache[frame] = values;
   ```

**Lazy evaluation:** Frames are only generated when needed (e.g., when morph parameter reaches them)

### Performance and Caching

**Frame caching:**
- Generated frames are cached in `frameCache`
- Re-morphing through same frames doesn't re-run Lua
- Cached until script is modified or parameters change

**When cache is invalidated:**
- Script text changes
- Resolution changes (`setResolution()`)
- Frame count changes (`setFrameCount()`)
- Explicit invalidation (`forceInvalidate()`)

**Memory usage:**
- 100 frames × 2048 samples × 4 bytes = 819,200 bytes (~800 KB)
- Cached in RAM for fast access
- Not a significant burden on modern systems

## Factory Wavetables

Surge XT ships with an extensive library of wavetables organized into categories.

**Location:** `/home/user/surge/resources/data/wavetables/`

### Category Structure

```
wavetables/
├── Basic/          - Fundamental waveforms and morphs
├── Generated/      - Algorithmically generated tables
├── Oneshot/        - Single-shot samples
├── Rhythmic/       - Rhythmic/percussive content
├── Sampled/        - Sampled instruments and sounds
├── Scripted/       - Lua-generated wavetables
│   └── Additive/   - Additive synthesis examples
├── Waldorf/        - Classic Waldorf wavetables
└── WT fileformat.txt
```

### Basic Category

**Contents:** Classic morphing wavetables

Examples:
- `Sine.wt`: Pure sine wave (why use wavetable for this? Compatibility)
- `Sine To Sawtooth.wt`: Smooth morph from sine to saw
- `Sine To Square.wt`: Sine to square morph
- `Tri-Saw.wt`: Triangle to sawtooth morph
- `Sine Octaves.wt`: Sine with added octaves

**Typical use:** Learning, basic sounds, building blocks

**Frame counts:** Usually 10-50 frames

**Resolution:** Mix of 128 and 2048 samples

### Generated Category

**Contents:** Mathematically generated wavetables

**Characteristics:**
- Precise harmonic control
- Geometric patterns
- FM-style spectra
- No sampling artifacts

**Use:** Clean, precise sounds for leads and pads

### Sampled Category

**Contents:** Real instruments and sounds sampled to wavetables

Examples:
- `cello.wt`: Sampled cello across different playing positions
- `piano.wt`: Piano samples

**File info** (from doc example):
```
$ python3 ./scripts/wt-tool/wt-tool.py --action=info --file=resources/data/wavetables/sampled/cello.wt
 WT :'resources/data/wavetables/sampled/cello.wt'
  contains  45 samples
  of length 128
  in format int16
```

**Characteristics:**
- Higher frame counts (capture different positions/dynamics)
- Often int16 format (save space)
- Realistic timbres

### Scripted/Additive Category

**Contents:** Lua-generated additive synthesis wavetables

Examples:
- `Sine to Saw.wtscript`: Additive synthesis Fourier saw
- `Hard Sync Saw.wtscript`: Hard sync simulation
- `Triangle to Square.wtscript`: Additive square morphs
- `Square PWM.wtscript`: Pulse width modulation
- `*HQ.wtscript`: High-quality versions (more samples)

**Characteristics:**
- Perfect mathematical precision
- Educational value (see the Lua code)
- Customizable (edit the scripts)
- Both standard and HQ versions

**Frame counts:** Usually 100 frames for smooth morphing

**Resolution:**
- Standard: `samples="5"` (32 samples)
- HQ: `samples="7"` to `samples="11"` (128-2048 samples)

### Waldorf Category

**Contents:** Classic wavetables from Waldorf synthesizers

**History:**
- Waldorf pioneered wavetable synthesis in the 1980s
- PPG Wave, Microwave, Blofeld
- Iconic sounds of the digital era

**Characteristics:**
- Vintage digital character
- Complex harmonic morphs
- Historical significance

**Use:** Classic digital synth sounds, PPG-style tones

## Creating Custom Wavetables

### Using the wt-tool Script

Surge includes a Python tool for wavetable manipulation:

**Location:** `/home/user/surge/scripts/wt-tool/wt-tool.py`

**Get info:**
```bash
python3 ./scripts/wt-tool/wt-tool.py --action=info --file=mywavetable.wt
```

**Explode to WAV files:**
```bash
python3 ./scripts/wt-tool/wt-tool.py --action=explode \
    --wav_dir=/tmp/myframes --file=mywavetable.wt
```
Creates numbered WAV files (wt_sample_000.wav, wt_sample_001.wav, ...)

**Create from WAV directory:**
```bash
python3 ./scripts/wt-tool/wt-tool.py --action=create \
    --file=newwavetable.wt --wav_dir=/tmp/myframes
```

**Requirements for WAV files:**
- Mono
- 16-bit integer
- 44.1 kHz sample rate (tool handles this)
- Power-of-2 length (128, 256, 512, 1024, 2048, or 4096 samples)
- All files in directory must be the same length

**Workflow:**
1. Create/export single-cycle waveforms as WAV
2. Name them alphabetically (frame_000.wav, frame_001.wav, ...)
3. Ensure power-of-2 length
4. Run create action
5. Load in Surge

### Using Lua Scripts

**Advantages:**
- Mathematical precision
- Easy to edit and experiment
- Version control friendly
- Educational

**Workflow:**
1. Start with default script or example
2. Edit init() for configuration
3. Edit generate() for waveform calculation
4. Save as .wtscript
5. Load in Surge's wavetable script editor

**Tips:**
- Use `wt.frame` to vary harmonics across frames
- Normalize output with `surge.mod.normalize_peaks()`
- Test with low resolution first (samples="5")
- Increase resolution for production (samples="9" or higher)

### Using External Tools

**WaveEdit** (multiplatform):
- Export 256-sample WAV files
- Use wt-tool to convert to .wt

**AudioTerm** (Windows only):
- Direct .wt export
- Extensive editing features

**Serum/Vital/etc:**
- Export wavetables as WAV
- Convert using wt-tool

## Advanced Techniques

### Modulation Strategies

**Morph + LFO:**
```
LFO → Morph parameter
Result: Cycling through frames rhythmically
Use: Evolving pads, animated textures
```

**Morph + Envelope:**
```
Envelope → Morph parameter
Result: Timbral change over note duration
Use: Plucks, percussive sounds, dynamic leads
```

**Morph + Velocity:**
```
Velocity → Morph parameter
Result: Brighter sound for harder hits
Use: Expressive playing, dynamic response
```

**Formant + LFO:**
```
LFO → Formant parameter
Result: Spectral animation
Use: Vowel-like modulation, vocal effects
```

### Unison + Wavetables

Combining unison with wavetables creates massive sounds:

```
Settings:
- Unison Voices: 16
- Unison Detune: 20 cents
- Stereo Spread: 100%

Result: Wide, thick, supersaw-style sound
```

**CPU consideration:** 16 voices × wavetable processing = heavy load

**Optimization:** Use lower frame counts if CPU is an issue

### Wavetable + Effects

**Wavetable → Distortion:**
- Emphasizes harmonic content
- Creates aggressive, modern sounds
- Try different wavetable frames through distortion

**Wavetable → Comb Filter:**
- Metallic, resonant tones
- Combine with formant parameter
- Flanging/phasing effects

**Wavetable → Reverb/Delay:**
- Pad sounds
- Ambient textures
- Long evolving soundscapes

## Performance Considerations

### CPU Usage Factors

1. **Resolution:** Higher resolution = more samples to read
   - 128 samples: Fast
   - 2048 samples: ~16x more data to process

2. **Unison:** Linear scaling
   - 1 voice: baseline
   - 16 voices: 16x CPU

3. **Deform mode:** Modern continuous slightly more expensive than legacy

4. **Modulation:** Minimal CPU impact

**Total CPU:**
```
CPU ≈ base_cost × (resolution/128) × unison_voices
```

### Memory Usage

**Per wavetable:**
```
Memory = n_frames × samples_per_frame × 4 bytes (float32)
       + mipmaps × 0.5 × base_size

Example (100 frames, 2048 samples):
= 100 × 2048 × 4 = 819,200 bytes
+ mipmaps ≈ 400,000 bytes
Total ≈ 1.2 MB
```

**With int16 compression:** Halve the memory

**Mipmaps:** Add ~50% overhead but essential for quality

### Optimization Tips

1. **Use appropriate resolution:**
   - Don't use 4096 samples if 1024 sounds identical
   - Test different resolutions

2. **Limit unison when possible:**
   - 4-8 voices often sufficient
   - 16 voices for special "supersaw" patches only

3. **Frame count:**
   - More frames = smoother morphing but larger files
   - 50-100 frames is usually plenty

4. **Int16 format:**
   - Use for final wavetables
   - Save disk space and memory
   - Minimal quality loss

## Conclusion

The Wavetable oscillator represents a perfect marriage of **flexibility** and **quality**:

- **Flexibility:** Infinite timbral possibilities through frame morphing, Lua scripting, and extensive parameters
- **Quality:** BLIT-based reproduction ensures alias-free output across the entire frequency spectrum
- **Power:** Formant, skew, and saturation parameters add dimension beyond simple playback
- **Creativity:** Lua scripting opens mathematical sound design possibilities

**Key takeaways:**

1. **Wavetables are collections** of waveforms, not single waves
2. **2D interpolation** (horizontal within frame, vertical between frames) creates smooth playback
3. **BLIT integration** provides the same quality as Classic oscillator
4. **Mipmaps** are essential for high-frequency playback without aliasing
5. **Lua scripting** enables mathematical wavetable generation
6. **Parameters** (formant, skew, saturation) multiply creative possibilities

The wavetable oscillator is one of Surge's most powerful tools for creating evolving, dynamic, and unique sounds. Combined with modulation, effects, and Surge's flexible architecture, it enables sounds ranging from classic digital synthesis to utterly alien soundscapes.

---

**Next: [Modern Oscillator](08-oscillators-modern.md)**
**See Also: [Classic Oscillator](06-oscillators-classic.md), [FM Synthesis](09-oscillators-fm.md)**

## Further Reading

**In Codebase:**
- `src/common/dsp/oscillators/WavetableOscillator.cpp` - Main implementation
- `src/common/dsp/WavetableScriptEvaluator.cpp` - Lua scripting system
- `src/common/dsp/Wavetable.h` - Data structures
- `doc/Wavetables.md` - User documentation
- `resources/data/wavetables/WT fileformat.txt` - File format specification
- `scripts/wt-tool/wt-tool.py` - Python wavetable tool

**Wavetable Synthesis:**
- "Digital Sound Generation" - Hal Chamberlin (1985) - Early wavetable theory
- PPG Wave documentation - Historical wavetable synthesis
- Waldorf Microwave manual - Classic wavetable synthesis

**Mathematical:**
- "The Audio Programming Book" - Boulanger & Lazzarini (2010)
- "Designing Sound" - Andy Farnell (2010) - Sound synthesis theory
