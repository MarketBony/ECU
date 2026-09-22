' =====================================================================
'  ecu-serveur-silencieux.vbs — demarre le SERVEUR d'ECU, rien d'autre.
'  Pose dans le dossier Demarrage par creer-raccourci.ps1 -Demarrage.
'
'  POURQUOI IL EXISTE. Une fois ECU installe comme application et
'  epingle a la barre des taches, cliquer cette icone ouvre Chrome
'  directement — sans passer par ECU.ps1, donc sans demarrer le serveur
'  local. Le service worker sert alors l'application depuis son cache :
'  elle s'affiche parfaitement, avec les donnees de la derniere fois.
'  Ce fichier garantit qu'un serveur ecoute des l'ouverture de session,
'  pour que l'icone epinglee marche comme une vraie application.
'
'  Il n'ouvre AUCUNE fenetre et ne rafraichit RIEN : le graphe se met a
'  jour quand on lance ECU par son icone du Bureau, pas au demarrage de
'  la machine — personne ne veut deux minutes de calcul au logon.
'
'  wscript.exe plutot que powershell.exe : voir l'en-tete de
'  ecu-silencieux.vbs, c'est la meme raison (aucune console qui clignote).
' =====================================================================

Dim shell, dossier, commande
Set shell = CreateObject("WScript.Shell")

dossier = Left(WScript.ScriptFullName, InStrRev(WScript.ScriptFullName, "\"))

commande = "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ _
         & dossier & "ECU.ps1"" -Serveur -Silencieux"

shell.Run commande, 0, False
