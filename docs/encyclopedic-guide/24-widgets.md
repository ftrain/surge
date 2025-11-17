# Chapter 24: Widget System

## Building Blocks of the User Interface

Surge XT's user interface is composed of over 40 different widget types, from simple switches to complex interactive displays like the MSEG editor and oscillator waveform viewer. This chapter explores the widget architecture that makes it all work: base classes, component hierarchy, modulation visualization, custom drawing, and event handling.

The widget system is located in `/src/surge-xt/gui/widgets/` and contains approximately 19,000 lines of code implementing the visual controls that users interact with.

## 1. Widget Base Classes

### WidgetBaseMixin<T>

All Surge widgets inherit from `WidgetBaseMixin<T>`, a CRTP (Curiously Recurring Template Pattern) base class that provides common functionality:

```cpp
// From: src/surge-xt/gui/widgets/WidgetBaseMixin.h
template <typename T>
struct WidgetBaseMixin : public Surge::GUI::SkinConsumingComponent,
                         public Surge::GUI::IComponentTagValue
{
    WidgetBaseMixin(juce::Component *c) { c->setWantsKeyboardFocus(true); }
    inline T *asT() { return static_cast<T *>(this); }

    uint32_t tag{0};
    void setTag(uint32_t t) { tag = t; }
    uint32_t getTag() const override { return tag; }

    std::unordered_set<Surge::GUI::IComponentTagValue::Listener *> listeners;
    void addListener(Surge::GUI::IComponentTagValue::Listener *t) { listeners.insert(t); }

    void notifyValueChanged()
    {
        for (auto t : listeners)
            t->valueChanged(this);

        if (auto *handler = asT()->getAccessibilityHandler())
        {
            if (handler->getValueInterface())
            {
                handler->notifyAccessibilityEvent(juce::AccessibilityEvent::valueChanged);
            }
            updateAccessibleStateOnUserValueChange();
        }
    }

    void notifyBeginEdit()
    {
        for (auto t : listeners)
            t->controlBeginEdit(this);
    }

    void notifyEndEdit()
    {
        for (auto t : listeners)
            t->controlEndEdit(this);
    }
};
```

**Key Features:**

1. **Tag System**: Each widget has a unique tag identifying its parameter
2. **Listener Pattern**: Multiple listeners can observe value changes
3. **CRTP**: Type-safe downcasting via `asT()`
4. **Accessibility**: Automatic screen reader notifications
5. **Edit Lifecycle**: Begin/end edit notifications for automation

**Info Window Support:**

```cpp
void enqueueFutureInfowindow(SurgeGUIEditor::InfoQAction place,
                             const juce::Point<float> &fromPosition)
{
    if (place == SurgeGUIEditor::InfoQAction::START)
    {
        // Guard against duplicate start events from JUCE hierarchy changes
        if (enqueueStartPosition == fromPosition)
            return;
        enqueueStartPosition = fromPosition;
    }

    auto t = getTag();
    auto sge = firstListenerOfType<SurgeGUIEditor>();
    if (sge)
        sge->enqueueFutureInfowindow(t, asT()->getBounds(), place);
}

void showInfowindow(bool isEditingModulation)
{
    auto l = asT()->getBounds();
    auto t = getTag();
    auto sge = firstListenerOfType<SurgeGUIEditor>();
    if (sge)
        sge->showInfowindow(t, l, isEditingModulation);
}
```

### LongHoldMixin<T>

Touch-friendly long-hold gesture support:

```cpp
template <typename T> struct LongHoldMixin
{
    static constexpr uint32_t holdDelayTimeInMS = 1000;
    static constexpr uint32_t fingerMovementTolerancePx = 8;

    bool shouldLongHold()
    {
        if (asT()->storage)
            return GUI::isTouchMode(asT()->storage);
        return false;
    }

    void mouseDownLongHold(const juce::MouseEvent &e)
    {
        if (!shouldLongHold())
            return;

        startingHoldPosition = e.position.toFloat();

        timer = std::make_unique<LHCB>(this);
        timer->startTimer(holdDelayTimeInMS);
    }

    virtual void onLongHold()
    {
        juce::ModifierKeys k{0};
        asT()->notifyControlModifierClicked(k, true);  // Simulate right-click
    }

    juce::Point<float> startingHoldPosition;
    std::unique_ptr<juce::Timer> timer;
};
```

**Usage:**
- Detects 1-second finger hold
- Converts to right-click menu on touch devices
- Cancels if finger moves >8 pixels
- Used throughout for touch accessibility

### ModulatableControlInterface

Interface for widgets that support modulation:

```cpp
// From: src/surge-xt/gui/widgets/ModulatableControlInterface.h
struct ModulatableControlInterface
{
    virtual Surge::GUI::IComponentTagValue *asControlValueInterface() = 0;
    virtual juce::Component *asJuceComponent() = 0;

    // Parameter characteristics
    virtual void setIsSemitone(bool b) { isSemitone = b; }
    bool isSemitone{false};

    virtual void setBipolarFn(std::function<bool()> f) { isBipolarFn = f; }
    std::function<bool()> isBipolarFn{[]() { return false; }};

    // Modulation state
    enum ModulationState
    {
        UNMODULATED,              // No modulation applied
        MODULATED_BY_ACTIVE,      // Modulated by selected source
        MODULATED_BY_OTHER        // Modulated by other source(s)
    } modulationState{UNMODULATED};

    void setModulationState(ModulationState m) { modulationState = m; }

    void setIsEditingModulation(bool b) { isEditingModulation = b; }
    bool isEditingModulation{false};

    void setIsModulationBipolar(bool b) { isModulationBipolar = b; }
    bool isModulationBipolar{false};

    virtual void setModValue(float v) { modValue = v; }
    virtual float getModValue() const { return modValue; }
    float modValue{0.f};

    // Display value (may differ during fine control)
    virtual void setQuantitizedDisplayValue(float f) { quantizedDisplayValue = f; }
    float quantizedDisplayValue{0.f};

    // Tempo sync indicator
    virtual void setTempoSync(bool b) { isTemposync = b; }
    bool isTemposync{false};

    // Edit type tracking
    enum EditTypeWas
    {
        NOEDIT,
        DRAG,
        WHEEL,
        DOUBLECLICK,
    } editTypeWas{NOEDIT};
};
```

**Modulation States:**

1. **UNMODULATED**: Standard display, no modulation bars
2. **MODULATED_BY_ACTIVE**: Blue/orange bars for selected mod source
3. **MODULATED_BY_OTHER**: Gray indicator showing other modulations

## 2. Key Widget Types

### ModulatableSlider

The workhorse parameter control supporting both horizontal and vertical orientations:

```cpp
// From: src/surge-xt/gui/widgets/ModulatableSlider.h
struct ModulatableSlider : public juce::Component,
                           public WidgetBaseMixin<ModulatableSlider>,
                           public LongHoldMixin<ModulatableSlider>,
                           public ModulatableControlInterface
{
    ModulatableSlider();

    enum MoveRateState
    {
        kUnInitialized = 0,
        kLegacy,
        kSlow,
        kMedium,
        kExact
    };

    static MoveRateState sliderMoveRateState;  // Global preference

    ctrltypes parameterType{ct_none};
    Surge::ParamConfig::Orientation orientation;

    void setOrientation(Surge::ParamConfig::Orientation o) { orientation = o; }

    // Style options
    virtual void setIsLightStyle(bool b) { isLightStyle = b; }
    bool isLightStyle{false};

    virtual void setIsMiniVertical(bool b) { isMiniVertical = b; }
    bool isMiniVertical{false};

    void setAlwaysUseModHandle(bool b)
    {
        forceModHandle = b;
        repaint();
    }

    // Value management
    float value{0.f};
    float getValue() const override { return value; }
    void setValue(float f) override
    {
        value = f;
        repaint();
    }

    void paint(juce::Graphics &g) override;

    // Mouse handling
    void mouseDown(const juce::MouseEvent &event) override;
    void mouseDrag(const juce::MouseEvent &event) override;
    void mouseUp(const juce::MouseEvent &event) override;
    void mouseDoubleClick(const juce::MouseEvent &event) override;
    void mouseWheelMove(const juce::MouseEvent &event,
                        const juce::MouseWheelDetails &wheel) override;
};
```

**Paint Implementation:**

The `paint()` method demonstrates sophisticated modulation visualization:

```cpp
// From: src/surge-xt/gui/widgets/ModulatableSlider.cpp
void ModulatableSlider::paint(juce::Graphics &g)
{
    updateLocationState();  // Calculate handle positions

    // 1. Draw the tray (background)
    {
        juce::Graphics::ScopedSaveState gs(g);
        auto t = juce::AffineTransform();
        t = t.translated(-trayTypeX * trayw, -trayTypeY * trayh);

        g.addTransform(trayPosition);
        g.reduceClipRegion(0, 0, trayw, trayh);
        pTray->draw(g, activationOpacity, t);
    }

    // 2. Draw modulation bars
    if (isEditingModulation)
    {
        juce::Graphics::ScopedSaveState gs(g);

        g.addTransform(trayPosition);
        g.setColour(skin->getColor(Colors::Slider::Modulation::Positive));
        g.drawLine(handleCX, handleCY, handleMX, handleMY, 2);
        g.setColour(skin->getColor(Colors::Slider::Modulation::Negative));
        g.drawLine(handleCX, handleCY, barNMX, barNMY, 2);
    }

    // 3. Draw label
    if (drawLabel)
    {
        g.setFont(font);
        g.setColour(isLightStyle ?
            skin->getColor(Colors::Slider::Label::Light) :
            skin->getColor(Colors::Slider::Label::Dark));
        g.drawText(label, labelRect, juce::Justification::topRight);
    }

    // 4. Draw main handle
    {
        auto q = handleSize.withCentre(juce::Point<int>(handleCX, handleCY));
        auto moveTo = juce::AffineTransform().translated(q.getTopLeft());
        auto t = juce::AffineTransform().translated(-1, -1);

        if (forceModHandle)
            t = t.translated(-modHandleX, 0);

        g.addTransform(moveTo);
        g.reduceClipRegion(handleSize.expanded(2));
        pHandle->draw(g, activationOpacity, t);

        if (isHovered && pHandleHover)
            pHandleHover->draw(g, activationOpacity, t);

        if (pTempoSyncHandle && isTemposync)
            pTempoSyncHandle->draw(g, activationOpacity, t);
    }

    // 5. Draw modulation handle (when editing)
    if (isEditingModulation)
    {
        auto q = handleSize.withCentre(juce::Point<int>(handleMX, handleMY));
        // ... draw modulation handle ...
    }
}
```

**Location State Calculation:**

```cpp
void ModulatableSlider::updateLocationState()
{
    // Select tray type based on parameter characteristics
    trayTypeX = 0;
    trayTypeY = 0;

    if (orientation == ParamConfig::kHorizontal)
    {
        if (isSemitone)
            trayTypeY = 2;       // Semitone scale
        else if (isBipolarFn())
            trayTypeY = 1;       // Bipolar
        if (isLightStyle)
            trayTypeY += 3;      // Light background variant
    }

    // Select based on modulation state
    switch (modulationState)
    {
    case UNMODULATED:
        trayTypeX = 0;
        break;
    case MODULATED_BY_OTHER:
        trayTypeX = 1;
        break;
    case MODULATED_BY_ACTIVE:
        trayTypeX = 2;
        break;
    }

    // Calculate handle positions
    if (orientation == ParamConfig::kVertical)
    {
        trayw = 16;
        trayh = 75;
        range = isMiniVertical ? 39 : 56;

        handleCY = (1 - quantizedDisplayValue) * range + handleY0;
        handleMY = limit01(1 - (value + modValue)) * range + handleY0;
        barNMY = limit01(1 - (value - modValue)) * range + handleY0;
    }
    else  // Horizontal
    {
        trayw = 133;
        trayh = 14;
        range = 112;

        handleCX = range * quantizedDisplayValue + handleX0;
        handleMX = range * limit01(value + modValue) + handleX0;
        barNMX = range * limit01(value - modValue) + handleX0;
    }
}
```

**Mouse Dragging:**

```cpp
void ModulatableSlider::mouseDrag(const juce::MouseEvent &event)
{
    float distance = event.position.getX() - mouseDownFloatPosition.getX();
    if (orientation == ParamConfig::kVertical)
        distance = -(event.position.getY() - mouseDownFloatPosition.getY());

    float dDistance = distance - lastDistance;
    lastDistance = distance;

    editTypeWas = DRAG;

    // Calculate delta based on move rate
    float delta = 0;

    if (sliderMoveRateState == kExact)
    {
        delta = dDistance / range;
    }
    else if (sliderMoveRateState == kSlow)
    {
        delta = dDistance / (5.f * range);
    }
    else  // Legacy
    {
        delta = dDistance / (range * legacyMoveRate);
    }

    // Apply modifiers
    if (event.mods.isShiftDown())
        delta *= 0.1f;  // Fine control

    // Update value
    if (isEditingModulation)
        modValue = limit_range(modValueOnMouseDown + delta, -1.f, 1.f);
    else
        value = limit01(valueOnMouseDown + delta);

    notifyValueChanged();
}
```

### ModulationSourceButton

Modulation source selector with hamburger menu for LFO variants:

```cpp
// From: src/surge-xt/gui/widgets/ModulationSourceButton.h
struct ModulationSourceButton : public juce::Component,
                                public WidgetBaseMixin<ModulationSourceButton>,
                                public LongHoldMixin<ModulationSourceButton>
{
    typedef std::vector<std::tuple<modsources, int, std::string, std::string>> modlist_t;
    modlist_t modlist;  // Source, index, label, accessibleLabel
    int modlistIndex{0};

    modsources getCurrentModSource() const { return std::get<0>(modlist[modlistIndex]); }
    int getCurrentModIndex() const { return std::get<1>(modlist[modlistIndex]); }
    std::string getCurrentModLabel() const { return std::get<2>(modlist[modlistIndex]); }

    void setModList(const modlist_t &m)
    {
        modlist = m;
        modlistIndex = 0;

        // Restore from DAW state
        auto sge = firstListenerOfType<SurgeGUIEditor>();
        int lfo_id = getCurrentModSource() - ms_lfo1;
        lfo_id = std::clamp(lfo_id, 0, n_lfos - 1);

        modlistIndex = storage->getPatch()
            .dawExtraState.editor.modulationSourceButtonState[scene][lfo_id].index;
        modlistIndex = limit_range(modlistIndex, 0, (int)(m.size() - 1));
    }

    bool needsHamburger() const { return modlist.size() > 1; }

    // Button state
    int state{0};  // Bits: selected, armed, used
    void setState(int s) { state = s; }

    bool isMeta{false}, isBipolar{false};
    void setIsMeta(bool b) { isMeta = b; }
    void setIsBipolar(bool b);

    // Drag-to-modulate support
    enum MouseState
    {
        NONE,
        CLICK,
        CLICK_TOGGLE_ARM,
        CLICK_SELECT_ONLY,
        CLICK_ARROW,
        CTRL_CLICK,
        PREDRAG_VALUE,
        DRAG_VALUE,
        DRAG_COMPONENT_HAPPEN,
        HAMBURGER
    } mouseMode{NONE};

    juce::ComponentDragger componentDragger;
    void mouseDrag(const juce::MouseEvent &event) override;
};
```

**Paint Implementation:**

```cpp
void ModulationSourceButton::paint(juce::Graphics &g)
{
    auto labelFont = skin->fontManager->getLatoAtSize(7);

    // Background color based on state
    juce::Colour bgColor, fgColor, fontColor;

    if (state & 3)  // Selected or armed
    {
        if (state == 2)  // Armed
        {
            bgColor = skin->getColor(Colors::ModSource::Armed::Background);
            fgColor = skin->getColor(Colors::ModSource::Armed::Border);
            fontColor = skin->getColor(Colors::ModSource::Armed::Text);
        }
        else  // Selected
        {
            bgColor = skin->getColor(Colors::ModSource::Selected::Background);
            fgColor = skin->getColor(Colors::ModSource::Selected::Border);
            fontColor = skin->getColor(Colors::ModSource::Selected::Text);
        }
    }
    else if (isUsed)
    {
        bgColor = skin->getColor(Colors::ModSource::Used::Background);
        fgColor = skin->getColor(Colors::ModSource::Used::Border);
        fontColor = skin->getColor(Colors::ModSource::Used::Text);
    }
    else  // Unused
    {
        bgColor = skin->getColor(Colors::ModSource::Unused::Background);
        fgColor = skin->getColor(Colors::ModSource::Unused::Border);
        fontColor = skin->getColor(Colors::ModSource::Unused::Text);
    }

    // Draw button
    auto bounds = getLocalBounds().reduced(1);
    g.setColour(bgColor);
    g.fillRoundedRectangle(bounds.toFloat(), 2.5);
    g.setColour(fgColor);
    g.drawRoundedRectangle(bounds.toFloat(), 2.5, 1.0);

    // Draw label
    g.setFont(font.withHeight(7));
    g.setColour(fontColor);
    g.drawText(getCurrentModLabel(), bounds, juce::Justification::centred);

    // Draw hamburger menu icon if multiple sources
    if (needsHamburger())
    {
        arrow->drawAt(g, hamburgerHome.getTopLeft().toFloat(), 1.0);
    }

    // Draw tint overlay if active
    if (isTinted)
    {
        g.setColour(juce::Colour(255, 255, 255).withAlpha(0.15f));
        g.fillRoundedRectangle(bounds.toFloat(), 2.5);
    }
}
```

### Switch and MultiSwitch

**Switch**: Binary or multi-value toggle:

```cpp
// From: src/surge-xt/gui/widgets/Switch.h
struct Switch : public juce::Component,
                public WidgetBaseMixin<Switch>,
                public LongHoldMixin<Switch>
{
    bool iit{false};  // Is integer-valued (not just binary)
    bool isMultiIntegerValued() const { return iit; }
    void setIsMultiIntegerValued(bool b) { iit = b; }

    int iv{0}, im{1};
    void setIntegerValue(int i) { iv = i; }
    void setIntegerMax(int i) { im = i; }

    float value{0};
    float getValue() const override { return value; }
    void setValue(float f) override { value = f; }

    SurgeImage *switchD{nullptr}, *hoverSwitchD{nullptr};

    void mouseDown(const juce::MouseEvent &event) override
    {
        mouseDownLongHold(event);

        if (event.mods.isPopupMenu())
        {
            notifyControlModifierClicked(event.mods);
            return;
        }

        if (!isMultiIntegerValued())
        {
            // Toggle binary switch
            value = (value > 0.5) ? 0.0 : 1.0;
        }
        else
        {
            // Cycle through integer values
            iv = (iv + 1) % (im + 1);
            value = (float)iv / im;
        }

        notifyValueChanged();
        repaint();
    }
};
```

**MultiSwitch**: Grid-based selector:

```cpp
// From: src/surge-xt/gui/widgets/MultiSwitch.h
struct MultiSwitch : public juce::Component,
                     public WidgetBaseMixin<MultiSwitch>,
                     public LongHoldMixin<MultiSwitch>
{
    int rows{0}, columns{0}, heightOfOneImage{0}, frameOffset{0};

    void setRows(int x) { rows = x; }
    void setColumns(int x) { columns = x; }

    int valueToOff(float v)
    {
        return (int)(frameOffset + ((v * (float)(rows * columns - 1) + 0.5f)));
    }

    int coordinateToSelection(int x, int y) const
    {
        int row = y * rows / getHeight();
        int col = x * columns / getWidth();
        return row * columns + col;
    }

    float coordinateToValue(int x, int y) const
    {
        int sel = coordinateToSelection(x, y);
        return (float)sel / (rows * columns - 1);
    }

    void mouseDown(const juce::MouseEvent &event) override
    {
        float newValue = coordinateToValue(event.x, event.y);

        if (value != newValue)
        {
            value = newValue;
            notifyBeginEdit();
            notifyValueChanged();
            notifyEndEdit();
            repaint();
        }
    }

    bool draggable{false};
    void setDraggable(bool d) { draggable = d; }

    void mouseDrag(const juce::MouseEvent &event) override
    {
        if (!draggable)
            return;

        everDragged = true;
        float newValue = coordinateToValue(event.x, event.y);

        if (value != newValue)
        {
            value = newValue;
            notifyValueChanged();
            repaint();
        }
    }
};
```

**MultiSwitchSelfDraw**: Text-based variant:

```cpp
struct MultiSwitchSelfDraw : public MultiSwitch
{
    std::vector<std::string> labels;

    void paint(juce::Graphics &g) override
    {
        for (int r = 0; r < rows; ++r)
        {
            for (int c = 0; c < columns; ++c)
            {
                auto idx = r * columns + c;
                auto isOn = (idx == getIntegerValue());

                auto cellRect = juce::Rectangle<float>(
                    c * getWidth() / columns,
                    r * getHeight() / rows,
                    getWidth() / columns,
                    getHeight() / rows
                ).reduced(1);

                // Background
                if (isOn)
                    g.setColour(skin->getColor(Colors::MSwitchSelfDraw::ActiveFill));
                else if (isHovered && hoverSelection == idx)
                    g.setColour(skin->getColor(Colors::MSwitchSelfDraw::HoverFill));
                else
                    g.setColour(skin->getColor(Colors::MSwitchSelfDraw::InactiveFill));

                g.fillRoundedRectangle(cellRect, 3);

                // Border
                g.setColour(isOn ?
                    skin->getColor(Colors::MSwitchSelfDraw::ActiveBorder) :
                    skin->getColor(Colors::MSwitchSelfDraw::InactiveBorder));
                g.drawRoundedRectangle(cellRect, 3, 1);

                // Label
                if (idx < labels.size())
                {
                    g.setColour(isOn ?
                        skin->getColor(Colors::MSwitchSelfDraw::ActiveText) :
                        skin->getColor(Colors::MSwitchSelfDraw::InactiveText));
                    g.drawText(labels[idx], cellRect.toNearestInt(),
                              juce::Justification::centred);
                }
            }
        }
    }
};
```

### NumberField

Numeric value display with drag-to-edit:

```cpp
// From: src/surge-xt/gui/widgets/NumberField.h
struct NumberField : public juce::Component,
                     public WidgetBaseMixin<NumberField>,
                     public LongHoldMixin<NumberField>
{
    float value{0};
    int iValue{0}, iMin{0}, iMax{1};

    void setValue(float f) override
    {
        value = f;
        bounceToInt();
        repaint();
    }

    void bounceToInt()
    {
        iValue = Parameter::intUnscaledFromFloat(value, iMax, iMin);
    }

    Surge::Skin::Parameters::NumberfieldControlModes controlMode;

    void setControlMode(Surge::Skin::Parameters::NumberfieldControlModes n,
                        bool isExtended = false)
    {
        controlMode = n;
        extended = isExtended;
    }

    std::string valueToDisplay() const
    {
        switch (controlMode)
        {
        case Surge::Skin::Parameters::POLY_COUNT:
            return std::to_string(iValue);
        case Surge::Skin::Parameters::PATCH_BROWSER:
            return std::to_string(iValue) + " / " + std::to_string(iMax);
        case Surge::Skin::Parameters::LFO_LABEL:
            return "LFO " + std::to_string(iValue + 1);
        default:
            return std::to_string(iValue);
        }
    }

    void mouseDrag(const juce::MouseEvent &event) override
    {
        if (mouseMode != DRAG)
        {
            lastDistanceChecked = 0;
            mouseMode = DRAG;
            notifyBeginEdit();
        }

        auto distance = event.position.y - mouseDownOrigin.y;
        auto distanceDelta = distance - lastDistanceChecked;

        if (fabs(distanceDelta) > 10)
        {
            int inc = (distanceDelta > 0) ? -1 : 1;
            inc *= getChangeMultiplier(event);

            changeBy(inc);
            lastDistanceChecked = distance;
        }
    }

    void changeBy(int inc)
    {
        setIntValue(limit_range(iValue + inc, iMin, iMax));
    }
};
```

### OscillatorWaveformDisplay

Real-time waveform visualization (71KB implementation):

```cpp
// From: src/surge-xt/gui/widgets/OscillatorWaveformDisplay.h
struct OscillatorWaveformDisplay : public juce::Component,
                                   public Surge::GUI::SkinConsumingComponent,
                                   public LongHoldMixin<OscillatorWaveformDisplay>
{
    static constexpr float disp_pitch = 90.15f - 48.f;
    static constexpr int wtbheight = 12;
    static constexpr float scaleDownBy = 0.235;

    OscillatorStorage *oscdata{nullptr};
    int oscInScene{-1};
    int scene{-1};

    void setOscStorage(OscillatorStorage *s)
    {
        oscdata = s;
        scene = oscdata->p[0].scene - 1;
        oscInScene = oscdata->p[0].ctrlgroup_entry;
    }

    ::Oscillator *setupOscillator();
    unsigned char oscbuffer alignas(16)[oscillator_buffer_size];

    void paint(juce::Graphics &g) override
    {
        // Complex rendering based on oscillator type
        if (oscdata->type.val.i == ot_wavetable || oscdata->type.val.i == ot_window)
        {
            paintWavetable(g);
        }
        else
        {
            paintClassicOscillator(g);
        }

        // Draw wavetable navigation if applicable
        if (supportsWavetables())
        {
            paintWavetableControls(g);
        }
    }

    void paintWavetable(juce::Graphics &g)
    {
        // Render current wavetable frame
        auto *osc = setupOscillator();
        if (!osc)
            return;

        // Generate waveform at display pitch
        osc->init(disp_pitch, true, true);

        // Copy to display buffer
        std::vector<float> waveform(getWidth());
        for (int i = 0; i < getWidth(); ++i)
        {
            float phase = (float)i / getWidth();
            waveform[i] = osc->outputForDisplay(phase);
        }

        // Draw waveform path
        juce::Path path;
        float h = getHeight();
        float w = getWidth();

        path.startNewSubPath(0, h / 2 - waveform[0] * h * scaleDownBy);
        for (int i = 1; i < w; ++i)
        {
            path.lineTo(i, h / 2 - waveform[i] * h * scaleDownBy);
        }

        g.setColour(skin->getColor(Colors::Osc::Display::Wave));
        g.strokePath(path, juce::PathStrokeType(1.0f));
    }

    juce::Rectangle<float> leftJog, rightJog, waveTableName;

    void mouseDown(const juce::MouseEvent &event) override
    {
        if (leftJog.contains(event.position))
        {
            loadWavetable(oscdata->wt.current_id - 1);
        }
        else if (rightJog.contains(event.position))
        {
            loadWavetable(oscdata->wt.current_id + 1);
        }
        else if (waveTableName.contains(event.position))
        {
            showWavetableMenu();
        }
        else if (customEditorBox.contains(event.position))
        {
            toggleCustomEditor();
        }
    }
};
```

### LFOAndStepDisplay

Complex LFO/step sequencer editor (82KB implementation):

```cpp
// From: src/surge-xt/gui/widgets/LFOAndStepDisplay.h
struct LFOAndStepDisplay : public juce::Component,
                           public WidgetBaseMixin<LFOAndStepDisplay>,
                           public LongHoldMixin<LFOAndStepDisplay>
{
    LFOStorage *lfodata{nullptr};
    StepSequencerStorage *ss{nullptr};
    MSEGStorage *ms{nullptr};
    FormulaModulatorStorage *fs{nullptr};

    bool isStepSequencer() { return lfodata->shape.val.i == lt_stepseq; }
    bool isMSEG() { return lfodata->shape.val.i == lt_mseg; }
    bool isFormula() { return lfodata->shape.val.i == lt_formula; }

    void paint(juce::Graphics &g) override
    {
        if (isStepSequencer())
            paintStepSeq(g);
        else
            paintWaveform(g);

        paintTypeSelector(g);
    }

    void paintStepSeq(juce::Graphics &g)
    {
        // Draw step sequencer grid
        for (int i = 0; i < n_stepseqsteps; ++i)
        {
            auto &stepRect = steprect[i];
            auto &gateRect = gaterect[i];

            // Step value bar
            float val = ss->steps[i];
            bool isPositive = (val >= 0);

            g.setColour(skin->getColor(
                isPositive ? Colors::StepSeq::Step::Fill :
                             Colors::StepSeq::Step::FillNegative));

            auto barRect = stepRect;
            barRect.setHeight(stepRect.getHeight() * fabs(val));
            if (!isPositive)
                barRect.setY(stepRect.getCentreY());
            else
                barRect.setBottom(stepRect.getCentreY());

            g.fillRect(barRect);

            // Gate indicator
            bool gateOn = ss->trigmask & (UINT64_C(1) << i);
            g.setColour(gateOn ?
                skin->getColor(Colors::StepSeq::TriggerClick::Background) :
                skin->getColor(Colors::StepSeq::TriggerDefault::Background));
            g.fillRect(gateRect);

            // Loop markers
            if (i == ss->loop_start)
            {
                g.setColour(skin->getColor(Colors::StepSeq::Loop::Marker));
                g.drawLine(loopStartRect.getX(), loopStartRect.getY(),
                          loopStartRect.getX(), loopStartRect.getBottom(), 2);
            }
        }
    }

    void paintWaveform(juce::Graphics &g)
    {
        // Create LFO modulation source
        LFOModulationSource *lfoMs = new LFOModulationSource();
        populateLFOMS(lfoMs);
        lfoMs->attack();

        // Sample waveform
        int n_samples = waveform_display.getWidth();
        std::vector<float> samples(n_samples);

        for (int i = 0; i < n_samples; ++i)
        {
            lfoMs->process_block();
            samples[i] = lfoMs->get_output(0);
        }

        // Draw waveform
        juce::Path path;
        float h = waveform_display.getHeight();

        path.startNewSubPath(0, h * (1 - samples[0]) / 2);
        for (int i = 1; i < n_samples; ++i)
        {
            path.lineTo(i, h * (1 - samples[i]) / 2);
        }

        g.setColour(skin->getColor(Colors::LFO::Waveform::Wave));
        g.strokePath(path, juce::PathStrokeType(1.5f));

        delete lfoMs;
    }

    void paintTypeSelector(juce::Graphics &g)
    {
        // Draw LFO type icons
        for (int i = 0; i < n_lfo_types; ++i)
        {
            bool isSelected = (lfodata->shape.val.i == i);
            bool isHovered = (lfoTypeHover == i);

            auto &rect = shaperect[i];

            // Background
            if (isSelected)
                g.setColour(skin->getColor(Colors::LFO::Type::SelectedBackground));
            else if (isHovered)
                g.setColour(skin->getColor(Colors::LFO::Type::HoverBackground));
            else
                continue;  // No background for unselected

            g.fillRect(rect);

            // Icon
            int iconX = trayTypeX * typeImg->resourceWidth + i * iconWidth;
            int iconY = (isSelected || isHovered) ? iconHeight : 0;

            auto t = juce::AffineTransform().translated(-iconX, -iconY);
            if (isSelected || isHovered)
                typeImgHoverOn->draw(g, 1.0, t);
            else
                typeImg->draw(g, 1.0, t);
        }
    }

    enum DragMode
    {
        NONE,
        ARROW,
        LOOP_START,
        LOOP_END,
        RESET_VALUE,
        TRIGGERS,
        VALUES,
    } dragMode{NONE};

    void mouseDown(const juce::MouseEvent &event) override
    {
        // Check what was clicked
        for (int i = 0; i < n_lfo_types; ++i)
        {
            if (shaperect[i].contains(event.position.toInt()))
            {
                updateShapeTo(i);
                return;
            }
        }

        if (isStepSequencer())
        {
            for (int i = 0; i < n_stepseqsteps; ++i)
            {
                if (steprect[i].contains(event.position))
                {
                    dragMode = VALUES;
                    draggedStep = i;
                    setStepValue(event);
                    return;
                }

                if (gaterect[i].contains(event.position))
                {
                    dragMode = TRIGGERS;
                    draggedStep = i;
                    // Toggle trigger
                    ss->trigmask ^= (UINT64_C(1) << i);
                    stepSeqDirty();
                    return;
                }
            }
        }
    }
};
```

### PatchSelector

Patch browser with search and favorites (54KB implementation):

```cpp
// From: src/surge-xt/gui/widgets/PatchSelector.h
struct PatchSelector : public juce::Component,
                       public WidgetBaseMixin<PatchSelector>,
                       public TypeAhead::TypeAheadListener
{
    void setIDs(int category, int patch)
    {
        current_category = category;
        current_patch = patch;

        if (auto *handler = getAccessibilityHandler())
        {
            handler->notifyAccessibilityEvent(juce::AccessibilityEvent::valueChanged);
            handler->notifyAccessibilityEvent(juce::AccessibilityEvent::titleChanged);
        }
    }

    bool isFavorite{false}, isUser{false};
    std::string pname, category, author, comment;
    std::vector<SurgePatch::Tag> tags;

    void paint(juce::Graphics &g) override
    {
        // Background
        g.setColour(skin->getColor(Colors::PatchBrowser::Background));
        g.fillRect(getLocalBounds());

        // Patch name
        g.setFont(skin->fontManager->getLatoAtSize(9, juce::Font::bold));
        g.setColour(skin->getColor(Colors::PatchBrowser::Text));
        g.drawText(pname, nameBounds, juce::Justification::centredLeft);

        // Category
        g.setFont(skin->fontManager->getLatoAtSize(7));
        g.setColour(skin->getColor(Colors::PatchBrowser::TextHover));
        g.drawText(category, categoryBounds, juce::Justification::centredLeft);

        // Author
        if (!author.empty())
        {
            g.setColour(skin->getColor(Colors::PatchBrowser::TextHover));
            g.drawText("by " + author, authorBounds, juce::Justification::centredRight);
        }

        // Icons: favorite, user, search
        if (isFavorite)
        {
            // Draw star icon
            juce::Path star;
            // ... create star path ...
            g.setColour(skin->getColor(Colors::PatchBrowser::FavoriteIcon));
            g.fillPath(star);
        }

        if (isUser)
        {
            // Draw user badge
            g.setColour(skin->getColor(Colors::PatchBrowser::UserIcon));
            // ... draw user indicator ...
        }

        // Search icon
        g.setColour(searchHover ?
            skin->getColor(Colors::PatchBrowser::SearchIconHover) :
            skin->getColor(Colors::PatchBrowser::SearchIcon));
        // ... draw magnifying glass ...
    }

    // Type-ahead search support
    bool isTypeaheadSearchOn{false};
    std::unique_ptr<Surge::Widgets::TypeAhead> typeAhead;
    std::unique_ptr<PatchDBTypeAheadProvider> patchDbProvider;

    void toggleTypeAheadSearch(bool b)
    {
        isTypeaheadSearchOn = b;

        if (b)
        {
            // Show type-ahead overlay
            typeAhead = std::make_unique<Surge::Widgets::TypeAhead>(
                "Patch Search", patchDbProvider.get());
            typeAhead->addTypeAheadListener(this);
            addAndMakeVisible(*typeAhead);
        }
        else
        {
            typeAhead.reset();
        }
    }

    void itemSelected(int providerIndex, bool dontCloseTypeAhead) override
    {
        // Load selected patch
        loadPatch(providerIndex);

        if (!dontCloseTypeAhead)
            toggleTypeAheadSearch(false);
    }
};
```

### EffectChooser

FX slot selector with routing display:

```cpp
// From: src/surge-xt/gui/widgets/EffectChooser.h
struct EffectChooser : public juce::Component,
                       public WidgetBaseMixin<EffectChooser>,
                       public LongHoldMixin<EffectChooser>
{
    int currentEffect{0};
    std::array<int, n_fx_slots> fxTypes;

    void setEffectType(int index, int type)
    {
        fxTypes[index] = type;
        repaint();
    }

    int bypassState{0};
    int deactivatedBitmask{0};

    bool isBypassedOrDeactivated(int fxslot)
    {
        if (deactivatedBitmask & (1 << fxslot))
            return true;

        switch (bypassState)
        {
        case fxb_no_fx:
            return true;
        case fxb_no_sends:
            if (fxslot >= fxslot_send1 && fxslot <= fxslot_send4)
                return true;
            break;
        case fxb_scene_fx_only:
            if (fxslot >= fxslot_send1)
                return true;
            break;
        }
        return false;
    }

    void paint(juce::Graphics &g) override
    {
        // Draw scene labels
        for (int i = 0; i < n_scenes; ++i)
        {
            auto rect = getSceneRectangle(i);
            g.setColour(skin->getColor(Colors::Effect::Grid::SceneText));
            g.drawText(scenename[i], rect, juce::Justification::centred);
        }

        // Draw FX slots
        for (int i = 0; i < n_fx_slots; ++i)
        {
            auto rect = getEffectRectangle(i);

            bool isSelected = (i == currentEffect);
            bool isHovered = (i == currentHover);
            bool isBypassed = isBypassedOrDeactivated(i);

            juce::Colour bgcol, frcol, txtcol;
            getColorsForSlot(i, bgcol, frcol, txtcol);

            // Background
            g.setColour(bgcol);
            g.fillRoundedRectangle(rect.toFloat(), 2);

            // Border
            g.setColour(frcol);
            float borderWidth = isSelected ? 2.0f : 1.0f;
            g.drawRoundedRectangle(rect.toFloat(), 2, borderWidth);

            // Effect name
            std::string fxName = fx_type_names[fxTypes[i]];
            g.setColour(txtcol);
            g.drawText(fxName, rect, juce::Justification::centred);

            // Bypass indicator
            if (isBypassed)
            {
                g.setColour(juce::Colours::black.withAlpha(0.5f));
                g.fillRoundedRectangle(rect.toFloat(), 2);
            }
        }
    }

    juce::Rectangle<int> getEffectRectangle(int fx)
    {
        // Layout: 4 rows (A scene, A sends, B scene, B sends) x various columns
        int row = 0, col = 0;

        if (fx < fxslot_ains1)  // A scene FX
        {
            row = 0;
            col = fx;
        }
        else if (fx < fxslot_bins1)  // A sends
        {
            row = 1;
            col = fx - fxslot_ains1;
        }
        else if (fx < fxslot_send1)  // B scene FX
        {
            row = 2;
            col = fx - fxslot_bins1;
        }
        else  // Global sends
        {
            row = 3;
            col = fx - fxslot_send1;
        }

        return juce::Rectangle<int>(
            margin + col * (slotWidth + spacing),
            margin + row * (slotHeight + spacing),
            slotWidth,
            slotHeight
        );
    }
};
```

### WaveShaperSelector

Waveshaping curve selector with preview:

```cpp
// From: src/surge-xt/gui/widgets/WaveShaperSelector.h
struct WaveShaperSelector : public juce::Component,
                            public WidgetBaseMixin<WaveShaperSelector>,
                            public LongHoldMixin<WaveShaperSelector>
{
    sst::waveshapers::WaveshaperType iValue;

    // Pre-computed curves for display
    static std::array<std::vector<std::pair<float, float>>,
                      (int)sst::waveshapers::WaveshaperType::n_ws_types> wsCurves;

    void paint(juce::Graphics &g) override
    {
        // Background
        if (isWaveHovered && bgHover)
            bgHover->draw(g, 1.0);
        else if (bg)
            bg->draw(g, 1.0);

        // Draw waveshaping curve
        if (wsCurves[(int)iValue].empty())
        {
            // Generate curve samples
            for (int i = 0; i < 128; ++i)
            {
                float x = -1.0f + 2.0f * i / 127.0f;
                float y = sst::waveshapers::LUT(iValue, x);
                wsCurves[(int)iValue].push_back({x, y});
            }
        }

        auto &curve = wsCurves[(int)iValue];
        juce::Path path;

        for (size_t i = 0; i < curve.size(); ++i)
        {
            float x = (curve[i].first + 1) * 0.5f * waveArea.getWidth();
            float y = (1 - (curve[i].second + 1) * 0.5f) * waveArea.getHeight();

            if (i == 0)
                path.startNewSubPath(x, y);
            else
                path.lineTo(x, y);
        }

        g.setColour(skin->getColor(Colors::Waveshaper::Wave));
        g.strokePath(path, juce::PathStrokeType(1.5f));

        // Draw zero lines
        g.setColour(skin->getColor(Colors::Waveshaper::Grid).withAlpha(0.3f));
        g.drawLine(0, waveArea.getHeight() / 2,
                   waveArea.getWidth(), waveArea.getHeight() / 2);
        g.drawLine(waveArea.getWidth() / 2, 0,
                   waveArea.getWidth() / 2, waveArea.getHeight());

        // Label
        std::string name = sst::waveshapers::wst_names[(int)iValue];
        g.setColour(isLabelHovered ?
            skin->getColor(Colors::Waveshaper::TextHover) :
            skin->getColor(Colors::Waveshaper::Text));
        g.drawText(name, labelArea, juce::Justification::centred);
    }

    std::vector<int> intOrdering;  // Custom sort order

    float nextValueInOrder(float v, int inc)
    {
        int current = (int)iValue;

        if (intOrdering.empty())
        {
            // No custom order, use sequential
            current = (current + inc) % (int)sst::waveshapers::WaveshaperType::n_ws_types;
            if (current < 0)
                current += (int)sst::waveshapers::WaveshaperType::n_ws_types;
        }
        else
        {
            // Find current in ordering
            auto it = std::find(intOrdering.begin(), intOrdering.end(), current);
            if (it != intOrdering.end())
            {
                int idx = it - intOrdering.begin();
                idx = (idx + inc) % intOrdering.size();
                if (idx < 0)
                    idx += intOrdering.size();
                current = intOrdering[idx];
            }
        }

        return (float)current / ((int)sst::waveshapers::WaveshaperType::n_ws_types - 1);
    }
};
```

## 3. Modulation Visualization

### Color Coding

Modulation is visualized using a consistent color scheme:

- **Blue** (Positive): Modulation increases parameter value
- **Orange** (Negative): Modulation decreases parameter value
- **Gray**: Parameter has modulation from inactive sources

```cpp
// From skin color definitions
Colors::Slider::Modulation::Positive  // Blue: #18A0FB
Colors::Slider::Modulation::Negative  // Orange: #FF6B3F
```

### Modulation Bar Rendering

```cpp
void ModulatableSlider::paint(juce::Graphics &g)
{
    if (isEditingModulation)
    {
        // Draw positive modulation (value to value+mod)
        g.setColour(skin->getColor(Colors::Slider::Modulation::Positive));
        g.drawLine(handleCX, handleCY, handleMX, handleMY, 2);

        // Draw negative modulation (value to value-mod) if bipolar
        if (isModulationBipolar)
        {
            g.setColour(skin->getColor(Colors::Slider::Modulation::Negative));
            g.drawLine(handleCX, handleCY, barNMX, barNMY, 2);
        }
    }

    // For force-modulation (alternate mod handle display)
    if (forceModHandle)
    {
        g.setColour(skin->getColor(Colors::Slider::Modulation::Positive));
        g.drawLine(barFM0X, barFM0Y, handleMX, handleMY, 2);

        if (isModulationBipolar)
        {
            g.setColour(skin->getColor(Colors::Slider::Modulation::Negative));
            g.drawLine(barFM0X, barFM0Y, barFMNX, barFMNY, 2);
        }
    }
}
```

### Real-Time Updates

Modulation display updates in real-time during:

1. **Modulation editing**: Dragging mod handle
2. **LFO playback**: Value changes from modulation source
3. **Envelope stages**: Attack/decay/release visualization

```cpp
// In SurgeGUIEditor::idle()
void SurgeGUIEditor::idle()
{
    // Update all modulatable controls
    for (auto [tag, control] : allControls)
    {
        if (auto *mc = dynamic_cast<ModulatableControlInterface*>(control))
        {
            // Get current modulation value
            float modValue = 0;
            if (isModulationBeingEdited())
            {
                int modidx = synth->getModulationDepth(tag, modsource);
                modValue = synth->getModulationValue01(tag, modsource, modidx);
            }

            mc->setModValue(modValue);

            // Update modulation state
            bool hasModulation = synth->isModulated(tag);
            bool isActiveSource = hasModulation &&
                                 (modsource == currentModSource);

            mc->setModulationState(hasModulation, isActiveSource);
        }
    }
}
```

### Multiple Modulation Display

When a parameter has multiple modulation sources:

```cpp
// Tray types encode modulation state
enum TrayType
{
    UNMODULATED = 0,
    MODULATED_BY_OTHER = 1,    // Gray indicator
    MODULATED_BY_ACTIVE = 2    // Colored indicator
};

// The tray image contains 3 columns for each state
trayTypeX = 0;  // UNMODULATED
trayTypeX = 1;  // MODULATED_BY_OTHER (subtle indicator)
trayTypeX = 2;  // MODULATED_BY_ACTIVE (prominent)

// Tray is rendered with offset based on state
auto t = juce::AffineTransform().translated(-trayTypeX * trayw, -trayTypeY * trayh);
pTray->draw(g, activationOpacity, t);
```

## 4. Custom Drawing

### Paint Method Pattern

All widgets override `paint()` from `juce::Component`:

```cpp
void paint(juce::Graphics &g) override
{
    // 1. Save graphics state
    juce::Graphics::ScopedSaveState gs(g);

    // 2. Set up transformations
    g.addTransform(offset);

    // 3. Clip to bounds
    g.reduceClipRegion(bounds);

    // 4. Draw background
    g.setColour(backgroundColor);
    g.fillRect(bounds);

    // 5. Draw content (text, shapes, images)
    drawContent(g);

    // 6. Draw overlays (hover, selection)
    if (isHovered)
        drawHoverOverlay(g);
}
```

### SVG Integration

Surge uses SVG for scalable icons:

```cpp
// From widget initialization
std::unique_ptr<juce::Drawable> icon;

void onSkinChanged() override
{
    // Load SVG from skin resources
    auto svgText = skin->getResourceAsString("icon_name.svg");
    icon = juce::Drawable::createFromSVG(
        *juce::XmlDocument::parse(svgText));
}

void paint(juce::Graphics &g) override
{
    if (icon)
    {
        // Draw at specific location and size
        icon->drawAt(g, iconPosition.x, iconPosition.y, 1.0);

        // Or with transformation
        juce::AffineTransform transform;
        transform = transform.scaled(scale)
                            .translated(position);
        icon->draw(g, 1.0, transform);
    }
}
```

### Skin Integration

Widgets automatically respond to skin changes:

```cpp
void onSkinChanged() override
{
    // Load images from skin
    if (orientation == ParamConfig::kHorizontal)
    {
        pTray = associatedBitmapStore->getImage(IDB_SLIDER_HORIZ_BG);
        pHandle = associatedBitmapStore->getImage(IDB_SLIDER_HORIZ_HANDLE);
        pHandleHover = associatedBitmapStore->getImageByStringID(
            skin->hoverImageIdForResource(IDB_SLIDER_HORIZ_HANDLE, GUI::Skin::HOVER));
    }
    else
    {
        pTray = associatedBitmapStore->getImage(IDB_SLIDER_VERT_BG);
        pHandle = associatedBitmapStore->getImage(IDB_SLIDER_VERT_HANDLE);
        pHandleHover = associatedBitmapStore->getImageByStringID(
            skin->hoverImageIdForResource(IDB_SLIDER_VERT_HANDLE, GUI::Skin::HOVER));
    }

    // Get colors from skin
    labelColor = skin->getColor(Colors::Slider::Label::Dark);

    // Get skin-specific properties
    if (skinControl)
    {
        auto hideLabel = skin->propertyValue(
            skinControl, Surge::Skin::Component::HIDE_SLIDER_LABEL, "");
        if (hideLabel == "true")
            drawLabel = false;
    }

    repaint();
}
```

### Path-Based Drawing

Complex shapes use `juce::Path`:

```cpp
void drawModulationIndicator(juce::Graphics &g)
{
    juce::Path triangle;

    // Create triangle pointing to modulated handle
    triangle.startNewSubPath(x, y);
    triangle.lineTo(x + width, y);
    triangle.lineTo(x + width/2, y + height);
    triangle.closeSubPath();

    g.setColour(modulationColor);
    g.fillPath(triangle);

    // Outline
    g.strokePath(triangle, juce::PathStrokeType(1.0f));
}

void drawWaveform(juce::Graphics &g, const std::vector<float> &samples)
{
    juce::Path waveform;

    float h = getHeight();
    float w = getWidth();

    waveform.startNewSubPath(0, h/2 - samples[0] * h/2);
    for (size_t i = 1; i < samples.size(); ++i)
    {
        float x = i * w / samples.size();
        float y = h/2 - samples[i] * h/2;
        waveform.lineTo(x, y);
    }

    // Anti-aliased stroke
    g.strokePath(waveform, juce::PathStrokeType(1.5f));
}
```

## 5. Event Handling

### Mouse Events

Standard JUCE mouse event handling:

```cpp
void mouseDown(const juce::MouseEvent &event) override
{
    // Check for long-hold gesture (touch)
    mouseDownLongHold(event);

    // Right-click menu
    if (event.mods.isPopupMenu())
    {
        notifyControlModifierClicked(event.mods);
        return;
    }

    // Middle-click for JUCE component movement (debugging)
    if (forwardedMainFrameMouseDowns(event))
        return;

    // Begin edit
    valueOnMouseDown = value;
    modValueOnMouseDown = modValue;
    mouseDownFloatPosition = event.position;
    lastDistance = 0;

    notifyBeginEdit();
}

void mouseDrag(const juce::MouseEvent &event) override
{
    // Calculate drag distance
    float distance = event.position.getX() - mouseDownFloatPosition.getX();
    if (orientation == ParamConfig::kVertical)
        distance = -(event.position.getY() - mouseDownFloatPosition.getY());

    float dDistance = distance - lastDistance;
    lastDistance = distance;

    // Apply sensitivity modifiers
    float delta = dDistance / range;
    if (event.mods.isShiftDown())
        delta *= 0.1f;  // Fine control
    if (event.mods.isCommandDown())
        delta *= 0.05f;  // Ultra-fine

    // Update value
    if (isEditingModulation)
        modValue = limit_range(modValueOnMouseDown + delta, -1.f, 1.f);
    else
        value = limit01(valueOnMouseDown + delta);

    notifyValueChanged();
}

void mouseUp(const juce::MouseEvent &event) override
{
    mouseUpLongHold(event);
    notifyEndEdit();

    // Reset unbounded mouse movement
    if (!Surge::GUI::showCursor(storage))
    {
        juce::Desktop::getInstance().getMainMouseSource()
            .enableUnboundedMouseMovement(false);
    }
}

void mouseDoubleClick(const juce::MouseEvent &event) override
{
    // Reset to default
    editTypeWas = DOUBLECLICK;
    notifyControlModifierDoubleClicked(event.mods);
}

void mouseWheelMove(const juce::MouseEvent &event,
                    const juce::MouseWheelDetails &wheel) override
{
    // Accumulate small wheel movements
    int inc = wheelAccumulationHelper.accumulate(wheel, false, true);

    if (inc == 0)
        return;

    editTypeWas = WHEEL;

    // Apply increment
    float delta = inc * 0.01f;  // 1% per notch
    if (event.mods.isShiftDown())
        delta *= 0.1f;

    notifyBeginEdit();
    value = limit01(value + delta);
    notifyValueChanged();
    notifyEndEdit();
}
```

### Keyboard Support

Full keyboard navigation and control:

```cpp
bool keyPressed(const juce::KeyPress &key) override
{
    // Arrow keys
    if (key.isKeyCode(juce::KeyPress::upKey) ||
        key.isKeyCode(juce::KeyPress::rightKey))
    {
        float delta = 0.01f;
        if (key.getModifiers().isShiftDown())
            delta = 0.001f;

        value = limit01(value + delta);
        notifyValueChangedWithBeginEnd();
        return true;
    }

    if (key.isKeyCode(juce::KeyPress::downKey) ||
        key.isKeyCode(juce::KeyPress::leftKey))
    {
        float delta = 0.01f;
        if (key.getModifiers().isShiftDown())
            delta = 0.001f;

        value = limit01(value - delta);
        notifyValueChangedWithBeginEnd();
        return true;
    }

    // Home/End for min/max
    if (key.isKeyCode(juce::KeyPress::homeKey))
    {
        value = 0.0f;
        notifyValueChangedWithBeginEnd();
        return true;
    }

    if (key.isKeyCode(juce::KeyPress::endKey))
    {
        value = 1.0f;
        notifyValueChangedWithBeginEnd();
        return true;
    }

    // Enter for type-in
    if (key.isKeyCode(juce::KeyPress::returnKey))
    {
        auto sge = firstListenerOfType<SurgeGUIEditor>();
        if (sge)
            sge->promptForUserValueEntry(this);
        return true;
    }

    // Delete for default
    if (key.isKeyCode(juce::KeyPress::deleteKey) ||
        key.isKeyCode(juce::KeyPress::backspaceKey))
    {
        notifyControlModifierDoubleClicked(juce::ModifierKeys());
        return true;
    }

    return false;
}
```

### Focus Management

Visual feedback for keyboard focus:

```cpp
void focusGained(juce::Component::FocusChangeType cause) override
{
    startHover(getBounds().getBottomLeft().toFloat());
    repaint();
}

void focusLost(juce::Component::FocusChangeType cause) override
{
    endHover();
    repaint();
}

void paint(juce::Graphics &g) override
{
    // ... normal rendering ...

    // Draw focus indicator
    if (hasKeyboardFocus(true))
    {
        g.setColour(skin->getColor(Colors::Focus::Ring));
        g.drawRect(getLocalBounds(), 2);
    }
}
```

### Hover State

Info window and visual feedback:

```cpp
void mouseEnter(const juce::MouseEvent &event) override
{
    startHover(event.position);
}

void startHover(const juce::Point<float> &p) override
{
    // Queue info window to appear
    enqueueFutureInfowindow(SurgeGUIEditor::InfoQAction::START, p);

    isHovered = true;

    // Notify editor for modulation routing highlight
    auto sge = firstListenerOfType<SurgeGUIEditor>();
    if (sge)
        sge->sliderHoverStart(getTag());

    repaint();
}

void mouseExit(const juce::MouseEvent &event) override
{
    endHover();
}

void endHover() override
{
    if (stuckHover)  // Info window is pinned
        return;

    enqueueFutureInfowindow(SurgeGUIEditor::InfoQAction::LEAVE);

    isHovered = false;

    auto sge = firstListenerOfType<SurgeGUIEditor>();
    if (sge)
        sge->sliderHoverEnd(getTag());

    repaint();
}
```

## 6. Creating Custom Widgets

### Subclassing Pattern

```cpp
// 1. Define your widget class
struct MyCustomWidget : public juce::Component,
                        public WidgetBaseMixin<MyCustomWidget>,
                        public LongHoldMixin<MyCustomWidget>
{
    // Constructor must initialize base
    MyCustomWidget() : juce::Component(), WidgetBaseMixin<MyCustomWidget>(this)
    {
        setRepaintsOnMouseActivity(true);  // Auto-repaint on hover
    }

    // Required: getValue/setValue
    float value{0.f};
    float getValue() const override { return value; }
    void setValue(float f) override
    {
        value = f;
        repaint();
    }

    // Required: paint
    void paint(juce::Graphics &g) override
    {
        // Your rendering code
        g.setColour(skin->getColor(Colors::MyWidget::Background));
        g.fillRect(getLocalBounds());

        // Draw value indicator
        float y = getHeight() * (1 - value);
        g.setColour(skin->getColor(Colors::MyWidget::Indicator));
        g.fillRect(0, y, getWidth(), 2);
    }

    // Optional: mouse handling
    void mouseDown(const juce::MouseEvent &event) override
    {
        mouseDownLongHold(event);  // Support touch

        if (event.mods.isPopupMenu())
        {
            notifyControlModifierClicked(event.mods);
            return;
        }

        notifyBeginEdit();
        // ... handle click ...
    }

    void mouseDrag(const juce::MouseEvent &event) override
    {
        mouseDragLongHold(event);  // Cancel long-hold if dragged

        // Update value from drag
        float newValue = 1.0f - (event.position.y / getHeight());
        value = limit01(newValue);

        notifyValueChanged();
    }

    void mouseUp(const juce::MouseEvent &event) override
    {
        mouseUpLongHold(event);
        notifyEndEdit();
    }

    // Optional: skin integration
    SurgeImage *background{nullptr};

    void onSkinChanged() override
    {
        background = associatedBitmapStore->getImage(IDB_MY_WIDGET_BG);
        repaint();
    }

    // Optional: accessibility
    std::unique_ptr<juce::AccessibilityHandler> createAccessibilityHandler() override
    {
        return std::make_unique<juce::AccessibilityHandler>(
            *this,
            juce::AccessibilityRole::slider,
            juce::AccessibilityActions()
                .addAction(juce::AccessibilityActionType::press, [this]() {
                    // Handle activation
                })
                .addAction(juce::AccessibilityActionType::showMenu, [this]() {
                    notifyControlModifierClicked(juce::ModifierKeys(), true);
                }),
            juce::AccessibilityHandler::Interfaces{
                std::make_unique<AccessibleValue>(this)
            });
    }
};
```

### Integration with SurgeGUIEditor

```cpp
// In SurgeGUIEditor.h
std::unique_ptr<MyCustomWidget> myWidget;

// In SurgeGUIEditor.cpp
void SurgeGUIEditor::createWidgets()
{
    // Create widget
    auto skinCtrl = currentSkin->componentById("my.widget");
    myWidget = std::make_unique<MyCustomWidget>();

    // Configure
    myWidget->setSkin(currentSkin, associatedBitmapStore);
    myWidget->setStorage(this->synth->storage);
    myWidget->setTag(tag_my_widget);
    myWidget->addListener(this);

    // Position from skin
    auto r = skinCtrl->getRect();
    myWidget->setBounds(r.x, r.y, r.w, r.h);

    // Add to frame
    frame->addAndMakeVisible(*myWidget);
}

// Handle value changes
int32_t SurgeGUIEditor::controlModifierClicked(
    Surge::GUI::IComponentTagValue *control,
    const juce::ModifierKeys &mods,
    bool isDoubleClickEvent)
{
    if (control->getTag() == tag_my_widget)
    {
        if (isDoubleClickEvent)
        {
            // Reset to default
            myWidget->setValue(0.5f);
            return 1;
        }

        if (mods.isRightButtonDown())
        {
            // Show context menu
            juce::PopupMenu menu;
            // ... build menu ...
            menu.showMenuAsync(popupMenuOptions(myWidget.get()));
            return 1;
        }
    }

    return 0;
}
```

### Template for Modulatable Widget

```cpp
struct MyModulatableWidget : public juce::Component,
                              public WidgetBaseMixin<MyModulatableWidget>,
                              public LongHoldMixin<MyModulatableWidget>,
                              public ModulatableControlInterface
{
    MyModulatableWidget() : juce::Component(),
                            WidgetBaseMixin<MyModulatableWidget>(this) {}

    // Implement ModulatableControlInterface
    Surge::GUI::IComponentTagValue *asControlValueInterface() override { return this; }
    juce::Component *asJuceComponent() override { return this; }

    float value{0.f};
    float getValue() const override { return value; }
    void setValue(float f) override
    {
        value = f;
        repaint();
    }

    void paint(juce::Graphics &g) override
    {
        // Base rendering
        drawBackground(g);

        // Modulation visualization
        if (isEditingModulation)
        {
            // Draw mod depth indicator
            float modPos = value + modValue;

            g.setColour(skin->getColor(Colors::Slider::Modulation::Positive));
            drawModulationBar(g, value, modPos);

            if (isModulationBipolar)
            {
                float negPos = value - modValue;
                g.setColour(skin->getColor(Colors::Slider::Modulation::Negative));
                drawModulationBar(g, value, negPos);
            }
        }

        // Value indicator
        drawValueIndicator(g, quantizedDisplayValue);
    }

    void mouseDrag(const juce::MouseEvent &event) override
    {
        float delta = calculateDelta(event);

        if (isEditingModulation)
        {
            modValue = limit_range(modValue + delta, -1.f, 1.f);
        }
        else
        {
            value = limit01(value + delta);
        }

        notifyValueChanged();
    }
};
```

## Summary

The Surge XT widget system provides a comprehensive framework for building interactive musical interfaces:

**Base Architecture:**
- `WidgetBaseMixin<T>` for common functionality
- `ModulatableControlInterface` for modulation support
- `LongHoldMixin<T>` for touch-friendly gestures

**40+ Widget Types:**
- Parameter controls (ModulatableSlider, Switch, MultiSwitch, NumberField)
- Displays (OscillatorWaveformDisplay, LFOAndStepDisplay, VuMeter)
- Navigation (PatchSelector, EffectChooser, WaveShaperSelector)
- Modulation (ModulationSourceButton)

**Visual Sophistication:**
- Real-time modulation visualization (blue/orange bars)
- Skin-based theming with SVG support
- Hardware-accelerated rendering via JUCE
- Responsive hover and focus states

**Interaction Excellence:**
- Mouse, keyboard, and touch support
- Info windows with parameter details
- Accessibility for screen readers
- Unbounded mouse movement for precise control

The widget system demonstrates how to build production-quality audio UIs: combining low-level graphics rendering with high-level abstractions, supporting multiple input modalities, and maintaining visual consistency across 40+ different control types.
