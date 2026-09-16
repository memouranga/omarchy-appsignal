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
  readonly property string collectorPath: {
    var url = String(Qt.resolvedUrl("bin/appsignal-collect"))
    return url.indexOf("file://") === 0 ? decodeURIComponent(url.substring(7)) : url
  }

  property var overview: ({})
  property int dataRevision: 0
  property int refreshIntervalSec: Math.max(30, Number(setting("refreshIntervalSec", 120)) || 120)
  property int incidentsPerApp: Math.max(1, Number(setting("incidentsPerApp", 5)) || 5)
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
                             "-limit", String(root.incidentsPerApp)]
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

  // Flat list of apps, each carrying its org so the panel can label it.
  readonly property var apps: {
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
          totals: a.totals && typeof a.totals === "object" ? a.totals : ({})
        })
      }
    }
    // Apps with something wrong float to the top.
    out.sort(function(x, y) { return root.attention(y) - root.attention(x) })
    return out
  }

  function attention(app) {
    var t = app.totals || {}
    return Number(t.monitorsDown || 0) * 100 + Number(t.checkInsFailing || 0) * 50 + Number(t.errors || 0) * 2 + Number(t.perf || 0)
  }

  readonly property int openErrors: Number(totals.errors || 0)
  readonly property int openPerf: Number(totals.perf || 0)
  readonly property int monitorsDown: Number(totals.monitorsDown || 0)
  readonly property int checkInsFailing: Number(totals.checkInsFailing || 0)
  readonly property bool urgent: monitorsDown > 0 || checkInsFailing > 0
  readonly property bool attentionNeeded: urgent || openErrors > 0
}
