"""Webby's icon: two panes of glass that weave into a W, glowing where they cross.

Usage: python3 gen.py OUT.svg WIDTH HEIGHT LAYERS ROUND [MARK_SCALE]
  LAYERS     comma list of: back (background and glow), left (cyan pane),
             right (violet pane and the bright crossing)
  ROUND      1 = clip to an iOS-style rounded square, 0 = full bleed
  MARK_SCALE size of the W relative to the canvas height (default 1)
"""
import sys

out, W, H, layers, rounded = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4].split(','), sys.argv[5] == '1'
mark = float(sys.argv[6]) if len(sys.argv) > 6 and sys.argv[6] else 1.0

LEFT = "M214 300 L386 724 L558 300"
RIGHT = "M466 300 L638 724 L810 300"
ROUNDED = 'fill="none" stroke-linecap="round" stroke-linejoin="round"'
STROKE = ROUNDED + ' stroke-width="124"'
GLOW = ROUNDED + ' stroke-width="150"'

sc = H / 1024 * mark
ox, oy = W / 2 - 512 * sc, H / 2 - 512 * sc
place = f'transform="translate({ox:.2f},{oy:.2f}) scale({sc:.5f})"'

defs = f'''
<clipPath id="sq"><rect width="{W}" height="{H}" rx="{228 * W / 1024 if rounded else 0:.1f}"/></clipPath>
<linearGradient id="bg" x1="0.15" y1="0" x2="0.85" y2="1"><stop offset="0" stop-color="#25305E"/><stop offset="0.5" stop-color="#121735"/><stop offset="1" stop-color="#06070F"/></linearGradient>
<radialGradient id="sheen" cx="0.3" cy="0.05" r="0.9"><stop offset="0" stop-color="#fff" stop-opacity="0.10"/><stop offset="0.6" stop-color="#fff" stop-opacity="0"/></radialGradient>
<linearGradient id="cyan" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#7FE3FF" stop-opacity="0.96"/><stop offset="1" stop-color="#3D8BFF" stop-opacity="0.9"/></linearGradient>
<linearGradient id="violet" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#C29BFF" stop-opacity="0.96"/><stop offset="1" stop-color="#6C5CFF" stop-opacity="0.9"/></linearGradient>
<linearGradient id="rim" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#fff" stop-opacity="0.95"/><stop offset="0.5" stop-color="#fff" stop-opacity="0.15"/><stop offset="1" stop-color="#fff" stop-opacity="0.5"/></linearGradient>
<filter id="sh" x="-30%" y="-30%" width="160%" height="160%"><feDropShadow dx="0" dy="30" stdDeviation="34" flood-color="#0B0640" flood-opacity="0.6"/></filter>
<filter id="glow" x="-40%" y="-40%" width="180%" height="180%"><feGaussianBlur stdDeviation="40"/></filter>
<mask id="cross" maskUnits="userSpaceOnUse" x="0" y="0" width="1024" height="1024"><rect width="1024" height="1024" fill="#000"/><path d="{LEFT}" stroke="#fff" {STROKE}/></mask>
'''

body = ''
if 'back' in layers:
    body += f'<rect width="{W}" height="{H}" fill="url(#bg)"/><rect width="{W}" height="{H}" fill="url(#sheen)"/>'
    body += (f'<g {place}><path d="{LEFT}" stroke="#5FA8FF" {GLOW} opacity="0.5" filter="url(#glow)"/>'
             f'<path d="{RIGHT}" stroke="#9B7BFF" {GLOW} opacity="0.5" filter="url(#glow)"/></g>')
if 'left' in layers:
    body += (f'<g {place}><path d="{LEFT}" stroke="url(#cyan)" {STROKE} filter="url(#sh)"/>'
             f'<path d="{LEFT}" stroke="url(#rim)" {STROKE} opacity="0.18"/></g>')
if 'right' in layers:
    body += (f'<g {place}><path d="{RIGHT}" stroke="url(#violet)" {STROKE} filter="url(#sh)"/>'
             f'<g mask="url(#cross)"><path d="{RIGHT}" stroke="#fff" {STROKE} opacity="0.55"/></g>'
             f'<path d="{RIGHT}" stroke="url(#rim)" {STROKE} opacity="0.18"/></g>')

open(out, 'w').write(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}"><defs>{defs}</defs><g clip-path="url(#sq)">{body}</g></svg>')
