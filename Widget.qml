import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import QtMultimedia
import qs.Commons
import qs.Ui
import "Model.js" as Model

// World Radio — bar widget + big globe popup in one file (agents pattern).
//
// Bar: a globe glyph that sits next to Weather. Lit (urgent) while playing.
// Click: opens a large globe popup with every country. Hovering a country
// on the globe, in the country list, or a city/station row starts live
// radio from there (toggleable via Hover-play). All paint comes from the
// Color/Style singletons, so theme switches restyle the whole plugin live.
Panel {
  id: root
  moduleName: "io.github.kaibur02.omarchy-world-radio"
  ipcTarget: "io.github.kaibur02.omarchy-world-radio"
  manageIpc: false

  // ------------------------------- state -------------------------------
  property var countries: []          // {name, iso, count}
  property var stations: []           // cleaned stations of selected country
  property var stationCache: ({})     // iso -> stations[]
  property string selectedIso: ""
  property string selectedName: ""
  property var currentStation: null
  property string currentUrl: ""
  property bool playing: false
  property bool buffering: false
  property bool muted: false
  property string statusText: "Hover the globe to tune in"
  property string errorText: ""
  property bool loadingCountries: false
  property bool loadingStations: false
  property string searchText: ""
  // Global name-search results while a search is live.
  property var searchStations: []
  property bool loadingSearch: false
  // Last query actually sent to the API, so stale responses can be dropped.
  property string searchQuery: ""
  property bool hoverPlay: setting("hoverPlay", true) === true || String(setting("hoverPlay", true)) === "true"
  property real volume: {
    var v = Number(setting("volume", 0.8));
    return isFinite(v) ? Math.max(0, Math.min(1, v)) : 0.8;
  }
  property int mirrorIndex: 0
  property string pendingIso: ""
  property var pendingStation: null
  property bool _persistGuard: false

  // The user's explicit choice: a country, plus the station they picked in
  // it. Only clicks and Enter write these — hover previews never do. This is
  // the anchor the list returns to when the search filter is cleared, so
  // emptying the filter can no longer leave the selection on whatever the
  // mouse happened to be over.
  property string committedIso: ""
  property string committedName: ""
  property var committedStation: null
  // Scroll the committed row into view once its list lands.
  property bool revealPending: false

  // Filter, preview and selection are three different things. While a search
  // filter is active the lists rebuild on every keystroke, so rows slide
  // under a still cursor and Qt re-fires containsMouse on them; acting on
  // those synthetic hovers is what moved the selection by itself. During a
  // live search hover only highlights — committing is click-only.
  readonly property bool hoverCommits: hoverPlay && !searching

  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property var globePoints: {
    var out = [];
    for (var i = 0; i < countries.length; i++) {
      var c = countries[i];
      if (!c || c.count < 1) continue;
      var ll = Model.coordFor(c.iso);
      // Keep the raw API name for station fetches (the API matches exact
      // names like "The United States Of America"); `display` is for paint.
      out.push({ iso: c.iso, name: c.name, display: Model.prettyCountry(c.name), lat: ll[0], lon: ll[1], count: c.count });
    }
    return out;
  }
  readonly property var filteredCountries: {
    var q = searchText.trim().toLowerCase();
    if (q === "") return countries;
    // Name/ISO matches keep their total station count. Countries of
    // matching stations join them with matched-station counts, so the
    // country list tracks the worldwide results dynamically.
    var out = [];
    var seen = {};
    for (var i = 0; i < countries.length; i++) {
      var c = countries[i];
      if (String(Model.prettyCountry(c.name)).toLowerCase().indexOf(q) < 0
          && String(c.iso).toLowerCase().indexOf(q) < 0) continue;
      out.push({ name: c.name, iso: c.iso, count: c.count });
      seen[c.iso] = true;
    }
    var counts = {};
    for (var j = 0; j < searchStations.length; j++) {
      var iso = String(searchStations[j].countrycode || "").toUpperCase();
      if (iso !== "") counts[iso] = (counts[iso] || 0) + 1;
    }
    for (var k = 0; k < countries.length; k++) {
      var cc = countries[k];
      if (seen[cc.iso] || !counts[cc.iso]) continue;
      seen[cc.iso] = true;
      out.push({ name: cc.name, iso: cc.iso, count: counts[cc.iso] });
    }
    for (var m = 0; m < out.length; m++) {
      if (counts[out[m].iso] > 0) out[m].count = counts[out[m].iso];
    }
    out.sort(function (a, b) { return b.count - a.count; });
    return out;
  }
  readonly property bool searching: searchText.trim() !== ""
  readonly property var displayStations: searching ? searchStations : stations

  // The picked station, when it is not part of the list on screen. Search
  // ranks worldwide by name relevance while a country list ranks by clicks
  // and cuts at 30, so a pick is often absent from its own country's top
  // list — it gets a pinned row above the list, so the choice is always
  // visible and clearing a filter always has something to land on.
  readonly property var pinnedStation: {
    if (!committedStation) return null;
    var list = displayStations;
    for (var i = 0; i < list.length; i++)
      if (list[i].uuid === committedStation.uuid) return null;
    return committedStation;
  }
  readonly property string playingIso: currentStation ? String(currentStation.countrycode || "") : ""
  readonly property string nowPlayingText: currentStation
    ? (currentStation.name + "  ·  " + Model.stationLabel(currentStation)) : "Nothing playing"
  readonly property string barTooltip: playing || buffering
    ? (nowPlayingText + (buffering ? "  (tuning…)" : "")) : "World Radio — click for the globe"

  // The bar tracks this widget (not the nested popup) as the popout owner.
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root
  readonly property bool opened: controller.open

  function open() {
    ensureData();
    controller.show();
    Qt.callLater(function () {
      if (root.opened) setCenterHoverRevealSuppressed(true);
    });
  }
  function close() {
    setCenterHoverRevealSuppressed(false);
    hoverTimer.stop();
    controller.hide();
  }
  function toggle() { root.opened ? root.close() : root.open(); }
  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction);
    return false;
  }
  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && typeof root.bar.setCenterHoverRevealSuppressed === "function")
      root.bar.setCenterHoverRevealSuppressed(value);
    else if (root.bar && "centerHoverRevealSuppressed" in root.bar)
      root.bar.centerHoverRevealSuppressed = value;
  }

  function persistSettings(values) {
    var entry = { id: root.moduleName };
    for (var k in root.settings) if (k !== "id") entry[k] = root.settings[k];
    for (var key in values) entry[key] = values[key];
    _persistGuard = true;
    root.settings = entry;
    if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = entry;
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry);
    _persistGuard = false;
  }

  // ------------------------------- audio -------------------------------
  // Qt's PipeWire backend resolves the "default" output once, when the
  // AudioOutput opens its stream, and pins node.target to that node — so a
  // live stream never follows later default-device changes on its own. Read
  // the live default sink from Quickshell (Pipewire.defaultAudioSink, the
  // same source the omarchy audio panel uses), bind AudioOutput.device to
  // it, and re-open the stream when it changes so the radio follows the
  // system default like every other app.
  MediaDevices { id: mediaDevices }

  readonly property var pwDefaultSink: Pipewire.defaultAudioSink

  readonly property var defaultOutDevice: {
    var ds = pwDefaultSink;
    if (!ds) return null;
    var outs = mediaDevices.audioOutputs;
    var i;
    // Match the PipeWire node name first: it is unique, where the friendly
    // description is not (identical devices, and DSP filter nodes that
    // PipeWire also lists as outputs, can share one).
    var wantName = String(ds.name || "");
    if (wantName !== "")
      for (i = 0; i < outs.length; i++)
        if (String(outs[i].id || "") === wantName) return outs[i];
    var wantDesc = String(ds.description || "");
    if (wantDesc !== "")
      for (i = 0; i < outs.length; i++)
        if (String(outs[i].description || "") === wantDesc) return outs[i];
    // Unknown device: fall back to letting Qt pick, which is the behaviour
    // from before this fix rather than a broken one.
    return null;
  }

  // Stable identity of the resolved device, so a retarget only fires when the
  // device really changes and not on every audioOutputs refresh.
  readonly property string defaultOutKey: {
    var d = root.defaultOutDevice;
    return d ? (String(d.id || "") + "|" + String(d.description || "")) : "";
  }

  // Re-open a live stream so a new default device takes effect. Debounced
  // because a device change (a Bluetooth speaker connecting, say) updates the
  // default sink and the output list a beat apart, and both of those land
  // here — one restart per change, after everything has settled.
  Timer {
    id: retargetTimer
    interval: 350
    onTriggered: {
      if (!(root.playing || root.buffering) || root.currentUrl === "") return;
      var url = root.currentUrl;
      player.stop();
      player.source = "";
      player.source = url;
      player.play();
    }
  }
  onPwDefaultSinkChanged: retargetTimer.restart()
  onDefaultOutKeyChanged: retargetTimer.restart()

  MediaPlayer {
    id: player
    audioOutput: AudioOutput {
      id: audioOut
      // Never assign null here: before Pipewire is ready there is no resolved
      // device yet, and handing QAudioDevice a null logs a warning on every
      // shell start. MediaDevices' own default is a valid stand-in until then.
      device: root.defaultOutDevice !== null
        ? root.defaultOutDevice
        : mediaDevices.defaultAudioOutput
      volume: root.muted ? 0 : root.volume
    }
    onPlaybackStateChanged: {
      root.playing = playbackState === MediaPlayer.PlayingState;
      if (playbackState === MediaPlayer.PlayingState) {
        root.buffering = false;
        root.errorText = "";
        root.statusText = "Live · " + root.nowPlayingText;
        pingClick();
      } else if (playbackState === MediaPlayer.StoppedState && root.currentUrl !== "") {
        // Stopped with a URL set means buffering/handover, not a user stop.
      }
    }
    onMediaStatusChanged: {
      if (mediaStatus === MediaPlayer.LoadingMedia || mediaStatus === MediaPlayer.BufferingMedia
          || mediaStatus === MediaPlayer.StalledMedia) {
        root.buffering = true;
        root.statusText = "Tuning… " + (root.currentStation ? root.currentStation.name : "");
      } else if (mediaStatus === MediaPlayer.BufferedMedia || mediaStatus === MediaPlayer.LoadedMedia) {
        root.buffering = false;
      } else if (mediaStatus === MediaPlayer.InvalidMedia) {
        root.buffering = false;
        onStreamFailed("Stream unreachable — trying next station");
      } else if (mediaStatus === MediaPlayer.EndOfMedia) {
        onStreamFailed("Stream ended — trying next station");
      }
    }
    onErrorOccurred: function (error, errorString) {
      root.buffering = false;
      onStreamFailed(errorString || "Playback error — trying next station");
    }
  }

  function playStation(st) {
    if (!st || !st.url) return;
    if (st.url === root.currentUrl && root.playing) return;
    root.currentStation = st;
    root.currentUrl = st.url;
    root.errorText = "";
    root.buffering = true;
    root.statusText = "Tuning… " + st.name;
    player.source = st.url;
    player.play();
  }

  // Clicking a station row plays it and remembers the pick: the country it
  // came from is what a later filter clear returns to. A pick from worldwide
  // search results also marks its country — highlighted in the country list
  // and on the globe — while the search and its results stay on screen.
  function playStationFromList(st) {
    playStation(st);
    if (!st) return;
    var iso = String(st.countrycode || "").toUpperCase();
    var name = String(st.country || "");
    if (iso === "") {
      for (var i = 0; i < countries.length; i++) {
        if (String(countries[i].name || "").toLowerCase()
            === name.toLowerCase()) {
          iso = countries[i].iso;
          name = countries[i].name;
          break;
        }
      }
    }
    if (iso !== "") {
      committedStation = st;
      committedIso = iso;
      committedName = name;
    }
    if (!root.searching || iso === "") return;
    root.selectCountry(iso, name, false);
  }

  function stopPlayback() {
    hoverTimer.stop();
    root.pendingStation = null;
    root.currentStation = null;
    root.currentUrl = "";
    root.playing = false;
    root.buffering = false;
    root.errorText = "";
    root.statusText = "Stopped — hover the globe to tune in";
    player.stop();
    player.source = "";
  }

  function onStreamFailed(msg) {
    // Advance to the next station in the current list (search results
    // included) so a dead stream never leaves silence behind.
    var list = root.displayStations;
    var idx = -1;
    for (var i = 0; i < list.length; i++) {
      if (currentStation && list[i].uuid === currentStation.uuid) { idx = i; break; }
    }
    if (idx >= 0 && idx + 1 < list.length) {
      root.errorText = msg;
      playStation(list[idx + 1]);
    } else {
      root.playing = false;
      root.buffering = false;
      root.errorText = msg;
      root.statusText = "Idle";
      player.source = "";
    }
  }

  function pingClick() {
    // Tell radio-browser this stream was clicked (ranking feedback).
    if (!currentStation || !currentStation.uuid) return;
    var xhr = new XMLHttpRequest();
    try {
      xhr.open("GET", Model.clickUrl(Model.MIRRORS[mirrorIndex], currentStation.uuid));
      xhr.send();
    } catch (e) {}
  }

  // ------------------------------- data -------------------------------
  function apiBase() { return Model.MIRRORS[mirrorIndex % Model.MIRRORS.length]; }

  function rotateMirror() {
    mirrorIndex = (mirrorIndex + 1) % Model.MIRRORS.length;
  }

  function ensureData() {
    if (countries.length === 0 && !loadingCountries) fetchCountries();
  }

  function fetchCountries() {
    loadingCountries = true;
    errorText = "";
    statusText = "Loading countries…";
    var xhr = new XMLHttpRequest();
    var base = apiBase();
    xhr.onreadystatechange = function () {
      if (xhr.readyState !== XMLHttpRequest.DONE) return;
      if (xhr.status === 200) {
        try {
          var arr = JSON.parse(xhr.responseText);
          var out = [];
          for (var i = 0; i < arr.length; i++) {
            var c = arr[i] || {};
            if (!c.name) continue;
            out.push({ name: String(c.name), iso: String(c.iso_3166_1 || "").toUpperCase(), count: Number(c.stationcount) || 0 });
          }
          out.sort(function (a, b) { return b.count - a.count; });
          root.countries = out;
          root.statusText = out.length + " countries · hover the globe to tune in";
          if (root.selectedIso === "" && out.length > 0) selectCountry(out[0].iso, out[0].name, false);
        } catch (e) {
          root.errorText = "Could not parse country list";
        }
        root.loadingCountries = false;
      } else {
        rotateMirror();
        if (mirrorIndex === 0) {
          root.loadingCountries = false;
          root.errorText = "Radio directory unreachable — check connection, then ↻";
          root.statusText = "Offline";
        } else {
          fetchCountries();
        }
      }
    };
    try {
      xhr.open("GET", Model.countriesUrl(base));
      xhr.send();
    } catch (e) {
      root.loadingCountries = false;
      root.errorText = "Radio directory unreachable";
    }
  }

  function selectCountry(iso, name, autoplay) {
    root.selectedIso = iso;
    root.selectedName = name;
    if (stationCache[iso]) {
      root.stations = stationCache[iso];
      if (autoplay && stationCache[iso].length > 0) playStation(stationCache[iso][0]);
      return;
    }
    fetchStations(iso, name, autoplay, false);
  }

  // An explicit country choice — a click on a row or on a globe point, or
  // Enter on a filtered country. This, and not whatever the pointer later
  // drifts across, is what the panel goes back to when a filter clears.
  function commitCountry(iso, name) {
    committedIso = iso;
    committedName = name;
    committedStation = null;
    // A country pick has no station row to reveal.
    revealPending = false;
  }

  // A keystroke invalidates any hover preview still sitting on its debounce:
  // the row that armed it may not even be on screen any more.
  function cancelPendingHover() {
    hoverTimer.stop();
    pendingIso = "";
    pendingStation = null;
  }

  // Clearing the filter is a view operation, not a selection one: it puts
  // the user back on the country they chose their station from.
  function restoreCommittedContext() {
    if (committedIso === "") return;
    revealPending = true;
    if (selectedIso === committedIso && stations.length > 0) {
      Qt.callLater(root.revealCommittedStation);
      return;
    }
    selectedIso = committedIso;
    selectedName = committedName;
    if (stationCache[committedIso]) {
      stations = stationCache[committedIso];
      Qt.callLater(root.revealCommittedStation);
    } else {
      // No autoplay: clearing a filter must not restart audio.
      fetchStations(committedIso, committedName, false, false);
    }
  }

  // Bring the chosen station back into view in the restored list — the same
  // thing a file manager does with the selection after a filter is cleared.
  function revealCommittedStation() {
    if (!revealPending || !committedStation || !stationFlick) return;
    // One attempt per restore. If the pick is not in this list it is shown
    // as the pinned row instead, so there is nothing to scroll to and no
    // reason to keep waiting on a later list change.
    revealPending = false;
    var list = displayStations;
    var idx = -1;
    for (var i = 0; i < list.length; i++) {
      if (list[i].uuid === committedStation.uuid) { idx = i; break; }
    }
    if (idx < 0) return;
    var rowH = Style.space(40);
    var view = stationFlick.height - Style.space(8);
    var top = idx * rowH;
    if (top < stationFlick.contentY
        || top + rowH > stationFlick.contentY + view) {
      var maxY = Math.max(0, stationFlick.contentHeight - view);
      stationFlick.contentY = Math.max(0, Math.min(top - rowH, maxY));
    }
  }

  // A fetch that was already in flight when the filter cleared still owes us
  // the scroll once it lands.
  onStationsChanged: Qt.callLater(root.revealCommittedStation)

  // isHover marks hover-armed fetches: their play-on-arrival is honored
  // only while hover-play is still on. Clicks pass false and always play.
  function fetchStations(iso, name, autoplay, isHover) {
    loadingStations = true;
    var xhr = new XMLHttpRequest();
    var base = apiBase();
    xhr.onreadystatechange = function () {
      if (xhr.readyState !== XMLHttpRequest.DONE) return;
      if (xhr.status === 200) {
        try {
          var arr = JSON.parse(xhr.responseText);
          var out = [];
          for (var i = 0; i < arr.length; i++) {
            var st = Model.cleanStation(arr[i]);
            if (st.url !== "") out.push(st);
          }
          var cache = root.stationCache;
          cache[iso] = out;
          root.stationCache = cache;
          if (root.selectedIso === iso) root.stations = out;
          // A hover preview may have been waiting on this fetch — honor it
          // only if hover-play is still on (it may have been toggled off
          // mid-flight). Click-initiated fetches always play on arrival.
          if (autoplay && (!isHover || root.hoverPlay) && out.length > 0
              && (root.pendingIso === iso || root.selectedIso === iso))
            playStation(out[0]);
        } catch (e) {}
        root.loadingStations = false;
      } else {
        rotateMirror();
        if (mirrorIndex === 0) {
          root.loadingStations = false;
        } else {
          fetchStations(iso, name, autoplay, isHover);
        }
      }
    };
    try {
      xhr.open("GET", Model.stationsByCountryUrl(base, name, 30));
      xhr.send();
    } catch (e) {
      root.loadingStations = false;
    }
  }

  // Global station search: typing a station name (or part of one) queries
  // the whole radio-browser directory, so any station is reachable without
  // knowing its country first. Typing is debounced and Enter plays the top
  // result.
  function commitSearch(playTop) {
    var q = searchText.trim();
    if (q === "") {
      searchTimer.stop();
      searchQuery = "";
      searchStations = [];
      loadingSearch = false;
      // An empty filter restores the full station list, but lands on the
      // user's committed pick — not on whatever row the pointer drifted
      // across while deleting.
      restoreCommittedContext();
      return;
    }
    if (q.length < 2) {
      // One character is too broad for a worldwide query.
      searchQuery = q;
      searchStations = [];
      loadingSearch = false;
      return;
    }
    if (q === searchQuery && searchStations.length > 0) {
      if (playTop) playStationFromList(searchStations[0]);
      return;
    }
    searchTimer.stop();
    fetchStationSearch(q, playTop);
  }

  function fetchStationSearch(q, playTop) {
    loadingSearch = true;
    searchQuery = q;
    var xhr = new XMLHttpRequest();
    var base = apiBase();
    xhr.onreadystatechange = function () {
      if (xhr.readyState !== XMLHttpRequest.DONE) return;
      // Ignore a response that a newer keystroke already superseded.
      if (q !== String(root.searchText || "").trim()) return;
      if (xhr.status === 200) {
        try {
          var arr = JSON.parse(xhr.responseText);
          var out = [];
          for (var i = 0; i < arr.length; i++) {
            var st = Model.cleanStation(arr[i]);
            if (st.url !== "") out.push(st);
          }
          root.searchStations = out;
          // Enter on a search is an explicit pick, so it commits like a click.
          if (playTop && out.length > 0) root.playStationFromList(out[0]);
        } catch (e) {}
        root.loadingSearch = false;
      } else {
        rotateMirror();
        if (mirrorIndex === 0) root.loadingSearch = false;
        else root.fetchStationSearch(q, playTop);
      }
    };
    try {
      xhr.open("GET", Model.stationsSearchUrl(base, q, 100));
      xhr.send();
    } catch (e) {
      root.loadingSearch = false;
    }
  }

  Timer {
    id: searchTimer
    interval: 320
    repeat: false
    onTriggered: root.commitSearch(false)
  }

  // Hover-to-play debounce: hovering is chatty, playback must not be.
  Timer {
    id: hoverTimer
    interval: 380
    repeat: false
    onTriggered: {
      if (!root.hoverPlay || !root.opened) {
        // Hover mode went off (or panel closed) with a preview armed:
        // disarm so nothing can start playing afterwards.
        root.pendingIso = "";
        root.pendingStation = null;
        return;
      }
      if (pendingStation) {
        root.playStation(pendingStation);
        pendingStation = null;
      } else if (pendingIso !== "") {
        var iso = pendingIso;
        pendingIso = "";
        var hit = null;
        for (var i = 0; i < countries.length; i++)
          if (countries[i].iso === iso) { hit = countries[i]; break; }
        if (!hit) return;
        root.selectCountry(hit.iso, hit.name, true);
      }
    }
  }

  function previewCountry(iso, name) {
    if (selectedIso !== iso) {
      selectedIso = iso;
      selectedName = name;
      if (stationCache[iso]) {
        stations = stationCache[iso];
        if (hoverPlay && stationCache[iso].length > 0) playStation(stationCache[iso][0]);
      } else {
        pendingIso = iso;
        pendingStation = null;
        hoverTimer.restart();
        fetchStations(iso, name, root.hoverPlay, true);
      }
    } else if (hoverPlay && stationCache[iso] && stationCache[iso].length > 0
               && (!currentStation || currentStation.countrycode !== iso)) {
      playStation(stationCache[iso][0]);
    }
  }

  function previewStation(st) {
    if (!hoverPlay || !st) return;
    if (currentUrl === st.url && playing) return;
    pendingIso = "";
    pendingStation = st;
    hoverTimer.restart();
  }

  Component.onCompleted: ensureData()
  onOpenedChanged: if (opened) ensureData()

  // ------------------------------- bar button -------------------------------
  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open(); }
    function close(): void { root.close(); }
    function show(): void { root.open(); }
    function hide(): void { root.close(); }
    function toggle(): void { root.toggle(); }
    function stop(): void { root.stopPlayback(); }
    function status(): string {
      return JSON.stringify({
        hoverPlay: root.hoverPlay,
        playing: root.playing,
        buffering: root.buffering,
        selected: root.selectedName,
        nowPlaying: root.currentStation ? root.currentStation.name : "",
        countries: root.countries.length,
        stations: root.stations.length,
        pending: root.pendingIso !== "" || root.pendingStation !== null
      });
    }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    active: root.playing
    tooltipText: root.barTooltip
    slotSize: Style.bar.statusSlot
    onPressed: function (b) {
      if (b === Qt.RightButton) {
        if (root.playing || root.buffering) root.stopPlayback();
        else if (root.currentStation) root.playStation(root.currentStation);
      } else if (b === Qt.MiddleButton) {
        if (root.bar) root.bar.run("xdg-open 'https://radio.garden'");
      } else {
        root.toggle();
      }
    }
  }

  // ------------------------------- popup -------------------------------
  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(920))
    contentHeight: panel.fittedContentHeight(sheet.implicitHeight, Style.space(700))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function (direction) { root.switchPanel(direction); }
      onTextKey: function (t) {
        if (t === "/") { searchField.forceActiveFocus(); }
        else if (t === " ") {
          if (root.playing) root.stopPlayback();
          else if (root.currentStation) root.playStation(root.currentStation);
        }
      }

      Flickable {
        id: sheetFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: sheet.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height

        Column {
          id: sheet
          width: sheetFlick.width
          spacing: Style.space(10)

          // ---- Hero ----
          PanelHero {
            width: parent.width
            title: "WORLD RADIO"
            meta: countries.length > 0
              ? (countries.length + " countries · " + (playing ? ("LIVE · " + nowPlayingText) : (buffering ? "tuning…" : "hover the globe to tune in")))
              : "loading the dial…"
            foreground: root.fg
            fontFamily: root.fontFamily
            iconComponent: Component {
              Text {
                text: ""
                color: root.playing ? Color.accent : root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.displayLarge
                verticalAlignment: Text.AlignVCenter
                Behavior on color { ColorAnimation { duration: 240 } }
              }
            }
            trailingControl: Component {
              Row {
                spacing: Style.space(8)
                Button {
                  text: root.hoverPlay ? "hover ▶ on" : "hover ▶ off"
                  fontSize: Style.font.caption
                  bordered: true
                  selected: root.hoverPlay
                  onClicked: {
                    root.hoverPlay = !root.hoverPlay;
                    if (!root.hoverPlay) {
                      // Disarm anything hover queued so the station can only
                      // change by click from here on.
                      hoverTimer.stop();
                      root.pendingIso = "";
                      root.pendingStation = null;
                    }
                    root.persistSettings({ hoverPlay: root.hoverPlay, volume: root.volume });
                  }
                }
                Button {
                  text: "↻"
                  fontSize: Style.font.body
                  bordered: true
                  tooltipText: "Reload countries"
                  onClicked: root.fetchCountries()
                }
                Button {
                  text: "✕"
                  fontSize: Style.font.body
                  bordered: true
                  tooltipText: "Close"
                  onClicked: root.close()
                }
              }
            }
          }

          // ---- Search + counts ----
          Row {
            width: parent.width
            spacing: Style.space(8)
            TextField {
              id: searchField
              width: parent.width - countLabel.width - parent.spacing
              placeholderText: "Search countries + stations…  ( / )"
              text: root.searchText
              font.family: root.fontFamily
              onTextChanged: {
                root.searchText = text;
                root.cancelPendingHover();
                if (text.trim() === "") root.commitSearch(false);
                else searchTimer.restart();
              }
              onAccepted: {
                if (root.searching) root.commitSearch(true);
                else if (filteredCountries.length > 0) {
                  root.commitCountry(filteredCountries[0].iso,
                                     filteredCountries[0].name);
                  root.selectCountry(filteredCountries[0].iso,
                                     filteredCountries[0].name, true);
                }
              }
            }
            Text {
              id: countLabel
              anchors.verticalCenter: parent.verticalCenter
              text: root.searching
                ? (root.loadingSearch
                   ? "searching…"
                   : (root.searchStations.length + " stations"))
                : (filteredCountries.length + " found")
              color: Util.alpha(root.fg, 0.6)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }

          // ---- Main: globe + lists ----
          Row {
            width: parent.width
            spacing: Style.space(12)

            // Globe card.
            Rectangle {
              width: Math.min(Style.space(430), parent.width * 0.47)
              height: Style.space(430)
              radius: Style.cornerRadius
              color: Util.alpha(root.fg, 0.045)
              border.width: 1
              border.color: Util.alpha(Color.popups.border, 0.8)
              Behavior on color { ColorAnimation { duration: 240 } }

              Globe {
                id: globe
                anchors.fill: parent
                anchors.margins: Style.space(6)
                points: root.globePoints
                selectedIso: root.selectedIso
                playingIso: root.playingIso
                onPointHovered: function (p) {
                  if (root.hoverCommits) root.previewCountry(p.iso, p.name);
                }
                onPointSelected: function (p) {
                  root.commitCountry(p.iso, p.name);
                  root.searchText = "";
                  root.selectCountry(p.iso, p.name, true);
                }
              }
            }

            // Right column: countries over stations.
            Column {
              width: parent.width - Style.space(430) - Style.space(12) > 200
                ? parent.width - Math.min(Style.space(430), parent.width * 0.47) - Style.space(12)
                : 200
              spacing: Style.space(8)

              PanelSectionHeader {
                text: "COUNTRIES"
                foreground: root.fg
                fontFamily: root.fontFamily
              }
              Rectangle {
                width: parent.width
                height: Style.space(168)
                radius: Style.cornerRadius
                color: Util.alpha(root.fg, 0.045)
                border.width: 1
                border.color: Util.alpha(root.fg, 0.14)
                clip: true

                Text {
                  visible: root.countries.length === 0 && !root.loadingCountries && root.errorText === ""
                  anchors.centerIn: parent
                  text: "…"
                  color: Util.alpha(root.fg, 0.5)
                  font.family: root.fontFamily
                }
                Text {
                  visible: root.loadingCountries
                  anchors.centerIn: parent
                  text: "Loading countries…"
                  color: Util.alpha(root.fg, 0.6)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.italic: true
                }
                Text {
                  visible: root.errorText !== "" && root.countries.length === 0
                  anchors.centerIn: parent
                  width: parent.width - 24
                  horizontalAlignment: Text.AlignHCenter
                  wrapMode: Text.WordWrap
                  text: root.errorText
                  color: Color.urgent
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }

                Flickable {
                  anchors.fill: parent
                  anchors.margins: Style.space(4)
                  contentWidth: width
                  contentHeight: countryCol.implicitHeight
                  clip: true
                  boundsBehavior: Flickable.StopAtBounds
                  interactive: contentHeight > height
                  ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                  Column {
                    id: countryCol
                    width: parent.width
                    Repeater {
                      model: root.filteredCountries.slice(0, 200)
                      Rectangle {
                        required property var modelData
                        required property int index
                        width: countryCol.width
                        height: Style.space(30)
                        radius: Style.cornerRadius
                        color: modelData.iso === root.selectedIso
                          ? Style.selectedFillFor(root.fg, Color.accent)
                          : (rowHover.containsMouse ? Style.hoverFillFor(root.fg, Color.accent) : "transparent")
                        Behavior on color { ColorAnimation { duration: 120 } }

                        Row {
                          anchors.left: parent.left
                          anchors.right: parent.right
                          anchors.leftMargin: Style.space(10)
                          anchors.rightMargin: Style.space(10)
                          anchors.verticalCenter: parent.verticalCenter
                          spacing: Style.space(8)
                          Rectangle {
                            width: 8; height: 8; radius: 4
                            anchors.verticalCenter: parent.verticalCenter
                            color: modelData.iso === root.playingIso ? Color.accent
                              : (modelData.iso === root.selectedIso ? root.fg : Util.alpha(root.fg, 0.35))
                            Behavior on color { ColorAnimation { duration: 200 } }
                          }
                          Text {
                            textFormat: Text.PlainText
                            width: parent.width - 8 - countText.width - 24
                            text: Model.prettyCountry(modelData.name)
                            color: root.fg
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.body
                            elide: Text.ElideRight
                          }
                          Text {
                            id: countText
                            text: modelData.count
                            color: Util.alpha(root.fg, 0.55)
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                          }
                        }
                        MouseArea {
                          id: rowHover
                          anchors.fill: parent
                          hoverEnabled: true
                          cursorShape: Qt.PointingHandCursor
                          onContainsMouseChanged: {
                            // Hover mode off — or a search is live and these
                            // rows are re-sorting under the cursor: hovering
                            // only highlights; selecting and playing stay
                            // click-only.
                            if (containsMouse && root.hoverCommits)
                              root.previewCountry(modelData.iso, modelData.name);
                          }
                          onClicked: {
                            root.commitCountry(modelData.iso, modelData.name);
                            root.searchText = "";
                            root.selectCountry(modelData.iso, modelData.name, true);
                          }
                        }
                      }
                    }
                  }
                }
              }

              PanelSectionHeader {
                text: root.searching
                  ? "SEARCH RESULTS · WORLDWIDE"
                  : ((root.selectedName !== "" ? Model.prettyCountry(root.selectedName).toUpperCase() + " · " : "") + "LIVE STATIONS")
                foreground: root.fg
                fontFamily: root.fontFamily
              }
              Rectangle {
                width: parent.width
                height: Style.space(196)
                radius: Style.cornerRadius
                color: Util.alpha(root.fg, 0.045)
                border.width: 1
                border.color: Util.alpha(root.fg, 0.14)
                clip: true

                Text {
                  visible: root.loadingStations && !root.searching
                  anchors.centerIn: parent
                  text: "Tuning " + Model.prettyCountry(root.selectedName) + "…"
                  color: Util.alpha(root.fg, 0.6)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.italic: true
                }
                Text {
                  visible: root.searching && root.loadingSearch
                  anchors.centerIn: parent
                  text: "Searching the world…"
                  color: Util.alpha(root.fg, 0.6)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                  font.italic: true
                }
                Text {
                  visible: root.searching && !root.loadingSearch
                    && root.searchStations.length === 0 && root.searchText.trim().length >= 2
                  anchors.centerIn: parent
                  text: "No stations match \"" + root.searchText.trim() + "\""
                  color: Util.alpha(root.fg, 0.5)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }
                Text {
                  visible: !root.searching && !root.loadingStations && root.stations.length === 0
                  anchors.centerIn: parent
                  text: "Hover a country to list its stations"
                  color: Util.alpha(root.fg, 0.5)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.bodySmall
                }

                // Pinned pick: parked above the scroll area so it stays put
                // while the list moves, the way a now-playing row does.
                Rectangle {
                  id: pinRow
                  visible: root.pinnedStation !== null
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.top: parent.top
                  anchors.margins: Style.space(4)
                  height: Style.space(40)
                  radius: Style.cornerRadius
                  color: Style.selectedFillFor(root.fg, Color.accent)

                  // Accent stripe marks the row as the user's pick, not a
                  // ranked entry.
                  Rectangle {
                    width: Style.space(3)
                    height: parent.height - Style.space(12)
                    radius: width / 2
                    anchors.left: parent.left
                    anchors.leftMargin: Style.space(5)
                    anchors.verticalCenter: parent.verticalCenter
                    color: Color.accent
                  }
                  Row {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: Style.space(12)
                    anchors.rightMargin: Style.space(10)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Style.space(8)
                    Text {
                      text: (root.pinnedStation && root.currentStation
                             && root.currentStation.uuid === root.pinnedStation.uuid
                             && root.playing) ? "▶" : "♫"
                      width: Style.space(16)
                      color: Color.accent
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.body
                    }
                    Column {
                      width: parent.width - Style.space(16) - Style.space(8)
                      spacing: 1
                      Text {
                        textFormat: Text.PlainText
                        width: parent.width
                        text: root.pinnedStation ? root.pinnedStation.name : ""
                        color: root.fg
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.body
                        elide: Text.ElideRight
                      }
                      Text {
                        textFormat: Text.PlainText
                        width: parent.width
                        text: {
                          var st = root.pinnedStation;
                          if (!st) return "";
                          var meta = Model.streamMeta(st);
                          var where = Model.stationLabel(st);
                          return "YOUR PICK · " + where + (meta !== "" ? " · " + meta : "");
                        }
                        color: Util.alpha(root.fg, 0.55)
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        elide: Text.ElideRight
                      }
                    }
                  }
                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      if (root.pinnedStation) root.playStationFromList(root.pinnedStation);
                    }
                  }
                }

                Flickable {
                  id: stationFlick
                  anchors.left: parent.left
                  anchors.right: parent.right
                  anchors.bottom: parent.bottom
                  anchors.top: pinRow.visible ? pinRow.bottom : parent.top
                  anchors.margins: Style.space(4)
                  contentWidth: width
                  contentHeight: stationCol.implicitHeight
                  clip: true
                  boundsBehavior: Flickable.StopAtBounds
                  interactive: contentHeight > height
                  ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                  Column {
                    id: stationCol
                    width: parent.width
                    Repeater {
                      model: root.displayStations
                      Rectangle {
                        required property var modelData
                        width: stationCol.width
                        height: Style.space(40)
                        radius: Style.cornerRadius
                        color: (root.currentStation && modelData.uuid === root.currentStation.uuid)
                          ? Style.selectedFillFor(root.fg, Color.accent)
                          : (stHover.containsMouse ? Style.hoverFillFor(root.fg, Color.accent) : "transparent")
                        Behavior on color { ColorAnimation { duration: 120 } }

                        Row {
                          anchors.left: parent.left
                          anchors.right: parent.right
                          anchors.leftMargin: Style.space(10)
                          anchors.rightMargin: Style.space(10)
                          anchors.verticalCenter: parent.verticalCenter
                          spacing: Style.space(8)
                          Text {
                            text: (root.currentStation && modelData.uuid === root.currentStation.uuid && root.playing) ? "▶" : "♫"
                            width: Style.space(16)
                            color: (root.currentStation && modelData.uuid === root.currentStation.uuid) ? Color.accent : Util.alpha(root.fg, 0.55)
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.body
                            Behavior on color { ColorAnimation { duration: 200 } }
                          }
                          Column {
                            width: parent.width - Style.space(16) - Style.space(8)
                            spacing: 1
                            Text {
                              textFormat: Text.PlainText
                              width: parent.width
                              text: modelData.name
                              color: root.fg
                              font.family: root.fontFamily
                              font.pixelSize: Style.font.body
                              elide: Text.ElideRight
                            }
                            Text {
                              textFormat: Text.PlainText
                              width: parent.width
                              text: {
                                var meta = Model.streamMeta(modelData);
                                if (root.searching) {
                                  // Worldwide results: show where the station lives.
                                  var loc = Model.stationLabel(modelData);
                                  return meta !== "" ? loc + " · " + meta : loc;
                                }
                                return (modelData.state ? modelData.state + " · " : "") + meta;
                              }
                              color: Util.alpha(root.fg, 0.55)
                              font.family: root.fontFamily
                              font.pixelSize: Style.font.caption
                              elide: Text.ElideRight
                            }
                          }
                        }
                        MouseArea {
                          id: stHover
                          anchors.fill: parent
                          hoverEnabled: true
                          cursorShape: Qt.PointingHandCursor
                          onContainsMouseChanged: {
                            // Search results re-sort under a still cursor, so
                            // during a live search rows only highlight.
                            if (containsMouse && root.hoverCommits)
                              root.previewStation(modelData);
                          }
                          onClicked: root.playStationFromList(modelData)
                        }
                      }
                    }
                  }
                }
              }
            }
          }

          // ---- Now playing footer ----
          PanelSeparator { foreground: root.fg }
          Row {
            width: parent.width
            spacing: Style.space(10)

            Button {
              id: playButton
              text: root.playing ? "⏹" : "▶"
              fontSize: Style.font.title
              bordered: true
              tooltipText: root.playing ? "Stop" : "Play"
              anchors.verticalCenter: parent.verticalCenter
              onClicked: {
                if (root.playing) root.stopPlayback();
                else if (root.currentStation) root.playStation(root.currentStation);
                else if (root.stations.length > 0) root.playStation(root.stations[0]);
              }
            }
            Column {
              // Size against the row's fixed-width siblings instead of a
              // guessed button width: the garden button carries text and is
              // wider than an icon button, which used to push it past the
              // clipped right edge of the panel.
              width: Math.max(Style.space(80),
                              parent.width - playButton.implicitWidth - muteButton.implicitWidth
                              - volSlider.width - gardenButton.implicitWidth - Style.space(10) * 4)
              anchors.verticalCenter: parent.verticalCenter
              spacing: 2
              Text {
                textFormat: Text.PlainText
                width: parent.width
                text: root.buffering ? ("Tuning… " + (root.currentStation ? root.currentStation.name : "")) : root.nowPlayingText
                color: root.fg
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: root.playing
                elide: Text.ElideRight
              }
              Text {
                textFormat: Text.PlainText
                width: parent.width
                text: root.errorText !== "" ? root.errorText : root.statusText
                color: root.errorText !== "" ? Color.urgent : Util.alpha(root.fg, 0.6)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }
            }
            Button {
              id: muteButton
              text: root.muted ? "󰝟" : "󰕾"
              fontSize: Style.font.title
              bordered: false
              tooltipText: root.muted ? "Unmute" : "Mute"
              anchors.verticalCenter: parent.verticalCenter
              onClicked: root.muted = !root.muted
            }
            PanelSlider {
              id: volSlider
              width: Style.space(120)
              anchors.verticalCenter: parent.verticalCenter
              bar: root.bar
              value: root.volume
              onMoved: function (v) {
                root.volume = v;
                if (v > 0) root.muted = false;
              }
              onReleased: function (v) {
                root.persistSettings({ hoverPlay: root.hoverPlay, volume: v });
              }
            }
            Button {
              id: gardenButton
              text: "garden ↗"
              fontSize: Style.font.caption
              bordered: true
              tooltipText: "Open radio.garden in browser"
              anchors.verticalCenter: parent.verticalCenter
              onClicked: if (root.bar) root.bar.run("xdg-open 'https://radio.garden'")
            }
          }

          Item { width: parent.width; height: Style.space(2) }
        }
      }
    }
  }
}
