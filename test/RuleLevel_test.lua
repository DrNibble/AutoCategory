-- Run from the addon root with Lua 5.1:
-- lua5.1 test/RuleLevel_test.lua
-- Tests the rule Level and Parent properties (the Edit Category "Level"
-- and "Parent" dropdowns that replace the former leveldisplay() rule
-- function) and their MatchCategoryRules integration, loading the
-- delivered files (never copies of them).

local assertions = 0
local function equal(expected, actual, message)
    assertions = assertions + 1
    assert(expected == actual, (message or "") .. ": expected "
        .. tostring(expected) .. ", got " .. tostring(actual))
end

-- ---------------------------------------------------------------------------
-- Part 1: the level/parent properties of a rule (validation, copies and
-- tooltips), from the delivered classes/RuleApi.lua
-- ---------------------------------------------------------------------------
AutoCategory = {
    RulesW = { ruleNames = {} },
    RuleFunc = {},
    Environment = {},
    checking = {},
}

-- string stubs for the tooltip (the real strings live in lang/)
SI_AC_TIP_LEVEL = "Level: %d"
SI_AC_TIP_PARENT = "Parent: %s"
function GetString(si)
    if si == SI_AC_TIP_LEVEL then return "Level: %d" end
    if si == SI_AC_TIP_PARENT then return "Parent: %s" end
    return tostring(si)
end

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

-- Parent validation: optional category name, other than its own name.
equal(true, isValidRule({ name = "n", rule = "true", level = 2,
    parent = "pn" }), "parent is valid")
equal(false, isValidRule({ name = "n", rule = "true", level = 2,
    parent = "n" }), "self parent is invalid")
equal(false, isValidRule({ name = "n", rule = "true", level = 2,
    parent = "" }), "empty parent is invalid")
equal(false, isValidRule({ name = "n", rule = "true", level = 2,
    parent = 3 }), "numeric parent is invalid")

-- CreateRule sets no level/parent; CopyFrom copies both.
local created = AutoCategory.CreateRule("created", "tag")
equal(nil, created.level, "created rule has no level")
equal(nil, created.parent, "created rule has no parent")
local src = AutoCategory.CreateRule("source", "tag")
src.level = 3
src.parent = "pn"
local copy = AutoCategory.CopyFrom(src)
equal(3, copy.level, "CopyFrom copies the level")
equal("pn", copy.parent, "CopyFrom copies the parent")

-- getDesc shows the level (and the parent) so it appears in tooltips.
local tt = src:getDesc()
equal(true, tt:find("Level: 3", 1, true) ~= nil, "tooltip shows the level")
equal(true, tt:find("Parent: pn", 1, true) ~= nil, "tooltip shows the parent")
local flat = AutoCategory.CreateRule("flat", "tag")
equal("flat", flat:getDesc(), "no level info without a level")

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

local function newRule(name, definition, level, parent)
    local rule = { name = name, rule = definition }
    if level then
        rule.level = level
    end
    if parent then
        rule.parent = parent
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

local function rule(name, definition, level, parent)
    return compileRule(newRule(name, definition, level, parent))
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
-- Three levels through the parent chain: a display section (rule true)
-- plus conditions in the deeper level rules
-- ---------------------------------------------------------------------------
-- The former leveldisplay(1, "premier niveau") is a rule named
-- "premier niveau" with Level 1 and rule text true; the deeper rules
-- choose their parent with the Parent dropdown.
rule("premier niveau", [[true]], 1)
rule("Armures", [[type("armor")]], 2, "premier niveau")
rule("Légères", [[type("armorlight")]], 3, "Armures")
rule("Moyennes", [[type("armormedium")]], 3, "Armures")

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
-- Sibling level-2 sections under the same parent
-- ---------------------------------------------------------------------------
rule("Armes", [[type("weapon")]], 2, "premier niveau")
bag.rules = {}
addBagRule("premier niveau", 10, 1)
addBagRule("Armures", 20, 2)
addBagRule("Armes", 25, 5)
itemType = "weapon"
ok, name, rp = match()
equal(true, ok, "sibling match")
equal("premier niveau----Armes", name, "sibling level 2 path")
equal(25, rp, "sibling run priority")

-- ---------------------------------------------------------------------------
-- Display sections (rule true) with the conditions in ordinary rules:
-- a Normal rule counts as level 1 and only refines the recorded path
-- when it extends it (same family, deeper): the level category keeps
-- the item, and a Normal or level 1 parent of ANOTHER family keeps its
-- own display for the items the level rules did not take
-- ---------------------------------------------------------------------------
rule("Trucs légers", [[type("armorlight")]]) -- ordinary (Normal) rule
bag.rules = {}
addBagRule("premier niveau", 10, 1)
addBagRule("Armures", 20, 2) -- display section (rule true)
addBagRule("Trucs légers", 30, 3)
itemType = "armorlight"
ok, name, rp = match()
equal(true, ok, "ordinary after open path")
equal("premier niveau----Armures", name,
    "ordinary rule does not append to the open path")
equal(20, rp, "level rule keeps its priority")

-- ---------------------------------------------------------------------------
-- A Normal parent and its level 2 child: the child takes its specific
-- items whatever the evaluation order, the parent keeps the rest flat
-- ---------------------------------------------------------------------------
rule("Protections", [[type("armor")]]) -- ordinary (Normal) parent
rule("Souples", [[type("armormedium")]], 2, "Protections")
bag.rules = {}
addBagRule("Souples", 20, 2) -- the level 2 rule comes first
addBagRule("Protections", 30, 1) -- the Normal parent follows it
itemType = "armormedium"
ok, name = match()
equal(true, ok, "child before parent match")
equal("Protections----Souples", name, "child takes its items")
itemType = "armorheavy" -- not medium: the child does not match
ok, name = match()
equal(true, ok, "parent keeps rest match")
equal("Protections", name, "parent keeps the other items flat")

-- ---------------------------------------------------------------------------
-- A Normal parent BEFORE its level 2 children (Normal counts as level 1):
-- the parent no longer swallows every item it matches - a child of the
-- family takes its specific items and nests them under the parent, the
-- parent keeps the rest flat
-- ---------------------------------------------------------------------------
bag.rules = {}
addBagRule("Protections", 30, 1) -- the Normal parent comes first
addBagRule("Souples", 20, 2) -- its level 2 child follows it
itemType = "armormedium" -- matches both the parent and the child
ok, name = match()
equal(true, ok, "parent before child match")
equal("Protections----Souples", name,
    "a Normal parent before its child lets the child take the item")
itemType = "armorheavy" -- not medium: the child does not match
ok, name = match()
equal(true, ok, "parent keeps rest before match")
equal("Protections", name, "the parent keeps its other items flat")

-- ---------------------------------------------------------------------------
-- A deeper rule of ANOTHER family does not steal the item from a Normal
-- rule that matched first: the first matching rule wins
-- ---------------------------------------------------------------------------
rule("Toutes armes", [[type("weapon")]]) -- ordinary (Normal) rule
rule("Étranger", [[type("weapon")]], 2, "premier niveau") -- another family
bag.rules = {}
addBagRule("Toutes armes", 30, 1)
addBagRule("Étranger", 20, 2)
itemType = "weapon"
ok, name = match()
equal(true, ok, "cross-family match")
equal("Toutes armes", name,
    "a deeper rule of another family does not steal the item")

-- ---------------------------------------------------------------------------
-- A Normal rule keeps the sort name and the dynamic (autoset) category
-- name its execution registered
-- ---------------------------------------------------------------------------
AutoCategory.Environment.setsort = function()
    AutoCategory.AdditionCategorySortName = "sortkey"
    return true
end
rule("Trié", [[setsort() and true]])
bag.rules = {}
addBagRule("Trié", 10, 1)
itemType = "weapon"
ok, name = match()
equal(true, ok, "sort name rule match")
equal("Trié", name, "a Normal rule stays flat")
equal("sortkey", AutoCategory.CategorySortNames["Trié"],
    "a flat Normal category keeps its plugin sort name")

AutoCategory.Environment.setcat = function(n)
    AutoCategory.AdditionCategoryName = n
    return true
end
rule("Dynamique", [[setcat("Sets----Truc")]])
bag.rules = {}
addBagRule("Dynamique", 10, 1)
itemType = "weapon"
ok, name = match()
equal(true, ok, "dynamic name rule match")
equal("Sets----Truc", name,
    "a dynamic nested name is kept for a Normal rule")

-- ---------------------------------------------------------------------------
-- A level category with the rule false: it holds no item itself, but its
-- children still nest under it - the level is display-only
-- ---------------------------------------------------------------------------
rule("Conteneur", [[false]], 1) -- display-only level: rule false
rule("Enfants", [[type("armorlight")]], 2, "Conteneur")
bag.rules = {}
addBagRule("Conteneur", 10, 1)
addBagRule("Enfants", 20, 2)
itemType = "armorlight" -- matches the child only
ok, name = match()
equal(true, ok, "false level with child match")
equal("Conteneur----Enfants", name,
    "a child nests under a level whose rule is false")
itemType = "weapon" -- matches nothing
ok, name = match()
equal(false, ok, "a false level holds no item")

-- ---------------------------------------------------------------------------
-- A level rule with no parent is a top-level section
-- ---------------------------------------------------------------------------
rule("Solo", [[type("armorlight")]], 3) -- no parent
bag.rules = {}
addBagRule("Solo", 30, 3)
itemType = "armorlight"
ok, name, rp = match()
equal(true, ok, "orphan level match")
equal("Solo", name, "orphan level rule is a top section")
equal(30, rp, "orphan level run priority")

-- ---------------------------------------------------------------------------
-- A dangling parent (deleted or renamed category) stops the chain:
-- the rule becomes a top-level section
-- ---------------------------------------------------------------------------
rule("Fantôme", [[true]], 2, "Catégorie disparue")
bag.rules = {}
addBagRule("Fantôme", 20, 2)
itemType = "armorlight"
ok, name = match()
equal(true, ok, "dangling parent match")
equal("Fantôme", name, "dangling parent stops the chain")

-- ---------------------------------------------------------------------------
-- A parent cycle (A parent of B, B parent of A) does not loop: the
-- chain stops at the first repeated name
-- ---------------------------------------------------------------------------
rule("Alpha", [[true]], 2, "Bêta")
rule("Bêta", [[true]], 2, "Alpha")
bag.rules = {}
addBagRule("Alpha", 20, 2)
ok, name = match()
equal(true, ok, "cycle match")
equal("Bêta----Alpha", name, "cycle stops the chain without looping")

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
-- The first rule naming a level wins it (equal-depth chains)
-- ---------------------------------------------------------------------------
rule("Blindées", [[type("armor")]], 2, "premier niveau")
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
-- A level rule that does not match records nothing
-- ---------------------------------------------------------------------------
bag.rules = {}
addBagRule("premier niveau", 10, 1)
addBagRule("Armures", 20, 2)
itemType = "weapon"
ok, name = match()
equal(true, ok, "non-matching level rule match")
equal("premier niveau", name, "non-matching level rule records nothing")

print("PASS: " .. assertions .. " assertions (RuleLevel)")
