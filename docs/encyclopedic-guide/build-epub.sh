#!/bin/bash

# Surge XT Documentation - EPUB Builder
# Generates a complete EPUB book from markdown chapters

set -e  # Exit on error

echo "Building Surge XT Encyclopedic Guide (EPUB)..."

# Navigate to guide directory
cd "$(dirname "$0")"

# Verify pandoc is installed
if ! command -v pandoc &> /dev/null; then
    echo "Error: pandoc is not installed"
    echo "Install with: brew install pandoc (macOS) or sudo apt-get install pandoc (Linux)"
    exit 1
fi

# Create output directory
mkdir -p ../../build/docs

# Gather all markdown files in order
FILES=(
    "00-INDEX.md"
    "01-architecture-overview.md"
    "02-core-data-structures.md"
    "03-synthesis-pipeline.md"
    "04-voice-architecture.md"
    "05-oscillators-overview.md"
    "06-oscillators-classic.md"
    "07-oscillators-wavetable.md"
    "08-oscillators-fm.md"
    "09-oscillators-advanced.md"
    "10-filter-theory.md"
    "11-filter-implementation.md"
    "12-effects-architecture.md"
    "13-effects-time-based.md"
    "14-effects-reverb.md"
    "15-effects-distortion.md"
    "16-effects-frequency.md"
    "17-effects-integration.md"
    "18-modulation-architecture.md"
    "19-envelopes.md"
    "20-lfos.md"
    "21-mseg.md"
    "22-formula-modulation.md"
    "23-gui-architecture.md"
    "24-widgets.md"
    "25-overlay-editors.md"
    "26-skinning.md"
    "27-patch-system.md"
    "28-preset-management.md"
    "29-resource-management.md"
    "30-microtuning.md"
    "31-midi-mpe.md"
    "32-simd-optimization.md"
    "33-plugin-architecture.md"
    "34-testing.md"
    "35-osc.md"
    "36-python-bindings.md"
    "37-build-system.md"
    "38-adding-features.md"
    "39-performance.md"
    "appendix-a-dsp-math.md"
    "appendix-b-glossary.md"
    "appendix-c-code-reference.md"
    "appendix-d-bibliography.md"
    "appendix-e-pandoc.md"
)

# Filter to only include files that exist
EXISTING_FILES=()
for file in "${FILES[@]}"; do
    if [ -f "$file" ]; then
        EXISTING_FILES+=("$file")
        echo "  Including: $file"
    else
        echo "  Skipping (not found): $file"
    fi
done

if [ ${#EXISTING_FILES[@]} -eq 0 ]; then
    echo "Error: No markdown files found!"
    exit 1
fi

# Build EPUB
echo ""
echo "Running pandoc..."
pandoc \
    "${EXISTING_FILES[@]}" \
    --from=markdown+smart \
    --to=epub3 \
    --output="../../build/docs/surge-xt-encyclopedic-guide.epub" \
    --toc \
    --toc-depth=3 \
    --metadata title="The Surge XT Synthesizer: An Encyclopedic Guide" \
    --metadata author="Surge Synth Team" \
    --metadata language="en-US" \
    --metadata rights="GPL-3.0" \
    --metadata subject="Digital Audio Synthesis, Software Development, DSP" \
    --epub-chapter-level=1 \
    --number-sections \
    --standalone

echo ""
echo "✓ EPUB generated successfully:"
echo "  ../../build/docs/surge-xt-encyclopedic-guide.epub"
echo ""

if [ -f "../../build/docs/surge-xt-encyclopedic-guide.epub" ]; then
    echo "Size: $(du -h ../../build/docs/surge-xt-encyclopedic-guide.epub | cut -f1)"
fi
