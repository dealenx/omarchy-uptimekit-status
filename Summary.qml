import QtQuick
import Quickshell.Io
import "UptimeKit.js" as UptimeKit

// Polls the public summary.json and keeps the last good answer.
//
// One instance is shared by the bar widget and its panel: the widget owns it,
// the panel renders what it is handed, so opening the panel never starts a
// second poller against the same server.
//
// A failed poll keeps the previous data and reports the failure beside it. A
// status page that is briefly unreachable is not a status page that says
// everything is down, and the bar must not claim the latter.
Item {
  id: root

  // Not `enabled`: that is Item's own property, and a widget that is disabled
  // by its parent must still be able to say why it is idle.
  property bool polling: true
  property string baseUrl: ""
  property string slug: ""
  property int intervalSeconds: 30
  // Bumped to force a poll now (middle click, panel refresh, IPC).
  property int requestRevision: 0

  readonly property string sourceUrl: UptimeKit.summaryUrl(baseUrl, slug)
  readonly property bool configured: sourceUrl !== ""
  readonly property bool loading: fetch.running
  // The last payload that parsed, kept across a failed poll so the bar keeps
  // showing the last known state instead of flapping to an error.
  readonly property var summary: lastGood
  readonly property bool failed: lastError !== ""
  readonly property string errorText: lastError

  property var lastGood: null
  property string lastError: ""
  property string attemptedUrl: ""

  // Set by the two signals a fetch produces, in whichever order they arrive,
  // so the answer is only judged once both the body and the exit code exist.
  property bool exited: false
  property int exitCode: 0
  property bool streamed: false
  property string body: ""
  property string stderrText: ""

  onSourceUrlChanged: restart()
  onIntervalSecondsChanged: restart()
  onPollingChanged: restart()
  onRequestRevisionChanged: if (polling) poll()
  onConfiguredChanged: if (!configured) clear()

  function clear() {
    lastGood = null
    lastError = ""
  }

  function restart() {
    refreshTimer.stop()
    fetch.running = false
    if (!polling) return
    if (!configured) {
      clear()
      return
    }
    refreshTimer.start()
    poll()
  }

  function poll() {
    if (!polling || !configured || fetch.running) return
    fetch.command = ["curl", "-fsS", "--max-time", "10", "--max-filesize", "1048576",
      "-H", "Accept: application/json", sourceUrl]
    // A poll answered for a URL the user has since replaced must not land on
    // the new page's data.
    attemptedUrl = sourceUrl
    exited = false
    streamed = false
    body = ""
    stderrText = ""
    fetch.running = true
  }

  // Called from both fetch signals; only the second one to arrive acts.
  function settleIfReady() {
    if (!exited || !streamed) return
    if (attemptedUrl !== sourceUrl) return

    var parsed = exitCode !== 0 ? null : UptimeKit.parseSummary(body)
    if (exitCode !== 0) {
      var detail = String(stderrText || "").trim().split("\n")[0]
      fail(detail !== "" ? detail : "curl exited " + exitCode)
      return
    }
    if (!parsed) {
      fail("unexpected payload")
      return
    }

    lastError = ""
    lastGood = parsed
  }

  function fail(reason) {
    console.debug("[uptimekit-status] poll failed:", reason, attemptedUrl)
    lastError = reason
  }

  Timer {
    id: refreshTimer
    interval: Math.max(1, UptimeKit.pollSeconds(root.intervalSeconds)) * 1000
    repeat: true
    onTriggered: root.poll()
  }

  // curl rather than a QML HTTP type: this shell ships no HTTP request type,
  // and its own plugins shell out for network work too. -f turns a 404 (a
  // password-protected page) into a failure instead of an HTML body,
  // --max-filesize caps a hostile or misconfigured server, and --max-time
  // keeps a hung connection from pinning the widget forever.
  //
  // The argv is built when the process starts rather than bound to
  // `sourceUrl`: a binding is re-evaluated on the next event loop turn, and
  // `running = true` takes the command as it stands right now, which launched
  // the previous URL (and an empty one for the first poll).
  Process {
    id: fetch

    onExited: function(code) {
      root.exitCode = code
      root.exited = true
      root.settleIfReady()
    }

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.body = text
        root.streamed = true
        root.settleIfReady()
      }
    }

    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.stderrText = text
    }
  }
}
