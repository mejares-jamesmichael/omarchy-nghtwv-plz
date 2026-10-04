import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Ui

// nghtwv plz window: a centered retro-computer popup with the
// live track, a progress readout, transport controls, volume, and the recent
// transmission log. Summoned from the bar widget via
// `omarchy-shell shell toggle kaelvxdev.nghtwv-plz`, which the shell routes
// to open()/close() below through the panel-loader path (same shape as
// akshar.radio-atlas: kinds ["bar-widget", "panel"] with keepLoaded).
Item {
  id: root

  // Injected by the shell panel loader.
  property var shell: null
  property var manifest: null

  property bool opened: false

  // ---- live player state (polled from plaza-player while open) ------------
  property bool playing: false
  property bool paused: false
  property bool buffering: false
  property int volume: 70
  property int pendingVolume: -1
  property string playerError: ""
  property string actionError: ""
  property bool statusBusy: false
  property bool actionBusy: false

  // ---- track metadata ------------------------------------------------------
  property string artist: ""
  property string track: ""
  property string album: ""
  property string artwork: ""
  property bool artworkFailed: false
  property real trackLength: 0
  property real trackPosition: 0
  property real positionStamp: 0
  property real positionNow: 0
  property int listeners: -1
  property bool metadataBusy: false

  // ---- transmission log ----------------------------------------------------
  property var history: []
  property bool historyBusy: false

  // ---- audio output --------------------------------------------------------
  property var audioOutputs: []
  property string outputsError: ""
  property bool outputMenuOpen: false
  property string currentOutput: ""
  property bool outputsBusy: false

  // ---- visuals: GIF backdrop + emulated meter (panel only) -----------------
  // The bars are decorative motion gated on playback state, not spectrum
  // analysis: nothing in this stack exports audio levels without an FFT
  // dependency, and the marketplace listing stays a one-liner install.
  property string bgUrl: ""
  property string bgAuthor: ""
  property string bgSource: ""
  property bool bgBusy: false
  property var levels: []
  property var bgSeeds: []
  property int visualTick: 0
  property real visualEnergy: 0
  readonly property string bgCredit: {
    var parts = []
    if (root.bgAuthor !== "") parts.push("by " + root.bgAuthor)
    if (root.bgSource !== "") parts.push(root.bgSource)
    return parts.join(" · ")
  }

  // ---- window plumbing (mirrors akshar.radio-atlas) ------------------------
  readonly property string playerPath:
    Qt.resolvedUrl("plaza-player").toString().replace(/^file:\/\//, "")
  readonly property string windowPath:
    Qt.resolvedUrl("nightwave-window").toString().replace(/^file:\/\//, "")
  readonly property int preferredWidth: Style.space(480)
  readonly property int preferredHeight: Style.space(620)

  property bool windowSetupReady: false
  property bool windowFrameReady: false
  property string pendingOpenPayload: ""

  property color background: Color.menu.background
  property color foreground: Color.menu.text
  property color border: Color.menu.border
  property color accent: Color.accent
  property color urgent: Color.urgent
  property color dim: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.56)
  property color faint: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.12)

  function singleLine(value, maxLength) {
    return String(value || "").replace(/[\r\n\t]+/g, " ").slice(0, maxLength)
  }

  function formatClock(seconds) {
    var total = Math.max(0, Math.floor(Number(seconds) || 0))
    return Math.floor(total / 60) + ":" + String(total % 60).padStart(2, "0")
  }

  function formatPlayedAt(epoch) {
    var stamp = Number(epoch)
    if (!isFinite(stamp) || stamp <= 0) return ""
    return Qt.formatDateTime(new Date(stamp * 1000), "HH:mm")
  }

  function outputLabel(sink) {
    if (!sink) return "System default"
    for (var i = 0; i < audioOutputs.length; i++) {
      if (audioOutputs[i].id === sink) return singleLine(audioOutputs[i].label || sink, 40)
    }
    return singleLine(sink, 40)
  }

  function registerWindowSetup() {
    windowSetupReady = false
    if (!windowSetupProcess.running) windowSetupProcess.running = true
  }

  function open(payloadJson) {
    if (!windowSetupReady) {
      pendingOpenPayload = payloadJson || "{}"
      return
    }
    openWindow(payloadJson)
  }

  function openWindow(payloadJson) {
    opened = true
    windowFrameReady = false
    windowRevealTimer.stop()
    panel.visible = true
    playerError = ""
    actionError = ""
    refreshAll()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    opened = false
    outputMenuOpen = false
    windowFrameReady = false
    windowRevealTimer.stop()
    panel.visible = false
    if (statusProcess.running) statusProcess.running = false
    if (metadataProcess.running) metadataProcess.running = false
    if (historyProcess.running) historyProcess.running = false
    if (outputsProcess.running) outputsProcess.running = false
    if (backgroundsProcess.running) backgroundsProcess.running = false
    if (actionProcess.running) actionProcess.running = false
    levels = []
    visualEnergy = 0
  }

  function dismiss() {
    close()
    if (shell && typeof shell.hide === "function")
      shell.hide((manifest && manifest.id) || "kaelvxdev.nghtwv-plz")
  }

  function scheduleWindowReveal() {
    if (windowFrameReady || !panel.visible || !panel.backingWindowVisible) return
    windowRevealTimer.restart()
  }

  function handleHyprlandEvent(event) {
    var eventName = String(event && event.name || "")
    if (eventName === "configreloaded") {
      windowSetupReloadTimer.restart()
      return
    }
    if (!opened || eventName !== "openwindow") return
    var parts = []
    try {
      parts = event.parse(4)
    } catch (error) {
      parts = String(event && event.data || "").split(",")
    }
    var windowClass = String(parts[2] || "")
    if (windowClass === "org.omarchy.screensaver") {
      dismiss()
    }
  }

  function refreshAll() {
    refreshStatus()
    refreshMetadata()
    refreshHistory()
    refreshBackground()
  }

  function refreshStatus() {
    if (statusBusy) return
    statusBusy = true
    statusProcess.command = [playerPath, "status"]
    statusProcess.running = true
  }

  function refreshMetadata() {
    if (metadataBusy) return
    metadataBusy = true
    metadataProcess.command = [playerPath, "metadata"]
    metadataProcess.running = true
  }

  function refreshHistory() {
    if (historyBusy) return
    historyBusy = true
    historyProcess.command = [playerPath, "history"]
    historyProcess.running = true
  }

  function refreshBackground() {
    if (bgBusy) return
    bgBusy = true
    backgroundsProcess.command = [playerPath, "backgrounds"]
    backgroundsProcess.running = true
  }

  function updateLevels() {
    visualTick++
    var live = playing && !paused && !buffering
    visualEnergy = live
      ? Math.min(1, visualEnergy + 0.12)
      : Math.max(0, visualEnergy - 0.25)
    if (bgSeeds.length !== 24) {
      var seeds = []
      for (var s = 0; s < 24; s++) seeds.push(Math.random() * 6.2832)
      bgSeeds = seeds
    }
    var energy = visualEnergy
    var breathe = 0.55 + 0.45 * Math.sin(visualTick * 0.05)
    var next = []
    for (var i = 0; i < 24; i++) {
      if (energy <= 0) {
        next.push(0.06)
        continue
      }
      var mirror = Math.min(i, 23 - i) / 11
      var wave = Math.sin(visualTick * 0.35 + bgSeeds[i]) * 0.5
        + Math.sin(visualTick * 0.13 + bgSeeds[i] * 1.7) * 0.3
      next.push(Math.max(0.06, (0.45 + 0.4 * wave) * (0.35 + 0.65 * mirror) * breathe * energy))
    }
    levels = next
  }

  function refreshOutputs() {
    if (outputsBusy) return
    outputsBusy = true
    outputsError = ""
    outputsProcess.command = [playerPath, "outputs"]
    outputsProcess.running = true
  }

  function toggleOutputMenu() {
    if (outputMenuOpen) {
      outputMenuOpen = false
      return
    }
    outputMenuOpen = true
    refreshOutputs()
  }

  function setOutput(sink) {
    outputMenuOpen = false
    outputsError = ""
    if (sink === "") root.runAction("output")
    else root.runAction("output", sink)
  }

  function runAction(action, value) {
    if (actionBusy) return
    actionBusy = true
    actionError = ""
    actionProcess.command = value === undefined
      ? [playerPath, action]
      : [playerPath, action, String(value)]
    actionProcess.running = true
  }

  function setVolumeFromX(x, width) {
    if (!(width > 0)) return
    pendingVolume = Math.max(0, Math.min(100, Math.round(x / width * 100)))
    volumeTimer.restart()
  }

  function changeVolume(delta) {
    var current = pendingVolume >= 0 ? pendingVolume : volume
    pendingVolume = Math.max(0, Math.min(100, current + delta))
    volumeTimer.restart()
  }

  function flushVolume() {
    if (pendingVolume < 0 || actionProcess.running) {
      if (pendingVolume >= 0) volumeTimer.restart()
      return
    }
    var target = pendingVolume
    pendingVolume = -1
    runAction("volume", target)
  }

  Process {
    id: windowSetupProcess
    command: [root.windowPath, String(root.preferredWidth), String(root.preferredHeight)]
    onExited: function(exitCode) {
      root.windowSetupReady = true
      if (!root.pendingOpenPayload) return
      var payload = root.pendingOpenPayload
      root.pendingOpenPayload = ""
      root.openWindow(payload)
    }
  }

  Process {
    id: statusProcess
    command: []
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const state = JSON.parse(text)
          root.playing = state.playing === true
          root.paused = state.paused === true
          root.buffering = state.buffering === true
          root.volume = Math.max(0, Math.min(100, Math.round(Number(state.volume) || 0)))
          if (typeof state.output === "string") root.currentOutput = state.output.slice(0, 160)
          if (state.error) root.playerError = root.singleLine(state.error, 180)
        } catch (error) {
          root.playing = false
        }
      }
    }
    onExited: root.statusBusy = false
  }

  Process {
    id: metadataProcess
    command: []
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const data = JSON.parse(text)
          if (typeof data.artist === "string") root.artist = root.singleLine(data.artist, 160)
          if (typeof data.track === "string") root.track = root.singleLine(data.track, 160)
          if (typeof data.album === "string") root.album = root.singleLine(data.album, 160)
          if (typeof data.artwork === "string" && data.artwork !== root.artwork) {
            root.artworkFailed = false
            root.artwork = data.artwork.slice(0, 512)
          }
          var length = Number(data.length)
          root.trackLength = isFinite(length) && length > 0 ? length : 0
          var position = Number(data.position)
          root.trackPosition = isFinite(position) && position >= 0 ? position : 0
          root.positionStamp = Date.now()
          root.positionNow = root.trackPosition
          if (Number.isFinite(Number(data.listeners))) root.listeners = Number(data.listeners)
        } catch (error) {
          // Keep the last known track when a fetch fails.
        }
      }
    }
    onExited: root.metadataBusy = false
  }

  Process {
    id: historyProcess
    command: []
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const data = JSON.parse(text)
          if (data && Array.isArray(data.songs)) root.history = data.songs.slice(0, 10)
        } catch (error) {
          // Keep the last known log when a fetch fails.
        }
      }
    }
    onExited: root.historyBusy = false
  }

  Process {
    id: backgroundsProcess
    command: []
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const data = JSON.parse(text)
          if (data && typeof data.src === "string" && data.src !== "") {
            root.bgUrl = data.src.slice(0, 512)
            root.bgAuthor = root.singleLine(data.author || "", 80)
            root.bgSource = root.singleLine(data.source || "", 80)
          }
        } catch (error) {
          // Keep the current backdrop (or the static one) when a fetch fails.
        }
      }
    }
    onExited: root.bgBusy = false
  }

  Process {
    id: outputsProcess
    command: []
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const data = JSON.parse(text)
          if (data && Array.isArray(data.outputs)) {
            root.audioOutputs = data.outputs.slice(0, 24)
            root.outputsError = ""
          } else {
            root.outputsError = "Audio outputs are unavailable"
          }
        } catch (error) {
          root.outputsError = "Audio outputs are unavailable"
        }
      }
    }
    stderr: StdioCollector { id: outputsErrors }
    onExited: function(exitCode) {
      if (exitCode !== 0 && root.outputsError === "")
        root.outputsError = root.singleLine(outputsErrors.text || "Audio outputs are unavailable", 180)
      root.outputsBusy = false
    }
  }

  Process {
    id: actionProcess
    command: []
    stdout: StdioCollector {}
    stderr: StdioCollector { id: actionErrors }
    onExited: function(exitCode) {
      root.actionError = exitCode === 0
        ? "" : root.singleLine(actionErrors.text || "Player action failed", 180)
      root.actionBusy = false
      root.refreshStatus()
      root.refreshMetadata()
    }
  }

  Timer {
    id: windowSetupReloadTimer
    interval: 100
    repeat: false
    onTriggered: root.registerWindowSetup()
  }

  Timer {
    id: windowRevealTimer
    interval: 50
    repeat: false
    onTriggered: {
      if (panel.visible && panel.backingWindowVisible) root.windowFrameReady = true
    }
  }

  Timer {
    id: tickTimer
    interval: 1000
    repeat: true
    running: root.opened
    triggeredOnStart: true
    onTriggered: {
      if (root.playing && !root.paused && root.trackLength > 0)
        root.positionNow = Math.min(root.trackPosition + (Date.now() - root.positionStamp) / 1000, root.trackLength)
      else
        root.positionNow = root.trackPosition
    }
  }

  Timer {
    id: statusTimer
    interval: 3000
    repeat: true
    running: root.opened
    triggeredOnStart: true
    onTriggered: root.refreshStatus()
  }

  Timer {
    id: metadataTimer
    interval: 30000
    repeat: true
    running: root.opened
    triggeredOnStart: true
    onTriggered: root.refreshMetadata()
  }

  Timer {
    id: historyTimer
    interval: 60000
    repeat: true
    running: root.opened
    triggeredOnStart: true
    onTriggered: root.refreshHistory()
  }

  Timer {
    id: volumeTimer
    interval: 120
    repeat: false
    onTriggered: root.flushVolume()
  }

  Timer {
    id: visualTimer
    interval: 100
    repeat: true
    running: root.opened
    triggeredOnStart: true
    onTriggered: root.updateLevels()
  }

  Component.onCompleted: {
    registerWindowSetup()
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) { root.handleHyprlandEvent(event) }
  }

  FloatingWindow {
    id: panel
    visible: false
    title: "Nghtwv Plz"
    color: root.background
    implicitWidth: root.preferredWidth
    implicitHeight: root.preferredHeight
    minimumSize: Qt.size(420, 520)
    HyprlandWindow.opacity: root.windowFrameReady ? 1 : 0

    onVisibleChanged: {
      if (visible) root.scheduleWindowReveal()
      if (!visible && root.opened) root.dismiss()
    }
    onBackingWindowVisibleChanged: root.scheduleWindowReveal()
    onWidthChanged: root.scheduleWindowReveal()
    onHeightChanged: root.scheduleWindowReveal()

    BorderSurface {
      id: card
      anchors.fill: parent
      color: root.background
      borderSpec: Border.surfaceSpec("menu", "border", root.border, Math.max(1, Style.normalBorderWidth))
      radius: Style.cornerRadius

      Keys.priority: Keys.AfterItem
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape) {
          if (root.outputMenuOpen) root.outputMenuOpen = false
          else root.dismiss()
          event.accepted = true
        } else if (event.key === Qt.Key_Space) {
          root.runAction("toggle")
          event.accepted = true
        } else if (event.key === Qt.Key_Plus || event.key === Qt.Key_Equal) {
          root.changeVolume(5)
          event.accepted = true
        } else if (event.key === Qt.Key_Minus) {
          root.changeVolume(-5)
          event.accepted = true
        }
      }

      MouseArea {
        anchors.fill: parent
        onClicked: keyCatcher.forceActiveFocus()
      }

      Item {
        id: keyCatcher
        anchors.fill: parent
        focus: true
      }

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: Style.spacing.panelPadding
        spacing: Style.space(10)

        // ---- titlebar ------------------------------------------------
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(8)

          Text {
            text: root.playing && !root.paused ? "\udb82\udd60" : "\uf186"
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.icon
            color: root.accent
          }
          Text {
            Layout.fillWidth: true
            text: "NGHTWV-PLZ — player"
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.body
            font.bold: true
            color: root.foreground
            elide: Text.ElideRight
          }
          Button {
            iconText: "\uf00d"
            bordered: true
            tooltipText: "Close (Esc)"
            fontFamily: Style.font.menuFamily
            onClicked: root.dismiss()
          }
        }

        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: 1
          color: root.faint
        }

        // ---- desktop: now playing ------------------------------------
        Rectangle {
          Layout.fillWidth: true
          Layout.preferredHeight: desktopInner.implicitHeight + Style.space(24)
          color: Qt.darker(root.background, 1.35)
          radius: Math.max(0, Style.cornerRadius - 2)
          border.color: root.faint
          border.width: 1

          AnimatedImage {
            anchors.fill: parent
            anchors.margins: 1
            source: root.bgUrl
            visible: root.bgUrl !== ""
            asynchronous: true
            cache: true
            playing: root.opened
            fillMode: Image.PreserveAspectCrop
            opacity: 0.5
            onStatusChanged: {
              if (status === Image.Error) root.bgUrl = ""
            }
          }
          Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            visible: root.bgUrl !== ""
            color: Qt.rgba(0, 0, 0, 0.45)
          }

          ColumnLayout {
            id: desktopInner
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Style.space(12)
            spacing: Style.space(10)

            RowLayout {
              Layout.fillWidth: true
              spacing: Style.space(12)

              Item {
                Layout.preferredWidth: Style.space(96)
                Layout.preferredHeight: Style.space(96)

                Rectangle {
                  anchors.fill: parent
                  color: root.faint
                }
                Image {
                  anchors.fill: parent
                  source: root.artworkFailed || root.artwork === "" ? "" : root.artwork
                  fillMode: Image.PreserveAspectCrop
                  asynchronous: true
                  onStatusChanged: {
                    if (status === Image.Error) root.artworkFailed = true
                  }
                }
                Text {
                  anchors.centerIn: parent
                  visible: root.artwork === "" || root.artworkFailed
                  text: "\uf001"
                  font.family: Style.font.menuFamily
                  font.pixelSize: Style.space(36)
                  color: root.dim
                }
              }

              ColumnLayout {
                Layout.fillWidth: true
                spacing: Style.space(4)

                RowLayout {
                  Layout.fillWidth: true
                  spacing: Style.space(6)

                  Rectangle {
                    Layout.preferredWidth: 8
                    Layout.preferredHeight: 8
                    Layout.alignment: Qt.AlignVCenter
                    radius: 4
                    color: root.playing && !root.paused ? root.urgent : root.dim
                  }
                  Text {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignVCenter
                    text: (root.playing ? (root.buffering ? "BUFFERING" : root.paused ? "PAUSED" : "LIVE") : "IDLE")
                      + (root.listeners >= 0 ? " · " + root.listeners + " listening" : "")
                    font.family: Style.font.menuFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                    color: root.dim
                    elide: Text.ElideRight
                  }
                }

                Text {
                  Layout.fillWidth: true
                  text: root.track !== "" ? root.track : "—"
                  font.family: Style.font.family
                  font.pixelSize: Style.font.title
                  font.bold: true
                  color: root.foreground
                  elide: Text.ElideRight
                  maximumLineCount: 2
                  wrapMode: Text.WordWrap
                }
                Text {
                  Layout.fillWidth: true
                  text: root.artist + (root.album !== "" && root.album !== root.track ? " · " + root.album : "")
                  visible: text !== ""
                  font.family: Style.font.family
                  font.pixelSize: Style.font.bodySmall
                  color: root.dim
                  elide: Text.ElideRight
                }
              }
            }

            ColumnLayout {
              Layout.fillWidth: true
              spacing: Style.space(4)

              Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 6

                Rectangle {
                  anchors.fill: parent
                  radius: 3
                  color: root.faint
                }
                Rectangle {
                  height: parent.height
                  radius: 3
                  width: root.trackLength > 0
                    ? parent.width * Math.max(0, Math.min(1, root.positionNow / root.trackLength))
                    : 0
                  color: root.accent
                }
              }

              Item {
                Layout.fillWidth: true
                Layout.preferredHeight: Math.max(posLabel.implicitHeight, lenLabel.implicitHeight)

                Text {
                  id: posLabel
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.formatClock(root.positionNow)
                  font.family: Style.font.menuFamily
                  font.pixelSize: Style.font.caption
                  color: root.dim
                }
                Text {
                  id: lenLabel
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.formatClock(root.trackLength)
                  font.family: Style.font.menuFamily
                  font.pixelSize: Style.font.caption
                  color: root.dim
                }
              }
            }

            Item {
              Layout.fillWidth: true
              Layout.preferredHeight: 44

              RowLayout {
                anchors.fill: parent
                spacing: 4

                Repeater {
                  model: 24

                  Rectangle {
                    required property int index
                    readonly property real level: index < root.levels.length ? root.levels[index] : 0.06
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.max(4, level * 44)
                    Layout.alignment: Qt.AlignBottom
                    radius: 2
                    color: root.accent
                    opacity: 0.35 + 0.65 * level
                  }
                }
              }
            }

            RowLayout {
              Layout.fillWidth: true
              spacing: Style.space(8)

              Button {
                iconText: "\uf021"
                bordered: true
                tooltipText: "Shuffle backdrop"
                fontFamily: Style.font.menuFamily
                onClicked: root.refreshBackground()
              }
              Text {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                visible: root.bgCredit !== ""
                text: root.bgCredit
                font.family: Style.font.menuFamily
                font.pixelSize: Style.font.caption
                color: root.dim
                elide: Text.ElideRight
              }
            }
          }
        }

        // ---- control deck --------------------------------------------
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(8)

          Button {
            iconText: root.playing && !root.paused ? "\uf04c" : "\uf04b"
            bordered: true
            tooltipText: root.playing && !root.paused ? "Pause (Space)" : "Play (Space)"
            fontFamily: Style.font.menuFamily
            onClicked: root.runAction("toggle")
          }
          Button {
            iconText: "\uf04d"
            bordered: true
            tooltipText: "Stop"
            fontFamily: Style.font.menuFamily
            onClicked: root.runAction("stop")
          }
          Button {
            iconText: "\uf028"
            bordered: true
            tooltipText: root.currentOutput !== ""
              ? "Audio output: " + root.outputLabel(root.currentOutput)
              : "Choose audio output"
            fontFamily: Style.font.menuFamily
            onClicked: root.toggleOutputMenu()
          }
          Item {
            id: volumeSlider
            Layout.fillWidth: true
            Layout.preferredHeight: Style.space(28)

            readonly property int shownVolume: root.pendingVolume >= 0 ? root.pendingVolume : root.volume

            Rectangle {
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width
              height: 6
              radius: 3
              color: root.faint
            }
            Rectangle {
              anchors.verticalCenter: parent.verticalCenter
              height: 6
              radius: 3
              color: root.accent
              width: parent.width * volumeSlider.shownVolume / 100
            }
            Rectangle {
              width: 14
              height: 14
              radius: 3
              color: root.foreground
              anchors.verticalCenter: parent.verticalCenter
              x: Math.max(0, Math.min(parent.width - 14, parent.width * volumeSlider.shownVolume / 100 - 7))
            }
            MouseArea {
              anchors.fill: parent
              onPressed: function(mouse) { root.setVolumeFromX(mouse.x, volumeSlider.width) }
              onPositionChanged: function(mouse) {
                if (pressed) root.setVolumeFromX(mouse.x, volumeSlider.width)
              }
            }
          }
          Text {
            Layout.preferredWidth: Style.space(40)
            horizontalAlignment: Text.AlignRight
            text: volumeSlider.shownVolume + "%"
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.bodySmall
            color: root.dim
          }
        }

        // ---- audio output picker -------------------------------------
        ColumnLayout {
          Layout.fillWidth: true
          Layout.preferredHeight: root.outputMenuOpen ? implicitHeight : 0
          visible: root.outputMenuOpen
          spacing: Style.space(2)

          Repeater {
            model: [{ id: "", label: "System default" }].concat(root.audioOutputs)

            Button {
              required property var modelData
              Layout.fillWidth: true
              leftAlign: true
              text: (modelData.id === root.currentOutput ? "● " : "○ ") + root.singleLine(modelData.label || modelData.id, 60)
              tooltipText: modelData.id === "" ? "Follow the system default output" : modelData.id
              fontFamily: Style.font.menuFamily
              onClicked: root.setOutput(modelData.id)
            }
          }

          Text {
            Layout.fillWidth: true
            visible: root.outputsError !== ""
            text: root.outputsError
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.caption
            color: root.urgent
          }
          Text {
            Layout.fillWidth: true
            visible: root.outputsError === "" && root.audioOutputs.length === 0
            text: root.outputsBusy ? "scanning outputs…" : "no extra outputs found"
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.caption
            color: root.dim
          }
        }

        PanelSectionHeader {
          Layout.fillWidth: true
          text: "RECENT TRANSMISSIONS"
        }

        ListView {
          id: historyList
          Layout.fillWidth: true
          Layout.fillHeight: true
          clip: true
          model: root.history
          spacing: 0

          delegate: Item {
            required property var modelData
            required property int index
            width: historyList.width
            height: Style.space(26)

            Text {
              anchors.left: parent.left
              anchors.right: histTime.left
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              text: {
                var entryArtist = root.singleLine(modelData.artist || "", 80)
                var entryTrack = root.singleLine(modelData.track || "", 80)
                if (entryArtist !== "" && entryTrack !== "") return entryArtist + " — " + entryTrack
                return (entryArtist + entryTrack) || "—"
              }
              font.family: Style.font.family
              font.pixelSize: Style.font.bodySmall
              color: root.foreground
              elide: Text.ElideRight
            }
            Text {
              id: histTime
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: root.formatPlayedAt(modelData.played_at)
              font.family: Style.font.menuFamily
              font.pixelSize: Style.font.caption
              color: root.dim
            }
            Rectangle {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              height: 1
              color: root.faint
              visible: index < root.history.length - 1
            }
          }
        }

        Text {
          Layout.fillWidth: true
          Layout.preferredHeight: visible ? implicitHeight : 0
          visible: root.history.length === 0
          text: root.historyBusy ? "tuning the log…" : "no recent transmissions — check your connection"
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.caption
          color: root.dim
        }

        Text {
          Layout.fillWidth: true
          text: root.actionError !== "" ? root.actionError
            : root.playerError !== "" ? root.playerError
            : (root.playing
              ? (root.buffering ? "⟳ buffering — esc closes" : root.paused ? "❚❚ paused — space resumes" : "▶ on air — space pauses · esc closes")
              : "■ idle — press play to tune in")
              + (root.currentOutput !== "" ? " · " + root.outputLabel(root.currentOutput) : "")
          font.family: Style.font.menuFamily
          font.pixelSize: Style.font.caption
          color: root.actionError !== "" || root.playerError !== "" ? root.urgent : root.dim
          elide: Text.ElideRight
        }
      }
    }
  }
}
