import math, sys, json
W, H = int(sys.argv[2]), int(sys.argv[3]); LAYERS = sys.argv[4].split(','); SMALL = sys.argv[5] == '1'; ROUND = sys.argv[6] == '1'
# TV screen frame
X0, Y0, X1, Y1, R = 168, 258, 856, 726, 86
cx, cy = 512, 492
def frame_pt(ang):
    # ray from centre to frame (rect, ignoring corner rounding but pulled in a touch at corners)
    dx, dy = math.cos(ang), math.sin(ang)
    tx = ((X1 - cx) if dx > 0 else (X0 - cx)) / dx if abs(dx) > 1e-6 else 1e9
    ty = ((Y1 - cy) if dy > 0 else (Y0 - cy)) / dy if abs(dy) > 1e-6 else 1e9
    t = min(tx, ty)
    x, y = cx + dx * t, cy + dy * t
    # keep anchors off the rounded corners
    if abs(x - cx) > (X1 - X0) / 2 - R * 0.55 and abs(y - cy) > (Y1 - Y0) / 2 - R * 0.55:
        t *= 0.9; x, y = cx + dx * t, cy + dy * t
    return x, y, t
angles = [math.radians(a) for a in (-90, -38, 0, 38, 90, 142, 180, 218)]
anchors = [frame_pt(a) for a in angles]
rings = [0.57] if SMALL else [0.3, 0.57, 0.84]
radials = ''.join(f'<line x1="{cx}" y1="{cy}" x2="{x:.1f}" y2="{y:.1f}"/>' for x, y, _ in anchors)
def ring_path(f):
    pts = [(cx + (x - cx) * f, cy + (y - cy) * f) for x, y, _ in anchors]
    d = f'M{pts[0][0]:.1f},{pts[0][1]:.1f}'
    for i in range(len(pts)):
        a, b = pts[i], pts[(i + 1) % len(pts)]
        mx, my = (a[0] + b[0]) / 2, (a[1] + b[1]) / 2
        sag = 0.16  # threads sag toward the centre
        qx, qy = mx + (cx - mx) * sag, my + (cy - my) * sag
        d += f' Q{qx:.1f},{qy:.1f} {b[0]:.1f},{b[1]:.1f}'
    return d + 'Z'
ringsvg = ''.join(f'<path d="{ring_path(f)}"/>' for f in rings)
# pointer caught on the web: top-right radial, second ring
px = cx + (anchors[1][0] - cx) * 0.57; py = cy + (anchors[1][1] - cy) * 0.57
dews = [(5, 0.57), (6, 0.84), (3, 0.3), (7, 0.3), (0, 0.84)]
dewsvg = ''.join(f'<circle cx="{cx + (anchors[i][0]-cx)*f:.1f}" cy="{cy + (anchors[i][1]-cy)*f:.1f}" r="{14 if f>0.5 else 11}"/>' for i, f in dews)

MARK = float(sys.argv[7]) if len(sys.argv) > 7 else 1.0
sc = H / 1024 * MARK; ox = (W - 1024 * sc) / 2; oy = H / 2 - 527 * sc
defs = open(__import__('os').path.join(__import__('os').path.dirname(__file__), 'defs.txt')).read()
back = '<rect width="1024" height="1024" fill="url(#bg)"/><circle cx="512" cy="492" r="430" fill="#4C3BD0" opacity="0.18" filter="url(#bigglow)"/>'
rw, fw = (24, 60) if SMALL else (14, 40)
mid = f'''<g filter="url(#sh)">
  <rect x="{X0}" y="{Y0}" width="{X1-X0}" height="{Y1-Y0}" rx="{R}" fill="url(#screen)"/>
  <g fill="none" stroke="url(#silk)" stroke-linecap="round" filter="url(#glow)">
    <g stroke-width="{rw}" opacity="0.95">{radials}</g>
    <g stroke-width="{rw-2}" opacity="0.92">{ringsvg}</g>
  </g>
  {'' if SMALL else f'<g fill="#DDF8FF" filter="url(#glow)" opacity="0.95">{dewsvg}<circle cx="{cx}" cy="{cy}" r="16"/></g>'}
  <rect x="{X0}" y="{Y0}" width="{X1-X0}" height="{Y1-Y0}" rx="{R}" fill="none" stroke="url(#frame)" stroke-width="{fw}"/>
  <rect x="440" y="{Y1+44}" width="144" height="{40 if SMALL else 26}" rx="13" fill="url(#frame)" opacity="0.9"/>
</g>'''
k = 1.35 if SMALL else 1
front = f'''<circle cx="{px:.1f}" cy="{py:.1f}" r="{110*k:.0f}" fill="#FFB534" opacity="0.6" filter="url(#bigglow)"/>
<circle cx="{px:.1f}" cy="{py:.1f}" r="{74*k:.0f}" fill="none" stroke="#FFD27A" stroke-width="{15*k:.0f}" opacity="0.9"/>
<circle cx="{px:.1f}" cy="{py:.1f}" r="{48*k:.0f}" fill="url(#amber)"/>
<circle cx="{px-14*k:.1f}" cy="{py-16*k:.1f}" r="{13*k:.0f}" fill="#fff" opacity="0.85"/>'''
body = ''
if 'back' in LAYERS:
    body += f'<g transform="scale({W/1024},{H/1024})">{back}</g>'
inner = (mid if 'mid' in LAYERS else '') + (front if 'front' in LAYERS else '')
body += f'<g transform="translate({ox:.2f},{oy:.2f}) scale({sc})">{inner}</g>'
if 'gloss' in LAYERS:
    body += f'<rect width="{W}" height="{H}" fill="url(#gloss)"/>'
clip = f'<clipPath id="sq"><rect width="{W}" height="{H}" rx="{228*W/1024 if ROUND else 0}"/></clipPath>'
svg = f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}"><defs>{clip}{defs}</defs><g clip-path="url(#sq)">{body}</g></svg>'
open(sys.argv[1], 'w').write(svg)
