"""Prepare faithful, material-batched copies of the approved Halloween GLBs.

Run with Blender in background mode. This never writes the approved source files.
Run again with ``-- --validate`` in a separate process to verify both exports.
"""

import json
import math
import re
import sys
from collections import defaultdict
from pathlib import Path

import bpy
from mathutils import Vector


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets" / "HalloweenCollection"
OUTPUT = SOURCE / "StudioImport"
NAMES = [
    "GhostSlime", "SkeletonImp", "PumpkinKing", "CountFang",
    "HexCat", "CryptMummy", "GraveGolem", "WraithReaper",
]
STEM = "HalloweenCollection_Studio"
MAX_TRIANGLES = 9000


def triangle_count(mesh):
    mesh.calc_loop_triangles()
    return len(mesh.loop_triangles)


def bounds(objects):
    points = [obj.matrix_world @ Vector(c) for obj in objects for c in obj.bound_box]
    return [[min(v[i] for v in points) for i in range(3)],
            [max(v[i] for v in points) for i in range(3)]]


def srgb(value):
    return value * 12.92 if value <= 0.0031308 else 1.055 * value ** (1 / 2.4) - 0.055


def material_data(material):
    shader = next(node for node in material.node_tree.nodes if node.type == "BSDF_PRINCIPLED")
    color = list(shader.inputs["Base Color"].default_value)
    return {
        "linear_rgba": color,
        "color_rgb_255": [round(max(0, min(1, srgb(v))) * 255) for v in color[:3]],
        "metallic": shader.inputs["Metallic"].default_value,
        "roughness": shader.inputs["Roughness"].default_value,
        "emission_strength": shader.inputs["Emission Strength"].default_value,
    }


def prepare():
    OUTPUT.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.unit_settings.system = "NONE"
    source_manifest = json.loads((SOURCE / "manifest.json").read_text(encoding="utf-8"))
    expected = {entry["name"]: entry for entry in source_manifest["models"]}
    canonical_materials = {}
    result = {"source": "../<character>.glb", "static": True, "rigged": False,
              "coordinate_system": "Blender Z-up, front -Y; FBX Y-up, front -Z",
              "mesh_triangle_limit": MAX_TRIANGLES, "models": [], "materials": {}}
    for index, name in enumerate(NAMES):
        before = set(bpy.context.scene.objects)
        bpy.ops.import_scene.gltf(filepath=str(SOURCE / f"{name}.glb"))
        imported = set(bpy.context.scene.objects) - before
        source_meshes = [obj for obj in imported if obj.type == "MESH"]
        original_triangles = sum(triangle_count(obj.data) for obj in source_meshes)
        assert original_triangles == expected[name]["triangles"], (name, original_triangles)
        original_bounds = bounds(source_meshes)
        grouped = defaultdict(list)
        for obj in source_meshes:
            obj.data.calc_loop_triangles()
            for triangle in obj.data.loop_triangles:
                material = obj.data.materials[triangle.material_index]
                key = re.sub(r"\.\d{3}$", "", material.name)
                if key not in canonical_materials:
                    canonical_materials[key] = material.copy()
                    canonical_materials[key].name = f"Studio_{key}"
                    result["materials"][key] = material_data(material)
                grouped[key].append(tuple(obj.matrix_world @ obj.data.vertices[v].co
                                          for v in triangle.vertices))
        # Preserve each source character as its own named root. Spacing prevents
        # overlapping importer previews; Studio placement can move the roots.
        root = bpy.data.objects.new(name + "_ROOT", None)
        bpy.context.scene.collection.objects.link(root)
        root.location = Vector(((index % 4 - 1.5) * 7, (index // 4) * 7, 0))
        new_objects = []
        for key, triangles in sorted(grouped.items()):
            for chunk_number, start in enumerate(range(0, len(triangles), MAX_TRIANGLES)):
                chunk = triangles[start:start + MAX_TRIANGLES]
                suffix = f"_{chunk_number + 1}" if len(triangles) > MAX_TRIANGLES else ""
                part_name = f"{name}__{key}{suffix}"
                # Exact triangle corners are retained; no decimation, remeshing,
                # welding, texture baking, or geometry substitution is performed.
                vertices = [tuple(vertex) for triangle in chunk for vertex in triangle]
                faces = [(i, i + 1, i + 2) for i in range(0, len(vertices), 3)]
                mesh = bpy.data.meshes.new(part_name)
                mesh.from_pydata(vertices, [], faces)
                mesh.materials.append(canonical_materials[key])
                mesh.update()
                obj = bpy.data.objects.new(part_name, mesh)
                bpy.context.scene.collection.objects.link(obj)
                obj.parent = root
                new_objects.append(obj)
        for obj in imported:
            bpy.data.objects.remove(obj, do_unlink=True)
        bpy.context.view_layer.update()
        combined_triangles = sum(triangle_count(obj.data) for obj in new_objects)
        assert combined_triangles == original_triangles
        translated_bounds = bounds(new_objects)
        for axis in range(3):
            for edge in range(2):
                assert abs(translated_bounds[edge][axis] - root.location[axis]
                           - original_bounds[edge][axis]) < 0.0001
        result["models"].append({
            "name": name, "root_name": root.name, "source_file": f"{name}.glb",
            "source_meshes": len(source_meshes), "mesh_count": len(new_objects),
            "triangles": combined_triangles, "source_local_bounds": original_bounds,
            "preview_translation_blender": list(root.location),
            "meshes": [{"name": obj.name, "material": obj.data.materials[0].name[7:],
                        "triangles": triangle_count(obj.data)} for obj in new_objects],
        })
        print(f"PREPARED {name}: {len(source_meshes)} -> {len(new_objects)} meshes; "
              f"{combined_triangles} triangles", flush=True)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.fbx(
        filepath=str(OUTPUT / f"{STEM}.fbx"), use_selection=True,
        object_types={"MESH", "EMPTY"}, apply_unit_scale=True,
        axis_forward="-Z", axis_up="Y", add_leaf_bones=False,
        bake_anim=False, path_mode="AUTO", use_mesh_modifiers=True,
    )
    bpy.ops.export_scene.gltf(
        filepath=str(OUTPUT / f"{STEM}.glb"), export_format="GLB",
        use_selection=True, export_yup=True, export_apply=True,
    )
    result["mesh_count"] = sum(entry["mesh_count"] for entry in result["models"])
    result["triangles"] = sum(entry["triangles"] for entry in result["models"])
    (OUTPUT / "import_manifest.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(f"PREPARATION COMPLETE: 8 characters, {result['mesh_count']} meshes, "
          f"{result['triangles']} triangles", flush=True)


def validate():
    manifest = json.loads((OUTPUT / "import_manifest.json").read_text(encoding="utf-8"))
    reports = []
    for extension in ("fbx", "glb"):
        bpy.ops.wm.read_factory_settings(use_empty=True)
        path = OUTPUT / f"{STEM}.{extension}"
        if extension == "fbx":
            bpy.ops.import_scene.fbx(filepath=str(path))
        else:
            bpy.ops.import_scene.gltf(filepath=str(path))
        meshes = [obj for obj in bpy.context.scene.objects if obj.type == "MESH"]
        roots = [obj for obj in bpy.context.scene.objects if obj.parent is None]
        assert sorted(obj.name for obj in roots) == sorted(name + "_ROOT" for name in NAMES)
        assert len(meshes) == manifest["mesh_count"]
        assert all(obj.type in {"MESH", "EMPTY"} for obj in bpy.context.scene.objects)
        assert all(0 < triangle_count(obj.data) <= MAX_TRIANGLES for obj in meshes)
        assert all(math.isfinite(v) for obj in meshes for vert in obj.data.vertices for v in vert.co)
        total = sum(triangle_count(obj.data) for obj in meshes)
        assert total == manifest["triangles"]
        for entry in manifest["models"]:
            root = bpy.data.objects[entry["root_name"]]
            descendants = [obj for obj in root.children_recursive if obj.type == "MESH"]
            assert len(descendants) == entry["mesh_count"]
            assert sum(triangle_count(obj.data) for obj in descendants) == entry["triangles"]
            for obj in descendants:
                assert len(obj.data.materials) == 1
                palette = obj.data.materials[0].name[7:]
                assert palette in manifest["materials"], palette
                actual = material_data(obj.data.materials[0])["linear_rgba"]
                expected = manifest["materials"][palette]["linear_rgba"]
                assert all(abs(a - b) < 0.0001 for a, b in zip(actual, expected))
            actual_bounds = bounds(descendants)
            for axis in range(3):
                for edge in range(2):
                    expected = entry["source_local_bounds"][edge][axis] + entry["preview_translation_blender"][axis]
                    assert abs(actual_bounds[edge][axis] - expected) < 0.001
        reports.append({"file": path.name, "bytes": path.stat().st_size,
                        "character_roots": len(roots), "meshes": len(meshes), "triangles": total})
    report = {"passed": True, "independent_reimports": reports,
              "verified": ["8 distinct named character roots", "all source triangles preserved",
                           "all source bounds preserved", "material base colors preserved",
                           "finite geometry", "each mesh below 9000 triangles", "no stage objects"],
              "unverified": ["Native Roblox import, asset upload, appearance and map placement"]}
    (OUTPUT / "validation_report.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print("VALIDATED: " + json.dumps(reports), flush=True)


if __name__ == "__main__":
    validate() if "--validate" in sys.argv else prepare()
