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
# Le MEME lanceur dans le menu Demarrer, la ou mene la recherche Windows. Une
# ancienne entree y pointait sur graphify-kb\kb\ECU.bat, morte depuis le
# deplacement du 22/09 : taper « ECU » dans la recherche ouvrait un raccourci
# casse. Elle est desormais posee et tenue a jour ici, avec celle du Bureau.
$cibleMenu = Join-Path ([Environment]::GetFolderPath('Programs')) $nom
# Entree de demarrage : elle ne lance QUE le serveur, sans fenetre ni calcul.
# Sans elle, l'application epinglee a la barre des taches ouvre Chrome sans
# serveur, et la PWA se charge depuis son cache — hors ligne, a chaque fois.
# ASCII pur, tiret simple : PowerShell 5.1 lit un .ps1 sans BOM comme de
# l'ANSI, et un tiret cadratin y ressort en « â€” » — dans le NOM DU FICHIER,
# pas seulement a l'ecran. Constate le 22/09/2026.
$nomSrv   = 'ECU - serveur.lnk'
$cibleSrv = Join-Path ([Environment]::GetFolderPath('Startup')) $nomSrv
$nomTache  = 'ECU - serveur'

if ($Retirer) {
    foreach ($c in @($cible, $cibleMenu, $cibleSrv)) {
        if (Test-Path $c) { Remove-Item $c -Force; Write-Output "  retire  $c" }
    }
    if (Get-ScheduledTask -TaskName $nomTache -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $nomTache -Confirm:$false
        Write-Output "  retire  tache planifiee '$nomTache'"
    }
    if (-not ((Test-Path $cible) -or (Test-Path $cibleMenu) -or (Test-Path $cibleSrv))) { Write-Output '  plus aucun raccourci ECU' }
    Write-Output ''
    return
}

if ($Demarrage) {
    $vbsSrv = Join-Path $Kb 'ecu-serveur-silencieux.vbs'
    if (-not (Test-Path $vbsSrv)) { throw "Fichier introuvable : $vbsSrv" }

    # UNE TACHE PLANIFIEE, PAS UN RACCOURCI DANS LE DOSSIER DEMARRAGE. La
    # premiere version posait un raccourci « Demarrage » : il ne joue qu'a
    # l'ouverture de session, et le 23/09/2026 la machine tournait sans
    # redemarrer depuis une semaine — il n'avait donc jamais servi. Pendant ce
    # temps, les trois icones de l'application installee (Bureau, menu
    # Demarrer, barre des taches) l'ouvraient sans serveur, hors ligne.
    #
    # La tache s'execute a l'ouverture de session PUIS toutes les 10 minutes.
    # ECU.ps1 -Serveur ne fait rien si le serveur tourne deja : la repetition
    # ne coute qu'un test de port, et elle releve le serveur s'il est tombe.
    # Lancee par le Planificateur de taches, elle vit hors de toute session
    # Claude — un serveur demarre depuis une session meurt avec elle.
    $moi       = "$env:USERDOMAIN\$env:USERNAME"
    $action    = New-ScheduledTaskAction -Execute (Join-Path $env:SystemRoot 'System32\wscript.exe') `
                   -Argument ('"' + $vbsSrv + '"') -WorkingDirectory $Kb
    # DEUX declencheurs. Une repetition accrochee au seul declencheur « ouverture
    # de session » ne demarre qu'a la PROCHAINE ouverture — le premier essai
    # affichait « prochain lancement : aucun » sur une machine qui ne redemarre
    # pas d'une semaine. La repetition vit donc sur un declencheur horaire qui
    # part tout de suite, et l'ouverture de session garde le sien pour relever
    # le serveur sans attendre dix minutes apres un redemarrage.
    $trigger   = @(
        (New-ScheduledTaskTrigger -AtLogOn -User $moi),
        (New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes 10))
    )
    $reglages  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
                   -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 5)
    $principal = New-ScheduledTaskPrincipal -UserId $moi -LogonType Interactive -RunLevel Limited
    Register-ScheduledTask -TaskName $nomTache -Action $action -Trigger $trigger -Settings $reglages `
        -Principal $principal -Force `
        -Description 'Garde le serveur local d ECU en marche : ouverture de session, puis toutes les 10 min.' | Out-Null
    Write-Output "  cree    tache planifiee '$nomTache' (ouverture de session + toutes les 10 min)"

    # L'ancien raccourci du dossier Demarrage fait desormais double emploi.
    if (Test-Path $cibleSrv) { Remove-Item $cibleSrv -Force; Write-Output "  retire  $cibleSrv (remplace par la tache)" }

    Start-ScheduledTask -TaskName $nomTache
    Write-Output '  tache declenchee : le serveur demarre maintenant, hors de toute session.'
    Write-Output ''
    Write-Output '  Toutes les icones ECU fonctionnent desormais, epinglee comprise.'
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
foreach ($c in @($cible, $cibleMenu)) {
    $r = $shell.CreateShortcut($c)
    $r.TargetPath       = Join-Path $env:SystemRoot 'System32\wscript.exe'
    $r.Arguments        = '"' + $vbs + '"'
    $r.WorkingDirectory = $Kb
    $r.IconLocation     = $icone + ',0'
    $r.Description      = 'ECU - reseau de connaissance des projets Bony auto-mobile'
    $r.Save()
    Write-Output "  cree    $c"
}

Write-Output ''
Write-Output '  Double-clic : ECU s''ouvre tout de suite, sans console.'
Write-Output '  Le graphe se met a jour derriere ; la fenetre proposera de recharger.'
Write-Output ''
