# Buienradar Rain for Omarchy

An [Omarchy](https://omarchy.org/) bar widget for weather and rain. It replaces the standard `omarchy.weather` widget.
Data comes from [Buienradar](https://www.buienradar.nl), so it works in the Netherlands and Belgium only.

- **Bar:** condition icon, temperature and the next rain change, for example `8° · rain 16:15`.
- **Popup, left:** weather now (feels like, wind, humidity), the next 3 days with rain chance, a rain summary, and a 2-hour rain graph.
- **Popup, right:** the animated Buienradar radar map.
- **Mouse:** left click opens the popup. Middle click refreshes.

## Install

```bash
git clone https://github.com/neotyk/omarchy-buienradar-rain ~/.config/omarchy/plugins/buienradar.rain
omarchy-shell shell rescanPlugins
omarchy bar put buienradar.rain --after omarchy.weather
omarchy bar set buienradar.rain latitude 52.37 --json
omarchy bar set buienradar.rain longitude 4.89 --json
omarchy bar set buienradar.rain place Amsterdam
```

`place` is only the label in the popup. Without a location, the widget uses Amsterdam.

## Test

```bash
node test.js
```

## Source

Rain data and radar images © Buienradar / RTL, used under the
[Buienradar feed terms](https://www.buienradar.nl), which require a credit to buienradar.nl.
