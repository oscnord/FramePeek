#!/usr/bin/env python3
"""FramePeek app icon generator.

Variants live in ./variants/<name>/ and are installed with ./activate.sh <name>.

  a-two-shapes    the shipped mark, preserved verbatim. An ellipse of 140x188
                  beside a semicircle of r192 -- two shapes with no relationship
                  to each other. Three independent design reviews all landed on
                  the same objection: the mark is arbitrary rather than abstract,
                  and it reads as the letters "OD".

  b-halved        the minimum fix. The second shape is the right half of the
                  SAME ellipse, so mass is exactly 2:1 and the two heights are
                  identical by construction rather than by luck.

  c-split-disc    one disc, one vertical cut, the pieces drawn apart. The cut
                  sits where it divides the disc's area in the golden ratio. The
                  counterform becomes a constant-width slot instead of a
                  tapering leftover, and the cut position is a parameter, so the
                  mark can extend into a family and can animate as a scan head.

Both new variants keep the appearance handling from the shipped icon.json and
apply the fixes from the Apple review: tinted glass off (it was an Icon Composer
import default, not a decision) and translucency off (measured inert in default
and dark, live only in clear and tinted). The contact shadow is kept -- it was
measured doing real work.
"""
import json, math, pathlib, subprocess, sys

HERE = pathlib.Path(__file__).parent
REPO = HERE.parent.parent
CREAM, INK = "#F4F1E9", "#111114"

BODY = 824 / 1024          # Apple's macOS icon body inside the 1024 canvas


def svg(shapes, fill=INK):
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1024 1024" '
            f'width="1024" height="1024"><g fill="{fill}">{shapes}</g></svg>')


# --- b: whole ellipse + the right half of the same ellipse -------------------
# 3:4 exactly, rather than the 0.745 near-miss the reviews flagged.
B_RX, B_RY = 198, 264
B_GAP = B_RX // 2                       # 99, a stated fraction rather than a residue
B_CX = 374                              # splits the difference between bbox- and
                                        # mass-centring, which is the usual convention


def b_shapes(rx=B_RX, ry=B_RY, gap=B_GAP, cx=B_CX):
    flat = cx + rx + gap                # left edge of the half
    whole = f'<ellipse cx="{cx}" cy="512" rx="{rx}" ry="{ry}"/>'
    half = f'<path d="M {flat} {512-ry} A {rx} {ry} 0 0 1 {flat} {512+ry} Z"/>'
    return whole, half


# --- c: one disc, split on the golden-ratio area chord -----------------------
C_R = 304


def golden_chord(r):
    """Offset of the vertical chord that cuts the disc's area at 1:phi.
    Solves (acos(u) - u*sqrt(1-u^2))/pi = 0.381966 for u = d/r."""
    target = 1 - 1 / ((1 + 5 ** 0.5) / 2)          # 0.381966
    lo, hi = 0.0, 1.0
    for _ in range(60):
        u = (lo + hi) / 2
        frac = (math.acos(u) - u * math.sqrt(1 - u * u)) / math.pi
        if frac > target:
            lo = u
        else:
            hi = u
    return r * (lo + hi) / 2


def c_shapes(r=C_R, gap=76):
    d = golden_chord(r)
    cut = 512 + d
    half_h = math.sqrt(r * r - d * d)
    y0, y1 = 512 - half_h, 512 + half_h
    off = gap / 2
    major = (f'<path transform="translate({-off:.0f} 0)" '
             f'd="M {cut:.1f} {y0:.1f} A {r} {r} 0 1 0 {cut:.1f} {y1:.1f} Z"/>')
    minor = (f'<path transform="translate({off:.0f} 0)" '
             f'd="M {cut:.1f} {y0:.1f} A {r} {r} 0 0 1 {cut:.1f} {y1:.1f} Z"/>')
    return major, minor


# --- icon.json ---------------------------------------------------------------

def layer(name, image):
    return {
        "blend-mode": "normal",
        "fill-specializations": [
            {"value": "automatic"},
            {"appearance": "dark", "value": {"solid": "display-p3:1.00000,1.00000,1.00000,1.00000"}},
        ],
        # All three appearances agree. The shipped file had tinted=true, which
        # was Icon Composer's import default and a material discontinuity.
        "glass-specializations": [
            {"value": False},
            {"appearance": "dark", "value": False},
            {"appearance": "tinted", "value": False},
        ],
        "hidden": False,
        "image-name": image,
        "name": name,
        "position": {"scale": 1, "translation-in-points": [0, 0]},
    }


def icon_json(layers):
    return json.dumps({
        "color-space-for-untagged-svg-colors": "display-p3",
        "fill": {"solid": "extended-srgb:0.95686,0.94510,0.91373,1.00000"},
        "groups": [{
            "layers": layers,
            "shadow": {"kind": "neutral", "opacity": 0.5},
            # Measured inert over an opaque fill; live only where glass is on.
            "translucency": {"enabled": False, "value": 0.5},
        }],
        "supported-platforms": {"circles": ["watchOS"], "squares": "shared"},
    }, indent=2) + "\n"


# --- variants ----------------------------------------------------------------

def build_b():
    whole, half = b_shapes()
    return {
        "Whole.svg": svg(whole), "Half.svg": svg(half),
        "_flat": svg(whole + half),
        "layers": [layer("Half", "Half.svg"), layer("Whole", "Whole.svg")],
    }


def build_c():
    major, minor = c_shapes()
    return {
        "Major.svg": svg(major), "Minor.svg": svg(minor),
        "_flat": svg(major + minor),
        "layers": [layer("Minor", "Minor.svg"), layer("Major", "Major.svg")],
    }


VARIANTS = {"b-halved": build_b, "c-split-disc": build_c}


def write(name):
    v = VARIANTS[name]()
    d = HERE / "variants" / name
    (d / "Assets").mkdir(parents=True, exist_ok=True)
    for k, val in v.items():
        if k.endswith(".svg"):
            (d / "Assets" / k).write_text(val)
    (d / "icon.json").write_text(icon_json(v["layers"]))
    (d / "_flat.svg").write_text(v["_flat"])   # reference composite, not shipped
    return d, v


def metrics(name):
    """Report the numbers the reviews asked for, so claims stay checkable."""
    if name == "b-halved":
        rx, ry, gap, cx = B_RX, B_RY, B_GAP, B_CX
        a_whole = math.pi * rx * ry
        a_half = a_whole / 2
        flat = cx + rx + gap
        cen = (a_whole * cx + a_half * (flat + 4 * rx / (3 * math.pi))) / (a_whole + a_half)
        l, r = cx - rx, flat + rx
        return {"ink %tile": (a_whole + a_half) / 1024 ** 2,
                "bbox w %": (r - l) / 1024, "bbox h %": 2 * ry / 1024,
                "mass split": f"{a_whole/(a_whole+a_half):.1%} / {a_half/(a_whole+a_half):.1%}",
                "heights": f"{2*ry} / {2*ry} (identical by construction)",
                "mass centroid dx": cen - 512, "gap": gap,
                "gap px @16": gap / 1024 * 16 * BODY}
    d = golden_chord(C_R)
    a = math.pi * C_R ** 2
    frac = (math.acos(d / C_R) - (d / C_R) * math.sqrt(1 - (d / C_R) ** 2)) / math.pi
    return {"ink %tile": a / 1024 ** 2,
            "bbox w %": (2 * C_R + 76) / 1024, "bbox h %": 2 * C_R / 1024,
            "area split": f"{1-frac:.1%} / {frac:.1%}  (ratio {(1-frac)/frac:.4f}, phi=1.6180)",
            "cut offset": round(d, 1), "slot": 76,
            "slot px @16": 76 / 1024 * 16 * BODY}


if __name__ == "__main__":
    for n in VARIANTS:
        d, _ = write(n)
        print(f"\n{n}  ->  {d.relative_to(REPO)}")
        for k, val in metrics(n).items():
            print(f"    {k:20} {val:.3f}" if isinstance(val, float) else f"    {k:20} {val}")
