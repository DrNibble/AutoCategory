-- Run from the addon root with Lua 5.1:
-- lua5.1 test/FormatShow_test.lua
-- Tests formatShow() of the delivered classes/BagRuleApi.lua: the level of
-- the category (when set) shows in the bag rule dropdowns after the
-- display priorities, in every branch (keyboard color, hidden, gamepad,
-- missing rule) and only for valid whole levels 1-5.

local assertions = 0
local function equal(expected, actual, message)
    assertions = assertions + 1
    assert(expected == actual, (message or "") .. ": expected "
        .. tostring(expected) .. ", got " .. tostring(actual))
end
local function contains(haystack, needle, message)
    assertions = assertions + 1
    assert(type(haystack) == "string" and string.find(haystack, needle, 1, true),
        (message or "") .. ": " .. tostring(haystack) .. " does not contain "
        .. tostring(needle))
end
local function lacks(haystack, needle, message)
    assertions = assertions + 1
    assert(type(haystack) ~= "string" or not string.find(haystack, needle, 1, true),
        (message or "") .. ": " .. tostring(haystack) .. " should not contain "
        .. tostring(needle))
end

-- ---------------------------------------------------------------------------
-- stubs
-- ---------------------------------------------------------------------------
SI_AC_TIP_LEVEL = "Level: %d"
function GetString(si)
    return si
end

LibSFUtils = {
    colorRGBToHex = function(r, g, b)
        return string.format("%02X%02X%02X", r * 255, g * 255, b * 255)
    end,
}

local rules = {}
AutoCategory = {
    saved = {
        general = { ENABLE_GAMEPAD = false },
        appearance = {
            CATEGORY_FONT_COLOR = { 1, 1, 1 },
            HIDDEN_CATEGORY_FONT_COLOR = { 0.4, 0.4, 0.4 },
        },
    },
    GetRuleByName = function(name)
        return rules[name]
    end,
}

assert(loadfile("classes/BagRuleApi.lua"))()

local function addRule(name, level)
    rules[name] = { name = name, level = level }
end

-- ---------------------------------------------------------------------------
-- Part 1: level shows after the priorities (keyboard, colored)
-- ---------------------------------------------------------------------------
addRule("Plain", nil)
addRule("Armures", 1)
addRule("Legeres", 2)
addRule("Profond", 5)

local br = AutoCategory.CreateBagRule(rules["Plain"], 10, 20)
contains(br:formatShow(), "Plain (10/20)", "no level: name and priorities")
lacks(br:formatShow(), "Level:", "no level: no level text")

br = AutoCategory.CreateBagRule(rules["Armures"], 10, 20)
contains(br:formatShow(), "Armures (10/20) Level: 1", "level 1 after priorities")

br = AutoCategory.CreateBagRule(rules["Legeres"], 10, 20)
contains(br:formatShow(), "Legeres (10/20) Level: 2", "level 2 after priorities")
contains(br:formatShow(), "|cFFFFFF", "keyboard: category color kept")

br = AutoCategory.CreateBagRule(rules["Profond"], 10, 20)
contains(br:formatShow(), "Profond (10/20) Level: 5", "level 5 after priorities")

-- runpriority defaults (showpriority falls back to runpriority)
br = AutoCategory.CreateBagRule(rules["Legeres"], 30)
contains(br:formatShow(), "Legeres (30/30) Level: 2", "priority fallback with level")

-- ---------------------------------------------------------------------------
-- Part 2: hidden bag rule still shows the level
-- ---------------------------------------------------------------------------
br = AutoCategory.CreateBagRule(rules["Legeres"], 10, 20)
br:setHidden(true)
contains(br:formatShow(), "Legeres (10/20) Level: 2", "hidden: level still shown")

-- ---------------------------------------------------------------------------
-- Part 3: gamepad mode (plain text, no color codes)
-- ---------------------------------------------------------------------------
AutoCategory.saved.general.ENABLE_GAMEPAD = true
br = AutoCategory.CreateBagRule(rules["Legeres"], 10, 20)
equal("Legeres (10/20) Level: 2", br:formatShow(), "gamepad: plain text with level")
AutoCategory.saved.general.ENABLE_GAMEPAD = false

-- ---------------------------------------------------------------------------
-- Part 4: invalid levels show no level text
-- ---------------------------------------------------------------------------
addRule("Zero", 0)
addRule("Six", 6)
addRule("Frac", 2.5)
for _, name in ipairs({ "Zero", "Six", "Frac" }) do
    br = AutoCategory.CreateBagRule(rules[name], 10, 20)
    lacks(br:formatShow(), "Level:", "invalid level " .. name .. ": no level text")
    contains(br:formatShow(), name .. " (10/20)", "invalid level " .. name .. ": priorities kept")
end

-- ---------------------------------------------------------------------------
-- Part 5: missing backing rule keeps the (!) marker, no level
-- ---------------------------------------------------------------------------
-- CreateBagRule refuses a missing rule: a dangling bagrule (saved variables
-- whose rule was deleted) is built directly with the mixin metatable
br = { name = "Disparue", runpriority = 10, showpriority = 20 }
setmetatable(br, AutoCategory.BagRuleMetatable)
contains(br:formatShow(), "|cFF4444(!)|r Disparue (10/20)", "missing rule marker")
lacks(br:formatShow(), "Level:", "missing rule: no level text")

print("PASS: " .. assertions .. " assertions (formatShow level display)")
