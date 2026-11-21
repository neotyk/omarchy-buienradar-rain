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

// Consecutive wet/dry stretches: [{ wet, end, peak }], end = index after the run.
// Under 0.1 mm/h is sensor noise, not rain.
function runs(points) {
  var out = []
  for (var i = 0; i < points.length; ++i) {
    var wet = points[i].mm >= 0.1
    var last = out[out.length - 1]
    if (last && last.wet === wet) {
      last.end = i + 1
      last.peak = Math.max(last.peak, points[i].mm)
    } else {
      out.push({ wet: wet, end: i + 1, peak: points[i].mm })
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
      ? { title: "Rain for the next 2 hours", sub: capitalize(intensity(first.peak)) + " rain until " + points[points.length - 1].time, pill: "" }
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

// Buienradar icon letter -> English word + Nerd Font (Material) weather glyph.
// A doubled letter ("aa.png", "bb.png") is the night version.
var CONDITIONS = {
  a: ["Clear", 0xf0599], b: ["Partly cloudy", 0xf0595], j: ["Partly cloudy", 0xf0595],
  o: ["Partly cloudy", 0xf0595], r: ["Partly cloudy", 0xf0595], c: ["Overcast", 0xf0590],
  p: ["Overcast", 0xf0590], d: ["Fog", 0xf0591], n: ["Fog", 0xf0591], f: ["Showers", 0xf0597],
  h: ["Showers", 0xf0597], k: ["Light rain", 0xf0597], l: ["Rain", 0xf0596], m: ["Light rain", 0xf0597],
  q: ["Rain", 0xf0596], g: ["Thunder", 0xf0593], s: ["Thunder", 0xf0593], i: ["Snow", 0xf0598],
  t: ["Snow", 0xf0598], u: ["Snow", 0xf0598], v: ["Snow", 0xf0598], w: ["Sleet", 0xf067f]
}

function condition(iconUrl) {
  var code = (String(iconUrl || "").match(/([a-z]+)\.png$/) || [])[1] || ""
  var c = CONDITIONS[code.charAt(code.length - 1)] || ["", 0xf0590]
  // Night: moon for clear, moon-and-cloud for partly cloudy; other conditions look the same.
  var night = code.length > 1 && code.charAt(0) === code.charAt(1)
  var glyph = night && c[1] === 0xf0599 ? 0xf0594 : night && c[1] === 0xf0595 ? 0xf0f31 : c[1]
  return { text: c[0], glyph: String.fromCodePoint(glyph) }
}

function windText(ms, dir) {
  var d = String(dir || "").replace(/Z/g, "S").replace(/O/g, "E")
  return (d ? d + " " : "") + Math.round(ms * 3.6) + " km/h"
}

function fmt(v, unit) {
  return v === null || v === undefined || v === "" || isNaN(v) ? "—" : Math.round(v) + unit
}

var WEEKDAYS = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]

// The feed's "now" from the station nearest to lat/lon, plus the next 3 days after today.
function parseFeed(raw, lat, lon, todayIso) {
  var feed
  try { feed = JSON.parse(raw) } catch (e) { return null }
  var stations = feed && feed.actual && feed.actual.stationmeasurements
  if (!stations || !stations.length) return null
  var k = Math.cos(lat * Math.PI / 180)
  var st = stations.filter(function (s) { return s.temperature !== undefined && s.temperature !== null })
    .sort(function (a, b) {
      return Math.pow(a.lat - lat, 2) + Math.pow((a.lon - lon) * k, 2) - Math.pow(b.lat - lat, 2) - Math.pow((b.lon - lon) * k, 2)
    })[0]
  if (!st) return null
  var c = condition(st.iconurl)
  var days = ((feed.forecast && feed.forecast.fivedayforecast) || [])
    .filter(function (d) { return String(d.day).slice(0, 10) > todayIso })
    .slice(0, 3)
    .map(function (d) {
      return {
        // A date-only ISO string parses as UTC midnight, so getUTCDay is timezone-safe.
        name: WEEKDAYS[new Date(String(d.day).slice(0, 10)).getUTCDay()],
        hi: fmt(d.maxtemperature, "°"), lo: fmt(d.mintemperature, "°"),
        rain: "rain " + (d.rainChance || 0) + "%", glyph: condition(d.iconurl).glyph
      }
    })
  return {
    now: {
      temp: fmt(st.temperature, "°"), feels: fmt(st.feeltemperature, "°"),
      wind: windText(st.windspeed || 0, st.winddirection),
      humidity: fmt(st.humidity, "%"),
      text: c.text, glyph: c.glyph
    },
    days: days
  }
}

if (typeof module !== "undefined") module.exports = { parseRainText: parseRainText, summary: summary, condition: condition, windText: windText, parseFeed: parseFeed }
