# -*- coding: utf-8 -*-
"""Dump communities of a repo, biggest first. Usage: _dumpc.py <repo> [min_size]"""
import collections
import json
import re
import sys
from pathlib import Path


def base(p):
    return re.split(r'[\\/]', p)[-1] if p else ''


def main():
    root = Path(sys.argv[1])
    minsize = int(sys.argv[2]) if len(sys.argv) > 2 else 1
    out = root / 'graphify-out'
    a = json.loads((out / '.graphify_analysis.json').read_text(encoding='utf-8'))
    g = json.loads((out / 'graph.json').read_text(encoding='utf-8'))
    lab = {n['id']: n.get('label', n['id']) for n in g['nodes']}
    src = {n['id']: (n.get('source_file') or '') for n in g['nodes']}
    comm = {int(k): v for k, v in a['communities'].items()}
    print(f'### {root.name} — {len(comm)} communautes')
    for c in sorted(comm, key=lambda k: -len(comm[k])):
        ids = comm[c]
        if len(ids) < minsize:
            continue
        names = [lab.get(i, i) for i in ids][:7]
        files = [f for f, _ in collections.Counter(base(src.get(i, '')) for i in ids).most_common(2) if f]
        print(f"C{c}({len(ids)})[{','.join(files)}]: {' | '.join(names)}")


if __name__ == '__main__':
    main()
