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
    extractBlock("local function searchableHeaderSubmenu(destinations)"),
    extractBlock("local function createHeaderScrollableMenu()"),
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

local Menu, pending, shownAt, options, scrollSubmenus
LibScrollableMenu = {
    DIVIDER = "-", LSM_ENTRY_TYPE_NORMAL = 1, LSM_ENTRY_TYPE_DIVIDER = 2,
    LSM_ENTRY_TYPE_HEADER = 3, LSM_ENTRY_TYPE_EDITBOX = 8,
    LSM_ENTRY_TYPE_CHECKBOX = 5, LSM_ENTRY_TYPE_SLIDER = 9,
}
function ClearMenu() end
function zo_callLater(callback, delay)
    equal(0, delay, "open after the right mouse-up")
    pending = callback
end
function ClearCustomScrollableMenu() Menu, scrollSubmenus = {}, {} end
function AddCustomScrollableMenuEntry(label, callback)
    Menu[#Menu + 1] = { label = label, callback = callback }
end
function AddCustomScrollableMenuDivider()
    Menu[#Menu + 1] = { divider = true }
end
function AddCustomScrollableSubMenuEntry(title, entries, callback)
    Menu[#Menu + 1] = { label = title, entries = entries, callback = callback }
    scrollSubmenus[title] = entries
end
function ShowCustomScrollableMenu(anchor, opts) shownAt, options = anchor, opts end
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
-- The real header handler builds LSM submenus without truncating entries.
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
        callback = function(_, _, value) priority = value end,
    } },
    { label = "true", callback = function() end },
}
local copyEntries = {
    { label = "Banque", overwriteTooltip = tip },
    { label = "Banque de guilde", onChecked = function() end },
}
copyEntries[1].onChecked = function(_, _, _, state) copyEntries[1].selected = state end
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
equal(nil, shownAt, "the root LSM menu waits for the mouse-up to finish")
clickedHeader.slot.dataEntry.data.AC_displayName = "Recycled"
pending()
clickedHeader.slot.dataEntry.data.AC_displayName = "Solo"
local scrolled = Menu
equal(clickedHeader, shownAt, "root menu belongs to the clicked header")
equal(15, options.visibleRowsSubmenu, "Move To shows up to fifteen rows")
equal(false, options.enableFilter, "no filter in the root menu")
equal(false, options.sortEntries, "preserve destination order")
equal("COLLAPSE", scrolled[1].label, "fold actions also use the root menu")
equal(true, scrolled[4].divider, "main divider immediately before Rule")
equal(ruleTitle, scrolled[5].label)
equal(levelTitle, scrolled[6].label)
equal(moveTitle, scrolled[7].label)
equal(copyTitle, scrolled[8].label)
for index = 5, 8 do
    equal(nil, scrolled[index].callback, "side submenu has no click launcher")
    equal(index == 7 and "function" or "table", type(scrolled[index].entries),
        "only Move To has dynamic submenu entries")
end

-- Simulate LSM rebuilding the open submenu and recycling its edit control.
local moveEntries = scrollSubmenus[moveTitle]
local moveRows = moveEntries()
local search = moveRows[1]
equal(LibScrollableMenu.LSM_ENTRY_TYPE_EDITBOX, search.entryType, "Move To begins with an edit field")
equal("Rechercher", search.editBoxData.defaultText, "search placeholder uses a game string")
equal("", search.editBoxData.text(), "search starts empty")
equal(19, #moveRows, "all destinations, including those past the viewport")
equal("Destination 18", moveRows[2].name, "first destination stays first")
equal("  Destination 17", moveRows[3].name, "LSM indent is preserved")
moveRows[19].callback()
equal("Destination 01", chosen, "last destination remains actionable")

local refreshCount, showCount = 0, 0
local submenu = {
    isSubmenu = true, visible = true, openingControl = {}, containerMinWidth = 380,
    m_dropdownObject = { control = { GetWidth = function() return 450 end } },
}
function submenu:IsDropdownVisible() return self.visible end
local function newEditBox()
    search.editBoxData._EditBoxCtrl = {
        rowControl = { m_owner = submenu, IsHidden = function() return false end },
        callback = search.callback,
        HasFocus = function(self) return self.focused end,
        GetCursorPosition = function(self) return self.cursor end,
        TakeFocus = function(self) self.focused = true end,
        SetCursorPosition = function(self, cursor) self.cursor = cursor end,
    }
    return search.editBoxData._EditBoxCtrl
end
function submenu:RefreshSortedItems(opener)
    equal(self.openingControl, opener, "refresh the submenu's own opener")
    moveRows = moveEntries()
    refreshCount = refreshCount + 1
end
function submenu:Show()
    equal(450, self.containerMinWidth, "filtering cannot shrink the menu width")
    showCount = showCount + 1
    newEditBox()
end
local editBox = newEditBox()
editBox.focused, editBox.cursor = true, 7
search.callback(nil, editBox, "  dESTINATION 1  ")
equal(10, #moveRows, "case-insensitive substring matches keep only relevant destinations")
equal(search, moveRows[1], "search remains the first row")
equal("Destination 18", moveRows[2].name)
equal("  Destination 17", moveRows[3].name, "filtered destinations retain indentation")
equal("Destination 10", moveRows[10].name, "filtered destinations retain display order")
equal(380, submenu.containerMinWidth, "the original width setting is restored")
editBox = search.editBoxData._EditBoxCtrl
equal(true, editBox.focused, "redrawn editbox retains keyboard focus")
equal(7, editBox.cursor, "redrawn editbox retains cursor position")
equal("  dESTINATION 1  ", search.editBoxData.text(), "redrawn editbox retains original query")
search.callback(nil, editBox, search.editBoxData.text())
equal(1, refreshCount, "initializing the editbox with its own text doesn't trigger another redraw")
search.callback(nil, editBox, "[50%]")
equal(2, #moveRows, "pattern characters are matched literally")
equal("    Destination 16 [50%]", moveRows[2].name)
moveRows[2].callback()
equal("    Destination 16 [50%]", chosen, "filtered row retains its original action")
search.callback(nil, search.editBoxData._EditBoxCtrl, "absent")
equal(2, #moveRows, "zero matches retains the search field and a status row")
equal("Aucun résultat", moveRows[2].name)
equal(false, moveRows[2].enabled, "no matching destination is not clickable")
equal(nil, moveRows[2].callback)
search.callback(nil, search.editBoxData._EditBoxCtrl, "")
equal(19, #moveRows, "clearing the query restores all destinations")
submenu.visible = false
search.callback(nil, search.editBoxData._EditBoxCtrl, "delayed")
equal(4, showCount, "delayed edits cannot reopen the closed submenu")
submenu.visible = true
search.editBoxData._EditBoxCtrl.callback = function() end
search.callback(nil, search.editBoxData._EditBoxCtrl, "reused")
equal(4, showCount, "delayed edits do not touch a control reused by another menu")
search.callback(nil, newEditBox(), "16")
equal(2, #moveRows, "search state is retained inside the currently open header menu")

local ruleRows = scrollSubmenus[ruleTitle]
equal(LibScrollableMenu.LSM_ENTRY_TYPE_HEADER, ruleRows[1].entryType, "Rule begins with an LSM header")
equal("Solo", ruleRows[1].name, "Rule title is the visible name, not the synthetic path")
equal(nil, ruleRows[1].callback, "the title is not clickable")
equal(9, ruleRows[2].entryType, "the slider follows the title")
equal(10, ruleRows[2].sliderData.value)
ruleRows[2].callback(nil, nil, 33)
equal(33, priority, "the slider callback remains wired")
equal(2, ruleRows[3].entryType, "the slider is followed by an LSM divider")
equal(nil, ruleRows[3].callback, "the divider is not clickable")
equal("true", ruleRows[4].name, "the rule text follows the divider")

local copyRows = scrollSubmenus[copyTitle]
equal(3, #copyRows, "two destinations followed by the copy action")
equal(5, copyRows[1].entryType, "destination is still a checkbox")
equal("|cFF5555Banque|r", copyRows[1].name, "existing destination has a red label")
equal(tip, copyRows[1].tooltip, "existing destination has the overwrite tooltip")
equal(false, copyRows[1].checked(), "existing destination is not preselected")
equal(false, copyRows[1].additionalData.closeOnSelect, "checking a row does not close the menu")
equal("Banque de guilde", copyRows[2].name, "non-existing destination uses a normal label")
equal(nil, copyRows[2].tooltip, "non-existing destination has no overwrite tooltip")
equal(false, copyRows[2].checked(), "non-existing destination is not preselected")
equal("Copier la sélection", copyRows[3].name, "the list ends with the localized apply action")
copyRows[1].callback(nil, nil, nil, true)
equal(true, copyRows[1].checked(), "the checkbox state is retained when the submenu is rebuilt")
equal(nil, applied, "selecting is separate from applying")
copyRows[3].callback()
equal(true, applied, "the final action applies the selection")

openHeader(clickedHeader)
local reopened = scrollSubmenus[moveTitle]()
equal(19, #reopened, "a new right click opens the full destination list")
equal("", reopened[1].editBoxData.text(), "a new right click resets the search")

print("PASS: " .. assertions .. " assertions (HeaderFoldMenu)")
