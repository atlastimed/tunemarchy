import QtQuick
import QtQuick.Controls
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// Now-playing label in the bar plus a keyboard-driven dropdown with seek,
// transport, volume and, once signed in, likes, the queue and Connect
// devices. One instance exists per monitor; all of them share the Service.
Panel {
  id: root
  moduleName: "atlastimed.tunemarchy"
  manageIpc: false

  readonly property string pluginId: "atlastimed.tunemarchy"
  property var spotify: null
  readonly property bool vertical: bar ? bar.vertical : false

  // ---- settings ------------------------------------------------------------
  readonly property bool showArtist: Model.flag(setting("showArtist", true), true)
  readonly property int maxWidth: Model.clampInt(setting("maxWidth", 240), 0, 800, 240)
  readonly property string whenClosed: Model.normalizeEnum(setting("whenClosed", "icon"), Model.WHEN_CLOSED, "icon")
  readonly property string scrollAction: Model.normalizeEnum(setting("scrollAction", "volume"), Model.SCROLL_ACTIONS, "volume")
  readonly property var serviceConfig: ({ clientId: String(setting("clientId", "")) })

  // ---- state -----------------------------------------------------------------
  readonly property var player: spotify ? spotify.player : null
  readonly property bool running: spotify ? spotify.running : false
  readonly property bool playing: spotify ? spotify.playing : false
  readonly property string title: spotify ? spotify.title : ""
  readonly property string artist: spotify ? spotify.artist : ""
  readonly property string authState: spotify ? spotify.authState : "off"
  readonly property bool apiReady: spotify ? spotify.apiReady : false
  readonly property var queue: spotify ? spotify.queue : []
  readonly property var devices: spotify ? spotify.devices : []
  readonly property string label: maxWidth > 0 && !vertical ? Model.barLabel(title, artist, showArtist) : ""
  readonly property bool shown: running || whenClosed === "icon"

  // ---- look --------------------------------------------------------------------
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color glyphColor: playing ? barForeground : Qt.darker(barForeground, running ? 1.4 : 1.9)

  visible: shown
  implicitWidth: shown ? button.implicitWidth : 0
  implicitHeight: shown ? button.implicitHeight : 0

  function resolveService() {
    if (spotify) return
    var api = bar ? bar.shell : null
    if (api && typeof api.serviceFor === "function") spotify = api.serviceFor(pluginId) || null
  }

  function pushConfig() {
    if (spotify) spotify.configure(serviceConfig)
  }

  onBarChanged: resolveService()
  onSpotifyChanged: pushConfig()
  onServiceConfigChanged: pushConfig()
  onOpenedChanged: if (opened) {
    if (spotify) spotify.touch()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  // The service can appear after the widget (plugin rescans, hot reloads).
  Timer {
    interval: 400
    repeat: true
    running: !root.spotify
    triggeredOnStart: true
    onTriggered: root.resolveService()
  }

  // MPRIS position is not reactive; ask for it only while someone is looking.
  Timer {
    interval: 500
    repeat: true
    running: root.opened && root.playing
    onTriggered: if (root.player) root.player.positionChanged()
  }

  // Keeps queue and devices fresh while the dropdown stays open.
  Timer {
    interval: 10000
    repeat: true
    running: root.opened
    onTriggered: if (root.spotify) root.spotify.touch()
  }

  // ---- actions -----------------------------------------------------------------
  function openSpotify() {
    if (spotify) spotify.launch()
    close()
  }

  function nudgeVolume(delta) {
    if (spotify && spotify.canVolume) spotify.setVolume(spotify.volume + delta)
  }

  function wheelStep(delta) {
    if (!spotify || !running || delta === 0) return
    if (scrollAction === "volume") nudgeVolume(delta > 0 ? 0.05 : -0.05)
    else if (scrollAction === "skip") delta > 0 ? spotify.previous() : spotify.next()
  }

  function moveCursor(dx, dy) {
    if (!spotify) return
    if (dx !== 0) spotify.seekBy(dx * 10)
    else if (dy !== 0) nudgeVolume(dy > 0 ? -0.05 : 0.05)
  }

  function handleKey(text) {
    if (!spotify) return
    var index = "123456789".indexOf(text)
    switch (text) {
    case "n": spotify.next(); break
    case "p": spotify.previous(); break
    case "s": spotify.toggleShuffle(); break
    case "r": spotify.cycleLoop(); break
    case "f": spotify.toggleLike(); break
    case "o": openSpotify(); break
    default:
      if (index !== -1 && index < devices.length) spotify.transferTo(devices[index].id)
    }
  }

  // ---- bar button ----------------------------------------------------------------
  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    labelVisible: false
    hasVisualContent: true
    fixedWidth: root.vertical ? -1 : (root.label !== "" ? Math.ceil(barRow.implicitWidth + scaledHorizontalMargin * 2) : Style.bar.iconSlot)
    fixedHeight: root.vertical ? barRow.implicitHeight + Style.space(12) : -1
    tooltipText: root.opened ? "" : Model.tooltip(root.running, root.title, root.artist, root.playing)

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.MiddleButton) { if (root.spotify) root.spotify.playPause() }
      else if (buttonCode === Qt.RightButton || !root.running) root.openSpotify()
      else root.toggle()
    }
    onWheelMoved: function(delta) { root.wheelStep(delta) }

    Row {
      id: barRow
      anchors.centerIn: parent
      spacing: Style.space(4)
      scale: button.pressScale

      // The bar's own icon canvas: optically centred and sized like the icons
      // beside it, as BarIconButton draws Omarchy's icons.
      OpticalGlyph {
        id: glyph
        width: Style.bar.iconCanvas
        height: Style.bar.iconCanvas
        text: "󰓇"
        color: root.glyphColor
        fontFamily: root.fontFamily
        fontSize: Style.bar.iconFont
        paintedSize: Style.bar.iconSize

        Behavior on color {
          enabled: !root.bar || root.bar.foregroundAnimationEnabled
          ColorAnimation { duration: 160 }
        }
      }

      Item {
        visible: root.label !== ""
        width: trackTitle.width
        height: Style.bar.iconCanvas

        Text {
          id: trackTitle
          width: Math.min(root.maxWidth, implicitWidth)
          textFormat: Text.PlainText
          text: root.label
          elide: Text.ElideRight
          color: root.playing ? root.barForeground : Qt.darker(root.barForeground, 1.3)
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          renderType: Text.NativeRendering
          // Centre the figures, not the line box, as the bar's labels do.
          y: (parent.height - height) / 2 + (titleMetrics.descent - titleMetrics.ascent + titleMetrics.tightBoundingRect("0").height) / 2
        }

        FontMetrics { id: titleMetrics; font: trackTitle.font }
      }
    }
  }

  // ---- dropdown --------------------------------------------------------------------
  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(680))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) { root.moveCursor(dx, dy) }
      onActivateRequested: if (root.spotify) root.spotify.playPause()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) { root.handleKey(t) }

      Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: parent.width
          spacing: Style.space(12)

          // -- not running
          Column {
            visible: !root.running
            width: parent.width
            spacing: Style.space(10)

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: "Spotify isn't running"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
            }

            Button {
              text: "Open Spotify"
              iconText: "󰓇"
              foreground: root.foreground
              fontFamily: root.fontFamily
              bordered: true
              onClicked: root.openSpotify()
            }
          }

          // -- now playing
          Row {
            visible: root.running
            width: parent.width
            spacing: Style.space(12)

            BorderSurface {
              id: art
              width: Style.space(76)
              height: Style.space(76)
              radius: Style.spacing.labelGap
              color: Style.normalFillFor(root.foreground, Commons.Color.accent)
              borderSpec: Border.controlSpec("normal", root.foreground, Commons.Color.accent)

              Image {
                id: cover
                anchors.fill: parent
                anchors.margins: Style.space(2)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize.width: Style.space(152)
                sourceSize.height: Style.space(152)
                source: root.spotify ? root.spotify.artUrl : ""
                visible: status === Image.Ready
              }

              Text {
                anchors.centerIn: parent
                visible: !cover.visible
                textFormat: Text.PlainText
                text: "󰝚"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.displayLarge
              }
            }

            Column {
              width: parent.width - art.width - parent.spacing - (likeButton.visible ? likeButton.width + parent.spacing : 0)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(3)

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: root.title || "Nothing playing"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.subtitle
                font.bold: true
                elide: Text.ElideRight
              }

              Text {
                width: parent.width
                visible: text !== ""
                textFormat: Text.PlainText
                text: root.artist
                color: Qt.darker(root.foreground, 1.25)
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }

              Text {
                width: parent.width
                visible: text !== ""
                textFormat: Text.PlainText
                text: root.spotify ? root.spotify.album : ""
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }
            }

            PanelActionButton {
              id: likeButton
              anchors.verticalCenter: parent.verticalCenter
              visible: root.apiReady && root.spotify && root.spotify.trackUri !== ""
              enabled: root.spotify && root.spotify.likeKnown
              opacity: enabled ? 1 : 0.4
              iconText: root.spotify && root.spotify.currentLiked ? "󰋑" : "󰋕"
              foreground: root.spotify && root.spotify.currentLiked ? Commons.Color.accent : root.foreground
              fontFamily: root.fontFamily
              tooltipText: root.spotify && root.spotify.currentLiked ? "Remove from Liked Songs (f)" : "Save to Liked Songs (f)"
              onClicked: root.spotify.toggleLike()
            }
          }

          // -- progress
          Column {
            visible: root.running && root.spotify && root.spotify.length > 0
            width: parent.width
            spacing: Style.space(2)

            PanelSlider {
              id: seek
              bar: root.bar
              width: parent.width
              minimum: 0
              maximum: root.spotify ? Math.max(1, root.spotify.length) : 1
              step: 1
              value: root.player ? root.player.position : 0
              enabled: root.spotify && root.spotify.canSeek
              onReleased: function(v) { root.spotify.seekTo(v) }
            }

            Item {
              width: parent.width
              height: elapsed.implicitHeight

              Text {
                id: elapsed
                anchors.left: parent.left
                textFormat: Text.PlainText
                text: Model.formatTime(seek.liveValue)
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }

              Text {
                anchors.right: parent.right
                textFormat: Text.PlainText
                text: Model.formatTime(root.spotify ? root.spotify.length : 0)
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }

          // -- transport
          Row {
            visible: root.running
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: Style.space(6)

            Button {
              iconText: root.spotify && root.spotify.shuffle ? "󰒟" : "󰒞"
              tooltipText: "Shuffle (s)"
              active: root.spotify && root.spotify.shuffle
              foreground: root.foreground
              enabled: root.spotify && root.spotify.canShuffle
              opacity: enabled ? 1 : 0.4
              onClicked: root.spotify.toggleShuffle()
            }

            Button {
              iconText: "󰒮"
              tooltipText: "Previous (p)"
              foreground: root.foreground
              enabled: root.player && root.player.canGoPrevious
              opacity: enabled ? 1 : 0.4
              onClicked: root.spotify.previous()
            }

            Button {
              iconText: root.playing ? "󰏤" : "󰐊"
              tooltipText: root.playing ? "Pause (Space)" : "Play (Space)"
              foreground: root.foreground
              iconSize: Style.font.iconLarge
              horizontalPadding: Style.spacing.panelGap
              bordered: true
              onClicked: root.spotify.playPause()
            }

            Button {
              iconText: "󰒭"
              tooltipText: "Next (n)"
              foreground: root.foreground
              enabled: root.player && root.player.canGoNext
              opacity: enabled ? 1 : 0.4
              onClicked: root.spotify.next()
            }

            Button {
              iconText: root.spotify && root.spotify.loopState === 1 ? "󰑘" : "󰑖"
              tooltipText: "Repeat: " + Model.loopName(root.spotify ? root.spotify.loopState : 0) + " (r)"
              active: root.spotify && root.spotify.loopState !== 0
              foreground: root.foreground
              enabled: root.spotify && root.spotify.canLoop
              opacity: enabled ? 1 : 0.4
              onClicked: root.spotify.cycleLoop()
            }
          }

          // -- volume
          Row {
            visible: root.running && root.spotify && root.spotify.canVolume
            width: parent.width
            spacing: Style.space(8)

            Text {
              id: volumeGlyph
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(18)
              textFormat: Text.PlainText
              text: Model.volumeIcon(root.spotify ? root.spotify.volume : 0)
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              horizontalAlignment: Text.AlignHCenter
            }

            PanelSlider {
              bar: root.bar
              width: parent.width - volumeGlyph.width - parent.spacing
              minimum: 0
              maximum: 1
              step: 0.05
              value: root.spotify ? root.spotify.volume : 0
              onMoved: function(v) { root.spotify.setVolume(v) }
            }
          }

          // -- up next
          Column {
            visible: root.apiReady && root.queue.length > 0
            width: parent.width
            spacing: Style.space(4)

            PanelSectionHeader {
              text: "Up next"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Repeater {
              model: root.queue

              Row {
                required property var modelData
                width: parent.width
                spacing: Style.space(6)

                Text {
                  id: queueTitle
                  width: Math.min(implicitWidth, parent.width * 0.6)
                  textFormat: Text.PlainText
                  text: modelData.title
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideRight
                }

                Text {
                  width: parent.width - queueTitle.width - parent.spacing
                  textFormat: Text.PlainText
                  text: modelData.artist
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  elide: Text.ElideRight
                }
              }
            }
          }

          // -- devices
          Column {
            visible: root.apiReady && root.devices.length > 0
            width: parent.width
            spacing: Style.space(4)

            PanelSectionHeader {
              text: "Devices"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Repeater {
              model: root.devices

              BorderSurface {
                id: deviceRow
                required property var modelData
                required property int index

                width: parent.width
                height: deviceInner.implicitHeight + Style.space(10)
                radius: Style.spacing.labelGap
                color: modelData.active ? Style.selectedFillFor(root.foreground, Commons.Color.accent)
                  : (deviceMouse.containsMouse ? Style.normalFillFor(root.foreground, Commons.Color.accent) : "transparent")
                borderSpec: modelData.active ? Border.controlSpec("normal", root.foreground, Commons.Color.accent) : Border.none()
                opacity: modelData.restricted ? 0.5 : 1

                Row {
                  id: deviceInner
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.leftMargin: Style.space(8)
                  anchors.rightMargin: Style.space(8)
                  spacing: Style.space(8)

                  Text {
                    width: Style.space(18)
                    textFormat: Text.PlainText
                    text: Model.deviceIcon(deviceRow.modelData.type)
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    horizontalAlignment: Text.AlignHCenter
                  }

                  Text {
                    width: parent.width - Style.space(18) - shortcut.width - parent.spacing * 2
                    textFormat: Text.PlainText
                    text: deviceRow.modelData.name
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    font.bold: deviceRow.modelData.active
                    elide: Text.ElideRight
                  }

                  Text {
                    id: shortcut
                    textFormat: Text.PlainText
                    text: deviceRow.index < 9 ? String(deviceRow.index + 1) : ""
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }

                MouseArea {
                  id: deviceMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  enabled: !deviceRow.modelData.active && !deviceRow.modelData.restricted
                  cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                  onClicked: root.spotify.transferTo(deviceRow.modelData.id)
                }
              }
            }
          }

          // -- Spotify account (likes, queue, devices)
          PanelSeparator {
            visible: root.authState !== "ready"
            foreground: root.foreground
          }

          Column {
            width: parent.width
            spacing: Style.space(8)

            Text {
              width: parent.width
              visible: text !== ""
              wrapMode: Text.WordWrap
              textFormat: Text.PlainText
              text: {
                if (!root.spotify) return ""
                switch (root.authState) {
                case "off": return "Add your Spotify app's Client ID in this widget's settings to like songs and see your queue and devices."
                case "checking": return "Connecting to Spotify…"
                case "signed-out": return root.spotify.authMessage || "Sign in to like songs and see your queue and devices."
                case "signing-in": return root.spotify.authMessage
                case "error": return root.spotify.authMessage
                default: return root.spotify.authMessage || Model.problemText(root.spotify.problem)
                }
              }
              color: root.authState === "error" ? Commons.Color.urgent : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Row {
              spacing: Style.space(6)
              visible: root.authState === "signed-out" || root.authState === "signing-in" || root.authState === "error"

              Button {
                visible: root.authState === "signed-out"
                text: "Sign in to Spotify"
                iconText: "󰍂"
                foreground: root.foreground
                fontFamily: root.fontFamily
                bordered: true
                onClicked: root.spotify.signIn()
              }

              Button {
                visible: root.authState === "signing-in"
                text: "Cancel"
                foreground: root.foreground
                fontFamily: root.fontFamily
                onClicked: root.spotify.cancelSignIn()
              }

              Button {
                visible: root.authState === "error"
                text: "Try again"
                foreground: root.foreground
                fontFamily: root.fontFamily
                bordered: true
                onClicked: root.spotify.runHelper("token")
              }
            }
          }

          // -- footer
          Item {
            width: parent.width
            height: hints.implicitHeight
            visible: root.running

            Text {
              id: hints
              anchors.left: parent.left
              width: parent.width - (root.apiReady ? signOut.implicitWidth + Style.space(8) : 0)
              textFormat: Text.PlainText
              wrapMode: Text.WordWrap
              text: "Space play · ←→ seek · ↑↓ volume · n/p skip" + (root.apiReady ? " · f like · 1–9 device" : "")
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Text {
              id: signOut
              anchors.right: parent.right
              anchors.bottom: parent.bottom
              visible: root.apiReady
              textFormat: Text.PlainText
              text: "Sign out"
              color: signOutMouse.containsMouse ? root.foreground : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.underline: signOutMouse.containsMouse

              MouseArea {
                id: signOutMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.spotify.signOut()
              }
            }
          }
        }
      }
    }
  }
}
