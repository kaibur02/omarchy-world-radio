// Shared data + math for the World Radio plugin.
// - Country anchor coordinates keyed by radio-browser ISO-3166-1 codes.
// - Orthographic globe projection.
// - radio-browser.info API helpers (mirrors, URL builders, record cleanup).
//
// All colors/styling stay in QML (Color/Style singletons) so theme changes
// flow through automatically. This file holds no colors.

.pragma library

var MIRRORS = [
  "https://de1.api.radio-browser.info",
  "https://de2.api.radio-browser.info",
  "https://nl1.api.radio-browser.info"
];

var UA = "OmarchyWorldRadio/1.0";

// Approximate anchor (capital / population centroid) per ISO code.
// Covers every country radio-browser reports stations for.
var COORDS = {
  "AD": [42.5, 1.5], "AE": [24.4, 54.4], "AF": [34.5, 69.2],
  "AG": [17.1, -61.8], "AL": [41.3, 19.8], "AM": [40.2, 44.5],
  "AO": [-8.8, 13.2], "AQ": [-75.0, 0.0], "AR": [-34.6, -58.4],
  "AT": [48.2, 16.4], "AU": [-35.3, 149.1], "AZ": [40.4, 49.9],
  "BA": [43.9, 18.4], "BB": [13.1, -59.6], "BD": [23.8, 90.4],
  "BE": [50.8, 4.4], "BF": [12.4, -1.5], "BG": [42.7, 23.3],
  "BH": [26.2, 50.6], "BI": [-3.4, 29.4], "BJ": [6.5, 2.6],
  "BN": [4.9, 114.9], "BO": [-16.5, -68.1], "BR": [-15.8, -47.9],
  "BS": [25.1, -77.4], "BT": [27.5, 89.6], "BW": [-24.6, 25.9],
  "BY": [53.9, 27.6], "BZ": [17.5, -88.3], "CA": [45.4, -75.7],
  "CD": [-4.3, 15.3], "CF": [4.4, 18.6], "CG": [-4.3, 15.2],
  "CH": [46.9, 7.4], "CI": [6.8, -5.3], "CL": [-33.4, -70.7],
  "CM": [3.9, 11.5], "CN": [39.9, 116.4], "CO": [4.7, -74.1],
  "CR": [9.9, -84.1], "CU": [23.1, -82.4], "CV": [14.9, -23.5],
  "CY": [35.2, 33.4], "CZ": [50.1, 14.4], "DE": [52.5, 13.4],
  "DJ": [11.6, 43.1], "DK": [55.7, 12.6], "DO": [18.5, -69.9],
  "DZ": [36.8, 3.1], "EC": [-0.2, -78.5], "EE": [59.4, 24.7],
  "EG": [30.0, 31.2], "ER": [15.3, 38.9], "ES": [40.4, -3.7],
  "ET": [9.0, 38.7], "FI": [60.2, 24.9], "FJ": [-18.1, 178.4],
  "FO": [62.0, -6.8], "FR": [48.9, 2.4], "GA": [0.4, 9.5],
  "GB": [51.5, -0.1], "GD": [12.1, -61.7], "GE": [41.7, 44.8],
  "GH": [5.6, -0.2], "GL": [64.2, -51.7], "GM": [13.5, -16.6],
  "GN": [9.5, -13.7], "GQ": [3.8, 8.8], "GR": [38.0, 23.7],
  "GT": [14.6, -90.5], "GW": [11.9, -15.6], "GY": [6.8, -58.2],
  "HK": [22.3, 114.2], "HN": [14.1, -87.2], "HR": [45.8, 16.0],
  "HT": [18.5, -72.3], "HU": [47.5, 19.0], "ID": [-6.2, 106.8],
  "IE": [53.3, -6.3], "IL": [31.8, 35.2], "IN": [28.6, 77.2],
  "IQ": [33.3, 44.4], "IR": [35.7, 51.4], "IS": [64.1, -21.9],
  "IT": [41.9, 12.5], "JM": [18.0, -76.8], "JO": [31.9, 35.9],
  "JP": [35.7, 139.7], "KE": [-1.3, 36.8], "KG": [42.9, 74.6],
  "KH": [11.6, 104.9], "KP": [39.0, 125.8], "KR": [37.6, 127.0],
  "KW": [29.4, 48.0], "KZ": [51.2, 71.4], "LA": [18.0, 102.6],
  "LB": [33.9, 35.5], "LK": [6.9, 79.9], "LR": [6.3, -10.8],
  "LS": [-29.3, 27.5], "LT": [54.7, 25.3], "LU": [49.6, 6.1],
  "LV": [56.9, 24.1], "LY": [32.9, 13.2], "MA": [34.0, -6.8],
  "MC": [43.7, 7.4], "MD": [47.0, 28.9], "ME": [42.4, 19.3],
  "MG": [-18.9, 47.5], "MK": [42.0, 21.4], "ML": [12.6, -8.0],
  "MM": [19.8, 96.2], "MN": [47.9, 106.9], "MR": [18.1, -16.0],
  "MT": [35.9, 14.5], "MU": [-20.2, 57.5], "MV": [4.2, 73.5],
  "MW": [-13.9, 33.8], "MX": [19.4, -99.1], "MY": [3.1, 101.7],
  "MZ": [-25.9, 32.6], "NA": [-22.6, 17.1], "NE": [13.5, 2.1],
  "NG": [9.1, 7.5], "NI": [12.1, -86.3], "NL": [52.4, 4.9],
  "NO": [59.9, 10.7], "NP": [27.7, 85.3], "NZ": [-41.3, 174.8],
  "OM": [23.6, 58.4], "PA": [9.0, -79.5], "PE": [-12.0, -77.0],
  "PG": [-9.5, 147.2], "PH": [14.6, 121.0], "PK": [33.7, 73.1],
  "PL": [52.2, 21.0], "PR": [18.5, -66.1], "PS": [31.9, 35.2],
  "PT": [38.7, -9.1], "PY": [-25.3, -57.6], "QA": [25.3, 51.5],
  "RO": [44.4, 26.1], "RS": [44.8, 20.5], "RU": [55.8, 37.6],
  "RW": [-1.9, 30.1], "SA": [24.7, 46.7], "SD": [15.6, 32.5],
  "SE": [59.3, 18.1], "SG": [1.4, 103.8], "SI": [46.0, 14.5],
  "SK": [48.1, 17.1], "SL": [8.5, -13.2], "SM": [43.9, 12.5],
  "SN": [14.7, -17.4], "SO": [2.0, 45.3], "SR": [5.9, -55.2],
  "SS": [4.9, 31.6], "SV": [13.7, -89.2], "SY": [33.5, 36.3],
  "SZ": [-26.3, 31.1], "TD": [12.1, 15.0], "TG": [6.1, 1.2],
  "TH": [13.8, 100.5], "TJ": [38.6, 68.8], "TM": [37.9, 58.4],
  "TN": [36.8, 10.2], "TR": [39.9, 32.9], "TT": [10.7, -61.5],
  "TW": [25.0, 121.5], "TZ": [-6.8, 39.3], "UA": [50.4, 30.5],
  "UG": [0.3, 32.6], "US": [38.9, -77.0], "UY": [-34.9, -56.2],
  "UZ": [41.3, 69.2], "VA": [41.9, 12.5], "VE": [10.5, -66.9],
  "VN": [21.0, 105.8], "XK": [42.7, 21.2], "YE": [15.4, 44.2],
  "ZA": [-25.7, 28.2], "ZM": [-15.4, 28.3], "ZW": [-17.8, 31.0]
};

// Deterministic pseudo-position for the few ISO codes missing above, so
// every API country still lands somewhere on the globe instead of vanishing.
function fallbackCoord(iso) {
  var h = 0;
  var s = String(iso || "?");
  for (var i = 0; i < s.length; i++)
    h = ((h * 31) + s.charCodeAt(i)) >>> 0;
  var lat = (h % 140) - 60;             // -60..80
  var lon = ((h >> 8) % 360) - 180;     // -180..180
  return [lat, lon];
}

function coordFor(iso) {
  var c = COORDS[String(iso || "").toUpperCase()];
  return c ? c : fallbackCoord(iso);
}

var DEG = Math.PI / 180;

// Orthographic projection. Returns {x, y, vis} in canvas pixels.
function project(lat, lon, centerLon, centerLat, cx, cy, r) {
  var la = lat * DEG;
  var lo = (lon - centerLon) * DEG;
  var ca = centerLat * DEG;
  var cosLa = Math.cos(la);
  var x = cosLa * Math.sin(lo);
  var y = Math.cos(ca) * Math.sin(la) - Math.sin(ca) * cosLa * Math.cos(lo);
  var z = Math.sin(ca) * Math.sin(la) + Math.cos(ca) * cosLa * Math.cos(lo);
  return { x: cx + r * x, y: cy - r * y, vis: z > 0.02, z: z };
}

// "THE UNITED STATES OF AMERICA" -> "United States Of America"
function prettyCountry(name) {
  var s = String(name || "").trim();
  if (s.indexOf("The ") === 0) s = s.slice(4);
  return s.replace(/\w\S*/g, function (w) {
    return w.charAt(0).toUpperCase() + w.slice(1).toLowerCase();
  });
}

// radio-browser station record -> slim {uuid,name,url,codec,bitrate,...}
function cleanStation(s) {
  s = s || {};
  var url = String(s.url_resolved || s.url || "").trim();
  // Force https where the host serves it; mixed http streams still play.
  return {
    uuid: String(s.stationuuid || ""),
    name: String(s.name || "Unknown station").trim().slice(0, 80),
    url: url,
    codec: String(s.codec || "").toUpperCase(),
    bitrate: Number(s.bitrate) || 0,
    country: String(s.country || ""),
    countrycode: String(s.countrycode || "").toUpperCase(),
    state: String(s.state || ""),
    language: String(s.language || "").split(",")[0].slice(0, 24),
    votes: Number(s.votes) || 0,
    clicks: Number(s.clickcount) || 0,
    favicon: String(s.favicon || "")
  };
}

function stationLabel(st) {
  if (!st) return "";
  var loc = st.state ? (st.state + ", " + prettyCountry(st.country)) : prettyCountry(st.country);
  return loc;
}

function streamMeta(st) {
  if (!st) return "";
  var bits = [];
  if (st.codec) bits.push(st.codec);
  if (st.bitrate > 0) bits.push(st.bitrate + "k");
  if (st.language) bits.push(st.language);
  return bits.join(" · ");
}

function countriesUrl(base) {
  return base + "/json/countries";
}

function stationsByCountryUrl(base, countryName, limit) {
  return base + "/json/stations/bycountry/" + encodeURIComponent(countryName)
    + "?order=clickcount&reverse=true&limit=" + (limit || 30) + "&hidebroken=true";
}

function topStationsUrl(base, limit) {
  return base + "/json/stations/topclick/" + (limit || 150);
}

function clickUrl(base, uuid) {
  return base + "/json/url/" + uuid;
}
