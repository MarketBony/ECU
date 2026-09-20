# Regenere la carte 3D du reseau et l'ouvre dans le navigateur.
$ErrorActionPreference = 'Stop'
$env:PATH = "$env:USERPROFILE\.local\bin;$env:PATH"

$Kb   = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root = Split-Path -Parent $Kb
$Py   = Join-Path $env:APPDATA 'uv\tools\graphifyy\Scripts\python.exe'
$Glob = Join-Path $env:USERPROFILE '.graphify\global-graph.json'

Write-Host ''
Write-Host '  Reseau de connaissance MarketBony' -ForegroundColor Cyan
Write-Host '  ---------------------------------' -ForegroundColor DarkGray

if (-not (Test-Path $Glob)) {
    Write-Host '  Graphe global introuvable. Lance d abord rebuild.ps1' -ForegroundColor Red
    Read-Host '  Entree pour fermer'
    exit 1
}

# Rafraichit la partie code de chaque depot (gratuit, aucun LLM)
$repos = Get-ChildItem (Join-Path $Root 'repos') -Directory -ErrorAction SilentlyContinue
foreach ($r in $repos) {
    Write-Host ("  maj  {0}" -f $r.Name) -NoNewline
    try {
        graphify update $r.FullName *>$null
        graphify global add (Join-Path $r.FullName 'graphify-out\graph.json') --as $r.Name *>$null
        Write-Host '  ok' -ForegroundColor Green
    } catch {
        Write-Host '  ignore' -ForegroundColor DarkYellow
    }
}

Copy-Item $Glob (Join-Path $Kb 'global-graph.json') -Force
Push-Location $Kb
graphify export html --graph '.\global-graph.json' *>$null
Pop-Location

& $Py (Join-Path $Root '_build3d.py')

$carte = Join-Path $Kb 'carte-3d.html'
Write-Host ''
Write-Host "  Ouverture de $carte" -ForegroundColor Cyan
Start-Process $carte
Start-Sleep -Milliseconds 700
