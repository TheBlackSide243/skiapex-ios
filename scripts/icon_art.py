#!/usr/bin/env python3
"""The drawings of the icon of Ski Apex: ski goggles, with the night, the peak and the snow seen in
their lens. Four of them, to choose from in Settings:

  close    the goggles from close, turned, the peak and its run in a mirror lens (the icon the
           app comes with)
  classic  the goggles in the middle of the night, the peak to one side and the slope in the lens
  mirror   the goggles bigger, with a mirror lens, the peak and its run in it
  snow     the goggles lying on the snow, the night and the peak in the lens

Only the twelve colors of scripts/icons.py are used, with white and black over them for the light
and the shade, so that every look of the app can recolor a drawing.

Usage: scripts/icon_art.py <out.svg> [close|classic|mirror|snow]
"""
import sys

SKY = ['#1D3A5F', '#0E1D33', '#08111E']
PEAK = ['#3A6EA5', '#16304F']
BACK = ['#22436B', '#0F2038']
SNOW, SHADE = '#EAF6FF', '#C9E3F7'
ACCENT, DARK, STAR = '#5CCFFF', '#0B1626', '#F2F6FB'

DESIGNS = ['close', 'classic', 'mirror', 'snow']

DEFS = f'''
    <radialGradient id="sky" cx="0.6" cy="0.2" r="1.0">
      <stop offset="0" stop-color="{SKY[0]}"/>
      <stop offset="0.5" stop-color="{SKY[1]}"/>
      <stop offset="1" stop-color="{SKY[2]}"/>
    </radialGradient>
    <radialGradient id="glow" cx="0.5" cy="0.5" r="0.5">
      <stop offset="0" stop-color="{PEAK[0]}" stop-opacity="0.8"/>
      <stop offset="1" stop-color="{PEAK[0]}" stop-opacity="0"/>
    </radialGradient>
    <linearGradient id="lit" x1="0.6" y1="0" x2="0.2" y2="1">
      <stop offset="0" stop-color="{PEAK[0]}"/>
      <stop offset="1" stop-color="{PEAK[1]}"/>
    </linearGradient>
    <linearGradient id="dim" x1="0" y1="0" x2="0.6" y2="1">
      <stop offset="0" stop-color="{PEAK[1]}"/>
      <stop offset="1" stop-color="{BACK[1]}"/>
    </linearGradient>
    <linearGradient id="back" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="{BACK[0]}"/>
      <stop offset="1" stop-color="{BACK[1]}"/>
    </linearGradient>
    <linearGradient id="slope" x1="0.1" y1="0" x2="0.75" y2="1">
      <stop offset="0" stop-color="{SNOW}"/>
      <stop offset="1" stop-color="{SHADE}"/>
    </linearGradient>
    <radialGradient id="edge" cx="0.5" cy="0.45" r="0.75">
      <stop offset="0.62" stop-color="black" stop-opacity="0"/>
      <stop offset="1" stop-color="black" stop-opacity="0.45"/>
    </radialGradient>
    <filter id="soft" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="16"/></filter>
    <filter id="softer" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="34"/></filter>
    <filter id="fine" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="5"/></filter>
    <filter id="dust" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="2.2"/></filter>'''

STARS = f'''
  <circle cx="232" cy="150" r="20" fill="{STAR}" opacity="0.25" filter="url(#fine)"/>
  <circle cx="232" cy="150" r="8" fill="{STAR}" opacity="0.95"/>
  <circle cx="420" cy="92" r="5" fill="{STAR}" opacity="0.6"/>
  <circle cx="120" cy="290" r="5" fill="{STAR}" opacity="0.5"/>
  <circle cx="930" cy="130" r="6" fill="{STAR}" opacity="0.7"/>
  <circle cx="860" cy="300" r="4" fill="{STAR}" opacity="0.45"/>
  <circle cx="330" cy="290" r="3.5" fill="{STAR}" opacity="0.4"/>'''

LENS = ('M 150 430 C 150 330 220 300 330 300 L 694 300 C 804 300 874 330 874 430 L 874 560 '
        'C 874 664 800 724 700 724 C 620 724 580 664 512 664 C 444 664 404 724 324 724 C 224 724 150 664 150 560 Z')


def scene_peak():
    """The night, the peak to one side and the slope with a track."""
    return f'''
      <rect x="-200" y="-200" width="1424" height="1424" fill="url(#night)"/>
      <ellipse cx="610" cy="430" rx="300" ry="220" fill="url(#glow)"/>
      <circle cx="300" cy="370" r="6" fill="{STAR}" opacity="0.9"/>
      <circle cx="420" cy="340" r="4" fill="{STAR}" opacity="0.6"/>
      <circle cx="800" cy="372" r="4" fill="{STAR}" opacity="0.6"/>
      <path d="M 180 640 L 360 430 L 440 520 L 500 470 L 640 640 Z" fill="url(#back)" opacity="0.85"/>
      <path d="M 610 330 L 420 650 L 610 680 Z" fill="url(#lit)"/>
      <path d="M 610 330 L 610 680 L 880 660 Z" fill="url(#dim)"/>
      <path d="M 610 330 L 540 448 L 566 440 L 580 472 L 598 448 L 610 480 Z" fill="{SNOW}"/>
      <path d="M 610 330 L 610 480 L 626 452 L 648 478 L 664 454 L 694 474 Z" fill="{SHADE}"/>
      <path d="M 100 560 C 320 590 620 650 900 700 L 900 780 L 100 780 Z" fill="url(#slope)"/>
      <path d="M 100 562 C 320 592 620 652 900 702" fill="none" stroke="white" stroke-width="6" opacity="0.9"/>
      <path d="M 130 610 C 250 606 300 660 420 668 C 520 676 560 700 640 730" fill="none" stroke="{ACCENT}" stroke-width="16" stroke-linecap="round"/>'''


def scene_run():
    """The night and the peak in the middle, with the track of a run glowing down from its top."""
    run = 'M 512 352 C 566 420 462 470 520 540 C 578 610 440 650 500 740'
    return f'''
      <rect x="-200" y="-200" width="1424" height="1424" fill="url(#night)"/>
      <ellipse cx="512" cy="450" rx="340" ry="250" fill="url(#glow)"/>
      <circle cx="250" cy="372" r="6" fill="{STAR}" opacity="0.9"/>
      <circle cx="350" cy="336" r="4" fill="{STAR}" opacity="0.6"/>
      <circle cx="770" cy="360" r="5" fill="{STAR}" opacity="0.7"/>
      <circle cx="690" cy="330" r="3.5" fill="{STAR}" opacity="0.5"/>
      <path d="M 120 720 L 300 470 L 372 560 L 430 510 L 560 720 Z" fill="url(#back)" opacity="0.85"/>
      <path d="M 520 720 L 720 480 L 790 560 L 920 720 Z" fill="url(#back)"/>
      <path d="M 512 324 L 250 760 L 512 760 Z" fill="url(#lit)"/>
      <path d="M 512 324 L 512 760 L 780 760 Z" fill="url(#dim)"/>
      <path d="M 512 324 L 400 620 L 512 760 Z" fill="black" opacity="0.1"/>
      <path d="M 512 324 L 414 488 L 446 474 L 464 512 L 492 482 L 512 524 Z" fill="{SNOW}"/>
      <path d="M 512 324 L 512 524 L 534 488 L 560 520 L 582 490 L 612 508 Z" fill="{SHADE}"/>
      <path d="M 512 324 L 512 524 L 534 488 L 560 520 L 582 490 L 612 508 Z" fill="{PEAK[0]}" opacity="0.3"/>
      <path d="{run}" fill="none" stroke="{ACCENT}" stroke-width="46" stroke-linecap="round" opacity="0.45" filter="url(#fine)"/>
      <path d="{run}" fill="none" stroke="{ACCENT}" stroke-width="20" stroke-linecap="round"/>
      <path d="{run}" fill="none" stroke="white" stroke-width="5" stroke-linecap="round" opacity="0.6" transform="translate(-4 -3)"/>
      <circle cx="512" cy="350" r="19" fill="{ACCENT}"/>
      <circle cx="512" cy="350" r="7" fill="{DARK}"/>
      <path d="M 100 690 C 300 660 420 716 512 716 C 620 716 740 664 920 692 L 920 800 L 100 800 Z" fill="url(#slope)" opacity="0.95"/>
      <path d="M 100 690 C 300 660 420 716 512 716 C 620 716 740 664 920 692" fill="none" stroke="white" stroke-width="5" opacity="0.9"/>'''


def goggles(place, scene, mirror=False, shade=0.55):
    """The goggles, put on the icon by `place` (a transform about its middle)."""
    tint = f'''
      <path d="{LENS}" fill="url(#mirror)"/>''' if mirror else ''
    return f'''
  <g transform="{place}">
    <!-- The strap, going off to both sides. -->
    <path d="M -600 300 L 190 404 L 190 618 L -600 730 Z" fill="{ACCENT}"/>
    <path d="M 1624 300 L 834 404 L 834 618 L 1624 730 Z" fill="{ACCENT}"/>
    <path d="M -600 300 L 190 404 L 190 452 L -600 366 Z" fill="white" opacity="0.3"/>
    <path d="M 1624 300 L 834 404 L 834 452 L 1624 366 Z" fill="white" opacity="0.3"/>
    <path d="M -600 484 L 190 498 L 190 534 L -600 552 Z" fill="{DARK}" opacity="0.85"/>
    <path d="M 1624 484 L 834 498 L 834 534 L 1624 552 Z" fill="{DARK}" opacity="0.85"/>
    <path d="M -600 660 L 190 580 L 190 618 L -600 730 Z" fill="black" opacity="0.25"/>
    <path d="M 1624 660 L 834 580 L 834 618 L 1624 730 Z" fill="black" opacity="0.25"/>
    <!-- The frame, with its shade under it. -->
    <path d="{LENS}" fill="black" opacity="{shade}" filter="url(#softer)" transform="translate(512 512) scale(1.12) translate(-512 -474)"/>
    <path d="{LENS}" fill="{DARK}" transform="translate(512 512) scale(1.13) translate(-512 -512)"/>
    <path d="{LENS}" fill="{PEAK[1]}" transform="translate(512 512) scale(1.13) translate(-512 -518)" opacity="0.9"/>
    <path d="{LENS}" fill="{DARK}" transform="translate(512 512) scale(1.07) translate(-512 -512)"/>
    <!-- The lens, and what is seen in it. -->
    <g clip-path="url(#lens)">{scene}{tint}
      <path d="M 150 300 L 874 300 L 874 430 C 640 380 380 400 150 500 Z" fill="white" opacity="0.13"/>
      <path d="M 250 280 L 360 280 L 250 740 L 140 740 Z" fill="white" opacity="0.16"/>
      <path d="M 396 280 L 430 280 L 320 740 L 286 740 Z" fill="white" opacity="0.12"/>
      <path d="{LENS}" fill="none" stroke="black" stroke-width="40" opacity="0.35" filter="url(#fine)"/>
    </g>
    <path d="{LENS}" fill="none" stroke="white" stroke-width="5" opacity="0.35"/>
    <path d="M 196 366 C 232 326 280 316 340 314" fill="none" stroke="white" stroke-width="12" stroke-linecap="round" opacity="0.6"/>
  </g>'''


def page(what, behind, art, edge=True):
    more = f'''
    <clipPath id="lens"><path d="{LENS}"/></clipPath>
    <linearGradient id="night" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="{SKY[2]}"/>
      <stop offset="0.55" stop-color="{SKY[0]}"/>
      <stop offset="1" stop-color="{SKY[1]}"/>
    </linearGradient>
    <linearGradient id="mirror" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="{ACCENT}" stop-opacity="0.34"/>
      <stop offset="0.55" stop-color="{ACCENT}" stop-opacity="0.04"/>
      <stop offset="1" stop-color="{PEAK[0]}" stop-opacity="0.18"/>
    </linearGradient>
    <linearGradient id="ground" x1="0.1" y1="0" x2="0.8" y2="1">
      <stop offset="0" stop-color="{SNOW}"/>
      <stop offset="1" stop-color="{SHADE}"/>
    </linearGradient>'''
    last = '\n  <rect width="1024" height="1024" fill="url(#edge)"/>' if edge else ''
    return f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" width="1024" height="1024">
  <!-- Ski Apex: {what}. iOS rounds the corners itself. -->
  <defs>{DEFS}{more}
  </defs>{behind}{art}{last}
</svg>
'''


NIGHT = f'''
  <rect width="1024" height="1024" fill="url(#sky)"/>
  <ellipse cx="512" cy="500" rx="560" ry="420" fill="url(#glow)"/>{STARS}'''

ON_SNOW = f'''
  <rect width="1024" height="1024" fill="url(#ground)"/>
  <ellipse cx="260" cy="200" rx="420" ry="260" fill="white" opacity="0.9" filter="url(#softer)"/>
  <ellipse cx="820" cy="900" rx="520" ry="240" fill="{PEAK[0]}" opacity="0.3" filter="url(#softer)"/>
  <path d="M -40 760 C 240 700 520 860 1064 800" fill="none" stroke="{PEAK[0]}" stroke-width="60" opacity="0.14" filter="url(#soft)"/>
  <path d="M -40 250 C 300 190 700 300 1064 220" fill="none" stroke="white" stroke-width="40" opacity="0.8" filter="url(#soft)"/>'''


def drawing(design):
    """The drawing of a design, as SVG, in the colors of the look "Notte"."""
    middle = 'translate(512 512) {} translate(-512 -512)'
    if design == 'classic':
        return page('ski goggles at night, the peak and the slope in their lens', NIGHT, goggles(middle.format(''), scene_peak()))
    if design == 'mirror':
        return page('ski goggles with a mirror lens at night, the peak and its run in the lens', NIGHT,
                    goggles(middle.format('scale(1.16)'), scene_run(), mirror=True))
    if design == 'snow':
        return page('ski goggles lying on the snow, the night and the peak in their lens', ON_SNOW,
                    goggles(middle.format('rotate(-9) scale(1.1)'), scene_peak(), shade=0.4), edge=False)
    if design == 'close':
        return page('ski goggles from close, turned, the peak and its run in the lens', NIGHT,
                    goggles('translate(512 520) rotate(-11) scale(1.48) translate(-512 -512)', scene_run(), mirror=True))
    raise SystemExit('one of: ' + ', '.join(DESIGNS))


if __name__ == '__main__':
    with open(sys.argv[1], 'w', encoding='utf-8', newline=chr(10)) as out:
        out.write(drawing(sys.argv[2] if len(sys.argv) > 2 else 'close'))
