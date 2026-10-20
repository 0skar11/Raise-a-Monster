"""Generate assets/TravelBar.rbxmx: the pixel-style HOME / SHOP / ARENA bar.
Run: python tools/build-travel-bar.py
The bar lives in StarterGui so it is visible in Studio edit mode without Play.
"""
from pathlib import Path

root = Path(__file__).resolve().parent.parent
refs = iter(range(1000))
BUTTONS = [
    # name, text, fill, glow, x, y, w, h
    ("HomeButton", "HOME", (206, 32, 48), (255, 84, 84), 0, 4, 124, 38),
    ("TeleportShopButton", "SHOP", (24, 160, 232), (70, 236, 255), 140, 0, 144, 46),
    ("TeleportArenaButton", "ARENA", (48, 176, 48), (156, 255, 80), 300, 4, 124, 38),
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


FONT = ('<Font name="FontFace"><Family><url>rbxasset://fonts/families/Arcade.json</url></Family>'
        '<Weight>400</Weight><Style>Normal</Style></Font>')


def stroke(rgb, thickness, transparency=0, mode=1):
    return item("UIStroke", "UIStroke", color("Color", rgb) + f'<token name="ApplyStrokeMode">{mode}</token>'
                f'<float name="Thickness">{thickness}</float><float name="Transparency">{transparency}</float>')


def button(name, text, fill, glow, x, y, w, h):
    light = tuple(min(255, c + 70) for c in fill)
    gradient = item("UIGradient", "Gloss",
                    '<ColorSequence name="Color">0 1 1 1 0 0.5 0.85 0.85 0.85 0 1 0.62 0.62 0.62 0 </ColorSequence>'
                    '<float name="Rotation">90</float>')
    bevel = item("Frame", "Bevel",
                 udim2("Size", 1, -8, 1, -8) + udim2("Position", 0, 4, 0, 4)
                 + '<float name="BackgroundTransparency">1</float>' + '<int name="ZIndex">1</int>',
                 stroke(light, 2, 0.15) + item("UICorner", "UICorner", '<UDim name="CornerRadius"><S>0</S><O>3</O></UDim>'))
    padding = item("UIPadding", "UIPadding", ''.join(
        f'<UDim name="Padding{s}"><S>0</S><O>{o}</O></UDim>' for s, o in
        (("Left", 8), ("Right", 8), ("Top", 5), ("Bottom", 5))))
    limit = item("UITextSizeConstraint", "UITextSizeConstraint", '<int name="MaxTextSize">24</int><int name="MinTextSize">8</int>')
    props = (udim2("Size", 0, w, 0, h) + udim2("Position", 0, x, 0, y) + color("BackgroundColor3", fill)
             + FONT + f'<string name="Text">{text}</string>' + color("TextColor3", (255, 255, 255))
             + '<bool name="TextScaled">true</bool><bool name="TextWrapped">false</bool>'
             + color("TextStrokeColor3", (20, 20, 40)) + '<float name="TextStrokeTransparency">0</float>'
             + '<bool name="AutoButtonColor">false</bool><int name="ZIndex">2</int>')
    return item("TextButton", name, props,
                item("UICorner", "UICorner", '<UDim name="CornerRadius"><S>0</S><O>6</O></UDim>')
                + stroke(glow, 3) + gradient + bevel + padding + limit)


bar = item("Frame", "Bar",
           '<Vector2 name="AnchorPoint"><X>0.5</X><Y>0</Y></Vector2>' + udim2("Position", 0.5, 0, 0, 8)
           + udim2("Size", 0, 424, 0, 46) + '<float name="BackgroundTransparency">1</float>',
           "".join(button(*b) for b in BUTTONS))
gui = item("ScreenGui", "TravelBar",
           '<bool name="ResetOnSpawn">false</bool><bool name="IgnoreGuiInset">false</bool>'
           '<token name="ZIndexBehavior">1</token>', bar)
(root / "assets" / "TravelBar.rbxmx").write_text(f'<roblox version="4">{gui}</roblox>', encoding="utf-8")
print("Wrote assets/TravelBar.rbxmx")
