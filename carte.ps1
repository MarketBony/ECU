# Regenere la carte 3D du reseau Bony et l'ouvre dans le navigateur.
#   .\carte.ps1            rafraichit la partie code de chaque projet puis ouvre la carte
#   .\carte.ps1 -Vite      ouvre la carte telle quelle, sans rafraichir

param([switch]$Vite)

$ErrorActionPreference = 'Continue'
$env:PATH = "$env:USERPROFILE\.local\bin;$env:PATH"

$Kb    = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root  = Split-Path -Parent $Kb
$Py    = Join-Path $env:APPDATA 'uv\tools\graphifyy\Scripts\python.exe'
$Glob  = Join-Path $env:USERPROFILE '.graphify\global-graph.json'
$Carte = Join-Path $Kb 'carte-3d.html'

. (Join-Path $Kb 'projets.ps1')

function Fin($code) {
    if ($code -ne 0) { Write-Host ''; Read-Host '  Une erreur est survenue. Entree pour fermer' }
    exit $code
}

# L'association .html de cette machine pointe vers Internet Explorer, qui n'existe
# plus : Start-Process sur le fichier n'ouvre rien. On resout un vrai navigateur.
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
Write-Host '  Reseau de connaissance Bony' -ForegroundColor Cyan
Write-Host '  ---------------------------' -ForegroundColor DarkGray

if (-not (Test-Path $Glob)) {
    Write-Host '  Graphe global introuvable. Lance d abord rebuild.ps1' -ForegroundColor Red
    Fin 1
}

if (-not $Vite) {
    foreach ($p in $global:ProjetsBony) {
        Write-Host ("  maj  {0,-14}" -f $p.Tag) -NoNewline
        if (-not (Test-Path $p.Chemin)) { Write-Host 'dossier absent' -ForegroundColor Red; continue }
        graphify update $p.Chemin *>$null
        $g = Join-Path $p.Chemin 'graphify-out\graph.json'
        if (Test-Path $g) {
            graphify global add $g --as $p.Tag *>$null
            Write-Host 'ok' -ForegroundColor Green
        } else {
            Write-Host 'pas encore indexe' -ForegroundColor DarkYellow
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
