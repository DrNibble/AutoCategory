-- Run from the addon root with Lua 5.1:
-- lua5.1 test/RuleItemId_test.lua
-- Tests addItemIdToIsItemId (the inventory context menu "AutoCategory"
-- submenu): adding the itemId of an item to the isitemid() command of a
-- category rule - " or isitemid(<id>)" appended when the rule has no
-- isitemid() call, or <id> added to the parameters when the command
-- already exists. Loading the delivered files (never copies of them).

local assertions = 0
local function equal(expected, actual, message)
    assertions = assertions + 1
    assert(expected == actual, (message or "") .. ": expected "
        .. tostring(expected) .. ", got " .. tostring(actual))
end

-- ---------------------------------------------------------------------------
-- Part 1: addItemIdToIsItemId on the rule mixin, from the delivered
-- classes/RuleApi.lua
-- ---------------------------------------------------------------------------
AutoCategory = {
    RulesW = { ruleNames = {} },
    RuleFunc = {},
    Environment = {},
    checking = {},
    compiledRules = {},
}

-- Lua 5.1 stand-ins for the ESO globals used by compile()
zo_loadstring = loadstring
function GetString(si) return tostring(si) end

assert(loadfile("classes/RuleApi.lua"))()

-- makes a rule with the given rule text (mixin attached)
local function rule(text)
    local r = AutoCategory.CreateRule("Test", "tag")
    r.rule = text
    return r
end

-- the rule text after adding the id (helper for the assertions)
local function added(text, id)
    local r = rule(text)
    r:addItemIdToIsItemId(id)
    return r.rule
end

-- no isitemid() yet: the command is appended with " or "
equal("true or isitemid(5)", added("true", 5), "command appended to true")
equal("name() or isitemid(73753)",
    added("name()", 73753), "command appended after a function call")
-- an empty rule text becomes the command alone (no leading " or ")
equal("isitemid(5)", added("", 5), "empty rule text becomes the command")
equal("isitemid(5)", added(nil, 5), "nil rule text becomes the command")

-- the command already exists: the id joins its parameters
equal("isitemid(1, 2, 5)", added("isitemid(1, 2)", 5), "id added to params")
equal("islockpick() or isitemid(73753, 73754, 71779)",
    added("islockpick() or isitemid(73753, 73754)", 71779),
    "id added to the params of the existing call")
-- spaces in the parameters are kept, the id still lands in the list
equal("isitemid( 1, 2 , 5)", added("isitemid( 1, 2 )", 5), "spaces kept")
-- an isitemid() without parameters takes the id alone (no leading comma)
equal("isitemid(5)", added("isitemid()", 5), "empty params take the id")

-- the id is already a parameter: the rule text is not touched
do
    local r = rule("isitemid(1, 2)")
    equal(false, r:addItemIdToIsItemId(2), "already a param: no change flag")
    equal("isitemid(1, 2)", r.rule, "already a param: text untouched")
end
do
    local r = rule("islockpick() or isitemid(73753)")
    equal(false, r:addItemIdToIsItemId(73753), "id of the only call: no change")
end
-- a number that only contains the id does not count as the id
do
    local r = rule("isitemid(73753)")
    equal(true, r:addItemIdToIsItemId(3753), "substring is not the id")
    equal("isitemid(73753, 3753)", r.rule, "substring id appended")
end

-- several isitemid() calls: the id goes to the parameters of the LAST one
equal("isitemid(1) or isitemid(2, 3)",
    added("isitemid(1) or isitemid(2)", 3), "id added to the last call")
-- and the duplicate check looks at every call
do
    local r = rule("isitemid(1) or isitemid(2)")
    equal(false, r:addItemIdToIsItemId(1), "id of the first call: no change")
end

-- a longer name that only ends with isitemid is NOT the command
equal("myisitemid(1) or isitemid(2)",
    added("myisitemid(1)", 2), "isitemid inside a longer name ignored")
do
    -- and its parameters are not scanned for the duplicate check either
    local r = rule("myisitemid(3)")
    equal(true, r:addItemIdToIsItemId(3), "param of the lookalike not seen")
end

-- spaces before the parenthesis are allowed (the call is rewritten
-- without them)
equal("isitemid(1, 5)", added("isitemid (1)", 5), "space before paren")

-- ---------------------------------------------------------------------------
-- Part 2: the modified rule text compiles
-- ---------------------------------------------------------------------------
do
    local r = rule("islockpick() or isitemid(73753)")
    equal(true, r:addItemIdToIsItemId(73754), "id added")
    local err = r:compile()
    equal("", err, "modified rule compiles")
end
do
    local r = rule("true")
    equal(true, r:addItemIdToIsItemId(5), "command appended")
    equal("", r:compile(), "appended command compiles")
end

print("PASS: " .. assertions .. " assertions (RuleItemId)")
