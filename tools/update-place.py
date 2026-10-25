"""Merge a fresh Rojo build into the actual place, retaining authored instances.
Run: python tools/update-place.py <rojo-build.rbxlx> [actual-place.rbxlx]
"""
from pathlib import Path
import sys, shutil, datetime, uuid, copy as copy_module, xml.etree.ElementTree as ET

root = Path(__file__).resolve().parent.parent
stage = ET.parse(sys.argv[1]).getroot()
target = root / (sys.argv[2] if len(sys.argv) > 2 else 'RaiseAMonster_fixed.rbxlx')
actual = ET.parse(target).getroot()
def name(item):
    return item.findtext('./Properties/string[@name="Name"]', item.attrib['class'])
def remove_editor_artifacts(tree):
    """Remove confirmed editor leftovers while retaining the spawn location."""
    for service in tree.findall('Item'):
        if service.attrib['class'] == 'Workspace':
            for child in service.findall('Item'):
                if child.attrib['class'] == 'Model' and name(child) == 'TemplateR6':
                    service.remove(child)
            worlds = [service] + [child for child in service.findall('Item') if name(child) == 'StudioWorld']
            for world in worlds:
                for model in world.findall('Item'):
                    if name(model) != 'Map': continue
                    for spawn in model.findall('Item'):
                        if spawn.attrib['class'] != 'SpawnLocation' or name(spawn) != 'CenterSpawn': continue
                        for item in [spawn] + [child for child in spawn.findall('Item') if child.attrib['class'] in ('Decal', 'Texture')]:
                            props = item.find('Properties')
                            values = [('float', 'Transparency', '1')]
                            if item is spawn: values.append(('bool', 'CanCollide', 'false'))
                            for kind, key, value in values:
                                prop = props.find(f'*[@name="{key}"]')
                                if prop is None: prop = ET.SubElement(props, kind, {'name': key})
                                prop.text = value
        elif service.attrib['class'] == 'StarterGui':
            for child in service.findall('Item'):
                if child.attrib['class'] == 'ScreenGui' and name(child) == 'TravelBar':
                    service.remove(child)

remove_editor_artifacts(stage)
remove_editor_artifacts(actual)

def scripts(tree):
    result = {}
    def walk(item, path):
        path += '/' + name(item)
        if item.attrib['class'] in ('Script', 'LocalScript', 'ModuleScript'):
            result[path] = item.find('./Properties/*[@name="Source"]')
        for child in item.findall('Item'): walk(child, path)
    for item in tree.findall('Item'): walk(item, '')
    return result
def items(tree):
    result = {}
    def walk(item, path):
        path += '/' + name(item)
        result[path] = item
        for child in item.findall('Item'): walk(child, path)
    for item in tree.findall('Item'): walk(item, '')
    return result
sources, embedded = scripts(stage), scripts(actual)
# New scripts in the source get inserted under the same parent in the actual place.
stage_items, actual_items = items(stage), items(actual)
new_script_prefix = 'NEWSCRIPT_' + uuid.uuid4().hex + '_'
for path in sorted(set(sources) - set(embedded)):
    parent = actual_items.get(path.rsplit('/', 1)[0])
    if parent is None:
        raise ValueError(f'No parent in the place for new script: {path}')
    copy = copy_module.deepcopy(stage_items[path])
    script_references = {element.attrib['referent']: new_script_prefix + element.attrib['referent']
                         for element in copy.iter() if 'referent' in element.attrib}
    for element in copy.iter():
        if 'referent' in element.attrib: element.attrib['referent'] = script_references[element.attrib['referent']]
        if element.tag == 'Ref': element.text = script_references.get(element.text, element.text)
    parent.append(copy)
    print(f'Added new script {path}')
embedded = scripts(actual)
if set(sources) != set(embedded):
    raise ValueError(f'Script paths differ: {set(sources)^set(embedded)}')
for path, source in sources.items(): embedded[path].text = source.text
# Imported models can reference shared binary data stored at the document root.
shared = actual.find('SharedStrings')
if shared is None:
    shared = ET.SubElement(actual, 'SharedStrings')
known = {entry.attrib['md5']: entry.text for entry in shared}
for entry in stage.findall('./SharedStrings/SharedString'):
    key = entry.attrib['md5']
    if key in known:
        assert (known[key] or '').strip() == (entry.text or '').strip(), 'Conflicting shared string'
    else:
        shared.append(entry)
        known[key] = entry.text
# Namespace each import independently of older updates and retained Studio rigs.
import_prefix = 'IMPORT_' + uuid.uuid4().hex + '_'
for element in stage.iter():
    if 'referent' in element.attrib: element.attrib['referent'] = import_prefix + element.attrib['referent']
    if element.tag == 'Ref' and element.text and element.text != 'null': element.text = import_prefix + element.text

def relative_instances(model):
    """Identify repeated named siblings by class/name/occurrence, including root."""
    result = {(): model}
    def walk(parent, path):
        occurrences = {}
        for child in parent.findall('Item'):
            identity = (child.attrib['class'], name(child))
            index = occurrences.get(identity, 0)
            occurrences[identity] = index + 1
            child_path = path + ((identity[0], identity[1], index),)
            result[child_path] = child
            walk(child, child_path)
    walk(model, ())
    return result

def replace_model(parent, imported):
    old = next((child for child in parent.findall('Item') if name(child) == name(imported)), None)
    if old is not None:
        previous = relative_instances(old)
        current = relative_instances(imported)
        remap = {item.attrib['referent']: previous[path].attrib['referent']
                 for path, item in current.items() if path in previous
                 and item.attrib['class'] == previous[path].attrib['class']}
        # Retain the root referent and surviving instances so authored ObjectValues
        # or other references outside the replaced subtree still point correctly.
        for element in imported.iter():
            if 'referent' in element.attrib:
                element.attrib['referent'] = remap.get(element.attrib['referent'], element.attrib['referent'])
            if element.tag == 'Ref': element.text = remap.get(element.text, element.text)
        parent.remove(old)
    parent.append(imported)
stage_workspace = next(i for i in stage.findall('Item') if i.attrib['class']=='Workspace')
workspace = next((i for i in actual.findall('Item') if i.attrib['class']=='Workspace'), None)
if workspace is None:
    workspace = ET.SubElement(actual, 'Item', {'class':'Workspace', 'referent':'AUTHORING_WORKSPACE'})
    props=ET.SubElement(workspace,'Properties')
    ET.SubElement(props,'string',{'name':'Name'}).text='Workspace'
for child in stage_workspace.findall('Item'):
    if name(child) in ('StudioWorld','AnimationRigs','HalloweenPortal','HalloweenArena'):
        if name(child)=='AnimationRigs' and any(name(old)=='AnimationRigs' for old in workspace.findall('Item')):
            continue # Retain animation work saved in Studio on subsequent code updates.
        replace_model(workspace, child)
stage_replicated = next(i for i in stage.findall('Item') if i.attrib['class']=='ReplicatedStorage')
replicated = next(i for i in actual.findall('Item') if i.attrib['class']=='ReplicatedStorage')
weapon_models = next(i for i in stage_replicated.findall('Item') if name(i)=='WeaponModels')
replace_model(replicated, weapon_models)
stage_gui = next((i for i in stage.findall('Item') if i.attrib['class']=='StarterGui'), None)
actual_gui = next((i for i in actual.findall('Item') if i.attrib['class']=='StarterGui'), None)
if stage_gui is not None and actual_gui is not None:
    for child in stage_gui.findall('Item'):
        if name(child) == 'TravelBar': replace_model(actual_gui, child)
backups = root.parent / '.codex-backups'
backups.mkdir(exist_ok=True)
stamp = datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
backup = backups / f'{target.stem}-{stamp}.rbxlx'
shutil.copy2(target, backup)
temporary=target.with_suffix('.updating.rbxlx')
ET.ElementTree(actual).write(temporary,encoding='utf-8',xml_declaration=True)
check=ET.parse(temporary).getroot()
assert {p:s.text for p,s in scripts(check).items()} == {p:s.text for p,s in sources.items()}
referents=[i.attrib['referent'] for i in check.iter('Item')]
assert len(referents)==len(set(referents)), 'Duplicate instance references'
known_referents=set(referents)
missing_refs={ref.text for ref in check.iter('Ref') if ref.text not in (None,'null') and ref.text not in known_referents}
assert not missing_refs, f'Missing instance references: {missing_refs}'
shared_keys = {entry.attrib['md5'] for entry in check.findall('./SharedStrings/SharedString')}
assert all(ref.text in shared_keys for ref in check.findall('.//Properties/SharedString')), 'Missing shared string'
temporary.replace(target)
print(f'Updated {len(sources)} scripts, StudioWorld and WeaponModels; retained authored AnimationRigs.\nFile: {target}\nBackup: {backup}')
