#!/usr/bin/env python3
"""Draws the icons of Ski Apex: the one the app comes with and the ones to choose from in Settings.
The drawings are those of scripts/icon_art.py: the first of them in the colors of each look of the
app, the others in the colors of the first look. (Every drawing in every color made the app eight
times heavier.)

For each icon: the 1024 px picture of its set in the asset catalog (without an alpha channel, as
the App Store wants it) and a small picture to show it in Settings. The sets are made when they
are missing. The icon of the Apple Watch app is the first one.

Needs rsvg-convert (brew install librsvg). Usage: scripts/icons.py [--svg <dir>]
With --svg it only writes the recolored drawings there, to look at them.
"""
import json
import os
import shutil
import subprocess
import sys
import tempfile

from icon_art import DESIGNS, drawing

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, 'Resources', 'Assets.xcassets')
WATCH_ICON = os.path.join(ROOT, 'Watch', 'Assets.xcassets', 'AppIcon.appiconset')

# The colors of the drawings, in the order of the lists below.
BASE = ['#1D3A5F', '#0E1D33', '#08111E',   # the sky, from the middle out
        '#3A6EA5', '#16304F',              # the peak
        '#22436B', '#0F2038',              # the mountain behind
        '#EAF6FF', '#C9E3F7',              # the snow cap and its shade
        '#5CCFFF',                         # the ski track
        '#0B1626',                         # the frame of the goggles, and what is dark
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
                              '#FFFFFF', '#DDEEFB', '#0A84C6', '#16324F', '#FFFFFF']),
]

# The part of the name of an icon that says its drawing: none for the one the app comes with.
PARTS = {'close': '', 'classic': 'Classica', 'mirror': 'Specchio', 'snow': 'SullaNeve'}


def icon_set(design, name):
    """AppIcon, AppIcon-Aurora, AppIcon-Classica, AppIcon-Classica-Aurora..."""
    part = PARTS[design]
    return 'AppIcon' + ('-' + part if part else '') + name[len('AppIcon'):]


def preview_set(design, look):
    return 'IconPreview-%s' % look if design == 'close' else 'IconPreview-%s-%s' % (design, look)


def ensure(folder, filename, icon):
    """The set of the asset catalog a picture goes in, with what Xcode wants to know of it."""
    os.makedirs(folder, exist_ok=True)
    image = {'filename': filename, 'idiom': 'universal'}
    if icon:
        image.update(platform='ios', size='1024x1024')
    with open(os.path.join(folder, 'Contents.json'), 'w', encoding='utf-8') as f:
        json.dump({'images': [image], 'info': {'author': 'xcode', 'version': 1}}, f, indent=2)
        f.write('\n')


def looks_of(design):
    """The looks a drawing comes in: all of them for the first, the first for the others."""
    return ICONS if design == DESIGNS[0] else ICONS[:1]


def alternates():
    """The names of every icon but the first, for ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES."""
    return [icon_set(design, name) for design in DESIGNS for name, _, _ in looks_of(design)][1:]


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


def flatten(pngs):
    """Without the alpha channel, as the App Store wants the icons (on a Mac: scripts/flatten.swift)."""
    if not pngs or not shutil.which('swift') or not shutil.which('sips'):
        return
    subprocess.run(['swift', os.path.join(ROOT, 'scripts', 'flatten.swift')] + pngs, check=True)
    for png in pngs:
        told = subprocess.run(['sips', '-g', 'hasAlpha', png], check=True, capture_output=True, text=True).stdout
        assert 'hasAlpha: no' in told, told


def main():
    if len(sys.argv) > 1 and sys.argv[1] == '--names':
        print(' '.join(alternates()))
        return
    only_svg = sys.argv[2] if len(sys.argv) > 2 and sys.argv[1] == '--svg' else None
    work = only_svg or tempfile.mkdtemp()
    os.makedirs(work, exist_ok=True)
    made = []
    for design in DESIGNS:
        svg = drawing(design)
        for name, look, colors in looks_of(design):
            assert len(colors) == len(BASE), name
            name = icon_set(design, name)
            file = os.path.join(work, name + '.svg')
            with open(file, 'w', encoding='utf-8') as f:
                f.write(recolor(svg, colors))
            if only_svg:
                continue
            folder = os.path.join(ASSETS, name + '.appiconset')
            ensure(folder, 'icon-1024.png', icon=True)
            icon = os.path.join(folder, 'icon-1024.png')
            render(file, 1024, colors[2], icon)
            made.append(icon)
            small = os.path.join(ASSETS, preview_set(design, look) + '.imageset')
            ensure(small, 'icon.png', icon=False)
            render(file, 240, colors[2], os.path.join(small, 'icon.png'))
            print('  ' + name)
    flatten(made)
    if made and os.path.isdir(WATCH_ICON):
        shutil.copyfile(made[0], os.path.join(WATCH_ICON, 'icon-1024.png'))


if __name__ == '__main__':
    main()
