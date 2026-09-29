import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

BarWidget {
  id: root

  moduleName: "kaelvxdev.nghtwv-plz"

  readonly property string playerPath:
    Qt.resolvedUrl("plaza-player").toString().replace(/^file:\/\//, "")
  property bool playing: false
  property bool paused: false
  property bool buffering: false
  property int volume: 70
  property string title: ""
  property string plazaTitle: ""
  property int listeners: -1
  property string playerError: ""
  property bool statusBusy: false
  property bool actionBusy: false
  property bool metadataBusy: false

  function updateStatus() {
    if (statusBusy) return
    statusBusy = true
    statusProcess.command = [playerPath, "status"]
    statusProcess.running = true
  }

  function runAction(action, value) {
    if (actionBusy) return
    actionBusy = true
    playerError = ""
    actionProcess.command = value === undefined
      ? [playerPath, action]
      : [playerPath, action, String(value)]
    actionProcess.running = true
  }

  function singleLine(value, maxLength) {
    return String(value || "").replace(/[\r\n\t]+/g, " ").slice(0, maxLength)
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
          root.title = root.singleLine(state.title || "", 160)
          if (state.error) root.playerError = root.singleLine(state.error, 180)
        } catch (error) {
          root.playing = false
        }
      }
    }
    onExited: root.statusBusy = false
  }

  Process {
    id: actionProcess
    command: []
    stdout: StdioCollector {}
    stderr: StdioCollector { id: actionErrors }
    onExited: function(exitCode) {
      root.playerError = exitCode === 0
        ? "" : root.singleLine(actionErrors.text || "Player action failed", 180)
      root.actionBusy = false
      root.updateStatus()
    }
  }

  Process {
    id: metadataProcess
    command: []
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          const data = JSON.parse(text)
          if (data.title) root.plazaTitle = root.singleLine(data.title, 160)
          if (Number.isFinite(Number(data.listeners))) root.listeners = Number(data.listeners)
        } catch (error) {
          // Stream metadata remains available when the status service is offline.
        }
      }
    }
    onExited: root.metadataBusy = false
  }

  Timer {
    interval: 3000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.updateStatus()
  }

  Timer {
    interval: 30000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      if (root.metadataBusy) return
      root.metadataBusy = true
      metadataProcess.command = [root.playerPath, "metadata"]
      metadataProcess.running = true
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.playing && !root.paused ? "\udb82\udd60" : "\uf186"
    active: root.playing && !root.paused
    tooltipText: root.playerError
      ? root.playerError
      : root.playing
          ? (root.buffering ? "Nightwave Plaza buffering: " : root.paused ? "Nightwave Plaza paused: " : "Nightwave Plaza: ")
          + (root.plazaTitle || root.title || "Live stream")
          + (root.listeners >= 0 ? " · " + root.listeners + " listening" : "")
          + " · " + root.volume + "%"
        : "Open Nightwave Plaza"

    onPressed: function(mouseButton) {
      if (!root.bar) return
      if (mouseButton === Qt.RightButton) root.runAction("stop")
      else if (mouseButton === Qt.MiddleButton) root.runAction("toggle")
      else root.bar.run("omarchy-shell shell toggle kaelvxdev.nghtwv-plz")
    }

    onWheelMoved: function(delta) {
      root.runAction("volume", Math.max(0, Math.min(100, root.volume + (delta > 0 ? 5 : -5))))
    }
  }
}
