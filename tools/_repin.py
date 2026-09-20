# -*- coding: utf-8 -*-
"""Repointe les hooks git de graphify sur l'interpreteur qui existe VRAIMENT.

Le bac a sable de l'application Claude virtualise %APPDATA% : vu de l'interieur,
l'outil est sous AppData\\Roaming\\uv\\tools ; vu d'un vrai terminal, il est sous
AppData\\Local\\Packages\\<app>\\LocalCache\\Roaming\\uv\\tools. Un hook epingle
sur le premier chemin echoue des qu'on commite hors de l'app.

On epingle donc le chemin non virtualise (celui sous Packages, s'il existe) et on
ecrit la meme valeur dans graphify-out/.graphify_python, que le hook lit comme
seconde sonde.
"""
import os
import re
from pathlib import Path

FOLDERS = ['APP FORUM', 'gearbox3backup', 'RELTEL']
DOCS = Path(r'C:\Users\Operateur\Documents')


def vrai_python():
    """Le chemin reel, pas sa projection dans le bac a sable."""
    local = Path(os.environ['LOCALAPPDATA'])
    for pkg in sorted((local / 'Packages').glob('*')):
        p = pkg / 'LocalCache' / 'Roaming' / 'uv' / 'tools' / 'graphifyy' / 'Scripts' / 'python.exe'
        if p.is_file():
            return p
    # pas d'application empaquetee : l'installation est deja au bon endroit
    p = Path(os.environ['APPDATA']) / 'uv' / 'tools' / 'graphifyy' / 'Scripts' / 'python.exe'
    return p if p.is_file() else None


PY = vrai_python()
if PY is None:
    raise SystemExit('interpreteur graphify introuvable')
print(f'interpreteur reel : {PY}\n')

for name in FOLDERS:
    repo = DOCS / name
    for hook in ('post-commit', 'post-checkout'):
        f = repo / '.git' / 'hooks' / hook
        if not f.is_file():
            print(f'  {name}/{hook} : absent')
            continue
        s = f.read_text(encoding='utf-8')
        new, n = re.subn(r"_PINNED='[^']*'", lambda _: "_PINNED='" + str(PY) + "'", s)
        if n:
            f.write_text(new, encoding='utf-8', newline='\n')
        print(f'  {name}/{hook} : {n} remplacement(s)')

    # seconde sonde du hook : graphify-out/.graphify_python
    out = repo / 'graphify-out'
    if out.is_dir():
        (out / '.graphify_python').write_text(str(PY), encoding='utf-8', newline='')
        print(f'  {name}/graphify-out/.graphify_python : ecrit')

print('\nverification :')
for name in FOLDERS:
    f = DOCS / name / '.git' / 'hooks' / 'post-commit'
    if f.is_file():
        m = re.search(r"_PINNED='([^']*)'", f.read_text(encoding='utf-8'))
        ok = m and Path(m.group(1)).is_file()
        marque = 'OK' if ok else 'PROBLEME'
        virt = 'VIRTUALISE' if m and '\\Roaming\\uv' in m.group(1) and 'Packages' not in m.group(1) else 'reel'
        print(f'  {name:<16} {marque:<9} ({virt})')
