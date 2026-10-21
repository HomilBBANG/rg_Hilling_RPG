"""Dialogue portrait prep: removes a flat background and crops to the character.

    python tools/portraits/prepare_portrait.py <source image> <output .png>

Images that already have transparency keep it (alpha just tidied). Otherwise the background
colour is taken from the image border; every background-coloured region touching the border is
removed, plus large enclosed background pockets (e.g. between an arm and the head). Small light
areas inside the outline (eye whites, shirt) stay. Edge pixels are un-mixed from the background
so no light fringe is left around the dark outline. Needs Pillow, numpy, scipy.
"""
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

TOLERANCE = 14        # max per-channel difference from the background colour
HOLE_MIN = 0.0012     # enclosed pockets at least this share of the image are background too
HOLE_MATCH = 7.0      # ... if their mean difference is this small (shirts/eyes are further off)
MARGIN = 8


def remove_background(rgb: np.ndarray) -> np.ndarray:
    h, w, _ = rgb.shape
    border = np.concatenate([rgb[0], rgb[-1], rgb[:, 0], rgb[:, -1]]).astype(np.float32)
    bg = np.median(border, axis=0)
    diff = np.abs(rgb.astype(np.float32) - bg).max(axis=2)
    labels, n = ndimage.label(diff < TOLERANCE)
    edge = set(np.unique(np.concatenate([labels[0], labels[-1], labels[:, 0], labels[:, -1]]))) - {0}
    removed = np.isin(labels, list(edge))
    sizes = ndimage.sum(np.ones_like(diff), labels, index=np.arange(1, n + 1))
    means = ndimage.mean(diff, labels, index=np.arange(1, n + 1))
    for i in range(n):
        if sizes[i] >= HOLE_MIN * h * w and means[i] < HOLE_MATCH:
            removed |= labels == i + 1
    alpha = np.where(removed, 0.0, 1.0)
    # un-mix the anti-aliased rim from the background
    rim = ndimage.binary_dilation(removed, iterations=2) & ~removed
    lum = rgb.astype(np.float32) @ np.array([0.299, 0.587, 0.114])
    lbg = float(bg @ np.array([0.299, 0.587, 0.114]))
    a_rim = np.clip((lbg - lum) / max(lbg - 30.0, 1.0), 0.0, 1.0)
    alpha[rim] = np.maximum(a_rim[rim], 0.0)
    out = rgb.astype(np.float32)
    a3 = np.maximum(alpha[..., None], 1e-3)
    out = np.where(rim[..., None], (out - (1.0 - a3) * bg) / a3, out)
    return np.dstack([np.clip(out, 0, 255), alpha * 255.0]).astype(np.uint8)


def main(src: str, dst: str) -> None:
    im = Image.open(src)
    if im.mode in ("RGBA", "LA") and np.array(im.convert("RGBA"))[..., 3].min() < 250:
        rgba = np.array(im.convert("RGBA"))
        a = rgba[..., 3]
        rgba[..., 3] = np.where(a < 8, 0, np.where(a > 245, 255, a))
    else:
        rgba = remove_background(np.array(im.convert("RGB")))
    ys, xs = np.nonzero(rgba[..., 3] > 0)
    h, w = rgba.shape[:2]
    box = (max(xs.min() - MARGIN, 0), max(ys.min() - MARGIN, 0), min(xs.max() + MARGIN + 1, w), min(ys.max() + MARGIN + 1, h))
    Image.fromarray(rgba).crop(box).save(dst, optimize=True)
    print(f"{src} -> {dst} {box[2] - box[0]}x{box[3] - box[1]}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
