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
  The folders may hold just some of the raws (e.g. the V2 batch in ../art_raw_v2/{chars,world},
  or the V3 batch: --chars ../art_raw_v3 --world ../art_raw_v3, both tables share one folder):
  ART_INDEX.md keeps the rows of files not processed in this run.
Outputs: art/characters_clean/, art/world_clean/ and art/ART_INDEX.md (originals never modified).
tiles_ore.png is built from the three ore sheets together (tiles_ore/2/3.png, see ORE_ATLAS).
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
# Height of the TALLEST frame per sheet, chosen so the figure itself comes out ~32 px like
# survivor_idle (a raised axe / fist / hit marker adds to the tallest frame).
SURV_H = {"chop": 33, "climb": 32, "flash": 32}
ZOMBIE_H = {"walk": 32, "attack": 30, "hurt": 32}
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
    # V2 batch: zombie, axe swing, climbing (seen from behind), flashlight idle. All face right.
    "zombie_walk.png":       dict(kind="sheet", out="zombie_walk", n=4, anim=True, h=ZOMBIE_H["walk"]),
    "Zombie_attack.png":     dict(kind="sheet", out="zombie_attack", n=3, anim=True, h=ZOMBIE_H["attack"]),
    "Zombie_hurt.png":       dict(kind="sheet", out="zombie_hurt", n=2, anim=True, h=ZOMBIE_H["hurt"]),
    "zombie_concept.png":    dict(kind="single", out="zombie_concept", h=64),
    "survivor_chop.png":     dict(kind="sheet", out="survivor_chop", n=4, anim=True, h=SURV_H["chop"]),
    "survivor_climb.png":    dict(kind="sheet", out="survivor_climb", n=4, anim=True, h=SURV_H["climb"]),
    "survivor_flash.png":    dict(kind="sheet", out="survivor_flashlight_idle", n=4, anim=True, h=SURV_H["flash"]),
    # V3 batch: zombie_walk.png above is now the grey-skinned crisp walk (same rule, 32 px).
    # Death: stagger, buckle, fall back, lying flat. Same px scale as the walk (its tallest frame
    # is 516 raw px = 32), so the lying frame comes out long; shared canvas, bottom baseline.
    "zombie_death.png":      dict(kind="sheet", out="zombie_death", n=4, anim=True, scale=ZOMBIE_H["walk"] / 516.0),
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
    # V2 batch. Trees: one file each, sized in 16 px tiles by height (the width follows):
    # dead tree 5 tiles, sapling 3, oak 7, pine 8; stump/bush/logs/branch small props.
    "obj_trees.png":   dict(kind="sheet", n=9, cuts=[284, 470, 795, 1090, 1363, 1582, 1804, 2010],
                            boxes=[(200, h) for h in (80, 48, 112, 112, 128, 16, 20, 14, 8)],
                            names=["obj_tree_dead", "obj_tree_sapling", "obj_tree_oak", "obj_tree_oak_orange",
                                   "obj_tree_pine", "obj_stump", "obj_bush", "obj_logs", "obj_branch"]),
    # 4 crack stages on one 4x1 grid -> tiles_crack.png 64x16 (thin lines: lower coverage threshold)
    "tiles_crack.png": dict(kind="overlay_grid", grid=(4, 1), tile=16, out="tiles_crack", cover=0.18),
    # Ore tiles: kept in memory and combined into tiles_ore.png (see ORE_ATLAS below)
    "tiles_ore.png":   dict(kind="ore_tiles", set="a", n=9,
                            names=["stone", "copper", "silver", "gold", "crystal_green", "dirt", "dirt_pebbles",
                                   "dirt_rocks", "toxic_cracked"]),
    "tiles_ore2.png":  dict(kind="ore_tiles", set="b", n=6,
                            names=["stone_chunks", "copper", "gold", "crystal_blue", "toxic", "crystal_purple"]),
    "tiles_ore3.png":  dict(kind="ore_tiles", set="c", n=6,
                            names=["stone", "copper", "silver", "crystal_blue", "gold", "toxic_slime"]),
    # V3 batch.
    # Geiger counter, 5 radiation states (green .. red with sparks): one scale for all (the red
    # one with its sparks is the tallest = 24 px), each in a 24x24 cell, bottom-left aligned so
    # the bodies line up; ui_geiger.png = the 5 cells side by side (120x24), as the HUD expects.
    "ui_gieger.png":   dict(kind="sheet", out="ui_geiger", n=5, anim=True, h=24, cell=(24, 24),
                            align="left", strip="ui_geiger"),
    # 5 tools 16x16 (the crowbar/pipe one is "pipe"), 4 backpack tiers 24x24 (each fitted).
    "icon_tools.png":  dict(kind="sheet", n=9, boxes=[(16, 16)] * 5 + [(24, 24)] * 4,
                            names=["icon_tool_axe", "icon_tool_pickaxe", "icon_tool_flashlight", "icon_tool_canteen",
                                   "icon_tool_pipe", "icon_backpack_1", "icon_backpack_2", "icon_backpack_3",
                                   "icon_backpack_4"]),
    # Bunker stations at 16 px tile scale (each fitted into its box; both doors 44 px tall).
    "bunker_stations.png": dict(kind="sheet", n=6, boxes=[(48, 32), (48, 32), (16, 32), (32, 44), (32, 44), (16, 32)],
                                names=["obj_workbench", "obj_upgrade_bench", "obj_locker", "obj_door_locked",
                                       "obj_door_open", "obj_lamp_ceiling"]),
    # Open surface hatch (32 px wide, lid raised), ladder segment, ladder top in its opening,
    # riveted concrete shaft wall tile.
    "obj_hatchladder.png": dict(kind="sheet", n=4, boxes=[(32, 64), (16, 16), (16, 16), (16, 16)],
                                names=["obj_hatch_open", "obj_ladder", "obj_ladder_top", "tile_shaft_wall"]),
    # Tutorial slide 3: a filled 16:9 picture (no magenta), cropped to exact 16:9 then 480x270.
    "tut3_rad.png":    dict(kind="full", out="tut_3_radiation", size=(480, 270), crop=True),
}
# V4 batch (new places: Old Mine, Bomb Crater, survival items, stations). Raw files from the
# designer's gameNewPlaces folder; run with --chars and --world both pointing at that folder.
# "parts" sheets: each object is cut from its own region, given in per-mille of the image width
# (x0, y0, x1, y1; y uses the same unit), so drips / steam / drops stay with their owner and a
# neighbour never leaks in. Spec per part:
#   ("tile",)        16x16 ground tile, cut inside its dark outline so it repeats seamlessly
#   ("ceil",)        a ceiling strip (rock with drips): inside the outline, stretched to fill 16x16
#   ("w", n)/("h", n) width / height in px (aspect kept), ("box", w, h) fit inside, ("f", k) raw px * k
# and optional extras: kill_purple=True drops painted light rays (purple over magenta).
# "atlas" builds a 4x2 sheet in the tiles_outside.png layout (scenes/expedition.gd art_tile:
# (0,0) under ground, (1,0) (3,0) (1,1) (2,1) (3,1) the surface row; (2,0) rock and (0,1)
# the ceiling's lowest row in tunnel locations) from the tiles: (tile name, op) with op None,
# "flip" (mirrored, for variety) or ("mul", (r, g, b)).
CHARS.update({
    # 4 wing beats; purple bats on magenta: strict background key, no inner recolouring.
    "Bats.png": dict(kind="sheet", out="bat_fly", n=4, anim=True, h=14, key_m=130, edge_m=70, inner_m=255),
    # 4 run frames, same height rule as the old rat (13 px for the tallest frame).
    "Rats.png": dict(kind="sheet", out="rat_run", n=4, anim=True, h=13),
})
MINE_UNDER = (0.78, 0.74, 0.74)   # the ground under the surface row a little darker, so the floor reads
CRATER_UNDER = (0.8, 0.8, 0.8)
WORLD.update({
    "Mine.png":               dict(kind="full", out="bg_mine", size=(480, 270)),
    "BombCraterBackDrop.png": dict(kind="full", out="bg_crater", size=(480, 270)),
    "MineObjects.png": dict(kind="parts", parts=[
        ("tile_mine_floor",   (110, 30, 260, 178), ("tile",)),
        ("tile_mine_wall",    (420, 30, 582, 180), ("tile",)),
        ("tile_mine_ceiling", (712, 28, 905, 152), ("ceil",)),
        ("obj_mine_support",  (45, 205, 335, 440), ("w", 56)),
        ("obj_mine_cart",     (385, 240, 625, 442), ("w", 34)),
        ("obj_mine_lamp",     (755, 222, 855, 418), ("h", 26)),
        ("obj_mine_exit",     (95, 468, 292, 728), ("w", 28), dict(kill_purple=True)),
        ("obj_mushroom",      (420, 545, 560, 672), ("h", 14)),
        ("obj_water_drip",    (730, 485, 885, 619), ("w", 20)),
        ("obj_water_pool",    (690, 619, 910, 708), ("w", 30)),
    ], atlas=("tiles_mine", [
        ("tile_mine_floor", MINE_UNDER), ("tile_mine_floor", None), ("tile_mine_wall", None), ("tile_mine_floor", "flip"),
        ("tile_mine_ceiling", None), ("tile_mine_floor", "flip"), ("tile_mine_floor", None), ("tile_mine_floor", (0.9, 1.0, 0.85)),
    ])),
    "BombCrateItems.png": dict(kind="parts", parts=[
        ("tile_crater_ground", (62, 40, 210, 190), ("tile",)),
        ("tile_crater_under",  (285, 40, 435, 190), ("tile",)),
        ("obj_bomb_shell",     (470, 8, 950, 210), ("w", 72)),
        ("obj_car_wreck",      (35, 236, 405, 378), ("w", 60)),
        ("obj_crater_crystal", (445, 230, 635, 376), ("w", 24)),
        ("obj_supply_crate",   (700, 260, 945, 378), ("w", 26)),
        ("obj_girder",         (85, 405, 255, 640), ("h", 34)),
        ("obj_crater_exit",    (385, 405, 585, 640), ("w", 30)),
        ("obj_ash_pile",       (675, 495, 930, 636), ("w", 28)),
    ], atlas=("tiles_crater", [
        ("tile_crater_under", CRATER_UNDER), ("tile_crater_ground", None), ("tile_crater_under", CRATER_UNDER), ("tile_crater_ground", "flip"),
        ("tile_crater_under", CRATER_UNDER), ("tile_crater_ground", "flip"), ("tile_crater_ground", None), ("tile_crater_ground", None),
    ])),
    # 9 icons, each fitted into 16x16 (steam and drops stay with their item).
    "SurivialItems.png": dict(kind="parts", parts=[
        (n, (x0, 70, x1, 232), ("box", 16, 16)) for n, x0, x1 in [
            ("icon_dirty_water", 25, 117), ("icon_clean_water", 117, 210), ("icon_raw_meat", 210, 329),
            ("icon_cooked_meat", 329, 445), ("icon_mushroom", 445, 547), ("icon_canned_food", 547, 648),
            ("icon_bandage", 648, 763), ("icon_tin_can", 763, 872), ("icon_bucket", 872, 980)]]),
    # Bunker stations, one px scale for all (the filter ~32 px tall like bld_purifier).
    "Water.png": dict(kind="parts", parts=[
        (n, (x0, 50, x1, 285), ("f", 1 / 13.5)) for n, x0, x1 in [
            ("obj_water_filter", 25, 235), ("obj_water_filter_on", 240, 450), ("obj_stove", 455, 620),
            ("obj_stove_lit", 625, 800), ("obj_shelf", 805, 980)]]),
})

# tiles_ore.png = 4x2 cells of 16 px in the order scenes/mining.gd ORE_ATLAS expects:
#   scrap_ore, concrete, circuits, bedrock / planks, pipe, bones, toxic
# each = (source set, tile name, recolour). Recolours: None, ("dark", rgb mul) for the
# whole tile, ("rocks", rgb) = only the grey stones in a dirt tile get that colour.
ORE_ATLAS = [
    ("scrap_ore", "c", "silver", None),
    ("concrete", "b", "stone_chunks", None),
    ("circuits", "c", "gold", None),
    ("bedrock", "c", "stone", ("dark", (0.52, 0.56, 0.74))),
    ("planks", "a", "dirt_rocks", ("rocks", (118, 76, 40))),
    ("pipe", "a", "dirt_pebbles", ("rocks", (180, 72, 36))),
    ("bones", "a", "dirt_pebbles", ("rocks", (226, 218, 192))),
    ("toxic", "b", "toxic", None),
]

# --------------------------------------------------------------------------- pixels

def magness(rgb):
    """How magenta a pixel is: min(R,B) - G (pure #FF00FF = 255)."""
    r, g, b = rgb[..., 0].astype(int), rgb[..., 1].astype(int), rgb[..., 2].astype(int)
    return np.minimum(r, b) - g


# Keying thresholds; a sheet's cfg may override them (e.g. purple bats on magenta need a
# stricter background test and no inner recolouring): key_m, edge_m, inner_m.
TH_DEFAULT = dict(key_m=70, edge_m=25, inner_m=40)
TH = dict(TH_DEFAULT)


def is_magenta_bg(rgb):
    m = magness(rgb)
    return (m > TH["key_m"]) & (rgb[..., 0] > 110) & (rgb[..., 2] > 110)


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


def resample(rgb, mask, out_w, out_h, cover=0.5):
    """Block-median downscale: each output pixel = median colour of the opaque source
    pixels in its block, opaque if at least `cover` of the block is. No blur across blocks."""
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
    a = m.mean(axis=2) >= cover
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
        a[edge & (m > TH["edge_m"])] = False
    m = magness(rgb)
    bad = a & (m > TH["inner_m"])
    for y, x in zip(*np.nonzero(bad)):
        ys, xs = slice(max(0, y - 1), y + 2), slice(max(0, x - 1), x + 2)
        nb = rgb[ys, xs][a[ys, xs] & (magness(rgb[ys, xs]) <= TH["inner_m"])]
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

def components(mask, n, coarse=4, dilate=3, min_area=40, warn=True):
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
    if len(boxes) != n and warn:
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


def despeckle(a, max_px=4):
    """Removes tiny loose specks (8-connected groups of at most max_px pixels)."""
    a = a.copy()
    seen = np.zeros_like(a)
    h, w = a.shape
    for sy, sx in zip(*np.nonzero(a)):
        if seen[sy, sx]:
            continue
        group, q = [], deque([(sy, sx)])
        seen[sy, sx] = True
        while q:
            y, x = q.popleft()
            group.append((y, x))
            for ny in (y - 1, y, y + 1):
                for nx in (x - 1, x, x + 1):
                    if 0 <= ny < h and 0 <= nx < w and a[ny, nx] and not seen[ny, nx]:
                        seen[ny, nx] = True
                        q.append((ny, nx))
        if len(group) <= max_px:
            for y, x in group:
                a[y, x] = False
    return a


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
ORE_TILES = {}   # (set, name) -> 16x16x3 uint8, filled by "ore_tiles" sheets


def tile_body(rgb, mask, box):
    """The part of a tile picture inside its dark outline (and bevel): scans in from each
    side on three lines and takes the deepest point where the outline ends, plus a margin."""
    x0, y0, x1, y1 = box
    lum = rgb[y0:y1, x0:x1].astype(int).mean(axis=2)
    m = mask[y0:y1, x0:x1]
    h, w = lum.shape
    body = m & (lum > 55)

    def depth(lines):   # lines: 1D bool arrays scanned from the outside in
        best = 0
        for ln in lines:
            opaque = np.nonzero(ln[0])[0]
            if len(opaque) == 0:
                continue
            inside = np.nonzero(ln[1][opaque[0]:])[0]
            best = max(best, opaque[0] + (inside[0] if len(inside) else 0))
        return best
    fr = (0.3, 0.5, 0.7)
    left = depth([(m[int(h * f)], body[int(h * f)]) for f in fr])
    right = depth([(m[int(h * f)][::-1], body[int(h * f)][::-1]) for f in fr])
    top = depth([(m[:, int(w * f)], body[:, int(w * f)]) for f in fr])
    bottom = depth([(m[:, int(w * f)][::-1], body[:, int(w * f)][::-1]) for f in fr])
    mx, my = w // 40, h // 40   # skip the light bevel just inside the outline
    return rgb[y0 + top + my:y1 - bottom - my, x0 + left + mx:x1 - right - mx]


def recolour(c, how):
    c = c.astype(float)
    if how is None:
        return c.astype(np.uint8)
    mode, col = how
    if mode == "dark":
        return np.clip(c * np.array(col), 0, 255).astype(np.uint8)
    # "rocks": low-saturation (grey) pixels take colour `col`, keeping their light/dark shading
    sat = c.max(axis=2) - c.min(axis=2)
    lum = c.mean(axis=2, keepdims=True)
    rock = (sat < 45)[..., None]
    shaded = np.array(col)[None, None] * (lum / max(1.0, float(np.median(lum[rock[..., 0]]) if rock.any() else 128)))
    # then darken the (orange) dirt towards tiles_outside_dirt so dug ore sits in the same ground
    return np.clip(np.where(rock, shaded, c) * np.array(DIRT_MATCH), 0, 255).astype(np.uint8)


DIRT_MATCH = (0.78, 0.78, 1.0)


def build_ore_atlas(folder, index):
    """tiles_ore.png (4x2, 16 px) from the ore tiles in ORE_ATLAS order, plus one file per cell."""
    need = {(s, n) for _, s, n, _ in ORE_ATLAS}
    if not need <= set(ORE_TILES):
        print("   ore atlas skipped: missing %s" % sorted(need - set(ORE_TILES)))
        return
    CURRENT_SOURCE[0] = "tiles_ore.png + tiles_ore2.png + tiles_ore3.png"
    atlas = Image.new("RGBA", (64, 32), (0, 0, 0, 0))
    for i, (kind, s, n, how) in enumerate(ORE_ATLAS):
        c = recolour(ORE_TILES[(s, n)], how)
        img = to_image(c, np.ones(c.shape[:2], bool))
        save(img, folder, "tiles_ore_%s" % kind, index)
        atlas.paste(img, ((i % 4) * 16, (i // 4) * 16))
    save(atlas, folder, "tiles_ore", index)
    if PREVIEW_DIR[0]:
        # every source tile, one row per raw sheet, for picking a different mapping (not game art)
        sheet = Image.new("RGBA", (17 * 9, 17 * 3), (0, 0, 0, 0))
        for r, s in enumerate("abc"):
            for i, c in enumerate(v for k, v in ORE_TILES.items() if k[0] == s):
                sheet.paste(to_image(c, np.ones(c.shape[:2], bool)), (i * 17, r * 17))
        os.makedirs(PREVIEW_DIR[0], exist_ok=True)
        sheet.save(os.path.join(PREVIEW_DIR[0], "ore_tiles_all.png"))


PREVIEW_DIR = [""]   # --preview: where to write debug sheets (outside the Godot project)


def process(path, cfg, folder, index):
    CURRENT_SOURCE[0] = os.path.basename(path)
    TH.clear()
    TH.update({k: cfg.get(k, v) for k, v in TH_DEFAULT.items()})
    rgb = np.array(Image.open(path).convert("RGB"))
    bg, colour = detect_background(rgb)
    kind = cfg["kind"]
    print("%-26s %-6s bg=%s" % (os.path.basename(path), kind, bg))

    if kind == "full":
        if cfg.get("crop"):   # centre-crop to the exact aspect of `size` first
            H, W = rgb.shape[:2]
            tw, th = cfg["size"]
            cw, ch = min(W, round(H * tw / th)), min(H, round(W * th / tw))
            x0, y0 = (W - cw) // 2, (H - ch) // 2
            rgb = rgb[y0:y0 + ch, x0:x0 + cw]
        mask =alpha_mask(rgb, bg) if cfg.get("key") and bg == "magenta" else np.ones(rgb.shape[:2], bool)
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

    if kind == "overlay_grid":
        # equal grid cells (a stage may be tiny, so no component split), each cell -> tile x tile
        cols, rows = cfg["grid"]
        H, W = rgb.shape[:2]
        mask = alpha_mask(rgb, bg)
        t = cfg["tile"]
        strip = Image.new("RGBA", (t * cols, t * rows), (0, 0, 0, 0))
        for i in range(cols * rows):
            cx, cy = i % cols, i // cols
            x0, x1 = W * cx // cols, W * (cx + 1) // cols
            y0, y1 = H * cy // rows, H * (cy + 1) // rows
            c, a = resample(rgb[y0:y1, x0:x1], mask[y0:y1, x0:x1], t, t, cover=cfg.get("cover", 0.5))
            c, a = defringe(c, a)
            strip.paste(to_image(c, a), (cx * t, cy * t))
        save(strip, folder, cfg["out"], index)
        return

    mask = alpha_mask(rgb, bg)
    if kind == "parts":
        process_parts(rgb, mask, cfg, folder, index)
        return

    if kind == "ore_tiles":
        # tiles with a dark outline on magenta: crop to the tile body (inside the outline), 16x16
        for name, box in zip(cfg["names"], components(mask, cfg["n"], dilate=1)):
            sub = tile_body(rgb, mask, box)
            c, a = resample(sub, np.ones(sub.shape[:2], bool), 16, 16)
            ORE_TILES[(cfg["set"], name)] = c
        return

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
    if "cuts" in cfg:
        # objects that touch each other: split at fixed x positions (raw px), box = opaque part of each slice
        xs = [0] + cfg["cuts"] + [mask.shape[1]]
        boxes = []
        for a, b in zip(xs[:-1], xs[1:]):
            sub = np.zeros_like(mask)
            sub[:, a:b] = mask[:, a:b]
            # drop bits of the neighbours that poke over the cut (small parts far from the main one)
            parts = components(sub, 99, dilate=1, min_area=1, warn=False)
            area = lambda p: int(sub[p[1]:p[3], p[0]:p[2]].sum())
            big = max(area(p) for p in parts)
            keep = np.zeros_like(mask)
            for p in parts:
                if area(p) >= 0.04 * big:
                    keep[p[1]:p[3], p[0]:p[2]] = True
            mask[:, a:b] &= keep[:, a:b]
            boxes.append(bbox(mask & keep))
    else:
        boxes = components(mask, n, dilate=cfg.get("dilate", 3))
    if cfg.get("order") == "ui":
        boxes = order_ui_parts(rgb, boxes)
    names = cfg.get("names") or ["%s_%d" % (cfg["out"], i) for i in range(len(boxes))]
    if cfg.get("anim"):
        if "scale" in cfg:   # fixed px scale (e.g. to match another sheet)
            scale = cfg["scale"]
        else:
            tallest = max(b[3] - b[1] for b in boxes)
            scale = cfg["h"] / tallest
        pieces = [trim(*scaled_piece(rgb, mask, b, scale)) for b in boxes]
        W = max(p[0].shape[1] for p in pieces)
        H = max(p[0].shape[0] for p in pieces)
        if "cell" in cfg:   # fixed canvas size (at least as big as the frames)
            W, H = max(W, cfg["cell"][0]), max(H, cfg["cell"][1])
        left = cfg.get("align") == "left"
        for name, (c, a) in zip(names, pieces):
            canvas = Image.new("RGBA", (W, H), (0, 0, 0, 0))
            img = to_image(c, a)
            canvas.paste(img, (0 if left else (W - img.width) // 2, H - img.height))   # bottom baseline, centred
            save(canvas, folder, name, index)
        strip = Image.new("RGBA", (W * len(pieces), H), (0, 0, 0, 0))
        for i, (c, a) in enumerate(pieces):
            img = to_image(c, a)
            strip.paste(img, (i * W + (0 if left else (W - img.width) // 2), H - img.height))
        if "out" in cfg:
            save(strip, folder, cfg.get("strip", cfg["out"] + "_strip"), index)
        return
    for i, (name, b) in enumerate(zip(names, boxes)):
        if "factor" in cfg:
            scale = cfg["factor"]
        else:
            bw, bh = cfg["boxes"][i] if "boxes" in cfg else cfg["box"]
            scale = fit_scale(b, bw, bh)
        c, a = scaled_piece(rgb, mask, b, scale)
        if "cuts" in cfg:
            a = despeckle(a)
        c, a = trim(c, a)
        save(to_image(c, a), folder, name, index)


PART_TILES = {}   # tile name -> RGBA image, for the "atlas" of a parts sheet


def process_parts(rgb, mask, cfg, folder, index):
    H, W = mask.shape
    u = W / 1000.0
    for part in cfg["parts"]:
        name, (rx0, ry0, rx1, ry1), spec = part[:3]
        extra = part[3] if len(part) > 3 else {}
        X0, Y0 = max(0, int(rx0 * u)), max(0, int(ry0 * u))
        X1, Y1 = min(W, int(rx1 * u)), min(H, int(ry1 * u))
        m = np.zeros_like(mask)
        m[Y0:Y1, X0:X1] = mask[Y0:Y1, X0:X1]
        if extra.get("kill_purple"):   # painted light rays: purple / pink over the magenta
            c = rgb.astype(int)
            m &= ~((c[..., 2] - c[..., 1] > 25) & (c[..., 0] - c[..., 1] > 50))
        box = bbox(m)
        x0, y0, x1, y1 = box
        if spec[0] in ("tile", "ceil"):
            ix, iy = (x1 - x0) // 14, (y1 - y0) // 14
            sub, sm = rgb[y0 + iy:y1 - iy, x0 + ix:x1 - ix], m[y0 + iy:y1 - iy, x0 + ix:x1 - ix]
            if spec[0] == "tile":
                c, a = resample(sub, np.ones(sm.shape, bool), 16, 16)
            else:   # rock band on top, the drips hang into the tunnel below
                c, a = resample(sub, sm, 16, 16)
                c, a = defringe(c, a)
            img = to_image(c, a)
            PART_TILES[name] = img
            save(img, folder, name, index)
            continue
        bw, bh = x1 - x0, y1 - y0
        scale = {"w": lambda: spec[1] / bw, "h": lambda: spec[1] / bh, "f": lambda: spec[1],
                 "box": lambda: fit_scale(box, spec[1], spec[2])}[spec[0]]()
        c, a = scaled_piece(rgb, m, box, scale)
        a = despeckle(a, 2)
        c, a = trim(c, a)
        save(to_image(c, a), folder, name, index)
    if "atlas" in cfg:
        out, cells = cfg["atlas"]
        atlas = Image.new("RGBA", (64, 32), (0, 0, 0, 0))
        for i, (tile, op) in enumerate(cells):
            img = PART_TILES[tile]
            if op == "flip":
                img = img.transpose(Image.FLIP_LEFT_RIGHT)
            elif op is not None:
                arr = np.array(img).astype(float)
                arr[..., :3] *= np.array(op)
                img = Image.fromarray(np.clip(np.round(arr), 0, 255).astype(np.uint8), "RGBA")
            atlas.paste(img, ((i % 4) * 16, (i // 4) * 16))
        save(atlas, folder, out, index)


def check_outputs(folders):
    bad = 0
    for folder in folders:
        for f in sorted(os.listdir(folder)):
            if not f.endswith(".png"):
                continue
            arr = np.array(Image.open(os.path.join(folder, f)).convert("RGBA"))
            vis = arr[..., 3] > 0
            # bright magenta only (the bats' own dark purple, ~145,65,148, is fine)
            mag = (magness(arr[..., :3]) > 60) & (np.maximum(arr[..., 0], arr[..., 2]) > 170) & vis
            if mag.sum():
                bad += 1
                print("   magenta left in %s: %d px" % (f, mag.sum()))
    print("magenta check: %s" % ("OK, no magenta pixels left" if not bad else "%d files with magenta" % bad))


def write_index(index):
    """Rewrites ART_INDEX.md: rows for the files made in this run, plus the rows of the old
    index for files that still exist (so a run on only part of the raws keeps the rest)."""
    made = {rel for rel, _, _ in index}
    old = os.path.join(ART, "ART_INDEX.md")
    if os.path.exists(old):
        for line in open(old):
            parts = [p.strip() for p in line.strip().strip("|").split("|")]
            if len(parts) == 3 and parts[0].endswith(".png") and parts[0] not in made \
                    and os.path.exists(os.path.join(ART, parts[0])):
                w, h = Image.open(os.path.join(ART, parts[0])).size
                index.append((parts[0], (w, h), parts[2]))
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
    ap.add_argument("--preview", default="", help="folder for debug sheets (e.g. all ore tiles); keep it outside the project")
    args = ap.parse_args()
    PREVIEW_DIR[0] = args.preview
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
        if sub == "world_clean" and ORE_TILES:
            build_ore_atlas(folder, index)
    write_index(index)
    check_outputs([os.path.join(ART, "characters_clean"), os.path.join(ART, "world_clean")])


if __name__ == "__main__":
    sys.exit(main())
