# Pumpkin Titan summon and gamepass audit — 2026-10-26

Universe: `10771956101` (Raise a Monster).

## Live dashboard configuration

The new **Summon Pumpkin Titan** Developer Product is `3722488952`, on sale for **50 Robux**, with managed/regional pricing disabled. It is a repeatable purchase: a permanent gamepass would only charge once and cannot represent one boss summon per purchase.

The six previously configured passes were checked in Creator Dashboard. The previously unconfigured collector pass has now been created and enabled as **Monster Collector**; Roblox filtered the old “Baby Collector” display name.

| Pass | ID | Robux | Dashboard |
| --- | --- | ---: | --- |
| VIP | 2036579024 | 299 | On sale; managed pricing off |
| Auto-Collect | 2038162860 | 149 | On sale; managed pricing off |
| +2 Slots | 2036429020 | 99 | On sale; managed pricing off |
| Auto-Feeder | 2037406772 | 99 | On sale; managed pricing off |
| Auto Minigame | 2044616622 | 99 | On sale; managed pricing off |
| x2 Damage | 2052905177 | 299 | On sale; managed pricing off |
| Monster Collector | 2052666547 | 149 | Created and enabled; managed pricing off |

Evidence: [new product](pumpkin-summon-product-2026-10-26.png), [existing passes](gamepasses-dashboard-2026-10-26.png), [collector pass](monster-collector-pass-2026-10-26.png).

## Delivered behavior

- The summon appears in the shop's Gamepasses tab and opens the new Developer Product prompt. It remains repeatable and never becomes an owned permanent pass.
- Only `MarketplaceService.ProcessReceipt` can grant a paid summon. Opening, canceling or completing the purchase prompt alone cannot spawn the boss.
- The receipt marker and pending summon credit are saved together before acknowledgement. Credits survive reconnects and progression resets.
- The current server spawns the real Pumpkin Titan when its arena is free. A living boss blocks a new prompt; a concurrent paid receipt remains queued and retries automatically. Waiting during a fight does not poll DataStore with writes.
- A premium purple/gold entrance card shows the authenticated buyer's avatar, display name, username and actual receipt Robux amount to the whole server. The existing boss entrance and combat effects remain active.
- Duplicate receipts do not add another credit. Failed writes keep the paid credit recoverable; a server-local delivery set prevents repeated world spawns while a debit retries. A replacement server can recover an unconfirmed debit, favoring recovery of a paid benefit after a crash.
- The collector grants one baby to each participating owner, prioritizing the killer, then damage. A failed inventory grant now preserves the original pickup instead of deleting it.
- Marketplace server purchase confirmation grants gamepasses; ownership reload retries transient API errors and restores entitlements after reconnect. Weapon shop entries remain in-game coin purchases.

## Verification

Offline tests use real production modules with deterministic Marketplace/world/DataStore substitutes and spend no Robux.

Executable: `C:\Users\ywsf5\AppData\Local\RaiseAMonsterTools\lune.exe`.

Run each with `lune.exe run tools/<test>.luau`:

| Test | Result |
| --- | --- |
| `test-boss-summon` | 43 checks passed: receipt routing, duplicate/canceled prompts, safe save retries, queue, no waiting writes, multi-credit debit priority, named announcement, reconnect |
| `test-monster-collector` | 10 checks passed: live ID, participation, purchase/cancel, one reward per owner, failed grant safety, ownership restore |
| `test-gamepasses` | 24 checks passed: VIP income, Auto-Collect, slot expansion, purchase/cancel, ownership retry, no stacking |
| `test-auto-feeder` | Passed |
| `test-auto-minigame` | 39 checks passed |
| `test-double-damage` | 42 checks passed, including all player weapons and PvE/PvP safeguards |
| `test-extra-slots-rejoin` | 30 checks passed |
| `test-coin-receipts` | Passed: three configured packs, duplicate receipts, save failures and unknown/unsafe receipts |
| `test-shop-layout` | 2668 geometry checks passed across desktop and phone dimensions |
| `test-data-persistence` | 55 checks passed, including paid summon save/rejoin and reset preservation |
| `check-source` | All 69 production Luau files compiled |

The initial whole Lune test sweep passed 36 suites and failed 9. The task-related stale Marketplace fixtures and shop category expectation were repaired. Unrelated fixture/source assumptions remain in geometry (`GetTagged` stub), gear inventory/save-queue, old hard-coded weapon prices, and saving-warning extraction tests. This is not a claim that the entire repository test suite is green.

## Verification boundaries

Studio MCP returned no connected instances during implementation. Native Studio Play, paid end-to-end purchases, final banner rendering on phone, and Roblox place publication were not verified by these offline tests. Dashboard sale configuration is live; source implementation and local-place delivery/publication are separate states.

Other Developer Products were outside the gamepass audit: the three legacy coin-pack IDs in Config were absent from this universe's current dashboard product list; their offline receipt logic passing does not establish current live sale availability. Unconfigured future products remain unavailable in production.
