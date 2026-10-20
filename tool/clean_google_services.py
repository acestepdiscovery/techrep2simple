"""Nettoie android/app/google-services.json après un téléchargement depuis Firebase.

(2026-10-20) Le fichier téléchargé liste TOUTES les apps Android du projet Firebase
partagé `smallfun` (et parfois le client iOS d'une autre app). Il est copié dans
l'app : on ne garde que TechReport. Le plugin Google ne lit que le bloc de l'app
compilée, donc rien ne change au fonctionnement. Sans risque à relancer.

Usage (depuis app/) : python tool/clean_google_services.py
"""
import json
import os
import sys

PKG = 'com.tec.reportnew1cld'
PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'android', 'app',
                    'google-services.json')

d = json.load(open(PATH, encoding='utf-8'))
mine = [c for c in d['client'] if c['client_info']['android_client_info']['package_name'] == PKG]
if len(mine) != 1:
    sys.exit(f'{PKG} introuvable dans google-services.json : rien modifié.')
before = len(d['client'])
d['client'] = mine
inv = mine[0].get('services', {}).get('appinvite_service', {})
if 'other_platform_oauth_client' in inv:
    inv['other_platform_oauth_client'] = [
        o for o in inv['other_platform_oauth_client'] if o.get('client_type') == 3]
open(PATH, 'w', encoding='utf-8', newline='\n').write(json.dumps(d, indent=2, ensure_ascii=False) + '\n')
sha = [o for o in mine[0].get('oauth_client', []) if o.get('client_type') == 1]
print(f'apps : {before} -> 1 ; empreintes SHA de {PKG} : {len(sha)} (il en faut 3 : debug, importation, signature Play)')
