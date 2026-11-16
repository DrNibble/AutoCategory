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
SI_AC_MENU_CM_LEVEL_MOVE_UP = "Move Up ^"
SI_AC_MENU_CM_LEVEL_DEEPER = "Increase Level -->"
SI_AC_MENU_CM_LEVEL_SHALLOWER = "Decrease Level <--"
SI_AC_MENU_CM_LEVEL_MOVE_DOWN = "Move Down v"
SI_AC_MENU_CM_REMOVE_DISPLAY = "Remove from display"
SI_AC_MENU_CM_NEW_CATEGORY = "New Category"
SI_AC_DIALOG_CATEGORY_NAME_EMPTY = "Empty name"
SI_AC_DIALOG_CATEGORY_NAME_EXISTS = "Duplicate name"
SI_AC_DIALOG_CATEGORY_CREATE_FAILED = "Invalid bag"
SI_AC_MENU_CM_COPY_SUBMENU = "Copy To"
SI_AC_MENU_CM_MOVE_SUBMENU = "Move To"
SI_AC_MENU_CM_MOVE_TOP = "Top Level"
SI_AC_MESSAGE_CM_COPY_DONE = "AutoCategory: %d categories copied to %s (%d already there)."
SI_AC_DEFAULT_NAME_NEW_CATEGORY = "NewCategory"
SI_AC_DEFAULT_NAME_EMPTY_TAG = "<Empty>"
SI_AC_NEW_CATEGORY_EMPTY_CHILD = "(empty)"
SI_AC_MENU_CM_RUN_PRIORITY = "Execution Priority: %d"

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
function AddCustomSubMenuItem(text, entries)
    capturedSubmenus[#capturedSubmenus + 1] = { text = text, entries = entries }
end
function AddCustomMenuItem(text, callback)
    capturedItems[#capturedItems + 1] = { label = text, callback = callback }
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

-- a header of a category of the bag gets the run priority, the Level
-- submenu and the Copy To submenu (Kid is Normal here: no Decrease
-- entry; three copy entries for the three bags of the stub other
-- than the clicked one)
capturedSubmenus = {}
capturedItems = {}
AutoCategory.AddCategoryLevelMenuEntries("Root----Kid", 12)
equal(3, #capturedItems, "priority, creation and removal entries for an operable header")
equal("Execution Priority: 5", capturedItems[1].label,
    "the header menu shows the category's execution priority")
equal("New Category", capturedItems[2].label, "creation comes after the operations")
equal("Remove from display", capturedItems[3].label, "the removal entry comes last")
equal(2, #capturedSubmenus, "a Level submenu and a Copy To submenu")
equal("Level", capturedSubmenus[1].text, "the level operations sit in their own submenu")
local levelMenu = capturedSubmenus[1].entries
equal(3, #levelMenu, "Kid is Normal: no Decrease entry")
equal("Move Up ^", levelMenu[1].label)
equal("Increase Level -->", levelMenu[2].label)
equal("Move Down v", levelMenu[3].label)
equal("Copy To", capturedSubmenus[2].text, "the second submenu is the Copy To menu")
menu = capturedSubmenus[2].entries
equal(3, #menu, "the copy entries list the other bags")
equal("Backpack", menu[1].label)
equal("Bank", menu[2].label)
equal("Guild Bank", menu[3].label)

-- the callbacks run the operations and refresh
refreshCalls.cacheInitialize = 0
levelMenu[2].callback()
equal(2, rKid.level, "the increase callback deepens the level")
equal(1, refreshCalls.cacheInitialize, "the callbacks refresh the caches")

-- the move callbacks step the display priority and refresh (Root is
-- no longer in the bag here, so Kid has no adjacent group)
refreshCalls.cacheInitialize = 0
levelMenu[1].callback()
equal(6, AutoCategory.saved.bags[12].rules[1].showpriority,
    "move up steps by one without an adjacent group")
equal(1, refreshCalls.cacheInitialize, "the move callback refreshes the caches")
levelMenu[3].callback()
equal(5, AutoCategory.saved.bags[12].rules[1].showpriority, "move down steps back")

-- the removal callback removes the category from the inventory
-- list of the clicked bag only: the global rule stays
refreshCalls.cacheInitialize = 0
capturedItems[3].callback()
equal(1, refreshCalls.cacheInitialize, "the removal callback refreshes the caches")
equal(0, #AutoCategory.saved.bags[12].rules, "the category leaves the bag list")
equal(true, rKid ~= nil, "the global rule is kept")

-- A header with no backing rule only gets category creation.
capturedSubmenus = {}
capturedItems = {}
AutoCategory.AddCategoryLevelMenuEntries("Others", 12)
equal(1, #capturedItems, "creation is offered on ungrouped headers")
equal(0, #capturedSubmenus, "no submenu for a category without a rule")

-- a predefined (protected) rule: its level and its priorities can be
-- changed, but it is never offered the removal
newRule("Pred", 1)
ruleList[ruleNames["Pred"]].pred = 1
setBag(13, { { name = "Pred", runpriority = 1, showpriority = 1 } })
capturedSubmenus = {}
capturedItems = {}
AutoCategory.AddCategoryLevelMenuEntries("Pred", 13)
equal(2, #capturedItems, "priority and creation for a predefined rule")
equal("Execution Priority: 1", capturedItems[1].label)
equal("New Category", capturedItems[2].label)
local hasRemove = false
for i = 1, #capturedItems do
    if capturedItems[i].label == "Remove from display" then
        hasRemove = true
    end
end
equal(false, hasRemove, "a predefined rule is never offered the removal")
equal(2, #capturedSubmenus, "a Level submenu and a Copy To submenu for a predefined rule")
equal("Level", capturedSubmenus[1].text)
equal(3, #capturedSubmenus[1].entries, "level 1: no Move Down at the priority floor")
equal("Move Up ^", capturedSubmenus[1].entries[1].label)
equal("Increase Level -->", capturedSubmenus[1].entries[2].label)
equal("Decrease Level <--", capturedSubmenus[1].entries[3].label,
    "an explicit level 1 can go back to Normal")
equal("Copy To", capturedSubmenus[2].text)
equal(3, #capturedSubmenus[2].entries, "the copy entries are offered for a predefined rule")

-- A category outside the clicked bag has no level operations.
capturedSubmenus = {}
capturedItems = {}
AutoCategory.AddCategoryLevelMenuEntries("Root", 13)
equal(1, #capturedItems, "creation only needs the captured bag")
equal(0, #capturedSubmenus, "no submenu outside the bag of the header")

-- At level 5 only increase is left out; creation is independent.
newRule("Deep", 5)
setBag(14, { { name = "Deep", runpriority = 1, showpriority = 1 } })
capturedSubmenus = {}
capturedItems = {}
AutoCategory.AddCategoryLevelMenuEntries("Deep", 14)
equal(3, #capturedItems, "priority, creation and removal at level 5")
equal("Execution Priority: 1", capturedItems[1].label)
equal("New Category", capturedItems[2].label)
equal("Remove from display", capturedItems[3].label)
equal(3, #capturedSubmenus, "Level, Move To and Copy To submenus at level 5")
equal("Level", capturedSubmenus[1].text)
equal(2, #capturedSubmenus[1].entries, "no Increase at level 5, no Move Down at the priority floor")
equal("Move Up ^", capturedSubmenus[1].entries[1].label)
equal("Decrease Level <--", capturedSubmenus[1].entries[2].label)
equal("Move To", capturedSubmenus[2].text)
equal(1, #capturedSubmenus[2].entries,
    "only the top level entry: no other category in the bag")
equal("Top Level", capturedSubmenus[2].entries[1].label)
menu = capturedSubmenus[3].entries
equal(3, #menu, "the copy entries are still offered at level 5")
equal("Backpack", menu[1].label)

-- the copy callback copies and reports to the chat
setBag(15, { { name = "CopyMe", runpriority = 7, showpriority = 7 } })
newRule("CopyMe", 1)
capturedSubmenus = {}
capturedItems = {}
AutoCategory.AddCategoryLevelMenuEntries("CopyMe", 15)
equal(2, #capturedSubmenus, "a Level submenu and a Copy To submenu")
equal("Level", capturedSubmenus[1].text)
equal("Copy To", capturedSubmenus[2].text)
menu = capturedSubmenus[2].entries
local copyEntry = nil
for i = 1, #menu do
    if menu[i].label == "Backpack" then
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
equal(true, CLM.MoveSubtreeToParent(20, "Mid", "TopB"),
    "the category moves under another category")
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
equal(false, CLM.MoveSubtreeToParent(20, "Mid", "Mid"),
    "cannot move under itself")
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
AutoCategory.AddCategoryLevelMenuEntries("Mid", 20)
equal(3, #capturedItems, "priority, creation and removal entries")
equal("Execution Priority: 30", capturedItems[1].label)
equal("New Category", capturedItems[2].label)
equal("Remove from display", capturedItems[3].label)
equal(3, #capturedSubmenus, "a Level, a Move To and a Copy To submenu")
equal("Level", capturedSubmenus[1].text)
equal(4, #capturedSubmenus[1].entries, "all four level operations for a mid-level category")
equal("Move Up ^", capturedSubmenus[1].entries[1].label)
equal("Increase Level -->", capturedSubmenus[1].entries[2].label)
equal("Decrease Level <--", capturedSubmenus[1].entries[3].label)
equal("Move Down v", capturedSubmenus[1].entries[4].label)
equal("Move To", capturedSubmenus[2].text)
equal("Copy To", capturedSubmenus[3].text)
local moveMenu = capturedSubmenus[2].entries
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

print("CategoryLevelMenu_test: " .. assertions .. " assertions passed")
