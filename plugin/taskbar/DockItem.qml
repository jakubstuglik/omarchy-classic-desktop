// /**
//  * @version   0.1.0
//  * @package   omarchy-classic-desktop
//  * Derived from Omarchy Classic Desktop (OCD) by Fotis Evangelou
//  * @url       https://github.com/fevangelou/ocd
//  * @copyright Copyright (c) 2026 Fotis Evangelou. All rights reserved.
//  * @license   GNU/GPL license: https://www.gnu.org/copyleft/gpl.html
//  */

// Same MouseArea pattern as the top-bar WidgetButton, which already
// distinguishes left/right clicks on this compositor.
import QtQuick
import QtQuick.Window
import qs.Commons
import qs.Ui

Item {
  id: root

  property int tabIndex: -1
  property string label: ""
  property string icon: ""
  property bool pinned: false
  property bool running: false
  property bool isMinimized: false
  property bool isActive: false
  property int windowCount: 0
  property bool dragging: false

  opacity: dragging ? 0.22 : 1
  readonly property bool hovered: mouseArea.containsMouse
  readonly property int iconSize: Style.space(24)
  readonly property int radius: Math.max(6, Style.space(6))

  signal activated()
  signal contextMenuRequested()
  signal closeRequested()
  signal hoverEntered()
  signal hoverPeekRequested()
  signal hoverPeekEnded()
  signal pinDragStarted()
  signal pinDragMoved(real xInParent)
  signal pinDragFinished()
  signal pinDragCancelled()

  Rectangle {
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.verticalCenter: parent.verticalCenter
    width: parent.width - Style.space(6)
    height: parent.height - Style.space(8)
    radius: root.radius
    color: root.isActive
      ? Util.alpha(Color.accent, 0.22)
      : (root.hovered
        ? Util.alpha(Color.foreground, 0.12)
        : "transparent")
    Behavior on color { ColorAnimation { duration: 120 } }
  }

  Column {
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.verticalCenter: parent.verticalCenter
    anchors.verticalCenterOffset: -Style.space(1)
    spacing: Style.space(2)

    Image {
      anchors.horizontalCenter: parent.horizontalCenter
      width: root.iconSize
      height: root.iconSize
      fillMode: Image.PreserveAspectFit
      asynchronous: true
      source: root.icon
      sourceSize.width: width * Screen.devicePixelRatio
      sourceSize.height: height * Screen.devicePixelRatio
      opacity: root.isMinimized ? 0.55 : 1
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      width: root.width - Style.space(8)
      horizontalAlignment: Text.AlignHCenter
      elide: Text.ElideRight
      text: root.label
      font.pixelSize: Math.max(9, Style.font.title - 5)
      font.bold: root.isActive
      font.family: Style.font.family
      color: root.isMinimized
        ? Util.alpha(Color.foreground, 0.6)
        : Color.foreground
    }
  }

  Rectangle {
    visible: root.running
    anchors.bottom: parent.bottom
    anchors.bottomMargin: Style.space(3)
    anchors.horizontalCenter: parent.horizontalCenter
    width: root.isActive ? Style.space(16) : Style.space(8)
    height: Style.space(3)
    radius: Style.space(2)
    color: root.isMinimized ? Util.alpha(Color.accent, 0.4) : Color.accent
    Behavior on width { NumberAnimation { duration: 120 } }
  }

  Timer {
    id: peekTimer
    interval: 400
    repeat: false
    onTriggered: root.hoverPeekRequested()
  }

  MouseArea {
    id: mouseArea
    anchors.fill: parent
    hoverEnabled: true
    preventStealing: true
    cursorShape: root.dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

    property bool suppressClick: false
    property real pressX: 0
    property real pressY: 0
    readonly property real dragThreshold: Style.space(8)

    onContainsMouseChanged: {
      if (root.dragging) return
      if (containsMouse) {
        // Immediate keep-alive so moving back from a miniature to this
        // icon does not lose the race against the close timer.
        root.hoverEntered()
        if (root.windowCount > 0)
          peekTimer.restart()
      } else {
        peekTimer.stop()
        root.hoverPeekEnded()
      }
    }

    onPressed: function (mouse) {
      suppressClick = false
      pressX = mouse.x
      pressY = mouse.y
    }

    onPositionChanged: function (mouse) {
      if (!root.pinned) return
      if (!(mouse.buttons & Qt.LeftButton)) return
      var dist = Math.abs(mouse.x - pressX) + Math.abs(mouse.y - pressY)
      if (!root.dragging && dist >= dragThreshold) {
        root.dragging = true
        peekTimer.stop()
        root.hoverPeekEnded()
        root.pinDragStarted()
      }
      if (root.dragging) {
        // Map through the Row (root.parent), not MouseArea.parent (the
        // DockItem). Using `parent` here made the drop marker track the
        // cursor as if the row started at the dragged icon, so icons on
        // the right landed a long way off.
        root.pinDragMoved(mapToItem(root.parent, mouse.x, mouse.y).x)
      }
    }

    onReleased: function (mouse) {
      if (root.dragging) {
        suppressClick = true
        root.dragging = false
        root.pinDragFinished()
      }
    }

    onCanceled: {
      if (root.dragging) {
        root.dragging = false
        suppressClick = false
        root.pinDragCancelled()
      }
    }

    onClicked: function (mouse) {
      if (suppressClick) {
        suppressClick = false
        return
      }
      if (mouse.button === Qt.RightButton) {
        peekTimer.stop()
        root.hoverPeekEnded()
        root.contextMenuRequested()
        return
      }
      if (mouse.button === Qt.MiddleButton) {
        peekTimer.stop()
        root.hoverPeekEnded()
        if (root.windowCount > 0)
          root.closeRequested()
        return
      }
      if (mouse.button === Qt.LeftButton)
        root.activated()
    }
  }
}
