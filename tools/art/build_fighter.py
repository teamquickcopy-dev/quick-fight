"""Builds a fighter's cutout rig and UI art from its source art sheets.

    python3 tools/art/build_fighter.py tools/art/arghya.json            # build
    python3 tools/art/build_fighter.py tools/art/arghya.json --preview  # numbered piece map

Reads the config (which piece is which, joint positions in the parts sheet) and writes into
client/fighters/<id>/art/:
  <part>.webp   each body part: background removed, joint caps filled with the neighbouring
                texture, cropped, scaled down
  rig.json      pivots/tips in texture pixels, bone lengths and joint anchors in screen pixels
  portrait.webp, face.webp, expr_<name>.webp   UI art
WebP keeps the download small. Each file gets a "keep" .import so Godot exports it unchanged;
the game decodes it at runtime (fighters/_cutout/art.gd).
The game draws the parts on the same skeleton the gray-box rig uses (fighters/_cutout/).
"""
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage

sys.path.insert(0, os.path.dirname(__file__))
import sheet  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
PAD = 8
PART_QUALITY = 88
UI_QUALITY = 80
KEEP_IMPORT = '[remap]\n\nimporter="keep"\n'


def save_webp(im, path, quality):
    im.save(path, "WEBP", quality=quality, method=6)
    with open(path + ".import", "w") as f:
        f.write(KEEP_IMPORT)
# Child pieces start this fraction of their length past the joint, so they tuck under the parent.
INSET = 0.06


def fill_caps(rgb, alpha, caps):
    """Replace cap pixels with the colour of the nearest non-cap pixel of the same piece."""
    solid = (alpha > 128) & ~caps
    _, (iy, ix) = ndimage.distance_transform_edt(~solid, return_indices=True)
    out = rgb.copy()
    out[caps] = rgb[iy[caps], ix[caps]]
    return out


def main(config_path, preview=False):
    cfg = json.load(open(config_path))
    src = os.path.join(ROOT, cfg["source"])
    out_dir = os.path.join(ROOT, "client", "fighters", cfg["id"], "art")
    os.makedirs(out_dir, exist_ok=True)

    rgb = sheet.load_rgb(os.path.join(src, "parts.webp"))
    alpha = sheet.cut_background(rgb)
    labels, comps = sheet.components(alpha)
    if preview:
        path = os.path.join(out_dir, "..", "parts_preview.png")
        sheet.preview(rgb, comps, path)
        print("wrote", os.path.relpath(path, ROOT))
        return
    caps = sheet.cap_mask(rgb, alpha)
    # Caps have a light rim around them in the source art: widen the area that gets filled.
    filled = fill_caps(rgb, alpha, ndimage.binary_dilation(caps, iterations=6) & (alpha > 0))
    e = cfg["export_scale"]
    parts = cfg["parts"]

    # Joint-to-joint lengths (sheet px), with child pivots moved INSET along their bone.
    def inset_pivot(p):
        (px, py), (tx, ty) = p["pivot"], p["tip"]
        k = 0.0 if p is parts["torso"] or p is parts["pelvis"] else INSET
        return [px + (tx - px) * k, py + (ty - py) * k]

    def length(p):
        (px, py), (tx, ty) = inset_pivot(p), p["tip"]
        return math.hypot(tx - px, ty - py)

    a = cfg["anchors"]
    pelvis_drop = a["hip_F"][1] - parts["pelvis"]["pivot"][1]
    shin = parts["leg_lower_F"]
    sole = math.hypot(shin["sole"][0] - shin["tip"][0], shin["sole"][1] - shin["tip"][1])
    total = (length(parts["head"]) + length(parts["torso"]) + pelvis_drop
             + length(parts["leg_upper_F"]) + length(parts["leg_lower_F"]) + sole)
    s = cfg["target_height_px"] / total
    rig = {"id": cfg["id"], "draw_scale": round(s / e, 5), "parts": {}, "anchors": {},
           "lengths": {}, "sole": round(sole * s, 2),
           # Where the face is in the portrait (0..1), so cards can crop around it.
           "portrait_focus": cfg["portrait"].get("focus", [0.5, 0.4])}

    for name, p in parts.items():
        comp_label = comps[p["comp"]][0]
        mask = labels == comp_label
        mask = ndimage.binary_dilation(mask, iterations=3) & (alpha > 0)
        x0, y0, x1, y1 = comps[p["comp"]][1]
        if "crop" in p:
            cx0, cy0, cx1, cy1 = p["crop"]
            box = np.zeros_like(mask)
            box[cy0:cy1, cx0:cx1] = True
            mask &= box
            x0, y0, x1, y1 = max(x0, cx0), max(y0, cy0), min(x1, cx1), min(y1, cy1)
        if "keep" in p:
            # Polygon outline to keep, e.g. the jacket body without the sleeves drawn onto it.
            poly = Image.new("L", (rgb.shape[1], rgb.shape[0]), 0)
            ImageDraw.Draw(poly).polygon([tuple(v) for v in p["keep"]], fill=255)
            mask &= np.asarray(poly) > 0
            xs = [v[0] for v in p["keep"]]
            ys = [v[1] for v in p["keep"]]
            x0, y0, x1, y1 = max(x0, min(xs)), max(y0, min(ys)), min(x1, max(xs)), min(y1, max(ys))
        x0, y0 = max(x0 - PAD, 0), max(y0 - PAD, 0)
        x1, y1 = min(x1 + PAD, rgb.shape[1]), min(y1 + PAD, rgb.shape[0])
        piece_a = np.where(mask, alpha, 0)[y0:y1, x0:x1].astype(np.uint8)
        piece_rgb = filled[y0:y1, x0:x1].astype(np.uint8)
        im = Image.fromarray(np.dstack([piece_rgb, piece_a]), "RGBA")
        w, h = round(im.width * e), round(im.height * e)
        im = im.resize((w, h), Image.LANCZOS)

        def tex(pt):
            x, y = (pt[0] - x0) * e, (pt[1] - y0) * e
            return [round(w - x if p.get("flip") else x, 2), round(y, 2)]

        if p.get("flip"):
            im = im.transpose(Image.FLIP_LEFT_RIGHT)
        save_webp(im, os.path.join(out_dir, f"{name}.webp"), PART_QUALITY)
        rig["parts"][name] = {"texture": f"{name}.webp", "pivot": tex(inset_pivot(p)), "tip": tex(p["tip"])}
        rig["lengths"][name] = round(length(p) * s, 2)

    # Anchors as screen-pixel offsets from the parent's pivot, in the parent's unrotated frame.
    tp, pp = parts["torso"]["pivot"], parts["pelvis"]["pivot"]
    for k in ("shoulder_F", "shoulder_B"):
        rig["anchors"][k] = [round((a[k][0] - tp[0]) * s, 2), round((a[k][1] - tp[1]) * s, 2)]
    for k in ("hip_F", "hip_B"):
        rig["anchors"][k] = [round((a[k][0] - pp[0]) * s, 2), round((a[k][1] - pp[1]) * s, 2)]

    # UI art
    port = Image.open(os.path.join(src, cfg["portrait"]["file"])).convert("RGB")
    save_webp(port.resize((cfg["portrait"]["size"],) * 2, Image.LANCZOS), os.path.join(out_dir, "portrait.webp"), UI_QUALITY)
    face = Image.open(os.path.join(src, cfg["face"]["file"])).convert("RGB").crop(cfg["face"]["crop"])
    save_webp(face.resize((cfg["face"]["size"],) * 2, Image.LANCZOS), os.path.join(out_dir, "face.webp"), UI_QUALITY)
    ex = cfg["expressions"]
    grid = Image.open(os.path.join(src, ex["file"])).convert("RGB")
    cols, rows = ex["grid"]
    cw, ch = grid.width // cols, grid.height // rows
    for i, name in enumerate(ex["names"]):
        c, r = i % cols, i // cols
        cell = grid.crop((c * cw + 6, r * ch + 6, (c + 1) * cw - 6, (r + 1) * ch - 6))
        save_webp(cell.resize((ex["size"],) * 2, Image.LANCZOS), os.path.join(out_dir, f"expr_{name}.webp"), UI_QUALITY)

    json.dump(rig, open(os.path.join(out_dir, "rig.json"), "w"), indent=1)
    size = sum(os.path.getsize(os.path.join(out_dir, f)) for f in os.listdir(out_dir) if not f.endswith(".import"))
    print(f"{cfg['id']}: scale {s:.4f} (draw {s / e:.3f}), {len(parts)} parts, {size / 1024:.0f} KB in {os.path.relpath(out_dir, ROOT)}")


if __name__ == "__main__":
    main(sys.argv[1], "--preview" in sys.argv)
