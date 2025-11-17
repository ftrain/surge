# Appendix B: Synthesis Glossary

## A Comprehensive Reference for Digital Audio Synthesis

This glossary provides clear, concise definitions of synthesis and DSP terms used throughout the Surge XT Encyclopedic Guide. Each entry explains the term's meaning, its application in synthesis, and references relevant chapters for deeper exploration.

---

## A

### ADSR
**Attack, Decay, Sustain, Release** - The four stages of a standard envelope generator. Attack is the time to reach peak amplitude, Decay is the time to fall to Sustain level, Sustain is the held level while a note is on, and Release is the time to fade to silence after note-off. See **[Chapter 19: Envelope Generators](19-envelopes.md)**.

### Aftertouch
MIDI **channel pressure** or **polyphonic pressure** sent when pressing down on keys after initial attack. Used as a modulation source for vibrato, filter brightness, or other expressive parameters. See **[Chapter 31: MIDI and MPE](31-midi-mpe.md)**.

### Algorithm
In FM synthesis, the **operator topology** - the arrangement and routing of FM operators. Common algorithms include stacked (serial FM), parallel (additive), and feedback configurations. See **[Chapter 8: FM Synthesis](08-oscillators-fm.md)**.

### Aliasing
**Frequency folding** artifacts that occur when a signal contains frequencies above the Nyquist frequency (half the sample rate). These high frequencies "reflect" back into the audible range as spurious, inharmonic tones. Band-limited synthesis techniques eliminate aliasing. See **[Chapter 5: Oscillator Theory](05-oscillators-overview.md)**.

Mathematical representation:
```
If f > fs/2, then f_alias = fs - f
```
Where `fs` is sample rate, `f` is actual frequency, and `f_alias` is the perceived frequency.

### Amplitude
The **magnitude** or **level** of a signal, typically ranging from -1.0 to +1.0 in floating-point audio. In synthesis, amplitude is shaped by envelopes and modulation to create volume contours.

### Analog Modeling
Digital synthesis techniques that **emulate analog circuits**, including component tolerances, drift, saturation, and non-linearities. Surge's "analog mode" for envelopes and oscillator drift are examples. See **[Chapter 6: Classic Oscillators](06-oscillators-classic.md)**.

### Attack
The first stage of an ADSR envelope - the time from note-on to reaching peak level. Expressed in seconds or milliseconds, often with curve shaping options (linear, exponential, etc.).

### Audio Rate
Processing that occurs at the **sample rate** (e.g., 44.1kHz, 48kHz), as opposed to control rate. Audio-rate modulation allows one oscillator to modulate another's frequency (FM) or amplitude (ring modulation).

---

## B

### Band-Limited
Waveforms that contain **no frequencies above the Nyquist limit**, preventing aliasing. Band-limited synthesis uses techniques like BLIT, polynomial approximation, or oversampling to ensure clean digital waveforms. See **[Chapter 5: Oscillator Theory](05-oscillators-overview.md)**.

### Bandwidth
In filters, the **range of frequencies** that pass through. In parametric EQ, bandwidth is expressed as **Q** (quality factor). Higher Q = narrower bandwidth.

Formula for bandwidth in octaves:
```
BW (octaves) = log2(f_high / f_low)
Q = f_center / (f_high - f_low)
```

### Bipolar
A signal or modulation source that ranges from **-1 to +1** (or negative to positive). LFOs are typically bipolar. Contrast with **unipolar** (0 to 1). Surge allows converting between these modes.

### Biquad
A **second-order IIR filter** (Infinite Impulse Response) characterized by two poles and up to two zeros. The fundamental building block for digital filters. Name derives from "bi-quadratic" transfer function.

Transfer function:
```
H(z) = (b0 + b1*z^-1 + b2*z^-2) / (a0 + a1*z^-1 + a2*z^-2)
```
See **[Chapter 11: Filter Implementation](11-filter-implementation.md)**.

### BLIT
**Band-Limited Impulse Train** - A synthesis technique that generates band-limited impulse trains which, when integrated, produce alias-free waveforms. Surge's classic oscillators use BLIT techniques. See **[Chapter 5: Oscillator Theory](05-oscillators-overview.md)** and **[Chapter 6: Classic Oscillators](06-oscillators-classic.md)**.

### Block Size
The number of samples processed in one batch, also called **buffer size**. Typical values: 64, 128, 256, 512 samples. Smaller blocks reduce latency but increase CPU overhead. Surge processes audio in blocks for efficiency. See **[Chapter 1: Architecture Overview](01-architecture-overview.md)**.

---

## C

### Carrier
In modulation, the signal being **modulated**. In FM synthesis, the carrier is the oscillator whose frequency is modulated. In ring modulation, both signals are carriers. Contrast with **modulator**.

### Cents
A logarithmic unit of musical pitch. **100 cents = 1 semitone**, 1200 cents = 1 octave. Used for fine-tuning and detune controls.

Frequency ratio from cents:
```
f_ratio = 2^(cents/1200)
```

### Comb Filter
A filter with a **frequency response resembling a comb** - regularly spaced peaks and notches. Created by mixing a signal with a delayed copy. Used in flangers, phasers, and physical modeling. See **[Chapter 13: Time-Based Effects](13-effects-time-based.md)**.

### Control Rate
Processing at a **lower rate than audio rate**, typically block-rate (e.g., every 32 samples). Envelopes, LFOs, and modulation typically operate at control rate for efficiency.

### Cutoff Frequency
The **frequency point** where a filter begins to attenuate signals. In a low-pass filter, frequencies above cutoff are reduced. In high-pass, frequencies below. Typically expressed in Hz or MIDI note number. See **[Chapter 10: Filter Theory](10-filter-theory.md)**.

At cutoff frequency (Fc), amplitude is typically -3dB (0.707x) of passband level.

---

## D

### DAC
**Digital-to-Analog Converter** - Hardware that converts digital samples to continuous voltage. In Surge's BLIT oscillators, DAC reconstruction is **modeled** to ensure band-limited output. See **[Chapter 5: Oscillator Theory](05-oscillators-overview.md)**.

### dB (Decibel)
Logarithmic unit for expressing **amplitude ratios**.

```
dB = 20 * log10(amplitude_ratio)
dB = 10 * log10(power_ratio)

Common values:
+6 dB = 2x amplitude
0 dB = unity gain (1x)
-6 dB = 0.5x amplitude
-12 dB = 0.25x amplitude
-∞ dB = silence (0)
```

### Decay
The second stage of an ADSR envelope - the time to fall from peak level to the **sustain level**. This stage occurs while the key is held down.

### Delay
An effect that **stores and plays back** audio after a time interval. Delay time ranges from milliseconds (slapback, doubling) to seconds (echo, looping). See **[Chapter 13: Time-Based Effects](13-effects-time-based.md)**.

### Detune
**Pitch offset** between oscillators or unison voices, typically measured in cents. Creates chorus/ensemble effects. Surge provides various unison detune distributions. See **[Chapter 6: Classic Oscillators](06-oscillators-classic.md)**.

### Distortion
Non-linear **waveshaping** that adds harmonic or inharmonic overtones. Types include soft clipping (smooth saturation), hard clipping (fuzz), and complex waveshaping functions. See **[Chapter 15: Distortion and Waveshaping](15-effects-distortion.md)**.

### Downsampling
Reducing the **sample rate** of a signal, typically after oversampled processing. Requires proper anti-aliasing filtering to prevent frequency folding.

### Dry/Wet
**Mix control** between unprocessed (dry) and processed (wet) signal. 0% = fully dry, 100% = fully wet, 50% = equal mix. Most effects provide dry/wet controls.

### DSP
**Digital Signal Processing** - Mathematical manipulation of digital audio signals, including filtering, synthesis, effects, and analysis.

---

## E

### Envelope
A **time-varying control signal** that shapes parameters over the duration of a note. Standard types include ADSR, multi-stage, and MSEG (multi-segment). See **[Chapter 19: Envelope Generators](19-envelopes.md)** and **[Chapter 21: MSEG](21-mseg.md)**.

### Envelope Follower
A circuit or algorithm that **tracks the amplitude** of an audio signal over time, creating a control signal. Used in vocoders, compressors, and envelope-following filters.

---

## F

### Feedback
Routing a signal's **output back to its input**. In filters, feedback creates resonance. In FM, it creates complex harmonic spectra. In delays, it creates repeating echoes. Excessive feedback can cause instability.

### Filter
A processor that **attenuates certain frequencies** while passing others. Types include:
- **Low-pass**: Passes lows, cuts highs
- **High-pass**: Passes highs, cuts lows
- **Band-pass**: Passes mid-range, cuts lows and highs
- **Notch**: Cuts mid-range, passes lows and highs
- **Comb**: Multiple peaks and notches
See **[Chapter 10: Filter Theory](10-filter-theory.md)** and **[Chapter 11: Filter Implementation](11-filter-implementation.md)**.

### FM (Frequency Modulation)
Using one oscillator to **modulate the frequency** of another. Creates complex harmonic and inharmonic timbres. FM depth controls modulation amount, ratio controls modulator/carrier frequency relationship. See **[Chapter 8: FM Synthesis](08-oscillators-fm.md)**.

Instantaneous frequency:
```
f(t) = f_carrier + modulation_depth * sin(2π * f_modulator * t)
```

### Formant
**Resonant frequency peaks** in a sound's spectrum, particularly important in vocal synthesis. Formant filters emphasize specific frequency bands to create vowel-like sounds.

### Frequency
**Rate of oscillation** measured in Hertz (Hz) - cycles per second. A 440 Hz tone completes 440 cycles per second. Musical note A4 = 440 Hz.

MIDI note to frequency:
```
f = 440 * 2^((midi_note - 69)/12)
```

### Frequency Response
The **amplitude and phase response** of a filter or system across the frequency spectrum. Typically visualized as a graph of gain (dB) vs. frequency (Hz).

---

## G

### Gain
**Amplification or attenuation** of a signal. Gain > 1 (or > 0 dB) increases amplitude, gain < 1 (or < 0 dB) decreases it.

### Gate
A binary on/off signal indicating when a **note is active**. Gate on = key pressed, gate off = key released. Used to trigger envelopes and control note duration.

### Granular Synthesis
Creating sounds by playing back many **short fragments (grains)** of audio, typically 1-100ms each. Grain parameters (position, pitch, duration, density) are varied to create evolving textures. Surge's Nimbus effect uses granular techniques. See **[Chapter 14: Reverb Effects](14-effects-reverb.md)**.

---

## H

### Harmonics
**Integer multiples of a fundamental frequency**. A 100 Hz fundamental has harmonics at 200 Hz (2nd), 300 Hz (3rd), 400 Hz (4th), etc. Harmonic content determines timbre:
- Sawtooth: all harmonics (1/n amplitude)
- Square: odd harmonics only (1/n amplitude)
- Triangle: odd harmonics only (1/n² amplitude)

### Headroom
The **available dynamic range** above the current signal level before clipping. Maintaining headroom prevents distortion. Digital audio clips hard at 0 dBFS (full scale).

### Hertz (Hz)
Unit of **frequency** - cycles per second. 1 Hz = one cycle per second. Named after Heinrich Hertz.

---

## I

### IIR Filter
**Infinite Impulse Response** filter - uses feedback, creating an impulse response that theoretically continues forever. Computationally efficient but can have phase distortion. Biquads are IIR filters. Contrast with **FIR** (Finite Impulse Response).

### Impulse Response
The **output of a system** when given a unit impulse (single sample at amplitude 1.0). Characterizes the complete behavior of linear systems. Convolution reverbs use recorded impulse responses.

### Interpolation
**Estimating values between samples**. Used in wavetable synthesis, delay lines, and sample playback. Types:
- **Linear**: Straight line between points (cheap, some aliasing)
- **Cubic**: Smooth curve (better quality)
- **Sinc**: Theoretically perfect (expensive)
See **[Chapter 7: Wavetable Synthesis](07-oscillators-wavetable.md)**.

---

## K

### kHz (Kilohertz)
1000 Hz. Standard sample rates: 44.1 kHz, 48 kHz, 96 kHz, 192 kHz.

---

## L

### Latency
The **time delay** from input to output. Plugin latency depends on buffer size and any look-ahead processing. Lower latency improves playing feel but increases CPU load.

```
Latency (ms) = (buffer_size / sample_rate) * 1000
At 48kHz: 128 samples = 2.67ms, 512 samples = 10.67ms
```

### Legato
Playing style where notes are **connected without gaps**. In synthesis, legato mode re-triggers envelopes differently (or not at all) for overlapping notes. See **[Chapter 4: Voice Architecture](04-voice-architecture.md)**.

### LFO (Low-Frequency Oscillator)
An oscillator operating at **sub-audio frequencies** (typically 0.01 Hz - 20 Hz) used for modulation rather than sound generation. Creates vibrato, tremolo, filter sweeps, and other cyclical modulations. See **[Chapter 20: Low-Frequency Oscillators](20-lfos.md)**.

### Linear
**Proportional** or straight-line relationship. In synthesis:
- Linear frequency scale: 100 Hz, 200 Hz, 300 Hz (equal spacing)
- Linear amplitude scale: 0.0, 0.5, 1.0 (equal steps)
Contrast with **logarithmic** or **exponential**.

### Logarithmic
**Exponential** relationship where equal ratios create equal perceptual changes. Human hearing is logarithmic:
- Frequency: Octaves (2x) sound equal
- Amplitude: Decibels (10x = 20 dB)
Most musical controls use logarithmic scaling.

### Low-Pass Filter (LPF)
Filter that **passes low frequencies, attenuates high frequencies**. The most common filter in subtractive synthesis. Cutoff frequency determines where attenuation begins. See **[Chapter 10: Filter Theory](10-filter-theory.md)**.

---

## M

### Macro
**User-assignable control** that can modulate multiple parameters simultaneously. Surge provides 8 macros per scene, each with its own modulation routing. See **[Chapter 18: Modulation Architecture](18-modulation-architecture.md)**.

### MIDI
**Musical Instrument Digital Interface** - Protocol for communicating musical performance data (notes, velocity, controllers, etc.) between instruments and software. See **[Chapter 31: MIDI and MPE](31-midi-mpe.md)**.

### Modulation
Using one signal (modulator) to **control a parameter** of another (carrier). Types:
- **Audio-rate**: FM, ring modulation
- **Control-rate**: LFOs, envelopes
See **[Chapter 18: Modulation Architecture](18-modulation-architecture.md)**.

### Modulation Depth
The **amount or intensity** of modulation applied. Typically expressed as a percentage or bipolar value (-100% to +100%).

### Modulation Matrix
The **routing system** connecting modulation sources to destinations. Surge's modulation system allows unlimited routings from 40+ sources to hundreds of parameters. See **[Chapter 18: Modulation Architecture](18-modulation-architecture.md)**.

### Modulator
In modulation, the **control signal**. In FM synthesis, the oscillator that modulates the carrier's frequency. In ring modulation, both signals are modulators.

### Mono
**Single-channel** audio or **monophonic** synthesis (one note at a time). Monophonic synths include portamento and legato features.

### MPE (MIDI Polyphonic Expression)
MIDI extension allowing **per-note control** of pitch bend, pressure, and timbre. Each note gets its own MIDI channel for independent expression. See **[Chapter 31: MIDI and MPE](31-midi-mpe.md)**.

### MSEG (Multi-Segment Envelope Generator)
A flexible **multi-breakpoint envelope** with various curve types. Unlike ADSR, MSEG can have any number of stages with different shapes. Used for complex modulation patterns. See **[Chapter 21: MSEG](21-mseg.md)**.

---

## N

### Noise
**Random signal** with no periodic structure. Types:
- **White noise**: Equal energy at all frequencies
- **Pink noise**: Equal energy per octave (rolls off -3dB/octave)
- **Red/Brown noise**: Rolls off -6dB/octave
Used as oscillator source and modulation source.

### Normalization
**Scaling audio** to use full available dynamic range without clipping. Typically normalizes peak to -0.1 dB or RMS to target level.

### Nyquist Frequency
**Half the sample rate** - the highest frequency that can be accurately represented. Named after Harry Nyquist.

```
f_nyquist = sample_rate / 2
At 48 kHz: Nyquist = 24 kHz
At 44.1 kHz: Nyquist = 22.05 kHz
```

Any frequency above Nyquist will alias. See **[Chapter 5: Oscillator Theory](05-oscillators-overview.md)**.

### Nyquist-Shannon Theorem
To accurately represent a signal digitally, the **sample rate must be at least twice** the highest frequency component. This is the foundation of digital audio.

---

## O

### Octave
**Doubling of frequency**. A4 = 440 Hz, A5 = 880 Hz (one octave higher). Musical intervals:
- 1 octave = 12 semitones = 1200 cents
- Frequency ratio = 2:1

### Operator
In FM synthesis, an **oscillator unit** (usually sine wave) that can function as carrier or modulator. Surge's FM oscillators have 2-3 operators with various routing algorithms. See **[Chapter 8: FM Synthesis](08-oscillators-fm.md)**.

### Oscillator
A **periodic signal generator** - the primary sound source in synthesis. Surge includes 13 oscillator types: Classic, Wavetable, FM, String, Twist, Modern, Window, Alias, S&H, etc. See **[Chapter 5: Oscillator Theory](05-oscillators-overview.md)**.

### Oversampling
Processing at a **higher sample rate** than the system rate, then downsampling the result. Used to reduce aliasing in non-linear processes (distortion, waveshaping, sync). Typical ratios: 2x, 4x, 8x, 16x. See **[Chapter 15: Distortion and Waveshaping](15-effects-distortion.md)**.

---

## P

### Pan
**Stereo positioning** - placement of a mono signal in the stereo field. -100% = full left, 0% = center, +100% = full right.

### Parameter
A **controllable value** in a synthesizer. Surge has hundreds of parameters (oscillator pitch, filter cutoff, effect mix, etc.). Most parameters are modulatable.

### Partial
A **single frequency component** in a complex sound. Harmonics are partials at integer multiples of the fundamental. Inharmonic partials (e.g., in bells) are non-integer multiples.

### Patch
A complete **synthesizer preset** - all parameter values, modulation routings, and settings. Surge patches are stored as XML files. See **[Chapter 27: Patch System](27-patch-system.md)**.

### Phase
**Position in a waveform's cycle**, typically measured in degrees (0-360°) or radians (0-2π). Phase relationship between signals affects summing behavior:
- In phase (0°): Signals add constructively
- 180° out of phase: Signals cancel
- 90° out of phase: No cancellation

### Pitch
**Perceived frequency** of a sound. MIDI note 69 = A4 = 440 Hz.

### Polyphony
Number of **simultaneous notes** a synth can play. Surge supports up to 64 voices per patch (32 per scene). See **[Chapter 4: Voice Architecture](04-voice-architecture.md)**.

### Portamento
**Smooth pitch glide** between notes rather than discrete steps. Also called glide. Time parameter controls glide duration. Common in monophonic synthesis.

### Pulse Wave
A **rectangular waveform** with variable duty cycle (pulse width). 50% duty cycle = square wave (odd harmonics). Other widths create different harmonic spectra. See **[Chapter 6: Classic Oscillators](06-oscillators-classic.md)**.

### PWM (Pulse Width Modulation)
**Varying the pulse width** of a pulse wave over time, typically via LFO. Creates a sweeping, chorused sound. Classic analog synth technique. See **[Chapter 6: Classic Oscillators](06-oscillators-classic.md)**.

---

## Q

### Q (Quality Factor)
In filters, **resonance amount**. Higher Q = narrower bandwidth and sharper peak. In parametric EQ, Q determines the width of the affected frequency band.

```
Q = f_center / bandwidth
Higher Q = narrower peak/cut
Lower Q = wider, gentler slope
```

### Quantization
**Converting continuous values to discrete levels**. In audio, bit depth determines quantization resolution:
- 16-bit: 65,536 levels
- 24-bit: 16,777,216 levels
- 32-bit float: Very high resolution

Quantization noise results from this discretization.

---

## R

### Random
**Non-periodic, unpredictable** signal or modulation. Surge's LFOs include random waveforms (stepped random, smooth random) for organic, non-repetitive modulation.

### Ratio
In FM synthesis, the **frequency relationship** between modulator and carrier, expressed as a ratio (e.g., 2:1, 3.5:1). Integer ratios produce harmonic spectra, non-integer ratios produce inharmonic timbres. See **[Chapter 8: FM Synthesis](08-oscillators-fm.md)**.

### Release
The final stage of an ADSR envelope - **time to fade to silence** after key release (gate off). Determines how long notes ring out.

### Resonance
In filters, **emphasis at the cutoff frequency** creating a peak in frequency response. Achieved through positive feedback in the filter circuit. At high resonance, filters self-oscillate. See **[Chapter 10: Filter Theory](10-filter-theory.md)**.

### Reverb
**Simulation of room acoustics** - dense, diffuse reflections that create a sense of space. Algorithms include algorithmic (Schroeder, FDN), convolution (impulse response), and hybrid approaches. See **[Chapter 14: Reverb Effects](14-effects-reverb.md)**.

### Ring Modulation
Multiplying two audio signals, producing **sum and difference frequencies**. Creates metallic, inharmonic timbres. Named after the ring of diodes in analog implementations.

```
output = signal_A * signal_B
Frequencies: (f1 + f2) and |f1 - f2|
```

### RMS (Root Mean Square)
A **measure of average signal level** that corresponds to perceived loudness better than peak level.

```
RMS = sqrt(mean(signal²))
```

---

## S

### Sample
A single **discrete amplitude value** in digital audio. At 48 kHz, 48,000 samples per second.

### Sample Rate
The **frequency of sampling** - number of samples per second, measured in Hz or kHz. Common rates:
- 44.1 kHz: CD quality
- 48 kHz: Professional standard
- 96 kHz, 192 kHz: High-resolution

Higher sample rates increase Nyquist frequency and reduce latency but increase CPU usage.

### Sampling Theorem
See **Nyquist-Shannon Theorem**.

### Sawtooth Wave
Waveform with **linear rise and sharp fall** (or vice versa). Contains all harmonics at 1/n amplitude. Sounds bright and buzzy. Common in subtractive synthesis. See **[Chapter 6: Classic Oscillators](06-oscillators-classic.md)**.

### Scene
In Surge, one of **two parallel synthesis engines**. Each scene is a complete synth with oscillators, filters, effects, and modulation. Scenes can be layered, split, or used independently. See **[Chapter 2: Core Data Structures](02-core-data-structures.md)**.

### Semitone
**1/12th of an octave** in equal temperament. The interval between adjacent piano keys. Frequency ratio = 2^(1/12) ≈ 1.059463.

### Sideband
Frequency components **created by modulation**. In FM and ring modulation, sidebands appear above and below the carrier frequency.

### Signal Path
The **routing of audio** through a synthesizer's components. Typical path: Oscillator → Filter → Amplifier → Effects. Understanding signal flow is crucial for sound design.

### SIMD (Single Instruction, Multiple Data)
CPU instruction sets that process **multiple values simultaneously**. Surge uses SSE2 (4-way float) for optimized DSP. Processes 4 voices in parallel (quad processing). See **[Chapter 32: SIMD Optimization](32-simd-optimization.md)**.

### Sine Wave
The **pure, fundamental waveform** - a single frequency with no harmonics. Described by:
```
y(t) = A * sin(2π * f * t)
```
Where A = amplitude, f = frequency, t = time.

### Soft Clipping
**Gradual limiting** that smoothly compresses signals approaching maximum amplitude, adding warm harmonic distortion. Contrast with hard clipping (abrupt cutoff). See **[Chapter 15: Distortion and Waveshaping](15-effects-distortion.md)**.

### Spectral
Relating to the **frequency content** of a signal. Spectral analysis reveals harmonic and inharmonic components.

### Square Wave
Waveform alternating between **+1 and -1** with 50% duty cycle. Contains only odd harmonics at 1/n amplitude. Sounds hollow and woodwind-like. See **[Chapter 6: Classic Oscillators](06-oscillators-classic.md)**.

### Step Sequencer
A **pattern-based modulation source** with discrete steps. Each step has a value and duration. Surge's LFOs include step sequencer mode. See **[Chapter 20: LFOs](20-lfos.md)**.

### Stereo
**Two-channel audio** (left and right). Stereo synthesis includes stereo oscillators, stereo filters, and stereo effects for width and spatial imaging.

### Subtractive Synthesis
Synthesis method starting with **harmonically rich waveforms** (sawtooth, square) and removing frequencies with filters. The classic analog synth approach. Surge excels at subtractive synthesis. See **[Chapter 6: Classic Oscillators](06-oscillators-classic.md)**.

### Sustain
The third stage of an ADSR envelope - the **held level** while a key remains pressed. Measured as a level (0-100%), not a time value.

### Sync (Oscillator Sync)
Technique where one oscillator **resets another's phase** each cycle, creating harmonically rich timbres. Hard sync resets immediately, soft sync blends. See **[Chapter 6: Classic Oscillators](06-oscillators-classic.md)**.

---

## T

### Tempo Sync
**Synchronizing modulation rates** to host tempo (BPM). LFOs, delays, and envelopes can lock to musical time divisions (1/4 note, 1/8 note, etc.) rather than absolute time.

### Timbre
The **tonal quality or color** of a sound that distinguishes different instruments playing the same pitch. Determined by harmonic content and envelope characteristics.

### Triangle Wave
Waveform with **linear rise and fall**. Contains only odd harmonics at 1/n² amplitude. Sounds mellow, similar to sine wave but slightly brighter. See **[Chapter 6: Classic Oscillators](06-oscillators-classic.md)**.

### Tremolo
**Amplitude modulation** - periodic variation in volume, typically from an LFO. Creates a pulsing or throbbing effect.

### Trigger
The **initiation of an envelope** or event, usually from note-on. Retriggering starts envelopes from the beginning.

---

## U

### Unipolar
A signal or modulation source that ranges from **0 to 1** (always positive). Envelopes are typically unipolar. Contrast with **bipolar** (-1 to +1). Surge allows converting between modes.

### Unison
Multiple **detuned copies** of the same oscillator played simultaneously, creating a thick, chorused sound. Surge supports up to 16 unison voices with various spread algorithms. See **[Chapter 6: Classic Oscillators](06-oscillators-classic.md)**.

---

## V

### VCA (Voltage-Controlled Amplifier)
In analog synths, an **amplifier whose gain is controlled by voltage**. In digital synths, the amplitude stage controlled by the amplitude envelope. See **[Chapter 4: Voice Architecture](04-voice-architecture.md)**.

### VCF (Voltage-Controlled Filter)
In analog synths, a **filter whose cutoff is controlled by voltage**. In digital synths, the filter stage typically controlled by envelopes and LFOs.

### VCO (Voltage-Controlled Oscillator)
In analog synths, an **oscillator whose frequency is controlled by voltage**. The primary sound source.

### Velocity
**Key press speed** in MIDI, ranging 0-127. Used to control volume, filter brightness, and other parameters for expressive playing. See **[Chapter 31: MIDI and MPE](31-midi-mpe.md)**.

### Vibrato
**Pitch modulation** - periodic variation in frequency, typically from an LFO. Creates a singing, expressive quality.

### Voice
A **single note instance** in a polyphonic synthesizer. Each voice has its own oscillators, filters, envelopes, and voice-level modulation. Surge processes up to 64 voices simultaneously. See **[Chapter 4: Voice Architecture](04-voice-architecture.md)**.

### Voice Stealing
When polyphony limit is reached, **oldest or quietest voices are terminated** to make room for new notes. Various algorithms determine which voice to steal. See **[Chapter 4: Voice Architecture](04-voice-architecture.md)**.

---

## W

### Waveform
The **shape of a signal** when plotted over time. Classic waveforms include sine, sawtooth, square, and triangle. Each has characteristic harmonic content and timbre.

### Waveshaping
Non-linear **transfer function** that maps input amplitude to output amplitude differently than 1:1. Creates harmonic distortion and new frequency content. See **[Chapter 15: Distortion and Waveshaping](15-effects-distortion.md)**.

Transfer function example (soft clipping):
```
output = tanh(input * drive)
```

### Wavetable
A **collection of waveforms** organized sequentially. Wavetable synthesis scans through these waveforms with interpolation, creating smoothly evolving timbres. Surge supports both single-cycle and multi-frame wavetables. See **[Chapter 7: Wavetable Synthesis](07-oscillators-wavetable.md)**.

### White Noise
**Random signal** with equal energy at all frequencies. Sounds like radio static or ocean waves (hissing). Used as sound source for percussive sounds and modulation.

---

## X

### XML
**Extensible Markup Language** - Text-based format used for Surge patch files. Human-readable and version-control friendly. See **[Chapter 27: Patch System](27-patch-system.md)**.

---

## Z

### Zero-Crossing
The point where a **waveform crosses zero amplitude**. Some audio editing operations (fades, cuts) work best at zero-crossings to avoid clicks. In filter design, zeros determine attenuation.

### Z-Transform
Mathematical tool for analyzing **discrete-time signals and systems** (digital filters). The discrete-time equivalent of Laplace transform. Transfer functions are expressed as ratios of polynomials in z^-1. See **[Appendix A: DSP Mathematics](appendix-a-dsp-math.md)**.

Transfer function in z-domain:
```
H(z) = Y(z) / X(z) = (b0 + b1*z^-1 + b2*z^-2 + ...) / (a0 + a1*z^-1 + a2*z^-2 + ...)
```

---

## Advanced Terms

### AAF (Anti-Aliasing Filter)
**Low-pass filter** applied before downsampling to remove frequencies above the new Nyquist limit, preventing aliasing. Essential in oversampled processing.

### Allpass Filter
Filter that **passes all frequencies** at equal amplitude but shifts their phase. Used in phasers, reverbs, and dispersion effects. See **[Chapter 13: Time-Based Effects](13-effects-time-based.md)**.

### Bit Depth
**Resolution of amplitude quantization** in digital audio. 16-bit = 65,536 levels, 24-bit = 16,777,216 levels. Higher bit depth = lower quantization noise and higher dynamic range.

### Block Processing
Processing audio in **chunks rather than sample-by-sample** for efficiency. Surge uses block sizes of typically 8-32 samples. See **[Chapter 1: Architecture Overview](01-architecture-overview.md)**.

### Clipping
**Amplitude limiting** when signal exceeds maximum level. Hard clipping creates harsh, square-wave-like distortion. Soft clipping creates smoother, tube-like saturation.

### Convolution
Mathematical operation where one function is **"smeared" by another**. Used in reverb (convolution of signal with impulse response) and sample-accurate filter design.

```
y[n] = Σ(x[k] * h[n-k])
```

Where x = input, h = impulse response, y = output.

### Denormal
Floating-point values **extremely close to zero** that can cause CPU performance degradation. Surge includes denormal protection. See **[Chapter 39: Performance Optimization](39-performance.md)**.

### Dynamic Range
The **ratio between loudest and quietest** signal a system can handle.

```
Dynamic Range (dB) = 20 * log10(max_amplitude / noise_floor)
16-bit: ~96 dB
24-bit: ~144 dB
32-bit float: ~1500 dB (theoretical)
```

### FDN (Feedback Delay Network)
Reverb algorithm using **multiple delay lines with feedback matrix**. Creates dense, natural-sounding reverberation. See **[Chapter 14: Reverb Effects](14-effects-reverb.md)**.

### FIR Filter (Finite Impulse Response)
Filter with **no feedback** - impulse response is finite length. Provides linear phase (no phase distortion) but requires more computation than IIR. Used for precise frequency response.

### Formant Filter
Filter that **emphasizes specific frequency bands** (formants) to create vocal-like timbres. Models resonances of vocal tract. See **[Chapter 11: Filter Implementation](11-filter-implementation.md)**.

### Fourier Transform
Mathematical transformation that converts **time-domain signals to frequency-domain** representation. FFT (Fast Fourier Transform) is the efficient algorithm. Fundamental to spectral analysis and processing.

```
X(f) = ∫ x(t) * e^(-i2πft) dt
```

### Jitter
**Timing variations** in sample clock, causing subtle distortion and noise. High-quality converters minimize jitter.

### Ladder Filter
Classic **Moog-style filter** with four cascaded low-pass stages creating 24 dB/octave slope. Named for the ladder-like arrangement of components in the original circuit. See **[Chapter 11: Filter Implementation](11-filter-implementation.md)**.

### Morphing
**Smooth interpolation** between different waveforms, wavetables, or filter states. Creates evolving, dynamic timbres.

### One-Pole Filter
Simplest IIR filter with **single feedback coefficient**, creating 6 dB/octave slope. Building block for more complex filters.

```
y[n] = x[n] + a * y[n-1]
```

### Phase Distortion
**Non-linear phase response** in filters causing different frequencies to be delayed by different amounts. IIR filters have phase distortion; linear-phase FIR filters don't.

### Pole
In filter theory, a **frequency where filter gain approaches infinity** (before resonance limiting). Number of poles determines filter slope (1 pole = 6 dB/octave, 2 poles = 12 dB/octave, etc.).

### Saturation
**Gentle compression and harmonic enhancement** as signal approaches clipping. Models analog circuit behavior (tape, tubes, transformers). See **[Chapter 15: Distortion and Waveshaping](15-effects-distortion.md)**.

### State Variable Filter
Filter topology that simultaneously provides **low-pass, band-pass, and high-pass outputs** from the same circuit. Allows smooth morphing between filter types. See **[Chapter 10: Filter Theory](10-filter-theory.md)**.

### Subharmonics
Frequencies **below the fundamental** (1/2, 1/3, etc.). Created by some non-linear processes and subharmonic generators.

### THD (Total Harmonic Distortion)
Measurement of **harmonic content added** by non-linear processing, expressed as percentage. Lower THD = cleaner signal.

### Windowing
**Tapering edges** of audio segments to reduce discontinuities. Common windows: Hann, Hamming, Blackman. Used in FFT analysis, granular synthesis, and grain processing.

---

## Surge-Specific Terms

### Absolute Unison
Unison mode where oscillators are **tuned to exact MIDI note** rather than being spread. Creates phasing effects.

### FX Send
Routing from scene to **global FX bus**. Allows sharing reverb and delay across scenes. See **[Chapter 12: Effects Architecture](12-effects-architecture.md)**.

### MPE Pitch Bend
Per-note pitch bend in MPE, allowing **each note to bend independently**. Essential for expressive synthesis. See **[Chapter 31: MIDI and MPE](31-midi-mpe.md)**.

### Scene Mode
How Surge's two scenes are **combined**: Single (one scene), Split (keyboard split), Layer (both), Channel Split (MIDI channel routing). See **[Chapter 2: Core Data Structures](02-core-data-structures.md)**.

### SST Filters
**Surge Synth Team filter library** - collection of high-quality digital filter implementations used throughout Surge. See **[Chapter 11: Filter Implementation](11-filter-implementation.md)**.

### Surge DB
Built-in **patch database** using SQLite for organizing, searching, and tagging presets. See **[Chapter 28: Preset Management](28-preset-management.md)**.

### Voice Routing
How oscillators are **combined in FM configurations**: Filter 1, Filter 2, or directly to output. Determines signal path through synthesis engine.

---

## Conclusion

This glossary covers the essential terminology for understanding digital synthesis and Surge XT's implementation. For deeper exploration of specific topics, consult the referenced chapters. As you work with Surge, these terms will become familiar tools in your sound design vocabulary.

**Total Terms:** 140+

For mathematical foundations, see **[Appendix A: DSP Mathematics](appendix-a-dsp-math.md)**.
For code-level details, see **[Appendix C: Code Reference](appendix-c-code-reference.md)**.

---

**[Return to Index](00-INDEX.md)**
