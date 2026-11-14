-- Run from the addon root with Lua 5.1:
-- lua5.1 test/LibSets_test.lua [../LibSets/LibSets/LibSets_ConstantsLibraryInternal.lua]
-- Loads the delivered plugin and Plugin_API, not copies of their functions.
local assertions = 0
local function equal(expected, actual, message)
    assertions = assertions + 1
    assert(expected == actual, (message or "") .. ": expected "
        .. tostring(expected) .. ", got " .. tostring(actual))
end

local constantNames, typeNames, cacheClientLanguage
if arg and arg[1] then
    -- Optional contract check against the actual LibSets branch supplied by
    -- the caller. Extract only its literal tables, preserving their contents.
    local file = assert(io.open(arg[1], "r"))
    local source = file:read("*a")
    file:close()
    source = source:gsub("\r\n", "\n")
    local possibleTypes = assert(source:match("(local possibleSetTypes%s*=%s*{.-\n})"))
    local translatedNames = assert(source:match("(local setTypesToName%s*=%s*{.-\n})"))
    local chunk = assert(loadstring(possibleTypes .. [[
        for id, name in ipairs(possibleSetTypes) do _G[name] = id end
        local langDE, langEN, langES, langFR = "de", "en", "es", "fr"
        local langPL, langJP, langRU, langZH = "pl", "jp", "ru", "zh"
        local function zocstrfor(_, value) return value end
    ]] .. translatedNames .. "\nreturn possibleSetTypes, setTypesToName"))
    constantNames, typeNames = chunk()
    local languageCache = assert(source:match(
        "(local clientLang%s*=%s*GetCVar%b().-lib%.clientLang%s*=%s*clientLang)"))
    cacheClientLanguage = assert(loadstring([[
        return function(lib, rawLanguage)
            local strlower = string.lower
            local supportedLanguages, fallbackLang = lib.supportedLanguages, lib.fallbackLang
            local function GetCVar() return rawLanguage end
    ]] .. languageCache .. "\nend"))()
else
    -- Fixtures for standalone execution without a LibSets checkout.
    local suffixes = {
        "ARENA", "BATTLEGROUND", "CRAFTED", "CYRODIIL",
        "DAILYRANDOMDUNGEONANDICREWARD", "DUNGEON", "IMPERIALCITY",
        "MONSTER", "OVERLAND", "SPECIAL", "TRIAL", "MYTHIC",
        "IMPERIALCITY_MONSTER", "CYRODIIL_MONSTER", "CLASS",
    }
    constantNames, typeNames = {}, {}
    for id, suffix in ipairs(suffixes) do
        constantNames[id] = "LIBSETS_SETTYPE_" .. suffix
        _G[constantNames[id]] = id
        typeNames[id] = { fr = "Type " .. id, en = "Type " .. id }
    end
    typeNames[6] = { fr = "Donjon", en = "Dungeon", de = "Verlies" }
    typeNames[1] = { fr = "Arène", en = "Arena" }
    typeNames[4] = { fr = "Cyrodiil", en = "Cyrodiil" }
    cacheClientLanguage = function(lib, rawLanguage)
        local language = string.lower(rawLanguage)
        lib.clientLang = lib.supportedLanguages[language] and language or lib.fallbackLang
    end
end

AutoCategory = {
    Environment = {},
    Plugins = {},
    checking = { ItemLink = "test:item" },
}
local logCount = 0
function AutoCat_Logger()
    return { Info = function() logCount = logCount + 1 end }
end
assert(loadfile("Plugin_API.lua"))()
assert(loadfile("plugins/LibSets_Plugin.lua"))()
equal("function", type(AutoCategory.Plugins.LibSets.init), "plugin registration")

-- Initialize without the optional dependency or before it is fully loaded.
AutoCategory.Plugins.LibSets.init()
equal(false, AutoCategory.Environment.autosettype(), "absent library dummy")
equal(0, logCount, "no success log without library")
local chatMessages = 0
function d()
    chatMessages = chatMessages + 1
end
function IsLibSetsAlreadyLoaded()
    error("The plugin must not call IsLibSetsAlreadyLoaded")
end
LibSets = {}
AutoCategory.Plugins.LibSets.init()
equal(AutoCategory_LibSets.RuleFunc.AutoSetType, AutoCategory.Environment.autosettype,
    "real function registered without fullyLoaded")
equal(false, AutoCategory.Environment.autosettype(), "no match without fullyLoaded")
LibSets = { fullyLoaded = false }
AutoCategory.Plugins.LibSets.init()
equal(AutoCategory_LibSets.RuleFunc.AutoSetType, AutoCategory.Environment.autosettype,
    "real function registered while not fully loaded")
equal(false, AutoCategory.Environment.autosettype(), "no match while not fully loaded")
-- once LibSets finished loading, the same registration starts matching:
-- no re-registration and no reloadui needed (the function reads
-- LibSets.fullyLoaded on every call)
LibSets.fullyLoaded = true
LibSets.GetSetType = function(id) return 1 end
LibSets.setTypesToName = { [1] = { fr = "Donjon", en = "Dungeon" } }
LibSets.clientLang = "fr"
LibSets.fallbackLang = "en"
function GetItemLinkSetInfo(itemLink)
    return true, "Nom du set", 5, 0, 5, 123, 0
end
equal(true, AutoCategory.Environment.autosettype(), "late-loaded LibSets matches")
equal("Donjon----Nom du set", AutoCategory.AdditionCategoryName,
    "late-loaded dynamic category")
AutoCategory.Plugins.LibSets.init()
equal(AutoCategory_LibSets.RuleFunc.AutoSetType, AutoCategory.Environment.autosettype,
    "fullyLoaded alone controls registration, with no per-API guards")

local hasSet, setName, setId = true, "Nom du set^m", 123
local currentType, ready = 6, true
local setCalls = 0
function GetCVar()
    error("The plugin must use LibSets' cached default, never GetCVar")
end
-- Simulate the native ESO function for the test strings, including accents.
function zo_strlower(value)
    return (value:gsub("É", "é"):gsub("È", "è"):gsub("Ä", "ä"):lower())
end
function GetItemLinkSetInfo(itemLink)
    equal("test:item", itemLink, "current item link")
    return hasSet, setName, 5, 0, 5, setId, 0
end
LibSets = {
    allowedSetTypes = {},
    setTypesToName = typeNames,
    fullyLoaded = true,
    version = 0.93,
    clientLang = "fr",
    fallbackLang = "en",
    supportedLanguages = { fr = true, en = true, de = true, pl = false },
}
for id in ipairs(constantNames) do LibSets.allowedSetTypes[id] = true end
function LibSets.GetSetType(id)
    equal(123, id, "sixth API return is setId")
    setCalls = setCalls + 1
    if ready then return currentType end
end
function LibSets.GetSetTypeName(id, lang)
    error("Type names must be read directly from LibSets.setTypesToName")
end
local library = LibSets
AutoCategory.Plugins.LibSets.init()
local rule = AutoCategory.Environment.autosettype
equal(AutoCategory_LibSets.RuleFunc.AutoSetType, rule, "registered rule function")
equal(2, logCount, "success logs for both fullyLoaded registrations")
equal(0, chatMessages, "no chat output at initialization")

local function match(filter, expectedName)
    AutoCategory.AdditionCategoryName = "unchanged"
    AutoCategory.AdditionCategorySortName = "unchanged"
    equal(true, rule(filter), "matching rule")
    equal(expectedName, AutoCategory.AdditionCategoryName, "dynamic category")
    -- The hierarchical name carries both levels; the two-level sort key is
    -- derived from it (CategoryTree.BuildSortKey), no separate sort name.
    equal("unchanged", AutoCategory.AdditionCategorySortName, "no sort side effect")
end
local function noMatch(filter)
    AutoCategory.AdditionCategoryName = "unchanged"
    AutoCategory.AdditionCategorySortName = "unchanged"
    equal(false, rule(filter), "non-matching rule")
    equal("unchanged", AutoCategory.AdditionCategoryName, "no category side effect")
    equal("unchanged", AutoCategory.AdditionCategorySortName, "no sort side effect")
end
local function invalidFilter(filter)
    AutoCategory.AdditionCategoryName = "unchanged"
    AutoCategory.AdditionCategorySortName = "unchanged"
    local ok, err = pcall(rule, filter)
    equal(false, ok, "invalid filter raises rule error")
    equal(true, tostring(err):find("autosettype()", 1, true) ~= nil, "error context")
    equal("unchanged", AutoCategory.AdditionCategoryName, "invalid filter name side effect")
    equal("unchanged", AutoCategory.AdditionCategorySortName, "invalid filter sort side effect")
end

-- Every actual possibleSetTypes entry, including IDs 13, 14 and 15.
equal(15, #constantNames, "current upstream type count")
for id in ipairs(constantNames) do
    currentType = id
    local expectedName = typeNames[id].fr .. "----Nom du set"
    match(nil, expectedName)
    match(id, expectedName)
    match(typeNames[id].fr, expectedName)
    match(zo_strlower(typeNames[id].fr), expectedName)
end
currentType = 6
-- These globals exist in the fixture, but quoted constant names must never
-- resolve through _G. Labels from every LibSets language are accepted.
for _, constantName in ipairs(constantNames) do invalidFilter(constantName) end
match("DUNGEON", "Donjon----Nom du set")
match("dungeon", "Donjon----Nom du set")
noMatch("ARENA")
-- A German label matches a French UI, and an English label a German UI.
match("Verlies", "Donjon----Nom du set")
cacheClientLanguage(LibSets, "de")
match("Dungeon", "Verlies----Nom du set")
cacheClientLanguage(LibSets, "fr")
local messagesBeforeRule = chatMessages
match(nil, "Donjon----Nom du set")
equal(messagesBeforeRule, chatMessages, "no chat output in rule")
cacheClientLanguage(LibSets, "FR")
match(nil, "Donjon----Nom du set")
cacheClientLanguage(LibSets, "de")
match(nil, "Verlies----Nom du set")
match("Verlies", "Verlies----Nom du set")
cacheClientLanguage(LibSets, "en")
match(nil, "Dungeon----Nom du set")
match("DUNGEON", "Dungeon----Nom du set") -- English UI label, not a constant alias.
match("Donjon", "Dungeon----Nom du set") -- French label on an English UI.
cacheClientLanguage(LibSets, "")
match(nil, "Dungeon----Nom du set")
cacheClientLanguage(LibSets, "xx")
match(nil, "Dungeon----Nom du set")
cacheClientLanguage(LibSets, "pl")
match(nil, "Dungeon----Nom du set")
local getCVar = GetCVar
cacheClientLanguage(LibSets, "fr")
GetCVar = nil
match(nil, "Donjon----Nom du set")
GetCVar = getCVar
noMatch(11)
noMatch("Arène")
match("DONJON", "Donjon----Nom du set")
-- The live name table, not a copied list or allowedSetTypes, defines types.
typeNames[99] = { fr = "Extension", en = "Extension" }
currentType = 99
match(99, "Extension----Nom du set")
match("Extension", "Extension----Nom du set")
noMatch("Donjon")
currentType = 6
noMatch("Extension")
typeNames[99] = nil
local imperialMonsterName, cyrodiilMonsterName = typeNames[13].fr, typeNames[14].fr
typeNames[13].fr, typeNames[14].fr = "Monstre partagé", "Monstre partagé"
currentType = 13
match("Monstre partagé", "Monstre partagé----Nom du set")
currentType = 14
match("MONSTRE PARTAGÉ", "Monstre partagé----Nom du set")
currentType = 6
noMatch("Monstre partagé")
typeNames[13].fr, typeNames[14].fr = imperialMonsterName, cyrodiilMonsterName
-- A foreign-language label shared with another type prefers the actual type.
local imperialCityMonsterDe = typeNames[13].de
typeNames[13].de = "Verlies"
currentType = 13
match("Verlies", typeNames[13].fr .. "----Nom du set")
currentType = 6
match("Verlies", "Donjon----Nom du set")
typeNames[13].de = imperialCityMonsterDe
-- A label shared by several types still resolves to the checked item's type.
currentType = 1
noMatch("Verlies")
currentType = 6
local frenchDungeonName = typeNames[6].fr
typeNames[6].fr = nil
match(6, "Dungeon----Nom du set")
match("Dungeon", "Dungeon----Nom du set")
typeNames[6].fr = ""
match(6, "Dungeon----Nom du set")
local dungeonNames = typeNames[6]
typeNames[6] = {}
noMatch()
typeNames[6] = nil
noMatch()
typeNames[6] = dungeonNames
typeNames[6].fr = frenchDungeonName
ready = false
noMatch()
ready, currentType = true, nil
noMatch()
currentType = 999
noMatch()
currentType, hasSet = 6, false
local before = setCalls
noMatch()
equal(before, setCalls, "non-set never queries LibSets")
hasSet, setId = true, 0
noMatch()
setId = nil
noMatch()
setId, setName = 123, nil
noMatch()
setName = ""
noMatch()
setName = "^f"
noMatch()
setName = "Nom du set^m"

for _, invalid in ipairs({ 0, -1, 999, 1.5, false, {}, "", "BOGUS", "6" }) do
    invalidFilter(invalid)
end

-- Unknown/missing optional dependency remains safe even after registration.
LibSets = nil
noMatch()
LibSets = { fullyLoaded = false }
noMatch()
LibSets = library
local loadedCheck = IsLibSetsAlreadyLoaded
IsLibSetsAlreadyLoaded = nil
match(6, "Donjon----Nom du set")
IsLibSetsAlreadyLoaded = loadedCheck
LibSets.fullyLoaded, LibSets.version = false, 0.1
noMatch(6)
LibSets.fullyLoaded = true
match(6, "Donjon----Nom du set")
LibSets.version = 0.93
local names = LibSets.setTypesToName
LibSets.setTypesToName = nil
equal(false, pcall(rule), "fullyLoaded now trusts the library table contract")
LibSets.setTypesToName = names
local allowedSetTypes = LibSets.allowedSetTypes
LibSets.allowedSetTypes = nil
match(6, "Donjon----Nom du set")
LibSets.allowedSetTypes = allowedSetTypes
match(6, "Donjon----Nom du set")
local getSetType = LibSets.GetSetType
LibSets.GetSetType = nil
equal(false, pcall(rule), "fullyLoaded replaces individual API capability checks")
LibSets.GetSetType = getSetType

-- Execute a real rule expression inside AutoCategory's restricted environment.
local expression = assert(loadstring('return autosettype("Donjon")'))
setfenv(expression, AutoCategory.Environment)
equal(true, expression(), "rule environment execution")
equal("Donjon----Nom du set", AutoCategory.AdditionCategoryName, "expression name")
local numericExpression = assert(loadstring("return autosettype(6)"))
setfenv(numericExpression, AutoCategory.Environment)
equal(true, numericExpression(), "numeric rule environment execution")

-- Integration: load the delivered matching API and extract the real keyboard
-- and gamepad producers/comparators in a shared chunk with minimal ESO stubs.
local function readSource(path)
    local file = assert(io.open(path, "r"))
    local source = file:read("*a"):gsub("\r\n", "\n")
    file:close()
    return source
end
local function extractFunction(source, name)
    return assert(source:match("(local function " .. name .. "%b().-\nend)"),
        "Function not found: " .. name)
end
AC_BAG_TYPE_BACKPACK = 1
LibSFUtils = { safeCall = pcall }
local bagRules = {
    { name = "arena", showpriority = 10, runpriority = 10 },
    { name = "otherSets", showpriority = 10, runpriority = 9 },
    { name = "ordinary", showpriority = 10, runpriority = 8 },
}
AutoCategory.saved = {
    general = { SHOW_CATEGORY_SET_TITLE = true },
    bags = { [1] = { rules = bagRules } },
}
AutoCategory.acctSaved = { appearance = { CATEGORY_OTHER_TEXT = "Other" } }
AutoCategory.Enabled = true
AutoCategory.SetCategoryCollapsed = function() end
AutoCategory.IsCategoryCollapsed = function() return false end
-- The merged hooks reference the delivered CategoryTree library
-- (ParentOf, BuildSortKey, JoinDisplayName): load it for real.
assert(loadfile("AutoCategory_CategoryTree.lua"))()
CategoryTree = AutoCategory.CategoryTree
local rules = {
    arena = { name = "ZZZ parent", key = function() return 1 end },
    otherSets = { name = "AAA parent", key = function() return 2 end },
    ordinary = { name = "Ordinary", key = function() return 3 end },
}
AutoCategory.GetRuleByName = function(name) return rules[name] end
local inventory = {
    { type = 6, name = "zulu" },
    { type = 1, name = "Zulu" },
    { type = 6, name = "Alpha" },
    { type = 4, name = "beta" },
    { type = 1, name = "alpha" },
    { type = 6, name = "Beta" },
    { type = 6, name = "not a set", hasSet = false },
}
function AutoCategory:setChecking(bagId, slotIndex)
    self.checking.BagId = bagId
    currentType, setName = inventory[slotIndex].type, inventory[slotIndex].name
    hasSet = inventory[slotIndex].hasSet ~= false
end
AutoCategory.compiledRules = {
    function()
        if currentType == 1 then return rule() end
        AutoCategory.AdditionCategorySortName = "must not leak from a failed rule"
        return false
    end,
    function() return rule() end,
    function()
        equal(nil, AutoCategory.AdditionCategorySortName, "sort key reset between rules")
        return true
    end,
}
assert(loadfile("AutoCategory_API.lua"))()
equal("Unchanged", AutoCategory.GetCategorySortName("Unchanged"), "ordinary fallback")

local keyboardSource = readSource("Hooks_Keyboard.lua")
local keyboardChunk = assert(loadstring([[
    local CATEGORY_HEADER = 998
    local sortKeys = {}
    local function isUngroupedHidden() return false end
]] .. extractFunction(keyboardSource, "NilOrLessThan") .. "\n"
    .. extractFunction(keyboardSource, "runRulesOnEntry") .. "\n"
    .. extractFunction(keyboardSource, "sortInventoryFn") .. [[
    return runRulesOnEntry, sortInventoryFn
]]))
local runKeyboardRules, keyboardComparator = keyboardChunk()
ZO_SORT_ORDER_UP = true
function ZO_TableOrderingFunction(left, right, key, keys, order)
    if key == "statValue" then
        equal(left, right, "keyboard only reaches native item sort for self comparison")
        return false
    end
    equal("sortPriorityName", key, "gamepad primary sort key")
    equal(true, order, "gamepad ascending")
    equal("bestItemTypeName", keys[key].tiebreaker, "gamepad tiebreaker preserved")
    -- Stub the native ESO sorter for the keys reached in these scenarios.
    -- Different generated category keys resolve before its item tiebreakers.
    return left[key] < right[key]
end
SHARED_INVENTORY = {
    GenerateSingleSlotData = function(_, bagId, slotIndex)
        return { bagId = bagId, slotIndex = slotIndex }
    end,
}
local gamepadSource = readSource("Hooks_Gamepad.lua")
local gamepadChunk = assert(loadstring(
    assert(gamepadSource:match("(local CUSTOM_GAMEPAD_ITEM_SORT%s*=%s*{.-\n})")) .. "\n"
    .. extractFunction(gamepadSource, "AutoCategory_ItemSortComparator") .. "\n"
    .. extractFunction(gamepadSource, "ZO_GamepadInventoryList_AddSlotDataToTable") .. "\n"
    .. extractFunction(gamepadSource, "gci_AddSlotDataToTable1") .. [[
    return ZO_GamepadInventoryList_AddSlotDataToTable, gci_AddSlotDataToTable1,
        AutoCategory_ItemSortComparator
]]))
local runGamepadRules, runGamepadCraftRules, gamepadComparator = gamepadChunk()

local function checkOrder(expected, label)
    local keyboard, gamepad, crafting = {}, {}, {}
    for slotIndex = 1, #expected do
        local row = { typeId = 1, data = { bagId = 1, slotIndex = slotIndex } }
        runKeyboardRules(row)
        keyboard[#keyboard + 1] = row
        runGamepadRules({}, gamepad, 1, slotIndex)
        runGamepadCraftRules({}, crafting, 1, slotIndex)
        -- Both views derive the same two-level key from the category name.
        equal(row.data.AC_sortPriorityName, gamepad[slotIndex].sortPriorityName,
            "shared key across views")
    end
    table.sort(keyboard, function(left, right)
        return keyboardComparator({}, left, right)
    end)
    table.sort(gamepad, gamepadComparator)
    table.sort(crafting, gamepadComparator)
    for index, slotIndex in ipairs(expected) do
        equal(slotIndex, keyboard[index].data.slotIndex, label .. " keyboard")
        equal(slotIndex, gamepad[index].slotIndex, label .. " gamepad")
        equal(slotIndex, crafting[index].slotIndex, label .. " gamepad crafting")
    end
    -- The displayed label stays readable and never contains the separator.
    equal(nil, keyboard[1].data.AC_categoryName:find("\001", 1, true), "display unchanged")
    local item = keyboard[1]
    local header = { data = {
        AC_sortPriorityName = item.data.AC_sortPriorityName, AC_isHeader = true,
    } }
    equal(true, keyboardComparator({}, header, item), "header precedes its items")
    equal(false, keyboardComparator({}, item, header), "header comparison inverse")
end

cacheClientLanguage(LibSets, "fr")
checkOrder({ 2, 5, 4, 3, 6, 1 }, "French type then set, mixed case, parent ignored")
AutoCategory.saved.general.SHOW_CATEGORY_SET_TITLE = false
checkOrder({ 2, 5, 4, 3, 6, 1 }, "same order without parent title")
cacheClientLanguage(LibSets, "en")
checkOrder({ 2, 5, 4, 3, 6, 1 }, "English type then set")
cacheClientLanguage(LibSets, "xx")
checkOrder({ 2, 5, 4, 3, 6, 1 }, "unsupported language English fallback")
cacheClientLanguage(LibSets, "fr")
-- Prefix types must remain separate levels, not be compared as display labels.
local arenaFrenchName = typeNames[1].fr
typeNames[1].fr = "Z-Arène"
checkOrder({ 4, 3, 6, 1, 2, 5 }, "type order follows current French translation")
cacheClientLanguage(LibSets, "en")
checkOrder({ 2, 5, 4, 3, 6, 1 }, "English order independent of French translation")
cacheClientLanguage(LibSets, "fr")
typeNames[1].fr = "Donjon étendu"
checkOrder({ 4, 3, 6, 1, 2, 5 }, "short type before its longer prefix variant")
typeNames[1].fr = arenaFrenchName
local firstSetName, thirdSetName = inventory[1].name, inventory[3].name
inventory[1].name, inventory[3].name = "ALPHA", "alpha"
checkOrder({ 2, 5, 4, 1, 6, 3 }, "case-only name collisions keep distinct groups")
equal(false, CategoryTree.BuildSortKey(10, "Donjon----ALPHA")
    == CategoryTree.BuildSortKey(10, "Donjon----alpha"), "distinct header keys")
inventory[1].name, inventory[3].name = firstSetName, thirdSetName
-- Original display priority still takes precedence over the alphabetical key.
bagRules[2].showpriority = 50
checkOrder({ 4, 3, 6, 1, 2, 5 }, "display priority preserved")
bagRules[2].showpriority = 10
AutoCategory.CategorySortNames.Ordinary = "stale"
local matched, ordinaryName = AutoCategory:MatchCategoryRules(1, 7)
equal(true, matched, "ordinary rule match")
equal("Ordinary", ordinaryName, "ordinary rule label")
equal(nil, AutoCategory.CategorySortNames.Ordinary, "stale dynamic key cleared")
equal("Ordinary", AutoCategory.GetCategorySortName(ordinaryName), "ordinary order retained")

local _, gamepadSites = gamepadSource:gsub(
    'CategoryTree%.BuildSortKey%(showPriority, categoryName,%s*AutoCategory%.GetCategorySortName%(categoryName%)%)', "")
equal(5, gamepadSites, "all matched gamepad key generation sites combine both helpers")

print("PASS: " .. assertions .. " assertions (" .. _VERSION
    .. (arg and arg[1] and ", actual LibSets constants/translations)" or ", fixtures)"))
