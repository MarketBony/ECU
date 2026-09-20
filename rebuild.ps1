# Reconstruit integralement le reseau de connaissance graphify.
# Usage : .\rebuild.ps1  [-Root <dossier>]  [-Docs]
#   -Docs : ajoute la passe semantique sur docs/PDF (necessite une cle API)

param(
  [string]$Root = "C:\Users\Operateur\Documents\graphify-kb",
  [switch]$Docs
)

$ErrorActionPreference = "Stop"
$env:PATH = "$env:USERPROFILE\.local\bin;$env:PATH"

$Repos = @("gearbox", "GRID", "Forum-2026", "clutch-press-review")
$RepoRoot = Join-Path $Root "repos"
$KbRoot   = Join-Path $Root "kb"

Write-Host "=== 1. Prerequis ===" -ForegroundColor Cyan
if (-not (Get-Command graphify -ErrorAction SilentlyContinue)) {
  Write-Host "graphify absent, installation..." -ForegroundColor Yellow
  winget install --id astral-sh.uv --accept-package-agreements --accept-source-agreements --disable-interactivity
  uv tool install "graphifyy[all]"
  $env:PATH = "$env:USERPROFILE\.local\bin;$env:PATH"
}
graphify --version

Write-Host "`n=== 2. Clone / mise a jour des depots ===" -ForegroundColor Cyan
New-Item -ItemType Directory -Force $RepoRoot | Out-Null
foreach ($r in $Repos) {
  $dest = Join-Path $RepoRoot $r
  if (Test-Path $dest) {
    Write-Host "  pull $r"
    git -C $dest pull --quiet
  } else {
    Write-Host "  clone $r"
    gh repo clone "MarketBony/$r" $dest -- --quiet
  }
}

Write-Host "`n=== 3. Extraction + fusion dans le graphe global ===" -ForegroundColor Cyan
foreach ($r in $Repos) {
  $dest = Join-Path $RepoRoot $r
  Write-Host "  --- $r ---"
  if ($Docs) {
    graphify extract $dest --global --as $r          # code + docs (cle API requise)
  } else {
    graphify extract $dest --code-only --global --as $r   # code seul, 0 token
  }
  graphify cluster-only $dest --no-label
}

Write-Host "`n=== 4. Export de la carte globale ===" -ForegroundColor Cyan
New-Item -ItemType Directory -Force $KbRoot | Out-Null
Copy-Item "$env:USERPROFILE\.graphify\global-graph.json" (Join-Path $KbRoot "global-graph.json") -Force
Push-Location $KbRoot
graphify export html --graph ".\global-graph.json"
Pop-Location

Write-Host "`n=== 5. Integration Claude Code + hooks git ===" -ForegroundColor Cyan
graphify install
foreach ($r in $Repos) {
  Push-Location (Join-Path $RepoRoot $r)
  graphify claude install | Out-Null
  graphify hook install   | Out-Null
  Pop-Location
}

Write-Host "`n=== Termine ===" -ForegroundColor Green
graphify global list
graphify benchmark (Join-Path $KbRoot "global-graph.json")
