# Colorful UI illustration assets

Approved reference: `docs/colorful-ui/approved-shop-concept.png`.

`icons-atlas.png` is the newly generated 1402 x 1122 RGBA production master containing twenty illustrations. At the user's explicit request, `tools/export-cartoon-icons.ps1` exports every illustration into its own transparent PNG under `icons/`. Each PNG was uploaded independently. `src/client/CartoonUI.luau` uses twenty separate asset IDs with no runtime atlas or ImageRect cropping, preventing neighboring icons from appearing together. No illustrated labels or prices are used as controls.

`sky-backdrop.png` is a newly generated decorative sky/cloud plate used behind the native shop and Rewards controls.

Both assets were generated with built-in `image_gen`, using the approved reference for style, and uploaded to the intended Raise a Monster Studio instance on 2026-10-26. Upload success alone does not prove image loading or public place publication.

| File | Roblox image ID |
| --- | --- |
| icons/*.png | Twenty independent IDs in upload-manifest.json |
| sky-backdrop.png | 95952111765124 |

Exact generation prompts are in adjacent `.prompt.txt` files and embedded in the PNG metadata. The original concept is a fixed design reference, not a source of shipping cropped pixels.
