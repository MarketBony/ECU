# Branche un nouveau projet Bony sur le reseau de connaissance ECU.
#
#   .\nouveau-projet.ps1 "C:\Users\Operateur\Documents\MON-PROJET"
#   .\nouveau-projet.ps1 "C:\...\MON-PROJET" -Github          # cree aussi le depot prive
#   .\nouveau-projet.ps1 "C:\...\MON-PROJET" -Tag mon-depot   # force le nom dans le graphe
#
# Fait, dans l'ordre :
#   1. (option -Github) cree le depot PRIVE MarketBony/<tag> et pousse
#   2. indexe le code (AST local, gratuit, aucun token)
#   3. installe la skill Claude Code + les hooks git du depot
#   4. re-epingle l'interpreteur des hooks sur son chemin REEL
#   5. enregistre le projet dans le graphe global
#   6. l'ajoute a projets.ps1 pour qu'ECU le reprenne
#   7. recalcule la disposition 3D
#
# La passe DOCUMENTS n'est pas faite ici : elle coute des tokens. Pour la lancer,
# ouvrir Claude Code dans le dossier du projet et taper :  /graphify .

param(
    [Parameter(Mandatory = $true)][string]$Chemin,
    [string]$Tag,
    [switch]$Github,
    [switch]$SansCarte
)

$ErrorActionPreference = 'Continue'
$env:PATH = "$env:USERPROFILE\.local\bin;$env:PATH"

$Kb   = Split-Path -Parent $MyInvocation.MyCommand.Path
$Fichier = Join-Path $Kb 'projets.ps1'
. (Join-Path $Kb 'python.ps1')
$Py = Get-PythonECU

function Fin($code) {
    if ($code -ne 0) { Write-Host ''; Read-Host '  Entree pour fermer' }
    exit $code
}

$Chemin = $Chemin.TrimEnd('\')
if (-not (Test-Path $Chemin)) { Write-Host "  Dossier introuvable : $Chemin" -ForegroundColor Red; Fin 1 }
if (-not $Py) {
    Write-Host '  Python porteur de graphify introuvable.' -ForegroundColor Red
    Write-Host '  Reinstalle avec :  uv tool install "graphifyy[all]"' -ForegroundColor DarkGray
    Fin 1
}

if (-not $Tag) { $Tag = Split-Path $Chemin -Leaf }
$remote = git -C $Chemin remote get-url origin 2>$null
if ($remote -and -not $PSBoundParameters.ContainsKey('Tag')) {
    $Tag = [IO.Path]::GetFileNameWithoutExtension(($remote -split '/')[-1])
}

Write-Host ''
Write-Host "  Nouveau projet ECU : $Tag" -ForegroundColor Cyan
Write-Host "  $Chemin" -ForegroundColor DarkGray
Write-Host ''

# ─── 1. depot GitHub prive ────────────────────────────────────────────────────
if ($Github) {
    if ($remote) {
        Write-Host "  1/7  depot deja lie : $remote" -ForegroundColor DarkYellow
    } else {
        Write-Host '  1/7  creation du depot prive...' -NoNewline
        if (-not (Test-Path (Join-Path $Chemin '.git'))) {
            git -C $Chemin init -q
            git -C $Chemin add -A
            git -C $Chemin -c user.email="romane.chambon@bonyauto-mobile.com" `
                -c user.name="Romane Chambon" commit -q -m "Premier commit" 2>$null
        }
        Push-Location $Chemin
        gh repo create "MarketBony/$Tag" --private --source=. --remote=origin --push 2>&1 | Select-Object -Last 1
        Pop-Location
        if ($LASTEXITCODE -eq 0) { Write-Host '  ok' -ForegroundColor Green }
        else { Write-Host '  echec — verifie `gh auth status`' -ForegroundColor Red }
    }
} else {
    Write-Host '  1/7  depot GitHub : ignore (ajoute -Github pour le creer)' -ForegroundColor DarkGray
}

# ─── 2. indexation du code ────────────────────────────────────────────────────
Write-Host '  2/7  indexation du code (gratuit)...' -NoNewline
graphify extract $Chemin --code-only *>$null
if ($LASTEXITCODE -ne 0) { Write-Host ' echec' -ForegroundColor Red; Fin 1 }
graphify cluster-only $Chemin --no-label *>$null
Write-Host ' ok' -ForegroundColor Green

# ─── 3. skill Claude Code + hooks git ─────────────────────────────────────────
Write-Host '  3/7  skill Claude Code + hooks git...' -NoNewline
Push-Location $Chemin
graphify claude install *>$null
if (Test-Path (Join-Path $Chemin '.git')) { graphify hook install *>$null }
Pop-Location
Write-Host ' ok' -ForegroundColor Green

# ─── 4. re-epinglage de l'interpreteur ────────────────────────────────────────
# `graphify hook install` inscrit dans le hook le chemin de l'interpreteur TEL
# QU'IL LE VOIT. Lance depuis l'application Claude, dont le bac a sable
# virtualise %APPDATA%, il inscrit un chemin qui n'existe pas depuis un vrai
# terminal — et le hook echoue silencieusement a chaque commit.
Write-Host '  4/7  re-epinglage de l interpreteur...' -NoNewline
$reel = $Py
foreach ($h in @('post-commit', 'post-checkout')) {
    $f = Join-Path $Chemin ".git\hooks\$h"
    if (Test-Path $f) {
        $t = Get-Content $f -Raw
        $t = [regex]::Replace($t, "_PINNED='[^']*'", { "_PINNED='" + $reel + "'" })
        [System.IO.File]::WriteAllText($f, $t, (New-Object System.Text.UTF8Encoding $false))
    }
}
$out = Join-Path $Chemin 'graphify-out'
if (Test-Path $out) {
    [System.IO.File]::WriteAllText((Join-Path $out '.graphify_python'), $reel,
        (New-Object System.Text.UTF8Encoding $false))
}
Write-Host ' ok' -ForegroundColor Green

# ─── 5. graphe global ─────────────────────────────────────────────────────────
Write-Host '  5/7  enregistrement dans le graphe global...' -NoNewline
graphify global add (Join-Path $Chemin 'graphify-out\graph.json') --as $Tag *>$null
Write-Host ' ok' -ForegroundColor Green

# ─── 6. projets.ps1 ───────────────────────────────────────────────────────────
Write-Host '  6/7  ajout a projets.ps1...' -NoNewline
# -Encoding UTF8 est obligatoire : sans lui, PowerShell 5.1 lit un fichier UTF-8
# sans BOM comme de l'ANSI et recrache les accents en mojibake a la reecriture.
$txt = Get-Content $Fichier -Raw -Encoding UTF8
if ($txt -match [regex]::Escape($Chemin)) {
    Write-Host ' deja present' -ForegroundColor DarkYellow
} else {
    $ligne = "    @{ Tag = '$Tag'; Chemin = '$Chemin' }"
    $txt = $txt -replace "(?s)\r?\n\)\s*$", ",`r`n$ligne`r`n)`r`n"
    [System.IO.File]::WriteAllText($Fichier, $txt, (New-Object System.Text.UTF8Encoding $true))
    Write-Host ' ok' -ForegroundColor Green
}

# ─── 7. disposition 3D ────────────────────────────────────────────────────────
if ($SansCarte) {
    Write-Host '  7/7  disposition 3D : ignoree' -ForegroundColor DarkGray
} else {
    Write-Host '  7/7  recalcul de la disposition 3D (~1 min)...' -NoNewline
    & $Py (Join-Path $Kb 'tools\_layout3d.py') --force *>$null
    if ($LASTEXITCODE -eq 0) { Write-Host ' ok' -ForegroundColor Green }
    else { Write-Host ' echec' -ForegroundColor Red }
}

Write-Host ''
graphify global list
Write-Host ''
Write-Host '  Chaque commit dans ce depot met desormais ECU a jour, gratuitement.' -ForegroundColor Green
Write-Host '  Pour y ajouter les documents (README, CLAUDE.md, PDF...) :' -ForegroundColor DarkGray
Write-Host '    ouvre Claude Code dans le dossier du projet et tape  /graphify .' -ForegroundColor DarkGray
Write-Host ''
