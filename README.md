# World Radio for Omarchy

A spinning world globe in the Omarchy top bar. Click for a big globe of
every country — hovering a country, city, or town plays live radio from
there.

## Features

- **Bar widget** — globe glyph next to Weather; lights up while playing.
  Left-click opens the globe, right-click stops, middle-click opens
  [radio.garden](https://radio.garden).
- **Big globe popup** — orthographic spinning globe with all ~250
  countries from [radio-browser.info](https://www.radio-browser.info) as
  dots sized by station count. Drag to spin by hand.
- **Hover-to-play** — hovering a globe dot, country row, or station row
  tunes in live radio (toggleable; when off, playback is click-only).
- Searchable country list, per-country live station list
  (city/state, codec, bitrate, language), volume + mute, now-playing
  footer.
- Fully theme-reactive: every color comes from Omarchy's `Color`/`Style`
  singletons, so theme switches restyle the plugin live.

## Install

```bash
omarchy plugin add https://github.com/kaibur02/omarchy-world-radio --enable --yes
```

The widget lands in the bar's `center` section. To place it right after
Weather:

```bash
omarchy bar move world-radio --after omarchy.weather
```

## Requirements

- Omarchy with the Quickshell shell (`omarchy-shell`)
- Internet access (station directory + streams via radio-browser.info)

## Files

| File          | What                         |
|---------------|------------------------------|
| `manifest.json` | Omarchy plugin manifest    |
| `Widget.qml`  | Bar widget + globe popup     |
| `Globe.qml`   | Canvas orthographic globe    |
| `Model.js`    | Country coordinates + API helpers |

## IPC

The widget exposes the `world-radio` IPC target:

```bash
omarchy-shell world-radio toggle   # open/close the globe
omarchy-shell world-radio stop     # stop playback
omarchy-shell world-radio status   # JSON: hoverPlay, playing, selection…
```

## License

MIT — see [LICENSE](LICENSE).
