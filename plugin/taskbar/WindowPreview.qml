// /**
//  * @version   0.3.0
//  * @package   omarchy-classic-desktop
//  * Derived from Omarchy Classic Desktop (OCD) Exposé WindowTile
//  * @url       https://github.com/fevangelou/ocd
//  * @copyright Copyright (c) 2026 Fotis Evangelou. All rights reserved.
//  * @license   GNU/GPL license: https://www.gnu.org/copyleft/gpl.html
//  */

import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui

Item {
  id: root

  property var toplevel: null
  property string title: ""
  property string icon: ""
  property bool minimized: false
  property bool isActive: false

  signal activated()

  readonly property bool hovered: mouse.containsMouse
  readonly property int previewW: Style.space(180)
  readonly property int previewH: Style.space(110)

  width: previewW + Style.space(12)
  height: previewH + Style.space(36)

  Rectangle {
    anchors.fill: parent
    radius: Math.max(6, Style.space(6))
    color: root.hovered
      ? Util.alpha(Color.foreground, 0.12)
      : "transparent"
    border.width: root.isActive || root.hovered ? 1 : 0
    border.color: Color.accent
  }

  Item {
    id: previewArea
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: Style.space(6)
    height: root.previewH
    property bool captureFailed: false

    ScreencopyView {
      id: capture
      anchors.fill: parent
      visible: hasContent && !previewArea.captureFailed
      live: root.hovered
      paintCursor: false
      captureSource: {
        var t = root.toplevel
        if (!t) return null
        return t.wayland ? t.wayland : t
      }
    }

    Timer {
      interval: 800
      running: root.visible && !capture.hasContent
      onTriggered: previewArea.captureFailed = true
    }

    Rectangle {
      anchors.fill: parent
      visible: !capture.visible
      radius: Math.max(4, Style.space(4))
      color: Util.alpha(Color.foreground, 0.08)

      Image {
        anchors.centerIn: parent
        width: Style.space(40)
        height: Style.space(40)
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        source: root.icon
      }
    }

    Rectangle {
      visible: root.minimized
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.margins: Style.space(4)
      radius: Math.max(3, Style.space(3))
      color: Color.accent
      width: minLabel.implicitWidth + Style.space(8)
      height: minLabel.implicitHeight + Style.space(2)
      Text {
        id: minLabel
        anchors.centerIn: parent
        text: "min"
        color: Color.background
        font.pixelSize: 9
        font.family: Style.font.family
      }
    }
  }

  Text {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.margins: Style.space(6)
    elide: Text.ElideRight
    horizontalAlignment: Text.AlignHCenter
    text: root.title
    font.family: Style.font.family
    font.pixelSize: Math.max(9, Style.font.title - 5)
    color: Color.foreground
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.activated()
  }
}
