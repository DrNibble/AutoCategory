-- From AutoCategory/: lua5.1 ../test/InventoryCategoryMenu_test.lua
local assertions = 0
local function equal(expected, actual, message)
    assertions = assertions + 1
    assert(expected == actual, message .. ": expected " .. tostring(expected)
        .. ", got " .. tostring(actual))
end

local file = assert(io.open("AutoCategory.lua", "rb"))
local source = file:read("*a"):gsub("\r\n", "\n")
file:close()
local function extract(signature)
    local first = assert(source:find("\n" .. signature, 1, true)) + 1
    local last = assert(source:find("\nend\n", first, true))
    return source:sub(first, last + 3)
end

local registered, native, submenu, scrolled, pending, events
local function reset()
    native, submenu, scrolled, pending, events = {}, {}, {}, {}, {}
end
reset()
MENU_ADD_OPTION_LABEL = 1
LibCustomMenu = {
    CATEGORY_LATE = 6,
    RegisterContextMenu = function(_, callback, category)
        equal(6, category, "same LibCustomMenu registration")
        registered = callback
    end,
}
function ZO_Inventory_GetBagAndIndex(row) return row.bag, row.slot end
function GetItemId(bagId, slotIndex) return bagId * 100 + slotIndex end
function AddCustomMenuItem(label, callback) native[label] = callback end
function AddCustomSubMenuItem(label, entries) submenu[label] = entries end
function ShowMenu(row)
    equal(true, type(row.slot) == "number", "original menu anchored to clicked slot")
    events[#events + 1] = "native"
end
function zo_callLater(callback, delay)
    equal(0, delay, "defer until the native mouse-up completes")
    pending[#pending + 1] = callback
end

local rules = {}
local function addRule(name, level, parent, predefined)
    rules[name] = {
        name = name, level = level, parent = parent,
        isPredefined = function() return predefined end,
        addItemIdToIsItemId = function(self, id)
            if self.itemId == id then return false end
            self.itemId = id
            return true
        end,
        compile = function() events[#events + 1] = "compile" end,
    }
end
addRule("Zèbre")
addRule("Enfant", 2, "Zèbre")
addRule("-")
addRule("Protégé", nil, nil, true)
addRule("Banque")

local bagRules = {
    { name = "Enfant", showpriority = 5 },
    { name = "-", showpriority = 80 },
    { name = "Protégé", showpriority = 90 },
    { name = "Zèbre", showpriority = 100 },
    { name = "Introuvable", showpriority = 105 },
}
AutoCategory = {
    saved = { bags = {
        [1] = { rules = bagRules },
        [2] = { rules = { { name = "Banque" } } },
        [3] = { rules = { { name = "Protégé" } } },
    } },
    getBagTypeId = function(id) if id <= 3 then return id end end,
    GetRuleByName = function(name) return rules[name] end,
    GetCategorySortName = function() end,
    cacheInitialize = function() events[#events + 1] = "cache" end,
    RefreshCurrentList = function() events[#events + 1] = "list" end,
}
AC_UI = {
    RefreshDropdownData = function() events[#events + 1] = "dropdowns" end,
    RefreshControls = function() events[#events + 1] = "controls" end,
}
assert(loadfile("AutoCategory_Tree.lua"))()
assert(loadstring(table.concat({
    "local AutoCat = AutoCategory",
    "local CategoryTree = AutoCategory.CategoryTree",
    "local LCM = LibCustomMenu",
    extract("local function BagRuleShowKey("),
    extract("function AutoCat.SortBagRulesByDisplay("),
    extract("local function addScrollableContextSubMenu("),
    extract("local function setupContextMenu()"),
    "setupContextMenu()",
}, "\n")))()

local backpack = { bag = 1, slot = 4 }
registered(backpack)
equal(nil, native.AutoCategory, "no launcher without LSM")
equal(3, #submenu.AutoCategory, "fallback only lists editable categories")
equal("    Enfant", submenu.AutoCategory[2].label, "fallback indents the child")
equal("AC: Get itemId", next(native), "existing item ID entry remains")

LibScrollableMenu = { DIVIDER = "-" }
ClearCustomScrollableMenu = function()
    scrolled = {}
    events[#events + 1] = "clear"
end
AddCustomScrollableMenuEntry = function(label, callback)
    scrolled[#scrolled + 1] = { label = label, callback = callback }
end
registered(backpack)
equal(nil, native.AutoCategory, "incomplete LSM API keeps the fallback")

local anchoredTo, options
function ShowCustomScrollableMenu(row, opts)
    anchoredTo, options = row, opts
    events[#events + 1] = "scrollable"
end
reset()
registered(backpack)
equal(nil, submenu.AutoCategory, "LSM does not add a duplicate native submenu")
equal("native", events[1], "normal item menu is shown first")
equal(0, #pending, "no scrollable list on right-click alone")
native.AutoCategory()
equal(1, #events, "defer opening until after the native menu click")
pending[1]()
equal("clear,scrollable", table.concat(events, ",", 2), "clear LSM before displaying")
equal(backpack, anchoredTo, "scrollable list belongs to clicked row")
equal(false, options.sortEntries, "LSM must not sort the display order")
equal(12, options.visibleRowsDropdown, "long lists have a fixed viewport")
equal(3, #scrolled, "filter out protected and missing rules")
equal("Zèbre", scrolled[1].label, "highest visual priority comes first")
equal("    Enfant", scrolled[2].label, "child follows its parent with indentation")
equal(" -", scrolled[3].label, "divider-like name is still clickable")
equal("Enfant", bagRules[1].name, "saved list was not reordered")

backpack.slot = 9
scrolled[2].callback({}, "    Enfant", {})
equal(104, rules.Enfant.itemId, "selection targets the item right-clicked originally")
equal(nil, rules["Zèbre"].itemId, "selection only changes the chosen category")
equal("compile,cache,dropdowns,controls,list", table.concat(events, ",", 4),
    "rule change recompiles and refreshes in original order")
scrolled[2].callback()
equal(8, #events, "duplicate item ID does not refresh")

local bank = { bag = 2, slot = 1 }
registered(bank)
native.AutoCategory()
pending[2]()
equal(bank, anchoredTo, "menu reanchors to the next clicked bag")
equal(1, #scrolled, "next opening clears the previous bag's entries")
equal("Banque", scrolled[1].label, "only categories of the clicked bag are offered")

reset()
registered({ bag = 3, slot = 1 })
equal(nil, native.AutoCategory, "no launcher when all categories are protected")
registered({ bag = 4, slot = 1 })
equal(nil, native.AutoCategory, "no launcher for unsupported bags")

print(("PASS: %d assertions (InventoryCategoryMenu)"):format(assertions))
