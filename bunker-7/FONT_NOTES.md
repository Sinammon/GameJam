# Font notes

**Pixelify Sans** (variable TTF, copyright 2021 The Pixelify Sans Project Authors, https://github.com/eifetx/Pixelify-Sans),
licensed under the SIL Open Font License 1.1. Files: `fonts/PixelifySans.ttf` (79 KB), license text `fonts/OFL.txt`
(added to the export `include_filter` so it ships with every build). Source: google/fonts, `ofl/pixelifysans`.

## How it is wired
- `project.godot` `[gui] theme/custom_font` makes it the default font of every Label, Button, RichTextLabel and also
  `ThemeDB.fallback_font` (the HUD's `draw_string` text uses that).
- `fonts/PixelifySans.ttf.import`: antialiasing 0 (none), hinting 0 (none), subpixel positioning 0 (disabled), MSDF off,
  mipmaps off. The matching `theme/default_font_*` project settings are set too.
- The font is drawn on a 10-unit pixel grid, so it is crisp at sizes that are whole multiples of 10 (or of 5 on a
  2x/4x window). `UIKit.fs(size)` in `scenes/ui_kit.gd` snaps every requested size to 10 / 15 / 20 / 30 / 50;
  `UIKit.label`, `UIKit.outlined` and `UIKit.button` call it, so scenes keep passing their old sizes (7-48) and get
  snapped ones. Anything that sets a `font_size` or calls `draw_string` itself should wrap the size in `UIKit.fs()`.
- Outline on `UIKit.outlined` text is 2 px (3 px smudged the 1 px strokes).
- Export: `all_resources` already includes the TTF (imported `.fontdata`); the excludes (`tools/*`, `art_tools/*`, `*.md`)
  do not touch `fonts/`.
