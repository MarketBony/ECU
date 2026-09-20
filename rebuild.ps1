# Reconstruit le reseau de connaissance Bony a partir des dossiers de travail reels.
#
#   .\rebuild.ps1           reindexe le code de chaque projet (gratuit, aucun token)
#   .\rebuild.ps1 -Complet  force une reextraction complete, sans cache
#
# La passe DOCUMENTS (README, CLAUDE.md, PDF, logos) n'est PAS refaite ici : elle
# coute des tokens. Elle vit dans graphify-out/cache de chaque projet et n'est
# relue que pour les fichiers modifies, via  /graphify .  dans Claude Code.

param([switch]$Complet)

$ErrorActionPreference = 'Continue'
$env:PATH = "$env:USERPROFILE\.local\bin;$env:PATH"

$Kb   = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root = Split-Path -Parent $Kb
$Py   = Join-Path $env:APPDATA 'uv\tools\graphifyy\Scripts\python.exe'

. (Join-Path $Kb 'projets.ps1')

Write-Host ''
Write-Host '=== 1. Prerequis ===' -ForegroundColor Cyan
if (-not (Get-Command graphify -ErrorAction SilentlyContinue)) {
    Write-Host 'graphify absent, installation...' -ForegroundColor Yellow
    winget install --id astral-sh.uv --accept-package-agreements --accept-source-agreements --disable-interactivity
    uv tool install "graphifyy[all]"
    $env:PATH = "$env:USERPROFILE\.local\bin;$env:PATH"
}
graphify --version

Write-Host ''
Write-Host '=== 2. Mise a jour et reindexation du code ===' -ForegroundColor Cyan
foreach ($p in $global:ProjetsBony) {
    Write-Host ("  --- {0} ({1})" -f $p.Tag, (Split-Path $p.Chemin -Leaf)) -ForegroundColor White
    if (-not (Test-Path $p.Chemin)) { Write-Host '      dossier absent, ignore' -ForegroundColor Red; continue }

    if (Test-Path (Join-Path $p.Chemin '.git')) {
        git -C $p.Chemin pull --quiet 2>$null
    }

    if ($Complet) {
        graphify extract $p.Chemin --code-only --force *>$null
        graphify cluster-only $p.Chemin --no-label *>$null
    } else {
        graphify update $p.Chemin *>$null
    }

    $g = Join-Path $p.Chemin 'graphify-out\graph.json'
    if (Test-Path $g) {
        graphify global add $g --as $p.Tag 2>&1 | Select-Object -Last 1
    } else {
        Write-Host '      pas de graphe, lance /graphify . dans ce dossier' -ForegroundColor DarkYellow
    }
}

Write-Host ''
Write-Host '=== 3. Integration Claude Code + hooks git ===' -ForegroundColor Cyan
graphify install *>$null
foreach ($p in $global:ProjetsBony) {
    if (-not (Test-Path $p.Chemin)) { continue }
    Push-Location $p.Chemin
    graphify claude install *>$null
    if (Test-Path (Join-Path $p.Chemin '.git')) { graphify hook install *>$null }
    Pop-Location
}
Write-Host '  ok' -ForegroundColor Green

Write-Host ''
Write-Host '=== 4. Export de la carte globale ===' -ForegroundColor Cyan
Copy-Item (Join-Path $env:USERPROFILE '.graphify\global-graph.json') (Join-Path $Kb 'global-graph.json') -Force
Push-Location $Kb
graphify export html --graph '.\global-graph.json' *>$null
Pop-Location
& $Py (Join-Path $Root '_build3d.py')

Write-Host ''
Write-Host '=== Termine ===' -ForegroundColor Green
graphify global list
graphify benchmark (Join-Path $Kb 'global-graph.json')
