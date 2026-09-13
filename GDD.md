# Teardown Bench — Game Design Document

> Nom de travail. Voir [Questions ouvertes](#10-questions-ouvertes).
> Document de conception en français ; les textes du jeu sont en anglais.

## 1. Pitch

Simulateur 2D de réparation d'appareils électroniques fictifs, sur mobile, en portrait.
Un client dépose un appareil avec une plainte. Le joueur diagnostique la panne, démonte,
remplace la pièce, remonte, puis teste.

- **Fantasme central** : le plaisir tactile du geste précis (dévisser, décoller, faire levier,
  tirer une nappe).
- **Direction artistique** : flat et minimaliste. La satisfaction vient des gestes, pas du rendu.
- **Public cible** : les curieux de tech, qui aiment comprendre comment un objet est fait et
  apprécient un minimum de réalisme sans être des réparateurs experts.

## 2. Piliers

1. **Chaque action a son geste.** Une vis se tourne, une nappe se tire, une colle se chauffe.
   Le plaisir vient de la maîtrise de ces gestes.
2. **On punit l'intention, pas la précision.** Un geste raté (doigt qui glisse, rotation
   incomplète) se réessaie sans conséquence. Seule une mauvaise *décision* casse quelque chose :
   forcer une pièce encore retenue, démonter dans le mauvais ordre, remplacer une pièce saine.
3. **Jamais bloqué.** Pas de faillite ni de game over. Les erreurs ralentissent la progression
   sans jamais l'arrêter.

## 3. Boucle principale

### 3.1 Session : la journée d'atelier

- Une session = **une journée** de 5 à 10 min réelles, avec 3 à 5 clients.
- La journée se termine par un **bilan**.

### 3.2 Une réparation

```
Plainte client → Inspection → Mesure / test → Démontage → Remplacement
              → Remontage (accéléré) → Test final ──échec──┐
                                           │                │
                                        succès        on rouvre l'appareil
                                           ↓
                                    Rendu au client
```

1. **Plainte** : le client décrit le symptôme en une phrase courte.
2. **Diagnostic** : inspection visuelle, puis outils de mesure et de test (voir 3.4).
3. **Démontage** : suit le graphe de prérequis de l'appareil (`requires`, voir section 8).
4. **Remplacement** de la pièce jugée défectueuse.
5. **Remontage** : joué mais accéléré (gestes simplifiés ou un tap par étape).
6. **Test final joué** : le joueur rallume l'appareil et vérifie la fonction réparée (par exemple
   toucher l'écran). Si le diagnostic était faux, le test échoue et il faut rouvrir l'appareil.

### 3.3 Vue et gestes

- **Vue** : 2D de dessus, en couches. Retirer un composant révèle ce qu'il y a dessous.
  L'appareil peut être **retourné** (face avant / face arrière).
- **Gestes** :

| Geste | Usage | Interaction |
|---|---|---|
| Rotation | Vis | Mouvement circulaire du doigt sur la vis |
| Glisser / tirer | Nappe, cache | Tirer dans le bon sens |
| Maintien | Colle | Appui long avec l'outil chauffant avant de pouvoir soulever |
| Levier | Jointure de coque | Insérer le médiator et faire le tour de l'appareil |

- Jeu à deux mains accepté (téléphone posé ou tenu). **Aucun multi-touch requis.**

### 3.4 Diagnostic

- Trois couches combinées : plainte + inspection visuelle, mesures et tests, puis remplacement.
  Le remplacement fait office d'essai-erreur : changer une pièce saine a un coût.
- **Difficulté progressive** : les premières pannes sont évidentes, puis les symptômes
  deviennent ambigus (plusieurs causes possibles pour une même plainte).
- Outils prévus : loupe (inspection), test logiciel de l'appareil, multimètre (post-MVP).

### 3.5 Erreurs et casse

- Une casse vient toujours d'une mauvaise décision (pilier 2).
- **Jeu complet** : une casse coûte de **l'argent** (pièce à racheter) et de la **réputation**.
- **Réputation** : débloque de nouveaux clients et des appareils plus complexes.

### 3.6 Délai client

- Chaque client annonce un délai, exprimé en **temps réel de réparation** (chrono visible et discret).
- Respecter le délai donne un bonus. Le dépasser n'entraîne pas d'échec dur.

### 3.7 Vis et petites pièces

- **MVP** : les vis sont collectées automatiquement au démontage et remises automatiquement
  au remontage.
- **Plus tard** : gestion fine (tapis magnétique, bonne vis dans le bon trou) introduite comme
  mécanique de progression.

## 4. Scope minimal jouable (MVP)

**But unique : valider le fun du geste.**

### Inclus

- **1 appareil** : un téléphone fictif.
- **3 pannes** : écran cassé, batterie morte, connecteur de charge.
- **Les 4 gestes** : rotation, glisser/tirer, maintien, levier.
- **Retournement** avant/arrière.
- **Diagnostic** : loupe + test logiciel de l'appareil.
- **Test final joué.**
- **Journée + bilan** : pour chaque client, temps réel, délai respecté ou non, pièces cassées,
  erreurs de diagnostic.
- **Casse** : la pièce cassée devient une panne supplémentaire à réparer (stock illimité) et
  apparaît dans le bilan.
- **Interruption** (appel, mise en arrière-plan) : pause automatique. Si l'OS tue l'app, la
  réparation en cours est perdue.
- **Langue** : anglais.

### Exclu du MVP

Argent, réputation, stock de pièces, upgrades d'outils, sauvegarde persistante, multimètre,
gestion fine des vis, monétisation, multijoueur / social, narration, micro-soudure,
génération procédurale, UGC.

### Critère de succès

> Des testeurs relancent une réparation **sans qu'on le leur demande**.

## 5. Monétisation (post-MVP)

Aucun SDK de pub ni d'achat intégré dans le MVP. On l'ajoute seulement une fois le fun validé.

- **Modèle** : free-to-play.
  - Pubs interstitielles **entre les journées uniquement**, après le bilan.
  - Achat unique « sans pub ».
  - Packs **cosmétiques d'atelier** (décor, tapis, skins d'outils).
- **Le jeu complet est gratuit.** Les packs ne sont que des bonus.

### Interdits, quoi qu'il arrive

- Monnaie premium (gemmes ou équivalent).
- Timers d'énergie ou limite de journées jouables.
- Tout achat ou pub qui saute, automatise ou facilite le geste : le geste est le produit.
- Aucun contenu de gameplay (appareils, outils) vendu en pack.

## 6. Contraintes mobiles

### Reprises de CLAUDE.md

- Android, portrait, écrans à partir de 360dp de large.
- Méthode de rendu `Mobile`, aucune fonctionnalité Forward+.
- Cibles tactiles d'au moins 48dp. Pas de survol, pas de clic droit, pas de raccourci clavier
  comme seul moyen d'action.
- 60 fps sur un mobile milieu de gamme, 200 draw calls maximum par écran de réparation.

### Ajoutées

- **Appareil minimum** : Android 8+, 3 Go de RAM.
- **APK < 150 Mo**, sans asset pack téléchargé séparément.
- **100 % hors ligne** (sauf pubs et achats, post-MVP).
- **Haptique** sur les gestes, désactivable.
- **Jouable son coupé** : chaque retour sonore (clic de vis, craquement) a un équivalent
  visuel et/ou haptique.

## 7. Hors périmètre

### Hors du jeu

- **3D**, y compris pour le retournement de l'appareil.

### Hors MVP, prévu plus tard

- Port iOS.
- Localisation (le MVP est en anglais seulement).
- Économie : argent, réputation, stock, upgrades d'outils.
- Sauvegarde persistante.
- Multimètre.
- Gestion fine des vis.
- Appareils et pannes supplémentaires.

### Exclu du MVP, à réévaluer ensuite

Ces points ne sont pas tranchés pour le jeu complet. On les exclut du MVP et on y reviendra
après la validation du fun (voir [Questions ouvertes](#10-questions-ouvertes)).

- Multijoueur / social (classements, partage).
- Narration (histoire d'atelier, clients récurrents). Au MVP, les clients n'ont qu'une plainte courte.
- Réparation au niveau des composants (micro-soudure). Au MVP, on remplace des modules.
- Appareils générés de façon procédurale.
- Éditeur d'appareils pour les joueurs (UGC).

## 8. Correspondance avec l'architecture

Rappel de CLAUDE.md : toute règle de jeu vit dans `core/`.

| Couche | Responsabilités |
|---|---|
| `core/` | Graphe de démontage et résolution des prérequis, système de pannes, diagnostic (indices révélés par la loupe et le test logiciel), évaluation de la casse (mauvaise décision → pièce cassée → panne ajoutée), chrono du délai client, déroulé de la journée, calcul du bilan |
| `game/` | Reconnaissance des gestes (rotation, glisser, maintien, levier), rendu des couches et du retournement, animations, audio, haptique, UI du bilan, pause sur interruption |
| `data/devices/*.json` | Composants, prérequis `requires`, geste requis par composant, pannes possibles et indices associés |

- Aucune séquence de démontage codée en dur dans le GDScript.
- Tout JSON d'appareil passe par `core/data/device_validator.gd`.
- `game/` décide si un geste est *réussi* (précision). `core/` décide si l'action est *permise*
  (intention). C'est la traduction directe du pilier 2.

## 9. Risques

| Risque | Atténuation |
|---|---|
| Gestes précis au doigt sur 360dp avec des erreurs pénalisantes : sentiment d'injustice | Pilier 2 : un geste raté n'est jamais puni. Tolérance de reconnaissance généreuse, cibles ≥ 48dp |
| Satisfaction tactile difficile avec un visuel flat | La richesse vient de la variété des gestes et du retour haptique. À valider en priorité avec le MVP |
| Chrono en temps réel qui casse le côté contemplatif | Chrono discret, bonus seulement, pas d'échec dur. À surveiller en playtest |
| Diagnostic trop mince avec 3 pannes | Le MVP valide le geste, pas le diagnostic. La profondeur arrive avec d'autres pannes |

## 10. Questions ouvertes

- **Nom** : « Teardown » est déjà le titre d'un jeu existant. Vérifier le risque de confusion
  ou de marque avant tout usage public de « Teardown Bench ».
Tous ces points sont exclus du MVP. Ils restent à trancher pour le jeu complet.

- Multijoueur / social (classements, partage) : dedans ou dehors ?
- Narration : clients récurrents, histoire d'atelier, ou plaintes courtes uniquement ?
- Réparation au niveau des composants (micro-soudure) ou seulement des modules ?
- Appareils générés de façon procédurale à partir des données ?
- Éditeur d'appareils pour les joueurs (UGC) ?
- Montant et forme exacte du bonus de délai une fois l'économie en place.
