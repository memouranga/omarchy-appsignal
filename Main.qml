import QtQuick
import Quickshell
import Quickshell.Io

// Data side of the AppSignal bar widget. bin/appsignal-collect does one
// GraphQL request and writes a JSON overview; this file runs it on a
// schedule, watches the file, and exposes normalized apps for the panel.
Item {
  id: root
  visible: false

  property var settings: ({})

  readonly property int schemaVersion: 1

  readonly property string home: Quickshell.env("HOME") || ""
  readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || home + "/.local/state"
  readonly property string stateDir: stateHome + "/omarchy/appsignal"
  readonly property string overviewPath: stateDir + "/overview.json"
  readonly property string prefsPath: stateDir + "/panel.json"
  readonly property string collectorPath: {
    var url = String(Qt.resolvedUrl("bin/appsignal-collect"))
    return url.indexOf("file://") === 0 ? decodeURIComponent(url.substring(7)) : url
  }

  property var overview: ({})
  property int dataRevision: 0
  property int refreshIntervalSec: Math.max(30, Number(setting("refreshIntervalSec", 120)) || 120)
  property int incidentsPerApp: Math.max(1, Number(setting("incidentsPerApp", 5)) || 5)
  // v0.5: host warn thresholds, forwarded to the collector so it can compute
  // hosts[].warn and totals.hostsWarn itself (same pattern as incidentsPerApp).
  property int cpuWarn: Math.min(100, Math.max(1, Number(setting("cpuWarn", 80)) || 80))
  property int memWarn: Math.min(100, Math.max(1, Number(setting("memWarn", 85)) || 85))
  property int diskWarn: Math.min(100, Math.max(1, Number(setting("diskWarn", 85)) || 85))
  // "pinned" (default) shows only apps pinned in AppSignal, when at least one
  // exists; "all" always shows every app. No boolean setting type exists in
  // this Omarchy's manifest schema, so this reads as an enum.
  readonly property bool onlyPinnedSetting: String(setting("onlyPinned", "pinned") || "pinned") !== "all"
  property double lastRunMs: 0
  property string collectorError: ""

  readonly property bool loading: updateProcess.running

  function setting(name, fallback) {
    var value = root.settings ? root.settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  // ------------------------------------------------------------- refresh

  Timer {
    interval: root.refreshIntervalSec * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.runUpdate()
  }

  Process {
    id: updateProcess
    running: false
    property string errorText: ""
    onRunningChanged: if (running) errorText = ""

    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        updateProcess.errorText = text.trim()
        if (updateProcess.errorText !== "") console.warn("memong.appsignal", updateProcess.errorText)
      }
    }

    onExited: function(exitCode) {
      if (exitCode === 0) {
        root.collectorError = ""
        overviewFile.reload()
        return
      }
      Qt.callLater(function() {
        root.collectorError = updateProcess.errorText !== ""
          ? updateProcess.errorText
          : "Collector exited with code " + exitCode + "."
      })
    }
  }

  FileView {
    id: overviewFile
    path: root.overviewPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.parse(text())
    onLoadFailed: root.overview = ({})
  }

  function parse(content) {
    try {
      var parsed = JSON.parse(String(content || ""))
      root.overview = parsed && typeof parsed === "object" ? parsed : ({})
    } catch (e) {
      console.warn("memong.appsignal", "Ignoring bad overview", root.overviewPath, e)
      root.overview = ({})
    }
    root.dataRevision++
  }

  function runUpdate() {
    if (updateProcess.running) return
    var now = Date.now()
    if (now - root.lastRunMs < 15000) return
    root.lastRunMs = now
    updateProcess.command = [root.collectorPath, "-output", root.overviewPath,
                             "-limit", String(root.incidentsPerApp),
                             "-cpu-warn", String(root.cpuWarn),
                             "-mem-warn", String(root.memWarn),
                             "-disk-warn", String(root.diskWarn)]
    updateProcess.running = true
  }

  function refreshNow() { root.lastRunMs = 0; root.runUpdate() }
  function refreshOnOpen() { root.runUpdate() }

  // ------------------------------------------------------------ derived

  readonly property bool schemaOk: Number(root.overview.schemaVersion || 0) === root.schemaVersion
  readonly property bool ready: { var r = root.dataRevision; return schemaOk && root.overview.ready === true }
  readonly property bool stale: { var r = root.dataRevision; return schemaOk && root.overview.stale === true }
  readonly property string authHelpText: { var r = root.dataRevision; return schemaOk ? String(root.overview.authHelpText || "") : "" }
  readonly property string error: { var r = root.dataRevision; return schemaOk ? String(root.overview.error || "") : "" }
  readonly property string updatedAt: { var r = root.dataRevision; return schemaOk ? String(root.overview.updatedAt || "") : "" }
  readonly property var viewer: { var r = root.dataRevision; return schemaOk && root.overview.viewer ? root.overview.viewer : ({ name: "", email: "" }) }
  readonly property var totals: { var r = root.dataRevision; return schemaOk && root.overview.totals ? root.overview.totals : ({}) }

  // Flat list of every app the token can see, each carrying its org so the
  // panel can label it. Apps with something wrong float to the top.
  readonly property var allApps: {
    var r = root.dataRevision
    if (!schemaOk) return []
    var orgs = Array.isArray(root.overview.organizations) ? root.overview.organizations : []
    var out = []
    for (var i = 0; i < orgs.length; i++) {
      var org = orgs[i] || {}
      var apps = Array.isArray(org.apps) ? org.apps : []
      for (var j = 0; j < apps.length; j++) {
        var a = apps[j] || {}
        out.push({
          key: String(a.id || ""),
          id: String(a.id || ""),
          name: String(a.name || ""),
          environment: String(a.environment || ""),
          status: String(a.status || ""),
          pinned: a.pinned === true,
          orgName: String(org.name || ""),
          orgSlug: String(org.slug || ""),
          lastPushProcessedAt: String(a.lastPushProcessedAt || ""),
          url: String(a.url || ""),
          errorsUrl: String(a.errorsUrl || ""),
          perfUrl: String(a.perfUrl || ""),
          uptimeUrl: String(a.uptimeUrl || ""),
          checkInsUrl: String(a.checkInsUrl || ""),
          deploysUrl: String(a.deploysUrl || ""),
          errors: Array.isArray(a.errors) ? a.errors : [],
          perf: Array.isArray(a.perf) ? a.perf : [],
          monitors: Array.isArray(a.monitors) ? a.monitors : [],
          checkIns: Array.isArray(a.checkIns) ? a.checkIns : [],
          lastDeploy: a.lastDeploy && typeof a.lastDeploy === "object" ? a.lastDeploy : null,
          totals: a.totals && typeof a.totals === "object" ? a.totals : ({}),
          // v0.4: 1h health (throughput/errorRate/meanMs) and 24h slowest
          // actions, only populated for apps the collector's metrics phase
          // covered (pinned apps, or the fallback first 6). null/[] otherwise.
          health: a.health && typeof a.health === "object" ? a.health : null,
          // v0.4.1: ranked by impact (totalMs = meanMs * count), split web vs.
          // background. slowActions is kept as their concatenation only for
          // compatibility; the panel renders the two lists separately.
          slowWeb: Array.isArray(a.slowWeb) ? a.slowWeb : [],
          slowBackground: Array.isArray(a.slowBackground) ? a.slowBackground : [],
          slowActions: Array.isArray(a.slowActions) ? a.slowActions : [],
          // v0.5: one entry per host reporting metrics for this app; [] when
          // the app was outside the collector's metrics phase or that host
          // query failed for it.
          hosts: Array.isArray(a.hosts) ? a.hosts : []
        })
      }
    }
    out.sort(function(x, y) { return root.attention(y) - root.attention(x) })
    return out
  }

  readonly property bool anyPinned: {
    var list = root.allApps
    for (var i = 0; i < list.length; i++) if (list[i].pinned) return true
    return false
  }

  // True when the "only pinned" setting is on but nothing is pinned yet: the
  // panel falls back to showing everything and says so.
  readonly property bool pinnedFallback: root.onlyPinnedSetting && !root.anyPinned

  // The apps the panel actually shows: pinned-only when that setting is on
  // and at least one app is pinned, otherwise every app.
  readonly property var apps: {
    if (!root.onlyPinnedSetting || !root.anyPinned) return root.allApps
    return root.allApps.filter(function(a) { return a.pinned === true })
  }

  function attention(app) {
    var t = app.totals || {}
    return Number(t.monitorsDown || 0) * 100 + Number(t.checkInsFailing || 0) * 50 +
      Number(t.hostsWarn || 0) * 20 + Number(t.errors || 0) * 2 + Number(t.perf || 0)
  }

  // Totals over the visible apps only, so a pinned-down view doesn't have the
  // bar dot or tooltip alarm about apps the panel isn't even showing.
  readonly property var visibleTotals: {
    var list = root.apps
    var out = { errors: 0, perf: 0, monitors: 0, monitorsDown: 0, checkIns: 0, checkInsFailing: 0, hostsWarn: 0 }
    for (var i = 0; i < list.length; i++) {
      var t = list[i].totals || {}
      out.errors += Number(t.errors || 0)
      out.perf += Number(t.perf || 0)
      out.monitors += Number(t.monitors || 0)
      out.monitorsDown += Number(t.monitorsDown || 0)
      out.checkIns += Number(t.checkIns || 0)
      out.checkInsFailing += Number(t.checkInsFailing || 0)
      out.hostsWarn += Number(t.hostsWarn || 0)
    }
    return out
  }

  readonly property int openErrors: Number(visibleTotals.errors || 0)
  readonly property int openPerf: Number(visibleTotals.perf || 0)
  readonly property int monitorsDown: Number(visibleTotals.monitorsDown || 0)
  readonly property int checkInsFailing: Number(visibleTotals.checkInsFailing || 0)
  readonly property int hostsWarn: Number(visibleTotals.hostsWarn || 0)
  readonly property bool urgent: monitorsDown > 0 || checkInsFailing > 0
  readonly property bool attentionNeeded: urgent || openErrors > 0 || hostsWarn > 0

  // ------------------------------------------------------- app selection

  property string selectedAppId: ""

  readonly property int selectedAppIndex: {
    var list = root.apps
    for (var i = 0; i < list.length; i++) if (list[i].id === root.selectedAppId) return i
    return 0
  }

  // The selected app, or the first visible one if the persisted id no longer
  // exists (removed, unpinned, or never set), or null when nothing is visible.
  readonly property var selectedApp: {
    var list = root.apps
    if (list.length === 0) return null
    for (var i = 0; i < list.length; i++) if (list[i].id === root.selectedAppId) return list[i]
    return list[0]
  }

  function selectApp(id) {
    if (!id || id === root.selectedAppId) return
    root.selectedAppId = String(id)
    root.savePrefs()
  }

  function stepApp(delta) {
    var list = root.apps
    if (list.length === 0) return
    var next = ((root.selectedAppIndex + delta) % list.length + list.length) % list.length
    root.selectApp(list[next].id)
  }

  function savePrefs() {
    prefsFile.setText(JSON.stringify({ selectedAppId: root.selectedAppId }, null, 2) + "\n")
  }

  function loadPrefs(content) {
    try {
      var parsed = JSON.parse(String(content || "{}"))
      root.selectedAppId = parsed && typeof parsed === "object" ? String(parsed.selectedAppId || "") : ""
    } catch (e) {
      root.selectedAppId = ""
    }
  }

  FileView {
    id: prefsFile
    path: root.prefsPath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadPrefs(text())
    onLoadFailed: root.selectedAppId = ""
  }
}
