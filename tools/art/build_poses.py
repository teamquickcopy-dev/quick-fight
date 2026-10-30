"""Cuts a fighter's pose sheets into one picture per pose, for the pose-picture rig.

    python3 tools/art/build_poses.py tools/art/arghya_poses.json            # build
    python3 tools/art/build_poses.py tools/art/arghya_poses.json --preview  # check the cuts

Each sheet is a row of 8 poses on a flat gray background (docs/art-prompts.md, Step 2). For each
sheet this removes the background and the floor shadows, splits the silhouette between the poses,
scales every pose to the same character size and writes into client/fighters/<id>/art/:
  pose_<name>.webp   one pose, background removed, cropped
  poses.json         per pose: texture, anchor (the point that stands on the fighter's position,
                     in texture pixels), plus draw_scale and the config's "map" (which pose shows
                     for which state / move, read by fighters/_poses/pose_rig.gd)
Poses on a sheet often overlap (a hammer reaching into the next pose). The config draws a few
lines along each pose's body, limbs and hammer; every pixel goes to the pose whose lines are
nearest when walking inside the silhouette. --preview colours each pose's share so wrong cuts show.
"""
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage

sys.path.insert(0, os.path.dirname(__file__))
import sheet  # noqa: E402
from build_fighter import save_webp  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
QUALITY = 84
PAD = 4
LINE_W = 9
COLORS = [(255, 60, 60), (60, 200, 60), (60, 120, 255), (255, 200, 0), (255, 0, 255), (0, 220, 220), (255, 128, 0), (160, 80, 255)]


def silhouette(rgb, tol=24):
    """Foreground mask: removes the border-connected background, the soft gray floor shadows
    (low saturation, darker than the background, in the bottom fifth) and big enclosed pockets of
    background (between an arm and the body)."""
    bg = sheet.background_color(rgb)
    dist = np.sqrt(((rgb - bg) ** 2).sum(axis=2))
    spread = rgb.max(axis=2) - rgb.min(axis=2)
    h = rgb.shape[0]
    low = (np.arange(h) > h * 0.8)[:, None]
    shadow = (spread < 14) & (rgb.max(axis=2) < bg.max() + 6) & (rgb.max(axis=2) > 60) & low
    near = (dist < tol) | shadow
    labels, _ = ndimage.label(near)
    border = set(np.unique(np.concatenate([labels[0], labels[-1], labels[:, 0], labels[:, -1]]))) - {0}
    back = np.isin(labels, list(border))
    pockets, n = ndimage.label((dist < tol) & ~back)
    if n:
        sizes = ndimage.sum(np.ones_like(dist), pockets, range(1, n + 1))
        back |= np.isin(pockets, [i + 1 for i, s in enumerate(sizes) if s > 600])
    return ndimage.binary_opening(~back, iterations=1)


def assign(fg, poses):
    """Label each foreground pixel with its pose (1..n): grow every pose's lines outward inside the
    silhouette (geodesic nearest); pieces no line reaches (paint drops, stars) go to the nearest pose."""
    seeds = Image.new("L", (fg.shape[1], fg.shape[0]), 0)
    d = ImageDraw.Draw(seeds)
    for i, p in enumerate(poses, start=1):
        for line in p["lines"]:
            d.line([tuple(v) for v in line], fill=i, width=LINE_W)
    lab = np.asarray(seeds).astype(np.int32) * fg
    footprint = ndimage.generate_binary_structure(2, 1)
    while True:
        grown = ndimage.grey_dilation(lab, footprint=footprint)
        new = (lab == 0) & fg & (grown > 0)
        if not new.any():
            break
        lab = np.where(new, grown, lab)
    rest = fg & (lab == 0)
    if rest.any():
        _, (iy, ix) = ndimage.distance_transform_edt(lab == 0, return_indices=True)
        lab = np.where(rest, lab[iy, ix], lab)
    # Where poses overlap, the split can leave a pose a loose crumb of its neighbour (the tip of a
    # boot behind another leg). Drop pieces of a pose that touch another pose and hold none of its
    # lines; free-standing pieces (paint drops, dizzy stars) stay.
    seeded = np.asarray(seeds) > 0
    for i in range(1, len(poses) + 1):
        pieces, n = ndimage.label(lab == i)
        for k, sl in enumerate(ndimage.find_objects(pieces), start=1):
            piece = pieces[sl] == k
            if (seeded[sl] & piece).any():
                continue
            ring = ndimage.binary_dilation(piece, iterations=2) & ~piece
            if ((lab[sl] > 0) & (lab[sl] != i) & ring).any():
                lab[sl][piece] = 0
    return lab


def soft_alpha(mask):
    a = ndimage.gaussian_filter(mask.astype(np.float32), 0.6)
    return (np.clip((a - 0.15) / 0.7, 0, 1) * 255).astype(np.uint8)


def main(config_path, preview=False):
    cfg = json.load(open(config_path))
    src = os.path.join(ROOT, cfg["source"])
    out_dir = os.path.join(ROOT, "client", "fighters", cfg["id"], "art")
    os.makedirs(out_dir, exist_ok=True)
    # Sheet scale -> game px: a standing pose on a scale-1.0 sheet is `ref_height` sheet px tall.
    game_per_sheet = cfg["standing_height_px"] / cfg["ref_height"]
    e = game_per_sheet * cfg["export_scale"]
    out = {"id": cfg["id"], "draw_scale": round(1.0 / cfg["export_scale"], 5), "poses": {}, "map": cfg.get("map", {})}
    total = 0
    for si, sh in enumerate(cfg["sheets"], start=1):
        rgb = sheet.load_rgb(os.path.join(src, sh["file"]))
        fg = silhouette(rgb)
        lab = assign(fg, sh["poses"])
        if preview:
            im = Image.fromarray(rgb.astype(np.uint8))
            tint = np.zeros_like(rgb)
            for i in range(1, len(sh["poses"]) + 1):
                tint[lab == i] = COLORS[(i - 1) % len(COLORS)]
            mixed = np.where(lab[..., None] > 0, rgb * 0.45 + tint * 0.55, rgb * 0.5 + 60).astype(np.uint8)
            im = Image.fromarray(mixed)
            d = ImageDraw.Draw(im)
            for i, p in enumerate(sh["poses"], start=1):
                for line in p["lines"]:
                    d.line([tuple(v) for v in line], fill=(0, 0, 0), width=3)
                hx = p.get("hip", p["lines"][0][min(2, len(p["lines"][0]) - 1)][0])
                d.line([(hx, im.height - 60), (hx, im.height - 20)], fill=(255, 255, 255), width=4)
                d.text((hx - 30, 5), p["name"], fill=(255, 255, 255), font=ImageFont.load_default(size=22))
            path = os.path.join(out_dir, "..", f"poses_preview_{si}.jpg")
            im.convert("RGB").save(path, quality=80)
            print("wrote", os.path.relpath(path, ROOT))
            continue
        k = e * sh.get("scale", 1.0)
        # The floor: where the feet of the standing poses end (median, so a splash or a hammer
        # head below the feet doesn't move it). A pose can override it with "ground".
        bottoms = [np.nonzero((lab == i).any(axis=1))[0].max() for i, p in enumerate(sh["poses"], start=1) if not p.get("air")]
        ground = sh.get("ground", int(np.median(bottoms)) - 3)
        for i, p in enumerate(sh["poses"], start=1):
            mask = lab == i
            ys, xs = np.nonzero(mask)
            x0, y0 = max(xs.min() - PAD, 0), max(ys.min() - PAD, 0)
            x1, y1 = min(xs.max() + 1 + PAD, rgb.shape[1]), min(ys.max() + 1 + PAD, rgb.shape[0])
            a = soft_alpha(mask)[y0:y1, x0:x1]
            im = Image.fromarray(np.dstack([rgb[y0:y1, x0:x1].astype(np.uint8), a]), "RGBA")
            w, h = max(1, round(im.width * k)), max(1, round(im.height * k))
            im = im.resize((w, h), Image.LANCZOS)
            name = p["name"]
            save_webp(im, os.path.join(out_dir, f"pose_{name}.webp"), QUALITY)
            total += os.path.getsize(os.path.join(out_dir, f"pose_{name}.webp"))
            hip = p.get("hip", p["lines"][0][min(2, len(p["lines"][0]) - 1)][0])
            foot_y = ys.max() if p.get("air") else p.get("ground", ground)
            out["poses"][name] = {"texture": f"pose_{name}.webp",
                                  "anchor": [round((hip - x0) * k, 1), round((foot_y - y0) * k, 1)]}
    if preview:
        return
    json.dump(out, open(os.path.join(out_dir, "poses.json"), "w"), indent=1)
    print(f"{cfg['id']}: {len(out['poses'])} poses, {total / 1024:.0f} KB in {os.path.relpath(out_dir, ROOT)}")


if __name__ == "__main__":
    main(sys.argv[1], "--preview" in sys.argv)
