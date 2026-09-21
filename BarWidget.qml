import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Pi Usage: what pi has actually burned and spent, read from pi's own session
// transcripts (~/.pi/agent/sessions). The bar shows a heat strip of the recent
// window plus one period's tokens and dollars; left click opens the full
// report, right click walks the period, middle click forces a fresh collect.
//
// All extraction lives in bin/pi-usage-collect; this file never parses a
// transcript and never guesses a number. The collector writes one JSON the
// FileView below watches, so a collect that finishes after the bar drew
// itself still lands on screen within a frame.
BarWidget {
  id: root
  moduleName: "zjm.pi-usage"

  // ── settings (from this widget's inline shell.json entry) ─────────────────
  readonly property int windowMinutes: clamp(Number(setting("windowMinutes", 360)) || 360, 30, 1440)
  readonly property int cells: clamp(Number(setting("cells", 12)) || 12, 4, 48)
  readonly property int refreshSec: clamp(Number(setting("refreshIntervalSec", 10)) || 10, 5, 600)
  readonly property bool showCells: setting("showCells", true) !== false
  readonly property bool showCost: setting("showCost", true) !== false
  readonly property bool followTheme: setting("followTheme", true) !== false
  readonly property string labelPeriod: String(setting("labelPeriod", "today"))

  // DeepSeek blue, for anyone who wants the strip to say what it is reading
  // rather than to match the wallpaper.
  readonly property color accentColor: followTheme ? Color.accent : "#4d6bfe"

  function clamp(value, low, high) {
    return Math.max(low, Math.min(high, value))
  }

  // ── state ────────────────────────────────────────────────────────────────
  property var report: ({})
  property bool ready: false
  property string lastError: ""

  readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME")
    || Quickshell.env("HOME") + "/.local/state") + "/omarchy/pi-usage"
  readonly property string reportPath: stateDir + "/report.json"
  // Resolved from this component's own location, not a hardcoded plugin id, so
  // a renamed or cloned copy still finds its own collector.
  readonly property string collectorPath: decodeURIComponent(String(Qt.resolvedUrl("bin/pi-usage-collect")).replace(/^file:\/\//, ""))

  readonly property var buckets: report.buckets || []
  readonly property var totals: report.totals || ({})
  readonly property var periodTotals: totals[labelPeriod] || ({ tokens: 0, cost: 0, cacheRead: 0, turns: 0, sessions: 0 })
  readonly property bool hasData: ready && report.sessionsFound > 0

  readonly property real windowTokens: sumOf(buckets, "tokens")
  readonly property real windowCost: sumOf(buckets, "cost")

  function sumOf(rows, key) {
    var total = 0
    if (!rows) return 0
    for (var i = 0; i < rows.length; i++) total += Number(rows[i] ? rows[i][key] : 0) || 0
    return total
  }

  readonly property var bucketTokens: {
    var out = []
    for (var i = 0; i < buckets.length; i++) out.push(Number(buckets[i].tokens) || 0)
    return out
  }

  // ── collect ──────────────────────────────────────────────────────────────
  function collect(force) {
    if (collector.running) return
    collector.running = true
  }

  function refresh() {
    collect(true)
  }

  function toggleCockpit() {
    if (panel.opened) close()
    else open()
  }

  function open() {
    panel.controller.show()
    collect(true)
  }

  function close() {
    panel.controller.hide()
  }

  function toggle() {
    toggleCockpit()
  }

  function closeForPopoutSwitch() {
    close()
  }

  readonly property bool opened: panel.opened
  readonly property bool popoutSwitchClosing: false

  // ── period ───────────────────────────────────────────────────────────────
  readonly property var periodRing: ["today", "d7", "d30", "all"]

  function periodName(id) {
    return id === "d7" ? "7 days" : id === "d30" ? "30 days" : id === "all" ? "all time" : "today"
  }

  function periodShort(id) {
    return id === "d7" ? "7D" : id === "d30" ? "30D" : id === "all" ? "ALL" : "TODAY"
  }

  // The period is a bar setting, not a panel state: cycling it has to survive
  // a restart, so it is written back through the shell the same way the clock
  // writes a cycled label format.
  function setPeriod(id) {
    var entry = { id: root.moduleName }
    for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
    entry.labelPeriod = id
    root.settings = entry
    if (bar && bar.shell && typeof bar.shell.updateEntryInline === "function")
      bar.shell.updateEntryInline(root.moduleName, entry)
  }

  function cyclePeriod() {
    var at = periodRing.indexOf(labelPeriod)
    setPeriod(periodRing[(at + 1) % periodRing.length])
  }

  // ── formatting ───────────────────────────────────────────────────────────
  function compactTokens(value) {
    var n = Number(value) || 0
    if (n < 1000) return String(Math.round(n))
    if (n < 1e6) return (n / 1e3).toFixed(n < 1e4 ? 1 : 0) + "K"
    if (n < 1e9) return (n / 1e6).toFixed(n < 1e7 ? 1 : 0) + "M"
    return (n / 1e9).toFixed(1) + "B"
  }

  function money(value) {
    var c = Number(value) || 0
    if (c > 0 && c < 0.005) return "<$0.01"
    if (c < 1000) return "$" + c.toFixed(2)
    return "$" + (c / 1000).toFixed(1) + "K"
  }

  function moneyExact(value) {
    var c = Number(value) || 0
    if (c > 0 && c < 0.0005) return "<$0.001"
    return "$" + c.toFixed(c < 10 ? 4 : 2)
  }

  function ago(ms) {
    var then = Number(ms) || 0
    if (then <= 0) return "never"
    var delta = Math.max(0, Date.now() - then)
    if (delta < 45000) return "just now"
    if (delta < 3600000) return Math.round(delta / 60000) + "m ago"
    if (delta < 86400000) return Math.round(delta / 3600000) + "h ago"
    return Math.round(delta / 86400000) + "d ago"
  }

  function plural(count, singular, many) {
    var n = Number(count) || 0
    return n + " " + (n === 1 ? singular : many)
  }

  function turnsText(row) {
    return Number(row && row.turns) > 0 ? plural(row.turns, "turn", "turns") : "no burn"
  }

  function sessionsText(row) {
    return plural(row ? row.sessions : 0, "session", "sessions")
  }

  function spanLabel(minutes) {
    var value = Number(minutes) || 0
    if (value < 60) return Math.round(value) + "m"
    var hours = value / 60
    return (hours % 1 === 0 ? hours.toFixed(0) : hours.toFixed(1)) + "h"
  }

  // ── heat ramp: dim accent -> accent -> foreground ─────────────────────────
  function mix(a, b, t) {
    return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1)
  }

  function heat(level) {
    var l = Math.max(0, Math.min(1, Number(level) || 0))
    if (l < 0.7) return mix(Qt.darker(accentColor, 2.1), accentColor, l / 0.7)
    return mix(accentColor, Color.foreground, (l - 0.7) / 0.3 * 0.85)
  }

  // ── what the bar says ────────────────────────────────────────────────────
  readonly property string labelText: {
    if (vertical) return hasData ? compactTokens(periodTotals.tokens) : "—"
    if (!ready) return "PI …"
    if (!hasData) return "PI —"
    var text = "PI " + compactTokens(periodTotals.tokens)
    if (showCost) text += " · " + money(periodTotals.cost)
    return text
  }

  readonly property string tooltipText: {
    if (lastError !== "") return "Pi usage\n" + lastError
    if (!ready) return "Pi usage\ncollecting…"
    if (!hasData) return "Pi usage\nno sessions in " + (report.source || "~/.pi/agent/sessions")
    var lines = [
      "PI · " + periodShort(labelPeriod),
      compactTokens(periodTotals.tokens) + " tokens · " + moneyExact(periodTotals.cost) + " · " + periodTotals.turns + " turns",
      compactTokens(windowTokens) + " tokens · " + moneyExact(windowCost) + " in the last " + spanLabel(windowMinutes),
      compactTokens(periodTotals.cacheRead) + " cache reads (billed, not counted above)",
      (report.lastModel || "unknown model") + " · last burn " + ago(report.lastAt)
    ]
    if (report.sessionsFound) lines.push(report.sessionsFound + " sessions · " + report.turns + " turns on this machine")
    lines.push("click: report · right click: period · middle click: recollect")
    return lines.join("\n")
  }

  // A tooltip is captured by the bar when it is shown, so a number changing
  // under the pointer has to be re-pushed or it goes stale on screen.
  onTooltipTextChanged: if (bar && button.tooltipHovered) bar.showTooltip(button, tooltipText)

  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // ── strip: one cell per collector bucket, oldest on the left ──────────────
  component Strip: Item {
    id: strip

    property var values: []
    property real cellMin: Style.spaceReal(2)
    property real gap: Style.spaceReal(1)

    readonly property int count: values ? values.length : 0
    readonly property real cell: cellMin
    readonly property real maxValue: {
      var max = 0
      for (var i = 0; i < count; i++) {
        var value = Number(values[i]) || 0
        if (value > max) max = value
      }
      return max
    }

    function level(index) {
      var value = Number(values[index]) || 0
      return maxValue > 0 ? Math.min(1, value / maxValue) : 0
    }

    implicitWidth: count > 0 ? count * cell + (count - 1) * gap : 0
    implicitHeight: Style.space(14)

    Repeater {
      model: strip.values
      Rectangle {
        required property int index
        readonly property real level: strip.level(index)
        x: index * (strip.cell + strip.gap)
        width: strip.cell
        height: Math.max(Style.spaceReal(2), Math.round(strip.height * (0.18 + 0.82 * Math.pow(level, 0.6))))
        y: strip.height - height
        radius: height > 4 ? Style.spaceReal(1) : 0
        color: root.heat(level)
        opacity: (Number(strip.values[index]) || 0) > 0 ? 1 : 0.22
        Behavior on height { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
      }
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    labelVisible: false
    hasVisualContent: true
    fixedHeight: -1
    horizontalMargin: 6
    verticalPadding: 6
    fixedWidth: root.vertical
      ? Style.bar.barSize
      : content.implicitWidth + button.scaledHorizontalMargin * 2

    onPressed: function(code) {
      if (code === Qt.MiddleButton) root.collect(true)
      else if (code === Qt.RightButton) root.cyclePeriod()
      else root.toggleCockpit()
    }

    Row {
      id: content
      anchors.centerIn: parent
      spacing: Style.space(6)
      height: Math.max(Style.space(10), Math.min(Style.bar.statusSlot, button.height - Style.space(8)))

      Strip {
        visible: root.showCells && !root.vertical
        anchors.verticalCenter: parent.verticalCenter
        values: root.bucketTokens
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: root.labelText
        color: root.lastError !== "" ? Color.urgent : button.foreground
        font.family: button.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
        renderType: Text.NativeRendering
      }
    }
  }

  IpcHandler {
    target: "zjm.pi-usage"

    function status(): string { return (root.opened ? "open" : "closed") + " · period " + root.labelPeriod + " · " + (root.hasData ? root.compactTokens(root.periodTotals.tokens) : "no data") }
    function refresh(): void { root.refresh() }
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
  }

  Process {
    id: collector
    command: ["python3", root.collectorPath, "--window", String(root.windowMinutes), "--buckets", String(root.cells)]
    onExited: function(exitCode) {
      if (exitCode !== 0) root.lastError = "collector exited " + exitCode
      else if (root.lastError !== "") root.lastError = ""
      reportFile.reload()
    }
  }

  Timer {
    interval: root.refreshSec * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.collect(false)
  }

  FileView {
    id: reportFile
    path: root.reportPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var parsed = JSON.parse(text())
        if (parsed && typeof parsed === "object") {
          root.report = parsed
          root.ready = true
        }
      } catch (error) {
        root.lastError = "unreadable report: " + error
      }
    }
  }

  PiUsagePanel {
    id: panel
    widget: root
  }
}
