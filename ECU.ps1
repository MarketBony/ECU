# ECU — Engine Control Unit
# Lance le reseau de connaissance Bony dans sa propre fenetre.
#
#   .\ECU.ps1              ouvre ECU tout de suite, rafraichit derriere
#   .\ECU.ps1 -Vite        ouvre ECU sans rien rafraichir du tout
#   .\ECU.ps1 -Rafraichir  met le graphe a jour, sans ouvrir de fenetre
#   .\ECU.ps1 -Arreter     arrete le serveur local
#
# Un service worker (donc une PWA installable) exige http:// — file:// ne suffit
# pas. On sert donc le dossier sur 127.0.0.1 et Chrome l'ouvre en mode app.
#
# POURQUOI L'OUVERTURE EST IMMEDIATE. Jusqu'au 22/09/2026, le lanceur
# rafraichissait AVANT d'ouvrir : jusqu'a deux minutes d'ecran vide. Une
# application s'ouvre tout de suite. On affiche donc le dernier etat connu, le
# rafraichissement tourne en tache de fond, et la page propose de se recharger
# quand les nouvelles donnees sont pretes (elle sonde ecu/version.json).

param([switch]$Vite, [switch]$Arreter, [switch]$Rafraichir, [switch]$Silencieux)

$ErrorActionPreference = 'Continue'
$env:PATH = "$env:USERPROFILE\.local\bin;$env:PATH"

# Louvain parcourt des ensembles de chaines dont l'ordre depend du hachage, tire
# au sort a chaque processus : sans ca les communautes peuvent etre reattribuees
# d'une execution a l'autre. Le hook git post-commit le pose deja ; les scripts
# d'ECU doivent poser le meme, sinon les deux chemins ne calculent pas pareil.
$env:PYTHONHASHSEED = '0'

$Moi  = $MyInvocation.MyCommand.Path
$Kb   = Split-Path -Parent $Moi
$Ecu  = Join-Path $Kb 'ecu'
. (Join-Path $Kb 'python.ps1')
$Py   = Get-PythonECU
$Port = 7420
$Url  = "http://127.0.0.1:$Port/index.html"
$PidF = Join-Path $env:TEMP 'ecu-serveur.pid'
$LockF = Join-Path $env:TEMP 'ecu-rafraichissement.pid'
$Journal = Join-Path $env:USERPROFILE '.cache\ecu-rafraichissement.log'

function Fin($code, $message) {
    if ($code -ne 0) {
        # Lance depuis le raccourci, ce script n'a aucune console : un Read-Host
        # y attendrait une touche que personne ne peut taper, et le processus
        # resterait bloque, invisible, pour toujours. On montre donc une boite
        # de dialogue — c'est le seul endroit ou l'erreur peut etre lue.
        if ($Silencieux) {
            $txt = if ($message) { $message } else { 'ECU n a pas pu demarrer.' }
            (New-Object -ComObject WScript.Shell).Popup($txt, 0, 'ECU', 16) | Out-Null
        } else {
            Write-Host ''
            Read-Host '  Une erreur est survenue. Entree pour fermer'
        }
    }
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

# Chrome ne donne une identite propre a une application web — sa propre icone
# dans la barre des taches, hors du groupe Chrome — que si elle est INSTALLEE.
# Tant qu'elle ne l'est pas, on rappelle comment faire ; ensuite on se tait.
function Pwa-Installee {
    $d = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Chrome Apps'
    return [bool](Get-ChildItem $d -Filter '*ECU*' -ErrorAction SilentlyContinue)
}

function Rafraichissement-Actif {
    if (-not (Test-Path $LockF)) { return $false }
    $id = Get-Content $LockF -ErrorAction SilentlyContinue
    if (-not $id) { return $false }
    return [bool](Get-Process -Id ([int]$id) -ErrorAction SilentlyContinue)
}

function Rafraichir-Graphe {
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
    if ($LASTEXITCODE -ne 0) { Write-Host '   disposition 3D : echec' -ForegroundColor Red; return $false }
    Write-Host '   disposition 3D : ok' -ForegroundColor Green
    return $true
}

if ($Arreter) { Arreter-Serveur; exit 0 }

# ── mode sans fenetre : seulement mettre le graphe a jour ──
# C'est ce que le lancement normal relance en tache de fond. Comme personne ne
# regarde, la sortie part dans un journal : une panne silencieuse doit rester
# diagnosticable apres coup.
if ($Rafraichir) {
    if (Rafraichissement-Actif) { exit 0 }
    if (-not $Py) { exit 1 }
    $PID | Out-File $LockF -Encoding ascii
    New-Item -ItemType Directory -Force -Path (Split-Path $Journal) -ErrorAction SilentlyContinue | Out-Null
    try {
        Start-Transcript -Path $Journal -Force -ErrorAction SilentlyContinue | Out-Null
        $ok = Rafraichir-Graphe
        Stop-Transcript -ErrorAction SilentlyContinue | Out-Null
    } finally {
        Remove-Item $LockF -Force -ErrorAction SilentlyContinue
    }
    if ($ok) { exit 0 } else { exit 1 }
}

Write-Host ''
Write-Host '   ECU  ' -ForegroundColor White -NoNewline
Write-Host 'Engine Control Unit' -ForegroundColor DarkGray
Write-Host '   reseau de connaissance Bony' -ForegroundColor DarkGray
Write-Host ''

if (-not (Test-Path $Ecu)) { Write-Host "  Dossier ECU introuvable : $Ecu" -ForegroundColor Red; Fin 1 "Dossier ECU introuvable :`n$Ecu" }
if (-not $Py) {
    Write-Host '  Python porteur de graphify introuvable.' -ForegroundColor Red
    Write-Host '  Reinstalle avec :  uv tool install "graphifyy[all]"' -ForegroundColor DarkGray
    Fin 1 'Python porteur de graphify introuvable.`n`nReinstalle avec :  uv tool install "graphifyy[all]"'
}

# ── 1. serveur local ──
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
    else { Write-Host ' echec' -ForegroundColor Red; Fin 1 "Le serveur local n a pas demarre sur le port $Port." }
}

# ── 2. fenetre applicative, TOUT DE SUITE ──
$nav = Get-Navigateur
if (-not $nav) { Write-Host '  Aucun navigateur Chromium trouve.' -ForegroundColor Red; Fin 1 'Aucun navigateur Chromium trouve (Chrome ou Edge).' }

Write-Host "   ouverture : $Url" -ForegroundColor Cyan
Start-Process -FilePath $nav -ArgumentList @(
    "--app=$Url",
    '--window-size=1600,980',
    '--disable-features=Translate'
)

# ── 3. rafraichissement, derriere ──
if ($Vite) {
    Write-Host '   rafraichissement : ignore (-Vite)' -ForegroundColor DarkGray
} elseif (Rafraichissement-Actif) {
    Write-Host '   rafraichissement deja en cours' -ForegroundColor DarkGray
} else {
    Write-Host '   rafraichissement lance en arriere-plan' -ForegroundColor DarkGray
    Write-Host '   la fenetre proposera de recharger quand ce sera pret' -ForegroundColor DarkGray
    Start-Process -FilePath 'powershell.exe' -WindowStyle Hidden -ArgumentList @(
        '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$Moi`"", '-Rafraichir'
    )
}

if (-not (Pwa-Installee)) {
    Write-Host ''
    Write-Host '   Pour l avoir comme une vraie application (icone ECU dans la barre' -ForegroundColor DarkGray
    Write-Host '   des taches, hors du groupe Chrome) : dans la fenetre, menu ... >' -ForegroundColor DarkGray
    Write-Host '   Ouvrir dans Chrome > icone d installation dans la barre d adresse.' -ForegroundColor DarkGray
    Write-Host '   A faire une seule fois.' -ForegroundColor DarkGray
}
Write-Host ''
Start-Sleep -Milliseconds 900
