#!/usr/bin/env python3
"""Bunker 7 art cleaner (Coder 2).

Turns the artists' raw ChatGPT PNGs into game-ready pixel art:
  * magenta (or flat-colour) background -> real transparency, halos removed
  * sprite / icon / button sheets split into single PNGs (connected components)
  * animation frames share one canvas size and one bottom baseline
  * everything downscaled to game size with a block-median (no blur, no smoothing)
  * full scenes (rooms, title, endings, sky, city layers) are resized, never trimmed

Needs: python3 + Pillow + numpy  (pip3 install --user pillow numpy)

Usage (from the bunker-7 folder):
  python3 art_tools/clean_art.py --chars <folder with character PNGs> --world <folder with world PNGs>
  python3 art_tools/clean_art.py ... --only BedRoom.png     # one file
Outputs: art/characters_clean/, art/world_clean/ and art/ART_INDEX.md (originals never modified).
"""
import argparse
import os
import sys
from collections import deque

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ART = os.path.normpath(os.path.join(HERE, "..", "art"))

# --------------------------------------------------------------------------- config
# kinds:
#   full   : whole picture resized to `size` (no trim). key=True removes magenta first.
#   single : one object, trimmed, scaled by `h` (height) or `box` (fit inside w,h).
#   sheet  : N objects split by connected components, named `names`.
#            anim=True -> same scale for all, shared canvas, bottom baseline.
#            h = target height of the TALLEST frame (anim) ; box/boxes = fit each item.
#   tiles  : N square tiles -> `tile` px each, plus a 4-wide atlas.
#   panels : full pictures on a flat background colour (event thumbnails).
SURV = ["survivor_%s" % s for s in ("idle", "walk", "jump", "mine", "hurt", "collapse")]
CHARS = {
    "survivor_idle.png.png": dict(kind="sheet", out="survivor_idle", n=4, anim=True, h=32),
    "survivor_idle.png":     dict(kind="sheet", out="survivor_idle", n=4, anim=True, h=32),
    "survivor_walk.png":     dict(kind="sheet", out="survivor_walk", n=4, anim=True, h=32),
    "survivor_jump.png":     dict(kind="sheet", out="survivor_jump", n=4, anim=True, h=33),
    "survivor_mine.png":     dict(kind="sheet", out="survivor_mine", n=4, anim=True, h=36),
    "survivor_hurt.png":     dict(kind="sheet", out="survivor_hurt", n=2, anim=True, h=32),
    "survivor_collapse.png": dict(kind="sheet", out="survivor_collapse", n=4, anim=True, h=32),
    "wakeup.png":            dict(kind="sheet", out="survivor_wakeup", n=4, anim=True, h=32),
    "survivor_wakeup.png":   dict(kind="sheet", out="survivor_wakeup", n=4, anim=True, h=32),
    "survivor_concept.png":  dict(kind="single", out="survivor_concept", h=64),
    "rat_concept.png":       dict(kind="single", out="rat_concept", h=40),
    "rat_run.png":           dict(kind="sheet", out="rat_run", n=4, anim=True, h=13),
    "raider_concept.png":    dict(kind="single", out="raider_concept", h=64),
    "raider_walk.png":       dict(kind="sheet", out="raider_walk", n=4, anim=True, h=33),
    "raider_attack.png":     dict(kind="sheet", out="raider_attack", n=3, anim=True, h=33),
    "drone_concept.png":     dict(kind="single", out="drone_concept", h=48),
    "drone_hover.png":       dict(kind="sheet", out="drone_hover", n=3, anim=True, h=24),
    "dog_concept.png":       dict(kind="single", out="dog_concept", h=48),
    "dog_run.png":           dict(kind="sheet", out="dog_run", n=4, anim=True, h=18),
    "portrait_survivor.png": dict(kind="sheet", n=3, h=48, anim=True,
                                  names=["portrait_survivor_neutral", "portrait_survivor_hurt", "portrait_survivor_happy"]),
    "portrait_radio.png":    dict(kind="single", out="portrait_radio", h=64),
    "title_art.png":         dict(kind="full", out="title_art", size=(480, 270)),
    "ending_rescue.png":     dict(kind="full", out="ending_rescue", size=(480, 270)),
    "ending_alone.png":      dict(kind="full", out="ending_alone", size=(480, 270)),
    "game_over.png":         dict(kind="full", out="game_over", size=(480, 270)),
}
ROOM = (234, 78)     # one bunker room cell in the bunker screen
BG = (810, 270)      # parallax layers: 270 px tall like the viewport
WORLD = {
    "BedRoom.png":     dict(kind="full", out="room_bedroom", size=ROOM),
    "UtilityRoom.png": dict(kind="full", out="room_utility", size=ROOM),
    "Storage.png":     dict(kind="full", out="room_garden", size=ROOM),    # hooks for grow lamps + trays
    "Storage2.png":    dict(kind="full", out="room_storage", size=ROOM),   # shelves + crates
    "Radio.png":       dict(kind="full", out="room_radio", size=ROOM),
    "Locked.png":      dict(kind="full", out="room_locked", size=ROOM),
    "DamagedRoom.png": dict(kind="full", out="room_damaged_overlay", size=ROOM, key=True),
    "Bunker.png":      dict(kind="full", out="bunker_overview", size=(480, 160)),
    "SunsetSky.png":   dict(kind="full", out="bg_sky", size=BG),
    "FarCityLine.png": dict(kind="full", out="bg_far", size=BG, key=True),
    "Ruins.png":       dict(kind="full", out="bg_near_suburb", size=BG, key=True),
    "GasStation.png":  dict(kind="full", out="bg_near_market", size=BG, key=True),
    "MilitaryBase.png": dict(kind="full", out="bg_near_depot", size=BG, key=True),
    "Outside ground.png": dict(kind="tiles", out="tiles_outside", n=8, tile=16,
                               names=["dirt", "dirt_grass", "stone", "asphalt", "rubble", "gravel", "dirt_scrap", "dirt_toxic"]),
    "Build.png":       dict(kind="tiles", out="tiles_bunker", n=8, tile=16,
                            names=["concrete_wall", "concrete_floor", "steel_plate", "pipe_wall", "wood_planks", "brick_damaged", "cave_dark", "dirt_packed"]),
    "IconStatus.png":  dict(kind="sheet", n=6, box=(16, 16),
                            names=["icon_health", "icon_radiation", "icon_bounce", "icon_day", "icon_medkit", "icon_locked"]),
    "Resources.png":   dict(kind="sheet", n=6, box=(16, 16),
                            names=["icon_wood", "icon_concrete", "icon_scrap", "icon_water", "icon_food", "icon_circuits"]),
    "PickUpItems.png": dict(kind="sheet", n=8, box=(16, 16),
                            names=["pickup_wood", "pickup_concrete", "pickup_scrap", "pickup_water", "pickup_food", "pickup_circuits", "pickup_medkit", "pickup_sparkle"]),
    "WorldResources.png": dict(kind="sheet", n=6,
                               boxes=[(16, 16), (16, 16), (32, 32), (32, 12), (14, 28), (22, 22)],
                               names=["obj_crate_closed", "obj_crate_open", "obj_hatch", "obj_puddle", "obj_sign", "obj_last_stand_pack"]),
    "MachineAndFurniture.png": dict(kind="sheet", n=6,
                                    boxes=[(32, 32), (32, 32), (20, 32), (20, 48), (32, 32), (32, 16)],
                                    names=["bld_purifier", "bld_garden", "bld_filter", "bld_door", "bld_radio", "bld_cot"]),
    "Scars.png":       dict(kind="sheet", n=5, box=(24, 24),
                            names=["scar_thick_skin", "scar_scavenger", "scar_light_feet", "scar_iron_gut", "scar_steady"]),
    "PanelButtons.png": dict(kind="sheet", n=5, factor=1 / 7.0, dilate=1, order="ui",
                             names=["ui_panel", "ui_button_normal", "ui_button_pressed", "ui_bar_frame", "ui_slot"]),
    "ThumbNail.png":   dict(kind="panels", grid=(3, 2), size=(88, 64),
                            names=["event_raiders", "event_storm", "event_pipe", "event_stranger", "event_rats", "event_quiet"]),
}

# --------------------------------------------------------------------------- pixels

def magness(rgb):
    """How magenta a pixel is: min(R,B) - G (pure #FF00FF = 255)."""
    r, g, b = rgb[..., 0].astype(int), rgb[..., 1].astype(int), rgb[..., 2].astype(int)
    return np.minimum(r, b) - g


def is_magenta_bg(rgb):
    m = magness(rgb)
    return (m > 70) & (rgb[..., 0] > 110) & (rgb[..., 2] > 110)


def detect_background(rgb):
    """'magenta', ('flat', colour) or 'none' from the border pixels."""
    border = np.concatenate([rgb[0], rgb[-1], rgb[:, 0], rgb[:, -1]]).astype(int)
    if is_magenta_bg(border[None])[0].mean() > 0.6:
        return "magenta", None
    med = np.median(border, axis=0)
    if (np.abs(border - med).max(axis=1) < 24).mean() > 0.8:
        return "flat", med
    return "none", None


def alpha_mask(rgb, bg, colour=None):
    if bg == "magenta":
        return ~is_magenta_bg(rgb)
    if bg == "flat":
        return np.abs(rgb.astype(int) - colour).max(axis=2) > 28
    return np.ones(rgb.shape[:2], bool)


def resample(rgb, mask, out_w, out_h):
    """Block-median downscale: each output pixel = median colour of the opaque source
    pixels in its block, opaque if at least half of the block is. No blur across blocks."""
    h, w = mask.shape
    sx, sy = w / out_w, h / out_h
    k = int(max(3, min(7, round(max(sx, sy)))))
    offs = (np.arange(k) + 0.5) / k
    xs = np.clip(((np.arange(out_w)[:, None] + offs[None]) * sx).astype(int), 0, w - 1)   # out_w,k
    ys = np.clip(((np.arange(out_h)[:, None] + offs[None]) * sy).astype(int), 0, h - 1)   # out_h,k
    Y = ys[:, None, :, None]
    X = xs[None, :, None, :]
    samp = rgb[Y, X].astype(float).reshape(out_h, out_w, k * k, 3)
    m = mask[Y, X].reshape(out_h, out_w, k * k)
    samp[~m] = np.nan
    with np.errstate(all="ignore"):
        import warnings
        warnings.simplefilter("ignore")
        col = np.nanmedian(samp, axis=2)
    a = m.mean(axis=2) >= 0.5
    col = np.nan_to_num(col)
    return np.clip(np.round(col), 0, 255).astype(np.uint8), a


def defringe(rgb, a):
    """Remove magenta halos left on edges; recolour magenta-tinted inner pixels."""
    rgb = rgb.copy()
    a = a.copy()
    for _ in range(2):
        m = magness(rgb)
        pad = np.pad(a, 1, constant_values=False)
        edge = a & ~(pad[:-2, 1:-1] & pad[2:, 1:-1] & pad[1:-1, :-2] & pad[1:-1, 2:])
        a[edge & (m > 25)] = False
    m = magness(rgb)
    bad = a & (m > 40)
    for y, x in zip(*np.nonzero(bad)):
        ys, xs = slice(max(0, y - 1), y + 2), slice(max(0, x - 1), x + 2)
        nb = rgb[ys, xs][a[ys, xs] & (magness(rgb[ys, xs]) <= 40)]
        if len(nb):
            rgb[y, x] = np.median(nb, axis=0)
        else:
            a[y, x] = False
    return rgb, a


def untint(rgb, a):
    """Smoke/haze painted over magenta comes out purple: turn it into warm grey haze."""
    c = rgb.astype(float)
    r, g, b = c[..., 0], c[..., 1], c[..., 2]
    tinted = a & (r > 90) & (b - g > 8) & (b > 0.4 * r)
    lum = 0.3 * r + 0.59 * g + 0.11 * b
    for i, f in enumerate((1.1, 0.9, 0.75)):
        c[..., i] = np.where(tinted, lum * f, c[..., i])
    return np.clip(np.round(c), 0, 255).astype(np.uint8)


def to_image(rgb, a):
    out = np.zeros(rgb.shape[:2] + (4,), np.uint8)
    out[..., :3] = rgb
    out[..., 3] = np.where(a, 255, 0)
    out[~a, :3] = 0
    return Image.fromarray(out, "RGBA")


def bbox(a):
    ys, xs = np.nonzero(a)
    if len(ys) == 0:
        return 0, 0, a.shape[1], a.shape[0]
    return xs.min(), ys.min(), xs.max() + 1, ys.max() + 1

# --------------------------------------------------------------------------- splitting

def components(mask, n, coarse=4, dilate=3, min_area=40):
    """Connected components on a coarse, dilated mask, merged down to n groups.
    Returns full-res boxes (x0,y0,x1,y1) sorted in reading order."""
    h, w = mask.shape
    ch, cw = (h + coarse - 1) // coarse, (w + coarse - 1) // coarse
    pm = np.zeros((ch * coarse, cw * coarse), bool)
    pm[:h, :w] = mask
    c = pm.reshape(ch, coarse, cw, coarse).mean(axis=(1, 3)) > 0.25
    d = c.copy()
    for _ in range(dilate):
        p = np.pad(d, 1)
        d = p[1:-1, 1:-1] | p[:-2, 1:-1] | p[2:, 1:-1] | p[1:-1, :-2] | p[1:-1, 2:]
    lab = np.zeros(d.shape, int)
    boxes = []
    cur = 0
    for sy, sx in zip(*np.nonzero(d)):
        if lab[sy, sx]:
            continue
        cur += 1
        q = deque([(sy, sx)])
        lab[sy, sx] = cur
        x0 = x1 = sx
        y0 = y1 = sy
        area = 0
        while q:
            y, x = q.popleft()
            area += 1
            x0, x1, y0, y1 = min(x0, x), max(x1, x), min(y0, y), max(y1, y)
            for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
                if 0 <= ny < d.shape[0] and 0 <= nx < d.shape[1] and d[ny, nx] and not lab[ny, nx]:
                    lab[ny, nx] = cur
                    q.append((ny, nx))
        if area >= min_area:
            boxes.append([x0, y0, x1 + 1, y1 + 1, area])
    # merge closest boxes until n remain (small bits like sparkles join their owner)
    def gap(a, b):
        dx = max(0, max(a[0], b[0]) - min(a[2], b[2]))
        dy = max(0, max(a[1], b[1]) - min(a[3], b[3]))
        return (dx * dx + dy * dy) ** 0.5 / (min(a[4], b[4]) ** 0.25)
    while len(boxes) > n:
        best = None
        for i in range(len(boxes)):
            for j in range(i + 1, len(boxes)):
                g = gap(boxes[i], boxes[j])
                if best is None or g < best[0]:
                    best = (g, i, j)
        _, i, j = best
        a, b = boxes[i], boxes[j]
        boxes[i] = [min(a[0], b[0]), min(a[1], b[1]), max(a[2], b[2]), max(a[3], b[3]), a[4] + b[4]]
        del boxes[j]
    if len(boxes) != n:
        print("   WARNING: found %d parts, expected %d" % (len(boxes), n))
    # undo dilation, go back to full res, then tighten on the real mask
    out = []
    for x0, y0, x1, y1, _ in boxes:
        X0, Y0 = max(0, (x0 + dilate) * coarse - coarse), max(0, (y0 + dilate) * coarse - coarse)
        X1, Y1 = min(w, (x1 - dilate) * coarse + coarse), min(h, (y1 - dilate) * coarse + coarse)
        sub = mask[Y0:Y1, X0:X1]
        bx0, by0, bx1, by1 = bbox(sub)
        out.append((X0 + bx0, Y0 + by0, X0 + bx1, Y0 + by1))
    # reading order: rows (by vertical overlap) then x
    out.sort(key=lambda b: (b[1] + b[3]) / 2)
    rows = []
    for b in out:
        if rows and (b[1] + b[3]) / 2 < rows[-1][0]:
            rows[-1][1].append(b)
            rows[-1][0] = max(rows[-1][0], b[3])
        else:
            rows.append([b[3], [b]])
    ordered = []
    for _, r in rows:
        ordered += sorted(r, key=lambda b: b[0])
    return ordered

def order_ui_parts(rgb, boxes):
    """PanelButtons sheet: [panel, button_normal, button_pressed, bar_frame, slot] by shape."""
    area = lambda b: (b[2] - b[0]) * (b[3] - b[1])
    aspect = lambda b: (b[2] - b[0]) / max(1, b[3] - b[1])
    rest = sorted(boxes, key=area)
    slot = min(rest, key=lambda b: abs(aspect(b) - 1)); rest.remove(slot)
    panel = max(rest, key=area); rest.remove(panel)
    bar = max(rest, key=aspect); rest.remove(bar)
    bright = lambda b: rgb[b[1]:b[3], b[0]:b[2]].mean()
    normal, pressed = sorted(rest, key=bright, reverse=True)
    return [panel, normal, pressed, bar, slot]

# --------------------------------------------------------------------------- processing

def scaled_piece(rgb, mask, box, scale):
    x0, y0, x1, y1 = box
    ow, oh = max(1, round((x1 - x0) * scale)), max(1, round((y1 - y0) * scale))
    c, a = resample(rgb[y0:y1, x0:x1], mask[y0:y1, x0:x1], ow, oh)
    c, a = defringe(c, a)
    return c, a


def trim(c, a):
    x0, y0, x1, y1 = bbox(a)
    return c[y0:y1, x0:x1], a[y0:y1, x0:x1]


def fit_scale(box, w, h):
    return min(w / (box[2] - box[0]), h / (box[3] - box[1]))


def save(img, folder, name, index):
    os.makedirs(folder, exist_ok=True)
    path = os.path.join(folder, name + ".png")
    img.save(path, optimize=True)
    index.append((os.path.relpath(path, ART), img.size, CURRENT_SOURCE[0]))
    return path


CURRENT_SOURCE = [""]


def process(path, cfg, folder, index):
    CURRENT_SOURCE[0] = os.path.basename(path)
    rgb = np.array(Image.open(path).convert("RGB"))
    bg, colour = detect_background(rgb)
    kind = cfg["kind"]
    print("%-26s %-6s bg=%s" % (os.path.basename(path), kind, bg))

    if kind == "full":
        mask = alpha_mask(rgb, bg) if cfg.get("key") and bg == "magenta" else np.ones(rgb.shape[:2], bool)
        if cfg.get("key") and bg != "magenta":   # e.g. magenta sky only at the top
            mask = ~is_magenta_bg(rgb)
        c, a = resample(rgb, mask, *cfg["size"])
        if cfg.get("key"):
            c, a = defringe(c, a)
            c = untint(c, a)
        save(to_image(c, a), folder, cfg["out"], index)
        return

    if kind == "panels":
        # a regular grid of filled pictures (cols x rows) separated by thin frame lines
        cols, rows = cfg["grid"]
        H, W = rgb.shape[:2]
        for i, name in enumerate(cfg["names"]):
            cx, cy = i % cols, i // cols
            x0, x1 = W * cx // cols, W * (cx + 1) // cols
            y0, y1 = H * cy // rows, H * (cy + 1) // rows
            ix, iy = (x1 - x0) * 3 // 100, (y1 - y0) * 3 // 100   # drop the frame line
            sub = rgb[y0 + iy:y1 - iy, x0 + ix:x1 - ix]
            c, a = resample(sub, np.ones(sub.shape[:2], bool), *cfg["size"])
            save(to_image(c, a), folder, name, index)
        return

    mask = alpha_mask(rgb, bg)
    if kind == "single":
        box = bbox(mask)
        scale = cfg["h"] / (box[3] - box[1]) if "h" in cfg else fit_scale(box, *cfg["box"])
        c, a = trim(*scaled_piece(rgb, mask, box, scale))
        save(to_image(c, a), folder, cfg["out"], index)
        return

    if kind == "tiles":
        boxes = components(mask, cfg["n"], dilate=1)
        t = cfg["tile"]
        atlas = Image.new("RGBA", (t * 4, t * ((cfg["n"] + 3) // 4)), (0, 0, 0, 0))
        for i, (name, (x0, y0, x1, y1)) in enumerate(zip(cfg["names"], boxes)):
            # cut inside the dark tile outline so tiles repeat without a grid line
            ix, iy = (x1 - x0) // 14, (y1 - y0) // 14
            sub = rgb[y0 + iy:y1 - iy, x0 + ix:x1 - ix]
            c, a = resample(sub, mask[y0 + iy:y1 - iy, x0 + ix:x1 - ix], t, t)
            c, a = defringe(c, a)
            img = to_image(c, a)
            save(img, folder, "%s_%s" % (cfg["out"], name), index)
            atlas.paste(img, ((i % 4) * t, (i // 4) * t))
        save(atlas, folder, cfg["out"], index)
        return

    # sheet
    n = cfg["n"]
    boxes = components(mask, n, dilate=cfg.get("dilate", 3))
    if cfg.get("order") == "ui":
        boxes = order_ui_parts(rgb, boxes)
    names = cfg.get("names") or ["%s_%d" % (cfg["out"], i) for i in range(len(boxes))]
    if cfg.get("anim"):
        tallest = max(b[3] - b[1] for b in boxes)
        scale = cfg["h"] / tallest
        pieces = [trim(*scaled_piece(rgb, mask, b, scale)) for b in boxes]
        W = max(p[0].shape[1] for p in pieces)
        H = max(p[0].shape[0] for p in pieces)
        for name, (c, a) in zip(names, pieces):
            canvas = Image.new("RGBA", (W, H), (0, 0, 0, 0))
            img = to_image(c, a)
            canvas.paste(img, ((W - img.width) // 2, H - img.height))   # bottom baseline, centred
            save(canvas, folder, name, index)
        strip = Image.new("RGBA", (W * len(pieces), H), (0, 0, 0, 0))
        for i, (c, a) in enumerate(pieces):
            img = to_image(c, a)
            strip.paste(img, (i * W + (W - img.width) // 2, H - img.height))
        if "out" in cfg:
            save(strip, folder, cfg["out"] + "_strip", index)
        return
    for i, (name, b) in enumerate(zip(names, boxes)):
        if "factor" in cfg:
            scale = cfg["factor"]
        else:
            bw, bh = cfg["boxes"][i] if "boxes" in cfg else cfg["box"]
            scale = fit_scale(b, bw, bh)
        c, a = trim(*scaled_piece(rgb, mask, b, scale))
        save(to_image(c, a), folder, name, index)


def check_outputs(folders):
    bad = 0
    for folder in folders:
        for f in sorted(os.listdir(folder)):
            if not f.endswith(".png"):
                continue
            arr = np.array(Image.open(os.path.join(folder, f)).convert("RGBA"))
            vis = arr[..., 3] > 0
            mag = (magness(arr[..., :3]) > 60) & vis
            if mag.sum():
                bad += 1
                print("   magenta left in %s: %d px" % (f, mag.sum()))
    print("magenta check: %s" % ("OK, no magenta pixels left" if not bad else "%d files with magenta" % bad))


def write_index(index):
    lines = ["# Art index (generated by art_tools/clean_art.py)", "",
             "Cleaned, game-size pixel art. Raw artist PNGs are not in the repo (too big); re-run the script on them.",
             "Animation frames of one sheet share one canvas size and a bottom baseline;",
             "`*_strip.png` is the same frames side by side (for SpriteFrames / AtlasTexture).",
             "Rooms are 234x78 (one bunker room cell), full screens 480x270, parallax layers 810x270.",
             "", "| file | size (px) | from raw file |", "|---|---|---|"]
    for rel, (w, h), src in sorted(index):
        lines.append("| %s | %dx%d | %s |" % (rel, w, h, src))
    with open(os.path.join(ART, "ART_INDEX.md"), "w") as f:
        f.write("\n".join(lines) + "\n")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--chars", required=True, help="folder with the character PNGs")
    ap.add_argument("--world", required=True, help="folder with the world PNGs")
    ap.add_argument("--only", default="", help="process just this source file name")
    args = ap.parse_args()
    index = []
    for src, table, sub in ((args.chars, CHARS, "characters_clean"), (args.world, WORLD, "world_clean")):
        folder = os.path.join(ART, sub)
        for f in sorted(os.listdir(src)):
            if not f.lower().endswith(".png") or (args.only and f != args.only):
                continue
            if f not in table:
                print("skip (no rule): %s" % f)
                continue
            process(os.path.join(src, f), table[f], folder, index)
    if not args.only:
        write_index(index)
    check_outputs([os.path.join(ART, "characters_clean"), os.path.join(ART, "world_clean")])


if __name__ == "__main__":
    sys.exit(main())
