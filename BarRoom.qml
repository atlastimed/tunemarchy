pragma ComponentBehavior: Bound

import QtQuick

// How much wider a bar widget may grow before its section runs into the next
// one. The bar lays its sections out without looking at each other, so a long
// label in one would otherwise be drawn straight over its neighbour.
//
// This reads the bar's own items, which a plugin is given no interface for. If
// the bar's structure ever changes, it finds nothing and steps aside: the
// allowance stays unlimited and the widget's own cap applies as before.
Item {
  id: room
  visible: false

  // The widget, and its width when it shows no label.
  property Item widget: null
  property real baseWidth: 0
  // Which of the widget's edges stays put as it grows: "start", "end" or "center".
  property string edge: "center"
  // Clear space kept between two sections.
  property real gap: 12
  property bool active: true

  // The most the widget may add to baseWidth. Infinity until measured.
  property real allowance: Infinity

  property var watched: []
  property Item section: null
  property bool queued: false
  property int attempts: 0

  Timer {
    id: search
    interval: 250
    onTriggered: {
      room.attempts++
      room.schedule()
    }
  }

  function isSection(item) {
    return !!item && typeof item.region === "string" && item.keys !== undefined
      && item.listRows !== undefined
  }

  function sectionOf(item) {
    var at = item ? item.parent : null
    for (var depth = 0; at && depth < 16; depth++) {
      if (isSection(at)) return at
      at = at.parent
    }
    return null
  }

  function collect(item, depth, found) {
    if (!item || depth > 10 || item.visible === false) return
    if (isSection(item)) {
      found.push(item)
      return
    }
    var kids = item.children
    if (!kids) return
    for (var i = 0; i < kids.length; i++) collect(kids[i], depth + 1, found)
  }

  function unwatch() {
    for (var i = 0; i < watched.length; i++) {
      var item = watched[i]
      try {
        item.widthChanged.disconnect(room.schedule)
        item.xChanged.disconnect(room.schedule)
        item.visibleChanged.disconnect(room.schedule)
      } catch (e) { /* the bar already let go of it */ }
    }
    watched = []
    section = null
  }

  function watch() {
    unwatch()
    var mine = sectionOf(widget)
    if (!mine || mine.region === "tray") return
    var top = mine
    while (top.parent) top = top.parent
    var found = []
    collect(top, 0, found)
    if (found.indexOf(mine) < 0) return
    for (var i = 0; i < found.length; i++) {
      found[i].widthChanged.connect(room.schedule)
      found[i].xChanged.connect(room.schedule)
      found[i].visibleChanged.connect(room.schedule)
    }
    watched = found
    section = mine
  }

  function schedule() {
    if (queued) return
    queued = true
    Qt.callLater(room.measure)
  }

  function measure() {
    queued = false
    if (!active || !widget) {
      allowance = Infinity
      return
    }
    if (sectionOf(widget) !== section || !section) watch()
    if (!section) {
      allowance = Infinity
      // The widget is built before the bar puts it in a section.
      if (attempts < 40) search.start()
      return
    }
    attempts = 0
    var own = section.mapToItem(null, 0, 0)
    var left = own.x
    var right = own.x + section.width
    var middle = (left + right) / 2
    var top = section
    while (top.parent) top = top.parent
    var before = 0
    var after = top.width
    for (var i = 0; i < watched.length; i++) {
      var other = watched[i]
      if (other === section || !other.visible || other.width <= 0) continue
      var at = other.mapToItem(null, 0, 0)
      var otherMiddle = at.x + other.width / 2
      if (otherMiddle < middle) before = Math.max(before, at.x + other.width + gap)
      else after = Math.min(after, at.x - gap)
    }
    var free = edge === "end" ? left - before
      : (edge === "start" ? after - right
        : 2 * Math.min(left - before, after - right))
    var extra = Math.max(0, widget.width - baseWidth)
    allowance = Math.max(0, Math.floor(free + extra))
  }

  onWidgetChanged: schedule()
  onActiveChanged: schedule()
  onBaseWidthChanged: schedule()
  onEdgeChanged: schedule()
  Component.onCompleted: schedule()
  Component.onDestruction: unwatch()
}
