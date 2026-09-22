# Source unique de verite : les projets Bony qui alimentent le reseau.
# Pour ajouter un projet, ajoute une ligne ici — rien d'autre a modifier.
#
#   Tag    nom dans le graphe global (idealement = nom du depot GitHub)
#   Chemin le dossier de travail REEL sur cette machine

$global:ProjetsBony = @(
    @{ Tag = 'gearbox';    Chemin = 'C:\Users\Operateur\Documents\gearbox3backup' },
    @{ Tag = 'GRID';       Chemin = 'C:\Users\Operateur\Documents\RELTEL'         },
    @{ Tag = 'Forum-2026'; Chemin = 'C:\Users\Operateur\Documents\APP FORUM'      },
    @{ Tag = 'partenariat-bony-limagrain'; Chemin = 'C:\Users\Operateur\Documents\Partenariat Bony x Limagrain' }
)
