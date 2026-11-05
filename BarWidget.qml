import QtQuick
import qs.Commons
import qs.Ui
import "Model.js" as Model

BarWidget {
  id: root
  moduleName: "atlastimed.tunemarchy"
  readonly property string pluginId: "atlastimed.tunemarchy"
  readonly property var spotify: bar && bar.shell ? bar.shell.serviceFor(pluginId) : null
  readonly property bool showArtist: Model.flag(setting("showArtist", true), true)
  readonly property int maxWidth: Model.clampInt(setting("maxWidth", 240), 0, 800, 240)
  readonly property string whenClosed: Model.normalizeEnum(setting("whenClosed", "icon"), Model.WHEN_CLOSED, "icon")
  readonly property string scrollAction: Model.normalizeEnum(setting("scrollAction", "volume"), Model.SCROLL_ACTIONS, "volume")
  readonly property bool running: spotify && spotify.running
  readonly property bool playing: spotify && spotify.playing
  readonly property string label: spotify && maxWidth > 0 && !vertical
    ? Model.barLabel(spotify.title, spotify.artist, showArtist) : ""
  readonly property bool opened: panel.opened
  readonly property bool popoutSwitchClosing: panel.popoutSwitchClosing
  readonly property real openPanelIndicatorWidth: button.width - Style.space(12)
  readonly property real openPanelIndicatorHeight: Style.space(14)
  visible: running || whenClosed === "icon"
  implicitWidth: visible ? button.implicitWidth : 0
  implicitHeight: visible ? button.implicitHeight : 0
  function open() { panel.open() }
  function close() { panel.close() }
  function toggle() { panel.toggle() }
  function closeForPopoutSwitch() { panel.closeForPopoutSwitch() }

  Translations { id: strings; directory: Qt.resolvedUrl("i18n") }
  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    labelVisible: false
    hasVisualContent: true
    fixedWidth: root.vertical ? -1 : Math.max(Style.bar.iconSlot, row.implicitWidth + scaledHorizontalMargin * 2)
    fixedHeight: root.vertical ? Style.bar.iconSlot : -1
    tooltipText: root.opened ? "" : Model.tooltipText(root.label || strings.t("open"))
    onPressed: function(b) {
      if (b === Qt.MiddleButton && root.spotify) root.spotify.playPause()
      else if (b === Qt.RightButton && root.spotify) root.spotify.launch()
      else root.toggle()
    }
    onWheelMoved: function(delta) {
      if (!root.spotify || !delta) return
      if (root.scrollAction === "volume") root.spotify.setVolume(root.spotify.volume + (delta > 0 ? 0.05 : -0.05))
      else if (root.scrollAction === "skip") delta > 0 ? root.spotify.previous() : root.spotify.next()
    }
    Row {
      id: row
      anchors.centerIn: parent
      spacing: root.label ? Style.space(6) : 0
      scale: button.pressScale
      OpticalGlyph {
        width: Style.bar.iconCanvas
        height: Style.bar.iconCanvas
        text: "󰓇"
        fontFamily: button.fontFamily
        fontSize: Style.bar.iconFont
        paintedSize: Style.bar.iconSize
        color: button.foreground
        opacity: root.playing ? 1 : 0.65
      }
      Text {
        visible: root.label !== ""
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, Style.space(root.maxWidth))
        text: root.label
        textFormat: Text.PlainText
        color: button.foreground
        font.family: button.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }
    }
  }
  PlayerPanel {
    id: panel
    bar: root.bar
    anchorItem: button
    hostWidget: root
    spotify: root.spotify
  }
}
