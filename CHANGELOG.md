# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [0.7.0] - 2026-09-17

Hardening release: no new user-visible features besides two settings — the
goal is making v1.0 safe to test and maintain.

### Added
- `OMARCHY_APPSIGNAL_DRY_RUN=1` (or the flag file
  `~/.local/state/omarchy/appsignal/dry-run`) puts every action that would
  otherwise run a real shell command (agent prompt, browser) through a
  single `runAction()` that only logs the command instead of executing it.
  The panel's hero shows "DRY RUN" next to "UPDATED …" while active, so a
  tester can confirm it before pressing Enter/`o` on a row. The flag file is
  re-checked on every panel open (a `FileView` only reliably reacts to
  *content* changes on a file that already existed when it started
  watching, not to the file appearing or disappearing later).
- `sections` setting: which sections are visible and in what order
  (`alerts,errors,performance,servers,uptime,jobs,checkins,deploy` by
  default). The row cursor and the panel layout both walk the same ordered
  list, and the collector skips the phase 2 metrics request entirely for
  any of performance/servers/jobs that are turned off.
- `appOrder` setting (`attention` | `name` | `pinned`): order of the app
  tab row. `pinned` keeps the order AppSignal itself returns, unsorted.
- Collector: `APPSIGNAL_FIXTURE_DIR` fixture mode for tests — replaces
  every `curl` call with a read from a canned JSON fixture, no network, no
  real token.
- `tests/`: `run.sh` + one `*-test.sh` per case, fixtures under
  `tests/fixtures/<scenario>/`, anonymized (app names, org, viewer, host and
  ids are all synthetic). Covers: no token, HTTP 401, a GraphQL validation
  error and its retry without the `#opt` blocks, the full happy-path
  overview shape, one app's phase 2 request failing without taking the rest
  down, impact ranking (web/background, with the row cutoff), host metrics
  with no memory total (`memPct` null + `memUsedMb`), job queues (MEAN/MIN,
  `scheduled`, `failed`, `ignoreQueues`), the phase 2 fallback when no app
  is pinned, and `sections` skipping requests. `tests/run.sh` puts a stub
  `curl` that fails loudly first on `PATH`, and also passes under
  `unshare -rn` (no network namespace at all).
- CI on GitHub Actions (`.github/workflows/ci.yml`): validates
  `manifest.json`, runs `shellcheck` on the collector and every test file,
  and runs `tests/run.sh`, on push and PR to `dev` and `main`.
- `CHANGELOG.md` (this file).

### Fixed
- The collector's own `-sections` parsing: an empty or malformed value fell
  through to "request nothing" instead of the intended "request everything"
  fallback.

## [0.6.0] - 2026-09-17

### Added
- **JOBS** section: one row per background queue (ActiveJob), with
  processed/failed counts and queue wait time. Wait is reported as
  MEAN aggregated with MIN (the quietest minute in the window) rather than
  a plain average, so a queue that mixes "run now" jobs with jobs
  deliberately scheduled for later isn't dragged into days by the
  scheduled ones; such a queue is instead flagged `scheduled` and never
  warns on wait time alone. A queue with any failed job always warns.
  `ignoreQueues` setting drops named queues entirely.
- **CHECK-INS** section: one row per check-in trigger (cron/heartbeat),
  MISSED/LATE/UNEXPECTED flagged as failing. Always opens in the browser,
  never the agent.
- **ALERTS** section: open (OPEN/WARMUP) anomaly-detection triggers, above
  every other section — the most urgent thing an app can be showing.
- Collector: the two newest GraphQL blocks (`checkIns`, `alerts`) are
  marked `#opt` and retried without them on a GraphQL validation error, so
  a schema change on AppSignal's side degrades to "no check-ins, no
  alerts" instead of taking down the whole overview.

### Fixed
- A queue whose every job in the window was scheduled for later no longer
  reads as a permanent backlog (the `mailers` false positive).

## [0.5.0] - 2026-09-17

### Added
- **SERVERS** section: one row per host (CPU %, memory, load average,
  fullest disk mountpoint, swap when in use), colored by warn thresholds
  (`cpuWarn`/`memWarn`/`diskWarn` settings). Real hosts never publish a
  memory or swap *total* metric, so `memPct`/`swapPct` fall back to null
  and the row shows the absolute `memUsedMb`/`swapUsedMb` instead.
- PERFORMANCE: slow actions are now ranked by impact (`totalMs = meanMs ×
  count`) instead of by mean duration alone, split into WEB and BACKGROUND
  lists — a rarely-run 59-second job and a 5ms action that runs 100k times
  both looked "slow" under a mean-only sort, but only one of them matters.

## [0.4.0] - 2026-09-17

### Added
- PERFORMANCE section: open performance incidents, or — since AppSignal
  auto-closes those almost immediately — the slowest actions over the last
  24h when none are open.
- Health line under each app header: throughput, error rate and mean
  duration over the last hour.
- Deploy line at the foot of each app: revision, who, how long it's been
  live, and errors since.
- ROADMAP.md: versions and rules through v1.0 (branches, roles per
  version, testing safety, the smoke-test checklist).

### Fixed
- Cursor scroll past the last row, and the error-rate figure (AppSignal
  reports it already as a percentage, not a 0–1 fraction).

## [0.3.0] - 2026-09-16

### Added
- Horizontally-scrolling row of app tabs, apps with something wrong first.
- `onlyPinned` setting: show only the apps pinned in AppSignal (falls back
  to every app when none is pinned).

## [0.2.0] - 2026-09-16

### Added
- `incidentAction` setting: Enter/left click on an error row sends it to
  the coding agent with a ready-made investigation prompt by default
  (`browser` restores the v0.1 behavior of just opening AppSignal).
- SPEC.md: the rule against ever simulating keys/clicks to test the agent
  action against real production data — a dry-run substitute for that came
  later, in v0.7.

## [0.1.0] - 2026-09-15

### Added
- First working version: one bar icon with an alert dot (open errors or a
  monitor down), a panel listing every app the token can see (apps with
  something wrong first), open exception incidents and uptime monitors per
  app, full keyboard navigation (j/k, Enter, r, Esc), and the no-token
  setup notice.
- README, MIT license, first screenshots.

<!--
No per-version tags exist yet — per ROADMAP.md, this project tags releases
only once, at v1.0.0 (the single dev -> main merge). Once that happens,
these entries can gain compare links the usual Keep a Changelog way.
-->
