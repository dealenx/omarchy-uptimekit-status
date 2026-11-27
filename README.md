# UptimeKit status for Omarchy

Your [UptimeKit](https://docs.uptimekit.dev/configuration/status_pages/) status
page in the Omarchy bar: components, incidents and maintenance, read from the
public `summary.json`. No API key, no configuration beyond the page URL.

`✓ 15/15` — a status glyph and a reading of the same numbers, in the theme's
own palette: green when everything is up, yellow for degraded or maintenance,
red for an outage, grey while there is no reading yet. The reading is
configurable: `15/15`, `100%`, `15`, or the coloured glyph alone.

- **Left click** — details panel
- **Right click** — open the status page in the browser
- **Middle click** — refresh now

The panel shows the page's own verdict, the updated time, open incidents, the
maintenance windows, and every component grouped as the page groups them. A
failed refresh keeps the last good data and says so, rather than claiming
everything is down.

## Install

```sh
omarchy plugin add https://github.com/dealenx/omarchy-uptimekit-status.git --enable
```

Then point it at your page, either in the panel (gear icon) or from the shell:

```sh
omarchy bar set dealenx.uptimekit-status baseUrl '"https://status.example.com"'
omarchy bar set dealenx.uptimekit-status slug api
omarchy bar set dealenx.uptimekit-status labelMode percent
```

## Settings

The panel's settings screen (gear icon, top right of the card) edits the same
values that live in `~/.config/omarchy/shell.json`:

| Key | Default | Meaning |
|---|---|---|
| `baseUrl` | *(empty)* | Status page base URL, e.g. `https://status.example.com`. Empty stops polling. |
| `slug` | *(empty)* | The `/<slug>` part of the page URL. Empty means the domain root. |
| `intervalSeconds` | `30` | Poll interval in seconds (10–3600). |
| `labelMode` | `ratio` | What the bar shows: `ratio` (`15/15`), `percent` (`100%`), `count` (`15`), or `status` (glyph only). |
| `labelFontPercent` | `100` | Label size as a percentage of the bar's own label size (60–140). |
| `openUrlOnRightClick` | `true` | Right click opens the page in the browser. |

`baseUrl` may be typed without a scheme (`status.example.com` becomes
`https://status.example.com`) and the slug with or without its slashes
(`/api/` and `api` are the same page).

## IPC

```sh
omarchy-shell dealenx.uptimekit-status status     # JSON state for scripts
omarchy-shell dealenx.uptimekit-status refresh
omarchy-shell dealenx.uptimekit-status settings   # open the panel on settings
omarchy-shell shell summon dealenx.uptimekit-status
omarchy-shell shell hide dealenx.uptimekit-status
```

## How it works

`BarWidget.qml` owns the bar button and the data model; `Panel.qml` is the
card, loaded by the widget and handed its data, as the Omarchy plugin contract
expects (`open`/`close`/`opened` are forwarded from the bar entry point).

`Summary.qml` polls `<base>[/<slug>]/summary.json` with `curl`: `-f` turns a
404 from a password-protected page into a failure, `--max-filesize` caps a
misbehaving server, and `--max-time` keeps a hung connection from pinning the
widget. Data is only replaced by a payload that parses, so a failed poll leaves
the last known state on the bar with the failure noted in the panel.

Status colours come from the active theme's `colors.toml` (`green`, `yellow`,
`red`), so a light theme gets tones that are readable on it rather than fixed
bright ones. `ThemePalette.qml` watches that file, so switching themes recolours
the widget without a shell restart.

`UptimeKit.js` holds the pure logic (URL building, payload parsing, the
status roll-up, grouping, interval clamping) and is tested offscreen.

## Validation

```sh
omarchy plugin validate .
qmllint -I "$OMARCHY_PATH/shell" BarWidget.qml Panel.qml Summary.qml ThemePalette.qml
QT_QPA_PLATFORM=offscreen /usr/lib/qt6/bin/qmltestrunner -input tests
```

## Remove

```sh
omarchy plugin remove dealenx.uptimekit-status
```

## License

MIT. Copyright (c) 2026 Daniil Gorodilov.

A port of [uptimekit-status-noctalia](https://github.com/dealenx/uptimekit-status-noctalia)
to the Omarchy bar.
