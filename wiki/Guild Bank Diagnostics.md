# Diagnostic de la banque de guilde

Version : **4.6.20**, interface clavier uniquement. Le correctif trie désormais
chaque reconstruction avant sa validation et préserve les priorités des parents
repliés ; sa validation visuelle en jeu reste à faire. Le mode de trace lui-même
reste purement observateur : il ne lance aucun tri ni reconstruction.

## Capturer le défaut

- Installer le dossier `AutoCategory` complet, puis `/reloadui`.
- Vérifier que LibDebugLogger enregistre le niveau **Info**. Le nouveau mode
  écrit au niveau Info : `/acdebug on` et le niveau Debug ne sont pas nécessaires.
- Avant d'ouvrir la banque, saisir `/acgbtrace on`.
- Changer lentement de banque, puis effectuer quelques changements rapides.
  Tester ensuite un dépôt/retrait. Garder la capture courte, environ 20 secondes.
- Dès qu'un défaut apparaît, saisir `/acgbtrace mark sans en-tetes` ou
  `/acgbtrace mark categories en desordre`, sans réinitialiser les filtres.
  Une capture d'écran au même moment facilite la comparaison.
- Saisir `/acgbtrace off`, puis exporter le journal LibDebugLogger habituel
  en conservant les lignes `[ACGB]` et les erreurs UI complètes.

La trace est désactivée au chargement et ne persiste pas après `/reloadui`.
Elle s'arrête automatiquement après 2 500 messages. Les 32 premières piles
d'appels sont conservées ; après ce budget, les instantanés continuent sans
nouvelles piles. Les hooks installés au premier démarrage restent en place
mais sont inactifs après `off`. Leur surcoût peut modifier le timing du défaut.
Si la limite automatique est atteinte, `mark` et `dump` acceptent encore un
instantané manuel borné, sans reprendre la capture continue. Un `off` explicite
désactive aussi cette possibilité jusqu'au prochain `on`.

Le journal contient les addons activés et leurs versions, les identifiants de
guilde sélectionnée, ainsi que des noms d'objets et de catégories. Le relire
avant de le partager publiquement.

## Comparer avec et sans Swiss Knife

Ne pas effacer les SavedVariables. Exécuter la même séquence après chaque
`/reloadui`, avec une nouvelle capture et un marqueur indiquant le test :

| Test | Configuration |
| --- | --- |
| A | Configuration habituelle |
| B | Même configuration, Swiss Knife désactivé |
| C | AutoCategory et dépendances nécessaires aux mêmes règles seulement |
| D | Configuration C avec Swiss Knife et ses dépendances |

Réactiver ensuite la configuration A pour vérifier que le défaut revient.
Conserver les dépendances nécessaires aux règles, sinon la comparaison change
aussi la catégorisation. Un résultat intermittent demande plusieurs essais.
La présence d'un addon dans une pile indique son implication dans le chemin
d'appel, pas automatiquement sa responsabilité dans le défaut.

## Lire la trace

- `BANK_SELECTED` et `ITEMS_READY` distinguent les événements. `gen`, `guild`,
  `list` et `data` permettent de suivre le contexte et les remplacements de table.
- `ApplySort_ENTER`, `APPLYSORT_EXIT`, `UpdateList_ENTER/EXIT`,
  `ZO_ScrollList_Clear_ENTER/EXIT` et `ZO_ScrollList_Commit_ENTER/EXIT` encadrent
  les opérations réellement appelées. `CALLER` conserve les chemins et lignes.
- `REBUILD_REPLACED_UNSORTED` est un état intermédiaire : des inversions y sont
  possibles. À partir de 4.6.20, `REBUILD_SORTED` puis `REBUILD_COMMITTED` doivent
  montrer l'ordre corrigé, même sans appelant `ApplySort` autour de la relance.
  `REBUILD_COMMITTED_BEFORE_CALLER_SORT` appartient aux anciennes traces 4.6.19.
- `RETRY_REBUILD` signale le chemin différé de reconstruction. Vérifier si un
  `APPLYSORT_EXIT` suit réellement, puis examiner `POLL` et le marqueur manuel :
  des en-têtes présents ne suffisent pas à valider l'ordre.
- `AFTER_SORT_0/100/300` observe l'état après le tri sans le modifier. Ces
  observations sont annulées par une nouvelle génération, une autre guilde,
  un nouveau tri observé, un remplacement de liste ou l'arrêt de la capture.
- `H`, `missingRules`, `headerMissingKeys`, `orphanItems`, `inversions`, `firstBad` et `hash` décrivent le contenu
  et l'ordre. `hash` couvre toute la séquence mais reste un checksum avec
  collisions possibles, pas une preuve cryptographique. `ROW` montre le début
  de la liste ; `BAD` montre le voisinage de la première inversion plus loin.
  `orphanItems` compte les objets sans en-tête de même catégorie et clé :
  avoir au moins un en-tête dans la liste ne suffit pas.
  `headerMissingKeys` révèle un en-tête ayant perdu sa priorité, y compris
  quand tous les objets sont masqués par une catégorie repliée.
- `inversions` vérifie les clés de catégorie et la position en-tête/objet
  à clé égale, pas le tri secondaire complet des objets dans une catégorie.
  Une inversion après le tri peut aussi provenir des clés produites par
  AutoCategory, pas nécessairement d'un autre addon.
- `FILTER` compte les objets conservés/masqués selon les décisions de
  `isHiddenEntry` : règle masquée, non groupés masqués, sac absent, catégorie
  ou ancêtre replié. Les anciens en-têtes ne sont pas comptés comme objets.
- `visibleH` compte les en-têtes admis dans les données visibles de la scroll
  list, pas seulement ceux à l'écran. `activeH` compte les contrôles d'en-têtes
  instanciés ; zéro peut être normal si aucun en-tête n'est dans le viewport.
- `HEADER_SETUP` et `ACTIVE_HEADER` exposent texte, hauteur, visibilité et alpha.
  `hiddenH` révèle un contrôle ou libellé masqué après sa préparation.
  `missingY` peut être normal avant le commit, ou hors viewport en mode uniforme.

Une liste correcte au marqueur manuel avec un affichage incorrect oriente
vers les contrôles/rendu. Un changement de checksum ou une disparition des
en-têtes entre deux étapes oriente vers une mutation/reconstruction ; les
piles d'appels et le test A/B aident à identifier son origine. Les callbacks
qui remplacent entièrement une fonction après l'installation des hooks peuvent
échapper à ceux-ci. Ce diagnostic ne prétend pas intercepter toutes les écritures.

## Vérification et références

Les tests hors jeu chargent le module livré et simulent les contrats ESO :
activation, hooks non bloquants, ordre, changements de contexte, rendu et bornes.
Les 56 assertions du diagnostic et les 24 contrôles de scroll/interaction
passent, dont le tri du chemin différé et l'annulation des relances obsolètes.
La conservation des clés des parents entièrement repliés est aussi testée.
Les suites de régression portent le total à 2 677 assertions réussies
(LibSets testé avec les fixtures intégrées).
**Non testé dans ESO.** Il faut une nouvelle capture en jeu pour conclure.

API et chemin d'affichage vérifiés dans les sources ESOUI `live` :
[tri et reconstruction](https://github.com/esoui/esoui/blob/live/esoui/ingame/inventory/inventory.lua),
[scroll lists et préparation des contrôles](https://github.com/esoui/esoui/blob/live/esoui/libraries/zo_templates/scrolltemplates.lua),
[contrats des hooks](https://github.com/esoui/esoui/blob/live/esoui/libraries/utility/zo_hook.lua),
[pile d'appels](https://github.com/esoui/esoui/blob/live/esoui/libraries/globals/globalapi.lua)
et [API natives](https://github.com/esoui/esoui/blob/live/ESOUIDocumentation.txt).
