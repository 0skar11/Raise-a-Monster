---
name: Monster Forge
description: Native Roblox shop with dark stone surfaces, bronze edges and warm purchase controls.
colors:
  ink: "#070f14"
  stone: "#0f1a21"
  raised: "#18252d"
  edge: "#516977"
  bronze: "#946d3e"
  gold: "#ffc552"
  ivory: "#ffedc4"
  text: "#f6f3e2"
  muted: "#c1d3dc"
  cyan: "#26ddff"
  red: "#bb3624"
typography:
  body:
    fontFamily: "Enum.Font.GothamBold"
    fontSize: "13px"
  label:
    fontFamily: "Enum.Font.GothamBold"
    fontSize: "14px"
rounded:
  shell: "9px"
  control: "5px"
  stat: "4px"
spacing:
  compact: "8px"
  regular: "12px"
components:
  button-primary:
    backgroundColor: "{colors.gold}"
    textColor: "{colors.ink}"
    rounded: "{rounded.control}"
    height: "44px"
  button-close:
    backgroundColor: "{colors.stone}"
    textColor: "{colors.ivory}"
    rounded: "{rounded.control}"
    size: "44px"
  category:
    backgroundColor: "{colors.stone}"
    textColor: "{colors.muted}"
    rounded: "{rounded.control}"
  category-selected:
    backgroundColor: "{colors.bronze}"
    textColor: "{colors.ivory}"
    rounded: "{rounded.control}"
  catalog-card:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.text}"
    rounded: "{rounded.control}"
  stat:
    backgroundColor: "{colors.ink}"
    textColor: "{colors.text}"
    rounded: "{rounded.stat}"
---

# Design System: Monster Forge

## Overview

**Creative North Star: "Monster Forge"**

The implemented shop uses midnight stone, bronze framing and warm ivory text to hold a dense catalog of native Roblox controls and actual game models. Gold marks purchase actions; cyan outlines the selected gear card. This document is scoped to the Monster Forge shop, not the rest of Raise a Monster.

This records the current source and bounded native Studio checks. Sources are `src/client/MonsterForge.luau`, shop sizing and preview helpers in `src/client/UI.luau`, `PRODUCT.md`, `docs/monster-forge/brief.md`, and `assets/MonsterForge/README.md` and `provenance.json`. The approved comp establishes direction; the code establishes the values recorded here. Seven decorative images were uploaded, assigned runtime IDs and observed loaded in Studio on 2026-10-23. Desktop and landscape phone screenshots and scrolling were reviewed. Complete illustration fidelity, real purchases and cloud place publication are not established by these checks.

**Key Characteristics:**
- Dense dark containers with warm metal edges.
- Native text and controls above decorative art.
- Actual 3D equipment previews.
- Native pixel sizing with scrolling and responsive reflow.

## Colors

Cool dark surfaces support warm labels and controls, with narrow contextual accents.

### Primary
- **Gold:** action base and active category border; the button also carries a vertical warm gradient.
- **Bronze:** outer shell border, selected navigation background and scrollbars.

### Secondary
- **Cyan:** selected gear outline.
- **Red:** Double Damage card outline.

### Neutral
- **Ink / Stone / Raised:** panel, header and catalog tonal layers.
- **Edge:** ordinary card and stat borders; inactive action base.
- **Ivory / Text / Muted:** prominent names and prices, regular labels, and supporting copy respectively.

**The State Accent Rule.** Use the selected gear outline and selected category treatment to communicate the current selection independently of item artwork.

## Typography

**Body Font:** native `Enum.Font.GothamBold`.

Supporting copy uses the body role, with compact descriptions at (12px). Navigation uses the label role, stepping down to (12px) on compact layouts. Gear names use (13px or 15px); prices use (17px). Selected-item stats use (14px or 17px), and the selected price uses (17px or 21px). These are native `TextSize` values, not browser CSS measurements. `TextWrapped` is enabled and `RichText` is disabled.

The current title, selected-item name and action faces are recorded under defects below rather than established as future display typography. No custom font asset is configured by this module. No line-height or tracking token is established.

## Layout

The shop is centered within the inset-adjusted viewport, capped at (1060 × 520 native pixels), with (24px) subtracted from available width and height. Its `UIScale` cancels the surrounding UI scale so the catalog reflows at native pixel sizes.

Compact mode begins when panel width is below (840px) or height below (420px). It uses the compact spacing token instead of regular spacing. Navigation width is (162px) normally, (126px) in compact mode and (86px) below (480px) panel width. Below that narrow threshold the decorative navigation icons and forge mark are hidden; category labels remain.

Weapons, accessories and owned gear use a catalog plus selected-item detail. Detail moves into the same vertical scrolling content when available content width is below (370px) or height below (300px). The gear grid uses one to three columns; product cards use one to three columns. Gamepasses have two featured cards followed by smaller upgrades, with fewer columns in compact layouts. Navigation and content scroll independently. Desktop and landscape phone checks are recorded in `docs/monster-forge/runtime-qa.md`.

## Elevation & Depth

Depth comes from vertical `UIGradient` tonal layers, `UIStroke` edges and native 3D previews. Cards shade from Raised to Ink; selected detail shades from RGB (13, 31, 43) to Ink. The shell uses a bronze stroke (3px); ordinary borders use (1px), and selected gear uses a cyan stroke (3px). No hard offset shadow is present in the shop module. Text carries an Ink stroke with transparency (0.3).

The button gradient runs from RGB (255, 218, 126) to RGB (218, 145, 42), including on currently inactive actions. The close control and category buttons explicitly remove that gradient. Custom tween or easing tokens are not implemented; controls use Roblox `AutoButtonColor`.

## Shapes

The shell is softly squared; cards, details and controls share the smaller control radius; stat blocks use the stat radius. Borders remain separate native strokes. Artwork is fitted inside preview regions rather than carrying control labels. The optional shell image is configured for nine-slice scaling with center rectangle (64, 144, 1799, 780).

## Components

### Buttons

Purchase and equip actions use gold gradient controls with Ink text, Ivory borders and a fixed native height from the component token. Their labels expose pending, owned, equipped and unavailable states. `Active` and `Selectable` follow state; changing the base background does not remove the existing gradient. The close control is a square Stone variant. Focus and hover visuals are Roblox defaults; no custom focus design is evidenced.

### Navigation

Five category buttons use Stone and Muted at rest, Bronze and Ivory when selected, with a Gold selected stroke. Compact mode reduces tab height from (65px) to (48px). Icons are native geometry built from Frames; they are documented as an implementation defect below, not a reusable icon system.

### Cards / Containers

Catalog cards share the Ink-to-Raised tonal treatment and Edge border. Gear cards expose a transparent full-card selection target. Prices and ownership remain native text; the selected state adds the cyan outline. Featured pass cards enlarge the art and heading above their purchase control.

### Selected-item detail

The detail panel repeats the selected equipment model, two stat blocks, current price or ownership state, and one action. Weapon and accessory previews reuse `UI.WeaponPreview` and `UI.GearPreview`; their appearance depends on actual game models. The existing model preview provides its own native pedestal, so the decorative Pedestal asset is optional.

## Do's and Don'ts

### Do:
- **Do** preserve native labels, prices, states and actionable controls over decorative artwork.
- **Do** use actual equipment models for item previews.
- **Do** reflow and scroll the catalog using native pixel sizes.
- **Do** distinguish source delivery, asset activation and Studio visual acceptance.

### Don't:
- **Don't** bake control labels or prices into raster art.
- **Don't** treat uploaded artwork as native Studio visual acceptance.
- **Don't** extend this shop-specific palette into unrelated screens without inspecting their incumbent system.

Not canonized or repaired: the current selected-item eyebrow, Frame-built glyph icons and GothamBlack system display faces remain craft-floor defects, not future house rules. Seven decorative PNGs were uploaded and observed loaded in Studio on 2026-10-23; provenance still flags damage-art composition drift and unverified capsule translucency. Bounded native QA passed, with real purchases, complete illustration fidelity and cloud publication outside the verified scope.
