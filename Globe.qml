import QtQuick
import qs.Commons
import "Model.js" as Model
import "Land.js" as Land

// Spinning orthographic globe rendered on a Canvas.
//
// - Every color is read live from Color / bar so theme switches repaint
//   automatically (see _themeTick below).
// - `points` are {iso, name, lat, lon, count} country anchors.
// - Hovering a dot emits pointHovered (parent auto-plays when hoverPlay is
//   on); clicking emits pointSelected. Dragging spins the globe by hand.
Item {
  id: root

  property real centerLon: 15
  property real centerLat: 22
  property var points: []
  property string hoveredIso: ""
  property string selectedIso: ""
  property string playingIso: ""
  property bool spinning: true
  // When not spinning, the country the globe rests on (playing station,
  // else the user's own). Re-applied whenever it changes and each time the
  // popup opens, so a hand-dragged globe comes back to it.
  property string focusIso: ""
  property bool shown: true
  property real pulse: 0 // 0..1 heartbeat for the now-playing dot

  signal pointHovered(var point)
  signal pointSelected(var point)

  // Theme-reactive repaint triggers: any theme swap reassigns these
  // singletons, which nudges the canvas. (Canvas has no automatic
  // binding to Color.*, so we bridge it explicitly.)
  readonly property color _fg: Color.foreground
  readonly property color _bg: Color.background
  readonly property color _accent: Color.accent
  readonly property color _popBg: Color.popups.background
  readonly property color _popBorder: Color.popups.border
  on_FgChanged: { canvas.requestPaint(); bgCanvas.requestPaint(); coastCanvas.requestPaint() }
  on_BgChanged: canvas.requestPaint()
  on_AccentChanged: { canvas.requestPaint(); bgCanvas.requestPaint() }
  on_PopBgChanged: { canvas.requestPaint(); bgCanvas.requestPaint() }
  on_PopBorderChanged: { canvas.requestPaint(); bgCanvas.requestPaint() }
  onPointsChanged: canvas.requestPaint()
  onHoveredIsoChanged: canvas.requestPaint()
  onSelectedIsoChanged: canvas.requestPaint()
  onPlayingIsoChanged: canvas.requestPaint()
  onCenterLonChanged: { canvas.requestPaint(); bgCanvas.requestPaint(); coastCanvas.requestPaint() }
  onCenterLatChanged: { canvas.requestPaint(); bgCanvas.requestPaint(); coastCanvas.requestPaint() }
  onPulseChanged: canvas.requestPaint()
  onWidthChanged: { canvas.requestPaint(); bgCanvas.requestPaint(); coastCanvas.requestPaint() }
  onHeightChanged: { canvas.requestPaint(); bgCanvas.requestPaint(); coastCanvas.requestPaint() }

  onFocusIsoChanged: recenter()
  onShownChanged: if (shown) recenter()
  onSpinningChanged: recenter()
  Component.onCompleted: recenter()

  function recenter() {
    if (spinning || focusIso === "") return;
    var ll = Model.coordFor(focusIso);
    centerLon = ll[1];
    centerLat = ll[0];
  }

  function pointAt(px, py) {
    var r = globeRadius();
    var c = globeCenter();
    var best = null;
    var bestD = 18 * 18;
    for (var i = 0; i < points.length; i++) {
      var p = points[i];
      var pr = Model.project(p.lat, p.lon, root.centerLon, root.centerLat, c.x, c.y, r);
      if (!pr.vis) continue;
      var dx = pr.x - px, dy = pr.y - py;
      var d = dx * dx + dy * dy;
      if (d < bestD) { bestD = d; best = p; }
    }
    return best;
  }

  function globeRadius() {
    return Math.max(40, Math.min(width, height) / 2 - 14);
  }

  function globeCenter() {
    return { x: width / 2, y: height / 2 };
  }

  function dotRadius(count, hovered) {
    var r = 2 + Math.log10(1 + Number(count || 0)) * 1.6;
    if (r > 6.5) r = 6.5;
    return hovered ? r + 2 : r;
  }

  // Ocean sphere and graticule, below the coastlines. The dots and the
  // hover chip stay on `canvas`, above them, so the pulse only repaints those.
  Canvas {
    id: bgCanvas
    anchors.fill: parent
    renderTarget: Canvas.FramebufferObject
    antialiasing: true

    onPaint: {
      var ctx = getContext("2d");
      ctx.clearRect(0, 0, width, height);
      var fg = root._fg, accent = root._accent;
      var popBg = root._popBg, popBorder = root._popBorder;
      var c = root.globeCenter();
      var r = root.globeRadius();

      // ---- Ocean sphere with a soft offset highlight ----
      var ocean = ctx.createRadialGradient(c.x - r * 0.35, c.y - r * 0.4, r * 0.1, c.x, c.y, r);
      ocean.addColorStop(0, Qt.lighter(popBg, 1.28).toString());
      ocean.addColorStop(0.65, popBg.toString());
      ocean.addColorStop(1, Qt.darker(popBg, 1.35).toString());
      ctx.beginPath();
      ctx.arc(c.x, c.y, r, 0, Math.PI * 2);
      ctx.fillStyle = ocean;
      ctx.fill();

      // Rim light on the day side, theme-accent kissed.
      ctx.beginPath();
      ctx.arc(c.x, c.y, r, Math.PI * 1.05, Math.PI * 1.65);
      ctx.strokeStyle = Qt.rgba(accent.r, accent.g, accent.b, 0.55).toString();
      ctx.lineWidth = 2.5;
      ctx.stroke();

      ctx.beginPath();
      ctx.arc(c.x, c.y, r, 0, Math.PI * 2);
      ctx.strokeStyle = popBorder.toString();
      ctx.lineWidth = 2;
      ctx.stroke();

      ctx.save();
      ctx.beginPath();
      ctx.arc(c.x, c.y, r, 0, Math.PI * 2);
      ctx.clip();

      // ---- Graticule ----
      ctx.lineWidth = 1;
      var i, k, p, pr, started;
      // Meridians every 20 deg.
      for (var m = -180; m < 180; m += 20) {
        ctx.strokeStyle = Qt.rgba(fg.r, fg.g, fg.b, (m === 0 ? 0.22 : 0.12)).toString();
        ctx.beginPath();
        started = false;
        for (k = -78; k <= 78; k += 4) {
          pr = Model.project(k, m, root.centerLon, root.centerLat, c.x, c.y, r);
          if (!pr.vis) { started = false; continue; }
          if (!started) { ctx.moveTo(pr.x, pr.y); started = true; }
          else ctx.lineTo(pr.x, pr.y);
        }
        ctx.stroke();
      }
      // Parallels every 20 deg.
      for (var par = -60; par <= 80; par += 20) {
        var isEq = par === 0;
        ctx.strokeStyle = Qt.rgba(fg.r, fg.g, fg.b, isEq ? 0.26 : 0.12).toString();
        ctx.beginPath();
        started = false;
        for (k = -180; k <= 180; k += 4) {
          pr = Model.project(par, root.centerLon + k, root.centerLon, root.centerLat, c.x, c.y, r);
          if (!pr.vis) { started = false; continue; }
          if (!started) { ctx.moveTo(pr.x, pr.y); started = true; }
          else ctx.lineTo(pr.x, pr.y);
        }
        ctx.stroke();
      }

      ctx.restore();
    }
  }

  // Coastlines on their own canvas: repainted only when the globe turns,
  // resizes or the theme changes, not on every pulse/hover frame. Raster
  // (Image) target because it strokes thousands of segments far cheaper.
  Canvas {
    id: coastCanvas
    anchors.fill: parent
    z: 1
    renderTarget: Canvas.Image
    antialiasing: true

    onPaint: {
      var ctx = getContext("2d");
      ctx.clearRect(0, 0, width, height);
      var fg = root._fg;
      var c = root.globeCenter();
      var r = root.globeRadius();
      var i, k, started;
      ctx.save();
      ctx.beginPath();
      ctx.arc(c.x, c.y, r, 0, Math.PI * 2);
      ctx.clip();
      ctx.strokeStyle = Qt.rgba(fg.r, fg.g, fg.b, 0.45).toString();
      ctx.lineWidth = 1.2;
      ctx.lineJoin = "round";
      // Same orthographic projection as Model.project, but on precomputed
      // unit vectors so thousands of points cost no trig per frame.
      var cLo = root.centerLon * Math.PI / 180, cLa = root.centerLat * Math.PI / 180;
      var cosCLo = Math.cos(cLo), sinCLo = Math.sin(cLo);
      var cosCLa = Math.cos(cLa), sinCLa = Math.sin(cLa);
      ctx.beginPath();
      for (i = 0; i < Land.unit.length; i++) {
        var u = Land.unit[i];
        started = false;
        for (k = 0; k < u.length; k += 3) {
          var q = u[k] * cosCLo + u[k + 1] * sinCLo;
          if (sinCLa * u[k + 2] + cosCLa * q <= 0.02) { started = false; continue; }
          var lx = c.x + r * (u[k + 1] * cosCLo - u[k] * sinCLo);
          var ly = c.y - r * (cosCLa * u[k + 2] - sinCLa * q);
          if (!started) { ctx.moveTo(lx, ly); started = true; }
          else ctx.lineTo(lx, ly);
        }
      }
      ctx.stroke();
      ctx.restore();
    }
  }

  Canvas {
    id: canvas
    anchors.fill: parent
    z: 2
    renderTarget: Canvas.FramebufferObject
    antialiasing: true

    onPaint: {
      var ctx = getContext("2d");
      var w = width, h = height;
      ctx.clearRect(0, 0, w, h);

      var fg = root._fg, accent = root._accent;
      var popBg = root._popBg, popBorder = root._popBorder;
      var c = root.globeCenter();
      var r = root.globeRadius();

      ctx.save();
      ctx.beginPath();
      ctx.arc(c.x, c.y, r, 0, Math.PI * 2);
      ctx.clip();
      var i, k, p, pr;

      // ---- Country dots ----
      for (i = 0; i < root.points.length; i++) {
        p = root.points[i];
        pr = Model.project(p.lat, p.lon, root.centerLon, root.centerLat, c.x, c.y, r);
        if (!pr.vis) continue;
        var hovered = p.iso === root.hoveredIso;
        var selected = p.iso === root.selectedIso;
        var playing = p.iso === root.playingIso;
        var dr = root.dotRadius(p.count, hovered);

        if (playing) {
          // Sonar rings around the now-playing country.
          for (var ring = 0; ring < 2; ring++) {
            var phase = (root.pulse + ring * 0.5) % 1.0;
            ctx.beginPath();
            ctx.arc(pr.x, pr.y, dr + 3 + phase * 11, 0, Math.PI * 2);
            ctx.strokeStyle = Qt.rgba(accent.r, accent.g, accent.b, (1 - phase) * 0.5).toString();
            ctx.lineWidth = 1.5;
            ctx.stroke();
          }
        }

        var fade = 0.45 + 0.55 * Math.min(1, Math.max(0, pr.z));
        if (playing) {
          ctx.fillStyle = accent.toString();
        } else if (hovered || selected) {
          var mixT = hovered ? 0.35 : 0.6;
          ctx.fillStyle = Qt.rgba(
            accent.r * (1 - mixT) + fg.r * mixT,
            accent.g * (1 - mixT) + fg.g * mixT,
            accent.b * (1 - mixT) + fg.b * mixT, fade).toString();
        } else {
          ctx.fillStyle = Qt.rgba(fg.r, fg.g, fg.b, 0.62 * fade + 0.18).toString();
        }
        ctx.beginPath();
        ctx.arc(pr.x, pr.y, dr, 0, Math.PI * 2);
        ctx.fill();

        if (selected) {
          ctx.beginPath();
          ctx.arc(pr.x, pr.y, dr + 3.5, 0, Math.PI * 2);
          ctx.strokeStyle = Qt.rgba(fg.r, fg.g, fg.b, 0.8).toString();
          ctx.lineWidth = 1.5;
          ctx.stroke();
        }
      }
      ctx.restore();

      // ---- Hovered label chip, painted in theme colors ----
      if (root.hoveredIso !== "") {
        var hp = null;
        for (i = 0; i < root.points.length; i++)
          if (root.points[i].iso === root.hoveredIso) { hp = root.points[i]; break; }
        if (hp) {
          var label = (hp.display || hp.name) + "  ·  " + hp.count + " stations";
          ctx.font = "600 13px monospace";
          var tw = ctx.measureText(label).width;
          var bx = Math.min(Math.max(c.x - tw / 2 - 12, 6), w - tw - 24);
          // Chip sits inside the globe's lower limb so it is never clipped
          // when the sphere fills its box.
          var by = Math.min(c.y + r - 38, h - 34);
          ctx.fillStyle = Qt.rgba(popBg.r, popBg.g, popBg.b, 0.94).toString();
          ctx.strokeStyle = Qt.rgba(accent.r, accent.g, accent.b, 0.7).toString();
          ctx.lineWidth = 1;
          ctx.beginPath();
          if (ctx.roundRect) ctx.roundRect(bx, by, tw + 24, 26, 8);
          else ctx.rect(bx, by, tw + 24, 26);
          ctx.fill();
          ctx.stroke();
          ctx.fillStyle = fg.toString();
          ctx.textBaseline = "middle";
          ctx.fillText(label, bx + 12, by + 14);
        }
      }
    }
  }

  // Gentle auto-spin (the `autospin` setting) + playing pulse. Spin
  // pauses while the pointer is down or resting on the globe so
  // hover-to-play never fights the motion.
  Timer {
    interval: 50
    running: root.visible && root.spinning && !globeMouse.pressed && !globeMouse.containsMouse
    repeat: true
    onTriggered: {
      root.centerLon = (root.centerLon + 0.35) % 360;
      if (root.centerLon > 180) root.centerLon -= 360;
    }
  }
  Timer {
    interval: 60
    running: root.visible && root.shown && root.playingIso !== ""
    repeat: true
    onTriggered: root.pulse = (root.pulse + 0.025) % 1.0
  }

  MouseArea {
    id: globeMouse
    anchors.fill: parent
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton
    cursorShape: root.hoveredIso !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor

    property real lastX: 0
    property real lastY: 0
    property bool dragging: false

    onPressed: function (mouse) {
      lastX = mouse.x; lastY = mouse.y; dragging = true;
    }
    onReleased: function (mouse) {
      var wasDrag = Math.abs(mouse.x - lastX) + Math.abs(mouse.y - lastY) > 6;
      dragging = false;
      if (!wasDrag) {
        var p = root.pointAt(mouse.x, mouse.y);
        if (p) root.pointSelected(p);
      }
    }
    onPositionChanged: function (mouse) {
      if (dragging && (mouse.buttons & Qt.LeftButton)) {
        root.centerLon -= (mouse.x - lastX) * 0.35;
        if (root.centerLon > 180) root.centerLon -= 360;
        if (root.centerLon < -180) root.centerLon += 360;
        root.centerLat = Math.max(-66, Math.min(66, root.centerLat + (mouse.y - lastY) * 0.25));
        lastX = mouse.x; lastY = mouse.y;
        return;
      }
      var hit = root.pointAt(mouse.x, mouse.y);
      var iso = hit ? hit.iso : "";
      if (iso !== root.hoveredIso) {
        root.hoveredIso = iso;
        if (hit) root.pointHovered(hit);
      }
    }
    onExited: root.hoveredIso = ""
  }
}
