# Monster Forge decorative assets

The approved shop composition is in `docs/monster-forge/approved-shop.png`. Native text, prices, buttons and actual 3D weapon previews remain in `src/client/MonsterForge.luau`; the PNGs only provide the carved frame and pass illustrations.

Shipping artwork is in `assets/plates/`. Exact generation prompts are embedded in the PNG metadata. `provenance.json`, the original atlas, and `asset-map.json` record generation and extraction. The shell is 1863 x 844 RGBA and uses a nine-slice center of `(64, 144, 1799, 780)`. Pass artwork has transparent padding; the client uses native ImageRect cropping to the recorded art bounds.

## Roblox activation

Roblox image IDs are not assigned yet. Studio disconnected during this task and Creator Dashboard could not be reached (DNS error). The zero image IDs in `MonsterForge.Assets` are deliberate pending values, not uploaded assets. The native shop remains functional, but its complete illustrated finish requires this activation before visual acceptance.

When Studio is connected to the intended Raise a Monster place, serve `assets/plates/` over a local HTTP server and upload these seven files with the Studio MCP `upload_image` tool. Fill only the corresponding entries in `MonsterForge.Assets`, then synchronize the source and playtest desktop and landscape mobile. This step does not require a new design or a change to economy logic.

| File | Client entry |
| --- | --- |
| forge-shell.png | Shell |
| damage-art.png | Passes.DoubleDamage |
| vip-art.png | Passes.VIP |
| collect-art.png | Passes.AutoCollect |
| slots-art.png | Passes.ExtraSlots |
| feeder-art.png | Passes.AutoFeeder |
| minigame-art.png | Passes.AutoMinigame |

`Pedestal` is optional: selected weapon previews already use a native pedestal. The board background and labels are presentation context, not shipping assets.
