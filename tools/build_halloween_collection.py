"""Build the eight approved Halloween characters as editable static Blender assets.

Run with Blender 5.2: blender --background --python tools/build_halloween_collection.py
All character meshes are authored here; no downloaded or paid assets are used.
"""
import bpy
import bmesh
import math
import json
import random
import sys
from pathlib import Path
from mathutils import Vector

random.seed(25102026)
bpy.context.preferences.filepaths.save_version=0
ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets' / 'HalloweenCollection'
OUT.mkdir(parents=True, exist_ok=True)
ONLY = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
QUICK = '--quick' in ONLY
FRONTS = '--fronts' in ONLY
RENDER_ONLY = '--render-only' in ONLY
PATCH_MODELS = '--patch-models' in ONLY
ONLY = [x for x in ONLY if not x.startswith('--')]
if RENDER_ONLY:
    # Reuse the approved geometry and exports for final imagery without rebuilding.
    bpy.ops.wm.open_mainfile(filepath=str(OUT/'HalloweenCollection.blend'))
    scene=bpy.context.scene
    names=['GhostSlime','SkeletonImp','PumpkinKing','CountFang','HexCat','CryptMummy','GraveGolem','WraithReaper']
    positions=[(-7,0),(-2.5,0),(2.5,0),(7,0),(-7,7),(-2.5,7),(2.5,7),(7,7)]
    cols={name:bpy.data.collections[name] for name in names}
    for name,(x,y) in zip(names,positions):
        for o in cols[name].objects:o.location-=Vector((x,y,0))
    scene.render.engine='BLENDER_EEVEE' if QUICK else 'CYCLES'
    scene.cycles.samples=24;scene.cycles.use_denoising=True
    scene.render.resolution_percentage=100
    camera=scene.camera
    views=[('Front',Vector((.46,-1,.35)))]
    if not FRONTS:views.append(('Back',Vector((-.57,1,.31))))
    for view,vec in views:
        for name in names:
            if ONLY and name not in ONLY:continue
            for other,c in cols.items():c.hide_render=other!=name
            bpy.context.view_layer.update()
            cs=[o.matrix_world@Vector(c) for o in cols[name].objects if o.type=='MESH' for c in o.bound_box]
            lo=Vector(tuple(min(v[i] for v in cs) for i in range(3)))
            hi=Vector(tuple(max(v[i] for v in cs) for i in range(3)))
            center=(lo+hi)/2
            camera.data.ortho_scale=max((hi.z-lo.z)*1.23,max(hi.x-lo.x,hi.y-lo.y)*1.37)
            camera.location=center+vec.normalized()*12
            camera.rotation_euler=(center+Vector((0,0,.03))-camera.location).to_track_quat('-Z','Y').to_euler()
            scene.render.filepath=str(OUT/(name+'_'+view+'.png'))
            bpy.ops.render.render(write_still=True)
            print('RENDERED',name,view,flush=True)
    for name,(x,y) in zip(names,positions):
        cols[name].hide_render=False
        for o in cols[name].objects:o.location+=Vector((x,y,0))
    camera.location=(14,-19,17)
    camera.rotation_euler=(Vector((0,3,1.5))-camera.location).to_track_quat('-Z','Y').to_euler()
    camera.data.ortho_scale=24
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'HalloweenCollection.blend'))
    print('FINAL RENDERS COMPLETE',flush=True)
    sys.exit(0)
MODELS = {}
if PATCH_MODELS:
    bpy.ops.wm.open_mainfile(filepath=str(OUT/'HalloweenCollection.blend'))
    names=['GhostSlime','SkeletonImp','PumpkinKing','CountFang','HexCat','CryptMummy','GraveGolem','WraithReaper']
    positions=[(-7,0),(-2.5,0),(2.5,0),(7,0),(-7,7),(-2.5,7),(2.5,7),(7,7)]
    for name,(x,y) in zip(names,positions):
        col=bpy.data.collections[name]
        if name in ONLY:
            for o in list(col.objects):bpy.data.objects.remove(o,do_unlink=True)
            bpy.data.collections.remove(col)
        else:
            MODELS[name]=col
            for o in col.objects:o.location-=Vector((x,y,0))
    BASE=bpy.data.collections['Studio']
    for o in list(BASE.objects):bpy.data.objects.remove(o,do_unlink=True)
else:
    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)
    for c in list(bpy.data.collections):
        if c.name != 'Collection':bpy.data.collections.remove(c)
    BASE=bpy.data.collections.get('Collection');BASE.name='Studio'
CURRENT=BASE

def mat(name, color, metallic=0, roughness=.68, emission=0):
    # Palette values are authored as sRGB swatches. Shader sockets and glTF
    # factors use linear RGB; passing the swatches straight in washes dark hues.
    color=tuple(v/12.92 if v<=.04045 else ((v+.055)/1.055)**2.4 for v in color)
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*color, 1)
    m.use_nodes = True
    p = m.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value = (*color, 1)
    p.inputs['Metallic'].default_value = metallic
    p.inputs['Roughness'].default_value = roughness
    if emission:
        p.inputs['Emission Color'].default_value = (*color, 1)
        p.inputs['Emission Strength'].default_value = emission
    return m

M = {}
for name, color, metal, rough, em in [
    ('Pearl',(.69,.49,.89),.07,.43,0),('PearlLight',(.88,.73,.99),.08,.38,0),
    ('PearlShade',(.45,.22,.68),0,.6,0),('Void',(.023,.012,.048),0,.9,0),
    ('Violet',(.22,.055,.38),.05,.67,0),('Purple',(.36,.08,.56),0,.6,0),
    ('PurpleLight',(.53,.16,.73),.05,.55,0),('BlackFur',(.047,.038,.085),0,.87,0),
    ('Indigo',(.105,.075,.21),0,.8,0),('IndigoLight',(.18,.12,.32),0,.8,0),
    ('Bone',(.78,.65,.44),0,.65,0),('Ivory',(.96,.83,.61),0,.58,0),
    ('BoneShadow',(.47,.34,.22),0,.85,0),('Bandage',(.73,.57,.38),0,.9,0),
    ('BandageLight',(.94,.81,.59),0,.88,0),('BandageDark',(.53,.39,.25),0,.95,0),
    ('Orange',(.94,.23,.025),0,.6,0),('OrangeLight',(1,.39,.035),0,.6,0),
    ('OrangeDark',(.50,.075,.009),0,.75,0),('Wood',(.26,.105,.035),0,.9,0),
    ('WoodLight',(.43,.21,.067),0,.88,0),('WoodDark',(.125,.042,.018),0,.95,0),
    ('Vine',(.18,.27,.045),0,.85,0),('Leaf',(.32,.42,.055),0,.83,0),
    ('Gold',(.95,.48,.055),.65,.31,0),('Bronze',(.55,.27,.065),.6,.4,0),
    ('Red',(.53,.018,.075),0,.65,0),('Magenta',(.65,.035,.20),0,.6,0),
    ('Ruby',(.95,.025,.055),.25,.27,.3),('Stone',(.30,.32,.34),0,.95,0),
    ('StoneLight',(.43,.44,.45),0,.95,0),('StoneDark',(.17,.18,.21),0,.98,0),
    ('Moss',(.22,.31,.035),0,.97,0),('MossLight',(.39,.45,.07),0,.95,0),
    ('Cyan',(.035,.82,1),.1,.35,3),('Mint',(.05,1,.48),0,.5,2.3),
    ('Lime',(.36,1,.025),0,.4,2),('Amber',(1,.45,.025),0,.4,3),
    ('GhostGlow',(.81,.27,1),0,.3,3),('Scarab',(.31,.055,.79),.5,.3,.2),
]:
    M[name] = mat(name, color, metal, rough, em)

def link(obj, name, material=None):
    obj.name = name
    for c in list(obj.users_collection):
        c.objects.unlink(obj)
    CURRENT.objects.link(obj)
    if material:
        obj.data.materials.append(M[material] if isinstance(material,str) else material)
    if obj.type == 'MESH':
        for p in obj.data.polygons:
            p.use_smooth = False
    return obj

def mesh(name, verts, faces, material, variants=None):
    data = bpy.data.meshes.new(name + '_Mesh')
    data.from_pydata(verts, [], faces)
    data.update()
    bm=bmesh.new();bm.from_mesh(data)
    bmesh.ops.recalc_face_normals(bm,faces=bm.faces)
    bm.to_mesh(data);bm.free()
    obj = link(bpy.data.objects.new(name,data),name,material)
    if variants:
        for v in variants: data.materials.append(M[v])
        for p in data.polygons:
            if random.random() < .24: p.material_index = random.randrange(len(data.materials))
    return obj

def ico(name, pos, scale, material, sub=1):
    bpy.ops.mesh.primitive_ico_sphere_add(subdivisions=sub, radius=1, location=pos)
    obj=link(bpy.context.object,name,material)
    obj.scale=scale
    return obj

def uv(name,pos,scale,material,segments=16,rings=8):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments,ring_count=rings,radius=1,location=pos)
    obj=link(bpy.context.object,name,material); obj.scale=scale
    return obj

def cube(name,pos,scale,material,bevel=.07):
    bpy.ops.mesh.primitive_cube_add(size=2,location=pos)
    obj=link(bpy.context.object,name,material); obj.scale=scale
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    if bevel:
        mod=obj.modifiers.new('Carved edges','BEVEL'); mod.width=bevel; mod.segments=1
        bpy.context.view_layer.objects.active=obj
        bpy.ops.object.modifier_apply(modifier=mod.name)
    return obj

def tube(name, points, radii, material, sides=8):
    if isinstance(radii,(int,float)): radii=[radii]*len(points)
    ps=[Vector(p) for p in points]; vs=[]
    for i,p in enumerate(ps):
        tangent=(ps[min(i+1,len(ps)-1)]-ps[max(i-1,0)]).normalized()
        ref=Vector((0,1,0))
        if abs(tangent.dot(ref))>.92: ref=Vector((1,0,0))
        u=tangent.cross(ref).normalized(); v=tangent.cross(u).normalized()
        for j in range(sides):
            a=2*math.pi*j/sides
            vs.append(p+radii[i]*(math.cos(a)*u+math.sin(a)*v))
    fs=[]
    for i in range(len(ps)-1):
        for j in range(sides): fs.append((i*sides+j,i*sides+(j+1)%sides,(i+1)*sides+(j+1)%sides,(i+1)*sides+j))
    fs.extend([tuple(reversed(range(sides))),tuple((len(ps)-1)*sides+j for j in range(sides))])
    return mesh(name,vs,fs,material)

def bone(name,a,b,r=.13):
    tube(name+'_Shaft',[a,b],[r*.72,r*.61],'Ivory',7)
    for i,p in enumerate([a,b]): ico(name+'_Joint'+str(i),p,(r,r,r),'Bone',1)

def ribbon(name,points,width,material):
    ps=[Vector(p) for p in points]
    direction=(ps[-1]-ps[0]).normalized()
    across=Vector((0,0,1)).cross(direction).normalized()*width*.5
    vs=[p+across*s for p in ps for s in [-1,1]]
    fs=[(i*2,i*2+1,i*2+3,i*2+2) for i in range(len(ps)-1)]
    obj=mesh(name,vs,fs,material)
    mod=obj.modifiers.new('Cloth ribbon thickness','SOLIDIFY');mod.thickness=.035
    bpy.context.view_layer.objects.active=obj;bpy.ops.object.modifier_apply(modifier=mod.name)
    return obj

def poly(name, outline, y, thick, material, bevel=0):
    # Front-facing 2D silhouette in X/Z with actual depth.
    n=len(outline); vs=[(x,y,z) for x,z in outline]+[(x,y+thick,z) for x,z in outline]
    fs=[tuple(reversed(range(n))),tuple(range(n,n*2))]
    fs += [(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
    obj=mesh(name,vs,fs,material)
    if bevel:
        mod=obj.modifiers.new('Soft cut bevel','BEVEL');mod.width=bevel;mod.segments=1
        bpy.context.view_layer.objects.active=obj
        bpy.ops.object.modifier_apply(modifier=mod.name)
    return obj

def eye(name,x,z,y,kind='Amber',size=.28,slant=1):
    # Angular socket, colored eye, small specular facet.
    side=1 if x<0 else -1
    pts=[(x-side*size*.9,z+size*.9),(x+side*size*.9,z+size*.40),(x+side*size*.6,z-size*.65),(x-side*size*.65,z-size*.6)]
    poly(name+'_Socket',pts,y,.07,'Void',.025)
    pts2=[(x+(a-x)*.62,z+(b-z)*.65) for a,b in pts]
    poly(name+'_Glow',pts2,y-.045,.025,kind)

def diamond(name,pos,sx,sz,material):
    x,y,z=pos
    return mesh(name,[(x-sx,y,z),(x,y, z+sz),(x+sx,y,z),(x,y,z-sz),(x,y-.12,z)],[(0,1,4),(1,2,4),(2,3,4),(3,0,4),(3,2,1,0)],material)

def leaf(name,pos,size=.2,rotation=0):
    x,y,z=pos
    obj=mesh(name,[(x,y,z),(x+size,y-.03,z+size*.5),(x,y-.08,z+size*1.7),(x-size*.8,y,z+size*.6),(x,y-.13,z+size*.7)],[(0,1,4),(1,2,4),(2,3,4),(3,0,4)],'Leaf')
    obj.rotation_euler[1]=rotation
    return obj

def start(name):
    global CURRENT
    CURRENT=bpy.data.collections.new(name);bpy.context.scene.collection.children.link(CURRENT)
    MODELS[name]=CURRENT

def ghost():
    start('GhostSlime')
    n=32
    profiles=[(.18,1.0,0),(.62,1.14,0),(1.18,1.13,0),(1.75,1.04,0),(2.15,.86,0),(2.42,.59,0),(2.59,.31,-.06),(2.78,.19,-.20),(2.97,.16,-.42),(3.18,.14,-.50),(3.34,.11,-.39),(3.37,.06,-.20),(3.26,.005,-.08)]
    vs=[]
    for k,(z,r,cx) in enumerate(profiles):
        for j in range(n):
            a=2*math.pi*j/n
            zz=z
            if k==0: zz+=.20*(1-math.cos(a*5))
            elif k==1: zz+=.05*math.cos(a*5)
            rr=r*(1+.035*math.sin(3*a+k*.7)+(.16*math.cos(a*5) if k==0 else 0))
            vs.append((cx+rr*math.cos(a),rr*.75*math.sin(a),zz))
    fs=[]
    for k in range(len(profiles)-1):
        for j in range(n):
            a=k*n+j;b=k*n+(j+1)%n;c=(k+1)*n+(j+1)%n;d=(k+1)*n+j
            fs.extend([(a,b,c),(a,c,d)])
    fs.extend([tuple(reversed(range(n))),tuple((len(profiles)-1)*n+j for j in range(n))])
    mesh('Pearlescent scalloped spirit',vs,fs,'Pearl',['PearlLight','PearlShade'])
    for s in [-1,1]:
        x=s*.48
        eye('SpiritEye'+str(s),x,1.72,-.782,'GhostGlow',.29,-s)
        ico('Floating mitten'+str(s),(s*1.48,-.01,1.30),( .27,.24,.36),'PearlLight',2)
        ico('Floating thumb'+str(s),(s*1.27,-.16,1.27),(.14,.15,.19),'Pearl',1)
    poly('Zigzag smile',[(-.28,1.2),(-.13,1.13),(0,1.23),(.12,1.12),(.29,1.2),(.14,.98),(0,1.07),(-.12,.98)],-.893,.025,'Void')
    for s in [-1,1]:
        ico('Blush'+str(s),(s*.79,-.68,1.29),(.13,.025,.065),'PearlLight',1)
    tube('Trailing spirit curl',[(-.9,.2,.52),(-1.2,.19,.39),(-1.42,.18,.58),(-1.5,.18,.87)],[.26,.18,.09,.004],'PearlLight',9)

def imp():
    start('SkeletonImp')
    ico('Demon skull',(0,0,2.98),(.85,.62,.85),'Ivory',2)
    ico('Jawbone',(0,-.10,2.5),(.53,.45,.34),'Bone',1)
    for s in [-1,1]:
        eye('ImpEye'+str(s),s*.38,2.95,-.57,'Amber',.32,-s)
        poly('Cheek ridge'+str(s),[(s*.25,2.63),(s*.57,2.64),(s*.74,2.95),(s*.62,2.55),(s*.4,2.43)],-.585,.10,'Ivory')
        tube('Curled purple horn'+str(s),[(s*.55,.12,3.52),(s*.77,.13,3.91),(s*1.01,.10,4.01),(s*1.17,.03,3.84),(s*1.12,-.03,3.62),(s*.96,-.1,3.57)],[.25,.27,.23,.17,.10,.01],'Violet',7)
        poly('Elfin bone ear'+str(s),[(s*.64,3.02),(s*1.1,3.43),(s*.96,2.85),(s*.70,2.72)],-.03,.19,'Bone')
    poly('Nasal cavity',[(-.11,2.68),(0,2.82),(.11,2.68),(.06,2.61),(0,2.65),(-.06,2.61)],-.635,.02,'Void')
    for i in range(5):
        x=(i-2)*.16
        poly('Skull tooth'+str(i),[(x-.075,2.48),(x+.075,2.48),(x+.045,2.28),(x-.035,2.32)],-.48,.16,'Ivory')
    uv('Violet soul',(0,0,1.88),(.29,.28,.46),'GhostGlow',12,6)
    bone('Spine',(0,.2,1.15),(0,.2,2.48),.12)
    for i in range(4):
        z=1.55+i*.21
        for s in [-1,1]:
            tube('Floating rib'+str(i)+str(s),[(s*.08,.17,z+.08),(s*.37,.14,z+.15),(s*.51,-.06,z+.08),(s*.39,-.32,z-.02),(s*.10,-.36,z-.04)],[.07,.075,.07,.065,.04],'Ivory',7)
    ico('Pelvis',(0,.02,1.15),(.44,.29,.24),'Violet',1)
    for s in [-1,1]:
        shoulder=(s*.61,0,2.22);elbow=(s*.94,-.02,1.83 if s<0 else 2.30);wrist=(s*1.14,-.31,1.43 if s<0 else 2.6)
        bone('Upper arm'+str(s),shoulder,elbow,.135);bone('Forearm'+str(s),elbow,wrist,.12)
        ico('Wrist wrap'+str(s),wrist,(.18,.14,.15),'Violet',1)
        ico('Palm'+str(s),(wrist[0],wrist[1]-.06,wrist[2]-.08),(.23,.13,.22),'Bone',1)
        for j in range(3):
            a=(wrist[0]+(j-1)*.15,wrist[1]-.16,wrist[2]-.14)
            b=(a[0]+s*.045,a[1]-.09,a[2]-.24)
            bone('Finger'+str(s)+str(j),a,b,.07)
        bone('Thumb'+str(s),(wrist[0]-s*.18,wrist[1],wrist[2]),(wrist[0]-s*.28,wrist[1]-.13,wrist[2]-.16),.085)
        hip=(s*.28,.05,1.14);knee=(s*.5,-.03,.67);ankle=(s*.55,-.03,.28)
        bone('Thigh'+str(s),hip,knee,.15);bone('Shin'+str(s),knee,ankle,.13)
        ico('Knee wrap'+str(s),knee,(.21,.2,.17),'Violet',1)
        ico('Foot'+str(s),(s*.56,-.18,.15),(.32,.38,.16),'Bone',1)
        for j in range(3):
            tube('Foot talon'+str(s)+str(j),[(s*.56+(j-1)*.19,-.35,.16),(s*.56+(j-1)*.2,-.62,.09)],[.1,.012],'Ivory',6)
    tube('Imp articulated tail',[(0,.26,1.08),(.3,.65,.84),(.7,.83,.83),(1,.89,1.02),(1.16,.85,1.23)],[.15,.14,.1,.07,.005],'Violet',7)
    for i,p in enumerate([(.35,.68,.92),(.72,.84,.91),(.99,.88,1.1)]):
        tube('Tail bone spike'+str(i),[p,(p[0],p[1],p[2]+.23)],[.09,.003],'Ivory',5)

def cape(name,width,top,bottom,y,material='Violet'):
    # Full back panel has an uneven cut hem, broad shoulder fold and triangular facets.
    ns=12;vs=[]
    for k,(z,w,yy) in enumerate([(top,width*.56,y),(top-.35,width,y+.12),(bottom,width*.88,y+.30)]):
        for j in range(ns+1):
            t=j/ns;xx=(t-.5)*2*w
            zz=z+(.14*(j%2) if k==2 else .04*math.cos(t*8))
            vs.append((xx,yy+.14*math.cos(t*math.pi*6),zz))
    fs=[]
    for k in range(2):
        for j in range(ns):
            a=k*(ns+1)+j;b=a+1;c=b+ns+1;d=a+ns+1
            fs.extend([(a,b,c),(a,c,d)])
    obj=mesh(name,vs,fs,material,['Purple','PurpleLight'])
    sol=obj.modifiers.new('Cloth thickness','SOLIDIFY');sol.thickness=.045
    bpy.context.view_layer.objects.active=obj;bpy.ops.object.modifier_apply(modifier=sol.name)
    return obj

def pumpkin():
    start('PumpkinKing')
    for s in [-1,1]:
        uv('Root foot'+str(s),(s*.5,-.12,.24),(.43,.53,.25),'Wood',12,6)
        for j in range(3): tube('Foot root'+str(s)+str(j),[(s*.5+(j-1)*.23,-.2,.30),(s*.5+(j-1)*.31,-.65,.06)],[.20,.025],'WoodLight',7)
        tube('Tree leg'+str(s),[(s*.48,.04,.25),(s*.45,.04,.85),(s*.35,.03,1.36)],[.29,.25,.28],'Wood',9)
    ico('Twisted trunk',(0,.03,1.75),(.72,.46,.85),'Wood',2)
    for i in range(6):
        a=i*math.pi/3
        tube('Trunk bark ridge'+str(i),[(.47*math.cos(a),.33*math.sin(a),1.0),(.61*math.cos(a+.2),.40*math.sin(a+.2),1.7),(.53*math.cos(a),.36*math.sin(a),2.35)],[.09,.12,.065],'WoodLight',6)
    cape('Royal tattered cape',1.05,2.47,.50,.43)
    for s in [-1,1]:
        a=(s*.68,.04,2.14);b=(s*1.05,-.03,1.71);c=(s*1.26,-.2,1.17)
        tube('Branch arm'+str(s),[a,b,c],[.31,.30,.25],'Wood',9)
        ico('Bark shoulder'+str(s),a,(.41,.32,.32),'WoodLight',1)
        for j in range(3):
            x=s*1.24+(j-1)*.19
            tube('Claw root finger'+str(s)+str(j),[(x,-.23,1.31),(x+s*.08,-.35,.96),(x+s*.03,-.45,.76)],[.12,.09,.006],'WoodLight',6)
        points=[]
        for k in range(19):
            t=k/18;ang=t*math.pi*4
            points.append((s*(.82+.37*t)+.31*math.cos(ang),-.05+.29*math.sin(ang),2.1-.77*t))
        tube('Arm wrapping vine'+str(s),points,.047,'Vine',6)
        for k in [3,9,15]: leaf('Arm leaf'+str(s)+str(k),points[k],.15)
    # Ribbed faceted pumpkin shell and true geometric cuts.
    seg=80;rings=24;vs=[]
    for k in range(rings+1):
        t=math.pi*k/rings
        for j in range(seg):
            a=j*math.pi*2/seg
            r=1.08*math.sin(t)*(1+.075*math.cos(10*a))
            vs.append((r*math.cos(a),r*.88*math.sin(a),3.14+.98*math.cos(t)))
    fs=[]
    for k in range(rings):
        for j in range(seg):fs.append((k*seg+j,k*seg+(j+1)%seg,(k+1)*seg+(j+1)%seg,(k+1)*seg+j))
    head=mesh('Carved ten-lobed pumpkin',vs,fs,'Orange')
    # Collapse the repeated latitude-ring poles before exact solid booleans.
    bm=bmesh.new();bm.from_mesh(head.data)
    bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.00001)
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
    assert all(e.is_manifold for e in bm.edges), 'Pumpkin shell must be closed'
    bm.to_mesh(head.data);bm.free();head.data.update()
    cuts=[('Left eye',[(-.76,3.48),(-.18,3.23),(-.49,3.10),(-.72,3.15)]),('Right eye',[(.76,3.48),(.18,3.23),(.49,3.10),(.72,3.15)]),('Nose',[(-.10,3.06),(.03,3.21),(.14,3.04)]),('Jagged grin',[(-.82,2.97),(-.57,2.83),(-.43,2.93),(-.27,2.75),(-.12,2.84),(.06,2.69),(.23,2.81),(.38,2.73),(.54,2.9),(.73,2.85),(.85,3.02),(.71,2.61),(.55,2.67),(.38,2.52),(.20,2.61),(.02,2.49),(-.15,2.59),(-.33,2.55),(-.50,2.68),(-.64,2.64)])]
    for name,outline in cuts:
        cutter=poly('Temporary cutter',outline,-1.45,1.10,'Void')
        # Derive a closed luminous plug from the ACTUAL ribbed head surface.
        # A guessed sphere or a nonplanar ngon can cross the orange skin and
        # leave fragmented eyes. The exact intersection retains every facet.
        liner=link(bpy.data.objects.new(name+' recessed glowing liner',head.data.copy()),name+' recessed glowing liner')
        bpy.context.view_layer.objects.active=liner
        mod=liner.modifiers.new('Surface matched luminous insert','BOOLEAN');mod.operation='INTERSECT';mod.solver='EXACT';mod.object=cutter
        bpy.ops.object.modifier_apply(modifier=mod.name)
        liner.data.materials.clear();liner.data.materials.append(M['Amber'])
        for p in liner.data.polygons:p.material_index=0
        liner.location.y=.035
        bpy.context.view_layer.objects.active=head
        mod=head.modifiers.new(name+' carved opening','BOOLEAN');mod.operation='DIFFERENCE';mod.solver='EXACT';mod.object=cutter
        bpy.ops.object.modifier_apply(modifier=mod.name)
        bpy.data.objects.remove(cutter,do_unlink=True)
    tube('Pumpkin woody stem',[(0,0,4.02),(.08,.03,4.25),(-.04,.05,4.43)],[.18,.15,.08],'Wood',8)
    # Open crown wall alternating high points.
    n=12;vs=[]
    for k in range(4):
        for j in range(n):
            a=2*math.pi*j/n;r=.57 if k<2 else .50
            z=4.00 if k%2==0 else 4.18+( .46 if j%2==0 else .02)
            vs.append((r*math.cos(a),r*math.sin(a),z))
    fs=[]
    for j in range(n):
        q=(j+1)%n
        fs += [(j,q,n+q,n+j),(n+j,n+q,3*n+q,3*n+j),(2*n+j,3*n+j,3*n+q,2*n+q)]
    mesh('Six point gold crown',vs,fs,'Gold',['Bronze'])
    for j in range(6):
        a=2*math.pi*j/6
        diamond('Crown gem'+str(j),(.59*math.cos(a),.59*math.sin(a),4.23),.07,.13,'Amber')
    for s in [-1,1]:
        tube('Purple folded collar'+str(s),[(0,-.47,2.43),(s*.52,-.40,2.52),(s*.94,.03,2.4)],[.15,.23,.10],'Violet',7)
        tube('Neck vine'+str(s),[(s*.2,-.50,2.37),(s*.68,-.45,2.20),(s*.83,-.30,2.38)],[.05,.055,.015],'Vine',6)
        leaf('Collar leaf'+str(s),(s*.78,-.34,2.33),.18)
    diamond('Royal clasp',(0,-.68,2.35),.21,.25,'Gold')
    diamond('Royal clasp center',(0,-.81,2.35),.13,.16,'Amber')
    tube('Crown vine',[(-.8,-.28,4.03),(-.32,-.60,4.1),(.27,-.57,4.04),(.7,-.25,4.01),(.92,.03,3.85)],[.055]*5,'Vine',6)
    leaf('Crown leaf',(.68,-.25,4.02),.22)

def wing(name,s):
    # A hand-cut membrane with five scallops, faceted between articulated wing bones.
    root=(s*.58,.16,1.91)
    outline=[(s*.74,.05,2.42),(s*1.35,.1,2.68),(s*2.03,.10,3.03),(s*2.21,.09,2.27),(s*1.98,.04,2.36),(s*1.87,.02,1.95),(s*1.58,-.02,2.02),(s*1.43,-.03,1.56),(s*1.18,-.04,1.69),(s*.99,-.04,1.22),(s*.77,0,1.48)]
    vs=[root]+outline
    fs=[(0,i,i+1) for i in range(1,len(vs)-1)]+[(0,len(vs)-1,1)]
    ob=mesh(name+' membrane',vs,fs,'Magenta',['Red'])
    sol=ob.modifiers.new('Wing membrane thickness','SOLIDIFY');sol.thickness=.055
    bpy.context.view_layer.objects.active=ob;bpy.ops.object.modifier_apply(modifier=sol.name)
    tube(name+' leading arm',[root,outline[1],outline[2]],[.13,.10,.025],'Indigo',7)
    for j in [4,6,8,10]: tube(name+' finger vein'+str(j),[root,outline[j]],[.065,.02],'IndigoLight',6)
    tube(name+' outer edge',outline+[outline[0]],.035,'Indigo',6)
    for j in range(3):
        p=(s*(1.25+j*.12),.04,2.72+j*.04)
        tube(name+' pale claw'+str(j),[p,(p[0]+s*.07,-.04,p[2]-.23)],[.075,.006],'Ivory',6)

def bat():
    start('CountFang')
    uv('Bat pear body',(0,.08,1.48),(.58,.36,.79),'Indigo',16,9)
    for s in [-1,1]:
        wing('Bat wing'+str(s),s)
        tube('Hind leg'+str(s),[(s*.31,.07,1.04),(s*.40,-.03,.50),(s*.47,-.18,.27)],[.23,.18,.21],'Indigo',8)
        ico('Bat foot'+str(s),(s*.48,-.20,.20),(.32,.35,.18),'IndigoLight',1)
        for j in range(3):tube('Bat toe claw'+str(s)+str(j),[(s*.48+(j-1)*.17,-.40,.18),(s*.48+(j-1)*.17,-.64,.05)],[.085,.003],'Ivory',6)
    ico('Angular bat head',(0,-.05,2.58),(.73,.52,.68),'IndigoLight',2)
    for s in [-1,1]:
        ear=[(s*.33,3.0),(s*.42,3.62),(s*.99,4.13),(s*.91,3.45),(s*.71,2.91)]
        poly('Enormous bat ear'+str(s),ear,.02,.21,'Indigo',.035)
        inner=[(s*.47,3.12),(s*.53,3.58),(s*.90,3.94),(s*.80,3.42),(s*.66,3.10)]
        poly('Magenta inner ear'+str(s),inner,-.025,.035,'Magenta')
        eye('Vampire eye'+str(s),s*.33,2.65,-.51,'Amber',.29,-s)
        poly('Cheek fur'+str(s),[(s*.42,2.50),(s*.93,2.5),(s*.70,2.35),(s*.87,2.24),(s*.53,2.23),(s*.28,2.30)],-.35,.20,'Indigo')
        tube('Eyebrow'+str(s),[(s*.12,-.54,2.89),(s*.42,-.54,3.02),(s*.65,-.44,2.89)],[.08,.12,.015],'Indigo',6)
    ico('Bat muzzle',(0,-.48,2.29),(.36,.23,.24),'Indigo',1)
    ico('Bat nose',(0,-.68,2.49),(.16,.11,.105),'BlackFur',1)
    poly('Open smile',[(-.32,2.36),(0,2.25),(.32,2.36),(.20,2.12),(0,2.05),(-.20,2.12)],-.68,.06,'Void')
    poly('Little tongue',[(-.09,2.13),(.09,2.13),(.07,2.06),(-.07,2.06)],-.75,.02,'Magenta')
    for s in [-1,1]:tube('Vampire fang'+str(s),[(s*.21,-.73,2.33),(s*.18,-.76,2.12)],[.09,.003],'Ivory',7)
    for s in [-1,1]:
        poly('High red collar'+str(s),[(0,2.05),(s*.42,2.3),(s*.83,2.22),(s*.54,1.83),(s*.19,1.89)],-.05,.14,'Red')
        poly('Front collar point'+str(s),[(0,1.94),(s*.57,2.10),(s*.40,1.71)],-.44,.05,'Magenta')
    diamond('Ruby gold setting',(0,-.55,1.86),.23,.26,'Gold')
    diamond('Vampire ruby',(0,-.69,1.86),.14,.18,'Ruby')
    for i in range(10):
        x=(i%5-2)*.18;z=1.14+(i//5)*.35
        tube('Chest fur tuft'+str(i),[(x,-.28,z+.28),(x*.9,-.41,z)],[.16,.005],'IndigoLight',5)
    tube('Bat tail',[(0,.34,.98),(0,.55,.70),(.18,.65,.84)],[.1,.065,.005],'Indigo',7)

def cat():
    start('HexCat')
    uv('Cat torso',(0,.19,.99),(.59,.79,.55),'BlackFur',16,8)
    for s in [-1,1]:
        for back in [False,True]:
            x=s*(.39 if back else .37);y=.62 if back else -.36
            tube(('Hind' if back else 'Fore')+' leg'+str(s),[(x,y,1.0),(x,y-.03,.34)],[.22,.17],'Indigo',8)
            uv('Cat paw'+str(s)+str(back),(x,y-.10,.18),(.26,.30,.17),'BlackFur',12,6)
            for j in range(3):tube('Paw crease'+str(s)+str(back)+str(j),[(x+(j-1)*.11,y-.355,.10),(x+(j-1)*.11,y-.355,.23)],.012,'IndigoLight',4)
    ico('Witch cat head',(0,-.40,1.77),(.71,.52,.62),'Indigo',2)
    for s in [-1,1]:
        poly('Cat pointed ear'+str(s),[(s*.31,2.09),(s*.66,2.77),(s*.81,2.15)],-.22,.24,'BlackFur')
        poly('Cat inner ear'+str(s),[(s*.44,2.18),(s*.64,2.59),(s*.72,2.2)],-.255,.025,'Magenta')
        eye('Emerald cat eye'+str(s),s*.32,1.84,-.84,'Lime',.29,-s)
        poly('Vertical pupil'+str(s),[(s*.32-.028,2.01),(s*.32+.028,2.01),(s*.32+.018,1.67),(s*.32-.018,1.67)],-.906,.008,'Void')
        ico('Cat muzzle'+str(s),(s*.16,-.84,1.52),(.22,.12,.15),'IndigoLight',1)
        for j in range(3):
            tube('Whisker'+str(s)+str(j),[(s*.25,-.935,1.54-j*.035),(s*(.68+.1*j),-.96,1.63-j*.13)],[.013,.003],'Bone',4)
    ico('Cat nose',(0,-.98,1.63),(.105,.065,.07),'BlackFur',1)
    tube('Mouth left',[(0,-.98,1.59),(-.06,-.96,1.48),(-.16,-.94,1.47)],.015,'Void',4)
    tube('Mouth right',[(0,-.98,1.59),(.06,-.96,1.48),(.16,-.94,1.47)],.015,'Void',4)
    # Forehead gold crescent crescent made of a single thin mesh.
    cres=[(-.10,2.06),(-.18,2.13),(-.18,2.24),(-.12,2.31),(-.14,2.18),(-.08,2.11),(.02,2.10),(.10,2.15),(.07,2.07),(-.01,2.03)]
    poly('Forehead crescent',cres,-.855,.022,'Gold')
    cape('Witch shoulder mantle',.71,1.53,.63,.21)
    for s in [-1,1]:poly('Witch front collar'+str(s),[(0,1.44),(s*.62,1.50),(s*.48,1.14),(s*.22,1.24)],-.55,.06,'Purple')
    diamond('Cat gold clasp',(0,-.64,1.29),.17,.20,'Gold');diamond('Cat clasp gem',(0,-.77,1.29),.10,.12,'OrangeLight')
    # Wide slanted brim and a deliberately crooked cone, both editable polygon meshes.
    seg=32;vs=[]
    for k,r in enumerate([.39,1.05]):
        for j in range(seg):
            a=j*math.pi*2/seg
            vs.append((r*math.cos(a),-.28+r*.76*math.sin(a),2.40+.20*math.cos(a)+(.07*math.sin(3*a) if k else 0)))
    fs=[(j,(j+1)%seg,seg+(j+1)%seg,seg+j) for j in range(seg)]
    ob=mesh('Wide crooked hat brim',vs,fs,'Violet',['Purple'])
    sol=ob.modifiers.new('Thick hat brim','SOLIDIFY');sol.thickness=.09;bpy.context.view_layer.objects.active=ob;bpy.ops.object.modifier_apply(modifier=sol.name)
    tube('Bent witch hat cone',[(0,-.28,2.45),(-.08,-.25,2.80),(-.18,-.23,3.14),(-.40,-.25,3.45),(-.69,-.27,3.56),(-.91,-.28,3.42),(-.88,-.28,3.20)],[.50,.43,.33,.25,.19,.11,.005],'Purple',10)
    tube('Leather hat band',[(0,-.28,2.48),(-.04,-.26,2.7)],[.505,.465],'WoodDark',12)
    for xx,zz,sx,sz in [(0,2.63,.23,.035),(0,2.43,.23,.035),(-.20,2.53,.035,.12),(.20,2.53,.035,.12)]:
        cube('Gold hat buckle',(xx,-.745,zz),(sx,.045,sz),'Gold',.012)
    tube('Cat curled tail',[(0,.82,1.1),(.31,1.07,1.38),(.74,1.10,1.53),(1.02,1.01,1.76),(1.02,.86,2.02),(.83,.76,2.14),(.65,.74,2.00)],[.18,.18,.17,.16,.14,.11,.03],'Indigo',8)
    tube('Potion hanging loop',[(-.93,-.23,2.44),(-1.07,-.23,2.27),(-1.07,-.23,2.09)],[.038,.04,.038],'Gold',6)
    uv('Orange potion flask',(-1.08,-.23,1.74),(.27,.25,.33),'OrangeLight',16,8)
    tube('Potion bottle neck',[(-1.08,-.23,1.98),(-1.08,-.23,2.10)],[.105,.10],'Gold',10)
    cube('Potion cork',(-1.08,-.23,2.13),(.09,.08,.07),'WoodLight',.02)
    for j,p in enumerate([(-1.17,-.46,1.85),(-.99,-.45,1.68),(-1.17,-.45,1.61)]):ico('Potion magic bubble'+str(j),p,(.04,.02,.04),'Amber',1)
    tube('Potion highlight',[(-1.2,-.435,1.77),(-1.21,-.425,1.9)],[.025,.01],'Ivory',5)

def wrap(name,pos,scale,count,axis='Z',profile=None):
    # Every wrap is a separate thick cloth ribbon with a staggered diagonal seam.
    x,y,z=pos;rx,ry,rz=scale;n=16
    if profile is None:
        uv(name+' closed rounded form',pos,(rx*.995,ry*.995,rz*1.07),'BandageLight',16,10)
    for k in range(count):
        t=(k+.5)/count
        zz=z-rz+2*rz*t
        a0=(k%2)*.22
        vs=[]
        for side in [0,1]:
            for j in range(n):
                a=2*math.pi*j/n
                wave=.065*math.sin(a+a0)
                vertex_z=zz+(side-.5)*2*rz/count*1.16+wave
                center_z,vertical_radius=profile if profile else (z,rz*1.07)
                factor=math.sqrt(max(.012,1-((vertex_z-center_z)/vertical_radius)**2))
                vs.append((x+rx*factor*math.cos(a),y+ry*factor*math.sin(a),vertex_z))
        fs=[(j,(j+1)%n,n+(j+1)%n,n+j) for j in range(n)]
        ob=mesh(name+' wrap '+str(k),vs,fs,'BandageLight' if k%3 else 'Bandage')
        mod=ob.modifiers.new('Bandage thickness','SOLIDIFY');mod.thickness=.045;bpy.context.view_layer.objects.active=ob;bpy.ops.object.modifier_apply(modifier=mod.name)

def mummy():
    start('CryptMummy')
    uv('Mummy dark underbody',(0,.02,1.50),(.66,.40,.72),'BandageDark',14,8)
    wrap('Torso',(0,.02,1.49),(.65,.42,.66),8)
    uv('Mummy head base',(0,-.01,2.76),(.63,.50,.70),'BandageDark',16,10)
    uv('Face shadow',(0,-.405,2.76),(.55,.18,.30),'Void',12,6)
    for s in [-1,1]:eye('Mummy eye'+str(s),s*.27,2.77,-.57,'Cyan',.235,-s)
    wrap('Head upper',(0,-.01,3.13),(.66,.53,.30),4,profile=(2.76,.74))
    wrap('Head lower',(0,-.025,2.40),(.66,.53,.22),3,profile=(2.76,.74))
    ribbon('Crown crossing bandage east west',[(-.60,-.02,3.06),(-.43,-.02,3.34),(0,-.02,3.50),(.43,-.02,3.34),(.60,-.02,3.06)],.25,'BandageLight')
    ribbon('Crown crossing bandage north south',[(-.1,-.48,3.07),(-.1,-.34,3.36),(-.1,0,3.52),(-.1,.34,3.36),(-.1,.48,3.07)],.26,'Bandage')
    # Broad forehead crossing strip; cloth tails are thin closed prisms.
    poly('Diagonal forehead bandage',[(-.59,3.20),(.51,3.46),(.61,3.29),(-.57,3.02)],-.43,.07,'BandageLight')
    for s in [-1,1]:
        shoulder=(s*.68,0,1.96)
        uv('Mummy shoulder'+str(s),shoulder,(.36,.36,.36),'Bandage',12,6)
        tube('Mummy upper arm'+str(s),[shoulder,(s*.94,-.07,1.56)],[.29,.27],'BandageDark',8)
        wrap('Upper arm'+str(s),(s*.82,-.04,1.77),(.31,.31,.33),4)
        wrap('Forearm'+str(s),(s*1.03,-.20,1.37),(.28,.29,.32),4)
        ico('Mummy fist'+str(s),(s*1.06,-.33,1.10),(.30,.27,.28),'BandageLight',1)
        for j in range(3):
            cube('Wrapped knuckle'+str(s)+str(j),(s*1.06+(j-1)*.13,-.56,1.13),(.075,.10,.12),'Ivory',.035)
        ico('Thumb'+str(s),(s*.85,-.38,1.14),(.13,.16,.19),'Bandage',1)
        wrap('Leg'+str(s),(s*.38,.03,.60),(.30,.31,.51),6)
        uv('Mummy foot'+str(s),(s*.40,-.17,.16),(.35,.45,.17),'BandageLight',12,6)
        for j in range(3):cube('Toe band'+str(s)+str(j),(s*.4+(j-1)*.17,-.48,.15),(.06,.13,.13),'Bandage',.025)
        poly('Loose shoulder ribbon'+str(s),[(s*.65,2.12),(s*.91,2.18),(s*1.23,1.91),(s*1.29,1.51),(s*1.39,1.40),(s*1.18,1.48),(s*1.10,1.85)],.02,.045,'BandageLight')
    # Egyptian segmented bronze gorget follows the neck in a broad fan.
    for j in range(13):
        a=math.pi*(j/12)
        x=.65*math.cos(a);z=2.23-.36*math.sin(a)
        ob=cube('Bronze collar plate'+str(j),(x,-.43,z),(.095,.055,.23),'Bronze',.025)
        ob.rotation_euler[1]=-(a-math.pi/2)*.65
    tube('Collar gold rim',[(-.65,-.43,2.22),(-.46,-.49,1.96),(0,-.5,1.84),(.46,-.49,1.96),(.65,-.43,2.22)],.04,'Gold',6)
    uv('Purple scarab body',(0,-.60,1.94),(.16,.11,.23),'Scarab',12,6)
    uv('Purple scarab head',(0,-.60,2.16),(.10,.085,.10),'PurpleLight',10,5)
    for s in [-1,1]:
        tube('Scarab wing edge'+str(s),[(0,-.63,2.12),(s*.17,-.65,2.02),(s*.13,-.65,1.79)],[.022,.03,.015],'Gold',5)
        for j in range(3):tube('Scarab leg'+str(s)+str(j),[(s*.12,-.61,2.02-j*.09),(s*.24,-.59,2.07-j*.12)],[.025,.014],'Gold',5)
    tube('Purple waist belt',[(-.58,-.35,1.24),(0,-.46,1.16),(.58,-.35,1.24)],.07,'Violet',7)
    poly('Purple linen sash',[(-.14,1.2),(.16,1.2),(.22,.50),(.06,.63),(-.06,.47),(-.19,.55)],-.46,.05,'Violet')
    diamond('Sash gold charm',(0,-.57,.99),.14,.20,'Gold')
    poly('Loose back head ribbon',[(-.40,3.26),(-.73,3.37),(-.96,3.09),(-.91,2.77),(-1.04,2.62),(-.82,2.72),(-.78,3.04),(-.60,3.14)],.21,.05,'BandageLight')
    poly('Loose back waist ribbon',[(.28,1.25),(.54,1.28),(.75,.95),(.63,.61),(.77,.48),(.57,.53),(.53,.90)],.34,.05,'Bandage')

def crack(name,points,glow=True):
    tube(name+' dark fissure',points,.048,'StoneDark',5)
    if glow:
        p=[(x,y-.018,z) for x,y,z in points]
        tube(name+' luminous seam',p,.018,'Mint',5)

def mushroom(name,pos,size):
    x,y,z=pos
    tube(name+' stalk',[(x,y,z),(x+.03,y,z+size*.55)],[size*.12,size*.10],'Pearl',6)
    n=10;vs=[(x+.03,y,z+size)]
    for rr,zz in [(size*.43,z+size*.63),(size*.48,z+size*.58)]:
        for j in range(n):
            a=2*math.pi*j/n;vs.append((x+.03+rr*math.cos(a),y+rr*math.sin(a),zz))
    fs=[(0,j+1,(j+1)%n+1) for j in range(n)]
    fs += [(j+1,(j+1)%n+1,n+(j+1)%n+1,n+j+1) for j in range(n)]
    fs.append(tuple(range(n+1,2*n+1)))
    mesh(name+' pointed cap',vs,fs,'PurpleLight',['Purple'])
    for j in range(3):
        a=j*math.pi*2/3;ico(name+' cap dot'+str(j),(x+.03+size*.23*math.cos(a),y+size*.23*math.sin(a),z+size*.80),(size*.07,size*.07,size*.035),'PearlLight',1)

def golem():
    start('GraveGolem')
    for s in [-1,1]:
        cube('Monolith foot'+str(s),(s*.62,-.15,.22),(.47,.57,.23),'Stone',.14)
        ico('Stone shin'+str(s),(s*.60,.02,.68),(.43,.41,.50),'StoneLight',1)
        ico('Boulder thigh'+str(s),(s*.47,.06,1.23),(.46,.43,.43),'Stone',1)
        for j in range(3):
            ob=cube('Foot slab toe'+str(s)+str(j),(s*.62+(j-1)*.27,-.62,.17),(.13,.15,.17),'StoneLight',.055)
    outline=[(-.88,1.28),(-1.01,2.67),(-.78,3.0),(-.63,3.17),(.63,3.17),(.92,2.95),(1.01,2.67),(.88,1.28)]
    poly('Ancient tombstone torso',outline,-.38,.84,'Stone',.09)
    # Embedded top stone with a recognizable grave silhouette.
    head=[(-.51,3.00),(-.51,3.66),(-.29,3.91),(.29,3.91),(.51,3.66),(.51,3.00)]
    poly('Raised gravestone crown',head,-.03,.55,'StoneLight',.065)
    poly('Gravestone inset',[(-.37,3.29),(-.37,3.62),(-.20,3.77),(.20,3.77),(.37,3.62),(.37,3.29)],-.101,.02,'Stone')
    # Heavy brow plates above cyan eyes.
    for s in [-1,1]:
        poly('Golem eye recess'+str(s),[(s*.13,2.88),(s*.73,2.97),(s*.63,2.64),(s*.20,2.61)],-.48,.05,'StoneDark')
        poly('Golem mint eye'+str(s),[(s*.21,2.79),(s*.62,2.88),(s*.52,2.68),(s*.23,2.67)],-.55,.02,'Mint')
        poly('Boulder eyebrow'+str(s),[(s*.08,3.08),(s*.57,3.19),(s*.85,3.02),(s*.73,2.9),(s*.18,2.88)],-.58,.19,'StoneLight',.025)
        shoulder=(s*1.02,.03,2.65);elbow=(s*1.35,-.01,1.96);wrist=(s*1.44,-.21,1.24)
        ico('Huge shoulder boulder'+str(s),shoulder,(.56,.47,.60),'Stone',1)
        ico('Upper arm stone'+str(s),(s*1.25,.02,2.23),(.43,.42,.50),'StoneLight',1)
        ico('Elbow core'+str(s),elbow,(.28,.28,.28),'StoneDark',1)
        ico('Forearm stone'+str(s),(s*1.40,-.10,1.62),(.45,.43,.52),'Stone',1)
        ico('Boulder fist'+str(s),wrist,(.48,.42,.39),'StoneLight',1)
        for j in range(3):cube('Rock knuckle'+str(s)+str(j),(s*1.44+(j-1)*.22,-.53,1.26),(.12,.11,.20),'Stone',.065)
        crack('Arm crack'+str(s),[(s*1.2,-.35,2.91),(s*1.08,-.43,2.65),(s*1.27,-.45,2.48),(s*1.19,-.40,2.26)])
        crack('Leg crack'+str(s),[(s*.72,-.28,1.03),(s*.57,-.38,.81),(s*.68,-.39,.55),(s*.53,-.38,.40)])
        for i in range(7):
            x=s*(.71+i*.10);y=.04+random.uniform(-.3,.3);z=3.05-random.uniform(0,.20)
            ico('Shoulder moss'+str(s)+str(i),(x,y,z),(.22,.20,.10),'MossLight' if i%3 else 'Moss',1)
        for i in range(4):
            tube('Hanging moss root'+str(s)+str(i),[(s*(.88+i*.11),-.32,2.99),(s*(.90+i*.11),-.38,2.66),(s*(.83+i*.11),-.35,2.46)],[.06,.045,.002],'Moss',5)
        mushroom('Shoulder mushroom'+str(s),(s*1.18,.08,3.03),.48)
        mushroom('Shoulder small mushroom'+str(s),(s*.83,.23,3.08),.30)
        for i in range(3):ico('Foot moss'+str(s)+str(i),(s*.63+(i-1)*.18,.08,.88),(.17,.16,.09),'Moss',1)
    # Skull relief at center reads as carved stone rather than a decal.
    ico('Chest skull relief',(0,-.52,2.18),(.37,.17,.43),'StoneLight',1)
    for s in [-1,1]:
        poly('Relief skull eye'+str(s),[(s*.07,2.26),(s*.25,2.29),(s*.24,2.11),(s*.10,2.12)],-.68,.025,'StoneDark')
    poly('Relief nose',[(-.06,2.06),(0,2.16),(.06,2.06)],-.70,.015,'StoneDark')
    for i in range(4):cube('Relief skull tooth'+str(i),((i-1.5)*.10,-.64,1.89),(.04,.045,.11),'StoneLight',.015)
    crack('Chest lower rune',[(-.52,-.475,1.88),(-.40,-.49,1.65),(-.08,-.49,1.54),(.16,-.49,1.70),(.43,-.49,1.64),(.64,-.49,1.94)])
    crack('Grave crown crack',[(-.20,-.12,3.70),(-.06,-.12,3.52),(-.13,-.12,3.37),(.08,-.12,3.22)],False)
    crack('Back stone crack',[(-.51,.48,2.88),(-.23,.49,2.55),(-.34,.49,2.30),(0,.49,2.12),(.17,.49,1.80)],False)
    for s in [-1,1]:ico('Back moss'+str(s),(s*.58,.49,2.65),(.35,.08,.30),'Moss',1)
    tube('Waist iron chain',[(-.72,-.38,1.51),(-.38,-.53,1.43),(0,-.55,1.48),(.38,-.53,1.43),(.72,-.38,1.51)],.07,'StoneDark',6)

def reaper():
    start('WraithReaper')
    # Hollow hood with angular thick rim and recessed face.
    outer=[(-.72,2.45),(-.83,3.0),(-.51,3.56),(-.22,3.98),(.28,3.89),(.68,3.52),(.78,2.92),(.49,2.45),(0,2.29)]
    inner=[(-.51,2.57),(-.58,3.0),(-.35,3.40),(-.13,3.65),(.20,3.58),(.47,3.33),(.54,2.94),(.35,2.59),(0,2.49)]
    n=len(outer);vs=[(x,-.48,z) for x,z in outer]+[(x,-.55,z) for x,z in inner]+[(x*.66,.37,3.13+(z-3.13)*.78) for x,z in outer]
    fs=[]
    for j in range(n):
        q=(j+1)%n
        fs += [(j,q,n+q,n+j),(j,2*n+j,2*n+q,q)]
    fs.append(tuple(2*n+j for j in range(n)))
    mesh('Deep faceted open hood',vs,fs,'Violet',['Purple','PurpleLight'])
    poly('Recessed featureless face',inner,-.34,.10,'Void')
    for s in [-1,1]:
        poly('Wraith cyan eye'+str(s),[(s*.12,3.10),(s*.34,3.23),(s*.32,2.98),(s*.22,2.90)],-.475,.015,'Cyan')
    # Draped robe with independent tapered hem wisps.
    seg=20;vs=[]
    for k,(z,r) in enumerate([(.48,.66),(1.18,.70),(1.89,.55),(2.47,.42)]):
        for j in range(seg):
            a=j*math.pi*2/seg
            vs.append((r*math.cos(a),r*.67*math.sin(a),z+(.18*(j%2) if k==0 else .05*math.cos(3*a))))
    fs=[]
    for k in range(3):
        for j in range(seg):
            a=k*seg+j;b=k*seg+(j+1)%seg;c=(k+1)*seg+(j+1)%seg;d=(k+1)*seg+j
            fs.extend([(a,b,c),(a,c,d)])
    fs.append(tuple(3*seg+j for j in range(seg)))
    ob=mesh('Spectral draped robe',vs,fs,'Violet',['Purple','PurpleLight'])
    sol=ob.modifiers.new('Robe cloth thickness','SOLIDIFY');sol.thickness=.045;bpy.context.view_layer.objects.active=ob;bpy.ops.object.modifier_apply(modifier=sol.name)
    for j in range(9):
        a=2*math.pi*j/9; x=.57*math.cos(a);y=.40*math.sin(a)
        tube('Ragged robe wisp'+str(j),[(x,y,1.20),(x*1.28,y*1.28,.65),(x*1.36+.13,y*1.36,.34),(x*1.17+.25,y*1.17,.10),(x+.30,y,.25)],[.23,.20,.13,.07,.003],'PurpleLight' if j%3==0 else 'Violet',6)
        if j%2==0:
            tube('Cyan spectral hem'+str(j),[(x*1.18,y*1.18,.61),(x*1.36+.13,y*1.36,.32),(x*1.17+.25,y*1.17,.10),(x+.30,y,.25)],[.055,.05,.033,.002],'Cyan',5)
    cape('Ragged shoulder shawl',.94,2.57,1.40,.25)
    for s in [-1,1]:
        poly('Folded front mantle'+str(s),[(0,2.50),(s*.77,2.72),(s*.94,2.42),(s*.60,2.05),(s*.32,2.27)],-.34,.10,'Purple')
        elbow=(s*.90,-.01,1.90 if s<0 else 2.26)
        wrist=(s*1.10,-.38,2.18 if s<0 else 2.56)
        tube('Sleeve'+str(s),[(s*.59,.03,2.46),elbow,wrist],[.29,.30,.24],'Violet',7)
        ico('Bone palm'+str(s),(wrist[0],wrist[1]-.08,wrist[2]),(.21,.13,.21),'Bone',1)
        for j in range(3):
            a=(wrist[0]+(j-1)*.14,wrist[1]-.17,wrist[2]-.04)
            b=(a[0],a[1]-.13,a[2]-.18)
            c=(a[0]+s*.02,a[1]-.16,a[2]-.28)
            bone('Wraith finger'+str(s)+str(j),a,b,.06);bone('Wraith fingertip'+str(s)+str(j),b,c,.052)
        bone('Wraith thumb'+str(s),(wrist[0]-s*.17,wrist[1],wrist[2]+.02),(wrist[0]-s*.26,wrist[1]-.2,wrist[2]-.09),.075)
    # Chain is geometry, with interleaved open torus links.
    for j in range(9):
        x=-.55+j*.1375;z=1.87-.10*(1-(x/.55)**2)
        bpy.ops.mesh.primitive_torus_add(major_segments=10,minor_segments=4,location=(x,-.48,z),major_radius=.095,minor_radius=.022,rotation=(math.pi/2,0,(j%2)*math.pi/3))
        link(bpy.context.object,'Iron chain link '+str(j),'StoneDark')
    diamond('Dangling gold amulet',(.10,-.54,1.49),.12,.24,'Gold');diamond('Amulet violet center',(.10,-.67,1.49),.063,.14,'Scarab')
    # Scythe is held beside the figure and has a crescent cut silhouette.
    handle=[(1.30,-.22,.30),(1.36,-.20,1.42),(1.36,-.20,2.56),(1.43,-.19,3.58),(1.33,-.18,4.47)]
    tube('Gnarled scythe shaft',handle,[.085,.09,.09,.11,.13],'WoodDark',8)
    for j in range(6):
        z=2.40+j*.11;tube('Scythe hand wrap'+str(j),[(1.36,-.20,z),(1.36,-.20,z+.045)],[.115,.115],'Violet',8)
    blade=[(1.43,4.44),(1.18,4.83),(.67,5.02),(.10,5.00),(-.46,4.74),(-.95,4.30),(-1.20,3.92),(-.70,4.22),(-.20,4.42),(.27,4.45),(.66,4.32),(1.02,4.04),(1.27,4.02)]
    poly('Great crescent scythe blade',blade,-.20,.16,'Indigo',.025)
    edge=[(1.20,4.70),(.66,4.90),(.13,4.90),(-.40,4.66),(-.90,4.25),(-1.20,3.92),(-.70,4.22),(-.20,4.42),(.27,4.45),(.66,4.32),(1.02,4.04),(.99,4.31)]
    poly('Cyan scythe cutting edge',edge,-.24,.04,'Cyan')
    for j,(x,z) in enumerate([(.55,4.61),(.10,4.68),(-.36,4.49)]):diamond('Blade facet'+str(j),(x,-.30,z),.15,.12,'PearlLight')
    diamond('Scythe socket',(1.31,-.30,4.35),.20,.27,'Violet')
    diamond('Scythe socket gem',(1.31,-.43,4.35),.09,.15,'Cyan')
    tube('Left floating soul curl',[(-.62,.28,2.41),(-1.0,.31,2.72),(-1.11,.30,3.07),(-.97,.28,3.29),(-1.02,.27,3.42)],[.14,.14,.10,.05,.002],'PurpleLight',7)

BUILDERS=[ghost,imp,pumpkin,bat,cat,mummy,golem,reaper]
for builder,model_name in zip(BUILDERS,['GhostSlime','SkeletonImp','PumpkinKing','CountFang','HexCat','CryptMummy','GraveGolem','WraithReaper']):
    if PATCH_MODELS and model_name not in ONLY:continue
    print('BUILDING',builder.__name__,flush=True)
    builder()
    print('BUILT',builder.__name__,flush=True)

def bounds(objects):
    corners=[o.matrix_world@Vector(c) for o in objects if o.type=='MESH' for c in o.bound_box]
    lo=Vector(tuple(min(v[i] for v in corners) for i in range(3)))
    hi=Vector(tuple(max(v[i] for v in corners) for i in range(3)))
    return lo,hi

# Model origins are a common ground-level world origin. All transforms are baked.
manifest={'title':'Halloween Collection','version':1,'static':True,'rigged':False,
    'coordinate_system':'Blender Z-up; front is -Y; origins centered at ground',
    'material_workflow':'Flat PBR vertex geometry with solid-color materials and emissive eyes',
    'models':[]}
for name,col in MODELS.items():
    objects=[o for o in col.objects if o.type=='MESH']
    bpy.ops.object.select_all(action='DESELECT')
    for o in objects:o.select_set(True)
    bpy.context.view_layer.objects.active=objects[0]
    bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
    bpy.context.view_layer.update()
    lo,hi=bounds(objects)
    # Keep the lowest geometric point on z=0, including the spirit's hanging wisps.
    dz=-lo.z
    for o in objects:
        o.location.z+=dz
    bpy.context.view_layer.update()
    for o in objects:
        bpy.context.scene.cursor.location=(0,0,0)
    bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
    lo,hi=bounds(objects)
    tris=0
    for o in objects:
        o.data.calc_loop_triangles();tris+=len(o.data.loop_triangles)
    manifest['models'].append({'name':name,'components':len(objects),'triangles':tris,
        'vertices':sum(len(o.data.vertices) for o in objects),
        'dimensions':[round(v,4) for v in hi-lo],
        'bounds_min':[round(v,4) for v in lo],'bounds_max':[round(v,4) for v in hi],
        'files':[name+'.blend',name+'.glb',name+'.fbx',name+'_Front.png',name+'_Back.png']})
    # Standard scene save: Blender 5.2 partial-library Scene writer has a native
    # view-layer crash. Temporarily unlink the other character collections so
    # opening this .blend immediately shows only the selected editable model.
    for other_name,other_col in MODELS.items():
        if other_name != name: bpy.context.scene.collection.children.unlink(other_col)
    for screen in bpy.data.screens:
        for area in screen.areas:
            if area.type=='VIEW_3D':
                area.spaces.active.region_3d.view_location=(lo+hi)*.5
                area.spaces.active.region_3d.view_distance=max(hi-lo)*1.8
                area.spaces.active.region_3d.view_rotation=Vector((.46,-1,.35)).to_track_quat('Z','Y')
                area.spaces.active.shading.type='MATERIAL'
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/(name+'.blend')),copy=True)
    for other_name,other_col in MODELS.items():
        if other_name != name: bpy.context.scene.collection.children.link(other_col)
    bpy.ops.object.select_all(action='DESELECT')
    for o in objects:o.select_set(True)
    bpy.context.view_layer.objects.active=objects[0]
    bpy.ops.export_scene.gltf(filepath=str(OUT/(name+'.glb')),export_format='GLB',use_selection=True,export_yup=True,export_apply=True)
    bpy.ops.export_scene.fbx(filepath=str(OUT/(name+'.fbx')),use_selection=True,object_types={'MESH'},apply_unit_scale=True,axis_forward='-Z',axis_up='Y',add_leaf_bones=False,bake_anim=False,path_mode='AUTO',use_mesh_modifiers=True)
    print('EXPORTED',name,len(objects),tris,flush=True)

# Render stage. It is excluded from every GLB / FBX selection.
CURRENT=BASE
floor=mat('Studio plum',(.19,.15,.23),0,.86)
cube('Studio floor',(0,0,-.13),(200,200,.12),floor,0)
world=bpy.data.worlds.new('Plum studio world') if not bpy.data.worlds else bpy.data.worlds[0]
bpy.context.scene.world=world;world.use_nodes=True
world.node_tree.nodes.get('Background').inputs['Color'].default_value=(.12,.075,.17,1)
world.node_tree.nodes.get('Background').inputs['Strength'].default_value=.35

def aim(o,p):o.rotation_euler=(Vector(p)-o.location).to_track_quat('-Z','Y').to_euler()
def area(name,pos,power,size,color):
    data=bpy.data.lights.new(name,'AREA');data.energy=power;data.shape='DISK';data.size=size;data.color=color
    o=link(bpy.data.objects.new(name,data),name);o.location=pos;aim(o,(0,0,1.7));return o
area('Warm softbox',(-4,-6,8),1100,5,(1,.77,.61))
area('Cool fill',(4,-3,5),850,4,(.63,.71,1))
area('Lilac rim',(2,4,6),1500,3,(.78,.42,1))
area('Top strip',(-1,1,9),800,3,(1,.88,.70))
camera_data=bpy.data.cameras.new('Character portrait camera');camera=link(bpy.data.objects.new('Character portrait camera',camera_data),'Character portrait camera')
camera_data.type='ORTHO';bpy.context.scene.camera=camera
scene=bpy.context.scene
scene.render.engine='BLENDER_EEVEE' if QUICK else 'CYCLES'
scene.cycles.samples=24
scene.cycles.use_denoising=True
scene.render.resolution_x=900;scene.render.resolution_y=1000;scene.render.resolution_percentage=55 if QUICK else 100
scene.render.image_settings.file_format='PNG'
scene.render.film_transparent=False
scene.view_settings.view_transform='AgX'
scene.view_settings.look='AgX - Medium High Contrast'
scene.render.image_settings.color_mode='RGBA'

for entry in manifest['models']:
    name=entry['name'];col=MODELS[name]
    if ONLY and name not in ONLY: continue
    for other,c in MODELS.items():c.hide_render=other!=name
    objects=list(col.objects);lo,hi=bounds(objects);center=(lo+hi)/2
    height=hi.z-lo.z;width=max(hi.x-lo.x,hi.y-lo.y)
    camera_data.ortho_scale=max(height*1.23,width*1.37)
    # Front camera is mild three-quarter so both eyes stay legible.
    for view,vec in [('Front',Vector((.46,-1,.35)))] if FRONTS else [('Front',Vector((.46,-1,.35))),('Back',Vector((-.57,1,.31)))]:
        camera.location=center+vec.normalized()*12
        aim(camera,center+Vector((0,0,.03)))
        scene.render.filepath=str(OUT/(name+'_'+view+'.png'))
        bpy.ops.render.render(write_still=True)
        print('RENDERED',name,view,flush=True)

for c in MODELS.values():c.hide_render=False
# Place the collection in two spacious rows for immediate Blender inspection.
positions={'GhostSlime':(-7,0),'SkeletonImp':(-2.5,0),'PumpkinKing':(2.5,0),'CountFang':(7,0),'HexCat':(-7,7),'CryptMummy':(-2.5,7),'GraveGolem':(2.5,7),'WraithReaper':(7,7)}
for name,col in MODELS.items():
    x,y=positions[name]
    for o in col.objects:o.location+=Vector((x,y,0))
camera.location=(14,-19,17);aim(camera,(0,3,1.5));camera_data.ortho_scale=24
scene.render.filepath=str(OUT/'HalloweenCollection.png')
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'HalloweenCollection.blend'))
(OUT/'manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
print('COLLECTION COMPLETE',str(OUT),flush=True)
