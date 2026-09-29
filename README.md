# nghtwv-plz for Omarchy

An Omarchy bar widget for [Nightwave Plaza](https://plaza.one/) — the 24/7
vaporwave and future funk station. A crescent moon sits in your bar while
idle, turns into a cat while the stream plays, and opens a mini-OS window
with the live track, artwork, playback controls, and an audio output picker.

<!-- Screenshot: assets/preview.png -->

Playback runs in `mpv`, so the stream shows up in Omarchy's media controls and
in `playerctl`.

## Features

- **Bar widget** — moon when idle, cat when playing, with track, listener
  count, and volume in the tooltip.
- **Mini-OS window** — a centered floating panel with album artwork, an
  extrapolated progress bar, transport controls, a volume slider, and a log of
  the last ten tracks.
- **Audio output picker** — switch between a Bluetooth headset and built-in
  audio without restarting playback. The choice is remembered across restarts.
- **Honest playback state** — a stalled stream shows `BUFFERING` rather than
  claiming to be live, and a failed connection falls back to `IDLE`.
- **Media key support** — works with Omarchy's media controls and `playerctl`.

## Requirements

| Dependency | Required | Notes |
| --- | --- | --- |
| Python 3 | Yes | Standard library only |
| `mpv` | Yes | Audio playback |
| `mpv-mpris` | No | Enables `playerctl` and Omarchy's media controls |
| `pactl` (pipewire-pulse) | No | Audio output picker; degrades gracefully |
| `hyprctl` + lua config | No | Window centering; skipped silently otherwise |

## Install

```sh
omarchy plugin add https://github.com/mejares-jamesmichael/omarchy-nghtwv-plz.git --enable
```

Already installed from a clone? Update it with:

```sh
omarchy plugin update kaelvxdev.nghtwv-plz
```

## Controls

**On the bar widget**

| Input | Action |
| --- | --- |
| Left click | Open the mini-OS window |
| Middle click | Pause/resume without opening the window |
| Right click | Stop playback |
| Scroll | Volume up/down |

**In the window**

| Input | Action |
| --- | --- |
| `Space` | Play/pause |
| `+` / `-` | Volume up/down |
| `Esc` | Close the output menu, then the window |

Bind a key to toggle the window from anywhere:

```lua
o.bind("SUPER + ALT + P", "Nghtwv Plz", "omarchy-shell shell toggle kaelvxdev.nghtwv-plz")
```

## How it works

The bar widget and the window are thin QML front ends over a single
`plaza-player` helper, which is a short-lived Python process per command. The
helper starts and drives one persistent `mpv` through a Unix domain socket at
`$XDG_RUNTIME_DIR/omarchy-nightwave-plaza/mpv.sock`, and reads track
information from Plaza's public API:

- stream: `https://radio.plaza.one/mp3`
- now playing: `https://api.plaza.one/status`
- history: `https://api.plaza.one/history`

No API key is required. If Plaza's API is unreachable, playback continues and
the window simply shows the last known track.

## Troubleshooting

- **No sound, but the widget says playing:** `mpv` is probably still holding a
  disconnected device — the usual cause is a Bluetooth headset sleeping and
  reconnecting. Open the window, press the speaker button, and re-pick the
  output; audio returns without restarting playback. You can check what `mpv`
  sees with `pactl list sink-inputs`: an empty list means it is decoding into
  a void.
- **The window shows `BUFFERING`:** the network stalled. Playback resumes on its
  own once the buffer refills; the cache is deliberately small so this happens
  within seconds instead of playing minutes-old audio.
- **The window is tiled or off-center:** centering is applied by
  `nightwave-window` through Hyprland's lua config provider. On other setups
  the script exits quietly and the compositor places the window; check
  `hyprctl -j status | jq -r .configProvider`.
- **Media controls do not see the stream:** install `mpv-mpris` and confirm
  `playerctl -l` lists MPV during playback.

## Credits and attribution

This is an unofficial, community-made plugin. It is not affiliated with,
endorsed by, or operated by Nightwave Plaza. The stream, artwork, track
metadata, and API belong to [plaza.one](https://plaza.one/).

The floating-window pattern and the audio output handling were modelled on
[Radio Atlas](https://github.com/AksharP5/omarchy-radio-atlas) by Akshar Patel.

## License

[MIT](LICENSE)
