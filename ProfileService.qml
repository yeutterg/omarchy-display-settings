import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

Item {
  id: root
  property string moduleName: "io.github.yeutterg.display-settings"
  property string helperPath: Quickshell.env("HOME") + "/.config/omarchy/plugins/" + moduleName + "/bin/display-manager"
  property string lastTopology: ""
  property string pendingTopology: ""

  function checkTopology() {
    if (!topologyProc.running) {
      topologyProc.command = [helperPath, "topology"]
      topologyProc.running = true
    }
  }

  Component.onCompleted: checkTopology()

  Timer { interval: 4000; running: true; repeat: true; onTriggered: root.checkTopology() }
  Timer { id: reloadTimer; interval: 250; repeat: false; onTriggered: root.checkTopology() }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (!event || String(event.name) !== "configreloaded") return
      // A reload can re-run monitor rules without changing the connected
      // topology. Forget the last match so the verified profile is checked
      // again instead of treating the unchanged connector list as sufficient.
      root.lastTopology = ""
      reloadTimer.restart()
    }
  }

  Process {
    id: topologyProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var value = String(text || "").trim()
        if (!value || value === root.lastTopology) return
        if (matchProc.running) return
        root.pendingTopology = value
        matchProc.command = [root.helperPath, "profiles-match"]
        matchProc.running = true
      }
    }
  }

  Process {
    id: matchProc
    property bool outputValid: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var result = JSON.parse(String(text || "{}"))
          matchProc.outputValid = result.ok === true
          if (result.matched) Quickshell.execDetached(["omarchy-notification-send", "-g", "󰍺", "Display profile applied", result.name])
        } catch (e) {}
      }
    }
    stderr: StdioCollector { id: matchError; waitForEnd: true }
    onRunningChanged: if (running) outputValid = false
    onExited: function(exitCode) {
      if (exitCode === 0 && outputValid) {
        root.lastTopology = root.pendingTopology
      } else {
        var detail = String(matchError.text || "").trim()
        console.warn("Display profile match failed" + (detail ? ": " + detail : ""))
      }
      root.pendingTopology = ""
    }
  }
}
