#!/usr/bin/env python3
"""Lager ikonene til Apple TV (App Icon & Top Shelf Image) og iPhone/iPad (AppIcon) fra fyret i Fyrlys-ikonet.

    pip install cairosvg pillow && python3 tools/make_icons.py          (alle)
    python3 tools/make_icons.py --ios                                    (bare iPhone/iPad-ikonet)

Ikonene til Apple TV har tre lag for parallakse-effekten: bakgrunn (helt dekkende), lysstrålene og fyret. Ikonet til
iPhone og iPad er ett bilde på 1024 × 1024 uten alfakanal (App Store avviser ikoner med alfa).
"""
import json
import sys
from pathlib import Path

import cairosvg

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "App" / "Assets.xcassets"
BRAND = ASSETS / "App Icon & Top Shelf Image.brandassets"
MOBILE = ROOT / "App" / "Mobil.xcassets"

BG, BG2, SIGNAL, TOWER, INK = "#07121C", "#183450", "#F2B544", "#B3C1CD", "#EDF1F4"
INFO = {"author": "xcode", "version": 1}


def lamp_and_scale(w, h, lamp_x=None):
    """Fyret står nederst med toppen av tårnet litt over midten; k er størrelsen (fyrlys.svg: 64 × 64)."""
    k = h / 57  # lampen (y 22) til bunnen av tårnet (y 58) = 36 enheter, litt luft over
    lamp_y = h - 36 * k + 2 * k
    return (lamp_x if lamp_x is not None else w / 2), lamp_y, k


def back(w, h, lx, ly, k):
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">
  <defs><radialGradient id="g" cx="{lx}" cy="{ly}" r="{max(w, h) * 0.75}" gradientUnits="userSpaceOnUse">
    <stop offset="0" stop-color="{BG2}"/><stop offset="1" stop-color="{BG}"/></radialGradient></defs>
  <rect width="{w}" height="{h}" fill="url(#g)"/>
</svg>'''


def beams(w, h, lx, ly, k):
    reach_r, reach_l = w - lx + 40, lx + 40
    half = 14 / 30
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">
  <defs><radialGradient id="glow" cx="{lx}" cy="{ly}" r="{16 * k}" gradientUnits="userSpaceOnUse">
    <stop offset="0" stop-color="{SIGNAL}" stop-opacity=".55"/><stop offset="1" stop-color="{SIGNAL}" stop-opacity="0"/>
  </radialGradient></defs>
  <path d="M{lx} {ly} L{lx + reach_r} {ly - reach_r * half} L{lx + reach_r} {ly + reach_r * half} Z" fill="{SIGNAL}" opacity=".30"/>
  <path d="M{lx} {ly} L{lx - reach_l} {ly - reach_l * half} L{lx - reach_l} {ly + reach_l * half} Z" fill="{SIGNAL}" opacity=".17"/>
  <circle cx="{lx}" cy="{ly}" r="{16 * k}" fill="url(#glow)"/>
</svg>'''


def tower(w, h, lx, ly, k, text=None):
    # fyrlys.svg: lampen (32, 22) r 5; tårnet (28, 28)–(36, 28)–(41, 58)–(23, 58); striper y 38 og 48
    def p(x, y):
        return f"{lx + (x - 32) * k:.1f} {ly + (y - 22) * k:.1f}"
    extra = 10  # tårnet går litt under kanten
    words = ""
    if text:
        size, x = text
        words = (f'<text x="{x}" y="{ly + 8 * k}" font-family="Inter" font-weight="700" font-size="{size}" '
                 f'fill="{INK}" letter-spacing="{-size * 0.02:.1f}">Fyrlys</text>')
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">
  <circle cx="{lx}" cy="{ly}" r="{5 * k}" fill="{SIGNAL}"/>
  <path d="M{p(28, 28)} L{p(36, 28)} L{p(41 + extra / 6, 58 + extra)} L{p(23 - extra / 6, 58 + extra)} Z" fill="{TOWER}"/>
  <path d="M{p(26.5, 38)} L{p(37.5, 38)} M{p(25, 48)} L{p(39, 48)}" stroke="{BG}" stroke-width="{2.4 * k}"/>
  {words}
</svg>'''


def render(svg, path, w, h):
    path.parent.mkdir(parents=True, exist_ok=True)
    cairosvg.svg2png(bytestring=svg.encode(), write_to=str(path), output_width=w, output_height=h)


def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2) + "\n")


def imagestack(name, w, h, scales):
    stack = BRAND / f"{name}.imagestack"
    layers = [("Front", tower), ("Middle", beams), ("Back", back)]
    write_json(stack / "Contents.json", {"info": INFO, "layers": [{"filename": f"{n}.imagestacklayer"} for n, _ in layers]})
    for layer, draw in layers:
        folder = stack / f"{layer}.imagestacklayer"
        write_json(folder / "Contents.json", {"info": INFO})
        images = []
        for scale in scales:
            sw, sh = w * scale, h * scale
            lx, ly, k = lamp_and_scale(sw, sh)
            file = f"{layer.lower()}{'' if scale == 1 else f'@{scale}x'}.png"
            render(draw(sw, sh, lx, ly, k), folder / "Content.imageset" / file, sw, sh)
            images.append({"filename": file, "idiom": "tv", "scale": f"{scale}x"})
        write_json(folder / "Content.imageset" / "Contents.json", {"images": images, "info": INFO})


def top_shelf(name, w, h):
    folder = BRAND / f"{name}.imageset"
    images = []
    for scale in (1, 2):
        sw, sh = w * scale, h * scale
        lx, ly, k = lamp_and_scale(sw, sh, lamp_x=sw * 0.30)
        k *= 0.82
        ly = sh - 36 * k
        layers = [back(sw, sh, lx, ly, k), beams(sw, sh, lx, ly, k),
                  tower(sw, sh, lx, ly, k, text=(sh * 0.30, lx + 14 * k))]
        file = f"top{'' if scale == 1 else f'@{scale}x'}.png"
        svg = merge(sw, sh, layers)
        render(svg, folder / file, sw, sh)
        images.append({"filename": file, "idiom": "tv", "scale": f"{scale}x"})
    write_json(folder / "Contents.json", {"images": images, "info": INFO})


def merge(w, h, layers):
    inner = "".join(layer.split(">", 1)[1].rsplit("</svg>", 1)[0] for layer in layers)
    return f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" viewBox="0 0 {w} {h}">{inner}</svg>'


def ios_icon():
    """AppIcon for iPhone og iPad: fyret med strålene på den mørke bakgrunnen, 1024 × 1024, RGB uten alfa."""
    from PIL import Image  # bare her: Apple TV-ikonene trenger ikke pillow

    size = 1024
    # mindre enn i TV-ikonene (5:3): lampa litt over midten, tårnet ut av bunnen
    lx, ly, k = size / 2, size * 0.42, size / 73
    folder = MOBILE / "AppIcon.appiconset"
    file = folder / "icon-1024.png"
    render(merge(size, size, [back(size, size, lx, ly, k), beams(size, size, lx, ly, k), tower(size, size, lx, ly, k)]),
           file, size, size)
    Image.open(file).convert("RGB").save(file, optimize=True)
    write_json(MOBILE / "Contents.json", {"info": INFO})
    write_json(folder / "Contents.json", {
        "images": [{"filename": "icon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
        "info": INFO,
    })


def main():
    if "--ios" in sys.argv:
        ios_icon()
        return
    ios_icon()
    write_json(ASSETS / "Contents.json", {"info": INFO})
    write_json(BRAND / "Contents.json", {"assets": [
        {"filename": "App Icon - App Store.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "1280x768"},
        {"filename": "App Icon.imagestack", "idiom": "tv", "role": "primary-app-icon", "size": "400x240"},
        {"filename": "Top Shelf Image Wide.imageset", "idiom": "tv", "role": "top-shelf-image-wide", "size": "2320x720"},
        {"filename": "Top Shelf Image.imageset", "idiom": "tv", "role": "top-shelf-image", "size": "1920x720"},
    ], "info": INFO})
    imagestack("App Icon", 400, 240, (1, 2))
    imagestack("App Icon - App Store", 1280, 768, (1,))
    top_shelf("Top Shelf Image", 1920, 720)
    top_shelf("Top Shelf Image Wide", 2320, 720)
    # et forhåndsbilde av ikonet med alle lagene (ikke i appen)
    lx, ly, k = lamp_and_scale(800, 480)
    render(merge(800, 480, [back(800, 480, lx, ly, k), beams(800, 480, lx, ly, k), tower(800, 480, lx, ly, k)]),
           ROOT / "docs" / "ikon.png", 800, 480)


if __name__ == "__main__":
    main()
