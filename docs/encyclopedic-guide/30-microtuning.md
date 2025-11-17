# Chapter 30: Microtuning System

## Beyond Equal Temperament

For most of Western music history, the question "What is a C?" had a complicated answer. Different tuning systems—meantone, Pythagorean, just intonation—produced different pitches for the same note name. The rise of **12-tone equal temperament (12-TET)** in the 18th and 19th centuries standardized pitch relationships, enabling instruments to play together in any key. But this standardization came at a cost: pure intervals were compromised for universal modulability.

Today, with digital synthesizers, we can escape the tyranny of equal temperament. Surge XT's microtuning system allows you to retune the entire instrument to any scale you can imagine—19 equal divisions of the octave, Pythagorean tuning, Indian ragas, Arabic maqamat, or your own experimental systems. This chapter explores how Surge implements one of the most sophisticated microtuning engines in any synthesizer.

## Why Microtuning Matters

### The Problem with 12-TET

In **12-tone equal temperament**, the octave (2:1 frequency ratio) is divided into 12 equal steps. Each semitone is the 12th root of 2, approximately 1.05946. This creates intervals that are mathematically consistent but acoustically imperfect:

| Interval | 12-TET Ratio | Just Intonation Ratio | Difference (cents) |
|----------|--------------|----------------------|-------------------|
| Perfect fifth | 1.498307 (700¢) | 3/2 = 1.500000 (701.96¢) | -1.96¢ |
| Major third | 1.259921 (400¢) | 5/4 = 1.250000 (386.31¢) | +13.69¢ |
| Minor third | 1.189207 (300¢) | 6/5 = 1.200000 (315.64¢) | -15.64¢ |

The major third in 12-TET is sharp by nearly 14 cents—audibly different from the pure 5:4 ratio. For solo instruments and electronic music, this compromise is unnecessary.

### Musical Applications

1. **Historical temperaments**: Recreate the sound of Baroque music in Werckmeister or meantone tuning
2. **Pure intervals**: Use just intonation for beatless harmonies
3. **Expanded tonality**: Explore 19-TET, 31-TET, or 53-TET for new harmonic possibilities
4. **World music**: Authentic tunings for Indian ragas, Arabic maqamat, Indonesian gamelan
5. **Experimental music**: Microtonal scales, stretched octaves, non-octave-repeating scales

## Theoretical Foundations

### Cents: The Universal Unit

Musical intervals are measured in **cents**, where:
- 1 octave = 1200 cents
- 1 semitone (12-TET) = 100 cents
- 1 cent = 1/100 of a semitone

The formula to convert a frequency ratio to cents:

```
cents = 1200 × log₂(f₂/f₁) = 1200 × ln(f₂/f₁) / ln(2)
```

Conversely, to convert cents to a frequency multiplier:

```
multiplier = 2^(cents/1200)
```

### Frequency Ratios: The Language of Just Intonation

**Just intonation** uses simple whole-number frequency ratios:

- **Octave**: 2/1 (1200¢)
- **Perfect fifth**: 3/2 (701.96¢)
- **Perfect fourth**: 4/3 (498.04¢)
- **Major third**: 5/4 (386.31¢)
- **Minor third**: 6/5 (315.64¢)

These ratios produce beatless intervals when played simultaneously. The overtone series naturally contains these ratios:

```
f₀ (1:1) → 2f₀ (2:1) → 3f₀ (3:1) → 4f₀ (4:1) → 5f₀ (5:1) → ...
```

### Equal Divisions of the Octave

An **equal temperament** divides the octave into N equal steps:

```
step_size_cents = 1200 / N
```

Common equal temperaments:
- **12-TET**: 100¢ steps (standard tuning)
- **19-TET**: 63.16¢ steps (excellent thirds, used by Guillaume Costeley)
- **31-TET**: 38.71¢ steps (very close to quarter-comma meantone)
- **53-TET**: 22.64¢ steps (approximates Pythagorean and just intervals)

## The Scala Format

Surge uses the **Scala** tuning file format, the de facto standard for microtonal music software. Scala files come in two types:

### .scl Files: Scale Definition

A `.scl` file defines the **scale intervals**—the pitch relationships between notes. Here's the structure:

```
! 12-intune.scl
!
Standard 12-tone equal temperament
 12
!
 100.0
 200.0
 300.0
 400.0
 500.0
 600.0
 700.0
 800.0
 900.0
 1000.0
 1100.0
 2/1
```

**Format breakdown:**

1. **Line 1**: Description (comment line starting with `!`)
2. **Line 2**: Optional blank or additional comment
3. **Line 3**: Description of the scale (displayed in menus)
4. **Line 4**: Number of notes in the scale (NOT including the 1/1 starting note)
5. **Line 5**: Optional comment
6. **Lines 6-16**: Each note of the scale, excluding the starting note (1/1 = 0¢)
7. **Last line**: The interval of equivalence (usually the octave = 2/1)

**Interval notation:**

Scala supports two formats for each interval:

1. **Cents notation**: `700.0` (700 cents = perfect fifth in 12-TET)
2. **Ratio notation**: `3/2` (perfect fifth in just intonation)

Example with ratios:

```
! pythagorean.scl
!
Pythagorean tuning (3-limit just intonation)
 12
!
 256/243     ! Minor second
 9/8         ! Major second
 32/27       ! Minor third
 81/64       ! Major third
 4/3         ! Perfect fourth
 729/512     ! Tritone
 3/2         ! Perfect fifth
 128/81      ! Minor sixth
 27/16       ! Major sixth
 16/9        ! Minor seventh
 243/128     ! Major seventh
 2/1         ! Octave
```

### .kbm Files: Keyboard Mapping

A `.kbm` file defines how the scale maps to MIDI keys. This allows you to:
- Set the reference pitch (e.g., A440)
- Map scales with ≠12 notes to a 128-key keyboard
- Skip keys (for scales with fewer than 12 notes)
- Transpose the scale to different root notes

Here's a standard mapping:

```
! mapping-a440-constant.kbm
!
! Size of map (pattern repeats every N keys):
12
! First MIDI note number to retune:
0
! Last MIDI note number to retune:
127
! Middle note where the first entry of the mapping is mapped to:
60
! Reference note for which frequency is given:
69
! Frequency to tune the above note to (floating point):
440.0
! Scale degree to consider as formal octave:
12
! Mapping
! (Scale degrees mapped to keys; x = unmapped)
0
1
2
3
4
5
6
7
8
9
10
11
```

**Format breakdown:**

1. **Map size**: How many keys before the pattern repeats (12 for standard keyboards)
2. **First/Last MIDI note**: Range to retune (usually 0-127)
3. **Middle note**: The MIDI key where scale degree 0 is mapped (usually 60 = middle C)
4. **Reference note**: Which MIDI key defines the reference frequency (usually 69 = A4)
5. **Reference frequency**: What frequency to tune the reference note to (usually 440.0 Hz)
6. **Octave degree**: Which scale degree represents the octave (usually equals map size)
7. **Mapping list**: Maps each keyboard position to a scale degree (or `x` for unmapped)

### Non-Standard Mappings

Map a 7-note scale (white keys only) to the keyboard:

```
! mapping-whitekeys-c261.kbm
!
! Size of map:
12
! First MIDI note:
0
! Last MIDI note:
127
! Middle note:
60
! Reference note:
60
! Reference frequency:
261.625565280
! Octave degree:
7
! Mapping (x = black keys unmapped):
0
x
1
x
2
3
x
4
x
5
x
6
```

This maps scale degrees 0-6 to the white keys, leaving black keys unmapped.

## Tuning Library Integration

Surge integrates a **tuning library** that handles scale parsing, frequency calculation, and keyboard mapping. While the library is located in `/home/user/surge/libs/tuning-library/` (a git submodule), the core interface is accessed via the `Tunings.h` header.

### Core Structures

The tuning system uses three primary structures:

```cpp
// From: Tunings.h (tuning-library)

namespace Tunings
{
    // Represents a single interval in a scale
    struct Tone
    {
        enum Type { kToneCents, kToneRatio } type;

        float cents;         // Value in cents
        float floatValue;    // Frequency multiplier (2^(cents/1200))
        int ratio_n, ratio_d; // Numerator and denominator for ratios
        std::string stringValue; // Original text representation
    };

    // A complete scale definition (.scl file)
    struct Scale
    {
        std::string name;        // Scale description
        std::string description; // Long description
        std::string rawText;     // Original file contents
        int count;               // Number of notes (excluding 1/1)
        std::vector<Tone> tones; // The scale intervals
    };

    // Keyboard mapping (.kbm file)
    struct KeyboardMapping
    {
        int count;              // Size of mapping pattern
        int firstMidi;          // First MIDI note to retune (usually 0)
        int lastMidi;           // Last MIDI note to retune (usually 127)
        int middleNote;         // MIDI key mapped to scale degree 0
        int tuningConstantNote; // Reference MIDI note
        float tuningFrequency;  // Reference frequency in Hz
        int octaveDegrees;      // Scale degree representing octave

        std::vector<int> keys;  // Mapping (-1 = unmapped)
        std::string name;       // File name
        std::string rawText;    // Original file contents
    };
}
```

### Reading Scala Files

The library provides functions to parse .scl and .kbm files:

```cpp
// From: Tunings.h

namespace Tunings
{
    // Parse a .scl file from disk
    Scale readSCLFile(const std::string &filename);

    // Parse a .scl file from string data
    Scale parseSCLData(const std::string &data);

    // Parse a .kbm file from disk
    KeyboardMapping readKBMFile(const std::string &filename);

    // Parse a .kbm file from string data
    KeyboardMapping parseKBMData(const std::string &data);
}
```

### The Tuning Class

The `Tunings::Tuning` class combines a scale and keyboard mapping into a complete tuning:

```cpp
// From: Tunings.h

namespace Tunings
{
    class Tuning
    {
    public:
        Tuning();
        Tuning(const Scale &scale);
        Tuning(const Scale &scale, const KeyboardMapping &mapping);

        // Get frequency for a MIDI note
        double frequencyForMidiNote(int midiNote) const;

        // Get frequency for a MIDI note with pitch bend
        double frequencyForMidiNoteScaledByMidi0(int midiNote) const;

        // Get the logarithmic frequency (pitch)
        double logScaledFrequencyForMidiNote(int midiNote) const;

        // Scale and mapping accessors
        const Scale &scale() const { return currentScale; }
        const KeyboardMapping &keyboardMapping() const { return currentMapping; }

        // Check if using standard tuning
        bool isStandardTuning() const;

    private:
        Scale currentScale;
        KeyboardMapping currentMapping;
        // ... internal frequency tables
    };
}
```

The `Tuning` class pre-computes a frequency table for all 128 MIDI notes, enabling efficient lookup during synthesis.

## SurgeStorage Tuning Integration

Surge's `SurgeStorage` class manages the active tuning state and provides methods for retuning:

```cpp
// From: src/common/SurgeStorage.h

class SurgeStorage
{
public:
    // Current tuning state
    Tunings::Tuning currentTuning;
    Tunings::Scale currentScale;
    Tunings::KeyboardMapping currentMapping;

    // Tuning state flags
    bool isStandardTuning = true;
    bool isStandardScale = true;
    bool isStandardMapping = true;

    // Retune to a new scale (keeps existing mapping)
    bool retuneToScale(const Tunings::Scale &s)
    {
        currentScale = s;
        currentTuning = Tunings::Tuning(currentScale, currentMapping);
        isStandardTuning = false;
        isStandardScale = false;
        return true;
    }

    // Apply a keyboard mapping (keeps existing scale)
    bool remapToKeyboard(const Tunings::KeyboardMapping &k)
    {
        currentMapping = k;
        currentTuning = Tunings::Tuning(currentScale, currentMapping);
        isStandardMapping = false;
        isStandardTuning = false;
        return true;
    }

    // Reset to standard tuning
    void resetToStandardTuning()
    {
        currentScale = Tunings::Scale();      // 12-TET
        currentMapping = Tunings::KeyboardMapping(); // Standard keyboard
        currentTuning = Tunings::Tuning();
        isStandardTuning = true;
        isStandardScale = true;
        isStandardMapping = true;
    }

    // Reset to standard scale (keep mapping)
    void resetToStandardScale()
    {
        currentScale = Tunings::Scale();
        currentTuning = Tunings::Tuning(currentScale, currentMapping);
        isStandardScale = true;
        isStandardTuning = isStandardMapping;
    }

    // Reset to concert C mapping (keep scale)
    void remapToConcertCKeyboard()
    {
        currentMapping = Tunings::KeyboardMapping();
        currentTuning = Tunings::Tuning(currentScale, currentMapping);
        isStandardMapping = true;
        isStandardTuning = isStandardScale;
    }

    // Get frequency for a MIDI note
    float note_to_pitch(int note) const
    {
        if (isStandardTuning)
            return note_to_pitch_ignoring_tuning(note);
        return currentTuning.frequencyForMidiNote(note);
    }
};
```

### Tuning Application Modes

Surge offers two modes for applying tuning:

```cpp
// From: src/common/SurgeStorage.h

enum TuningApplicationMode
{
    RETUNE_ALL = 0,        // Retune oscillators AND wavetables/tables
    RETUNE_MIDI_ONLY = 1   // Only retune keyboard, not internal tables
} tuningApplicationMode = RETUNE_MIDI_ONLY;
```

**RETUNE_MIDI_ONLY** (default):
- Retuning affects MIDI note-to-pitch mapping only
- Wavetables, internal oscillator tables remain in 12-TET
- Best for most musical applications
- Preserves the character of factory wavetables

**RETUNE_ALL**:
- Retuning affects everything: MIDI mapping AND internal tables
- Wavetables are resampled to match the tuning
- More consistent tuning behavior
- May change the timbre of wavetables

This is set via the **Menu > Tuning > Apply Tuning After Modulation** toggle.

## MTS-ESP Integration

**MTS-ESP** (MIDI Tuning Standard - Extended Specification Protocol) by ODDSound allows dynamic, real-time tuning changes across multiple plugins. Instead of loading static .scl files, MTS-ESP enables a "master" plugin to control the tuning of all "client" plugins in a DAW session.

### How MTS-ESP Works

1. **Master plugin**: A dedicated tuning plugin (like ODDSound's MTS-ESP Master) sends tuning data
2. **Client plugins**: Synthesizers (like Surge XT) receive and apply the tuning
3. **Dynamic updates**: Tuning can change in real-time during playback
4. **Per-note tuning**: Each MIDI note can have a unique frequency (not just scale-based)

### Integration in Surge

```cpp
// From: src/common/SurgeStorage.h

class SurgeStorage
{
public:
    // MTS-ESP client handle
    void *oddsound_mts_client = nullptr;

    // Is MTS-ESP active and providing tuning?
    bool oddsound_mts_active_as_client = false;
};
```

When MTS-ESP is active, Surge queries the tuning for each note:

```cpp
// From: src/surge-xt/gui/overlays/TuningOverlays.cpp (lines 194-201)

double fr = 0;
if (storage && storage->oddsound_mts_client && storage->oddsound_mts_active_as_client)
{
    // Query MTS-ESP for frequency
    fr = MTS_NoteToFrequency(storage->oddsound_mts_client, rowNumber, 0);
}
else
{
    // Use internal tuning
    fr = tuning.frequencyForMidiNote(mn);
}
```

The `libMTSClient.h` header provides the interface:

```cpp
// From: libs/oddsound-mts/

// Get frequency for a MIDI note from MTS-ESP master
double MTS_NoteToFrequency(const void* client, int midinote, int midichannel);

// Check if MTS-ESP is providing tuning
bool MTS_HasMaster(const void* client);

// Query scale name from master
const char* MTS_GetScaleName(const void* client);
```

**Advantages of MTS-ESP:**

1. **Real-time control**: Change tuning during playback without reloading patches
2. **Multi-plugin sync**: All instruments in the session share the same tuning
3. **Dynamic scales**: Scales can morph, modulate, or sequence over time
4. **Per-note control**: Individual notes can be retuned independently

## Tuning in Practice

### Loading Tuning Files via Menu

Surge provides a comprehensive tuning menu:

**Menu > Tuning**:
- **Set to Standard Tuning**: Reset to 12-TET with A440 mapping
- **Set to Standard Mapping (Concert C)**: Reset keyboard mapping only
- **Set to Standard Scale (12-TET)**: Reset scale only
- **Load .scl Tuning...**: Load a scale file
- **Load .kbm Keyboard Mapping...**: Load a keyboard mapping
- **Factory Tuning Library...**: Browse included tunings
- **Show Tuning Editor**: Open the tuning overlay
- **Apply Tuning at MIDI Input**: RETUNE_MIDI_ONLY mode
- **Apply Tuning After Modulation**: RETUNE_ALL mode

### The Tuning Editor Overlay

The tuning editor (accessed via **Menu > Tuning > Show Tuning Editor**) provides visual feedback and editing:

**Layout (from src/surge-xt/gui/overlays/TuningOverlays.h):**

1. **Frequency Keyboard** (TuningTableListBoxModel):
   - Visual keyboard showing all 128 MIDI notes
   - Displays frequency in Hz for each note
   - Color-coded (white keys, black keys, pressed keys)
   - Click to audition notes

2. **Control Area**:
   - Load/save .scl and .kbm files
   - Adjust scale intervals
   - Rescale the entire scale

3. **Visualization Modes**:
   - **Scala**: Text editor for .scl/.kbm files
   - **Polar**: Radial graph showing scale intervals
   - **Interval**: Interval matrix showing all interval relationships
   - **To Equal**: Deviation from equal temperament
   - **Rotation**: Circular representation
   - **True Keys**: Keyboard with actual scale mapping

### Frequency Table Display

The frequency table shows exact Hz values for each MIDI note:

```cpp
// From: src/surge-xt/gui/overlays/TuningOverlays.cpp (lines 189-244)

auto mn = rowNumber;  // MIDI note number
double fr = tuning.frequencyForMidiNote(mn);

// Display format: "C4 (60) - 261.63 Hz"
std::string notenum = std::to_string(mn);
std::string notename = (noteInScale % 12 == 0)
    ? fmt::format("C{:d}", rowNumber / 12 - mcoff)
    : "";
std::string display = fmt::format("{:.2f}", fr);
```

Example output for 12-TET:
```
C-1  (0)   - 8.18 Hz
C0   (12)  - 16.35 Hz
C1   (24)  - 32.70 Hz
C2   (36)  - 65.41 Hz
C3   (48)  - 130.81 Hz
C4   (60)  - 261.63 Hz    (Middle C)
A4   (69)  - 440.00 Hz
C5   (72)  - 523.25 Hz
C6   (84)  - 1046.50 Hz
C7   (96)  - 2093.00 Hz
```

### Per-Patch vs. Global Tuning

Tuning can be:

1. **Global** (default): Applies to all patches
2. **Per-patch**: Saved with the patch (requires patch format ≥16)

```cpp
// From: src/common/SurgePatch.cpp

// When loading a patch:
if (patch_has_tuning_data)
{
    storage->setTuningApplicationMode(SurgeStorage::RETUNE_ALL);
    // Load patch tuning
}
else
{
    // Use global tuning
}
```

## Common Tuning Systems

### 12-TET (Standard Tuning)

The default tuning: 12 equal divisions of the octave.

```
! 12-tet.scl
12-tone equal temperament
12
!
100.0
200.0
300.0
400.0
500.0
600.0
700.0
800.0
900.0
1000.0
1100.0
2/1
```

### 19-TET

19 equal divisions of the octave. Excellent for meantone-like music with better thirds than 12-TET.

```
! 19-tet.scl
19-tone equal temperament
19
!
63.15789
126.31579
189.47368
252.63158
315.78947
378.94737
442.10526
505.26316
568.42105
631.57895
694.73684
757.89474
821.05263
884.21053
947.36842
1010.52632
1073.68421
1136.84211
2/1
```

**Characteristics:**
- Step size: 63.16 cents
- Third: 5 steps = 315.79¢ (very close to 5/4 = 316.31¢)
- Fifth: 11 steps = 694.74¢ (close to 3/2 = 701.96¢)
- Used by Guillaume Costeley in the 16th century

### 31-TET

31 equal divisions of the octave. Approximates quarter-comma meantone temperament.

```
! 31-tet.scl
31-tone equal temperament
31
!
38.70968
77.41935
116.12903
154.83871
193.54839
232.25806
270.96774
309.67742
348.38710
387.09677
425.80645
464.51613
503.22581
541.93548
580.64516
619.35484
658.06452
696.77419
735.48387
774.19355
812.90323
851.61290
890.32258
929.03226
967.74194
1006.45161
1045.16129
1083.87097
1122.58065
1161.29032
2/1
```

**Characteristics:**
- Step size: 38.71 cents
- Major third: 10 steps = 387.10¢ (very close to 5/4 = 386.31¢)
- Fifth: 18 steps = 696.77¢ (slightly flat)
- Supports 31-tone chromaticism

### Pythagorean Tuning

Based on pure 3:2 fifths. Creates beatless fifths but wolf intervals.

```
! pythagorean.scl
Pythagorean tuning
12
!
256/243
9/8
32/27
81/64
4/3
729/512
3/2
128/81
27/16
16/9
243/128
2/1
```

**Frequency table (C4 = 261.63 Hz):**
```
C  - 261.63 Hz  (1/1)
C# - 275.62 Hz  (256/243 = 90.22¢)
D  - 294.33 Hz  (9/8 = 203.91¢)
Eb - 310.08 Hz  (32/27 = 294.13¢)
E  - 330.63 Hz  (81/64 = 407.82¢)
F  - 348.83 Hz  (4/3 = 498.04¢)
F# - 368.51 Hz  (729/512 = 611.73¢)
G  - 392.44 Hz  (3/2 = 701.96¢)
Ab - 413.42 Hz  (128/81 = 792.18¢)
A  - 441.49 Hz  (27/16 = 905.87¢)
Bb - 465.11 Hz  (16/9 = 996.09¢)
B  - 495.00 Hz  (243/128 = 1109.78¢)
C  - 523.25 Hz  (2/1 = 1200.00¢)
```

**Characteristics:**
- Pure fifths (3:2 ratio, 701.96¢)
- Sharp major thirds (81/64 = 407.82¢ vs. 386.31¢)
- Bright, brilliant sound
- Used in medieval and Renaissance music

### 5-Limit Just Intonation

Uses ratios from the first 5 primes (2, 3, 5). Creates pure triads.

```
! just_5limit.scl
5-limit just intonation major scale
12
!
16/15
9/8
6/5
5/4
4/3
45/32
3/2
8/5
5/3
9/5
15/8
2/1
```

**In the key of C:**
```
C  - 261.63 Hz  (1/1)      - Root
C# - 279.07 Hz  (16/15)    - Minor second
D  - 294.33 Hz  (9/8)      - Major second
Eb - 313.96 Hz  (6/5)      - Minor third
E  - 327.03 Hz  (5/4)      - Major third (pure!)
F  - 348.83 Hz  (4/3)      - Perfect fourth
F# - 367.92 Hz  (45/32)    - Augmented fourth
G  - 392.44 Hz  (3/2)      - Perfect fifth (pure!)
Ab - 418.60 Hz  (8/5)      - Minor sixth
A  - 436.05 Hz  (5/3)      - Major sixth
Bb - 470.93 Hz  (9/5)      - Minor seventh
B  - 490.55 Hz  (15/8)     - Major seventh
C  - 523.25 Hz  (2/1)      - Octave
```

**Characteristics:**
- C major triad (C-E-G) is perfectly in tune: 4:5:6 ratio
- Beatless harmonies
- Cannot modulate to other keys (different pitches needed)
- Ideal for drone-based music

### Quarter-Comma Meantone

Historical temperament optimizing major thirds at the expense of fifths.

```
! quarter_comma_meantone.scl
1/4-comma meantone
12
!
76.04900
193.15686
310.26471
5/4
503.42157
579.47057
696.57843
25/16
889.73529
1006.84314
1082.89214
2/1
```

**Characteristics:**
- Pure major thirds (5/4)
- Flat fifths (696.58¢)
- Popular in Renaissance and Baroque music
- Wolf fifth between G# and Eb

### La Monte Young's "Well-Tuned Piano"

Experimental just intonation system used by composer La Monte Young.

```
! young_well_tuned.scl
La Monte Young - The Well-Tuned Piano
12
!
567/512
9/8
147/128
21/16
1323/1024
189/128
3/2
49/32
7/4
441/256
63/32
2/1
```

### Arabic Maqam (Rast)

24-tone equal temperament approximation of Arabic Rast maqam.

```
! arabic_24tet.scl
24-tone equal temperament (Arabic quarter-tones)
24
!
50.0
100.0
150.0
200.0
250.0
300.0
350.0
400.0
450.0
500.0
550.0
600.0
650.0
700.0
750.0
800.0
850.0
900.0
950.0
1000.0
1050.0
1100.0
1150.0
2/1
```

### Bohlen-Pierce Scale

Non-octave scale based on 3:1 (tritave) instead of 2:1 (octave).

```
! bohlen_pierce.scl
Bohlen-Pierce scale (13 steps to tritave)
13
!
146.304
292.608
438.913
585.217
731.522
877.826
1024.130
1170.435
1316.739
1463.043
1609.348
1755.652
3/1
```

**Characteristics:**
- 13 equal divisions of the tritave (3:1)
- Step size: 146.30 cents
- No octave equivalence!
- Alien, otherworldly sound

## Creating Custom Tunings

### Simple 7-Note Just Scale

Let's create a just intonation major scale:

```
! custom_just_major.scl
!
Custom just intonation major scale
 7
!
9/8         ! Major second (203.91¢)
5/4         ! Major third (386.31¢)
4/3         ! Perfect fourth (498.04¢)
3/2         ! Perfect fifth (701.96¢)
5/3         ! Major sixth (884.36¢)
15/8        ! Major seventh (1088.27¢)
2/1         ! Octave
```

Map it to white keys only:

```
! just_major_whitekeys.kbm
!
12
0
127
60
60
261.625565280
7
0
x
1
x
2
3
x
4
x
5
x
6
```

### Stretched Octave Tuning

Slightly stretch the octave for a brighter sound:

```
! stretched_12tet.scl
!
12-TET with stretched octave (1201.5 cents)
 12
!
100.125
200.250
300.375
400.500
500.625
600.750
700.875
801.000
901.125
1001.250
1101.375
1201.500
```

### Gamelan Pelog Scale

Indonesian 7-note scale with unequal intervals:

```
! pelog.scl
!
Gamelan Pelog (Javanese)
 7
!
136.0
383.0
515.0
678.0
813.0
951.0
2/1
```

### Harmonic Series Segment

Use the overtone series directly:

```
! harmonics_8_16.scl
!
Harmonics 8-16
 8
!
9/8
10/8
11/8
12/8
13/8
14/8
15/8
16/8
```

This creates a scale from harmonics 8-16 of the overtone series.

### Converting Cents to Ratios

To convert a cents value to the closest simple ratio, use the formula:

```python
def cents_to_ratio(cents, max_denominator=128):
    freq_ratio = 2 ** (cents / 1200.0)
    # Use continued fractions or brute force search
    # to find closest ratio a/b where b <= max_denominator
    # ...
```

## Frequency Tables and Examples

### 12-TET Frequency Table

Complete frequency table for 12-TET with A4 = 440 Hz:

| Note | MIDI | Frequency (Hz) |
|------|------|---------------|
| C-1  | 0    | 8.176         |
| C0   | 12   | 16.352        |
| C1   | 24   | 32.703        |
| C2   | 36   | 65.406        |
| C3   | 48   | 130.813       |
| **C4** | **60** | **261.626** |
| A4   | 69   | 440.000       |
| C5   | 72   | 523.251       |
| C6   | 84   | 1046.502      |
| C7   | 96   | 2093.005      |
| C8   | 108  | 4186.009      |

### Comparison: 12-TET vs. Just Intonation

Major scale comparison in Hz (root = C4 = 261.63 Hz):

| Degree | 12-TET Hz | Just Hz | Difference (cents) |
|--------|-----------|---------|-------------------|
| C (1)  | 261.63    | 261.63  | 0.00              |
| D (2)  | 293.66    | 294.33  | +3.91             |
| E (3)  | 329.63    | 327.03  | -13.69            |
| F (4)  | 349.23    | 348.83  | -1.96             |
| G (5)  | 392.00    | 392.44  | +1.96             |
| A (6)  | 440.00    | 436.05  | -15.64            |
| B (7)  | 493.88    | 490.55  | -11.73            |
| C (8)  | 523.25    | 523.25  | 0.00              |

Notice the major third (E) is 13.69 cents sharp in 12-TET, and the major sixth (A) is 15.64 cents flat.

## Advanced Topics

### Voice Architecture Integration

When a voice is triggered, Surge applies tuning at note-on:

```cpp
// From: src/common/dsp/SurgeVoice.cpp (lines 75-116)

if (storage->oddsound_mts_active_as_client &&
    storage->oddsound_mts_client &&
    storage->tuningApplicationMode == SurgeStorage::RETUNE_MIDI_ONLY)
{
    // Use MTS-ESP tuning
    state.keyRetuning =
        MTS_RetuningInSemitones(storage->oddsound_mts_client,
                               state.key, state.channel);
}
else if (storage->tuningApplicationMode == SurgeStorage::RETUNE_ALL)
{
    // Apply tuning to everything
    state.pitch = storage->note_to_pitch(state.key);
}
```

### Oscillator Interaction

Different oscillator types respond differently to tuning:

**Classic oscillators**: Tuning affects pitch directly via `oscstate` frequency
**Wavetable oscillators**:
- RETUNE_MIDI_ONLY: Wavetable remains 12-TET, pitch changes
- RETUNE_ALL: Wavetable is resampled to match tuning

**FM oscillators**: Carrier and modulator both follow tuning, preserving ratios

### Unit Testing

Surge includes comprehensive tuning tests:

```cpp
// From: src/surge-testrunner/UnitTestsTUN.cpp

TEST_CASE("Retune Surge XT to Scala Files", "[tun]")
{
    auto surge = Surge::Headless::createSurge(44100);
    surge->storage.tuningApplicationMode = SurgeStorage::RETUNE_ALL;

    SECTION("Zeus 22")
    {
        Tunings::Scale s = Tunings::readSCLFile("resources/test-data/scl/zeus22.scl");
        surge->storage.retuneToScale(s);

        REQUIRE(n2f(60) == surge->storage.scaleConstantPitch());
        REQUIRE(n2f(60 + s.count) == surge->storage.scaleConstantPitch() * 2);
    }
}
```

## Factory Tuning Library

Surge ships with 191+ tuning files in `/home/user/surge/resources/data/tuning_library/`:

**Categories:**
- **Equal Linear Temperaments 17-71/**: EDOs from 17 to 71
- **KBM Concert Pitch/**: Reference pitch mappings (A440, A432, etc.)
- **SCL/**: Over 5000+ historical and experimental scales

Access via **Menu > Tuning > Factory Tuning Library**.

## Practical Tips

### Choosing a Tuning

1. **For beatless chords**: Use 5-limit or 7-limit just intonation
2. **For modulation**: Use 19-TET, 31-TET, or 53-TET
3. **For historical authenticity**: Use period temperaments (meantone, Werckmeister)
4. **For experimentation**: Try Bohlen-Pierce, stretched tunings, or harmonic series

### Workflow Recommendations

1. **Start simple**: Try 19-TET or quarter-comma meantone before complex systems
2. **Use white keys**: Map 7-note scales to white keys for easier playing
3. **Reference pitch matters**: Adjust .kbm reference frequency for different concert pitches
4. **Save with patches**: Enable per-patch tuning for compositions in specific tunings
5. **MTS-ESP for exploration**: Use MTS-ESP Master for real-time tuning experiments

### Common Pitfalls

1. **Wolf fifths**: Many historical tunings have unusable intervals in certain keys
2. **Wavetable artifacts**: RETUNE_ALL mode can change wavetable timbre unexpectedly
3. **Keyboard mapping confusion**: Unmapped keys (x) produce no sound
4. **Octave stretching**: Non-2/1 octaves may sound "wrong" without acclimatization

## Conclusion

Surge XT's microtuning system opens the door to thousands of years of tuning history and infinite experimental possibilities. From the pure intervals of ancient Greek modes to the stretched timbres of Indonesian gamelan, from the wolf fifths of Pythagorean tuning to the alien landscapes of Bohlen-Pierce—all are available with a simple .scl file.

The integration of Scala format, comprehensive keyboard mapping, MTS-ESP support, and visual editing tools makes Surge one of the most capable microtonal synthesizers available. Whether you're recreating historical temperaments, exploring world music traditions, or inventing entirely new harmonic systems, Surge provides the tools to hear your vision.

**Key Takeaways:**

1. Tuning is defined by two files: `.scl` (scale) and `.kbm` (keyboard mapping)
2. The tuning library handles parsing and frequency calculation
3. MTS-ESP enables dynamic, multi-plugin tuning
4. RETUNE_MIDI_ONLY vs. RETUNE_ALL affects wavetable behavior
5. The tuning editor provides visual feedback and editing
6. 191+ factory tunings cover historical and experimental systems
7. Custom tunings are created with simple text files

In the next chapter, we'll explore **MIDI and MPE**, examining how Surge handles polyphonic expression, controller routing, and the future of expressive synthesis.

---

**Further Reading:**

- Manuel Op de Coul: *Scala: The Scala Scale Archive* (http://www.huygens-fokker.org/scala/)
- William A. Sethares: *Tuning, Timbre, Spectrum, Scale*
- Kyle Gann: *The Arithmetic of Listening*
- Easley Blackwood: *The Structure of Recognizable Diatonic Tunings*
- ODDSound: *MTS-ESP Documentation* (https://oddsound.com/)

**File Reference:**
- `/home/user/surge/src/common/SurgeStorage.h` - Tuning state management
- `/home/user/surge/src/surge-xt/gui/overlays/TuningOverlays.cpp` - Tuning editor (112KB)
- `/home/user/surge/libs/tuning-library/` - Scala parser library
- `/home/user/surge/libs/oddsound-mts/` - MTS-ESP integration
- `/home/user/surge/resources/data/tuning_library/` - Factory tunings (191 files)
