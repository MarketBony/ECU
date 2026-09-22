#requires -Version 5
# =====================================================================
#  creer-raccourci.ps1 — pose l'icone « ECU » sur le Bureau.
#
#  A lancer UNE FOIS. A relancer si le dossier du projet est deplace :
#  un raccourci Windows retient un chemin absolu.
#
#  Le raccourci pointe sur wscript.exe plutot que sur powershell.exe,
#  pour qu'aucune console n'apparaisse au demarrage — voir l'en-tete de
#  ecu-silencieux.vbs. C'est la meme mecanique que le raccourci des
#  badges du Forum, qui avait deja resolu ce probleme.
#
#    .\creer-raccourci.ps1
#    .\creer-raccourci.ps1 -Retirer      (enleve le raccourci)
#
#  POUR L'AVOIR DANS LA BARRE DES TACHES AVEC SON LOGO, ce raccourci ne
#  suffit pas : une fenetre « chrome --app= » reste groupee sous l'icone
#  de Chrome. Il faut installer ECU en application web, une seule fois —
#  ECU.ps1 affiche la marche a suivre tant que ce n'est pas fait.
# =====================================================================
param([switch]$Retirer, [switch]$Demarrage)

$ErrorActionPreference = 'Stop'

$Kb  = $PSScriptRoot
$nom = 'ECU.lnk'
$cible = Join-Path ([Environment]::GetFolderPath('Desktop')) $nom
# Entree de demarrage : elle ne lance QUE le serveur, sans fenetre ni calcul.
# Sans elle, l'application epinglee a la barre des taches ouvre Chrome sans
# serveur, et la PWA se charge depuis son cache — hors ligne, a chaque fois.
# ASCII pur, tiret simple : PowerShell 5.1 lit un .ps1 sans BOM comme de
# l'ANSI, et un tiret cadratin y ressort en « â€” » — dans le NOM DU FICHIER,
# pas seulement a l'ecran. Constate le 22/09/2026.
$nomSrv   = 'ECU - serveur.lnk'
$cibleSrv = Join-Path ([Environment]::GetFolderPath('Startup')) $nomSrv

if ($Retirer) {
    foreach ($c in @($cible, $cibleSrv)) {
        if (Test-Path $c) { Remove-Item $c -Force; Write-Output "  retire  $c" }
    }
    if (-not (Test-Path $cible) -and -not (Test-Path $cibleSrv)) { Write-Output '  plus aucun raccourci ECU' }
    Write-Output ''
    return
}

if ($Demarrage) {
    $vbsSrv = Join-Path $Kb 'ecu-serveur-silencieux.vbs'
    if (-not (Test-Path $vbsSrv)) { throw "Fichier introuvable : $vbsSrv" }
    $shell = New-Object -ComObject WScript.Shell
    $r = $shell.CreateShortcut($cibleSrv)
    $r.TargetPath       = Join-Path $env:SystemRoot 'System32\wscript.exe'
    $r.Arguments        = '"' + $vbsSrv + '"'
    $r.WorkingDirectory = $Kb
    $r.IconLocation     = (Join-Path $Kb 'ecu\ecu.ico') + ',0'
    $r.Description      = 'Demarre le serveur local d ECU a l ouverture de session'
    $r.Save()
    Write-Output "  cree    $cibleSrv"
    Write-Output ''
    Write-Output '  Le serveur ECU demarrera desormais a chaque ouverture de session.'
    Write-Output '  L''application epinglee fonctionnera donc sans passer par l''icone du Bureau.'
    Write-Output '  Pour l''enlever :  .\creer-raccourci.ps1 -Retirer'
    Write-Output ''
    return
}

$vbs   = Join-Path $Kb 'ecu-silencieux.vbs'
$icone = Join-Path $Kb 'ecu\ecu.ico'
foreach ($f in @($vbs, $icone)) {
    if (-not (Test-Path $f)) { throw "Fichier introuvable : $f" }
}

$shell = New-Object -ComObject WScript.Shell
$r = $shell.CreateShortcut($cible)
$r.TargetPath       = Join-Path $env:SystemRoot 'System32\wscript.exe'
$r.Arguments        = '"' + $vbs + '"'
$r.WorkingDirectory = $Kb
$r.IconLocation     = $icone + ',0'
$r.Description      = 'ECU - reseau de connaissance des projets Bony auto-mobile'
$r.Save()
Write-Output "  cree    $cible"

Write-Output ''
Write-Output '  Double-clic : ECU s''ouvre tout de suite, sans console.'
Write-Output '  Le graphe se met a jour derriere ; la fenetre proposera de recharger.'
Write-Output ''
