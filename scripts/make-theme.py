#!/usr/bin/env python3
"""Render every themed config of Huilo from theme/templates/ and theme/palette.toml.

  python3 scripts/make-theme.py            write the generated files
  python3 scripts/make-theme.py --check    exit 1 if a generated file is out of date

theme/templates/ mirrors archiso/: theme/templates/airootfs/etc/skel/.config/kitty/kitty.conf
becomes archiso/airootfs/etc/skel/.config/kitty/kitty.conf.

Placeholders (the palette names are the keys of [colors], [terminal] and [fonts]):
  @{amber}        #f2a33a
  @{amber.hex}    f2a33a            e.g. rgba(@{amber.hex}ee) for Hyprland
  @{amber.rgb}    242, 163, 58      e.g. rgba(@{amber.rgb}, 0.6) in CSS
  @{amber.argb}   #fff2a33a         Qt colour scheme format
  @{amber.float}  0.949, 0.639, 0.227   Plymouth script colours
  @{font.ui}      Inter
Also generated: archiso/airootfs/etc/vtrgb (text console palette) and the Plymouth
progress bar colour.
"""
import os
import re
import sys
import tomllib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TEMPLATES = os.path.join(ROOT, "theme", "templates")
OUT = os.path.join(ROOT, "archiso")
COMMENT = {  # how to write the "generated" header per file type
    ".lua": "--", ".css": "/*", ".rasi": "/*", ".conf": "#", ".toml": "#", ".ini": "#", ".cfg": "#",
    ".sh": "#", "": "#", ".script": "//", ".jsonc": "//",
}
NO_HEADER = {".json", ".txt"}


def load_palette():
    with open(os.path.join(ROOT, "theme", "palette.toml"), "rb") as f:
        p = tomllib.load(f)
    colors = {**p["colors"], **p["terminal"]}
    for k, v in colors.items():
        if not re.fullmatch(r"#[0-9a-fA-F]{6}", v):
            sys.exit(f"palette: {k} = {v} is not #rrggbb")
    return colors, p["fonts"]


def render(text, colors, fonts, where):
    def sub(m):
        name, _, fmt = m.group(1).partition(".")
        if name == "font":
            if fmt not in fonts:
                sys.exit(f"{where}: unknown font @{{{m.group(1)}}}")
            return fonts[fmt]
        if name not in colors:
            sys.exit(f"{where}: unknown colour @{{{m.group(1)}}}")
        c = colors[name]
        r, g, b = (int(c[i:i + 2], 16) for i in (1, 3, 5))
        return {"": c, "hex": c[1:], "rgb": f"{r}, {g}, {b}", "argb": "#ff" + c[1:],
                "float": f"{r / 255:.3f}, {g / 255:.3f}, {b / 255:.3f}"}.get(fmt) \
            or sys.exit(f"{where}: unknown format @{{{m.group(1)}}}")
    return re.sub(r"@\{([a-z_]+(?:\.[a-z]+)?)\}", sub, text)


def header(path):
    ext = os.path.splitext(path)[1]
    if ext in NO_HEADER or os.path.basename(path) in (".bashrc",):
        return ""
    c = COMMENT.get(ext, "#")
    line = ("generated from theme/templates by scripts/make-theme.py — in the Huilo repository edit the "
            "template; on your computer edit this file freely (huilo-update keeps a .bak copy)")
    return f"/* {line} */\n" if c == "/*" else f"{c} {line}\n"


def outputs(colors, fonts):
    files = {}
    for base, _, names in os.walk(TEMPLATES):
        for n in names:
            src = os.path.join(base, n)
            rel = os.path.relpath(src, TEMPLATES)
            text = open(src, encoding="utf-8").read()
            body = render(text, colors, fonts, rel)
            if body.startswith("#!"):            # keep the shebang first
                first, _, rest = body.partition("\n")
                body = first + "\n" + header(rel) + rest
            else:
                body = header(rel) + body
            files[os.path.join(OUT, rel)] = body.encode()
    # text console palette for setvtrgb: 3 lines (red, green, blue) of 16 decimals
    order = ["black", "red", "green", "yellow", "blue", "magenta", "cyan", "white",
             "bright_black", "bright_red", "bright_green", "bright_yellow", "bright_blue",
             "bright_magenta", "bright_cyan", "bright_white"]
    vt = [colors["ink1"]] + [colors[k] for k in order[1:]]   # colour 0 is the console background
    files[os.path.join(OUT, "airootfs", "etc", "vtrgb")] = (
        "\n".join(",".join(str(int(c[i:i + 2], 16)) for c in vt) for i in (1, 3, 5)) + "\n").encode()
    return files


def main():
    check = "--check" in sys.argv
    colors, fonts = load_palette()
    stale = []
    for path, data in sorted(outputs(colors, fonts).items()):
        old = open(path, "rb").read() if os.path.exists(path) else None
        if old == data:
            continue
        stale.append(os.path.relpath(path, ROOT))
        if not check:
            os.makedirs(os.path.dirname(path), exist_ok=True)
            open(path, "wb").write(data)
    # the Plymouth progress bar is a 1x1 PNG in the accent colour
    try:
        from PIL import Image
        bar = os.path.join(OUT, "airootfs", "usr", "share", "plymouth", "themes", "huilo", "bar.png")
        c = colors["amber"]
        want = tuple(int(c[i:i + 2], 16) for i in (1, 3, 5))
        if not os.path.exists(bar) or Image.open(bar).convert("RGB").getpixel((0, 0)) != want:
            stale.append(os.path.relpath(bar, ROOT))
            if not check:
                Image.new("RGB", (1, 1), want).save(bar)
    except ImportError:
        pass
    if check:
        if stale:
            print("out of date (run python3 scripts/make-theme.py):\n  " + "\n  ".join(stale))
            return 1
        print("theme: all generated files are up to date")
    else:
        print(f"theme: {len(stale)} file(s) written" + ("" if not stale else ":\n  " + "\n  ".join(stale)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
