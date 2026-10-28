"""Shared helpers for turning character art sheets into game sprites.

Backgrounds in the source art are flat gray. `cut_background` removes the gray that is connected
to the image border (so gray *inside* a character, e.g. a highlight, is kept), with a soft edge.
"""
import numpy as np
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage


def load_rgb(path):
    return np.asarray(Image.open(path).convert("RGB")).astype(np.int16)


def background_color(rgb):
    edge = np.concatenate([rgb[0], rgb[-1], rgb[:, 0], rgb[:, -1]])
    return np.median(edge, axis=0)


def cut_background(rgb, tol=26, soften=1):
    """Returns an alpha mask (0..255) with the border-connected background removed."""
    bg = background_color(rgb)
    dist = np.sqrt(((rgb - bg) ** 2).sum(axis=2))
    near_bg = dist < tol
    labels, _ = ndimage.label(near_bg)
    border = set(np.unique(np.concatenate([labels[0], labels[-1], labels[:, 0], labels[:, -1]]))) - {0}
    background = np.isin(labels, list(border))
    fg = ~background
    fg = ndimage.binary_fill_holes(fg)
    fg = ndimage.binary_opening(fg, iterations=1)        # drop single-pixel specks
    alpha = fg.astype(np.float32)
    if soften:
        alpha = ndimage.gaussian_filter(alpha, soften * 0.6)
        alpha = np.clip((alpha - 0.15) / 0.7, 0, 1)
    return (alpha * 255).astype(np.uint8)


def components(alpha, min_area=1500):
    """Separate pieces on a parts sheet: [(index, (x0, y0, x1, y1), area), ...] sorted by position."""
    labels, n = ndimage.label(alpha > 128)
    out = []
    for i, sl in enumerate(ndimage.find_objects(labels), start=1):
        area = int((labels[sl] == i).sum())
        if area >= min_area:
            out.append((i, (sl[1].start, sl[0].start, sl[1].stop, sl[0].stop), area))
    out.sort(key=lambda c: (c[1][1] // 120, c[1][0]))
    return labels, out


def preview(rgb, comps, path):
    im = Image.fromarray(rgb.astype(np.uint8)).convert("RGB")
    d = ImageDraw.Draw(im)
    for n, (_, (x0, y0, x1, y1), area) in enumerate(comps):
        d.rectangle([x0, y0, x1, y1], outline=(255, 0, 0), width=3)
        d.rectangle([x0, y0, x0 + 46, y0 + 30], fill=(255, 0, 0))
        d.text((x0 + 6, y0 + 4), str(n), fill=(255, 255, 255), font=ImageFont.load_default(size=22))
    im.save(path)


def cap_mask(rgb, alpha, min_area=300):
    """The flat dark mauve-brown ellipses the source art uses as joint 'caps' (cut ends)."""
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    m = (r >= 55) & (r <= 135) & (g >= 35) & (g <= 95) & (b >= 38) & (b <= 95)
    m &= (r - g >= 12) & (r - g <= 48) & (np.abs(g - b) <= 16) & (alpha > 128)
    m = ndimage.binary_opening(m, iterations=2)
    labels, n = ndimage.label(m)
    keep = np.zeros_like(m)
    for i, sl in enumerate(ndimage.find_objects(labels), start=1):
        blob = labels[sl] == i
        if blob.sum() >= min_area:
            keep[sl] |= blob
    return ndimage.binary_closing(keep, iterations=2)


def blobs(mask, min_area=300):
    """Centroid and size of each blob in a mask: [((cx, cy), area, (x0, y0, x1, y1)), ...]"""
    labels, n = ndimage.label(mask)
    out = []
    for i, sl in enumerate(ndimage.find_objects(labels), start=1):
        blob = labels[sl] == i
        area = int(blob.sum())
        if area >= min_area:
            cy, cx = ndimage.center_of_mass(blob)
            out.append(((round(cx + sl[1].start), round(cy + sl[0].start)), area,
                        (sl[1].start, sl[0].start, sl[1].stop, sl[0].stop)))
    return out
