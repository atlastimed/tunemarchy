import QtQuick
import QtQuick.Controls as QQC
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "atlastimed.tunemarchy"
  manageIpc: false
  property var spotify: null
  property var anchorItem: null
  property var hostWidget: null
  readonly property string viewerKey: "tunemarchy-panel-" + String(root)
  property string expanded: ""
  property string cursor: "play"
  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool available: spotify && spotify.connected
  readonly property bool hasTrack: available && spotify.title !== ""
  readonly property var actions: {
    var result = []
    if (spotify && spotify.canLike) result.push("like")
    if (spotify && spotify.canSeek) result.push("seek")
    if (spotify && spotify.canControl) result.push("shuffle", "previous")
    result.push("play")
    if (spotify && spotify.canControl) result.push("next", "repeat")
    if (spotify && spotify.canVolume) result.push("volume")
    if (spotify && spotify.accountConnected) result.push("queue", "devices")
    result.push("open")
    if (expanded === "devices" && spotify) spotify.devices.forEach(function(d, i) {
      if (!d.active && !d.restricted) result.push("device:" + i)
    })
    return result
  }
  onActionsChanged: if (actions.indexOf(cursor) < 0) cursor = "play"
  onOpenedChanged: {
    if (opened) { cursor = "play"; Qt.callLater(function() { keys.forceActiveFocus() }) }
    else expanded = ""
    syncWatch()
  }
  onExpandedChanged: syncWatch()
  onSpotifyChanged: syncWatch()
  Component.onDestruction: if (spotify) spotify.watch(viewerKey, false, "")
  function syncWatch() { if (spotify) spotify.watch(viewerKey, opened, expanded) }
  function move(dx, dy) {
    if (dx && cursor === "seek" && spotify) { spotify.seekBy(dx * 10); return }
    if (dx && cursor === "volume" && spotify) { spotify.setVolume(spotify.volume + dx * 0.05); return }
    var index = actions.indexOf(cursor)
    cursor = actions[(Math.max(0, index) + (dy || dx) + actions.length) % actions.length]
  }
  function activate(action) {
    if (!spotify) return
    switch (action) {
    case "play": spotify.playPause(); break
    case "previous": spotify.previous(); break
    case "next": spotify.next(); break
    case "shuffle": spotify.toggleShuffle(); break
    case "repeat": spotify.cycleRepeat(); break
    case "like": spotify.toggleLike(); break
    case "open": close(); spotify.launch(); break
    case "queue": case "devices": expanded = expanded === action ? "" : action; break
    default: if (action.indexOf("device:") === 0) {
      var d = spotify.devices[Number(action.slice(7))]
      if (d) spotify.transferTo(d.id)
    }
    }
  }
  Translations { id: strings; directory: Qt.resolvedUrl("i18n") }
  component Label: Text {
    textFormat: Text.PlainText
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
    wrapMode: Text.WordWrap
  }
  component Action: PlayerAction {
    property string action: ""
    foreground: root.foreground
    fontFamily: root.fontFamily
    hasCursor: root.cursor === action
    onPointed: root.cursor = action
    onClicked: root.activate(action)
    onHasCursorChanged: if (hasCursor && visible) Qt.callLater(function() {
      var point = mapToItem(content, 0, 0)
      if (point.y < scroll.contentY) scroll.contentY = Math.max(0, point.y)
      else if (point.y + height > scroll.contentY + scroll.height)
        scroll.contentY = Math.min(Math.max(0, scroll.contentHeight - scroll.height), point.y + height - scroll.height)
    })
  }
  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keys
    contentWidth: panel.fittedContentWidth(Style.space(352))
    contentHeight: panel.fittedContentHeight(content.implicitHeight, Style.space(620))
    PanelKeyCatcher {
      id: keys
      anchors.fill: parent
      onMoveRequested: (dx, dy) => root.move(dx, dy)
      onActivateRequested: root.activate(root.cursor)
      onCloseRequested: root.close()
      onTabRequested: function(direction) { if (root.bar) root.bar.switchPanelFrom(root.hostWidget || root, direction) }
      onTextKey: function(text) {
        var shortcut = {n: "next", p: "previous", s: "shuffle", r: "repeat", f: "like", o: "open", q: "queue", d: "devices"}
        if (shortcut[text]) root.activate(shortcut[text])
      }
      Flickable {
        id: scroll
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        QQC.ScrollBar.vertical: QQC.ScrollBar { policy: QQC.ScrollBar.AsNeeded }
        Column {
          id: content
          width: parent.width
          spacing: Style.spacing.controlGap
          Row {
            width: parent.width
            spacing: Style.space(12)
            Item {
              id: art
              width: Style.space(80)
              height: width
              Rectangle { anchors.fill: parent; color: Style.normalFillFor(root.foreground, Commons.Color.accent); radius: Style.cornerRadius }
              Image {
                id: cover
                anchors.fill: parent
                source: root.opened && root.spotify ? root.spotify.artUrl : ""
                sourceSize: Qt.size(160, 160)
                asynchronous: true
                fillMode: Image.PreserveAspectCrop
                visible: status === Image.Ready
              }
              Label { anchors.centerIn: parent; visible: !cover.visible; text: "󰓇"; font.pixelSize: Style.font.displayLarge }
            }
            Column {
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width - art.width - like.width - parent.spacing * 2
              spacing: Style.space(3)
              Label {
                width: parent.width
                text: root.hasTrack ? root.spotify.title : strings.t("title")
                font.pixelSize: Style.font.subtitle
                font.bold: true
                maximumLineCount: 2
                elide: Text.ElideRight
              }
              Label {
                width: parent.width
                text: root.hasTrack ? root.spotify.artist : strings.t(root.available ? "ready" : "unavailable")
                font.pixelSize: Style.font.bodySmall
                maximumLineCount: 2
                elide: Text.ElideRight
              }
              Label {
                width: parent.width
                visible: root.hasTrack
                text: root.spotify ? (root.spotify.deviceName || root.spotify.album) : ""
                font.pixelSize: Style.font.caption
                maximumLineCount: 1
                elide: Text.ElideRight
                opacity: 0.8
              }
            }
            Action {
              id: like
              action: "like"
              width: root.spotify && root.spotify.canLike ? implicitWidth : 0
              visible: width > 0
              anchors.verticalCenter: parent.verticalCenter
              iconText: root.spotify && root.spotify.liked ? "󰋑" : "󰋕"
              tooltipText: strings.t(root.spotify && root.spotify.liked ? "unlike" : "like")
              current: root.spotify && root.spotify.liked
            }
          }
          Column {
            width: parent.width
            visible: root.hasTrack && root.spotify.length > 0
            CursorSurface {
              width: parent.width
              height: seek.implicitHeight
              hasCursor: root.cursor === "seek"
              PanelSlider {
                id: seek
                width: parent.width
                bar: root.bar
                value: root.spotify ? root.spotify.position : 0
                maximum: root.spotify ? Math.max(1, root.spotify.length) : 1
                step: 1
                enabled: root.spotify && root.spotify.canSeek
                onMoved: root.cursor = "seek"
                onReleased: value => root.spotify.seekTo(value)
              }
            }
            Row {
              width: parent.width
              Label { width: parent.width / 2; text: Model.formatTime(seek.liveValue); font.pixelSize: Style.font.caption }
              Label { width: parent.width / 2; horizontalAlignment: Text.AlignRight; text: Model.formatTime(root.spotify ? root.spotify.length : 0); font.pixelSize: Style.font.caption }
            }
          }
          Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Style.space(4)
            Action { action: "shuffle"; iconText: "󰒟"; tooltipText: strings.t("shuffle"); enabled: root.spotify && root.spotify.canControl; current: root.spotify && root.spotify.shuffle }
            Action { action: "previous"; iconText: "󰒮"; tooltipText: strings.t("previous"); enabled: root.spotify && root.spotify.canControl }
            Action { action: "play"; iconText: root.spotify && root.spotify.playing ? "󰏤" : "󰐊"; tooltipText: strings.t(root.spotify && root.spotify.playing ? "pause" : "play"); iconSize: Style.font.iconLarge; bordered: true; width: Style.space(56) }
            Action { action: "next"; iconText: "󰒭"; tooltipText: strings.t("next"); enabled: root.spotify && root.spotify.canControl }
            Action { action: "repeat"; iconText: root.spotify && root.spotify.repeatMode === "track" ? "󰑘" : "󰑖"; tooltipText: strings.t("repeat"); enabled: root.spotify && root.spotify.canControl; current: root.spotify && root.spotify.repeatMode !== "off" }
          }
          CursorSurface {
            width: parent.width
            height: volume.implicitHeight
            visible: root.spotify && root.spotify.canVolume
            hasCursor: root.cursor === "volume"
            Row {
              width: parent.width
              spacing: Style.space(8)
              Label { width: Style.space(22); text: "󰕾"; anchors.verticalCenter: parent.verticalCenter }
              PanelSlider {
                id: volume
                width: parent.width - Style.space(72)
                bar: root.bar
                value: root.spotify ? root.spotify.volume : 0
                onMoved: function(value) { root.cursor = "volume"; root.spotify.setVolume(value) }
              }
              Label { width: Style.space(34); text: I18n.formatNumber(Math.round(volume.liveValue * 100)) + "%"; anchors.verticalCenter: parent.verticalCenter; font.pixelSize: Style.font.caption }
            }
          }
          PanelSeparator { foreground: root.foreground }
          Row {
            width: parent.width
            spacing: Style.space(4)
            Action { action: "queue"; text: strings.t("queue"); iconText: "󰲸"; width: (parent.width - parent.spacing * 2) / 3; enabled: root.spotify && root.spotify.accountConnected; current: root.expanded === "queue" }
            Action { action: "devices"; text: strings.t("devices"); iconText: "󰍹"; width: (parent.width - parent.spacing * 2) / 3; enabled: root.spotify && root.spotify.accountConnected; current: root.expanded === "devices" }
            Action { action: "open"; text: strings.t("openShort"); iconText: "󰏌"; width: (parent.width - parent.spacing * 2) / 3; tooltipText: strings.t("open") }
          }
          Column {
            width: parent.width
            visible: root.expanded === "queue"
            spacing: Style.spacing.sm
            Label {
              width: parent.width
              visible: !root.spotify || root.spotify.queue.length === 0
              text: strings.t(root.spotify && root.spotify.queueLoading ? "loading" : "emptyQueue")
              font.pixelSize: Style.font.bodySmall
            }
            Repeater {
              model: root.expanded === "queue" && root.spotify ? root.spotify.queue : []
              Column {
                required property var modelData
                width: parent.width
                spacing: Style.space(2)
                Label { width: parent.width; text: modelData.title; maximumLineCount: 1; elide: Text.ElideRight; font.pixelSize: Style.font.bodySmall }
                Label { width: parent.width; text: modelData.artist; maximumLineCount: 1; elide: Text.ElideRight; font.pixelSize: Style.font.caption; opacity: 0.8 }
                Item { width: 1; height: Style.space(4) }
              }
            }
          }
          Column {
            width: parent.width
            visible: root.expanded === "devices"
            spacing: Style.spacing.sm
            Label { width: parent.width; visible: !root.spotify || root.spotify.devices.length === 0; text: strings.t(root.spotify && root.spotify.devicesLoading ? "loading" : "emptyDevices"); font.pixelSize: Style.font.bodySmall }
            Repeater {
              model: root.expanded === "devices" && root.spotify ? root.spotify.devices : []
              Action {
                required property var modelData
                required property int index
                action: "device:" + index
                width: parent.width
                text: modelData.name
                iconText: modelData.active ? "󰄬" : "󰍹"
                enabled: !modelData.active && !modelData.restricted
                current: modelData.active
              }
            }
          }
          Label {
            width: parent.width
            visible: text !== ""
            text: !root.available ? strings.t("unavailable") : (!root.spotify.accountConnected ? strings.t("signIn") : root.spotify.error)
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }
}
