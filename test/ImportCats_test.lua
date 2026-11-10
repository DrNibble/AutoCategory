-- Run from the addon root with Lua 5.1:
-- lua5.1 test/ImportCats_test.lua
-- Tests the "Import Categories" multi-select dropdown and the "Import
-- Selected Categories" button of the Import/Export bag settings section
-- (settings/BagSet.lua, ImpExp_ImportCats_LAM / ImpExp_ImportSel_LAM),
-- loading the delivered files (never copies of them).
--
-- The LAM control definitions are driven through their real getFunc /
-- setFunc / func / disabled closures (what LibAddonMenu-2.0 itself
-- calls), and the choices the dropdown control receives are read from a
-- fake LAM control through the same UpdateChoices / UpdateValue calls
-- the delivered updateControl makes.

local assertions = 0
local function equal(expected, actual, message)
    assertions = assertions + 1
    assert(expected == actual, (message or "") .. ": expected "
        .. tostring(expected) .. ", got " .. tostring(actual))
end

-- ---------------------------------------------------------------------------
-- stubs (the delivered classes/CVT.lua, classes/BaseUI.lua and
-- settings/BagSet.lua need these)
-- ---------------------------------------------------------------------------
function GetString(si)
    return tostring(si)
end

LibSFUtils = {
    safeClearTable = function(t)
        for k in pairs(t) do t[k] = nil end
        return t
    end,
    -- a real deep copy, like the LibSFUtils one used by the whole bag import
    deepCopy = function(src)
        if type(src) ~= "table" then return src end
        local copy = {}
        for k, v in pairs(src) do
            copy[k] = LibSFUtils.deepCopy(v)
        end
        return copy
    end,
}

ZO_Object = {}
function ZO_Object.New(cls)
    return setmetatable({}, cls)
end
function ZO_Object:Subclass()
    local cls = {}
    cls.__index = cls
    setmetatable(cls, { __index = self })
    return cls
end

function ZO_IsElementInNumericallyIndexedTable(list, item)
    for _, v in ipairs(list) do
        if v == item then return true end
    end
    return false
end

-- fake LAM controls (what WINDOW_MANAGER:GetControlByName returns):
-- the multi-select dropdown records the choices pushed by updateControl
-- and the value refreshes
local lastChoices, lastValues, lastTooltips
local numUpdateValueCalls = 0
local lastUpdateValueArg
local fakeDropdown = {
    UpdateChoices = function(self, choices, values, tooltips)
        lastChoices = choices
        lastValues = values
        lastTooltips = tooltips
    end,
    UpdateValue = function(self, forceDefault, value)
        numUpdateValueCalls = numUpdateValueCalls + 1
        lastUpdateValueArg = value
    end,
}
WINDOW_MANAGER = {
    GetControlByName = function(self, name)
        if name == "AC_DROPDOWN_IMPORTBAG_CATS" then return fakeDropdown end
        return nil
    end,
}

-- bag type ids (the values of AutoCategory_Global.lua)
AC_BAG_TYPE_BACKPACK = 1
AC_BAG_TYPE_BANK = 2
AC_BAG_TYPE_GUILDBANK = 3
AC_BAG_TYPE_CRAFTBAG = 4
AC_BAG_TYPE_CRAFTSTATION = 5
AC_BAG_TYPE_HOUSEBANK = 6
AC_BAG_TYPE_FURNVAULT = 7
AC_BAG_TYPE_VENGEANCE = 8

-- string ids of the Import/Export controls (they are globals in game)
SI_AC_MENU_UBS_BUTTON_EXPORT_TO_ALL_BAGS = "SI:EXPORT_ALL_BAGS"
SI_AC_MENU_IBS_DROPDOWN_IMPORT_FROM_BAG = "SI:IMPORT_FROM_BAG"
SI_AC_MENU_IBS_BUTTON_IMPORT = "SI:IMPORT"
SI_AC_MENU_IBS_BUTTON_IMPORT_CATEGORIES = "SI:IMPORT_CATEGORIES"

local cacheInitCalls = 0
local refreshDropdownCalls = 0
local refreshControlsCalls = 0

AutoCategory = {
    logDebug = function() end,
    logWouldDebug = function() return false end,
    cache = {
        bags_cvt = nil, -- a real CVT, created once the class is loaded
        entriesByBag = {},
        entriesByShowBag = {},
        entriesByName = {},
    },
    cacheInitialize = function() cacheInitCalls = cacheInitCalls + 1 end,
    GetRuleByName = function(name)
        return nil -- tooltips fall back to the plain category name
    end,
    RulesW = { tags = {} },
}
AC_UI = {
    RefreshDropdownData = function() refreshDropdownCalls = refreshDropdownCalls + 1 end,
    RefreshControls = function() refreshControlsCalls = refreshControlsCalls + 1 end,
    divider = function()
        return { type = "divider" }
    end,
    header = function(name)
        return { type = "header", name = name }
    end,
}

assert(loadfile("classes/CVT.lua"))()
assert(loadfile("classes/BaseUI.lua"))()

-- the bag list dropdown data is a real CVT (a plain table is silently
-- ignored by CVT:assign, the real bug documented by ParentDD_test.lua):
-- BagSet.lua fills its lists at load time with the bag type ids
AutoCategory.cache.bags_cvt = AutoCategory.CVT:New("BAGS", nil, 3)

assert(loadfile("settings/BagSet.lua"))()

-- ---------------------------------------------------------------------------
-- the bag settings under test: bag 1 is the current bag (the Select Bag
-- dropdown defaults to AC_BAG_TYPE_BACKPACK = 1), bag 2 is the source
-- ---------------------------------------------------------------------------
local function bagRule(name, runpriority, showpriority)
    return { name = name, runpriority = runpriority, showpriority = showpriority }
end

AutoCategory.saved = {
    bags = {
        [1] = { -- the current bag (backpack)
            rules = {
                bagRule("Gardée", 30, 3),
                bagRule("Remplacée", 20, 2),
            },
        },
        [2] = { -- the source bag (a bank)
            rules = {
                bagRule("Banque B", 50, 5),
                bagRule("Banque A", 40, 4),
                bagRule("Banque C", 10, 1),
            },
        },
    },
}

-- the real initialization: assigns the bag lists to the dropdowns and
-- selects the current bag (the first one: the backpack)
AC_UI.BagSet.Init()

-- ---------------------------------------------------------------------------
-- drive the real LAM control definitions of the Import/Export submenu
-- ---------------------------------------------------------------------------
local menu = AC_UI.BagSet.controlDef()
local impexp
for _, c in ipairs(menu.controls) do
    if c.type == "submenu" and c.reference == "SI_AC_MENU_SUBMENU_IMPORT_EXPORT" then
        impexp = c
    end
end
equal(true, impexp ~= nil, "the Import/Export submenu exists")

local importBagDD, importBtn, importCatsDD, importSelBtn
for _, c in ipairs(impexp.controls) do
    if c.type == "dropdown" and c.multiSelect == true then
        importCatsDD = c
    elseif c.type == "dropdown" and c.name == SI_AC_MENU_IBS_DROPDOWN_IMPORT_FROM_BAG then
        importBagDD = c
    elseif c.type == "button" and c.name == SI_AC_MENU_IBS_BUTTON_IMPORT then
        importBtn = c
    elseif c.type == "button" and c.name == SI_AC_MENU_IBS_BUTTON_IMPORT_CATEGORIES then
        importSelBtn = c
    end
end
equal(true, importBagDD ~= nil, "the Import From Bag dropdown exists")
equal(true, importBtn ~= nil, "the Import button exists")
equal(true, importCatsDD ~= nil, "the Import Categories dropdown exists")
equal(true, importSelBtn ~= nil, "the Import Selected Categories button exists")

-- the categories dropdown really is a multi-select one (LibAddonMenu-2.0
-- multiSelect, the feature of the former LibAddonMenu-MultiSelectDropdown
-- widget)
equal(true, importCatsDD.multiSelect, "the categories dropdown is multiSelect")

-- ---------------------------------------------------------------------------
-- Part 1: the choices depend on the source bag
-- ---------------------------------------------------------------------------
-- choosing the source bag refreshes the categories dropdown: the fake
-- control receives the categories of the source bag, sorted by name
importBagDD.setFunc(2)
equal(3, #lastChoices, "choices: the categories of the source bag")
equal("Banque A", lastChoices[1], "choices: sorted by name")
equal("Banque B", lastChoices[2], "choices: sorted by name (2)")
equal("Banque C", lastChoices[3], "choices: sorted by name (3)")
equal("Banque A", lastValues[1], "values: the category names")
equal("Banque A", lastTooltips[1], "tooltips: the category description")
-- the display refresh does not call setFunc (UpdateValue without a value)
equal(nil, lastUpdateValueArg, "refresh: UpdateValue without a value")

-- ---------------------------------------------------------------------------
-- Part 2: the selection is a table (LAM multiSelect) and drives the button
-- ---------------------------------------------------------------------------
-- nothing selected: the button is disabled
equal(true, importSelBtn.disabled(), "button disabled with no selection")

-- LAM passes the selected values as a table
importCatsDD.setFunc({ "Banque A", "Banque C" })
local selected = importCatsDD.getFunc()
equal(2, #selected, "getFunc returns the selected values")
local sel = {}
for _, v in ipairs(selected) do sel[v] = true end
equal(true, sel["Banque A"] and sel["Banque C"], "the selection is kept")
equal(false, importSelBtn.disabled(), "button enabled with a selection")

-- ---------------------------------------------------------------------------
-- Part 3: importing the selected categories only
-- ---------------------------------------------------------------------------
-- a selected category that has the same name as a current bag category
-- replaces it (with the source bag rule and its priorities); the other
-- categories of the current bag are kept
AutoCategory.saved.bags[2].rules[1].name = "Remplacée" -- was "Banque B"
importBagDD.setFunc(2) -- refresh the choices with the renamed category
importCatsDD.setFunc({ "Remplacée", "Banque C" })
cacheInitCalls = 0
importSelBtn.func()

local rules = AutoCategory.saved.bags[1].rules
equal(3, #rules, "import: the selected categories are added, the rest kept")
equal("Gardée", rules[1].name, "import: the untouched current category stays first")
local byName = {}
for _, r in ipairs(rules) do byName[r.name] = r end
equal(true, byName["Remplacée"] ~= nil, "import: the same-name category is replaced")
equal(50, byName["Remplacée"].runpriority, "import: the source bag rule is copied")
equal(5, byName["Remplacée"].showpriority, "import: the source priorities are copied")
equal(true, byName["Banque C"] ~= nil, "import: the new category is appended")
-- the copy is a copy: changing the source does not change the imported one
AutoCategory.saved.bags[2].rules[3].runpriority = 99
equal(10, byName["Banque C"].runpriority, "import: the bag rule is a deep copy")
equal(true, cacheInitCalls >= 1, "import: the cache is re-initialized")

-- ---------------------------------------------------------------------------
-- Part 4: a source bag identical to the current bag does nothing
-- ---------------------------------------------------------------------------
local before = #AutoCategory.saved.bags[1].rules
importBagDD.setFunc(1)
importCatsDD.setFunc({ "Gardée" })
importSelBtn.func()
equal(before, #AutoCategory.saved.bags[1].rules,
    "the current bag as source does not import")

-- ---------------------------------------------------------------------------
-- Part 5: changing the source bag drops the selections that are no
-- longer offered
-- ---------------------------------------------------------------------------
importBagDD.setFunc(2)
importCatsDD.setFunc({ "Banque A" }) -- only in the source bag
importBagDD.setFunc(1) -- the current bag does not offer "Banque A"
selected = importCatsDD.getFunc()
equal(0, #selected, "a selection no longer offered is dropped")

print("PASS: " .. assertions .. " assertions (ImportCats)")
