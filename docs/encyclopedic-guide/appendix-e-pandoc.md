# Appendix E: Building the Book with Pandoc

## Overview

This encyclopedic guide is designed to be compiled into various formats using [Pandoc](https://pandoc.org/), a universal document converter. This appendix provides instructions for generating EPUB, PDF, and HTML versions of the complete documentation.

## Prerequisites

### Installing Pandoc

**macOS (via Homebrew):**
```bash
brew install pandoc
brew install pandoc-crossref  # For cross-references
```

**Linux (Ubuntu/Debian):**
```bash
sudo apt-get update
sudo apt-get install pandoc pandoc-data
```

**Windows:**
Download the installer from https://pandoc.org/installing.html

**Verify Installation:**
```bash
pandoc --version
```

### Installing LaTeX (for PDF output)

PDF generation requires a LaTeX distribution:

**macOS:**
```bash
brew install basictex
# Or download MacTeX: https://www.tug.org/mactex/
```

**Linux:**
```bash
sudo apt-get install texlive-full
# Or minimal: texlive-latex-base texlive-fonts-recommended
```

**Windows:**
Download MiKTeX from https://miktex.org/

## Build Configuration

### Metadata File

Create `metadata.yaml` in the `docs/encyclopedic-guide` directory:

```yaml
---
title: "The Surge XT Synthesizer"
subtitle: "An Encyclopedic Guide to Advanced Software Synthesis"
author:
  - "Surge Synth Team"
  - "Community Contributors"
date: "2025"
lang: "en-US"
subject: "Digital Audio Synthesis"
keywords:
  - "Synthesizer"
  - "DSP"
  - "Audio Programming"
  - "Software Synthesis"
  - "C++"
rights: "GPL-3.0"
toc: true
toc-depth: 3
numbersections: true
documentclass: book
geometry:
  - margin=1in
fontsize: 11pt
linestretch: 1.2
link-citations: true
urlcolor: blue
linkcolor: black
---
```

### CSS for HTML/EPUB

Create `style.css`:

```css
/* Typography */
body {
    font-family: "Georgia", "Times New Roman", serif;
    font-size: 16px;
    line-height: 1.6;
    max-width: 800px;
    margin: 0 auto;
    padding: 20px;
    color: #333;
}

code {
    font-family: "Consolas", "Monaco", "Courier New", monospace;
    font-size: 14px;
    background-color: #f4f4f4;
    padding: 2px 6px;
    border-radius: 3px;
}

pre {
    background-color: #f4f4f4;
    padding: 15px;
    border-radius: 5px;
    overflow-x: auto;
    border-left: 4px solid #007acc;
}

pre code {
    background-color: transparent;
    padding: 0;
}

/* Headings */
h1 {
    font-size: 2.5em;
    color: #2c3e50;
    border-bottom: 2px solid #007acc;
    padding-bottom: 10px;
    margin-top: 40px;
}

h2 {
    font-size: 2em;
    color: #34495e;
    margin-top: 30px;
    border-bottom: 1px solid #bdc3c7;
    padding-bottom: 5px;
}

h3 {
    font-size: 1.5em;
    color: #7f8c8d;
    margin-top: 25px;
}

/* Links */
a {
    color: #007acc;
    text-decoration: none;
}

a:hover {
    text-decoration: underline;
}

/* Tables */
table {
    border-collapse: collapse;
    width: 100%;
    margin: 20px 0;
}

th, td {
    border: 1px solid #ddd;
    padding: 12px;
    text-align: left;
}

th {
    background-color: #007acc;
    color: white;
    font-weight: bold;
}

tr:nth-child(even) {
    background-color: #f9f9f9;
}

/* Blockquotes */
blockquote {
    border-left: 4px solid #007acc;
    padding-left: 20px;
    margin-left: 0;
    color: #555;
    font-style: italic;
}

/* Code filename labels */
.filename {
    background-color: #2c3e50;
    color: white;
    padding: 5px 15px;
    border-radius: 5px 5px 0 0;
    font-family: monospace;
    font-size: 0.9em;
    display: inline-block;
    margin-bottom: -10px;
}

/* Chapter markers */
.chapter {
    page-break-before: always;
}

/* Navigation */
nav {
    background-color: #2c3e50;
    color: white;
    padding: 10px 20px;
    margin-bottom: 30px;
    border-radius: 5px;
}

nav ul {
    list-style: none;
    padding: 0;
}

nav a {
    color: #ecf0f1;
}

nav a:hover {
    color: #3498db;
}
```

## Build Scripts

### Generate EPUB

Create `build-epub.sh`:

```bash
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
    --epub-cover-image=cover.png \
    --css=style.css \
    --metadata title="The Surge XT Synthesizer: An Encyclopedic Guide" \
    --metadata author="Surge Synth Team" \
    --metadata language="en-US" \
    --metadata rights="GPL-3.0" \
    --epub-chapter-level=1 \
    --number-sections \
    --standalone

echo ""
echo "✓ EPUB generated successfully:"
echo "  ../../build/docs/surge-xt-encyclopedic-guide.epub"
echo ""
echo "Size: $(du -h ../../build/docs/surge-xt-encyclopedic-guide.epub | cut -f1)"
```

Make it executable:
```bash
chmod +x build-epub.sh
```

### Generate PDF

Create `build-pdf.sh`:

```bash
#!/bin/bash

# Surge XT Documentation - PDF Builder

set -e

echo "Building Surge XT Encyclopedic Guide (PDF)..."

cd "$(dirname "$0")"

# Verify dependencies
if ! command -v pandoc &> /dev/null; then
    echo "Error: pandoc is not installed"
    exit 1
fi

if ! command -v pdflatex &> /dev/null; then
    echo "Error: pdflatex is not installed (required for PDF)"
    echo "Install LaTeX: brew install basictex (macOS) or sudo apt-get install texlive-full (Linux)"
    exit 1
fi

mkdir -p ../../build/docs

# Same file gathering as EPUB script
FILES=(
    "00-INDEX.md"
    "01-architecture-overview.md"
    # ... (same as above)
)

EXISTING_FILES=()
for file in "${FILES[@]}"; do
    if [ -f "$file" ]; then
        EXISTING_FILES+=("$file")
        echo "  Including: $file"
    fi
done

echo ""
echo "Running pandoc (this may take a while)..."

pandoc \
    "${EXISTING_FILES[@]}" \
    --from=markdown+smart \
    --to=pdf \
    --output="../../build/docs/surge-xt-encyclopedic-guide.pdf" \
    --toc \
    --toc-depth=3 \
    --number-sections \
    --pdf-engine=pdflatex \
    --variable documentclass=book \
    --variable geometry:margin=1in \
    --variable fontsize=11pt \
    --variable linestretch=1.2 \
    --metadata title="The Surge XT Synthesizer: An Encyclopedic Guide" \
    --metadata author="Surge Synth Team" \
    --metadata date="$(date +%Y)" \
    --highlight-style=tango \
    --standalone

echo ""
echo "✓ PDF generated successfully:"
echo "  ../../build/docs/surge-xt-encyclopedic-guide.pdf"
echo ""
echo "Size: $(du -h ../../build/docs/surge-xt-encyclopedic-guide.pdf | cut -f1)"
```

### Generate HTML

Create `build-html.sh`:

```bash
#!/bin/bash

# Surge XT Documentation - HTML Builder

set -e

echo "Building Surge XT Encyclopedic Guide (HTML)..."

cd "$(dirname "$0")"

mkdir -p ../../build/docs/html

# Same file gathering
FILES=( ... )  # As above

EXISTING_FILES=()
for file in "${FILES[@]}"; do
    [ -f "$file" ] && EXISTING_FILES+=("$file")
done

# Generate single-page HTML
pandoc \
    "${EXISTING_FILES[@]}" \
    --from=markdown+smart \
    --to=html5 \
    --output="../../build/docs/html/index.html" \
    --toc \
    --toc-depth=3 \
    --number-sections \
    --css=style.css \
    --self-contained \
    --metadata title="The Surge XT Synthesizer: An Encyclopedic Guide" \
    --metadata author="Surge Synth Team" \
    --highlight-style=tango \
    --standalone

# Copy CSS
cp style.css ../../build/docs/html/

echo ""
echo "✓ HTML generated successfully:"
echo "  ../../build/docs/html/index.html"
echo ""
echo "Open in browser:"
echo "  open ../../build/docs/html/index.html  # macOS"
echo "  xdg-open ../../build/docs/html/index.html  # Linux"
```

### Build All Formats

Create `build-all.sh`:

```bash
#!/bin/bash

# Build all documentation formats

set -e

echo "=========================================="
echo "Surge XT Encyclopedic Guide - Build All"
echo "=========================================="
echo ""

./build-epub.sh
echo ""
./build-pdf.sh
echo ""
./build-html.sh

echo ""
echo "=========================================="
echo "✓ All formats built successfully!"
echo "=========================================="
echo ""
echo "Output files:"
ls -lh ../../build/docs/*.{epub,pdf} ../../build/docs/html/*.html
```

Make all executable:
```bash
chmod +x build-*.sh
```

## Building the Documentation

### Quick Start

From the `docs/encyclopedic-guide` directory:

```bash
# Build all formats
./build-all.sh

# Or build individually:
./build-epub.sh   # EPUB e-book
./build-pdf.sh    # PDF book
./build-html.sh   # HTML web page
```

### Output Location

Built files are in:
```
surge/build/docs/
├── surge-xt-encyclopedic-guide.epub
├── surge-xt-encyclopedic-guide.pdf
└── html/
    ├── index.html
    └── style.css
```

## Customization

### Adjusting PDF Layout

Edit the pandoc command in `build-pdf.sh`:

```bash
pandoc \
    # ... files ...
    --variable geometry:margin=1.5in \    # Wider margins
    --variable fontsize=12pt \            # Larger font
    --variable linestretch=1.5 \          # More spacing
    --variable mainfont="Palatino" \      # Different font
    --variable monofont="Courier" \       # Code font
    --variable colorlinks=true \          # Colored links in PDF
    # ...
```

### Adding a Cover Image

Create or download a cover image `cover.png` (recommended: 1600×2400 pixels).

The EPUB build script already includes:
```bash
--epub-cover-image=cover.png \
```

### Custom LaTeX Template

For advanced PDF customization, create a custom template:

```bash
# Get the default template
pandoc -D latex > template.tex

# Edit template.tex as needed

# Use in build
pandoc \
    # ... files ...
    --template=template.tex \
    # ...
```

## Syntax Highlighting

Pandoc supports many syntax highlighting styles:

**Available styles:**
- `pygments` (default, colorful)
- `tango` (softer colors)
- `espresso` (dark theme)
- `kate`, `monochrome`, `breezedark`, `haddock`

Change in build script:
```bash
--highlight-style=tango \
```

## Advanced Options

### Including Only Specific Chapters

Edit the `FILES` array in build scripts:

```bash
FILES=(
    "00-INDEX.md"
    "01-architecture-overview.md"
    "05-oscillators-overview.md"
    # ... only chapters you want
)
```

### Generating Individual Chapter PDFs

```bash
pandoc 05-oscillators-overview.md \
    -o oscillators.pdf \
    --toc \
    --number-sections \
    --pdf-engine=pdflatex
```

### Multi-File HTML (One Page Per Chapter)

```bash
for file in *.md; do
    pandoc "$file" \
        -o "../../build/docs/html/${file%.md}.html" \
        --css=style.css \
        --standalone
done
```

## Troubleshooting

### "pandoc: command not found"

Install pandoc: `brew install pandoc` or `sudo apt-get install pandoc`

### "pdflatex: command not found"

Install LaTeX: `brew install basictex` or `sudo apt-get install texlive-full`

### "File not found" errors

Some chapters may not exist yet. The build scripts skip missing files.

### PDF generation fails

Try simpler options:
```bash
pandoc *.md \
    -o output.pdf \
    --pdf-engine=pdflatex
```

If still failing, check LaTeX packages:
```bash
sudo tlmgr update --self
sudo tlmgr install booktabs
```

### EPUB won't open

Validate with epubcheck:
```bash
brew install epubcheck  # macOS
epubcheck surge-xt-encyclopedic-guide.epub
```

### Large file sizes

Reduce image sizes, or exclude images:
```bash
pandoc ... --extract-media=media/
```

## Integration with CMake

Add to `surge/CMakeLists.txt`:

```cmake
# Optional documentation target
find_program(PANDOC_EXECUTABLE pandoc)

if(PANDOC_EXECUTABLE)
    add_custom_target(docs-epub
        COMMAND ${CMAKE_CURRENT_SOURCE_DIR}/docs/encyclopedic-guide/build-epub.sh
        WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/docs/encyclopedic-guide
        COMMENT "Building EPUB documentation"
    )

    add_custom_target(docs-pdf
        COMMAND ${CMAKE_CURRENT_SOURCE_DIR}/docs/encyclopedic-guide/build-pdf.sh
        WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/docs/encyclopedic-guide
        COMMENT "Building PDF documentation"
    )

    add_custom_target(docs-all
        DEPENDS docs-epub docs-pdf
    )
endif()
```

Then build with:
```bash
cmake --build build --target docs-all
```

## Distribution

### Hosting HTML Documentation

Deploy to GitHub Pages:

```bash
# Build HTML
./build-html.sh

# Copy to gh-pages branch
git checkout gh-pages
cp -r ../../build/docs/html/* .
git add .
git commit -m "Update documentation"
git push origin gh-pages
```

### Releasing with Surge

Include EPUB/PDF in release packages:

```bash
# In release script
./docs/encyclopedic-guide/build-all.sh
cp build/docs/*.{epub,pdf} release-package/docs/
```

## Continuous Integration

Add to GitHub Actions (`.github/workflows/docs.yml`):

```yaml
name: Build Documentation

on:
  push:
    paths:
      - 'docs/encyclopedic-guide/**'

jobs:
  build-docs:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3

      - name: Install Pandoc
        run: |
          sudo apt-get update
          sudo apt-get install -y pandoc texlive-full

      - name: Build EPUB
        run: |
          cd docs/encyclopedic-guide
          ./build-epub.sh

      - name: Build PDF
        run: |
          cd docs/encyclopedic-guide
          ./build-pdf.sh

      - name: Upload artifacts
        uses: actions/upload-artifact@v3
        with:
          name: documentation
          path: build/docs/*
```

## Conclusion

With these tools, the Surge XT encyclopedic guide can be built into professional-quality documentation in multiple formats:

- **EPUB**: For e-readers (Kindle, Apple Books, etc.)
- **PDF**: For printing or offline reading
- **HTML**: For web hosting and searchability

The build system is automated, customizable, and integrates with Surge's existing build infrastructure.

---

**Happy documenting!**
