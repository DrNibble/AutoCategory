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
    extractBlock("local function createHeaderScrollableMenu(menuRows)"),
    extractBlock("local function showHeaderContextMenu("),
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
    AddCategoryLevelMenuEntries = function() end,
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

local Menu, pending, shownAt, options
function ClearMenu() end
function zo_callLater(callback, delay)
    equal(0, delay, "open after the right mouse-up")
    pending = callback
end
AutoCategory.ScrollMenu = {}
function AutoCategory.ScrollMenu.Show(anchor, rows, opts)
    shownAt, Menu, options = anchor, rows, opts
end
local function openHeader(header)
    M.OnShowContextMenu(header)
    pending()
end

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
            item.action()
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
openHeader(header("PvP"))
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
openHeader(header("PvP"))
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
openHeader(header("PvP"))
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
openHeader(header("Solo"))
equal(true, hasLabel("COLLAPSE"), "single Collapse offered for a flat category")
equal(false, hasLabel("COLLAPSE_ALL_SUBLEVELS"),
    "no Collapse All Sub-Levels without sub-levels")
equal(false, hasLabel("EXPAND_ALL_SUBLEVELS"),
    "no Expand All Sub-Levels without sub-levels")

--------------------------------------------------------------------
-- The real header handler builds internal submenus without truncating entries.
--------------------------------------------------------------------
local moveTitle = "Déplacer vers"
local ruleTitle, levelTitle, copyTitle = "Règle", "Niveau", "Copier vers"
local tip = "déjà existant, sélectionner pour écraser"
SI_AC_MENU_CM_COPY_SELECTED = "Copier la sélection"
SI_GAMEPAD_BANK_SEARCH_DEFAULT_TEXT = "Rechercher"
SI_SORT_FILTER_LIST_NO_RESULTS = "Aucun résultat"
GetString = L

local destinations, chosen = {}
for index = 1, 18 do
    local label = ("Destination %02d"):format(19 - index)
    if index == 2 then label = "  " .. label end
    if index == 3 then label = "    Destination 16 [50%]" end
    destinations[index] = { label = label, callback = function() chosen = label end }
end
local priority
local ruleEntries = {
    { isHeader = true },
    { slider = {
        label = "Priorité d’exécution", data = { value = 10 },
        callback = function(value) priority = value end,
    } },
    { label = "true", kind = "text" },
}
local copyEntries = {
    { label = "Banque", overwriteTooltip = tip },
    { label = "Banque de guilde", onChecked = function() end },
}
copyEntries[1].onChecked = function(state) copyEntries[1].selected = state end
local applied
local clickedHeader = header("Parent----Solo")
clickedHeader.slot.dataEntry.data.AC_displayName = "Solo"
AutoCategory.AddCategoryLevelMenuEntries = function(name, bagId, menu, displayName)
    equal("Parent----Solo", name, "renderer receives the clicked category key")
    equal("Solo", displayName, "renderer receives the inventory's display name")
    equal(GUILDBANK, bagId, "renderer receives the clicked bag")
    menu.addDivider()
    ruleEntries[1].label = displayName
    menu.addSubMenu(ruleTitle, ruleEntries)
    menu.addSubMenu(levelTitle, { { label = "Increase Level", callback = function() end } })
    menu.addSubMenu(moveTitle, destinations, { searchable = true })
    menu.addSubMenu(copyTitle, copyEntries, { copyAction = function() applied = true end })
end

shownAt = nil
M.OnShowContextMenu(clickedHeader)
equal(nil, shownAt, "the root menu waits for the mouse-up to finish")
clickedHeader.slot.dataEntry.data.AC_displayName = "Recycled"
pending()
clickedHeader.slot.dataEntry.data.AC_displayName = "Solo"
local scrolled = Menu
equal(clickedHeader, shownAt, "root menu belongs to the clicked header")
equal(15, options.submenuRows, "Move To shows up to fifteen destinations")
equal("COLLAPSE", scrolled[1].label, "fold actions also use the root menu")
equal("divider", scrolled[4].kind, "main divider immediately before Rule")
equal(ruleTitle, scrolled[5].label)
equal(levelTitle, scrolled[6].label)
equal(moveTitle, scrolled[7].label)
equal(copyTitle, scrolled[8].label)
for index = 5, 8 do
    equal(nil, scrolled[index].action, "submenu does not execute an action")
    equal("table", type(scrolled[index].entries), "the submenu has its own rows")
    equal(index == 7, scrolled[index].search == true, "only Move To has a search field")
end

local moveRows = scrolled[7].entries
equal(18, #moveRows, "all destinations, including those past the viewport")
equal("Destination 18", moveRows[1].label, "first destination stays first")
equal("  Destination 17", moveRows[2].label, "indentation is preserved")
equal("    Destination 16 [50%]", moveRows[3].label, "special characters are preserved")
moveRows[18].action()
equal("Destination 01", chosen, "last destination remains actionable")

local ruleRows = scrolled[5].entries
equal("header", ruleRows[1].kind, "Rule begins with a header")
equal("Solo", ruleRows[1].label, "Rule title is the visible name, not the synthetic path")
equal(nil, ruleRows[1].action, "the title is not clickable")
equal("slider", ruleRows[2].kind, "the slider follows the title")
equal(10, ruleRows[2].slider.data.value)
ruleRows[2].slider.callback(33)
equal(33, priority, "the slider callback remains wired")
equal("divider", ruleRows[3].kind, "the slider is followed by a divider")
equal(nil, ruleRows[3].action, "the divider is not clickable")
equal("true", ruleRows[4].label, "the rule text follows the divider")
equal(nil, ruleRows[4].action, "the rule text is read-only")

local copyRows = scrolled[8].entries
equal(3, #copyRows, "two destinations followed by the copy action")
equal("check", copyRows[1].kind, "destination is still a checkbox")
equal("|cFF5555Banque|r", copyRows[1].label, "existing destination has a red label")
equal(tip, copyRows[1].tooltip, "existing destination has the overwrite tooltip")
equal(false, copyRows[1].checked(), "existing destination is not preselected")
equal("Banque de guilde", copyRows[2].label, "non-existing destination uses a normal label")
equal(nil, copyRows[2].tooltip, "non-existing destination has no overwrite tooltip")
equal(false, copyRows[2].checked(), "non-existing destination is not preselected")
equal("Copier la sélection", copyRows[3].label, "the list ends with the localized apply action")
copyRows[1].setChecked(true)
equal(true, copyRows[1].checked(), "the checkbox state is retained when the submenu is rebuilt")
equal(nil, applied, "selecting is separate from applying")
copyRows[3].action()
equal(true, applied, "the final action applies the selection")

print("PASS: " .. assertions .. " assertions (HeaderFoldMenu)")
