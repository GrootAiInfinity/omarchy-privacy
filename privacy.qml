import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

Panel {
  id: root
  moduleName: "io.github.grootaiinfinity.privacy"
  ipcTarget: "io.github.grootaiinfinity.privacy"

  // This plugin's own folder, wherever `omarchy plugin add` installed it.
  readonly property string pluginDir: {
    var dir = String(Qt.resolvedUrl("."))
    return dir.replace(/^file:\/\//, "").replace(/\/$/, "")
  }
  readonly property string control: pluginDir + "/privacy-control.sh"

  property bool micMuted: false
  property bool cameraDisabled: false
  property bool cameraPresent: false
  property bool cameraWritable: false
  property bool privacyActive: false

  // Derived states for intuitive indicators
  readonly property bool micActive: !root.micMuted
  readonly property bool camActive: root.cameraPresent && !root.cameraDisabled

  // Dynamic status bar icon selection (using verified system-compatible glyphs)
  readonly property string statusIcon: {
    if (micActive && camActive) {
      return "󰈈" // Shield-off (both are active/unsecure)
    } else if (micActive) {
      return "󰍬" // Microphone icon (only microphone is active)
    } else if (camActive) {
      return "󰕧" // Camera icon (only webcam is active)
    } else {
      return "󰈉" // Shield-check icon (both are disabled/fully secure)
    }
  }

  // Dynamic tooltip description
  readonly property string statusTooltip: {
    if (micActive && camActive) {
      return "Privacy Center: Mic & Webcam LIVE"
    } else if (micActive) {
      return "Privacy Center: Microphone LIVE"
    } else if (camActive) {
      return "Privacy Center: Webcam LIVE"
    } else {
      return "Privacy Center: Fully Secure"
    }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function refresh() {
    if (!statusProc.running) {
      statusProc.running = true
    }
  }

  function toggleMic() {
    if (!toggleMicProc.running) {
      toggleMicProc.running = true
    }
  }

  function toggleCamera() {
    if (!toggleCamProc.running) {
      toggleCamProc.running = true
    }
  }

  function parseStatus(text) {
    try {
      var data = JSON.parse(text)
      root.micMuted = data.mic_muted
      root.cameraDisabled = data.camera_disabled
      root.cameraPresent = data.camera_present
      root.cameraWritable = data.camera_writable
      root.privacyActive = data.privacy_active
    } catch(e) {
      console.log("Error parsing privacy status: " + e)
    }
  }

  Component.onCompleted: {
    refresh()
  }

  Process {
    id: statusProc
    command: [root.control, "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.parseStatus(text)
      }
    }
  }

  Process {
    id: toggleMicProc
    command: [root.control, "mic-toggle"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.parseStatus(text)
      }
    }
  }

  Process {
    id: toggleCamProc
    command: [root.control, "cam-toggle"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.parseStatus(text)
      }
    }
  }

  Timer {
    interval: 3000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.statusIcon
    active: root.opened || micActive || camActive
    tooltipText: root.statusTooltip
    onPressed: function(b) {
      root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight, Style.space(400))

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
        ScrollBar.vertical.policy: panelColumn.implicitHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff
        Binding {
          target: scrollArea.contentItem
          property: "interactive"
          value: panelColumn.implicitHeight > scrollArea.height
        }

        Column {
          id: panelColumn
          width: scrollArea.availableWidth
          spacing: Style.space(12)

          PanelHero {
            width: parent.width
            title: "Privacy Controls"
            meta: "System Shield"
            foreground: Color.popups.text
            iconComponent: Component {
              Text {
                text: root.statusIcon
                color: Color.popups.text
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: Style.font.display
              }
            }
          }

          PanelSeparator {
            width: parent.width
            foreground: Color.popups.text
          }

          Toggle {
            width: parent.width
            label: "Microphone"
            description: root.micMuted ? "Muted / Secure" : "Unmuted / Live"
            checked: !root.micMuted
            foreground: Color.popups.text
            accent: Color.accent
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            onClicked: {
              root.toggleMic()
            }
          }

          Toggle {
            width: parent.width
            label: "Webcam"
            description: root.cameraPresent ? (root.cameraDisabled ? "Powered Off / Secure" : "Powered On / Live") : "No webcam detected"
            checked: root.cameraPresent && !root.cameraDisabled
            enabled: root.cameraPresent && root.cameraWritable
            foreground: Color.popups.text
            accent: Color.accent
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            onClicked: {
              root.toggleCamera()
            }
          }

          Text {
            visible: root.cameraPresent && !root.cameraWritable
            text: "🔒 Click here to copy webcam setup command to clipboard"
            color: Color.urgent
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
            width: parent.width
            horizontalAlignment: Text.AlignHCenter

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                root.bar.run("printf %s \"sudo bash '" + root.pluginDir + "/setup_udev.sh'\" | wl-copy")
                root.bar.run("notify-send 'Privacy Center' 'Setup command copied to clipboard! Paste it in a terminal to enable webcam toggle.'")
              }
            }
          }
        }
      }
    }
  }
}
