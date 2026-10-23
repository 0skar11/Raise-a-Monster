# Halloween 2026 event

Everything lives behind `Config.Halloween` (src/shared/Config.luau). Nothing is built, scheduled or rewarded unless the event is on.

## Turning it off (or on)
* Set `Config.Halloween.Enabled = false` and publish, **or** set `Config.Halloween.EndsAt` to a unix time for a scheduled end.
* When the event stops (server start with it off, `EndsAt` reached, or the Studio toggle) the server:
  removes the merchant, props, pumpkins and invaders, restores Lighting/Atmosphere/Sky, strips cosmetics and
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
| Pumpkin Merchant | NPC at `Merchant.Position` with a ProximityPrompt that opens the shop panel. Purchases are `HalloweenBuy(itemId)` only; the server checks distance, cooldown, price, ownership and refunds if delivery fails. |
| Items | Candy Boost (2x live cash, 10 min, stacks time up to 1 h), Pumpkin Hat, Ghost Trail, Candy Aura, Halloween 2026 title, Haunted Egg (real Rare/Mythic egg, 70/30), Ghost Slime, Skeleton Imp, Pumpkin King (most expensive, one per player). Prices/weights are in `Config.Halloween.Items`. |
| Atmosphere | The spooky night (fog, Atmosphere, bloom/colour grade, stars) is **event-only**: it fades in (3 s, `Atmosphere.FadeSeconds`) when a Mother Invasion is announced (60 s warning) and stays until all Mothers are dead or gone; it also covers a Pumpkin Hunt until it ends. Overlapping events share one night; otherwise the normal day lighting is kept. The night is brighter than v1 (`Atmosphere.Brightness/Ambient/OutdoorAmbient/Fog*`). Original values are snapshotted and restored (instantly on Stop). Props (jack-o-lanterns, tombstones, dead trees, embers) are permanent decorations while the event is on. |

## Code map
* `src/shared/HalloweenLogic.luau` pure rules (counts, rewards, hints, purchases, conversion), unit tested.
* `src/server/HalloweenService.luau` scheduling, world objects, AI, remotes.
* `src/client/CandyCounter.luau` drives the Studio-authored `StarterGui.CandyCounter` (small copy of CashCounter above it; Candy from `HalloweenState`).
* `src/client/HalloweenUI.luau` event timers, hint arrow, shop panel.
* Hooks: `DataService` (Halloween block + sanitiser), `MonsterService.GetEventMultiplier` (live income only, never saved as the offline multiplier), `init.server` (init/join/leave/respawn), `Remotes` (six `Halloween*` events).

## Checks
`lune run tools/test-halloween` (config, rules, DataService migration/persistence, wiring) and `lune run tools/check-source`.
Needs a Studio playtest: NPC/prop placement, Lighting look, the shop panel position, a real Mother fight, trails/hat on the R6 character, and the Monster Rain/Big Boss events running alongside.
