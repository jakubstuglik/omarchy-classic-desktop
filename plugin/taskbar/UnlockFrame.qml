// /**
//  * @version   0.10.0
//  * @package   omarchy-classic-desktop
//  * Derived from Omarchy Classic Desktop (OCD) by Fotis Evangelou
//  * @url       https://github.com/fevangelou/ocd
//  * @copyright Copyright (c) 2026 Fotis Evangelou. All rights reserved.
//  * @license   GNU/GPL license: https://www.gnu.org/copyleft/gpl.html
//  */

import QtQuick
import qs.Commons
import qs.Ui

// Four short corner ticks. Shown while icon dragging is unlocked.
Item {
  id: root

  property color lineColor: Util.alpha(Color.foreground, 0.62)
  readonly property int arm: Math.max(6, Style.space(6))
  readonly property int thick: 1

  Rectangle { width: root.arm; height: root.thick; color: root.lineColor }
  Rectangle { width: root.thick; height: root.arm; color: root.lineColor }

  Rectangle {
    anchors.right: parent.right
    width: root.arm
    height: root.thick
    color: root.lineColor
  }
  Rectangle {
    anchors.right: parent.right
    width: root.thick
    height: root.arm
    color: root.lineColor
  }

  Rectangle {
    anchors.bottom: parent.bottom
    width: root.arm
    height: root.thick
    color: root.lineColor
  }
  Rectangle {
    anchors.bottom: parent.bottom
    width: root.thick
    height: root.arm
    color: root.lineColor
  }

  Rectangle {
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    width: root.arm
    height: root.thick
    color: root.lineColor
  }
  Rectangle {
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    width: root.thick
    height: root.arm
    color: root.lineColor
  }
}
