// Run: node test.js
const assert = require("assert")
const fs = require("fs")
// Model.js starts with QML's ".pragma library"; strip it so node can load the file.
const src = fs.readFileSync(__dirname + "/Model.js", "utf8").replace(".pragma library", "")
const m = {}; new Function("module", src)(m); const { parseRainText, summary, condition, windText, parseFeed } = m.exports

// Weather feed
assert.strictEqual(condition("https://x/30x30/c.png").text, "Overcast")
assert.notStrictEqual(condition("https://x/30x30/aa.png").glyph, condition("https://x/30x30/a.png").glyph)
assert.strictEqual(windText(4, "WZW"), "WSW 14 km/h")
const feed = JSON.stringify({
  actual: { stationmeasurements: [
    { stationname: "Far", lat: 51.0, lon: 4.0, temperature: 3, feeltemperature: 1, humidity: 50, windspeed: 1, winddirection: "N", iconurl: "a.png" },
    { stationname: "Near", lat: 52.10, lon: 5.18, temperature: 8.2, feeltemperature: null, humidity: 83, windspeed: 4, winddirection: "WZW", iconurl: "c.png" },
  ] },
  forecast: { fivedayforecast: [
    { day: "2026-11-21T00:00:00", mintemperature: "0", maxtemperature: "8", rainChance: 70, iconurl: "q.png" },
    { day: "2026-11-22T00:00:00", mintemperature: "-1", maxtemperature: "7", rainChance: 10, iconurl: "b.png" },
    { day: "2026-11-23T00:00:00", mintemperature: "-1", maxtemperature: "5", rainChance: 0, iconurl: "b.png" },
    { day: "2026-11-24T00:00:00", mintemperature: "-2", maxtemperature: "3", rainChance: 0, iconurl: "b.png" },
    { day: "2026-11-25T00:00:00", mintemperature: "-2", maxtemperature: "2", rainChance: 0, iconurl: "b.png" },
  ] },
})
const w = parseFeed(feed, 52.09, 5.12, "2026-11-21")
assert.strictEqual(w.now.temp, "8°")
assert.strictEqual(w.now.feels, "—")
assert.strictEqual(w.now.wind, "WSW 14 km/h")
assert.strictEqual(w.now.humidity, "83%")
assert.strictEqual(w.now.text, "Overcast")
assert.deepStrictEqual(w.days.map(d => d.name), ["SUN", "MON", "TUE"])
assert.deepStrictEqual([w.days[0].hi, w.days[0].lo, w.days[0].rain], ["7°", "-1°", "rain 10%"])
assert.strictEqual(parseFeed("nope", 52, 5, "2026-11-21"), null)

const raw = "118|14:35\n104|14:40\n077|14:45\n000|14:50\n000|14:55\n000|15:00\n087|15:05\n092|15:10\n000|15:15\n000|15:20\n087|15:25\n"
const pts = parseRainText(raw)
assert.strictEqual(pts.length, 11)
assert.strictEqual(pts[3].mm, 0)
assert.ok(Math.abs(pts[0].mm - 1.91) < 0.01)

assert.deepStrictEqual(summary(pts), {
  title: "Rain stops at 14:50",
  sub: "Dry from 14:50 to 15:05, then light rain again",
  pill: "dry 14:50",
})
assert.deepStrictEqual(summary(parseRainText("000|10:00\n000|10:05\n130|10:10\n")), {
  title: "Rain starts at 10:10", sub: "Moderate rain after that", pill: "rain 10:10",
})
assert.strictEqual(summary(parseRainText("000|10:00\n000|10:05\n")).title, "Dry for the next 2 hours")
assert.strictEqual(summary(parseRainText("")).pill, "")
// Sensor noise (001 ≈ 0.0004 mm/h) is not rain.
assert.strictEqual(summary(parseRainText("001|10:00\n000|10:05\n")).title, "Dry for the next 2 hours")
// Every sub line starts with a capital.
assert.strictEqual(summary(parseRainText("100|23:50\n100|23:55\n")).sub, "Light rain until 23:55")
// Graph height: log scale, 0 when dry, 1 at 20 mm/h and above; light rain stays visible.
assert.strictEqual(m.exports.scale(0), 0)
assert.strictEqual(m.exports.scale(20), 1)
assert.strictEqual(m.exports.scale(100), 1)
assert.ok(m.exports.scale(0.7) > 0.3 && m.exports.scale(0.7) < 0.5)
assert.ok(m.exports.scale(m.exports.MODERATE) < m.exports.scale(m.exports.HEAVY))
// Place search: only NL/BE results (Buienradar covers nothing else).
const geo = JSON.stringify({ results: [
  { name: "Utrecht", admin1: "Utrecht", country: "Netherlands", country_code: "NL", latitude: 52.0908, longitude: 5.1222 },
  { name: "Utrecht", admin1: "KwaZulu-Natal", country: "South Africa", country_code: "ZA", latitude: -27.65, longitude: 30.32 },
  { name: "Gent", admin1: "Flanders", country: "Belgium", country_code: "BE", latitude: 51.05, longitude: 3.72 },
] })
assert.deepStrictEqual(m.exports.parsePlaces(geo).map(p => p.description), ["Utrecht, Netherlands", "Flanders, Belgium"])
assert.strictEqual(m.exports.parsePlaces(geo)[0].latitude, 52.0908)
assert.deepStrictEqual(m.exports.parsePlaces("{}"), [])
assert.deepStrictEqual(m.exports.parsePlaces("not json"), [])
// Night versions: doubled letter.
assert.notStrictEqual(condition("bb.png").glyph, condition("b.png").glyph)
assert.strictEqual(condition("cc.png").text, "Overcast")
// Radar frames are 10 minutes apart; the first one is the UTC time in the URL.
process.env.TZ = "Europe/Amsterdam"
const url = "https://x/Animation/202611211945__500x512_True_False_True_0_12_1_0_run202611211940.gif"
const start = m.exports.radarStart(url)
assert.strictEqual(m.exports.frameTime(start, 0), "20:45")
assert.strictEqual(m.exports.frameTime(start, 11), "22:35")
assert.strictEqual(m.exports.frameTime(m.exports.radarStart("nope"), 0), "")
// Hourly forecast: drops past hours, keeps 24, crosses days.
const hrs = []
for (let i = 0; i < 30; ++i) {
  const utc = new Date(Date.UTC(2026, 10, 24, 18 + i)).toISOString().slice(0, 19)
  const local = new Date(Date.UTC(2026, 10, 24, 19 + i)).toISOString().slice(0, 19)
  hrs.push({ datetime: local, datetimeutc: utc, temperature: i, precipitation: i === 5 ? 40 : 0, iconcode: i % 2 ? "aa" : "q" })
}
const fc = JSON.stringify({ days: [{ hours: hrs.slice(0, 6) }, { hours: null }, { hours: hrs.slice(6) }] })
const hourly = m.exports.parseHourly(fc, Date.UTC(2026, 10, 24, 20, 30))
assert.strictEqual(hourly.length, 24)
assert.deepStrictEqual([hourly[0].hour, hourly[0].temp, hourly[3].chance], ["21", 2, 40])
assert.strictEqual(hourly[0].glyph, condition("q.png").glyph)
assert.deepStrictEqual(m.exports.parseHourly("nope", 0), [])
// Place id: nearest result wins.
const locs = JSON.stringify([{ id: 1, location: { lat: 50, lon: 4 } }, { id: 2751738, location: { lat: 52.508, lon: 5.475 } }])
assert.strictEqual(m.exports.parseLocationId(locs, 52.51, 5.48), 2751738)
assert.strictEqual(m.exports.parseLocationId("[]", 52, 5), 0)
console.log("ok")
