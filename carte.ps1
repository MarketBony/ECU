# Regenere la carte 3D du reseau et l'ouvre dans le navigateur.
#   .\carte.ps1            rafraichit la partie code puis ouvre la carte
#   .\carte.ps1 -Vite      ouvre la carte telle quelle, sans rafraichir

param([switch]$Vite)

$ErrorActionPreference = 'Continue'
$env:PATH = "$env:USERPROFILE\.local\bin;$env:PATH"

$Kb    = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root  = Split-Path -Parent $Kb
$Py    = Join-Path $env:APPDATA 'uv\tools\graphifyy\Scripts\python.exe'
$Glob  = Join-Path $env:USERPROFILE '.graphify\global-graph.json'
$Carte = Join-Path $Kb 'carte-3d.html'

function Fin($code) {
    if ($code -ne 0) { Write-Host ''; Read-Host '  Une erreur est survenue. Entree pour fermer' }
    exit $code
}

# Resout un vrai navigateur. L'association .html de cette machine pointe vers
# Internet Explorer, qui n'existe plus : Start-Process sur le fichier ne fait rien.
function Get-Navigateur {
    $c = @(
        "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
        "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe",
        "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
        "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
        "$env:ProgramFiles\Mozilla Firefox\firefox.exe"
    )
    foreach ($p in $c) { if (Test-Path $p) { return $p } }
    return $null
}

Write-Host ''
Write-Host '  Reseau de connaissance MarketBony' -ForegroundColor Cyan
Write-Host '  ---------------------------------' -ForegroundColor DarkGray

if (-not (Test-Path $Glob)) {
    Write-Host '  Graphe global introuvable. Lance d abord rebuild.ps1' -ForegroundColor Red
    Fin 1
}

if (-not $Vite) {
    $repos = Get-ChildItem (Join-Path $Root 'repos') -Directory -ErrorAction SilentlyContinue
    foreach ($r in $repos) {
        Write-Host ("  maj  {0,-22}" -f $r.Name) -NoNewline
        graphify update $r.FullName *>$null
        if ($LASTEXITCODE -eq 0) {
            graphify global add (Join-Path $r.FullName 'graphify-out\graph.json') --as $r.Name *>$null
            Write-Host 'ok' -ForegroundColor Green
        } else {
            Write-Host 'inchange' -ForegroundColor DarkYellow
        }
    }
    Copy-Item $Glob (Join-Path $Kb 'global-graph.json') -Force
    Push-Location $Kb
    graphify export html --graph '.\global-graph.json' *>$null
    Pop-Location
    Write-Host '  carte 3D...' -NoNewline
    & $Py (Join-Path $Root '_build3d.py') *>$null
    if ($LASTEXITCODE -ne 0) { Write-Host ' echec' -ForegroundColor Red; Fin 1 }
    Write-Host ' ok' -ForegroundColor Green
}

if (-not (Test-Path $Carte)) {
    Write-Host "  Carte introuvable : $Carte" -ForegroundColor Red
    Fin 1
}

$nav = Get-Navigateur
if ($nav) {
    Write-Host ("  ouverture dans {0}" -f (Split-Path $nav -Leaf)) -ForegroundColor Cyan
    Start-Process -FilePath $nav -ArgumentList ('"file:///' + ($Carte -replace '\\', '/') + '"')
} else {
    Write-Host '  Aucun navigateur trouve, ouverture par defaut' -ForegroundColor DarkYellow
    Start-Process $Carte
}
Start-Sleep -Milliseconds 900
