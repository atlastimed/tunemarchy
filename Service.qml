import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import "Model.js" as Model

// Singleton for every bar (one per monitor). Playback state and controls come
// straight from Spotify's MPRIS interface and cost nothing. The optional Web
// API layer (likes, queue, devices) only runs once a Client ID is configured,
// and only calls Spotify when a track changes or a dropdown is open.
Item {
  id: root

  property var shell: null
  property var manifest: null

  // ---- player (MPRIS) -----------------------------------------------------
  readonly property var players: Mpris.players ? Mpris.players.values : []
  readonly property var player: Model.findSpotify(players)
  readonly property bool running: player !== null
  readonly property bool playing: !!(player && player.isPlaying)
  readonly property bool hasTrack: title !== "" || artist !== ""
  readonly property string title: player ? (player.trackTitle || "") : ""
  readonly property string artist: player ? (player.trackArtist || "") : ""
  readonly property string album: player ? (player.trackAlbum || "") : ""
  readonly property string artUrl: player ? (player.trackArtUrl || "") : ""
  readonly property string trackUri: player ? Model.uriFromMetadata(player.metadata) : ""
  readonly property real length: player && player.lengthSupported ? player.length : 0
  readonly property bool canSeek: !!(player && player.canSeek && player.positionSupported && length > 0)
  readonly property bool canShuffle: !!(player && player.shuffleSupported)
  readonly property bool shuffle: !!(player && player.shuffle)
  readonly property bool canLoop: !!(player && player.loopSupported)
  readonly property int loopState: player && player.loopSupported ? player.loopState : 0
  readonly property bool canVolume: !!(player && player.volumeSupported)
  readonly property real volume: canVolume ? player.volume : 0

  function launch() {
    Quickshell.execDetached(["omarchy-launch-spotify"])
  }

  function playPause() {
    if (!player) return launch()
    if (player.isPlaying) {
      if (player.canPause) player.pause()
    } else if (player.canPlay) {
      player.play()
    }
  }

  function next() { if (player && player.canGoNext) player.next() }
  function previous() { if (player && player.canGoPrevious) player.previous() }

  function seekTo(seconds) {
    if (canSeek) player.position = Model.seekTarget(seconds, 0, length)
  }

  function seekBy(delta) {
    if (canSeek) player.position = Model.seekTarget(player.position, delta, length)
  }

  function setVolume(value) {
    if (canVolume) player.volume = Model.clampVolume(value)
  }

  function toggleShuffle() {
    if (canShuffle) player.shuffle = !player.shuffle
  }

  function cycleLoop() {
    if (canLoop) player.loopState = Model.nextLoopState(player.loopState)
  }

  // ---- Web API: sign-in -----------------------------------------------------
  readonly property string pluginDir: {
    var url = Qt.resolvedUrl(".").toString()
    return decodeURIComponent(url.replace(/^file:\/\//, "")).replace(/\/$/, "")
  }
  readonly property string backend: pluginDir + "/backend/tunemarchyctl"
  // The system interpreter, not whatever is first on PATH (mise, venvs).
  readonly property string python: "/usr/bin/python3"

  property string clientId: ""
  // off: no Client ID · checking · signed-out · signing-in · ready · error
  property string authState: "off"
  property string authMessage: ""
  property string problem: ""
  readonly property bool apiReady: authState === "ready"

  property string _accessToken: ""
  property real _expiresAt: 0
  property var _waiting: []
  property string _queuedHelper: ""
  property real _pausedUntil: 0

  function configure(settings) {
    var id = Model.normalizeClientId(settings ? settings.clientId : "")
    if (id === clientId) return
    clientId = id
    _accessToken = ""
    _expiresAt = 0
    _flushWaiting("")
    liked = ({})
    queue = []
    devices = []
    problem = ""
    authMessage = ""
    _queuedHelper = ""
    if (!id) {
      authState = "off"
      _stopHelper()
      return
    }
    authState = "checking"
    _stopHelper()
    runHelper("token")
  }

  // Ends a running helper without treating its exit as a result.
  function _stopHelper() {
    if (!helper.running) return
    helper.discard = true
    helper.running = false
  }

  function signIn() {
    if (!clientId || authState === "signing-in") return
    authState = "signing-in"
    authMessage = "Finish signing in in your browser…"
    runHelper("login")
  }

  function cancelSignIn() {
    if (authState !== "signing-in") return
    if (helper.mode === "login") _stopHelper()
    authState = "signed-out"
    authMessage = ""
  }

  function signOut() {
    if (!clientId) return
    _accessToken = ""
    _expiresAt = 0
    liked = ({})
    queue = []
    devices = []
    authState = "signed-out"
    authMessage = ""
    runHelper("logout")
  }

  // One helper at a time; the latest request waits for the running one. A
  // sign-in can sit in the browser for minutes, so a sign-out replaces it.
  function runHelper(mode) {
    if (!clientId) return
    if (helper.running) {
      if (helper.mode === mode && mode === "token") return
      _queuedHelper = mode
      if (helper.mode === "login" && mode === "logout") _stopHelper()
      return
    }
    helper.mode = mode
    helper.lastLine = ""
    helper.discard = false
    helper.command = [python, "-I", backend, mode, "--client-id", clientId]
    helper.running = true
  }

  function _runQueuedHelper() {
    var queued = _queuedHelper
    _queuedHelper = ""
    if (queued) runHelper(queued)
  }

  function helperFinished(mode, line) {
    var result = null
    try { result = JSON.parse(line || "") } catch (e) {}
    if (!result) result = { ok: false, error: "crashed", message: "The sign-in helper stopped unexpectedly." }
    var previous = authState

    if (mode === "logout") {
      authState = "signed-out"
    } else if (result.ok && result.accessToken) {
      _accessToken = String(result.accessToken)
      _expiresAt = Date.now() + Math.max(60, Number(result.expiresIn) - 60) * 1000
      authState = "ready"
      authMessage = String(result.warning || "")
      problem = ""
      retryTimer.stop()
      _flushWaiting(_accessToken)
      likeTimer.restart()
      if (watched()) refreshPanelData(true)
    } else {
      _accessToken = ""
      _flushWaiting("")
      var kind = String(result.error || "error")
      if (kind === "signed-out") {
        authState = "signed-out"
        // Nothing stored at start-up is normal; losing a live session is news.
        authMessage = previous === "ready" ? Model.problemText("auth") : ""
      } else if (kind === "denied" || kind === "timeout" || kind === "port-busy") {
        authState = "signed-out"
        authMessage = String(result.message || "")
      } else {
        authState = "error"
        authMessage = String(result.message || "Spotify sign-in failed.")
        if (kind === "offline") retryTimer.restart()
      }
    }
    _runQueuedHelper()
  }

  function _flushWaiting(token) {
    var list = _waiting
    _waiting = []
    for (var i = 0; i < list.length; i++) list[i](token)
  }

  function withToken(callback) {
    if (_accessToken && Date.now() < _expiresAt) {
      callback(_accessToken)
      return
    }
    if (authState !== "ready" && authState !== "checking") {
      callback("")
      return
    }
    _waiting = _waiting.concat([callback])
    runHelper("token")
  }

  // ---- Web API: requests ----------------------------------------------------
  function api(method, path, body, done) {
    if (Date.now() < _pausedUntil) {
      done(false, null, problem || "rate")
      return
    }
    withToken(function(token) {
      if (!token) done(false, null, "auth")
      else _send(method, path, body, done, token, false)
    })
  }

  function _send(method, path, body, done, token, retried) {
    var xhr = new XMLHttpRequest()
    xhr.onreadystatechange = function() {
      if (xhr.readyState !== XMLHttpRequest.DONE) return
      var kind = Model.classifyResponse(xhr.status, xhr.responseText)
      if (kind === "auth" && !retried) {
        root._accessToken = ""
        root.withToken(function(fresh) {
          if (fresh) root._send(method, path, body, done, fresh, true)
          else done(false, null, "auth")
        })
        return
      }
      if (kind === "rate" || kind === "quota") {
        var wait = Model.retryAfterSeconds(xhr.getResponseHeader("Retry-After"), kind === "quota" ? 3600 : 30)
        root._pausedUntil = Date.now() + wait * 1000
      }
      if (kind !== "ok") {
        if (kind !== "no-device") root.problem = kind
        done(false, null, kind)
        return
      }
      root.problem = ""
      var data = null
      try { data = xhr.responseText ? JSON.parse(xhr.responseText) : null } catch (e) {}
      done(true, data, "ok")
    }
    xhr.open(method, "https://api.spotify.com/v1" + path)
    xhr.setRequestHeader("Authorization", "Bearer " + token)
    if (body !== null && body !== undefined) {
      xhr.setRequestHeader("Content-Type", "application/json")
      xhr.send(JSON.stringify(body))
    } else if (method === "PUT" || method === "POST") {
      xhr.send("")  // Spotify answers a body-less PUT without Content-Length with 411
    } else {
      xhr.send()
    }
  }

  // ---- Web API: liked songs -------------------------------------------------
  property var liked: ({})
  readonly property bool likeKnown: trackUri !== "" && liked[trackUri] !== undefined
  readonly property bool currentLiked: trackUri !== "" && liked[trackUri] === true

  function _setLiked(uri, value) {
    var next = {}
    var keys = Object.keys(liked)
    // Keep the cache small; it only has to cover recent skips.
    for (var i = Math.max(0, keys.length - 100); i < keys.length; i++) next[keys[i]] = liked[keys[i]]
    if (value === undefined) delete next[uri]
    else next[uri] = value
    liked = next
  }

  function refreshLiked() {
    var uri = trackUri
    if (!apiReady || !uri || liked[uri] !== undefined) return
    api("GET", "/me/library/contains?uris=" + encodeURIComponent(uri), null, function(ok, data) {
      if (ok && Array.isArray(data) && data.length > 0) root._setLiked(uri, data[0] === true)
    })
  }

  function toggleLike() {
    var uri = trackUri
    if (!apiReady || !uri || !likeKnown) return
    var was = liked[uri] === true
    _setLiked(uri, !was)
    api(was ? "DELETE" : "PUT", "/me/library?uris=" + encodeURIComponent(uri), null, function(ok) {
      if (!ok) root._setLiked(uri, was)
    })
  }

  // Wait for skips to settle before asking about the new track.
  Timer {
    id: likeTimer
    interval: 700
    onTriggered: root.refreshLiked()
  }

  onTrackUriChanged: {
    likeTimer.restart()
    if (watched()) queueTimer.restart()
  }

  // ---- Web API: queue and devices (only while a dropdown is open) -----------
  property var queue: []
  property var devices: []
  property bool devicesLoaded: false
  property real _lastTouch: 0
  property real _lastPanelRefresh: 0

  // Dropdowns call this when they open and every few seconds while open.
  function touch() {
    var first = !watched()
    _lastTouch = Date.now()
    if (first) refreshPanelData(false)
  }

  function watched() {
    return Date.now() - _lastTouch < 20000
  }

  function refreshPanelData(force) {
    if (!apiReady) return
    if (!force && Date.now() - _lastPanelRefresh < 4000) return
    _lastPanelRefresh = Date.now()
    refreshQueue()
    refreshDevices()
  }

  function refreshQueue() {
    if (!apiReady) return
    api("GET", "/me/player/queue", null, function(ok, data) {
      if (ok) root.queue = Model.queueItems(data, 5)
    })
  }

  function refreshDevices() {
    if (!apiReady) return
    api("GET", "/me/player/devices", null, function(ok, data) {
      if (ok) {
        root.devices = Model.deviceList(data)
        root.devicesLoaded = true
      }
    })
  }

  function transferTo(deviceId) {
    if (!apiReady || !deviceId) return
    api("PUT", "/me/player", { device_ids: [String(deviceId)], play: root.playing }, function(ok) {
      if (ok) devicesTimer.restart()
    })
  }

  // The queue reflects a skip a moment after MPRIS reports it.
  Timer {
    id: queueTimer
    interval: 1200
    onTriggered: root.refreshQueue()
  }

  // Spotify takes a second to report the new active device.
  Timer {
    id: devicesTimer
    interval: 1500
    onTriggered: root.refreshDevices()
  }

  Timer {
    id: retryTimer
    interval: 60000
    onTriggered: if (root.clientId && root.authState === "error") root.runHelper("token")
  }

  Process {
    id: helper
    property string mode: ""
    property string lastLine: ""
    stdout: SplitParser {
      onRead: function(line) { if (line.trim()) helper.lastLine = line }
    }
    stderr: SplitParser {
      onRead: function(line) { console.warn("[tunemarchy] " + line) }
    }
    property bool discard: false
    onExited: function(exitCode, exitStatus) {
      if (helper.discard) {
        helper.discard = false
        root._runQueuedHelper()
      } else {
        root.helperFinished(helper.mode, helper.lastLine)
      }
    }
  }

  function statusJson() {
    return JSON.stringify({
      running: root.running,
      playing: root.playing,
      title: root.title,
      artist: root.artist,
      album: root.album,
      uri: root.trackUri,
      liked: root.likeKnown ? root.currentLiked : null,
      auth: root.authState
    })
  }

  IpcHandler {
    target: "tunemarchy"

    function status(): string { return root.statusJson() }
    // Diagnostics: every MPRIS player the shell can see.
    function players(): string {
      var out = []
      for (var i = 0; i < root.players.length; i++) {
        var p = root.players[i]
        out.push({ dbusName: p.dbusName, identity: p.identity, desktopEntry: p.desktopEntry, playing: p.isPlaying })
      }
      return JSON.stringify(out)
    }
    function playPause(): string { root.playPause(); return "ok" }
    function next(): string { root.next(); return "ok" }
    function previous(): string { root.previous(); return "ok" }
    function like(): string {
      if (!root.apiReady || !root.likeKnown) return "unavailable"
      root.toggleLike()
      return root.currentLiked ? "liked" : "unliked"
    }
    function seek(seconds: string): string {
      var delta = Number(seconds)
      if (!isFinite(delta) || !root.canSeek) return "unavailable"
      root.seekBy(delta)
      return "ok"
    }
  }

  Component.onDestruction: _stopHelper()
}
