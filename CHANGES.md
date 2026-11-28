# Changes

## 2026-11-28: fold a level-1 header again (5.1.4)

- Clicking the level-1 header of a hierarchy whose top name carries no
  rule of its own ("Potions" for a category named
  "Potions----Magie----Soin") is no longer ignored: the header folds and
  unfolds its whole subtree again, and the state survives a refresh.
- Cause: the collapse state only received the categories of the list, never
  the intermediate header levels built from the level chain, so
  SetCategoryCollapsed considered the level-1 header unknown and returned
  without doing anything. createNewScrollData now hands it every header
  name as well.
- Test: test/HeaderLevel1Collapse_test.lua (10 assertions) replays a
  three-level hierarchy through the ApplySort prehook, folds and unfolds
  the level-1 header. Not tested in ESO.

## 2026-11-27: the new strings in every language (5.1.3)

- German, Spanish, Russian and Chinese now carry the strings of the two
  previous entries: the warning of the Delete button, the Delete category
  dialog and its refusals, the two placements of a dropped category, and
  the sentence about right-clicking the left column in the hint.
- The six keys are present in every shipped language, English and French
  included, and each one keeps the quoting style of its file.
- 404 assertions in CategoryLevelMenu_test, the other suites unchanged.
  Not tested in ESO.

## 2026-11-27: choose the placement of a dragged category (5.1.2)

- Dragging a category header onto another header of the same inventory no
  longer nests it straight away: a small menu opens on the destination with
  the dragged category and two placements, "Level 1 (its own top-level
  category)" and "Child of <destination>".
- A placement that cannot apply stays visible but inert: the destination is
  the category itself, one of the categories nested under it, its current
  parent, or more than one level short of its depth budget, or the category
  already sits at level 1. When neither placement applies, no menu opens.
- The read-only test lives in CLM.CanMoveSubtreeToParent, which shares the
  new planSubtreeMove with CLM.MoveSubtreeToParent: the drag and the Move To
  submenu decide on the same plan, and the predicate edits nothing.
- The drop menu reuses the internal menu of the addon, anchored on the
  destination header.
- 404 assertions in CategoryLevelMenu_test (27 new). Not tested in ESO.

## 2026-11-27: delete a category from the left column (5.1.1)

- Right-click a category of the left column (the categories not used in this
  inventory) to open a "Delete category" entry. It asks for a confirmation
  with the same kind of warning as the Delete button of the category
  settings, then removes the category from the rule definitions and from
  every inventory. The manager hides itself while the dialog is up and comes
  back on the same tab, with a draft rebuilt on the updated saved variables.
- Refuse the deletion while the manager holds pending edits: apply or cancel
  them first, like switching inventory or creating a category.
- The delete entry is inert for a predefined category, and "(read-only)" is
  now appended to its name in the left column instead of appearing only in
  the tooltip.
- The shared removal lives in AC.DeleteCategory, used by both this menu and
  the Delete button. The Delete button now also passes its warning text to
  the confirmation dialog of LibAddonMenu, which was empty, and removes every
  copy of the category from an inventory rather than the first one only.
- The labels stay translated: new SI_AC_CATEGORY_MANAGER_DELETE,
  SI_AC_CATEGORY_MANAGER_DELETE_WARNING, SI_AC_CATEGORY_MANAGER_DELETE_PENDING
  and SI_AC_MENU_EC_BUTTON_DELETE_CATEGORY_WARNING strings in English and
  French; other languages fall back to English.
- CategoryManagement suite: 682 assertions, all other suites unchanged, every
  file compiles with Lua 5.1.
- Not tested in ESO.

## 2026-11-27: upstream 4.7 merged (5.1.0)

- Import the eleven commits of the upstream master branch (4.6.16 to 4.7.1).
  They add the category collapse expiry saved in collapseExpiry, a separate
  AC_Collapsed.lua, CVT:assignNE for a plain list of choices, the gamepad
  sort key that no longer formats a nil category name, ipairs in the gamepad
  lists, the extended gamepad supplies defaults and the Lower Level rule
  that includes level 1 gear again. misc/BagSet_Service.lua comes along but
  is not loaded, as upstream.
- The template change is resolved in favour of this branch: the collapse
  module replaces the inline functions of AutoCategory.lua, Expand All and
  Collapse All call it, the tag dropdowns keep their tagListCVT() source and
  the header context menu keeps addItem. The reconciliation added to
  Hooks_Keyboard is guarded with type(...) so the harnesses that do not load
  AC_Collapsed still run.
- The two general saved-variable defaults upstream added read their source
  from defaultAcctSettings.general / defaultCharSettings.general, since
  defaultAcctBagSettings has no general table.
- All 21 suites of test/ behave as before the merge (same passes, same
  pre-existing failures), and every file compiles with Lua 5.1.
- Not tested in ESO.

## 2026-11-27: the rule of a category is no longer truncated (5.0.2)

- The Rule submenu of a category header shows the whole rule expression.
  A menu row draws one line clamped with an ellipsis, so the lines are now
  measured with the row font and split until each one fits the panel width.
  A single word wider than the panel on its own (a long isitemid() list) is
  cut rather than ellipsized. The rule text itself is unchanged.
- Not tested in ESO.

## 2026-11-24: create categories from Manage Categories

- Add a New Category button below the left column. It opens the existing
  dialog for the selected inventory and returns to the same tab afterward.
- Refresh the lists after creation. Apply or cancel pending manager edits
  before opening the creation dialog. Not tested in ESO.

## 2026-11-24: sort the New Category parent dropdown by name

- List eligible parents alphabetically, ignoring case, with None first.
  Keep the clicked parent selected and leave inventory priorities unchanged.
  Not tested in ESO.

## 2026-11-24: keep execution and display order separate

- Bag Settings and its order window use the inventory's display keys
  at every level, including for siblings and parents in another bag.
- The display list sorts a copy; the saved rule list is sorted for
  execution before the order window renders. Not tested in ESO.

## 2026-11-23: manage category branches from the list

- Add space under the inventory dropdown and show the selected level
  (1–5) between the horizontal arrows. Mixed selections show their levels.
- In Display Priority, move branches with their descendants. The right
  arrow nests under a preceding eligible sibling; the left arrow promotes
  the branch one level.
- Right-click opens actions for the selection: copy branches to checked
  inventories, remove from the current inventory (promoting remaining
  children), or attach to a named parent. Apply saves the draft, including
  queued copies; Cancel discards it. Not tested in ESO.

## 2026-11-23: hide display-priority numbers in Manage Categories

- Display Priority shows category names and indentation without the
  numeric prefix. Execution Priority still shows its numbers. Not tested in ESO.

## 2026-11-23: switch inventories in Manage Categories

- The dropdown under the title lists all inventory types and starts on
  the inventory whose context menu opened the window.
- Changing inventory refreshes both lists and keeps the priority tab.
  Apply or cancel unsaved changes before switching inventories.
  Not tested in ESO.

## 2026-11-23: match inventory display order in Manage Categories

- Display Priority uses the inventory's category paths and sort keys.
  Parents stay above their subcategories, and display priority sorts
  categories that share a parent. Draft layout changes are previewed
  before Apply, including categories without a visible inventory header.
- Display-priority arrows and drag-and-drop reorder siblings without
  changing parent links or execution priorities. Not tested in ESO.

## 2026-11-23: select multiple categories in Manage Categories

- Ctrl+click toggles a category on the right; Shift+click selects a
  range of filtered rows. Ctrl+Shift+click adds a range. The vertical
  arrows move the selection without changing its relative order.
- Switch between execution and display priority above the list.
  Display priority controls the order of siblings in the inventory;
  it does not change the order in which rules run.
- The horizontal arrows shift the selected branches together; selecting
  both a parent and its child does not shift the child twice. If one
  branch reaches a level limit, the whole shift is blocked. Changes
  remain in the draft until Apply. Not tested in ESO.

## 2026-11-22: filter and change levels in Manage Categories

- Both lists have independent name filters. The right list stays sorted
  by execution priority and indents categories by three spaces per level
  below the top level.
- The right list shows categories with no header in the originating
  inventory list in grey, and categories marked hidden in red.
- Select a category on the right and use the horizontal arrows below
  the list to raise (left) or lower (right) its level. The same-bag
  subtree follows the existing level rules. Apply saves the changes;
  Cancel discards them. Levels and parents are shared across inventories
  that use the same categories. Not tested in ESO.

## 2026-11-22: share the inventory move destinations

- Move To on headers and Move to Category on items share the configured
  category list, including empty or collapsed categories but excluding
  hidden entries. Subheaders use three spaces per displayed level.
- Ineligible destinations are shown dimmed: impossible hierarchy moves
  on headers and predefined rules on items. The item submenu opens beside
  the native context menu with the same search and scrollable list.
  Updated all six languages. Not tested in ESO.

## 2026-11-22: choose a parent when creating an inventory category

- New Category remembers the clicked category's name and level and
  preselects it when eligible. The native Parent dropdown offers
  non-hidden categories from this bag at effective levels 1 to 4,
  including categories under collapsed headers. Choose no parent to
  keep the existing Normal creation behavior.
- The new category gets the selected parent's level plus one. A category
  created at level 5 has no hidden placeholder child. Stale selections
  are refused without saving. Updated all six languages. Not tested in ESO.

## 2026-11-22: drag inventory category headers

- In keyboard inventory, hold the left mouse button and drag a category
  header onto another category header of the same bag to make it a child.
  This runs the same operation as Move To: descendants move along with
  the category, while invalid drops (including a cycle or a depth above
  level 5) leave the layout unchanged.
- A simple left click still folds or unfolds the header, and right-click
  still opens its menu. Generated headings without their own bag rule and
  legacy headings made from separator-delimited category names cannot be
  dragged or used as parents. Not tested in ESO.

## 2026-11-20: manage categories in the selected inventory

- AutoCategory no longer requires LibScrollableMenu. Its Lua/XML menus
  keep the Move To search, destination order and indentation, the
  Rule priority slider and the Copy To destination checkboxes. New
  Category uses ESO's native scrollable tag selector.
- Manage Categories opens a persistent window with two internal,
  15-row scroll lists anchored inside the window.
  Search and click on the left to add. On the right, reorder by
  execution priority using the arrows or by dragging, or right-click to
  remove. Apply saves changes for this bag; Cancel discards them.
- The four reorder buttons use ESO's arrow textures for all states
  instead of text glyphs.
- The game's System Menu and Inventory shortcuts cancel the category
  manager without saving. The inventory shortcut follows the game's
  keybinding rather than using a hardcoded key. Escape also cancels
  from the search field.
- Reordering decrements lower priorities by one, adjusting at ties and
  at the priority limits when needed. Existing display priorities and
  global rules are unchanged. Not tested in ESO.

## 2026-11-19: search only in Move To and category title in Rule

- Move To has its own search field, above the indented destinations. The
  main header menu and other hover submenus are not filtered.
- Rule starts with the selected category's display name, above the
  execution-priority slider. Existing ESO translations are reused.

## 2026-11-19: New Category dialog and required LibScrollableMenu

- LibScrollableMenu 2.44 or newer is required. Removed native menu
  fallbacks while keeping standard inventory item actions.
- New Category uses a dedicated dialog with a name field and a scrollable
  tag dropdown. Select no tag, an existing tag, or name a new tag without
  leaving the dialog. Validation and bag-specific creation are unchanged.
  Existing translations are reused. Not tested in ESO.

## 2026-11-19: hover submenus for category headers

- Rule, Level, Move To and Copy To open as side submenus with
  LibScrollableMenu. The header menu has a divider before Rule, and
  the Rule submenu has a divider after the execution-priority slider.
- Move To indents each destination by two spaces per nested level
  without changing the eligible destinations or their order. The search
  field is now at the top of the header menu and can find destinations
  inside the submenus. Copy To keeps its checkboxes and overwrite warning.
- Without LibScrollableMenu, the native submenus remain available with
  the main divider and the same indentation. No translation changes.
  Not tested in ESO.

## 2026-11-19: select multiple bags in Copy To

- With LibScrollableMenu, check the destination bags and use the copy
  action to apply the selection together. A bag that already contains
  the chosen category is red and has an overwrite tooltip.
- Selecting a marked bag replaces the matching entries' per-bag
  priorities and visibility in the copied subtree. Shared definitions,
  existing ancestors and destination-only entries are not changed.
  The native fallback still copies to one bag and skips existing entries.
  Updated all six languages. Not tested in ESO.

## 2026-11-19: execution priority slider in Rule

- The category header's "Rule" menu uses a LibScrollableMenu slider for
  the clicked bag's execution priority. It starts at the current value,
  displays the selected number, and accepts integer values from 0 to 1000.
  The display priority and the rule text are unchanged.
- Bag Settings supports the same execution priority range. Without a
  compatible LibScrollableMenu, the original read-only Rule menu is kept.
  Existing translations are reused. Not tested in ESO.

## 2026-11-19: parent items before subcategories

- In categorized bags, items assigned directly to a parent are displayed
  immediately under its header, before its subcategories and their items.
  This also applies at deeper levels. Display priority orders sibling
  sections, and rule matching is unchanged.
- The same order is used in keyboard and gamepad lists. No new translation
  strings. Not tested in ESO.

## 2026-11-19: search in Move To

- The category header's "Move To" list uses LibScrollableMenu's built-in
  search box to filter destinations by name as you type. The 15-row limit,
  destination order and native fallback are unchanged. No new translation
  strings. Not tested in ESO.

## 2026-11-19: scrollable Move To menu

- The category header's "Move To" entry opens a scrollable list of up to
  15 visible rows when LibScrollableMenu is installed. Destination
  eligibility and order are unchanged, including the "Top Level" entry.
  With no LibScrollableMenu, the original submenu remains available.
  No changes to translations or other menus. Not tested in ESO.

## 2026-11-18: scrollable inventory item categories

- On keyboard, right-click an inventory item and select "AutoCategory" to
  open a scrollable category list with LibScrollableMenu. The list keeps the
  clicked bag's display order, level indentation and editable categories.
- LibScrollableMenu is optional: without it, the original submenu is
  retained. The regular item actions and category header menus are unchanged.
  No new translation strings. Not tested in ESO.

## 2026-11-18: header Rule submenu, Parent dropdown selection (5.0.1)

- The right-click menu of a category header offers a new "Rule"
  submenu (SI_AC_MENU_CM_RULE) right after the execution priority
  display: it holds the run priority of the category and the content
  of its rule - the same text the rule editbox of the settings
  shows. The context menu entries are single-line, so a long rule
  is wrapped over as many entries as needed, cut at word
  boundaries; the strings ship in all six languages.
- Category Settings: the Parent dropdown lost its displayed
  selection after picking a parent - the refresh that rebuilds
  the choices (LAM's UpdateChoices clears the combobox items)
  never restored the displayed text, because a value-holding
  UpdateValue only runs setFunc and never touches the display.
  BaseDD:updateControl now follows the choices rebuild with a
  display-only UpdateValue (no value, no setFunc - no extra
  refresh round), and the redundant updateControl call inside
  CatSet_ParentDD_LAM:setValue is gone: the LAM callback of the
  very selection had already run it.

## 2026-11-17: sub-level collapse entry, guild-bank ghosts, dialog proportions (4.6.28)

- The right-click menu of a category header offers again a
  "Collapse All Sub-Levels" entry (SI_CONTEXT_MENU_COLLAPSE_LEVEL_ALL,
  "Réduire tout le sous-niveau"): it folds every sub-level of the
  selected category at once, exactly like "Collapse All" but scoped
  to the sub-levels of the clicked header. It is offered whenever the
  category has at least one sub-level, and its counterpart
  "Expand All Sub-Levels" ("Développer tout le sous-niveau") whenever
  a sub-level (or the category itself) is folded. They replace the
  per-level "Lower/Raise level" entries; the strings ship in all six
  languages.
- The guild bank showed permanent zero-count headers ("PvP [0]",
  "Commandes scellées [0]") in every bag: orphan "false" rules
  left over from earlier sessions (an abandoned "new sub-level"
  placeholder) kept their parent categories marked as parents of
  a never-matching rule, and the empty-category display showed
  them everywhere. The empty display no longer scans the rules:
  a category created since the UI loaded (CLM.CreatedThisSession,
  set by the New Category dialog) shows right after its creation
  even when "Display empty categories" is off, and the marker is
  cleared as soon as the category matches its first item - after
  that it is an ordinary category again, hidden when emptied. The
  orphan rules themselves are harmless and stay untouched.
- New Category dialog: the name edit box was collapsing to an
  unusable sliver and the OK/Cancel buttons were not centered.
  The layout is rebuilt: the name field always gets an explicit
  width and never shrinks below 160 pixels, the tag dropdown
  gives way first on a cramped row (down to 120), the room
  reserved for the "Tag" label is back to 90, and the buttons
  are centered on the width the edit box row really occupies.
- The tag of a new category is now chosen in the same dialog: picking
  "New Tag..." in the dropdown shows a tag name input row below
  the category name field (the OK and Cancel buttons move under
  it), instead of opening a second dialog after the first one
  closes. A blank tag name is refused without closing the dialog;
  switching the dropdown back to an existing tag hides the row and
  clears what was typed.
- The New Category window is a quarter wider (450 instead of the
  stock 360): the title, the divider and the content grow together
  so the window stays centered on screen, and the extra room goes
  to the name field. The stock width is restored when the dialog
  closes, so the other dialogs that use the same window are
  unaffected.
- The level and the parent of a predefined category can now be
  changed in Category Settings: the Level and Parent dropdowns are
  enabled for them (their name, tag, description, rule and deletion
  stay protected). The change is kept as an override in the account
  saved rules and re-applied at every load - the predefined
  definitions themselves come from the addon code and are never
  saved. The same persistence now covers the level and parent
  operations of the category context menu (one level deeper or
  shallower, move under another category), and a reset to defaults
  clears the overrides.

## 2026-11-16: header menu rework, tag dropdown, predefined rules, collapse all (4.6.27)

- The header right-click menu is reorganized: the execution priority
  first, then the level operations grouped in a "Level" submenu
  (Monter / Abaisser / Relever / Descendre: move one display position
  up, nest one level deeper, un-nest one level, move one display
  position down - each inside its existing limits, and an
  inapplicable operation is not offered), then the "Move To" and
  "Copy To" submenus, "Remove the category from display" and "New
  Category" last. The removal takes the category out of the inventory list
  of the clicked bag only: the global rule stays and the categories
  nested under it move up one level (the previous "Delete Level"
  behavior). It is neither hiding the category (its children would
  vanish with it) nor deleting the rule.
- Each entry of the Level submenu carries a Unicode arrow that
  pictures the operation: "↑" to move one display position up, "↓"
  to move one display position down, "→" to nest one level deeper
  and "←" to un-nest one level.
- Monter / Descendre (the Level submenu and the Display Order
  window) now take the display priority of the category displayed
  just above / just below and step one past it (+1 / -1): the
  category lands directly above / below that neighbor, passing its
  whole priority group, and the other categories keep their
  priorities (the previous behavior swapped the priorities with the
  adjacent group). A category with no displayed neighbor in the
  direction (alone in the bag, or already at that end) is not
  offered the move, and the result must stay inside the 2..1000
  slider range.
- The neighbor search follows the visible display order of the
  bag: the neighbor is the category whose header is actually
  displayed just above / below the moved one (read from the
  inventory lists), so a hidden or empty category is never a
  neighbor. Sub-level headers are not neighbors of a top-level
  category either (the search stays among the displayed siblings
  of the same level); the ungrouped "Others" section has no
  priority and stays out of it. When the inventory lists are not
  built yet, the bag rules stand in for the visible order.
- A predefined (protected) rule keeps its level and its display
  priorities editable through the menu, and can be removed from
  the display of the clicked bag like any other category: the
  global rule stays (a protected rule is never deleted, it only
  leaves the inventory list of the bag) and its nested categories
  move up one level.
- New Category: the tag is now chosen in a dropdown directly beside
  the name edit box (the existing tags sorted, the empty tag and
  "New Tag..."), replacing the follow-up context menu; the edit box
  is narrowed to make room. The default selection stays the empty
  tag, so a plain submit keeps the previous default behavior.
- The OK and Cancel buttons of the New Category dialog are centered
  horizontally under the edit box row, on their texts (SI_OK /
  SI_DIALOG_CANCEL): each button also carries its key label ([E],
  [ALT]) and its paddings on the left of its text, so the pair is
  positioned from the name labels instead of the button boxes (the
  dialog framework anchors them to the bottom right corner by
  default; the framework's spacing and vertical offset are kept).
- "Collapse All" now folds every category of the bag, not only the
  already folded ones: the names come from the displayed headers and
  from the parent chains of the bag rules, so the levels hidden
  under an already folded parent are collapsed too.
- Translations updated (fr / en / de / es / ru / zh) for the new
  menu entries; the old level entry strings were removed.
- Updated suites and harness: the menu structure expectations, the
  predefined rule (operations without removal), the dialog flow with
  the tag dropdown and the placeholder child tag. CategoryLevelMenu
  184, CategoryCreation 146 assertions pass; RuleLevel 78,
  CategoryTree 140, ScrollCommit 37, ParentDD 15, LevelMenu 55,
  LibSets 2586 unchanged and passing (3241 in total).
- Non testé dans ESO. Verify in game: right-click a category header
  and check the new menu order and the Level submenu; change the
  level of a predefined rule and check the removal is absent; create
  a category and pick its tag in the dropdown; collapse all on a bag
  with several nested levels and check every level folds.
## 2026-11-15: autosettype under its category, new category visible, run priority (4.6.26)

- autosettype rule (LibSets plugin): the category name now heads the
  dynamic list. A hierarchical dynamic name used to be displayed as-is
  ("Type----Set name"), so the sets showed detached from their
  category. The category name is now the first level
  ("Category----Type----Set name"), both for a top-level category and
  for a level 2-5 category (where the dynamic levels follow the
  category's own name under its parent chain). The plain (non
  hierarchical) dynamic names and the set-title option are unchanged.
- A newly created category is now visible right away, even with the
  "Show Empty Categories" setting off: creation adds a hidden
  placeholder sub-category to the new category (a "false" rule nested
  under it, shown as "Name (empty)" in the rules list). The placeholder
  never matches anything so it never displays, but it keeps the new
  category a structural parent, so its header shows (with a zero
  count) until items land in it. With the setting off, only the
  categories carrying such a placeholder are shown when empty - an
  ordinary emptied category stays hidden. The placeholder is an
  ordinary category: it can be edited (to put items in it) or deleted
  like any other.
- The header right-click menu now shows the numeric execution
  priority of the category ("Execution Priority: N"), read-only, from
  the bag rule of the clicked bag. The display order (showpriority)
  stays what the Move Category Up/Down entries change.
- Updated suites and harness: the placeholder child of CreateCategory
  (rule false, level 2, hidden bag rule), the menu entry and its
  place in the captured menus, the new expected dynamic names
  ("Category----Type----Set") and the option-off empty display of a
  marked category. RuleLevel 78, CategoryTree 140,
  CategoryLevelMenu 156, ScrollCommit 37, ParentDD 15, LevelMenu 55,
  CategoryCreation 133, LibSets 2586 assertions pass, plus the 24
  assertions of the createNewScrollData empty-categories harness.
- Non testé dans ESO. Verify in game: create a category and check it
  appears empty at once; right-click its header and read the
  execution priority; drop a set item in an autosettype category and
  check the category name heads the list.

## 2026-11-15: Tag choice at creation, empty categories, priority moves (4.6.25)

- New category from the header right-click menu: after the name is
  validated, a context menu now offers every existing tag, the empty
  tag (the previous default) and "New Tag...", a small dialog that
  creates the category with a brand new tag. The tag list is read
  live, so tags created during the session are offered. Cancelling
  the menu or the dialog creates nothing; a failure at creation
  (priority compaction limit) is reported in the chat window.
- New setting "Show Empty Categories" (General Settings, off by
  default): when on, the inventory lists show a zero-count header for
  every non-hidden category of the bag, even when no item matches its
  rule. This answers why a new category did not appear: headers are
  only built from matched items, and a new category is created with
  the rule false. Intermediate headers of an empty hierarchical
  category are shown too; hidden categories and a fully empty list are
  not affected (an empty list is not rebuilt at all). Keyboard lists
  only.
- "Move Category Up" / "Move Category Down" in the inventory header
  right-click menu and in the Display Order window context menu: swap
  the category's display priority with the adjacent priority group,
  so the category moves exactly one display position and the other
  categories keep their relative order. Without an adjacent group the
  priority steps by one. The display priority stays inside the 2..1000
  slider range; execution priorities (runpriority) are never touched.
- Lua 5.1 harness on the delivered blocks and updated CategoryCreation
  suite: the name dialog now hands over to the tag menu (blank and
  duplicate names still keep the dialog open), the tag menu creates
  the category with the chosen tag, the new-tag dialog refuses blank
  names, MoveCategoryPriority swaps adjacent groups, respects the
  2..1000 bounds, refuses moves outside them and never touches
  runpriority. createNewScrollData harness: empty categories appear
  only when the setting is on, hidden ones never, hierarchical empty
  categories feed their parent headers, collapsed ancestors still
  suppress them, and matched categories are unaffected. Regression
  suites re-run: RuleLevel 78, CategoryTree 140, CategoryLevelMenu 146,
  ScrollCommit 37, ParentDD 15, LevelMenu 55, CategoryCreation 119
  assertions pass, plus the 20 assertions of the createNewScrollData
  empty-categories harness (610 total).
- Non testé dans ESO. Verify in game: create a category from a header
  right-click and pick a tag; toggle Show Empty Categories; move a
  category up and down from the header menu and the Display Order
  window.

## 2026-11-15: Tag dropdowns repopulated and self-healing (4.6.24)

- Root cause of the always-empty, disabled Étiquette dropdowns: the
  delivered CVT class (classes/CVT.lua) silently ignores assign() calls
  that pass a plain table ({ choices = ... } has no GetUses), while every
  tag-dropdown call site (CatSet_Init, BagSet.Init, the tag-dropdown
  setValue refreshes) passed exactly that. The tag lists were therefore
  never populated in any session, leaving the dropdowns empty and grayed
  (disabled = size() == 0) and the tag selection impossible from the UI.
- New shared helper AC_UI.tagListCVT() (settings/UI_Utilities.lua)
  builds a real CVT source (USE_NONE, matching the tag dropdowns) from
  the live RulesW.tags list; all four plain-table assign call sites now
  use it (CategorySettings CatSet_Init and tag setValue, BagSet Init and
  AddCat tag refresh).
- Self-healing refresh: CatSet_SelectTag_LAM:refresh() and
  AC_UI.AddCat_SelectTag_LAM:refresh() now resynchronize their choices
  from RulesW.tags on every refresh instead of relying on the startup
  snapshot, so tags created or removed during a session appear without
  a reload and a bad startup no longer keeps the dropdown dead all
  session. CVT:assign keeps the current selection when it is still in
  the list and falls back to the first entry otherwise.
- Panel-open resync: the LAM-RefreshPanel callback (fired by LAM2 when
  the panel opens and whenever a control value changes) now calls
  RefreshDropdownData + RefreshControls, so the dropdowns recover as
  soon as the settings panel is opened.
- Lua 5.1 harness on the delivered blocks (classes/CVT.lua,
  classes/BaseUI.lua, UI_Utilities.lua, CategorySettings.lua): proves
  the old plain-table assign is a no-op (size stays 0) and that the new
  helper populates the list (3 tags), refresh self-heals a cleared
  dropdown, preserves a still-valid selection, falls back to the first
  entry when the selected tag disappears, is safe with a nil tag list
  and idempotent across repeated refreshes. Regression suites re-run:
  78 rule-level, 140 category-tree, 138 category-menu, 55 level-menu,
  37 scroll-commit and 15 ParentDD assertions pass (463 total).
- Non testé dans ESO. Verify in game that the Étiquette dropdown of
  Select Existing Category (and of Add Category in Bag Settings) is
  populated and enabled, and that creating a new tag shows up without
  a /reloadui.

## 2026-11-15: Tag edit no longer errors out in Edit Category (4.6.23)

- CatSet_TagEdit_LAM:setValue (settings/CategorySettings.lua) crashed with
  "attempt to index a nil value" as soon as the tag editbox lost focus,
  including with an unchanged value: lines 783-785 referenced
  AddCat_SelectTag_LAM / AddCat_SelectRule_LAM without the AC_UI. prefix.
  Those names are locals of settings/BagSet.lua, nil in this file. The
  crash aborted the whole tag change UI sync (Add-Category dropdowns and
  RefreshControls) after the rule's tag had already been updated in
  memory, leaving the settings screens out of sync and an error popup on
  every focus loss. This blocked setting the tag of a category created
  with the empty tag (e.g. via the header context menu "New Category").
- Fix: use AC_UI.AddCat_SelectTag_LAM / AC_UI.AddCat_SelectRule_LAM,
  matching the pattern already used at lines 581-583, 631-635 and
  695-696 of the same function's file. No behavior change beyond the
  crash: the Add-Category tag/rule dropdowns and the controls refresh
  now run to completion.
- Lua 5.1 harness on the delivered blocks: the original file reproduces
  the exact user error (setValue with unchanged "<vide>" tag), the fixed
  file completes unchanged-value, real tag change (rule moved between
  tag groups, empty tag pruned) and return-to-empty-tag scenarios.
  Regression suites re-run: 78 rule-level, 140 category-tree,
  138 category-menu, 55 level-menu, 37 scroll-commit and 15 ParentDD
  assertions pass. BagSet_Test remains unrunnable outside the author's
  environment (LibSFUtils fixtures with Windows paths), unchanged.
- Non testé dans ESO. Verify in game that editing the tag of a category
  created with the empty tag no longer shows an error and that the
  category then appears in the bag once added (Bag Settings, Add
  Category with its tag selected).

## 2026-11-15: Named Normal category from the header context menu (4.6.22)

- Replace "New Sub-Level" with "New Category". Open an ESO text-entry dialog
  instead of silently creating an automatically named child category.
- Trim the entered name; reject blank or duplicate names, including
  case-insensitive global matches and existing saved bag entries. Show the
  error in the same dialog without closing it or changing the saved rules.
- Create the category only in the clicked bag, with rule text "false",
  Normal level (no level value) and no parent. Capture the bag when opening
  the dialog so a subsequent selection change cannot redirect creation.
- Assign the highest display priority in the clicked bag automatically,
  then refresh caches and inventory lists without opening the ordering window.
  If priority 1000 is occupied, compact existing display-priority groups
  below it, preserving their order and ties. Leave execution priorities and
  other bags unchanged. Refuse creation without mutation if all 999 supported
  distinct priority values are occupied.
  A false rule initially matches no items; do not manufacture item matches
  or change the inventory's empty-header behavior to imply otherwise.
- Offer creation on ungrouped/predefined headers and at level 5, independently
  of level operations. Cancel and failed validation create nothing.
- Translate the new menu/dialog strings in en/de/fr/es/ru/zh; retain the
  guild-bank ordering fixes and the removal of trace/retry workarounds.
- Lua 5.1: 70 creation/dialog, 138 category-menu, 37 scroll-commit,
  140 category-tree, 78 rule-level and 2242 LibSets-fixture assertions pass
  (2705 total); 48 delivered/test Lua files compile.
- Non testé dans ESO. Verify naming, rejection of a duplicate, cancellation
  and automatic first position without opening the ordering window in game.

## 2026-11-15: Remove guild-bank diagnostics and workaround timers (4.6.21)

- Remove GuildBankTrace.lua and its manifest entry, /acgbtrace, /acdebug,
  bank diagnostic logs, the empty-list retry and the guild-bank polling
  handlers/timers. An empty list now returns immediately; normal ESO list
  refreshes use the existing ApplySort hook once items are available.
- Keep the actual 4.6.20 fixes: category-aware sorting before every rebuilt
  list commit, preservation of fully collapsed parent sort keys, and the
  scroll-list commit needed to calculate entry positions.
- Keep the original logger, its dependency and unrelated existing item-update
  timer. Do not remove pre-existing addon infrastructure as diagnostic code.
- Replace trace/retry tests with checks for normal guild-bank sorting,
  repeated clear/refill cycles, standalone rebuilding, valid scroll positions,
  no queued bank callback, and hook/timer cleanup.
- Lua 5.1: 37 scroll-commit, 140 category-tree, 78 rule-level, 137 category-menu
  and 2242 LibSets-fixture assertions pass (2634 total); 47 Lua files compile.
- The user confirmed 4.6.20 functional in ESO. This stripped 4.6.21 build is
  not yet tested in ESO; removal of polling needs in-game confirmation.

## 2026-11-15: Sort every rebuilt keyboard list before committing (4.6.20)

- The new capture shows a correctly sorted guild bank being overwritten by
  the empty-list retry: createNewScrollData appends headers after surviving
  items, but the standalone rebuild commits without an enclosing ApplySort.
  Headers remain present, so the old poll does not detect the broken order.
- Sort rebuilt data with the category-aware comparator before every commit,
  covering normal sorting, delayed retries and standalone updateHook calls.
  Preserve the commit needed to calculate header scroll positions.
- Cancel delayed empty-list retries after a guild selection/items-ready
  generation change, selected guild change, list replacement, addon disable,
  bulk mode or keyboard unhook.
- Preserve intermediate parent header sort keys when rebuilding already
  collapsed output. With no child items to feed their priority, those keys
  were otherwise lost (nil), making parent ordering unreliable.
- Trace REBUILD_SORTED/REBUILD_COMMITTED and headerMissingKeys. Allow a bounded
  manual marker/snapshot after the automatic trace line cap, without resuming
  continuous logging; the real capture's marker came after that cap.
- Lua 5.1: 56 diagnostic, 24 scroll/retry integration, 140 category-tree,
  78 rule-level, 137 category-menu and 2242 LibSets-fixture assertions pass
  (2677 total). A new two-collapsed-parent regression fails on the old code.
- No claim of a Swiss Knife conflict: it is present in the capture but the
  demonstrated bad rewrite is AutoCategory's own delayed rebuild.
  Not tested in ESO; the new build still needs visual confirmation.

## 2026-11-15: Opt-in guild bank trace through sorting and rendering

- Version 4.6.19 (159). Add `/acgbtrace on|off|mark <symptom>|dump`,
  disabled by default, using LibDebugLogger Info independently of `/acdebug`.
- Observe UpdateList, ApplySort, list clear/commit, reconstruction, deferred
  retries, polling and header setup. Log selected guild, generation, list/data
  identity, sequence checksum, missing rules/positions, category-order
  inversions, visible/active headers and current header controls.
- Record enabled addon versions for A/B comparisons, filtering decisions for
  actual items, and bounded caller stacks. No additional repair or sort.
  Existing delayed rebuilds may commit before any caller sort: this trace
  exposes that path rather than assuming headers present means correct UI.
- Bound capture to 2500 messages and 32 caller stacks; guard delayed samples
  against stale session/generation/guild/list/sort and keyboard mode changes.
- Add a Lua 5.1 behavioral harness loading the delivered module and a French
  capture/A-B guide in `wiki/Guild Bank Diagnostics.md`.
- Lua 5.1: 53 diagnostic assertions and 19 scroll-commit/integration checks
  pass, including observation (without repair) of an unsorted delayed rebuild.
  Regression suites pass: RuleLevel 78, CategoryTree 125, CategoryLevelMenu 137,
  LibSets 2242 with standalone fixtures (2654 assertions in total).
- Not tested in ESO. Existing visual defect remains unconfirmed/unresolved;
  the new logs are intended to distinguish an internal ordering/rendering
  problem from interference by Swiss Knife or another addon.

## 2026-11-14 (23): /acdebug command to toggle the debug logging

- The debug logs added in (22) never reach LibDebugLogger: the debug
  logging of AutoCategory is disabled by default (the SetDebug call
  is commented out) and the minimum log level of LibDebugLogger
  must be lowered to "Debug" as well.
- New /acdebug command (with optional on/off argument, toggles when
  omitted) turns the debug logging of AutoCategory on and off at
  runtime; the state is confirmed in the chat and logged. It does
  not persist across sessions.
- Version bumped to 4.6.18.

## 2026-11-14 (22): Guild bank headers: safer poll and debug logs

- Entry (21) polled the list and ran the full list update
  (UpdateList) whenever items showed up without headers; in the
  game the display stayed broken. Two risks identified: UpdateList
  repopulates the list from the inventory slots and can empty it
  while the text search results of the new guild are not ready
  yet, and the poll only detected missing headers, not items
  displayed without their rule results (the "jumbled" case).
- The poll now sorts the list again with ApplySort instead: it
  only re-sorts what is already displayed, and its sort hook
  re-runs the rules, adds the headers and sorts everything under
  them. The poll also treats entries without rule results
  (AC_sortPriorityName) as needing a sort, not only missing
  headers.
- The poll now starts on both EVENT_GUILD_BANK_SELECTED and
  EVENT_GUILD_BANK_ITEMS_READY (a newer event cancels the older
  poll) and watches the list for about 10 seconds.
- Debug logs (LibDebugLogger, prefix [AC]) added to the sort
  prehook (skipped: no ready scene / bulk mode), to the guild bank
  empty-list retry and to the list rebuild (entry counts), to
  diagnose the remaining cases in the game.
- Version bumped to 4.6.17 so the loaded build can be verified
  in the addon list.

## 2026-11-14 (21): Guild bank headers: poll and run the full list update

- Entry (20) rebuilt the headers directly after
  EVENT_GUILD_BANK_ITEMS_READY; in the game the headers were still
  missing: the addons that filter the inventory lists (Advanced
  Filters) rebuild the list again after the switch without going
  through the sort hook, so the directly rebuilt headers never
  reached the final list.
- The handler now polls the guild bank list for about four seconds
  after the new guild's items are ready (every 200 ms, twenty
  attempts) and, whenever items are displayed without category
  headers, runs the full path of a list update -
  PLAYER_INVENTORY:UpdateList(INVENTORY_GUILD_BANK), which sorts
  and commits through the addon's sort hook. That is the same
  refresh the filter reset of Advanced Filters performs, which is
  known to restore the headers after a guild bank switch.
- Not covered by the offline test harness (the file needs the ESO
  client globals); compile checked only. Not tested in the game
  client (ESO).
## 2026-11-14 (20): Category headers restored when another guild bank is selected

- Switching to another guild bank could leave the guild bank list
  without its category headers: the stock rebuild of the list (the
  old guild's items emptied, then the new guild's items added) runs
  the sort hook while the list is empty, and its single 100 ms
  retry gives up before the new guild's items arrive.
- The keyboard mode now rebuilds the guild bank list with its
  headers when EVENT_GUILD_BANK_ITEMS_READY fires (the new guild's
  items are in), 100 ms after the event so the stock rebuild of the
  list finishes first. The rebuild is the same one the sort hook
  performs, so running it again when the headers are already there
  is harmless. Not covered by the offline test harness (the file
  needs the ESO client globals); compile checked only.
- Not tested in the game client (ESO).
## 2026-11-14 (19): Move To submenu in the header right click

- New "Move To" submenu in the category header context menu: it
  moves the clicked category and the categories nested under it
  under another category of the same bag. The category becomes a
  child of the chosen target (one level below it, a Normal target
  included), and every category of the section shifts by the same
  difference so the whole section moves together, parents kept.
- The first entry of the submenu moves the section back to the top
  level: the category becomes a Normal category without a parent,
  and its section shifts up with it.
- The candidates are the categories of the same bag in its display
  order, never the category itself, the categories nested under it
  (a cycle), its current parent (nothing to move) or a category the
  section does not fit under (level 5 is the deepest level the
  addon offers). An entry that cannot apply is not shown, the same
  rule as the other entries of the menu.
- The levels and the parent are properties of the global rules, so
  the move shows in every bag that has the categories, like the
  other level operations of the menu.
- Not tested in the game client (ESO); tested offline with Lua 5.1
  (38 new assertions in CategoryLevelMenu_test, 137 total, all
  existing suites still pass).
## 2026-11-14 (18): Flat level operations and a Copy To submenu in the header right click

- The level operations of the category header context menu are no
  longer wrapped in an "AutoCategory" submenu: "Increase Level",
  "Decrease Level", "New Sub-Level" and "Delete Level" are direct
  entries of the right click menu of a category header, next to the
  collapse entries.
- The "Copy to: <bag>" entries are now a "Copy To" submenu holding
  the other inventories of the addon (backpack, bank, guild bank,
  craft bag, craft station, house bank, furniture vault, vengeance),
  one entry per inventory, the clicked one excluded. ESO cannot nest
  a submenu inside a submenu (a LibCustomMenu limitation), which is
  why the level operations stay at the top level of the menu and the
  copy submenu sits next to them.
- The copy behavior is unchanged: the global rules are reused (the
  categories are shared with the source bag), the categories already
  present in the destination bag are skipped, and the missing
  ancestors are copied along so the level keeps its place.
- Not tested in the game client (ESO); tested offline with Lua 5.1
  (CategoryLevelMenu_test reworked for the new menu structure, 99
  assertions, all existing suites still pass).
## 2026-11-14 (17): SavedVariables file size optimization

- The AutoCategory SavedVariables file of a long-time player grows
  past a megabyte, mostly with data that is never read again: every
  character section keeps a full copy of the bag category lists and
  collapse states even when the account-wide setting is on (the
  account-wide section is used instead), older versions left data in
  a format that is no longer read (rules with a "priority" key), every
  bag rule repeats its default values (runpriority 1000, showpriority
  equal to runpriority, isHidden false), and the sections of every
  account ever logged in on the machine stay in the file forever
  (the game rewrites the whole file at logout).
- New file SavedVarsCompact.lua (pure Lua, no dependency, unit tested
  in test/SavedVarsCompact_test.lua) with the fix, applied
  automatically at load and logout:
- At load, the dead per-character data of every account in the file
  is removed (bags, collapses, rules, general and appearance of a
  character using account-wide settings - its section keeps only
  the accountWide flag, the version and the character name). The
  load no longer fills the per-character bags back with the default
  categories while the account-wide setting is on (the old default
  refill created the bulk again on every login). Measured on the
  1.5 MB file this was tested with: the file drops to about 0.7 MB.
- At load and at logout, the redundant default values are trimmed
  from the bag rules (showpriority when equal to runpriority,
  runpriority 1000, isHidden false) and filled back at the next
  load (InflateBagRules, which also migrates the old "priority" key),
  so the values the addon works with are unchanged. The current
  account is trimmed at logout only (its tables are read during the
  session); the other accounts are trimmed at load.
- Switching a character from account-wide back to character
  specific settings now recreates its bags (from the default
  categories) and collapse table when they were cleaned up, instead
  of pointing the live settings at a missing table.
- Why not LibSavedVars: the library manages flat settings tables and
  its proxy cannot be iterated with pairs() or the # operator, which
  AutoCategory relies on everywhere; its own documentation advises
  against it for addons with custom scope logic like this one. The
  valuable part (not persisting default values) is implemented
  natively instead.
- Not tested in the game client (ESO); tested offline with Lua 5.1
  (73 new assertions, all existing suites still pass).
## 2026-11-14 (16): AutoCategory submenu on the category header right click

- Right-clicking a category header in any keyboard inventory list
  (player inventory, bank, guild bank, craft bag, home storage chests,
  furniture vault, vengeance, craft stations) now shows an
  "AutoCategory" submenu (new file CategoryLevelMenu.lua, added by
  AC_ItemRowHeader_OnShowContextMenu next to the collapse entries)
  operating on the clicked category and every category nested under it
  in the same bag (its bag rules whose parent chain contains it):
- "Increase Level" / "Decrease Level": every category of that level
  family moves one level deeper or shallower. Increasing is refused
  (the entry is not shown) when any of them is already at level 5;
  decreasing past level 1 turns the category into a Normal (flat)
  category and clears its parent. A top-level category that moves
  deeper is attached to the nearest category of the level above it in
  the display order of the bag (the same automatic parent as the Edit
  Category Level dropdown); a parent already set is never touched.
- "New Sub-Level": creates a new category one level under the clicked
  one, with the rule text "false" (it never matches an item, so the
  level stays a pure display section until categories are nested under
  it), parented to it, added to the bag of the header with the same
  priorities. Not offered under a level 5 category.
- "Delete Level": removes the category from the clicked bag only (the
  global rule stays, exactly like the Remove Category button of Bag
  Settings); every category nested under it moves up one level and the
  direct children nest under the deleted category's own parent, so the
  section keeps its place without the deleted level.
- "Copy to: <bag>": copies the category and the categories nested
  under it to another bag, one entry per other bag of the addon. The
  rules are global and shared, so the copy reuses them (like the
  "Export all" button): editing the category in one bag changes it
  everywhere. Categories already present in the destination bag are
  skipped, and the ancestors of the copied category are copied along
  when they are missing there, so it keeps its place in the level
  hierarchy (without them a level 2-5 category displays flat).
- Levels and parents are properties of the global rules, shared by
  every bag: the level operations apply everywhere the categories
  show, not only in the clicked bag. The menu is keyboard-only (the
  gamepad lists have no right click) and is not offered for headers
  without an operable backing rule (the "Others" category, dynamic
  set names, predefined rules) or for a category that is not a
  category of the clicked bag.
- New strings SI_AC_MENU_CM_* / SI_AC_MESSAGE_CM_COPY_DONE, translated
  in en/de/fr/es/ru/zh.
- Verified offline with Lua 5.1 (test/CategoryLevelMenu_test.lua, 92
  assertions, run from the AutoCategory folder like the other suites);
  the existing suites still pass (RuleLevel 78, CategoryTree 125,
  LibSets 2242). Not tested in ESO.
## 2026-11-13 (4.6.16): commit scroll lists after replacing their data

- Fixed a Lua error in ZO_ScrollList_UpdateScroll ("operator < is
  not supported for nil < number") when scrolling an inventory list
  or a shared dropdown after a guild bank rebuild
  (Hooks_Keyboard.lua, rebuildScrollData): the function replaces
  list.data without committing the list, and in a NON_UNIFORM scroll
  list (mode 2) an entry only gets its top/bottom offsets from
  ZO_ScrollList_Commit - an uncommitted entry has a nil top, which
  crashes the first scroll update. The guild bank path is the main
  trigger: its delayed retry (zo_callLater 100 ms) rebuilds the data
  and returns without a commit, and every keyboard dropdown shares
  the singleton ZO_ComboBoxDropdown_Singleton_Keyboard scroll list,
  which stays NON_UNIFORM once any dropdown has used spacing or a
  custom template (e.g. the currency dropdown). rebuildScrollData now
  always calls ZO_ScrollList_Commit(list) after replacing the data,
  so every entry - including the category headers (typeId 998) -
  receives its scroll position.
- updateHook no longer fails silently when started without an
  inventory: it was started via SF.CallLater:NewSingle(updateHook, 50)
  with no argument, so zo_inventory was nil and SF_safeCall swallowed
  the error; it now only rebuilds when zo_inventory exists.
- Verified offline with Lua 5.1 (test/ScrollCommit_test.lua, 14
  assertions, model of the ZO scroll list: 5 fail without the fix,
  14 pass with); not tested in ESO.

## 2026-11-11 (15): add an item to a category from the inventory context menu

- Right-clicking an item in the inventory (player inventory, bank,
  guild bank, craft bag, home storage chests, furniture vault,
  vengeance) now shows an "AutoCategory" submenu (AutoCategory.lua,
  setupContextMenu) with the categories (levels) of the bag the item
  is in: all of them, in display order (the order of the Display
  Order window), indented one step per sub-menu level. Categories are
  tied to a bag: a bank item lists the categories of the bank bag, an
  inventory item the categories of the inventory bag.
- Selecting a category adds the itemId of the right-clicked item to
  the isitemid() command of that category's rule (the new rule mixin
  method addItemIdToIsItemId, classes/RuleApi.lua): when the rule has
  no isitemid() call yet, " or isitemid(<itemId>)" is appended to the
  rule text (an empty rule text becomes just the command); when the
  command already exists, <itemId> is added to the parameters of its
  last call, unless the id is already a parameter of one of its calls
  (then nothing changes). A longer name that only ends with
  isitemid is not taken for the command.
- The rule is compiled again and everything refreshes like a rule
  edit in Edit Category (cacheInitialize, the settings dropdowns and
  controls, the open inventories re-sorted so the item moves into the
  category right away).
- Categories whose rule is predefined (a plugin rule) are not
  offered: a predefined rule is not editable, the same guard as the
  Edit Category rule editbox.
- Test: test/RuleItemId_test.lua (22 assertions, Lua 5.1 off-game).

## 2026-11-10 (14): import only the selected categories from another bag

- The Import/Export section of the Bag Settings submenu
  (settings/BagSet.lua) has a new function next to "Import From Bag"
  and its Import button: a "Categories To Import" multi-select
  dropdown (ImpExp_ImportCats_LAM, AC_DROPDOWN_IMPORTBAG_CATS) using
  the LibAddonMenu-2.0 dropdown control with multiSelect (the feature
  of the former LibAddonMenu-MultiSelectDropdown widget, built into
  LAM2 since r36 - this addon requires LibAddonMenu-2.0>=43) and an
  "Import Selected Categories" button (ImpExp_ImportSel_LAM). The
  dropdown lists the categories of the source bag chosen in "Import
  From Bag" (sorted by name, the tooltip is the category
  description), so the choices depend on the bag; the button copies
  only the selected categories into the current bag: their bag rules
  (run priority, show priority, hidden state) are deep-copied from
  the source bag, a category of the current bag with the same name is
  replaced and the other categories of the current bag are kept (the
  rule definitions are global and shared, only the bag rules are
  copied). The whole bag import above is unchanged. The selection is
  dropped for the categories that are no longer offered when the
  source bag changes, and the button is disabled with nothing
  selected or when the source bag is the current bag.
- Strings: SI_AC_MENU_IBS_DROPDOWN_IMPORT_CATEGORIES,
  SI_AC_MENU_IBS_BUTTON_IMPORT_CATEGORIES and their tooltips in the
  6 languages. Tests: the new test/ImportCats_test.lua (27
  assertions) loads the delivered settings/BagSet.lua and drives the
  real LAM control definitions (setFunc / getFunc / func / disabled)
  through a fake LAM control.

## 2026-11-10 (13): the levels know the bag of their categories

- Categories are tied to a bag (inventory, bank, guild bank, ...), and
  the Level/Parent system now knows it: a parent must be a category of
  the SAME bag as the category it nests. The Parent dropdown of Edit
  Category (settings/CategorySettings.lua, CatSet_ParentDD_LAM:refresh)
  draws its candidates from the categories of the current bag (its bag
  rules) instead of the global rule list, so a category of another bag
  (a bank category for an inventory category) is never offered - a
  higher level category of one bag cannot be nested under a lower
  level category of another bag. CatSet_ParentDD_LAM:setValue refuses
  (and keeps no parent instead) a parent that is not a category of
  the current bag, the same guard as the cyclic parents. The current
  parent stays visible in the dropdown even when it is a category of
  another bag (set before this restriction), so it can still be
  changed - choosing it again clears it.
- MatchCategoryRules (AutoCategory_API.lua) follows the same rule at
  display time: the parent chain of a level 2-5 category stops at a
  parent that is a category of ANOTHER bag (a bank category while
  evaluating the inventory bag) - that parent is not a section in
  this bag, so the category displays under its own name instead of
  nesting under a category that does not exist here. A parent that is
  a category of no bag at all is still followed: it is only a display
  path. autoAttachParent already chose its parents from the current
  bag only.
- Strings: SI_AC_MENU_EC_DROPDOWN_PARENT_TOOLTIP documents the
  same-bag rule in the 6 languages. Tests: LevelMenu_test covers the
  bag filtering of the dropdown (a category of another bag not
  offered, the current parent of another bag visible and refused by
  setValue), RuleLevel_test covers the display-time chain stop.

## 2026-11-08 (12): the inventory header menu folds and unfolds the sub-levels

- "Lower level" and "Raise level" in the right-click menu of a category
  header in the inventory (AutoCategory.lua,
  AC_ItemRowHeader_OnShowContextMenu) now fold and unfold the display
  of the sub-levels under the category, instead of stepping the level
  of its rule (change 11): "Lower level" collapses every lower-level
  header of the chain - the category itself stays expanded, with its
  own items and its folded sub-headers - and "Raise level" expands the
  category when folded and every folded sub-level with it. The
  sub-level names come from the inventory lists of the bag type and
  from the collapses table (the folded ones are absent from the
  lists); an entry that cannot apply is not shown (nothing to fold on
  a category without sub-levels or already fully folded, nothing to
  unfold when everything is expanded). New pure helper
  CategoryTree.IsSubLevelOf (CategoryTree.lua). AC_UI.CatSet.
  StepRuleLevel of change 11 is removed with its tests. The strings
  SI_AC_MENU_LEVEL_LOWER / _RAISE now read "Fold lower levels" /
  "Unfold lower levels" (fr: "Réduire le niveau" / "Développer le
  niveau", unchanged).

## 2026-11-08 (11): the inventory header menu lowers and raises the level

- The right-click menu of a category header in the inventory
  (AutoCategory.lua, AC_ItemRowHeader_OnShowContextMenu) has two new
  entries, next to Collapse/Expand: "Lower level" and "Raise level"
  step the level of the category's rule by one - Normal -> 1 -> ... ->
  5 and back down (the shared AC_UI.CatSet.SetRuleLevel does the
  change, so the automatic Parent attach of change 10 applies on the
  way up, and an existing Parent is kept on the way down; a level 1
  category steps down to Normal). The entry that cannot apply is not
  shown (no "Lower level" on a Normal category, no "Raise level" on
  level 5). Headers without a category of their own - the ungrouped
  category, the dynamic autosettype set names - do not get the
  entries. New strings SI_AC_MENU_LEVEL_LOWER / _RAISE in the 6
  languages.

## 2026-11-08 (10): choosing a level 2-5 attaches the parent automatically

- Choosing a level 2-5 - from the Level dropdown of Edit Category or
  from the right-click "Set level" entry of the Category Display Order
  window (settings/CategorySettings.lua, AC_UI.CatSet.SetRuleLevel) -
  now also attaches the Parent automatically when the category has
  none: the nearest category of the level just below in the display
  order of the current bag (the section the category visually follows
  there), or the first one when it sits above them all. Normal
  categories are never chosen (they are not offered as parents in the
  dropdown either), and a Parent already set is never touched - the
  Parent dropdown can still change it afterwards. A level without any
  matching category of the level below stays top-level.

## 2026-11-08 (9): the Parent dropdown no longer lists Normal categories, and a level 2-5 autosettype nests its dynamic levels

- The Parent dropdown of Edit Category (settings/CategorySettings.lua)
  now offers only categories with an explicit level of exactly one
  below the edited category (a level 1 category for a level 2 child,
  and so on): Normal categories are no longer listed. The current
  parent stays visible even when its level no longer matches (set
  before the level changed), so it can still be changed. The dropdown
  tooltip was updated in en/de/fr/es/ru/zh. The matching semantics are
  unchanged: a Normal category still counts as level 1, so a level 2-5
  child whose parent is a Normal category keeps nesting under it
  (requested: the dozens of Normal categories cluttered the choices).
- MatchCategoryRules (AutoCategory_API.lua): a level 2-5 rule whose
  execution registers a hierarchical dynamic name (autosettype
  registers "Type----Set name") now nests those dynamic levels under
  the parent chain, replacing the category's own name - exactly like a
  Normal or level 1 category uses a hierarchical dynamic name as-is.
  Previously the dynamic name was dropped for level 2-5 rules, so a
  level 2 "Set" child of "Ensembles" with autosettype() displayed its
  set items flat under "Ensembles----Set" without the set type / set
  name sections. A plain (non-hierarchical) dynamic name at level 2-5
  keeps the previous behavior (the category's own name).
- CatSet_ParentDD_LAM is now exposed as AC_UI.CatSet_ParentDD_LAM
  (like the other Edit Category dropdowns).
- test/RuleLevel_test.lua extended (74 assertions: level 2 and 3
  dynamic names nest under the parent chain, plain dynamic name
  unchanged); test/LevelMenu_test.lua extended (41 assertions: parent
  choices exclude Normal, current Normal parent stays visible). Other
  suites unchanged. Not tested in ESO.
## 2026-11-08 (8): right-click level choice in the Display Order window, and autosettype survives a late-loading LibSets

- The context menu of the Category Display Order window (right click on
  a category) has a new "Set level" entry with the same Normal and 1-5
  choices as the Level dropdown of Edit Category: the level the
  category currently has is shown in gold. The change is applied by a
  new shared AC_UI.CatSet.SetRuleLevel (settings/CategorySettings.lua)
  that both the Level dropdown and the context menu call, so the two
  paths change the level exactly the same way (including the
  defaulting of an empty rule text to true); the Level dropdown
  setFunc now delegates to it. String SI_AC_MENU_DSO_SUBMENU_LEVEL
  added in en/de/fr/es/ru/zh.
- The LibSets plugin (plugins/LibSets_Plugin.lua) now registers the
  real autosettype rule function whenever LibSets is installed, even
  when it is not fully loaded yet: the function already checks
  LibSets.fullyLoaded on every call and returns false while LibSets is
  still loading, then starts matching as soon as it is ready - without
  a re-registration or a UI reload. Previously a dummy was registered
  when LibSets was not ready at AutoCategory's initialization, and it
  kept returning false for the whole session even after LibSets
  finished loading - a plausible cause of "sets no longer display"
  (they fall through to the broad gear categories) after a reloadui.
  With LibSets not installed at all, the dummy is still registered.
- Investigation of the reported "Ensembles (level 1 + autosettype)
  does not display its sets" with the delivered files: with the
  user's priorities (Sets de monstre 52, Set mythique 51, Ensembles
  50, Armes 46, Armures 46), the offline evaluation puts set items
  under the Ensembles autoset name, so the level 1 selection is not
  the cause; the execution priority order works as documented. The
  remaining suspect was the LibSets load timing above.
- test/LevelMenu_test.lua added (32 assertions: GetRuleLevel,
  SetRuleLevel, the late-loading LibSets registration, DisplayOrderWin
  load); test/LibSets_test.lua updated to the new registration
  contract (2242 assertions). Other suites unchanged. Not tested in
  ESO.
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
