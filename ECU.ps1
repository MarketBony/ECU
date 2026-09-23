# ECU — Engine Control Unit
# Lance le reseau de connaissance Bony dans sa propre fenetre.
#
#   .\ECU.ps1              ouvre ECU tout de suite, rafraichit derriere
#   .\ECU.ps1 -Vite        ouvre ECU sans rien rafraichir du tout
#   .\ECU.ps1 -Rafraichir  met le graphe a jour, sans ouvrir de fenetre
#   .\ECU.ps1 -Serveur     demarre le serveur seul, sans ouvrir de fenetre
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

param([switch]$Vite, [switch]$Arreter, [switch]$Rafraichir, [switch]$Serveur, [switch]$Silencieux)

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

# Un serveur deja en place peut dater d'avant tools\serveur.py, donc servir sans
# Cache-Control — et le navigateur reprend alors ses copies perimees. On le
# reconnait a son absence d'en-tete et on le remplace, plutot que de laisser
# trainer une session qui affichera un graphe faux jusqu'au prochain redemarrage.
function Serveur-Conforme {
    try {
        $r = Invoke-WebRequest "http://127.0.0.1:$Port/version.json" `
             -UseBasicParsing -TimeoutSec 3 -ErrorAction Stop
        return ([string]$r.Headers['Cache-Control'] -match 'no-cache')
    } catch { return $false }
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
        Where-Object { $_.CommandLine -match 'http\.server|serveur\.py' -and $_.CommandLine -match "\b$Port\b" } |
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
# A l'installation, Chrome pose lui-meme un raccourci dans « Chrome Apps » qui
# porte le bon --app-id et le bon profil. Le lancer, c'est obtenir l'icone ECU ;
# passer par « --app=<url> » comme avant, c'est rester groupe sous Chrome.
#
# LE NOM DE CE DOSSIER DEPEND DE LA LANGUE : « Chrome Apps » en anglais,
# « Applications Chrome » en francais. La premiere version ne cherchait que le
# nom anglais : elle n'a jamais vu l'application, pourtant installee le 22/09 a
# 12:08. ECU.ps1 affichait donc « pas encore installe » a chaque lancement et
# ouvrait une fenetre --app= rangee sous l'icone Chrome. On reconnait desormais
# le raccourci a ce qu'il FAIT (il porte --app-id=), pas a l'endroit ou il est.
function Raccourci-Pwa {
    $menu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
    $sh = New-Object -ComObject WScript.Shell
    return Get-ChildItem $menu -Recurse -Filter '*.lnk' -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match 'ECU' -and $sh.CreateShortcut($_.FullName).Arguments -match '--app-id=' } |
        Select-Object -First 1
}

# UNE seule facon de demarrer le serveur, appelee par le lancement normal comme
# par le mode -Serveur du demarrage de session. Deux copies de cette logique
# auraient divergé le jour ou l'une des deux apprend quelque chose — c'est
# exactement ce qui est arrive avec la liste des projets de _layout3d.py.
function Demarrer-Serveur {
    if ((Serveur-Actif) -and -not (Serveur-Conforme)) {
        Write-Host '   serveur obsolete (sans Cache-Control), remplacement...' -ForegroundColor DarkYellow
        Arreter-Serveur | Out-Null
        Start-Sleep -Milliseconds 400
    }
    if (Serveur-Actif) {
        Write-Host "   serveur deja actif sur $Port" -ForegroundColor DarkGray
        return $true
    }
    Write-Host '   demarrage du serveur...' -NoNewline
    $p = Start-Process -FilePath $Py `
        -ArgumentList @((Join-Path $Kb 'tools\serveur.py'), "`"$Ecu`"", "$Port") `
        -WindowStyle Hidden -PassThru
    $p.Id | Out-File $PidF -Encoding ascii
    $n = 0
    while (-not (Serveur-Actif) -and $n -lt 40) { Start-Sleep -Milliseconds 120; $n++ }
    if (Serveur-Actif) { Write-Host ' ok' -ForegroundColor Green; return $true }
    Write-Host ' echec' -ForegroundColor Red
    Fin 1 "Le serveur local n a pas demarre sur le port $Port."
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

    # La copie de global-graph.json dans ce depot est la SEULE sauvegarde des
    # noeuds issus des documents : graphify-out/ est exclu de git dans les cinq
    # projets. Elle n'etait rafraichie que par rebuild.ps1, et le 23/09/2026 on
    # a decouvert qu'elle datait de trois jours — sans ECU, sans Limagrain, sans
    # les 185 000 tokens de la derniere passe. On la tient donc a jour ici, a
    # chaque rafraichissement. La COMMITER reste un geste delibere : apres une
    # passe documents, pas apres chaque push (voir NOUVEAU-PROJET-BONY.md).
    Copy-Item (Join-Path $env:USERPROFILE '.graphify\global-graph.json') `
              (Join-Path $Kb 'global-graph.json') -Force -ErrorAction SilentlyContinue

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

# ── mode serveur seul ──
# Pose au demarrage de session par creer-raccourci.ps1 -Demarrage. Sans lui,
# cliquer l'application EPINGLEE ouvre Chrome sans demarrer le serveur : la PWA
# se charge alors depuis son cache, hors ligne, a chaque fois. L'icone ECU du
# Bureau, elle, continue de tout faire (serveur + fenetre + rafraichissement).
if ($Serveur) {
    if (-not $Py) { exit 1 }
    Demarrer-Serveur | Out-Null
    exit 0
}

# ── 1. serveur local ──
Demarrer-Serveur | Out-Null

# ── 2. fenetre applicative, TOUT DE SUITE ──
$nav = Get-Navigateur
if (-not $nav) { Write-Host '  Aucun navigateur Chromium trouve.' -ForegroundColor Red; Fin 1 'Aucun navigateur Chromium trouve (Chrome ou Edge).' }

$pwa = Raccourci-Pwa
if ($pwa) {
    Write-Host '   ouverture : application installee' -ForegroundColor Cyan
    Start-Process -FilePath $pwa.FullName
} else {
    Write-Host "   ouverture : $Url" -ForegroundColor Cyan
    Start-Process -FilePath $nav -ArgumentList @(
        "--app=$Url",
        '--window-size=1600,980',
        '--disable-features=Translate'
    )
}

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

if (-not $pwa) {
    Write-Host ''
    Write-Host '   Pas encore installe : la fenetre affiche un bouton "Installer ECU' -ForegroundColor DarkGray
    Write-Host '   comme application" en bas de la colonne de gauche. Un clic, une' -ForegroundColor DarkGray
    Write-Host '   seule fois, et la barre des taches montrera le logo ECU au lieu de' -ForegroundColor DarkGray
    Write-Host '   celui de Chrome.' -ForegroundColor DarkGray
}
Write-Host ''
Start-Sleep -Milliseconds 900
