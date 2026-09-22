' =====================================================================
'  ecu-silencieux.vbs — enveloppe de trois lignes autour d'ECU.ps1,
'  appelee par le raccourci « ECU ».
'
'  POURQUOI ELLE EXISTE. Un raccourci qui pointe directement sur
'  powershell.exe fait clignoter une console noire au demarrage, meme
'  avec -WindowStyle Hidden : l'hote console est cree avant que le
'  script puisse se cacher. Le raccourci d'ECU etait en style « reduite »
'  pour masquer ca, ce qui ne faisait que la mettre dans la barre des
'  taches. wscript.exe, lui, lance le processus avec un style de fenetre
'  0 des le depart. Rien ne clignote, rien n'apparait.
'
'  Repris de APP FORUM\scripts\badges-silencieux.vbs, ou le meme
'  probleme avait deja ete resolu de cette maniere.
'
'  -Silencieux previent ECU.ps1 qu'il n'a pas de console : en cas
'  d'erreur il ouvre une boite de dialogue au lieu d'attendre une touche
'  que personne ne pourrait taper.
'
'  Le troisieme argument False veut dire : ne pas attendre la fin.
'  wscript rend la main tout de suite ; ECU.ps1 ouvre la fenetre puis
'  lance le rafraichissement en tache de fond.
' =====================================================================

Dim shell, dossier, commande
Set shell = CreateObject("WScript.Shell")

' Le dossier kb\, deduit du chemin de ce fichier : le raccourci continue
' de marcher si le projet est deplace ailleurs.
dossier = Left(WScript.ScriptFullName, InStrRev(WScript.ScriptFullName, "\"))

commande = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ _
         & dossier & "ECU.ps1"" -Silencieux"

shell.Run commande, 0, False
