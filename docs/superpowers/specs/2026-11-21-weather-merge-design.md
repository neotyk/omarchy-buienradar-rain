# Weather + rain in one widget (design F)

## Why
The user wants one weather item in the bar. The standard `omarchy.weather` widget has a nice
"now" row and useful data. Our `buienradar.rain` widget has the rain graph and radar map.
Merge them by growing our widget, so we keep one small plugin and no fork of Omarchy code.

## Goals
- Bar pill: condition icon, temperature, next rain change. Example: `8° · rain 16:15`.
- Popup, two columns (design F on the canvas):
  - Left: "now" row (icon, temperature, place, condition, FEELS, WIND, HUMID),
    next 3 days (icon, high/low, rain chance), rain title + sub line, 2-hour rain graph.
  - Right: animated radar map, 526 × 500, and the source credit.
- Remove `omarchy.weather` from the user's bar after the new widget works.

## Non-goals
- Location search in the popup. Location stays in `shell.json` (latitude, longitude, place).
- Weather outside the Netherlands and Belgium.
- Hourly forecast, sunrise/sunset, unit switching (°C and km/h only).

## Anti-goals
- A bar crash. The widget must not take the shell down.

## Approaches
1. **Grow our widget, all data from Buienradar** (picked by the user). One source, about 150 more lines.
2. Clone `omarchy.weather` and add rain to it. Rejected: about 900 lines of Omarchy code to
   maintain, and the clone misses Omarchy's fixes.

## Data (my calls)
- Now and days: `https://data.buienradar.nl/2.0/feed/json` (35 KB), every 10 minutes.
  - "Now" comes from the station nearest to the set latitude/longitude.
  - Days: `forecast.fivedayforecast`, skipping today, first 3 entries.
- Rain: `raintext` as today, every 5 minutes.
- Condition text and icon: map Buienradar's icon letter (`a`…`w` in `iconurl`) to an English
  word and a Nerd Font weather glyph. Buienradar's own text is Dutch, so we don't use it.
- Wind: m/s → km/h. Direction letters translated (Z→S, O→E), for example `WZW` → `WSW`.
- Radar map: download the GIF with `curl` to `$XDG_RUNTIME_DIR` and show the local file.
  This replaces Qt's own network loading, the main suspect in the 14:55 crash.

## Left to the builder
- Exact spacing and font sizes, using Omarchy's `Style` values like the standard widget.
- Unit tests for the new pure functions in `Model.js` (nearest station, icon map, wind).
