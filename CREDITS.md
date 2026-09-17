# Crédits et licences des ressources

Ressources de tiers utilisées par le jeu. Chaque dossier de `assets/third_party/` contient le
fichier de licence d'origine.

## Règles

- **Licences acceptées** : CC0, SIL OFL, MIT, ISC, Apache 2.0.
- **Refusées** : « usage personnel uniquement », CC-BY-NC, et toute ressource dérivant d'une marque
  ou d'un modèle réel (voir CLAUDE.md, « Propriété intellectuelle »).
- Toute ressource ajoutée est inscrite ici, avec son auteur, sa version, sa licence et son lien.

## Polices

| Ressource | Version | Auteur | Licence | Obligations |
|---|---|---|---|---|
| [Inter](https://github.com/rsms/inter) | 4.1 | Rasmus Andersson et les auteurs du projet Inter | [SIL Open Font License 1.1](assets/third_party/inter/LICENSE.txt) | Conserver la licence ; ne pas vendre la police seule ; renommer en cas de modification |

Fichiers : `assets/third_party/inter/Inter-Regular.ttf`, `Inter-SemiBold.ttf`.

## Icônes

| Ressource | Version | Auteur | Licence | Obligations |
|---|---|---|---|---|
| [Lucide](https://lucide.dev) | 1.46.0 | Lucide Icons and Contributors (fork de Feather, Cole Bemis) | [ISC](assets/third_party/lucide/LICENSE), MIT pour les icônes héritées de Feather | Conserver la notice de copyright dans les sources |

Fichiers : 22 icônes dans `assets/third_party/lucide/icons/`, importées à l'échelle 3 (72 px) pour
rester nettes sur un écran de téléphone.

| Icône | Usage prévu |
|---|---|
| `rotate-3d` | Retourner l'appareil (« flip » n'existe pas chez Lucide) |
| `zoom-in` | Loupe |
| `list-checks` | Tests logiciels |
| `circle-check` | Test final |
| `layout-grid` | Tapis magnétique |
| `graduation-cap` | Mode solution |
| `pause`, `skip-forward`, `gauge`, `square` | Contrôles du mode solution |
| `play` | Reprendre après une pause |
| `x` | Fermer un panneau |
| `volume-2`, `volume-x`, `vibrate`, `vibrate-off` | Réglages son et vibrations |
| `undo-2`, `replace` | Remonter, remplacer une pièce |
| `banknote`, `star`, `timer` | Bilan : argent, note, temps |
| `wrench` | Réserve (atelier) |

## Sons

Les effets sonores de `assets/audio/` sont générés par `scripts/generate_sfx.py` : aucune
ressource de tiers, aucune licence à respecter.
