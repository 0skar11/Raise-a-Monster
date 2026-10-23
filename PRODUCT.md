# Raise a Monster

## Platform

Roblox, using native Luau ScreenGui interfaces and in-game 3D models. The shop must support desktop and compact landscape mobile viewports.

## Users and purpose

Players hatch and raise monsters, collect their income, and acquire weapons, accessories and permanent upgrades. The shop lets a player inspect an item, understand its cost and effect, buy it through the existing server-controlled flow, or equip an owned item.

## Source of truth

`src/shared/Config.luau` defines catalog entries, stats and fallback prices. Existing state snapshots define ownership and equipped items. Marketplace prices and native purchase prompts govern Robux purchases. Client presentation never grants currency, products or pass benefits.

## Approved scope

On 2026-10-23 the user approved the Monster Forge shop concept in `docs/monster-forge/approved-shop.png` and requested implementation preserving its visual features. Preserve the working gameplay and economy, all catalog items, growth selection, and ownership flows while replacing the shop presentation.

## Delivery boundaries

Report source checks, local builds, Studio visual tests and public Roblox publication separately. A screenshot mock is not a runtime capture. Real purchase verification requires a real purchase and must not be inferred from mocked ownership tests.
