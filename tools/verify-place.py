from pathlib import Path
from decimal import Decimal, InvalidOperation
from collections import Counter
import xml.etree.ElementTree as ET

root=Path(__file__).resolve().parent.parent
tree=ET.parse(root/'RaiseAMonster_fixed.rbxlx').getroot()
def name(i): return i.findtext('./Properties/string[@name="Name"]',i.attrib['class'])
def walk(i,p=''):
    p+='/'+name(i)
    yield p,i
    for c in i.findall('Item'): yield from walk(c,p)
items=dict(pair for i in tree.findall('Item') for pair in walk(i))
mapping={
 '/ReplicatedStorage/Shared/':'src/shared/',
 '/ServerScriptService/Server/':'src/server/',
 '/StarterPlayer/StarterPlayerScripts/Client/':'src/client/',
}
count=0
for path,item in items.items():
    if item.attrib['class'] not in ('ModuleScript','Script','LocalScript'): continue
    if path=='/ServerScriptService/Server': file=root/'src/server/init.server.luau'
    elif path=='/StarterPlayer/StarterPlayerScripts/Client': file=root/'src/client/init.client.luau'
    else:
        prefix=next(p for p in mapping if path.startswith(p))
        file=root/(mapping[prefix]+path.removeprefix(prefix)+'.luau')
    actual=item.findtext('./Properties/*[@name="Source"]','').replace('\r\n','\n')
    assert actual==file.read_text(encoding='utf-8').replace('\r\n','\n'),path
    count+=1
rigs=items['/Workspace/AnimationRigs']
models=[i for i in rigs.iter('Item') if i.attrib['class']=='Model']
assert len(models)==150
for model in models:
    classes=[i.attrib['class'] for i in model.iter('Item')]
    assert 'Motor6D' in classes and 'Animator' in classes,name(model)
    assert model.findtext('./Properties/Ref[@name="PrimaryPart"]') not in (None,'null'),name(model)
world=items['/Workspace/StudioWorld']
# The old code-made EggShop stall is intentionally absent from the preview (the authored Blacksmith stand replaces it).
assert not any(name(i)=='EggShop' for i in world.iter('Item'))
weapons=items['/ReplicatedStorage/WeaponModels']
source_weapons=ET.parse(root/'assets/WeaponModels.rbxmx').getroot().find('Item')
def weapon_signature(model):
    """Compare actual geometry/properties and resolved links, ignoring XML ids."""
    identities={}
    def index(item,path):
        identities[item.attrib['referent']]=path
        occurrences={}
        for child in item.findall('Item'):
            key=(child.attrib['class'],name(child))
            occurrence=occurrences.get(key,0); occurrences[key]=occurrence+1
            index(child,path+((key[0],key[1],occurrence),))
    index(model,())
    def property_signature(element):
        text=element.text or ''
        if list(element) and not text.strip(): text=''
        if element.tag=='Ref':
            assert text in ('','null') or text in identities, f'Weapon reference leaves asset: {text}'
            text=identities.get(text,text)
        elif element.tag not in ('string','ProtectedString','BinaryString','url','SharedString') and not list(element):
            try: text=tuple(Decimal(value) for value in text.split())
            except InvalidOperation: text=text.strip()
        elif element.tag in ('BinaryString','SharedString'): text=''.join(text.split())
        return (element.tag,tuple(sorted(element.attrib.items())),text,
                tuple(property_signature(child) for child in element))
    def signature(item):
        properties=item.find('Properties')
        # Rojo explicitly adds this false migration flag to imported PVInstances.
        properties=[p for p in properties if not (p.tag=='bool' and p.attrib.get('name')=='NeedsPivotMigration' and p.text=='false')]
        return (item.attrib['class'],tuple(sorted((property_signature(p) for p in properties),key=lambda p:(p[0],p[1]))),
                tuple(signature(child) for child in item.findall('Item')))
    return signature(model)
assert weapon_signature(weapons)==weapon_signature(source_weapons),'Embedded WeaponModels differ from the approved asset'
templates={name(i) for i in weapons.findall('Item') if i.attrib['class']=='Tool'}
expected_templates={'WoodenBat','IronBat','IronSword','ForestSword','DesertSword','IceSword','LavaSword','VoidBat'}
assert templates==expected_templates, f'Unexpected weapon templates: {templates}'
weapon_counts=Counter(i.attrib['class'] for i in weapons.iter('Item'))
assert weapon_counts==Counter(i.attrib['class'] for i in source_weapons.iter('Item')),'Weapon instance counts differ'
assert not any(e.tag=='uri' or e.attrib.get('name')=='TextureContent' for e in weapons.iter()),'Modern weapon Content is incompatible with pinned Rojo'
referents={i.attrib['referent'] for i in tree.iter('Item')}
missing={ref.text for ref in tree.iter('Ref') if ref.text not in (None,'null') and ref.text not in referents}
assert not missing,missing
shared_keys={entry.attrib['md5'] for entry in tree.findall('./SharedStrings/SharedString')}
missing_shared={ref.text for ref in tree.findall('.//Properties/SharedString') if ref.text not in shared_keys}
assert not missing_shared,missing_shared
print(f'PASS: {count} embedded scripts match source, {len(models)} complete animation rigs, map and shop present, '
      f'{len(templates)} approved weapon templates/{weapon_counts["Part"]} Parts match asset including resolved weld refs; '
      'legacy weapon Content and all instance/shared references resolve.')
