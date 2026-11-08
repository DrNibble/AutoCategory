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

-- ---------------------------------------------------------------------------
-- Part 5: the Parent dropdown of Edit Category offers only categories with
-- an explicit level of exactly one below - Normal categories are not listed
-- ---------------------------------------------------------------------------
AutoCategory.dictionary = {}
local function makeRule(name, level)
    local r = AutoCategory.CreateRule(name, "tag")
    if level then r.level = level end
    r:compile()
    return r
end
local lvl1 = makeRule("Niveau un", 1)
local norm = makeRule("Ordinaire", nil) -- Normal (no level)
local lvl2 = makeRule("Enfants", 2)
local lvl3 = makeRule("Petits-enfants", 3)
AutoCategory.RulesW.ruleList = { lvl1, norm, lvl2, lvl3 }
AutoCategory.GetRuleByName = function(name)
    for _, r in ipairs(AutoCategory.RulesW.ruleList) do
        if r.name == name then return r end
    end
    return nil
end

local function parentChoices()
    local out = {}
    for _, v in ipairs(AC_UI.CatSet_ParentDD_LAM.cvt.choicesValues) do
        out[#out + 1] = v
    end
    return out
end
local function hasChoice(list, value)
    for _, v in ipairs(list) do
        if v == value then return true end
    end
    return false
end

-- a level 2 category: only level 1 categories are offered, not the
-- Normal ones, and "(none)" stays first
AC_UI.CatSet_SelectRule_LAM:setValue("Enfants")
local choices = parentChoices()
equal("", choices[1], "parent choices: (none) first")
equal(true, hasChoice(choices, "Niveau un"), "parent choices: level 1 offered")
equal(false, hasChoice(choices, "Ordinaire"),
    "parent choices: Normal not offered")
equal(false, hasChoice(choices, "Enfants"), "parent choices: self excluded")
equal(false, hasChoice(choices, "Petits-enfants"),
    "parent choices: deeper level not offered")

-- a level 3 category: only level 2 categories are offered
AC_UI.CatSet_SelectRule_LAM:setValue("Petits-enfants")
choices = parentChoices()
equal(true, hasChoice(choices, "Enfants"), "level 3: level 2 offered")
equal(false, hasChoice(choices, "Niveau un"), "level 3: level 1 not offered")
equal(false, hasChoice(choices, "Ordinaire"), "level 3: Normal not offered")

-- the current parent stays visible even when it is a Normal category,
-- so it can still be changed
lvl2.parent = "Ordinaire"
AC_UI.CatSet_SelectRule_LAM:setValue("Enfants")
choices = parentChoices()
equal(true, hasChoice(choices, "Ordinaire"),
    "current Normal parent stays visible")
lvl2.parent = nil

-- ---------------------------------------------------------------------------
-- Part 6: choosing a level 2-5 automatically attaches the parent of the
-- level just below - the nearest category above in the display order
-- ---------------------------------------------------------------------------
local function bagRule(name, prio)
    return { name = name, runpriority = prio, showpriority = prio }
end

local conso = makeRule("Conso", 1)
local haut = makeRule("Haut", 1)
local bas = makeRule("Bas", 1)
local norm2 = makeRule("Ordinaire deux", nil)
local target = makeRule("Max Vigueur", nil)
AutoCategory.RulesW.ruleList = { conso, haut, bas, norm2, target }
AutoCategory.saved = {
    bags = {
        [1] = { -- the bag rules, in the Display Order window order
            rules = {
                bagRule("Haut", 50),
                bagRule("Max Vigueur", 45),
                bagRule("Bas", 20),
                bagRule("Ordinaire deux", 10),
            },
        },
    },
}

-- a level 2 choice nests the category under the level 1 category right
-- above it in the display order
AC_UI.CatSet.SetRuleLevel(target, 2)
equal(2, AC_UI.CatSet.GetRuleLevel(target), "auto-attach: level set")
equal("Haut", target.parent, "auto-attach: nearest level 1 above")

-- a category sitting above every level 1 attaches to the first one
local top = makeRule("Tout en haut", nil)
AutoCategory.RulesW.ruleList = { conso, haut, bas, norm2, target, top }
AutoCategory.saved.bags[1].rules = {
    bagRule("Tout en haut", 60),
    bagRule("Haut", 50),
    bagRule("Bas", 20),
}
AC_UI.CatSet.SetRuleLevel(top, 2)
equal("Haut", top.parent, "auto-attach: first level 1 when above all")

-- the saved bag is the source of the order, not the global rule list:
-- the first level 1 of the bag ("Bas") wins over the first level 1 of
-- the rule list ("Conso", not even in this bag)
AutoCategory.saved.bags[1].rules = {
    bagRule("Max Magie", 45),
    bagRule("Bas", 30),
    bagRule("Ordinaire deux", 10),
}
local target2 = makeRule("Max Magie", nil)
AutoCategory.RulesW.ruleList = { conso, haut, bas, norm2, target, top, target2 }
AC_UI.CatSet.SetRuleLevel(target2, 2)
equal("Bas", target2.parent,
    "auto-attach: bag order drives the choice, not the rule list")

-- a parent already set is never touched
local kept = makeRule("Déjà rattaché", nil)
kept.parent = "Conso"
AutoCategory.RulesW.ruleList = { conso, haut, bas, norm2, target, top, target2, kept }
AC_UI.CatSet.SetRuleLevel(kept, 2)
equal("Conso", kept.parent, "auto-attach: existing parent kept")

-- level 1 and Normal never attach a parent
local lvl1cat = makeRule("Niveau un cat", nil)
AutoCategory.RulesW.ruleList = { conso, haut, bas, norm2, target, top, target2, kept, lvl1cat }
AC_UI.CatSet.SetRuleLevel(lvl1cat, 1)
equal(1, AC_UI.CatSet.GetRuleLevel(lvl1cat), "auto-attach: level 1 set")
equal(nil, lvl1cat.parent, "auto-attach: level 1 gets no parent")
AC_UI.CatSet.SetRuleLevel(lvl1cat, 0) -- Normal
equal(0, AC_UI.CatSet.GetRuleLevel(lvl1cat), "auto-attach: Normal set")
equal(nil, lvl1cat.parent, "auto-attach: Normal gets no parent")

-- Normal categories are never candidates
AutoCategory.saved.bags[1].rules = {
    bagRule("Ordinaire deux", 10),
    bagRule("Orphelin", 5),
}
local orphan = makeRule("Orphelin", nil)
AutoCategory.RulesW.ruleList = { conso, haut, bas, norm2, target, top, target2, kept, lvl1cat, orphan }
AC_UI.CatSet.SetRuleLevel(orphan, 2)
equal(nil, orphan.parent,
    "auto-attach: no parent when only Normal categories exist")

-- with no level 1 category in the bag either, the parent stays empty
AutoCategory.saved.bags[1].rules = { bagRule("Orphelin", 5) }
local orphan2 = makeRule("Orphelin deux", nil)
AutoCategory.RulesW.ruleList[#AutoCategory.RulesW.ruleList + 1] = orphan2
AC_UI.CatSet.SetRuleLevel(orphan2, 2)
equal(nil, orphan2.parent,
    "auto-attach: no parent when no level 1 in the bag")

AutoCategory.saved = nil

-- ---------------------------------------------------------------------------
-- Part 7: the inventory header context menu steps the level by one -
-- Normal -> 1 -> ... -> 5 and back down, within the bounds
-- ---------------------------------------------------------------------------
local step = makeRule("Pas à pas", nil)
AutoCategory.RulesW.ruleList = { step }
AutoCategory.GetRuleByName = function(name)
    for _, r in ipairs(AutoCategory.RulesW.ruleList) do
        if r.name == name then return r end
    end
    return nil
end

-- raising a Normal category makes it level 1
equal(1, AC_UI.CatSet.StepRuleLevel(step, 1), "step: Normal raises to 1")
equal(1, step.level, "step: level 1 stored")
equal(nil, step.parent, "step: level 1 gets no parent")

-- raising again to 2 attaches the parent automatically (nearest level 1)
AutoCategory.saved = {
    bags = { [1] = { rules = { bagRule("Pas à pas", 30), bagRule("Conso", 36) } } },
}
local consoRule = makeRule("Conso", 1)
AutoCategory.RulesW.ruleList = { step, consoRule }
equal(2, AC_UI.CatSet.StepRuleLevel(step, 1), "step: 1 raises to 2")
equal("Conso", step.parent, "step: raise to 2 auto-attaches the parent")

-- lowering keeps an existing parent (the dropdown can still change it)
equal(1, AC_UI.CatSet.StepRuleLevel(step, -1), "step: 2 lowers to 1")
equal("Conso", step.parent, "step: lower keeps the parent")

-- lowering a level 1 category back to Normal clears the level
equal(0, AC_UI.CatSet.StepRuleLevel(step, -1), "step: 1 lowers to Normal")
equal(nil, step.level, "step: Normal has no level")

-- the bounds: no step below Normal or above 5
equal(nil, AC_UI.CatSet.StepRuleLevel(step, -1), "step: below Normal refused")
equal(nil, step.level, "step: below Normal changes nothing")
local five = makeRule("Cinq", 5)
AutoCategory.RulesW.ruleList = { step, consoRule, five }
equal(nil, AC_UI.CatSet.StepRuleLevel(five, 1), "step: above 5 refused")
equal(5, five.level, "step: above 5 changes nothing")
equal(4, AC_UI.CatSet.StepRuleLevel(five, -1), "step: 5 lowers to 4")
equal(4, AC_UI.CatSet.GetRuleLevel(five), "step: 4 after the step down")

-- a missing rule or no step at all applies nothing
equal(nil, AC_UI.CatSet.StepRuleLevel(nil, 1), "step: nil rule refused")
equal(nil, AC_UI.CatSet.StepRuleLevel(step, 0), "step: zero step refused")

AutoCategory.saved = nil

print("PASS: " .. assertions .. " assertions (level menu and late LibSets)")
