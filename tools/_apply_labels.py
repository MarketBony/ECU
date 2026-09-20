# -*- coding: utf-8 -*-
"""Apply community labels, regenerate report, re-export graph.json.
Hand-written labels come from _labels.json; the remaining (small) communities
get a name derived from their dominant node, never left as 'Community N'.
Usage: _apply_labels.py <repo-abs-path> <semantic-input-tokens>
"""
import collections
import json
import re
import sys
from pathlib import Path

from graphify.build import build_from_json
from graphify.analyze import suggest_questions
from graphify.report import generate
from graphify.export import to_json

LABELS_FILE = str(Path(__file__).with_name('_labels.json'))


def derive(ids, lab, src):
    """Name a small community after its most representative member."""
    names = [lab.get(i, i) for i in ids]
    # prefer a human-looking label over a symbol like `foo()` or `ref_x`
    human = [n for n in names if not n.endswith('()') and not n.startswith('ref_')
             and not n.startswith('.') and len(n) > 3]
    pick = (human or names or ['?'])[0]
    pick = re.sub(r'\.(ts|tsx|js|mjs|sql|md|json|html|py|ps1|yml|svg|png|pdf)$', '', pick)
    pick = pick.strip('"').strip()
    if len(pick) > 48:
        pick = pick[:45].rstrip() + '…'
    return pick or 'Divers'


def main():
    root = Path(sys.argv[1])
    sem_tokens = int(sys.argv[2])
    out = root / 'graphify-out'

    extraction = json.loads((out / '.graphify_extract.json').read_text(encoding='utf-8'))
    detection = json.loads((out / '.graphify_detect.json').read_text(encoding='utf-8'))
    analysis = json.loads((out / '.graphify_analysis.json').read_text(encoding='utf-8'))
    graph = json.loads((out / 'graph.json').read_text(encoding='utf-8'))
    hand = json.loads(Path(LABELS_FILE).read_text(encoding='utf-8')).get(root.name, {})

    lab = {n['id']: n.get('label', n['id']) for n in graph['nodes']}
    src = {n['id']: (n.get('source_file') or '') for n in graph['nodes']}

    G = build_from_json(extraction, root=str(root), directed=False)
    communities = {int(k): v for k, v in analysis['communities'].items()}
    cohesion = {int(k): v for k, v in analysis['cohesion'].items()}

    labels, derived = {}, 0
    for cid, ids in communities.items():
        if str(cid) in hand:
            labels[cid] = hand[str(cid)]
        else:
            labels[cid] = derive(ids, lab, src)
            derived += 1

    questions = suggest_questions(G, communities, labels)
    report = generate(G, communities, cohesion, labels, analysis['gods'], analysis['surprises'],
                      detection, {'input': sem_tokens, 'output': 0}, str(root),
                      suggested_questions=questions)
    (out / 'GRAPH_REPORT.md').write_text(report, encoding='utf-8')
    (out / '.graphify_labels.json').write_text(
        json.dumps({str(k): v for k, v in labels.items()}, ensure_ascii=False), encoding='utf-8')

    if not to_json(G, communities, str(out / 'graph.json'), community_labels=labels):
        print('  ATTENTION: garde anti-retrecissement a refuse la reecriture')
    print(f'  {root.name}: {len(labels)} communautes nommees ({len(hand)} a la main, {derived} derivees)')


if __name__ == '__main__':
    main()
