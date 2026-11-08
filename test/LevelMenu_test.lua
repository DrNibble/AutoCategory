-- Run from the addon root with Lua 5.1:
-- lua5.1 test/LevelMenu_test.lua
-- Tests the shared level change AC_UI.CatSet.SetRuleLevel / GetRuleLevel
-- (settings/CategorySettings.lua) used by both the Edit Category level
-- dropdown and the Display Order window context menu, and the LibSets
-- plugin autosettype registration when LibSets is not fully loaded at
-- initialization, loading the delivered files (never copies of them).

local assertions = 0
local function equal(expected, actual, message)
    assertions = assertions + 1
    assert(expected == actual, (message or "") .. ": expected "
        .. tostring(expected) .. ", got " .. tostring(actual))
end

-- ---------------------------------------------------------------------------
-- stubs shared by the delivered files under test
-- ---------------------------------------------------------------------------
function GetString(si)
    return tostring(si)
end

LibSFUtils = {
    safeClearTable = function(t)
        for k in pairs(t) do t[k] = nil end
        return t
    end,
    safeCall = function(fn)
        local ok, res = pcall(fn)
        return ok, res
    end,
}

ZO_Object = {}
function ZO_Object.New(cls)
    return setmetatable({}, cls)
end
function ZO_Object:Subclass()
    local cls = {}
    cls.__index = cls
    setmetatable(cls, { __index = self })
    return cls
end

function ZO_IsElementInNumericallyIndexedTable(list, item)
    for _, v in ipairs(list) do
        if v == item then return true end
    end
    return false
end

zo_loadstring = loadstring

-- fake LAM rule editbox (what WINDOW_MANAGER:GetControlByName returns)
local lastEditText
local fakeEditbox = {
    editbox = {
        SetText = function(self, text) lastEditText = text end,
    },
}
WINDOW_MANAGER = {
    GetControlByName = function(self, name)
        if name == "AC_EDITBOX_EDITRULE_RULE" then return fakeEditbox end
        return nil
    end,
}

local cacheInitCalls = 0
local refreshDropdownCalls = 0
local refreshControlsCalls = 0
local refreshOrderCalls = 0

AutoCategory = {
    logDebug = function() end,
    RulesW = { ruleNames = {}, ruleList = {}, tags = {} },
    Environment = {},
    compiledRules = {},
    checking = {},
    Plugins = {},
    cacheInitialize = function() cacheInitCalls = cacheInitCalls + 1 end,
    GetRuleByName = function(name)
        return nil -- no parent chains in these tests
    end,
    getCurrentBagId = function() return 1 end,
}
AC_UI = {
    BagSet = {},
    RefreshDropdownData = function() refreshDropdownCalls = refreshDropdownCalls + 1 end,
    RefreshControls = function() refreshControlsCalls = refreshControlsCalls + 1 end,
    BagSet_RefreshOrder = function() refreshOrderCalls = refreshOrderCalls + 1 end,
}

assert(loadfile("classes/CVT.lua"))()
assert(loadfile("classes/BaseUI.lua"))()
assert(loadfile("classes/RuleApi.lua"))()

-- ---------------------------------------------------------------------------
-- Part 1: AC_UI.CatSet.GetRuleLevel (the level shown in the UI)
-- ---------------------------------------------------------------------------
assert(loadfile("settings/CategorySettings.lua"))()

equal(0, AC_UI.CatSet.GetRuleLevel(nil), "GetRuleLevel: no rule is Normal")
equal(0, AC_UI.CatSet.GetRuleLevel({}), "GetRuleLevel: no level is Normal")
equal(1, AC_UI.CatSet.GetRuleLevel({ level = 1 }), "GetRuleLevel: level 1")
equal(3, AC_UI.CatSet.GetRuleLevel({ level = 3 }), "GetRuleLevel: level 3")
equal(5, AC_UI.CatSet.GetRuleLevel({ level = 5 }), "GetRuleLevel: level 5")
equal(0, AC_UI.CatSet.GetRuleLevel({ level = 0 }), "GetRuleLevel: 0 is Normal")
equal(0, AC_UI.CatSet.GetRuleLevel({ level = 6 }), "GetRuleLevel: out of range high")
equal(0, AC_UI.CatSet.GetRuleLevel({ level = 2.5 }), "GetRuleLevel: non-integer")
equal(0, AC_UI.CatSet.GetRuleLevel({ level = "2" }), "GetRuleLevel: non-number")

-- ---------------------------------------------------------------------------
-- Part 2: AC_UI.CatSet.SetRuleLevel (shared by dropdown and context menu)
-- ---------------------------------------------------------------------------
local rule = AutoCategory.CreateRule("Alpha", "tag")
equal("true", rule.rule, "CreateRule: default rule text")

-- setting a level on a rule with a rule text keeps the text (the rule
-- stays as compiled as it was when it was saved)
rule:compile()
cacheInitCalls = 0
AC_UI.CatSet.SetRuleLevel(rule, 2)
equal(2, rule.level, "SetRuleLevel: level 2 stored")
equal("true", rule.rule, "SetRuleLevel: existing rule text kept")
equal(true, AutoCategory.compiledRules[rule:key()] ~= nil,
    "SetRuleLevel: rule still compiled")
equal(true, cacheInitCalls >= 1, "SetRuleLevel: cache re-initialized")
equal(true, refreshOrderCalls >= 1, "SetRuleLevel: display order refreshed")

-- setting the same level again is a no-op (LAM programmatic refreshes)
local before = { cacheInitCalls, refreshDropdownCalls, refreshControlsCalls,
    refreshOrderCalls }
AC_UI.CatSet.SetRuleLevel(rule, 2)
equal(2, rule.level, "SetRuleLevel: unchanged level kept")
equal(before[1], cacheInitCalls, "SetRuleLevel: no-op does not re-cache")

-- Normal removes the level
AC_UI.CatSet.SetRuleLevel(rule, 0)
equal(nil, rule.level, "SetRuleLevel: 0 clears the level")
AC_UI.CatSet.SetRuleLevel(rule, 1)
equal(1, rule.level, "SetRuleLevel: level 1 stored")
AC_UI.CatSet.SetRuleLevel(rule, nil)
equal(nil, rule.level, "SetRuleLevel: nil clears the level")

-- an empty rule text is defaulted to true for a level category
local emptyRule = AutoCategory.CreateRule("Empty", "tag")
emptyRule.rule = ""
AC_UI.CatSet.SetRuleLevel(emptyRule, 1)
equal(1, emptyRule.level, "SetRuleLevel: level 1 stored on empty rule")
equal("true", emptyRule.rule, "SetRuleLevel: empty rule defaulted to true")
equal(true, AutoCategory.compiledRules[emptyRule:key()] ~= nil,
    "SetRuleLevel: defaulted rule compiled")

-- a missing rule is ignored
AC_UI.CatSet.SetRuleLevel(nil, 3)
equal(nil, nil, "SetRuleLevel: nil rule ignored")

-- ---------------------------------------------------------------------------
-- Part 3: LibSets plugin - autosettype survives a late-loading LibSets
-- ---------------------------------------------------------------------------
local itemLinkIsSet = true
function GetItemLinkSetInfo(link)
    if itemLinkIsSet then
        return true, "Mère du chagrin", "", "", "", 123
    end
    return false, "", "", "", "", 0
end

local setTypeNameByType = { [1] = { fr = "Donjon", en = "Dungeon" } }
LibSets = {
    fullyLoaded = false, -- LibSets still loading when AutoCategory inits
    clientLang = "fr",
    fallbackLang = "en",
    setTypesToName = setTypeNameByType,
    GetSetType = function(setId) return 1 end,
}
function AutoCat_Logger()
    return { Info = function() end }
end

assert(loadfile("Plugin_API.lua"))()
assert(loadfile("plugins/LibSets_Plugin.lua"))()
AutoCategory_LibSets.Initialize()

-- the real rule function is registered even though LibSets is not ready:
-- it returns false while LibSets is still loading
equal(true, AutoCategory.Environment.autosettype
    ~= AutoCategory.dummyRuleFunc,
    "LibSets: real function registered while loading")
AutoCategory.checking.ItemLink = "setitem"
equal(false, AutoCategory.Environment.autosettype(),
    "LibSets: no match while not fully loaded")

-- once LibSets finished loading, the same registration starts matching
-- (no re-registration, no reloadui needed)
LibSets.fullyLoaded = true
equal(true, AutoCategory.Environment.autosettype(),
    "LibSets: matches once fully loaded")
equal("Donjon----Mère du chagrin", AutoCategory.AdditionCategoryName,
    "LibSets: hierarchical category name")

-- a non-set item never matches
itemLinkIsSet = false
equal(false, AutoCategory.Environment.autosettype(),
    "LibSets: non-set item does not match")

-- without LibSets at all, the dummy is registered and returns false
AutoCategory.Environment.autosettype = nil
LibSets = nil
AutoCategory_LibSets.Initialize()
equal(AutoCategory.dummyRuleFunc, AutoCategory.Environment.autosettype,
    "LibSets: dummy registered without LibSets")
equal(false, AutoCategory.Environment.autosettype(),
    "LibSets: dummy returns false")

-- ---------------------------------------------------------------------------
-- Part 4: the Display Order window file still loads with the new submenu
-- ---------------------------------------------------------------------------
AC_UI.DspWin = AC_UI.DspWin or {}
assert(loadfile("settings/DisplayOrderWin.lua"))()
equal(true, AC_UI.DspWin ~= nil, "DisplayOrderWin: loads")

print("PASS: " .. assertions .. " assertions (level menu and late LibSets)")
