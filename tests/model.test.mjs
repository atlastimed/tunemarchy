// Tests for Model.js, the pure helpers behind the bar label, the dropdown and
// the Web API layer. Run with: node --test tests/
import { test } from "node:test"
import assert from "node:assert/strict"
import { readFileSync } from "node:fs"

const source = readFileSync(new URL("../Model.js", import.meta.url), "utf8").replace(/^\.pragma library$/m, "")
const module = { exports: {} }
new Function("module", source)(module)
const M = module.exports

// Quickshell hands QML a Qt list, which is array-like but not an Array.
const qtList = (...items) => Object.assign(Object.create(null), items, { length: items.length })

test("finds Spotify among MPRIS players, preferring the one playing", () => {
  const chromium = { dbusName: "org.mpris.MediaPlayer2.chromium.instance9", isPlaying: true, trackTitle: "Video" }
  const idle = { dbusName: "org.mpris.MediaPlayer2.spotify", desktopEntry: "spotify", isPlaying: false }
  const spotifyd = { dbusName: "org.mpris.MediaPlayer2.spotifyd.instance42", isPlaying: true, trackTitle: "Song" }
  assert.equal(M.findSpotify([chromium, idle]), idle)
  assert.equal(M.findSpotify([idle, spotifyd]), spotifyd)
  assert.equal(M.findSpotify(qtList(chromium, idle)), idle)
  assert.equal(M.findSpotify([chromium]), null)
  assert.equal(M.findSpotify(null), null)
})

test("prefers a Spotify player with a track over an empty one", () => {
  const empty = { dbusName: "org.mpris.MediaPlayer2.spotify", isPlaying: false }
  const loaded = { dbusName: "org.mpris.MediaPlayer2.spotifyd", isPlaying: false, trackTitle: "Song" }
  assert.equal(M.findSpotify([empty, loaded]), loaded)
})

test("builds Spotify URIs from MPRIS metadata", () => {
  const id = "0xXK0qpcPTFenmNDs4RoWr"
  assert.equal(M.uriFromMetadata({ "mpris:trackid": `/com/spotify/track/${id}` }), `spotify:track:${id}`)
  assert.equal(M.uriFromMetadata({ "xesam:url": `https://open.spotify.com/episode/${id}?si=x` }), `spotify:episode:${id}`)
  assert.equal(M.uriFromMetadata({ "mpris:trackid": "/com/spotify/ad/abc" }), "")
  assert.equal(M.uriFromMetadata({ "mpris:trackid": "/com/spotify/local/Artist/Album/Song/123" }), "")
  assert.equal(M.uriFromMetadata({ "mpris:trackid": "/com/spotify/track/short" }), "")
  assert.equal(M.uriFromMetadata(undefined), "")
})

test("settings fall back to safe values", () => {
  assert.equal(M.normalizeEnum("Volume", M.SCROLL_ACTIONS, "volume"), "volume")
  assert.equal(M.normalizeEnum("skip", M.SCROLL_ACTIONS, "volume"), "skip")
  assert.equal(M.normalizeEnum("sideways", M.SCROLL_ACTIONS, "volume"), "volume")
  assert.equal(M.normalizeEnum(null, M.WHEN_CLOSED, "icon"), "icon")
  assert.equal(M.flag("off", true), false)
  assert.equal(M.flag("yes", false), true)
  assert.equal(M.flag("maybe", true), true)
  assert.equal(M.flag(undefined, false), false)
  assert.equal(M.clampInt("9000", 0, 800, 240), 800)
  assert.equal(M.clampInt("abc", 0, 800, 240), 240)
})

test("accepts only well-formed Client IDs", () => {
  assert.equal(M.normalizeClientId(" 0123456789ABCDEF0123456789ABCDEF "), "0123456789abcdef0123456789abcdef")
  assert.equal(M.normalizeClientId("0123abcd"), "")
  assert.equal(M.normalizeClientId("zz".repeat(16)), "")
  assert.equal(M.normalizeClientId(undefined), "")
})

test("formats track times", () => {
  assert.equal(M.formatTime(0), "0:00")
  assert.equal(M.formatTime(9.9), "0:09")
  assert.equal(M.formatTime(278.9), "4:38")
  assert.equal(M.formatTime(3725), "1:02:05")
  assert.equal(M.formatTime(-4), "0:00")
  assert.equal(M.formatTime(NaN), "0:00")
})

test("bar label and tooltip", () => {
  assert.equal(M.barLabel("Song", "Artist", true), "Song  ·  Artist")
  assert.equal(M.barLabel("Song", "Artist", false), "Song")
  assert.equal(M.barLabel("", "Artist", true), "Artist")
  assert.equal(M.barLabel("", "", true), "")
  assert.match(M.tooltip(false, "", "", false), /not running/)
  assert.equal(M.tooltip(true, "Song", "Artist", true), "Song — Artist")
  assert.equal(M.tooltip(true, "Song", "", false), "Paused · Song")
})

test("repeat cycles like Spotify's button: off, playlist, track", () => {
  assert.equal(M.nextLoopState(0), 2)
  assert.equal(M.nextLoopState(2), 1)
  assert.equal(M.nextLoopState(1), 0)
  assert.equal(M.loopName(1), "track")
  assert.equal(M.loopName(2), "playlist")
  assert.equal(M.loopName(0), "none")
})

test("seek and volume stay in range", () => {
  assert.equal(M.seekTarget(5, -10, 200), 0)
  assert.equal(M.seekTarget(195, 10, 200), 199)
  assert.equal(M.seekTarget(50, 10, 200), 60)
  assert.equal(M.seekTarget(50, 10, 0), 0)
  assert.equal(M.clampVolume(1.04), 1)
  assert.equal(M.clampVolume(-0.1), 0)
  assert.equal(M.clampVolume(0.731182), 0.73)
  assert.equal(M.clampVolume("x"), 0)
})

test("queue items keep title and artist, capped", () => {
  const response = {
    currently_playing: { name: "Now" },
    queue: [
      { uri: "spotify:track:a", name: "One", artists: [{ name: "A" }, { name: "B" }] },
      { uri: "spotify:episode:b", name: "Two", show: { name: "Podcast" } },
      null,
      { uri: "spotify:track:c" },
      { uri: "spotify:track:d", name: "Three", artists: [] }
    ]
  }
  assert.deepEqual(M.queueItems(response, 5), [
    { uri: "spotify:track:a", title: "One", artist: "A, B" },
    { uri: "spotify:episode:b", title: "Two", artist: "Podcast" },
    { uri: "spotify:track:d", title: "Three", artist: "" }
  ])
  assert.equal(M.queueItems(response, 1).length, 1)
  assert.deepEqual(M.queueItems(null, 5), [])
})

test("devices: active first, then by name; id-less devices dropped", () => {
  const response = {
    devices: [
      { id: "b", name: "Phone", type: "Smartphone", is_active: false, volume_percent: 40 },
      { id: null, name: "Ghost" },
      { id: "c", name: "Desk", type: "Computer", is_active: true, is_restricted: false, volume_percent: 73 },
      { id: "a", name: "Kitchen", type: "Speaker", is_restricted: true }
    ]
  }
  const list = M.deviceList(response)
  assert.deepEqual(list.map(d => d.id), ["c", "a", "b"])
  assert.equal(list[0].active, true)
  assert.equal(list[1].restricted, true)
  assert.equal(list[1].volume, -1)
  assert.deepEqual(M.deviceList({}), [])
})

test("device icons fall back to a computer", () => {
  assert.equal(M.deviceIcon("Smartphone"), "󰄜")
  assert.equal(M.deviceIcon("nonsense"), M.deviceIcon("Computer"))
})

test("classifies Web API responses", () => {
  assert.equal(M.classifyResponse(200, "[true]"), "ok")
  assert.equal(M.classifyResponse(204, ""), "ok")
  assert.equal(M.classifyResponse(0, ""), "offline")
  assert.equal(M.classifyResponse(401, "{}"), "auth")
  assert.equal(M.classifyResponse(429, ""), "rate")
  assert.equal(M.classifyResponse(429, '{"reason":"QUOTA_EXCEEDED"}'), "quota")
  assert.equal(M.classifyResponse(429, '{"error":{"status":429,"reason":"QUOTA_EXCEEDED"}}'), "quota")
  assert.equal(M.classifyResponse(403, '{"error":{"reason":"PREMIUM_REQUIRED"}}'), "premium")
  assert.equal(M.classifyResponse(404, '{"error":{"reason":"NO_ACTIVE_DEVICE"}}'), "no-device")
  assert.equal(M.classifyResponse(500, "<html>"), "error")
})

test("Retry-After is bounded", () => {
  assert.equal(M.retryAfterSeconds("12", 30), 12)
  assert.equal(M.retryAfterSeconds("", 30), 30)
  assert.equal(M.retryAfterSeconds("999999", 30), 3600)
  assert.equal(M.retryAfterSeconds("-3", 0), 30)
})

test("problem text covers every kind", () => {
  for (const kind of ["quota", "rate", "premium", "offline", "no-device", "auth", "error"]) {
    assert.notEqual(M.problemText(kind), "")
  }
  assert.equal(M.problemText(""), "")
})
