-- Run from the addon root with Lua 5.1:
-- lua5.1 test/CategoryLevelMenu_test.lua  (run from the AutoCategory/ addon folder)
-- Tests the category header context menu level operations (the
-- AutoCategory submenu of the inventory category header right click
-- menu), loading the delivered files (never copies of them).

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
SI_AC_MENU_CM_SUBMENU = "AutoCategory"
SI_AC_MENU_CM_LEVEL_UP = "Increase Level"
SI_AC_MENU_CM_LEVEL_DOWN = "Decrease Level"
SI_AC_MENU_CM_NEW_LEVEL = "New Sub-Level"
SI_AC_MENU_CM_DELETE_LEVEL = "Delete Level"
SI_AC_MENU_CM_COPY_TO = "Copy to: %s"
SI_AC_MESSAGE_CM_COPY_DONE = "AutoCategory: %d categories copied to %s (%d already there)."
SI_AC_DEFAULT_NAME_NEW_CATEGORY = "NewCategory"
SI_AC_DEFAULT_NAME_EMPTY_TAG = "<Empty>"

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

-- a minimal rules world: the global rule list with a name lookup, the
-- same shape AutoCategory.RulesW provides
local ruleList = {}
local ruleNames = {}

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
function AddCustomSubMenuItem(text, entries)
    capturedSubmenus[#capturedSubmenus + 1] = { text = text, entries = entries }
end
function AddMenuItem() end
function ClearMenu() end
function ShowMenu() end

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
equal(true, CLM.ShiftLevels(4, subtree, 1), "increase applies")
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
equal(false, CLM.ShiftLevels(4, CLM.SubtreeInBag(4, "A"), 1),
    "the refused increase changes nothing")
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
-- Part 5: CreateSubLevel
-- ---------------------------------------------------------------------------

setBag(9, { { name = "Niv1", runpriority = 10, showpriority = 10 } })
newRule("Niv1", 1)

local newRuleResult = CLM.CreateSubLevel(9, "Niv1")
equal(true, newRuleResult ~= nil, "a new sub-level is created")
equal("false", newRuleResult.rule, "the new level has the rule false")
equal(2, newRuleResult.level, "the new level is one deeper")
equal("Niv1", newRuleResult.parent, "the new level nests under the category")
equal("Niv1,NewCategory", table.concat(bagNames(9), ","),
    "the new level is added to the bag")
equal(10, bags[9].rules[2].runpriority, "the new level keeps the category's priorities")

-- no new level under a level 5 category
newRule("Niv5", 5)
setBag(10, { { name = "Niv5", runpriority = 1, showpriority = 1 } })
equal(nil, CLM.CreateSubLevel(10, "Niv5"),
    "no new level under a level 5 category")

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

-- a header of a category of the bag gets the AutoCategory submenu
-- (Kid is Normal here: no Decrease entry, three copy entries for the
-- three bags of the stub other than the clicked one)
capturedSubmenus = {}
AutoCategory.AddCategoryLevelMenuEntries("Root----Kid", 12)
equal(1, #capturedSubmenus, "one submenu is added for an operable header")
equal("AutoCategory", capturedSubmenus[1].text, "the submenu is the AutoCategory menu")
local menu = capturedSubmenus[1].entries
equal(6, #menu, "increase, new level, delete and three copy entries")
equal("Increase Level", menu[1].label, "first entry increases the level")
equal("New Sub-Level", menu[2].label)
equal("Delete Level", menu[3].label)
equal("Copy to: Backpack", menu[4].label,
    "the copy entries list the other bags")

-- the callbacks run the operations and refresh
refreshCalls.cacheInitialize = 0
menu[1].callback()
equal(2, rKid.level, "the increase callback deepens the level")
equal(1, refreshCalls.cacheInitialize, "the callbacks refresh the caches")

-- a header with no backing rule gets no submenu
capturedSubmenus = {}
AutoCategory.AddCategoryLevelMenuEntries("Others", 12)
equal(0, #capturedSubmenus, "no submenu for a category without a rule")

-- a predefined rule is not operable
newRule("Pred", 1)
ruleList[ruleNames["Pred"]].pred = 1
setBag(13, { { name = "Pred", runpriority = 1, showpriority = 1 } })
capturedSubmenus = {}
AutoCategory.AddCategoryLevelMenuEntries("Pred", 13)
equal(0, #capturedSubmenus, "no submenu for a predefined rule")

-- a category that is not a category of the clicked bag gets no submenu
capturedSubmenus = {}
AutoCategory.AddCategoryLevelMenuEntries("Root", 13)
equal(0, #capturedSubmenus, "no submenu outside the bag of the header")

-- at level 5 the increase and new level entries are left out
newRule("Deep", 5)
setBag(14, { { name = "Deep", runpriority = 1, showpriority = 1 } })
capturedSubmenus = {}
AutoCategory.AddCategoryLevelMenuEntries("Deep", 14)
menu = capturedSubmenus[1].entries
equal(5, #menu, "no increase and no new level at level 5")
equal("Decrease Level", menu[1].label)
equal("Delete Level", menu[2].label)
equal("Copy to: Backpack", menu[3].label)

-- the copy callback copies and reports to the chat
setBag(15, { { name = "CopyMe", runpriority = 7, showpriority = 7 } })
newRule("CopyMe", 1)
capturedSubmenus = {}
AutoCategory.AddCategoryLevelMenuEntries("CopyMe", 15)
menu = capturedSubmenus[1].entries
local copyEntry = nil
for i = 1, #menu do
    if menu[i].label == "Copy to: Backpack" then
        copyEntry = menu[i]
    end
end
equal(true, copyEntry ~= nil, "the copy entries list the other bags")
chatMessages = {}
copyEntry.callback()
equal("CopyMe", bagNames(1)[#bagNames(1)],
    "the copy target bag received the category")
equal("AutoCategory: 1 categories copied to Backpack (0 already there).",
    chatMessages[1], "the copy reports to the chat")

print("CategoryLevelMenu_test: " .. assertions .. " assertions passed")
