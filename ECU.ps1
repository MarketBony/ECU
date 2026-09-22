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

# Louvain parcourt des ensembles de chaines dont l'ordre depend du hachage, tire
# au sort a chaque processus : sans ca les communautes peuvent etre reattribuees
# d'une execution a l'autre. Le hook git post-commit le pose deja ; les scripts
# d'ECU doivent poser le meme, sinon les deux chemins ne calculent pas pareil.
$env:PYTHONHASHSEED = '0'

$Kb   = Split-Path -Parent $MyInvocation.MyCommand.Path
$Ecu  = Join-Path $Kb 'ecu'
. (Join-Path $Kb 'python.ps1')
$Py   = Get-PythonECU
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
    $tues = @()

    if (Test-Path $PidF) {
        $id = Get-Content $PidF -ErrorAction SilentlyContinue
        if ($id) { Stop-Process -Id $id -Force -ErrorAction SilentlyContinue; $tues += [int]$id }
        Remove-Item $PidF -Force -ErrorAction SilentlyContinue
    }

    # Le fichier PID ne connait qu'un serveur : celui du dernier demarrage. Deux
    # lancements rapproches (double-clic) en laissent d'autres derriere, que
    # « -Arreter » ne voyait pas — il en trainait deux depuis deux jours. On vise
    # donc aussi les processus qui servent reellement ce port, en verifiant leur
    # ligne de commande pour ne jamais tuer un voisin innocent.
    Get-CimInstance Win32_Process -Filter "Name like '%python%'" -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -match 'http\.server' -and $_.CommandLine -match "\b$Port\b" } |
        ForEach-Object {
            if ($tues -notcontains $_.ProcessId) {
                Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
                $tues += $_.ProcessId
            }
        }

    if ($tues.Count) { Write-Host ("  Serveur ECU arrete ({0} processus)." -f $tues.Count) -ForegroundColor Yellow }
    else            { Write-Host '  Aucun serveur ECU en cours.' -ForegroundColor DarkGray }
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
if (-not $Py) {
    Write-Host '  Python porteur de graphify introuvable.' -ForegroundColor Red
    Write-Host '  Reinstalle avec :  uv tool install "graphifyy[all]"' -ForegroundColor DarkGray
    Fin 1
}

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
    # La sortie du moteur est REEMISE, pas avalee. Un recalcul complet dure
    # ~2 min (210 iterations) et l'ancienne version affichait une ligne figee
    # sans rien d'autre : le 22/09/2026, un calcul parfaitement normal a ete
    # pris pour un plantage. Une attente longue doit se voir travailler.
    #
    #   -u  : sans lui, Python met sa sortie en tampon des qu'elle part dans un
    #         tuyau, et les 210 iterations arrivent toutes A LA FIN — ce qui
    #         supprime precisement ce qu'on cherche a montrer.
    #   pas de 2>&1 : sous PowerShell 5.1 il emballe chaque ligne d'erreur d'un
    #         executable natif dans un NativeCommandError. On laisse donc stderr
    #         filer vers la console, ou il reste visible.
    Write-Host '   disposition 3D' -NoNewline
    Write-Host '   (recalcul complet ~2 min si le graphe a change)' -ForegroundColor DarkGray
    & $Py -u (Join-Path $Kb 'tools\_layout3d.py') |
        ForEach-Object { Write-Host "      $_" -ForegroundColor DarkGray }
    if ($LASTEXITCODE -ne 0) { Write-Host '   disposition 3D : echec' -ForegroundColor Red; Fin 1 }
    Write-Host '   disposition 3D : ok' -ForegroundColor Green
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
