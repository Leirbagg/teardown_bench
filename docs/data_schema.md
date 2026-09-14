# Schéma des données — appareils et pannes

Référence des fichiers `data/devices/*.json` et `data/faults/*.json`.
Tout fichier doit passer `DeviceValidator` (`core/data/device_validator.gd`).

## Principes

- **`requires` est l'unique source du graphe de démontage** (graphe orienté acyclique).
  Un composant ne peut être retiré que si tous ses `requires` sont retirés.
- **`covered_by` ⊆ `requires`** liste les pièces qui *cachent* le composant. Il en découle
  trois états :

| État | Condition | Terminer le geste… |
|---|---|---|
| Caché | un `covered_by` est en place | refusé, sans conséquence |
| Visible mais retenu | `covered_by` tous retirés, un `requires` en place | **forcer** : casse |
| Libre | `requires` tous retirés | retire le composant |

- « Retiré » signifie « défait » pour un connecteur ou un adhésif.
- **Invariant** : si un composant est retiré, tous ses `requires` le sont aussi.
- Les pannes ciblent un **rôle** (`screen`, `battery`…), pas un composant. Le module
  `core/disassembly/` ignore tout des pannes.

## Décisions

1. `covered_by` est ajouté à `requires` pour distinguer une pièce cachée d'une pièce retenue.
2. **Forcer casse sans retirer** : les pièces de `force_breaks` passent à « cassé », le
   composant forcé reste en place et doit être démonté normalement.
3. **Remonter dans le mauvais ordre est refusé sans pénalité.** Remonter X exige que tous
   les composants qui requièrent X soient en place.
4. **Les tests logiciels en échec se déduisent des rôles** : un test échoue si un de ses rôles
   est en panne ou cassé (détail dans [Règles du diagnostic](#règles-du-diagnostic-corediagnosisdiagnosisgd)).
   Les pannes partielles demanderont un champ supplémentaire plus tard.
5. **Les plaintes sont en anglais directement dans le JSON** au MVP (pas de clés de traduction).
6. **`replace_requires` pour les pièces qui cachent leurs propres attaches.** Un écran qui s'ouvre
   comme un livre cache ses nappes : elles ne peuvent pas figurer dans ses `requires` (cycle).
   Ouvrir l'écran = le retirer ; le remplacer exige en plus d'avoir débranché ses nappes.

## Appareil

```json
{
  "schema_version": 1,
  "id": "starter_phone",
  "name": "Starter Phone",
  "tier": 1,
  "faces": ["front", "back"],
  "software_tests": [
    { "id": "boot", "roles": ["battery"], "after": [] }
  ],
  "components": [
    {
      "id": "back_cover", "kind": "cover", "face": "back", "gesture": "pry",
      "gesture_params": {},
      "requires": ["back_screw_l"], "covered_by": [],
      "role": "", "replaceable": true, "force_breaks": [],
      "visual": { "sprite": "res://…", "rect": [0, 0, 180, 360] }
    }
  ]
}
```

| Champ | Obligatoire | Lu par | Valeurs / rôle |
|---|---|---|---|
| `schema_version` | oui | core | `1` |
| `id` | oui | core | snake_case, unique dans `data/devices/` |
| `name` | oui | game | Nom fictif, en anglais |
| `tier` | oui | core | Entier ≥ 1 |
| `faces` | oui | core + game | Sous-ensemble non vide de `front`, `back` |
| `software_tests[].id` | oui | core | Unique |
| `software_tests[].roles` | oui | core | Rôles existant sur l'appareil |
| `software_tests[].after` | oui | core | Tests préalables ; indisponible si l'un échoue. Sans cycle |
| `components[].id` | oui | core | Unique dans l'appareil |
| `components[].kind` | oui | core + game | `screw`, `cover`, `connector`, `adhesive`, `module` |
| `components[].face` | oui | game | Une valeur de `faces` |
| `components[].gesture` | oui | game | `rotate`, `pull`, `hold`, `pry` |
| `components[].gesture_params` | non | game | Réglages de reconnaissance (`turns`, `direction_deg`, `duration_s`) |
| `components[].requires` | oui | core | Ids existants, sans cycle |
| `components[].covered_by` | oui | core | Sous-ensemble de `requires` |
| `components[].role` | non | core | Lien avec pannes et tests. Unique par appareil |
| `components[].replaceable` | non (`false`) | core | Seules ces pièces peuvent être remplacées ou cassées |
| `components[].force_breaks` | non (`[id]`) | core | Pièces cassées quand on force ce composant |
| `components[].replace_requires` | non (`[]`) | core | Pièces à retirer avant de remplacer ce composant, ex. les nappes d'un écran qui s'ouvre comme un livre |
| `components[].visual` | non | game | Ignoré par `core/`. Sprites à lister dans `data/preload_manifest.json` |

### Règles du validateur

- Ids uniques ; toute référence (`requires`, `covered_by`, `force_breaks`, rôles, `after`) existe.
- Aucun cycle dans `requires` ni dans `after`.
- Au moins un composant sans `requires`.
- `covered_by` ⊆ `requires`.
- Un composant qu'on peut forcer (`requires` non inclus dans `covered_by`) ne casse que des
  pièces `replaceable`.
- `replace_requires` : références existantes, jamais le composant lui-même, et seulement sur un
  composant `replaceable`.
- **Orphelin** : composant que rien ne requiert (ni `requires` ni `replace_requires`), non
  `replaceable` et sans rôle. Le retirer ne sert à rien, c'est une erreur.

## Panne

```json
{
  "schema_version": 1,
  "id": "charge_port_faulty",
  "tier": 1,
  "target_role": "charge_port",
  "complaints": ["It stopped charging, even with a new cable."],
  "clues": [
    { "tool": "loupe", "role": "charge_port", "clue": "corrosion", "visible": "exposed" }
  ],
  "target_time_s": 150
}
```

| Champ | Obligatoire | Valeurs / rôle |
|---|---|---|
| `id` | oui | Unique dans `data/faults/` |
| `tier` | oui | Entier ≥ 1, pour la difficulté progressive |
| `target_role` | oui | Rôle mis en panne |
| `complaints` | oui | Au moins une phrase, en anglais |
| `clues[].tool` | oui | `loupe` au MVP |
| `clues[].visible` | oui | `always` ou `exposed` (quand le composant du rôle est visible) |
| `target_time_s` | oui | Base du délai client, > 0 |

Une panne s'applique à tout appareil qui possède son `target_role`.

## Règles du diagnostic (`core/diagnosis/diagnosis.gd`)

Elles découlent des données ci-dessus, sans champ supplémentaire.

- **Rôle opérationnel** : le composant du rôle est en place et ses connecteurs directs
  (`requires` de kind `connector`) sont branchés. On peut tester un appareil ouvert.
- **Rôle en panne** : il porte une panne non résolue, ou son composant est cassé. Une casse
  se comporte donc exactement comme une panne.
- **Statut d'un test logiciel**, évalué dans cet ordre :

| Statut | Condition |
|---|---|
| `BLOCKED` | un test de `after` n'est pas `PASS` |
| `DISCONNECTED` | un de ses rôles n'est pas opérationnel |
| `FAIL` | un de ses rôles est en panne |
| `PASS` | sinon |

- **Indices** : seuls ceux des pannes non résolues sont visibles. `always` en permanence,
  `exposed` quand le composant du rôle est en place et visible.
- **Résolution** : une panne est résolue au premier remplacement du composant de son rôle.
- **Verdict d'un remplacement** : `FIXED_FAULT` (panne non résolue sur ce rôle), sinon
  `FIXED_BREAK` (pièce cassée), sinon `UNNECESSARY` (erreur de diagnostic, comptée au bilan).
- **Test final** : `NOT_ASSEMBLED` si l'appareil n'est pas remonté (non compté). Sinon
  `PASSED` si tous les tests sont `PASS` et qu'aucune pièce n'est cassée, `FAILED` sinon
  (compté au bilan).

## Règles de la journée (`core/day/`)

- **Clients** : `DayGenerator` en tire entre 3 et 5. Chacun reçoit une panne applicable dont le
  `tier`, comme celui de l'appareil, ne dépasse pas le tier demandé. Deux clients consécutifs
  n'ont pas la même panne quand une autre est possible. Même graine, même journée.
- **Plainte** : tirée parmi les `complaints` de la panne.
- **Délai** : somme des `target_time_s` des pannes du client, en temps réel de réparation.
- **Temps** : `game/` appelle `advance(delta)`. Le temps ne compte ni en pause, ni entre deux
  clients, ni après la fin de la réparation. La pause persiste d'un client au suivant.
- **Fin d'un client** : au premier test final réussi. Il n'y a pas d'abandon : l'appareil est
  toujours réparable (stock illimité).
- **Bilan par client** : temps écoulé, délai respecté (temps ≤ délai), pièces cassées (une
  entrée par casse), erreurs de diagnostic (remplacements inutiles + tests finaux ratés).
- **Bilan de la journée** : les lignes des clients commencés et leurs totaux. Les délais
  respectés ne comptent que les clients terminés.
