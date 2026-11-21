.pragma library

// Buienradar raintext: one "vvv|HH:MM" line per 5 minutes, 2 hours ahead.
// vvv is 0-255; mm/h = 10^((vvv - 109) / 32), and 0 means dry.
function parseRainText(raw) {
  return String(raw || "").split(/\r?\n/).map(function (line) {
    var parts = line.trim().split("|")
    if (parts.length !== 2 || !/^\d+$/.test(parts[0])) return null
    var v = parseInt(parts[0], 10)
    return { time: parts[1].trim(), mm: v > 0 ? Math.pow(10, (v - 109) / 32) : 0 }
  }).filter(function (p) { return p !== null })
}

function intensity(mm) {
  if (mm >= 10) return "heavy"
  if (mm >= 2.5) return "moderate"
  return "light"
}

// Consecutive wet/dry stretches: [{ wet, start, end, peak }], end = index after the run.
function runs(points) {
  var out = []
  for (var i = 0; i < points.length; ++i) {
    var wet = points[i].mm > 0
    var last = out[out.length - 1]
    if (last && last.wet === wet) {
      last.end = i + 1
      last.peak = Math.max(last.peak, points[i].mm)
    } else {
      out.push({ wet: wet, start: i, end: i + 1, peak: points[i].mm })
    }
  }
  return out
}

// Title, sub line and bar pill text for the next 2 hours.
function summary(points) {
  if (!points || points.length === 0) return { title: "", sub: "", pill: "" }
  var r = runs(points)
  var first = r[0]
  if (r.length === 1)
    return first.wet
      ? { title: "Rain for the next 2 hours", sub: intensity(first.peak) + " rain until " + points[points.length - 1].time, pill: "" }
      : { title: "Dry for the next 2 hours", sub: "", pill: "" }

  var change = points[first.end].time
  var second = r[1]
  var title = first.wet ? "Rain stops at " + change : "Rain starts at " + change
  var pill = (first.wet ? "dry " : "rain ") + change
  var sub
  if (r.length === 2) {
    sub = second.wet ? intensity(second.peak) + " rain after that" : "Dry after that"
  } else {
    var back = points[second.end].time
    sub = second.wet
      ? capitalize(intensity(second.peak)) + " rain from " + change + " to " + back + ", then dry"
      : "Dry from " + change + " to " + back + ", then " + intensity(r[2].peak) + " rain again"
  }
  return { title: title, sub: capitalize(sub), pill: pill }
}

function capitalize(s) {
  return s ? s.charAt(0).toUpperCase() + s.slice(1) : s
}

if (typeof module !== "undefined") module.exports = { parseRainText: parseRainText, summary: summary, runs: runs }
