-- Run from the addon root with Lua 5.1:
-- lua5.1 test/LevelDisplay_test.lua
-- Tests the leveldisplay() rule function and its MatchCategoryRules
-- integration, loading the delivered files (never copies of them).

local assertions = 0
local function equal(expected, actual, message)
    assertions = assertions + 1
    assert(expected == actual, (message or "") .. ": expected "
        .. tostring(expected) .. ", got " .. tostring(actual))
end
local function errorMessage(fn, ...)
    local ok, err = pcall(fn, ...)
    if ok then
        error("expected an error, got none")
    end
    return tostring(err)
end

-- ---------------------------------------------------------------------------
-- Part 1: the LevelDisplay rule function itself, extracted from the
-- delivered AutoCategory_RuleFunc.lua
-- ---------------------------------------------------------------------------
local rfFile = assert(io.open("AutoCategory_RuleFunc.lua", "r"))
local rfSource = rfFile:read("*a")
rfFile:close()
rfSource = rfSource:gsub("\r\n", "\n")
local ldSource = assert(rfSource:match(
    "(function AutoCategory%.RuleFunc%.LevelDisplay%b().-\nend)"),
    "LevelDisplay function not found")

AutoCategory = {
    RuleFunc = {},
    Environment = {},
    checking = {},
}

assert(loadstring(ldSource))()
local LevelDisplay = AutoCategory.RuleFunc.LevelDisplay
equal("function", type(LevelDisplay), "LevelDisplay extracted")

-- A string section records the level name.
equal(true, LevelDisplay(1, "premier niveau"), "string section matches")
equal("premier niveau", AutoCategory.AdditionLevelNames[1], "level 1 name")
equal(true, LevelDisplay(2, "Armures"), "second string section")
equal("Armures", AutoCategory.AdditionLevelNames[2], "level 2 name")

-- A falsy section does not match and records nothing.
equal(false, LevelDisplay(3, false), "false section does not match")
equal(nil, AutoCategory.AdditionLevelNames[3], "no level 3 recorded")

-- A truthy condition takes the rule's own name as section name.
AutoCategory.checking.RuleName = "Armures"
equal(true, LevelDisplay(2, true), "condition section matches")
equal("Armures", AutoCategory.AdditionLevelNames[2], "rule name as section")

-- Without a rule name, a condition section is an error.
AutoCategory.checking.RuleName = nil
local err = errorMessage(LevelDisplay, 2, true)
equal(true, err:find("leveldisplay()", 1, true) ~= nil, "missing rule name error")

-- Validation errors.
err = errorMessage(LevelDisplay)
equal(true, err:find("expected a section name", 1, true) ~= nil,
    "no section error")
err = errorMessage(LevelDisplay, 0, "zéro")
equal(true, err:find("whole level number", 1, true) ~= nil, "depth 0 error")
err = errorMessage(LevelDisplay, 2.5, "milieu")
equal(true, err:find("whole level number", 1, true) ~= nil, "fractional depth error")
err = errorMessage(LevelDisplay, "1", "texte")
equal(true, err:find("whole level number", 1, true) ~= nil, "string depth error")
err = errorMessage(LevelDisplay, 1, "")
equal(true, err:find("empty section name", 1, true) ~= nil, "empty name error")
err = errorMessage(LevelDisplay, 1, "   ")
equal(true, err:find("empty section name", 1, true) ~= nil,
    "whitespace name error")

-- ---------------------------------------------------------------------------
-- Part 2: MatchCategoryRules integration with the delivered API file
-- ---------------------------------------------------------------------------
BAG_BACKPACK = 1
AC_BAG_TYPE_BACKPACK = 1
LibSFUtils = {
    safeCall = function(fn)
        local ok, res = pcall(fn)
        return ok, res
    end,
}

AutoCategory.checking = {}
function AutoCategory:setChecking(bagId, slotIndex)
    self.checking.BagId = bagId
    self.checking.SlotIndex = slotIndex
end

-- Collapse state stub, keyed like the saved settings.
local collapsed = {}
local collapseCalls = {}
function AutoCategory.SetCategoryCollapsed(bagTypeId, name, state)
    collapseCalls[#collapseCalls + 1] = tostring(bagTypeId) .. "\001" .. tostring(name)
    collapsed[bagTypeId .. "\001" .. name] = state or nil
end
function AutoCategory.IsCategoryCollapsed(bagTypeId, name)
    return collapsed[bagTypeId .. "\001" .. name] or false
end

AutoCategory.saved = { bags = {}, general = {} }
AutoCategory.compiledRules = {}
AutoCategory.CategorySortNames = {}

-- The real CategoryTree, loaded from the delivered file.
assert(loadfile("CategoryTree.lua"))()

-- Rule compilation, the way classes/RuleApi.lua does it.
local rulesByName = {}
function AutoCategory.GetRuleByName(name)
    return rulesByName[name]
end

local function newRule(name, definition)
    local rule = { name = name, rule = definition }
    function rule:key()
        return "R:" .. self.name
    end
    function rule:setError()
        self.damaged = true
    end
    rulesByName[name] = rule
    return rule
end

local function compileRule(rule)
    local fn = assert(loadstring("return(" .. rule.rule .. ")"))
    setfenv(fn, AutoCategory.Environment)
    AutoCategory.compiledRules[rule:key()] = fn
    return rule
end

local function rule(name, definition)
    return compileRule(newRule(name, definition))
end

-- The rule environment: the real leveldisplay plus a controllable type()
-- with the ESO armor hierarchy (armor covers light, medium and heavy).
local itemType = nil
local typeMatches = {
    armor = { armor = true, armorlight = true, armormedium = true,
        armorheavy = true },
    armorlight = { armorlight = true },
    armormedium = { armormedium = true },
    armorheavy = { armorheavy = true },
    weapon = { weapon = true },
}
AutoCategory.Environment.leveldisplay = LevelDisplay
AutoCategory.Environment.type = function(kind)
    return (typeMatches[kind] or {})[itemType] or false
end

-- Load the delivered API file with the stubs in place.
assert(loadfile("AutoCategory_API.lua"))()

local bag = { rules = {} }
AutoCategory.saved.bags[AC_BAG_TYPE_BACKPACK] = bag

local function addBagRule(name, runpriority, showpriority)
    bag.rules[#bag.rules + 1] = {
        name = name,
        runpriority = runpriority or 0,
        showpriority = showpriority or 0,
        isHidden = false,
    }
end

local function match()
    return AutoCategory:MatchCategoryRules(BAG_BACKPACK, 4)
end

-- ---------------------------------------------------------------------------
-- Three levels: explicit name, then conditions named by their rules
-- ---------------------------------------------------------------------------
rule("Niveau 1", [[leveldisplay(1, "premier niveau")]])
rule("Armures", [[leveldisplay(2, type("armor"))]])
rule("Légères", [[leveldisplay(3, type("armorlight"))]])
rule("Moyennes", [[leveldisplay(3, type("armormedium"))]])

bag.rules = {}
addBagRule("Niveau 1", 10, 1)
addBagRule("Armures", 20, 2)
addBagRule("Légères", 30, 3)
addBagRule("Moyennes", 40, 4)

itemType = "armorlight"
local ok, name, rp, sp, bti = match()
equal(true, ok, "light armor matched")
equal("premier niveau----Armures----Légères", name, "three-level path")
equal(30, rp, "deepest rule run priority")
equal(3, sp, "deepest rule show priority")
equal(AC_BAG_TYPE_BACKPACK, bti, "bag type id")
local registered = false
for _, call in ipairs(collapseCalls) do
    if call == AC_BAG_TYPE_BACKPACK .. "\001" .. name then
        registered = true
    end
end
equal(true, registered, "collapse state registered for final name")

itemType = "armormedium"
ok, name = match()
equal(true, ok, "medium armor matched")
equal("premier niveau----Armures----Moyennes", name, "medium armor path")

-- ---------------------------------------------------------------------------
-- A level without a matching rule is skipped (gap compaction)
-- ---------------------------------------------------------------------------
bag.rules = {}
addBagRule("Niveau 1", 10, 1)
addBagRule("Légères", 30, 3)
itemType = "armorlight"
ok, name, rp = match()
equal(true, ok, "gap match")
equal("premier niveau----Légères", name, "level 2 gap compacted")
equal(30, rp, "gap run priority")

-- ---------------------------------------------------------------------------
-- Only the top level matches: the parent path alone
-- ---------------------------------------------------------------------------
bag.rules = {}
addBagRule("Niveau 1", 10, 1)
addBagRule("Armures", 20, 2)
addBagRule("Légères", 30, 3)
itemType = "weapon"
ok, name, rp = match()
equal(true, ok, "parent-only match")
equal("premier niveau", name, "parent-only path")
equal(10, rp, "parent-only run priority")

-- ---------------------------------------------------------------------------
-- An ordinary rule before the leveldisplay rules stays flat
-- ---------------------------------------------------------------------------
rule("Trucs", [[true]])
bag.rules = {}
addBagRule("Trucs", 5, 0)
addBagRule("Niveau 1", 10, 1)
itemType = "armorlight"
ok, name, rp = match()
equal(true, ok, "ordinary first match")
equal("Trucs", name, "ordinary rule before stays flat")
equal(5, rp, "ordinary rule priority")

-- ---------------------------------------------------------------------------
-- An ordinary rule after an open leveldisplay path joins it as the
-- deepest level
-- ---------------------------------------------------------------------------
bag.rules = {}
addBagRule("Niveau 1", 10, 1)
addBagRule("Trucs", 5, 0)
ok, name, rp = match()
equal(true, ok, "ordinary after match")
equal("premier niveau----Trucs", name, "ordinary rule appended as deepest level")
equal(5, rp, "ordinary rule priority after path")

-- ---------------------------------------------------------------------------
-- The first rule naming a level wins it
-- ---------------------------------------------------------------------------
rule("Blindées", [[leveldisplay(2, type("armor"))]])
bag.rules = {}
addBagRule("Niveau 1", 10, 1)
addBagRule("Armures", 20, 2)
addBagRule("Blindées", 25, 5)
addBagRule("Légères", 30, 3)
itemType = "armorlight"
ok, name = match()
equal(true, ok, "first-wins match")
equal("premier niveau----Armures----Légères", name,
    "first rule naming a level wins it")

-- A later rule cannot steal an already named level either.
bag.rules = {}
addBagRule("Niveau 1", 10, 1)
addBagRule("Armures", 20, 2)
addBagRule("Blindées", 25, 5)
ok, name = match()
equal("premier niveau----Armures", name, "second level 2 rule ignored")

print("PASS: " .. assertions .. " assertions (LevelDisplay)")
