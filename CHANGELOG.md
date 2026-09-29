# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.1] - 2026-09-29

Patch release: fixes the playing-state icon and the window title.

### Fixed

- **Playing-state icon**: the bar widget and window titlebar now show a
  vinyl-record glyph (U+F0960) while the stream plays, keeping the crescent
  moon for idle and paused. The previous codepoint never rendered as
  intended: a QML `\u` escape takes exactly four hex digits, so `\uf011b` parsed as U+F011 (power symbol) plus a
  literal "b". Astral-plane codepoints (above U+FFFF) must be written
  as UTF-16 surrogate pairs (`\udb82\udd60` for U+F0960).
- **Window title**: the panel titlebar now reads `NGHTWV-PLZ — player`.

## [1.0.0] - 2026-09-29

First stable release. The plugin is feature-complete: bar widget, mini-OS
window, audio output selection, and hardened playback.

### Added

- **Mini-OS window** (`PlazaPanel.qml`): a centered floating window summoned
  from the bar widget, showing album artwork, track/artist/album, listener
  count, an extrapolated progress bar, transport controls, a volume slider,
  and a log of recent transmissions. Keyboard: `Space` toggles playback,
  `+`/`-` adjust volume, `Esc` closes.
- **Audio output picker**: a speaker button lists PipeWire sinks and re-routes
  `mpv` live through `set_property audio-device`, with no playback restart.
  The choice is remembered in `settings.json` and re-applied at launch when the
  sink still exists, falling back to the system default otherwise.
- **Rich track metadata**: `plaza-player metadata` now returns artist, track,
  album, artwork URL, track length, and position alongside the listener count.
- **Transmission log**: `plaza-player history` reads Plaza's history endpoint
  and returns the ten most recent tracks with timestamps.
- **Window centering**: `nightwave-window` registers a float-and-center
  Hyprland rule for the panel window, degrading gracefully on setups without
  the lua config provider.

### Changed

- **Bar and window iconography**: a crescent moon when idle or paused, a cat
  head while playing, and the same cat as the no-artwork placeholder.
- **Bar interaction**: left click opens the window, middle click toggles
  playback directly, right click stops, scroll adjusts volume.
- The plugin is published under the namespaced id `kaelvxdev.nghtwv-plz`, and
  the manifest homepage now points at this repository.

### Fixed

- **Stillborn `mpv` processes**: an unreachable stream could hang `mpv` on
  connect indefinitely, so every play attempt spawned another zombie and stop
  did nothing. Added `--network-timeout=30` so a failed load falls back to
  idle.
- **Zombie stacking**: `launch()` now runs the stale-socket check and spawn
  under an `flock` on `player.lock`, so rapid clicks produce one `mpv`.
- **Orphaned processes**: `stop()` falls back to SIGTERM for a player whose
  IPC socket is dead, after verifying the recorded PID's command line belongs
  to this plugin's socket.
- **Stale audio after a stall**: the cache is now bounded
  (`--cache-secs=20 --demuxer-max-bytes=8MiB`), so a network hiccup surfaces
  immediately instead of replaying minutes-old audio.
- **Honest playback state**: `status` reports `buffering` from `mpv`'s
  `paused-for-cache`, and the widget and window show `BUFFERING` (or `IDLE`
  after a failed load) instead of claiming `LIVE` while silent.
- **Glyph rendering**: bar glyphs are now restricted to codepoints present in
  JetBrainsMono Nerd Font, fixing icons that rendered as tofu boxes.

[1.0.1]: https://github.com/mejares-jamesmichael/omarchy-nghtwv-plz/releases/tag/v1.0.1
[1.0.0]: https://github.com/mejares-jamesmichael/omarchy-nghtwv-plz/releases/tag/v1.0.0
