-- Run from the addon root with Lua 5.1:
-- lua5.1 test/RuleLevel_test.lua
-- Tests the rule Level property (the Edit Category "Level" dropdown that
-- replaces the former leveldisplay() rule function) and its
-- MatchCategoryRules integration, loading the delivered files (never
-- copies of them).

local assertions = 0
local function equal(expected, actual, message)
    assertions = assertions + 1
    assert(expected == actual, (message or "") .. ": expected "
        .. tostring(expected) .. ", got " .. tostring(actual))
end

-- ---------------------------------------------------------------------------
-- Part 1: the level property of a rule (validation and copies), from the
-- delivered classes/RuleApi.lua
-- ---------------------------------------------------------------------------
AutoCategory = {
    RulesW = { ruleNames = {} },
    RuleFunc = {},
    Environment = {},
    checking = {},
}

assert(loadfile("classes/RuleApi.lua"))()

local isValidRule = AutoCategory.isValidRule

-- No level at all is valid (the default, ordinary flat category).
equal(true, isValidRule({ name = "n", rule = "true" }), "no level is valid")
-- Valid levels.
equal(true, isValidRule({ name = "n", rule = "true", level = 1 }),
    "level 1 is valid")
equal(true, isValidRule({ name = "n", rule = "true", level = 5 }),
    "level 5 is valid")
-- Invalid levels.
equal(false, isValidRule({ name = "n", rule = "true", level = 0 }),
    "level 0 is invalid")
equal(false, isValidRule({ name = "n", rule = "true", level = 2.5 }),
    "fractional level is invalid")
equal(false, isValidRule({ name = "n", rule = "true", level = "1" }),
    "string level is invalid")
equal(false, isValidRule({ name = "n", rule = "true", level = -1 }),
    "negative level is invalid")

-- CreateRule does not set a level; CopyFrom copies it.
local created = AutoCategory.CreateRule("created", "tag")
equal(nil, created.level, "created rule has no level")
local src = AutoCategory.CreateRule("source", "tag")
src.level = 3
local copy = AutoCategory.CopyFrom(src)
equal(3, copy.level, "CopyFrom copies the level")
local flat = AutoCategory.CopyFrom(AutoCategory.CreateRule("flat", "tag"))
equal(nil, flat.level, "CopyFrom of a level-less rule stays level-less")

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

local function newRule(name, definition, level)
    local rule = { name = name, rule = definition }
    if level then
        rule.level = level
    end
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

local function rule(name, definition, level)
    return compileRule(newRule(name, definition, level))
end

-- The rule environment: a controllable type() with the ESO armor
-- hierarchy (armor covers light, medium and heavy).
local itemType = nil
local typeMatches = {
    armor = { armor = true, armorlight = true, armormedium = true,
        armorheavy = true },
    armorlight = { armorlight = true },
    armormedium = { armormedium = true },
    armorheavy = { armorheavy = true },
    weapon = { weapon = true },
}
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
-- Three levels: a top-level section plus conditions named by their rules
-- ---------------------------------------------------------------------------
-- The former leveldisplay(1, "premier niveau") becomes a rule named
-- "premier niveau" with level 1; leveldisplay(2, type("armor")) becomes
-- a rule with level 2 and its condition as rule text, and so on.
rule("premier niveau", [[true]], 1)
rule("Armures", [[type("armor")]], 2)
rule("Légères", [[type("armorlight")]], 3)
rule("Moyennes", [[type("armormedium")]], 3)

bag.rules = {}
addBagRule("premier niveau", 10, 1)
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
addBagRule("premier niveau", 10, 1)
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
addBagRule("premier niveau", 10, 1)
addBagRule("Armures", 20, 2)
addBagRule("Légères", 30, 3)
itemType = "weapon"
ok, name, rp = match()
equal(true, ok, "parent-only match")
equal("premier niveau", name, "parent-only path")
equal(10, rp, "parent-only run priority")

-- ---------------------------------------------------------------------------
-- A level rule with no higher level open is a flat category
-- ---------------------------------------------------------------------------
bag.rules = {}
addBagRule("Légères", 30, 3)
itemType = "armorlight"
ok, name, rp = match()
equal(true, ok, "orphan level match")
equal("Légères", name, "orphan level rule is flat")
equal(30, rp, "orphan level run priority")

-- ---------------------------------------------------------------------------
-- An ordinary rule before the level rules stays flat
-- ---------------------------------------------------------------------------
rule("Trucs", [[true]])
bag.rules = {}
addBagRule("Trucs", 5, 0)
addBagRule("premier niveau", 10, 1)
itemType = "armorlight"
ok, name, rp = match()
equal(true, ok, "ordinary first match")
equal("Trucs", name, "ordinary rule before stays flat")
equal(5, rp, "ordinary rule priority")

-- ---------------------------------------------------------------------------
-- An ordinary rule after an open level path joins it as the deepest level
-- ---------------------------------------------------------------------------
bag.rules = {}
addBagRule("premier niveau", 10, 1)
addBagRule("Trucs", 5, 0)
ok, name, rp = match()
equal(true, ok, "ordinary after match")
equal("premier niveau----Trucs", name, "ordinary rule appended as deepest level")
equal(5, rp, "ordinary rule priority after path")

-- ---------------------------------------------------------------------------
-- The first rule naming a level wins it
-- ---------------------------------------------------------------------------
rule("Blindées", [[type("armor")]], 2)
bag.rules = {}
addBagRule("premier niveau", 10, 1)
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
addBagRule("premier niveau", 10, 1)
addBagRule("Armures", 20, 2)
addBagRule("Blindées", 25, 5)
ok, name = match()
equal("premier niveau----Armures", name, "second level 2 rule ignored")

-- ---------------------------------------------------------------------------
-- A level rule that does not match records nothing (its flat name is
-- still registered for the collapse state, like any ordinary rule)
-- ---------------------------------------------------------------------------
bag.rules = {}
addBagRule("premier niveau", 10, 1)
addBagRule("Armures", 20, 2)
itemType = "weapon"
ok, name = match()
equal(true, ok, "non-matching level rule match")
equal("premier niveau", name, "non-matching level rule records nothing")

print("PASS: " .. assertions .. " assertions (RuleLevel)")
