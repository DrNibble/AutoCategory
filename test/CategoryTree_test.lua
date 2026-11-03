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

-- ---------------------------------------------------------------------------
-- Part 1: the delivered CategoryTree library
-- ---------------------------------------------------------------------------
assert(loadfile("CategoryTree.lua"))()
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
equal("A", (CategoryTree.Split("A----B----C")), "first separator splits")
equal("B----C", select(2, CategoryTree.Split("A----B----C")), "child keeps rest")
equal(nil, CategoryTree.Split(42), "non-string name")

equal("Potions", CategoryTree.ParentOf("Potions----Magie"), "parent of child")
equal(nil, CategoryTree.ParentOf("Potions"), "parent of flat")
equal(nil, CategoryTree.ParentOf(42), "parent of non-string")

equal(string.format("%04d%s", 990, "Weapons"),
    CategoryTree.BuildSortKey(10, "Weapons"), "flat key keeps legacy format")
equal("0990Potions\001Magie",
    CategoryTree.BuildSortKey(10, "Potions----Magie"), "hierarchical key")
equal("0990Potions", CategoryTree.ParentSortKey("0990Potions\001Magie"),
    "parent key truncates child")
equal("0990Potions", CategoryTree.ParentSortKey("0990Potions"),
    "parent key of flat key")
equal(nil, CategoryTree.ParentSortKey(nil), "parent key of nil")

equal("Magie", CategoryTree.DisplayName("Potions----Magie"), "child display")
equal("Potions", CategoryTree.DisplayName("Potions"), "flat display")
equal("Potions - Magie", CategoryTree.JoinDisplayName("Potions----Magie"),
    "joined display")
equal("Potions", CategoryTree.JoinDisplayName("Potions"), "joined flat display")

equal(false, CategoryTree.IsParentCollapsed(1, nil), "no parent never collapsed")
equal(false, CategoryTree.IsParentCollapsed(1, "Potions"), "parent not collapsed")
AutoCategory.SetCategoryCollapsed(1, "Potions", true)
equal(true, CategoryTree.IsParentCollapsed(1, "Potions"), "collapsed parent")
equal(false, CategoryTree.IsParentCollapsed(nil, "Potions"), "nil bag")
AutoCategory.SetCategoryCollapsed(1, "Potions", false)

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
equal("0990Weapons", entry.data.AC_sortPriorityName, "flat item legacy key")

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
    "flat category serves as parent header")

-- Collapsing the shared name hides the flat items and the children.
AutoCategory.SetCategoryCollapsed(1, "Potions", true)
built = H.createNewScrollData(flatAndChild)
sortEntries(built)
equalList({ "(1)Potions" }, built, "shared name collapse hides everything")
AutoCategory.SetCategoryCollapsed(1, "Potions", false)

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
