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

local registered, native, scrolled, events
local function reset()
    native, scrolled, events = {}, {}, {}
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
function ShowMenu(row)
    equal(true, type(row.slot) == "number", "original menu anchored to clicked slot")
    events[#events + 1] = "native"
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
addRule("Petit-enfant", 3, "Enfant")
addRule("Masquée", 2, "Zèbre")
addRule("Vide")
addRule("-")
addRule("Protégé", nil, nil, true)
addRule("Banque")

local bagRules = {
    { name = "Enfant", showpriority = 5 },
    { name = "Petit-enfant", showpriority = 4 },
    { name = "Masquée", showpriority = 99, isHidden = true },
    { name = "Vide", showpriority = 60 },
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
assert(loadfile("AutoCategory_LevelMenu.lua"))()
assert(loadfile("AutoCategory_API.lua"))()
AutoCategory.getBagTypeId = function(id) if id <= 3 then return id end end
SI_AC_MENU_CM_MOVE_ITEM_SUBMENU = "Déplacer vers catégorie"
function GetString(id) return id end
assert(loadstring(table.concat({
    "local AutoCat = AutoCategory",
    "local LCM = LibCustomMenu",
    extract("local function setupContextMenu()"),
    "setupContextMenu()",
}, "\n")))()

local backpack = { bag = 1, slot = 4 }
AutoCategory.ScrollMenu = { Hide = function() end }
function AutoCategory.ScrollMenu.AddNativeSubmenu(label, entries)
    if #entries > 0 then native[label] = entries end
end
registered(backpack)
equal("function", type(native["AC: Get itemId"]), "existing item ID entry remains")
equal("native", events[1], "native item menu is shown")
equal(nil, native.AutoCategory, "old launcher is gone")
scrolled = assert(native[SI_AC_MENU_CM_MOVE_ITEM_SUBMENU])
equal(6, #scrolled, "include empty and protected, omit hidden and missing rules")
equal("Zèbre", scrolled[1].label, "highest visual priority comes first")
equal("   Enfant", scrolled[2].label, "child follows its parent with three spaces")
equal("      Petit-enfant", scrolled[3].label, "grandchild has six spaces")
equal("Protégé", scrolled[4].label, "protected categories appear in display order")
equal(nil, scrolled[4].action, "predefined rules cannot be edited")
equal("-", scrolled[5].label, "a hyphen is a literal category name")
equal("Vide", scrolled[6].label, "an empty category without a visible header is included")
local headerRows
AutoCategory.AddCategoryLevelMenuEntries("Zèbre", 1, {
    addItem = function() end,
    addDivider = function() end,
    addSubMenu = function(_, entries, opts)
        if opts and opts.searchable then headerRows = entries end
    end,
})
equal(#scrolled, #headerRows, "header and item menus share the same destinations")
for i, row in ipairs(scrolled) do
    equal(row.label, headerRows[i].label, "header and item menus share order and label")
end
equal("Enfant", bagRules[1].name, "saved list was not reordered")

backpack.slot = 9
scrolled[2].action()
equal(104, rules.Enfant.itemId, "selection targets the item right-clicked originally")
equal(nil, rules["Zèbre"].itemId, "selection only changes the chosen category")
equal("compile,cache,dropdowns,controls,list", table.concat(events, ",", 2),
    "rule change recompiles and refreshes in original order")
scrolled[2].action()
equal(6, #events, "duplicate item ID does not refresh")
bagRules[4].isHidden = true
scrolled[6].action()
equal(nil, rules.Vide.itemId, "do not edit a category hidden after the menu was built")

local bank = { bag = 2, slot = 1 }
reset()
registered(bank)
scrolled = assert(native[SI_AC_MENU_CM_MOVE_ITEM_SUBMENU])
equal(1, #scrolled, "next opening clears the previous bag's entries")
equal("Banque", scrolled[1].label, "only categories of the clicked bag are offered")

reset()
registered({ bag = 3, slot = 1 })
scrolled = assert(native[SI_AC_MENU_CM_MOVE_ITEM_SUBMENU])
equal(1, #scrolled, "protected-only bag still shows its category")
equal(nil, scrolled[1].action, "protected-only category remains disabled")
reset()
registered({ bag = 4, slot = 1 })
equal(nil, native[SI_AC_MENU_CM_MOVE_ITEM_SUBMENU], "no submenu for unsupported bags")

print(("PASS: %d assertions (InventoryCategoryMenu)"):format(assertions))
