import QtQuick
import qs.Commons
import qs.Ui

CursorSurface {
  id: root
  property string text: ""
  property string iconText: ""
  property string tooltipText: ""
  property string fontFamily: Style.font.family
  property real iconSize: Style.font.icon
  signal clicked()
  signal pointed()
  implicitWidth: content.implicitWidth + Style.spacing.controlPaddingX * 2
  implicitHeight: Math.max(Style.spacing.controlHeight, content.implicitHeight + Style.spacing.controlPaddingY * 2)
  opacity: enabled || current ? 1 : 0.4
  Accessible.role: Accessible.Button
  Accessible.name: tooltipText || text
  Accessible.onPressAction: if (enabled) clicked()
  Row {
    id: content
    anchors.centerIn: parent
    spacing: root.text && root.iconText ? Style.spacing.sm : 0
    Text {
      visible: root.iconText !== ""
      text: root.iconText
      textFormat: Text.PlainText
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: root.iconSize
      anchors.verticalCenter: parent.verticalCenter
    }
    Text {
      visible: root.text !== ""
      text: root.text
      textFormat: Text.PlainText
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      anchors.verticalCenter: parent.verticalCenter
      width: Math.min(implicitWidth, Math.max(0, root.width - Style.spacing.controlPaddingX * 2 - (root.iconText ? Style.space(24) : 0)))
      elide: Text.ElideRight
    }
  }
  MouseArea {
    id: pointer
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onPositionChanged: root.pointed()
    onClicked: { root.pointed(); root.clicked() }
  }
  PanelToolTip {
    visible: pointer.containsMouse && root.tooltipText !== ""
    text: root.tooltipText
  }
}
