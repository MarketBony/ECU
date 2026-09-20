# -*- coding: utf-8 -*-
"""Save manifest, update cost tracker, report unstamped files.
Usage: _finish.py <repo-abs-path> <semantic-input-tokens>
"""
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

from graphify.detect import save_manifest
from graphify.cli import _stamped_manifest_files


def main():
    root = Path(sys.argv[1])
    sem_tokens = int(sys.argv[2])
    out = root / 'graphify-out'

    detect = json.loads((out / '.graphify_detect.json').read_text(encoding='utf-8'))
    extract = json.loads((out / '.graphify_extract.json').read_text(encoding='utf-8'))

    corpus = detect.get('all_files') or detect['files']
    manifest_files = _stamped_manifest_files(corpus, extract, root)
    sem_types = ('document', 'paper', 'image')
    dispatched = {f for t, fl in detect['files'].items() if t in sem_types for f in fl}
    stamped = {f for fl in manifest_files.values() for f in fl}
    cleared = dispatched - stamped
    scan = {f for fl in corpus.values() for f in fl}
    save_manifest(manifest_files, root=str(root), scan_corpus=scan, clear_semantic=cleared or None)

    print(f'== {root.name} ==')
    if cleared:
        print(f'   NON marques (seront repris au prochain run): {len(cleared)}')
        for f in sorted(cleared):
            print('     ', f)
    else:
        print('   tous les fichiers semantiques ont produit des noeuds')

    cp = out / 'cost.json'
    cost = json.loads(cp.read_text(encoding='utf-8')) if cp.exists() else {
        'runs': [], 'total_input_tokens': 0, 'total_output_tokens': 0}
    cost['runs'].append({'date': datetime.now(timezone.utc).isoformat(),
                         'input_tokens': sem_tokens, 'output_tokens': 0,
                         'files': detect.get('total_files', 0)})
    cost['total_input_tokens'] += sem_tokens
    cp.write_text(json.dumps(cost, indent=2, ensure_ascii=False), encoding='utf-8')
    print(f'   cout de ce run: {sem_tokens:,} tokens')


if __name__ == '__main__':
    main()
