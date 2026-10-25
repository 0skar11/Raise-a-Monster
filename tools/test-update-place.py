"""Regression: successive source imports must not reuse retained script referents."""
from pathlib import Path
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET


def item(parent, kind, title, referent):
    node = ET.SubElement(parent, 'Item', {'class': kind, 'referent': referent})
    props = ET.SubElement(node, 'Properties')
    ET.SubElement(props, 'string', {'name': 'Name'}).text = title
    return node


def module(parent, title, referent, source):
    node = item(parent, 'ModuleScript', title, referent)
    ET.SubElement(node.find('Properties'), 'ProtectedString', {'name': 'Source'}).text = source
    return node


def make_place(staged):
    tree = ET.Element('roblox', {'version': '4'})
    workspace = item(tree, 'Workspace', 'Workspace', 'ws')
    world = item(workspace, 'Folder', 'StudioWorld', 'world')
    floor = item(world, 'Part', 'Ground', 'stage-floor' if staged else 'kept-floor')
    rigs = item(workspace, 'Folder', 'AnimationRigs', 'rigs')
    link = item(rigs, 'ObjectValue', 'FloorReference', 'floor-link')
    ET.SubElement(link.find('Properties'), 'Ref', {'name': 'Value'}).text = floor.attrib['referent']
    replicated = item(tree, 'ReplicatedStorage', 'ReplicatedStorage', 'rs')
    shared = item(replicated, 'Folder', 'Shared', 'shared')
    module(shared, 'Existing', 'stage-existing' if staged else 'NEWSCRIPT_5', 'return 2' if staged else 'return 1')
    item(replicated, 'Folder', 'WeaponModels', 'weapons')
    if staged:
        new = module(shared, 'NewModule', '5', 'return 3')
        own_link = item(new, 'ObjectValue', 'SelfReference', 'new-link')
        ET.SubElement(own_link.find('Properties'), 'Ref', {'name': 'Value'}).text = '5'
        item(workspace, 'Model', 'HalloweenArena', 'arena')
    return tree


with tempfile.TemporaryDirectory(prefix='raise-arena-update-') as directory:
    directory = Path(directory)
    stage, actual = directory / 'stage.rbxlx', directory / 'actual.rbxlx'
    ET.ElementTree(make_place(True)).write(stage, encoding='utf-8')
    ET.ElementTree(make_place(False)).write(actual, encoding='utf-8')
    updater = Path(__file__).with_name('update-place.py')
    for iteration in range(2):
        result = subprocess.run([sys.executable, str(updater), str(stage), str(actual)], capture_output=True, text=True)
        assert result.returncode == 0, result.stdout + result.stderr
        tree = ET.parse(actual).getroot()
        nodes = list(tree.iter('Item'))
        ids = [node.attrib['referent'] for node in nodes]
        assert len(ids) == len(set(ids)), 'The import reused an existing referent'
        by_name = {node.findtext('./Properties/string[@name="Name"]'): node for node in nodes}
        existing, new = by_name['Existing'], by_name['NewModule']
        assert existing.attrib['referent'] == 'NEWSCRIPT_5', 'Existing script identity changed'
        assert existing.findtext('./Properties/ProtectedString[@name="Source"]') == 'return 2'
        assert new.attrib['referent'] != 'NEWSCRIPT_5', 'New script collided with a previous import'
        assert by_name['SelfReference'].findtext('./Properties/Ref') == new.attrib['referent']
        assert by_name['FloorReference'].findtext('./Properties/Ref') == 'kept-floor'
        assert sum(node.findtext('./Properties/string[@name="Name"]') == 'HalloweenArena' for node in nodes) == 1
    print('PASS: repeated place updates retain existing identities, namespace new scripts, preserve internal/external links and import one arena')
