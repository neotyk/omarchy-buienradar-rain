import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// Popup, two columns: weather now, next 3 days, rain summary and graph on the
// left; animated Buienradar radar map on the right.
// Lifecycle code follows Omarchy's own omarchy.weather panel.
Panel {
  id: root
  moduleName: "buienradar.rain"
  ipcTarget: "buienradar.rain"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // ponytail: rain is blue in every theme, so this one color is fixed.
  readonly property color rainColor: "#3badb2"
  readonly property color dim: Qt.darker(root.bar.foreground, 1.4)
  readonly property real latitude: parseFloat(setting("latitude", 52.37))
  readonly property real longitude: parseFloat(setting("longitude", 4.89))
  readonly property string placeName: setting("place", "")
  readonly property string radarPath: Quickshell.env("XDG_RUNTIME_DIR") + "/buienradar-radar.gif"

  property var points: []
  property var weather: null   // last good parseFeed() result
  readonly property var info: Model.summary(points)
  // Bar text; empty until the first good response, which hides the widget.
  readonly property string label: {
    var change = info.pill
    if (weather) return weather.now.glyph + " " + weather.now.temp + (change ? " · " + change : "")
    return points.length ? String.fromCodePoint(0xf0597) + (change ? " " + change : "") : ""
  }

  function refresh() {
    if (!rainProc.running) rainProc.running = true
    if (!feedProc.running) feedProc.running = true
  }

  function open() { openFromHotkey() }

  function openFromHotkey() {
    root.controller.show()
    if (!radarProc.running) radarProc.running = true
    root.refresh()
  }

  function close() { root.controller.hide() }

  function toggle() {
    if (root.opened) root.close()
    else root.openFromHotkey()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }

  Process {
    id: rainProc
    command: ["curl", "-fsS", "--max-time", "10",
      "https://gpsgadget.buienradar.nl/data/raintext?lat=" + root.latitude.toFixed(2) + "&lon=" + root.longitude.toFixed(2)]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = Model.parseRainText(text)
        if (parsed.length) {
          root.points = parsed
          graph.requestPaint()
        }
      }
    }
  }

  Process {
    id: feedProc
    command: ["curl", "-fsS", "--max-time", "10", "https://data.buienradar.nl/2.0/feed/json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = Model.parseFeed(text, root.latitude, root.longitude, Qt.formatDate(new Date(), "yyyy-MM-dd"))
        if (parsed) root.weather = parsed
      }
    }
  }

  // Download the GIF ourselves and show the local file: Qt's own network
  // loading of the animation was the main suspect in a shell crash.
  Process {
    id: radarProc
    command: ["sh", "-c", "curl -fsSL --max-time 20 -o \"$1.tmp\" \"$2\" && [ -s \"$1.tmp\" ] && mv \"$1.tmp\" \"$1\"", "sh", root.radarPath,
      "https://image.buienradar.nl/2.0/image/animation/RadarMapRainNL"
      + "?height=512&width=500&renderBackground=True&renderBranding=False&renderText=True&history=12&forecast=24"]
    onExited: function(code) {
      if (code !== 0) return
      radar.source = ""
      radar.source = "file://" + root.radarPath
    }
  }

  // Rain updates every 5 minutes; the small weather feed rides the same timer.
  Timer {
    interval: 5 * 60 * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.openFromHotkey() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): void { root.refresh() }
  }

  component Label: Text {
    color: root.bar.foreground
    font.family: root.bar.fontFamily
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
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Row {
        id: content
        spacing: Style.space(20)

        Column {
          width: Style.space(500)
          spacing: Style.space(16)

          // ---- Now: icon + temperature left, place and stats right.
          Item {
            width: parent.width
            height: Math.max(nowLeft.height, nowRight.height)
            visible: root.weather !== null

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
                anchors.right: parent.right
                text: [root.placeName, root.weather ? root.weather.now.text : ""].filter(Boolean).join(" · ").toUpperCase()
                font.letterSpacing: 1
              }
              Row {
                anchors.right: parent.right
                spacing: Style.space(14)
                Stat { name: "FEELS"; value: root.weather ? root.weather.now.feels : "" }
                Stat { name: "WIND"; value: root.weather ? root.weather.now.wind : "" }
                Stat { name: "HUMID"; value: root.weather ? root.weather.now.humidity : "" }
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

          // ---- Rain, next 2 hours.
          Column {
            width: parent.width
            spacing: Style.space(4)
            Label { text: "Rain · next 2 hours"; color: root.dim; font.pixelSize: Style.font.bodySmall }
            Label { text: root.info.title || "No rain data"; font.pixelSize: Style.font.title; font.bold: true }
            Label { visible: text !== ""; text: root.info.sub; color: Commons.Color.accent }
          }

          Column {
            width: parent.width
            spacing: Style.space(6)

            Canvas {
              id: graph
              width: parent.width
              height: Style.space(120)
              onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                var pts = root.points
                if (pts.length < 2) return
                var peak = 0
                for (var i = 0; i < pts.length; ++i) peak = Math.max(peak, pts[i].mm)
                var max = Math.max(2.5, peak)
                function y(mm) { return height - 4 - (mm / max) * (height - 8) }

                ctx.strokeStyle = Qt.rgba(root.bar.foreground.r, root.bar.foreground.g, root.bar.foreground.b, 0.12)
                ctx.setLineDash([3, 4])
                ;[0.5, 2].forEach(function (mm) {
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

                ctx.fillStyle = Commons.Color.accent
                ctx.fillRect(0, 0, 2, height)
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

        // ---- Radar map.
        Column {
          spacing: Style.space(10)
          AnimatedImage {
            id: radar
            width: Style.space(526)
            height: Style.space(500)
            fillMode: Image.PreserveAspectCrop
            playing: root.opened
            cache: false
          }
          Label { text: "Source: buienradar.nl"; color: root.dim; font.pixelSize: Style.font.caption }
        }
      }
    }
  }
}
