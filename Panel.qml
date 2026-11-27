import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// Popup, two columns: weather now, next 3 days, and two tabs (rain for the next
// 2 hours, forecast for the next 24 hours) on the left; animated Buienradar radar map on the right.
// Lifecycle code follows Omarchy's own omarchy.weather panel.
Panel {
  id: root
  moduleName: "io.github.neotyk.buienradar-rain"
  ipcTarget: "io.github.neotyk.buienradar-rain"

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // ponytail: rain is blue in every theme, so this one color is fixed.
  readonly property color rainColor: "#3badb2"
  // bar is injected after load, so it is null for a moment.
  readonly property color fg: root.bar ? root.bar.foreground : Commons.Color.foreground
  readonly property color dim: Qt.darker(root.fg, 1.4)
  readonly property real latitude: parseFloat(setting("latitude", 52.37))
  readonly property real longitude: parseFloat(setting("longitude", 4.89))
  readonly property string placeName: setting("place", "")
  readonly property string radarPath: Quickshell.env("XDG_RUNTIME_DIR") + "/buienradar-radar.gif"
  property string radarUrl: ""            // final GIF URL; it holds the frame times
  readonly property real radarStart: Model.radarStart(radarUrl)

  property var points: []
  property real pointsAt: 0    // when points last arrived (ms)
  property var weather: null   // last good parseFeed() result
  property var hourly: []      // last good parseHourly() result
  property int locationId: 0   // Buienradar id for the hourly forecast
  property string idKey: ""    // the location the id was found for
  property string tab: "rain"  // "rain" or "hours"
  readonly property var info: Model.summary(points)
  // Bar text; empty until the first good response, which hides the widget.
  readonly property string label: {
    var change = info.pill
    if (weather) return weather.now.glyph + " " + weather.now.temp + (change ? " · " + change : "")
    return points.length ? String.fromCodePoint(0xf0597) + (change ? " " + change : "") : ""
  }

  function refresh() {
    // Rain data older than 15 minutes would show a "next change" that has passed.
    if (points.length && Date.now() - pointsAt > 15 * 60 * 1000) points = []
    if (!rainProc.running) { rainProc.key = locationKey; rainProc.running = true }
    if (!feedProc.running) { feedProc.key = locationKey; feedProc.running = true }
    if (idKey !== locationKey) { if (!idProc.running) { idProc.key = locationKey; idProc.running = true } }
    else if (locationId && !hourlyProc.running) { hourlyProc.key = locationKey; hourlyProc.running = true }
  }

  // Each fetch remembers the location it was started for; results for an older place are dropped.
  function stale(proc) {
    if (proc.key === locationKey) return false
    locationChange.restart()   // refetch shortly, once this process has exited
    return true
  }

  // close() also ends a search, so the key catcher is not left blocked.
  function close() {
    if (editing) stopEditing()
    root.controller.hide()
  }

  // toggle() and IPC come from the base Panel.
  function open() {
    root.controller.show()
    radarProc.running = true
    root.refresh()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  Process {
    id: rainProc
    property string key
    command: ["curl", "-fsS", "--max-time", "10",
      "https://gpsgadget.buienradar.nl/data/raintext?lat=" + root.latitude.toFixed(2) + "&lon=" + root.longitude.toFixed(2)]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (root.stale(rainProc)) return
        var parsed = Model.parseRainText(text)
        if (parsed.length) {
          root.points = parsed
          root.pointsAt = Date.now()
        }
      }
    }
  }

  Process {
    id: feedProc
    property string key
    command: ["curl", "-fsS", "--max-time", "10", "https://data.buienradar.nl/2.0/feed/json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (root.stale(feedProc)) return
        var parsed = Model.parseFeed(text, root.latitude, root.longitude, Qt.formatDate(new Date(), "yyyy-MM-dd"))
        if (parsed) root.weather = parsed
      }
    }
  }

  // The hourly forecast needs a Buienradar place id: search by place name, keep the nearest hit.
  Process {
    id: idProc
    property string key
    command: ["curl", "-fsS", "--max-time", "10",
      "https://location.buienradar.nl/1.1/location/search?query=" + encodeURIComponent(root.placeName || "Amsterdam")]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (root.stale(idProc)) return
        var id = Model.parseLocationId(text, root.latitude, root.longitude)
        if (!id) return   // try again on the next refresh
        root.locationId = id
        root.idKey = idProc.key
        root.hourly = []
        root.refresh()
      }
    }
  }

  Process {
    id: hourlyProc
    property string key
    command: ["curl", "-fsS", "--max-time", "10", "https://forecast.buienradar.nl/2.0/forecast/" + root.locationId]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (root.stale(hourlyProc)) return
        var parsed = Model.parseHourly(text, Date.now())
        if (parsed.length) root.hourly = parsed
      }
    }
  }

  // Download the GIF ourselves and show the local file: Qt's own network
  // loading of the animation was the main suspect in a shell crash.
  Process {
    id: radarProc
    // Own temp file per run, so two instances during a hot reload never share one.
    // Prints the final URL (after redirects) only when the new file is in place.
    command: ["sh", "-c", "t=$(mktemp \"$1.XXXXXX\") && u=$(curl -fsSL --max-time 20 -w '%{url_effective}' -o \"$t\" \"$2\") && [ -s \"$t\" ] && mv \"$t\" \"$1\" && echo \"$u\" || { rm -f \"$t\"; exit 1; }",
      "sh", root.radarPath,
      "https://image.buienradar.nl/2.0/image/animation/RadarMapRainNL"
      // No past frames and 12 ten-minute frames: the map spans the 2-hour rain graph.
      + "?height=512&width=500&renderBackground=True&renderBranding=False&renderText=True&history=0&forecast=12"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var url = text.trim()
        if (!url) return   // download failed; keep the old map
        // Stop the animation before swapping files; set the new one, and its
        // frame times, together on the next tick.
        radar.playing = false
        radar.source = ""
        Qt.callLater(function() {
          root.radarUrl = url
          radar.source = "file://" + root.radarPath
          radar.playing = Qt.binding(function() { return root.opened })
        })
      }
    }
  }

  // Rain updates every 5 minutes; the small weather feed rides the same timer.
  // The radar map only updates while the popup is open; open() fetches it too.
  Timer {
    interval: 5 * 60 * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      root.refresh()
      if (root.opened) radarProc.running = true
    }
  }

  // A new location refetches once both coordinates have changed.
  readonly property string locationKey: latitude + "," + longitude
  onLocationKeyChanged: locationChange.restart()
  Timer { id: locationChange; interval: 300; onTriggered: root.refresh() }

  // ---- Place search: click the place name, type, pick a suggestion.
  property bool editing: false
  property var places: []
  property int placeIndex: 0

  function startEditing() {
    editing = true
    Qt.callLater(function() { placeField.text = root.placeName; placeField.selectAll(); placeField.forceActiveFocus() })
  }

  function stopEditing() {
    editing = false
    placeDebounce.stop()
    places = []
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  // Saves to this widget's shell.json entry, like the bar's own widgets do.
  function pickPlace(p) {
    if (!p || !root.bar) return
    root.points = []
    root.bar.shell.updateEntryInline(root.moduleName,
      Object.assign({}, root.settings, { id: root.moduleName, latitude: p.latitude, longitude: p.longitude, place: p.name }))
    stopEditing()
  }

  Timer {
    id: placeDebounce
    interval: 300
    onTriggered: {
      var q = placeField.text.trim()
      if (q.length < 2) { root.places = []; return }
      if (placeProc.running) { restart(); return }
      placeProc.command = ["curl", "-fsS", "--max-time", "5",
        "https://geocoding-api.open-meteo.com/v1/search?count=10&language=en&format=json&name=" + encodeURIComponent(q)]
      placeProc.running = true
    }
  }

  Process {
    id: placeProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.places = root.editing ? Model.parsePlaces(text) : []
        root.placeIndex = 0
      }
    }
  }

  component Label: Text {
    color: root.fg
    font.family: root.bar ? root.bar.fontFamily : ""
    font.pixelSize: Style.font.body
  }

  component Stat: Column {
    property string name
    property string value
    Label { anchors.right: parent.right; text: parent.name; color: root.dim; font.pixelSize: Style.font.caption }
    Label { anchors.right: parent.right; text: parent.value }
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(1046))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.editing
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Row {
        id: content
        width: parent.width
        spacing: Style.space(20)

        Column {
          id: left
          width: Style.space(500)
          spacing: Style.space(16)

          // ---- Now: icon + temperature left, place and stats right.
          Item {
            z: 1   // the place suggestions below it cover the rest of the column
            width: parent.width
            height: Math.max(nowLeft.height, nowRight.height)

            Row {
              id: nowLeft
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(14)
              Label { text: root.weather ? root.weather.now.glyph : ""; font.pixelSize: 56; anchors.verticalCenter: parent.verticalCenter }
              Label { text: root.weather ? root.weather.now.temp : ""; font.pixelSize: 50; font.bold: true; anchors.verticalCenter: parent.verticalCenter }
            }

            Column {
              id: nowRight
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(6)
              Label {
                visible: !root.editing
                anchors.right: parent.right
                text: [root.placeName || "Set location", root.weather ? root.weather.now.text : ""].filter(Boolean).join(" · ").toUpperCase()
                font.letterSpacing: 1
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.startEditing()
                }
              }
              TextField {
                id: placeField
                visible: root.editing
                anchors.right: parent.right
                width: Style.space(220)
                placeholderText: "Search place (NL/BE)"
                foreground: root.fg
                font.family: root.bar ? root.bar.fontFamily : ""
                // Old suggestions go away at once, so Enter never picks from a previous search.
                onTextChanged: if (root.editing) { root.places = []; placeDebounce.restart() }
                Keys.onPressed: function(event) {
                  if (event.key === Qt.Key_Escape) root.stopEditing()
                  else if (event.key === Qt.Key_Down) root.placeIndex = Math.max(0, Math.min(root.placeIndex + 1, root.places.length - 1))
                  else if (event.key === Qt.Key_Up) root.placeIndex = Math.max(root.placeIndex - 1, 0)
                  else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) root.pickPlace(root.places[root.placeIndex])
                  else return
                  event.accepted = true
                }
              }
              Row {
                anchors.right: parent.right
                spacing: Style.space(14)
                Stat { name: "FEELS"; value: root.weather ? root.weather.now.feels : "" }
                Stat { name: "WIND"; value: root.weather ? root.weather.now.wind : "" }
                Stat { name: "HUMID"; value: root.weather ? root.weather.now.humidity : "" }
              }
            }

            // ---- Place suggestions while searching: drawn over the days and rain,
            // so the layout does not move while typing.
            Rectangle {
              anchors.top: parent.bottom
              anchors.topMargin: Style.space(8)
              width: parent.width
              height: suggestionList.height
              color: Commons.Color.popups.background
              visible: root.editing && root.places.length > 0
              Column {
                id: suggestionList
                width: parent.width
                Repeater {
                  model: root.places
                  Rectangle {
                    required property var modelData
                    required property int index
                    width: parent.width
                    height: placeRow.implicitHeight + Style.space(12)
                    radius: Style.cornerRadius
                    color: index === root.placeIndex ? Style.hoverFillFor(root.fg, Commons.Color.accent) : "transparent"
                    Row {
                      id: placeRow
                      anchors.left: parent.left
                      anchors.leftMargin: Style.space(12)
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: Style.space(8)
                      Label { text: modelData.name }
                      Label { text: modelData.description; color: root.dim; font.pixelSize: Style.font.bodySmall; anchors.verticalCenter: parent.verticalCenter }
                    }
                    MouseArea {
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onPositionChanged: root.placeIndex = index
                      onClicked: root.pickPlace(modelData)
                    }
                  }
                }
              }
            }
          }

          // ---- Next 3 days.
          Row {
            width: parent.width
            visible: root.weather !== null && root.weather.days.length > 0
            Repeater {
              model: root.weather ? root.weather.days : []
              Item {
                width: parent.width / 3
                height: dayRow.height + Style.space(16)
                Row {
                  id: dayRow
                  anchors.centerIn: parent
                  spacing: Style.space(10)
                  Label { text: modelData.glyph; font.pixelSize: 26; anchors.verticalCenter: parent.verticalCenter }
                  Column {
                    Label { text: modelData.name; font.bold: true; font.pixelSize: Style.font.bodySmall }
                    Label { text: modelData.hi + "  " + modelData.lo; font.pixelSize: Style.font.bodySmall }
                    Label { text: modelData.rain; color: root.rainColor; font.pixelSize: Style.font.caption }
                  }
                }
              }
            }
          }

          // ---- Tabs: rain for the next 2 hours, or the next 24 hours.
          Row {
            spacing: Style.space(18)
            Repeater {
              model: [["rain", "RAIN 2H"], ["hours", "24 HOURS"]]
              Label {
                text: modelData[1]
                color: root.tab === modelData[0] ? root.fg : root.dim
                font.bold: root.tab === modelData[0]
                font.letterSpacing: 1
                font.pixelSize: Style.font.bodySmall
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.tab = modelData[0]
                }
              }
            }
          }

          // Both tabs share this box, so the popup keeps its size.
          // The rain graph bottom lines up with the map bottom; its axis sits beside the source caption.
          Item {
            id: tabArea
            width: parent.width
            height: Math.max(Style.space(220), radar.height - y + Style.space(6 + 14))

            Column {
              anchors.fill: parent
              visible: root.tab === "rain"
              spacing: Style.space(16)

              // ---- Rain, next 2 hours.
              Column {
                id: rainHead
                width: parent.width
                spacing: Style.space(4)
                Label { text: root.info.title || "No rain data"; font.pixelSize: Style.font.title; font.bold: true }
                Label { visible: text !== ""; text: root.info.sub; color: Commons.Color.accent }
              }

              Column {
                id: graphBlock
                width: parent.width
                spacing: Style.space(6)

                Canvas {
                  id: graph
                  width: parent.width
                  height: Math.max(Style.space(120), tabArea.height - rainHead.height - Style.space(16 + 6 + 14))
                  // Repaint when the data or the theme colors change.
                  readonly property var watch: [root.points, root.fg, root.dim, Commons.Color.accent]
                  onWatchChanged: requestPaint()
                  onPaint: {
                    var ctx = getContext("2d")
                    ctx.reset()
                    var pts = root.points
                    if (pts.length < 2) return
                    function y(mm) { return height - 4 - Model.scale(mm) * (height - 8) }

                    ctx.strokeStyle = Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.12)
                    ctx.setLineDash([3, 4])
                    ;[Model.MODERATE, Model.HEAVY].forEach(function (mm) {
                      ctx.beginPath(); ctx.moveTo(0, y(mm)); ctx.lineTo(width, y(mm)); ctx.stroke()
                    })
                    ctx.setLineDash([])

                    ctx.beginPath()
                    for (var j = 0; j < pts.length; ++j) {
                      var x = j * width / (pts.length - 1)
                      if (j === 0) ctx.moveTo(x, y(pts[j].mm)); else ctx.lineTo(x, y(pts[j].mm))
                    }
                    ctx.lineWidth = 2
                    ctx.strokeStyle = root.rainColor
                    ctx.stroke()
                    ctx.lineTo(width, height); ctx.lineTo(0, height); ctx.closePath()
                    ctx.fillStyle = Qt.rgba(root.rainColor.r, root.rainColor.g, root.rainColor.b, 0.18)
                    ctx.fill()

                    // Level names, each centred in its own band.
                    ctx.font = Style.font.caption + "px \"" + (root.bar ? root.bar.fontFamily : "monospace") + "\""
                    ctx.fillStyle = root.dim
                    ctx.textAlign = "right"
                    ctx.textBaseline = "middle"
                    ctx.fillText("light", width - 2, (y(0.1) + y(Model.MODERATE)) / 2)
                    ctx.fillText("moderate", width - 2, (y(Model.MODERATE) + y(Model.HEAVY)) / 2)
                    ctx.fillText("heavy", width - 2, (y(Model.HEAVY) + 4) / 2)
                  }

                  // Time of the radar frame on screen; hidden if that time is not on the graph.
                  Rectangle {
                    id: cursor
                    readonly property string time: Model.frameTime(root.radarStart, radar.currentFrame)
                    readonly property int idx: root.points.findIndex(function (p) { return p.time === cursor.time })
                    visible: idx >= 0 && root.points.length > 1
                    x: idx * (parent.width - width) / (root.points.length - 1)
                    width: 2
                    height: parent.height
                    color: Commons.Color.accent
                  }
                }

                Item {
                  width: parent.width
                  height: Style.space(14)
                  Repeater {
                    // now, then four evenly spaced times to the end of the forecast.
                    model: root.points.length ? [0, 0.25, 0.5, 0.75, 1] : []
                    Label {
                      readonly property int idx: Math.round(modelData * (root.points.length - 1))
                      x: modelData * (parent.width - width)
                      text: idx === 0 ? "now" : root.points[idx].time
                      color: root.dim
                      font.pixelSize: Style.font.caption
                    }
                  }
                }
              }
            }

            // ---- Next 24 hours: icon, hour and temperature every 3 hours over a
            // temperature line and rain chance bars.
            Column {
              id: hourTab
              anchors.fill: parent
              visible: root.tab === "hours"
              spacing: Style.space(6)
              readonly property var hrs: root.hourly
              // x of hour i on the chart.
              function xAt(i, w) { return hrs.length > 1 ? i * w / (hrs.length - 1) : 0 }

              Label { visible: hourTab.hrs.length === 0; text: "No hourly data"; font.pixelSize: Style.font.title; font.bold: true }

              Item {
                id: hourLabels
                width: parent.width
                height: Style.space(50)
                Repeater {
                  model: hourTab.hrs.filter(function (h, i) { return i % 3 === 0 })
                  Column {
                    x: Math.max(0, Math.min(parent.width - width, hourTab.xAt(index * 3, parent.width) - width / 2))
                    spacing: Style.space(2)
                    Label { anchors.horizontalCenter: parent.horizontalCenter; text: modelData.glyph; font.pixelSize: 22 }
                    Label { anchors.horizontalCenter: parent.horizontalCenter; text: Math.round(modelData.temp) + "°"; font.pixelSize: Style.font.bodySmall }
                  }
                }
              }

              Canvas {
                id: hourChart
                width: parent.width
                height: parent.height - hourLabels.height - hourAxis.height - 2 * parent.spacing
                readonly property var watch: [root.hourly, root.fg, root.dim]
                onWatchChanged: requestPaint()
                onPaint: {
                  var ctx = getContext("2d")
                  ctx.reset()
                  var hs = hourTab.hrs
                  if (hs.length < 2) return
                  var temps = hs.map(function (h) { return h.temp })
                  var lo = Math.min.apply(null, temps), hi = Math.max.apply(null, temps)
                  // Whole-degree levels, 2 to 5 of them; the range is padded to the outer levels.
                  var step = hi - lo <= 3 ? 1 : hi - lo <= 8 ? 2 : 5
                  lo = Math.floor(lo / step) * step
                  hi = Math.max(Math.ceil(hi / step) * step, lo + step)
                  // Two panels with a gap: temperature on top, rain chance below.
                  var cap = Style.font.caption
                  var tTop = cap + 10, tBottom = height * 0.56
                  var rTop = height * 0.70, rH = height - rTop
                  function x(i) { return hourTab.xAt(i, width) }
                  function ty(t) { return tTop + (1 - (t - lo) / (hi - lo)) * (tBottom - tTop) }
                  function ry(pct) { return height - pct / 100 * rH }
                  var grid = Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.12)

                  // Rain panel background, so it reads as its own chart.
                  ctx.fillStyle = Qt.rgba(root.rainColor.r, root.rainColor.g, root.rainColor.b, 0.07)
                  ctx.fillRect(0, rTop, width, rH)

                  // Hour lines every 3 hours, inside each panel only.
                  ctx.strokeStyle = grid
                  for (var i = 3; i < hs.length; i += 3) {
                    ctx.beginPath(); ctx.moveTo(x(i), tTop - 4); ctx.lineTo(x(i), tBottom); ctx.stroke()
                    ctx.beginPath(); ctx.moveTo(x(i), rTop); ctx.lineTo(x(i), height); ctx.stroke()
                  }

                  ctx.font = cap + "px \"" + (root.bar ? root.bar.fontFamily : "monospace") + "\""
                  ctx.textBaseline = "bottom"
                  // Panel titles.
                  ctx.textAlign = "left"
                  ctx.fillStyle = root.dim
                  ctx.fillText("TEMPERATURE", 0, cap + 2)
                  ctx.fillStyle = root.rainColor
                  ctx.fillText("RAIN CHANCE", 0, rTop - 4)

                  // Level lines with their values on the right.
                  ctx.fillStyle = root.dim
                  ctx.textAlign = "right"
                  ctx.setLineDash([3, 4])
                  function level(y, text) {
                    ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(width, y); ctx.stroke()
                    ctx.fillText(text, width - 2, y - 1)
                  }
                  for (var t = lo; t <= hi; t += step) level(ty(t), t + "°")
                  level(ry(50), "50%")
                  level(ry(100), "100%")
                  ctx.setLineDash([])

                  ctx.fillStyle = Qt.rgba(root.rainColor.r, root.rainColor.g, root.rainColor.b, 0.7)
                  var bw = width / hs.length * 0.7
                  hs.forEach(function (h, i) {
                    var bh = h.chance / 100 * rH
                    if (bh > 0) ctx.fillRect(Math.max(0, Math.min(width - bw, x(i) - bw / 2)), height - bh, bw, bh)
                  })
                  ctx.strokeStyle = grid
                  ctx.beginPath(); ctx.moveTo(0, height - 0.5); ctx.lineTo(width, height - 0.5); ctx.stroke()

                  ctx.beginPath()
                  hs.forEach(function (h, i) {
                    var y = ty(h.temp)
                    if (i === 0) ctx.moveTo(x(i), y); else ctx.lineTo(x(i), y)
                  })
                  ctx.lineWidth = 2
                  ctx.strokeStyle = root.fg
                  ctx.stroke()
                }
              }

              Item {
                id: hourAxis
                width: parent.width
                height: Style.space(14)
                Repeater {
                  model: hourTab.hrs.filter(function (h, i) { return i % 3 === 0 })
                  Label {
                    x: Math.max(0, Math.min(parent.width - width, hourTab.xAt(index * 3, parent.width) - width / 2))
                    text: index === 0 ? "now" : modelData.hour + ":00"
                    color: root.dim
                    font.pixelSize: Style.font.caption
                  }
                }
              }
            }
          }
        }

        // ---- Radar map.
        Column {
          spacing: Style.space(10)
          AnimatedImage {
            id: radar
            // Fill whatever width the popup has left; crop, never spill.
            width: content.width - left.width - content.spacing
            height: Math.round(width * 500 / 526)
            fillMode: Image.PreserveAspectCrop
            clip: true
            playing: root.opened
            cache: false
          }
          Label { text: "Source: buienradar.nl"; color: root.dim; font.pixelSize: Style.font.caption }
        }
      }
    }
  }
}
