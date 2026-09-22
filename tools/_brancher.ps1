# Deplace l'index graphify des clones temporaires vers les VRAIS dossiers de travail,
# puis y installe les hooks pour que chaque commit mette le reseau a jour.
#
# SCRIPT HISTORIQUE — il ne tourne plus tel quel. Il decrit la toute premiere
# installation, ou les depots etaient clones sous <racine>\repos\ avant d'etre
# rebranches sur les dossiers de travail. Ce dossier `repos\` n'existe plus
# depuis longtemps ; il en reste seulement un `source_path` mort pour gearbox
# dans ~/.graphify/global-manifest.json, sans effet sur le graphe.
# Conserve pour la trace. Pour brancher un projet aujourd'hui :
# nouveau-projet.ps1, documente dans NOUVEAU-PROJET-BONY.md.

$ErrorActionPreference = 'Continue'
$env:PATH = "$env:USERPROFILE\.local\bin;$env:PATH"

# Deduit de l'emplacement de ce fichier : le dossier a ete renomme le 22/09/2026.
$Root = Split-Path -Parent $PSScriptRoot
$Docs = 'C:\Users\Operateur\Documents'

# clone temporaire  ->  vrai dossier de travail  ->  tag dans le graphe global
$Paires = @(
    @{ Clone = "$Root\repos\Forum-2026"; Reel = "$Docs\APP FORUM";      Tag = 'Forum-2026' },
    @{ Clone = "$Root\repos\gearbox";    Reel = "$Docs\gearbox3backup"; Tag = 'gearbox'    },
    @{ Clone = "$Root\repos\GRID";       Reel = "$Docs\RELTEL";         Tag = 'GRID'       }
)

$Utf8NoBom = New-Object System.Text.UTF8Encoding $false

foreach ($p in $Paires) {
    Write-Host ''
    Write-Host ("===== {0}  ->  {1}" -f $p.Tag, (Split-Path $p.Reel -Leaf)) -ForegroundColor Cyan

    if (-not (Test-Path $p.Reel)) { Write-Host '  dossier reel introuvable, ignore' -ForegroundColor Red; continue }
    if (-not (Test-Path "$($p.Clone)\graphify-out")) { Write-Host '  index source introuvable, ignore' -ForegroundColor Red; continue }

    # 1. deplacer l'index (code + documents + cache semantique)
    $dest = Join-Path $p.Reel 'graphify-out'
    if (Test-Path $dest) { Remove-Item $dest -Recurse -Force }
    Copy-Item "$($p.Clone)\graphify-out" $dest -Recurse -Force
    Write-Host '  index deplace' -ForegroundColor Green

    # 2. re-ancrer les chemins absolus du sidecar
    [System.IO.File]::WriteAllText((Join-Path $dest '.graphify_root'), $p.Reel, $Utf8NoBom)

    # 3. reconcilier le code (gratuit, aucun LLM) — le dossier reel peut differer du clone
    Write-Host '  reconciliation du code...' -NoNewline
    graphify update $p.Reel *>$null
    if ($LASTEXITCODE -eq 0) { Write-Host ' ok' -ForegroundColor Green }
    else { Write-Host ' rien a faire' -ForegroundColor DarkYellow }

    # 4. brancher Claude Code + les hooks git
    Push-Location $p.Reel
    graphify claude install *>$null
    graphify hook install   *>$null
    Pop-Location
    Write-Host '  hooks Claude Code + git installes' -ForegroundColor Green

    # 5. (re)enregistrer dans le graphe global depuis le vrai dossier
    graphify global add (Join-Path $dest 'graph.json') --as $p.Tag 2>&1 | Select-Object -Last 1
}

Write-Host ''
Write-Host '===== projet obsolete retire =====' -ForegroundColor Cyan
graphify global remove clutch-press-review 2>&1 | Select-Object -Last 1

Write-Host ''
Write-Host '===== etat du graphe global =====' -ForegroundColor Cyan
graphify global list
