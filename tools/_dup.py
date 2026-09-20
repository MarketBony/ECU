# -*- coding: utf-8 -*-
"""Cross-repo duplication report over the global graph."""
import collections
import json
import re
from pathlib import Path

G = json.loads(Path(r'C:\Users\Operateur\.graphify\global-graph.json').read_text(encoding='utf-8'))
nodes = G['nodes']

SKIP_DEP = {'react', 'react-dom', 'typescript', 'vite', 'zod', 'express', 'cors', 'dotenv',
            'axios', 'prisma', 'tsx', 'lucide-react', 'date-fns', 'name', 'type', 'private',
            'dependencies', 'devDependencies', 'scripts', 'compilerOptions', 'lib', 'module',
            'target', 'include', 'strict', 'types', 'noEmit', 'jsx', 'baseUrl', 'outDir',
            'rootDir', 'esModuleInterop', 'skipLibCheck', 'moduleResolution', 'isolatedModules',
            'forceConsistentCasingInFileNames', 'allowJs', 'resolveJsonModule', 'description',
            'icons', 'lang', 'dir', 'display', 'background_color'}

by_label = collections.defaultdict(set)
detail = collections.defaultdict(list)
kinds = collections.defaultdict(set)
for n in nodes:
    lab = n.get('norm_label') or n.get('label')
    repo = n.get('repo')
    if not lab or not repo:
        continue
    by_label[lab].add(repo)
    detail[lab].append((repo, n.get('source_file'), n.get('label')))
    kinds[lab].add(n.get('file_type') or '?')


def base(p):
    return re.split(r'[\\/]', p or '')[-1]


shared = {l: r for l, r in by_label.items() if len(r) >= 2}
print(f'Concepts presents dans au moins 2 depots : {len(shared)}\n')

print('=== PARTAGES PAR 3 DEPOTS OU PLUS ===')
for l in sorted(shared, key=lambda k: (-len(by_label[k]), k)):
    if len(by_label[l]) < 3:
        break
    lab = detail[l][0][2]
    if lab.lower() in SKIP_DEP:
        continue
    files = sorted({base(f) for _, f, _ in detail[l] if f})
    print(f'  {lab:<32} {len(by_label[l])} depots: {", ".join(sorted(by_label[l]))}')
    print(f'        {", ".join(files[:5])}')

print('\n=== CONCEPTS (docs) PARTAGES PAR 2 DEPOTS ===')
shown = 0
for l in sorted(shared, key=lambda k: k):
    if len(by_label[l]) != 2:
        continue
    k = kinds[l]
    if not (k & {'document', 'rationale', 'concept', 'paper', 'image'}):
        continue
    lab = detail[l][0][2]
    if lab.lower() in SKIP_DEP:
        continue
    files = sorted({base(f) for _, f, _ in detail[l] if f})
    print(f'  {lab[:60]:<62} {", ".join(sorted(by_label[l]))}')
    print(f'        {", ".join(files[:4])}')
    shown += 1
    if shown >= 20:
        break
