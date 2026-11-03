# Changes

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
- Verified offline with Lua 5.1: compilation passes for CategoryTree.lua,
  Hooks_Keyboard.lua and Hooks_Gamepad.lua; 69 assertions pass in
  test/CategoryTree_test.lua (library + real blocks extracted from
  Hooks_Keyboard.lua: build, sort, collapsed parent, collapsed child,
  re-sort path, shared name, legacy headers). Not tested in ESO.
