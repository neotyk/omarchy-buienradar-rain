# Buienradar Rain for Omarchy

An [Omarchy](https://omarchy.org/) bar widget that shows rain for the next 2 hours.
Data comes from [Buienradar](https://www.buienradar.nl), so it works in the Netherlands and Belgium only.

- **Bar:** a rain icon plus the next change, for example `dry 14:50` or `rain 16:15`. Only the icon shows when nothing changes within 2 hours.
- **Popup:** a summary, a rain graph in 5-minute steps, and the animated Buienradar radar map.
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
