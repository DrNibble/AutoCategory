# Changes

## 2026-11-08 (7): the Level tooltip documents the rule false (display-only level)

- The Level dropdown tooltip (SI_AC_MENU_EC_DROPDOWN_LEVEL_TOOLTIP)
  now documents what the rule of a level category decides: with true
  (or any condition) the section also keeps, flat under it, the items
  it matches that no child took; with false the level is display-only
  - it holds no item itself and only its children's sections show
  under it (verified offline: a level 2 child still nests under a
  level 1 parent whose rule is false). Tooltip updated in
  en/de/fr/es/ru/zh; wiki (Building Levels from Rules) updated.
- test/RuleLevel_test.lua extended (68 assertions). Other suites
  unchanged. Not tested in ESO.

## 2026-11-08 (6): a Normal category counts as level 1 and its children can take their items

- MatchCategoryRules (AutoCategory_API.lua) now counts a Normal
  category (no level set, or an out-of-range value) as level 1, exactly
  like a category set to level 1 explicitly - only the displayed level
  text differs. A matching Normal rule no longer returns a flat
  category immediately: it records its path (the category name, or the
  levels of a dynamic autoset name) and the evaluation CONTINUES, so a
  level 2-5 child whose parent chain starts with that category can
  still take the item and nest it under the parent. This fixes the
  reported inventory bug where all the items of a broad Normal parent
  (e.g. "Conso") piled up flat under the parent instead of filling
  their level 2 sections ("Max Magie", ...), whatever the rule order.
- A later matching rule now replaces the recorded path only when its
  chain EXTENDS it (the same family, one or more levels deeper);
  anything else - equal depth, shallower, or a deeper chain of another
  family - is ignored, so the first matching rule keeps the item
  whatever the evaluation order (the historical first-match-wins
  behavior, which the old deepest-chain-wins rule broke across
  families). A Normal parent keeps the items none of its children
  took, flat under it, before its sections (unchanged sort).
- A flat category (Normal or level 1) keeps the plugin sort name
  registered while its rule ran (autoset), like the ordinary rules
  always did; deeper paths keep clearing it. The parent-chain walk now
  stops at a Normal or level 1 parent (consistent with
  BagRuleShowKey), and non-matching flat rules still re-register their
  collapse state.
- Level dropdown tooltip updated in en/de/fr/es/ru/zh; wiki
  (Building Levels from Rules) updated to the new semantics.
- test/RuleLevel_test.lua extended (65 assertions): a Normal parent
  BEFORE its child lets the child take the item, a deeper rule of
  another family does not steal it, a Normal rule keeps its plugin
  sort name and its dynamic nested name. All the other suites still
  pass: CategoryTree (117), BagOrder (6), FormatShow (17), ParentDD
  (15), LibSets (1969). Not tested in ESO.

## 2026-11-08 (5): Normal/level 1 parent displays first, then its level 2+ sections

- Reverts the display order of 2026-11-08 (4): a Normal or level 1
  category now displays FIRST, followed by its level 2+ sections with
  the items associated with each level. The flat sort key is back to
  the historical format (CategoryTree.BuildSortKey, no tail marker),
  which sorts the parent's own items before the deeper levels of the
  same name ("0000Potions" sorts before "0000Potions----Magie").
- Fixed the inventory bug where a Normal or level 1 category following
  a level 2+ rule no longer displayed: MatchCategoryRules
  (AutoCategory_API.lua) no longer appends an ordinary rule to an open
  Level path (the doubled name hid the parent's flat display). The
  level category keeps the item it matches, and the Normal or level 1
  parent keeps its own display for the items the level rules did not
  take, whatever the evaluation order. Put the ordinary rule first in
  the bag to give it precedence over the level rules.
- The Categories list (InitScrollBag) now sorts with the same order as
  the bag (AutoCat.SortBagRulesByDisplay): showpriority desc, Normal
  and level 1 categories first, then the level 2-5 sections grouped
  under their parent chain (like the bag display, alphabetical within
  a group); entries without a priority sort last.
- test/CategoryTree_test.lua updated (117 assertions), test/
  RuleLevel_test.lua extended (54: the ordinary rule no longer appends
  to an open path; a Normal parent and its level 2 child keep their
  own items whatever the order), new test/BagOrder_test.lua (6
  assertions on SortBagRulesByDisplay). Other suites still pass:
  ParentDD_test (15), FormatShow_test (17), LibSets_test (1969).
  Not tested in ESO.

## 2026-11-08 (4): Normal/level 1 categories display after the level 2+ sections

- In the bag, the direct items of a flat category (Normal or level 1)
  that also carries deeper levels now display AFTER its level 2+
  sections: the flat sort key gains a tail marker (CategoryTree.FLAT_TAIL,
  byte 255) that sorts after every level name, so with equal
  showpriorities the sections come first, then the parent's own items.
  Nothing changes between flat categories or between different parents;
  a parent with an explicitly HIGHER showpriority than its children
  still displays its own items first (the priority wins).
- In the Category Display Order window and the Categories dropdowns,
  level 2-5 categories now list before the Normal and level 1 ones
  (BagRuleShowSortingFunction groups by level first, then keeps the
  showpriority order within each group).
- test/CategoryTree_test.lua updated and extended (117 assertions):
  flat key tail marker, flat parent after its sections (also with a
  deeper chain), priority still winning, flat-vs-flat order unchanged,
  and the extracted header-building scenario now expects the parent's
  own items after the sections. Other suites still pass: RuleLevel_test
  (50), ParentDD_test (15), FormatShow_test (17), LibSets_test (1969).
  Not tested in ESO.

## 2026-11-08 (3): level in the Categories dropdowns and indentation in the Display Order window

- The Categories dropdowns (bag settings, edit category) now show the
  level of the category after the display priorities, using the
  localized "Level: n" string: "Legeres (10/20) Niveau : 2". formatShow()
  (classes/BagRuleApi.lua) appends it in every branch (keyboard color,
  hidden category, gamepad plain text); no level text for Normal
  categories, invalid levels or a missing backing rule.
- The "Category Display Order" window (settings/DisplayOrderWin.lua)
  indents each category according to its level: level 1 and Normal
  categories are not indented, each deeper level adds one indentation
  (4 spaces per level).
- New test/FormatShow_test.lua (17 assertions on the delivered
  classes/BagRuleApi.lua). The other suites still pass: ParentDD_test
  (15), RuleLevel_test (50), CategoryTree_test (113), LibSets_test
  (1969). Not tested in ESO.

## 2026-11-08 (2): a Normal category counts as level 1 for the Parent dropdown

- A Normal category is a top-level category: it now counts as level 1 and
  is a valid parent for a level 2 category (the Parent dropdown of a
  level 2 category lists the level 1 categories AND the Normal ones).
  Levels 3-5 keep requiring a parent of the level just below (a level 3
  category lists the level 2 categories only). A Normal or level 1
  category never has a parent itself (the Parent dropdown stays disabled
  below level 2).
- Parent dropdown tooltip updated in en/de/fr/es/ru/zh to say so.
- Not tested in ESO. The offline suites are unchanged: test/ParentDD_test
  (15), test/RuleLevel_test (50), test/CategoryTree_test (113),
  test/LibSets_test (1969) still pass.

## 2026-11-08: Parent dropdown shows only the categories of the level above

- Bug: the Parent dropdown stayed empty. CVT:assign() silently ignores a
  plain table (it checks tblB.GetUses), and CatSet_ParentDD_LAM:refresh()
  passed it one: the choices never reached the dropdown. refresh() now
  builds a real CVT (CVT:New(nil, nil, CVT.USE_VALUES)), the pattern used
  everywhere else in the addon, and assign() copies the lists and marks
  the control dirty so updateControl() pushes them.
- The Parent choices are now filtered by level: the parent of a level N
  category is a level N-1 category (for a level 2 category the dropdown
  lists the level 1 categories). A parent set before (whose level no
  longer matches) stays visible so it can be changed; "(none)" remains
  available.
- New test/ParentDD_test.lua (15 assertions, delivered classes/CVT.lua
  and classes/BaseUI.lua): documents that assign() ignores a plain table,
  that a real CVT is copied and marks dirty, and that updateControl()
  pushes the choices and the value to the LAM control. The other suites
  still pass: RuleLevel_test (50), CategoryTree_test (113),
  LibSets_test (1969). Not tested in ESO.

## 2026-11-07 (3): Fix infinite recursion when editing Level/Parent (Maximum call depth of 10000 exceeded)

- LAM-2.0 calls a dropdown's setFunc on every UpdateValue(false, value),
  including the programmatic refreshes done while the Edit Category panel
  updates itself. The Level setFunc called CatSet_SyncEditRuleControls,
  which pushed the level back into the dropdown (UpdateValue(false, level)
  -> setFunc -> sync -> ...), and CatSet_ParentDD_LAM:setValue called
  updateControl, which pushed the parent back into its dropdown
  (setValue -> updateControl -> UpdateValue -> setFunc -> setValue -> ...):
  both loops ended in "Maximum call depth of 10000 exceeded" as soon as
  the Edit Category panel was used.
- CatSet_SyncEditRuleControls now refreshes both dropdowns with
  UpdateValue() WITHOUT a value: LAM then only re-reads getFunc and
  updates the displayed text, without calling setFunc (verified against
  the LibAddonMenu-2.0 source).
- Both setFuncs (Level and Parent) are now idempotent: they return early
  when the value did not change, which also breaks any remaining
  setFunc -> refresh -> setFunc bounce.
- Verified offline with Lua 5.1: the modified file compiles;
  test/RuleLevel_test.lua (50), test/CategoryTree_test.lua (113) and
  test/LibSets_test.lua (1969) still pass. Not tested in ESO.

## 2026-11-07 (2): Parent dropdown, parent chains and level in tooltips

- New **Parent** dropdown in Edit Category, next to the Level dropdown:
  for a level 2-5 category it chooses the category under which this one is
  nested. Choices are all known categories (the current one excluded);
  "(none)" leaves the category without a parent, which makes it a
  top-level section. A parent that would create a cycle (this category
  itself or one of its ancestors) is refused.
- The sub-menu path is now the **parent chain**: the parent, its own
  parent, and so on up to the top, then the category itself. A level rule
  that matches records its whole chain; a deeper chain replaces a
  shallower one (the first rule wins among chains of equal depth). This
  replaces the former level-number ordering: two level-2 sections under
  the same level-1 parent (siblings) now nest correctly, whatever the
  bag's rule order. A dangling parent (deleted or renamed category) stops
  the chain: the rule becomes a top-level section.
- Level categories are display sections: when a Level is selected and the
  rule text is empty, it is filled with `true` (the section name is the
  category name). Conditions may still be used in level rules; ordinary
  (Normal) rules matching after an open path still join it as the deepest
  level.
- The level (and parent) of a category now shows in its tooltip
  (getDesc appends "Level: n - Parent: name"), i.e. in the Category
  dropdowns and the bag rule list tooltips.
- Rules: optional `parent` field validated by isValidRule (category name
  other than its own name) and copied by CopyFrom. New strings in
  en/de/fr/es/ru/zh.
- Verified offline with Lua 5.1: the modified Lua files compile;
  test/RuleLevel_test.lua passes 50 assertions (level/parent validation,
  copies, tooltips and MatchCategoryRules parent chains, siblings,
  dangling parents and cycles, on the delivered files);
  test/CategoryTree_test.lua (113) and test/LibSets_test.lua (1969)
  still pass. Not tested in ESO.

## 2026-11-07: Level dropdown in Edit Category (replaces leveldisplay())

- New **Level** dropdown in the Edit Category section of the settings menu
  (next to the Name and Tag fields): it sets the sub-menu level of the
  category. `Normal` (default) is the ordinary flat category (first matching
  rule wins, unchanged behavior); `1` is a top-level section that keeps
  evaluating the deeper levels; `2`-`5` are nested sub-sections of the level
  above. The level is a property of the rule (saved with it in AutoCatRules),
  so the same rule nests the same way in every bag.
- This replaces the `leveldisplay(depth, section)` rule function, which is
  removed (function, Environment registration and wiki section). A former
  `leveldisplay(1, "premier niveau")` becomes a rule named
  `premier niveau` with Level `1` and rule text `true`;
  `leveldisplay(2, type("armor"))` becomes a rule with Level `2` and rule
  text `type("armor")` (the section is always named after the rule).
- MatchCategoryRules (AutoCategory_API.lua) now reads `rule.level` after the
  rule matched instead of collecting the levels recorded by leveldisplay()
  calls in AutoCategory.AdditionLevelNames. Behavior is otherwise identical:
  the first rule naming a level wins it, a level without a matching rule is
  skipped (gap compaction), a level rule with no higher level open is a flat
  category, an ordinary rule matching before an open path stays flat and one
  matching after joins it as the deepest level, and the final name is joined
  with the CategoryTree separator using the deepest rule's priorities.
- Rules: optional `level` field validated by isValidRule (whole number >= 1,
  no upper bound; the dropdown offers 1-5 and falls back to Normal for
  out-of-range values) and copied by CopyFrom (Copy Category). Predefined
  rules are read-only for the level, like for Name/Tag/Rule.
- Docs updated: wiki/Rule Function Reference.md (Level Display section
  removed), wiki/Creating Custom Categories.md (Building Levels from Rules
  rewritten for the dropdown).
- Verified offline with Lua 5.1: the 10 modified/delivered Lua files
  compile; new test/RuleLevel_test.lua passes 38 assertions (level
  validation, copies and MatchCategoryRules integration on the delivered
  files); test/CategoryTree_test.lua still passes 113 assertions and
  test/LibSets_test.lua 1969 assertions. The other test/* files require the
  author's local LibSFUtils fixtures and cannot run in this checkout
  (unchanged). Not tested in ESO.

## 2026-11-05: leveldisplay() rule function and N-level categories

- New rule function `leveldisplay(depth, section)`: builds nested categories
  from several rules instead of one hardcoded name. `depth` is the section
  level (any whole number ≥ 1, not only 1-3); `section` is either the section
  name (a string) or the condition for the item to belong to that level
  (typically a rule call such as `type("armor")`), in which case the section
  takes the rule's own name. Example bag rules:
  `leveldisplay(1, "premier niveau")`, `leveldisplay(2, type("armor"))`,
  `leveldisplay(3, type("armorlight"))` categorize a light armor item as
  `premier niveau----Armures----Légères`.
- A matching `leveldisplay()` does not stop the rule evaluation: MatchCategoryRules
  (AutoCategory_API.lua) records the levels in AutoCategory.AdditionLevelNames,
  merges them across rules (the first rule naming a level wins it, levels
  without a matching rule are skipped) and joins them with the CategoryTree
  separator at the end of the bag's rule list, using the deepest rule's
  priorities. An ordinary rule matching after an open path joins it as the
  deepest level; before it, it stays flat as usual. Errors: missing section,
  non-whole depth, empty/whitespace name, condition section with no rule name.
- CategoryTree.lua generalized to N levels: Levels/LevelCount/IsHierarchical/
  Ancestors/JoinName/LevelSortKey/IsAnyAncestorCollapsed replace the two-level
  view (Split and IsParentCollapsed kept for compatibility, Split now returns
  all-but-last as parent). BuildSortKey and ParentSortKey handle any depth.
- Hooks_Keyboard.lua: headers of any depth, collapse of any level hides every
  deeper level (transitive, whatever the state of the levels in between), and
  a hybrid category (own items plus deeper levels, e.g. `Armes----Épées` with
  direct items next to `Armes----Épées----Lourdes`) now totals both in its
  header count (previously only its direct items were counted).
- Docs updated: wiki/Rule Function Reference.md (new Level Display section,
  including the `or` vs `and` note — `type("armorlight") and
  type("armormedium")` can never match), wiki/Creating Custom Categories.md
  (N-level names, Building Levels from Rules).
- Verified offline with Lua 5.1: all 65 delivered Lua files compile;
  test/CategoryTree_test.lua passes 113 assertions (N-level API, three-level
  keyboard scenarios, hybrid counts); new test/LevelDisplay_test.lua passes
  39 assertions (function behavior and MatchCategoryRules integration);
  test/LibSets_test.lua still passes 1969 assertions. Not tested in ESO.

## 2026-11-05: Nested collapsible sections for autosettype (LibSets)

- The LibSets plugin now generates a hierarchical category name instead of a
  flat one: `AutoCategory.AdditionCategoryName` is
  `localized type----localized set name` (e.g. `Arène----Chance du valet`,
  `Artisanal----Adversaire d'Oblivion`), reusing the CategoryTree two-level
  display added on 2026-11-03. The inventory shows a collapsible parent
  header per set type (Arène, Artisanal, ...) with the total count of its
  sets, and a collapsible child header per set name with its own count.
  Gamepad shows one-line `type - set name` headers.
- The separate `AutoCategory.AdditionCategorySortName` registration is
  removed: hierarchical sort keys are derived from the category name by
  CategoryTree.BuildSortKey (parent part, then set name, raw Lua string
  ordering — no more zo_strlower normalization). Keyboard and gamepad
  paths share the same key; display priority and ordinary flat categories
  are unchanged.
- adjustName (AutoCategory_API.lua): a hierarchical dynamic name is returned
  as-is instead of being wrapped in the rule name as `rule (type----set)`,
  which would have broken the two levels. The "Show 'Set(name)' for
  autosets" setting still wraps flat dynamic names (autoset, ...).
- Docs updated (wiki/Rule Function Reference.md, Auto Set Type section) and
  test/LibSets_test.lua reclassified: expected names are hierarchical, the
  match helper no longer expects a registered sort name, and checkOrder
  orders follow the raw string ordering (uppercase before lowercase).
- Verified offline with Lua 5.1: all 64 delivered Lua files compile;
  test/LibSets_test.lua passes 1969 assertions with fixtures (the
  Windows-path harnesses were not runnable here before or after this
  change); test/CategoryTree_test.lua still passes 72 assertions. Not
  tested in ESO.

## 2026-11-03: Two-level collapsible categories (CategoryTree)

- New CategoryTree library (CategoryTree.lua, loaded before the hooks). A
  category name containing "----" (four hyphens) is displayed as two
  collapsible levels: a parent header with the text before the separator,
  and child headers with the text after it. Example: rules named
  "Potions----Magie" and "Potions----Santé" render as a "Potions" header
  that expands to "Magie" and "Santé" sub-headers, each collapsible.
- Keyboard inventory (Hooks_Keyboard.lua): items and child headers of a
  collapsed parent are hidden; child headers are indented 30px and show
  only their own text; parent headers show the total count of their
  children. Both levels collapse through the existing saved collapse state
  (parent headers are keyed by the parent name, child headers by their
  full "parent----child" name) and reuse the existing +/- marker, context
  menu and click handling.
- Sort keys: hierarchical names sort parent first, then children, then
  items, by extending the existing "%04d%s" key with a \001 child part.
  Flat category names keep the exact historical key format, so existing
  rules sort exactly as before.
- Gamepad (Hooks_Gamepad.lua): hierarchical names sort the same way and
  display as "parent - child" on one-line headers.
- Edge cases: names with an empty parent or child part are treated as
  flat; only the first separator splits a name; spaces around both parts
  are trimmed; a flat category sharing a parent's name serves as the
  parent header and its items sort directly under it, before the
  sub-categories.
- Integration with the LibSets plugin: BuildSortKey accepts a category's
  registered sort name (AutoCategory.GetCategorySortName) as the base of
  a flat key, so LibSets' localized set sorting and the two-level keys
  work together. Hierarchical keys always use their parent part.
- Verified offline with Lua 5.1: compilation passes for CategoryTree.lua,
  Hooks_Keyboard.lua and Hooks_Gamepad.lua; 72 assertions pass in
  test/CategoryTree_test.lua (library + real blocks extracted from
  Hooks_Keyboard.lua: build, sort, collapsed parent, collapsed child,
  re-sort path, shared name, legacy headers). Not tested in ESO.

## 2026-11-03: Accept set type names in every LibSets language

- String filters for `autosettype()` are now matched against every language
  present in `LibSets.setTypesToName` (de, en, es, fr, pl, jp, ru, zh), not
  only `LibSets.clientLang` with its English fallback. `"Dungeon"`,
  `"Donjon"` and `"Verlies"` all resolve on any UI language.
- Display names and sort keys still use `LibSets.clientLang` with the
  `LibSets.fallbackLang` fallback; only filter matching changed.
- A label shared by several types still prefers the checked item's actual
  type, then any other matching type. Quoted constant names and numeric
  strings remain invalid.
- Update the rule reference and tests: foreign-language labels now match
  (English and German labels on a French UI, French label on an English
  UI), a shared foreign label prefers the actual type, and the
  missing-label fallback cases are kept. Lua 5.1 compilation passes for the
  plugin; 1969 assertions pass with upstream LibSets data and 1969 with
  fixtures. Not tested in ESO.

## 2026-11-03: Restrict filters to numeric IDs and UI names

- Remove the entire `if requestedSetType == nil then` fallback and
  `rawget(_G, constantName)` lookup. No exported constant strings or suffix
  aliases are resolved.
- Only a numeric type ID or a translated type label from the current
  `LibSets.clientLang` (with the existing missing-label fallback) is accepted.
  Names remain case-insensitive. No argument still matches all known types.
- A string such as `"DUNGEON"` only works if it is the current translated
  label (English `"Dungeon"`), not as an alias on a French UI. Numeric
  strings such as `"6"` remain invalid.
- Update examples and tests: reject all 15 quoted global constant names
  even though the actual globals exist, reject foreign-UI labels and numeric
  strings, and exercise localized/numeric rule expressions. Keep the
  fullyLoaded gate, LibSets' cached language and two-level sorting.
  Lua 5.1 compilation passes for all six integration Lua files; 1948
  assertions pass with upstream LibSets data and 1948 with fixtures.
  Not tested in ESO.

## 2026-11-03: Use fullyLoaded and LibSets' cached language

- Delete `isLibSetsAvailable()` and the copied
  `setTypeToLibraryInternalVariableNames` table. Use the explicit condition
  `if LibSets.fullyLoaded then` during initialization and rule evaluation.
  Retain only the separate nil check needed for the manifest's optional
  LibSets dependency. Fully-loaded libraries are now trusted; missing API
  functions/tables surface as errors instead of triggering compatibility
  guards.
- Detect and validate types directly from the live `LibSets.setTypesToName`
  table. Accept its translated type names as filters, case-insensitively,
  in addition to existing numeric IDs and quoted constants/suffixes.
  Shared translated labels match all corresponding type IDs. No private
  type mapping or hardcoded whitelist is maintained.
- Delete `uiLanguage`, the plugin's `GetCVar` call, and plugin-side language
  normalization. Use `LibSets.clientLang`, the library's cached UI default,
  with `LibSets.fallbackLang` / `"en"` for missing or empty labels.
- Preserve type-first/set-second alphabetical ordering, case normalization,
  shared keyboard/gamepad keys, displayed labels, and display priorities.
- A false `fullyLoaded` at initialization installs a dummy rule; there is
  no automatic late activation. Reinitialize or reload after LibSets loads.
- Update behavioral tests to extract and execute LibSets' actual language
  caching block, reject any plugin `GetCVar` call, validate localized filters
  and shared labels, discover a synthetic new type without whitelist edits,
  and exercise false/true `fullyLoaded` and removed compatibility guards.
  Lua 5.1 compilation passes for all six Lua files in the integration path;
  2042 assertions pass both with upstream LibSets tables/language-cache code
  and with standalone fixtures. Not tested in ESO.

Reference: [LibSets language cache and type names](https://github.com/DrNibble/LibSets/blob/LibSets-reworked/LibSets/LibSets_ConstantsLibraryInternal.lua).

## 2026-11-03: Type-first, set-second inventory sorting

- Read type labels directly from `LibSets.setTypesToName[setType]`, using
  the UI language and the `"en"` default/fallback. Replace the old
  `GetSetTypeName` API dependency with a `setTypesToName` table check in
  the existing local `isLibSetsAvailable()` function.
- Generate a separate two-component sort name: localized type name first,
  localized set name second, each lowercased using ESO's native
  `zo_strlower`. Keep the displayed `(type) set name` unchanged.
- Add `AutoCategory.GetCategorySortName` to the plugin API and store custom
  dynamic keys only for successful rule matches. Reset the temporary sort
  name before each rule; clear old dynamic keys on ordinary matches.
- Use the shared lookup in keyboard and all five matched gamepad
  inventory/crafting/store key-generation sites. Preserve display priority,
  ordinary category ordering, and headers before their items. Parent rule
  titles no longer override the type/set order; exact display labels are
  a final tie-breaker to keep distinct case-folded groups contiguous.
- This is two-level ordering, not a nested/collapsible type-header UI.
  Different display priorities still dominate; use equal display priorities
  across filtered rules for a common alphabetical ordering. Normalized Lua
  string ordering is not accent-folded dictionary collation.
- Extend the Lua 5.1 harness to load the real matching API and extract the
  real keyboard/gamepad key producers and comparators in shared chunks.
  Test French/English/fallback ordering, mixed case, translated type order,
  prefix types, parent title settings, case-only label collisions, stale
  keys, ordinary categories, and retained display priorities.
  Lua 5.1 compilation passes for all six changed Lua files; 2087 assertions
  pass with actual LibSets constants/translations and 2070 with standalone
  fixtures. ESO native APIs remain simulated; not tested in ESO.

References: [LibSets translations](https://github.com/DrNibble/LibSets/blob/LibSets-reworked/LibSets/LibSets_ConstantsLibraryInternal.lua),
[ESO native lowercasing API](https://github.com/esoui/esoui/blob/live/ESOUIDocumentation.txt),
[ESO string ordering](https://github.com/esoui/esoui/blob/live/esoui/libraries/utility/zo_tableutils.lua).

## 2026-11-03: Restore the local availability check

- Restore the original local `isLibSetsAvailable()` and its calls during
  initialization and rule evaluation. Check LibSets' presence, `GetSetType`,
  `GetSetTypeName`, and the `allowedSetTypes` table.
- Remove calls to `IsLibSetsAlreadyLoaded(true)`, including its repeated chat
  output and its fully-loaded/version requirements.
- Keep the literal type mapping copy, inline argument validation, UI
  language and `"en"` fallback. This is a selective revert, not a revert
  of the entire previous commit. Only `plugins/libsets-autosettype` changes.
- Test that the removed global check is never called, even when present,
  and that missing APIs safely return false. Lua 5.1 compilation passes;
  644 assertions pass with upstream constants/tables and 627 with fixtures.
  Not tested in ESO.

## 2026-11-03: LibSets load check and copied type mapping

- On `plugins/libsets-autosettype`, remove `isLibSetsAvailable` and call
  `IsLibSetsAlreadyLoaded(true)` during initialization and rule evaluation.
  If the global check is absent or returns false, use the dummy rule or
  return false respectively.
- Remove `resolveSetType`. Copy the literal
  `LibSets.setTypeToLibraryInternalVariableNames` table into initialization,
  after LibSets' constants are available. Use the copy to validate IDs,
  retaining numeric IDs and quoted constant names/suffixes as arguments.
- Keep the UI language and `"en"` fallback unchanged.
- The copied mapping must be updated if LibSets changes its types.
  The `true` load-check argument intentionally emits LibSets' chat message
  on every successful call, including each item evaluated.
- Extend tests to exercise the actual LibSets load-check function, compare
  the plugin's actual mapping upvalue against the upstream literal table,
  and check unloaded/old-version/absent-library behavior.
  Lua 5.1 compilation passes; 630 assertions pass against real LibSets
  code/tables and 613 with standalone fixtures. Not tested in ESO.

## 2026-11-03: Explicit UI language and English fallback

- Read `GetCVar("language.2")` for LibSets type labels, normalize the language
  to lowercase, and explicitly pass it to `LibSets.GetSetTypeName`.
- Default to `"en"` if the UI language is missing, empty, or not supported
  by LibSets. Keep the English fallback if a translated type label is missing.
  The set name still comes from ESO in the UI language.
- Extend the Lua 5.1 behavioral tests to cover French, German, English,
  uppercase language codes, nil/empty/unsupported/disabled languages,
  unavailable `GetCVar`, and missing translations. Compilation passes, as do
  608 assertions with fixtures and 608 with the actual LibSets constants and
  translations. Not tested in ESO.

## 2026-11-03: LibSets auto set type plugin

- Add `AutoCategory_LibSets.RuleFunc.AutoSetType(setType)`, registered as
  `autosettype()` through the existing plugin API.
- Generate `AutoCategory.AdditionCategoryName = "(" .. setTypeName .. ") " .. setName`.
  Use LibSets' localized type name and ESO's localized set name.
- Optionally filter by numeric type ID or quoted constant name/suffix.
  Resolve exported constants and validate against `LibSets.allowedSetTypes`
  rather than copying the private `possibleSetTypes` table.
- Declare LibSets as an optional dependency and register a dummy rule if absent.
  Missing/unready set data returns false, without altering the dynamic name.
- Document usage and add a standalone behavioral harness loading the actual
  plugin and plugin API files, with no external test framework.
- Verification: native Lua 5.1 compilation via `lupa.lua51`, plus 395 passing
  behavioral assertions both with standalone fixtures and with the actual
  constants/translation tables extracted from LibSets commit
  `76f2adab4e495f0b3ddb9884cb10c47f32e9f4b1` on `LibSets-reworked`.
  Not tested in ESO. No automatic migration of existing bag rules or merging
  of perfected/non-perfected sets.

References: [existing plugin API](https://github.com/DrNibble/AutoCategory/blob/master/Plugin_API.lua),
[LibSets constants](https://github.com/DrNibble/LibSets/blob/LibSets-reworked/LibSets/LibSets_ConstantsLibraryInternal.lua),
[LibSets API](https://github.com/DrNibble/LibSets/blob/LibSets-reworked/LibSets/LibSets.lua),
[ESO live API documentation](https://github.com/esoui/esoui/blob/live/ESOUIDocumentation.txt).
