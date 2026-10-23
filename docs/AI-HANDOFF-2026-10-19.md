# Handoff for the next AI — 2026-10-19 session

Read `AI-HANDOFF.md` first (rules, layout, services). This file is the update from the session of 2026-10-19.

## Standing instructions from the owner (this session)
1. **Push to the repo automatically.** After each finished task: run the checks, commit with a clear English message, and `git push` the current branch (now `feat/coin-shop-player-gear`; default branch is `claude/laughing-bell-h5hg6n`).
   - Never merge PRs (the owner merges), never force-push, never publish the place to Roblox, never log in or type passwords/tokens (use the git/gh login that already exists).
   - The working tree already holds a lot of uncommitted work from earlier sessions: stage by file, don't discard anything, don't `git reset`/`stash`.
2. **Work exactly like this session did:**
   - Reply in short Egyptian Arabic; code, file names and commit messages stay in English.
   - Handle every request item separately, verify each one, and say plainly what was tested and what was not (nothing here was ever seen in Studio).
   - Ask only when a request is truly ambiguous (e.g. "damge" = damage).
   - Look at reference images/videos the owner sends (OpenCV is installed: extract frames with a script in the scratchpad) and match them.
   - Keep going until the task is really done; don't stop at "should work".

## How to run checks (Windows)
- Offline tests: `C:\Users\ywsf5\AppData\Local\Packages\OpenAI.Codex_2p2nqsd0c76g0\LocalCache\Local\RaiseAMonsterTools\lune.exe run tools/test-<name>.luau`
  - Pass now: auto-feeder, coin-receipts, followers, gear-save-queue, monster-inventory, monster-inventory-layout.
  - Fail for old reasons (not caused by this session): `test-approved-geometry` (bat weld assertion, line 5), `test-gear-inventory` (stale pill-caption assertion near line 533).
- Syntax check without Studio: `lune` script that calls `luau.compile(fs.readFile(file))` and tests that the first byte is not 0.
- Build: `rojo build default.project.json -o $TEMP/x.rbxlx` (rojo is in `~/.rokit/bin`).
- Live sync: desktop shortcut `Rojo Raise a Monster.bat` (runs `rojo serve`).
- Editing tips: source files use CRLF and tabs; when patching with Python, normalise `\r\n` first and restore it; write the script to a file (heredocs with quotes broke in bash).

## What was done this session
**HUD / UI** (`UI.luau`, `init.client.luau`, `Features.luau`)
- Compact top bar (wallet 200x46, Home / To Shop / To Arena 90x34) and 48px icon column.
- Removed the Upgrade button/panel and the "waiting at your base" text (only `+X/s` stays).
- Shop Accessories cards show 3D previews (`UI.GearPreview`) instead of the muscle icon.

**Base (tycoon)** (`PlotService.luau`, `MonsterService.luau`, `init.server.luau`)
- Slot upgrades are bought at a blue **Upgrade pad** in the front corner of each base (`Callbacks.Upgrade` -> `MonsterService.BuyUpgrade`); the old `BuyUpgrade` remote handler was removed (remote name kept).
- Per-habitat coin collectors removed; the single coin chest moved to the other front corner.

**Map** (`TerrainService.luau`, `Config.lua`, `LeaderboardService.luau`)
- Removed the blue crystals on the border cliffs.
- Gear Shop and the 3 leaderboards moved to the plaza side of the zone-entrance wall (shop south of the gate road, boards north).

**Arena** (`ArenaService.luau`, `Config.Arena`)
- Old arena removed. Two arenas (radius 22) at `(-40, 0, ±238)`, gate facing the plaza (+X). Battles use the first free arena; `ArenaService.GetTeleportCFrame` alternates between arenas and skips one that is busy. The entrance pillar was removed so the path is clear.
- `To Arena` HUD button -> `Teleport` remote with `"Arena"`.

**Combat / monsters**
- Sword grip derives the blade axis from the model (`CombatService.luau`); sword/bat damage and mother damage raised ~15% (`Config.lua`).
- Mothers also chase players who come within `Config.Combat.MotherNoticeRange` (32), not only the last attacker (`ZoneService.luau`).
- Procedural walk rewritten for full-body motion; legless monsters (slime, serpent...) hop instead of walking (`MonsterAnimator.luau`).
- Attack telegraph zones (coloured hit areas) removed (`CombatFx.luau`).
- Studio-only chat commands (end of `init.server.luau`): `/follow` (adult follower) and `/dragon [desert|ice|volcano|void]` (adult dragon in inventory). Remove before publishing if the owner asks.

**Speed gear** (`CharacterService.luau` builds it, `GearAnimate.luau` animates it on every client, `Config.SpeedAccessories` names)
- Renamed: Neon Dash Sneakers, Ember Stompers, Frost Glide Skates, Zephyr Scarf, Storm Strike Boots, Umbral Cloak, Sunfeather Wings (keys unchanged, so saves are safe). Void Hoverboard keeps its name.
- Designs/effects follow the owner's reference images (sneakers, flame boots with burning footprints, ice skates with frost line, lightning boots with ground strikes, scarf with wind swirl, cloak with mist, ornate wings).
- Animation is done by offsetting `Motor6D.C0` (Transform did not take effect). Parts are parented to the character only after the model is fully built (`GearReady`), and the client rescans when new parts arrive (fixed "only the left wing moves").
- Wings: ~half size, own slower flap clock. Hoverboard: skate stance side-on, board built along the travel axis, kick-flip 380 degrees on jump, jump power x sqrt(1.5) while equipped, pink ribbon trail.

## Known gaps / not verified
- Nothing was run in Roblox Studio. Rider pose/yaw signs, wing size, arena spacing, shop/board layout are estimates.
- Shop preview cards for the new gear details were not updated beyond the first version.
- No automated test covers GearAnimate, ArenaService or the new effects.
- `Config.MapBorder.LanternEvery` is now unused. `Remotes.BuyUpgrade` has no handler.
- Flow (ElevenLabs flows) was used once for an arena concept image (190 credits); the owner makes the gear reference videos/images themself.
