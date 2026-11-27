import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "UptimeKit.js" as UptimeKit

// The UptimeKit card: the page's own status, its open incidents and
// maintenance windows, every component grouped as the page groups them, and a
// settings screen behind the gear icon.
//
// Data belongs to the bar widget that hosts this panel; the panel never polls
// on its own. It renders what it is handed and writes settings through the
// shell's bar entry, exactly as the built-in widgets do.
Panel {
  id: root
  moduleName: "dealenx.uptimekit-status"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null

  // Fed by BarWidget.qml on load and on every change.
  property var summary: null
  property bool loading: false
  property bool failed: false
  property string errorText: ""
  property bool configured: false

  property string page: "overview"

  // The card's built content, once it has opened at least once. A Component's
  // own ids are unreachable from outside, so the loaded root is exposed the
  // same way built-in panels alias their hero and list items.
  readonly property Item contentRoot: panel.loadedContent

  readonly property var counts: UptimeKit.rollup(summary)
  readonly property string pageTitle: summary && summary.page && summary.page.name !== ""
    ? summary.page.name : strings.t("panel.title")
  readonly property string pageUrl: summary && summary.page && summary.page.url !== ""
    ? summary.page.url : UptimeKit.pageUrl(setting("baseUrl", ""), setting("slug", ""))
  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.4)
  readonly property color accent: Commons.Color.accent
  readonly property color muted: Commons.Color.muted
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }
  ThemePalette { id: themeColors }

  readonly property color statusColor: {
    switch (counts.status) {
      case "operational": return themeColors.green
      case "degraded": return themeColors.yellow
      case "maintenance": return themeColors.yellow
      case "outage": return themeColors.red
      default: return muted
    }
  }

  function statusText(status) {
    switch (status) {
      case "operational": return strings.t("panel.status.operational")
      case "degraded": return strings.t("panel.status.degraded")
      case "outage": return strings.t("panel.status.outage")
      case "maintenance": return strings.t("panel.status.maintenance")
      default: return strings.t("panel.status.unknown")
    }
  }

  function componentText(status) {
    var known = ["up", "down", "degraded", "maintenance", "pending"]
    return known.indexOf(status) === -1
      ? strings.t("component.unknown")
      : strings.t("component." + status)
  }

  // "2m ago", localized. An unparseable timestamp says nothing at all rather
  // than inventing a time.
  function updatedText() {
    var seconds = UptimeKit.ageSeconds(summary ? summary.updatedAt : "", Date.now())
    if (seconds < 0) return ""
    var value
    if (seconds < 60) return strings.t("panel.justNow")
    if (seconds < 3600) {
      value = Math.floor(seconds / 60)
      return strings.t("panel.minutesAgo").arg(value)
    }
    if (seconds < 86400) {
      value = Math.floor(seconds / 3600)
      return strings.t("panel.hoursAgo").arg(value)
    }
    value = Math.floor(seconds / 86400)
    return strings.t("panel.daysAgo").arg(value)
  }

  function open() {
    showOverview()
    root.controller.show()
  }

  function close() {
    root.controller.hide()
  }

  function showOverview() {
    if (root.page === "overview") return
    root.page = "overview"
  }

  // Reached by the gear in the panel header, and over IPC for scripting.
  function showSettings() {
    if (root.page === "settings") return
    root.page = "settings"
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.hostWidget || root, direction)
    return false
  }

  function openPage() {
    if (root.pageUrl === "") return
    Commons.Util.execArgv(["xdg-open", root.pageUrl])
  }

  function refresh() {
    if (root.hostWidget && typeof root.hostWidget.refresh === "function") root.hostWidget.refresh()
  }

  // Settings edits go to the bar widget first, so its `settings` object and the
  // bar re-render immediately; the shell's write to shell.json then comes back
  // through `settings` and re-injects this panel.
  function previewSetting(key, value) {
    if (!root.hostWidget) return
    var next = {}
    var current = root.hostWidget.settings || {}
    for (var k in current) next[k] = current[k]
    next[key] = value
    root.hostWidget.settings = next
    root.settings = next
  }

  function saveSetting(key, value) {
    previewSetting(key, value)
    // The host widget owns the bar entry the shell writes to; the panel only
    // renders. Asking it keeps one writer and one source of truth.
    if (root.hostWidget && typeof root.hostWidget.saveSetting === "function") {
      root.hostWidget.saveSetting(key, value)
      return
    }
    if (bar && bar.shell && typeof bar.shell.updateEntryInline === "function")
      bar.shell.updateEntryInline(root.moduleName, root.settings)
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    // The content is a Component, built on first open, so its own ids are not
    // reachable from here. The panel exposes what it built instead.
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight)

    content: PanelKeyCatcher {
      anchors.fill: parent
      // Only the page on screen is laid out, so this is the visible page's
      // height, which the card grows to. A Flickable has no implicit height of
      // its own, so this reads the columns the page is drawn from; content
      // taller than the screen is capped by the card and scrolls.
      implicitHeight: root.page === "settings"
        ? settingsColumn.implicitHeight
        : overviewColumn.implicitHeight
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Flickable {
        id: overviewFlick
        anchors.fill: parent
        visible: root.page === "overview"
        contentWidth: width
        contentHeight: overviewColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: overviewColumn
          width: overviewFlick.width
          spacing: Style.space(8)

          // ---- Header: page name, gear.
          Item {
            width: parent.width
            implicitHeight: Math.max(titleLabel.implicitHeight, settingsButton.implicitHeight)

            Text {
              id: titleLabel
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width - settingsButton.width - Style.space(6)
              text: root.pageTitle
              textFormat: Text.PlainText
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
              elide: Text.ElideRight
            }

            PanelActionButton {
              id: settingsButton
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              iconText: "\u{F013}"
              tooltipText: strings.t("panel.settingsButton")
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.showSettings()
            }
          }

          // ---- Headline: the overall verdict, coloured.
          Row {
            width: parent.width
            spacing: Style.space(8)
            visible: root.summary !== null

            Text {
              text: UptimeKit.statusGlyph(root.counts.status)
              color: root.statusColor
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
              anchors.verticalCenter: parent.verticalCenter
            }

            Text {
              width: parent.width - Style.space(30)
              text: root.statusText(root.counts.status)
              textFormat: Text.PlainText
              color: root.statusColor
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
              wrapMode: Text.WordWrap
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          Row {
            width: parent.width
            spacing: Style.space(8)
            visible: root.summary !== null && root.counts.total > 0

            Text {
              id: countsLabel
              text: strings.t("panel.upOf").arg(root.counts.up).arg(root.counts.total)
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }

            Text {
              text: root.updatedText() === "" ? "" : strings.t("panel.updated").arg(root.updatedText())
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              anchors.baseline: countsLabel.baseline
            }
          }

          // ---- Not configured, loading, and transport failure states.
          Text {
            width: parent.width
            visible: !root.configured
            text: strings.t("panel.notConfigured")
            textFormat: Text.PlainText
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
          }

          Text {
            width: parent.width
            visible: root.configured && root.summary === null && root.loading
            text: strings.t("panel.loading")
            textFormat: Text.PlainText
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
          }

          Text {
            width: parent.width
            visible: root.configured && root.summary === null && !root.loading
            text: root.failed
              ? strings.t("panel.lastFailed").arg(root.errorText) + " " + strings.t("panel.noData")
              : strings.t("panel.noData")
            textFormat: Text.PlainText
            color: root.failed ? themeColors.red : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            wrapMode: Text.WordWrap
          }

          Text {
            width: parent.width
            visible: root.configured && root.summary !== null && root.failed
            text: strings.t("panel.lastFailed").arg(root.errorText) + " " + strings.t("panel.offline")
            textFormat: Text.PlainText
            color: themeColors.yellow
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }

          // ---- Incidents.
          Item {
            width: parent.width
            implicitHeight: incidentsColumn.implicitHeight
            visible: root.summary !== null && root.summary.incidents.length > 0

            Column {
              id: incidentsColumn
              width: parent.width
              spacing: Style.space(4)

              PanelSectionHeader {
                text: strings.t("panel.incidents")
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              Repeater {
                model: root.summary ? root.summary.incidents : []
                delegate: Column {
                  width: incidentsColumn.width
                  spacing: Style.space(1)

                  Text {
                    width: parent.width
                    text: "\u26A0 " + modelData.title
                    textFormat: Text.PlainText
                    color: themeColors.yellow
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    wrapMode: Text.WordWrap
                  }

                  Text {
                    width: parent.width
                    text: modelData.status + (modelData.severity !== "" ? " \u00B7 " + modelData.severity : "")
                    textFormat: Text.PlainText
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
              }
            }
          }

          // ---- Maintenance windows.
          Item {
            width: parent.width
            implicitHeight: maintenancesColumn.implicitHeight
            visible: root.summary !== null && root.summary.maintenances.length > 0

            Column {
              id: maintenancesColumn
              width: parent.width
              spacing: Style.space(4)

              PanelSectionHeader {
                text: strings.t("panel.maintenances")
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              Repeater {
                model: root.summary ? root.summary.maintenances : []
                delegate: Column {
                  width: maintenancesColumn.width
                  spacing: Style.space(1)

                  Text {
                    width: parent.width
                    text: "\u2699 " + modelData.title
                    textFormat: Text.PlainText
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.body
                    wrapMode: Text.WordWrap
                  }

                  Text {
                    width: parent.width
                    text: modelData.status
                    textFormat: Text.PlainText
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
              }
            }
          }

          // ---- Components, grouped.
          Item {
            width: parent.width
            implicitHeight: componentsColumn.implicitHeight
            visible: root.summary !== null

            Column {
              id: componentsColumn
              width: parent.width
              spacing: Style.space(4)

              PanelSectionHeader {
                text: strings.t("panel.components")
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              Text {
                width: parent.width
                visible: root.summary !== null && root.summary.components.length === 0
                text: strings.t("panel.componentsEmpty")
                textFormat: Text.PlainText
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }

              Repeater {
                model: UptimeKit.groupedComponents(root.summary)
                delegate: Column {
                  width: componentsColumn.width
                  spacing: Style.space(2)

                  Text {
                    width: parent.width
                    visible: modelData.name !== ""
                    text: modelData.name
                    textFormat: Text.PlainText
                    color: root.dim
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                    font.bold: true
                  }

                  Repeater {
                    model: modelData.components
                    delegate: Item {
                      width: componentsColumn.width
                      implicitHeight: Math.max(componentName.implicitHeight, componentStatus.implicitHeight)

                      Text {
                        id: componentName
                        anchors.left: parent.left
                        width: parent.width - componentStatus.width - Style.space(8)
                        text: (modelData.status === "up" ? "\u25CF  " : "\u25CB  ") + modelData.name
                        textFormat: Text.PlainText
                        color: modelData.status === "up" ? root.foreground : themeColors.red
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                        elide: Text.ElideRight
                      }

                      Text {
                        id: componentStatus
                        anchors.right: parent.right
                        text: root.componentText(modelData.status)
                        textFormat: Text.PlainText
                        color: modelData.status === "up" ? themeColors.green : themeColors.red
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                      }
                    }
                  }
                }
              }
            }
          }

          PanelSeparator { foreground: root.foreground }

          // ---- Actions.
          Row {
            width: parent.width
            spacing: Style.space(6)

            Button {
              width: (parent.width - parent.spacing) / 2
              text: strings.t("panel.openPage")
              bordered: true
              enabled: root.pageUrl !== ""
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onClicked: root.openPage()
            }

            Button {
              width: (parent.width - parent.spacing) / 2
              text: root.loading ? strings.t("panel.refreshing") : strings.t("panel.refresh")
              bordered: true
              enabled: root.configured && !root.loading
              foreground: root.foreground
              accent: root.accent
              fontFamily: root.fontFamily
              onClicked: root.refresh()
            }
          }
        }
      }

      Flickable {
        id: settingsFlick
        anchors.fill: parent
        visible: root.page === "settings"
        contentWidth: width
        contentHeight: settingsColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: settingsColumn
          width: settingsFlick.width
          spacing: Style.space(10)

          Item {
            width: parent.width
            implicitHeight: Math.max(settingsHeading.implicitHeight, backButton.implicitHeight)

            PanelActionButton {
              id: backButton
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              iconText: "\u{F0151}"
              tooltipText: strings.t("panel.back")
              foreground: root.foreground
              fontFamily: root.fontFamily
              onClicked: root.showOverview()
            }

            Text {
              id: settingsHeading
              anchors.left: backButton.right
              anchors.leftMargin: Style.space(6)
              anchors.verticalCenter: parent.verticalCenter
              text: strings.t("panel.settings")
              textFormat: Text.PlainText
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
            }
          }

          // Text settings commit on Enter or when focus leaves the field, so a
          // half-typed URL never triggers a poll.
          SettingField {
            width: parent.width
            label: strings.t("settings.baseUrl.label")
            description: strings.t("settings.baseUrl.description")
            value: String(root.setting("baseUrl", ""))
            placeholder: "https://status.example.com"
            onCommitted: function(text) { root.saveSetting("baseUrl", text.trim()) }
          }

          SettingField {
            width: parent.width
            label: strings.t("settings.slug.label")
            description: strings.t("settings.slug.description")
            value: String(root.setting("slug", ""))
            placeholder: "api"
            onCommitted: function(text) { root.saveSetting("slug", text.trim()) }
          }

          // Interval: 10 s to 1 h, the same range the manifest advertises.
          Column {
            width: parent.width
            spacing: Style.space(5)

            Item {
              width: parent.width
              implicitHeight: Math.max(intervalLabel.implicitHeight, intervalValue.implicitHeight)

              Text {
                id: intervalLabel
                anchors.left: parent.left
                text: strings.t("settings.interval.label")
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }

              Text {
                id: intervalValue
                anchors.right: parent.right
                text: Math.round(intervalSlider.dragging
                  ? intervalSlider.liveValue
                  : Number(root.setting("intervalSeconds", 30))) + " s"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            PanelSlider {
              id: intervalSlider
              width: parent.width
              bar: root.bar
              minimum: 10
              maximum: 3600
              step: 10
              integer: true
              value: Number(root.setting("intervalSeconds", 30))
              onMoved: function(value) {
                root.previewSetting("intervalSeconds", UptimeKit.pollSeconds(Math.round(value / 10) * 10))
              }
              onReleased: function(value) {
                root.saveSetting("intervalSeconds", UptimeKit.pollSeconds(Math.round(value / 10) * 10))
              }
            }

            Text {
              width: parent.width
              text: strings.t("settings.interval.description")
              textFormat: Text.PlainText
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          // What the bar shows beside the glyph. Four readings of the same
          // numbers, so none of them is a separate data path.
          Column {
            width: parent.width
            spacing: Style.space(5)

            Text {
              width: parent.width
              text: strings.t("settings.labelMode.label")
              textFormat: Text.PlainText
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
            }

            ButtonGroup {
              width: parent.width
              options: [
                { value: "ratio", label: strings.t("settings.labelMode.ratio") },
                { value: "percent", label: strings.t("settings.labelMode.percent") },
                { value: "count", label: strings.t("settings.labelMode.count") },
                { value: "status", label: strings.t("settings.labelMode.status") }
              ]
              value: root.setting("labelMode", "ratio")
              foreground: root.foreground
              background: root.bar ? root.bar.background : Commons.Color.background
              accent: root.accent
              fontFamily: root.fontFamily
              fontSize: Style.font.bodySmall
              focusable: false
              onChanged: function(mode) { root.saveSetting("labelMode", mode) }
            }

            Text {
              width: parent.width
              text: strings.t("settings.labelMode.description")
              textFormat: Text.PlainText
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          // Label size, as a percentage of the bar's own label size.
          Column {
            width: parent.width
            spacing: Style.space(5)

            Item {
              width: parent.width
              implicitHeight: Math.max(labelSizeTitle.implicitHeight, labelSizeValue.implicitHeight)

              Text {
                id: labelSizeTitle
                anchors.left: parent.left
                text: strings.t("settings.labelFont.label")
                textFormat: Text.PlainText
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
              }

              Text {
                id: labelSizeValue
                anchors.right: parent.right
                text: Math.round(labelSizeSlider.dragging
                  ? labelSizeSlider.liveValue
                  : UptimeKit.labelFontPercent(root.setting("labelFontPercent", 100))) + "%"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            PanelSlider {
              id: labelSizeSlider
              width: parent.width
              bar: root.bar
              minimum: 60
              maximum: 140
              step: 5
              integer: true
              value: UptimeKit.labelFontPercent(root.setting("labelFontPercent", 100))
              onMoved: function(value) { root.previewSetting("labelFontPercent", Math.round(value / 5) * 5) }
              onReleased: function(value) {
                root.saveSetting("labelFontPercent", UptimeKit.labelFontPercent(Math.round(value / 5) * 5))
              }
            }

            Text {
              width: parent.width
              text: strings.t("settings.labelFont.description")
              textFormat: Text.PlainText
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          Toggle {
            width: parent.width
            label: strings.t("settings.rightClick.label")
            description: strings.t("settings.rightClick.description")
            checked: root.setting("openUrlOnRightClick", true) !== false
            foreground: root.foreground
            accent: root.accent
            fontFamily: root.fontFamily
            onClicked: root.saveSetting("openUrlOnRightClick",
              !(root.setting("openUrlOnRightClick", true) !== false))
          }
        }
      }
    }
  }

  // A labelled text setting: title, description, and a field that commits on
  // Enter or when it loses focus.
  component SettingField: Column {
    id: field

    required property string label
    required property string description
    property string value: ""
    property string placeholder: ""

    signal committed(string text)

    width: parent ? parent.width : implicitWidth
    spacing: Style.space(4)

    Text {
      width: parent.width
      text: field.label
      textFormat: Text.PlainText
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }

    TextField {
      id: input
      width: parent.width
      text: field.value
      placeholderText: field.placeholder
      foreground: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      horizontalPadding: Style.spacing.controlGap

      // The field's own edits are what get committed, never the binding above
      // (which would fight the user on every keystroke).
      onAccepted: field.committed(text)
      onEditingFinished: field.committed(text)
    }

    Text {
      width: parent.width
      text: field.description
      textFormat: Text.PlainText
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }
  }
}
