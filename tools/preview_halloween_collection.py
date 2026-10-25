"""Create a local gallery and contact sheets from actual Blender renders."""
from pathlib import Path
import shutil
import sys
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'assets' / 'HalloweenCollection'
NAMES = [('GhostSlime', 'Ghost Slime'), ('SkeletonImp', 'Skeleton Imp'),
         ('PumpkinKing', 'Pumpkin King'), ('CountFang', 'Count Fang'),
         ('HexCat', 'Hex Cat'), ('CryptMummy', 'Crypt Mummy'),
         ('GraveGolem', 'Grave Golem'), ('WraithReaper', 'Wraith Reaper')]

def main():
    OUT.mkdir(exist_ok=True)
    (OUT / 'vendor').mkdir(exist_ok=True)
    shutil.copy2(ROOT / 'assets/PumpkinBossPreview/vendor/model-viewer.min.js', OUT / 'vendor/model-viewer.min.js')
    font_path = Path('C:/Windows/Fonts/seguisb.ttf')
    font = ImageFont.truetype(str(font_path), 28)
    small = ImageFont.truetype(str(font_path), 19)
    for view in ('Front', 'Back'):
        if '--html-only' in sys.argv:
            break
        if view == 'Back' and '--front-only' in sys.argv:
            continue
        board = Image.new('RGB', (1920, 1260), '#171220')
        draw = ImageDraw.Draw(board)
        draw.text((40, 18), f'HALLOWEEN COLLECTION / {view.upper()} / BLENDER RENDERS', font=font, fill='#f0d9ae')
        for i, (stem, title) in enumerate(NAMES):
            path = OUT / f'{stem}_{view}.png'
            with Image.open(path) as source:
                im = source.convert('RGB')
                im.thumbnail((470, 530))
                x, y = (i % 4) * 480, 70 + (i // 4) * 590
                board.paste(im, (x + (480 - im.width)//2, y + (530-im.height)//2))
                draw.text((x+240, y+538), title, font=font, fill='#eee5fa', anchor='mt')
                draw.text((x+240, y+572), view + ' view', font=small, fill='#afa2c4', anchor='mt')
        board.save(OUT / f'Collection_{view}.jpg', quality=94)
    options = ''.join(f'<option value="{stem}">{title}</option>' for stem,title in NAMES)
    gallery = ''.join(f'<article><h2>{title}</h2><div class="pair"><img src="{stem}_Front.png" alt="{title} front"><img src="{stem}_Back.png" alt="{title} back"></div><p><a href="{stem}.blend">Blender</a> · <a href="{stem}.glb">GLB</a> · <a href="{stem}.fbx">FBX</a></p></article>' for stem,title in NAMES)
    html = '''<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Halloween Collection — 8 actual 3D models</title>
<script type="module" src="./vendor/model-viewer.min.js"></script>
<style>*{box-sizing:border-box}body{margin:0;background:#171220;color:#f2e8fa;font:16px system-ui,sans-serif}header,main{max-width:1500px;margin:auto;padding:24px}h1{margin:0;color:#ffd49c}p{color:#c3b7d1}select,button{background:#342740;color:#fff;border:1px solid #8e769e;padding:12px;font:inherit;border-radius:6px}a{color:#ffce90}model-viewer{display:block;width:100%;height:65vh;min-height:380px;background:radial-gradient(#3e2f4d,#171220)}nav{display:flex;gap:10px;align-items:center;flex-wrap:wrap}#gallery{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:24px;margin-top:40px}article{border-top:1px solid #594361;padding-top:12px}.pair{display:flex}.pair img{width:50%;object-fit:contain}h2{font-size:22px}#status{color:#d4c5df}@media(max-width:700px){#gallery{grid-template-columns:1fr}header,main{padding:16px}}</style>
<header><h1>Halloween Collection</h1><p>Eight actual editable 3D models · Static models · Blender renders below</p><nav><label for="pick">Monster</label><select id="pick">OPTIONS</select><span id="status" role="status">Loading…</span></nav></header>
<main><model-viewer id="model" src="GhostSlime.glb" camera-controls camera-orbit="25deg 75deg auto" environment-image="neutral" exposure="1.1" shadow-intensity="0.5" interaction-prompt="none" alt="Ghost Slime actual 3D model"></model-viewer><nav><button data-orbit="0deg 80deg auto">Front</button><button data-orbit="90deg 80deg auto">Side</button><button data-orbit="180deg 80deg auto">Back</button><a id="download" href="GhostSlime.glb" download>Download GLB</a></nav><section id="gallery">GALLERY</section></main>
<script>const model=document.querySelector('#model'),pick=document.querySelector('#pick'),status=document.querySelector('#status');pick.addEventListener('change',()=>{status.textContent='Loading…';document.body.dataset.modelReady='loading';model.src=pick.value+'.glb';model.alt=pick.selectedOptions[0].text+' actual 3D model';document.querySelector('#download').href=model.src;model.resetTurntableRotation(0);model.cameraOrbit='25deg 75deg auto'});model.addEventListener('load',()=>{status.textContent=pick.selectedOptions[0].text+' — 3D model ready';document.body.dataset.modelReady=pick.value});model.addEventListener('error',()=>{status.textContent='Model could not load';document.body.dataset.modelReady='error'});document.querySelectorAll('[data-orbit]').forEach(b=>b.onclick=()=>{model.resetTurntableRotation(0);model.cameraOrbit=b.dataset.orbit;model.jumpCameraToGoal()});</script></html>'''
    (OUT / 'preview.html').write_text(html.replace('OPTIONS',options).replace('GALLERY',gallery), encoding='utf-8')
    print('Created preview.html; contact sheets generated for requested views')

if __name__ == '__main__':
    main()
