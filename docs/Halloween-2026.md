# Halloween 2026 event

Everything lives behind `Config.Halloween` (src/shared/Config.luau). Nothing is built, scheduled or rewarded unless the event is on.

## Turning it off (or on)
* Set `Config.Halloween.Enabled = false` and publish, **or** set `Config.Halloween.EndsAt` to a unix time for a scheduled end.
* When the event stops (server start with it off, `EndsAt` reached, or the Studio toggle) the server:
  removes pumpkins and invaders, takes `Workspace.HalloweenWorld` (merchant + decorations) out of the running game (stashed, never destroyed or moved; the saved place is untouched), restores Lighting/Atmosphere/Sky, strips cosmetics and
  converts every player's leftover Candy to coins at `CandyToCoinRate` (default 20 coins per Candy).
  Players who were offline are converted when they next join. Owned cosmetics and monsters are kept.
* Studio only: `game.ServerStorage.RaiseAMonsterDebug` gets `HalloweenInvasion` (optional count), `HalloweenPumpkins`,
  `HalloweenToggle` (flips `Enabled` live) and `HalloweenCandy` (+1000 Candy to the first player).

## What it does
| Feature | Rules (all in Config.Halloween) |
| --- | --- |
| Mother Invasion | Every hour on the hour (server clock, same time everywhere), warned 60 s ahead. 3 to 10 Mothers, weights make 3-6 about 90% of waves. Random level 1-60 each; HP and damage scale with level. Uses the normal Mother rigs/attacks (MonsterModels, MonsterAttack, CombatService targets). Anyone who dealt >= 5% of a Mother's max HP gets `level x 5` Candy when she dies. No stealing, no carrying. Survivors leave after 15 min. |
| Pumpkin Hunt | At :15 and :45. 5 pumpkins in the plaza for 2 min, 3-10 Candy each, 8% chance one is golden (50). Pickup is validated on the server (real distance, per-player debounce, one claim per pumpkin). Clients get only a coarse hint: 8 compass sectors plus a near/mid/far band for the nearest pumpkin. |
| Candy | Stored in `profile.Data.Halloween` (DataService; old saves get defaults, bad data is sanitised). |
| Pumpkin Merchant | Studio-authored R6 character (witch costume, staff lantern, ghost companion, stall with goods) under `Workspace.HalloweenWorld.Merchant`, tagged `HalloweenMerchant`, with a ProximityPrompt "Open Shop" on his Torso. The server finds him by tag and measures the shop distance from where he stands NOW (`Config.Halloween.Merchant.Position` is only the fallback spot). The prompt opens the shop panel. Purchases are `HalloweenBuy(itemId)` only; the server checks distance, cooldown, price, ownership and refunds if delivery fails. |
| Items | Candy Boost (2x live cash, 10 min, stacks time up to 1 h), Pumpkin Hat, Ghost Trail, Candy Aura, Halloween 2026 title, Haunted Egg (real Rare/Mythic egg, 70/30), Ghost Slime, Skeleton Imp, Pumpkin King (most expensive, one per player). Prices/weights are in `Config.Halloween.Items`. |
| Atmosphere | The spooky night (fog, Atmosphere, bloom/colour grade, stars) is **event-only**: it fades in (3 s, `Atmosphere.FadeSeconds`) when a Mother Invasion is announced (60 s warning) and stays until all Mothers are dead or gone; it also covers a Pumpkin Hunt until it ends. Overlapping events share one night; otherwise the normal day lighting is kept. The night is brighter than v1 (`Atmosphere.Brightness/Ambient/OutdoorAmbient/Fog*`). Original values are snapshotted and restored (instantly on Stop). The decorations are permanent while the event is on (see Studio-authored world below). |

## Studio-authored world (Workspace.HalloweenWorld)
The decorations and the merchant are real objects saved in the place, visible in Edit mode without pressing Play, and they stay where you move them. `HalloweenService` ADOPTS them: it never rebuilds, repositions or destroys them.
* `HalloweenWorld/Merchant/MerchantStand`: the merchant character + stall (move the whole model; the shop distance follows him).
* `HalloweenWorld/Props/*`: Graveyards (tombstones, fence, arch, sign), DeadTrees, JackOLanterns (carved faces), PumpkinPatches, Lanterns, GateDecor, Cobwebs, Spiders, FloatingCandles, Ghosts, GlowingEyes, FogAndEmbers. Delete a folder to remove a group.
* Tags: `HalloweenProp`, `HalloweenWeb`, `HalloweenSpider`, `HalloweenFloat`, `HalloweenEyes`, `HalloweenMerchant`. A `README` StringValue inside the folder repeats this.
* Idle life (spiders/candles/ghosts bob, eyes blink, merchant breathes and looks around) is client-local in `src/client/HalloweenDecor.luau`; it re-bases on whatever you moved and does nothing in Edit mode.
* Fallback: if the merchant is missing the server builds the old code-made one at `Config.Halloween.Merchant.Position` into `HalloweenWorld/Merchant`; if `HalloweenWorld/Props` is missing or empty it builds the old default props there. Folders built that way carry the attribute `AutoBuilt` and are discarded when the event stops; authored ones are only stashed.
* Runtime-only objects (pumpkin pickups, invaders, lighting holds) still live in `Workspace.HalloweenEvent`, rebuilt on every Start.
* The world exists only in the place file: after editing it, File > Save in Studio (`RaiseAMonster_fixed.rbxlx`). `tools/UpdateGame.ps1` replaces only StudioWorld, AnimationRigs and scripts, so HalloweenWorld survives it. To retire the decorations for good delete `Workspace.HalloweenWorld`.

## Code map
* `src/shared/HalloweenLogic.luau` pure rules (counts, rewards, hints, purchases, conversion), unit tested.
* `src/server/HalloweenService.luau` scheduling, world objects, AI, remotes.
* `src/client/CandyCounter.luau` drives the Studio-authored `StarterGui.CandyCounter` (small copy of CashCounter above it; Candy from `HalloweenState`).
* `src/client/HalloweenUI.luau` event timers, hint arrow, shop panel.
* `src/client/HalloweenDecor.luau` idle motion for the authored decorations and the merchant.
* Hooks: `DataService` (Halloween block + sanitiser), `MonsterService.GetEventMultiplier` (live income only, never saved as the offline multiplier), `init.server` (init/join/leave/respawn), `Remotes` (six `Halloween*` events).

## Checks
`lune run tools/test-halloween` (config, rules, DataService migration/persistence, wiring) and `lune run tools/check-source`.
Needs a Studio playtest: merchant prompt/shop, moving props in Edit then Play, prop look, Lighting look, the shop panel position, a real Mother fight, trails/hat on the R6 character, and the Monster Rain/Big Boss events running alongside.

## Pumpkin Titan loot (added 2026-10-26)

- The boss no longer drops a guaranteed Secret Egg. Damage per player is tracked (`EventService`), and a background-free damage board under the boss lists each fighter's damage and % of the boss's max HP.
- When it dies, everyone with at least 1% of its max HP gets 1-3 loot rolls (`Config.BossLoot`, `BossLootMath`, `BossLoot`). More damage means more rolls and a bigger weight on rare entries. Fixed odds per roll: Halloween Monster Egg 5%, Secret Egg 3%.
- The eight Halloween monsters (`Config.Species.Halloween*`, MonsterModels region 6, index 1-8) only hatch from `Config.Eggs.HalloweenMonster` (45s). Weights: Ghost Slime 20, Skeleton Imp 20, Hex Cat 15, Crypt Mummy 15, Count Fang 10, Grave Golem 10, Wraith Reaper 7, Pumpkin King 3 (strongest). The Candy shop no longer sells monsters.
- Boss-loot-only speed gear (`LootOnly`, never sold, listed under Owned): Hexed Witch Boots x1.18, Phantom Shroud x1.32, Pumpkin King Wings x1.45.
- Tests: `tools/test-boss-loot.luau`, `tools/test-halloween.luau`.
