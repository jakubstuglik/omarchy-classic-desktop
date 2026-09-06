// Desktop right-click menu for omarchy-classic-desktop.
//
// A Bottom layer-shell sits above the wallpaper and below windows, so empty
// desktop clicks reach us without stealing left-clicks from clients, the
// top bar, or the taskbar. The menu itself is an Overlay so it can appear
// over windows (Windows does that too).
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui

Item {
  id: root

  readonly property string home: Quickshell.env("HOME")
  readonly property string pluginDir: home + "/.config/omarchy/plugins/io.github.jstuglik.desktop"
  readonly property int topBar: Style.space(26)
  readonly property int taskbar: Style.space(48)
  readonly property int menuWidth: Style.space(204)

  property bool menuOpen: false
  property real menuX: 0
  property real menuY: 0
  property string menuScreen: ""

  readonly property var menuModel: [
    { id: "new-folder", label: "New folder", danger: false, sep: false },
    { id: "sep-1", label: "", danger: false, sep: true },
    { id: "wallpaper", label: "Change wallpaper", danger: false, sep: false },
    { id: "wallpaper-file", label: "Browse wallpaper...", danger: false, sep: false },
    { id: "wallpaper-next", label: "Next wallpaper", danger: false, sep: false },
    { id: "theme", label: "Change theme", danger: false, sep: false },
    { id: "sep-2", label: "", danger: false, sep: true },
    { id: "display", label: "Display settings", danger: false, sep: false },
    { id: "files", label: "Open in Files", danger: false, sep: false },
    { id: "terminal", label: "Open Terminal here", danger: false, sep: false }
  ]

  function openMenu(screenName, x, y) {
    root.menuScreen = screenName || ""
    root.menuX = x
    root.menuY = y
    root.menuOpen = true
  }

  function closeMenu() {
    root.menuOpen = false
  }

  function runAction(id) {
    root.closeMenu()
    if (!id || String(id).indexOf("sep") === 0)
      return
    actionProc.command = [root.pluginDir + "/desktop.sh", id]
    actionProc.running = true
  }

  function clampMenuX(parentWidth, cardWidth, x) {
    var maxX = Math.max(8, parentWidth - cardWidth - 8)
    return Math.max(8, Math.min(x, maxX))
  }

  function clampMenuY(parentHeight, cardHeight, y) {
    var minY = root.topBar + 8
    var maxY = Math.max(minY, parentHeight - root.taskbar - cardHeight - 8)
    return Math.max(minY, Math.min(y, maxY))
  }

  Process {
    id: actionProc
    stderr: SplitParser { onRead: line => console.log("[ocd-desktop] " + line) }
  }

  IpcHandler {
    target: "ocd-classic-desktop"
    function ping(): string { return "ok" }
    function open(): string {
      root.openMenu("", 80, 80)
      return "ok"
    }
    function close(): string {
      root.closeMenu()
      return "ok"
    }
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: catcher
      required property var modelData
      screen: modelData
      visible: true
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "ocd-classic-desktop"
      WlrLayershell.layer: WlrLayer.Bottom
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      anchors { top: true; bottom: true; left: true; right: true }

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPressed: function (mouse) {
          if (mouse.button === Qt.RightButton)
            root.openMenu(catcher.modelData.name || "", mouse.x, mouse.y)
          else
            root.closeMenu()
        }
        onDoubleClicked: function (mouse) {
          // Same as stock omarchy.background: left double-click picks a wallpaper.
          if (mouse.button === Qt.LeftButton)
            root.runAction("wallpaper")
        }
      }
    }
  }

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: menuLayer
      required property var modelData
      screen: modelData
      visible: root.menuOpen
      color: "transparent"
      exclusionMode: ExclusionMode.Ignore
      WlrLayershell.namespace: "ocd-classic-desktop-menu"
      WlrLayershell.layer: WlrLayer.Overlay
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
      anchors { top: true; bottom: true; left: true; right: true }

      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onPressed: function (mouse) {
          if (mouse.button === Qt.RightButton)
            root.openMenu(menuLayer.modelData.name || "", mouse.x, mouse.y)
          else
            root.closeMenu()
        }
      }

      Rectangle {
        id: menuCard
        visible: root.menuScreen === "" || root.menuScreen === (menuLayer.modelData.name || "")
        width: root.menuWidth
        implicitHeight: menuCol.implicitHeight + Style.space(8)
        x: root.clampMenuX(parent.width, width, root.menuX)
        y: root.clampMenuY(parent.height, implicitHeight, root.menuY)
        color: Color.background
        border.width: 1
        border.color: Util.alpha(Color.foreground, 0.22)
        radius: Math.max(6, Style.space(6))

        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.LeftButton | Qt.RightButton
          onPressed: function (mouse) { mouse.accepted = true }
        }

        Column {
          id: menuCol
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: Style.space(4)
          spacing: 0

          Repeater {
            model: root.menuModel
            delegate: Item {
              required property var modelData
              width: menuCol.width
              height: modelData.sep ? Style.space(9) : Style.space(28)

              Rectangle {
                visible: modelData.sep
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: Style.space(8)
                anchors.rightMargin: Style.space(8)
                height: 1
                color: Util.alpha(Color.foreground, 0.16)
              }

              Rectangle {
                visible: !modelData.sep
                anchors.fill: parent
                radius: Math.max(4, Style.space(4))
                color: rowMouse.containsMouse
                  ? Util.alpha(Color.foreground, 0.12)
                  : "transparent"
              }

              Text {
                visible: !modelData.sep
                anchors.fill: parent
                anchors.leftMargin: Style.space(12)
                anchors.rightMargin: Style.space(12)
                verticalAlignment: Text.AlignVCenter
                text: modelData.label
                font.family: Style.font.family
                font.pixelSize: Math.max(10, Style.font.title - 3)
                color: modelData.danger ? Color.urgent : Color.foreground
              }

              MouseArea {
                id: rowMouse
                anchors.fill: parent
                hoverEnabled: true
                enabled: !modelData.sep
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: root.runAction(modelData.id)
              }
            }
          }
        }
      }
    }
  }
}
