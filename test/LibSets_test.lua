-- Run from the addon root with Lua 5.1:
-- lua5.1 test/LibSets_test.lua [../LibSets/LibSets/LibSets_ConstantsLibraryInternal.lua]
-- Loads the delivered plugin and Plugin_API, not copies of their functions.
local assertions = 0
local function equal(expected, actual, message)
    assertions = assertions + 1
    assert(expected == actual, (message or "") .. ": expected "
        .. tostring(expected) .. ", got " .. tostring(actual))
end

local constantNames, typeNames, upstreamMapping
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
    local mapping = assert(source:match(
        "(lib.setTypeToLibraryInternalVariableNames%s*=%s*{.-\n})"))
    LIBSETS_TABLEKEY_TABLENAME = "tableName"
    upstreamMapping = assert(loadstring("local lib = {}\n" .. mapping
        .. "\nreturn lib.setTypeToLibraryInternalVariableNames"))()
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
end
LIBSETS_TABLEKEY_TABLENAME = "tableName"

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

-- Initialize without the optional dependency or with missing APIs.
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
equal(AutoCategory.dummyRuleFunc, AutoCategory.Environment.autosettype,
    "missing APIs dummy")
LibSets = { GetSetType = function() end, allowedSetTypes = {} }
AutoCategory.Plugins.LibSets.init()
equal(AutoCategory.dummyRuleFunc, AutoCategory.Environment.autosettype,
    "missing GetSetTypeName dummy")

local hasSet, setName, setId = true, "Nom du set^m", 123
local currentType, ready, missingTranslation, missingNames = 6, true, false, false
local setCalls = 0
local uiLanguage = "fr"
function GetCVar(name)
    equal("language.2", name, "UI language CVar")
    return uiLanguage
end
function GetItemLinkSetInfo(itemLink)
    equal("test:item", itemLink, "current item link")
    return hasSet, setName, 5, 0, 5, setId, 0
end
LibSets = {
    allowedSetTypes = {},
    fullyLoaded = true,
    version = 0.93,
    supportedLanguages = { fr = true, en = true, de = true, pl = false },
}
for id in ipairs(constantNames) do LibSets.allowedSetTypes[id] = true end
function LibSets.GetSetType(id)
    equal(123, id, "sixth API return is setId")
    setCalls = setCalls + 1
    if ready then return currentType end
end
function LibSets.GetSetTypeName(id, lang)
    equal("string", type(lang), "explicit language passed to LibSets")
    if missingNames or (missingTranslation and lang == "fr") then return nil end
    return typeNames[id][lang]
end
local library = LibSets
AutoCategory.Plugins.LibSets.init()
local rule = AutoCategory.Environment.autosettype
equal(AutoCategory_LibSets.RuleFunc.AutoSetType, rule, "registered rule function")
equal(1, logCount, "success log")
equal(0, chatMessages, "no chat output at initialization")

if upstreamMapping then
    local copiedMapping
    for index = 1, 10 do
        local name, value = debug.getupvalue(AutoCategory_LibSets.Initialize, index)
        if name == "setTypeToLibraryInternalVariableNames" then
            copiedMapping = value
            break
        end
    end
    equal("table", type(copiedMapping), "actual plugin mapping upvalue")
    local count = 0
    for id, entry in pairs(upstreamMapping) do
        count = count + 1
        equal(entry[LIBSETS_TABLEKEY_TABLENAME],
            copiedMapping[id][LIBSETS_TABLEKEY_TABLENAME], "literal mapping copy")
    end
    equal(15, count, "upstream mapping count")
end

local function match(filter, expectedName)
    AutoCategory.AdditionCategoryName = "unchanged"
    equal(true, rule(filter), "matching rule")
    equal(expectedName, AutoCategory.AdditionCategoryName, "dynamic category")
end
local function noMatch(filter)
    AutoCategory.AdditionCategoryName = "unchanged"
    equal(false, rule(filter), "non-matching rule")
    equal("unchanged", AutoCategory.AdditionCategoryName, "no category side effect")
end

-- Every actual possibleSetTypes entry, including IDs 13, 14 and 15.
equal(15, #constantNames, "current upstream type count")
for id, constantName in ipairs(constantNames) do
    currentType = id
    local expectedName = "(" .. typeNames[id].fr .. ") Nom du set"
    match(nil, expectedName)
    match(id, expectedName)
    match(constantName, expectedName)
    match(constantName:sub(17), expectedName)
    match(constantName:sub(17):lower(), expectedName)
end
currentType = 6
local messagesBeforeRule = chatMessages
match(nil, "(Donjon) Nom du set")
equal(messagesBeforeRule, chatMessages, "no chat output in rule")
uiLanguage = "FR"
match(nil, "(Donjon) Nom du set")
uiLanguage = "de"
match(nil, "(Verlies) Nom du set")
uiLanguage = "en"
match(nil, "(Dungeon) Nom du set")
uiLanguage = nil
match(nil, "(Dungeon) Nom du set")
uiLanguage = ""
match(nil, "(Dungeon) Nom du set")
uiLanguage = "xx"
match(nil, "(Dungeon) Nom du set")
uiLanguage = "pl"
match(nil, "(Dungeon) Nom du set")
local getCVar = GetCVar
GetCVar = nil
match(nil, "(Dungeon) Nom du set")
GetCVar, uiLanguage = getCVar, "fr"
noMatch(11)
missingTranslation = true
match(6, "(Dungeon) Nom du set")
missingTranslation, missingNames = false, true
noMatch()
missingNames, ready = false, false
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
    AutoCategory.AdditionCategoryName = "unchanged"
    local ok, err = pcall(rule, invalid)
    equal(false, ok, "invalid type raises rule error")
    equal(true, tostring(err):find("autosettype()", 1, true) ~= nil, "error context")
    equal("unchanged", AutoCategory.AdditionCategoryName, "invalid input side effect")
end

-- Unknown/missing optional dependency remains safe even after registration.
LibSets = nil
noMatch()
LibSets = { fullyLoaded = false }
noMatch()
LibSets = library
local loadedCheck = IsLibSetsAlreadyLoaded
IsLibSetsAlreadyLoaded = nil
match(6, "(Donjon) Nom du set")
IsLibSetsAlreadyLoaded = loadedCheck
LibSets.fullyLoaded, LibSets.version = false, 0.1
match(6, "(Donjon) Nom du set")
LibSets.fullyLoaded, LibSets.version = true, 0.93
local getSetTypeName = LibSets.GetSetTypeName
LibSets.GetSetTypeName = nil
noMatch()
LibSets.GetSetTypeName = getSetTypeName
local allowedSetTypes = LibSets.allowedSetTypes
LibSets.allowedSetTypes = nil
noMatch()
LibSets.allowedSetTypes = allowedSetTypes
match(6, "(Donjon) Nom du set")

-- Execute a real rule expression inside AutoCategory's restricted environment.
local expression = assert(loadstring('return autosettype("DUNGEON")'))
setfenv(expression, AutoCategory.Environment)
equal(true, expression(), "rule environment execution")
equal("(Donjon) Nom du set", AutoCategory.AdditionCategoryName, "expression name")

print("PASS: " .. assertions .. " assertions (" .. _VERSION
    .. (arg and arg[1] and ", actual LibSets constants/translations)" or ", fixtures)"))
