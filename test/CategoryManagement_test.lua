-- From AutoCategory/: lua5.1 ../test/CategoryManagement_test.lua
-- Exercises the actual hosted list code with simulated ESO UI controls.
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
local lists, refreshes = {}, 0
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

local function control(name)
    local c = { hidden = true, name = name, children = {}, handlers = {}, text = "" }
    function c:Fire(event, ...) if self.handlers[event] then return self.handlers[event](self, ...) end end
    function c:SetText(value) self.text = value; self:Fire("OnTextChanged") end
    function c:GetText() return self.text end
    function c:GetName() return self.name end
    function c:SetHandler(event, fn) self.handlers[event] = fn end
    function c:SetHidden(value)
        local wasHidden = self.hidden
        self.hidden = value
        if not wasHidden and value then self:Fire("OnEffectivelyHidden") end
    end
    function c:IsHidden() return self.hidden end
    function c:BringWindowToTop() end
    function c:LoseFocus() self.focused = false end
    function c:SetEnabled(value) self.enabled = value end
    function c:SetNormalTexture(value) self.normalTexture = value end
    function c:SetMouseOverTexture(value) self.mouseOverTexture = value end
    function c:SetPressedMouseOverTexture(value) self.pressedMouseOverTexture = value end
    function c:SetPressedTexture(value) self.pressedTexture = value end
    function c:SetDisabledTexture(value) self.disabledTexture = value end
    function c:SetTextureCoords(...) self.textureCoords = table.concat({ ... }, ",") end
    function c:SetAnchor(point, _, _, x, y) self[point] = { x, y } end
    function c:GetLeft() return 0 end
    function c:GetRight() return 350 end
    function c:GetTop() return 0 end
    function c:GetBottom() return 375 end
    function c:GetNamedChild(key)
        if not self.children[key] then self.children[key] = control(self.name .. key) end
        return self.children[key]
    end
    return c
end

TOPLEFT, BOTTOMRIGHT, LEFT = 1, 2, 3
MOUSE_BUTTON_INDEX_LEFT, MOUSE_BUTTON_INDEX_RIGHT = 1, 2
EVENT_GLOBAL_MOUSE_UP = 99
local mouseOver, events, shift, tooltip = nil, {}, false, nil
local pointerX, pointerY = 10, 365
EVENT_MANAGER = {}
function EVENT_MANAGER:RegisterForEvent(key, id, callback)
    equal(EVENT_GLOBAL_MOUSE_UP, id)
    events[key] = callback
end
function EVENT_MANAGER:UnregisterForEvent(key, id)
    equal(EVENT_GLOBAL_MOUSE_UP, id)
    events[key] = nil
end
WINDOW_MANAGER = { GetMouseOverControl = function() return mouseOver end }
function IsShiftKeyDown() return shift end
function GetUIMousePosition() return pointerX, pointerY end
function GetFrameTimeSeconds() return 1 end
function ZO_Tooltips_ShowTextTooltip(_, _, text) tooltip = text end
function ZO_Tooltips_HideTextTooltip() tooltip = nil end
function ZO_ScrollList_AddDataType(list, id, template, height, setup, hide)
    equal(1, id)
    equal("AC_OrderListRow", template)
    list.height, list.setup, list.hide, list.rows = height, setup, hide, {}
end
function ZO_ScrollList_CreateDataEntry(_, data) return data end
function ZO_ScrollList_Clear(list) list.data = {} end
function ZO_ScrollList_GetDataList(list) return list.data end
function ZO_ScrollList_ResetToTop(list) list.offset = 0 end
function ZO_ScrollList_ScrollDataIntoView(list, index) list.revealed = index end
function ZO_ScrollList_ScrollRelative(list, delta) list.offset = (list.offset or 0) + delta end
function ZO_ScrollList_Commit(list)
    for _, row in ipairs(list.rows) do list.hide(row); row:SetHidden(true) end
    for i, data in ipairs(list.data) do
        local row = list.rows[i] or control(list.name .. i)
        list.rows[i] = row
        list.setup(row, data)
        row:SetHidden(false)
    end
end

AC_CategoryManagementWindow = control("Manager")
AC_OrderListDragLabel = control("DragLabel")
dofile("AutoCategory_OrderList.lua")
local create = AutoCategory.OrderList.New
function AutoCategory.OrderList.New(host, options)
    local list = create(host, options)
    lists[#lists + 1] = list
    return list
end
local function button(key)
    return AC_CategoryManagementWindow:GetNamedChild(key):Fire("OnClicked")
end
local function rowClick(list, index, right)
    list.scroll.rows[index]:Fire("OnMouseUp", right and MOUSE_BUTTON_INDEX_RIGHT or MOUSE_BUTTON_INDEX_LEFT, true)
end
local function drag(list, index, target)
    list.scroll.rows[index]:Fire("OnDragStart", MOUSE_BUTTON_INDEX_LEFT)
    equal(false, AC_OrderListDragLabel:IsHidden())
    local offset = list.scroll.offset or 0
    list.host:Fire("OnUpdate", 1)
    equal(offset + 25, list.scroll.offset, "holding near the lower edge scrolls")
    local release = assert(events[list.eventName])
    mouseOver = target
    release(EVENT_GLOBAL_MOUSE_UP, MOUSE_BUTTON_INDEX_RIGHT)
    equal(false, AC_OrderListDragLabel:IsHidden(), "right release does not end a left drag")
    release(EVENT_GLOBAL_MOUSE_UP, MOUSE_BUTTON_INDEX_LEFT)
    equal(true, AC_OrderListDragLabel:IsHidden())
    equal(nil, events[list.eventName], "drag handler is removed")
    mouseOver = nil
end
local function refreshInventory() refreshes = refreshes + 1 end
equal(false, M.Cancel(), "a closed manager must not consume key presses")
M.Open(1, refreshInventory)
equal(true, layerActive)
equal(false, AC_CategoryManagementWindow:IsHidden())
equal(true, lists[1].shown)
equal(true, lists[2].shown)
equal(true, lists[1].edit ~= nil, "available list has search")
equal(nil, lists[2].edit, "present list does not filter reorder indices")
equal(25, lists[1].scroll.height)
equal(25, lists[2].scroll.height)
equal(46, lists[1].scroll[TOPLEFT][2], "space for the search box")
for _, spec in ipairs({
    { "First", "/esoui/art/chatwindow/chat_scrollbar_endarrow_", "disabled", "1,0,1,0" },
    { "Up", "/esoui/art/buttons/scrollbox_uparrow_", "up_disabled" },
    { "Down", "/esoui/art/buttons/scrollbox_downarrow_", "up_disabled" },
    { "Last", "/esoui/art/chatwindow/chat_scrollbar_endarrow_", "disabled" },
}) do
    local button = lists[2].arrows:GetNamedChild(spec[1])
    local prefix = spec[2]
    equal(prefix .. "up.dds", button.normalTexture, spec[1] .. " normal")
    equal(prefix .. "over.dds", button.mouseOverTexture, spec[1] .. " hovered")
    equal(prefix .. "down.dds", button.pressedTexture, spec[1] .. " pressed")
    equal(prefix .. "down.dds", button.pressedMouseOverTexture, spec[1] .. " pressed while hovered")
    equal(prefix .. spec[3] .. ".dds", button.disabledTexture, spec[1] .. " disabled")
    equal(spec[4], button.textureCoords, spec[1] .. " orientation")
end
equal("Bear", lists[1].items[1].name)
equal("[1000] dog", lists[2].items[1].label)
local function rowText(list, index) return list.scroll.rows[index]:GetNamedChild("Text"):GetText() end
equal("Bear", rowText(lists[1], 1))
equal("[1000] dog", rowText(lists[2], 1))
lists[2].scroll.rows[2]:Fire("OnMouseEnter")
equal("Apple |cFF0000(lecture seule)|r\nquality() == ITEM_QUALITY_NORMAL", tooltip)
lists[1].edit:SetText("  bEAr ")
lists[1].edit:LoseFocus()
equal(false, AC_CategoryManagementWindow:IsHidden())
equal(1, #lists[1].scroll.data)
equal("Bear", rowText(lists[1], 1))
lists[1].edit:SetText("[missing%]")
equal(0, #lists[1].scroll.data)
equal(false, lists[1].empty.hidden, "show no-results state")
lists[1].host:GetNamedChild("Filter"):GetNamedChild("Reset"):Fire("OnClicked")
equal(2, #lists[1].scroll.data, "reset restores all categories")
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
edit:Fire("OnKeyDown", 18, false, true, false, false)
equal(false, AC_CategoryManagementWindow:IsHidden(), "typing and raw Alt must not cancel")
equal(true, edit:Fire("OnEscape"))
expectCancelled()
equal("", edit:GetText())
equal(false, edit.focused)

M.Open(1, refreshInventory)
rowClick(lists[1], 1)
lists[2].scroll.rows[4]:Fire("OnDragStart", MOUSE_BUTTON_INDEX_LEFT)
equal(false, AC_OrderListDragLabel.hidden)
AC_CategoryManagementWindow:SetHidden(true)
equal(true, AC_OrderListDragLabel.hidden, "closing cancels an active drag")
equal(nil, events[lists[2].eventName])
expectCancelled()

M.Open(1, refreshInventory)
equal("", lists[1].edit:GetText())
equal(2, #lists[1].scroll.data)
local present = lists[2]
rowClick(lists[1], 1)
drag(present, 4, lists[1].scroll.rows[1])
equal("Zebra", present.items[4].key, "dropping in the available list does not reorder")
drag(present, 4, present.scroll.rows[1])
equal("Zebra", present.items[1].key, "dragging reorders the draft")
equal("Zebra", present.selected)
equal(1, present.scroll.revealed)
equal(false, present.arrows:GetNamedChild("First").enabled, "first row cannot move up")
equal(true, present.arrows:GetNamedChild("Down").enabled)
present.arrows:GetNamedChild("Down"):Fire("OnClicked")
equal("Zebra", present.items[2].key, "Down moves a category one position")
shift = true
present.arrows:GetNamedChild("Down"):Fire("OnClicked")
shift = false
equal("Zebra", present.items[4].key, "Shift+Down moves to the end")
equal(false, present.arrows:GetNamedChild("Last").enabled)
equal(true, M.Cancel(), "discard the reorder tests before verifying the commit")

M.Open(1, refreshInventory)
rowClick(lists[1], 1)
rowClick(present, 4)
present.arrows:GetNamedChild("First"):Fire("OnClicked")
equal("Zebra", present.selected, "the selected category stays selected")
equal("[1000] Zebra", rowText(present, 1))
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
equal(nil, LibScrollableMenu)
print("PASS: " .. checks .. " assertions (CategoryManagement)")
