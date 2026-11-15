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
    "SI_AC_MENU_CM_TAG_NEW", "SI_AC_DIALOG_TAG_NAME_PROMPT",
    "SI_AC_DIALOG_TAG_NAME_EMPTY",
    "SI_AC_MENU_CM_MOVE_UP", "SI_AC_MENU_CM_MOVE_DOWN",
    "SI_AC_MENU_CM_MOVE_UP", "SI_AC_MENU_CM_MOVE_DOWN",
    "SI_AC_NEW_CATEGORY_EMPTY_CHILD", "SI_AC_MENU_CM_RUN_PRIORITY",
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
function ClearMenu() items = {} end
function ShowMenu() shownMenu = true end
shownMenu = false
function AddCustomMenuItem(label, callback)
    items[#items + 1] = { label = label, callback = callback }
end
local chatMessages = {}
CHAT_ROUTER = { AddSystemMessage = function(_, msg)
    chatMessages[#chatMessages + 1] = msg end }
MENU_ADD_OPTION_LABEL = "option"
local function menuItem(label)
    for i = 1, #items do
        if items[i].label == label then return items[i] end
    end
    error("no menu item " .. tostring(label))
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
AutoCategory.RulesW.tags = { "Tag B", GetString(SI_AC_DEFAULT_NAME_EMPTY_TAG), "Tag A" }
submit("  Ma catégorie  ")
equal(1, releases, "valid name closes the popup")
equal(true, shownMenu, "tag menu opens after the name dialog")
equal(4, #items, "menu: two tags, empty tag, new tag")
equal("Tag A", items[1].label, "tags are sorted")
equal("Tag B", items[2].label, "second tag")
equal(GetString(SI_AC_DEFAULT_NAME_EMPTY_TAG), items[3].label, "empty tag entry")
equal(SI_AC_MENU_CM_TAG_NEW, items[4].label, "new tag entry")
local created = AutoCategory.GetRuleByName("Ma catégorie")
equal(nil, created, "choosing a tag is required before creation")
menuItem("Tag A").callback()
created = AutoCategory.GetRuleByName("Ma catégorie")
equal(true, created ~= nil, "trimmed name is registered")
equal("Tag A", created.tag, "chosen tag is applied to the new rule")
equal("false", created.rule, "false rule is preserved literally")
equal(false, AutoCategory.compiledRules[created:key()](), "real compiled rule matches nothing")
equal(nil, created.level, "Normal level")
equal(nil, created.parent, "no inherited parent")
equal(2, #AutoCategory.saved.bags[3].rules, "captured bag receives category and placeholder")
equal(0, #AutoCategory.saved.bags[1].rules, "other bag unchanged")
equal("Ma catégorie", AutoCategory.saved.bags[3].rules[1].name, "saved bag entry")
local createdChild = AutoCategory.GetRuleByName("Ma catégorie " .. SI_AC_NEW_CATEGORY_EMPTY_CHILD)
equal(true, createdChild ~= nil, "the hidden placeholder child rule is created")
equal("false", createdChild.rule, "the placeholder child never matches")
equal(2, createdChild.level, "the placeholder child sits one level below")
equal("Ma catégorie", createdChild.parent, "the placeholder child nests under the new category")
equal("Tag A", createdChild.tag, "the placeholder child keeps the category's tag")
equal(true, AutoCategory.saved.bags[3].rules[2].isHidden, "the placeholder child bag rule is hidden")
equal(1000, AutoCategory.saved.bags[3].rules[2].showpriority,
    "the placeholder child keeps the display priority")
equal(1000, AutoCategory.saved.bags[3].rules[1].showpriority, "default sortable priority")
equal(2, cacheAdds, "cache updated for the category and its placeholder")
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
equal(2, #AutoCategory.RulesW.ruleList, "duplicate not suffixed or overwritten")
submit("MA CATéGORIE")
equal(SI_AC_DIALOG_CATEGORY_NAME_EXISTS, displayed.errorText, "case-insensitive duplicate")
equal(1, releases, "duplicate keeps popup open")
submit("Unique")
equal(2, releases, "corrected input closes popup")
menuItem(GetString(SI_AC_DEFAULT_NAME_EMPTY_TAG)).callback()
equal(2, #AutoCategory.saved.bags[1].rules, "corrected input creates in captured bag")
equal(GetString(SI_AC_DEFAULT_NAME_EMPTY_TAG),
    AutoCategory.GetRuleByName("Unique").tag, "empty tag entry keeps the default")

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

-- New Tag... dialog: blank refused, valid tag creates the category.
AutoCategory.saved.bags[8] = { rules = {} }
CLM.OpenNewCategoryDialog(8)
submit("Étiquetée")
menuItem(SI_AC_MENU_CM_TAG_NEW).callback()
submit("  ")
equal(SI_AC_DIALOG_TAG_NAME_EMPTY, displayed.errorText, "blank tag refused")
equal(0, #AutoCategory.saved.bags[8].rules, "blank tag creates nothing")
submit("  Ma nouvelle étiquette  ")
equal(4, releases, "tag dialog closes on success")
equal("Ma nouvelle étiquette",
    AutoCategory.GetRuleByName("Étiquetée").tag, "typed tag is applied")
equal(2, #AutoCategory.saved.bags[8].rules, "category created in captured bag")
equal(1000, AutoCategory.saved.bags[8].rules[1].showpriority,
    "tagged creation gets highest priority")
CLM.CreateCategory(8, "Sans étiquette")
equal(GetString(SI_AC_DEFAULT_NAME_EMPTY_TAG),
    AutoCategory.GetRuleByName("Sans étiquette").tag, "nil tag keeps the default")
-- the two creations above changed the rule count: re-baseline it
count = #AutoCategory.RulesW.ruleList

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
equal(releasedBefore + 1, releases, "name validation releases the popup")
menuItem("Tag A").callback()
equal(1, #chatMessages, "stale bag failure is reported in chat")
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
equal(1000, entries[7].showpriority, "repeated creation goes to the top")
equal(999, entries[5].showpriority, "previous new category remains directly below")
equal("false", first.rule, "priority placement keeps false rule")
equal(nil, second.level, "priority placement keeps Normal level")
equal(0, windowOpens, "priority placement never opens ordering window")
equal(true, AutoCategory.CategoryTree.BuildSortKey(entries[7].showpriority, second.name)
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
-- Move Category Up/Down: swap with the adjacent priority group,
-- inside the 2..1000 slider range, without touching runpriority.
AutoCategory.saved.bags[9] = { rules = {
    { name = "A", showpriority = 900, runpriority = 10 },
    { name = "B", showpriority = 500, runpriority = 20 },
    { name = "C", showpriority = 500, runpriority = 30 },
    { name = "D", showpriority = 100, runpriority = 40 },
} }
equal(true, CLM.CanMoveCategoryPriority(9, "B", 1), "B can move up")
equal(true, CLM.MoveCategoryPriority(9, "B", 1), "B moves up")
equal(900, AutoCategory.saved.bags[9].rules[2].showpriority, "B takes A's priority")
equal(500, AutoCategory.saved.bags[9].rules[1].showpriority, "A takes B's old priority")
equal(500, AutoCategory.saved.bags[9].rules[3].showpriority, "C keeps its group priority")
equal(20, AutoCategory.saved.bags[9].rules[2].runpriority, "runpriority untouched")
equal(true, CLM.MoveCategoryPriority(9, "B", -1), "B moves back down")
equal(500, AutoCategory.saved.bags[9].rules[2].showpriority, "B restored")
equal(900, AutoCategory.saved.bags[9].rules[1].showpriority, "A back on top")
equal(900, AutoCategory.saved.bags[9].rules[3].showpriority, "C moved up with the swap")
-- group below: B passes D's group
equal(true, CLM.MoveCategoryPriority(9, "B", -1), "B moves below D")
equal(100, AutoCategory.saved.bags[9].rules[2].showpriority, "B takes D's priority")
equal(500, AutoCategory.saved.bags[9].rules[4].showpriority, "D takes B's old priority")
-- bounds: a category at 1000 cannot move up, one at 2 cannot move down
AutoCategory.saved.bags[13] = { rules = {
    { name = "Top", showpriority = 1000, runpriority = 70 },
} }
equal(false, CLM.CanMoveCategoryPriority(13, "Top", 1), "1000 cannot move up")
equal(false, CLM.MoveCategoryPriority(13, "Top", 1), "top move refused")
equal(1000, AutoCategory.saved.bags[13].rules[1].showpriority, "top unchanged")
AutoCategory.saved.bags[10] = { rules = {
    { name = "Floor", showpriority = 2, runpriority = 50 },
} }
equal(false, CLM.CanMoveCategoryPriority(10, "Floor", -1), "floor cannot move down")
equal(false, CLM.MoveCategoryPriority(10, "Floor", -1), "floor move refused")
-- no adjacent group: the priority steps by one inside the bounds
AutoCategory.saved.bags[11] = { rules = {
    { name = "Solo", showpriority = 500, runpriority = 60 },
} }
equal(true, CLM.MoveCategoryPriority(11, "Solo", 1), "solo move up allowed")
equal(501, AutoCategory.saved.bags[11].rules[1].showpriority, "solo steps by one")
-- a bag rule without explicit showpriority uses runpriority and sets showpriority
AutoCategory.saved.bags[12] = { rules = {
    { name = "X", runpriority = 400 },
    { name = "Y", runpriority = 300 },
} }
equal(true, CLM.MoveCategoryPriority(12, "Y", 1), "implicit priority move")
equal(400, AutoCategory.saved.bags[12].rules[2].showpriority, "Y swaps to X's priority")
equal(300, AutoCategory.saved.bags[12].rules[1].showpriority, "X takes Y's implicit priority")
equal(400, AutoCategory.saved.bags[12].rules[1].runpriority, "X runpriority untouched")
-- unknown rule or bag: refused, nothing changes
equal(false, CLM.MoveCategoryPriority(9, "Nulle part", 1), "unknown rule refused")
equal(false, CLM.CanMoveCategoryPriority(99, "A", 1), "unknown bag refused")

print("CategoryCreation_test: " .. assertions .. " assertions passed")
