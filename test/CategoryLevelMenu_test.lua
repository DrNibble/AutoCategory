-- Run from the addon root with Lua 5.1:
-- lua5.1 test/CategoryLevelMenu_test.lua  (run from the AutoCategory/ addon folder)
-- Tests the flat category-header context menu operations, loading the
-- delivered files (never copies of them).

local assertions = 0
local function equal(expected, actual, message)
    assertions = assertions + 1
    assert(expected == actual, (message or "") .. ": expected "
        .. tostring(expected) .. ", got " .. tostring(actual))
end

-- ---------------------------------------------------------------------------
-- Stubs: the globals the delivered files expect from the ESO client
-- ---------------------------------------------------------------------------

-- string constants (the real translations live in lang/)
SI_AC_MENU_CM_LEVEL_SUBMENU = "Level"
SI_AC_MENU_CM_LEVEL_MOVE_UP = "Move Up ↑"
SI_AC_MENU_CM_LEVEL_DEEPER = "Increase Level →"
SI_AC_MENU_CM_LEVEL_SHALLOWER = "Decrease Level ←"
SI_AC_MENU_CM_LEVEL_MOVE_DOWN = "Move Down ↓"
SI_AC_MENU_CM_REMOVE_DISPLAY = "Remove from display"
SI_AC_MENU_CM_NEW_CATEGORY = "New Category"
SI_AC_MENU_CM_MANAGE_CATEGORIES = "Manage Categories"
SI_AC_DIALOG_CATEGORY_NAME_EMPTY = "Empty name"
SI_AC_DIALOG_CATEGORY_NAME_EXISTS = "Duplicate name"
SI_AC_DIALOG_CATEGORY_CREATE_FAILED = "Invalid bag"
SI_AC_MENU_CM_COPY_SUBMENU = "Copy To"
SI_AC_TIP_CM_COPY_OVERWRITE = "Already exists, select to overwrite"
SI_AC_MENU_CM_MOVE_SUBMENU = "Move To"
SI_AC_MENU_CM_MOVE_TOP = "Top Level"
SI_AC_MESSAGE_CM_COPY_DONE = "AutoCategory: %d categories copied to %s (%d already there)."
SI_AC_MESSAGE_CM_COPY_OVERWRITE_DONE = "AutoCategory: %d categories added to %s (%d overwritten)."
SI_AC_DEFAULT_NAME_NEW_CATEGORY = "NewCategory"
SI_AC_DEFAULT_NAME_EMPTY_TAG = "<Empty>"
SI_AC_NEW_CATEGORY_EMPTY_CHILD = "(empty)"
SI_AC_MENU_BS_SLIDER_CATEGORY_RUNPRIORITY = "Execution Priority"
SI_AC_MENU_BS_SLIDER_CATEGORY_RUNPRIORITY_TOOLTIP = "Execution priority tooltip"
SI_AC_MENU_CM_RULE = "Rule"

function GetString(si)
    return si
end

-- the rule mixin: only what the menu operations use
local ruleMixin = {
    isPredefined = function(self) return self.pred == 1 end,
    compile = function(self) return "" end,
}
local ruleMeta = { __index = ruleMixin }

AutoCategory = {}

-- load the delivered AutoCategory_CategoryTree.lua, then the delivered
-- CategoryLevelMenu.lua (never copies of them)
assert(loadfile("AutoCategory_Tree.lua"))()
assert(loadfile("AutoCategory_LevelMenu.lua"))()

local CLM = AutoCategory.CategoryLevelMenu
local CategoryTree = AutoCategory.CategoryTree

-- the level/parent layout of a predefined category is persisted as
-- an override in the account saved rules: record the sync calls
local syncCalls = 0
AutoCategory.SyncPredefinedLayouts = function() syncCalls = syncCalls + 1 end

-- a minimal rules world: the global rule list with a name lookup, the
-- same shape AutoCategory.RulesW provides
local ruleList = {}
local ruleNames = {}
AutoCategory.RulesW = { ruleList = ruleList, ruleNames = ruleNames }

local function addRule(rule)
    setmetatable(rule, ruleMeta)
    ruleList[#ruleList + 1] = rule
    ruleNames[rule.name] = #ruleList
    return rule
end

local function newRule(name, level, parent)
    return addRule({
        name = name, rule = "true", tag = "General",
        level = level, parent = parent,
    })
end

function AutoCategory.GetRuleByName(name)
    if not name then return nil end
    local ndx = ruleNames[name]
    return ndx and ruleList[ndx] or nil
end

function AutoCategory.GetUsableRuleName(name)
    name = tostring(name)
    local testName = name
    local index = 1
    while ruleNames[testName] do
        testName = name .. index
        index = index + 1
    end
    return testName
end

function AutoCategory.CreateRule(name, tag)
    local rule = { name = name, description = "", rule = "true", tag = tag }
    setmetatable(rule, ruleMeta)
    return rule
end

function AutoCategory.CreateBagRule(rule, runpriority, showprior)
    local name = type(rule) == "string" and rule or rule and rule.name
    if not name then return nil end
    local rp = runpriority or 1000
    return { name = name, runpriority = rp, showpriority = showprior or rp }
end

local arwAdded = {}
AutoCategory.ARW = {
    AddRule = function(self, newRule)
        addRule(newRule)
        arwAdded[#arwAdded + 1] = newRule
    end,
}

AutoCategory.cache = {
    bags_cvt = {
        choices = { "Backpack", "Bank", "Guild Bank" },
        choicesValues = { 1, 2, 3 },
    },
    AddRule = function() end,
}

local bags = {}
AutoCategory.saved = { bags = bags }

local function setBag(bagId, rules)
    bags[bagId] = { rules = rules }
end

local function bagNames(bagId)
    local names = {}
    for i = 1, #bags[bagId].rules do
        names[#names + 1] = bags[bagId].rules[i].name
    end
    return names
end

-- refresh stubs: the operations must call them after a change
local refreshCalls = { cacheInitialize = 0, RefreshCurrentList = 0,
    RefreshDropdownData = 0 }
function AutoCategory.cacheInitialize()
    refreshCalls.cacheInitialize = refreshCalls.cacheInitialize + 1
end
function AutoCategory.RefreshCurrentList()
    refreshCalls.RefreshCurrentList = refreshCalls.RefreshCurrentList + 1
end
AC_UI = {
    RefreshDropdownData = function()
        refreshCalls.RefreshDropdownData = refreshCalls.RefreshDropdownData + 1
    end,
    RefreshControls = function() end,
    BagSet_RefreshOrder = function() end,
}

local chatMessages = {}
CHAT_ROUTER = {
    AddSystemMessage = function(self, msg)
        chatMessages[#chatMessages + 1] = msg
    end,
}

-- context menu capture
local capturedSubmenus = {}
local capturedItems = {}
local capturedOrder = {}
local testMenu = {
    addItem = function(text, callback)
        capturedOrder[#capturedOrder + 1] = text
        capturedItems[#capturedItems + 1] = { label = text, callback = callback }
    end,
    addDivider = function() capturedOrder[#capturedOrder + 1] = "-" end,
    addSubMenu = function(text, entries, options)
        capturedOrder[#capturedOrder + 1] = text
        capturedSubmenus[#capturedSubmenus + 1] = { text = text, entries = entries,
            apply = options and options.copyAction, searchable = options and options.searchable }
    end,
}

-- ---------------------------------------------------------------------------
-- Part 1: EffectiveLevel and HeaderRule
-- ---------------------------------------------------------------------------

equal(1, CLM.EffectiveLevel({ level = nil }), "no level counts as 1")
equal(1, CLM.EffectiveLevel({ level = 1 }), "explicit level 1")
equal(3, CLM.EffectiveLevel({ level = 3 }), "explicit level 3")
equal(1, CLM.EffectiveLevel({ level = 0 }), "level 0 is out of range")
equal(1, CLM.EffectiveLevel({ level = 6 }), "level 6 is out of range")
equal(1, CLM.EffectiveLevel({ level = 2.5 }), "fractional level is out of range")
equal(1, CLM.EffectiveLevel(nil), "nil rule")

newRule("Flat", nil)
newRule("Potions", 1)
newRule("Magie", 2, "Potions")

equal("Flat", CLM.HeaderRule("Flat").name, "flat header name finds its rule")
equal("Magie", CLM.HeaderRule("Potions----Magie").name,
    "chain header name finds the deepest rule")
equal(nil, CLM.HeaderRule("NoSuchCategory"),
    "header with no backing rule finds nothing")
equal(nil, CLM.HeaderRule(nil), "nil header name")

-- ---------------------------------------------------------------------------
-- Part 2: DescendantsInBag and SubtreeInBag
-- ---------------------------------------------------------------------------

-- bag 1: Potions(1) > Magie(2) > Soin(3), plus an unrelated top level
setBag(1, {
    { name = "Potions", runpriority = 10, showpriority = 10 },
    { name = "Magie", runpriority = 9, showpriority = 9 },
    { name = "Soin", runpriority = 8, showpriority = 8 },
    { name = "Armes", runpriority = 7, showpriority = 7 },
})
newRule("Soin", 3, "Magie")
newRule("Armes", 1)

-- RuleChainPrefixes: every display name a rule contributes to the
-- lists of a bag that has it - the full chain and each prefix, the
-- same names Collapse All folds
local function prefixesOf(name)
    local out = {}
    for _, p in ipairs(CLM.RuleChainPrefixes(AutoCategory.GetRuleByName(name))) do
        out[#out + 1] = p
    end
    return table.concat(out, ",")
end
equal("Flat", prefixesOf("Flat"), "a Normal category contributes its name only")
equal("Potions", prefixesOf("Potions"), "a level 1 category contributes its name")
equal("Potions,Potions----Magie", prefixesOf("Magie"),
    "a nested category contributes its chain and each prefix")
equal("Potions,Potions----Magie,Potions----Magie----Soin", prefixesOf("Soin"),
    "the chain runs to the top")
equal(0, #CLM.RuleChainPrefixes(nil), "a nil rule contributes nothing")

-- a parent cycle must not loop
newRule("CycA", 2, "CycB")
newRule("CycB", 2, "CycA")
equal(true, #CLM.RuleChainPrefixes(AutoCategory.GetRuleByName("CycA")) >= 1,
    "a parent cycle terminates")

local function descendantNames(bagId, name)
    local names = {}
    for _, entry in ipairs(CLM.DescendantsInBag(bagId, name)) do
        names[#names + 1] = entry.rule.name
    end
    return names
end

equal("Magie,Soin", table.concat(descendantNames(1, "Potions"), ","),
    "descendants follow the parent chain to any depth")
equal("Soin", table.concat(descendantNames(1, "Magie"), ","),
    "descendants of a mid-level category")
equal("", table.concat(descendantNames(1, "Armes"), ","),
    "a category without children has no descendants")

-- a parent cycle must not loop or self-include
newRule("X")
newRule("Y")
ruleList[ruleNames["X"]].parent = "Y"
ruleList[ruleNames["Y"]].parent = "X"
setBag(2, {
    { name = "X", runpriority = 1, showpriority = 1 },
    { name = "Y", runpriority = 1, showpriority = 1 },
})
equal("Y", table.concat(descendantNames(2, "X"), ","),
    "a cycle makes the other rule a descendant, never the rule itself")

-- SubtreeInBag: the category first, then its descendants
setBag(3, {
    { name = "Potions", runpriority = 10, showpriority = 10 },
    { name = "Magie", runpriority = 9, showpriority = 9 },
})
local subtree = CLM.SubtreeInBag(3, "Potions")
equal(2, #subtree, "subtree = category + descendants")
equal("Potions", subtree[1].rule.name, "the category comes first")
equal("Magie", subtree[2].rule.name, "then the descendants")
equal(nil, CLM.SubtreeInBag(3, "Armes"),
    "a rule that is not a category of the bag has no subtree")

-- ---------------------------------------------------------------------------
-- Part 3: ShiftLevels (increase and decrease)
-- ---------------------------------------------------------------------------

-- bag 4: D(1) displays above A(1) > B(2) > C(3)
setBag(4, {
    { name = "D", runpriority = 20, showpriority = 20 },
    { name = "A", runpriority = 10, showpriority = 10 },
    { name = "B", runpriority = 9, showpriority = 9 },
    { name = "C", runpriority = 8, showpriority = 8 },
})
local rD, rA, rB, rC = newRule("D", 1), newRule("A", 1),
    newRule("B", 2, "A"), newRule("C", 3, "B")

subtree = CLM.SubtreeInBag(4, "A")
equal(true, CLM.CanIncrease(subtree), "levels 1-3 can increase")
local syncBefore = syncCalls
equal(true, CLM.ShiftLevels(4, subtree, 1), "increase applies")
equal(syncBefore + 1, syncCalls, "a level shift persists the predefined layouts")
equal(2, rA.level, "the category moves one level deeper")
equal("D", rA.parent, "a top-level category attaches to the nearest level above")
equal(3, rB.level, "children move one level deeper")
equal("A", rB.parent, "children keep their parent")
equal(4, rC.level, "grandchildren move one level deeper")

-- increase is refused when any category of the subtree is at level 5
equal(true, CLM.CanIncrease(CLM.SubtreeInBag(4, "A")),
    "levels 2-4 can still increase")
rC.level = 5
equal(false, CLM.CanIncrease(CLM.SubtreeInBag(4, "A")),
    "a level 5 category blocks the increase")
local syncBefore2 = syncCalls
equal(false, CLM.ShiftLevels(4, CLM.SubtreeInBag(4, "A"), 1),
    "the refused increase changes nothing")
equal(syncBefore2, syncCalls, "a refused shift persists nothing")
equal(2, rA.level, "levels untouched after a refused increase")

-- decrease: explicit levels go down, level 1 becomes Normal
equal(true, CLM.ShiftLevels(4, CLM.SubtreeInBag(4, "A"), -1), "decrease applies")
equal(nil, rA.level, "a decreased level 1 becomes Normal (no level)")
equal(nil, rA.parent, "a Normal category has no parent")
equal(2, rB.level, "children move one level shallower")
equal("A", rB.parent, "children keep their parent")
equal(4, rC.level, "deeper children keep their relative depth")
equal("B", rC.parent, "deeper children keep their parent")

-- nothing to decrease when everything is Normal
rB.level, rC.level = nil, nil
equal(false, CLM.CanDecrease(CLM.SubtreeInBag(4, "A")),
    "all-Normal subtree cannot decrease")
equal(false, CLM.ShiftLevels(4, CLM.SubtreeInBag(4, "A"), -1),
    "a decrease without explicit levels changes nothing")

-- a parent set by the user is kept when increasing
rA.level, rA.parent = 1, "D"
equal(true, CLM.ShiftLevels(4, CLM.SubtreeInBag(4, "A"), 1))
equal("D", rA.parent, "an existing parent is kept")

-- ---------------------------------------------------------------------------
-- Part 4: CopySubtreeToBag
-- ---------------------------------------------------------------------------

-- bag 5: P(1) > M(2) > S(3); bag 6: empty; bag 7: already has S
setBag(5, {
    { name = "P", runpriority = 30, showpriority = 30 },
    { name = "M", runpriority = 20, showpriority = 20 },
    { name = "S", runpriority = 10, showpriority = 10 },
})
newRule("P", 1)
newRule("M", 2, "P")
newRule("S", 3, "M")
setBag(6, {})
setBag(7, { { name = "S", runpriority = 5, showpriority = 5 } })

local copied, skipped = CLM.CopySubtreeToBag(5, "P", 6)
equal(3, copied, "the level and its children are copied")
equal(0, skipped, "nothing skipped in an empty bag")
equal("P,M,S", table.concat(bagNames(6), ","), "the copy reuses the global rules")
equal(30, bags[6].rules[1].runpriority, "the copy keeps the priorities")
equal(20, bags[6].rules[2].showpriority, "each category keeps its own priorities")

-- a category already present in the destination bag is skipped
copied, skipped = CLM.CopySubtreeToBag(5, "P", 7)
equal(2, copied, "P and M are added, S is already there")
equal(1, skipped, "S is reported as skipped")
equal("S,P,M", table.concat(bagNames(7), ","))

-- copying a mid-level category brings its missing ancestors along, so
-- it keeps its place in the level hierarchy of the destination bag
setBag(8, {})
copied, skipped = CLM.CopySubtreeToBag(5, "M", 8)
equal(3, copied, "the ancestors are copied with a mid-level category")
equal("P,M,S", table.concat(bagNames(8), ","))

-- copying to the same bag does nothing
equal(0, select(1, CLM.CopySubtreeToBag(5, "P", 5)),
    "copying to the same bag copies nothing")

-- a category that is not in the source bag has nothing to copy
equal(0, select(1, CLM.CopySubtreeToBag(5, "Armes", 6)),
    "copying a category of another bag copies nothing")

-- ---------------------------------------------------------------------------
-- Part 5: CreateCategory
-- ---------------------------------------------------------------------------

setBag(9, { { name = "Niv1", runpriority = 10, showpriority = 10 } })
newRule("Niv1", 1)

local newRuleResult = CLM.CreateCategory(9, "NewCategory")
equal(true, newRuleResult ~= nil, "a new named category is created")
equal("false", newRuleResult.rule, "the new category has the rule false")
equal(nil, newRuleResult.level, "the new category is Normal")
equal(nil, newRuleResult.parent, "the new category has no parent")
equal("Niv1,NewCategory,NewCategory (empty)", table.concat(bagNames(9), ","),
    "the new category is added to the bag with its placeholder child")
equal(1000, bags[9].rules[2].runpriority, "the new category uses default priorities")
local newChildRule = AutoCategory.GetRuleByName("NewCategory (empty)")
equal(true, newChildRule ~= nil, "the placeholder child rule is created")
equal("false", newChildRule.rule, "the placeholder child never matches")
equal(2, newChildRule.level, "the placeholder child sits one level below")
equal("NewCategory", newChildRule.parent, "the placeholder child nests under the new category")
equal(GetString(SI_AC_DEFAULT_NAME_EMPTY_TAG), newChildRule.tag,
    "the placeholder child keeps the same tag")
equal(true, bags[9].rules[3].isHidden, "the placeholder child bag rule is hidden")
equal(bags[9].rules[2].showpriority, bags[9].rules[3].showpriority,
    "the placeholder child keeps the new category's display priority")

-- Creation is independent of the clicked category's level.
newRule("Niv5", 5)
setBag(10, { { name = "Niv5", runpriority = 1, showpriority = 1 } })
equal(nil, CLM.CreateCategory(10, "NewCategory"),
    "duplicate names are refused instead of suffixed")

-- ---------------------------------------------------------------------------
-- Part 6: DeleteLevelInBag
-- ---------------------------------------------------------------------------

-- bag 11: Top(1) > A(2) > B(3), C(3) also directly under A
setBag(11, {
    { name = "Top", runpriority = 30, showpriority = 30 },
    { name = "A", runpriority = 20, showpriority = 20 },
    { name = "B", runpriority = 10, showpriority = 10 },
    { name = "C", runpriority = 5, showpriority = 5 },
})
local rTop, rA2, rB2, rC2 = newRule("Top", 1), newRule("A", 2, "Top"),
    newRule("B", 3, "A"), newRule("C", 3, "A")

equal(true, CLM.DeleteLevelInBag(11, "A"), "the level is deleted from the bag")
equal("Top,B,C", table.concat(bagNames(11), ","),
    "only the category is removed from the bag")
equal(true, ruleNames["A"] ~= nil, "the global rule is kept")
equal(2, rB2.level, "children move up one level")
equal("Top", rB2.parent, "children nest under the deleted category's parent")
equal(2, rC2.level, "direct children move up one level")
equal("Top", rC2.parent, "direct children nest under the grandparent")
equal(1, rTop.level, "unrelated categories are untouched")

-- deleting a top-level category flattens its children
setBag(12, {
    { name = "Root", runpriority = 10, showpriority = 10 },
    { name = "Kid", runpriority = 5, showpriority = 5 },
})
local rRoot, rKid = newRule("Root", 1), newRule("Kid", 2, "Root")
equal(true, CLM.DeleteLevelInBag(12, "Root"))
equal(nil, rKid.level, "children of a deleted top level become Normal")
equal(nil, rKid.parent, "children of a deleted top level have no parent")
equal("Kid", table.concat(bagNames(12), ","))

-- deleting a category that is not in the bag changes nothing
equal(false, CLM.DeleteLevelInBag(12, "Root"), "nothing to delete")

-- ---------------------------------------------------------------------------
-- Part 7: the context menu itself
-- ---------------------------------------------------------------------------

-- a header of a category of the bag gets the Rule submenu, the Level
-- submenu and the Copy To submenu (Kid is Normal and alone in the
-- bag here: no Decrease entry, no move entries; three copy entries
-- for the three bags of the stub other than the clicked one)
capturedSubmenus = {}
capturedItems = {}
capturedOrder = {}
AutoCategory.AddCategoryLevelMenuEntries("Root----Kid", 12, testMenu, "Nom affiché")
equal("-", capturedOrder[1], "divider comes immediately before Rule")
equal("Rule", capturedOrder[2], "Rule follows the divider")
equal(3, #capturedItems, "removal, creation and management for an operable header")
equal("Remove from display", capturedItems[1].label, "the removal entry comes after the operations")
equal("New Category", capturedItems[2].label)
equal("Manage Categories", capturedItems[3].label, "management comes last")
local openedBag
AutoCategory.CategoryManagement = { Open = function(bagId, refresh)
    openedBag = bagId
    equal("function", type(refresh), "refresh callback is passed to the manager")
end }
capturedItems[3].callback()
equal(12, openedBag, "manager uses the clicked bag")
equal(3, #capturedSubmenus, "a Rule, a Level and a Copy To submenu")
equal("Rule", capturedSubmenus[1].text,
    "the rule submenu comes first")
local ruleMenu = capturedSubmenus[1].entries
equal(3, #ruleMenu, "the rule submenu holds the title, priority and rule text")
equal(true, ruleMenu[1].isHeader, "the title is a header row")
equal("Nom affiché", ruleMenu[1].label, "use the actual display name, not the synthetic path")
equal(nil, ruleMenu[1].callback, "the category title isn't clickable")
local slider = ruleMenu[2].slider
equal("Execution Priority", slider.label, "the rule submenu shows the priority slider")
equal(5, slider.data.value(), "the slider starts at the bag rule's execution priority")
equal(0, slider.data.min, "the slider starts at zero")
equal(1000, slider.data.max, "the slider is bounded by 1000")
local callsBefore = refreshCalls.cacheInitialize
slider.callback(5)
equal(callsBefore, refreshCalls.cacheInitialize, "initial value does not refresh")
slider.callback(9.6)
equal(10, bags[12].rules[1].runpriority, "the slider rounds valid input")
equal(5, bags[12].rules[1].showpriority, "display priority is untouched")
equal(callsBefore + 1, refreshCalls.cacheInitialize, "the changed slider refreshes once")
equal("true", ruleMenu[3].label, "the rule submenu shows the rule text")
equal("Level", capturedSubmenus[2].text, "the level operations sit in their own submenu")
local levelMenu = capturedSubmenus[2].entries
equal(1, #levelMenu, "Kid is Normal and alone: no Decrease entry, no move entries")
equal("Increase Level →", levelMenu[1].label)
equal("Copy To", capturedSubmenus[3].text, "the third submenu is the Copy To menu")
menu = capturedSubmenus[3].entries
equal(3, #menu, "the copy entries list the other bags")
equal("Backpack", menu[1].label)
equal("Bank", menu[2].label)
equal("Guild Bank", menu[3].label)

-- the callbacks run the operations and refresh
refreshCalls.cacheInitialize = 0
levelMenu[1].callback()
equal(2, rKid.level, "the increase callback deepens the level")
equal(1, refreshCalls.cacheInitialize, "the callbacks refresh the caches")

-- the removal callback removes the category from the inventory
-- list of the clicked bag only: the global rule stays
refreshCalls.cacheInitialize = 0
capturedItems[1].callback()
equal(1, refreshCalls.cacheInitialize, "the removal callback refreshes the caches")
equal(0, #AutoCategory.saved.bags[12].rules, "the category leaves the bag list")
equal(true, rKid ~= nil, "the global rule is kept")

-- A header with no backing rule still gets category creation and management.
capturedSubmenus = {}
capturedItems = {}
AutoCategory.AddCategoryLevelMenuEntries("Others", 12, testMenu)
equal(2, #capturedItems, "creation and management are offered on ungrouped headers")
equal(0, #capturedSubmenus, "no submenu for a category without a rule")

-- a predefined (protected) rule: its level and its priorities can be
-- changed, and its display can be removed from the clicked bag too
-- (the protected rule itself is never deletable)
newRule("Pred", 1)
ruleList[ruleNames["Pred"]].pred = 1
setBag(13, { { name = "Pred", runpriority = 1, showpriority = 1 } })
capturedSubmenus = {}
capturedItems = {}
AutoCategory.AddCategoryLevelMenuEntries("Pred", 13, testMenu)
equal(3, #capturedItems, "removal, creation and management for a predefined rule")
equal("Remove from display", capturedItems[1].label,
    "a predefined rule is offered the removal")
equal("New Category", capturedItems[2].label)
equal(3, #capturedSubmenus,
    "a Rule, a Level and a Copy To submenu for a predefined rule")
equal("Rule", capturedSubmenus[1].text, "the predefined rule text shows too")
equal("Level", capturedSubmenus[2].text)
equal(2, #capturedSubmenus[2].entries, "alone in the bag: no move entries")
equal("Increase Level →", capturedSubmenus[2].entries[1].label)
equal("Decrease Level ←", capturedSubmenus[2].entries[2].label,
    "an explicit level 1 can go back to Normal")
equal("Copy To", capturedSubmenus[3].text)
equal(3, #capturedSubmenus[3].entries, "the copy entries are offered for a predefined rule")

-- the removal of a predefined category only takes it out of the
-- inventory list of the clicked bag: the protected rule is kept
refreshCalls.cacheInitialize = 0
capturedItems[1].callback()
equal(1, refreshCalls.cacheInitialize, "the removal callback refreshes the caches")
equal(0, #AutoCategory.saved.bags[13].rules, "the predefined category leaves the bag list")
equal(true, ruleList[ruleNames["Pred"]] ~= nil, "the protected rule is kept")

-- A category outside the clicked bag has no level operations.
capturedSubmenus = {}
capturedItems = {}
AutoCategory.AddCategoryLevelMenuEntries("Root", 13, testMenu)
equal(2, #capturedItems, "creation and management only need the captured bag")
equal(0, #capturedSubmenus, "no submenu outside the bag of the header")

-- At level 5 only increase is left out; creation is independent.
newRule("Deep", 5)
setBag(14, { { name = "Deep", runpriority = 1, showpriority = 1 } })
capturedSubmenus = {}
capturedItems = {}
AutoCategory.AddCategoryLevelMenuEntries("Deep", 14, testMenu)
equal(3, #capturedItems, "removal, creation and management at level 5")
equal("Remove from display", capturedItems[1].label)
equal("New Category", capturedItems[2].label)
equal(4, #capturedSubmenus, "Rule, Level, Move To and Copy To submenus at level 5")
equal("Rule", capturedSubmenus[1].text)
equal("Level", capturedSubmenus[2].text)
equal(1, #capturedSubmenus[2].entries, "no Increase at level 5, no neighbor to move to")
equal("Decrease Level ←", capturedSubmenus[2].entries[1].label)
equal("Move To", capturedSubmenus[3].text)
equal(1, #capturedSubmenus[3].entries,
    "only the top level entry: no other category in the bag")
equal("Top Level", capturedSubmenus[3].entries[1].label)
menu = capturedSubmenus[4].entries
equal(3, #menu, "the copy entries are still offered at level 5")
equal("Backpack", menu[1].label)

-- the copy callback copies and reports to the chat
setBag(15, { { name = "CopyMe", runpriority = 7, showpriority = 7 } })
newRule("CopyMe", 1)
capturedSubmenus = {}
capturedItems = {}
AutoCategory.AddCategoryLevelMenuEntries("CopyMe", 15, testMenu)
equal(3, #capturedSubmenus, "a Rule, a Level and a Copy To submenu")
equal("Rule", capturedSubmenus[1].text)
equal("Level", capturedSubmenus[2].text)
equal("Copy To", capturedSubmenus[3].text)
menu = capturedSubmenus[3].entries
local copyEntry = nil
for i = 1, #menu do
    if menu[i].label == "Backpack" then
        copyEntry = menu[i]
    end
end
equal(true, copyEntry ~= nil, "the copy entries list the other bags")
chatMessages = {}
copyEntry.onChecked(true)
capturedSubmenus[3].apply()
equal("CopyMe", bagNames(1)[#bagNames(1)],
    "the copy target bag received the category")
equal("AutoCategory: 1 categories copied to Backpack (0 already there).",
    chatMessages[1], "the copy reports to the chat")

-- ---------------------------------------------------------------------------
-- Part 8: MoveSubtreeToParent and the Move To submenu
-- ---------------------------------------------------------------------------

-- bag 20: TopA(Normal), TopB(1), Mid(2, TopA), Leaf(3, Mid), Other(1)
setBag(20, {
    { name = "TopA", runpriority = 50, showpriority = 50 },
    { name = "TopB", runpriority = 40, showpriority = 40 },
    { name = "Mid", runpriority = 30, showpriority = 30 },
    { name = "Leaf", runpriority = 20, showpriority = 20 },
    { name = "Other", runpriority = 10, showpriority = 10 },
})
local rTopA, rTopB = newRule("TopA", nil), newRule("TopB", 1)
local rMid, rLeaf = newRule("Mid", 2, "TopA"), newRule("Leaf", 3, "Mid")
local rOther = newRule("Other", 1)

-- move Mid under TopB: same depth, Leaf keeps its place under Mid
local syncBefore3 = syncCalls
equal(true, CLM.MoveSubtreeToParent(20, "Mid", "TopB"),
    "the category moves under another category")
equal(syncBefore3 + 1, syncCalls, "a move persists the predefined layouts")
equal("TopB", rMid.parent, "the moved category is parented to the target")
equal(2, rMid.level, "the moved category sits one level below the target")
equal(3, rLeaf.level, "the children keep their depth under the category")
equal("Mid", rLeaf.parent, "the children keep their parent")

-- move Leaf under TopA (a Normal category): level 2
equal(true, CLM.MoveSubtreeToParent(20, "Leaf", "TopA"))
equal(2, rLeaf.level, "a move under a Normal category nests at level 2")
equal("TopA", rLeaf.parent)

-- move Leaf back to the top level: Normal, no parent
equal(true, CLM.MoveSubtreeToParent(20, "Leaf", nil))
equal(nil, rLeaf.level, "a move to the top level makes the category Normal")
equal(nil, rLeaf.parent, "a move to the top level clears the parent")

-- refused moves
local syncBefore4 = syncCalls
equal(false, CLM.MoveSubtreeToParent(20, "Mid", "Mid"),
    "cannot move under itself")
equal(syncBefore4, syncCalls, "a refused move persists nothing")
equal(false, CLM.MoveSubtreeToParent(20, "Mid", "TopB"),
    "cannot move under the current parent")
equal(false, CLM.MoveSubtreeToParent(20, "TopB", "Mid"),
    "cannot move under a category nested under it (cycle)")
equal(false, CLM.MoveSubtreeToParent(20, "Leaf", nil),
    "nothing to move when already top level")
equal(false, CLM.MoveSubtreeToParent(20, "Mid", "NoSuchRule"),
    "the target must be an existing rule")
newRule("Elsewhere", 1)
setBag(22, { { name = "Elsewhere", runpriority = 1, showpriority = 1 } })
equal(false, CLM.MoveSubtreeToParent(20, "Mid", "Elsewhere"),
    "the target must be a category of the same bag")

-- the section must fit under the target: bag 21 has X(1), A(1) with
-- B(2) > C(3) > D(4) > E(5) under A
setBag(21, {
    { name = "X", runpriority = 60, showpriority = 60 },
    { name = "A", runpriority = 50, showpriority = 50 },
    { name = "B", runpriority = 40, showpriority = 40 },
    { name = "C", runpriority = 30, showpriority = 30 },
    { name = "D", runpriority = 20, showpriority = 20 },
    { name = "E", runpriority = 10, showpriority = 10 },
})
newRule("X", 1)
local rA, rB = newRule("A", 1), newRule("B", 2, "A")
local rC, rD = newRule("C", 3, "B"), newRule("D", 4, "C")
local rE = newRule("E", 5, "D")
equal(false, CLM.MoveSubtreeToParent(21, "A", "X"),
    "a section too deep for the target is refused")
equal(true, CLM.MoveSubtreeToParent(21, "D", "X"),
    "a section that fits moves with its children")
equal(2, rD.level, "the moved category sits one level below the target")
equal("X", rD.parent)
equal(3, rE.level, "the children shift with the category")
equal("D", rE.parent, "the children keep their parent")

-- the Move To submenu: the candidates of the bag in display order,
-- never the category itself, its children or its current parent
capturedSubmenus = {}
capturedItems = {}
AutoCategory.AddCategoryLevelMenuEntries("Mid", 20, testMenu)
equal(3, #capturedItems, "removal, creation and management entries")
equal("Remove from display", capturedItems[1].label)
equal("New Category", capturedItems[2].label)
equal(4, #capturedSubmenus, "a Rule, a Level, a Move To and a Copy To submenu")
equal("Level", capturedSubmenus[2].text)
equal(4, #capturedSubmenus[2].entries, "all four level operations for a mid-level category")
equal("Move Up ↑", capturedSubmenus[2].entries[1].label)
equal("Increase Level →", capturedSubmenus[2].entries[2].label)
equal("Decrease Level ←", capturedSubmenus[2].entries[3].label)
equal("Move Down ↓", capturedSubmenus[2].entries[4].label)

-- the level move callbacks take the display priority of the
-- category displayed just above/below and step one past it
refreshCalls.cacheInitialize = 0
capturedSubmenus[2].entries[1].callback()
equal(41, AutoCategory.saved.bags[20].rules[3].showpriority,
    "move up takes one above the neighbor's priority")
equal(1, refreshCalls.cacheInitialize, "the move callback refreshes the caches")
capturedSubmenus[2].entries[4].callback()
equal(39, AutoCategory.saved.bags[20].rules[3].showpriority,
    "move down takes one below the neighbor's priority")

equal("Move To", capturedSubmenus[3].text)
equal("Copy To", capturedSubmenus[4].text)
local moveMenu = capturedSubmenus[3].entries
equal(4, #moveMenu, "top level, then the candidates in display order")
equal("Top Level", moveMenu[1].label)
equal("TopA", moveMenu[2].label)
equal("Leaf", moveMenu[3].label)
equal("Other", moveMenu[4].label)

-- the move callback moves and refreshes
refreshCalls.cacheInitialize = 0
moveMenu[2].callback()
equal("TopA", rMid.parent, "the move callback parents to the target")
equal(1, refreshCalls.cacheInitialize, "the callbacks refresh the caches")

-- a long rule text is wrapped over several single-line entries: the
-- context menu entries never wrap, so the words stay whole and each
-- line fits the menu; the entries joined back give the rule again.
-- Kid is reset to Normal so the submenu count stays the one above
setBag(12, { { name = "Kid", runpriority = 5, showpriority = 5 } })
rKid.level = nil
rKid.parent = nil
rKid.rule = "type(2) and quality(2) and (isSetOf(1) or isSetOf(2)) and not (bound() or stolen()) and level() >= 50 and (trait(1) or trait(2) or trait(3)) and (enchant() or poisen()) and (stolen() and fencePrice() > 100 or not stolen()) and (bagId() == 1 or bagId() == 2) and (isJunk() or isUsable()) and (potency() or aspect()) and (essence() or style()) and (hasEnchant() or hasPoisen() or hasCharge()) and (isImproved() or isRetraitable()) and (isInHouse() or isTreasure() or isOrnate()) and (isStackable() or isCrafted() or isRefined())"
capturedSubmenus = {}
capturedItems = {}
AutoCategory.AddCategoryLevelMenuEntries("Root----Kid", 12, testMenu)
equal(3, #capturedSubmenus, "the rule submenu is there for a long rule too")
local longMenu = capturedSubmenus[1].entries
equal(true, #longMenu > 4, "a long rule is wrapped over several entries")
local joined = {}
for i = 3, #longMenu do joined[#joined + 1] = longMenu[i].label end
equal(rKid.rule, table.concat(joined, " "),
    "the wrapped entries joined back give the rule again")
for i = 3, #longMenu do
    equal(true, #longMenu[i].label <= 75, "each wrapped line fits the menu width")
end

-- Copy To multiselect: matching root, descendant-only overlap, and a
-- conflicting destination that is deselected before applying.
AutoCategory.cache.bags_cvt = {
    choices = { "Source", "Matching root", "Descendant only", "Deselected" },
    choicesValues = { 5, 6, 7, 8 },
}
newRule("Destination only", 3, "M")
local sourceM, sourceS = bags[5].rules[2], bags[5].rules[3]
sourceS.isHidden = true
local existingAncestor = { name = "P", runpriority = 2, showpriority = 3 }
local existingM = { name = "M", runpriority = 1, showpriority = 2, isHidden = true }
local existingS = { name = "S", runpriority = 3, showpriority = 4 }
local destOnly = { name = "Destination only", runpriority = 6, showpriority = 7 }
local descendantOnly = { name = "S", runpriority = 500, showpriority = 501 }
local deselected = { name = "M", runpriority = 600, showpriority = 601 }
setBag(6, { existingAncestor, existingM, existingS, destOnly })
setBag(7, { descendantOnly })
setBag(8, { deselected })

capturedSubmenus = {}
AutoCategory.AddCategoryLevelMenuEntries("P----M", 5, testMenu)
local copyMenu = capturedSubmenus[#capturedSubmenus]
equal("Copy To", copyMenu.text, "copy is the final submenu")
local destinations, apply = copyMenu.entries, copyMenu.apply
equal(3, #destinations, "the source bag is excluded")
equal("Matching root", destinations[1].label)
equal(SI_AC_TIP_CM_COPY_OVERWRITE, destinations[1].overwriteTooltip, "the matching root is marked")
equal(nil, destinations[2].overwriteTooltip, "a descendant alone does not mark the bag")
equal(SI_AC_TIP_CM_COPY_OVERWRITE, destinations[3].overwriteTooltip, "both matching bags are marked")

local messageCount, refreshCount = #chatMessages, refreshCalls.cacheInitialize
apply()
equal(messageCount, #chatMessages, "an empty selection does not copy")
equal(refreshCount, refreshCalls.cacheInitialize, "an empty selection does not refresh")
destinations[1].onChecked(true)
destinations[2].onChecked(true)
destinations[3].onChecked(true)
destinations[3].onChecked(false)
equal(1, existingM.runpriority, "checking a bag alone does not overwrite")
equal("S", table.concat(bagNames(7), ","), "copy only happens on apply")
apply()
equal(refreshCount + 1, refreshCalls.cacheInitialize, "the whole batch refreshes once")
equal(messageCount + 2, #chatMessages, "only selected bags report results")
equal("AutoCategory: 0 categories added to Matching root (2 overwritten).", chatMessages[messageCount + 1])
equal("AutoCategory: 2 categories copied to Descendant only (1 already there).", chatMessages[messageCount + 2])
equal("P,M,S,Destination only", table.concat(bagNames(6), ","), "no duplicates or loss")
equal(sourceM.runpriority, existingM.runpriority, "root execution priority is copied")
equal(sourceM.showpriority, existingM.showpriority, "root display priority is copied")
equal(nil, existingM.isHidden, "a visible source entry clears the hidden flag")
equal(sourceS.runpriority, existingS.runpriority, "existing descendants are overwritten in a red bag")
equal(true, existingS.isHidden, "a hidden source entry copies its hidden flag")
equal(500, descendantOnly.runpriority, "unmarked destinations do not overwrite descendants")
equal("S,P,M", table.concat(bagNames(7), ","), "missing ancestors and the root are added")
equal(2, existingAncestor.runpriority, "an existing ancestor is not overwritten")
equal(6, destOnly.runpriority, "unrelated destination entries are untouched")
equal(600, deselected.runpriority, "a deselected red bag is not overwritten")
equal("M", AutoCategory.GetRuleByName("S").parent, "global hierarchy is unchanged")
apply()
equal(messageCount + 2, #chatMessages, "applying again does not repeat the batch")

-- Indent by two literal spaces per nested level. The indent is display
-- only: the action must still resolve the destination by its real name.
newRule("Indent source")
newRule("Indent L1", 1)
newRule("Indent L2", 2, "Indent L1")
newRule("Indent L3", 3, "Indent L2")
newRule("Indent L4", 4, "Indent L3")
newRule("Indent L5", 5, "Indent L4")
setBag(23, {
    { name = "Indent source", runpriority = 60, showpriority = 60 },
    { name = "Indent L1", runpriority = 50, showpriority = 50 },
    { name = "Indent L2", runpriority = 40, showpriority = 40 },
    { name = "Indent L3", runpriority = 30, showpriority = 30 },
    { name = "Indent L4", runpriority = 20, showpriority = 20 },
    { name = "Indent L5", runpriority = 10, showpriority = 10 },
})
capturedSubmenus = {}
AutoCategory.AddCategoryLevelMenuEntries("Indent source", 23, testMenu)
local indentEntries
for _, submenu in ipairs(capturedSubmenus) do
    if submenu.text == "Move To" then
        indentEntries = submenu.entries
        equal(true, submenu.searchable, "the Move To renderer is asked to provide a search field")
    else
        equal(nil, submenu.searchable, "sibling submenus are not searchable")
        if submenu.text == "Rule" then
            equal("Indent source", submenu.entries[1].label, "fall back to the rule name when needed")
        end
    end
end
equal(4, #indentEntries, "level five still cannot be a destination")
equal("Indent L1", indentEntries[1].label)
equal("  Indent L2", indentEntries[2].label)
equal("    Indent L3", indentEntries[3].label)
equal("      Indent L4", indentEntries[4].label)
indentEntries[4].callback()
equal("Indent L4", AutoCategory.GetRuleByName("Indent source").parent, "move resolves the unindented name")
equal(5, AutoCategory.GetRuleByName("Indent source").level, "move still nests under the selected level")

print("CategoryLevelMenu_test: " .. assertions .. " assertions passed")
