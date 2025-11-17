# Chapter 34: Testing Framework

Surge XT maintains a comprehensive test suite that ensures reliability and prevents regressions. The testing infrastructure is built around headless operation, allowing automated testing without GUI interaction.

## Test Architecture

### Catch2 Integration

Surge uses **Catch2 v3** as its testing framework, providing a modern, header-only test infrastructure:

```cpp
// From UnitTests.cpp - Test runner configuration
#define CATCH_CONFIG_RUNNER
#include "catch2/catch_amalgamated.hpp"
#include "HeadlessUtils.h"

int runAllTests(int argc, char **argv)
{
    // Verify test data exists
    std::string tfn = "resources/test-data/wav/Wavetable.wav";
    auto p = fs::path{tfn};
    if (!fs::exists(p))
    {
        std::cout << "Can't find file '" << tfn << "'.\n"
                  << "surge-testrunner assumes you run with CWD as root of the\n"
                  << "Surge XT repo, so that the above local reference loads.\n";

        if (!getenv("SURGE_TEST_WITH_FILE_ERRORS"))
            return 62;
    }

    // Run all tests via Catch2 session
    int result = Catch::Session().run(argc, argv);
    return result;
}
```

**Key features:**
- **BDD-style syntax**: TEST_CASE and SECTION macros
- **Dynamic sections**: DYNAMIC_SECTION for parameterized tests
- **Rich assertions**: REQUIRE, REQUIRE_FALSE, Approx matchers
- **Test discovery**: CMake integration via catch_discover_tests

### Test Organization

Tests are organized in `/home/user/surge/src/surge-testrunner/` by functional domain:

```
src/surge-testrunner/
├── main.cpp                      # Entry point and CLI routing
├── UnitTests.cpp                 # Test runner main
├── HeadlessUtils.h/cpp          # Headless Surge creation
├── Player.h/cpp                 # Event playback system
├── UnitTestUtilities.h/cpp      # Test helper functions
├── UnitTestsDSP.cpp             # DSP algorithm tests
├── UnitTestsFX.cpp              # Effects testing
├── UnitTestsFLT.cpp             # Filter testing
├── UnitTestsMIDI.cpp            # MIDI handling
├── UnitTestsMOD.cpp             # Modulation system
├── UnitTestsMSEG.cpp            # MSEG envelope tests
├── UnitTestsTUN.cpp             # Tuning system
├── UnitTestsIO.cpp              # File I/O operations
├── UnitTestsLUA.cpp             # Lua scripting
├── UnitTestsVOICE.cpp           # Voice management
├── UnitTestsNOTEID.cpp          # Note ID tracking
├── UnitTestsPARAM.cpp           # Parameter handling
├── UnitTestsQUERY.cpp           # Query operations
├── UnitTestsINFRA.cpp           # Infrastructure tests
└── HeadlessNonTestFunctions.cpp # Performance testing utilities
```

### Build Configuration

The test runner is configured in **CMakeLists.txt**:

```cmake
project(surge-testrunner)

surge_add_lib_subdirectory(catch2_v3)

add_executable(${PROJECT_NAME}
  HeadlessNonTestFunctions.cpp
  HeadlessUtils.cpp
  Player.cpp
  UnitTestUtilities.cpp
  UnitTests.cpp
  UnitTestsDSP.cpp
  UnitTestsFLT.cpp
  UnitTestsFX.cpp
  # ... all test files
  main.cpp
)

target_link_libraries(${PROJECT_NAME} PRIVATE
  surge-lua-src
  surge::catch2_v3
  surge::surge-common
  juce::juce_audio_basics
)

# Stack size adjustment for complex tests
if (MSVC AND CMAKE_BUILD_TYPE STREQUAL "Debug")
  set(CMAKE_EXE_LINKER_FLAGS_DEBUG
      "${CMAKE_EXE_LINKER_FLAGS_DEBUG} /STACK:0x1000000")
endif()

# CTest integration
catch_discover_tests(${PROJECT_NAME} WORKING_DIRECTORY ${SURGE_SOURCE_DIR})
```

## Unit Test Categories

### UnitTestsDSP.cpp - DSP Algorithms

Tests core digital signal processing:

```cpp
TEST_CASE("Simple Single Oscillator is Constant", "[osc]")
{
    auto surge = Surge::Headless::createSurge(44100);
    REQUIRE(surge);

    int len = 4410 * 5;
    Surge::Headless::playerEvents_t heldC =
        Surge::Headless::makeHoldMiddleC(len);
    REQUIRE(heldC.size() == 2);

    float *data = nullptr;
    int nSamples, nChannels;

    Surge::Headless::playAsConfigured(surge, heldC,
                                     &data, &nSamples, &nChannels);
    REQUIRE(data);
    REQUIRE(std::abs(nSamples - len) <= BLOCK_SIZE);
    REQUIRE(nChannels == 2);

    // Verify RMS is in expected range
    float rms = 0;
    for (int i = 0; i < nSamples * nChannels; ++i)
    {
        rms += data[i] * data[i];
    }
    rms /= (float)(nSamples * nChannels);
    rms = sqrt(rms);
    REQUIRE(rms > 0.1);
    REQUIRE(rms < 0.101);

    // Count zero crossings for frequency verification
    int zeroCrossings = 0;
    for (int i = 0; i < nSamples * nChannels - 2; i += 2)
    {
        if (data[i] > 0 && data[i + 2] < 0)
            zeroCrossings++;
    }
    REQUIRE(zeroCrossings > 130);
    REQUIRE(zeroCrossings < 160);

    delete[] data;
}
```

**Oscillator unison testing:**

```cpp
TEST_CASE("Unison Absolute and Relative", "[osc]")
{
    auto surge = Surge::Headless::createSurge(44100, true);
    REQUIRE(surge);

    auto assertRelative = [surge](const char *pn) {
        REQUIRE(surge->loadPatchByPath(pn, -1, "Test"));
        auto f60_0 = frequencyForNote(surge, 60, 5, 0);
        auto f60_1 = frequencyForNote(surge, 60, 5, 1);
        auto f60_avg = 0.5 * (f60_0 + f60_1);

        auto f72_0 = frequencyForNote(surge, 72, 5, 0);
        auto f72_1 = frequencyForNote(surge, 72, 5, 1);
        auto f72_avg = 0.5 * (f72_0 + f72_1);

        // In relative mode, frequencies should double proportionally
        REQUIRE(f72_avg / f60_avg == Approx(2).margin(0.01));
        REQUIRE(f72_0 / f60_0 == Approx(2).margin(0.01));
        REQUIRE(f72_1 / f60_1 == Approx(2).margin(0.01));
    };

    SECTION("Wavetable Oscillator")
    {
        assertRelative("resources/test-data/patches/Wavetable-Sin-Uni2-Relative.fxp");
        assertAbsolute("resources/test-data/patches/Wavetable-Sin-Uni2-Absolute.fxp");
    }
}
```

### UnitTestsFX.cpp - Effects Testing

Comprehensive effects validation:

```cpp
TEST_CASE("Every FX Is Created And Processes", "[fx]")
{
    for (int i = fxt_off + 1; i < n_fx_types; ++i)
    {
        DYNAMIC_SECTION("FX Testing " << i << " " << fx_type_names[i])
        {
            auto surge = Surge::Headless::createSurge(44100);
            REQUIRE(surge);

            // Process some blocks to stabilize
            for (int i = 0; i < 100; ++i)
                surge->process();

            // Set FX type
            auto *pt = &(surge->storage.getPatch().fx[0].type);
            auto awv = 1.f * i / (pt->val_max.i - pt->val_min.i);
            auto did = surge->idForParameter(pt);
            surge->setParameter01(did, awv, false);

            // Play note and process
            surge->playNote(0, 60, 100, 0, -1);
            for (int s = 0; s < 100; ++s)
            {
                surge->process();
            }

            surge->releaseNote(0, 60, 100);
            for (int s = 0; s < 20; ++s)
            {
                surge->process();
            }
        }
    }
}
```

**FX modulation persistence:**

```cpp
TEST_CASE("Move FX With Assigned Modulation", "[fx]")
{
    auto step = [](auto surge) {
        for (int i = 0; i < 10; ++i)
            surge->process();
    };

    auto confirmDestinations = [](auto surge,
                                  const std::vector<std::pair<int, int>> &fxp) {
        std::map<int, int> destinations;
        for (const auto &mg : surge->storage.getPatch().modulation_global)
        {
            if (destinations.find(mg.destination_id) == destinations.end())
                destinations[mg.destination_id] = 0;
            destinations[mg.destination_id]++;
        }

        // Verify each FX parameter has correct modulation count
        for (auto p : fxp)
        {
            auto id = surge->storage.getPatch().fx[p.first].p[p.second].id;
            if (destinations.find(id) == destinations.end())
                destinations[id] = 0;
            destinations[id]--;
        }

        for (auto p : destinations)
        {
            INFO("Confirming destination " << p.first);
            REQUIRE(p.second == 0);
        }
    };
}
```

### UnitTestsFLT.cpp - Filter Testing

Systematic filter coverage:

```cpp
TEST_CASE("Run Every Filter", "[flt]")
{
    for (int fn = 0; fn < sst::filters::num_filter_types; fn++)
    {
        DYNAMIC_SECTION("Test Filter " << sst::filters::filter_type_names[fn])
        {
            auto nst = std::max(1, sst::filters::fut_subcount[fn]);
            auto surge = Surge::Headless::createSurge(44100);
            REQUIRE(surge);

            for (int fs = 0; fs < nst; ++fs)
            {
                INFO("Subtype is " << fs);
                surge->storage.getPatch().scene[0].filterunit[0].type.val.i = fn;
                surge->storage.getPatch().scene[0].filterunit[0].subtype.val.i = fs;

                int len = BLOCK_SIZE * 5;
                Surge::Headless::playerEvents_t heldC =
                    Surge::Headless::makeHoldMiddleC(len);

                float *data = NULL;
                int nSamples, nChannels;

                Surge::Headless::playAsConfigured(surge, heldC,
                                                 &data, &nSamples, &nChannels);
                REQUIRE(data);
                REQUIRE(std::abs(nSamples - len) <= BLOCK_SIZE);
                REQUIRE(nChannels == 2);

                if (data)
                    delete[] data;
            }
        }
    }
}
```

**Waveshaper testing:**

```cpp
TEST_CASE("Run Every Waveshaper", "[flt]")
{
    for (int wt = 0; wt < (int)sst::waveshapers::WaveshaperType::n_ws_types; wt++)
    {
        DYNAMIC_SECTION("Test Waveshaper " << sst::waveshapers::wst_names[wt])
        {
            auto surge = Surge::Headless::createSurge(44100);

            surge->storage.getPatch().scene[0].wsunit.type.val.i = wt;
            surge->storage.getPatch().scene[0].wsunit.drive.set_value_f01(0.8);

            int len = BLOCK_SIZE * 4;
            Surge::Headless::playerEvents_t heldC =
                Surge::Headless::makeHoldMiddleC(len);

            float *data = NULL;
            int nSamples, nChannels;

            Surge::Headless::playAsConfigured(surge, heldC,
                                             &data, &nSamples, &nChannels);
            // Verify output
            if (data)
                delete[] data;
        }
    }
}
```

### UnitTestsMIDI.cpp - MIDI Handling

MIDI functionality validation:

```cpp
TEST_CASE("Channel Split Routes on Channel", "[midi]")
{
    auto surge = std::shared_ptr<SurgeSynthesizer>(
        Surge::Headless::createSurge(44100));
    REQUIRE(surge);
    REQUIRE(surge->loadPatchByPath(
        "resources/test-data/patches/ChannelSplit-Sin-2OctaveB.fxp",
        -1, "Test"));

    SECTION("Regular (non-MPE)")
    {
        surge->mpeEnabled = false;
        for (auto splitChan = 2; splitChan < 14; splitChan++)
        {
            auto smc = splitChan * 8;
            surge->storage.getPatch().splitpoint.val.i = smc;

            for (auto mc = 0; mc < 16; ++mc)
            {
                auto fr = frequencyForNote(surge, 69, 1, 0, mc);
                auto targetfr = mc <= splitChan ? 440 : 440 * 4;
                REQUIRE(fr == Approx(targetfr).margin(0.1));
            }
        }
    }

    SECTION("MPE Enabled")
    {
        surge->mpeEnabled = true;
        // Test MPE channel routing
    }
}
```

### UnitTestsMOD.cpp - Modulation System

ADSR and modulation routing:

```cpp
TEST_CASE("ADSR Envelope Behaviour", "[mod]")
{
    std::shared_ptr<SurgeSynthesizer> surge(
        Surge::Headless::createSurge(44100));
    REQUIRE(surge.get());

    auto runAdsr = [surge](float a, float d, float s, float r,
                          int a_s, int d_s, int r_s,
                          bool isAnalog, float releaseAfter,
                          float runUntil) {
        auto *adsrstorage = &(surge->storage.getPatch().scene[0].adsr[0]);
        std::shared_ptr<ADSRModulationSource> adsr(
            new ADSRModulationSource());
        adsr->init(&(surge->storage), adsrstorage,
                  surge->storage.getPatch().scenedata[0], nullptr);
        REQUIRE(adsr.get());

        auto inverseEnvtime = [](float desiredTime) {
            return log(desiredTime) / log(2.0);
        };

        // Set envelope parameters
        adsrstorage->a.set_value_f01(
            adsrstorage->a.value_to_normalized(inverseEnvtime(a)));
        adsrstorage->d.set_value_f01(
            adsrstorage->d.value_to_normalized(inverseEnvtime(d)));
        adsrstorage->s.set_value_f01(
            adsrstorage->s.value_to_normalized(s));
        adsrstorage->r.set_value_f01(
            adsrstorage->r.value_to_normalized(inverseEnvtime(r)));

        adsrstorage->a_s.val.i = a_s;
        adsrstorage->d_s.val.i = d_s;
        adsrstorage->r_s.val.i = r_s;
        adsrstorage->mode.val.b = isAnalog;

        // Run envelope and collect data
        adsr->attack();
        std::vector<std::pair<float, float>> res;
        // Process and verify envelope shape
    };
}
```

### UnitTestsTUN.cpp - Tuning System

Scala file and tuning validation:

```cpp
TEST_CASE("Retune Surge XT to Scala Files", "[tun]")
{
    auto surge = Surge::Headless::createSurge(44100);
    surge->storage.tuningApplicationMode = SurgeStorage::RETUNE_ALL;
    auto n2f = [surge](int n) {
        return surge->storage.note_to_pitch(n);
    };

    SECTION("12-intune SCL file")
    {
        Tunings::Scale s = Tunings::readSCLFile(
            "resources/test-data/scl/12-intune.scl");
        surge->storage.retuneToScale(s);

        REQUIRE(n2f(surge->storage.scaleConstantNote()) ==
                surge->storage.scaleConstantPitch());
        REQUIRE(n2f(surge->storage.scaleConstantNote() + 12) ==
                surge->storage.scaleConstantPitch() * 2);
    }

    SECTION("Zeus 22")
    {
        Tunings::Scale s = Tunings::readSCLFile(
            "resources/test-data/scl/zeus22.scl");
        surge->storage.retuneToScale(s);

        REQUIRE(n2f(surge->storage.scaleConstantNote() + s.count) ==
                surge->storage.scaleConstantPitch() * 2);
    }
}
```

**Frequency accuracy:**

```cpp
TEST_CASE("Notes at Appropriate Frequencies", "[tun]")
{
    auto surge = surgeOnSine();
    REQUIRE(surge.get());

    SECTION("Untuned - Standard Tuning")
    {
        auto f60 = frequencyForNote(surge, 60);
        auto f72 = frequencyForNote(surge, 72);
        auto f69 = frequencyForNote(surge, 69);

        REQUIRE(f60 == Approx(261.63).margin(.1));
        REQUIRE(f72 == Approx(261.63 * 2).margin(.1));
        REQUIRE(f69 == Approx(440.0).margin(.1));
    }
}
```

### UnitTestsIO.cpp - I/O Operations

File loading and resource management:

```cpp
TEST_CASE("We Can Read Wavetables", "[io]")
{
    auto surge = Surge::Headless::createSurge(44100);
    REQUIRE(surge.get());
    std::string metadata;

    SECTION("Wavetable.wav")
    {
        auto wt = &(surge->storage.getPatch().scene[0].osc[0].wt);
        surge->storage.load_wt_wav_portable(
            "resources/test-data/wav/Wavetable.wav", wt, metadata);
        REQUIRE(wt->size == 2048);
        REQUIRE(wt->n_tables == 256);
        REQUIRE((wt->flags & wtf_is_sample) == 0);
    }
}
```

**Batch wavetable validation:**

```cpp
TEST_CASE("All Factory Wavetables Are Loadable", "[io]")
{
    auto surge = Surge::Headless::createSurge(44100, true);
    REQUIRE(surge.get());

    for (auto p : surge->storage.wt_list)
    {
        // Skip .wtscript files
        if (p.path.extension() == ".wtscript")
            continue;

        auto wt = &(surge->storage.getPatch().scene[0].osc[0].wt);
        wt->size = -1;
        wt->n_tables = -1;
        surge->storage.load_wt(path_to_string(p.path), wt,
                              &(surge->storage.getPatch().scene[0].osc[0]));

        REQUIRE(wt->size > 0);
        REQUIRE(wt->n_tables > 0);
    }
}
```

### UnitTestsLUA.cpp - Lua Scripting

Lua integration testing:

```cpp
#if HAS_LUA

TEST_CASE("Lua Hello World", "[lua]")
{
    SECTION("Hello World")
    {
        lua_State *L = luaL_newstate();
        REQUIRE(L);
        luaL_openlibs(L);

        const char lua_script[] = "print('Hello World from LuaJIT!')";
        int load_stat = luaL_loadbuffer(L, lua_script,
                                       strlen(lua_script), lua_script);
        lua_pcall(L, 0, 0, 0);

        lua_close(L);
    }
}

TEST_CASE("Lua Sample Operations", "[lua]")
{
    SECTION("Math")
    {
        lua_State *L = luaL_newstate();
        REQUIRE(L);
        luaL_openlibs(L);

        const char lua_script[] = "function addThings(a, b) return a+b; end";
        luaL_loadbuffer(L, lua_script, strlen(lua_script), lua_script);
        lua_pcall(L, 0, 0, 0);

        // Load function and test
        lua_getglobal(L, "addThings");
        if (lua_isfunction(L, -1))
        {
            lua_pushnumber(L, 5.0);
            lua_pushnumber(L, 6.0);
            lua_pcall(L, 2, 1, 0);

            double sumval = 0.0;
            if (!lua_isnil(L, -1))
            {
                sumval = lua_tonumber(L, -1);
                lua_pop(L, 1);
            }
            REQUIRE(sumval == 5 + 6);
        }

        lua_close(L);
    }
}

#endif // HAS_LUA
```

### UnitTestsVOICE.cpp - Voice Management

Note ID and voice lifecycle:

```cpp
TEST_CASE("Release by Note ID", "[voice]")
{
    SECTION("Simple Sine Case")
    {
        auto s = surgeOnSine();

        auto proc = [&s]() {
            for (int i = 0; i < 5; ++i)
                s->process();
        };

        auto voicecount = [&s]() -> int {
            int res{0};
            for (auto sc = 0; sc < n_scenes; ++sc)
            {
                for (const auto &v : s->voices[sc])
                {
                    if (v->state.gate)
                        res++;
                }
            }
            return res;
        };

        proc();

        s->playNote(0, 60, 127, 0, 173);
        proc();
        REQUIRE(voicecount() == 1);

        s->playNote(0, 64, 127, 0, 177);
        proc();
        REQUIRE(voicecount() == 2);

        s->releaseNoteByHostNoteID(173, 0);
        proc();
        REQUIRE(voicecount() == 1);

        s->releaseNoteByHostNoteID(177, 0);
        proc();
        REQUIRE(voicecount() == 0);
    }
}
```

### UnitTestsMSEG.cpp - MSEG Envelopes

MSEG evaluation and segment testing:

```cpp
struct msegObservation
{
    msegObservation(int ip, float fp, float va)
    {
        iPhase = ip;
        fPhase = fp;
        phase = ip + fp;
        v = va;
    }
    int iPhase;
    float fPhase;
    float v;
    float phase;
};

std::vector<msegObservation> runMSEG(MSEGStorage *ms, float dPhase,
                                     float phaseMax, float deform = 0)
{
    auto res = std::vector<msegObservation>();
    double phase = 0.0;
    int iphase = 0;
    Surge::MSEG::EvaluatorState es;

    while (phase + iphase < phaseMax)
    {
        auto r = Surge::MSEG::valueAt(iphase, phase, deform, ms, &es, false);
        res.emplace_back(msegObservation(iphase, phase, r));

        phase += dPhase;
        if (phase > 1)
        {
            phase -= 1;
            iphase += 1;
        }
    }
    return res;
}

TEST_CASE("Basic MSEG Evaluation", "[mseg]")
{
    SECTION("Simple Square")
    {
        MSEGStorage ms;
        ms.n_activeSegments = 4;
        ms.endpointMode = MSEGStorage::EndpointMode::LOCKED;

        // Configure square wave segments
        ms.segments[0].duration = 0.5 - MSEGStorage::minimumDuration;
        ms.segments[0].type = MSEGStorage::segment::LINEAR;
        ms.segments[0].v0 = 1.0;

        // ... configure remaining segments

        resetCP(&ms);
        Surge::MSEG::rebuildCache(&ms);

        auto runIt = runMSEG(&ms, 0.0321, 5);
        for (auto c : runIt)
        {
            if (c.fPhase < 0.5 - MSEGStorage::minimumDuration)
                REQUIRE(c.v == 1);
            if (c.fPhase > 0.5 && c.fPhase < 1 - MSEGStorage::minimumDuration)
                REQUIRE(c.v == -1);
        }
    }
}
```

### UnitTestsINFRA.cpp - Infrastructure Tests

Memory alignment and resource management:

```cpp
TEST_CASE("Test Setup Is Correct", "[infra]")
{
    SECTION("No Patches, No Wavetables")
    {
        auto surge = Surge::Headless::createSurge(44100, false);
        REQUIRE(surge);
        REQUIRE(surge->storage.patch_list.empty());
        REQUIRE(surge->storage.wt_list.empty());
    }

    SECTION("Patches, Wavetables")
    {
        auto surge = Surge::Headless::createSurge(44100, true);
        REQUIRE(surge);
        REQUIRE(!surge->storage.patch_list.empty());
        REQUIRE(!surge->storage.wt_list.empty());
    }
}

TEST_CASE("Biquad Is SIMD Aligned", "[infra]")
{
    SECTION("Is It Aligned?")
    {
        std::vector<BiquadFilter *> pointers;
        for (int i = 0; i < 5000; ++i)
        {
            auto *f = new BiquadFilter();
            REQUIRE(align_diff(f, 16) == 0);
            pointers.push_back(f);
        }
        for (auto *d : pointers)
            delete d;
    }
}

TEST_CASE("QuadFilterUnit Is SIMD Aligned", "[infra]")
{
    SECTION("Array of QuadFilterUnits")
    {
        int nqfus = 5;
        for (int i = 0; i < 5000; ++i)
        {
            auto *f = new sst::filters::QuadFilterUnitState[nqfus]();
            for (int j = 0; j < nqfus; ++j)
            {
                auto *q = &f[j];
                REQUIRE(align_diff(q, 16) == 0);
            }
            delete[] f;
        }
    }
}
```

## Headless Testing

### Creating Headless Surge

The headless infrastructure allows testing without GUI:

```cpp
// From HeadlessUtils.h
namespace Surge
{
namespace Headless
{

std::shared_ptr<SurgeSynthesizer> createSurge(int sr,
                                              bool loadAllPatches = false);

void writeToStream(const float *data, int nSamples,
                  int nChannels, std::ostream &str);

} // namespace Headless
} // namespace Surge
```

**Usage:**

```cpp
// Create without loading factory content (faster)
auto surge = Surge::Headless::createSurge(44100, false);

// Create with all patches and wavetables (for patch tests)
auto surge = Surge::Headless::createSurge(44100, true);
```

### Event Playback System

The Player system provides MIDI-like event sequences:

```cpp
// From Player.h
struct Event
{
    typedef enum Type
    {
        NOTE_ON,
        NOTE_OFF,
        LAMBDA_EVENT,
        NO_EVENT  // Keep player running with no event
    } Type;

    Type type;
    char channel;
    char data1;
    char data2;
    std::function<void(std::shared_ptr<SurgeSynthesizer>)> surgeLambda;
    long atSample;
};

typedef std::vector<Event> playerEvents_t;
```

**Event creation helpers:**

```cpp
// Hold middle C for specified samples
playerEvents_t makeHoldMiddleC(int forSamples, int withTail = 0);

// Hold specific note
playerEvents_t makeHoldNoteFor(int note, int forSamples,
                               int withTail = 0, int midiChannel = 0);

// C major scale at 120 BPM
playerEvents_t make120BPMCMajorQuarterNoteScale(long sample0 = 0,
                                                int sr = 44100);
```

**Playing events:**

```cpp
void playAsConfigured(std::shared_ptr<SurgeSynthesizer> synth,
                     const playerEvents_t &events,
                     float **resultData, int *nSamples, int *nChannels);

void playOnEveryPatch(std::shared_ptr<SurgeSynthesizer> synth,
                     const playerEvents_t &events,
                     std::function<void(const Patch &p, const PatchCategory &c,
                                       const float *data, int nSamples,
                                       int nChannels)> completedCallback);
```

### Automated Testing

Tests run automatically without user interaction:

```cpp
// Example: Test all patches produce audio
auto surge = Surge::Headless::createSurge(44100);
Surge::Headless::playerEvents_t scale =
    Surge::Headless::make120BPMCMajorQuarterNoteScale(0, 44100);

auto callBack = [](const Patch &p, const PatchCategory &pc,
                   const float *data, int nSamples, int nChannels) {
    // Verify patch produces sound
    float rms = 0;
    for (int i = 0; i < nSamples * nChannels; ++i)
    {
        rms += data[i] * data[i];
    }
    rms = sqrt(rms / nChannels / nSamples);

    REQUIRE(rms > 0);  // Patch should produce audio
};

Surge::Headless::playOnEveryPatch(surge, scale, callBack);
```

## Test Patterns

### Testing Oscillators

**Basic oscillator test pattern:**

```cpp
TEST_CASE("Oscillator Produces Expected Output", "[osc]")
{
    auto surge = Surge::Headless::createSurge(44100);

    // Set oscillator type
    surge->storage.getPatch().scene[0].osc[0].type.val.i = ot_sine;

    // Generate audio
    int len = BLOCK_SIZE * 100;
    auto events = Surge::Headless::makeHoldMiddleC(len);

    float *data = nullptr;
    int nSamples, nChannels;
    Surge::Headless::playAsConfigured(surge, events,
                                     &data, &nSamples, &nChannels);

    // Verify frequency
    auto freq = frequencyFromData(data, nSamples, nChannels, 0,
                                 nSamples/10, nSamples*8/10, 44100);
    REQUIRE(freq == Approx(261.63).margin(0.5));

    delete[] data;
}
```

### Testing Filters

**Filter sweep pattern:**

```cpp
TEST_CASE("Filter Cutoff Sweep", "[flt]")
{
    auto surge = Surge::Headless::createSurge(44100);

    surge->storage.getPatch().scene[0].filterunit[0].type.val.i =
        sst::filters::fut_lp24;

    for (float cutoff = -60; cutoff <= 70; cutoff += 10)
    {
        surge->storage.getPatch().scene[0].filterunit[0].cutoff.val.f = cutoff;

        auto events = Surge::Headless::makeHoldMiddleC(BLOCK_SIZE * 20);
        float *data = nullptr;
        int nSamples, nChannels;

        Surge::Headless::playAsConfigured(surge, events,
                                         &data, &nSamples, &nChannels);

        // Verify no NaN or Inf
        for (int i = 0; i < nSamples * nChannels; ++i)
        {
            REQUIRE(std::isfinite(data[i]));
        }

        delete[] data;
    }
}
```

### Testing Effects

**FX parameter sweep:**

```cpp
TEST_CASE("Effect Parameter Stability", "[fx]")
{
    auto surge = Surge::Headless::createSurge(44100);

    // Set effect type
    setFX(surge, 0, fxt_reverb);

    // Sweep all parameters
    for (int p = 0; p < n_fx_params; ++p)
    {
        auto *param = &(surge->storage.getPatch().fx[0].p[p]);
        if (param->ctrltype == ct_none)
            continue;

        for (float val = 0; val <= 1.0; val += 0.1)
        {
            param->set_value_f01(val);

            surge->playNote(0, 60, 100, 0);
            for (int i = 0; i < 50; ++i)
                surge->process();
            surge->releaseNote(0, 60, 100);

            // Verify stability
            for (int i = 0; i < 20; ++i)
            {
                surge->process();
                for (int s = 0; s < BLOCK_SIZE; ++s)
                {
                    REQUIRE(std::isfinite(surge->output[0][s]));
                    REQUIRE(std::isfinite(surge->output[1][s]));
                }
            }
        }
    }
}
```

### Testing Patches

**Patch loading and playback:**

```cpp
TEST_CASE("Factory Patches Load and Play", "[io]")
{
    auto surge = Surge::Headless::createSurge(44100, true);

    for (int i = 0; i < surge->storage.patch_list.size(); ++i)
    {
        INFO("Testing patch " << i << ": " <<
             surge->storage.patch_list[i].name);

        surge->loadPatch(i);

        // Process to initialize
        for (int b = 0; b < 10; ++b)
            surge->process();

        // Play note
        auto events = Surge::Headless::makeHoldNoteFor(60, 44100 * 2);
        float *data = nullptr;
        int nSamples, nChannels;

        Surge::Headless::playAsConfigured(surge, events,
                                         &data, &nSamples, &nChannels);

        // Verify output is sane
        bool hasSound = false;
        for (int s = 0; s < nSamples * nChannels; ++s)
        {
            REQUIRE(std::isfinite(data[s]));
            REQUIRE(std::abs(data[s]) < 10.0);
            if (std::abs(data[s]) > 0.001)
                hasSound = true;
        }

        // Most patches should produce audible output
        // (Some pads may be very quiet initially)

        delete[] data;
    }
}
```

## Performance Testing

### Non-Test Functions

The test runner includes performance utilities in **HeadlessNonTestFunctions.cpp**:

```cpp
namespace Surge::Headless::NonTest
{

// Initialize patch database
void initializePatchDB();

// Generate statistics from every patch
void statsFromPlayingEveryPatch();

// Analyze filter frequency response
void filterAnalyzer(int ft, int fst, std::ostream &os);

// Generate nonlinear feedback norms
void generateNLFeedbackNorms();

// Performance testing
[[noreturn]] void performancePlay(const std::string &patchName, int mode);

} // namespace
```

### Running Performance Tests

**CLI access:**

```bash
# Run performance test
surge-testrunner --non-test --performance "PatchName" 0

# Analyze filter response
surge-testrunner --non-test --filter-analyzer 0 0

# Generate patch statistics
surge-testrunner --non-test --stats-from-every-patch
```

**Stats from every patch:**

```cpp
void statsFromPlayingEveryPatch()
{
    auto surge = Surge::Headless::createSurge(44100);

    Surge::Headless::playerEvents_t scale =
        Surge::Headless::make120BPMCMajorQuarterNoteScale(0, 44100);

    auto callBack = [](const Patch &p, const PatchCategory &pc,
                      const float *data, int nSamples, int nChannels) {
        std::cout << "cat/patch = " << pc.name << " / "
                  << std::setw(30) << p.name;

        if (nSamples * nChannels > 0)
        {
            const auto minmaxres = std::minmax_element(
                data, data + nSamples * nChannels);

            float rms = 0, L1 = 0;
            for (int i = 0; i < nSamples * nChannels; ++i)
            {
                rms += data[i] * data[i];
                L1 += fabs(data[i]);
            }
            L1 = L1 / (nChannels * nSamples);
            rms = sqrt(rms / nChannels / nSamples);

            std::cout << "  range = [" << *minmaxres.first << ", "
                      << *minmaxres.second << "]"
                      << " L1=" << L1 << " rms=" << rms;
        }
        std::cout << std::endl;
    };

    Surge::Headless::playOnEveryPatch(surge, scale, callBack);
}
```

### Filter Analysis

**Frequency response measurement:**

```cpp
void standardCutoffCurve(int ft, int sft, std::ostream &os)
{
    std::array<std::vector<float>, 127> ampRatios;
    std::array<std::vector<float>, 127> phases;
    std::vector<float> resonances;

    for (float res = 0; res <= 1.0; res += 0.2)
    {
        res = limit_range(res, 0.f, 0.99f);
        resonances.push_back(res);

        auto surge = Surge::Headless::createSurge(48000);
        surge->storage.getPatch().scenemode.val.i = sm_dual;

        // Scene 0: Filtered sine
        surge->storage.getPatch().scene[0].filterunit[0].type.val.i = ft;
        surge->storage.getPatch().scene[0].filterunit[0].subtype.val.i = sft;
        surge->storage.getPatch().scene[0].filterunit[0].resonance.val.f = res;
        surge->storage.getPatch().scene[0].osc[0].type.val.i = ot_sine;

        // Scene 1: Unfiltered sine (reference)
        surge->storage.getPatch().scene[1].filterunit[0].type.val.i =
            sst::filters::fut_none;
        surge->storage.getPatch().scene[1].osc[0].type.val.i = ot_sine;

        // Sweep frequencies and measure response
        for (int i = 0; i < 127; ++i)
        {
            surge->playNote(0, i, 100, 0);
            surge->playNote(1, i, 100, 0);

            // Process and measure amplitude ratio
            // ... analysis code
        }
    }
}
```

### Benchmarking

**CPU usage measurement:**

```cpp
void performancePlay(const std::string &patchName, int mode)
{
    auto surge = Surge::Headless::createSurge(44100, true);

    // Load patch
    bool found = false;
    for (int i = 0; i < surge->storage.patch_list.size(); ++i)
    {
        if (surge->storage.patch_list[i].name == patchName)
        {
            surge->loadPatch(i);
            found = true;
            break;
        }
    }

    if (!found)
    {
        std::cerr << "Patch '" << patchName << "' not found\n";
        return;
    }

    // Warm up
    for (int i = 0; i < 100; ++i)
        surge->process();

    // Benchmark loop
    const int iterations = 10000;
    auto start = std::chrono::high_resolution_clock::now();

    for (int i = 0; i < iterations; ++i)
    {
        if (i % 100 == 0)
            surge->playNote(0, 60 + (i % 24), 100, 0);
        surge->process();
    }

    auto end = std::chrono::high_resolution_clock::now();
    auto duration = std::chrono::duration_cast<std::chrono::microseconds>(
        end - start);

    double blocksPerSecond = iterations * 1000000.0 / duration.count();
    double samplesPerSecond = blocksPerSecond * BLOCK_SIZE;
    double realTimeFactor = samplesPerSecond / 44100.0;

    std::cout << "Performance for '" << patchName << "':\n";
    std::cout << "  Blocks/sec: " << blocksPerSecond << "\n";
    std::cout << "  Samples/sec: " << samplesPerSecond << "\n";
    std::cout << "  Real-time factor: " << realTimeFactor << "x\n";
    std::cout << "  CPU usage: " << (100.0 / realTimeFactor) << "%\n";
}
```

## Writing Tests

### Test Structure

**Basic test anatomy:**

```cpp
TEST_CASE("Test Description", "[tag]")
{
    // Setup
    auto surge = Surge::Headless::createSurge(44100);

    SECTION("First Test Section")
    {
        // Arrange
        surge->storage.getPatch().scene[0].osc[0].type.val.i = ot_sine;

        // Act
        auto events = Surge::Headless::makeHoldMiddleC(BLOCK_SIZE * 100);
        float *data = nullptr;
        int nSamples, nChannels;
        Surge::Headless::playAsConfigured(surge, events,
                                         &data, &nSamples, &nChannels);

        // Assert
        REQUIRE(data != nullptr);
        REQUIRE(nChannels == 2);

        // Cleanup
        delete[] data;
    }

    SECTION("Second Test Section")
    {
        // Independent section - surge is reset
    }
}
```

### Assertions

**Catch2 assertion macros:**

```cpp
// Basic assertions
REQUIRE(condition);               // Must be true
REQUIRE_FALSE(condition);         // Must be false
REQUIRE_NOTHROW(expression);      // Should not throw
REQUIRE_THROWS(expression);       // Should throw
REQUIRE_THROWS_AS(expr, type);    // Should throw specific type

// Approximate comparisons
REQUIRE(value == Approx(expected).margin(tolerance));
REQUIRE(value == Approx(expected).epsilon(relativeError));

// Range checks
REQUIRE(value > min);
REQUIRE(value < max);

// String matching
REQUIRE_THAT(str, Catch::Matchers::Contains("substring"));
REQUIRE_THAT(str, Catch::Matchers::StartsWith("prefix"));
```

**Common patterns:**

```cpp
// Frequency testing
auto freq = frequencyForNote(surge, 60);
REQUIRE(freq == Approx(261.63).margin(0.5));

// RMS level testing
auto [freq, rms] = frequencyAndRMSForNote(surge, 60, 2);
REQUIRE(rms > 0.05);
REQUIRE(rms < 0.15);

// Finite value checking
for (int i = 0; i < nSamples * nChannels; ++i)
{
    REQUIRE(std::isfinite(data[i]));
    REQUIRE(std::abs(data[i]) < 10.0);  // Reasonable range
}

// Voice count verification
int activeVoices = 0;
for (auto &v : surge->voices[0])
{
    if (v->state.gate)
        activeVoices++;
}
REQUIRE(activeVoices == expectedCount);
```

### Test Data

**Test data directory structure:**

```
resources/test-data/
├── patches/           # Test patches (.fxp)
│   ├── all-filters/  # Filter test patches
│   └── ...
├── scl/              # Scala tuning files
│   ├── 12-intune.scl
│   ├── zeus22.scl
│   └── ...
├── wav/              # Wavetables and samples
│   ├── Wavetable.wav
│   ├── 05_BELL.WAV
│   └── pluckalgo.wav
└── daw-files/        # DAW project files for manual testing
```

**Loading test data:**

```cpp
// Load test patch
REQUIRE(surge->loadPatchByPath(
    "resources/test-data/patches/TestPatch.fxp", -1, "Test"));

// Load test wavetable
auto wt = &(surge->storage.getPatch().scene[0].osc[0].wt);
std::string metadata;
surge->storage.load_wt_wav_portable(
    "resources/test-data/wav/Wavetable.wav", wt, metadata);

// Load test tuning
Tunings::Scale s = Tunings::readSCLFile(
    "resources/test-data/scl/zeus22.scl");
surge->storage.retuneToScale(s);
```

### Utility Functions

**Test helper functions from UnitTestUtilities.h:**

```cpp
namespace Surge::Test
{

// Measure frequency from audio buffer
double frequencyForNote(std::shared_ptr<SurgeSynthesizer> surge,
                       int note, int seconds = 2,
                       int audioChannel = 0, int midiChannel = 0);

// Measure frequency and RMS
std::pair<double, double> frequencyAndRMSForNote(
    std::shared_ptr<SurgeSynthesizer> surge, int note,
    int seconds = 2, int audioChannel = 0, int midiChannel = 0);

// Frequency from raw audio data
double frequencyFromData(float *buffer, int nS, int nC,
                        int audioChannel, int start, int trimTo,
                        float sampleRate);

// RMS from raw audio data
double RMSFromData(float *buffer, int nS, int nC,
                  int audioChannel, int start, int trimTo);

// Set effect in slot
void setFX(std::shared_ptr<SurgeSynthesizer> surge,
          int slot, fx_type type);

// Create surge on specific patch
std::shared_ptr<SurgeSynthesizer> surgeOnPatch(
    const std::string &patchName);

// Create surge with specific template
std::shared_ptr<SurgeSynthesizer> surgeOnTemplate(
    const std::string &, float sr = 44100);

// Quick sine/saw setup
std::shared_ptr<SurgeSynthesizer> surgeOnSine(float sr = 44100);
std::shared_ptr<SurgeSynthesizer> surgeOnSaw(float sr = 44100);

} // namespace Surge::Test
```

**Using utilities:**

```cpp
TEST_CASE("Utility Function Example", "[example]")
{
    // Quick sine patch
    auto surge = surgeOnSine(44100);

    // Measure frequency
    auto freq = frequencyForNote(surge, 60);
    REQUIRE(freq == Approx(261.63).margin(0.5));

    // Measure frequency and RMS
    auto [f, rms] = frequencyAndRMSForNote(surge, 69);
    REQUIRE(f == Approx(440).margin(0.5));
    REQUIRE(rms > 0);

    // Set effect
    setFX(surge, 0, fxt_reverb);
}
```

### Best Practices

**1. Use descriptive test names:**

```cpp
// Good
TEST_CASE("ADSR Attack Time Matches Parameter", "[mod]")

// Bad
TEST_CASE("Test 1", "[mod]")
```

**2. Use SECTION for variants:**

```cpp
TEST_CASE("Filter Types Process Correctly", "[flt]")
{
    SECTION("Lowpass 24dB")
    {
        // Test LP24
    }

    SECTION("Highpass 12dB")
    {
        // Test HP12
    }
}
```

**3. Use DYNAMIC_SECTION for loops:**

```cpp
for (int i = 0; i < n_fx_types; ++i)
{
    DYNAMIC_SECTION("FX Type " << fx_type_names[i])
    {
        // Test effect i
    }
}
```

**4. Clean up resources:**

```cpp
float *data = nullptr;
Surge::Headless::playAsConfigured(surge, events,
                                 &data, &nSamples, &nChannels);
// Use data...
delete[] data;  // Always clean up
```

**5. Use INFO for context:**

```cpp
for (int note = 0; note < 128; ++note)
{
    INFO("Testing note " << note);
    auto freq = frequencyForNote(surge, note);
    REQUIRE(freq > 0);
}
```

**6. Test edge cases:**

```cpp
TEST_CASE("Parameter Boundary Values", "[param]")
{
    auto surge = Surge::Headless::createSurge(44100);
    auto &cutoff = surge->storage.getPatch().scene[0].filterunit[0].cutoff;

    SECTION("Minimum value")
    {
        cutoff.val.f = cutoff.val_min.f;
        // Verify stability
    }

    SECTION("Maximum value")
    {
        cutoff.val.f = cutoff.val_max.f;
        // Verify stability
    }

    SECTION("Zero crossing")
    {
        cutoff.val.f = 0;
        // Verify behavior
    }
}
```

## CI Integration

### GitHub Actions Workflow

Tests run automatically on pull requests in **.github/workflows/build-pr.yml**:

```yaml
name: "Build pull request"
on:
  pull_request:

jobs:
  build_plugin:
    name: PR - ${{ matrix.name }}
    runs-on: ${{ matrix.os }}
    strategy:
      matrix:
        include:
          - name: "macOS test runner"
            os: macos-latest
            target: surge-testrunner
            cmakeConfig: -GNinja
            cmakeOpt: RELEASE
            runTests: true

          - name: "Linux test runner"
            os: ubuntu-latest
            target: surge-testrunner
            cmakeConfig: -GNinja
            cmakeOpt: RELEASE
            runTests: true

          - name: "Windows test runner"
            os: windows-latest
            target: surge-testrunner
            cmakeConfig: -G"Visual Studio 17 2022" -A x64
            cmakeOpt: RELEASE
            runTests: true

    steps:
      - name: "Checkout code"
        uses: actions/checkout@v4
        with:
          submodules: recursive

      - name: "Build pull request version"
        run: |
          cmake -S . -B ./build ${{ matrix.cmakeConfig }} \
                -DCMAKE_BUILD_TYPE=${{ matrix.cmakeOpt }}
          cmake --build ./build --config ${{ matrix.cmakeOpt }} \
                --target ${{ matrix.target }} --parallel 3

      - name: Run tests
        if: ${{ matrix.runTests }}
        run: |
          set -e
          cd build
          ctest -j 4 || ctest --rerun-failed --output-on-failure
```

### CTest Integration

CMake's `catch_discover_tests` automatically creates CTest targets:

```cmake
catch_discover_tests(${PROJECT_NAME} WORKING_DIRECTORY ${SURGE_SOURCE_DIR})
```

**Running tests:**

```bash
# Build test runner
cmake -B build
cmake --build build --target surge-testrunner

# Run all tests
cd build
ctest -j 4

# Run with verbose output
ctest -V

# Run specific test tags
ctest -R "\[osc\]"

# Rerun failed tests
ctest --rerun-failed --output-on-failure
```

### Test Runner CLI

The test runner supports Catch2 command-line options:

```bash
# Run all tests
./surge-testrunner

# List all tests
./surge-testrunner --list-tests

# Run tests with specific tag
./surge-testrunner "[osc]"

# Run specific test
./surge-testrunner "Simple Single Oscillator is Constant"

# Show successful tests
./surge-testrunner --success

# Break on first failure
./surge-testrunner --abort

# Non-test utilities
./surge-testrunner --non-test --stats-from-every-patch
./surge-testrunner --non-test --filter-analyzer 0 0
./surge-testrunner --non-test --performance "PatchName" 0
```

### Regression Detection

Tests prevent regressions through:

**1. Frequency verification:**
```cpp
// Ensure tuning remains accurate
auto f60 = frequencyForNote(surge, 60);
REQUIRE(f60 == Approx(261.63).margin(0.1));
```

**2. Output validation:**
```cpp
// Detect DSP explosions
for (int i = 0; i < nSamples * nChannels; ++i)
{
    REQUIRE(std::isfinite(data[i]));
    REQUIRE(std::abs(data[i]) < 10.0);
}
```

**3. Patch compatibility:**
```cpp
// Verify all factory patches load
for (auto &patch : surge->storage.patch_list)
{
    REQUIRE_NOTHROW(surge->loadPatch(i));
}
```

**4. API consistency:**
```cpp
// Ensure voice management works correctly
s->playNote(0, 60, 127, 0, 173);
REQUIRE(voicecount() == 1);
s->releaseNoteByHostNoteID(173, 0);
REQUIRE(voicecount() == 0);
```

## Test Coverage

Surge's test suite includes **385+ test cases** covering:

- **DSP algorithms**: Oscillators, filters, waveshapers
- **Effects**: All 30+ effect types
- **Modulation**: ADSR, LFO, MSEG, formula
- **MIDI**: Note handling, MPE, channel routing
- **Tuning**: Scala files, microtuning, keyboard mapping
- **I/O**: Patch loading, wavetable loading, preset management
- **Voice management**: Polyphony, note stealing, note ID tracking
- **Infrastructure**: Memory alignment, SIMD, resource management
- **Lua scripting**: Formula evaluation, wavetable scripting

The comprehensive test suite ensures Surge remains stable and reliable across platforms and updates.

## Summary

Surge XT's testing framework provides:

1. **Catch2-based architecture** for modern C++ testing
2. **Organized test categories** by functional domain
3. **Headless operation** for automated testing
4. **Extensive utilities** for audio analysis
5. **Performance benchmarking** tools
6. **CI integration** with automatic regression detection
7. **385+ test cases** covering all major subsystems

The testing infrastructure is a critical component of Surge's development process, enabling rapid iteration while maintaining quality and preventing regressions. Contributors can easily add new tests using the established patterns and utilities.
