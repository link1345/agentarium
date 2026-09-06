"""Assemble generated RGBA frames; never removes or replaces a background."""
import argparse
import json
from pathlib import Path
from PIL import Image

COUNTS = [6, 8, 8, 4, 5, 8, 6, 6, 6, 8, 8]

def read_frame(path):
    with Image.open(path) as source:
        if 'A' not in source.getbands():
            raise ValueError(f'{path}: native alpha required')
        image = source.convert('RGBA')
    alpha = image.getchannel('A')
    histogram = alpha.histogram()
    if histogram[0] < image.width * image.height * .1 or not alpha.getbbox():
        raise ValueError(f'{path}: missing transparent margins or empty frame')
    bounds = alpha.getbbox()
    if bounds[0] == 0 or bounds[1] == 0 or bounds[2] == image.width or bounds[3] == image.height:
        raise ValueError(f'{path}: source touches canvas edge')
    return image.crop(bounds)

def assemble(manifest_path, output):
    manifest_path, output = Path(manifest_path), Path(output)
    manifest = json.loads(manifest_path.read_text(encoding='utf-8-sig'))
    rows = manifest['rows']
    if len(rows) != 11 or [len(row) for row in rows] != COUNTS:
        raise ValueError('Exact v2 row counts required')
    paths = [path for row in rows for path in row] + [manifest['neutral']]
    frames = [read_frame(manifest_path.parent / path) for path in paths]
    scale = min(176 / max(f.width for f in frames), 192 / max(f.height for f in frames))
    atlas = Image.new('RGBA', (1536, 2288))
    locations = [(col, row) for row, count in enumerate(COUNTS) for col in range(count)] + [(6, 0)]
    for frame, (col, row) in zip(frames, locations):
        frame = frame.resize((max(1, round(frame.width * scale)), max(1, round(frame.height * scale))), Image.Resampling.LANCZOS)
        atlas.alpha_composite(frame, (col * 192 + (192-frame.width)//2, row * 208 + 200-frame.height))
    output.parent.mkdir(parents=True, exist_ok=True)
    atlas.save(output, lossless=True)
    report = {'nativeAlpha': True, 'backgroundRemoval': False, 'frames': len(frames), 'sharedScale': scale,
              'width': atlas.width, 'height': atlas.height, 'visualQARequired': True}
    output.with_suffix('.alpha.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    return report

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('manifest', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    print(json.dumps(assemble(args.manifest, args.output)))
