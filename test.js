// Run: node test.js
const assert = require("assert")
const fs = require("fs")
// Model.js starts with QML's ".pragma library"; strip it so node can load the file.
const src = fs.readFileSync(__dirname + "/Model.js", "utf8").replace(".pragma library", "")
const m = {}; new Function("module", src)(m); const { parseRainText, summary } = m.exports

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
console.log("ok")
