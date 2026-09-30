#!/usr/bin/env python3
"""Contact sheets for reviewing snapshots.

  sheet.py <out.png> <img>...                grid, 4 per row, numbered
  sheet.py --rows <out.png> <label>=<img>...  stack sheets vertically, labeled
"""
import sys
from PIL import Image, ImageDraw


def grid(out, paths, cols=4):
    ims = [Image.open(p).convert("RGB") for p in paths]
    w, h = ims[0].size
    rows = (len(ims) + cols - 1) // cols
    sheet = Image.new("RGB", (w * min(cols, len(ims)), h * rows))
    for i, im in enumerate(ims):
        x, y = (i % cols) * w, (i // cols) * h
        sheet.paste(im.resize((w, h)), (x, y))
        ImageDraw.Draw(sheet).text((x + 2, y + 2), str(i), fill=(255, 0, 0))
    sheet.save(out)


def rows(out, items):
    ims = []
    for item in items:
        label, path = item.split("=", 1)
        ims.append((label, Image.open(path).convert("RGB")))
    w = max(im.width for _, im in ims)
    sheet = Image.new("RGB", (w, sum(im.height for _, im in ims)))
    y = 0
    for label, im in ims:
        sheet.paste(im, (0, y))
        ImageDraw.Draw(sheet).text((2, y + 2), label, fill=(255, 0, 0))
        y += im.height
    sheet.save(out)


if sys.argv[1] == "--rows":
    rows(sys.argv[2], sys.argv[3:])
else:
    grid(sys.argv[1], sys.argv[2:])
