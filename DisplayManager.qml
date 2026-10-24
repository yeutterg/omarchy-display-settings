import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons
import "DisplayModel.js" as DisplayModel

Panel {
  id: root
  moduleName: "io.github.yeutterg.display-settings"
  manageIpc: false

  property var displays: []
  property int selectedIndex: 0
  property bool loading: false
  property bool applying: false
  property bool undoAvailable: false
  property string undoKind: ""
  property string undoBrightnessName: ""
  property int undoBrightnessValue: -1
  property var queuedDisplayConfig: null
  property string statusMessage: ""
  property string refreshMessage: ""
  property string helperPath: Quickshell.env("HOME") + "/.config/omarchy/plugins/" + moduleName + "/bin/display-manager"

  property var brightnessByDisplay: ({})
  property var brightnessQueue: []
  property string brightnessInFlight: ""
  property string focusedMonitor: ""
  property real wheelAccumulator: 0
  property bool arrangementExpanded: false
  property var detailsExpandedByDisplay: ({})
  property bool nightLightExpanded: false
  property bool nightLightLoaded: false
  property int nightLightTemperature: 6500
  property int nightLightPreferredTemperature: 4000
  property bool nightLightSetQueued: false
  property int nightLightQueuedTemperature: 4000
  property bool nightLightScheduleLoaded: false
  property bool nightLightScheduleEnabled: false
  property string nightLightScheduleStart: "20:00"
  property string nightLightScheduleEnd: "07:00"
  property bool nightLightScheduleSaving: false
  property bool nightLightScheduleQueued: false

  readonly property var scalePresets: [1, 1.25, 1.6, 2, 3, 4]
  readonly property bool nightLightEnabled: nightLightLoaded && nightLightTemperature < 6000

  readonly property var selectedDisplay: displays.length && selectedIndex < displays.length ? displays[selectedIndex] : null
  readonly property int activeCount: displays.filter(function(d) { return !d.disabled }).length
  readonly property bool overlappingLayout: DisplayModel.hasOverlap(displays)
  readonly property bool connectedLayout: DisplayModel.isConnected(displays)
  readonly property bool validLayout: activeCount > 0 && !overlappingLayout && connectedLayout

  function parseOutput(text) {
    try { return JSON.parse(String(text || "")) } catch (e) { return null }
  }

  function processError(text, fallback) {
    var parsed = parseOutput(text)
    return parsed && parsed.error ? parsed.error : fallback
  }

  function refresh(message) {
    refreshBrightness()
    refreshNightLight()
    refreshNightLightSchedule()
    refreshUndoState()
    if (stateProc.running) {
      if (message) refreshMessage = message
      return
    }
    refreshMessage = message || ""
    loading = true
    stateProc.command = [helperPath, "state"]
    stateProc.running = true
  }

  function brightnessFor(name) {
    var entry = brightnessByDisplay[String(name || "")]
    return entry && entry.available ? Number(entry.value) : -1
  }

  function updateBrightness(name, value, available) {
    var next = Object.assign({}, brightnessByDisplay)
    next[name] = { value: Number(value), available: available === true }
    brightnessByDisplay = next
  }

  function refreshBrightness() {
    if (!brightnessStateProc.running) {
      brightnessStateProc.command = [helperPath, "brightness-state"]
      brightnessStateProc.running = true
    }
  }

  function refreshNightLight() {
    if (!nightLightStatusProc.running) {
      nightLightStatusProc.command = ["omarchy-toggle-nightlight", "--status"]
      nightLightStatusProc.running = true
    }
  }

  function refreshNightLightSchedule() {
    if (!nightLightScheduleStateProc.running) {
      nightLightScheduleStateProc.command = [helperPath, "night-light-schedule-state"]
      nightLightScheduleStateProc.running = true
    }
  }

  function validTime(value) {
    return /^([01][0-9]|2[0-3]):[0-5][0-9]$/.test(String(value || ""))
  }

  function saveNightLightSchedule() {
    if (!validTime(nightLightScheduleStart) || !validTime(nightLightScheduleEnd)
        || nightLightScheduleStart === nightLightScheduleEnd) {
      statusMessage = "Choose two different times in HH:MM format"
      return
    }
    if (nightLightScheduleSetProc.running) {
      nightLightScheduleQueued = true
      return
    }
    nightLightScheduleSaving = true
    nightLightScheduleSetProc.command = [helperPath, "night-light-schedule-set", JSON.stringify({
      enabled: nightLightScheduleEnabled,
      start: nightLightScheduleStart,
      end: nightLightScheduleEnd,
      temperature: nightLightPreferredTemperature
    })]
    nightLightScheduleSetProc.running = true
  }

  function setNightLightScheduleEnabled(enabled) {
    nightLightScheduleEnabled = enabled
    saveNightLightSchedule()
  }

  function setNightLightScheduleTime(key, value) {
    var time = String(value || "").trim()
    if (!validTime(time)) {
      statusMessage = "Use HH:MM, for example 20:00"
      return false
    }
    if (key === "start") nightLightScheduleStart = time
    else nightLightScheduleEnd = time
    saveNightLightSchedule()
    return true
  }

  function startNightLightSet(temperature) {
    var target = Math.round(Number(temperature))
    nightLightSetProc.command = [helperPath, "night-light-set", String(target)]
    nightLightSetProc.running = true
  }

  function applyNightLightTemperature(temperature) {
    var target = Math.max(1600, Math.min(6500, Math.round(Number(temperature) / 100) * 100))
    nightLightTemperature = target
    nightLightLoaded = true
    if (target < 6000) nightLightPreferredTemperature = Math.min(5500, target)
    if (nightLightSetProc.running) {
      nightLightQueuedTemperature = target
      nightLightSetQueued = true
      return
    }
    startNightLightSet(target)
  }

  function setNightLightEnabled(enabled) {
    applyNightLightTemperature(enabled ? nightLightPreferredTemperature : 6500)
  }

  function setNightLightTemperature(temperature) {
    var target = Math.max(1600, Math.min(5500, Math.round(Number(temperature) / 100) * 100))
    nightLightPreferredTemperature = target
    applyNightLightTemperature(target)
    if (nightLightScheduleEnabled) saveNightLightSchedule()
  }

  function startNextBrightnessSet() {
    if (setBrightnessProc.running || brightnessQueue.length === 0) return
    var queue = brightnessQueue.slice()
    var next = queue.shift()
    brightnessQueue = queue
    brightnessInFlight = next.name
    setBrightnessProc.command = ["omarchy-brightness-display", "--no-osd", "--monitor", next.name, next.value + "%"]
    setBrightnessProc.running = true
  }

  function setBrightnessFor(name, value, recordUndo) {
    if (!name) return
    var percent = Math.max(1, Math.min(100, Math.round(Number(value))))
    var previous = brightnessFor(name)
    if (recordUndo !== false && previous >= 0 && Math.round(previous) !== percent) {
      undoKind = "brightness"
      undoBrightnessName = name
      undoBrightnessValue = Math.round(previous)
      undoAvailable = true
    }
    updateBrightness(name, percent, true)
    var queue = brightnessQueue.filter(function(item) { return item.name !== name })
    queue.push({ name: name, value: percent })
    brightnessQueue = queue
    startNextBrightnessSet()
  }

  function displayIndex(name) {
    for (var i = 0; i < displays.length; i++) if (displays[i].name === name) return i
    return -1
  }

  function displayLabelForConnector(name) {
    var index = displayIndex(name)
    return index >= 0 ? DisplayModel.friendlyName(displays[index]) : name
  }

  function scaleOptions(display) {
    if (!display) return []
    var valid = DisplayModel.validScales(display.mode)
    var result = scalePresets.filter(function(value) {
      return valid.indexOf(value) >= 0
    })
    var current = Number(display.scale)
    if (isFinite(current) && result.indexOf(current) < 0 && valid.indexOf(current) >= 0) {
      result.push(current)
      result.sort(function(left, right) { return left - right })
    }
    return result
  }

  function scaleLabel(value) {
    return String(Math.round(Number(value) * 100) / 100) + "x"
  }

  function detailsExpandedFor(name) {
    return detailsExpandedByDisplay[String(name || "")] === true
  }

  function toggleDetailsFor(name) {
    var key = String(name || "")
    var next = Object.assign({}, detailsExpandedByDisplay)
    next[key] = next[key] !== true
    detailsExpandedByDisplay = next
  }

  function refreshUndoState() {
    if (!undoStateProc.running) {
      undoStateProc.command = [helperPath, "undo-state"]
      undoStateProc.running = true
    }
  }

  function commitDisplayChange(copy) {
    displays = copy
    var active = copy.filter(function(display) { return !display.disabled }).length
    if (active === 0 || DisplayModel.hasOverlap(copy) || !DisplayModel.isConnected(copy)) return
    queuedDisplayConfig = DisplayModel.normalizePositions(copy)
    statusMessage = applyProc.running ? "Applying latest changes…" : "Applying…"
    autoApplyTimer.restart()
  }

  function startAutoApply() {
    if (applyProc.running || queuedDisplayConfig === null) return
    var config = queuedDisplayConfig
    queuedDisplayConfig = null
    applying = true
    statusMessage = "Applying…"
    applyProc.command = [helperPath, "apply", JSON.stringify(config)]
    applyProc.running = true
  }

  function updateDisplayAt(index, key, value) {
    if (index < 0 || index >= displays.length) return
    var copy = DisplayModel.clone(displays)
    copy[index][key] = value
    if (key === "mode") {
      var scales = DisplayModel.validScales(value)
      if (scales.indexOf(Number(copy[index].scale)) < 0) copy[index].scale = scales[0]
    }
    var needsAttachment = key === "mode" || key === "scale" || key === "transform"
      || (key === "disabled" && value === false) || (key === "mirror" && value === "")
    if (needsAttachment && !copy[index].disabled && !copy[index].mirror) {
      var attached = DisplayModel.snapPosition(copy, index, copy[index].x, copy[index].y, 24)
      copy[index].x = attached.x
      copy[index].y = attached.y
    }
    commitDisplayChange(copy)
  }

  function updateDisplay(key, value) { updateDisplayAt(selectedIndex, key, value) }
  function updateDisplayFor(name, key, value) { updateDisplayAt(displayIndex(name), key, value) }

  function setResolution(value) {
    if (!selectedDisplay) return
    updateDisplay("mode", DisplayModel.nearestMode(selectedDisplay.modes, value, DisplayModel.refresh(selectedDisplay.mode)))
  }

  function setResolutionFor(name, value) {
    var index = displayIndex(name)
    if (index < 0) return
    var display = displays[index]
    updateDisplayAt(index, "mode", DisplayModel.nearestMode(display.modes, value, DisplayModel.refresh(display.mode)))
  }

  function setRefresh(value) {
    if (!selectedDisplay) return
    updateDisplay("mode", DisplayModel.nearestMode(selectedDisplay.modes, DisplayModel.resolution(selectedDisplay.mode), value))
  }

  function setRefreshFor(name, value) {
    var index = displayIndex(name)
    if (index < 0) return
    var display = displays[index]
    updateDisplayAt(index, "mode", DisplayModel.nearestMode(display.modes, DisplayModel.resolution(display.mode), value))
  }

  function toggleEnabled() {
    if (!selectedDisplay || (!selectedDisplay.disabled && activeCount <= 1)) return
    updateDisplay("disabled", !selectedDisplay.disabled)
  }

  function toggleEnabledFor(name) {
    var index = displayIndex(name)
    if (index < 0) return
    var display = displays[index]
    if (!display.disabled && activeCount <= 1) return
    updateDisplayAt(index, "disabled", !display.disabled)
  }

  function undoLastChange() {
    if (!undoAvailable || applying || undoProc.running) return
    if (undoKind === "brightness") {
      var name = undoBrightnessName
      var value = undoBrightnessValue
      undoKind = ""
      undoBrightnessName = ""
      undoBrightnessValue = -1
      undoAvailable = false
      setBrightnessFor(name, value, false)
      statusMessage = "Undone"
      refreshUndoState()
      return
    }
    statusMessage = "Undoing…"
    undoProc.command = [helperPath, "undo"]
    undoProc.running = true
  }

  Component.onCompleted: refresh()
  onOpenedChanged: if (opened) refresh()

  // Keep identification inside the widget. A separate overlay entry point
  // becomes the plugin's summon target and steals the normal Display shortcut.
  IdentifyOverlay { id: identifyOverlay }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: Quickshell.screens.length > 1 ? "󰍺" : "󰍹"
    tooltipText: "Display Settings"
    active: root.applying || undoProc.running
    onPressed: function(mouseButton) { root.toggle() }
    onWheelMoved: function(delta) {
      var current = root.brightnessFor(root.focusedMonitor)
      if (current < 0) return
      var wheel = Util.wheelSteps(root.wheelAccumulator, delta)
      root.wheelAccumulator = wheel.remainder
      if (wheel.steps !== 0) root.setBrightnessFor(root.focusedMonitor, current + wheel.steps * 5)
    }
  }

  Process {
    id: brightnessStateProc
    property bool outputValid: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = root.parseOutput(text)
        if (!parsed || !Array.isArray(parsed)) return
        var next = ({})
        parsed.forEach(function(entry) {
          next[entry.name] = { value: Number(entry.value), available: entry.available === true }
        })
        root.brightnessByDisplay = next
        brightnessStateProc.outputValid = true
      }
    }
    onRunningChanged: if (running) outputValid = false
  }

  Process {
    id: setBrightnessProc
    stdout: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) root.refreshBrightness()
      root.brightnessInFlight = ""
      Qt.callLater(root.startNextBrightnessSet)
    }
  }

  Process {
    id: nightLightStatusProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = root.parseOutput(text)
        if (!parsed || parsed.temperature === null || parsed.temperature === undefined) return
        var temperature = Number(parsed.temperature)
        if (!isFinite(temperature)) return
        root.nightLightTemperature = Math.round(temperature)
        root.nightLightLoaded = true
        if (temperature < 6000)
          root.nightLightPreferredTemperature = Math.max(1600, Math.min(5500, Math.round(temperature / 100) * 100))
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) root.nightLightLoaded = true
    }
  }

  Process {
    id: nightLightSetProc
    stderr: StdioCollector { id: nightLightSetError; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0)
        root.statusMessage = root.processError(nightLightSetError.text, "Could not change Night Light")
      if (root.nightLightSetQueued) {
        var target = root.nightLightQueuedTemperature
        root.nightLightSetQueued = false
        root.startNightLightSet(target)
      } else {
        root.refreshNightLight()
      }
    }
  }

  Process {
    id: nightLightScheduleStateProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = root.parseOutput(text)
        if (!parsed || typeof parsed.enabled !== "boolean") return
        root.nightLightScheduleEnabled = parsed.enabled
        root.nightLightScheduleStart = String(parsed.start || "20:00")
        root.nightLightScheduleEnd = String(parsed.end || "07:00")
        if (parsed.enabled && Number(parsed.temperature) >= 1600 && Number(parsed.temperature) <= 5500)
          root.nightLightPreferredTemperature = Number(parsed.temperature)
        root.nightLightScheduleLoaded = true
      }
    }
  }

  Process {
    id: nightLightScheduleSetProc
    property bool outputValid: false
    stderr: StdioCollector { id: nightLightScheduleError; waitForEnd: true }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = root.parseOutput(text)
        if (!parsed || typeof parsed.enabled !== "boolean") return
        nightLightScheduleSetProc.outputValid = true
        root.nightLightScheduleEnabled = parsed.enabled
        root.nightLightScheduleStart = String(parsed.start)
        root.nightLightScheduleEnd = String(parsed.end)
        root.nightLightScheduleLoaded = true
      }
    }
    onRunningChanged: if (running) outputValid = false
    onExited: function(exitCode) {
      root.nightLightScheduleSaving = false
      if (exitCode !== 0 || !outputValid)
        root.statusMessage = root.processError(nightLightScheduleError.text, "Could not update the Night Light schedule")
      if (root.nightLightScheduleQueued) {
        root.nightLightScheduleQueued = false
        Qt.callLater(root.saveNightLightSchedule)
      } else {
        root.refreshNightLightSchedule()
        root.refreshNightLight()
      }
    }
  }

  Timer {
    interval: 5000
    running: root.opened
    repeat: true
    onTriggered: {
      root.refreshBrightness()
      root.refreshNightLight()
      root.refreshNightLightSchedule()
    }
  }

  Process {
    id: stateProc
    property bool outputValid: false
    stderr: StdioCollector { id: stateError; waitForEnd: true }
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = root.parseOutput(text)
        if (parsed && Array.isArray(parsed)) {
          stateProc.outputValid = true
          root.displays = parsed
          var focused = parsed.filter(function(display) { return display.focused })
          root.focusedMonitor = focused.length ? focused[0].name : ""
          if (root.selectedIndex >= parsed.length) root.selectedIndex = Math.max(0, parsed.length - 1)
          root.statusMessage = root.refreshMessage
          root.refreshMessage = ""
        }
      }
    }
    onExited: function(exitCode) {
      if (exitCode !== 0 || !outputValid) {
        root.statusMessage = root.processError(stateError.text, "Could not read Hyprland display state")
        root.refreshMessage = ""
      }
    }
    onRunningChanged: {
      if (running) outputValid = false
      else root.loading = false
    }
  }

  Process {
    id: undoStateProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = root.parseOutput(text)
        if (root.undoKind !== "brightness") {
          root.undoAvailable = parsed && parsed.available === true
          root.undoKind = root.undoAvailable ? "layout" : ""
        }
      }
    }
  }

  Timer {
    id: autoApplyTimer
    interval: 180
    repeat: false
    onTriggered: root.startAutoApply()
  }

  Process {
    id: applyProc
    stdout: StdioCollector { id: applyOutput; waitForEnd: true }
    stderr: StdioCollector { id: applyError; waitForEnd: true }
    onExited: function(exitCode) {
      root.applying = false
      if (exitCode === 0) {
        root.undoAvailable = true
        root.undoKind = "layout"
        if (root.queuedDisplayConfig !== null) {
          root.statusMessage = "Applying latest changes…"
          Qt.callLater(function() { root.startAutoApply() })
        } else {
          root.refresh("Applied")
        }
      } else {
        root.queuedDisplayConfig = null
        root.refresh(root.processError(applyError.text, "Could not apply the change; the previous layout was restored"))
      }
    }
  }

  Process {
    id: undoProc
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { id: undoError; waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode === 0) {
        root.undoAvailable = false
        root.undoKind = ""
        root.refresh("Undone")
      } else {
        root.refresh(root.processError(undoError.text, "Could not undo the last display change"))
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Math.min(root.arrangementExpanded ? 620 : 420, panel.availableCardWidth))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight, Math.min(760, panel.availableCardHeight))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      ScrollView {
        id: scrollArea
        anchors.fill: parent
        clip: true
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

        Column {
          id: contentColumn
          width: scrollArea.availableWidth
          spacing: Style.space(14)

          RowLayout {
            width: parent.width
            spacing: Style.space(14)

            Text {
              text: root.displays.length > 1 ? "󰍺" : "󰍹"
              color: root.barForeground
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.display
            }

            ColumnLayout {
              Layout.fillWidth: true
              spacing: Style.space(2)
              Text {
                Layout.fillWidth: true
                text: "Display"
                color: root.barForeground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                elide: Text.ElideRight
              }
              Text {
                Layout.fillWidth: true
                text: root.displays.length + " CONNECTED"
                color: Qt.darker(root.barForeground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.2
              }
            }

            Button {
              text: "Identify"
              foreground: root.barForeground
              fontFamily: root.bar.fontFamily
              bordered: true
              onClicked: identifyOverlay.open(JSON.stringify({ displays: root.displays }))
            }
          }

          PanelSeparator {
            visible: root.activeCount > 0
            foreground: root.barForeground
          }

          Column {
            width: parent.width
            spacing: Style.space(10)
            visible: root.activeCount > 0

            PanelSectionHeader {
              text: "BRIGHTNESS"
              foreground: root.barForeground
              fontFamily: root.bar.fontFamily
            }

            Repeater {
              model: root.displays.filter(function(display) { return !display.disabled })

              Column {
                id: brightnessSection
                required property var modelData
                width: parent.width
                spacing: Style.space(6)

                Item {
                  width: parent.width
                  implicitHeight: Math.max(brightnessName.implicitHeight, brightnessPercent.implicitHeight)
                  Text {
                    id: brightnessName
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: DisplayModel.friendlyName(brightnessSection.modelData)
                    color: root.barForeground
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: true
                  }
                  Text {
                    id: brightnessPercent
                    anchors.right: parent.right
                    anchors.rightMargin: Style.space(6)
                    anchors.verticalCenter: parent.verticalCenter
                    text: brightnessSlider.dragging
                      ? Math.round(brightnessSlider.liveValue) + "%"
                      : (root.brightnessFor(brightnessSection.modelData.name) >= 0
                        ? Math.round(root.brightnessFor(brightnessSection.modelData.name)) + "%" : "—")
                    color: Qt.darker(root.barForeground, 1.4)
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }
                }

                CursorSurface {
                  width: parent.width
                  height: brightnessSlider.implicitHeight + Style.spacing.controlGap
                  foreground: root.barForeground
                  outline: false
                  PanelSlider {
                    id: brightnessSlider
                    anchors.fill: parent
                    anchors.leftMargin: Style.space(6)
                    anchors.rightMargin: Style.space(6)
                    bar: root.bar
                    minimum: 1
                    maximum: 100
                    step: 1
                    integer: true
                    enabled: root.brightnessFor(brightnessSection.modelData.name) >= 0
                    opacity: enabled ? 1 : 0.35
                    value: Math.max(1, root.brightnessFor(brightnessSection.modelData.name))
                    onReleased: function(value) { root.setBrightnessFor(brightnessSection.modelData.name, value) }
                  }
                }
              }
            }
          }

          PanelSeparator { foreground: root.barForeground }

          Column {
            width: parent.width
            spacing: Style.space(8)

            RowLayout {
              width: parent.width
              spacing: Style.space(8)
              PanelSectionHeader {
                text: "NIGHT LIGHT"
                foreground: root.barForeground
                fontFamily: root.bar.fontFamily
              }
              Item { Layout.fillWidth: true; height: 1 }
              Button {
                text: root.nightLightEnabled ? "󰔎  On" : "󰔎  Off"
                foreground: root.barForeground
                fontFamily: root.bar.fontFamily
                bordered: true
                active: root.nightLightEnabled
                onClicked: root.setNightLightEnabled(!root.nightLightEnabled)
              }
              Button {
                text: root.nightLightExpanded ? "󰅀" : "󰅂"
                tooltipText: root.nightLightExpanded ? "Hide Night Light settings" : "Show Night Light settings"
                foreground: root.barForeground
                fontFamily: root.bar.fontFamily
                onClicked: root.nightLightExpanded = !root.nightLightExpanded
              }
            }

            Column {
              width: parent.width
              spacing: Style.space(6)
              visible: root.nightLightExpanded

              Item {
                width: parent.width
                implicitHeight: Math.max(nightTemperatureHeader.implicitHeight, nightTemperatureValue.implicitHeight)
                enabled: root.nightLightEnabled
                opacity: enabled ? 1 : 0.45
                PanelSectionHeader {
                  id: nightTemperatureHeader
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  text: "TEMPERATURE"
                  foreground: root.barForeground
                  fontFamily: root.bar.fontFamily
                }
                Text {
                  id: nightTemperatureValue
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(6)
                  anchors.verticalCenter: parent.verticalCenter
                  text: Math.round(nightTemperatureSlider.dragging
                    ? nightTemperatureSlider.liveValue : root.nightLightPreferredTemperature) + " K"
                  color: Qt.darker(root.barForeground, 1.4)
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
              }

              CursorSurface {
                width: parent.width
                height: nightTemperatureSlider.implicitHeight + Style.spacing.controlGap
                enabled: root.nightLightEnabled
                opacity: enabled ? 1 : 0.45
                foreground: root.barForeground
                outline: false
                PanelSlider {
                  id: nightTemperatureSlider
                  anchors.fill: parent
                  anchors.leftMargin: Style.space(6)
                  anchors.rightMargin: Style.space(6)
                  bar: root.bar
                  minimum: 1600
                  maximum: 5500
                  step: 100
                  integer: true
                  tickCount: 9
                  value: root.nightLightPreferredTemperature
                  onReleased: function(value) { root.setNightLightTemperature(value) }
                }
              }

              PanelSeparator { width: parent.width; foreground: root.barForeground }

              RowLayout {
                width: parent.width
                spacing: Style.space(8)
                PanelSectionHeader {
                  text: "SCHEDULE"
                  foreground: root.barForeground
                  fontFamily: root.bar.fontFamily
                }
                Item { Layout.fillWidth: true; height: 1 }
                Button {
                  text: root.nightLightScheduleSaving ? "Saving…"
                    : (root.nightLightScheduleEnabled ? "On" : "Off")
                  foreground: root.barForeground
                  fontFamily: root.bar.fontFamily
                  bordered: true
                  active: root.nightLightScheduleEnabled
                  enabled: !root.nightLightScheduleSaving
                  onClicked: root.setNightLightScheduleEnabled(!root.nightLightScheduleEnabled)
                }
              }

              RowLayout {
                visible: root.nightLightScheduleEnabled
                width: parent.width
                spacing: Style.space(8)

                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: Style.space(4)
                  PanelSectionHeader {
                    text: "START"
                    foreground: root.barForeground
                    fontFamily: root.bar.fontFamily
                  }
                  TextField {
                    id: nightScheduleStartField
                    Layout.fillWidth: true
                    text: root.nightLightScheduleStart
                    placeholderText: "20:00"
                    maximumLength: 5
                    foreground: root.barForeground
                    font.family: root.bar.fontFamily
                    horizontalAlignment: TextInput.AlignHCenter
                    onEditingFinished: {
                      if (!root.setNightLightScheduleTime("start", text)) text = root.nightLightScheduleStart
                    }
                  }
                }

                ColumnLayout {
                  Layout.fillWidth: true
                  spacing: Style.space(4)
                  PanelSectionHeader {
                    text: "END"
                    foreground: root.barForeground
                    fontFamily: root.bar.fontFamily
                  }
                  TextField {
                    id: nightScheduleEndField
                    Layout.fillWidth: true
                    text: root.nightLightScheduleEnd
                    placeholderText: "07:00"
                    maximumLength: 5
                    foreground: root.barForeground
                    font.family: root.bar.fontFamily
                    horizontalAlignment: TextInput.AlignHCenter
                    onEditingFinished: {
                      if (!root.setNightLightScheduleTime("end", text)) text = root.nightLightScheduleEnd
                    }
                  }
                }
              }
            }
          }

          PanelSeparator { foreground: root.barForeground }

          Button {
            width: parent.width
            text: root.arrangementExpanded ? "Hide arrangement" : "Arrange displays"
            iconText: root.arrangementExpanded ? "󰅀" : "󰅂"
            foreground: root.barForeground
            fontFamily: root.bar.fontFamily
            bordered: true
            leftAlign: true
            active: root.arrangementExpanded
            onClicked: root.arrangementExpanded = !root.arrangementExpanded
          }

          Rectangle {
            id: layoutCanvas
            visible: root.arrangementExpanded && root.displays.length > 0
            width: parent.width
            height: 292
            radius: Style.cornerRadius
            color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.025)
            border.color: root.validLayout
              ? Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.18)
              : Color.urgent
            border.width: 1

            property real minX: {
              var value = Infinity
              root.displays.forEach(function(display) {
                if (!display.disabled && !display.mirror) value = Math.min(value, display.x)
              })
              return isFinite(value) ? value : 0
            }
            property real minY: {
              var value = Infinity
              root.displays.forEach(function(display) {
                if (!display.disabled && !display.mirror) value = Math.min(value, display.y)
              })
              return isFinite(value) ? value : 0
            }
            property real maxX: {
              var value = 1
              root.displays.forEach(function(display) {
                var size = DisplayModel.logicalSize(display)
                if (!display.disabled && !display.mirror) value = Math.max(value, display.x + size.width)
              })
              return value
            }
            property real maxY: {
              var value = 1
              root.displays.forEach(function(display) {
                var size = DisplayModel.logicalSize(display)
                if (!display.disabled && !display.mirror) value = Math.max(value, display.y + size.height)
              })
              return value
            }
            property real zoom: Math.min(
              (width - Style.space(32)) / Math.max(1, maxX - minX),
              (height - Style.space(32)) / Math.max(1, maxY - minY))

            Repeater {
              model: root.displays
              Rectangle {
                required property var modelData
                required property int index
                property var logical: DisplayModel.logicalSize(modelData)
                visible: !modelData.disabled
                x: Style.space(16) + (modelData.x - layoutCanvas.minX) * layoutCanvas.zoom
                y: Style.space(16) + (modelData.y - layoutCanvas.minY) * layoutCanvas.zoom
                width: Math.max(Style.space(70), logical.width * layoutCanvas.zoom)
                height: Math.max(Style.space(44), logical.height * layoutCanvas.zoom)
                radius: Style.cornerRadius
                color: index === root.selectedIndex
                  ? Style.selectedFillFor(root.barForeground, Color.accent)
                  : Style.hoverFillFor(root.barForeground, Color.accent)
                border.color: index === root.selectedIndex ? Color.accent : root.barForeground
                border.width: index === root.selectedIndex ? 2 : 1
                opacity: modelData.mirror ? 0.65 : 1

                Text {
                  anchors.centerIn: parent
                  text: (index + 1) + "  " + DisplayModel.friendlyName(modelData)
                    + (modelData.mirror ? "\nMirrors " + root.displayLabelForConnector(modelData.mirror) : "")
                  color: root.barForeground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  horizontalAlignment: Text.AlignHCenter
                }
                MouseArea {
                  anchors.fill: parent
                  drag.target: parent
                  drag.axis: Drag.XAndYAxis
                  cursorShape: Qt.SizeAllCursor
                  onPressed: root.selectedIndex = index
                  onReleased: {
                    var copy = DisplayModel.clone(root.displays)
                    var wantedX = Math.round((parent.x - Style.space(16)) / layoutCanvas.zoom + layoutCanvas.minX)
                    var wantedY = Math.round((parent.y - Style.space(16)) / layoutCanvas.zoom + layoutCanvas.minY)
                    var snapDistance = Math.max(24, Math.round(14 / layoutCanvas.zoom))
                    var snapped = DisplayModel.snapPosition(copy, index, wantedX, wantedY, snapDistance)
                    copy[index].x = snapped.x
                    copy[index].y = snapped.y
                    root.commitDisplayChange(copy)
                  }
                }
              }
            }
          }

          Text {
            visible: root.arrangementExpanded && !root.validLayout
            text: root.activeCount === 0 ? "At least one display must stay enabled."
              : root.overlappingLayout ? "Displays cannot overlap."
              : "Every display must share an edge so the pointer can move between them."
            color: Color.urgent
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.caption
          }

          Text {
            visible: root.loading || root.displays.length === 0
            width: parent.width
            text: root.loading ? "Reading displays…" : "No displays were reported by Hyprland."
            color: root.barForeground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
            horizontalAlignment: Text.AlignHCenter
          }

          Repeater {
            id: displaySettingsRepeater
            model: root.displays

            Column {
              id: displaySection
              required property var modelData
              required property int index
              width: parent.width
              spacing: Style.space(10)

              PanelSeparator { width: parent.width; foreground: root.barForeground }

              Item {
                width: parent.width
                implicitHeight: Math.max(displayName.implicitHeight, displayNumber.implicitHeight)
                Text {
                  id: displayName
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  text: DisplayModel.friendlyName(displaySection.modelData)
                  color: root.barForeground
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.title
                  font.bold: true
                }
                Text {
                  id: displayNumber
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(6)
                  anchors.verticalCenter: parent.verticalCenter
                  text: (displaySection.index + 1) + (displaySection.modelData.disabled ? " · DISCONNECTED" : "")
                  color: Qt.darker(root.barForeground, 1.4)
                  font.family: root.bar.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
              }

              Column {
                width: parent.width
                spacing: Style.space(10)
                visible: !displaySection.modelData.disabled

                PanelSectionHeader {
                  text: "SCALE"
                  foreground: root.barForeground
                  fontFamily: root.bar.fontFamily
                }

                Grid {
                  id: scaleRow
                  width: parent.width
                  property var values: root.scaleOptions(displaySection.modelData)
                  columns: values.length
                  spacing: Style.spacing.xs
                  readonly property real cellWidth: values.length > 0
                    ? (width - spacing * (columns - 1)) / columns : 0

                  Repeater {
                    model: scaleRow.values
                    Button {
                      required property var modelData
                      width: scaleRow.cellWidth
                      text: root.scaleLabel(modelData)
                      fontSize: Style.font.caption
                      foreground: root.barForeground
                      fontFamily: root.bar.fontFamily
                      horizontalPadding: Style.spacing.sm
                      verticalPadding: Style.spacing.controlPaddingY
                      bordered: true
                      active: Math.abs(Number(displaySection.modelData.scale) - Number(modelData)) < 0.01
                      onClicked: root.updateDisplayFor(displaySection.modelData.name, "scale", Number(modelData))
                    }
                  }
                }

                RowLayout {
                  width: parent.width
                  spacing: Style.space(8)
                  Text {
                    Layout.fillWidth: true
                    text: DisplayModel.resolution(displaySection.modelData.mode)
                      + " · " + DisplayModel.refresh(displaySection.modelData.mode) + " Hz"
                    color: root.barForeground
                    font.family: root.bar.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    elide: Text.ElideRight
                  }
                  Button {
                    text: root.detailsExpandedFor(displaySection.modelData.name) ? "Less settings" : "More settings"
                    iconText: root.detailsExpandedFor(displaySection.modelData.name) ? "󰅀" : "󰅂"
                    foreground: root.barForeground
                    fontFamily: root.bar.fontFamily
                    onClicked: root.toggleDetailsFor(displaySection.modelData.name)
                  }
                }

                GridLayout {
                  visible: root.detailsExpandedFor(displaySection.modelData.name)
                  width: parent.width
                  columns: width >= 560 ? 3 : 1
                  columnSpacing: Style.space(8)
                  rowSpacing: Style.space(8)

                  Dropdown {
                    Layout.fillWidth: true
                    label: options.length === 1 ? "RESOLUTION · NATIVE" : "RESOLUTION"
                    foreground: root.barForeground
                    fontFamily: root.bar.fontFamily
                    options: DisplayModel.resolutionOptions(displaySection.modelData.modes)
                    value: DisplayModel.resolution(displaySection.modelData.mode)
                    enabled: options.length > 1
                    opacity: enabled ? 1 : 0.72
                    onChanged: function(value) { root.setResolutionFor(displaySection.modelData.name, value) }
                  }
                  Dropdown {
                    Layout.fillWidth: true
                    label: "REFRESH RATE"
                    foreground: root.barForeground
                    fontFamily: root.bar.fontFamily
                    options: DisplayModel.refreshOptions(displaySection.modelData.modes, DisplayModel.resolution(displaySection.modelData.mode))
                    value: DisplayModel.refresh(displaySection.modelData.mode)
                    onChanged: function(value) { root.setRefreshFor(displaySection.modelData.name, value) }
                  }
                  Dropdown {
                    Layout.fillWidth: true
                    label: "ORIENTATION"
                    foreground: root.barForeground
                    fontFamily: root.bar.fontFamily
                    options: [
                      {value:"0",label:"Landscape"},
                      {value:"1",label:"Portrait"},
                      {value:"2",label:"Landscape flipped"},
                      {value:"3",label:"Portrait flipped"}
                    ]
                    value: String(displaySection.modelData.transform)
                    onChanged: function(value) {
                      root.updateDisplayFor(displaySection.modelData.name, "transform", Number(value))
                    }
                  }
                  Dropdown {
                    Layout.fillWidth: true
                    label: "MULTIPLE DISPLAYS"
                    foreground: root.barForeground
                    fontFamily: root.bar.fontFamily
                    options: [{value:"",label:"Extend desktop"}].concat(root.displays.filter(function(display) {
                      return display.name !== displaySection.modelData.name && !display.disabled
                    }).map(function(display) {
                      return {value:display.name,label:"Duplicate " + DisplayModel.friendlyName(display)}
                    }))
                    value: displaySection.modelData.mirror
                    onChanged: function(value) {
                      root.updateDisplayFor(displaySection.modelData.name, "mirror", value)
                    }
                  }
                  Button {
                    Layout.alignment: Qt.AlignBottom
                    text: "Disconnect display"
                    foreground: root.barForeground
                    fontFamily: root.bar.fontFamily
                    bordered: true
                    enabled: root.activeCount > 1
                    onClicked: root.toggleEnabledFor(displaySection.modelData.name)
                  }
                }
              }

              Button {
                visible: displaySection.modelData.disabled
                width: parent.width
                text: "Connect display"
                foreground: root.barForeground
                fontFamily: root.bar.fontFamily
                bordered: true
                onClicked: root.toggleEnabledFor(displaySection.modelData.name)
              }
            }
          }

          PanelSeparator { foreground: root.barForeground }

          RowLayout {
            width: parent.width
            spacing: Style.space(10)
            Item {
              visible: root.statusMessage.length === 0
              Layout.fillWidth: true
              height: 1
            }
            Text {
              Layout.fillWidth: true
              Layout.alignment: Qt.AlignVCenter
              text: root.statusMessage
              visible: text.length > 0
              color: Qt.darker(root.barForeground, 1.25)
              font.family: root.bar.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
            Button {
              Layout.alignment: Qt.AlignVCenter
              text: "Refresh"
              foreground: root.barForeground
              fontFamily: root.bar.fontFamily
              bordered: true
              enabled: !root.applying && !undoProc.running
              onClicked: root.refresh()
            }
            Button {
              Layout.alignment: Qt.AlignVCenter
              text: undoProc.running ? "Undoing…" : "Undo"
              foreground: root.barForeground
              fontFamily: root.bar.fontFamily
              bordered: true
              active: root.undoAvailable
              enabled: root.undoAvailable && !root.applying && !undoProc.running
              onClicked: root.undoLastChange()
            }
          }

          Item { width: parent.width; height: Style.space(4) }
        }
      }
    }
  }
}
