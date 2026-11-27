import QtQuick
import QtTest
import "../UptimeKit.js" as UptimeKit

TestCase {
  name: "UptimeKit"

  readonly property string summaryJson: JSON.stringify({
    page: { id: "p1", name: "Example", url: "https://status.example.com/" },
    status: "degraded",
    updatedAt: "2026-10-20T19:00:00.000Z",
    components: [
      { id: "a", name: "API", group: "Core", status: "up" },
      { id: "b", name: "Web", group: "Core", status: "degraded" },
      { id: "c", name: "Docs", group: "Site", status: "up" }
    ],
    incidents: [
      { id: "i1", title: "Slow API", status: "monitoring", severity: "major", componentIds: ["a"] }
    ],
    maintenances: [
      { id: "m1", title: "Database upgrade", status: "scheduled" }
    ]
  })

  // ---- URLs ---------------------------------------------------------------

  function test_summaryUrlRoot() {
    compare(UptimeKit.summaryUrl("https://status.example.com", ""),
      "https://status.example.com/summary.json")
  }

  function test_summaryUrlSlug() {
    compare(UptimeKit.summaryUrl("https://status.example.com", "api"),
      "https://status.example.com/api/summary.json")
    // Slashes typed as they appear in the URL join once, not twice.
    compare(UptimeKit.summaryUrl("https://status.example.com/", "/api/"),
      "https://status.example.com/api/summary.json")
  }

  function test_bareHostGetsHttps() {
    compare(UptimeKit.summaryUrl("status.example.com", ""),
      "https://status.example.com/summary.json")
    compare(UptimeKit.summaryUrl("http://plain.example.com", ""),
      "http://plain.example.com/summary.json")
  }

  function test_emptyBaseHasNoUrl() {
    compare(UptimeKit.summaryUrl("", "api"), "")
    compare(UptimeKit.summaryUrl("   ", ""), "")
    compare(UptimeKit.pageUrl("", ""), "")
  }

  function test_pageUrlDropsSummaryJson() {
    compare(UptimeKit.pageUrl("https://status.example.com", "api"),
      "https://status.example.com/api")
  }

  // ---- Parsing ------------------------------------------------------------

  function test_parseSummaryShapes() {
    var summary = UptimeKit.parseSummary(summaryJson)
    verify(summary !== null)
    compare(summary.page.name, "Example")
    compare(summary.status, "degraded")
    compare(summary.components.length, 3)
    compare(summary.components[1].status, "degraded")
    compare(summary.incidents.length, 1)
    compare(summary.incidents[0].severity, "major")
    compare(summary.incidents[0].componentIds[0], "a")
    compare(summary.maintenances[0].title, "Database upgrade")
  }

  function test_parseSummaryRejectsNonSummaries() {
    compare(UptimeKit.parseSummary(""), null)
    compare(UptimeKit.parseSummary("not json"), null)
    compare(UptimeKit.parseSummary("<html>404</html>"), null)
    compare(UptimeKit.parseSummary("[]"), null)
    compare(UptimeKit.parseSummary('{"status":"degraded"}'), null)
    compare(UptimeKit.parseSummary('{"components":[]}') !== null, true)
  }

  function test_parseSummaryDefaultsMissingLists() {
    var summary = UptimeKit.parseSummary('{"components":[{"name":"API","status":"up"}]}')
    compare(summary.incidents.length, 0)
    compare(summary.maintenances.length, 0)
    compare(summary.page.name, "")
    compare(summary.components[0].group, "")
  }

  function test_unknownStatusIsNotHealthy() {
    compare(UptimeKit.pageStatusOf("degraded"), "degraded")
    compare(UptimeKit.pageStatusOf("up"), "unknown")
    compare(UptimeKit.pageStatusOf(""), "unknown")
    compare(UptimeKit.pageStatusOf("operational"), "operational")

    compare(UptimeKit.componentStatusOf("up"), "up")
    compare(UptimeKit.componentStatusOf("operational"), "unknown")
    compare(UptimeKit.componentStatusOf("nonsense"), "unknown")
  }

  // ---- Rollup -------------------------------------------------------------

  function test_rollupCounts() {
    var counts = UptimeKit.rollup(UptimeKit.parseSummary(summaryJson))
    compare(counts.total, 3)
    compare(counts.up, 2)
    compare(counts.bad, 1)
    compare(counts.status, "degraded")
  }

  function test_rollupWithoutSummary() {
    var counts = UptimeKit.rollup(null)
    compare(counts.total, 0)
    compare(counts.status, "unknown")
  }

  function test_rollupUnknownPageFallsBackToComponents() {
    var allDown = UptimeKit.parseSummary(JSON.stringify({
      status: "unknown",
      components: [{ name: "A", status: "down" }, { name: "B", status: "down" }]
    }))
    compare(UptimeKit.rollup(allDown).status, "outage")

    // One healthy component means the page is merely unrated, not down.
    var mixed = UptimeKit.parseSummary(JSON.stringify({
      status: "unknown",
      components: [{ name: "A", status: "down" }, { name: "B", status: "up" }]
    }))
    compare(UptimeKit.rollup(mixed).status, "unknown")
  }

  function test_openIncidentOutranksOperational() {
    var summary = UptimeKit.parseSummary(JSON.stringify({
      status: "operational",
      components: [{ name: "A", status: "up" }],
      incidents: [{ title: "Investigating" }]
    }))
    compare(UptimeKit.rollup(summary).status, "degraded")
  }

  // ---- Grouping -----------------------------------------------------------

  function test_groupedComponentsKeepPageOrder() {
    var groups = UptimeKit.groupedComponents(UptimeKit.parseSummary(summaryJson))
    compare(groups.length, 2)
    compare(groups[0].name, "Core")
    compare(groups[0].components.length, 2)
    compare(groups[1].name, "Site")
  }

  function test_groupedComponentsMergeInterleavedGroups() {
    var summary = UptimeKit.parseSummary(JSON.stringify({
      components: [
        { name: "A", group: "Core", status: "up" },
        { name: "B", group: "Site", status: "up" },
        { name: "C", group: "Core", status: "up" }
      ]
    }))
    var groups = UptimeKit.groupedComponents(summary)
    compare(groups.length, 2)
    compare(groups[0].components.length, 2)
    compare(groups[0].components[1].name, "C")
  }

  // ---- Bar label modes ----------------------------------------------------

  function test_barLabelModes() {
    var summary = UptimeKit.parseSummary(summaryJson)
    compare(UptimeKit.barLabel(summary, "ratio"), "2/3")
    compare(UptimeKit.barLabel(summary, "percent"), "67%")
    compare(UptimeKit.barLabel(summary, "count"), "2")
    compare(UptimeKit.barLabel(summary, "status"), "")
  }

  function test_barLabelFullHealthIsHundredPercent() {
    var summary = UptimeKit.parseSummary(JSON.stringify({
      status: "operational",
      components: [{ name: "A", status: "up" }, { name: "B", status: "up" }]
    }))
    compare(UptimeKit.upPercent(summary), 100)
    compare(UptimeKit.barLabel(summary, "percent"), "100%")
  }

  function test_barLabelWithoutSummaryIsEmpty() {
    compare(UptimeKit.barLabel(null, "ratio"), "")
    compare(UptimeKit.barLabel(null, "percent"), "")
  }

  // A page with no components has no share to report; it must not claim 100%.
  function test_upPercentWithoutComponents() {
    var summary = UptimeKit.parseSummary('{"components":[]}')
    compare(UptimeKit.upPercent(summary), 0)
    compare(UptimeKit.rollup(summary).total, 0)
  }

  function test_labelModeFallsBack() {
    compare(UptimeKit.labelMode("percent"), "percent")
    compare(UptimeKit.labelMode("count"), "count")
    compare(UptimeKit.labelMode("status"), "status")
    compare(UptimeKit.labelMode("nonsense"), "ratio")
    compare(UptimeKit.labelMode(""), "ratio")
    compare(UptimeKit.labelMode(undefined), "ratio")
  }

  function test_labelFontPercentClamps() {
    compare(UptimeKit.labelFontPercent(100), 100)
    compare(UptimeKit.labelFontPercent(60), 60)
    compare(UptimeKit.labelFontPercent(140), 140)
    compare(UptimeKit.labelFontPercent(20), 60)
    compare(UptimeKit.labelFontPercent(400), 140)
    compare(UptimeKit.labelFontPercent("85"), 85)
    compare(UptimeKit.labelFontPercent(undefined), 100)
    compare(UptimeKit.labelFontPercent("abc"), 100)
  }

  // ---- Interval and age ---------------------------------------------------

  function test_pollSecondsClamps() {
    compare(UptimeKit.pollSeconds(30), 30)
    compare(UptimeKit.pollSeconds(1), 10)
    compare(UptimeKit.pollSeconds(99999), 3600)
    compare(UptimeKit.pollSeconds("45"), 45)
    compare(UptimeKit.pollSeconds(undefined), 30)
    compare(UptimeKit.pollSeconds("abc"), 30)
  }

  function test_ageSeconds() {
    var now = Date.parse("2026-10-20T19:00:30.000Z")
    compare(UptimeKit.ageSeconds("2026-10-20T19:00:00.000Z", now), 30)
    compare(UptimeKit.ageSeconds("", now), -1)
    compare(UptimeKit.ageSeconds("nonsense", now), -1)
    // A clock skew that puts the payload in the future reads as "now", not a
    // negative age.
    compare(UptimeKit.ageSeconds("2026-10-20T19:05:00.000Z", now), 0)
  }
}
