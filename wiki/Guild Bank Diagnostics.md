# Diagnostic de la banque de guilde

La version **4.6.21** retire l'instrumentation temporaire et les contournements
par temporisation. La version 4.6.20 a été confirmée fonctionnelle dans ESO par
l'utilisateur ; cette version nettoyée doit encore être vérifiée en jeu.

## Cause établie et correctif conservé

- **Ordre des entrées :** `createNewScrollData` conserve les objets visibles,
  puis ajoute les en-têtes. Une reconstruction autonome pouvait valider cette
  liste avant tout tri, même après un `ApplySort` correct. Trier avec
  `sortInventoryFn` avant chaque `ZO_ScrollList_Commit` conserve les catégories
  dans l'ordre, y compris hors d'un appel englobant à `ApplySort`.
- **Parents repliés :** conserver leur `AC_sortPriorityName` stocké, car
  aucun enfant visible ne reste pour recalculer leur priorité.
- **Positions de défilement :** conserver le commit après le remplacement
  de `list.data`, nécessaire aux positions `top`/`bottom` des nouvelles lignes.

Le journal fourni établissait le passage de zéro à 21 inversions après une
relance d'AutoCategory. La présence d'en-têtes ne prouve donc pas que l'ordre
ou le rendu est correct. Aucun conflit Swiss Knife n'a été démontré par ce
chemin ; l'archive ne contenait pas de comparaison avec/sans cet addon.

## Éléments retirés

- **Instrumentation :** `GuildBankTrace.lua`, `/acgbtrace`, `/acdebug`,
  instantanés, hooks d'observation et logs ajoutés pour cette enquête.
- **Contournements :** retry de liste vide, polling après sélection/chargement
  d'une banque, compteurs de génération et événements dédiés à ce polling.
- **Conservés :** logger historique et dépendance LibDebugLogger, suivi
  préexistant des objets et son minuteur `SF.CallLater`, sans nouveau délai.

Une liste vide n'arme plus de relance. Les mises à jour normales d'ESO
repassent par le hook `ApplySort` lorsque les objets sont disponibles, d'après
le [flux d'inventaire ESOUI live](https://github.com/esoui/esoui/blob/live/esoui/ingame/inventory/inventory.lua).
Le calcul des positions reste assuré par le
[commit des scroll lists ESOUI](https://github.com/esoui/esoui/blob/live/esoui/libraries/zo_templates/scrolltemplates.lua).

## Vérifier la version nettoyée

1. Installer le dossier `AutoCategory` complet de la 4.6.21 et lancer
   `/reloadui`. Supprimer l'ancien fichier `GuildBankTrace.lua` si l'installation
   est une simple copie par-dessus ; il n'est plus chargé par le manifeste.
2. Garder d'abord la configuration habituelle d'addons, sans changer les
   SavedVariables. Les commandes de trace ont été supprimées.
3. Ouvrir la banque, changer plusieurs fois de guilde et tester dépôt/retrait.
   Vérifier l'ordre immédiatement, puis après quelques secondes.
4. Replier/déplier plusieurs parents et sous-niveaux, puis faire défiler les
   listes. Vérifier l'ordre des parents et l'absence d'erreur de position.
5. Si le défaut revient, conserver une capture et les erreurs Lua complètes,
   noter la version et la séquence exacte. Ne pas attribuer le défaut à un
   addon tiers sans preuve ; une comparaison contrôlée peut ensuite aider.

Les tests hors jeu passent : **2 634 assertions** sur cinq suites, avec les
fixtures LibSets intégrées, et 47 fichiers compilés en Lua 5.1. Le harnais de
scroll charge le fichier livré sans module de diagnostic ; il vérifie le tri
au moment du commit, les cycles vide/remplissage et l'absence de relance.
**Non testé dans ESO** pour la 4.6.21.
