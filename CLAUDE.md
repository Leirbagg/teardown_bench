# Projet — Simulateur de réparation (Godot 4, mobile)

Jeu 2D de réparation d'appareils électroniques. Le joueur reçoit un appareil
avec une plainte client, diagnostique la panne, démonte, remplace, remonte, teste.

## Commandes

```bash
godot --headless --script res://tests/run_tests.gd   # suite de tests
godot --headless --script res://tests/run_tests.gd -- scoring   # une seule suite (~1 s)
godot --headless --import --path .                   # vérifie que le projet importe
./scripts/build_android.sh                           # tests puis APK debug → build/
```

Toujours lancer la suite de tests après une série de modifications. Une suite est un
fichier `tests/cases/test_*.gd` qui étend `TestSuite` ; une erreur d'exécution pendant
un test compte comme un échec.

## Architecture — règle non négociable

- `core/` : logique de jeu **pure GDScript**. Aucun `extends Node`, aucun appel au
  moteur, aucune référence à une scène ou à un asset. Testable en headless.
  Seule exception : lire les fichiers JSON de `data/` (`FileAccess`, `JSON`).
  Contient : graphe de démontage, système de pannes, diagnostic, journée et bilan, plan du mode solution,
  économie, sauvegarde.
- `game/` : scènes, nœuds, UI, input, animation. Consomme `core/`, jamais l'inverse.
- `data/` : définitions d'appareils et de pannes en JSON. Aucune logique.

Si une fonctionnalité peut vivre dans `core/`, elle va dans `core/`.
Toute règle de jeu ajoutée dans `game/` est un bug.

## Données

Un appareil = un fichier JSON dans `data/devices/`. Le démontage est un graphe
orienté acyclique : chaque composant liste ses prérequis (`requires`). Ne jamais
coder en dur une séquence de démontage dans du GDScript.

Valider tout nouveau JSON avec `core/data/device_validator.gd` (détecte cycles,
prérequis manquants, composants orphelins). Schéma, décisions de design et règles du
diagnostic et de la journée : `docs/data_schema.md`.

## Conventions

- Typage statique obligatoire (`var x: int`, signatures de fonctions typées).
- Signaux pour la communication `core/` → `game/`, jamais de référence directe.
- Une scène = un fichier `.tscn` = une responsabilité.

## Contraintes plateforme

- Cible : Android, portrait, écrans à partir de 360dp de large.
- Rendu : méthode `Mobile`. Ne pas utiliser de fonctionnalités Forward+.
- Toute interaction se fait au doigt : cible tactile minimum 48dp, pas de survol,
  pas de clic droit, pas de raccourci clavier comme unique moyen d'action.
- Budget : viser 60 fps sur un mobile milieu de gamme. Pas plus de 200 draw calls
  par écran de réparation.

## Propriété intellectuelle — IMPORTANT

Aucun nom de marque, logo, ou nom de modèle réel dans le code, les données ou les
assets. Les appareils sont des analogues fictifs. Si un nom réel apparaît dans une
demande, utiliser l'équivalent fictif du projet.

**Exception décidée par le propriétaire du projet** : les noms de modèle affichés au
joueur (champ `name` des appareils et plaque gravée au dos) sont des quasi-homonymes
assumés de modèles réels. Ne pas les « corriger ».
Ils restent risqués pour une publication sur un store : le reste de la règle s'applique
toujours, et rien d'autre ne doit évoquer une marque.

## Pièges connus

- `class_name` en double casse l'import du projet en silence.
- Un **nouveau** `class_name` n'est connu qu'après `godot --headless --import` : sans ça, les
  tests échouent sur des erreurs d'analyse (`Identifier "X" not declared`) qui ressemblent à du
  code cassé alors que seul le cache de classes est en retard.
- La journée est tirée au hasard parmi **tous** les appareils : un test qui nomme une pièce
  (`pentalobe_left`, `connector_cover`…) doit choisir son appareil — voir `_main_on()` dans
  `tests/cases/test_game_scenes.gd`. Sinon il passe une fois sur deux, selon le modèle tiré.
- Les ressources chargées avec `load()` au runtime ne sont pas exportées dans l'APK
  si rien ne les référence : les lister dans `data/preload_manifest.json`.
- Les touchers (`InputEventScreenTouch`/`ScreenDrag`) sont routés par l'interface vers
  le contrôle sous le doigt et n'atteignent pas `_unhandled_input`. Une vue tactile se
  met en `mouse_filter` STOP et lit ses gestes dans `_gui_input`.
- En `--headless`, la fenêtre fait 0×0 : les sondes d'input ou de mise en page y
  donnent des résultats faux. Les vérifier dans une vraie fenêtre.
