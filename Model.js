.pragma library
// Pure helpers shared by the widget, the service and the tests (node --test tests/).
// No QML imports here so the logic can run anywhere.

var SCROLL_ACTIONS = ["volume", "skip", "off"]
var WHEN_CLOSED = ["icon", "hide"]
var LOOP_STATES = ["none", "playlist", "track"]

// Spotify's desktop client owns org.mpris.MediaPlayer2.spotify. spotifyd and
// librespot-based players use the same prefix with a suffix, so match on it.
function isSpotifyPlayer(player) {
  if (!player) return false
  var dbus = String(player.dbusName || "").toLowerCase()
  var entry = String(player.desktopEntry || "").toLowerCase()
  return dbus.indexOf("org.mpris.mediaplayer2.spotify") === 0 || entry === "spotify"
}

// Prefer a playing Spotify player, then any with a track, then any at all.
// Mpris.players.values is a Qt list, not a JS Array, so only index into it.
function findSpotify(players) {
  var list = players && typeof players.length === "number" ? players : []
  var withTrack = null
  var any = null
  for (var i = 0; i < list.length; i++) {
    var p = list[i]
    if (!isSpotifyPlayer(p)) continue
    if (p.isPlaying) return p
    if (!withTrack && (p.trackTitle || p.trackArtist)) withTrack = p
    if (!any) any = p
  }
  return withTrack || any
}

// Spotify reports "/com/spotify/track/<id>" (or episode/ad/local) as the MPRIS
// track id and https://open.spotify.com/<type>/<id> as xesam:url. Returns a
// spotify:<type>:<id> URI for the kinds the Web API library accepts, else "".
function spotifyUri(trackId, url) {
  var pattern = /\/(track|episode)\/([A-Za-z0-9]{22})(?:$|[/?#])/
  var candidates = [String(trackId || ""), String(url || "")]
  for (var i = 0; i < candidates.length; i++) {
    var match = pattern.exec(candidates[i])
    if (match) return "spotify:" + match[1] + ":" + match[2]
  }
  return ""
}

function uriFromMetadata(metadata) {
  var m = metadata || {}
  return spotifyUri(m["mpris:trackid"], m["xesam:url"])
}

function normalizeEnum(value, options, fallback) {
  var v = String(value === undefined || value === null ? "" : value).trim().toLowerCase()
  return options.indexOf(v) !== -1 ? v : fallback
}

function flag(value, fallback) {
  if (typeof value === "string") {
    var v = value.trim().toLowerCase()
    if (/^(false|0|no|off)$/.test(v)) return false
    if (/^(true|1|yes|on)$/.test(v)) return true
    return fallback
  }
  return value === undefined || value === null ? fallback : !!value
}

function clampInt(value, min, max, fallback) {
  var n = Math.round(Number(value))
  if (!isFinite(n)) return fallback
  return Math.max(min, Math.min(max, n))
}

// Spotify Client IDs are 32 lowercase hex characters.
function normalizeClientId(value) {
  var v = String(value || "").trim().toLowerCase()
  return /^[0-9a-f]{32}$/.test(v) ? v : ""
}

function formatTime(seconds) {
  var s = Math.max(0, Math.floor(Number(seconds) || 0))
  var h = Math.floor(s / 3600)
  var m = Math.floor((s % 3600) / 60)
  var r = s % 60
  var mm = h > 0 && m < 10 ? "0" + m : String(m)
  return (h > 0 ? h + ":" : "") + mm + ":" + (r < 10 ? "0" : "") + r
}

function barLabel(title, artist, showArtist) {
  var t = String(title || "")
  var a = String(artist || "")
  if (!t) return showArtist ? a : ""
  return showArtist && a ? t + "  ·  " + a : t
}

function tooltip(running, title, artist, playing) {
  if (!running) return "Spotify is not running · click to open"
  if (!title) return "Spotify"
  return (playing ? "" : "Paused · ") + title + (artist ? " — " + artist : "")
}

// MprisLoopState is None=0, Track=1, Playlist=2. Spotify's button cycles
// off -> playlist -> track -> off, so mirror that order.
function nextLoopState(current) {
  if (current === 0) return 2
  if (current === 2) return 1
  return 0
}

function loopName(state) {
  if (state === 1) return "track"
  if (state === 2) return "playlist"
  return "none"
}

function clampVolume(value) {
  var v = Number(value)
  if (!isFinite(v)) return 0
  return Math.max(0, Math.min(1, Math.round(v * 100) / 100))
}

// Seek target in seconds, kept just inside the track so a seek past the end
// does not skip to the next song.
function seekTarget(position, delta, length) {
  var target = (Number(position) || 0) + (Number(delta) || 0)
  var max = Math.max(0, (Number(length) || 0) - 1)
  return Math.max(0, Math.min(max, target))
}

function volumeIcon(volume) {
  if (volume <= 0) return "󰝟"
  if (volume < 0.34) return "󰕿"
  if (volume < 0.67) return "󰖀"
  return "󰕾"
}

function deviceIcon(type) {
  switch (String(type || "").toLowerCase()) {
  case "smartphone": return "󰄜"
  case "tablet": return "󰓶"
  case "speaker": return "󰓃"
  case "tv": return "󰔂"
  case "avr":
  case "stb": return "󰗃"
  case "audiodongle":
  case "castaudio":
  case "castvideo": return "󰐻"
  case "automobile": return "󰄋"
  case "game_console": return "󰊴"
  default: return "󰍹"
  }
}

// Web API helpers -----------------------------------------------------------

function artistsText(item) {
  if (!item) return ""
  if (Array.isArray(item.artists)) return item.artists.map(function(a) { return a && a.name ? a.name : "" }).filter(Boolean).join(", ")
  if (item.show && item.show.name) return item.show.name
  return ""
}

// GET /me/player/queue -> [{ uri, title, artist }], at most `limit`.
function queueItems(response, limit) {
  var queue = response && Array.isArray(response.queue) ? response.queue : []
  var out = []
  var max = Math.max(0, Number(limit) || 0)
  for (var i = 0; i < queue.length && out.length < max; i++) {
    var item = queue[i]
    if (!item || !item.name) continue
    out.push({ uri: String(item.uri || ""), title: String(item.name), artist: artistsText(item) })
  }
  return out
}

// GET /me/player/devices -> [{ id, name, type, active, restricted, volume }],
// active first, then by name. Devices without an id cannot be targeted.
function deviceList(response) {
  var devices = response && Array.isArray(response.devices) ? response.devices : []
  var out = []
  for (var i = 0; i < devices.length; i++) {
    var d = devices[i]
    if (!d || !d.id) continue
    out.push({
      id: String(d.id),
      name: String(d.name || "Unknown device"),
      type: String(d.type || ""),
      active: !!d.is_active,
      restricted: !!d.is_restricted,
      volume: typeof d.volume_percent === "number" ? d.volume_percent : -1
    })
  }
  out.sort(function(a, b) {
    if (a.active !== b.active) return a.active ? -1 : 1
    return a.name.localeCompare(b.name)
  })
  return out
}

// Classify a Web API failure so the service can decide what to do next.
// Returns one of: "ok", "auth" (refresh and retry once), "rate" (back off),
// "quota" (the developer account's quota is spent), "premium", "offline",
// "no-device", "error".
function classifyResponse(status, bodyText) {
  if (status >= 200 && status < 300) return "ok"
  if (status === 0) return "offline"
  var reason = ""
  try {
    var body = JSON.parse(bodyText || "{}")
    reason = String((body.error && body.error.reason) || body.reason || "").toUpperCase()
  } catch (e) {}
  if (status === 401) return "auth"
  if (status === 429) return reason === "QUOTA_EXCEEDED" ? "quota" : "rate"
  if (status === 403 && reason === "PREMIUM_REQUIRED") return "premium"
  if (status === 404 && reason === "NO_ACTIVE_DEVICE") return "no-device"
  return "error"
}

// Seconds to wait after a 429, from Retry-After, bounded to [1, 3600].
function retryAfterSeconds(header, fallback) {
  var n = parseInt(String(header || ""), 10)
  if (!isFinite(n) || n <= 0) n = Number(fallback) || 30
  return Math.max(1, Math.min(3600, n))
}

function problemText(kind) {
  switch (kind) {
  case "quota": return "Spotify API quota used up for today; likes, queue and devices pause until it resets."
  case "rate": return "Spotify asked us to slow down; trying again shortly."
  case "premium": return "This needs Spotify Premium."
  case "offline": return "Can't reach Spotify right now."
  case "no-device": return "No active Spotify device."
  case "auth": return "Spotify sign-in expired. Sign in again."
  case "": return ""
  default: return "Spotify returned an error."
  }
}

if (typeof module !== "undefined") {
  module.exports = {
    SCROLL_ACTIONS: SCROLL_ACTIONS,
    WHEN_CLOSED: WHEN_CLOSED,
    LOOP_STATES: LOOP_STATES,
    isSpotifyPlayer: isSpotifyPlayer,
    findSpotify: findSpotify,
    spotifyUri: spotifyUri,
    uriFromMetadata: uriFromMetadata,
    normalizeEnum: normalizeEnum,
    flag: flag,
    clampInt: clampInt,
    normalizeClientId: normalizeClientId,
    formatTime: formatTime,
    barLabel: barLabel,
    tooltip: tooltip,
    nextLoopState: nextLoopState,
    loopName: loopName,
    clampVolume: clampVolume,
    seekTarget: seekTarget,
    volumeIcon: volumeIcon,
    deviceIcon: deviceIcon,
    artistsText: artistsText,
    queueItems: queueItems,
    deviceList: deviceList,
    classifyResponse: classifyResponse,
    retryAfterSeconds: retryAfterSeconds,
    problemText: problemText
  }
}
