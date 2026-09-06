"""Selective hue-family replacement for an existing generated RGBA pet atlas.

Preserves alpha and HSV value; neutral face/eyes/outline are excluded. This is
deterministic user-requested palette editing, never animation generation.
"""
import argparse
import colorsys
import json
from pathlib import Path
from PIL import Image


def swap(image, source_hue, target_hex, hue_tolerance=0.11, min_saturation=0.12, min_value=0.45):
    target = target_hex.lstrip('#')
    if len(target) != 6:
        raise ValueError('target must be #RRGGBB')
    th, _, _ = colorsys.rgb_to_hsv(*(int(target[i:i+2], 16) / 255 for i in (0, 2, 4)))
    result = image.convert('RGBA')
    pixels = []
    changed = 0
    for r, g, b, a in result.getdata():
        h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
        distance = abs((h - source_hue + 0.5) % 1 - 0.5)
        if a and distance <= hue_tolerance and s >= min_saturation and v >= min_value:
            # Keep original brightness and saturation, including antialiased edges.
            target_hue = (th + (h - source_hue + 0.5) % 1 - 0.5) % 1
            nr, ng, nb = colorsys.hsv_to_rgb(target_hue, s, v)
            pixels.append((round(nr*255), round(ng*255), round(nb*255), a))
            changed += 1
        else:
            pixels.append((r, g, b, a))
    result.putdata(pixels)
    return result, changed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('--output', required=True, type=Path)
    parser.add_argument('--source-hue', type=float, default=0.72)
    parser.add_argument('--target', required=True)
    parser.add_argument('--hue-tolerance', type=float, default=0.11)
    args = parser.parse_args()
    source = Image.open(args.source).convert('RGBA')
    result, count = swap(source, args.source_hue, args.target, args.hue_tolerance)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    result.save(args.output, lossless=True)
    assert source.getchannel('A').tobytes() == result.getchannel('A').tobytes()
    print(json.dumps({'ok': True, 'changed_pixels': count, 'alpha_preserved': True, 'output': str(args.output)}))


if __name__ == '__main__':
    main()

