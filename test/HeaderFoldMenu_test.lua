-- Run from AutoCategory/: lua5.1 ../test/HeaderFoldMenu_test.lua
-- Extracts the real header context-menu blocks from AutoCategory.lua
-- (getBagTypeId, subLevelNames, bagCategoryNames and
-- AC_ItemRowHeader_OnShowContextMenu) and checks the "Collapse All
-- Sub-Levels" / "Expand All Sub-Levels" entries: the collapse entry is
-- offered whenever the clicked category has sub-levels (like Collapse
-- All is always offered), so it no longer disappears once every
-- sub-level is already folded; the expand entry is offered whenever
-- anything under the category (or the category itself) is folded.

local assertions = 0
local function equal(expected, actual, message)
    assertions = assertions + 1
    assert(expected == actual, (message or "") .. ": expected "
        .. tostring(expected) .. ", got " .. tostring(actual))
end

--------------------------------------------------------------------
-- Source extraction: the delivered blocks, never copies
--------------------------------------------------------------------
local function readSource(path)
    local file = assert(io.open(path, "r"))
    local source = file:read("*a")
    file:close()
    return source
end

local src = readSource("AutoCategory.lua")

-- A top-level function block: from its signature line to the first
-- "end" at column 0 (every inner end is indented).
local function extractBlock(signature)
    local start = assert(src:find(signature, 1, true), signature)
    while start > 1 and src:sub(start - 1, start - 1) ~= "\n" do
        start = start - 1
    end
    local lines = {}
    local pos = start
    while true do
        local lineEnd = src:find("\n", pos, true) or #src + 1
        local line = src:sub(pos, lineEnd - 1):gsub("\r$", "")
        lines[#lines + 1] = line
        if line == "end" then break end
        pos = lineEnd + 1
    end
    return table.concat(lines, "\n")
end

local chunkSource = table.concat({
    extractBlock("local function getBagTypeId(header)"),
    extractBlock("local function subLevelNames(fullName, bagTypeId)"),
    extractBlock("local function bagCategoryNames(bagTypeId)"),
    extractBlock("local function addScrollableContextSubMenu("),
    extractBlock("function AC_ItemRowHeader_OnShowContextMenu(header)"),
}, "\n")

local chunk = assert(loadstring(chunkSource .. "\n" .. [[
return {
    subLevelNames = subLevelNames,
    bagCategoryNames = bagCategoryNames,
    OnShowContextMenu = AC_ItemRowHeader_OnShowContextMenu,
}
]]))
local M = chunk()

--------------------------------------------------------------------
-- Stubs for the upvalues the extracted blocks reference
--------------------------------------------------------------------
local GUILDBANK = 3
local collapses = { [GUILDBANK] = {} }
local Refreshes = 0

AutoCat = {
    saved = {
        collapses = collapses,
        appearance = { CATEGORY_OTHER_TEXT = "Autres" },
        bags = { [GUILDBANK] = { rules = {} } },
    },
    IsCategoryCollapsed = function(bagTypeId, name)
        local bagCollapses = collapses[bagTypeId]
        return bagCollapses and bagCollapses[name] or false
    end,
    RefreshCurrentList = function() Refreshes = Refreshes + 1 end,
}
function setCategoryCollapsed(bagTypeId, name, collapsed)
    collapses[bagTypeId] = collapses[bagTypeId] or {}
    collapses[bagTypeId][name] = collapsed or nil
end

CategoryTree = {
    SEPARATOR = "----",
    IsSubLevelOf = function(fullName, parentName)
        if type(fullName) ~= "string" or type(parentName) ~= "string" then
            return false
        end
        local prefix = parentName .. "----"
        return fullName:sub(1, #prefix) == prefix
    end,
}

AutoCategory = {
    -- AddCategoryLevelMenuEntries stays nil: the AutoCategory entries
    -- of the menu are covered by CategoryLevelMenu_test.
    CategoryLevelMenu = { RuleChainPrefixes = function() return {} end },
    GetRuleByName = function() return nil end,
}

local ScrollData = {} -- the visible entries of the guild bank list
inven_data = { [GUILDBANK] = { listView = {} } }
function ZO_ScrollList_GetDataList() return ScrollData end

L = function(s) return s end
SI_CONTEXT_MENU_EXPAND = "EXPAND"
SI_CONTEXT_MENU_COLLAPSE = "COLLAPSE"
SI_CONTEXT_MENU_EXPAND_ALL = "EXPAND_ALL"
SI_CONTEXT_MENU_COLLAPSE_ALL = "COLLAPSE_ALL"
SI_CONTEXT_MENU_COLLAPSE_LEVEL_ALL = "COLLAPSE_ALL_SUBLEVELS"
SI_CONTEXT_MENU_EXPAND_LEVEL_ALL = "EXPAND_ALL_SUBLEVELS"

local Menu = {}
function ClearMenu()
    for i = #Menu, 1, -1 do Menu[i] = nil end
end
function AddMenuItem(label, callback)
    Menu[#Menu + 1] = { label = label, callback = callback }
end
function ShowMenu() end

local function menuLabels()
    local labels = {}
    for i, item in ipairs(Menu) do labels[i] = item.label end
    return labels
end
local function hasLabel(label)
    for _, item in ipairs(Menu) do
        if item.label == label then return true end
    end
    return false
end
local function click(label)
    for _, item in ipairs(Menu) do
        if item.label == label then
            item.callback()
            return true
        end
    end
    return false
end

local function header(name)
    return { slot = { dataEntry = { data = {
        AC_categoryName = name, AC_bagTypeId = GUILDBANK,
    } } } }
end
local function subEntry(name)
    return { data = { AC_categoryName = name, AC_bagTypeId = GUILDBANK } }
end
local function resetList(entries)
    for i = #ScrollData, 1, -1 do ScrollData[i] = nil end
    for i, e in ipairs(entries) do ScrollData[i] = e end
end

--------------------------------------------------------------------
-- subLevelNames: the sub-levels of a category, from the visible list
-- and from the collapses table, never the category itself
--------------------------------------------------------------------
resetList({ subEntry("PvP"), subEntry("PvP----Siège"),
    subEntry("PvP----Siège----Baliste"), subEntry("PvP----Réparation") })
setCategoryCollapsed(GUILDBANK, "PvP----Caché", true)
local subs = M.subLevelNames("PvP", GUILDBANK)
local subSet = {}
for _, name in ipairs(subs) do subSet[name] = true end
equal(true, subSet["PvP----Siège"], "visible sub-level found")
equal(true, subSet["PvP----Siège----Baliste"], "deeper sub-level found")
equal(true, subSet["PvP----Réparation"], "second sub-level found")
equal(true, subSet["PvP----Caché"], "folded sub-level found via collapses")
equal(nil, subSet["PvP"], "the category itself is not a sub-level")
equal(4, #subs, "deduplicated sub-level count")
setCategoryCollapsed(GUILDBANK, "PvP----Caché", false)

--------------------------------------------------------------------
-- Expanded parent: Collapse All Sub-Levels is offered and folds every
-- sub-level; the parent itself stays expanded
--------------------------------------------------------------------
M.OnShowContextMenu(header("PvP"))
equal(true, hasLabel("COLLAPSE"), "single Collapse offered for expanded parent")
equal(true, hasLabel("COLLAPSE_ALL_SUBLEVELS"),
    "Collapse All Sub-Levels offered with expanded sub-levels")
equal(false, hasLabel("EXPAND_ALL_SUBLEVELS"),
    "Expand All Sub-Levels not offered when nothing is folded")
local before = Refreshes
equal(true, click("COLLAPSE_ALL_SUBLEVELS"), "collapse callback found")
equal(true, AutoCat.IsCategoryCollapsed(GUILDBANK, "PvP----Siège"),
    "sub-level folded by Collapse All Sub-Levels")
equal(true, AutoCat.IsCategoryCollapsed(GUILDBANK, "PvP----Siège----Baliste"),
    "deeper sub-level folded too")
equal(true, AutoCat.IsCategoryCollapsed(GUILDBANK, "PvP----Réparation"),
    "second sub-level folded too")
equal(false, AutoCat.IsCategoryCollapsed(GUILDBANK, "PvP"),
    "the clicked category itself stays expanded")
equal(before + 1, Refreshes, "the list is refreshed after folding")

--------------------------------------------------------------------
-- Every sub-level already folded: the collapse entry is STILL offered
-- (it used to vanish here), next to Expand All Sub-Levels
--------------------------------------------------------------------
M.OnShowContextMenu(header("PvP"))
equal(true, hasLabel("COLLAPSE_ALL_SUBLEVELS"),
    "Collapse All Sub-Levels still offered when all sub-levels are folded")
equal(true, hasLabel("EXPAND_ALL_SUBLEVELS"),
    "Expand All Sub-Levels offered when sub-levels are folded")
before = Refreshes
equal(true, click("EXPAND_ALL_SUBLEVELS"), "expand callback found")
equal(false, AutoCat.IsCategoryCollapsed(GUILDBANK, "PvP----Siège"),
    "sub-level unfolded by Expand All Sub-Levels")
equal(false, AutoCat.IsCategoryCollapsed(GUILDBANK, "PvP----Siège----Baliste"),
    "deeper sub-level unfolded too")
equal(before + 1, Refreshes, "the list is refreshed after unfolding")

--------------------------------------------------------------------
-- The category itself folded: Expand All Sub-Levels unfolds it too
--------------------------------------------------------------------
setCategoryCollapsed(GUILDBANK, "PvP", true)
setCategoryCollapsed(GUILDBANK, "PvP----Siège", true)
M.OnShowContextMenu(header("PvP"))
equal(true, hasLabel("EXPAND"), "single Expand offered for folded category")
equal(true, hasLabel("EXPAND_ALL_SUBLEVELS"),
    "Expand All Sub-Levels offered for a folded category")
click("EXPAND_ALL_SUBLEVELS")
equal(false, AutoCat.IsCategoryCollapsed(GUILDBANK, "PvP"),
    "the folded category itself is expanded")
equal(false, AutoCat.IsCategoryCollapsed(GUILDBANK, "PvP----Siège"),
    "its folded sub-levels are expanded with it")

--------------------------------------------------------------------
-- A category without sub-levels: neither Sub-Levels entry is offered
--------------------------------------------------------------------
resetList({ subEntry("Solo") })
M.OnShowContextMenu(header("Solo"))
equal(true, hasLabel("COLLAPSE"), "single Collapse offered for a flat category")
equal(false, hasLabel("COLLAPSE_ALL_SUBLEVELS"),
    "no Collapse All Sub-Levels without sub-levels")
equal(false, hasLabel("EXPAND_ALL_SUBLEVELS"),
    "no Expand All Sub-Levels without sub-levels")

--------------------------------------------------------------------
-- The real header handler supplies the Move To renderer. Verify the
-- fallback plus the 15-row viewport without truncating destinations.
--------------------------------------------------------------------
local moveTitle = "Déplacer vers"
local destinations, chosen = {}
for index = 1, 18 do
    local label = ("Destination %02d"):format(19 - index)
    destinations[index] = { label = label, callback = function() chosen = label end }
end
AutoCategory.AddCategoryLevelMenuEntries = function(name, bagId, addMoveSubMenu)
    equal("Solo", name, "Move To receives the clicked category")
    equal(GUILDBANK, bagId, "Move To receives the clicked bag")
    addMoveSubMenu(moveTitle, destinations)
end
local fallbackTitle, fallbackEntries
function AddCustomSubMenuItem(title, entries)
    fallbackTitle, fallbackEntries = title, entries
end
AddCustomMenuItem = AddMenuItem
local clickedHeader = header("Solo")
M.OnShowContextMenu(clickedHeader)
equal(moveTitle, fallbackTitle, "fallback uses the localized menu title")
equal(destinations, fallbackEntries, "fallback retains all destinations")
equal(false, hasLabel(moveTitle), "fallback does not add a launcher")

local pending, scrolled, shownAt, options
LibScrollableMenu = {}
function zo_callLater(callback, delay)
    equal(0, delay, "open after the native click")
    pending = callback
end
function ClearCustomScrollableMenu() scrolled = {} end
function AddCustomScrollableMenuEntry(label, callback)
    scrolled[#scrolled + 1] = { label = label, callback = callback }
end
function ShowCustomScrollableMenu(anchor, opts) shownAt, options = anchor, opts end
fallbackTitle = nil
M.OnShowContextMenu(clickedHeader)
equal(true, hasLabel("COLLAPSE"), "other header options stay native")
equal(nil, fallbackTitle, "no duplicate native Move To submenu with LSM")
equal(true, click(moveTitle), "click the localized Move To launcher")
equal(nil, shownAt, "the scrollable menu waits for the native menu to finish")
pending()
equal(clickedHeader, shownAt, "scrollable menu belongs to the clicked header")
equal(15, options.visibleRowsDropdown, "Move To shows up to fifteen rows")
equal(false, options.sortEntries, "preserve destination order")
equal(18, #scrolled, "destinations past the viewport are still present")
equal("Destination 18", scrolled[1].label, "first destination stays first")
scrolled[18].callback()
equal("Destination 01", chosen, "destination past row fifteen remains actionable")

print("PASS: " .. assertions .. " assertions (HeaderFoldMenu)")
