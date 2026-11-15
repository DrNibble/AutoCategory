-- Run from AutoCategory/: lua5.1 ../test/CategoryCreation_test.lua
-- Real factories, compiler, rule list and dialog/menu code; no copies.
local assertions = 0
local function equal(expected, actual, message)
    assertions = assertions + 1
    assert(expected == actual, (message or "") .. ": expected "
        .. tostring(expected) .. ", got " .. tostring(actual))
end

for _, key in ipairs({
    "SI_AC_MENU_CM_NEW_CATEGORY", "SI_AC_DEFAULT_NAME_EMPTY_TAG",
    "SI_AC_DIALOG_CATEGORY_NAME_PROMPT", "SI_AC_DIALOG_CATEGORY_NAME_EMPTY",
    "SI_AC_DIALOG_CATEGORY_NAME_EXISTS", "SI_AC_DIALOG_CATEGORY_CREATE_FAILED",
    "SI_OK", "SI_DIALOG_CANCEL",
}) do _G[key] = key end
function GetString(key) return key end
LocaleAwareToLower = string.lower
zo_loadstring = loadstring
LibSFUtils = {}
ZO_Object = {}
function ZO_Object:Subclass() return setmetatable({}, { __index = self }) end
function ZO_Object:New() return setmetatable({}, { __index = self }) end

AutoCategory = {
    saved = { bags = { [1] = { rules = {} }, [3] = { rules = {} } } },
    compiledRules = {}, Environment = {},
}
assert(loadfile("classes/RuleApi.lua"))()
assert(loadfile("classes/BagRuleApi.lua"))()
assert(loadfile("classes/RuleList.lua"))()
AutoCategory.ARW = AutoCategory.RuleList:New({})
AutoCategory.RulesW = AutoCategory.RuleList:New({})
function AutoCategory.GetRuleByName(name)
    return AutoCategory.RuleList.getRuleByName(AutoCategory.RulesW, name)
end
local cacheAdds, refreshes = 0, 0
AutoCategory.cache = { AddRule = function(rule)
    equal(rule, AutoCategory.ARW:getRuleByName(rule.name), "saved rules updated first")
    AutoCategory.RulesW:AddRule(rule)
    cacheAdds = cacheAdds + 1
end }
function AutoCategory.cacheInitialize() refreshes = refreshes + 1 end
function AutoCategory.RefreshCurrentList() end
AC_UI = { BagSet = {} }

local selectedBag, windowOpens = 1, 0
function AC_UI.BagSet.ShowCategoryOrder() error("ordering window must not open") end
AutoCategory.dspWin = {
    SetHidden = function() windowOpens = windowOpens + 1 end,
}

local registered, registrations, displayed, releases = {}, 0, nil, 0
function ZO_Dialogs_RegisterCustomDialog(name, info)
    registrations = registrations + 1
    registered[name] = info
end
function ZO_Dialogs_ShowDialog(name, data)
    displayed = { name = name, data = data, info = registered[name], text = "" }
end
function ZO_Dialogs_GetEditBoxText(dialog) return dialog.text end
function ZO_Dialogs_UpdateDialogMainText(dialog, text) dialog.errorText = text.text end
function ZO_Dialogs_ReleaseDialog(name)
    equal(displayed.name, name, "release the correct popup")
    releases = releases + 1
    -- Native dialogs clear their state on release: capture the bag first.
    displayed.data = nil
end
local items = {}
function AddCustomMenuItem(label, callback)
    items[#items + 1] = { label = label, callback = callback }
end
assert(loadfile("AutoCategory_Tree.lua"))()
assert(loadfile("AutoCategory_LevelMenu.lua"))()
local CLM = AutoCategory.CategoryLevelMenu
local function submit(text)
    displayed.text = text
    displayed.info.buttons[1].callback(displayed)
end

AutoCategory.AddCategoryLevelMenuEntries("Others", 3)
equal(1, #items, "creation available on header without backing rule")
equal(SI_AC_MENU_CM_NEW_CATEGORY, items[1].label, "new label")
items[1].callback()
equal(1, registrations, "popup registered once")
equal(3, displayed.data.bagTypeId, "popup captures clicked bag")
equal(0, #AutoCategory.RulesW.ruleList, "opening does not create anything")
equal(true, displayed.info.buttons[1].noReleaseOnClick, "invalid input stays editable")
equal(nil, displayed.info.buttons[2].callback, "cancel has no mutation callback")
submit(" \t ")
equal(SI_AC_DIALOG_CATEGORY_NAME_EMPTY, displayed.errorText, "blank error is visible")
equal(0, releases, "blank name keeps popup open")
equal(0, #AutoCategory.RulesW.ruleList, "blank name does not create a rule")

-- Another bag becomes current while the popup is open.
selectedBag = 1
submit("  Ma catégorie  ")
local created = AutoCategory.GetRuleByName("Ma catégorie")
equal(true, created ~= nil, "trimmed name is registered")
equal("false", created.rule, "false rule is preserved literally")
equal(false, AutoCategory.compiledRules[created:key()](), "real compiled rule matches nothing")
equal(nil, created.level, "Normal level")
equal(nil, created.parent, "no inherited parent")
equal(1, #AutoCategory.saved.bags[3].rules, "only captured bag receives category")
equal(0, #AutoCategory.saved.bags[1].rules, "other bag unchanged")
equal("Ma catégorie", AutoCategory.saved.bags[3].rules[1].name, "saved bag entry")
equal(1000, AutoCategory.saved.bags[3].rules[1].showpriority, "default sortable priority")
equal(1, cacheAdds, "cache updated once")
equal(1, refreshes, "lists refreshed once")
equal(1, releases, "success closes popup")
equal(1, selectedBag, "creation does not change settings bag selection")
equal(0, windowOpens, "ordering window is not opened")

CLM.OpenNewCategoryDialog(1)
equal(1, registrations, "popup definition reused")
submit("Ma catégorie")
equal(SI_AC_DIALOG_CATEGORY_NAME_EXISTS, displayed.errorText, "cross-bag duplicate refused")
equal(1, releases, "duplicate keeps popup open")
equal(0, #AutoCategory.saved.bags[1].rules, "duplicate adds no bag entry")
equal(1, #AutoCategory.RulesW.ruleList, "duplicate not suffixed or overwritten")
submit("MA CATéGORIE")
equal(SI_AC_DIALOG_CATEGORY_NAME_EXISTS, displayed.errorText, "case-insensitive duplicate")
submit("Unique")
equal(1, #AutoCategory.saved.bags[1].rules, "corrected input creates in captured bag")
equal(2, releases, "corrected input closes popup")

-- An existing global rule need not belong to this bag; predefined names
-- and orphan saved bag names must not be reused either.
local pred = AutoCategory.CreateRule("Predefined", "")
pred.pred = 1
AutoCategory.ARW:AddRule(pred)
AutoCategory.RulesW:AddRule(pred)
equal(nil, CLM.CreateCategory(1, "predefined"), "predefined duplicate refused")
AutoCategory.saved.bags[3].rules[2] = { name = "Orphan", showpriority = 500 }
equal(nil, CLM.CreateCategory(1, "orphan"), "orphan bag entry duplicate refused")
local count = #AutoCategory.RulesW.ruleList
equal(nil, CLM.CreateCategory(99, "Missing bag"), "unknown bag refused")
equal(count, #AutoCategory.RulesW.ruleList, "unknown bag leaves no orphan rule")

local factory = AutoCategory.CreateBagRule
AutoCategory.CreateBagRule = function() return nil end
equal(nil, CLM.CreateCategory(1, "Factory failure"), "failed bag factory refused")
equal(nil, AutoCategory.GetRuleByName("Factory failure"), "failure adds no global rule")
equal(nil, AutoCategory.compiledRules["Factory failure"], "failure leaves no compiled rule")
equal(1000, AutoCategory.saved.bags[1].rules[1].showpriority,
    "factory failure does not compact existing priorities")
AutoCategory.CreateBagRule = factory

-- Cancellation and a bag removed while a popup is open do not mutate state.
CLM.OpenNewCategoryDialog(1)
ZO_Dialogs_ReleaseDialog(displayed.name)
equal(count, #AutoCategory.RulesW.ruleList, "cancel does not create")
CLM.OpenNewCategoryDialog(3)
local bag = AutoCategory.saved.bags[3]
AutoCategory.saved.bags[3] = nil
local releasedBefore = releases
submit("After removal")
equal(SI_AC_DIALOG_CATEGORY_CREATE_FAILED, displayed.errorText, "stale bag error")
equal(releasedBefore, releases, "stale bag leaves popup open")
equal(count, #AutoCategory.RulesW.ruleList, "stale bag leaves no orphan rule")
AutoCategory.saved.bags[3] = bag

-- Highest display priority is strict, including when the old maximum
-- already equals the supported 1000. Preserve old ties and run priorities.
AutoCategory.saved.bags[5] = { rules = {
    { name = "Top A", showpriority = 1000, runpriority = 100 },
    { name = "Top B", showpriority = 1000, runpriority = 200 },
    { name = "Middle", showpriority = 700, runpriority = 300 },
    { name = "Bottom", showpriority = 2, runpriority = 400 },
} }
local otherPriority = AutoCategory.saved.bags[3].rules[1].showpriority
local first = assert(CLM.CreateCategory(5, "First created"))
local entries = AutoCategory.saved.bags[5].rules
equal(1000, entries[5].showpriority, "new category gets highest supported priority")
equal(999, entries[1].showpriority, "previous top group makes room")
equal(entries[1].showpriority, entries[2].showpriority, "old ties are preserved")
equal(true, entries[2].showpriority > entries[3].showpriority, "old group order preserved")
equal(true, entries[3].showpriority > entries[4].showpriority, "bottom remains last")
equal(100, entries[1].runpriority, "run priority untouched")
equal(otherPriority, AutoCategory.saved.bags[3].rules[1].showpriority,
    "other bag priorities are unchanged")
local second = assert(CLM.CreateCategory(5, "Second created"))
equal(1000, entries[6].showpriority, "repeated creation goes to the top")
equal(999, entries[5].showpriority, "previous new category remains directly below")
equal("false", first.rule, "priority placement keeps false rule")
equal(nil, second.level, "priority placement keeps Normal level")
equal(0, windowOpens, "priority placement never opens ordering window")
equal(true, AutoCategory.CategoryTree.BuildSortKey(entries[6].showpriority, second.name)
    < AutoCategory.CategoryTree.BuildSortKey(entries[5].showpriority, first.name),
    "real inventory sort key puts newest category first")
AutoCategory.saved.bags[6] = { rules = {
    { name = "Low", runpriority = 10, showpriority = 20 },
} }
assert(CLM.CreateCategory(6, "Above low"))
equal(21, AutoCategory.saved.bags[6].rules[2].showpriority, "one above existing maximum")
equal(20, AutoCategory.saved.bags[6].rules[1].showpriority, "no compaction when room remains")
local full = {}
for i = 2, 1000 do
    full[#full + 1] = { name = "Existing " .. i, showpriority = i }
end
AutoCategory.saved.bags[7] = { rules = full }
local beforeFull = #AutoCategory.RulesW.ruleList
equal(nil, CLM.CreateCategory(7, "No room"), "full priority range fails without changing order")
equal(beforeFull, #AutoCategory.RulesW.ruleList, "capacity failure creates no rule")
equal(1000, full[#full].showpriority, "capacity failure leaves priorities unchanged")
print("CategoryCreation_test: " .. assertions .. " assertions passed")
