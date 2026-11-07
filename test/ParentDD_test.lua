-- Run from the addon root with Lua 5.1:
-- lua5.1 test/ParentDD_test.lua
-- Tests the CVT/BaseDD dropdown mechanics used by the Edit Category
-- "Parent" dropdown (CatSet_ParentDD_LAM in settings/CategorySettings.lua),
-- loading the delivered files (never copies of them).
--
-- Documents the real bug: CVT:assign() silently ignores a plain table (it
-- checks tblB.GetUses), so a dropdown whose refresh() passes a plain table
-- never receives its choices; assign() must be given a real CVT.

local assertions = 0
local function equal(expected, actual, message)
    assertions = assertions + 1
    assert(expected == actual, (message or "") .. ": expected "
        .. tostring(expected) .. ", got " .. tostring(actual))
end

-- ---------------------------------------------------------------------------
-- stubs (the delivered classes/CVT.lua and classes/BaseUI.lua need these)
-- ---------------------------------------------------------------------------
function GetString(si)
    return tostring(si)
end

LibSFUtils = {
    safeClearTable = function(t)
        for k in pairs(t) do t[k] = nil end
        return t
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

AutoCategory = {
    logDebug = function() end,
}

-- fake LAM dropdown control (what WINDOW_MANAGER:GetControlByName returns)
local fakeCtrl
local lastUpdateChoices, lastChoicesValues, lastUpdateValue, lastUpdateTooltips
fakeCtrl = {
    UpdateChoices = function(self, choices, values, tooltips)
        lastUpdateChoices = choices
        lastChoicesValues = values
        lastUpdateTooltips = tooltips
    end,
    UpdateValue = function(self, forceDefault, value)
        lastUpdateValue = value
    end,
}

WINDOW_MANAGER = {
    GetControlByName = function(self, name)
        if name == "TEST_DD" then return fakeCtrl end
        return nil
    end,
}

assert(loadfile("classes/CVT.lua"))()
assert(loadfile("classes/BaseUI.lua"))()

local CVT = AutoCategory.CVT
local BaseDD = AutoCategory.BaseDD

-- ---------------------------------------------------------------------------
-- Part 1: assign() with a plain table is a silent no-op (the bug)
-- ---------------------------------------------------------------------------
local dd = BaseDD:New("TEST_DD", nil, CVT.USE_VALUES)

dd:assign({ choices = { "(none)", "Alpha" }, choicesValues = { "", "Alpha" } })
equal(0, #dd.cvt.choices, "plain table assign: choices not copied")
equal(nil, dd.cvt.dirty, "plain table assign: not even marked dirty")
equal(0, #dd.cvt.choicesValues, "plain table assign: values not copied")

-- ---------------------------------------------------------------------------
-- Part 2: assign() with a real CVT copies the lists and marks dirty
-- ---------------------------------------------------------------------------
local tbl = CVT:New(nil, nil, CVT.USE_VALUES)
tbl.choices = { "(none)", "Alpha", "Beta" }
tbl.choicesValues = { "", "Alpha", "Beta" }
tbl.indexValue = "Beta"

dd:assign(tbl)
equal(3, #dd.cvt.choices, "CVT assign: choices copied")
equal("Alpha", dd.cvt.choices[2], "CVT assign: choice entry")
equal(3, #dd.cvt.choicesValues, "CVT assign: values copied")
equal("Beta", dd.cvt.choicesValues[3], "CVT assign: value entry")
equal(true, dd.cvt.dirty, "CVT assign: marked dirty")
equal("Beta", dd.cvt.indexValue, "CVT assign: indexValue selected")

-- assign with mismatched uses is ignored too (choicesTooltips vs none)
local wrong = CVT:New(nil, nil, CVT.USE_VALUES + CVT.USE_TOOLTIPS)
wrong.choices = { "x" }
wrong.choicesValues = { "x" }
wrong.choicesTooltips = { "x" }
dd:assign(wrong)
equal(3, #dd.cvt.choices, "mismatched uses: choices unchanged")

-- ---------------------------------------------------------------------------
-- Part 3: updateControl pushes the choices and the value to the LAM control
-- ---------------------------------------------------------------------------
dd:updateControl()
equal("(none)", lastUpdateChoices[1], "updateControl: choices pushed")
equal("Beta", lastChoicesValues[3], "updateControl: values pushed")
equal("Beta", lastUpdateValue, "updateControl: value pushed via UpdateValue")
equal(nil, dd.cvt.dirty, "updateControl: dirty cleared")
equal(nil, lastUpdateTooltips, "updateControl: no tooltips (USE_VALUES only)")

print("PASS: " .. assertions .. " assertions (ParentDD CVT mechanics)")
