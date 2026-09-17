<h1 align="center">
  <br>
  󰐰 AppSignal for Omarchy
  <br>
</h1>

<p align="center">
  Your <a href="https://appsignal.com">AppSignal</a> apps, open errors and uptime monitors, one click away in the
  <a href="https://omarchy.org">Omarchy</a> bar.
</p>

<p align="center">
  <a href="LICENSE"><img alt="MIT license" src="https://img.shields.io/badge/license-MIT-50f872.svg?style=flat-square"></a>
  <img alt="Omarchy 4.x" src="https://img.shields.io/badge/omarchy-4.x-1a1b26.svg?style=flat-square">
  <img alt="No build step" src="https://img.shields.io/badge/build-none-lightgrey.svg?style=flat-square">
</p>

<p align="center">
  <img src="preview.png" alt="The AppSignal panel listing open exception incidents per app" width="560">
</p>

<p align="center">
  <img src="bar.png" alt="The bar icon with its alert dot" width="620">
</p>

## What you get

- **One icon in the bar.** A dot appears on it whenever anything needs attention — an open alert, an open error, an uptime monitor down, a failing check-in or a host running hot — across the apps the panel is showing. No numbers, no noise. Hover it for a one-line summary of what's wrong (e.g. "3 errors · 1 alert · 1 host hot").
- **A row of app tabs.** A slidable row of every app your token can see, apps with trouble sorted first and marked with a dot. Only the selected app's details show below it.
- **Only your favorites, if you have any.** Pin apps in AppSignal and the row shows just those; if nothing is pinned, it shows everything and says so.
- **Alerts.** Open (or warming up) anomaly-detection triggers, the most urgent thing an app can show — trigger name, metric, last/peak value and how long it has been open. Click one and it opens in AppSignal.
- **Open errors.** The latest open exception incidents for the selected app: exception class, action, occurrence count and age. Click one and it opens in AppSignal.
- **Health at a glance.** A line under the app header with the last hour's throughput, error rate and mean response time — shown for pinned apps (the ones the collector fetches metrics for); omitted when there is nothing to show.
- **Performance.** Open performance incidents when AppSignal has any (rare, it auto-closes them); otherwise the 24h slowest actions **ranked by impact** (mean duration × request count), split into WEB and BACKGROUND, each row showing mean, request count and the humanized daily total (e.g. "36 min/day").
- **Servers.** One row per host reporting metrics for the app: CPU, memory, load average, the fullest disk, and swap when the host is actually swapping — each figure turning urgent-colored past its warn threshold. Memory shows a percentage when the host publishes a memory total, and the absolute figure ("MEM 1.1 GB") when it does not, which is the usual case on container hosts.
- **Uptime monitors.** Each monitor with its up/down state and, when down, since when. Click to open it.
- **Jobs.** One row per background queue (ActiveJob): jobs processed in the last hour, mean queue wait time (turning urgent past its warn threshold), and failed jobs if any.
- **Check-ins.** One row per cron/heartbeat check-in trigger: its kind and last state — "OK · 2h ago" or "MISSED · 5h ago" — always opens the browser.
- **Last deploy.** A line at the foot of the app with the revision, who deployed it, how long it has been live, and errors since — when AppSignal has a real deploy marker for that app.
- **Keyboard first.** `j`/`k` walk the rows, `h`/`l` (or `←`/`→`) switch apps, `1`-`9` jump to an app, `Enter` opens, `r` refreshes, `g`/`G` jump, `Esc` closes.
- **Honest about staleness.** If AppSignal is unreachable the last good data stays on screen, marked `STALE`.
- **Nothing to build.** Bash, `curl` and `jq` collect; QML paints. Clone it and it runs.

## Install

```bash
omarchy plugin add https://github.com/memouranga/omarchy-appsignal.git --enable --yes
```

Then give it a token. Create a **personal API key** on your
[AppSignal personal settings](https://appsignal.com/users/edit) page and save it:

```bash
mkdir -p ~/.config/appsignal
echo 'YOUR-PERSONAL-API-KEY' > ~/.config/appsignal/api_token
chmod 600 ~/.config/appsignal/api_token
```

The panel picks it up on the next refresh (or right-click the icon). The token is read from, in order:
`$APPSIGNAL_API_TOKEN`, the file named by `$APPSIGNAL_TOKEN_FILE`, then `~/.config/appsignal/api_token`.
It never goes into `shell.json`.

## Use it

| Action | Result |
|---|---|
| Left click on the bar icon | Toggle the panel |
| Right click on the bar icon | Refresh now |
| Middle click on the bar icon | Select the next app (works even with the panel closed) |
| `h` / `l` or `←` / `→` (apps row focused) | Previous / next app |
| `1`-`9` | Jump to app N in the row |
| Click an app tab, or `Enter` with the apps row focused | Open the app in the browser |
| `j` / `k` | Switch focus between the apps row and the alert/error/performance/server/monitor/job/check-in rows, then walk them |
| `Enter` or left click on an alert row | Investigate with your coding agent (or open the browser, see `incidentAction` below) |
| Right click on an alert row, or `o` | Open the app in the browser |
| `Enter` or left click on an error row | Investigate with your coding agent (or open the browser, see `incidentAction` below) |
| Right click on an error row, or `o` | Open the incident in the browser |
| `Enter` or left click on a performance row | Investigate with your coding agent (or open the browser, see `incidentAction` below) |
| Right click on a performance row, or `o` | Open it in the browser |
| `Enter` or left click on a server row | Investigate the host with your coding agent (or open the browser, see `incidentAction` below) |
| Right click on a server row, or `o` | Open the app in the browser |
| `Enter` or click on a monitor row | Open the monitor in the browser (always) |
| `Enter` or left click on a job row | Investigate the queue with your coding agent (or open the browser, see `incidentAction` below) |
| Right click on a job row, or `o` | Open the app in the browser |
| `Enter` or click on a check-in row | Open the check-in in the browser (always) |
| `g` / `G` | First / last row |
| `r` | Refresh now |
| `Tab` | Neighbouring bar panel |
| `Esc` | Close |

The `incidentAction` setting controls what `Enter`/left click do on an **alert**, **error**,
**performance**, **server** or **job** row: `"agent"` (the default) hands it to your coding agent,
`"browser"` opens it on appsignal.com like uptime monitors and check-ins always do. Right click and
`o` always mean "open in the browser", whatever the setting. For a server, job or alert row that means
the app's page — the exact per-host, per-queue and per-trigger URLs could not be confirmed without an
authenticated browser session (see `SPEC.md` "v0.5" and "v0.6").

Only the selected app's errors and monitors are shown. Your selection is remembered across panel
opens (`~/.local/state/omarchy/appsignal/panel.json`); if the saved app is gone, the first one in
the row is picked instead.

Bind it to a key in `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + CTRL + A", "AppSignal", "omarchy-shell memong.appsignal toggle")
```

`toggle`, `open`, `close` and `refresh` are all available over IPC.

## Remove

```bash
omarchy plugin remove memong.appsignal
rm -rf ~/.config/appsignal            # only if you want the token gone too
```

The plugin writes nothing else: its only state is `~/.local/state/omarchy/appsignal/overview.json`.

## Settings

Set them on the widget entry in `~/.config/omarchy/shell.json`:

```json
{ "id": "memong.appsignal", "refreshIntervalSec": 120, "incidentsPerApp": 5 }
```

| Key | Default | What it does |
|---|---|---|
| `refreshIntervalSec` | `120` | Seconds between collector runs (min 30) |
| `incidentsPerApp` | `5` | Open error rows shown per app (also caps performance and job rows) |
| `incidentAction` | `agent` | What `Enter`/left click do on an alert, error, performance, server or job row: `agent` or `browser` |
| `onlyPinned` | `pinned` | `pinned` shows only the apps you pinned in AppSignal (if you've pinned any); `all` always shows every app |
| `cpuWarn` | `80` | Host CPU % at or above which a server row's CPU figure (and its warn dot) turns urgent |
| `memWarn` | `85` | Same, for host memory % — only applies when AppSignal reports a usable memory total for the host; a host that only reports megabytes used shows them, and never warns on them (see `SPEC.md` "v0.5") |
| `diskWarn` | `85` | Same, for the fullest disk mountpoint's % |
| `queueTimeWarn` | `30000` | Job queue mean wait time, in milliseconds, at or above which a job row's wait figure turns urgent |

### Pinning apps in AppSignal

The app row shows only your pinned apps by default. To pin one, open it on
[appsignal.com](https://appsignal.com), find it in the apps list (or its own page), and click the
pin/star icon next to its name. With nothing pinned, the row falls back to showing every app and the
panel says so ("Pin apps in AppSignal to show only those here").

## Investigate with your coding agent

With `incidentAction` set to `agent` (the default), opening an error row runs
`omarchy agent prompt "<prompt>"` — the same mechanism behind `omarchy agent crash`. It opens a
terminal with **your default coding agent** (whatever `omarchy default agent` is set to) and hands
it a one-line prompt built from the incident: app, environment, exception, namespace, action,
occurrence count, last-seen time, message and URL. The agent is asked to use the AppSignal MCP to
read the incident, its stack trace and recent samples, explain the probable root cause, and propose
a fix — it is explicitly told not to change the incident's state or severity unless you ask. Opening
a performance row works the same way, with a prompt built from an open performance incident or a
24h slowest action instead; a server row asks it to analyze the host's CPU/memory/load/disk/swap; an
alert row asks it to investigate the open anomaly-detection trigger; a job row asks it to look at
that background queue's throughput, wait time and slowest jobs. Every prompt explicitly tells the
agent not to change anything in AppSignal unless you ask. The plugin itself never mutates anything
there; only the agent does, and only in that session, if you tell it to.

Run `omarchy default agent` to see or change which agent that is.

This only works well once your agent can reach AppSignal's data, so connect the
[AppSignal MCP server](https://docs.appsignal.com/mcp-server) first. For Claude Code:

```bash
claude mcp add --transport http appsignal https://appsignal.com/api/mcp \
  --header "Authorization: Bearer <YOUR_MCP_TOKEN>"
```

The `<YOUR_MCP_TOKEN>` is an AppSignal **MCP token** (not the personal API key above), created from
your AppSignal profile under **Account Settings → MCP Tokens**. Give it **read** permissions only —
this plugin and the prompt it sends only need to read incidents, traces and samples, never to change
them. See [docs.appsignal.com/mcp-server](https://docs.appsignal.com/mcp-server) for setup with other
agents and for OAuth as an alternative to a Bearer token.

## Requirements and trust

- **Dependencies:** `curl` and `jq`, both present on a stock Omarchy install. Nothing is compiled, installed or fetched at runtime.
- **Network:** one HTTPS request to `appsignal.com` per refresh. Your token travels only there, as the query parameter AppSignal's API requires.
- **Privileges:** runs unsandboxed inside the Omarchy shell as your user, like every plugin. It reads your token file, writes one state file, and opens URLs with `omarchy launch browser`. It never asks for elevated privileges and installs no services or background daemons.
- **Read only:** the token grants read access to your AppSignal account. The plugin never mutates anything there.

## How it works

```
manifest.json           declares the bar widget
bin/appsignal-collect   bash + curl + jq: one GraphQL request, writes
                        ~/.local/state/omarchy/appsignal/overview.json
Main.qml                runs the collector on a timer, watches the file
Panel.qml               the bar icon and the panel
```

The collector runs in two phases. First, one GraphQL request asks the
[AppSignal GraphQL API](https://docs.appsignal.com/api/graphql) for every organization and app, their
open exception and performance incidents, uptime monitors with alerts, check-in triggers, open
anomaly-detection alerts and the last deploy marker. A monitor counts as down when it carries an
alert in `OPEN` or `WARMUP` state; the same two states are what makes an anomaly-detection alert show
up in the ALERTS section (`App.alerts` has no server-side state filter, so this is filtered client-side).

Second, for apps pinned in AppSignal only (or, with nothing pinned, the first 6 apps — to keep the
request count bounded), five read-only requests to the
[metrics API](https://docs.appsignal.com/api/v2/metrics.md) fetch: the last hour's health (throughput,
error rate, mean duration); the 24h slowest actions, ranked by impact (mean × count) and split into
web/background; the last 15 minutes of host metrics (CPU, memory, swap, load, disk — two requests,
since CPU/memory/swap and disk usage need different tag groupings); and the last hour's job queues
(jobs processed, failed, and mean queue wait time per background queue). This phase runs in parallel
per app with its own timeout; if any of these fail for an app, that app's health line, performance,
servers or jobs section is simply empty — the rest of the overview is unaffected. The exact queries,
and how each host percentage and job-queue figure is derived, are documented in `SPEC.md` ("v0.4",
"v0.5" and "v0.6").

## Roadmap

- `v0.7`: settings for which sections show and their order, a dry-run mode for agent actions, tests,
  CI, and full keyboard accessibility — see `ROADMAP.md`.

## Contributing

Issues and pull requests welcome. Validate before you push:

```bash
omarchy plugin validate .
```

## License

[MIT](LICENSE) © 2026 Memo Uranga
