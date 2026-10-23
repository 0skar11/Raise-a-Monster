"""Exercise the updater's scoped cleanup without touching an authored place."""
import ast
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

source = ast.parse(Path(__file__).with_name('update-place.py').read_text())
functions = [node for node in source.body if isinstance(node, ast.FunctionDef)
             and node.name in ('name', 'remove_editor_artifacts')]
namespace = {'ET': ET}
exec(compile(ast.Module(body=functions, type_ignores=[]), 'update-place.py', 'exec'), namespace)


def item(parent, kind, name):
    child = ET.SubElement(parent, 'Item', {'class': kind})
    ET.SubElement(ET.SubElement(child, 'Properties'), 'string', {'name': 'Name'}).text = name
    return child


class CleanupTests(unittest.TestCase):
    def test_removes_only_confirmed_rig_and_row(self):
        tree = ET.Element('roblox')
        workspace = item(tree, 'Workspace', 'Workspace')
        item(workspace, 'Model', 'TemplateR6')
        keep = item(workspace, 'Model', 'AnimationRigs')
        nested = item(keep, 'Model', 'TemplateR6')
        gui = item(tree, 'StarterGui', 'StarterGui')
        item(gui, 'ScreenGui', 'TravelBar')
        pixels = item(gui, 'ScreenGui', 'ToShop')
        settings = item(gui, 'ScreenGui', 'SettingsUI_EditorCopy')
        namespace['remove_editor_artifacts'](tree)
        self.assertEqual(workspace.findall('Item'), [keep])
        self.assertIn(nested, keep.findall('Item'))
        self.assertEqual(gui.findall('Item'), [pixels, settings])

    def test_spawn_remains_enabled_and_invisible_in_both_map_locations(self):
        for baked in (False, True):
            with self.subTest(baked=baked):
                tree = ET.Element('roblox')
                workspace = item(tree, 'Workspace', 'Workspace')
                world = item(workspace, 'Model', 'StudioWorld') if baked else workspace
                map_model = item(world, 'Folder', 'Map')
                spawn = item(map_model, 'SpawnLocation', 'CenterSpawn')
                props = spawn.find('Properties')
                ET.SubElement(props, 'bool', {'name': 'Enabled'}).text = 'true'
                ET.SubElement(props, 'float', {'name': 'Transparency'}).text = '0'
                decal = item(spawn, 'Decal', 'SpawnIcon')
                other = item(map_model, 'SpawnLocation', 'OtherSpawn')
                cleanup = namespace['remove_editor_artifacts']
                cleanup(tree)
                first = ET.tostring(tree)
                cleanup(tree)
                self.assertEqual(ET.tostring(tree), first, 'Cleanup must be idempotent')
                self.assertIn(spawn, map_model.findall('Item'))
                self.assertEqual(props.findtext('*[@name="Enabled"]'), 'true')
                self.assertEqual(props.findtext('*[@name="Transparency"]'), '1')
                self.assertEqual(props.findtext('*[@name="CanCollide"]'), 'false')
                self.assertEqual(decal.findtext('Properties/*[@name="Transparency"]'), '1')
                self.assertIsNone(other.find('Properties/*[@name="Transparency"]'))


if __name__ == '__main__':
    unittest.main()
