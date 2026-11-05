import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

Item {
  id: root
  property var shell: null
  property var manifest: null
  property var snapshot: ({})
  property var viewers: ({})
  property string section: ""
  readonly property bool watched: Object.keys(viewers).length > 0
  readonly property bool connected: socket.connected && snapshot.v === 1
  readonly property bool running: connected && snapshot.running === true
  readonly property bool playing: connected && snapshot.playing === true
  readonly property string title: connected ? snapshot.title || "" : ""
  readonly property string artist: connected ? snapshot.artist || "" : ""
  readonly property string album: connected ? snapshot.album || "" : ""
  readonly property string artUrl: connected ? snapshot.artUrl || "" : ""
  readonly property real position: connected ? snapshot.position || 0 : 0
  readonly property real length: connected ? snapshot.length || 0 : 0
  readonly property real volume: connected ? snapshot.volume || 0 : 0
  readonly property bool canPlay: connected && snapshot.canPlay === true
  readonly property bool canControl: connected && snapshot.canControl === true
  readonly property bool canSeek: canControl && length > 0
  readonly property bool canVolume: connected && snapshot.canVolume === true
  readonly property bool canLike: connected && snapshot.canLike === true
  readonly property bool liked: connected && snapshot.liked === true
  readonly property bool shuffle: connected && snapshot.shuffle === true
  readonly property string repeatMode: connected ? snapshot.repeat || "off" : "off"
  readonly property bool accountConnected: connected && snapshot.connected === true
  readonly property var queue: connected ? snapshot.queue || [] : []
  readonly property var devices: connected ? snapshot.devices || [] : []
  readonly property string deviceName: connected ? snapshot.deviceName || "" : ""
  readonly property string error: connected ? snapshot.error || "" : ""
  readonly property bool queueLoading: connected && snapshot.queueLoading === true
  readonly property bool devicesLoading: connected && snapshot.devicesLoading === true
  readonly property bool queueLoaded: connected && snapshot.queueLoaded === true
  readonly property bool devicesLoaded: connected && snapshot.devicesLoaded === true

  function launch() {
    Quickshell.execDetached(["omarchy-shell", "shell", "summon", "io.github.atlastimed.omaspotify", "{}"])
  }
  function send(action, value) {
    if (!connected) return false
    socket.write(JSON.stringify({v: 1, action: action, value: value}) + "\n")
    socket.flush()
    return true
  }
  function playPause() { if (canPlay) send("playPause"); else launch() }
  function next() { if (canControl) send("next") }
  function previous() { if (canControl) send("previous") }
  function seekTo(value) { if (canSeek) send("seek", Model.seekTarget(value, 0, length)) }
  function seekBy(delta) { seekTo(position + delta) }
  function setVolume(value) { if (canVolume) send("volume", Model.clampVolume(value)) }
  function toggleShuffle() { if (canControl) send("shuffle") }
  function cycleRepeat() { if (canControl) send("repeat") }
  function toggleLike() { if (canLike) send("like") }
  function transferTo(id) {
    if (devices.some(function(d) { return d.id === id && !d.restricted && !d.active })) send("device", id)
  }
  function watch(key, visible, details) {
    var next = Object.assign({}, viewers)
    if (visible) next[key] = details || ""
    else delete next[key]
    viewers = next
    var values = Object.values(next)
    section = values.indexOf("devices") >= 0 && values.indexOf("queue") >= 0 ? "both" : values.indexOf("devices") >= 0 ? "devices" : (values.indexOf("queue") >= 0 ? "queue" : "")
    sendWatch()
  }
  function sendWatch() {
    if (!socket.connected) return
    socket.write(JSON.stringify({v: 1, action: "watch", visible: watched, section: section}) + "\n")
    socket.flush()
  }
  Socket {
    id: socket
    path: Quickshell.env("XDG_RUNTIME_DIR") + "/atlastimed-omaspotify-"
      + Qt.md5(Quickshell.env("WAYLAND_DISPLAY")).slice(0, 12) + ".sock"
    onConnectedChanged: {
      root.snapshot = ({})
      if (connected) { retry.stop(); root.sendWatch() }
      else retry.restart()
    }
    onError: retry.restart()
    parser: SplitParser {
      onRead: function(line) {
        var next = Model.parseSnapshot(line)
        if (next) root.snapshot = next
      }
    }
  }
  Timer {
    id: retry
    interval: 3000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: if (!socket.connected && Quickshell.env("XDG_RUNTIME_DIR")) socket.connected = true
  }
  IpcHandler {
    target: "tunemarchy"
    function status(): string { return JSON.stringify(root.snapshot) }
    function playPause(): void { root.playPause() }
    function next(): void { root.next() }
    function previous(): void { root.previous() }
    function like(): void { root.toggleLike() }
    function seek(seconds: string): void { var n = Number(seconds); if (isFinite(n)) root.seekBy(n) }
  }
}
