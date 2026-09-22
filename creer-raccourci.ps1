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
param([switch]$Retirer)

$ErrorActionPreference = 'Stop'

$Kb  = $PSScriptRoot
$nom = 'ECU.lnk'
$cible = Join-Path ([Environment]::GetFolderPath('Desktop')) $nom

if ($Retirer) {
    if (Test-Path $cible) { Remove-Item $cible -Force; Write-Output "  retire  $cible" }
    else { Write-Output '  aucun raccourci a retirer' }
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
$r.Description      = 'ECU — reseau de connaissance des projets Bony auto-mobile'
$r.Save()
Write-Output "  cree    $cible"

Write-Output ''
Write-Output '  Double-clic : ECU s''ouvre tout de suite, sans console.'
Write-Output '  Le graphe se met a jour derriere ; la fenetre proposera de recharger.'
Write-Output ''
