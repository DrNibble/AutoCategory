-- Run from AutoCategory/: lua5.1 ../test/CategoryCreation_test.lua
-- Real factories, compiler, rule list and dialog/menu code; no copies.
local assertions = 0
local function equal(expected, actual, message)
    assertions = assertions + 1
    assert(expected == actual, (message or "") .. ": expected "
        .. tostring(expected) .. ", got " .. tostring(actual))
end

for _, key in ipairs({
    "SI_AC_MENU_CM_NEW_CATEGORY", "SI_AC_MENU_CM_MANAGE_CATEGORIES", "SI_AC_DEFAULT_NAME_EMPTY_TAG",
    "SI_AC_DIALOG_CATEGORY_NAME_PROMPT", "SI_AC_DIALOG_CATEGORY_NAME_EMPTY",
    "SI_AC_DIALOG_CATEGORY_NAME_EXISTS", "SI_AC_DIALOG_CATEGORY_CREATE_FAILED",
    "SI_AC_MENU_CM_TAG_NEW", "SI_AC_DIALOG_TAG_NAME_FIELD",
    "SI_AC_DIALOG_TAG_NAME_EMPTY", "SI_AC_MENU_CS_DROPDOWN_TAG",
    "SI_AC_NEW_CATEGORY_EMPTY_CHILD",
    "SI_OK", "SI_DIALOG_CANCEL",
}) do _G[key] = key end
function GetString(key) return key end
LocaleAwareToLower = string.lower
zo_loadstring = loadstring
LibSFUtils = {}
ZO_Object = {}
function ZO_Object:Subclass() return setmetatable({}, { __index = self }) end
function ZO_Object:New() return setmetatable({}, { __index = self }) end

AutoCategory = {
    saved = { bags = { [1] = { rules = {} }, [3] = { rules = {} } } },
    compiledRules = {}, Environment = {},
}
assert(loadfile("classes/RuleApi.lua"))()
assert(loadfile("classes/BagRuleApi.lua"))()
assert(loadfile("classes/RuleList.lua"))()
AutoCategory.ARW = AutoCategory.RuleList:New({})
AutoCategory.RulesW = AutoCategory.RuleList:New({})
AutoCategory.RulesW.tags = {}
function AutoCategory.GetRuleByName(name)
    return AutoCategory.RuleList.getRuleByName(AutoCategory.RulesW, name)
end
local cacheAdds, refreshes = 0, 0
AutoCategory.cache = { AddRule = function(rule)
    equal(rule, AutoCategory.ARW:getRuleByName(rule.name), "saved rules updated first")
    AutoCategory.RulesW:AddRule(rule)
    cacheAdds = cacheAdds + 1
end }
function AutoCategory.cacheInitialize() refreshes = refreshes + 1 end
function AutoCategory.RefreshCurrentList() end
AC_UI = { BagSet = {} }

local selectedBag, windowOpens = 1, 0
function AC_UI.BagSet.ShowCategoryOrder() error("ordering window must not open") end
AutoCategory.dspWin = {
    SetHidden = function() windowOpens = windowOpens + 1 end,
}

local function mockControl(children)
    local control = { children = children, hidden = false, text = "" }
    function control:GetNamedChild(name) return assert(self.children[name], "missing " .. name) end
    function control:SetHidden(hidden) self.hidden = hidden end
    function control:SetText(text) self.text = text end
    function control:GetText() return self.text end
    function control:SetMaxInputChars(max) self.maxInputChars = max end
    function control:TakeFocus() self.hasFocus = true end
    return control
end

local nameEditBox = mockControl()
local tagEditBox = mockControl()
local newTagRow = mockControl({ Backdrop = mockControl({ Edit = tagEditBox }) })
local comboControl, confirm, cancel = mockControl(), mockControl(), mockControl()
AC_NewCategoryDialog = mockControl({
    CategoryName = mockControl({ Edit = nameEditBox }),
    NewTag = newTagRow, Tag = comboControl, Confirm = confirm, Cancel = cancel,
})

local comboBoxItems, comboBox = {}, {}
function comboBox:ClearItems() comboBoxItems = {} end
function comboBox:CreateItemEntry(label, callback) return { label = label, callback = callback } end
function comboBox:AddItem(entry) comboBoxItems[#comboBoxItems + 1] = entry end
function comboBox:SelectItem(entry, ignoreCallback)
    self.selected = entry
    if not ignoreCallback then entry.callback() end
end
function comboBox:HideDropdown() self.open = false end
function comboBox:SetSortsItems(sort)
    equal(false, sort, "native combo box preserves the order of special choices")
end
local comboInitializations = 0
function ZO_ComboBox_ObjectFromContainer(control)
    equal(comboControl, control, "get the native tag selector from the dialog")
    comboInitializations = comboInitializations + 1
    return comboBox
end

local registered, registrations, displayed, releases = {}, 0, nil, 0
function ZO_Dialogs_RegisterCustomDialog(name, info)
    registrations = registrations + 1
    registered[name] = info
end
function ZO_Dialogs_ShowDialog(name, data)
    if displayed then return end
    local info = assert(registered[name])
    displayed = assert(info.customControl, "expected a dedicated dialog")
    displayed.name, displayed.data, displayed.info = name, data, info
    displayed.errorText = info.mainText.text
    info.setup(displayed)
end
function ZO_Dialogs_UpdateDialogMainText(dialog, text) dialog.errorText = text.text end
function ZO_Dialogs_ReleaseDialog(dialog)
    equal(displayed, dialog, "release the correct popup")
    releases = releases + 1
    displayed, dialog.data = nil, nil
    dialog.info.finishedCallback(dialog)
end
ZO_Dialogs_ReleaseDialogOnButtonPress = ZO_Dialogs_ReleaseDialog

local items = {}
local menu = { addItem = function(label, callback)
    items[#items + 1] = { label = label, callback = callback }
end }

assert(loadfile("AutoCategory_Tree.lua"))()
assert(loadfile("AutoCategory_LevelMenu.lua"))()
local CLM = AutoCategory.CategoryLevelMenu
local function submit(text)
    nameEditBox:SetText(text)
    displayed.info.buttons[1].callback(displayed)
end

AutoCategory.AddCategoryLevelMenuEntries("Others", 3, menu)
equal(2, #items, "creation and management available on header without backing rule")
equal(SI_AC_MENU_CM_NEW_CATEGORY, items[1].label, "new label")
items[1].callback()
equal(1, registrations, "popup registered once")
equal(128, nameEditBox.maxInputChars, "category name length is unchanged")
equal(3, displayed.data.bagTypeId, "popup captures clicked bag")
equal(0, #AutoCategory.RulesW.ruleList, "opening does not create anything")
equal(confirm, displayed.info.buttons[1].control, "confirm uses the XML button")
equal(cancel, displayed.info.buttons[2].control, "cancel uses the XML button")
equal(true, displayed.info.buttons[1].noReleaseOnClick, "invalid input stays editable")
equal(nil, displayed.info.buttons[2].callback, "cancel has no mutation callback")
submit(" \t ")
equal(SI_AC_DIALOG_CATEGORY_NAME_EMPTY, displayed.errorText, "blank error is visible")
equal(0, releases, "blank name keeps popup open")
equal(0, #AutoCategory.RulesW.ruleList, "blank name does not create a rule")

-- Another opening attempt must not overwrite the current bag or draft.
AutoCategory.RulesW.tags = { "Tag B", SI_AC_DEFAULT_NAME_EMPTY_TAG, "Tag A" }
CLM.OpenNewCategoryDialog(1)
equal(3, displayed.data.bagTypeId, "second request cannot retarget the open form")
equal(" \t ", nameEditBox:GetText(), "second request leaves the draft untouched")
equal(2, #comboBoxItems, "second request did not rebuild the open list")
submit("  Ma catégorie  ")
equal(1, releases, "valid name closes the first popup")
CLM.OpenNewCategoryDialog(1)
equal(1, comboInitializations, "the native combo box is reused")
equal(1, displayed.data.bagTypeId, "reopened form captures its own bag")
equal("", nameEditBox:GetText(), "new form clears the previous name")
equal(SI_AC_DIALOG_CATEGORY_NAME_PROMPT, displayed.errorText, "new form restores the prompt")
equal(4, #comboBoxItems, "dropdown refreshes with two tags and two special entries")
equal("Tag A", comboBoxItems[1].label, "existing tags are sorted")
equal("Tag B", comboBoxItems[2].label, "second tag")
equal(SI_AC_DEFAULT_NAME_EMPTY_TAG, comboBoxItems[3].label, "empty tag is offered")
equal(comboBoxItems[3], comboBox.selected, "empty tag is selected by default")
equal(SI_AC_MENU_CM_TAG_NEW, comboBoxItems[4].label, "create a new tag")

local created = AutoCategory.GetRuleByName("Ma catégorie")
equal(true, created ~= nil, "trimmed name is registered")
equal(GetString(SI_AC_DEFAULT_NAME_EMPTY_TAG), created.tag, "the default empty tag is applied")
equal("false", created.rule, "false rule is preserved literally")
equal(false, AutoCategory.compiledRules[created:key()](), "real compiled rule matches nothing")
equal(nil, created.level, "Normal level")
equal(nil, created.parent, "no inherited parent")
equal(2, #AutoCategory.saved.bags[3].rules, "captured bag receives category and placeholder")
equal(0, #AutoCategory.saved.bags[1].rules, "other bag unchanged")
equal("Ma catégorie", AutoCategory.saved.bags[3].rules[1].name, "saved bag entry")
local createdChild = AutoCategory.GetRuleByName("Ma catégorie " .. SI_AC_NEW_CATEGORY_EMPTY_CHILD)
equal(true, createdChild ~= nil, "the hidden placeholder child rule is created")
equal("false", createdChild.rule, "the placeholder child never matches")
equal(2, createdChild.level, "the placeholder child sits one level below")
equal("Ma catégorie", createdChild.parent, "the placeholder child nests under the new category")
equal(GetString(SI_AC_DEFAULT_NAME_EMPTY_TAG), createdChild.tag,
    "the placeholder child keeps the category's tag")
equal(true, AutoCategory.saved.bags[3].rules[2].isHidden, "the placeholder child bag rule is hidden")
equal(1000, AutoCategory.saved.bags[3].rules[2].showpriority,
    "the placeholder child keeps the display priority")
equal(1000, AutoCategory.saved.bags[3].rules[1].showpriority, "default sortable priority")
equal(2, cacheAdds, "cache updated for the category and its placeholder")
equal(1, refreshes, "lists refreshed once")
equal(1, releases, "success closes popup")
equal(1, selectedBag, "creation does not change settings bag selection")
equal(0, windowOpens, "ordering window is not opened")

equal(1, registrations, "popup definition reused")
submit("Ma catégorie")
equal(SI_AC_DIALOG_CATEGORY_NAME_EXISTS, displayed.errorText, "cross-bag duplicate refused")
equal(1, releases, "duplicate keeps popup open")
equal(0, #AutoCategory.saved.bags[1].rules, "duplicate adds no bag entry")
equal(2, #AutoCategory.RulesW.ruleList, "duplicate not suffixed or overwritten")
submit("MA CATéGORIE")
equal(SI_AC_DIALOG_CATEGORY_NAME_EXISTS, displayed.errorText, "case-insensitive duplicate")
equal(1, releases, "duplicate keeps popup open")
comboBox:SelectItem(comboBoxItems[2])
submit("Unique")
equal(2, releases, "corrected input closes popup")
equal(2, #AutoCategory.saved.bags[1].rules, "corrected input creates in captured bag")
equal("Tag B", AutoCategory.GetRuleByName("Unique").tag, "existing tag is applied")

-- An existing global rule need not belong to this bag; predefined names
-- and orphan saved bag names must not be reused either.
local pred = AutoCategory.CreateRule("Predefined", "")
pred.pred = 1
AutoCategory.ARW:AddRule(pred)
AutoCategory.RulesW:AddRule(pred)
equal(nil, CLM.CreateCategory(1, "predefined"), "predefined duplicate refused")
AutoCategory.saved.bags[3].rules[2] = { name = "Orphan", showpriority = 500 }
equal(nil, CLM.CreateCategory(1, "orphan"), "orphan bag entry duplicate refused")
local count = #AutoCategory.RulesW.ruleList
equal(nil, CLM.CreateCategory(99, "Missing bag"), "unknown bag refused")
equal(count, #AutoCategory.RulesW.ruleList, "unknown bag leaves no orphan rule")

-- New Tag... entry of the dropdown: the tag name input row appears
-- IN THE SAME dialog, below the edit box row; blank refused (the
-- dialog stays open), valid tag creates the category.
AutoCategory.saved.bags[8] = { rules = {} }
CLM.OpenNewCategoryDialog(8)
equal(true, newTagRow.hidden, "the tag name input row is hidden by default")
local newTagEntry = comboBoxItems[#comboBoxItems]
equal(SI_AC_MENU_CM_TAG_NEW, newTagEntry.label, "the dropdown offers New Tag")
comboBox:SelectItem(newTagEntry)
equal(false, newTagRow.hidden, "the tag name input row appears in the same dialog")
equal(true, tagEditBox.hasFocus, "the revealed input takes focus")
tagEditBox:SetText("Do not retain this tag")
comboBox:SelectItem(comboBoxItems[#comboBoxItems - 1])
equal(true, newTagRow.hidden, "switching away hides the input")
equal("", tagEditBox:GetText(), "switching away clears the draft")
comboBox:SelectItem(newTagEntry)
tagEditBox:SetText(" \t ")
local releasesBefore = releases
submit("Étiquetée")
equal(SI_AC_DIALOG_TAG_NAME_EMPTY, displayed.errorText, "blank tag refused")
equal(0, releases - releasesBefore, "blank tag keeps the dialog open")
equal(0, #AutoCategory.saved.bags[8].rules, "blank tag creates nothing")
tagEditBox:SetText("  Ma nouvelle étiquette  ")
submit("Étiquetée")
equal(1, releases - releasesBefore, "the dialog closes on success")
equal("Ma nouvelle étiquette",
    AutoCategory.GetRuleByName("Étiquetée").tag, "typed tag is applied")
equal(2, #AutoCategory.saved.bags[8].rules, "category created in captured bag")
equal(1000, AutoCategory.saved.bags[8].rules[1].showpriority,
    "tagged creation gets highest priority")
local taggedChild = AutoCategory.GetRuleByName(
    "Étiquetée " .. SI_AC_NEW_CATEGORY_EMPTY_CHILD)
equal(true, taggedChild ~= nil, "the placeholder child of a tagged category is created")
equal("Ma nouvelle étiquette", taggedChild.tag,
    "the placeholder child keeps the category's tag")
CLM.CreateCategory(8, "Sans étiquette")
equal(GetString(SI_AC_DEFAULT_NAME_EMPTY_TAG),
    AutoCategory.GetRuleByName("Sans étiquette").tag, "nil tag keeps the default")
-- the two creations above changed the rule count: re-baseline it
count = #AutoCategory.RulesW.ruleList

local factory = AutoCategory.CreateBagRule
AutoCategory.CreateBagRule = function() return nil end
equal(nil, CLM.CreateCategory(1, "Factory failure"), "failed bag factory refused")
equal(nil, AutoCategory.GetRuleByName("Factory failure"), "failure adds no global rule")
equal(nil, AutoCategory.compiledRules["Factory failure"], "failure leaves no compiled rule")
equal(1000, AutoCategory.saved.bags[1].rules[1].showpriority,
    "factory failure does not compact existing priorities")
AutoCategory.CreateBagRule = factory

-- Cancellation and a bag removed while a popup is open do not mutate state.
CLM.OpenNewCategoryDialog(1)
comboBox:SelectItem(comboBoxItems[#comboBoxItems])
tagEditBox:SetText("Cancelled tag")
nameEditBox:SetText("Cancelled name")
comboBox.open = true
ZO_Dialogs_ReleaseDialog(displayed)
equal(count, #AutoCategory.RulesW.ruleList, "cancel does not create")
equal(false, comboBox.open, "cancel closes the native dropdown")
CLM.OpenNewCategoryDialog(3)
equal("", nameEditBox:GetText(), "reopening drops the cancelled name")
equal("", tagEditBox:GetText(), "reopening drops the cancelled tag")
equal(true, newTagRow.hidden, "reopening returns to no tag")
local bag = AutoCategory.saved.bags[3]
AutoCategory.saved.bags[3] = nil
local releasedBefore = releases
submit("After removal")
equal(releasedBefore, releases, "stale bag keeps the popup open")
equal(SI_AC_DIALOG_CATEGORY_CREATE_FAILED, displayed.errorText, "stale bag explained inline")
equal(count, #AutoCategory.RulesW.ruleList, "stale bag leaves no orphan rule")
AutoCategory.saved.bags[3] = bag
ZO_Dialogs_ReleaseDialog(displayed)

-- A single hyphen remains selectable, without altering its label.
AutoCategory.RulesW.tags = { "-" }
AutoCategory.saved.bags[9] = { rules = {} }
CLM.OpenNewCategoryDialog(9)
equal("-", comboBoxItems[1].label, "hyphen tag has a literal label")
comboBox:SelectItem(comboBoxItems[1])
submit("Divider tag")
equal("-", AutoCategory.GetRuleByName("Divider tag").tag, "original tag value is preserved")

-- Highest display priority is strict, including when the old maximum
-- already equals the supported 1000. Preserve old ties and run priorities.
AutoCategory.saved.bags[5] = { rules = {
    { name = "Top A", showpriority = 1000, runpriority = 100 },
    { name = "Top B", showpriority = 1000, runpriority = 200 },
    { name = "Middle", showpriority = 700, runpriority = 300 },
    { name = "Bottom", showpriority = 2, runpriority = 400 },
} }
local otherPriority = AutoCategory.saved.bags[3].rules[1].showpriority
local first = assert(CLM.CreateCategory(5, "First created"))
local entries = AutoCategory.saved.bags[5].rules
equal(1000, entries[5].showpriority, "new category gets highest supported priority")
equal(999, entries[1].showpriority, "previous top group makes room")
equal(entries[1].showpriority, entries[2].showpriority, "old ties are preserved")
equal(true, entries[2].showpriority > entries[3].showpriority, "old group order preserved")
equal(true, entries[3].showpriority > entries[4].showpriority, "bottom remains last")
equal(100, entries[1].runpriority, "run priority untouched")
equal(otherPriority, AutoCategory.saved.bags[3].rules[1].showpriority,
    "other bag priorities are unchanged")
equal(true, CLM.CreatedThisSession["First created"] ~= nil,
    "created category marked for the session empty display")
local second = assert(CLM.CreateCategory(5, "Second created"))
equal(1000, entries[7].showpriority, "repeated creation goes to the top")
equal(999, entries[5].showpriority, "previous new category remains directly below")
equal("false", first.rule, "priority placement keeps false rule")
equal(nil, second.level, "priority placement keeps Normal level")
equal(0, windowOpens, "priority placement never opens ordering window")
equal(true, AutoCategory.CategoryTree.BuildSortKey(entries[7].showpriority, second.name)
    < AutoCategory.CategoryTree.BuildSortKey(entries[5].showpriority, first.name),
    "real inventory sort key puts newest category first")
AutoCategory.saved.bags[6] = { rules = {
    { name = "Low", runpriority = 10, showpriority = 20 },
} }
assert(CLM.CreateCategory(6, "Above low"))
equal(21, AutoCategory.saved.bags[6].rules[2].showpriority, "one above existing maximum")
equal(20, AutoCategory.saved.bags[6].rules[1].showpriority, "no compaction when room remains")
local full = {}
for i = 2, 1000 do
    full[#full + 1] = { name = "Existing " .. i, showpriority = i }
end
AutoCategory.saved.bags[7] = { rules = full }
local beforeFull = #AutoCategory.RulesW.ruleList
equal(nil, CLM.CreateCategory(7, "No room"), "full priority range fails without changing order")
equal(beforeFull, #AutoCategory.RulesW.ruleList, "capacity failure creates no rule")
equal(1000, full[#full].showpriority, "capacity failure leaves priorities unchanged")
-- Move Category Up/Down: take the display priority of the category
-- displayed just above (up: +1) or just below (down: -1) and step
-- one past it, inside the 2..1000 slider range, without touching
-- runpriority. The other categories keep their priorities.
AutoCategory.saved.bags[9] = { rules = {
    { name = "A", showpriority = 900, runpriority = 10 },
    { name = "B", showpriority = 500, runpriority = 20 },
    { name = "C", showpriority = 500, runpriority = 30 },
    { name = "D", showpriority = 100, runpriority = 40 },
} }
equal(true, CLM.CanMoveCategoryPriority(9, "B", 1), "B can move up")
equal(true, CLM.MoveCategoryPriority(9, "B", 1), "B moves up")
equal(901, AutoCategory.saved.bags[9].rules[2].showpriority,
    "B takes one above the category displayed just above")
equal(900, AutoCategory.saved.bags[9].rules[1].showpriority, "A keeps its priority")
equal(500, AutoCategory.saved.bags[9].rules[3].showpriority, "C keeps its group priority")
equal(20, AutoCategory.saved.bags[9].rules[2].runpriority, "runpriority untouched")
equal(true, CLM.MoveCategoryPriority(9, "B", -1), "B moves back down")
equal(899, AutoCategory.saved.bags[9].rules[2].showpriority,
    "B takes one below the category displayed just below")
-- B passes the whole group of its displayed neighbor
equal(true, CLM.MoveCategoryPriority(9, "B", -1), "B moves below the C group")
equal(499, AutoCategory.saved.bags[9].rules[2].showpriority, "B sits one below C")
equal(500, AutoCategory.saved.bags[9].rules[3].showpriority, "C keeps its priority")
equal(true, CLM.MoveCategoryPriority(9, "B", -1), "B moves below D")
equal(99, AutoCategory.saved.bags[9].rules[2].showpriority, "B sits one below D")
equal(100, AutoCategory.saved.bags[9].rules[4].showpriority, "D keeps its priority")
-- bounds: no displayed neighbor beyond the end of the bag, or the
-- step past the neighbor would leave the 2..1000 range
AutoCategory.saved.bags[13] = { rules = {
    { name = "Top", showpriority = 1000, runpriority = 70 },
} }
equal(false, CLM.CanMoveCategoryPriority(13, "Top", 1), "no neighbor above: cannot move up")
equal(false, CLM.MoveCategoryPriority(13, "Top", 1), "top move refused")
equal(1000, AutoCategory.saved.bags[13].rules[1].showpriority, "top unchanged")
AutoCategory.saved.bags[10] = { rules = {
    { name = "Floor", showpriority = 2, runpriority = 50 },
} }
equal(false, CLM.CanMoveCategoryPriority(10, "Floor", -1), "no neighbor below: cannot move down")
equal(false, CLM.MoveCategoryPriority(10, "Floor", -1), "floor move refused")
-- a neighbor at the range edge: the step past it is out of range
AutoCategory.saved.bags[14] = { rules = {
    { name = "Ceiling", showpriority = 1000, runpriority = 80 },
    { name = "Below", showpriority = 500, runpriority = 90 },
} }
equal(false, CLM.CanMoveCategoryPriority(14, "Below", 1), "one above a 1000 neighbor is out of range")
equal(false, CLM.MoveCategoryPriority(14, "Below", 1), "step past a 1000 neighbor refused")
AutoCategory.saved.bags[15] = { rules = {
    { name = "Floor2", showpriority = 2, runpriority = 95 },
    { name = "Above2", showpriority = 500, runpriority = 96 },
} }
equal(false, CLM.MoveCategoryPriority(15, "Above2", -1), "step past a 2 neighbor refused")
-- a category alone in the bag has no displayed neighbor to pass
AutoCategory.saved.bags[11] = { rules = {
    { name = "Solo", showpriority = 500, runpriority = 60 },
} }
equal(false, CLM.MoveCategoryPriority(11, "Solo", 1), "solo move refused: no neighbor")
equal(500, AutoCategory.saved.bags[11].rules[1].showpriority, "solo unchanged")
-- a tie-group member displayed just above: the step goes past it
AutoCategory.saved.bags[16] = { rules = {
    { name = "A1", showpriority = 500, runpriority = 97 },
    { name = "Mid", showpriority = 500, runpriority = 98 },
    { name = "Z9", showpriority = 500, runpriority = 99 },
} }
equal(true, CLM.MoveCategoryPriority(16, "Mid", 1), "tie-group neighbor move up")
equal(501, AutoCategory.saved.bags[16].rules[2].showpriority, "Mid sits just above A1")
equal(500, AutoCategory.saved.bags[16].rules[1].showpriority, "A1 unchanged")
-- a bag rule without explicit showpriority uses runpriority for
-- itself and its neighbors, and sets showpriority
AutoCategory.saved.bags[12] = { rules = {
    { name = "X", runpriority = 400 },
    { name = "Y", runpriority = 300 },
} }
equal(true, CLM.MoveCategoryPriority(12, "Y", 1), "implicit priority move")
equal(401, AutoCategory.saved.bags[12].rules[2].showpriority, "Y sits one above X")
equal(nil, AutoCategory.saved.bags[12].rules[1].showpriority, "X keeps its implicit priority")
equal(400, AutoCategory.saved.bags[12].rules[1].runpriority, "X runpriority untouched")
-- unknown rule or bag: refused, nothing changes
equal(false, CLM.MoveCategoryPriority(9, "Nulle part", 1), "unknown rule refused")
equal(false, CLM.CanMoveCategoryPriority(99, "A", 1), "unknown bag refused")

-- the neighbor search follows the VISIBLE display order of the bag,
-- read from the displayed headers: a hidden or empty category (no
-- header displayed) is never a neighbor. Each case gets its own bag:
-- a move changes the priorities, and the stubbed header order is
-- static
local function visRules()
    return {
        { name = "VisTop", showpriority = 900, runpriority = 10 },
        { name = "HiddenMid", showpriority = 500, runpriority = 20, isHidden = true },
        { name = "VisBottom", showpriority = 100, runpriority = 30 },
    }
end
AutoCategory.GetDisplayedHeaders = function(bagTypeId)
    if bagTypeId >= 17 and bagTypeId <= 21 then
        return { "VisTop", "VisBottom" }
    end
    return {}
end
-- VisBottom moves up: the neighbor is VisTop, displayed just above it;
-- the hidden HiddenMid (a higher priority than VisBottom) is skipped
AutoCategory.saved.bags[17] = { rules = visRules() }
equal(true, CLM.CanMoveCategoryPriority(17, "VisBottom", 1), "visible neighbor above")
equal(true, CLM.MoveCategoryPriority(17, "VisBottom", 1), "moves above the displayed category")
equal(901, AutoCategory.saved.bags[17].rules[3].showpriority,
    "the move takes VisTop's priority, not the hidden category's")
-- VisTop moves down: the neighbor is VisBottom, displayed just below;
-- the hidden HiddenMid between them is skipped
AutoCategory.saved.bags[18] = { rules = visRules() }
equal(true, CLM.MoveCategoryPriority(18, "VisTop", -1), "moves below the displayed category")
equal(99, AutoCategory.saved.bags[18].rules[1].showpriority,
    "the move takes VisBottom's priority, not the hidden category's")
-- VisTop cannot move up: it is the topmost displayed category
AutoCategory.saved.bags[19] = { rules = visRules() }
equal(false, CLM.CanMoveCategoryPriority(19, "VisTop", 1),
    "no displayed neighbor above the top category")
-- a hidden category itself moves relative to the displayed siblings
-- around its priority position
AutoCategory.saved.bags[20] = { rules = visRules() }
equal(true, CLM.MoveCategoryPriority(20, "HiddenMid", -1),
    "a hidden category moves relative to the displayed ones")
equal(99, AutoCategory.saved.bags[20].rules[2].showpriority,
    "the hidden category sits just below the displayed VisBottom")
-- a sub-level header is not a neighbor of a top-level category: the
-- sibling filter keeps the displayed headers of the same level only
AutoCategory.saved.bags[21] = { rules = {
    { name = "Top", showpriority = 900, runpriority = 40 },
    { name = "Top----Kid", showpriority = 500, runpriority = 50 },
    { name = "Other", showpriority = 100, runpriority = 60 },
} }
AutoCategory.GetDisplayedHeaders = function(bagTypeId)
    if bagTypeId == 21 then
        return { "Top", "Top----Kid", "Other" }
    end
    return {}
end
equal(true, CLM.MoveCategoryPriority(21, "Top", -1), "Top moves down")
equal(99, AutoCategory.saved.bags[21].rules[1].showpriority,
    "the neighbor is the displayed top-level Other, not the sub-level")
AutoCategory.GetDisplayedHeaders = nil

print("CategoryCreation_test: " .. assertions .. " assertions passed")
