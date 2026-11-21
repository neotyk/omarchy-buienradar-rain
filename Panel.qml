import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

// Popup: summary, 2-hour rain graph and the animated Buienradar radar map.
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
  readonly property real latitude: parseFloat(setting("latitude", 52.37))
  readonly property real longitude: parseFloat(setting("longitude", 4.89))
  readonly property string placeName: setting("place", "")

  property var points: []
  readonly property var info: Model.summary(points)
  // Bar text; empty until the first good response, which hides the widget.
  readonly property string label: points.length ? String.fromCodePoint(0xf0597) + (info.pill ? " " + info.pill : "") : ""
  property string radarUrl: ""

  function radarSource() {
    return "https://image.buienradar.nl/2.0/image/animation/RadarMapRainNL"
      + "?height=512&width=500&renderBackground=True&renderBranding=False&renderText=True"
      + "&history=12&forecast=24&t=" + Date.now()
  }

  function refresh() {
    if (!rainProc.running) rainProc.running = true
  }

  function open() { openFromHotkey() }

  function openFromHotkey() {
    root.controller.show()
    root.radarUrl = radarSource()
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

  // Buienradar updates the forecast every 5 minutes.
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

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(526))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        width: parent.width
        spacing: Style.space(16)

        Column {
          width: parent.width
          spacing: Style.space(4)

          Text {
            text: (root.placeName ? root.placeName + " · " : "") + "next 2 hours"
            color: Qt.darker(root.bar.foreground, 1.4)
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
          Text {
            text: root.info.title || "No rain data"
            color: root.bar.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
          }
          Text {
            visible: text !== ""
            text: root.info.sub
            color: Commons.Color.accent
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
          }
        }

        Column {
          width: parent.width
          spacing: Style.space(6)

          Canvas {
            id: graph
            width: parent.width
            height: Style.space(110)
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
              Text {
                readonly property int idx: Math.round(modelData * (root.points.length - 1))
                x: modelData * (parent.width - width)
                text: idx === 0 ? "now" : root.points[idx].time
                color: Qt.darker(root.bar.foreground, 1.4)
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.caption
              }
            }
          }
        }

        AnimatedImage {
          width: parent.width
          height: Math.round(width * 500 / 526)
          fillMode: Image.PreserveAspectCrop
          source: root.opened ? root.radarUrl : ""
          playing: root.opened
          cache: false
        }

        Text {
          text: "Source: buienradar.nl"
          color: Qt.darker(root.bar.foreground, 1.4)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
