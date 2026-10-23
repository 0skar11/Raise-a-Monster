# Raise a Monster: handoff for a new AI assistant

> Paste this whole file into ChatGPT or Codex at the start of the conversation, or put it in the agent's instructions.

---

## 1) Who I am and how to deal with me
- Talk to me in **Egyptian Arabic**: short and clear. Code, file names, and commit messages stay in English.
- I build Roblox games in Luau, on **Windows 11** with **Roblox Studio**.
- Don't change anything I didn't ask for. If a decision is mine to make, **ask me** before you do it.
- If you're not sure, say so. Don't guess numbers or APIs.
- Be honest about what you tested and what you didn't. Never say "it works" unless you actually tried it.
- Every run command goes in its own code block.
- Old files go to the Recycle Bin, never permanently deleted.

## 2) Hard rules (never break them)
1. **Don't Publish the game to Roblox.** I publish it myself.
2. Don't change Roblox Studio settings or my settings on Roblox or GitHub.
3. **Don't log in to any account and don't type any password or token.** If something needs login or device approval, I do it.
4. Don't install software without asking me first.
5. **Visual changes** (map, base, UI, models): if the request is open-ended or not clear, show me a mockup or a top-down plan first and wait for my OK before writing code. If the request is clear and specific, just do it.
6. **The owner (me) merges PRs.** Don't merge unless I ask.

---

## 3) The project
- **Game:** Raise a Monster. You hatch eggs, raise monsters, hunt mother monsters in the zones, carry their babies home, and earn coins.
- **Repo:** `https://github.com/0skar11/Raise-a-Monster`
- **Default branch:** `claude/laughing-bell-h5hg6n`
- **Local copy:** `D:\downloads\raise a monster\Raise-a-Monster`
- **The place on Roblox:** "Raise a Monster" (Private), with **Team Create on**.

### Repo layout (Rojo project, see `default.project.json`)
| Path | Becomes in the game | What it is |
|---|---|---|
| `src/shared/` | `ReplicatedStorage.Shared` | `Config.luau` (**all game numbers**), `MonsterMath.luau`, `Remotes.luau`, `MonsterAnimator.luau` |
| `src/server/` | `ServerScriptService.Server` | `init.server.luau` starts all the services, one `*Service.luau` per system |
| `src/client/` | `StarterPlayerScripts.Client` | `init.client.luau`, `UI.luau` (HUD and windows), `Features.luau` (Rewards, accessories, Trade, Arena, shop extras), `MonsterAnimate.luau` |
| `assets/MonsterModels.rbxmx` | `ServerStorage.MonsterModels` | 150 rigged monsters (5 regions × 10 × Baby/Teen/Adult) |
| `assets/WeaponModels.rbxmx` | `ReplicatedStorage.WeaponModels` | Weapon models (WoodenBat, IronBat, and the swords) |
| `tools/build-place.js` | | Builds `RaiseAMonster.rbxlx` without Rojo |
| `tools/GrowAMonster_RiggedGenerator.lua` | | The script that generates the monsters |
| `RaiseAMonster.rbxlx` | | The ready-to-open place file, **committed to git** |
| `.github/copilot-instructions.md` | | A short version of this guide for Copilot |

### The services (server)
- **ZoneService:**
  - The mothers and their nests in 5 regions: Grassland, Desert, Ice, Volcano, Void.
  - Nests reset every 10 minutes.
  - Mother damage and health go up with rarity (`Config.MotherDamageByRarity` / `MotherHealthByRarity`).
  - A mother chases the last player who hit her, up to `Config.Combat.MotherLeashRange` (70 studs), then goes back to her nest.
  - You have to kill the mother to take her babies.
- **CombatService:**
  - Weapons come from `WeaponModels`, with their stats in `Config.WeaponStats`.
  - PvP outside the bases.
  - Target registry `{Part, Radius, OnHit}`.
- **PlotService:**
  - 6 bases side by side (open tycoon). The theme is `Normal`; the other themes are registered but unused.
  - Monster rendering.
  - Accessories (`addRigAccessories` switches on `accessory.Shape`).
- **MonsterService:** eggs, care (Feed/Play/Sell), the economy, accessories, and mini-games.
- **CarryService:** carrying monsters and eggs on your back. Whoever knocks out the carrier takes it.
- **EventService:** Monster Rain every hour, and the Big Boss that drops a Secret egg.
- **TradeService:** trading, with both players confirming.
- **ArenaService:** 1v1 fights. The winner gets coins plus the loser's monster.
- **RewardService:** the daily reward and the spin wheel, both in one 🎁 Rewards window on the client.
- **MonetizationService:** Gamepasses and products. **All the Ids are still 0**, which makes them free in Studio.
- **CharacterService:** walk speed is a fixed 25 (`Config.WalkSpeed`), times factors like Speed Boost ×1.4, which stays by my decision.
- **DataService** (DataStore save), **LeaderboardService**, **TerrainService** (mountains), **StealService** (stealing is off: `Config.Steal.Enabled = false`).

### Important design decisions
- R6 characters. Attacking is with a Tool (the bat), not the E key.
- Accessories are **per species**. Every monster has its own hat and glasses (`Config.Accessories["<Species>_Hat"|"<Species>_Glasses"]`), and they have to be bought. Only that species can wear them.
- HUD buttons stay on the left, top, or bottom. **The right side gets covered by the Roblox player list, which eats clicks.**
- The rigs:
  - PrimaryPart = HumanoidRootPart, with Motor6D joints.
  - The `AnimState` attribute (Idle/Walk/Attack) drives the animation.
  - The `PivotHeight` attribute = the distance from the feet to the pivot.

---

## 4) Code conventions
- `--!strict` Luau, tabs, `PascalCase` module tables.
- Comments are short and in Egyptian Arabic. Follow how much the surrounding code comments.
- **Every gameplay number goes in `src/shared/Config.luau`.** No numbers hard-coded in the code.
- Edit the files in the repo directly, not by pasting code into Studio (because of Rojo, see below).

## 5) The workflow
1. Make a new branch from `claude/laughing-bell-h5hg6n` for each task.
2. Edit the files.
3. **Rebuild the place file:**
   ```
   node tools/build-place.js
   ```
   If you get `UNKNOWN: open`, Studio has the file open. Build to another path and copy it over later.
4. Commit the source changes **together with `RaiseAMonster.rbxlx`** in the same commit. Messages are short, in English.
5. Push and open a PR into `claude/laughing-bell-h5hg6n`, then send me the link. I merge it.

### Rojo (live sync between the files and Studio)
- Rokit 1.2.0 and Rojo 7.4.4 are installed (`rokit.toml`), and the Rojo plugin is installed in Studio.
- How to run it:
  ```
  rojo serve
  ```
  Then in Studio: **Plugins → Rojo → Connect → Accept**.
- **While Rojo is connected:** edit only from the files. If someone edits a script inside Studio, Rojo can overwrite it.
- Rojo syncs whatever is in the folder at that moment (including uncommitted work or another branch).
- Because Team Create is on, any sync gets saved to the place on Roblox right away (players won't see it until I Publish).

### Testing in Studio
- Open `RaiseAMonster.rbxlx` (or the place through Rojo) and press **Play**.
- Multiplayer: **Test → Server & Clients**, and you can add players from the server window with **Add Clients**.
- Debug triggers from the server Command Bar:
  ```
  game.ServerStorage.RaiseAMonsterDebug.MonsterRain:Fire()
  ```
  ```
  game.ServerStorage.RaiseAMonsterDebug.Boss:Fire()
  ```
  ```
  game.ServerStorage.RaiseAMonsterDebug.KillBoss:Fire()
  ```
- Saving (DataStore) needs the game published, plus **Game Settings → Security → Enable Studio Access to API Services**.

---

## 6) Open items right now (2026-10-11)
- [ ] I need to test PR #6's changes in Studio: per-species accessories, the Rewards window, the left buttons and the top teleports, and the tycoon without the blue sign or line.
- [ ] PR #10 (the place rebuilt with the weapons, `tools/build-place.js`, and `.github/copilot-instructions.md`). Check whether it got merged.
- [ ] Branch `feature/speed-accessories` (8 speed items bought with coins) isn't merged. It has a bug: `ApplySpeedAccessory` and `GetSpeedAccessoryMultiplier` are defined **inside** `SetSpeedFactor` in `CharacterService.luau`. There was work on a fix in branch `fix/speed-accessory-scope`.
- [ ] Gamepass and product Ids are all 0. They need real Ids from Roblox before the official release.

---

## 7) Ready-made templates (copy any of them into the chat)

### 🐞 Debugging
```
I have a problem in Raise a Monster: [describe what happens vs what should happen].
The error from Output: [paste the error].
Go step by step: reproduce the problem, narrow it down to a file or function, explain the cause, then fix it with the smallest change possible.
Don't change anything outside the problem. Tell me exactly how to check that it's fixed in Studio.
```

### 🔍 Strict code review
```
Review the changes in [branch / PR] for: logic bugs, exploits (any RemoteEvent that trusts the client), performance, crashes from nil, and rules (numbers outside Config).
List the problems from most severe to least, each with the file:line, why it's a problem, and the fix. If something is fine, don't make up problems.
```

### 🎨 Mockup before building
```
I want [describe the visual change].
Don't write code yet. Show me a mockup or top-down plan with sizes and colors, and 2 options if possible. Wait for my OK.
```

### ✅ Test checklist
```
Write me a checklist to test [feature] in Studio: the steps in order, what I should see at each step, and Command Bar commands that make testing faster. Include the edge cases (2 players, leaving mid-game, low on coins).
```

### 🏗️ System design (compare 2 solutions)
```
I want to add [system]. Before any code: suggest 2 different ways to do it, with the pros and cons of each (complexity, performance, exploit risk, how it fits the current code), and recommend one. Wait for my decision.
```

### 📝 Documentation in Egyptian Arabic
```
Write documentation in Egyptian Arabic for [system/file]: what it does, which files it touches, which numbers in Config control it, and how to change it. Short, with tables wherever it helps.
```

### 🚀 Asking for a new feature
```
Task: [the feature].
Follow AI-HANDOFF.md: new branch → edit → node tools/build-place.js → commit with the rbxlx → PR. Put all the numbers in Config.luau.
At the end tell me: what changed, what you tested and what you didn't, and the PR link.
```
