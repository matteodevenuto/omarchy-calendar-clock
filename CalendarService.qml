import QtQuick
import Quickshell
import Quickshell.Io
import "CalendarModel.js" as Model

Item {
  id: root

  property var settings: ({})

  property var events: []
  property var buckets: ({})
  property var feeds: []
  property bool configured: false
  property bool stale: false
  property string error: ""
  property var generatedAt: null
  property bool syncing: syncProcess.running || feedProcess.running
  property bool everLoaded: false

  readonly property string feedError: Model.firstFeedError(feeds)

  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 900, 60, 86400)
  readonly property int dayStartHour: intSetting("dayStartHour", 7, 0, 23)
  readonly property int dayEndHour: Math.max(dayStartHour + 1, intSetting("dayEndHour", 22, 1, 24))
  readonly property string feedsFile: stringSetting("feedsFile", "")

  SystemClock {
    id: clock
    precision: SystemClock.Minutes
  }
  readonly property date now: clock.date
  readonly property string todayKey: Model.keyForDate(now)

  readonly property var nextEvent: Model.nextUpcoming(events, now)
  readonly property string nextRelative: Model.relativeLabel(nextEvent, now)
  readonly property var todayEvents: Model.eventsOn(buckets, todayKey)

  function scriptPath(name) {
    return String(Qt.resolvedUrl("bin/" + name)).replace(/^file:\/\//, "")
  }

  function intSetting(name, fallback, min, max) {
    var v = parseInt(settings ? settings[name] : undefined, 10)
    if (isNaN(v)) return fallback
    return Math.max(min, Math.min(max, v))
  }

  function stringSetting(name, fallback) {
    var v = settings ? settings[name] : undefined
    if (v === undefined || v === null) return fallback
    return String(v)
  }

  function syncArgs(extra) {
    // -I: ignore PYTHON* env vars and the user site dir, so imports stay in system paths
    var args = ["/usr/bin/python3", "-I", scriptPath("calendars-sync")]
    if (feedsFile !== "") args = args.concat(["--feeds", feedsFile])
    return extra ? args.concat(extra) : args
  }

  // Backend runs with a cleared environment; pass only what it needs.
  readonly property var syncEnv: {
    var env = { "HOME": Quickshell.env("HOME"), "LC_ALL": "C.UTF-8" }
    var tz = Quickshell.env("TZ")
    if (tz) env["TZ"] = tz
    return env
  }

  function apply(text) {
    var state = Model.readPayload(text)
    root.events = state.events
    root.buckets = Model.bucketByDay(state.events)
    root.feeds = state.feeds
    root.configured = state.configured
    root.stale = state.stale
    root.error = state.error
    root.generatedAt = state.generatedAt
    root.everLoaded = true
  }

  function refresh() {
    if (syncProcess.running) return
    syncProcess.command = syncArgs(null)
    syncProcess.running = true
  }

  function ensureFresh() {
    if (!everLoaded) { loadCached(); return }
    if (!generatedAt) { refresh(); return }
    var age = (now.getTime() - generatedAt.getTime()) / 1000
    if (age >= refreshIntervalSec) refresh()
  }

  function loadCached() {
    if (cacheProcess.running) return
    cacheProcess.command = syncArgs(["--cached"])
    cacheProcess.running = true
  }

  function addFeed(url, name) {
    var trimmed = String(url || "").replace(/^\s+|\s+$/g, "")
    if (trimmed === "" || feedProcess.running) return
    runFeedOperation({ "action": "add", "url": trimmed, "name": String(name || "") })
  }

  function removeFeed(url) {
    if (feedProcess.running) return
    runFeedOperation({ "action": "remove", "url": String(url) })
  }

  function setFeedColor(url, color) {
    if (feedProcess.running) return
    runFeedOperation({ "action": "color", "url": String(url), "color": String(color) })
  }

  function moveFeed(url, index) {
    if (feedProcess.running) return
    runFeedOperation({ "action": "move", "url": String(url), "index": Number(index) })
  }

  function runFeedOperation(operation) {
    feedProcess.input = JSON.stringify(operation) + "\n"
    feedProcess.command = syncArgs(["--feed-operation-stdin"])
    feedProcess.running = true
  }

  Process {
    id: syncProcess
    command: []
    clearEnvironment: true
    environment: root.syncEnv
    stdout: StdioCollector { id: syncStdout; waitForEnd: true }
    onExited: function (exitCode) {
      if (exitCode === 0) root.apply(String(syncStdout.text || ""))
      else root.error = "sync failed (exit " + exitCode + ")"
    }
  }

  Process {
    id: cacheProcess
    command: []
    clearEnvironment: true
    environment: root.syncEnv
    stdout: StdioCollector { id: cacheStdout; waitForEnd: true }
    onExited: function (exitCode) {
      if (exitCode === 0) root.apply(String(cacheStdout.text || ""))
      root.everLoaded = true
    }
  }

  Process {
    id: feedProcess
    property string input: ""
    command: []
    clearEnvironment: true
    environment: root.syncEnv
    stdinEnabled: true
    stdout: StdioCollector { id: feedStdout; waitForEnd: true }
    onStarted: write(input)
    onExited: function (exitCode) {
      input = ""
      if (exitCode === 0) root.apply(String(feedStdout.text || ""))
      else root.error = "calendar update failed (exit " + exitCode + ")"
    }
  }

  Timer {
    id: refreshTimer
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: true
    onTriggered: root.refresh()
  }

  Component.onCompleted: {
    loadCached()
    firstSync.start()
  }

  Timer {
    id: firstSync
    interval: 1200
    repeat: false
    onTriggered: root.refresh()
  }
}
