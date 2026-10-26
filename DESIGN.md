---
name: Colorful Monster Forge and Rewards
description: Native Roblox cartoon shop and prize wheel with sky artwork, cream surfaces and navy text.
colors:
  shop-navy: "#102b5e"
  shop-text: "#132c62"
  shop-cream: "#fff8df"
  shop-raised: "#fffff9"
  shop-edge: "#89c8e8"
  shop-sky: "#1da8e5"
  shop-gold: "#ffd139"
  shop-muted: "#375473"
  shop-cyan: "#00c9d6"
  shop-blue: "#dbf4ff"
  shop-selected: "#43e5ed"
  shop-coral: "#e8395b"
  shop-disabled: "#d3e2e3"
  rewards-navy: "#122352"
  rewards-cream: "#fff8e2"
  rewards-card: "#e5f7ff"
  rewards-edge: "#51c0e0"
  rewards-gold: "#ffc737"
  rewards-pale: "#ffe779"
  rewards-muted: "#354f76"
  rewards-lime: "#96ed24"
  rewards-disabled: "#d3e2eb"
  rewards-sky: "#28b9f8"
  rewards-cyan: "#1fd5eb"
  white: "#ffffff"
typography:
  body:
    fontFamily: "Enum.Font.GothamBold"
    fontSize: "13px"
  label:
    fontFamily: "Enum.Font.GothamBold"
    fontSize: "14px"
rounded:
  shell: "16px"
  detail: "14px"
  shop-control: "12px"
  inset: "10px"
  rewards-control: "9px"
spacing:
  compact: "8px"
  regular: "12px"
components:
  button-primary:
    backgroundColor: "{colors.white}"
    textColor: "{colors.shop-navy}"
    rounded: "{rounded.shop-control}"
    height: "44px"
  button-disabled:
    backgroundColor: "{colors.shop-disabled}"
    textColor: "{colors.shop-muted}"
    rounded: "{rounded.shop-control}"
  button-close:
    backgroundColor: "{colors.shop-coral}"
    textColor: "{colors.white}"
    rounded: "{rounded.shop-control}"
    size: "44px"
  category:
    backgroundColor: "{colors.shop-blue}"
    textColor: "{colors.shop-text}"
    rounded: "{rounded.shop-control}"
  category-selected:
    backgroundColor: "{colors.shop-selected}"
    textColor: "{colors.shop-text}"
    rounded: "{rounded.shop-control}"
  catalog-card:
    backgroundColor: "{colors.white}"
    textColor: "{colors.shop-text}"
    rounded: "{rounded.shop-control}"
  rewards-spin:
    backgroundColor: "{colors.rewards-lime}"
    textColor: "{colors.rewards-navy}"
    rounded: "{rounded.rewards-control}"
    height: "48px"
---

# Design System: Colorful Monster Forge and Rewards

## Overview

**Creative North Star: "Colorful Monster Forge and Rewards"**

The approved cartoon world uses blue sky and clouds around cream containers, navy text, gold titles, turquoise selection and lime actions. Native Roblox controls carry readable prices, ownership and cooldowns; authored illustrations supply character. Equipment previews remain actual game models.

This refresh replaces the former dark-stone shop record following the approved 2026-10-26 concept and extension to Rewards in `docs/colorful-ui/direction.md`. Scope is `MonsterForge.luau`, `RewardsArcade.luau` and shared `CartoonUI.luau`; other game surfaces retain their own systems. The current RewardsArcade source implements the spin wheel, not daily reward cards. PRODUCT.md still records the older shop approval; its native-platform and server-authority constraints remain applicable.

**Key Characteristics:**
- Sky artwork around bright cream content.
- Navy text with gold display headings and lime actions.
- Independent uploaded illustrations alongside native controls and model previews.
- Native pixel reflow and scrolling, with explicit state labels.

## Colors

Cool blues frame warm cream surfaces. Shop and Rewards preserve their source-specific palette variants rather than claiming identical values.

### Primary
- **Shop Sky / Rewards Sky:** shell framing and header color; the shared raster Sky supplies clouds.
- **Shop Gold / Rewards Gold / Rewards Pale:** headings and wheel rim/hub accents.
- **Rewards Lime:** available spin action. Shop actions use a white base multiplied by the lime gradient recorded in the sidecar.

### Secondary
- **Shop Cyan / Shop Selected / Rewards Cyan:** selection borders, active navigation and Rewards shell edging.
- **Shop Coral:** close action; Rewards uses its own coral close override.

### Neutral
- **Shop Cream / Shop Raised / Rewards Cream / Rewards Card / Shop Blue:** content, card and inset layers.
- **Shop Navy / Shop Text / Rewards Navy:** dark readable text and title outlines.
- **Shop Muted / Rewards Muted:** supporting copy and disabled labels.
- **Shop Edge / Rewards Edge:** card strokes and scrollbar accents.
- **Shop Disabled / Rewards Disabled:** inactive actions with the active gradient disabled.

**The State Accent Rule.** Selection, ownership and availability must remain understandable through native text and borders independently of illustrations.

## Typography

**Body Font:** native `Enum.Font.GothamBold`. Body and label frontmatter values serialize native `TextSize`, not browser measurements. Supporting shop descriptions use (12–13px); category labels use (12–15px); prices use (17–21px); detail stats use (14–17px). Rewards supporting text uses (11–14px). No source-defined line-height, tracking or custom font asset is established.

Observed display roles use `Enum.Font.FredokaOne`: shop title (20/27/34px), selected item (20/25px), featured pass headings (27/34px), shop actions (16–23px), Rewards title (31px), spin heading (23px), clock (27px) and spin action (20px). These built-in display faces are recorded as implementation evidence, not canonized as a future display font requirement. Prize labels use native scaling constrained to (8–17px); phone legibility remains unverified. Labels wrap; RichText is disabled.

## Layout

Shop bounds come from `UI.ShopBounds`: viewport minus (24px), capped at (1060 × 520px). Compact mode uses width below (840px) or height below (420px), with compact spacing. Navigation widths are (162px), (126px) compact and (86px) below (480px); icons hide below that narrow threshold. Tabs are (65px) tall or (48px) compact. Navigation and content scroll separately.

Gear detail moves into the catalog scroll when content width is below (370px) or height below (300px). Gear and product grids use one to three columns. Gamepasses use two featured columns, falling to one below the content threshold, followed by a desktop row of four to six smaller cards and one or two compact columns. Detail stat icons hide below (250px) detail width.

Rewards bounds are inset-adjusted viewport minus (24px), capped at (790 × 760px), with source minimum dimensions (240 × 180px). Its native scale cancels inherited scaling and applies `GuiTheme.ModalShrink`. The header is (66px) tall; content starts at (78px) and scrolls vertically. Below (530px) arcade width, spin controls stack below the disc; otherwise they sit beside it. Disc size caps at (330px) compact or (390px) wide, with a wide-layout height fit when space permits. These are source behaviors, not verified desktop/phone rendering results.

## Elevation & Depth

Native `UIGradient`, `UIStroke` and model previews provide depth; no offset shadow system is established. Shop card gradients run Raised to Cream; detail uses a pale cyan gradient. White bases preserve gradient colors instead of multiplying them by dark surfaces. The shop shell has a Sky stroke (3px), selected gear a Cyan stroke (3px), and active navigation a Cyan stroke (2.5px).

Rewards uses a light-blue header gradient and gold rim/hub gradients. Its lime base multiplies a white-to-green sheen. Disabled actions disable the gradient as well as input. Shop uses Roblox `AutoButtonColor`; Rewards also binds `GuiTheme.ButtonFeedback` for pressed, hover and controller selection border/gloss response. Wheel motion and confetti values are in the sidecar.

## Shapes

Rounded native containers use the recorded shell, detail, inset and control radii. Wheel rim and hub are circles using oversized corner radii. The fixed wheel pointer is countable native geometry; colored prize sectors are WedgeParts viewed head-on in a ViewportFrame. These functional wheel shapes do not establish a Frame-built illustration icon style.

Illustrations are independent ImageLabels using Fit; Sky uses Crop and the shell corner radius. Icons are noninteractive decoration. No runtime sprite cropping is used.

## Components

### Buttons

Shop purchase/equip actions combine lime gradient, navy native labels, rounded controls and a green border (2px). Pending, equipped, owned and unavailable states come from state/config. Inactive controls use muted colors with gradient disabled; Active and Selectable follow state. Close controls are coral squares with the action gradient removed.

Rewards spin uses a lime base and sheen, native loading/cooldown/pending/spinning labels and disabled input when unavailable. Its helper responds to mouse, touch and controller selection. No additional custom shop focus treatment is established.

### Navigation

Five shop categories use independent illustrated icons and native FredokaOne captions. Selected tabs use turquoise fill and stronger Cyan edging; unselected tabs use light blue. Narrow layouts retain captions while hiding icons.

### Cards / Containers

Catalog cards use cream gradients, blue edges, actual model previews for gear and authored illustration for passes/products. Selected gear uses a stronger Cyan outline. Featured damage and VIP cards retain warm coral/gold gradient variants. Detail repeats the actual model, stats, price/ownership and action; the old selected-item eyebrow exists as a hidden empty label and is not a visible design pattern.

### Prize wheel

Config provides prize labels, sector colors and rewards; the server chooses the result. Icons and native labels travel with the disc while label groups counter-rotate for readability. The wheel makes five turns plus alignment to the selected sector over (4s), then displays the returned prize. The pointer stays fixed; closing during a spin settles the result. Daily cards are not present in this module.

### Shared artwork

`CartoonUI.Assets` and `assets/CartoonUI/upload-manifest.json` contain 20 independent icon IDs plus one Sky ID: 21 image assets in total. Aliases reuse icon IDs and missing icon keys fall back to Gift. The direction's original atlas description is superseded by these independent runtime images. Upload IDs do not establish live loading or visual acceptance.

## Do's and Don'ts

### Do:
- **Do** preserve native labels, prices, cooldowns and ownership over decorative art.
- **Do** use actual equipment models and server-selected spin results.
- **Do** disable the active gradient together with unavailable actions.
- **Do** distinguish offline checks, image upload IDs, Studio visual acceptance and public publication.

### Don't:
- **Don't** bake prices or action labels into raster images.
- **Don't** use emoji or primitive Frame-built substitutes for the authored illustration icons.
- **Don't** treat this scoped system as a redesign of unrelated game interfaces.

Not canonized or repaired: built-in display faces remain an observed craft-floor exception; minimum prize-label legibility and actual image loading need runtime review. The manifest's wording says 20 images despite 20 icon IDs plus Sky, and PRODUCT.md retains the older approval scope. No desktop/phone visual acceptance is claimed: the user stopped Computer Use with physical Escape during capture, and no new captures are available. Offline results supplied by the coordinator are recorded separately in `docs/colorful-ui/implementation.md`.
