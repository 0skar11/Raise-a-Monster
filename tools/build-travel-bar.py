"""Generate assets/TravelBar.rbxmx: the primary HOME / SHOP / ARENA bar.
Run: python tools/build-travel-bar.py
The bar lives in StarterGui so it is visible in Studio edit mode without Play.
"""
from pathlib import Path

root = Path(__file__).resolve().parent.parent
refs = iter(range(1000))
BUTTONS = [
    # name, text, fill, glow, x, y, w, h
    ("HomeButton", "HOME", (190, 32, 48), (255, 100, 106), 0, 0, 136, 44),
    ("TeleportShopButton", "SHOP", (0, 139, 190), (85, 225, 255), 144, 0, 136, 44),
    ("TeleportArenaButton", "ARENA", (40, 146, 32), (135, 235, 92), 288, 0, 136, 44),
]


def u32(rgb):
    return (rgb[0] << 16) | (rgb[1] << 8) | rgb[2]


def item(cls, name, props, children=""):
    return (f'<Item class="{cls}" referent="RBX{next(refs)}"><Properties>'
            f'<string name="Name">{name}</string>{props}</Properties>{children}</Item>')


def udim2(name, xs, xo, ys, yo):
    return f'<UDim2 name="{name}"><XS>{xs}</XS><XO>{xo}</XO><YS>{ys}</YS><YO>{yo}</YO></UDim2>'


def color(name, rgb):
    return f'<Color3uint8 name="{name}">{u32(rgb)}</Color3uint8>'


FONT = ('<Font name="FontFace"><Family><url>rbxasset://fonts/families/GothamSSm.json</url></Family>'
        '<Weight>700</Weight><Style>Normal</Style></Font>')


def stroke(rgb, thickness, transparency=0, mode=1):
    return item("UIStroke", "UIStroke", color("Color", rgb) + f'<token name="ApplyStrokeMode">{mode}</token>'
                f'<float name="Thickness">{thickness}</float><float name="Transparency">{transparency}</float>')


def button(name, text, fill, glow, x, y, w, h):
    light = tuple(min(255, c + 70) for c in fill)
    gradient = item("UIGradient", "Gloss",
                    '<ColorSequence name="Color">0 1 1 1 0 0.5 0.85 0.85 0.85 0 1 0.62 0.62 0.62 0 </ColorSequence>'
                    '<float name="Rotation">90</float>')
    padding = item("UIPadding", "UIPadding", ''.join(
        f'<UDim name="Padding{s}"><S>0</S><O>{o}</O></UDim>' for s, o in
        (("Left", 8), ("Right", 8), ("Top", 5), ("Bottom", 5))))
    limit = item("UITextSizeConstraint", "UITextSizeConstraint", '<int name="MaxTextSize">20</int><int name="MinTextSize">14</int>')
    props = (udim2("Size", 0, w, 0, h) + udim2("Position", 0, x, 0, y) + color("BackgroundColor3", fill)
             + FONT + f'<string name="Text">{text}</string>' + color("TextColor3", (255, 255, 255))
             + '<bool name="TextScaled">true</bool><bool name="TextWrapped">false</bool>'
             + '<float name="TextStrokeTransparency">1</float><int name="BorderSizePixel">0</int>'
             + '<bool name="AutoButtonColor">false</bool><int name="ZIndex">2</int>')
    return item("TextButton", name, props,
                item("UICorner", "UICorner", '<UDim name="CornerRadius"><S>0</S><O>8</O></UDim>')
                + stroke(glow, 2) + gradient + padding + limit)


bar = item("Frame", "Bar",
           '<Vector2 name="AnchorPoint"><X>0.5</X><Y>0</Y></Vector2>' + udim2("Position", 0.5, 0, 0, 8)
           + udim2("Size", 0, 424, 0, 44) + '<float name="BackgroundTransparency">1</float>',
           item("UIScale", "ResponsiveScale", '<float name="Scale">1</float>') + "".join(button(*b) for b in BUTTONS))
gui = item("ScreenGui", "TravelBar",
           '<bool name="ResetOnSpawn">false</bool><bool name="IgnoreGuiInset">false</bool>'
           '<token name="ZIndexBehavior">1</token><int name="DisplayOrder">10</int>', bar)
(root / "assets" / "TravelBar.rbxmx").write_text(f'<roblox version="4">{gui}</roblox>', encoding="utf-8")
print("Wrote assets/TravelBar.rbxmx")
