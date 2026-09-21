import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui

// Detail view for Pi Usage: what the strip in the bar cannot say. One column,
// top to bottom: the day's headline, the four periods side by side, the burn
// window the bar draws, a full day by the hour, then where the tokens went —
// model, project, session.
Panel {
  id: panel
  moduleName: "zjm.pi-usage"
  manageIpc: false

  required property var widget
  readonly property var report: widget.report || ({})
  readonly property var totals: report.totals || ({})

  readonly property color foreground: widget.bar ? widget.bar.barForeground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.5)
  readonly property color faint: Util.alpha(foreground, 0.05)
  readonly property color accentColor: widget.accentColor
  readonly property string fontFamily: widget.bar ? widget.bar.fontFamily : Style.font.family

  // Relative times go stale while the panel is open; a 1s tick re-evaluates
  // the few bindings that read it.
  property int tick: 0
  Timer {
    interval: 1000
    running: panel.opened
    repeat: true
    onTriggered: panel.tick++
  }

  readonly property var periodRing: widget.periodRing

  function range(id) {
    return totals[id] || ({ tokens: 0, cost: 0, cacheRead: 0, turns: 0, sessions: 0 })
  }

  function periodCaption(id) {
    return id === "d7" ? "7 DAYS" : id === "d30" ? "30 DAYS" : id === "all" ? "ALL TIME" : "TODAY"
  }

  function valuesOf(rows) {
    var out = []
    if (!rows) return out
    for (var i = 0; i < rows.length; i++) out.push(Number(rows[i].tokens) || 0)
    return out
  }

  function mix(a, b, t) {
    return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, 1)
  }

  function heat(accent, front, level) {
    var l = Math.max(0, Math.min(1, Number(level) || 0))
    if (l < 0.7) return mix(Qt.darker(accent, 2.1), accent, l / 0.7)
    return mix(accent, front, (l - 0.7) / 0.3 * 0.85)
  }

  function windowStartLabel() {
    return panel.widget.ago(report.generatedAt ? report.generatedAt - panel.widget.windowMinutes * 60000 : 0)
      .replace(" ago", " back")
  }

  function sessionTitle(row) {
    if (row.name !== "") return row.name
    return row.cwd !== "" ? row.cwd : (row.id !== "" ? row.id.slice(0, 8) : "session")
  }

  // ── refresh button for the hero's trailing edge ───────────────────────────
  component RefreshAction: Button {
    text: "Refresh"
    bordered: true
    foreground: panel.foreground
    accent: panel.accentColor
    fontSize: Style.font.bodySmall
    onClicked: panel.widget.refresh()
  }

  component Caption: Text {
    textFormat: Text.PlainText
    color: panel.dim
    font.family: panel.fontFamily
    font.pixelSize: Style.font.caption
    elide: Text.ElideRight
  }

  // PanelSeparator binds its own width to its parent, which fights a Layout;
  // inside the ColumnLayout below a plain rule is the same line without the
  // second width writer.
  component Rule: Rectangle {
    Layout.fillWidth: true
    implicitHeight: 1
    height: 1
    color: Util.alpha(panel.foreground, 0.12)
  }

  // ── heat strip: one cell per bucket, oldest on the left ───────────────────
  component Strip: Item {
    id: strip

    property var values: []
    property color accent: Color.accent
    property color front: Color.foreground
    property real gap: Style.spaceReal(2)
    property real minCell: Style.spaceReal(3)

    readonly property int count: values ? values.length : 0
    readonly property real cell: count > 0 ? Math.max(minCell, (width - (count - 1) * gap) / count) : minCell
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

    implicitWidth: count > 0 ? count * minCell + (count - 1) * gap : 0
    implicitHeight: Style.space(26)

    Repeater {
      model: strip.values
      Rectangle {
        required property int index
        readonly property real level: strip.level(index)
        x: index * (strip.cell + strip.gap)
        width: strip.cell
        height: Math.max(Style.spaceReal(2), Math.round(strip.height * (0.16 + 0.84 * Math.pow(level, 0.6))))
        y: strip.height - height
        radius: height > 4 ? Style.spaceReal(1) : 0
        color: panel.heat(strip.accent, strip.front, level)
        opacity: (Number(strip.values[index]) || 0) > 0 ? 1 : 0.22
      }
    }
  }

  // ── one period tile ──────────────────────────────────────────────────────
  component Tile: Rectangle {
    id: tile

    property string caption: ""
    property string value: ""
    property string note: ""
    property string sub: ""
    property bool highlight: false

    Layout.fillWidth: true
    implicitHeight: tileColumn.implicitHeight + Style.space(16)
    // A belt to the braces below: if a label is ever longer than the plate,
    // it is cut at the plate's edge instead of painted over its neighbour.
    clip: true
    color: Util.alpha(panel.foreground, highlight ? 0.09 : 0.045)
    radius: Style.cornerRadius
    border.width: highlight ? Math.max(1, Style.space(1)) : 0
    border.color: Util.alpha(panel.accentColor, highlight ? 0.55 : 0)

    Column {
      id: tileColumn
      x: Style.space(10)
      y: Style.space(8)
      width: parent.width - Style.space(20)
      spacing: Style.space(2)

      // Every line is width-bound to the plate and elides: a caption font
      // scaled up by the user's text size must not spill into the next tile.
      Caption {
        width: tileColumn.width
        text: tile.caption
        font.bold: true
        color: tile.highlight ? panel.accentColor : panel.dim
      }
      Text {
        textFormat: Text.PlainText
        width: tileColumn.width
        text: tile.value
        elide: Text.ElideRight
        color: panel.foreground
        font.family: panel.fontFamily
        font.pixelSize: Style.font.title
        font.bold: true
      }
      Caption { width: tileColumn.width; text: tile.note }
      Caption { width: tileColumn.width; visible: tile.sub !== ""; text: tile.sub }
    }
  }

  // ── one label / value row in a table ─────────────────────────────────────
  component DataRow: RowLayout {
    id: row

    property string label: ""
    property string note: ""
    property string value: ""
    property color valueColor: panel.foreground

    Layout.fillWidth: true
    spacing: Style.space(8)

    Text {
      textFormat: Text.PlainText
      text: row.label
      Layout.fillWidth: true
      Layout.preferredWidth: 0
      elide: Text.ElideRight
      color: panel.foreground
      font.family: panel.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
    Caption {
      visible: row.note !== ""
      text: row.note
      Layout.alignment: Qt.AlignVCenter
    }
    Text {
      textFormat: Text.PlainText
      text: row.value
      Layout.alignment: Qt.AlignVCenter
      color: row.valueColor
      font.family: panel.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: true
    }
  }

  component Section: PanelSectionHeader {
    foreground: panel.foreground
    fontFamily: panel.fontFamily
    elide: Text.ElideRight
  }

  KeyboardPanel {
    id: kpanel
    anchorItem: panel.widget
    owner: panel.widget
    bar: panel.widget.bar
    open: panel.opened
    focusTarget: keyCatcher
    contentWidth: kpanel.fittedContentWidth(Style.space(760))
    contentHeight: kpanel.fittedContentHeight(content.implicitHeight, Style.space(900))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: panel.widget.close()
      onTextKey: function(text) {
        var index = "1234".indexOf(text)
        if (index >= 0) panel.widget.setPeriod(panel.periodRing[index])
        else if (text === "r" || text === "R") panel.widget.refresh()
      }

      ColumnLayout {
        id: content
        width: parent.width
        spacing: Style.space(10)

        // ── headline ────────────────────────────────────────────────────────
        PanelHero {
          Layout.fillWidth: true
          title: panel.widget.compactTokens(panel.range("today").tokens) + " tokens today"
          detail: panel.widget.moneyExact(panel.range("today").cost)
          meta: "pi · " + (panel.report.lastModel || "no model yet")
            + "  ·  " + (panel.report.sessionsFound || 0) + " sessions"
            + "  ·  " + (panel.report.turns || 0) + " turns"
            + "  ·  last burn " + panel.widget.ago(panel.report.lastAt)
          foreground: panel.foreground
          fontFamily: panel.fontFamily
          trailingControl: Component { RefreshAction { } }
        }

        Rule {}

        // ── the four periods ────────────────────────────────────────────────
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(8)

          Repeater {
            model: panel.periodRing

            Tile {
              required property string modelData
              readonly property var row: panel.range(modelData)
              caption: panel.periodCaption(modelData)
              value: panel.widget.compactTokens(row.tokens)
              // Two short lines rather than one long one: "$0.71 · 1898 turns"
              // plus "5 sessions" is the same information a third narrower.
              note: panel.widget.money(row.cost) + " · " + panel.widget.turnsText(row)
              sub: Number(row.turns) > 0 ? panel.widget.sessionsText(row) : "no burn"
              highlight: modelData === panel.widget.labelPeriod
            }
          }
        }

        Caption {
          Layout.fillWidth: true
          text: "Cache reads are billed but left out of the token figures above: "
            + panel.widget.compactTokens(panel.range(panel.widget.labelPeriod).cacheRead)
            + " reads in " + panel.widget.periodName(panel.widget.labelPeriod) + "."
        }

        // ── the window the bar strip draws ──────────────────────────────────
        Section { Layout.fillWidth: true; text: "BURN · LAST " + panel.widget.spanLabel(panel.widget.windowMinutes).toUpperCase() }

        Strip {
          Layout.fillWidth: true
          Layout.preferredHeight: Style.space(26)
          values: panel.valuesOf(panel.report.buckets)
          accent: panel.accentColor
          front: panel.foreground
          gap: Style.spaceReal(2)
        }

        RowLayout {
          Layout.fillWidth: true
          Caption { Layout.fillWidth: true; text: panel.widget.spanLabel(panel.report.bucketMinutes || 30) + " per cell · " + panel.windowStartLabel() }
          Caption { text: "now" }
        }

        // ── a full day, by the hour ─────────────────────────────────────────
        Section { Layout.fillWidth: true; text: "HOURLY · LAST " + (panel.report.hourly ? panel.report.hourly.length : 24) + " HOURS" }

        Strip {
          Layout.fillWidth: true
          Layout.preferredHeight: Style.space(20)
          values: panel.valuesOf(panel.report.hourly)
          accent: panel.accentColor
          front: panel.foreground
          gap: Style.spaceReal(2)
        }

        RowLayout {
          Layout.fillWidth: true
          Caption { Layout.fillWidth: true; text: "peak hour " + panel.widget.compactTokens(panel.peakHour()) + " tokens" }
          Caption { text: "oldest left · newest right" }
        }

        Rule {}

        // ── where the tokens went ───────────────────────────────────────────
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(20)

          ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.space(4)

            Section { Layout.fillWidth: true; text: "BY MODEL · 7 DAYS" }

            Repeater {
              model: panel.report.byModel || []

              DataRow {
                required property var modelData
                label: modelData.model
                note: modelData.turns + " turns"
                value: panel.widget.compactTokens(modelData.tokens)
              }
            }

            Caption {
              visible: (panel.report.byModel || []).length === 0
              text: "nothing burned in the last 7 days"
            }
          }

          ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.space(4)

            Section { Layout.fillWidth: true; text: "BY PROJECT · 7 DAYS" }

            Repeater {
              model: panel.report.projects || []

              DataRow {
                required property var modelData
                label: modelData.name
                note: panel.widget.money(modelData.cost)
                value: panel.widget.compactTokens(modelData.tokens)
              }
            }

            Caption {
              visible: (panel.report.projects || []).length === 0
              text: "nothing burned in the last 7 days"
            }
          }
        }

        Rule {}

        // ── sessions ────────────────────────────────────────────────────────
        Section { Layout.fillWidth: true; text: "RECENT SESSIONS" }

        Repeater {
          model: panel.report.sessions || []

          DataRow {
            required property var modelData
            label: panel.sessionTitle(modelData)
            note: modelData.turns + " turns · " + panel.widget.ago(modelData.lastAt)
            value: panel.widget.compactTokens(modelData.tokens) + " · " + panel.widget.money(modelData.cost)
          }
        }

        Caption {
          visible: (panel.report.sessions || []).length === 0
          text: "no sessions found under " + (panel.report.source || "~/.pi/agent/sessions")
        }

        Rule {}

        // ── footer ──────────────────────────────────────────────────────────
        RowLayout {
          Layout.fillWidth: true
          spacing: Style.space(6)

          Caption {
            Layout.fillWidth: true
            text: {
              void panel.tick
              return "collected " + panel.widget.ago(panel.report.generatedAt)
                + " · " + (panel.report.source || "~/.pi/agent/sessions")
            }
          }
          Caption { text: "1-4 period · R refresh · Esc close" }
        }
      }
    }
  }

  function peakHour() {
    var rows = report.hourly || []
    var max = 0
    for (var i = 0; i < rows.length; i++) max = Math.max(max, Number(rows[i].tokens) || 0)
    return max
  }
}
