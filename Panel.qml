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
    return Number(t.errors || 0) > 0 || Number(t.monitorsDown || 0) > 0
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
  property var rowItems: ({})
  function registerRow(index, item) { root.rowItems[index] = item }
  function unregisterRow(index, item) { if (root.rowItems[index] === item) delete root.rowItems[index] }

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

  function activateItem(row, viaBrowser) {
    if (!row) return
    if (row.kind === "error" && !viaBrowser && root.incidentAction !== "browser") {
      root.investigate(row)
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

  function scrollToSelected() {
    if (!panelFlick || root.focusRows.length === 0) return
    var row = root.rowItems[root.clamp(root.selectedRowIndex, 0, root.focusRows.length - 1)]
    if (!row) return
    var pos = row.mapToItem(panelFlick.contentItem, 0, 0)
    var pad = Style.space(8)
    if (pos.y - pad < panelFlick.contentY)
      panelFlick.contentY = Math.max(0, pos.y - pad)
    else if (pos.y + row.height + pad > panelFlick.contentY + panelFlick.height)
      panelFlick.contentY = pos.y + row.height + pad - panelFlick.height
  }

  // ---------------------------------------------------------------- helpers

  function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }
  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }
  function plural(n, one, many) { return n + " " + (n === 1 ? one : many) }

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
                  flatIndex: appSection.errs.length + index
                }
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

    Component.onCompleted: root.registerRow(errorRow.flatIndex, errorRow)
    Component.onDestruction: root.unregisterRow(errorRow.flatIndex, errorRow)

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

    Component.onCompleted: root.registerRow(monitorRow.flatIndex, monitorRow)
    Component.onDestruction: root.unregisterRow(monitorRow.flatIndex, monitorRow)

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
}
