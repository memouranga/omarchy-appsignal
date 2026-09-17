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
  // v0.7: a flag file that turns dry-run on without touching the shell's
  // environment (which would need `omarchy restart shell` to pick up).
  readonly property string dryRunFlagPath: stateDir + "/dry-run"
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
  // v0.6: job queue wait-time warn threshold (ms), same pattern as the host
  // warn thresholds — forwarded to the collector so it can compute
  // queues[].warn and totals.queuesWarn itself.
  property int queueTimeWarn: Math.max(1, Number(setting("queueTimeWarn", 30000)) || 30000)
  // v0.6: comma-separated queue names the collector leaves out entirely, for
  // queues that are noise on this machine's bar (e.g. a queue that only ever
  // carries scheduled work). Empty by default.
  readonly property string ignoreQueues: String(setting("ignoreQueues", "") || "")
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

  // ------------------------------------------------------------- dry-run
  //
  // v0.7 (SPEC.md "Dry-run"): every action that would otherwise run a real
  // shell command (agent prompt, browser) goes through Panel.qml's single
  // runAction(cmd), which checks this property. Dry-run is on when either
  // $OMARCHY_APPSIGNAL_DRY_RUN=1 (read once, at startup — this is an
  // environment variable, the shell only sees it on launch) or the flag file
  // below exists, watched live so it can be toggled without a shell restart.
  readonly property bool dryRunEnv: Quickshell.env("OMARCHY_APPSIGNAL_DRY_RUN") === "1"
  property bool dryRunFlagPresent: false
  readonly property bool dryRun: root.dryRunEnv || root.dryRunFlagPresent

  FileView {
    id: dryRunFlagFile
    path: root.dryRunFlagPath
    watchChanges: true
    printErrors: false
    onLoaded: root.dryRunFlagPresent = true
    onLoadFailed: root.dryRunFlagPresent = false
  }

  // ------------------------------------------------------------ sections
  //
  // v0.7: which sections are visible and in what order. Comma list, read
  // left to right; unknown keys are dropped and duplicates collapsed to
  // their first occurrence. Falls back to every section, in the shipped
  // order, when the setting is empty or ends up with nothing valid in it.
  readonly property var validSections: ["alerts", "errors", "performance", "servers", "uptime", "jobs", "checkins", "deploy"]
  readonly property var defaultSectionOrder: root.validSections.slice()
  readonly property var sectionOrder: {
    var raw = String(setting("sections", root.defaultSectionOrder.join(",")) || "")
    var parts = raw.split(",")
    var out = []
    for (var i = 0; i < parts.length; i++) {
      var key = parts[i].trim().toLowerCase()
      if (key === "") continue
      if (root.validSections.indexOf(key) < 0) continue
      if (out.indexOf(key) >= 0) continue
      out.push(key)
    }
    return out.length > 0 ? out : root.defaultSectionOrder
  }

  // v0.7: order of the app tabs. "attention" (default) = apps with something
  // wrong first, as before; "name" = alphabetical, stable; "pinned" = the
  // order AppSignal itself returns (no client-side sort at all).
  readonly property string appOrderSetting: {
    var v = String(setting("appOrder", "attention") || "attention").toLowerCase()
    return (v === "name" || v === "pinned") ? v : "attention"
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
                             "-disk-warn", String(root.diskWarn),
                             "-queue-time-warn", String(root.queueTimeWarn),
                             "-ignore-queues", root.ignoreQueues,
                             // v0.7: sections the panel isn't showing don't need
                             // their phase-2 metrics request either.
                             "-sections", root.sectionOrder.join(",")]
    updateProcess.running = true
  }

  function refreshNow() { root.lastRunMs = 0; root.runUpdate() }
  // v0.7: also re-stat the dry-run flag file on every open. watchChanges on a
  // FileView tracks *content* changes to a file that already existed when the
  // watch was set up; it does not reliably notice the file appearing or
  // disappearing afterward (confirmed by hand: touching or rm'ing the flag
  // while the shell kept running did not flip dryRunFlagPresent — only a
  // fresh reload() or a shell restart did). Doing it here means the one
  // moment SPEC.md actually cares about — opening the panel to check for
  // "DRY RUN" before pressing Enter/o on a row — is always accurate, with no
  // shell restart required.
  function refreshOnOpen() { root.runUpdate(); dryRunFlagFile.reload() }

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
          // query failed for it. Each entry: hostname, shortName, cpuPct,
          // memPct, memUsedMb, load1, diskPct, diskMount, swapPct, swapUsedMb,
          // warn. The *Pct fields are null on hosts that never publish a memory
          // or swap total (every container host checked), which is why the
          // absolute *UsedMb fields exist — see SPEC.md "v0.5".
          hosts: Array.isArray(a.hosts) ? a.hosts : [],
          // v0.6: one entry per background queue (ActiveJob), from the same
          // metrics phase as health/slowActions/hosts — [] outside that
          // phase or on a failed request. Each entry: name, processed,
          // failed, queueTimeMs (nullable, the floor wait — see SPEC.md
          // "v0.6"), queueTimeHighMs (nullable p95), scheduled, warn. Warning
          // queues first, scheduled ones last; top incidentsPerApp and the
          // `ignoreQueues` filter already applied by the collector.
          queues: Array.isArray(a.queues) ? a.queues : [],
          // v0.6: open (OPEN/WARMUP) anomaly-detection alerts, straight from
          // the GraphQL phase — always populated when ready (not gated by
          // the metrics phase). Each entry: id, state, triggerName, metric,
          // message, lastValue, peakValue, openedAt, url.
          alerts: Array.isArray(a.alerts) ? a.alerts : []
        })
      }
    }
    // v0.7: "pinned" keeps organizations[].apps[] exactly as the API returned
    // them (no sort at all); "name" and "attention" (default) both need a
    // stable sort, which Array.prototype.sort has guaranteed since ES2019.
    if (root.appOrderSetting === "name") {
      out.sort(function(x, y) {
        var xn = x.name.toLowerCase(), yn = y.name.toLowerCase()
        if (xn < yn) return -1
        if (xn > yn) return 1
        return 0
      })
    } else if (root.appOrderSetting === "attention") {
      out.sort(function(x, y) { return root.attention(y) - root.attention(x) })
    }
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
    return Number(t.monitorsDown || 0) * 100 + Number(t.alertsOpen || 0) * 90 +
      Number(t.checkInsFailing || 0) * 50 + Number(t.hostsWarn || 0) * 20 +
      Number(t.queuesWarn || 0) * 10 + Number(t.errors || 0) * 2 + Number(t.perf || 0)
  }

  // Totals over the visible apps only, so a pinned-down view doesn't have the
  // bar dot or tooltip alarm about apps the panel isn't even showing.
  readonly property var visibleTotals: {
    var list = root.apps
    var out = { errors: 0, perf: 0, monitors: 0, monitorsDown: 0, checkIns: 0, checkInsFailing: 0,
                hostsWarn: 0, queuesWarn: 0, alertsOpen: 0 }
    for (var i = 0; i < list.length; i++) {
      var t = list[i].totals || {}
      out.errors += Number(t.errors || 0)
      out.perf += Number(t.perf || 0)
      out.monitors += Number(t.monitors || 0)
      out.monitorsDown += Number(t.monitorsDown || 0)
      out.checkIns += Number(t.checkIns || 0)
      out.checkInsFailing += Number(t.checkInsFailing || 0)
      out.hostsWarn += Number(t.hostsWarn || 0)
      out.queuesWarn += Number(t.queuesWarn || 0)
      out.alertsOpen += Number(t.alertsOpen || 0)
    }
    return out
  }

  readonly property int openErrors: Number(visibleTotals.errors || 0)
  readonly property int openPerf: Number(visibleTotals.perf || 0)
  readonly property int monitorsDown: Number(visibleTotals.monitorsDown || 0)
  readonly property int checkInsFailing: Number(visibleTotals.checkInsFailing || 0)
  readonly property int hostsWarn: Number(visibleTotals.hostsWarn || 0)
  readonly property int queuesWarn: Number(visibleTotals.queuesWarn || 0)
  readonly property int alertsOpen: Number(visibleTotals.alertsOpen || 0)
  readonly property bool urgent: monitorsDown > 0 || checkInsFailing > 0 || alertsOpen > 0
  // v0.6: queuesWarn lights the dot exactly like hostsWarn. It only counts
  // queues with failed jobs or a *real* wait over the threshold — a queue full
  // of deliberately delayed jobs is flagged `scheduled` by the collector and
  // never warns, so this no longer fires permanently on a mailers queue.
  readonly property bool attentionNeeded: urgent || openErrors > 0 || hostsWarn > 0 || queuesWarn > 0

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
