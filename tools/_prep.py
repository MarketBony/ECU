# -*- coding: utf-8 -*-
"""Detect corpus + check semantic cache for one repo. Usage: _prep.py <repo-abs-path>"""
import json
import sys
from pathlib import Path
from graphify.detect import detect
from graphify.cache import check_semantic_cache

SPEC = r'C:\Users\Operateur\.claude\skills\graphify\references\extraction-spec.md'


def main():
    root = sys.argv[1]
    out = Path(root) / 'graphify-out'
    out.mkdir(exist_ok=True)

    result = detect(Path(root))
    (out / '.graphify_detect.json').write_text(json.dumps(result, ensure_ascii=False), encoding='utf-8')
    print(f'== {Path(root).name} ==')
    print(f'   total: {result["total_files"]} files, {result.get("total_words"):,} words')
    for k, v in result.get('files', {}).items():
        if v:
            print(f'   {k}: {len(v)}')
    for s in (result.get('skipped_sensitive') or []):
        print(f'   SENSIBLE (ecarte): {s}')

    all_files = [f for cat in ('document', 'paper', 'image') for f in result['files'].get(cat, [])]
    cn, ce, ch, uncached = check_semantic_cache(all_files, root=root, prompt_file=SPEC)
    if cn or ce or ch:
        (out / '.graphify_cached.json').write_text(
            json.dumps({'nodes': cn, 'edges': ce, 'hyperedges': ch}, ensure_ascii=False), encoding='utf-8')
    else:
        (out / '.graphify_cached.json').unlink(missing_ok=True)
    (out / '.graphify_uncached.txt').write_text('\n'.join(uncached), encoding='utf-8')
    print(f'   cache: {len(all_files) - len(uncached)} hits, {len(uncached)} a extraire')

    imgs = set(result['files'].get('image', []))
    texts = [f for f in uncached if f not in imgs]
    images = [f for f in uncached if f in imgs]
    print(f'   --> {len(texts)} fichiers texte, {len(images)} images')
    print('   TEXTES:')
    for f in texts:
        print('     ', f)
    print('   IMAGES:')
    for f in images:
        print('     ', f)


if __name__ == '__main__':
    main()
