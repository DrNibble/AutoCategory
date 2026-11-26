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

local testNow = 1000000
local originalGetTimeStamp = GetTimeStamp

local TEST_BAG = 9101
local TEST_CATEGORY = "Test Weapons"
local CATEGORY = TEST_CATEGORY

local DAY = 24 * 60 * 60

local function setTime(timestamp)
    testNow = timestamp
end

local function advanceTime(seconds)
    testNow = testNow + seconds
end

local function testIsCategoryInit()
    ZO_PlayerInventory = {}
    mn = moduleName
    class = moduleName

    AutoCategory.saved = {
        rules = {}, -- obsolete
        bags = {}, 
        general = {
            SAVE_CATEGORY_COLLAPSE_STATUS = true,
            CATEGORY_COLLAPSE_EXPIRY_SECONDS = 7 * DAY,
        },
        appearance = {}, -- from savedvars
        collapses = {},
        collapseExpiry = {},
    }

    AutoCategory.cache = {
        bags_cvt = CVT:New(nil, nil, CVT.USE_VALUES + CVT.USE_TOOLTIPS),
        entriesByBag = {},
        entriesByShowBag = {},
        entriesByName = {},
    }

    AutoCategory.BagRuleEntry = {}

    AutoCat.categoryState = {}

    -- Use a deterministic clock for expiry tests.
    GetTimeStamp = function()
        return testNow
    end

    setTime(1000000)

    saved = AutoCategory.saved
    cache = AutoCategory.cache
    
    -- Establish the configured duration baseline.
    AutoCat.LoadCollapse()


end

local function testIsCategoryReset()
    ZO_PlayerInventory = {}
    moduleName = ""
end

local function setupTest(duration, bagId)
    bagId = bagId or TEST_BAG

    AutoCat.saved = {
        general = {
            SAVE_CATEGORY_COLLAPSE_STATUS = true,
            CATEGORY_COLLAPSE_EXPIRY_SECONDS = duration,
        },
        collapses = {},
        collapseExpiry = {},
    }

    AutoCat.categoryState = {}

    -- Use a deterministic clock for expiry tests.
    GetTimeStamp = function()
        return testNow
    end

    setTime(1000000)

    -- Establish the configured duration baseline.
    AutoCat.LoadCollapse()

    return bagId
end

local function addCategory(bagId, categoryName)
    categoryName = categoryName or TEST_CATEGORY

    local categories = {}
    local state = AutoCat.categoryState[bagId]

    -- Preserve categories already present in this bag.
    for name in pairs(state or {}) do
        categories[name] = true
    end

    categories[categoryName] = true

    AutoCat.UpdateCategoryState(bagId, categories)
end

local function addCollapsedCategory(bagId, categoryName)
    categoryName = categoryName or TEST_CATEGORY

    addCategory(bagId, categoryName)
    AutoCat.SetCategoryCollapsed(bagId, categoryName, true)
end

local function removeCategory(bagId, categoryName)
    local categories = {}

    -- A nil categoryName means remove every category.
    if categoryName ~= nil then
        local state = AutoCat.categoryState[bagId]

        for name in pairs(state or {}) do
            if name ~= categoryName then
                categories[name] = true
            end
        end
    end

    AutoCat.UpdateCategoryState(bagId, categories)
end

local function getSavedCollapse(bagId, categoryName)
    categoryName = categoryName or TEST_CATEGORY

    local collapses = AutoCat.saved.collapses[bagId]
    return collapses and collapses[categoryName]
end

local function getExpiry(bagId, categoryName)
    categoryName = categoryName or TEST_CATEGORY

    local expiry = AutoCat.saved.collapseExpiry[bagId]
    return expiry and expiry[categoryName]
end

-- ============================================================================
-- Collapse tests
-- ============================================================================

local function resetCollapseTestState()
    AutoCat.saved.collapses = {}
    AutoCat.saved.collapseExpiry = {}
    AutoCat.categoryState = {}
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
    --TK.assertNil(AutoCategory.saved.collapses[1].Test,
    --    "removes expanded state from SavedVars")
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
    resetCollapseTestState()

    local bagId = BAG_BACKPACK

    AutoCat.categoryState = {
        [bagId] = {
            Weapons = false,
            Armor = true,
            Food = false,
            Other = true,
        },

        [BAG_BANK] = {
            Materials = false,
        },
    }

    AutoCat.saved.collapses = {
        [bagId] = {
            Armor = true,
            Other = true,
        },

        [BAG_BANK] = {},
    }

    AutoCat:CollapseAllCategories(bagId)

    local state = AutoCat.categoryState[bagId]
    local savedBag = AutoCat.saved.collapses[bagId]

    TK.assertTrue(state.Weapons, "CollapseAll: Weapons collapsed")
    TK.assertTrue(state.Armor, "CollapseAll: Armor collapsed")
    TK.assertTrue(state.Food, "CollapseAll: Food collapsed")
    TK.assertTrue(state.Other, "CollapseAll: Other collapsed")

    TK.assertTrue(savedBag.Weapons, "CollapseAll: Weapons saved")
    TK.assertTrue(savedBag.Armor, "CollapseAll: Armor saved")
    TK.assertTrue(savedBag.Food, "CollapseAll: Food saved")
    TK.assertTrue(savedBag.Other, "CollapseAll: Other saved")

    TK.assertFalse(
        AutoCat.categoryState[BAG_BANK].Materials,
        "CollapseAll: other bag runtime state unchanged"
    )

    TK.assertNil(
        AutoCat.saved.collapses[BAG_BANK].Materials,
        "CollapseAll: other bag saved state unchanged"
    )
end


local function testExpandAllCategories()
    TK.printSuite("Collapse", "ExpandAllCategories")
    resetCollapseTestState()

    local bagId = BAG_BACKPACK

    -- Persist collapsed preferences for all present categories.
    AutoCat.saved.collapses = {
        [bagId] = {
            Weapons = true,
            Armor = true,
            Food = true,
            Other = true,
        },

        [BAG_BANK] = {
            Materials = true,
        },
    }

    -- Rebuild runtime state from the currently present categories.
    AutoCat.UpdateCategoryState(bagId, {
        Weapons = true,
        Armor = true,
        Food = true,
        Other = true,
    })

    local before = AutoCat.categoryState[bagId]

    TK.assertTrue(before.Weapons, "ExpandAll setup: Weapons collapsed")
    TK.assertTrue(before.Armor, "ExpandAll setup: Armor collapsed")
    TK.assertTrue(before.Food, "ExpandAll setup: Food collapsed")
    TK.assertTrue(before.Other, "ExpandAll setup: Other collapsed")

    -- This is a colon method in AC_Collapsed.lua.
    AutoCat:ExpandAllCategories(bagId)

    local state = AutoCat.categoryState[bagId]

    TK.assertFalse(state.Weapons, "ExpandAll: Weapons expanded")
    TK.assertFalse(state.Armor, "ExpandAll: Armor expanded")
    TK.assertFalse(state.Food, "ExpandAll: Food expanded")
    TK.assertFalse(state.Other, "ExpandAll: Other expanded")

    -- Expanded categories are not saved as false.
    TK.assertNil(
        AutoCat.saved.collapses[bagId],
        "ExpandAll: empty saved bag table removed"
    )

    -- Other bags must not be affected.
    TK.assertTrue(
        AutoCat.saved.collapses[BAG_BANK].Materials,
        "ExpandAll: other bag preference unchanged"
    )
end
-- ==================================================================
-- Expiry tests
local function testExpiryStartsWhenCategoryBecomesEmpty()
    TK.printSuite("Collapse", "ExpiryStartsWhenCategoryBecomesEmpty")
    local bagId = setupTest(7 * DAY)

    addCollapsedCategory(bagId, "Weapons")
    addCollapsedCategory(bagId, "Armor")

    TK.assertEqual(true, getSavedCollapse(bagId, "Weapons"),
        "Weapons collapsed preference is saved")

    TK.assertEqual(true, getSavedCollapse(bagId, "Armor"),
        "Armor collapsed preference is saved")

    TK.assertNil(getExpiry(bagId, "Weapons"),
        "present Weapons category has no expiry")

    TK.assertNil(getExpiry(bagId, "Armor"),
        "present Armor category has no expiry")

    -- Remove every category from this bag.
    removeCategory(bagId)

    TK.assertEqual(true, getSavedCollapse(bagId, "Weapons"),
        "Weapons preference remains after category disappears")

    TK.assertEqual(true, getSavedCollapse(bagId, "Armor"),
        "Armor preference remains after category disappears")

    TK.assertEqual(testNow + 7 * DAY, getExpiry(bagId, "Weapons"),
        "Weapons expiry starts when category disappears")

    TK.assertEqual(testNow + 7 * DAY, getExpiry(bagId, "Armor"),
        "Armor expiry starts when category disappears")

    local state = AutoCat.categoryState[bagId]

    TK.assertNotNil(state,
        "empty bag retains its runtime table")

    TK.assertNil(next(state),
        "empty runtime table contains no categories")
end

local function testCountdownDoesNotRestart()
    TK.printSuite("Collapse", "CountdownDoesNotRestart")
    local bagId = setupTest(7 * DAY)

    addCollapsedCategory(bagId, CATEGORY)
    removeCategory(bagId, CATEGORY)

    local originalExpiry = getExpiry(bagId, CATEGORY)

    TK.assertNotNil(originalExpiry,
        "expiry is created when the category becomes absent")

    advanceTime(3 * DAY)

    -- Reconcile again while the category is still absent.
    removeCategory(bagId, CATEGORY)

    TK.assertEqual(originalExpiry, getExpiry(bagId, CATEGORY),
        "reconciliation does not restart the countdown")
end

local function testPreferenceExpiresAfterSevenDaysAbsent()
    TK.printSuite("Collapse", "PreferenceExpiresAfterSevenDaysAbsent")
    local bagId = setupTest(7 * DAY)

    addCollapsedCategory(bagId)
    removeCategory(bagId)

    testNow = testNow + 7 * DAY - 1
    removeCategory(bagId)

    TK.assertEqual(true, getSavedCollapse(bagId),
        "preference remains just before expiry")

    testNow = testNow + 1
    removeCategory(bagId)

    TK.assertNil(getSavedCollapse(bagId),
        "preference is removed at expiry")

    TK.assertNil(getExpiry(bagId),
        "expiry timestamp is removed with preference")
end

local function testCategoryEmptyOnDaySixGetsSevenMoreDays()
    TK.printSuite("Collapse", "CategoryEmptyOnDaySixGetsSevenMoreDays")
    local bagId = setupTest(7 * DAY)

    addCollapsedCategory(bagId)

    testNow = testNow + 6 * DAY
    removeCategory(bagId)

    local expectedExpiry = testNow + 7 * DAY

    TK.assertEqual(expectedExpiry, getExpiry(bagId),
        "expiry begins when the category becomes empty")

    testNow = testNow + DAY
    removeCategory(bagId)

    TK.assertEqual(true, getSavedCollapse(bagId),
        "preference remains after one day absent")

    testNow = testNow + 6 * DAY
    removeCategory(bagId)

    TK.assertNil(getSavedCollapse(bagId),
        "preference expires after seven days absent")
end

local function testReturningCategoryRestoresCollapsedState()
    TK.printSuite("Collapse", "ReturningCategoryRestoresCollapsedState")
    local bagId = setupTest(7 * DAY)

    addCollapsedCategory(bagId)
    removeCategory(bagId)

    testNow = testNow + 3 * DAY
    addCategory(bagId)

    TK.assertEqual(true, AutoCat.IsCategoryCollapsed(bagId, CATEGORY),
        "returning category restores collapsed state")

    TK.assertEqual(true, getSavedCollapse(bagId),
        "saved preference remains")

    TK.assertNil(getExpiry(bagId),
        "expiry is cleared when category returns")
end

local function testReturningCategoryAfterExpiryDefaultsExpanded()
    TK.printSuite("Collapse", "ReturningCategoryAfterExpiryDefaultsExpanded")
    local bagId = setupTest(7 * DAY)

    addCollapsedCategory(bagId)
    removeCategory(bagId)

    testNow = testNow + 7 * DAY
    removeCategory(bagId)

    addCategory(bagId)

    TK.assertEqual(false, AutoCat.IsCategoryCollapsed(bagId, CATEGORY),
        "expired category returns expanded")

    TK.assertNil(getSavedCollapse(bagId),
        "expired preference is not restored")
end

local function testChangingDurationRestartsCountdown()
    TK.printSuite("Collapse", "ChangingDurationRestartsCountdown")
    local bagId = setupTest(7 * DAY)

    addCollapsedCategory(bagId)
    removeCategory(bagId)

    testNow = testNow + 6 * DAY

    AutoCat.saved.general.CATEGORY_COLLAPSE_EXPIRY_SECONDS = DAY
    AutoCat.OnCollapseExpiryDurationChanged()

    TK.assertEqual(testNow + DAY, getExpiry(bagId),
        "changing duration starts a fresh countdown")

    testNow = testNow + DAY - 1
    removeCategory(bagId)

    TK.assertEqual(true, getSavedCollapse(bagId),
        "preference remains just before the new expiry")

    testNow = testNow + 1
    removeCategory(bagId)

    TK.assertNil(getSavedCollapse(bagId),
        "preference expires at the new expiry")
end

local function testChangedDurationAppliesToNewlyAbsentCategory()
    TK.printSuite("Collapse", "ChangedDurationAppliesToNewlyAbsentCategory")
    local bagId = setupTest(7 * DAY)

    addCollapsedCategory(bagId)

    testNow = testNow + 6 * DAY

    AutoCat.saved.general.CATEGORY_COLLAPSE_EXPIRY_SECONDS = DAY
    AutoCat.OnCollapseExpiryDurationChanged()

    removeCategory(bagId)

    TK.assertEqual(testNow + DAY, getExpiry(bagId),
        "newly absent category uses the current duration")
end

local function testNeverDoesNotCreateExpiry()
    TK.printSuite("Collapse", "NeverDoesNotCreateExpiry")
    local bagId = setupTest("never")

    addCollapsedCategory(bagId)
    removeCategory(bagId)

    TK.assertEqual(true, getSavedCollapse(bagId),
        "preference is retained")

    TK.assertNil(getExpiry(bagId),
        "never does not create an expiry timestamp")
end

local function testSwitchingToNeverPreservesPreference()
    TK.printSuite("Collapse", "SwitchingToNeverPreservesPreference")
    local bagId = setupTest(7 * DAY)

    addCollapsedCategory(bagId)
    removeCategory(bagId)

    testNow = testNow + 3 * DAY

    AutoCat.saved.general.CATEGORY_COLLAPSE_EXPIRY_SECONDS = "never"
    AutoCat.OnCollapseExpiryDurationChanged()

    TK.assertNil(getExpiry(bagId),
        "switching to never clears the expiry timestamp")

    testNow = testNow + 365 * DAY
    removeCategory(bagId)

    TK.assertEqual(true, getSavedCollapse(bagId),
        "preference remains after a year")
end

local function testSwitchingFromNeverStartsFreshCountdown()
    TK.printSuite("Collapse", "SwitchingFromNeverStartsFreshCountdown")
    local bagId = setupTest("never")

    addCollapsedCategory(bagId)
    removeCategory(bagId)

    testNow = testNow + 30 * DAY

    AutoCat.saved.general.CATEGORY_COLLAPSE_EXPIRY_SECONDS = DAY
    AutoCat.OnCollapseExpiryDurationChanged()

    TK.assertEqual(testNow + DAY, getExpiry(bagId),
        "switching from never starts a fresh countdown")
end

local function testExpandRemovesSavedPreference()
    TK.printSuite("Collapse", "ExpandRemovesSavedPreference")
    local bagId = setupTest(7 * DAY)

    addCollapsedCategory(bagId)
    removeCategory(bagId)
    addCategory(bagId)

    AutoCat.SetCategoryCollapsed(bagId, CATEGORY, false)

    TK.assertEqual(false, AutoCat.IsCategoryCollapsed(bagId, CATEGORY),
        "category is expanded")

    TK.assertNil(getSavedCollapse(bagId),
        "expanded preference is removed")

    TK.assertNil(getExpiry(bagId),
        "expanded category has no expiry")
end

local function testCollapseAllClearsExpiry()
    TK.printSuite("Collapse", "CollapseAllClearsExpiry")

    local bagId = setupTest(7 * DAY)

    -- Create a present, expanded category.
    addCategory(bagId, CATEGORY)

    -- Ensure the test verifies that Collapse All creates the preference.
    AutoCat.saved.collapses[bagId] = nil

    -- Seed an expiry timestamp to verify that Collapse All clears it.
    AutoCat.saved.collapseExpiry[bagId] = {
        [CATEGORY] = testNow + DAY,
    }

    AutoCat:CollapseAllCategories(bagId)

    TK.assertEqual(true,
        AutoCat.IsCategoryCollapsed(bagId, CATEGORY),
        "Collapse All collapses the category")

    TK.assertEqual(true,
        getSavedCollapse(bagId, CATEGORY),
        "Collapse All saves the collapsed preference")

    TK.assertNil(
        getExpiry(bagId, CATEGORY),
        "Collapse All clears expiry for the present category"
    )
end

local function testExpandAllRemovesPreferences()
    TK.printSuite("Collapse", "ExpandAllRemovesPreferences")
    local bagId = setupTest(7 * DAY)

    addCategory(bagId, "Weapons")
    addCategory(bagId, "Armor")

    AutoCat.SetCategoryCollapsed(bagId, "Weapons", true)
    AutoCat.SetCategoryCollapsed(bagId, "Armor", true)

    AutoCat:ExpandAllCategories(bagId)

    TK.assertEqual(false, AutoCat.IsCategoryCollapsed(bagId, "Weapons"),
        "Expand All expands Weapons")

    TK.assertEqual(false, AutoCat.IsCategoryCollapsed(bagId, "Armor"),
        "Expand All expands Armor")

    TK.assertNil(getSavedCollapse(bagId, "Weapons"),
        "Expand All removes the Weapons preference")

    TK.assertNil(getSavedCollapse(bagId, "Armor"),
        "Expand All removes the Armor preference")
end

local function testCollapseExpiry()
    testExpiryStartsWhenCategoryBecomesEmpty()
    testCountdownDoesNotRestart()
    testPreferenceExpiresAfterSevenDaysAbsent()
    testCategoryEmptyOnDaySixGetsSevenMoreDays()
    testReturningCategoryRestoresCollapsedState()
    testReturningCategoryAfterExpiryDefaultsExpanded()
    testChangingDurationRestartsCountdown()
    testChangedDurationAppliesToNewlyAbsentCategory()
    testNeverDoesNotCreateExpiry()
    testSwitchingToNeverPreservesPreference()
    testSwitchingFromNeverStartsFreshCountdown()
    testExpandRemovesSavedPreference()
    testCollapseAllClearsExpiry()
    testExpandAllRemovesPreferences()
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
    
    testCollapseExpiry()
end

if not Suite then
    TK.init()
    
    testCollapse_runAll()
    
    TK.showResult("Collapse Tests")
end
