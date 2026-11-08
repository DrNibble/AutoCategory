-- Run from the addon root with Lua 5.1:
-- lua5.1 test/BagOrder_test.lua
-- Tests the display order of the bag rule lists (AutoCat.SortBagRulesByDisplay):
-- Normal and level 1 categories first, then the level 2-5 sections grouped
-- under their parent chain, loading the delivered files (never copies).
local assertions = 0
local function equal(expected, actual, message)
    assertions = assertions + 1
    assert(expected == actual, (message or "") .. ": expected "
        .. tostring(expected) .. ", got " .. tostring(actual))
end

AutoCategory = {}
local CT = assert(loadfile("CategoryTree.lua"))()
if CT then AutoCategory.CategoryTree = CT end
assert(AutoCategory.CategoryTree, "CategoryTree not registered")

-- minimal stubs used by AutoCategory.lua's sort helpers
GetString = function() return "" end
LibSFUtils = {}
local function dummyCVT() return setmetatable({}, { __index = function() return dummyCVT end }) end
AutoCategory.CVT = { New = function() return dummyCVT() end, USE_VALUES = 1, USE_TOOLTIPS = 2 }
CHAT_ROUTER = { AddSystemMessage = function() end }
AutoCategory.RulesW = {}

AutoCategory.saved = { bags = {}, general = {}, appearance = {}, collapses = {} }
AutoCategory.cache = { bags_cvt = {}, entriesByBag = {}, entriesByShowBag = {}, entriesByName = {} }
AutoCategory.BagRuleEntry = {}
AutoCategory.logDebug = function() end
AutoCategory.logWouldDebug = function() return false end
AutoCategory.CategorySortNames = {}
function AutoCategory.GetCategorySortName(name)
    local sn = AutoCategory.CategorySortNames[name]
    return sn and (sn .. "\001" .. name) or name
end

local rulesByName = {}
function AutoCategory.GetRuleByName(name)
    return rulesByName[name]
end

local src = io.open("AutoCategory.lua", "r"):read("*a")
-- load only up to the end of SortBagRulesByDisplay: cut after its end
local cut = src:find("AutoCat_Internal.BagRuleShowSortingFunction")
assert(cut, "cut point not found")
local chunk = src:sub(1, cut - 1)
-- drop the rest-of-file references: stop before InitScrollBag etc.
local f, err = loadstring(chunk, "AutoCategory-part")
assert(f, err)
f()

local AutoCat = AutoCategory

local function addRule(name, level, parent)
    rulesByName[name] = { name = name, level = level, parent = parent }
end

addRule("Armures", nil, nil)          -- Normal
addRule("Légères", 2, "Armures")      -- level 2 under Armures
addRule("Moyennes", 2, "Armures")     -- level 2 under Armures
addRule("Tissus", 1, nil)             -- level 1
addRule("Soie", 3, "Tissus")          -- level 3 under Tissus (level 1)
addRule("Armes", nil, nil)            -- Normal

local function bagrule(name, run, show)
    return { name = name, runpriority = run, showpriority = show, isHidden = false }
end

-- display order: showpriority desc; parent then its level sections
local rules = {
    bagrule("Légères", 30, 3),
    bagrule("Armures", 10, 1),
    bagrule("Armes", 50, 5),
    bagrule("Moyennes", 20, 2),
    bagrule("Soie", 40, 4),
    bagrule("Tissus", 60, 6),
}
AutoCat.SortBagRulesByDisplay(rules)
local order = {}
for i = 1, #rules do order[i] = rules[i].name end
local joined = table.concat(order, ",")
print("order: " .. joined)
-- Tissus (6) first, then Soie under it; Armes (5); Armures (1) then its
-- level sections Légères and Moyennes (alphabetical within the group,
-- like the bag display)
equal("Tissus,Soie,Armes,Armures,Légères,Moyennes", joined,
    "parent first then its level sections, priority desc")

-- a Normal parent following its level 2 child still displays (the user's
-- bug): the child is grouped under the parent, both are in the list
equal(6, #rules, "all entries kept")

-- tie on priority: alphabetical within the group
local tie = {
    bagrule("Zèbre", 10, 1),
    bagrule("Arme", 10, 1),
}
AutoCat.SortBagRulesByDisplay(tie)
equal("Arme,Zèbre", tie[1].name .. "," .. tie[2].name, "name asc on tie")

-- rules without any priority sort last
local nopri = {
    bagrule("Sans", nil, nil),
    bagrule("Avec", 10, 1),
}
AutoCat.SortBagRulesByDisplay(nopri)
equal("Avec,Sans", nopri[1].name .. "," .. nopri[2].name,
    "no priority sorts last")

-- a level 2 rule whose parent is not a bag rule of this bag: it keeps its
-- own priority and sorts as its own group
local orphan = {
    bagrule("Parent", 10, 1),
    bagrule("Enfant", 20, 2),
}
rulesByName["Enfant"] = { name = "Enfant", level = 2, parent = "ParentAbsent" }
AutoCat.SortBagRulesByDisplay(orphan)
equal("Enfant,Parent", orphan[1].name .. "," .. orphan[2].name,
    "orphan level 2 rule sorts by its own priority")

-- a level 1 rule is a top-level category: flat, like Normal
rulesByName["Parent"] = { name = "Parent", level = 1 }
local lvl1 = {
    bagrule("Enfant", 20, 2),
    bagrule("Parent", 10, 1),
}
rulesByName["Enfant"] = { name = "Enfant", level = 2, parent = "Parent" }
AutoCat.SortBagRulesByDisplay(lvl1)
equal("Parent,Enfant", lvl1[1].name .. "," .. lvl1[2].name,
    "level 1 parent displays before its level 2 child")

print("PASS: " .. assertions .. " assertions (BagOrder)")
