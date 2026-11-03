# Changes

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
