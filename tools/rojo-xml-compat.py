"""Keep Lune's generated XML compatible with the project's pinned Rojo 7.4."""
from pathlib import Path
import re
for name in ('StudioWorld', 'AnimationRigs', 'WeaponModels'):
    path = Path('assets') / (name + '.rbxmx')
    text = path.read_text(encoding='utf-8')
    text = re.sub(r'<Content name="TextureContent">\s*<uri>(.*?)</uri>\s*</Content>',
                  r'<Content name="Texture"><url>\1</url></Content>', text, flags=re.S)
    if '<uri>' in text:
        raise ValueError('Unconverted modern Content property')
    path.write_text(text, encoding='utf-8')
