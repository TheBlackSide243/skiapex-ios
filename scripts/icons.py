#!/usr/bin/env python3
"""Draws the icons of Ski Apex from icon.svg: the one the app comes with and the ones to choose
from in Settings, each in the colors of a look of the app.

For each icon: the 1024 px picture of its set in the asset catalog (without an alpha channel, as
the App Store wants it) and a small picture to show it in Settings. The icon of the Apple Watch
app is the first one.

Needs rsvg-convert (brew install librsvg). Usage: scripts/icons.py [--svg <dir>]
With --svg it only writes the recolored drawings there, to look at them.
"""
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, 'Resources', 'Assets.xcassets')
WATCH_ICON = os.path.join(ROOT, 'Watch', 'Assets.xcassets', 'AppIcon.appiconset')

# The colors of icon.svg, in the order of the lists below.
BASE = ['#1D3A5F', '#0E1D33', '#08111E',   # the sky, from the middle out
        '#3A6EA5', '#16304F',              # the peak
        '#22436B', '#0F2038',              # the mountain behind
        '#EAF6FF', '#C9E3F7',              # the snow cap and its shade
        '#5CCFFF',                         # the ski track
        '#0B1626',                         # the dot at the top
        '#F2F6FB']                         # the stars

# set in the asset catalog, look of the app (`Look.rawValue`), colors
ICONS = [
    ('AppIcon', 'night', BASE),
    ('AppIcon-Aurora', 'aurora', ['#17564F', '#0B2A2C', '#061214', '#2F8F86', '#123B3C', '#1C5A58', '#0B2527',
                                  '#EFFFFA', '#BFEDE2', '#5EEAD4', '#0A1A1C', '#EFFAF8']),
    ('AppIcon-Alba', 'sunrise', ['#8A4466', '#3A1D3F', '#140C18', '#9A5282', '#3A2046', '#5B2F58', '#22132B',
                                 '#FFF1E8', '#FFD2BF', '#FF9F6B', '#1C1220', '#FBF3F1']),
    ('AppIcon-Bosco', 'forest', ['#27583F', '#12281B', '#0A130D', '#3F7F55', '#173524', '#28563A', '#0E2016',
                                 '#F3FFE9', '#CFEBC0', '#A3E635', '#0F1A13', '#F1F7F0']),
    ('AppIcon-Carbone', 'carbon', ['#2E2E33', '#111113', '#000000', '#5A5A62', '#1E1E22', '#34343A', '#0C0C0E',
                                   '#FFFFFF', '#CFCFD6', '#FFD60A', '#000000', '#F5F5F7']),
    ('AppIcon-Neve', 'snow', ['#FFFFFF', '#E3EFFA', '#C3DAEE', '#7FB2E0', '#3F7FBF', '#A9CBE8', '#7AA7D0',
                              '#FFFFFF', '#DDEEFB', '#0A84C6', '#FFFFFF', '#FFFFFF']),
]


def recolor(svg, colors):
    # Through placeholders, so that a color put in is not taken for one still to change.
    for i, old in enumerate(BASE):
        assert old in svg, old
        svg = svg.replace(old, '@@%d@@' % i)
    for i, new in enumerate(colors):
        svg = svg.replace('@@%d@@' % i, new)
    return svg


def render(svg_file, size, background, out):
    os.makedirs(os.path.dirname(out), exist_ok=True)
    subprocess.run(['rsvg-convert', '-w', str(size), '-h', str(size), '-b', background, svg_file, '-o', out], check=True)


def flatten(png):
    """Without the alpha channel: through JPEG and back (sips, on a Mac)."""
    if not shutil.which('sips'):
        return
    jpg = png + '.jpg'
    subprocess.run(['sips', '-s', 'format', 'jpeg', '-s', 'formatOptions', '100', png, '--out', jpg],
                   check=True, stdout=subprocess.DEVNULL)
    subprocess.run(['sips', '-s', 'format', 'png', jpg, '--out', png], check=True, stdout=subprocess.DEVNULL)
    os.remove(jpg)


def main():
    svg = open(os.path.join(ROOT, 'icon.svg'), encoding='utf-8').read()
    only_svg = sys.argv[2] if len(sys.argv) > 2 and sys.argv[1] == '--svg' else None
    work = only_svg or tempfile.mkdtemp()
    os.makedirs(work, exist_ok=True)
    for name, look, colors in ICONS:
        assert len(colors) == len(BASE), name
        drawing = os.path.join(work, name + '.svg')
        with open(drawing, 'w', encoding='utf-8') as f:
            f.write(recolor(svg, colors))
        if only_svg:
            continue
        icon = os.path.join(ASSETS, name + '.appiconset', 'icon-1024.png')
        render(drawing, 1024, colors[2], icon)
        flatten(icon)
        render(drawing, 240, colors[2], os.path.join(ASSETS, 'IconPreview-%s.imageset' % look, 'icon.png'))
        if name == 'AppIcon' and os.path.isdir(WATCH_ICON):
            shutil.copyfile(icon, os.path.join(WATCH_ICON, 'icon-1024.png'))
        print('  ' + name)


if __name__ == '__main__':
    main()
