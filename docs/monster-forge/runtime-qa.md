# Monster Forge runtime QA — 2026-10-23

Connected place: Raise a Monster, `134442007298395`. Source and asset updates were applied in Edit mode before restarting Play.

- All seven decorative images reported `ImageLabel.IsLoaded = true` in the client.
- Desktop viewport `1819 x 697`: shop `1060 x 520`; weapon grid, actual model preview and two featured plus four smaller pass cards inspected.
- iPhone 17 Pro landscape: viewport `750 x 381`, shop `726 x 299`. Visible native labels reported `TextFits = true`. Purchase/equip controls measured 44 native pixels high.
- Mouse-wheel scrolling in the phone simulator changed catalog CanvasPosition from `(0, 0)` to `(0, 200)` and exposed the EQUIP action plus the weapon grid. This validates the tested scroll path, not every touch gesture or device.
- Native desktop category selection and all seven loaded illustrations were inspected. A gradient multiplication defect found in Studio was corrected: card bases are white, Damage uses a dark red gradient and VIP uses a warm gold-brown gradient.
- Independent review accepted source, screenshots, 35 Forge checks, 2605 geometry checks, compilation of 49 production sources and the rebuilt artifact with 49 matching source bodies.

Captures: `studio-desktop-passes.png`, `studio-phone-weapons.png`, `studio-phone-scroll.png`. These are native Studio screenshots, not the concept image.

The simulator was reset to its original default viewport. No real Robux purchase was made, and the cloud place was not published. The existing `ShopGui:WaitForChild("Group 1")` warning remains outside this change. The previously recorded full-suite result remains 24 passing and 7 pre-existing failing fixtures; this is not a claim that the full suite is green.
