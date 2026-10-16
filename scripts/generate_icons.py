import json, os, sys, math
from PIL import Image, ImageDraw, ImageFilter

root = sys.argv[1]
cat = os.path.join(root, "Webby/Resources/Assets.xcassets")
brand = os.path.join(cat, "App Icon & Top Shelf Image.brandassets")
info = {"info": {"author": "xcode", "version": 1}}

def wjson(path, obj):
    os.makedirs(path, exist_ok=True)
    with open(os.path.join(path, "Contents.json"), "w") as f:
        json.dump(obj, f, indent=2)

def gradient(w, h, c1, c2):
    img = Image.new("RGB", (w, h))
    px = img.load()
    for y in range(h):
        for x in range(0, w):
            t = (x / w * 0.55 + y / h * 0.45)
            px[x, y] = tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3))
    return img

def fast_gradient(w, h, c1, c2):
    small = gradient(160, max(2, int(160 * h / w)), c1, c2)
    return small.resize((w, h), Image.BICUBIC)

def back(w, h):
    img = fast_gradient(w, h, (40, 16, 90), (0, 170, 200)).convert("RGBA")
    glow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(glow)
    r = int(h * 0.7)
    d.ellipse([w * 0.75 - r, -r * 0.6, w * 0.75 + r, r * 1.4], fill=(120, 200, 255, 70))
    glow = glow.filter(ImageFilter.GaussianBlur(h * 0.12))
    return Image.alpha_composite(img, glow)

def middle(w, h):
    s = 4
    img = Image.new("RGBA", (w * s, h * s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx, cy, r = w * s / 2, h * s / 2, h * s * 0.34
    lw = int(h * s * 0.03)
    col = (255, 255, 255, 230)
    d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=col, width=lw)
    for k in (0.42, 0.78):
        d.ellipse([cx - r * k, cy - r, cx + r * k, cy + r], outline=(255, 255, 255, 150), width=lw // 2)
    d.line([cx, cy - r, cx, cy + r], fill=(255, 255, 255, 150), width=lw // 2)
    for f in (-0.5, 0, 0.5):
        y = cy + r * f
        half = math.sqrt(max(0, r * r - (r * f) ** 2))
        d.line([cx - half, y, cx + half, y], fill=(255, 255, 255, 150), width=lw // 2)
    return img.resize((w, h), Image.LANCZOS)

def front(w, h):
    s = 4
    img = Image.new("RGBA", (w * s, h * s), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cx, cy = w * s / 2 + h * s * 0.22, h * s / 2 + h * s * 0.2
    r = h * s * 0.13
    d.ellipse([cx - r * 1.45, cy - r * 1.45, cx + r * 1.45, cy + r * 1.45], outline=(255, 210, 80, 255), width=int(r * 0.18))
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(255, 255, 255, 255))
    d.ellipse([cx - r * 0.55, cy - r * 0.55, cx + r * 0.55, cy + r * 0.55], fill=(255, 170, 40, 255))
    img = img.resize((w, h), Image.LANCZOS)
    shadow = Image.new("RGBA", img.size, (0, 0, 0, 0))
    shadow.paste((0, 0, 0, 120), mask=img.split()[3])
    shadow = shadow.filter(ImageFilter.GaussianBlur(h * 0.02))
    out = Image.new("RGBA", img.size, (0, 0, 0, 0))
    out.alpha_composite(shadow, (0, int(h * 0.02)))
    out.alpha_composite(img)
    return out

def imagestack(name, sizes):
    stack = os.path.join(brand, name + ".imagestack")
    layers = [("Front", front), ("Middle", middle), ("Back", back)]
    wjson(stack, {**info, "layers": [{"filename": n + ".imagestacklayer"} for n, _ in layers]})
    for lname, fn in layers:
        layer = os.path.join(stack, lname + ".imagestacklayer")
        wjson(layer, info)
        iset = os.path.join(layer, "Content.imageset")
        images = []
        for scale, (w, h) in sizes:
            fname = f"{lname.lower()}@{scale}.png"
            os.makedirs(iset, exist_ok=True)
            im = fn(w, h)
            if lname == "Back":
                im = im.convert("RGB")
            im.save(os.path.join(iset, fname))
            images.append({"filename": fname, "idiom": "tv", "scale": scale})
        wjson(iset, {**info, "images": images})

def topshelf(name, sizes):
    iset = os.path.join(brand, name + ".imageset")
    images = []
    os.makedirs(iset, exist_ok=True)
    for scale, (w, h) in sizes:
        im = back(w, h)
        mid = middle(h, h)
        fr = front(h, h)
        x = int(w * 0.5 - h * 0.5)
        im.alpha_composite(mid, (x, 0))
        im.alpha_composite(fr, (x, 0))
        fname = f"topshelf@{scale}.png"
        im.convert("RGB").save(os.path.join(iset, fname))
        images.append({"filename": fname, "idiom": "tv", "scale": scale})
    wjson(iset, {**info, "images": images})

wjson(cat, info)
wjson(brand, {**info, "assets": [
    {"filename": "App Icon - App Store.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "1280x768"},
    {"filename": "App Icon.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "400x240"},
    {"filename": "Top Shelf Image Wide.imageset", "idiom": "tv", "role": "top-shelf-image-wide", "size": "2320x720"},
    {"filename": "Top Shelf Image.imageset", "idiom": "tv", "role": "top-shelf-image", "size": "1920x720"},
]})
imagestack("App Icon", [("1x", (400, 240)), ("2x", (800, 480))])
imagestack("App Icon - App Store", [("1x", (1280, 768))])
topshelf("Top Shelf Image", [("1x", (1920, 720)), ("2x", (3840, 1440))])
topshelf("Top Shelf Image Wide", [("1x", (2320, 720)), ("2x", (4640, 1440))])
# Preview for README
prev = back(800, 480); prev.alpha_composite(middle(800, 480)); prev.alpha_composite(front(800, 480))
os.makedirs(os.path.join(root, "docs"), exist_ok=True)
prev.convert("RGB").save(os.path.join(root, "docs/icon.png"))
print("ok")
