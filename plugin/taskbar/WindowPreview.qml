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
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

Item {
  id: root

  property string address: ""
  property string title: ""
  property string icon: ""
  property bool minimized: false
  property bool isActive: false

  signal activated()
  signal closed()

  readonly property bool hovered: mouse.containsMouse
  readonly property int previewW: Style.space(180)
  readonly property int previewH: Style.space(110)

  width: previewW + Style.space(12)
  height: previewH + Style.space(36)

  property var captureToplevel: null

  function refreshCapture() {
    var want = String(root.address || "")
    var found = null
    if (want) {
      if (want.indexOf("0x") !== 0) want = "0x" + want
      var raw = (Hyprland.toplevels && Hyprland.toplevels.values) ? Hyprland.toplevels.values : []
      for (var i = 0; i < raw.length; i++) {
        var a = String(raw[i].address || "")
        if (a.indexOf("0x") !== 0) a = "0x" + a
        if (a === want) {
          found = raw[i]
          break
        }
      }
    }
    captureToplevel = found
  }

  Component.onCompleted: refreshCapture()
  onAddressChanged: refreshCapture()

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
      live: true
      paintCursor: false
      // Live capture is visual-only. If this item takes pointer events,
      // moving onto a miniature steals hover from the peek card and the
      // popup closes before a click can land.
      enabled: false
      captureSource: (root.captureToplevel && root.captureToplevel.wayland)
        ? root.captureToplevel.wayland
        : null
    }

    Timer {
      interval: 900
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
      anchors.left: parent.left
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
    z: 10
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: function (mouse) {
      if (closeMouse.containsMouse) {
        mouse.accepted = true
        return
      }
      root.activated()
    }

    Rectangle {
      id: closeBtn
      visible: root.hovered
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.margins: Style.space(4)
      width: Style.space(18)
      height: Style.space(18)
      radius: Math.max(3, Style.space(3))
      color: closeMouse.containsMouse ? Color.urgent : Util.alpha(Color.foreground, 0.22)
      border.width: 1
      border.color: Util.alpha(Color.foreground, 0.28)

      Text {
        anchors.centerIn: parent
        text: "×"
        color: closeMouse.containsMouse ? Color.background : Color.foreground
        font.pixelSize: Math.max(12, Style.font.title - 2)
        font.bold: true
        font.family: Style.font.family
      }

      MouseArea {
        id: closeMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: function (mouse) {
          mouse.accepted = true
          root.closed()
        }
      }
    }
  }
}
