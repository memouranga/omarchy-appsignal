import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// AppSignal dashboard. One bar icon with an alert dot; the panel opens on a
// horizontally-scrolling row of app tabs (apps with something wrong first,
// pinned-only when the user has pinned any) and shows only the selected
// app's open exception incidents and uptime monitors below it. Two focus
// zones, "apps" and "rows", the same up/down-to-switch, left/right-to-move-
// within pattern as dev.git.
Panel {
  id: root
  moduleName: "memong.appsignal"
  ipcTarget: "memong.appsignal"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  // Panel content uses the palette's urgent role; the bar dot uses the bar's
  // own "calling attention" color. Both are theme-supplied — a theme whose
  // colors.toml paints red green (this one does) gets a green alert, and
  // that is the theme's call, not ours.
  readonly property color urgent: Color.urgent
  readonly property color barUrgent: bar ? bar.urgent : Color.urgent
  readonly property color accent: Color.accent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property string glyphHeartbeat: "󰐰"  // mdi-pulse (U+F0430)
  readonly property string glyphBug: "󰃤"        // mdi-bug (U+F00E4)
  readonly property string glyphUptime: "󰖟"     // globe
  readonly property string glyphRefresh: "󰑐"    // refresh
  readonly property string glyphSpeedometer: "󰓅" // mdi-speedometer (U+F04C5)
  readonly property string glyphServer: "󰒋"      // mdi-server (U+F048B)

  // ---------------------------------------------------------------- rows

  readonly property var apps: root.asList(data.apps)

  // Mirrored onto the root: inside a Button delegate `data` resolves to the
  // item's own default property, not this file's Main instance (same reason
  // dev.git mirrors pinnedKind).
  readonly property var selectedApp: data.selectedApp
  readonly property int selectedAppIndex: data.selectedAppIndex
  readonly property bool pinnedFallback: data.pinnedFallback

  // A JS array that crosses a QML `var` property boundary arrives as a
  // QVariantList wrapper: indexable and with a length, but Array.isArray()
  // says false. Everything that walks a list from Main goes through here.
  function asList(v) {
    if (!v || typeof v !== "object") return []
    var n = Number(v.length)
    if (!isFinite(n) || n <= 0) return []
    var out = []
    for (var i = 0; i < n; i++) out.push(v[i])
    return out
  }

  // Only the selected app's rows are ever on screen, so this is the one list
  // j/k walks: every error row followed by every monitor row of that app.
  readonly property var focusRows: {
    var rows = []
    var app = root.selectedApp
    if (!app) return rows
    var errs = root.asList(app.errors)
    for (var j = 0; j < errs.length; j++)
      rows.push({ kind: "error", app: app, item: errs[j], url: errs[j].url })
    // PERFORMANCE: open incidents take priority (rare — AppSignal auto-closes
    // them); with none open, fall back to the two 24h impact-ranked lists the
    // collector's metrics phase computed (web first, then background). Never
    // both perf incidents and slow-action rows at once.
    var perf = root.asList(app.perf)
    if (perf.length > 0) {
      for (var p = 0; p < perf.length; p++)
        rows.push({ kind: "perf", app: app, item: perf[p], url: perf[p].url })
    } else {
      var slowWeb = root.asList(app.slowWeb)
      for (var sw = 0; sw < slowWeb.length; sw++)
        rows.push({ kind: "slow", app: app, item: slowWeb[sw], url: app.perfUrl })
      var slowBg = root.asList(app.slowBackground)
      for (var sb = 0; sb < slowBg.length; sb++)
        rows.push({ kind: "slow", app: app, item: slowBg[sb], url: app.perfUrl })
    }
    // SERVERS (v0.5): sits between PERFORMANCE and UPTIME. Right-click/`o`
    // always opens app.url (the real host-metrics route could not be
    // confirmed without an authenticated browser session; see SPEC.md).
    var hosts = root.asList(app.hosts)
    for (var h = 0; h < hosts.length; h++)
      rows.push({ kind: "host", app: app, item: hosts[h], url: app.url })
    var mons = root.asList(app.monitors)
    for (var k = 0; k < mons.length; k++)
      rows.push({ kind: "monitor", app: app, item: mons[k], url: mons[k].panelUrl })
    return rows
  }

  property bool cursorActive: false
  property int selectedRowIndex: 0

  // ---------------------------------------------------------------- app tabs

  function envAbbrev(env) {
    var e = String(env || "").toLowerCase()
    if (e === "production") return "prod"
    if (e === "development") return "dev"
    if (e === "staging") return "stg"
    return String(env || "")
  }

  function appTabLabel(app) {
    var env = root.envAbbrev(app ? app.environment : "")
    var name = app ? String(app.name || "") : ""
    return env !== "" ? name + " · " + env : name
  }

  function appHasAlert(app) {
    var t = app ? app.totals || {} : {}
    return Number(t.errors || 0) > 0 || Number(t.monitorsDown || 0) > 0 || Number(t.hostsWarn || 0) > 0
  }

  // Delegates inside the Repeater below sit in their own implicit Component,
  // where the bare identifier `data` resolves to the delegate item's own
  // default `data` property (every Item has one), not this file's Main
  // instance — so app-tab delegates call this wrapper instead of `data.
  // selectApp` directly.
  function selectApp(id) { data.selectApp(id) }

  function jumpApp(index) {
    var list = root.apps
    if (index < 0 || index >= list.length) return
    root.selectApp(list[index].id)
  }

  // App button delegates register themselves so the selection can be
  // scrolled into view without guessing at layout geometry.
  property var appButtonItems: ({})
  function registerAppButton(index, item) { root.appButtonItems[index] = item }
  function unregisterAppButton(index, item) { if (root.appButtonItems[index] === item) delete root.appButtonItems[index] }

  function scrollToSelectedApp() {
    if (!appsFlick) return
    var item = root.appButtonItems[root.selectedAppIndex]
    if (!item) return
    var pos = item.mapToItem(appsFlick.contentItem, 0, 0)
    var pad = Style.space(8)
    if (pos.x - pad < appsFlick.contentX)
      appsFlick.contentX = Math.max(0, pos.x - pad)
    else if (pos.x + item.width + pad > appsFlick.contentX + appsFlick.width)
      appsFlick.contentX = pos.x + item.width + pad - appsFlick.width
  }

  // Identity of the currently selected app (not just its index, which can
  // coincidentally stay put across a refresh that reorders the list): the
  // row cursor and scroll position only reset when the app itself changes.
  readonly property string selectedAppKey: root.selectedApp ? String(root.selectedApp.id) : ""
  onSelectedAppKeyChanged: {
    root.selectedRowIndex = 0
    if (panelFlick) panelFlick.contentY = 0
    root.scrollToSelectedApp()
  }

  // ---------------------------------------------------------------- focus zones

  // Vertical focus zones, top to bottom: the app tabs, then the row list.
  // Up/Down (k/j) walks between them and Left/Right (h/l) moves inside
  // whichever zone holds the cursor, same pattern as dev.git.
  property string focusZone: "rows"

  readonly property bool appsZoneAvailable: root.apps.length > 1

  function zoneOrder() {
    var zones = []
    if (root.appsZoneAvailable) zones.push("apps")
    if (root.focusRows.length > 0) zones.push("rows")
    return zones
  }

  function enterZone(zone) {
    root.focusZone = zone
    root.cursorActive = zone === "rows"
    if (zone === "rows") root.scrollToSelected()
    else root.scrollToSelectedApp()
  }

  function moveZone(dy) {
    var zones = root.zoneOrder()
    if (zones.length === 0) return
    var at = zones.indexOf(root.focusZone)
    if (at < 0) at = 0

    if (root.focusZone === "rows" && zones[at] === "rows") {
      // Inside the rows the cursor scrolls first and only leaves the zone
      // when it is already parked on the top row.
      if (dy > 0 || (root.cursorActive && root.selectedRowIndex > 0)) {
        root.moveRows(dy)
        return
      }
    }

    var next = root.clamp(at + dy, 0, zones.length - 1)
    if (zones[next] === root.focusZone) {
      if (root.focusZone === "rows") root.moveRows(dy)
      return
    }
    root.enterZone(zones[next])
  }

  function moveWithinZone(dx) {
    if (root.focusZone === "apps") data.stepApp(dx)
  }

  function activateZone() {
    if (root.focusZone === "rows") root.activateRow()
    else if (root.focusZone === "apps") root.openUrl(root.selectedApp ? root.selectedApp.url : "")
  }

  onFocusZoneChanged: root.cursorActive = root.focusZone === "rows"
  onAppsZoneAvailableChanged: if (!root.appsZoneAvailable && root.focusZone === "apps") root.enterZone("rows")

  // Row delegates register themselves so the cursor can scroll to a row
  // that is currently off-screen without guessing at layout geometry.
  //
  // The registry is keyed by item identity, not by flatIndex: a delegate's
  // flatIndex is a live binding (the PERFORMANCE and UPTIME rows offset
  // themselves by how many rows sit above them), so it routinely changes
  // after Component.onCompleted — a Repeater can finish building the slow-
  // action rows while `errors` is still empty, then shift them from 0-4 to
  // 5-9 once the data lands. An index-keyed map recorded the stale indices
  // and the later rows became unreachable, so the panel never scrolled to
  // them (G, or j/k past the fold, moved the cursor off-screen silently).
  property var rowItems: []
  function registerRow(item) { if (item && root.rowItems.indexOf(item) < 0) root.rowItems.push(item) }
  function unregisterRow(item) {
    var at = root.rowItems.indexOf(item)
    if (at >= 0) root.rowItems.splice(at, 1)
  }
  function rowItemAt(index) {
    for (var i = 0; i < root.rowItems.length; i++)
      if (root.rowItems[i] && root.rowItems[i].flatIndex === index) return root.rowItems[i]
    return null
  }

  function moveRows(dy) {
    var n = root.focusRows.length
    if (n === 0) { root.cursorActive = false; return }
    var next = root.cursorActive ? root.selectedRowIndex + dy : root.selectedRowIndex
    root.cursorActive = true
    root.selectedRowIndex = root.clamp(next, 0, n - 1)
    root.scrollToSelected()
  }

  function jumpRows(index) {
    var n = root.focusRows.length
    if (n === 0) return
    root.focusZone = "rows"
    root.cursorActive = true
    root.selectedRowIndex = root.clamp(index, 0, n - 1)
    root.scrollToSelected()
  }

  function activateRow() { root.activateSelected(false) }

  function activateSelected(viaBrowser) {
    var rows = root.focusRows
    if (rows.length === 0 || !root.cursorActive) return
    var idx = root.clamp(root.selectedRowIndex, 0, rows.length - 1)
    root.activateItem(rows[idx], viaBrowser)
  }

  // incidentAction setting: "agent" (default) sends error rows to the coding
  // agent on Enter/left click; "browser" restores the v0.1 behavior. Monitor
  // rows always open in the browser regardless of this setting.
  readonly property string incidentAction: String(root.setting("incidentAction", "agent") || "agent")

  // v0.5: host warn thresholds, read straight from settings the same way as
  // incidentAction — used only to color individual metrics in a SERVERS row;
  // the collector already decided hosts[].warn (the tab dot / attention
  // aggregate) using these same values passed as -cpu-warn/-mem-warn/-disk-warn.
  function clampWarnPct(v, fallback) {
    var n = Number(v)
    return isFinite(n) && n > 0 ? Math.min(100, Math.max(1, n)) : fallback
  }
  readonly property int cpuWarnPct: root.clampWarnPct(root.setting("cpuWarn", 80), 80)
  readonly property int memWarnPct: root.clampWarnPct(root.setting("memWarn", 85), 85)
  readonly property int diskWarnPct: root.clampWarnPct(root.setting("diskWarn", 85), 85)

  function activateItem(row, viaBrowser) {
    if (!row) return
    if (row.kind === "error" && !viaBrowser && root.incidentAction !== "browser") {
      root.investigate(row)
      return
    }
    if ((row.kind === "perf" || row.kind === "slow") && !viaBrowser && root.incidentAction !== "browser") {
      root.investigatePerf(row)
      return
    }
    if (row.kind === "host" && !viaBrowser && root.incidentAction !== "browser") {
      root.investigateHost(row)
      return
    }
    root.openUrl(row.url)
  }

  // Builds the one-line prompt from SPEC.md and hands it to the user's
  // default coding agent in a new terminal (same as `omarchy agent crash`),
  // then closes the panel. Empty fields (namespace, action, count, message,
  // url, environment) are omitted gracefully.
  function investigate(row) {
    if (!row || !root.bar) return
    var err = row.item || {}
    var app = row.app || {}

    var appPart = String(app.name || "")
    if (app.environment) appPart += " (" + app.environment + ")"

    var head = "Investigate AppSignal incident"
    if (err.number) head += " #" + err.number
    if (err.title) head += " \"" + err.title + "\""
    if (appPart !== "") head += " in app " + appPart

    var detail = []
    if (err.namespace) detail.push("namespace " + err.namespace)
    if (err.action) detail.push("action " + err.action)
    if (Number(err.count || 0) > 0) detail.push(err.count + " occurrences")
    if (err.lastOccurredAt) detail.push("last at " + err.lastOccurredAt)

    var parts = [head + (detail.length > 0 ? ", " + detail.join(", ") : "") + "."]
    if (err.message) parts.push("Message: " + err.message + ".")
    if (err.url) parts.push("URL: " + err.url + ".")
    parts.push("Use the AppSignal MCP to read the incident, its stack trace and recent " +
      "samples; explain the probable root cause and propose a fix. Do not change the " +
      "incident state or severity unless I ask.")

    root.bar.run("omarchy agent prompt " + Util.shellQuote(parts.join(" ")))
    root.close()
  }

  // Same pattern as investigate(), for a PERFORMANCE row: an open performance
  // incident ("perf") or one of the 24h slowest actions ("slow"). The slow-
  // action wording is the one from SPEC.md verbatim; the open-incident one
  // mirrors investigate()'s error wording since AppSignal rarely leaves one
  // open (both apps we develop against have 0).
  function investigatePerf(row) {
    if (!row || !root.bar) return
    var it = row.item || {}
    var app = row.app || {}

    var appPart = String(app.name || "")
    if (app.environment) appPart += " (" + app.environment + ")"

    var action = String(it.action || "")
    var namespace = String(it.namespace || "")
    var count = Number(it.count || 0)
    var url = String(it.url || app.perfUrl || "")

    var parts
    if (row.kind === "slow") {
      var meanMs = Math.round(Number(it.meanMs || 0))
      var totalMs = Number(it.totalMs || (Number(it.meanMs || 0) * count))
      parts = ["Investigate slow action " + action + " (" + namespace + ") in app " + appPart +
        ": mean " + meanMs + " ms over " + root.plural(count, "request", "requests") +
        " in the last 24h, totaling " + root.humanizePerDay(totalMs) + "."]
    } else {
      var head = "Investigate AppSignal performance incident"
      if (it.number) head += " #" + it.number
      if (action !== "") head += " \"" + action + "\""
      if (appPart !== "") head += " in app " + appPart
      var detail = []
      if (namespace !== "") detail.push("namespace " + namespace)
      if (Number(it.mean || 0) > 0) detail.push("mean " + Math.round(Number(it.mean)) + " ms")
      if (count > 0) detail.push(count + " occurrences")
      if (it.lastOccurredAt) detail.push("last at " + it.lastOccurredAt)
      parts = [head + (detail.length > 0 ? ", " + detail.join(", ") : "") + "."]
    }

    if (url !== "") parts.push("URL: " + url + ".")
    parts.push("Use the AppSignal MCP to inspect performance samples and span breakdowns; find the " +
      "bottleneck and propose optimizations. Do not change anything in AppSignal unless I ask.")

    root.bar.run("omarchy agent prompt " + Util.shellQuote(parts.join(" ")))
    root.close()
  }

  // Same pattern for a SERVERS row (v0.5). memPct/swapPct can be null (the
  // collector could not derive a percentage — see SPEC.md "v0.5"): the prompt
  // then carries the absolute megabytes instead, and a clause with neither
  // figure is left out rather than printing "null%".
  function investigateHost(row) {
    if (!row || !root.bar) return
    var h = row.item || {}
    var app = row.app || {}

    var appPart = String(app.name || "")
    if (app.environment) appPart += " (" + app.environment + ")"

    var hostname = String(h.hostname || h.shortName || "")

    var detail = []
    if (h.cpuPct !== null && h.cpuPct !== undefined) detail.push("CPU " + root.formatPercent(Number(h.cpuPct)))
    if (h.memPct !== null && h.memPct !== undefined) detail.push("memory " + root.formatPercent(Number(h.memPct)))
    else if (h.memUsedMb !== null && h.memUsedMb !== undefined) detail.push("memory " + root.formatMb(h.memUsedMb) + " used")
    if (h.load1 !== null && h.load1 !== undefined) detail.push("load " + Number(h.load1).toFixed(2))
    if (h.diskPct !== null && h.diskPct !== undefined) {
      var diskText = "disk " + root.formatPercent(Number(h.diskPct))
      if (h.diskMount) diskText += " on " + h.diskMount
      detail.push(diskText)
    }
    var swapText = root.hostSwapText(h)
    if (swapText !== "") detail.push("swap " + swapText + " in use")

    var head = "Analyze host " + hostname + " of app " + appPart + " in AppSignal"
    var parts = [head + (detail.length > 0 ? ": " + detail.join(", ") : "") + "."]
    parts.push("Use the AppSignal MCP to read host metrics over the last 24h and 7d, correlate with " +
      "throughput, slow actions and background jobs, and propose concrete optimizations (right-sizing, " +
      "memory, swap, disk cleanup, process counts). Do not change anything unless I ask.")

    root.bar.run("omarchy agent prompt " + Util.shellQuote(parts.join(" ")))
    root.close()
  }

  function scrollToSelected() {
    if (!panelFlick || root.focusRows.length === 0) return
    var last = root.focusRows.length - 1
    var row = root.rowItemAt(root.clamp(root.selectedRowIndex, 0, last))
    if (!row) return
    var maxY = Math.max(0, panelFlick.contentHeight - panelFlick.height)
    // The deploy line hangs below the last row and is not focusable, so
    // stopping one padding short of the bottom row would leave it forever
    // off-screen for anyone driving the panel from the keyboard. On the last
    // row, go all the way down instead.
    if (root.selectedRowIndex >= last) { panelFlick.contentY = maxY; return }
    // Same on the way up: the hero and the app tabs sit above the first row,
    // so parking on it means the top of the panel.
    if (root.selectedRowIndex <= 0) { panelFlick.contentY = 0; return }
    var pos = row.mapToItem(panelFlick.contentItem, 0, 0)
    var pad = Style.space(8)
    if (pos.y - pad < panelFlick.contentY)
      panelFlick.contentY = Math.max(0, pos.y - pad)
    else if (pos.y + row.height + pad > panelFlick.contentY + panelFlick.height)
      panelFlick.contentY = Math.min(maxY, pos.y + row.height + pad - panelFlick.height)
  }

  // ---------------------------------------------------------------- helpers

  function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }
  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
  function plural(n, one, many) { return n + " " + (n === 1 ? one : many) }

  // "36 min/day" for a 24h totalMs (the collector's window already is 24h, so
  // totalMs over that window equals the daily total): seconds under a
  // minute, minutes under an hour, hours (one decimal below 10h) above that.
  function humanizePerDay(ms) {
    var totalSeconds = Math.max(0, Number(ms) || 0) / 1000
    if (totalSeconds < 60) return Math.round(totalSeconds) + " s/day"
    var totalMinutes = totalSeconds / 60
    if (totalMinutes < 60) return Math.round(totalMinutes) + " min/day"
    var totalHours = totalMinutes / 60
    var hoursText = totalHours >= 10 ? Math.round(totalHours) : totalHours.toFixed(1).replace(/\.0$/, "")
    return hoursText + " h/day"
  }

  // "updated"/"stale" reads this instead of Date.now() so the panel keeps
  // telling the truth while it sits open.
  property double nowMs: Date.now()

  function timeAgo(iso, now) {
    if (!iso) return ""
    var ms = new Date(iso).getTime()
    if (!isFinite(ms)) return ""
    var seconds = Math.floor(Math.max(0, now - ms) / 1000)
    if (seconds < 60) return "just now"
    var minutes = Math.floor(seconds / 60)
    if (minutes < 60) return minutes + "m"
    var hours = Math.floor(minutes / 60)
    if (hours < 24) return hours + "h"
    var days = Math.floor(hours / 24)
    if (days < 30) return days + "d"
    var months = Math.floor(days / 30)
    if (months < 12) return months + "mo"
    return Math.floor(months / 12) + "y"
  }

  function heroMeta() {
    if (data.loading) return "REFRESHING…"
    var ago = root.timeAgo(data.updatedAt, root.nowMs)
    var when = ago === "" || ago === "just now" ? "JUST NOW" : ago.toUpperCase() + " AGO"
    return (data.stale ? "STALE · FROM " : "UPDATED ") + when
  }

  function heroIdentity() {
    var name = String(data.viewer && data.viewer.name || "")
    var email = String(data.viewer && data.viewer.email || "")
    if (name !== "" && email !== "" && name !== email) return name + " · " + email
    return name !== "" ? name : email
  }

  function alertText() {
    var parts = []
    if (data.collectorError !== "") parts.push(data.collectorError)
    if (data.error !== "") parts.push(data.error)
    if (data.authHelpText !== "") parts.push(data.authHelpText)
    return parts.join("\n\n")
  }

  function appSummary(app) {
    var t = app.totals || {}
    var errs = Number(t.errors || 0)
    var down = Number(t.monitorsDown || 0)
    var parts = []
    if (errs > 0) parts.push(errs + (errs === 1 ? " error" : " errors"))
    if (down > 0) parts.push(down + " down")
    return parts.join(" · ")
  }

  // "1.2k" for 1200, "254" for 254 — one decimal above 1000, trimmed when
  // it would just be ".0".
  function formatCount(n) {
    if (!isFinite(n)) return "0"
    if (n >= 1000) return (n / 1000).toFixed(1).replace(/\.0$/, "") + "k"
    return String(Math.round(n))
  }

  // AppSignal's error_rate gauge is already expressed in percent, not as a
  // 0-1 fraction: namespaces that fail on every transaction ("unhandled",
  // "rake", "runner") report exactly 100.0, and SkillsNT prod's 0.07 over 24h
  // lines up with its 44 HTTP 500s out of ~78k requests (0.06%), not with 7%.
  // So the value is printed as-is, with enough decimals that a real-world
  // rate below 1% does not collapse into "0.0%".
  function formatPercent(n) {
    if (!isFinite(n) || n <= 0) return "0%"
    if (n >= 10) return Math.round(n) + "%"
    if (n >= 1) return n.toFixed(1).replace(/\.0$/, "") + "%"
    return n.toFixed(2).replace(/0$/, "").replace(/\.$/, "") + "%"
  }

  // Absolute memory, in the megabytes AppSignal reports: "512 MB" below a
  // gigabyte, "1.1 GB" above it.
  function formatMb(n) {
    var v = Number(n)
    if (!isFinite(v) || v < 0) return ""
    if (v < 1024) return Math.round(v) + " MB"
    return (v / 1024).toFixed(1) + " GB"
  }

  // Memory for a host row. A real percentage wins when the host publishes a
  // memory total; otherwise the absolute "used" figure is shown, which is all
  // container hosts report (see SPEC.md "v0.5"). "n/a" only when neither exists.
  function hostMemText(h) {
    if (!h) return "n/a"
    if (h.memPct !== null && h.memPct !== undefined) return Math.round(Number(h.memPct)) + "%"
    if (h.memUsedMb !== null && h.memUsedMb !== undefined) {
      var t = root.formatMb(h.memUsedMb)
      if (t !== "") return t
    }
    return "n/a"
  }

  // Swap for a host row, and "" when the host is not swapping (or reports no
  // swap at all) so the caller can drop the metric instead of printing a zero.
  function hostSwapText(h) {
    if (!h) return ""
    if (h.swapPct !== null && h.swapPct !== undefined && Number(h.swapPct) > 0)
      return Math.round(Number(h.swapPct)) + "%"
    if (h.swapUsedMb !== null && h.swapUsedMb !== undefined && Number(h.swapUsedMb) > 0)
      return root.formatMb(h.swapUsedMb)
    return ""
  }

  // The health line under the app header: "1.2k req/h · 0.4% errors · 182 ms
  // mean" (last hour). Any missing field is omitted, not zeroed; with no
  // health at all (app outside the collector's metrics phase, or that phase
  // failed for it) this returns "" and the caller hides the line entirely.
  function healthLine(app) {
    var h = app ? app.health : null
    if (!h || typeof h !== "object") return ""
    var parts = []
    if (h.throughput !== null && h.throughput !== undefined)
      parts.push(root.formatCount(Number(h.throughput)) + " req/h")
    if (h.errorRate !== null && h.errorRate !== undefined)
      parts.push(root.formatPercent(Number(h.errorRate)) + " errors")
    if (h.meanMs !== null && h.meanMs !== undefined)
      parts.push(Math.round(Number(h.meanMs)) + " ms mean")
    return parts.join(" · ")
  }

  // Foot line: "deploy 8a7eda9 · memo · 21d ago · 3 errors since". AppSignal
  // hands back a synthetic marker for apps that never really deployed
  // (shortRevision "No deploy yet"); treat that the same as no deploy at all.
  function deployLine(app) {
    var d = app ? app.lastDeploy : null
    if (!d || typeof d !== "object") return ""
    var rev = String(d.shortRevision || "")
    if (rev === "" || rev === "No deploy yet") return ""
    var parts = ["deploy " + rev]
    if (d.user && d.user !== "N/A") parts.push(String(d.user))
    if (d.liveForInWords) parts.push(String(d.liveForInWords) + " ago")
    var errCount = Number(d.exceptionCount || 0)
    if (errCount > 0) parts.push(errCount + (errCount === 1 ? " error" : " errors") + " since")
    return parts.join(" · ")
  }

  function openUrl(url) {
    if (!url || !root.bar) return
    root.bar.run("omarchy launch browser " + Util.shellQuote(url))
    root.close()
  }

  function refreshNow() { data.refreshNow() }

  // ---------------------------------------------------------------- lifecycle

  onOpenedChanged: if (opened) {
    focusZone = root.appsZoneAvailable ? "apps" : "rows"
    cursorActive = focusZone === "rows"
    selectedRowIndex = 0
    nowMs = Date.now()
    if (panelFlick) panelFlick.contentY = 0
    if (appsFlick) appsFlick.contentX = 0
    data.refreshOnOpen()
    Qt.callLater(function() { keyCatcher.forceActiveFocus(); root.scrollToSelectedApp() })
  }

  Main {
    id: data
    settings: root.settings
  }

  Timer {
    interval: 30000
    running: root.opened
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refreshNow(); return "ok" }
  }

  // Always shown, even with no token configured yet, so there is a way to
  // open the panel and see the setup instructions.
  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.glyphHeartbeat
    tooltipText: {
      if (data.openErrors === 0 && data.monitorsDown === 0) return "AppSignal"
      var parts = []
      if (data.openErrors > 0) parts.push(root.plural(data.openErrors, "error", "errors") + " open")
      if (data.monitorsDown > 0) parts.push(root.plural(data.monitorsDown, "monitor", "monitors") + " down")
      return parts.join(" · ")
    }
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.refreshNow()
      else if (buttonCode === Qt.MiddleButton) data.stepApp(1)
      else root.toggle()
    }
  }

  // Alert dot over the icon: drawn as a sibling above the button so the
  // button's own hover/press chrome never paints over it.
  Rectangle {
    z: button.z + 1
    visible: data.attentionNeeded
    anchors.right: button.right
    anchors.top: button.top
    anchors.rightMargin: Style.space(4)
    anchors.topMargin: Style.space(4)
    width: Style.space(5)
    height: width
    radius: width / 2
    color: root.barUrgent
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(460))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(640))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onMoveRequested: function(dx, dy) {
        if (dx !== 0) root.moveWithinZone(dx)
        if (dy !== 0) root.moveZone(dy)
      }
      onActivateRequested: root.activateZone()
      onCloseRequested: root.close()
      onTextKey: function(t) {
        if (t === "r" || t === "R") root.refreshNow()
        else if (t === "g") root.jumpRows(0)
        else if (t === "G") root.jumpRows(root.focusRows.length - 1)
        else if (t === "o" || t === "O") root.activateSelected(true)
        else if (t >= "1" && t <= "9") root.jumpApp(t.charCodeAt(0) - 49)
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          x: Math.max(1, Style.space(2))
          width: panelFlick.width - x * 2
          bottomPadding: x
          spacing: Style.space(12)

          // ---------- Hero ----------
          Item {
            id: hero
            width: parent.width
            implicitHeight: Math.max(heroMark.height, heroLabels.implicitHeight, refreshButton.height)

            Text {
              id: heroMark
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              width: Style.font.display
              height: Style.font.display
              text: root.glyphHeartbeat
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
              horizontalAlignment: Text.AlignHCenter
              verticalAlignment: Text.AlignVCenter
            }

            Column {
              id: heroLabels
              anchors.left: heroMark.right
              anchors.leftMargin: Style.space(14)
              anchors.right: refreshButton.left
              anchors.rightMargin: Style.space(10)
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(2)

              Text {
                width: parent.width
                text: "AppSignal"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
                elide: Text.ElideRight
              }

              Text {
                width: parent.width
                text: root.heroIdentity()
                visible: text !== ""
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                elide: Text.ElideRight
              }

              Text {
                width: parent.width
                text: root.heroMeta()
                visible: text !== ""
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
                font.letterSpacing: 1.2
                elide: Text.ElideRight
              }
            }

            PanelActionButton {
              id: refreshButton
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              iconText: root.glyphRefresh
              tooltipText: "Refresh now  ·  r"
              foreground: root.foreground
              fontFamily: root.fontFamily
              enabled: !data.loading
              onClicked: root.refreshNow()

              RotationAnimation on rotation {
                from: 0
                to: 360
                duration: 1100
                loops: Animation.Infinite
                running: data.loading
                alwaysRunToEnd: true
              }
            }
          }

          // ---------- Auth / error / collector notice ----------
          BorderSurface {
            visible: root.alertText() !== ""
            width: parent.width
            implicitHeight: alertBoxText.implicitHeight + Style.spacing.xl * 2
            color: root.alpha(root.urgent, 0.10)
            borderSpec: Border.flat(root.alpha(root.urgent, 0.35), 1)
            radius: Style.cornerRadius

            Text {
              id: alertBoxText
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(12)
              anchors.rightMargin: Style.space(12)
              text: root.alertText()
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          // ---------- Pinned-apps fallback notice ----------
          Text {
            visible: data.ready && root.apps.length > 0 && root.pinnedFallback
            width: parent.width
            text: "Pin apps in AppSignal to show only those here"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          // ---------- No apps ----------
          Text {
            visible: data.ready && root.apps.length === 0
            width: parent.width
            topPadding: Style.space(24)
            text: "No apps visible with this token."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
          }

          // ---------- App tabs ----------
          Flickable {
            id: appsFlick
            visible: root.apps.length > 1
            width: parent.width
            height: appsRow.implicitHeight
            contentWidth: appsRow.implicitWidth
            contentHeight: height
            clip: true
            flickableDirection: Flickable.HorizontalFlick
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentWidth > width

            WheelHandler {
              onWheel: function(event) {
                var delta = event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x
                appsFlick.contentX = root.clamp(appsFlick.contentX - delta, 0,
                  Math.max(0, appsFlick.contentWidth - appsFlick.width))
              }
            }

            Row {
              id: appsRow
              spacing: Style.spacing.md

              Repeater {
                model: root.apps

                Button {
                  id: appButton
                  required property var modelData
                  required property int index

                  text: root.appTabLabel(modelData)
                  selected: index === root.selectedAppIndex
                  hasCursor: root.focusZone === "apps" && index === root.selectedAppIndex
                  bordered: true
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                  fontSize: Style.font.bodySmall
                  verticalPadding: Style.spacing.controlPaddingY
                  onClicked: { root.focusZone = "apps"; root.selectApp(modelData.id) }
                  onHovered: function(isHovered) { if (isHovered) root.focusZone = "apps" }

                  Component.onCompleted: root.registerAppButton(appButton.index, appButton)
                  Component.onDestruction: root.unregisterAppButton(appButton.index, appButton)

                  // Alert dot: this app has open errors or a monitor down.
                  Rectangle {
                    visible: root.appHasAlert(appButton.modelData)
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.rightMargin: Style.space(3)
                    anchors.topMargin: Style.space(3)
                    width: Style.space(5)
                    height: width
                    radius: width / 2
                    color: root.urgent
                  }
                }
              }
            }
          }

          // ---------- Selected app ----------
          Column {
            id: appSection
            visible: !!root.selectedApp
            width: column.width
            spacing: Style.space(8)

            readonly property var app: root.selectedApp || ({})
            readonly property var errs: root.asList(appSection.app.errors)
            readonly property var mons: root.asList(appSection.app.monitors)
            readonly property var perfIncidents: root.asList(appSection.app.perf)
            // v0.4.1: two impact-ranked lists (web, background) instead of one
            // mean-ranked list; only used as a fallback when there is no open
            // performance incident.
            readonly property var slowWeb: appSection.perfIncidents.length > 0 ? [] : root.asList(appSection.app.slowWeb)
            readonly property var slowBackground: appSection.perfIncidents.length > 0 ? [] : root.asList(appSection.app.slowBackground)
            // Where the PERFORMANCE rows (perf incidents, or their slow-action
            // fallback: web rows then background rows) sit in focusRows: right
            // after the error rows.
            readonly property int perfRowCount: appSection.perfIncidents.length > 0
              ? appSection.perfIncidents.length
              : (appSection.slowWeb.length + appSection.slowBackground.length)
            // v0.5: SERVERS sits between PERFORMANCE and UPTIME.
            readonly property var hosts: root.asList(appSection.app.hosts)
            readonly property int hostsFlatOffset: appSection.errs.length + appSection.perfRowCount
            readonly property int monitorFlatOffset: appSection.hostsFlatOffset + appSection.hosts.length

            PanelSeparator { foreground: root.foreground }

            // App header: name + environment, click opens the app.
            Item {
              width: parent.width
              implicitHeight: appHeaderRow.implicitHeight

              Row {
                id: appHeaderRow
                anchors.left: parent.left
                anchors.right: appSummaryText.visible ? appSummaryText.left : parent.right
                anchors.rightMargin: appSummaryText.visible ? Style.space(8) : 0
                spacing: Style.space(6)

                Text {
                  text: appSection.app.name || ""
                  color: root.foreground
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.body
                  font.bold: true
                  elide: Text.ElideRight
                }

                Text {
                  visible: (appSection.app.environment || "") !== ""
                  text: appSection.app.environment || ""
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              Text {
                id: appSummaryText
                anchors.right: parent.right
                anchors.verticalCenter: appHeaderRow.verticalCenter
                text: root.appSummary(appSection.app)
                visible: text !== ""
                color: appSection.errs.length > 0 || appSection.mons.length > 0
                  ? root.urgent
                  : root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.openUrl(appSection.app.url)
              }
            }

            // ---- Health (last hour) ----
            Text {
              width: parent.width
              text: root.healthLine(appSection.app)
              visible: text !== ""
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight
            }

            // ---- Open errors ----
            Column {
              width: parent.width
              spacing: Style.space(6)

              PanelSectionHeader {
                width: parent.width
                text: "OPEN ERRORS"
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              Text {
                visible: appSection.errs.length === 0
                width: parent.width
                text: "No open errors"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
              }

              Repeater {
                model: appSection.errs

                ErrorRow {
                  required property var modelData
                  required property int index

                  width: appSection.width
                  err: modelData
                  flatIndex: index
                }
              }
            }

            // ---- Performance ----
            // Open performance incidents when there are any (AppSignal auto-
            // closes these, so it is rare); otherwise two 24h impact-ranked
            // lists (WEB, BACKGROUND) the collector's metrics phase computed.
            // Hidden entirely when none of the three exists.
            Column {
              width: parent.width
              visible: appSection.perfIncidents.length > 0 || appSection.slowWeb.length > 0 || appSection.slowBackground.length > 0
              spacing: Style.space(6)

              PanelSectionHeader {
                width: parent.width
                text: "PERFORMANCE"
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              Repeater {
                model: appSection.perfIncidents

                PerfRow {
                  required property var modelData
                  required property int index

                  width: appSection.width
                  perf: modelData
                  flatIndex: appSection.errs.length + index
                }
              }

              // WEB · 24H
              Column {
                width: parent.width
                visible: appSection.perfIncidents.length === 0 && appSection.slowWeb.length > 0
                spacing: Style.space(6)

                Text {
                  width: parent.width
                  text: "WEB · 24H"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  font.letterSpacing: 1.2
                }

                Repeater {
                  model: appSection.slowWeb

                  SlowActionRow {
                    required property var modelData
                    required property int index

                    width: appSection.width
                    action: modelData
                    flatIndex: appSection.errs.length + index
                  }
                }
              }

              // BACKGROUND · 24H
              Column {
                width: parent.width
                visible: appSection.perfIncidents.length === 0 && appSection.slowBackground.length > 0
                spacing: Style.space(6)

                Text {
                  width: parent.width
                  text: "BACKGROUND · 24H"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                  font.letterSpacing: 1.2
                }

                Repeater {
                  model: appSection.slowBackground

                  SlowActionRow {
                    required property var modelData
                    required property int index

                    width: appSection.width
                    action: modelData
                    flatIndex: appSection.errs.length + appSection.slowWeb.length + index
                  }
                }
              }
            }

            // ---- Servers ----
            Column {
              width: parent.width
              visible: appSection.hosts.length > 0
              spacing: Style.space(6)

              PanelSectionHeader {
                width: parent.width
                text: "SERVERS"
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              Repeater {
                model: appSection.hosts

                HostRow {
                  required property var modelData
                  required property int index

                  width: appSection.width
                  host: modelData
                  flatIndex: appSection.hostsFlatOffset + index
                }
              }
            }

            // ---- Uptime ----
            Column {
              width: parent.width
              visible: appSection.mons.length > 0
              spacing: Style.space(6)

              PanelSectionHeader {
                width: parent.width
                text: "UPTIME"
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              Repeater {
                model: appSection.mons

                MonitorRow {
                  required property var modelData
                  required property int index

                  width: appSection.width
                  mon: modelData
                  flatIndex: appSection.monitorFlatOffset + index
                }
              }
            }

            // ---- Deploy ----
            Text {
              width: parent.width
              text: root.deployLine(appSection.app)
              visible: text !== ""
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              elide: Text.ElideRight

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.openUrl(appSection.app.deploysUrl)
              }
            }
          }
        }
      }
    }
  }

  // ---------------------------------------------------------------- components

  // One open exception incident: bug glyph, exception name, action + count,
  // and how long ago it last occurred. Clicking opens the incident.
  component ErrorRow: CursorSurface {
    id: errorRow

    property var err: null
    property int flatIndex: -1

    readonly property string title: err ? String(err.title || "") : ""
    readonly property string action: err ? String(err.action || "") : ""
    readonly property int count: err ? Number(err.count || 0) : 0
    // Some incidents carry no action name; don't leave a dangling separator.
    readonly property string meta: {
      var parts = []
      if (errorRow.action !== "") parts.push(errorRow.action)
      if (errorRow.count > 0) parts.push(errorRow.count + "×")
      return parts.join("  ·  ")
    }
    readonly property string url: err ? String(err.url || "") : ""
    readonly property string lastOccurredAt: err ? String(err.lastOccurredAt || "") : ""

    foreground: root.foreground
    hasCursor: root.cursorActive && root.selectedRowIndex === errorRow.flatIndex
    implicitHeight: Math.max(Style.space(40),
      rowTitle.implicitHeight + rowMeta.implicitHeight + Style.spacing.md * 2)

    Component.onCompleted: root.registerRow(errorRow)
    Component.onDestruction: root.unregisterRow(errorRow)

    Column {
      id: rowBody
      anchors.left: parent.left
      anchors.leftMargin: Style.space(10)
      anchors.right: rowAge.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)

      Row {
        width: parent.width
        spacing: Style.space(8)

        Text {
          id: rowGlyph
          anchors.verticalCenter: parent.verticalCenter
          text: root.glyphBug
          color: root.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        Text {
          id: rowTitle
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - rowGlyph.width - parent.spacing
          text: errorRow.title
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideRight
        }
      }

      Row {
        width: parent.width
        spacing: Style.space(8)

        Item { width: rowGlyph.width; height: 1 }

        Text {
          id: rowMeta
          width: parent.width - rowGlyph.width - parent.spacing
          text: errorRow.meta
          visible: text !== ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }

    Text {
      id: rowAge
      anchors.right: parent.right
      anchors.rightMargin: Style.space(10)
      anchors.top: rowBody.top
      text: root.timeAgo(errorRow.lastOccurredAt, root.nowMs)
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    MouseArea {
      id: errorMouse
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      cursorShape: Qt.PointingHandCursor
      onClicked: function(mouse) {
        root.activateItem(root.focusRows[errorRow.flatIndex], mouse.button === Qt.RightButton)
      }
      onEntered: {
        root.focusZone = "rows"
        root.cursorActive = true
        root.selectedRowIndex = errorRow.flatIndex
      }
    }

    PanelToolTip {
      visible: errorMouse.containsMouse
      text: root.incidentAction === "browser"
        ? "Click / Enter opens the browser"
        : "Click / Enter: agent  ·  right-click / o: browser"
    }
  }

  // One uptime monitor: globe glyph, name, its URL, and up/down status.
  // Clicking opens the monitor's page in AppSignal.
  component MonitorRow: CursorSurface {
    id: monitorRow

    property var mon: null
    property int flatIndex: -1

    readonly property string name: mon ? String(mon.name || "") : ""
    readonly property string monitorUrl: mon ? String(mon.url || "") : ""
    readonly property string panelUrl: mon ? String(mon.panelUrl || "") : ""
    readonly property bool down: mon ? mon.down === true : false
    readonly property string openedAt: mon ? String(mon.openedAt || "") : ""

    foreground: root.foreground
    hasCursor: root.cursorActive && root.selectedRowIndex === monitorRow.flatIndex
    implicitHeight: Math.max(Style.space(40),
      rowTitle.implicitHeight + rowMeta.implicitHeight + Style.spacing.md * 2)

    Component.onCompleted: root.registerRow(monitorRow)
    Component.onDestruction: root.unregisterRow(monitorRow)

    Column {
      id: rowBody
      anchors.left: parent.left
      anchors.leftMargin: Style.space(10)
      anchors.right: rowStatus.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)

      Row {
        width: parent.width
        spacing: Style.space(8)

        Text {
          id: rowGlyph
          anchors.verticalCenter: parent.verticalCenter
          text: root.glyphUptime
          color: monitorRow.down ? root.urgent : root.alpha(root.foreground, 0.60)
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        Text {
          id: rowTitle
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - rowGlyph.width - parent.spacing
          text: monitorRow.name
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideRight
        }
      }

      Row {
        width: parent.width
        spacing: Style.space(8)

        Item { width: rowGlyph.width; height: 1 }

        Text {
          id: rowMeta
          width: parent.width - rowGlyph.width - parent.spacing
          text: monitorRow.monitorUrl
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideLeft
        }
      }
    }

    Text {
      id: rowStatus
      anchors.right: parent.right
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      text: monitorRow.down
        ? "DOWN · since " + root.timeAgo(monitorRow.openedAt, root.nowMs)
        : "UP"
      color: monitorRow.down ? root.urgent : root.accent
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.openUrl(monitorRow.panelUrl)
      onEntered: {
        root.focusZone = "rows"
        root.cursorActive = true
        root.selectedRowIndex = monitorRow.flatIndex
      }
    }
  }

  // One open performance incident: speedometer glyph, action name, namespace
  // + mean + count, and how long ago it last occurred. Same click pattern as
  // ErrorRow, routed through investigatePerf() instead of investigate().
  component PerfRow: CursorSurface {
    id: perfRow

    property var perf: null
    property int flatIndex: -1

    readonly property string title: perfRow.perf ? String(perfRow.perf.action || perfRow.perf.title || "") : ""
    readonly property string namespace: perfRow.perf ? String(perfRow.perf.namespace || "") : ""
    readonly property real meanMs: perfRow.perf ? Number(perfRow.perf.mean || 0) : 0
    readonly property int count: perfRow.perf ? Number(perfRow.perf.count || 0) : 0
    readonly property string meta: {
      var parts = []
      if (perfRow.namespace !== "") parts.push(perfRow.namespace)
      if (perfRow.meanMs > 0) parts.push(Math.round(perfRow.meanMs) + " ms")
      if (perfRow.count > 0) parts.push(perfRow.count + "×")
      return parts.join("  ·  ")
    }
    readonly property string url: perfRow.perf ? String(perfRow.perf.url || "") : ""
    readonly property string lastOccurredAt: perfRow.perf ? String(perfRow.perf.lastOccurredAt || "") : ""

    foreground: root.foreground
    hasCursor: root.cursorActive && root.selectedRowIndex === perfRow.flatIndex
    implicitHeight: Math.max(Style.space(40),
      rowTitle.implicitHeight + rowMeta.implicitHeight + Style.spacing.md * 2)

    Component.onCompleted: root.registerRow(perfRow)
    Component.onDestruction: root.unregisterRow(perfRow)

    Column {
      id: rowBody
      anchors.left: parent.left
      anchors.leftMargin: Style.space(10)
      anchors.right: rowAge.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)

      Row {
        width: parent.width
        spacing: Style.space(8)

        Text {
          id: rowGlyph
          anchors.verticalCenter: parent.verticalCenter
          text: root.glyphSpeedometer
          color: root.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        Text {
          id: rowTitle
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - rowGlyph.width - parent.spacing
          text: perfRow.title
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideRight
        }
      }

      Row {
        width: parent.width
        spacing: Style.space(8)

        Item { width: rowGlyph.width; height: 1 }

        Text {
          id: rowMeta
          width: parent.width - rowGlyph.width - parent.spacing
          text: perfRow.meta
          visible: text !== ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }

    Text {
      id: rowAge
      anchors.right: parent.right
      anchors.rightMargin: Style.space(10)
      anchors.top: rowBody.top
      text: root.timeAgo(perfRow.lastOccurredAt, root.nowMs)
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
    }

    MouseArea {
      id: perfMouse
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      cursorShape: Qt.PointingHandCursor
      onClicked: function(mouse) {
        root.activateItem(root.focusRows[perfRow.flatIndex], mouse.button === Qt.RightButton)
      }
      onEntered: {
        root.focusZone = "rows"
        root.cursorActive = true
        root.selectedRowIndex = perfRow.flatIndex
      }
    }

    PanelToolTip {
      visible: perfMouse.containsMouse
      text: root.incidentAction === "browser"
        ? "Click / Enter opens the browser"
        : "Click / Enter: agent  ·  right-click / o: browser"
    }
  }

  // One of the 24h slowest actions (shown only when the app has no open
  // performance incident): speedometer glyph, action name, namespace, and
  // "182 ms · 340×" on the right. Same click pattern as PerfRow.
  component SlowActionRow: CursorSurface {
    id: slowRow

    property var action: null
    property int flatIndex: -1

    readonly property string title: slowRow.action ? String(slowRow.action.action || "") : ""
    readonly property string namespace: slowRow.action ? String(slowRow.action.namespace || "") : ""
    readonly property real meanMs: slowRow.action ? Number(slowRow.action.meanMs || 0) : 0
    readonly property int count: slowRow.action ? Number(slowRow.action.count || 0) : 0
    readonly property real totalMs: slowRow.action
      ? Number(slowRow.action.totalMs !== undefined ? slowRow.action.totalMs : slowRow.meanMs * slowRow.count) : 0
    readonly property string stat: Math.round(slowRow.meanMs) + " ms  ·  " + slowRow.count + "×  ·  " + root.humanizePerDay(slowRow.totalMs)
    readonly property string url: slowRow.action ? String(slowRow.action.url || "") : ""

    foreground: root.foreground
    hasCursor: root.cursorActive && root.selectedRowIndex === slowRow.flatIndex
    implicitHeight: Math.max(Style.space(40),
      rowTitle.implicitHeight + rowMeta.implicitHeight + Style.spacing.md * 2)

    Component.onCompleted: root.registerRow(slowRow)
    Component.onDestruction: root.unregisterRow(slowRow)

    Column {
      id: rowBody
      anchors.left: parent.left
      anchors.leftMargin: Style.space(10)
      anchors.right: rowStat.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)

      Row {
        width: parent.width
        spacing: Style.space(8)

        Text {
          id: rowGlyph
          anchors.verticalCenter: parent.verticalCenter
          text: root.glyphSpeedometer
          color: root.alpha(root.foreground, 0.60)
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        Text {
          id: rowTitle
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - rowGlyph.width - parent.spacing
          text: slowRow.title
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideRight
        }
      }

      Row {
        width: parent.width
        spacing: Style.space(8)

        Item { width: rowGlyph.width; height: 1 }

        Text {
          id: rowMeta
          width: parent.width - rowGlyph.width - parent.spacing
          text: slowRow.namespace
          visible: text !== "" && text !== "web"
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
    }

    Text {
      id: rowStat
      anchors.right: parent.right
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: rowBody.verticalCenter
      text: slowRow.stat
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
    }

    MouseArea {
      id: slowMouse
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      cursorShape: Qt.PointingHandCursor
      onClicked: function(mouse) {
        root.activateItem(root.focusRows[slowRow.flatIndex], mouse.button === Qt.RightButton)
      }
      onEntered: {
        root.focusZone = "rows"
        root.cursorActive = true
        root.selectedRowIndex = slowRow.flatIndex
      }
    }

    PanelToolTip {
      visible: slowMouse.containsMouse
      text: root.incidentAction === "browser"
        ? "Click / Enter opens the browser"
        : "Click / Enter: agent  ·  right-click / o: browser"
    }
  }

  // One host reporting server metrics for the app (v0.5). Two lines, because
  // the metric line ("CPU 4% · MEM 1.1 GB · LOAD 0.02 · DISK 37% · SWAP
  // 512 MB") is far too long to share a line with the hostname at panel width:
  // first the server glyph and the hostname (shortName in full color, the
  // "-<container id>" tail dim), then the metrics underneath, each one colored
  // urgent at or above its warn threshold. MEM falls back to absolute
  // megabytes when the host publishes no memory total (every container host
  // checked — see SPEC.md "v0.5"), and only shows "n/a" with neither figure.
  component HostRow: CursorSurface {
    id: hostRow

    property var host: null
    property int flatIndex: -1

    readonly property string hostname: hostRow.host ? String(hostRow.host.hostname || "") : ""
    readonly property string shortName: hostRow.host ? String(hostRow.host.shortName || hostRow.hostname) : ""
    readonly property bool warn: hostRow.host ? hostRow.host.warn === true : false

    function metricColor(overWarn) { return overWarn ? String(root.urgent) : String(root.dim) }
    function pctText(value) { return (value === null || value === undefined) ? "n/a" : Math.round(Number(value)) + "%" }

    readonly property string statText: {
      if (!hostRow.host) return ""
      var h = hostRow.host
      var cpuOver = h.cpuPct !== null && h.cpuPct !== undefined && Number(h.cpuPct) >= root.cpuWarnPct
      var memOver = h.memPct !== null && h.memPct !== undefined && Number(h.memPct) >= root.memWarnPct
      var diskOver = h.diskPct !== null && h.diskPct !== undefined && Number(h.diskPct) >= root.diskWarnPct
      var load1Text = (h.load1 === null || h.load1 === undefined) ? "n/a" : Number(h.load1).toFixed(2)
      var parts = [
        "<font color=\"" + hostRow.metricColor(cpuOver) + "\">CPU " + hostRow.pctText(h.cpuPct) + "</font>",
        "<font color=\"" + hostRow.metricColor(memOver) + "\">MEM " + root.hostMemText(h) + "</font>",
        "<font color=\"" + String(root.dim) + "\">LOAD " + load1Text + "</font>",
        "<font color=\"" + hostRow.metricColor(diskOver) + "\">DISK " + hostRow.pctText(h.diskPct) + "</font>"
      ]
      // Swap only shows up when the host is actually swapping: a host with no
      // swap in use (CloudHealth) would only add noise. Swapping never raises
      // `warn` on its own, so this stays dim.
      var swapText = root.hostSwapText(h)
      if (swapText !== "")
        parts.push("<font color=\"" + String(root.dim) + "\">SWAP " + swapText + "</font>")
      return parts.join("  ·  ")
    }

    // The full hostname, with everything shortName dropped (the container id)
    // in the dim color: the whole name stays on screen without the noisy tail
    // competing with the readable part.
    readonly property string titleText: {
      var full = hostRow.hostname !== "" ? hostRow.hostname : hostRow.shortName
      if (full === "") return ""
      // StyledText: a hostname is plain enough in practice, but it comes from
      // an AppSignal tag, so it is escaped before being framed in markup.
      function esc(s) { return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;") }
      if (hostRow.shortName === "" || full.indexOf(hostRow.shortName) !== 0 || full === hostRow.shortName)
        return esc(full)
      return esc(hostRow.shortName) + "<font color=\"" + String(root.dim) + "\">" +
        esc(full.substring(hostRow.shortName.length)) + "</font>"
    }

    foreground: root.foreground
    hasCursor: root.cursorActive && root.selectedRowIndex === hostRow.flatIndex
    implicitHeight: Math.max(Style.space(40),
      rowTitle.implicitHeight + rowStat.implicitHeight + Style.spacing.md * 2)

    Component.onCompleted: root.registerRow(hostRow)
    Component.onDestruction: root.unregisterRow(hostRow)

    Column {
      id: rowBody
      anchors.left: parent.left
      anchors.leftMargin: Style.space(10)
      anchors.right: parent.right
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(2)

      Row {
        width: parent.width
        spacing: Style.space(8)

        Text {
          id: rowGlyph
          anchors.verticalCenter: parent.verticalCenter
          text: root.glyphServer
          color: hostRow.warn ? root.urgent : root.alpha(root.foreground, 0.60)
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        Text {
          id: rowTitle
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - rowGlyph.width - parent.spacing
          textFormat: Text.StyledText
          text: hostRow.titleText
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          elide: Text.ElideRight
        }
      }

      Row {
        width: parent.width
        spacing: Style.space(8)

        Item { width: rowGlyph.width; height: 1 }

        Text {
          id: rowStat
          width: parent.width - rowGlyph.width - parent.spacing
          textFormat: Text.StyledText
          text: hostRow.statText
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          elide: Text.ElideRight
        }
      }
    }

    MouseArea {
      id: hostMouse
      anchors.fill: parent
      hoverEnabled: true
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      cursorShape: Qt.PointingHandCursor
      onClicked: function(mouse) {
        root.activateItem(root.focusRows[hostRow.flatIndex], mouse.button === Qt.RightButton)
      }
      onEntered: {
        root.focusZone = "rows"
        root.cursorActive = true
        root.selectedRowIndex = hostRow.flatIndex
      }
    }

    PanelToolTip {
      visible: hostMouse.containsMouse
      text: root.incidentAction === "browser"
        ? "Click / Enter opens the browser"
        : "Click / Enter: agent  ·  right-click / o: browser"
    }
  }
}
