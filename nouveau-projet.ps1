# Branche un nouveau projet Bony sur le reseau de connaissance.
#
#   .\nouveau-projet.ps1 "C:\Users\Operateur\Documents\MON-PROJET"
#   .\nouveau-projet.ps1 "C:\...\MON-PROJET" -Tag mon-depot
#
# Fait, dans l'ordre :
#   1. indexe le code (AST local, gratuit, aucun token)
#   2. installe la skill Claude Code + les hooks git du depot
#   3. enregistre le projet dans le graphe global
#   4. l'ajoute a projets.ps1 pour que la carte le reprenne
#
# La passe DOCUMENTS n'est pas faite ici : elle coute des tokens. Pour la lancer,
# ouvre Claude Code dans le dossier du projet et tape :  /graphify .

param(
    [Parameter(Mandatory = $true)][string]$Chemin,
    [string]$Tag
)

$ErrorActionPreference = 'Continue'
$env:PATH = "$env:USERPROFILE\.local\bin;$env:PATH"

$Kb = Split-Path -Parent $MyInvocation.MyCommand.Path
$Fichier = Join-Path $Kb 'projets.ps1'

function Fin($code) {
    if ($code -ne 0) { Write-Host ''; Read-Host '  Entree pour fermer' }
    exit $code
}

$Chemin = $Chemin.TrimEnd('\')
if (-not (Test-Path $Chemin)) { Write-Host "  Dossier introuvable : $Chemin" -ForegroundColor Red; Fin 1 }
if (-not $Tag) { $Tag = Split-Path $Chemin -Leaf }

# Si c'est un depot git, prefere le nom du depot GitHub comme tag
$remote = git -C $Chemin remote get-url origin 2>$null
if ($remote -and -not $PSBoundParameters.ContainsKey('Tag')) {
    $Tag = [IO.Path]::GetFileNameWithoutExtension(($remote -split '/')[-1])
}

Write-Host ''
Write-Host "  Nouveau projet : $Tag" -ForegroundColor Cyan
Write-Host "  $Chemin" -ForegroundColor DarkGray
if ($remote) { Write-Host "  depot : $remote" -ForegroundColor DarkGray }
else { Write-Host '  (aucun remote git — le projet sera indexe localement)' -ForegroundColor DarkYellow }
Write-Host ''

Write-Host '  1/4  indexation du code (gratuit)...' -NoNewline
graphify extract $Chemin --code-only *>$null
if ($LASTEXITCODE -ne 0) { Write-Host ' echec' -ForegroundColor Red; Fin 1 }
graphify cluster-only $Chemin --no-label *>$null
Write-Host ' ok' -ForegroundColor Green

Write-Host '  2/4  skill Claude Code + hooks git...' -NoNewline
Push-Location $Chemin
graphify claude install *>$null
if (Test-Path (Join-Path $Chemin '.git')) { graphify hook install *>$null }
Pop-Location
Write-Host ' ok' -ForegroundColor Green

Write-Host '  3/4  enregistrement dans le graphe global...' -NoNewline
graphify global add (Join-Path $Chemin 'graphify-out\graph.json') --as $Tag *>$null
Write-Host ' ok' -ForegroundColor Green

Write-Host '  4/4  ajout a projets.ps1...' -NoNewline
$txt = Get-Content $Fichier -Raw
if ($txt -match [regex]::Escape($Chemin)) {
    Write-Host ' deja present' -ForegroundColor DarkYellow
} else {
    $ligne = "    @{{ Tag = '{0}'; Chemin = '{1}' }}" -f $Tag, $Chemin
    $txt = $txt -replace "(?s)(\r?\n\)\s*)$", ",`r`n$ligne`r`n)`r`n"
    Set-Content $Fichier $txt -Encoding UTF8
    Write-Host ' ok' -ForegroundColor Green
}

Write-Host ''
graphify global list
Write-Host ''
Write-Host '  A partir de maintenant, chaque commit dans ce depot met le reseau a jour.' -ForegroundColor Green
Write-Host '  Pour y ajouter aussi les documents (README, CLAUDE.md, PDF...) :' -ForegroundColor DarkGray
Write-Host '    ouvre Claude Code dans le dossier et tape  /graphify .' -ForegroundColor DarkGray
Write-Host ''
