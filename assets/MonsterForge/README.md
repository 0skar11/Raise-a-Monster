# Monster Forge decorative assets

The approved shop composition is in `docs/monster-forge/approved-shop.png`. Native text, prices, buttons and actual 3D weapon previews remain in `src/client/MonsterForge.luau`; the PNGs only provide the carved frame and pass illustrations.

Shipping artwork is in `assets/plates/`. Exact generation prompts are embedded in the PNG metadata. `provenance.json`, the original atlas, and `asset-map.json` record generation and extraction. The shell is 1863 x 844 RGBA and uses a nine-slice center of `(64, 144, 1799, 780)`. Pass artwork has transparent padding; the client uses native ImageRect cropping to the recorded art bounds.

## Roblox activation

The seven decorative images were uploaded through Studio MCP on 2026-10-23, and their returned image IDs are assigned in `MonsterForge.Assets`. `upload-manifest.json` records the portable file-to-ID mapping. All seven images loaded successfully in Studio. Desktop and landscape phone captures, scrolling and native control sizes were checked; see `docs/monster-forge/runtime-qa.md`. Real Robux purchases and cloud place publication were not performed.

Synchronize the source to the intended Raise a Monster place, then playtest desktop and landscape mobile to verify image loading, cropping and native interactions. Upload completion does not establish runtime visual acceptance or place publication.

| File | Client entry | Roblox image ID |
| --- | --- | --- |
| forge-shell.png | Shell | 107413501937236 |
| damage-art.png | Passes.DoubleDamage | 107172821558895 |
| vip-art.png | Passes.VIP | 114721435821486 |
| collect-art.png | Passes.AutoCollect | 96489741894811 |
| slots-art.png | Passes.ExtraSlots | 107348462504183 |
| feeder-art.png | Passes.AutoFeeder | 97133893417228 |
| minigame-art.png | Passes.AutoMinigame | 136084988913737 |

`Pedestal` is optional: selected weapon previews already use a native pedestal. The board background and labels are presentation context, not shipping assets.
