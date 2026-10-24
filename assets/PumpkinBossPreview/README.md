# Pumpkin Titan — actual 3D preview

An original modeled interpretation of the user's pumpkin-boss references. The preview PNG is a Blender render of the exported geometry, not an AI image. The browser viewer loads the actual GLB and supports rotation, zoom, and front/side/back views.

## Files

- `PumpkinTitan.blend`: editable Blender scene, including the presentation stage and neutral scale figure.
- `PumpkinTitan.fbx`: selected boss geometry with embedded bark textures; intended for subsequent Roblox import.
- `PumpkinTitan.glb`: portable boss geometry with embedded textures for the interactive viewer.
- `textures/`: five source bark PNGs used by all formats.
- `PumpkinTitan_Preview.png`: render of the same boss geometry, with a 5.5-unit reference figure.
- `model_stats.json` and `validation_report.json`: geometry and native import checks.

The exported boss has 332 mesh objects and 53,490 triangles. It is 28.055 units high, about 5.1 times the reference figure. The stage, lights, cameras, cutters and reference figure are excluded from FBX and GLB.

## View

Serve this folder over HTTP, for example:

```powershell
python -m http.server 8777 --bind 127.0.0.1 --directory assets/PumpkinBossPreview
```

Open `http://127.0.0.1:8777/preview.html`. Drag to rotate, scroll to zoom, or use the view buttons. The vendored model-viewer 4.4.0 module comes from Google's official distribution; its Apache 2.0 license is included in `vendor/LICENSE`. Project information: https://modelviewer.dev/.

## Verification and limits

Fresh isolated Blender processes opened the Blend and imported the FBX and GLB. All formats matched mesh count, triangle count and finite world bounds; every mesh had UVs, and the five bark image textures were packed. The interactive viewer loaded the actual GLB with brown bark rather than unsupported white procedural materials.

The viewer's inherited-background contrast warnings were corrected with explicit dark backgrounds. Text contrast measures 8.11:1 or higher in the checked states; no contrast warning was suppressed. Shop-specific color/radius advisories are left advisory because this standalone inspection viewer is outside the Monster Forge shop's design scope.

This is a static model preview. It has no armature, animations, combat logic or Roblox placement. Studio import and in-game performance have not been verified. Preview approval does not mean the model is already playable.
