# Gamepasses and progress saving

## Roblox configuration

Verified in Creator Dashboard for Raise a Monster, universe `10771956101`:

| Benefit | Pass ID | Base price (Robux) |
| --- | --- | --- |
| VIP | 2036579024 | 299 |
| Auto-Collect | 2038162860 | 149 |
| +2 Slots | 2036429020 | 99 |
| Auto-Feeder | 2037406772 | 99 |

All four passes were created and enabled for sale. The legacy hidden CoinBoost ID was disabled because it was not a pass in this universe. Weapons remain purchases with in-game coins.

## Saving and Studio behavior

Profiles acquire an atomic DataStore session lease. Saves require the same lease, retry transient failures, and release ownership when leaving or shutting down. This prevents an older server from overwriting progress after a new server acquires the profile. Concurrent joins share one profile load.

When Studio cannot access DataStore services, it can run a temporary session with saving disabled and a warning. Temporary progress is never written to the saved profile. Live servers, malformed records and active session conflicts still reject unsafe loads. Paid product prompts are blocked when saving is unavailable.

After syncing the source, stop Play and start it again. A Studio temporary session is suitable for gameplay testing; it does not prove cloud persistence. To validate real persistence, use the published experience and verify the same coins, monsters, eggs and equipped gear after leaving and rejoining.

## Validation

- Independent review and regression checks passed: 47 persistence checks, 20 gamepass checks, receipt processing and 77 save-queue checks.
- All 33 production Luau files compiled successfully. Rojo build passed.
- A separate build of the selected commit files over HEAD passed using the repository's build script.
- Two full-suite failures reproduce on the previous local baseline: approved geometry and an outdated gear UI caption assertion.
- No Studio instance was connected through MCP. Real purchase, live DataStore rejoin, device and multiplayer behavior were not verified. No static type analyzer was installed.

## Delivery scope

The selected source files include existing local feature work needed by the current shop and server APIs. Other local edits, the deleted place file, and unrelated untracked artifacts are preserved outside this commit.
