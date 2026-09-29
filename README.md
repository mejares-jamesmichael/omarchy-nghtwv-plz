# nghtwv-plz for Omarchy

A lightweight Omarchy bar widget for [Nightwave Plaza](https://plaza.one/), the continuously running vaporwave and future funk station. Playback runs in `mpv` and is available to Omarchy's media controls through `mpv-mpris`.

## Install

```sh
omarchy plugin add https://github.com/mejares-jamesmichael/omarchy-nghtwv-plz.git --enable
```

Requires `mpv` and Python 3. `mpv-mpris` is recommended for desktop media controls.

## Controls

- Left click the bar widget to open the NGHTWV-PLZ mini-OS window: live track with artwork, progress, transport controls, volume, and recent transmissions.
- Middle click to pause/resume playback without opening the window.
- Right click to stop playback.
- Scroll over the widget to adjust volume.
- Inside the window: `Space` toggles playback, `+`/`-` adjust volume, `Esc` closes.
- The speaker button in the window picks the audio output (e.g. Bluetooth headset vs. built-in audio) without restarting playback; the choice is remembered across restarts.
- Bind a key to open the window from anywhere: `omarchy-shell shell toggle kaelvxdev.nghtwv-plz`.
- Use Omarchy's media controls or `playerctl` for standard playback controls.

The widget reads the stream title from mpv and refreshes track/listener details from Plaza's status endpoint when available. The MP3 stream is `https://radio.plaza.one/mp3`; the status endpoint is `https://api.plaza.one/status`. Playback continues when Plaza's status service is unavailable.

## Remove

Stop the player and remove the plugin:

```sh
~/.config/omarchy/plugins/kaelvxdev.nghtwv-plz/plaza-player stop
omarchy plugin remove kaelvxdev.nghtwv-plz
```
