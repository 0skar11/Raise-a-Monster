# Halloween monster collection

Eight original, static, editable 3D characters based on the approved concept boards:

| Filename stem | Character |
| --- | --- |
| GhostSlime | Ghost Slime |
| SkeletonImp | Skeleton Imp |
| PumpkinKing | Pumpkin King |
| CountFang | Count Fang |
| HexCat | Hex Cat |
| CryptMummy | Crypt Mummy |
| GraveGolem | Grave Golem |
| WraithReaper | Wraith Reaper |

Each character has `.blend`, `.glb`, `.fbx`, `_Front.png` and `_Back.png` files. `HalloweenCollection.blend` contains the complete collection. Mesh parts and materials have descriptive names. Exports contain character meshes and materials only; portrait lighting, floor and camera are excluded.

`preview.html` is a local interactive viewer with character selection, orbit controls, front/side/back buttons and the actual front/back render gallery. Serve the repository over HTTP and open `/assets/HalloweenCollection/preview.html`. The bundled model-viewer library is covered by `MODEL-VIEWER-LICENSE.txt`.

`Collection_Front.jpg` and `Collection_Back.jpg` are contact sheets made from the Blender renders. `DesignReference_*.png` are the approved concept images, included for comparison; they are not screenshots of the delivered meshes.

## Rebuild and validation

Run `tools/build_halloween_collection.py` with Blender in background mode to regenerate the assets. Run `tools/validate_halloween_collection.py` in a separate Blender process to independently reimport the 16 GLB/FBX exports, open the editable files and inspect basic geometry. Run `tools/preview_halloween_collection.py` with Python and Pillow to rebuild the local gallery and contact sheets.

`manifest.json` records source geometry counts and bounds. `validation_report.json` records independent import results when validation succeeds.

## Delivery boundary

These are static visual assets with no skeleton, skin weights, idle/attack animation or Roblox gameplay configuration. Roblox Studio import, Motor6D integration, physics, mobile performance and multiplayer have not been tested. No game scripts, species configuration, live map or cloud place are changed by this asset build.

Emissive PBR materials are included in GLB. FBX and Roblox may display emission differently; recreate glow using Roblox materials and effects during integration. The collection is a 3D interpretation of the concepts, rather than pixel-identical reconstruction of the generated reference images.
