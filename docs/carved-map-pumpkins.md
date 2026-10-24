# Carved map pumpkins — 2026-10-24

The user requested replacing natural map pumpkins with a carved orange jack-o'-lantern matching their reference and explicitly allowed Creator Store models.

## Asset source

- Creator Store model: [Jack o Lantern, by Xenostarr](https://create.roblox.com/store/asset/1051236676).
- Retained only the classic pumpkin geometry `16973748` and texture `16973739`. The imported model contained an unrelated lantern assembly; that assembly and the temporary candidate were removed. No imported scripts are used.
- The texture is displayed with white part tint and SmoothPlastic, preserving the orange body and brown stem rather than the model thumbnail's bright tint.
- Native `AssetService:CreateMeshPartAsync` measured mesh size `(1.74819, 1.738895, 1.81699)`. Version 1 mesh-file coordinates are twice the native size; the code uses the measured native size and corresponding center `(0, 0.2544275, 0.002035)`.

## Scope

`PumpkinDecor` converts decorations under `HalloweenWorld.Props`, including nested pumpkin patches and the code-generated flat decoration layout. The original body instances, parent containers and metadata are retained. Only recognized decorative stem, rib and face parts are removed. Models with unknown contents or gameplay prompts are skipped. Hunt pickups, the merchant, hats and monster models are outside this traversal.

The initializer runs after Halloween initialization and reapplies idempotently when the Halloween world is restored from storage. The game does not download or execute a Creator Store model at runtime; its approved mesh and texture are referenced directly.

## Verification

- Native Edit mode: 96 of 96 map pumpkin bodies converted; all 96 remained converted after stopping Play.
- Width and rotation assertions passed for every converted body. Maximum ground-anchor error was `1.1920928955078126e-7` studs.
- A second native conversion changed zero bodies. Play server also reported 96 converted and zero pending bodies.
- `tools/test-pumpkin-decor.luau`: 1544 checks passed, covering nested variants, flat decorations, geometry, prompt/unknown-model exclusions, metadata, idempotence and event lifecycle.
- `tools/test-halloween.luau`: 1361 checks passed. Production compilation: 52 source files passed. A local place build completed.
- Independent verifier accepted the final technical change. Native scene capture showed the selected classic pumpkin before the final all-map pass; later close-up capture returned the viewport's blank 3D layer, so comprehensive final visual fidelity is not claimed.

The edit was applied in Studio before Play, and no cloud place publication was performed.
