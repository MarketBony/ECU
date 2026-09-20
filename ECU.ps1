# ECU — Engine Control Unit
# Lance le reseau de connaissance Bony dans sa propre fenetre.
#
#   .\ECU.ps1              rafraichit le code des projets puis ouvre ECU
#   .\ECU.ps1 -Vite        ouvre ECU tel quel
#   .\ECU.ps1 -Arreter     arrete le serveur local
#
# Un service worker (donc une PWA installable) exige http:// — file:// ne suffit
# pas. On sert donc le dossier sur 127.0.0.1 et Chrome l'ouvre en mode app.

param([switch]$Vite, [switch]$Arreter)

$ErrorActionPreference = 'Continue'
$env:PATH = "$env:USERPROFILE\.local\bin;$env:PATH"

$Kb   = Split-Path -Parent $MyInvocation.MyCommand.Path
$Root = Split-Path -Parent $Kb
$Ecu  = Join-Path $Kb 'ecu'
$Py   = Join-Path $env:APPDATA 'uv\tools\graphifyy\Scripts\python.exe'
$Port = 7420
$Url  = "http://127.0.0.1:$Port/index.html"
$PidF = Join-Path $env:TEMP 'ecu-serveur.pid'

function Fin($code) {
    if ($code -ne 0) { Write-Host ''; Read-Host '  Une erreur est survenue. Entree pour fermer' }
    exit $code
}

function Serveur-Actif {
    try { return [bool](Test-NetConnection -ComputerName 127.0.0.1 -Port $Port -InformationLevel Quiet -WarningAction SilentlyContinue) }
    catch {
        $c = New-Object Net.Sockets.TcpClient
        try { $c.Connect('127.0.0.1', $Port); $c.Close(); return $true } catch { return $false }
    }
}

function Arreter-Serveur {
    if (Test-Path $PidF) {
        $id = Get-Content $PidF -ErrorAction SilentlyContinue
        if ($id) { Stop-Process -Id $id -Force -ErrorAction SilentlyContinue }
        Remove-Item $PidF -Force -ErrorAction SilentlyContinue
    }
    Write-Host '  Serveur ECU arrete.' -ForegroundColor Yellow
}

function Get-Navigateur {
    $c = @(
        "$env:ProgramFiles\Google\Chrome\Application\chrome.exe",
        "${env:ProgramFiles(x86)}\Google\Chrome\Application\chrome.exe",
        "$env:LOCALAPPDATA\Google\Chrome\Application\chrome.exe",
        "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe",
        "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
    )
    foreach ($p in $c) { if (Test-Path $p) { return $p } }
    return $null
}

if ($Arreter) { Arreter-Serveur; exit 0 }

Write-Host ''
Write-Host '   ECU  ' -ForegroundColor White -NoNewline
Write-Host 'Engine Control Unit' -ForegroundColor DarkGray
Write-Host '   reseau de connaissance Bony' -ForegroundColor DarkGray
Write-Host ''

if (-not (Test-Path $Ecu)) { Write-Host "  Dossier ECU introuvable : $Ecu" -ForegroundColor Red; Fin 1 }

# ── 1. rafraichir le graphe (gratuit, aucun LLM) ──
if (-not $Vite) {
    . (Join-Path $Kb 'projets.ps1')
    foreach ($p in $global:ProjetsBony) {
        Write-Host ("   maj  {0,-14}" -f $p.Tag) -NoNewline
        if (-not (Test-Path $p.Chemin)) { Write-Host 'dossier absent' -ForegroundColor Red; continue }
        graphify update $p.Chemin *>$null
        $g = Join-Path $p.Chemin 'graphify-out\graph.json'
        if (Test-Path $g) { graphify global add $g --as $p.Tag *>$null; Write-Host 'ok' -ForegroundColor Green }
        else { Write-Host 'pas indexe' -ForegroundColor DarkYellow }
    }
    Write-Host '   disposition 3D...' -NoNewline
    & $Py (Join-Path $Root '_layout3d.py') *>$null
    if ($LASTEXITCODE -ne 0) { Write-Host ' echec' -ForegroundColor Red; Fin 1 }
    Write-Host ' ok' -ForegroundColor Green
}

# ── 2. serveur local ──
if (Serveur-Actif) {
    Write-Host "   serveur deja actif sur $Port" -ForegroundColor DarkGray
} else {
    Write-Host '   demarrage du serveur...' -NoNewline
    $p = Start-Process -FilePath $Py `
        -ArgumentList @('-m', 'http.server', "$Port", '--bind', '127.0.0.1', '--directory', "`"$Ecu`"") `
        -WindowStyle Hidden -PassThru
    $p.Id | Out-File $PidF -Encoding ascii
    $n = 0
    while (-not (Serveur-Actif) -and $n -lt 40) { Start-Sleep -Milliseconds 120; $n++ }
    if (Serveur-Actif) { Write-Host ' ok' -ForegroundColor Green }
    else { Write-Host ' echec' -ForegroundColor Red; Fin 1 }
}

# ── 3. fenetre applicative ──
$nav = Get-Navigateur
if (-not $nav) { Write-Host '  Aucun navigateur Chromium trouve.' -ForegroundColor Red; Fin 1 }

Write-Host "   ouverture : $Url" -ForegroundColor Cyan
Start-Process -FilePath $nav -ArgumentList @(
    "--app=$Url",
    '--window-size=1600,980',
    '--disable-features=Translate'
)
Write-Host ''
Write-Host '   Pour installer ECU comme application : dans la fenetre,' -ForegroundColor DarkGray
Write-Host '   menu ... > Ouvrir dans Chrome > icone d installation dans la barre d adresse.' -ForegroundColor DarkGray
Write-Host ''
Start-Sleep -Milliseconds 1200
