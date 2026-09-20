# -*- coding: utf-8 -*-
"""AST + merge + build + cluster for one repo.
Usage: _pipeline.py <repo-abs-path> <semantic-input-tokens>
"""
import glob
import json
import sys
from pathlib import Path

from graphify.extract import collect_files, extract
from graphify.cache import save_semantic_cache
from graphify.build import build_from_json
from graphify.cluster import cluster, score_all
from graphify.analyze import god_nodes, surprising_connections, suggest_questions
from graphify.report import generate
from graphify.export import to_json
from graphify.diagnostics import diagnose_extraction

SPEC = r'C:\Users\Operateur\.claude\skills\graphify\references\extraction-spec.md'


def main():
    root = sys.argv[1]
    sem_tokens = int(sys.argv[2])
    out = Path(root) / 'graphify-out'
    print(f'===== {Path(root).name} =====')

    detect = json.loads((out / '.graphify_detect.json').read_text(encoding='utf-8'))

    # --- Part A : AST (sequential, avoids the Windows spawn guard) ---
    code_files = []
    for f in detect.get('files', {}).get('code', []):
        p = Path(f)
        code_files.extend(collect_files(p) if p.is_dir() else [p])
    if code_files:
        ast = extract(code_files, cache_root=Path(root), parallel=False)
    else:
        ast = {'nodes': [], 'edges': [], 'input_tokens': 0, 'output_tokens': 0}
    print(f'  AST      : {len(ast["nodes"])} noeuds, {len(ast["edges"])} aretes')

    # --- Part B3 : merge chunks + cache ---
    n, e, h = [], [], []
    for c in sorted(glob.glob(str(out / '.graphify_chunk_*.json'))):
        d = json.loads(Path(c).read_text(encoding='utf-8'))
        n += d.get('nodes', [])
        e += d.get('edges', [])
        h += d.get('hyperedges', [])
    uncached = [l for l in (out / '.graphify_uncached.txt').read_text(encoding='utf-8').splitlines() if l]
    saved = save_semantic_cache(n, e, h, root=root, allowed_source_files=uncached, prompt_file=SPEC)
    print(f'  semantique: {len(n)} noeuds, {len(e)} aretes — {saved} fichiers mis en cache')

    cp = out / '.graphify_cached.json'
    cached = json.loads(cp.read_text(encoding='utf-8')) if cp.exists() else {'nodes': [], 'edges': [], 'hyperedges': []}
    seen, ded = set(), []
    for x in cached['nodes'] + n:
        if x['id'] not in seen:
            seen.add(x['id'])
            ded.append(x)
    sem = {'nodes': ded, 'edges': cached['edges'] + e,
           'hyperedges': cached.get('hyperedges', []) + h,
           'input_tokens': sem_tokens, 'output_tokens': 0}
    (out / '.graphify_semantic.json').write_text(json.dumps(sem, ensure_ascii=False), encoding='utf-8')

    # --- Part C : merge AST + semantic ---
    seen = {x['id'] for x in ast['nodes']}
    merged_nodes = list(ast['nodes'])
    for x in sem['nodes']:
        if x['id'] not in seen:
            merged_nodes.append(x)
            seen.add(x['id'])
    merged = {'nodes': merged_nodes, 'edges': ast['edges'] + sem['edges'],
              'hyperedges': sem['hyperedges'],
              'input_tokens': sem_tokens, 'output_tokens': 0}
    (out / '.graphify_extract.json').write_text(json.dumps(merged, indent=2, ensure_ascii=False), encoding='utf-8')
    print(f'  fusion   : {len(merged_nodes)} noeuds, {len(merged["edges"])} aretes')

    # --- Step 4 : build, cluster, analyse ---
    G = build_from_json(merged, root=root, directed=False)
    if G.number_of_nodes() == 0:
        print('  ERREUR: graphe vide')
        raise SystemExit(1)
    communities = cluster(G)
    cohesion = score_all(G, communities)
    gods = god_nodes(G)
    surprises = surprising_connections(G, communities)
    labels = {cid: f'Community {cid}' for cid in communities}
    questions = suggest_questions(G, communities, labels)

    if not to_json(G, communities, str(out / 'graph.json')):
        print('  ERREUR: garde anti-retrecissement (#479) a refuse l ecriture')
        raise SystemExit(1)
    report = generate(G, communities, cohesion, labels, gods, surprises, detect,
                      {'input': sem_tokens, 'output': 0}, root, suggested_questions=questions)
    (out / 'GRAPH_REPORT.md').write_text(report, encoding='utf-8')
    (out / '.graphify_analysis.json').write_text(json.dumps({
        'communities': {str(k): v for k, v in communities.items()},
        'cohesion': {str(k): v for k, v in cohesion.items()},
        'gods': gods, 'surprises': surprises, 'questions': questions,
    }, indent=2, ensure_ascii=False), encoding='utf-8')
    print(f'  GRAPHE   : {G.number_of_nodes()} noeuds, {G.number_of_edges()} aretes, {len(communities)} communautes')

    d = diagnose_extraction(merged, directed=False, root=root)
    flags = [f'{d[k]} {lab}' for k, lab in (
        ('dangling_endpoint_edges', 'orphelines'), ('missing_endpoint_edges', 'endpoints manquants'),
        ('self_loop_edges', 'boucles'), ('undirected_same_endpoint_collapsed_edges', 'fusionnees')) if d.get(k, 0)]
    print('  SANTE    : ' + ('; '.join(flags) if flags else 'OK'))


if __name__ == '__main__':
    main()
