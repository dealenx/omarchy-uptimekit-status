import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "UptimeKit.js" as UptimeKit

// UptimeKit status on the bar: a coloured status glyph and "3/4 up", read from
// the status page's public summary.json (no API key).
//
//   left click   opens the panel
//   right click  opens the status page in the browser
//   middle click refreshes now
//
// The panel is part of this bar widget (see Panel.qml), as the Omarchy plugin
// contract expects: this file keeps open/close/opened and forwards them.
BarWidget {
  id: root
  moduleName: "dealenx.uptimekit-status"

  readonly property bool configured: summaryModel.configured
  readonly property var summary: summaryModel.summary
  readonly property var counts: UptimeKit.rollup(summary)
  readonly property bool loading: summaryModel.loading
  readonly property bool failed: summaryModel.failed

  // What the label counts, and how large it is drawn. `labelMode` is one of
  // ratio, percent, count, status (see UptimeKit.barLabel).
  readonly property string labelMode: UptimeKit.labelMode(setting("labelMode", "ratio"))
  readonly property bool openOnRightClick: setting("openUrlOnRightClick", true) === true
  // A percentage of the bar's own icon font, clamped so a hand-edited value
  // cannot make the label unreadable or taller than the bar.
  readonly property int labelFontPercent: UptimeKit.labelFontPercent(setting("labelFontPercent", 100))

  // Bar label: the configured reading when there is data, a dash while the
  // first poll is in flight, nothing at all before the URL is set.
  readonly property string label: {
    if (!configured) return ""
    if (!summary) return loading ? "\u2026" : "\u2014"
    return UptimeKit.barLabel(summary, labelMode)
  }

  // Green for healthy, yellow for anything degraded or in maintenance, red for
  // an outage, grey while there is no reading at all. These are the theme's own
  // palette entries, so a light theme gets a readable dark green rather than a
  // fixed bright one.
  readonly property color statusColor: {
    if (!configured) return Commons.Color.muted
    if (!summary) return failed ? bar.urgent : Commons.Color.muted
    switch (counts.status) {
      case "operational": return themeColors.green
      case "maintenance": return themeColors.yellow
      case "degraded": return themeColors.yellow
      case "outage": return themeColors.red
      default: return Commons.Color.muted
    }
  }

  readonly property string glyph: {
    if (!configured) return "\uF013"          // gear: needs setting up
    if (loading && !summary) return "\uF110"  // spinner while the first poll runs
    if (!summary) return "\uF071"             // warning: nothing received
    return UptimeKit.statusGlyph(counts.status)
  }

  readonly property string tooltip: {
    if (!configured) return strings.t("bar.notConfigured")
    var hint = strings.t("bar.tooltip.open")
    if (!summary) return (failed ? summaryModel.errorText : strings.t("panel.noData")) + "\n" + hint
    // The tooltip always carries both readings, whatever the bar shows: the
    // label is a glance, the tooltip is the answer.
    return pageTitle + "\n" + counts.up + "/" + counts.total + " \u00B7 "
      + UptimeKit.upPercent(summary) + "%\n" + hint
  }

  readonly property string pageTitle: summary && summary.page && summary.page.name !== ""
    ? summary.page.name : "UptimeKit"
  readonly property string pageUrl: summary && summary.page && summary.page.url !== ""
    ? summary.page.url : UptimeKit.pageUrl(setting("baseUrl", ""), setting("slug", ""))

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }

  // IPC for scripting and the shell's own socket: `omarchy-shell
  // dealenx.uptimekit-status status`. Every copy on every monitor answers a
  // refresh, so it lands on all screens instead of the one owning the target.
  ShellIpc {
    target: "dealenx.uptimekit-status"

    function refresh(): void {
      root.broadcast("refresh")
    }

    function status(): string {
      return JSON.stringify({
        configured: root.configured,
        page: root.pageTitle,
        url: root.pageUrl,
        status: root.counts.status,
        up: root.counts.up,
        total: root.counts.total,
        loading: root.loading,
        failed: root.failed,
        error: summaryModel.errorText,
        updatedAt: root.summary ? root.summary.updatedAt : "",
        // Which screen the card is on, for scripting and for the tests.
        page: panelLoader.item ? panelLoader.item.page : ""
      })
    }

    function open(): void {
      root.open()
    }

    // Open straight onto the settings screen: `omarchy-shell
    // dealenx.uptimekit-status settings`.
    function settings(): void {
      root.open()
      if (panelLoader.item && typeof panelLoader.item.showSettings === "function")
        panelLoader.item.showSettings()
    }

    function close(): void {
      root.close()
    }
  }

  // The active theme's palette. Commons.Color exposes only the shell's own
  // surfaces (foreground, accent, urgent, muted); semantic status colours are
  // in the theme's colors.toml, which this reads the same way the shell does.
  ThemePalette { id: themeColors }

  Summary {
    id: summaryModel
    baseUrl: String(setting("baseUrl", ""))
    slug: String(setting("slug", ""))
    intervalSeconds: UptimeKit.pollSeconds(setting("intervalSeconds", 30))
    // Nothing is fetched until the user has a URL to fetch from.
    polling: configured
  }

  // Re-injected into the loaded panel on every settings change, so the panel
  // never edits a stale copy of what the bar is reading.
  function injectPanel() {
    var target = panelLoader.item
    if (!target) return
    target.bar = root.bar
    target.settings = root.settings
    target.anchorItem = button
    target.hostWidget = root
    target.summary = root.summary
    target.loading = root.loading
    target.failed = root.failed
    target.errorText = summaryModel.errorText
    target.configured = root.configured
  }

  onSummaryChanged: injectPanel()
  onLoadingChanged: injectPanel()
  onFailedChanged: injectPanel()
  onConfiguredChanged: injectPanel()
  // The shell writes a setting back through this object; the panel edits the
  // same copy, so it has to see the write land.
  onSettingsChanged: injectPanel()

  // ---- Panel lifecycle. The bar routes clicks, Escape, and the shell's own
  //      summon/hide/toggle through these.
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item
    ? panelLoader.item.popoutSwitchClosing === true
    : false

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  // Clicking the icon while the panel is up closes it, like every other bar
  // panel. The guard covers the click that dismissed the card by clearing its
  // focus grab: that same click lands here, and without it the card would shut
  // and reopen in one gesture.
  property bool justClosed: false
  function toggle() {
    if (opened) {
      justClosed = true
      closeGuard.restart()
      close()
      return
    }
    if (justClosed) return
    open()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  Timer {
    id: closeGuard
    interval: 220
    onTriggered: root.justClosed = false
  }

  // ---- Actions ------------------------------------------------

  function refresh() {
    summaryModel.requestRevision++
  }

  // The panel saves through this object so the bar re-reads immediately, then
  // the shell's own write to shell.json lands back through `settings`.
  function saveSetting(key, value) {
    var next = {}
    var current = settings || {}
    for (var k in current) if (k !== "id") next[k] = current[k]
    next[key] = value
    settings = next
    if (bar && bar.shell && typeof bar.shell.updateEntryInline === "function")
      bar.shell.updateEntryInline(moduleName, next)
  }

  function openPage() {
    if (root.pageUrl === "") return
    // execArgv keeps the URL a single literal argument: a shell that re-tokenized
    // it would split a query string at its ampersands.
    Commons.Util.execArgv(["xdg-open", root.pageUrl])
  }

  function handleClick(buttonCode) {
    if (buttonCode === Qt.RightButton) {
      if (openOnRightClick) openPage()
      else toggle()
      return
    }
    if (buttonCode === Qt.MiddleButton) {
      refresh()
      return
    }
    toggle()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  // Icon and counts in one button. BarIconButton gives the glyph the shell's
  // optical centring; the label rides beside it, as the power widget does with
  // its percentage. Its slot has to be widened by hand: BarIconButton fixes the
  // width at `slotSize` and would crop a label that hangs off the icon.
  //
  // `active` is the button's "mark this out" state, and its colour is exactly
  // the status colour: the counts beside the glyph stay in the bar foreground,
  // so the glyph is what carries the reading.
  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.glyph
    labelText: root.vertical ? "" : root.label
    // WidgetButton sizes the label from its own fontSize, which is also the
    // font its OpticalGlyph measures against, so the label is scaled here and
    // the glyph keeps the bar's icon size.
    fontSize: Style.bar.iconFont * root.labelFontPercent / 100
    active: root.configured
    activeColor: root.statusColor
    slotSize: Style.bar.statusSlot + (labelText !== "" ? labelMetrics.advanceWidth + Style.space(4) : 0)
    tooltipText: root.tooltip

    // Measured with the label's real font, so the slot is as wide as what is
    // painted and no wider.
    TextMetrics {
      id: labelMetrics
      font.family: button.fontFamily
      font.pixelSize: button.fontSize
      text: button.labelText
    }

    onPressed: function(buttonCode) { root.handleClick(buttonCode) }
  }
}
