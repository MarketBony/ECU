# -*- coding: utf-8 -*-
"""Serveur local d'ECU : http.server, plus un en-tete qui change tout.

POURQUOI CE FICHIER EXISTE
--------------------------
`python -m http.server` envoie Last-Modified mais AUCUN Cache-Control. Sans
consigne explicite, le navigateur applique une heuristique : il considere une
reponse fraiche pendant environ 10 % du temps ecoule depuis sa derniere
modification. Un data.json modifie il y a six heures est donc juge bon pour une
demi-heure, et l'application affiche un graphe perime sans que rien ne le
signale.

Le service worker n'y change rien : son « reseau d'abord » appelle fetch(), qui
passe lui aussi par ce cache. C'est la meme cause qui figeait version.json, donc
le signal de fraicheur cense justement reperer ce probleme.

Constate le 22/09/2026 : le fichier sur le disque portait 119 commits, la
fenetre en affichait 115, et le bouton « Recharger » n'apparaissait pas.

`no-cache` ne veut pas dire « ne garde rien » mais « revalide avant de servir » :
le navigateur conserve ses copies, demande un 304, et ne peut plus servir du
perime. Le cout est un aller-retour par fichier, en local, sur 127.0.0.1.

Usage :  python serveur.py <dossier a servir> <port>
"""
import sys
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer


class SansCache(SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header('Cache-Control', 'no-cache, must-revalidate')
        super().end_headers()

    def log_message(self, *args):
        pass    # le serveur tourne sans console : personne ne lirait le journal


if __name__ == '__main__':
    if len(sys.argv) < 3:
        raise SystemExit('usage: serveur.py <dossier> <port>')
    racine, port = sys.argv[1], int(sys.argv[2])
    ThreadingHTTPServer(
        ('127.0.0.1', port),
        partial(SansCache, directory=racine),
    ).serve_forever()
