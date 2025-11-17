# Surge XT Encyclopedic Guide

## A Comprehensive Documentation of Software Synthesis

This directory contains a comprehensive, encyclopedic guide to the Surge XT synthesizer codebase. Written in literate programming style, it interweaves prose explanations with code examples to teach both synthesis theory and implementation details.

## What's Inside

This guide covers:

- **Architecture** - System design, data structures, and core engine
- **Sound Generation** - Oscillators, filters, and DSP algorithms
- **Effects** - 30+ effect types and processing chains
- **Modulation** - LFOs, envelopes, MSEG, and formula modulation
- **User Interface** - JUCE-based GUI architecture and skinning
- **Advanced Topics** - SIMD optimization, microtuning, MPE, OSC
- **Development** - Building, testing, and adding features

## Quick Start

### Reading Online

Start with **[00-INDEX.md](00-INDEX.md)** which contains the full table of contents and reading guides for different audiences:

- Musicians and sound designers
- Developers wanting to contribute
- Students learning DSP
- Computer scientists interested in architecture

### Building as E-Book

Generate EPUB, PDF, or HTML versions:

```bash
# Make scripts executable
chmod +x build-*.sh

# Build EPUB (for e-readers)
./build-epub.sh

# Or build all formats
./build-all.sh
```

Output files will be in: `../../build/docs/`

**Requirements:**
- [Pandoc](https://pandoc.org/) - Universal document converter
- [LaTeX](https://www.latex-project.org/) - For PDF output (optional)

See **[appendix-e-pandoc.md](appendix-e-pandoc.md)** for detailed build instructions.

## Documentation Status

Currently documented chapters:

- ✅ 00: Index and Table of Contents
- ✅ 01: Architecture Overview
- ✅ 05: Oscillator Theory and Implementation
- ✅ 12: Effects Architecture
- ✅ Appendix E: Pandoc Build System

Planned chapters (39 total):

- Chapters 2-4: Core data structures and synthesis pipeline
- Chapters 6-11: Detailed oscillator and filter documentation
- Chapters 13-17: Complete effects documentation
- Chapters 18-22: Modulation system deep-dive
- Chapters 23-26: UI/GUI architecture
- Chapters 27-29: Patch and resource management
- Chapters 30-36: Advanced topics (tuning, MIDI, SIMD, plugins)
- Chapters 37-39: Development and performance
- Appendices A-D: Math, glossary, code reference, bibliography

**Contributions welcome!** See the main Surge repository for contribution guidelines.

## Structure

Each chapter follows literate programming principles:

1. **Theory First** - Explain concepts before showing code
2. **Code in Context** - Real examples from the Surge codebase
3. **Detailed Comments** - Line-by-line explanations where helpful
4. **Cross-References** - Links to related chapters and appendices
5. **Further Reading** - Academic papers and external resources

### File Naming Convention

```
NN-chapter-name.md         # Main chapters (00-39)
appendix-X-name.md         # Appendices (A-E)
build-*.sh                 # Build scripts
style.css                  # HTML/EPUB styling
README.md                  # This file
```

## Who Is This For?

### Musicians & Sound Designers
Learn the theory behind synthesis to create better sounds. Focus on theory sections and skim implementation details.

### Developers
Understand the codebase to contribute features, fix bugs, or build similar software. Read everything sequentially.

### Students
Learn DSP and synthesis with working code examples. Start with Appendix A (DSP Math) then progress through synthesis chapters.

### Audio Programmers
See professional software architecture in action. Focus on architecture, optimization, and advanced topics.

## Key Features of This Guide

- **Complete Coverage** - Every major system documented
- **Code Examples** - Real code from Surge, not toy examples
- **Pedagogical** - Teaches concepts, not just API reference
- **Up-to-Date** - Covers Surge XT 1.3+ features
- **Portable** - Converts to EPUB, PDF, HTML
- **Open Source** - GPL-3.0 licensed, contributions welcome

## Technology Stack Documented

The guide covers Surge's technology stack:

- **Language**: C++20
- **Framework**: JUCE 7.x
- **Build**: CMake
- **DSP**: Hand-coded SSE2 SIMD
- **Libraries**: SST (Surge Synth Team libraries), Airwindows, Eurorack ports
- **Formats**: VST3, AU, CLAP, LV2, Standalone
- **Scripting**: LuaJIT for wavetables and modulation
- **Platforms**: Windows, macOS, Linux (x86_64, ARM64)

## Learning Path

**Beginner** (understanding synthesis):
1. Chapter 5 - Oscillator Theory
2. Chapter 10 - Filter Theory
3. Chapter 18 - Modulation Architecture
4. Chapter 19 - Envelopes

**Intermediate** (understanding implementation):
1. Chapter 1 - Architecture Overview
2. Chapter 3 - Synthesis Pipeline
3. Chapter 6 - Classic Oscillators (detailed)
4. Chapter 12 - Effects Architecture

**Advanced** (contributing to Surge):
1. Chapters 1-4 - Complete architecture
2. Chapter 32 - SIMD Optimization
3. Chapter 37 - Build System
4. Chapter 38 - Adding Features
5. Chapter 39 - Performance

## Contributing

To contribute to this documentation:

1. Follow the literate programming style of existing chapters
2. Include code examples from actual Surge source
3. Explain theory before implementation
4. Cross-reference related chapters
5. Test code examples for accuracy
6. Submit via pull request to the main Surge repository

**Style Guidelines:**
- Write in clear, educational prose
- Use code blocks with language tags: ` ```cpp `
- Include file paths in comments: `// From: src/common/...`
- Explain "why" not just "what"
- Define technical terms on first use
- Link to academic papers where applicable

## Building From Source

### Prerequisites

**macOS:**
```bash
brew install pandoc
# Optional for PDF:
brew install basictex
```

**Linux (Debian/Ubuntu):**
```bash
sudo apt-get install pandoc
# Optional for PDF:
sudo apt-get install texlive-full
```

**Windows:**
Download installers from:
- https://pandoc.org/installing.html
- https://miktex.org/ (for PDF)

### Build Commands

```bash
# EPUB (e-book format)
./build-epub.sh

# PDF (requires LaTeX)
./build-pdf.sh

# HTML (single-page website)
./build-html.sh

# All formats
./build-all.sh
```

Outputs:
- `../../build/docs/surge-xt-encyclopedic-guide.epub`
- `../../build/docs/surge-xt-encyclopedic-guide.pdf`
- `../../build/docs/html/index.html`

## License

This documentation is part of the Surge XT project and is released under **GPL-3.0** license.

Surge XT synthesizer is:
- Copyright (c) 2018-2025, Surge Synth Team
- Copyright (c) 2005-2018, Claes Johanson / Vember Audio

## Acknowledgments

### Primary Sources
- Surge XT codebase and inline documentation
- Surge Synth Team developer knowledge
- Academic DSP literature
- Open-source synthesis community

### Contributors
See the main Surge repository for a complete list of contributors.

### Inspiration
This guide draws inspiration from:
- Donald Knuth's *Literate Programming*
- *The Architecture of Open Source Applications*
- Will Pirkle's synthesis textbooks
- Julius O. Smith III's DSP lecture series

## Support

- **Surge Website**: https://surge-synthesizer.github.io/
- **GitHub**: https://github.com/surge-synthesizer/surge
- **Discord**: https://discord.gg/spGANHw
- **Forum**: https://github.com/surge-synthesizer/surge/discussions

## Roadmap

**Near-term goals:**
- [ ] Complete all 39 main chapters
- [ ] Add all appendices
- [ ] Include diagrams and visualizations
- [ ] Add interactive code examples
- [ ] Create video walkthroughs

**Long-term vision:**
- Serve as the definitive Surge developer documentation
- Become a teaching resource for software synthesis
- Inspire similar documentation in other projects
- Publish as physical book (if community interest exists)

---

**Start reading: [00-INDEX.md](00-INDEX.md)**

*Last updated: 2025*
