import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// AppSignal dashboard. One bar icon with an alert dot; the panel lists every
// app the token can see (apps with something wrong first), each with its
// open exception incidents and uptime monitors. All rows across all apps
// flatten into a single j/k cursor — there are no tabs or host zones to
// juggle like dev.git has.
Panel {
  id: root
  moduleName: "memong.appsignal"
  ipcTarget: "memong.appsignal"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color accent: Color.accent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property string glyphHeartbeat: ""  // fa-heartbeat
  readonly property string glyphBug: ""        // fa-bug
  readonly property string glyphUptime: "󰖟"     // globe
  readonly property string glyphRefresh: "󰑐"    // refresh

  // ---------------------------------------------------------------- rows

  readonly property var apps: data.apps

  function appRowCount(app) {
    var errs = app && Array.isArray(app.errors) ? app.errors.length : 0
    var mons = app && Array.isArray(app.monitors) ? app.monitors.length : 0
    return errs + mons
  }

  function appOffset(appIndex) {
    var offset = 0
    for (var i = 0; i < appIndex && i < root.apps.length; i++) offset += root.appRowCount(root.apps[i])
    return offset
  }

  // Every error row followed by every monitor row, app by app, in the same
  // order the apps render in. This is the one list j/k walks.
  readonly property var focusRows: {
    var rows = []
    for (var i = 0; i < root.apps.length; i++) {
      var app = root.apps[i]
      var errs = Array.isArray(app.errors) ? app.errors : []
      for (var j = 0; j < errs.length; j++)
        rows.push({ kind: "error", app: app, item: errs[j], url: errs[j].url })
      var mons = Array.isArray(app.monitors) ? app.monitors : []
      for (var k = 0; k < mons.length; k++)
        rows.push({ kind: "monitor", app: app, item: mons[k], url: mons[k].panelUrl })
    }
    return rows
  }

  property bool cursorActive: false
  property int selectedRowIndex: 0

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
    root.cursorActive = true
    root.selectedRowIndex = root.clamp(index, 0, n - 1)
    root.scrollToSelected()
  }

  function activateRow() {
    var rows = root.focusRows
    if (rows.length === 0 || !root.cursorActive) return
    var idx = root.clamp(root.selectedRowIndex, 0, rows.length - 1)
    root.openUrl(rows[idx].url)
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
    cursorActive = false
    selectedRowIndex = 0
    nowMs = Date.now()
    if (panelFlick) panelFlick.contentY = 0
    data.refreshOnOpen()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
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
      else root.toggle()
    }
  }

  Rectangle {
    visible: data.attentionNeeded
    anchors.right: button.right
    anchors.top: button.top
    anchors.rightMargin: Style.space(4)
    anchors.topMargin: Style.space(4)
    width: Style.space(5)
    height: width
    radius: width / 2
    color: root.urgent
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

      onMoveRequested: function(dx, dy) { if (dy !== 0) root.moveRows(dy) }
      onActivateRequested: root.activateRow()
      onCloseRequested: root.close()
      onTextKey: function(t) {
        if (t === "r" || t === "R") root.refreshNow()
        else if (t === "g") root.jumpRows(0)
        else if (t === "G") root.jumpRows(root.focusRows.length - 1)
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

          // ---------- Apps ----------
          Repeater {
            model: root.apps

            Column {
              id: appSection
              required property var modelData
              required property int index

              readonly property var app: modelData
              readonly property int offset: root.appOffset(index)
              readonly property var errs: Array.isArray(app.errors) ? app.errors : []
              readonly property var mons: Array.isArray(app.monitors) ? app.monitors : []

              width: column.width
              spacing: Style.space(8)

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
                    text: appSection.app.name
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    font.bold: true
                    elide: Text.ElideRight
                  }

                  Text {
                    visible: appSection.app.environment !== ""
                    text: appSection.app.environment
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
                  color: root.urgent
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
                    flatIndex: appSection.offset + index
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
                    flatIndex: appSection.offset + appSection.errs.length + index
                  }
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
          text: errorRow.action + "  ·  " + errorRow.count + "×"
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
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.openUrl(errorRow.url)
      onEntered: {
        root.cursorActive = true
        root.selectedRowIndex = errorRow.flatIndex
      }
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
        root.cursorActive = true
        root.selectedRowIndex = monitorRow.flatIndex
      }
    }
  }
}
