package.path = package.path .. ";C:/Users/scott/Documents/SFAddons/TK/?.lua;C:/Users/scott/Documents/Elder Scrolls Online/live/AddOns/LibSFUtils/?.lua"

require "zos"
require "tk"
local TK = TestKit

local AC_DECON = 880
local AC_IMPROV = 881
local UV_DECON = 882

require "LibSFUtils_Global"
require "SFUtils_Color"
require "LibSFUtils"
require "SFUtils_Strings"
require "SFUtils_Tables"
require "SFUtils_Events"
require "SFUtils_HookManager"
require "SFUtils_LoadLanguage"
require "SFUtils_Logger"
local SF = LibSFUtils

require "AutoCategory_Global"
require "AutoCategory_Defaults"
require "Plugin_API"
require "Hooks_Keyboard"
require "classes.CVT"
require "classes.RuleList"
require "classes.RuleApi"
require "classes.BagRuleApi"
require "classes.BaseUI"
require "AC_Collapsed"
require "AutoCategory"

local AutoCat = AutoCategory
local CVT = AutoCategory.CVT

local ZO_PlayerInventory
local saved, cache

local moduleName = "Category"
local mn, class

local function testIsCategoryInit()
    ZO_PlayerInventory = {}
    mn = moduleName
    class = moduleName

    AutoCategory.saved = {
        rules = {}, -- obsolete
        bags = {}, 
        general = {},   -- from savedvars
        appearance = {}, -- from savedvars
        collapses = {},  
    }

    AutoCategory.cache = {
        bags_cvt = CVT:New(nil, nil, CVT.USE_VALUES + CVT.USE_TOOLTIPS),
        entriesByBag = {},
        entriesByShowBag = {},
        entriesByName = {},
    }

    AutoCategory.BagRuleEntry = {}


    saved = AutoCategory.saved
    cache = AutoCategory.cache
end

local function testIsCategoryReset()
    ZO_PlayerInventory = {}
    moduleName = ""
end

-- ============================================================================
-- Collapse tests
-- ============================================================================

local function resetCollapseTestState()
    AutoCat.saved.collapses = {}
end


local function testIsCategoryCollapsed()
    TK.printSuite("Collapse", "IsCategoryCollapsed")
    resetCollapseTestState()

    local bagId = BAG_BACKPACK

    TK.assertFalse(AutoCat.IsCategoryCollapsed(bagId, "Missing"),
        "missing bag returns false")

    AutoCat.UpdateCategoryState(bagId, {Test = true,})

    TK.assertTrue(AutoCat.categoryState[bagId] ~= nil,
        "Created entry for Test")
    TK.assertFalse(AutoCat.categoryState[bagId].Test,
        "Test initially expanded")

    AutoCat.SetCategoryCollapsed(bagId, "Test", true)

    TK.assertTrue(AutoCat.categoryState[bagId].Test,
        "runtime Test state is true")
    TK.assertTrue(AutoCat.saved.collapses[bagId].Test,
        "saved Test state is true")
    TK.assertTrue(AutoCat.IsCategoryCollapsed(bagId, "Test"),
        "collapsed category returns true")

    AutoCat.SetCategoryCollapsed(bagId, "Test", false)

    TK.assertFalse(AutoCat.categoryState[bagId].Test,
        "runtime Test state is false")
    TK.assertFalse(AutoCat.IsCategoryCollapsed(bagId, "Test"),
        "expanded category returns false")
end


function testIsCategoryCollapsed_invalid()
    TK.printSuite("Collapse", "IsCategoryCollapsed_invalid")
    resetCollapseTestState()

    TK.assertFalse(AutoCat.IsCategoryCollapsed(nil, "Test"),
        "nil bagId returns false")
    TK.assertFalse(AutoCat.IsCategoryCollapsed(1, nil),
        "nil category returns false")
    TK.assertFalse(AutoCat.IsCategoryCollapsed(nil, nil),
        "nil bagId and category return false")
end


function testIsCategoryCollapsed_noCreate()
    TK.printSuite("Collapse", "IsCategoryCollapsed_noCreate")
    resetCollapseTestState()

    AutoCat.IsCategoryCollapsed(123, "Missing")

    TK.assertTrue(AutoCat.saved.collapses[123] == nil,
        "read does not create missing bag table")
end


function testSetCategoryCollapsed()
    TK.printSuite("Collapse", "SetCategoryCollapsed")
    resetCollapseTestState()

    -- Establish Test as a currently-present category.
    AutoCategory.UpdateCategoryState(1, {
        Test = true,
    })

    AutoCategory.SetCategoryCollapsed(1, "Test", true)

    TK.assertTrue(AutoCategory.categoryState[1] ~= nil,
        "creates bag runtime state")
    TK.assertTrue(AutoCategory.categoryState[1].Test == true,
        "sets runtime state to true")
    TK.assertTrue(AutoCategory.saved.collapses[1] ~= nil,
        "creates bag collapse table")
    TK.assertTrue(AutoCategory.saved.collapses[1].Test == true,
        "stores collapsed state")
    TK.assertTrue(AutoCategory.IsCategoryCollapsed(1, "Test"),
        "stored true state is readable")

    AutoCategory.SetCategoryCollapsed(1, "Test", false)

    TK.assertFalse(AutoCategory.categoryState[1].Test,
        "sets runtime state to false")

    TK.assertFalse(AutoCategory.IsCategoryCollapsed(1, "Test"),
        "updated false state is readable")
    TK.assertNil(AutoCategory.saved.collapses[1].Test,
        "removes expanded state from SavedVars")
end

local function testSetCategoryCollapsed_multiple()
    TK.printSuite("Collapse", "SetCategoryCollapsed multiple")

    resetCollapseTestState()

    AutoCat.UpdateCategoryState(BAG_BACKPACK, {
        Weapons = true,
        Armor = true,
        Food = true,
    })

    AutoCat.SetCategoryCollapsed(BAG_BACKPACK, "Weapons", true)
    AutoCat.SetCategoryCollapsed(BAG_BACKPACK, "Armor", true)
    AutoCat.SetCategoryCollapsed(BAG_BACKPACK, "Food", false)

    local state = AutoCat.categoryState[BAG_BACKPACK]
    local saved = AutoCat.saved.collapses[BAG_BACKPACK]

    TK.assertTrue(state.Weapons, "multiple: Weapons collapsed")
    TK.assertTrue(state.Armor,  "multiple: Armor collapsed")
    TK.assertFalse(state.Food, "multiple: Food expanded")
    TK.assertTrue(saved.Weapons, "multiple: Weapons saved")
    TK.assertTrue(saved.Armor, "multiple: Armor saved")
    TK.assertNil(saved.Food, "multiple: Food not saved when expanded")
end


function testSetCategoryCollapsed_invalid()
    TK.printSuite("Collapse", "SetCategoryCollapsed_invalid")
    resetCollapseTestState()

    AutoCat.SetCategoryCollapsed(nil, "Test", true)

    TK.assertTrue(next(AutoCat.saved.collapses) == nil,
        "nil bagId does not modify collapse state")

    AutoCat.SetCategoryCollapsed(1, nil, true)

    TK.assertTrue(next(AutoCat.saved.collapses) == nil,
        "nil category does not modify collapse state")
end


function testResetCollapse()
    TK.printSuite("Collapse", "ResetCollapse")
    resetCollapseTestState()

    AutoCat.saved.collapses[1] = {
        First = true,
        Second = false,
    }

    AutoCat.saved.collapses[2] = {
        Third = true,
    }

    AutoCat.ResetCollapse(AutoCat.saved.collapses)

    TK.assertNil( next(AutoCat.saved.collapses[1]),
        "clears bag 1 collapse state")
    TK.assertNil(next(AutoCat.saved.collapses[2]),
        "clears bag 2 collapse state")
end

function testPruneCollapse()
    TK.printSuite("Collapse", "PruneCollapse")
    resetCollapseTestState()

    AutoCat.saved.collapses[1] = {
        First = true,
        Second = false,
    }

    AutoCat.saved.collapses[2] = {
        Third = true,
    }

    AutoCat.PruneCollapse(AutoCat.saved.collapses)

    TK.assertNotNil( AutoCat.saved.collapses[1].First,
        "preserves bag 1 First collapse state")
    TK.assertNil( AutoCat.saved.collapses[1].Second,
        "clears bag 1 Second collapse state")
    TK.assertNotNil(next(AutoCat.saved.collapses[2]),
        "preserves bag 2 collapse state")
end


function testResetCollapse_preservesTables()
    TK.printSuite("Collapse", "SetCategoryCollapsed_preservesTables")
    resetCollapseTestState()

    local bagcol = {
        First = true,
        Second = true,
    }

    AutoCat.saved.collapses[1] = bagcol

    AutoCat.ResetCollapse(AutoCat.saved.collapses)

    TK.assertTrue(AutoCat.saved.collapses[1] == bagcol,
        "preserves collapse table reference")
    TK.assertNil(next(bagcol),
        "clears collapse table in place")
end



---------------------------------------------------------------------------
-- CollapseAllCategories / ExpandAllCategories
---------------------------------------------------------------------------

local function testCollapseAllCategories()
    TK.printSuite("Collapse", "CollapseAllCategories")

    local bagId = BAG_BACKPACK

    AutoCat.saved.appearance["CATEGORY_OTHER_TEXT"] = "Other"

    -- Runtime state contains every currently present category.
    AutoCat.categoryState = {
        [bagId] = {
            ["Weapons"] = false,
            ["Armor"] = true,
            ["Food"] = false,
            ["Other"] = true,
        },

        [BAG_BANK] = {
            ["Materials"] = false,
        },
    }

    -- SavedVars contains only collapsed categories.
    AutoCat.saved.collapses = {
        [bagId] = {
            ["Armor"] = true,
            ["Other"] = true,
        },

        [BAG_BANK] = {},
    }

    AutoCat:CollapseAllCategories(bagId)

    local state = AutoCat.categoryState[bagId]
    local saved = AutoCat.saved.collapses[bagId]

    TK.assertTrue(state["Weapons"], "CollapseAll: Weapons collapsed")
    TK.assertTrue(state["Armor"], "CollapseAll: Armor collapsed")
    TK.assertTrue(state["Food"], "CollapseAll: Food collapsed")
    TK.assertTrue(state["Other"], "CollapseAll: Other collapsed")

    -- All currently-present categories should now be persisted.
    TK.assertTrue(saved["Weapons"], "CollapseAll: Weapons saved")
    TK.assertTrue(saved["Armor"], "CollapseAll: Armor saved")
    TK.assertTrue(saved["Food"], "CollapseAll: Food saved")
    TK.assertTrue(saved["Other"], "CollapseAll: Other saved")

    -- Other bags must not be affected.
    TK.assertFalse(AutoCat.categoryState[BAG_BANK]["Materials"],
        "CollapseAll: other (Materials) runtime state unchanged" )

    TK.assertNil(AutoCat.saved.collapses[BAG_BANK]["Materials"],
        "CollapseAll: other (Materials) saved state unchanged")
end


local function testExpandAllCategories()
    TK.printSuite("Collapse", "ExpandAllCategories")
    local bagId = BAG_BACKPACK
    AutoCat.saved.appearance["CATEGORY_OTHER_TEXT"] = "Other"

    AutoCat.saved.collapses = {
        [bagId] = {
            ["Weapons"] = true,
            ["Armor"] = false,
            ["Food"] = true,
        },
        [BAG_BANK] = {
            ["Materials"] = true,
        },
    }

    AutoCat:ExpandAllCategories(bagId)

    local state = AutoCat.saved.collapses[bagId]

    TK.assertFalse(state["Weapons"], "ExpandAll: Weapons expanded")
    TK.assertFalse(state["Armor"], "ExpandAll: Armor expanded")
    TK.assertFalse(state["Food"], "ExpandAll: Food expanded")
    TK.assertFalse(state["Other"], "ExpandAll: Other expanded")

    -- Other bags must not be affected.
    TK.assertTrue(AutoCat.saved.collapses[BAG_BANK]["Materials"],
        "ExpandAll: (Materials) other bag unchanged")
end


-- ============================================================================
-- Run tests
-- ============================================================================
function testCollapse_runAll()
    testIsCategoryInit()
    
    testIsCategoryCollapsed()
    testIsCategoryCollapsed_invalid()
    testIsCategoryCollapsed_noCreate()
    testSetCategoryCollapsed()
    testSetCategoryCollapsed_multiple()
    testSetCategoryCollapsed_invalid()
    testResetCollapse()
    testResetCollapse_preservesTables()
    testPruneCollapse()
    testCollapseAllCategories()
    testExpandAllCategories()
    
    testIsCategoryReset()
end

if not Suite then
    TK.init()
    
    testCollapse_runAll()
    
    TK.showResult("Collapse Tests")
end
