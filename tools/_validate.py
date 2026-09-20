# -*- coding: utf-8 -*-
"""Validate chunk JSON files and report coverage against .graphify_uncached.txt"""
import json
import sys
import glob
from pathlib import Path


def main():
    root = Path(sys.argv[1])
    out = root / 'graphify-out'
    print(f'== {root.name} ==')

    uncached = [l for l in (out / '.graphify_uncached.txt').read_text(encoding='utf-8').splitlines() if l]
    covered = set()
    total_n = total_e = total_h = 0

    for c in sorted(glob.glob(str(out / '.graphify_chunk_*.json'))):
        name = Path(c).name
        try:
            d = json.loads(Path(c).read_text(encoding='utf-8'))
        except Exception as ex:
            print(f'   {name}: JSON INVALIDE -> {ex}')
            continue
        n, e, h = d.get('nodes', []), d.get('edges', []), d.get('hyperedges', [])
        ids = {x.get('id') for x in n}
        dangling = [x for x in e if x.get('source') not in ids or x.get('target') not in ids]
        for x in n:
            if x.get('source_file'):
                covered.add(x['source_file'])
        total_n += len(n); total_e += len(e); total_h += len(h)
        flag = f'  {len(dangling)} aretes hors-chunk' if dangling else '  ok'
        print(f'   {name}: {len(n)} noeuds, {len(e)} aretes, {len(h)} hyper —{flag}')

    missing = [f for f in uncached if f not in covered]
    print(f'   TOTAL: {total_n} noeuds, {total_e} aretes, {total_h} hyperedges')
    print(f'   couverture: {len(uncached) - len(missing)}/{len(uncached)} fichiers')
    if missing:
        print('   MANQUANTS:')
        for f in missing:
            print('     ', f)


if __name__ == '__main__':
    main()
