import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons as Commons

// The active theme's semantic palette, for the status colours the shell does
// not surface itself. Commons.Color exposes the shell's own roles (foreground,
// background, accent, urgent, muted); green, yellow and red live only in the
// theme's colors.toml, which is where the terminals, btop and the rest of the
// desktop read them from too.
//
// Watched, so a theme switch recolours the widget without a shell restart. A
// theme that ships no colors.toml falls back to the shell's own roles, which
// are already theme-derived.
QtObject {
  id: root

  readonly property string themePath: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/colors.toml"

  property var values: ({})
  readonly property color green: color("green", Commons.Color.accent)
  readonly property color yellow: color("yellow", Commons.Color.foreground)
  readonly property color red: color("red", Commons.Color.urgent)

  function color(key, fallback) {
    var value = values[key]
    return typeof value === "string" && value.length > 0 ? value : fallback
  }

  // Same shape the shell parses: `key = "#rrggbb"`, one per line, tolerating
  // quotes and inline comments.
  function parse(raw) {
    var result = {}
    var lines = String(raw || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var match = lines[i].match(/^\s*([A-Za-z0-9_-]+)\s*=\s*["']?(#[0-9A-Fa-f]{6,8})/)
      if (match) result[match[1]] = match[2]
    }
    return result
  }

  property FileView colorsFile: FileView {
    path: root.themePath
    watchChanges: true
    printErrors: false
    onLoaded: root.values = root.parse(text())
    onFileChanged: reload()
    onLoadFailed: root.values = ({})
  }
}
