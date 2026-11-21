# Weather + Rain Merge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Grow `io.github.neotyk.buienradar-rain` into one weather + rain widget laid out as design F.
**Architecture:** Pure data functions in `Model.js` (tested with `node test.js`); `Panel.qml` fetches the Buienradar feed, raintext and radar GIF and renders two columns; `BarWidget.qml` shows the pill.
**Tech Stack:** Quickshell QML, plain JS, curl.
**Spec:** `docs/superpowers/specs/2026-11-21-weather-merge-design.md`

## Global Constraints
- Data only from Buienradar: `https://data.buienradar.nl/2.0/feed/json` and raintext, every 5 min.
- English condition words; °C and km/h only.
- Radar GIF downloaded with curl to `$XDG_RUNTIME_DIR/buienradar-radar.gif`, never loaded by Qt from the network.
- Pill format: `<glyph> 8° · rain 16:15`; `<glyph> 8°` when no change within 2 hours.

## Review Focus
- Feed down or bad JSON: keep last good data, widget stays up (`parseFeed` returns null on bad input).
- Station missing a value (`feeltemperature` null): show `—`, not `NaN`.
- Night icon codes (`aa.png`): map by last letter, use night glyph for `a`.
- Fewer than 4 forecast days in the feed: show what exists.
- Radar download fails: map area stays empty, no crash.

---

### Task 1: Model functions

**Files:** Modify `Model.js`, `test.js`

**Interfaces (Produces):**
- `condition(iconUrl: string) -> { text: string, glyph: string }`
- `windText(ms: number, dir: string) -> string` e.g. `windText(4, "WZW") === "WSW 14 km/h"`
- `parseFeed(raw: string, lat: number, lon: number, todayIso: string) -> { now: {temp, feels, wind, humidity, text, glyph}, days: [{name, hi, lo, rain, glyph}] } | null`
  - `now` from nearest station (equirectangular distance), `days` = forecast entries after `todayIso`, max 3, `name` = 3-letter English weekday upper case.

- [ ] Tests: `condition(".../c.png").text === "Overcast"`; `condition(".../aa.png").glyph` is the night glyph; `windText(4,"WZW") === "WSW 14 km/h"`; `parseFeed` on a 2-station fixture picks the nearer one; null feels → `"—"`; `parseFeed("nope") === null`; days skip today and cap at 3.
- [ ] Run `node test.js` → fails. Implement. Run → `ok`. Commit.

### Task 2: Panel two-column layout + data

**Files:** Modify `Panel.qml`

- [ ] Add feed `Process` + 10-min `Timer`; keep last good `weather` on null.
- [ ] Radar: `sh -c 'curl … -o "$1.tmp" "$2" && mv "$1.tmp" "$1"'` on open; reload `AnimatedImage` from the local file.
- [ ] Layout: `Row` → left column 500 wide (now row, 3 days, rain text, graph), right column (map 526×500, source).
- [ ] Expose `label` = glyph + temp + pill.
- [ ] Verify live: open popup over IPC, screenshot. Commit.

### Task 3: Bar swap

- [ ] Remove `omarchy.weather` from the user's `shell.json` center section (backup first). Screenshot bar. Push.
