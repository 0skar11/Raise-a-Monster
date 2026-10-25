"""Run in a fresh background Blender to reimport every delivered export."""
import bpy
import json
from pathlib import Path
from mathutils import Vector

OUT = Path(__file__).resolve().parents[1] / 'assets/HalloweenCollection'
NAMES = ['GhostSlime', 'SkeletonImp', 'PumpkinKing', 'CountFang', 'HexCat', 'CryptMummy', 'GraveGolem', 'WraithReaper']
results = []
for name in NAMES:
    for extension in ('glb', 'fbx'):
        bpy.ops.wm.read_factory_settings(use_empty=True)
        path = OUT / f'{name}.{extension}'
        assert path.is_file() and path.stat().st_size > 1000, str(path)
        if extension == 'glb':
            bpy.ops.import_scene.gltf(filepath=str(path))
        else:
            bpy.ops.import_scene.fbx(filepath=str(path))
        meshes = [o for o in bpy.context.scene.objects if o.type == 'MESH']
        assert meshes, f'No meshes: {path}'
        assert not any(o.type in {'CAMERA', 'LIGHT'} for o in bpy.context.scene.objects), f'Stage leaked: {path}'
        corners = [o.matrix_world @ Vector(corner) for o in meshes for corner in o.bound_box]
        dimensions = [max(v[a] for v in corners)-min(v[a] for v in corners) for a in range(3)]
        assert min(dimensions) > 0.1, f'Invalid dimensions: {path}'
        triangles = sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in meshes)
        assert triangles > 100, f'Empty geometry: {path}'
        results.append({'file':path.name,'meshes':len(meshes),'triangles':triangles,'dimensions':dimensions,'bytes':path.stat().st_size})
    for extension in ('blend',):
        path=OUT/f'{name}.{extension}'
        bpy.ops.wm.open_mainfile(filepath=str(path))
        assert any(o.type == 'MESH' for o in bpy.context.scene.objects), str(path)
    for view in ('Front', 'Back'):
        assert (OUT/f'{name}_{view}.png').is_file(), f'Missing {name} {view} render'
bpy.ops.wm.open_mainfile(filepath=str(OUT/'HalloweenCollection.blend'))
assert len([o for o in bpy.context.scene.objects if o.type == 'MESH']) > 8
(OUT/'validation_report.json').write_text(json.dumps({'passed':True,'independent_imports':results,'limits':['Static models, no skeletal animation','Roblox import and runtime performance not tested']},indent=2),encoding='utf-8')
print('VALIDATED: 16 exports, 8 editable model files, collection, and 16 render files')
