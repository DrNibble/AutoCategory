-- Run from the addon root with Lua 5.1:
-- lua5.1 test/CategoryTree_test.lua
-- Loads the delivered CategoryTree library and extracts the real header
-- building blocks from Hooks_Keyboard.lua; nothing is re-implemented here.

local assertions = 0
local function equal(expected, actual, message)
    assertions = assertions + 1
    assert(expected == actual, (message or "") .. ": expected "
        .. tostring(expected) .. ", got " .. tostring(actual))
end

-- ---------------------------------------------------------------------------
-- Shared stubs
-- ---------------------------------------------------------------------------
local collapses = {} -- [bagTypeId][categoryName] = true
local otherText = "Other"

AutoCategory = {
    logDebug = function() end,
    Enabled = true,
    acctSaved = {
        appearance = { CATEGORY_OTHER_TEXT = otherText },
        general = {},
    },
    saved = { bags = {} },
    cache = { entriesByName = {} },
}
function AutoCategory.IsCategoryCollapsed(bagTypeId, categoryName)
    local bagCollapses = collapses[bagTypeId]
    return bagCollapses and bagCollapses[categoryName] or false
end
function AutoCategory.SetCategoryCollapsed(bagTypeId, categoryName, collapsed)
    collapses[bagTypeId] = collapses[bagTypeId] or {}
    collapses[bagTypeId][categoryName] = collapsed or nil
end

local matchMap = {} -- [slotIndex] = { category, showpriority }
function AutoCategory:MatchCategoryRules(bagId, slotIndex, specialType)
    local match = matchMap[slotIndex]
    if not match then
        return false, "", 0, 0, 1, false
    end
    return true, match.category, 10, match.showpriority or 10, 1, false
end
AutoCategory.CategorySortNames = {}
function AutoCategory.GetCategorySortName(categoryName)
    local sortName = AutoCategory.CategorySortNames[categoryName]
    return sortName and (sortName .. "\001" .. categoryName) or categoryName
end

-- ---------------------------------------------------------------------------
-- Part 1: the delivered CategoryTree library
-- ---------------------------------------------------------------------------
assert(loadfile("AutoCategory_Tree.lua"))()
local CategoryTree = AutoCategory.CategoryTree

equal("Potions", (CategoryTree.Split("Potions")), "flat split parent")
equal(nil, select(2, CategoryTree.Split("Potions")), "flat split child")
equal("Potions", (CategoryTree.Split("Potions----Magie")), "split parent")
equal("Magie", select(2, CategoryTree.Split("Potions----Magie")), "split child")
equal("Potions", (CategoryTree.Split("Potions ---- Magie")), "split trims spaces")
equal("Magie", select(2, CategoryTree.Split("Potions ---- Magie")), "split trims child")
equal("----Magie", (CategoryTree.Split("----Magie")), "empty parent stays flat")
equal(nil, select(2, CategoryTree.Split("----Magie")), "empty parent no child")
equal("Potions----", (CategoryTree.Split("Potions----")), "empty child stays flat")
equal("A----B", (CategoryTree.Split("A----B----C")), "split parent joins outer levels")
equal("C", select(2, CategoryTree.Split("A----B----C")), "split child is the last level")
equal(nil, CategoryTree.Split(42), "non-string name")

equal("A", CategoryTree.Levels("A----B----C")[1], "levels first")
equal("B", CategoryTree.Levels("A----B----C")[2], "levels second")
equal("C", CategoryTree.Levels("A----B----C")[3], "levels third")
equal(3, CategoryTree.LevelCount("A----B----C"), "level count")
equal(1, CategoryTree.LevelCount("Potions"), "flat level count")
equal(0, CategoryTree.LevelCount(42), "non-string level count")
-- sub-levels of a category (the fold/unfold of the lower levels)
equal(true, CategoryTree.IsSubLevelOf("A----B", "A"), "direct sub-level")
equal(true, CategoryTree.IsSubLevelOf("A----B----C", "A"), "deeper sub-level")
equal(true, CategoryTree.IsSubLevelOf("A----B----C", "A----B"),
    "sub-level of a sub-level")
equal(false, CategoryTree.IsSubLevelOf("A", "A"), "no name is its own sub-level")
equal(false, CategoryTree.IsSubLevelOf("AB", "A"), "prefix without separator")
equal(false, CategoryTree.IsSubLevelOf("A", "A----B"), "parent is not a sub-level")
equal(false, CategoryTree.IsSubLevelOf(42, "A"), "non-string name")
equal(false, CategoryTree.IsSubLevelOf("A----B", 42), "non-string parent")
equal(true, CategoryTree.IsHierarchical("A----B"), "hierarchical name")
equal(false, CategoryTree.IsHierarchical("Potions"), "flat is not hierarchical")
equal(false, CategoryTree.IsHierarchical(42), "non-string is not hierarchical")
equal("A----B", CategoryTree.JoinName({ "A", "B" }), "join two levels")
equal("A----B----C", CategoryTree.JoinName({ "A", "B", "C" }), "join three levels")
equal("A----B", CategoryTree.ParentOf("A----B----C"), "parent of three levels")
local ancestors = CategoryTree.Ancestors("A----B----C")
equal("A", ancestors[1], "first ancestor")
equal("A----B", ancestors[2], "second ancestor")
equal(2, #ancestors, "ancestor count")
equal(nil, CategoryTree.Ancestors("A"), "flat has no ancestors")
equal(nil, CategoryTree.Ancestors(42), "non-string has no ancestors")

equal("Potions", CategoryTree.ParentOf("Potions----Magie"), "parent of child")
equal(nil, CategoryTree.ParentOf("Potions"), "parent of flat")
equal(nil, CategoryTree.ParentOf(42), "parent of non-string")

equal(string.format("%04d%s", 990, "Weapons"),
    CategoryTree.BuildSortKey(10, "Weapons"), "flat key legacy format")
equal(true,
    CategoryTree.BuildSortKey(10, "Potions")
        < CategoryTree.BuildSortKey(10, "Potions----Magie"),
    "flat parent sorts before its level 2 section")
equal(true,
    CategoryTree.BuildSortKey(10, "Potions")
        < CategoryTree.BuildSortKey(10, "Potions----Magie----Soins"),
    "flat parent sorts before its deepest section")
equal(true,
    CategoryTree.BuildSortKey(20, "Potions----Magie")
        < CategoryTree.BuildSortKey(10, "Potions"),
    "section with better priority still sorts before the flat parent")
equal(true,
    CategoryTree.BuildSortKey(10, "Aaa") < CategoryTree.BuildSortKey(10, "Bbb"),
    "flat key ordering between flat categories unchanged")
equal("0990Potions\001Magie",
    CategoryTree.BuildSortKey(10, "Potions----Magie"), "hierarchical key")
equal(
    string.format("%04d%s", 990, "Potions") .. "\001Magie",
    CategoryTree.BuildSortKey(10, "Potions----Magie", "registered sort name"),
    "hierarchical key ignores registered sort name")
equal(
    string.format("%04d%s", 990, "donjon\001(Donjon) Alpha"),
    (function()
        AutoCategory.CategorySortNames["(Donjon) Alpha"] = "donjon"
        return CategoryTree.BuildSortKey(10, "(Donjon) Alpha",
            AutoCategory.GetCategorySortName("(Donjon) Alpha"))
    end)(),
    "flat key uses registered sort name")
equal(
    string.format("%04d%s", 990, "Ordinary"),
    CategoryTree.BuildSortKey(10, "Ordinary", "Ordinary"),
    "flat key accepts unchanged sort name")
equal("0990Potions", CategoryTree.ParentSortKey("0990Potions\001Magie"),
    "parent key truncates child")
equal("0990A\001B", CategoryTree.ParentSortKey("0990A\001B\001C"),
    "parent key of three levels")
equal("0990Potions", CategoryTree.ParentSortKey("0990Potions"),
    "parent key of flat key")
equal(nil, CategoryTree.ParentSortKey(nil), "parent key of nil")

equal("0990A\001B\001C", CategoryTree.BuildSortKey(10, "A----B----C"),
    "three-level key")
equal("0990A", CategoryTree.LevelSortKey("0990A\001B\001C", 1), "level 1 key")
equal("0990A\001B", CategoryTree.LevelSortKey("0990A\001B\001C", 2), "level 2 key")
equal("0990A\001B\001C", CategoryTree.LevelSortKey("0990A\001B\001C", 3), "level 3 key")
equal("0990A\001B\001C", CategoryTree.LevelSortKey("0990A\001B\001C", 9),
    "key beyond deepest level")
equal("0990Weapons", CategoryTree.LevelSortKey("0990Weapons", 1), "flat level key")
equal(nil, CategoryTree.LevelSortKey(nil, 1), "nil level key")
equal(nil, CategoryTree.LevelSortKey("0990Weapons", 0), "zero level key")

equal("Magie", CategoryTree.DisplayName("Potions----Magie"), "child display")
equal("Potions", CategoryTree.DisplayName("Potions"), "flat display")
equal("Potions - Magie", CategoryTree.JoinDisplayName("Potions----Magie"),
    "joined display")
equal("A - B - C", CategoryTree.JoinDisplayName("A----B----C"),
    "joined three-level display")
equal("Potions", CategoryTree.JoinDisplayName("Potions"), "joined flat display")

equal(false, CategoryTree.IsParentCollapsed(1, nil), "no parent never collapsed")
equal(false, CategoryTree.IsParentCollapsed(1, "Potions"), "parent not collapsed")
AutoCategory.SetCategoryCollapsed(1, "Potions", true)
equal(true, CategoryTree.IsParentCollapsed(1, "Potions"), "collapsed parent")
equal(false, CategoryTree.IsParentCollapsed(nil, "Potions"), "nil bag")
AutoCategory.SetCategoryCollapsed(1, "Potions", false)

equal(false, CategoryTree.IsAnyAncestorCollapsed(1, "A----B----C"),
    "no ancestor collapsed")
AutoCategory.SetCategoryCollapsed(1, "A----B", true)
equal(true, CategoryTree.IsAnyAncestorCollapsed(1, "A----B----C"),
    "middle ancestor collapsed")
equal(false, CategoryTree.IsAnyAncestorCollapsed(1, "A----B"),
    "own collapse is not an ancestor")
equal(true, CategoryTree.IsAnyAncestorCollapsed(1, "A----B----C----D"),
    "deep entry hidden by middle collapse")
AutoCategory.SetCategoryCollapsed(1, "A----B", false)
equal(false, CategoryTree.IsAnyAncestorCollapsed(1, "A----B----C"),
    "middle ancestor expanded")
equal(false, CategoryTree.IsAnyAncestorCollapsed(1, "A"),
    "flat never ancestor-collapsed")
equal(false, CategoryTree.IsAnyAncestorCollapsed(nil, "A----B"),
    "nil bag not collapsed")
equal(false, CategoryTree.IsAnyAncestorCollapsed(1, nil),
    "nil name not collapsed")

-- ---------------------------------------------------------------------------
-- Part 2: the real Hooks_Keyboard.lua blocks
-- ---------------------------------------------------------------------------
local function readSource(path)
    local file = assert(io.open(path, "r"))
    local source = file:read("*a")
    file:close()
    return source
end

local hooksSource = readSource("Hooks_Keyboard.lua")
local chunkStart = assert(hooksSource:find("local sortKeys = {", 1, true))
local rebuildStart = assert(hooksSource:find("local function rebuildScrollData", 1, true))
local chunkSource = hooksSource:sub(chunkStart, rebuildStart - 1)
-- The extracted block has no local CategoryTree upvalue: route the calls to
-- the real library loaded above.
chunkSource = chunkSource:gsub("CategoryTree%.", "ACTree.")

ZO_SORT_ORDER_UP = true
ZO_ScrollList_CreateDataEntry = function(typeId, data)
    return { typeId = typeId, data = data }
end
ZO_TableOrderingFunction = function(left, right, key)
    return (left[key] or 0) < (right[key] or 0)
end
SF = {
    safeTable = function(t) return t or {} end,
    safeClearTable = function(t)
        for k in pairs(t) do t[k] = nil end
        return t
    end,
}
ACTree = CategoryTree

local chunk = assert(loadstring(chunkSource .. [[
return {
    isHiddenEntry = isHiddenEntry,
    isCollapsed = isCollapsed,
    runRulesOnEntry = runRulesOnEntry,
    sortInventoryFn = sortInventoryFn,
    createHeaderEntry = createHeaderEntry,
    createNewScrollData = createNewScrollData,
    CATEGORY_HEADER = CATEGORY_HEADER,
}
]]))
local H = chunk()
local CATEGORY_HEADER = H.CATEGORY_HEADER
equal(998, CATEGORY_HEADER, "header type id unchanged")

local function itemEntry(slotIndex)
    return { typeId = 1, data = { bagId = 1, slotIndex = slotIndex,
        stackCount = 1, statValue = slotIndex } }
end

local function runRules(entries)
    for _, entry in ipairs(entries) do
        H.runRulesOnEntry(entry)
    end
end

-- Sort a scroll data list the way the hooked inventory sort does.
local inven = { currentSortKey = "statValue", currentSortOrder = true,
    sortKey = "statValue", sortOrder = true }
local function sortEntries(entries)
    table.sort(entries, function(left, right)
        return H.sortInventoryFn(inven, left, right, nil, nil)
    end)
end

-- Describe a built list: headers as (level)name, items as slotIndex.
local function describe(entries)
    local described = {}
    for _, entry in ipairs(entries) do
        if entry.typeId == CATEGORY_HEADER then
            described[#described + 1] = "(" .. (entry.data.AC_headerLevel or 1)
                .. ")" .. entry.data.AC_displayName
        else
            described[#described + 1] = tostring(entry.data.slotIndex)
        end
    end
    return described
end

local function equalList(expected, entries, message)
    local described = describe(entries)
    equal(table.concat(expected, " "), table.concat(described, " "), message)
end

-- ---------------------------------------------------------------------------
-- runRulesOnEntry fills the two-level fields
-- ---------------------------------------------------------------------------
local entry = itemEntry(1)
matchMap[1] = { category = "Potions----Magie" }
H.runRulesOnEntry(entry)
equal("Potions----Magie", entry.data.AC_categoryName, "item full name")
equal("Potions", entry.data.AC_parentName, "item parent name")
equal("0990Potions\001Magie", entry.data.AC_sortPriorityName, "item sort key")
equal(true, entry.data.AC_matched, "item matched")

matchMap[1] = { category = "Weapons" }
H.runRulesOnEntry(entry)
equal(nil, entry.data.AC_parentName, "flat item has no parent")
equal("0990Weapons", entry.data.AC_sortPriorityName, "flat item key")

matchMap[1] = nil
H.runRulesOnEntry(entry)
equal(otherText, entry.data.AC_categoryName, "unmatched category")
equal(nil, entry.data.AC_parentName, "unmatched has no parent")
equal("9999" .. otherText, entry.data.AC_sortPriorityName, "unmatched key")

-- ---------------------------------------------------------------------------
-- Two-level display: build and sort
-- ---------------------------------------------------------------------------
matchMap[1] = { category = "Potions----Magie" }
matchMap[2] = { category = "Potions----Magie" }
matchMap[3] = { category = "Potions----Santé" }
matchMap[4] = { category = "Weapons" }
-- slot 5 unmatched

local items = {}
for slotIndex = 1, 5 do items[#items + 1] = itemEntry(slotIndex) end
runRules(items)

local headers = {}
for _, e in ipairs(H.createNewScrollData(items)) do
    if e.typeId == CATEGORY_HEADER then headers[#headers + 1] = e end
end
local byName = {}
for _, h in ipairs(headers) do byName[h.data.AC_categoryName] = h.data end
equal(5, #headers, "header count: parent, 2 children, Weapons, Other")
equal(true, byName["Potions"].AC_isParent, "parent flag")
equal(1, byName["Potions"].AC_headerLevel, "parent level")
equal("Potions", byName["Potions"].AC_displayName, "parent display name")
equal(3, byName["Potions"].AC_catCount, "parent total count")
equal(2, byName["Potions----Magie"].AC_catCount, "Magie count")
equal("Magie", byName["Potions----Magie"].AC_displayName, "Magie display name")
equal(2, byName["Potions----Magie"].AC_headerLevel, "Magie level")
equal("Potions", byName["Potions----Magie"].AC_parentName, "Magie parent")
equal(1, byName["Potions----Santé"].AC_catCount, "Santé count")
equal(1, byName["Weapons"].AC_headerLevel, "Weapons stays level 1")
equal(nil, byName["Weapons"].AC_parentName, "Weapons has no parent")

local built = H.createNewScrollData(items)
sortEntries(built)
equalList({ "(1)Potions", "(2)Magie", "1", "2", "(2)Santé", "3",
    "(1)Weapons", "4", "(1)" .. otherText, "5" }, built,
    "expanded two-level order")

-- ---------------------------------------------------------------------------
-- Collapsed parent: only the parent header remains, with the total count
-- ---------------------------------------------------------------------------
AutoCategory.SetCategoryCollapsed(1, "Potions", true)
built = H.createNewScrollData(items)
sortEntries(built)
equalList({ "(1)Potions", "(1)Weapons", "4", "(1)" .. otherText, "5" }, built,
    "collapsed parent hides children and their items")
for _, e in ipairs(built) do
    if e.typeId == CATEGORY_HEADER and e.data.AC_categoryName == "Potions" then
        equal(3, e.data.AC_catCount, "collapsed parent total count")
    end
end
equal(true, H.isHiddenEntry(items[1]), "item hidden by collapsed parent")

-- Rebuilding from the collapsed output (re-sort without refresh) keeps the
-- stored total count and does not resurrect children.
built = H.createNewScrollData(built)
sortEntries(built)
equalList({ "(1)Potions", "(1)Weapons", "4", "(1)" .. otherText, "5" }, built,
    "re-sort of collapsed parent output")

-- ---------------------------------------------------------------------------
-- Collapsed child: child header stays, its items are hidden
-- ---------------------------------------------------------------------------
AutoCategory.SetCategoryCollapsed(1, "Potions", false)
AutoCategory.SetCategoryCollapsed(1, "Potions----Magie", true)
built = H.createNewScrollData(items)
sortEntries(built)
equalList({ "(1)Potions", "(2)Magie", "(2)Santé", "3",
    "(1)Weapons", "4", "(1)" .. otherText, "5" }, built,
    "collapsed child keeps its header, hides its items")

-- Re-sort path: child counts come from the stored headers.
built = H.createNewScrollData(built)
sortEntries(built)
equalList({ "(1)Potions", "(2)Magie", "(2)Santé", "3",
    "(1)Weapons", "4", "(1)" .. otherText, "5" }, built,
    "re-sort of collapsed child output")
for _, e in ipairs(built) do
    if e.typeId == CATEGORY_HEADER then
        if e.data.AC_categoryName == "Potions" then
            equal(3, e.data.AC_catCount, "parent total after child re-sort")
        elseif e.data.AC_categoryName == "Potions----Magie" then
            equal(2, e.data.AC_catCount, "collapsed child count after re-sort")
        end
    end
end

AutoCategory.SetCategoryCollapsed(1, "Potions----Magie", false)

-- ---------------------------------------------------------------------------
-- A flat category with the parent's name reuses that header
-- ---------------------------------------------------------------------------
matchMap[6] = { category = "Potions" }
items[6] = itemEntry(6)
runRules({ items[6] })

local flatAndChild = { items[1], items[2], items[3], items[6] }
built = H.createNewScrollData(flatAndChild)
sortEntries(built)
equalList({ "(1)Potions", "6", "(2)Magie", "1", "2", "(2)Santé", "3" }, built,
    "flat category serves as parent header, own items before the sections")

-- Collapsing the shared name hides the flat items and the children.
AutoCategory.SetCategoryCollapsed(1, "Potions", true)
built = H.createNewScrollData(flatAndChild)
sortEntries(built)
equalList({ "(1)Potions" }, built, "shared name collapse hides everything")
AutoCategory.SetCategoryCollapsed(1, "Potions", false)

-- ---------------------------------------------------------------------------
-- Three-level names: a collapsed middle level hides the deepest one
-- ---------------------------------------------------------------------------

-- Each fake item announces which category name a rule produced.
local threeItems = {}
for slotIndex = 7, 9 do threeItems[#threeItems + 1] = itemEntry(slotIndex) end
matchMap[7] = { category = "Armes----Épées----Lourdes" }
matchMap[8] = { category = "Armes----Épées" }
matchMap[9] = { category = "Armes----Boucliers" }
runRules(threeItems)

built = H.createNewScrollData(threeItems)
sortEntries(built)
equalList({ "(1)Armes", "(2)Boucliers", "9", "(2)Épées", "8", "(3)Lourdes", "7" },
    built, "three-level headers in depth order")

-- Collapsing the middle level keeps its header (total count) and hides
-- both its own items and the deepest level.
AutoCategory.SetCategoryCollapsed(1, "Armes----Épées", true)
built = H.createNewScrollData(threeItems)
sortEntries(built)
equalList({ "(1)Armes", "(2)Boucliers", "9", "(2)Épées" }, built,
    "collapsed middle hides own items and deepest level")
for _, e in ipairs(built) do
    if e.typeId == CATEGORY_HEADER and e.data.AC_categoryName == "Armes----Épées" then
        equal(2, e.data.AC_catCount, "collapsed middle total count")
    end
end
equal(true, H.isHiddenEntry(threeItems[1]), "deepest hidden by collapsed middle")
equal(true, H.isHiddenEntry(threeItems[2]), "own item hidden by collapsed middle")
AutoCategory.SetCategoryCollapsed(1, "Armes----Épées", false)

-- Collapsing the top level hides the whole subtree.
AutoCategory.SetCategoryCollapsed(1, "Armes", true)
built = H.createNewScrollData(threeItems)
sortEntries(built)
equalList({ "(1)Armes" }, built, "collapsed top hides subtree")
AutoCategory.SetCategoryCollapsed(1, "Armes", false)
matchMap[7], matchMap[8], matchMap[9] = nil, nil, nil

-- ---------------------------------------------------------------------------
-- Old-format headers in scrollData still rebuild as flat categories
-- ---------------------------------------------------------------------------
local legacyHeader = { typeId = CATEGORY_HEADER, data = {
    AC_categoryName = "Weapons", AC_bagTypeId = 1, AC_isHeader = true,
    AC_catCount = 7, AC_sortPriorityName = "0990Weapons",
} }
built = H.createNewScrollData({ legacyHeader, items[4] })
sortEntries(built)
equalList({ "(1)Weapons", "4" }, built, "legacy header rebuild")
for _, e in ipairs(built) do
    if e.typeId == CATEGORY_HEADER and e.data.AC_categoryName == "Weapons" then
        equal(1, e.data.AC_catCount, "legacy count from present item")
    end
end

-- A legacy header for a fully collapsed flat category keeps its stored count.
AutoCategory.SetCategoryCollapsed(1, "Weapons", true)
built = H.createNewScrollData({ legacyHeader })
for _, e in ipairs(built) do
    if e.typeId == CATEGORY_HEADER and e.data.AC_categoryName == "Weapons" then
        equal(7, e.data.AC_catCount, "legacy stored count reuse")
    end
end
AutoCategory.SetCategoryCollapsed(1, "Weapons", false)

-- ---------------------------------------------------------------------------
-- createHeaderEntry carries the two-level fields
-- ---------------------------------------------------------------------------
local childHeader = H.createHeaderEntry({
    AC_categoryName = "Potions----Magie", AC_bagTypeId = 1,
    AC_catCount = 2, AC_sortPriorityName = "0990Potions\001Magie",
    AC_parentName = "Potions", AC_headerLevel = 2, AC_displayName = "Magie",
})
equal(2, childHeader.data.AC_headerLevel, "child header level")
equal("Magie", childHeader.data.AC_displayName, "child header display")
equal("Potions", childHeader.data.AC_parentName, "child header parent")
equal(nil, childHeader.data.AC_isParent, "child is not a parent")
equal(nil, H.createHeaderEntry(nil), "nil catInfo")

print("PASS: " .. assertions .. " assertions (CategoryTree)")
