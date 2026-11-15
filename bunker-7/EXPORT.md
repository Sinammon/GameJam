# Exporting Bunker 7

Presets are in `export_presets.cfg`: **Web**, **macOS**, **Windows**. All three export every resource,
add `*.json` (so `data/events.json` is packed: it is read with FileAccess, not as a resource) and
leave out `tools/*`, `art_tools/*` and `*.md`. Output goes to `build/` in the repo root (git-ignored).

## 1. Install the export templates (once, ~1 GB download)
Not installed on this machine yet (`~/Library/Application Support/Godot/export_templates/4.7.2.stable/` is missing).
Editor: **Editor > Manage Export Templates > Download and Install** (pick the official mirror).
Or download `Godot_v4.7.2-stable_export_templates.tpz` from godotengine.org, then
**Manage Export Templates > Install from File**.

## 2. Export (from the repo root)
```sh
G=/Users/yehooor/Downloads/Godot.app/Contents/MacOS/Godot
mkdir -p build/web build/macos build/windows
$G --headless --path bunker-7 --export-release "Web"     ../build/web/index.html
$G --headless --path bunker-7 --export-release "macOS"   ../build/macos/Bunker7.zip
$G --headless --path bunker-7 --export-release "Windows" ../build/windows/Bunker7.exe
```
(Export paths are relative to `bunker-7/`.)

## 3. Check the web build locally
```sh
cd build/web && python3 -m http.server 8000   # open http://localhost:8000
```
For itch.io: zip the *contents* of `build/web/` (index.html at the top level), upload as HTML, set
viewport 960x540 (2x of 480x270) and enable fullscreen button. The Web preset is single-threaded
(`variant/thread_support=false`), so it needs no SharedArrayBuffer / COOP-COEP headers.

## Notes
- Web compatibility checked: no threads, no OS.execute, no file writes (the game only reads
  `res://data/events.json`). Debug keys (ESC, F1, cheats) only work in debug builds.
- macOS build is unsigned: on another Mac, right-click > Open the first time.
- Template-free sanity check: `$G --headless --path bunker-7 --export-pack "Web" ../build/test/bunker7.pck`
  then `$G --headless --main-pack build/test/bunker7.pck` boots the packed game (done: boots with no errors,
  events.json is inside, tools/ are not).
- V3 (survival, Old Mine, Bomb Crater, Crafts / Book) is not exported yet: re-export the Web build and check the
  mine darkness, the book scrolling and the new keys (Q / R) in the browser. No new file writes or threads.
