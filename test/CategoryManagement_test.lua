-- From AutoCategory/: lua5.1 ../test/CategoryManagement_test.lua
-- Set LSM_REPO to a LibScrollableMenu checkout to exercise actual widget code.
local checks = 0
local function equal(expected, actual, message)
    checks = checks + 1
    assert(expected == actual, (message or "unexpected value") .. ": expected "
        .. tostring(expected) .. ", got " .. tostring(actual))
end

local function definition(name, rule, predefined)
    return { name = name, rule = rule, isPredefined = function() return predefined == true end }
end
local definitions = {
    Zebra = definition("Zebra", "true"),
    Apple = definition("Apple", "quality() == ITEM_QUALITY_NORMAL", true),
    Bear = definition("Bear", "false"),
    cat = definition("cat", "isJunk()"),
    dog = definition("dog", "true"),
}
local function lookup(name) return definitions[name] end
local function bagRule(rule, value)
    return { name = rule.name, runpriority = value, showpriority = value }
end
local apple = { name = "Apple", runpriority = 60, showpriority = 17, isHidden = true }
local bear = { name = "Bear", runpriority = 30, showpriority = 105 }
local zebra = { name = "Zebra", runpriority = 10, showpriority = 49 }
local orphan = { name = "deleted", runpriority = 150, showpriority = 500 }
local other = { name = "Apple", runpriority = 900, showpriority = 9 }
local bag = { rules = { zebra, orphan, apple, bear } }
local saved = { bags = { bag, { rules = { other } } } }
local globals = { definitions.Zebra, definitions.dog, definitions.Apple, definitions.cat, definitions.Bear, definitions.cat }
AutoCategory = {
    saved = saved, GetRuleByName = lookup, CreateBagRule = bagRule,
    RulesW = { ruleList = globals },
}
GetString = function(id) return id end
ZO_Tooltips_HideTextTooltip = function() end
SI_AC_CATEGORY_MANAGER_READ_ONLY = "lecture seule"
SI_AC_CATEGORY_MANAGER_STALE = "obsolete"
dofile("AutoCategory_CategoryManagement.lua")
local M = AutoCategory.CategoryManagement
local function expect(row, name, value)
    equal(name, row.name)
    equal(value, row.priority)
end

local draft = M.NewDraft(saved, 1, lookup)
equal(3, #draft.rows, "an orphan must not be shown as a category")
expect(draft.rows[1], "Apple", 60)
expect(draft.rows[2], "Bear", 30)
expect(draft.rows[3], "Zebra", 10)
equal("cat,dog", table.concat(M.GetAvailable(draft, globals), ","), "sort and deduplicate available rules")
equal(true, M.Move(draft, 3, 1))
expect(draft.rows[1], "Zebra", 60)
expect(draft.rows[2], "Apple", 59)
expect(draft.rows[3], "Bear", 29)
equal(60, apple.runpriority, "reordering is draft only")
equal(true, M.Move(draft, 1, 2))
expect(draft.rows[1], "Apple", 59)
expect(draft.rows[2], "Zebra", 59)
expect(draft.rows[3], "Bear", 28)
equal(false, M.Add(draft, "Apple"), "duplicates are rejected")
equal(false, M.Add(draft, "not-a-rule"))
equal(true, M.Add(draft, "dog"))
expect(draft.rows[1], "dog", 1000)
equal(true, M.Remove(draft, "Bear"))
equal("Bear,cat", table.concat(M.GetAvailable(draft, globals), ","))
equal("Apple |cFF0000(lecture seule)|r\nquality() == ITEM_QUALITY_NORMAL", M.Tooltip("Apple", definitions.Apple))
equal("Zebra\ntrue", M.Tooltip("Zebra", definitions.Zebra))
equal(true, M.Commit(draft, saved, bagRule))
equal(4, #bag.rules)
equal(orphan, bag.rules[2], "unrecognized entries are preserved")
equal(59, apple.runpriority)
equal(17, apple.showpriority)
equal(true, apple.isHidden)
equal(49, zebra.showpriority)
equal(900, other.runpriority, "no edits in other inventories")
equal("dog", bag.rules[4].name)
equal(1000, bag.rules[4].runpriority)
equal(true, definitions.Apple:isPredefined(), "no edits to global definitions")

local tieSaved = { bags = { { rules = {
    bagRule(definitions.Apple, 0), bagRule(definitions.Bear, 0), bagRule(definitions.Zebra, 0),
} } } }
local tie = M.NewDraft(tieSaved, 1, lookup)
equal(true, M.Move(tie, 3, 1), "reorder even with priorities at zero")
expect(tie.rows[1], "Zebra", 1)
expect(tie.rows[2], "Apple", 0)
expect(tie.rows[3], "Bear", 0)
equal(true, M.Commit(tie, tieSaved, bagRule))
expect(M.NewDraft(tieSaved, 1, lookup).rows[1], "Zebra", 1)
equal(false, M.Commit(M.NewDraft(tieSaved, 1, lookup), tieSaved, bagRule), "no-op validation")

local stale = M.NewDraft(saved, 1, lookup)
M.Remove(stale, "Zebra")
apple.runpriority = 50
equal(nil, M.Commit(stale, saved, bagRule), "never overwrite concurrent priority changes")
equal(4, #bag.rules, "failed validation made no writes")
apple.runpriority = 59

-- Window wiring: preserve an open draft when focus changes and confirm once.
local lists, children, refreshes = {}, {}, 0
local repo = os.getenv("LSM_REPO")
local UI
if repo then UI = assert(loadfile(repo .. "/tests/order_list_box_mock.lua"))(repo) end
local layerName = "AutoCategoryCategoryManagement"
local layerActive = false
function PushActionLayerByName(name)
    equal(layerName, name)
    equal(false, layerActive, "don't stack the cancel layer")
    layerActive = true
end
function RemoveActionLayerByName(name)
    equal(layerName, name)
    layerActive = false
end
local bindingsFile = assert(io.open("Bindings.xml"))
local bindings = bindingsFile:read("*a")
bindingsFile:close()
local layer = assert(bindings:match('<Layer name="' .. layerName .. '">(.-)</Layer>'))
local bindingByAction = {}
for attributes, content in layer:gmatch("<Action ([^>]+)>(.-)</Action>") do
    local inheritedAction = assert(attributes:match('inheritsBindFrom="([^"]+)"'))
    bindingByAction[inheritedAction] = assert(loadstring(assert(content:match("<Down>(.-)</Down>")), "@Bindings.xml"))
end
local function press(action)
    local binding = bindingByAction[action]
    if not layerActive or not binding then return false end
    return binding()
end

local function control()
    return {
        hidden = true,
        SetText = function(self, value) self.text = value end,
        SetHandler = function(self, event, fn) self[event] = fn end,
        SetHidden = function(self, value)
            local wasHidden = self.hidden
            self.hidden = value
            if not wasHidden and value and self.OnEffectivelyHidden then self.OnEffectivelyHidden() end
        end,
        IsHidden = function(self) return self.hidden end,
        BringWindowToTop = function() end,
    }
end
AC_CategoryManagementWindow = UI and UI.control("AC_CategoryManagementWindow") or control()
AC_CategoryManagementWindow:SetHidden(true)
function AC_CategoryManagementWindow:GetNamedChild(name)
    if not children[name] then children[name] = UI and UI.add(self, name) or control() end
    return children[name]
end
LibScrollableMenu = LibScrollableMenu or {}
local create = LibScrollableMenu.CreateOrderListBox or function(host, options)
    local list = { host = host, options = options }
    if options.enableFilter then list.edit = control() end
    function list:SetItems(items) self.items = items end
    function list:Show() self.shown = true end
    function list:Hide() self.shown = false end
    return list
end
function LibScrollableMenu.CreateOrderListBox(host, options)
    local list = create(host, options)
    lists[#lists + 1] = list
    return list
end
local function button(key)
    if UI then children[key]:Fire("OnClicked") else children[key].OnClicked() end
end
local function rowClick(list, index, right)
    if UI then
        list.scroll.rows[index]:Fire("OnMouseUp", right and MOUSE_BUTTON_INDEX_RIGHT or MOUSE_BUTTON_INDEX_LEFT, true)
    elseif right then
        list.items[index].rightClickCallback()
    else
        list.items[index].callback()
    end
end
local function fireEdit(event, ...)
    local edit = lists[1].edit
    if UI then return edit:Fire(event, ...) end
    if edit[event] then return edit[event](edit, ...) end
end
local function refreshInventory() refreshes = refreshes + 1 end
equal(false, M.Cancel(), "a closed manager must not consume key presses")
M.Open(1, refreshInventory)
equal(true, layerActive)
equal(false, AC_CategoryManagementWindow:IsHidden())
equal(true, lists[1].shown)
equal(true, lists[2].shown)
equal(true, lists[1].options.enableFilter)
equal(true, lists[2].options.enableManualOrder)
equal(15, lists[1].options.visibleRows)
equal(15, lists[2].options.visibleRows)
equal("Bear", lists[1].items[1].name)
equal("[1000] dog", lists[2].items[1].label)
if UI then
    equal("Bear", lists[1].scroll.rows[1]:GetText())
    equal("[1000] dog", lists[2].scroll.rows[1]:GetText())
    lists[2].scroll.rows[2]:Fire("OnMouseEnter")
    equal("Apple |cFF0000(lecture seule)|r\nquality() == ITEM_QUALITY_NORMAL", UI.tooltip)
    lists[1].edit:SetText("bear")
    lists[1].edit:LoseFocus()
    equal(false, AC_CategoryManagementWindow:IsHidden())
    equal(1, #lists[1].scroll.data)
    equal("Bear", lists[1].scroll.rows[1]:GetText())
end
rowClick(lists[1], 1)
equal(4, #bag.rules, "click to add does not save")
M.Open(2, refreshInventory)
equal("cat", lists[1].items[1].name, "opening another bag keeps the pending draft")
button("Cancel")
equal(true, AC_CategoryManagementWindow:IsHidden())
equal(false, layerActive)
equal(4, #bag.rules, "cancel discards the addition")
equal(0, refreshes, "cancel doesn't refresh the inventory")

local function expectCancelled()
    equal(true, AC_CategoryManagementWindow:IsHidden())
    equal(false, layerActive)
    equal(false, lists[1].shown)
    equal(false, lists[2].shown)
    equal(4, #bag.rules, "keyboard cancel discards changes")
    equal("dog", bag.rules[4].name)
    equal(0, refreshes)
    button("Confirm")
    equal(0, refreshes, "no pending callback after cancelling")
end
for _, action in ipairs({ "TOGGLE_SYSTEM", "TOGGLE_INVENTORY" }) do
    M.Open(1, refreshInventory)
    equal("Bear", lists[1].items[1].name, "reopen restores the original draft")
    rowClick(lists[1], 1)
    equal(false, press("TOGGLE_GAME_CAMERA_UI_MODE"), "do not intercept the camera/UI shortcut")
    equal(false, AC_CategoryManagementWindow:IsHidden())
    equal(true, press(action), "consume the game key only while cancelling")
    expectCancelled()
    equal(false, press(action))
end

M.Open(1, refreshInventory)
rowClick(lists[1], 1)
local edit = lists[1].edit
edit.focused = true
edit:SetText("inventory")
fireEdit("OnKeyDown", 18, false, true, false, false)
equal(false, AC_CategoryManagementWindow:IsHidden(), "typing and raw Alt must not cancel")
equal(true, fireEdit("OnEscape"))
expectCancelled()
if UI then
    equal("", edit:GetText())
    equal(false, edit.focused)
end

M.Open(1, refreshInventory)
rowClick(lists[1], 1)
AC_CategoryManagementWindow:SetHidden(true)
expectCancelled()

M.Open(1, refreshInventory)
if UI then
    equal("", lists[1].edit:GetText())
    equal(2, #lists[1].scroll.rows)
end
rowClick(lists[1], 1)
if UI then
    rowClick(lists[2], 4)
    lists[2].buttons[1]:Fire("OnClicked")
    equal("Zebra", ZO_ScrollList_GetSelectedData(lists[2].scroll).key)
    equal("[1000] Zebra", lists[2].scroll.rows[1]:GetText())
else
    lists[2].options.onOrderChanged(nil, nil, nil, 4, 1)
end
rowClick(lists[2], 3, true)
equal(4, #bag.rules, "move and remove also stay in the draft")
button("Confirm")
equal(true, AC_CategoryManagementWindow:IsHidden())
equal(false, layerActive)
equal(1, refreshes)
equal(4, #bag.rules, "one add and one remove committed")
equal(nil, (function() for _, entry in ipairs(bag.rules) do if entry.name == "dog" then return entry end end end)())
equal("Bear", bag.rules[4].name)
equal(1000, zebra.runpriority)
button("Confirm")
equal(1, refreshes, "the same draft cannot commit twice")
print("PASS: " .. checks .. " assertions (CategoryManagement)")
