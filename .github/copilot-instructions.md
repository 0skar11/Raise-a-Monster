# Raise a Monster: guide for AI coding agents

Roblox game: hatch eggs, raise monsters, hunt mother monsters in 5 region zones, carry babies home, earn coins.
The owner (GitHub `0skar11`) writes in **Egyptian Arabic**. Reply in Egyptian Arabic and keep code identifiers in English.

## Repo layout (Rojo project, see `default.project.json`)
| Path | Becomes in the game | What it is |
|---|---|---|
| `src/shared/` | `ReplicatedStorage.Shared` | `Config.luau` (**all tuning numbers live here**), `MonsterMath.luau`, `Remotes.luau`, `MonsterAnimator.luau` |
| `src/server/` | `ServerScriptService.Server` | `init.server.luau` wires all services; one `*Service.luau` per system |
| `src/client/` | `StarterPlayerScripts.Client` | `init.client.luau`, `UI.luau` (HUD and panels), `Features.luau` (shop extras, rewards, accessories, trade, arena), `MonsterAnimate.luau` |
| `assets/MonsterModels.rbxmx` | `ServerStorage.MonsterModels` | 150 rigged monsters (5 regions × 10 × Baby/Teen/Adult) |
| `assets/WeaponModels.rbxmx` | `ReplicatedStorage.WeaponModels` | Weapon Tool templates (WoodenBat, IronBat, swords) |
| `tools/build-place.js` | | Builds `RaiseAMonster.rbxlx` from the project, with no Rojo needed |
| `tools/GrowAMonster_RiggedGenerator.lua` | | Script that generates the monster rigs |
| `RaiseAMonster.rbxlx` | | The ready-to-open place file, **committed to git** |

## Server services
- **ZoneService:** mother monsters and baby nests.
  - Damage and health scale with `Config.MotherDamageByRarity` and `Config.MotherHealthByRarity`.
  - Mothers chase the last player who hit them, within `Config.Combat.MotherLeashRange`.
  - Nests reset every 10 minutes.
- **CombatService:** weapons (from `WeaponModels`, with stats in `Config.WeaponStats`), PvP, and the target registry `{Part, Radius, OnHit}`.
- **PlotService:** the 6 tycoon bases (themes are in `Config.BaseThemes`), monster rendering, and accessories (`addRigAccessories`, which switches on `accessory.Shape`).
- **MonsterService:** eggs, care, economy, accessories, and mini-games.
- **CarryService:** carrying monsters and eggs on your back.
- **EventService:** Monster Rain and the Big Boss.
- **TradeService** and **ArenaService:** trading and 1v1 arena fights.
- **RewardService:** the daily reward and spin wheel, shown in one 🎁 Rewards window on the client.
- **MonetizationService:** gamepasses and products. The ids in `Config` are still `0`, which means they are free in Studio.
- **LeaderboardService**, **DataService** (DataStore save), **CharacterService** (fixed `Config.WalkSpeed = 25` × factors, such as Speed Boost), and **TerrainService**.

## Code conventions
- `--!strict` Luau, tabs, and `PascalCase` module tables.
- Comments are short and in Egyptian Arabic. Match the surrounding comment density.
- Every gameplay number goes in `Config.luau`, never hard-coded.
- Accessories are per species. `Config.Accessories["<Species>_Hat" | "<Species>_Glasses"]` is generated from `Config.Species`, and a monster can only wear its own species' items.
- Rigs use a HumanoidRootPart PrimaryPart, Motor6D joints, and the `AnimState` attribute (Idle/Walk/Attack). The `PivotHeight` attribute is the distance from the feet to the pivot.

## After every code change: rebuild the place file
```
node tools/build-place.js
```
This rewrites `RaiseAMonster.rbxlx` from `default.project.json`. It handles `$path` folders and scripts, `.server`/`.client` suffixes, `$properties`, and embedded `.rbxmx` assets.
**Always commit the rebuilt `RaiseAMonster.rbxlx` together with the source change**, or the place file goes stale.
If the write fails with `UNKNOWN: open`, Roblox Studio has the file open. Build to another path and copy it over after Studio is closed.

## Testing in Roblox Studio
- Open `RaiseAMonster.rbxlx` and press Play.
- For multiplayer, use **Test → Server & Clients**.
- Debug triggers from the server command bar:
  - `game.ServerStorage.RaiseAMonsterDebug.MonsterRain:Fire()`
  - `game.ServerStorage.RaiseAMonsterDebug.Boss:Fire()`
  - `game.ServerStorage.RaiseAMonsterDebug.KillBoss:Fire()`
- The Roblox player list covers the right side of the screen and eats clicks, so keep HUD buttons on the left, top, or bottom.

## Git / PR workflow
- The default branch is `claude/laughing-bell-h5hg6n`. Make a new branch for each task, push it, and open a PR into that branch.
- **The owner merges PRs themselves.** Don't merge unless asked.
- Commit messages are short and imperative, in English.

## Hard rules
- **Never Publish the game to Roblox.** Don't change Studio settings or the owner's Roblox or GitHub account settings.
- Don't install software without asking first.
- Never log in to the owner's accounts or type credentials. The owner does any login or device approval themselves.
- For visual changes (map, UI, models), describe or show a preview before building when the request is open-ended.
- Report honestly. If something wasn't tested in Studio, say so.

## Open items (as of 2026-10-10)
- PR #6's changes still need a Studio check: per-species accessories, the Rewards window, the new button positions, and the tycoon without the blue sign or line.
- Branch `feature/speed-accessories` is not merged. In `src/server/CharacterService.luau`, `ApplySpeedAccessory` and `GetSpeedAccessoryMultiplier` are declared *inside* `SetSpeedFactor` and must be moved out to module level before it can work.
- Speed Boost (×1.4) stays, by the owner's decision.
- Gamepass and product ids are `0`. Real ids are needed before release.
