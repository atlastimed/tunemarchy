.pragma library
var SCROLL_ACTIONS = ["volume", "skip", "off"]
var WHEN_CLOSED = ["icon", "hide"]
function normalizeEnum(value, options, fallback) {
  var v = String(value === undefined || value === null ? "" : value).trim().toLowerCase()
  return options.indexOf(v) >= 0 ? v : fallback
}
function flag(value, fallback) {
  if (typeof value === "string") {
    if (/^(false|0|no|off)$/i.test(value.trim())) return false
    if (/^(true|1|yes|on)$/i.test(value.trim())) return true
    return fallback
  }
  return value === undefined || value === null ? fallback : !!value
}
function clampInt(value, min, max, fallback) {
  var n = Math.round(Number(value))
  return isFinite(n) ? Math.max(min, Math.min(max, n)) : fallback
}
function clampVolume(value) {
  var n = Number(value)
  return isFinite(n) ? Math.max(0, Math.min(1, Math.round(n * 100) / 100)) : 0
}
function seekTarget(position, delta, length) {
  return Math.max(0, Math.min(Math.max(0, (Number(length) || 0) - 1), (Number(position) || 0) + (Number(delta) || 0)))
}
function formatTime(value) {
  var seconds = Math.max(0, Math.floor(Number(value) || 0))
  return Math.floor(seconds / 60) + ":" + String(seconds % 60).padStart(2, "0")
}
function barLabel(title, artist, showArtist) {
  return title ? title + (showArtist && artist ? "  ·  " + artist : "") : (showArtist ? artist : "")
}
// Shared Omarchy tooltip components use AutoText.
function tooltipText(value) {
  return "<span>" + String(value || "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;") + "</span>"
}
function safeArt(value) {
  var url = String(value || "")
  return url.length <= 2048 && /^https:\/\/(?:i\.scdn\.co|mosaic\.scdn\.co|image-cdn-[a-z0-9-]+\.spotifycdn\.com)\//i.test(url) ? url : ""
}
function parseSnapshot(line) {
  if (typeof line !== "string" || line.length > 65536) return null
  var data
  try { data = JSON.parse(line) } catch (_) { return null }
  if (!data || data.v !== 1) return null
  var out = {v: 1}
  ;["connected", "running", "playing", "canPlay", "canControl", "canVolume", "canLike", "liked", "shuffle",
    "queueLoading", "queueLoaded", "devicesLoading", "devicesLoaded"].forEach(function(k) { out[k] = data[k] === true })
  ;["title", "artist", "album", "deviceName", "error"].forEach(function(k) { out[k] = String(data[k] || "").slice(0, 512) })
  out.artUrl = safeArt(data.artUrl)
  out.volume = clampVolume(data.volume)
  out.length = clampInt(data.length, 0, 604800, 0)
  out.position = Math.min(out.length, Math.max(0, Number(data.position) || 0))
  out.repeat = normalizeEnum(data.repeat, ["off", "context", "track"], "off")
  out.queue = (Array.isArray(data.queue) ? data.queue : []).slice(0, 10).filter(Boolean).map(function(q) {
    return {title: String(q.title || "").slice(0, 512), artist: String(q.artist || "").slice(0, 512)}
  })
  out.devices = (Array.isArray(data.devices) ? data.devices : []).slice(0, 32).filter(function(d) { return d && typeof d.id === "string" && d.id.length <= 256 }).map(function(d) {
    return {id: d.id, name: String(d.name || "Device").slice(0, 512), active: d.active === true, restricted: d.restricted === true}
  })
  return out
}
