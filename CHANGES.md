# Changes

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
  `LocaleAwareToLower`. Keep the displayed `(type) set name` unchanged.
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
