.pragma library

// Pure helpers behind the UptimeKit widget: URL construction, summary.json
// parsing, and the roll-up the bar and the panel both read. No state, no QML
// objects, and no user-facing wording (the panel localizes its own labels), so
// every rule here is testable offscreen.
//
// summary.json is the public, keyless status summary documented at
// https://docs.uptimekit.dev/configuration/status_pages.md

// Page statuses, worst first. Anything broken outranks anything planned.
// Component statuses are a different vocabulary (up/down/degraded/...), so
// they are validated separately: "up" is not a page status and "operational"
// is not a component status.
var PAGE_STATUSES = ["outage", "degraded", "maintenance", "operational", "unknown"]
var COMPONENT_STATUSES = ["up", "down", "degraded", "maintenance", "pending"]

function trimSlashes(value) {
  return String(value || "").replace(/^\/+/, "").replace(/\/+$/, "")
}

// The base URL as the user typed it, less trailing slashes. A bare host gets
// https:// so "status.example.com" works without being spelled out.
function normalizeBaseUrl(value) {
  var text = String(value || "").trim()
  if (text === "") return ""
  text = text.replace(/\/+$/, "")
  if (!/^[a-zA-Z][a-zA-Z0-9+.-]*:\/\//.test(text)) text = "https://" + text
  return text
}

// A page slug may be typed with the slashes it has in the URL ("/api/") or as
// the bare segment. Either way it is joined once.
function normalizeSlug(value) {
  return trimSlashes(value)
}

function summaryUrl(baseUrl, slug) {
  var base = normalizeBaseUrl(baseUrl)
  if (base === "") return ""
  var path = normalizeSlug(slug)
  return base + (path === "" ? "" : "/" + encodeURI(path)) + "/summary.json"
}

function pageUrl(baseUrl, slug) {
  var base = normalizeBaseUrl(baseUrl)
  if (base === "") return ""
  var path = normalizeSlug(slug)
  return base + (path === "" ? "" : "/" + encodeURI(path))
}

// The JSON summary, or null when the payload is not one. A page with no
// components is still a page; a 404 body or an HTML error page is not.
function parseSummary(raw) {
  var parsed
  try {
    parsed = JSON.parse(String(raw || ""))
  } catch (e) {
    return null
  }
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return null
  if (!Array.isArray(parsed.components)) return null

  var components = []
  for (var i = 0; i < parsed.components.length; i++) {
    var component = parsed.components[i]
    if (!component || typeof component !== "object") continue
    components.push({
      id: String(component.id || ""),
      name: String(component.name || ""),
      group: String(component.group || ""),
      status: componentStatusOf(component.status)
    })
  }

  return {
    page: pageInfo(parsed.page),
    status: pageStatusOf(parsed.status),
    updatedAt: String(parsed.updatedAt || ""),
    components: components,
    incidents: entries(parsed.incidents, "incident"),
    maintenances: entries(parsed.maintenances, "maintenance")
  }
}

function pageInfo(page) {
  if (!page || typeof page !== "object") return { id: "", name: "", url: "" }
  return {
    id: String(page.id || ""),
    name: String(page.name || ""),
    url: String(page.url || "")
  }
}

// A documented page status, or "unknown" for anything else. A value this
// widget does not know must never read as healthy.
function pageStatusOf(value) {
  var status = String(value || "")
  return PAGE_STATUSES.indexOf(status) === -1 ? "unknown" : status
}

// A documented component status, or "unknown". The two vocabularies do not
// overlap, so a page status in a component slot is a server this widget does
// not understand rather than something to guess about.
function componentStatusOf(value) {
  var status = String(value || "")
  return COMPONENT_STATUSES.indexOf(status) === -1 ? "unknown" : status
}

function entries(list, kind) {
  var result = []
  if (!Array.isArray(list)) return result
  for (var i = 0; i < list.length; i++) {
    var entry = list[i]
    if (!entry || typeof entry !== "object") continue
    result.push({
      id: String(entry.id || ""),
      kind: kind,
      title: String(entry.title || ""),
      description: String(entry.description || ""),
      status: String(entry.status || ""),
      severity: String(entry.severity || ""),
      startAt: String(entry.startAt || ""),
      endAt: String(entry.endAt || ""),
      url: String(entry.url || ""),
      componentIds: Array.isArray(entry.componentIds) ? entry.componentIds.map(String) : []
    })
  }
  return result
}

// What the bar and the panel headline say. The page status is the server's
// own verdict and is preferred; components only fill in for a page that has
// no status yet, and an open incident outranks a page that still claims to be
// operational.
function rollup(summary) {
  if (!summary) return { total: 0, up: 0, bad: 0, status: "unknown" }

  var total = summary.components.length
  var bad = 0
  for (var i = 0; i < total; i++) {
    if (summary.components[i].status !== "up") bad++
  }

  var status = summary.status
  if (status === "unknown" && total > 0 && bad === total) status = "outage"
  if (summary.incidents.length > 0 && status === "operational") status = "degraded"

  return { total: total, up: total - bad, bad: bad, status: status }
}

// The glyph the bar shows for a status. Polling and transport failures are the
// widget's own states, not the server's, so the caller picks those itself.
function statusGlyph(status) {
  switch (status) {
    case "operational": return "\uF058"  // circled check
    case "degraded": return "\uF071"     // warning triangle
    case "outage": return "\uF057"       // circled cross
    case "maintenance": return "\uF013"  // gear
    default: return "\uF059"             // circled question
  }
}

// Components in page order, with each group's members kept together. A page
// that lists groups separately keeps its order; one that interleaves them
// still gets a single heading per group.
function groupedComponents(summary) {
  var groups = []
  if (!summary) return groups
  var index = {}
  for (var i = 0; i < summary.components.length; i++) {
    var component = summary.components[i]
    var name = component.group
    if (!index[name]) {
      index[name] = { name: name, components: [] }
      groups.push(index[name])
    }
    index[name].components.push(component)
  }
  return groups
}

// The share of components that are up, as a 0-100 percentage. A page with no
// components has nothing to be a percentage of, so it reports 0 rather than
// claiming a healthy 100.
function upPercent(summary) {
  var counts = rollup(summary)
  if (counts.total === 0) return 0
  return Math.round(counts.up / counts.total * 100)
}

// The bar label for a display mode. Modes are validated here, not in QML, so a
// hand-edited shell.json cannot produce a blank bar:
//
//   ratio   "15/15"      up count out of the total
//   percent "100%"       share of components that are up
//   count   "15"         the up count alone
//   status  ""           glyph only, colour carries the reading
//
// Every mode still shows the coloured glyph beside it; `status` is the one
// that drops the number entirely.
function barLabel(summary, mode) {
  if (!summary) return ""
  var counts = rollup(summary)
  switch (mode) {
    case "percent": return upPercent(summary) + "%"
    case "count": return String(counts.up)
    case "status": return ""
    default: return counts.up + "/" + counts.total
  }
}

// A documented label mode, or the ratio default. An unknown value from a
// hand-edited shell.json falls back rather than blanking the bar.
var LABEL_MODES = ["ratio", "percent", "count", "status"]

function labelMode(value) {
  var mode = String(value || "")
  return LABEL_MODES.indexOf(mode) === -1 ? "ratio" : mode
}

// The label size as a percentage of the bar's icon font, clamped to a range
// that stays legible and never outgrows the bar.
function labelFontPercent(value) {
  var percent = Math.round(Number(value))
  if (!isFinite(percent)) return 100
  return Math.max(60, Math.min(140, percent))
}

// The refresh interval the widget actually polls at, clamped to the range the
// manifest advertises so a hand-edited shell.json cannot hammer a server.
function pollSeconds(value) {
  var seconds = Math.round(Number(value))
  if (!isFinite(seconds)) return 30
  return Math.max(10, Math.min(3600, seconds))
}

// The whole seconds since an ISO timestamp, or -1 when it does not parse. The
// panel turns this into a localized "2m ago".
function ageSeconds(updatedAt, nowMs) {
  var then = Date.parse(String(updatedAt || ""))
  if (!isFinite(then)) return -1
  return Math.max(0, Math.floor((Number(nowMs) - then) / 1000))
}
