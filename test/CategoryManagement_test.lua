-- From AutoCategory/: lua5.1 ../test/CategoryManagement_test.lua
-- Exercises the actual hosted list code with simulated ESO UI controls.
local checks = 0
local function equal(expected, actual, message)
    checks = checks + 1
    assert(expected == actual, (message or "unexpected value") .. ": expected "
        .. tostring(expected) .. ", got " .. tostring(actual))
end

local function definition(name, rule, predefined)
    return {
        name = name, rule = rule, key = function(self) return self.name end,
        isPredefined = function() return predefined == true end,
    }
end
local definitions = {
    Zebra = definition("Zebra", "true"),
    Apple = definition("Apple", "quality() == ITEM_QUALITY_NORMAL", true),
    Bear = definition("Bear", "false"),
    cat = definition("cat", "isJunk()"),
    dog = definition("dog", "true"),
}
local function lookup(name) return definitions[name] end
local function bagRule(rule, value, shown)
    return { name = type(rule) == "table" and rule.name or rule, runpriority = value, showpriority = shown or value }
end
local apple = { name = "Apple", runpriority = 60, showpriority = 17, isHidden = true }
local bear = { name = "Bear", runpriority = 30, showpriority = 105 }
local zebra = { name = "Zebra", runpriority = 10, showpriority = 49 }
local orphan = { name = "deleted", runpriority = 150, showpriority = 500 }
local other = { name = "Apple", runpriority = 900, showpriority = 9 }
local bag = { rules = { zebra, orphan, apple, bear } }
local saved = { bags = { bag, { rules = { other } } } }
local globals = { definitions.Zebra, definitions.dog, definitions.Apple, definitions.cat, definitions.Bear, definitions.cat }
local inventoryList = {}
local inventoryHeaders = { "Apple", "Zebra" }
local bagIds = { 1, 2, 3, 4, 5, 6, 7, 8 }
local bagNames = { "Inventaire", "Banque", "Banque de guilde", "Sac d’artisanat",
    "Atelier", "Coffre de maison", "Coffre de mobilier", "Vengeance" }
AutoCategory = {
    saved = saved, GetRuleByName = lookup, CreateBagRule = bagRule,
    cache = { bags_cvt = { choices = bagNames, choicesValues = bagIds } },
    RulesW = { ruleList = globals },
    GetCategorySortName = function() end,
    GetDisplayedHeaders = function(bagId, sourceList)
        if bagId == 1 and sourceList == inventoryList then return inventoryHeaders end
    end,
}
GetString = function(id) return id end
ZO_Tooltips_HideTextTooltip = function() end
SI_AC_CATEGORY_MANAGER_READ_ONLY = "lecture seule"
SI_AC_CATEGORY_MANAGER_STALE = "obsolete"
SI_AC_CATEGORY_MANAGER_SWITCH_BAG = "save or cancel before switching"
SI_AC_CATEGORY_MANAGER_CREATE_PENDING = "save or cancel before creating"
SI_AC_MENU_CM_NEW_CATEGORY = "Nouvelle catégorie"
SI_AC_CATEGORY_MANAGER_ATTACH = "Attacher à une catégorie"
SI_AC_CATEGORY_MANAGER_COPY_PENDING = "Copie en attente"
SI_AC_MENU_CM_REMOVE_DISPLAY = "Supprimer l’affichage"
SI_AC_MENU_CM_COPY_SUBMENU = "Copier vers"
SI_AC_MENU_CM_COPY_SELECTED = "Copier la sélection"
SI_AC_TIP_CM_COPY_OVERWRITE = "Remplace les catégories présentes"
SI_AC_TIP_LEVEL = "Niveau : %d"
SI_AC_MENU_CM_LEVEL_SHALLOWER = "Relever ←"
SI_AC_MENU_CM_LEVEL_DEEPER = "Abaisser →"
SI_AC_MENU_BS_SLIDER_CATEGORY_RUNPRIORITY = "Priorité d'exécution"
SI_AC_MENU_BS_SLIDER_CATEGORY_SHOWPRIORITY = "Priorité d'affichage"
LibSFUtils = { safeCall = pcall }
dofile("AutoCategory_Tree.lua")
dofile("AutoCategory_LevelMenu.lua")
dofile("PredefinedLayouts.lua")
dofile("AutoCategory_API.lua")
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
local bindingsFile = assert(io.open("XML/Bindings.xml"))
local bindings = bindingsFile:read("*a")
bindingsFile:close()
local layer = assert(bindings:match('<Layer name="' .. layerName .. '">(.-)</Layer>'))
local bindingByAction = {}
for attributes, content in layer:gmatch("<Action ([^>]+)>(.-)</Action>") do
    local inheritedAction = assert(attributes:match('inheritsBindFrom="([^"]+)"'))
    bindingByAction[inheritedAction] = assert(loadstring(assert(content:match("<Down>(.-)</Down>")), "@XML/Bindings.xml"))
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
    function c:SetColor(...) self.color = table.concat({ ... }, ",") end
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

TOPLEFT, BOTTOMRIGHT, LEFT, TOP = 1, 2, 3, 4
MOUSE_BUTTON_INDEX_LEFT, MOUSE_BUTTON_INDEX_RIGHT = 1, 2
EVENT_GLOBAL_MOUSE_UP = 99
local mouseOver, events, shift, ctrl, tooltip = nil, {}, false, false, nil
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
function IsControlKeyDown() return ctrl end
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
local inventoryCombo = { items = {} }
function inventoryCombo:SetSortsItems(sort)
    equal(false, sort, "preserve the addon’s inventory order")
end
function inventoryCombo:ClearItems() self.items, self.selected = {}, nil end
function inventoryCombo:CreateItemEntry(name, callback, enabled)
    return { name = name, callback = callback, enabled = enabled }
end
function inventoryCombo:AddItem(entry) self.items[#self.items + 1] = entry end
function inventoryCombo:SelectItem(entry, ignoreCallback)
    if not entry or not entry.enabled then return false end
    local oldItem = self.selected
    self.selected = entry
    if not ignoreCallback then entry.callback(self, entry.name, entry, oldItem ~= entry, oldItem) end
    return true
end
function inventoryCombo:HideDropdown() self.open = false end
function ZO_ComboBox_ObjectFromContainer(container)
    equal(AC_CategoryManagementWindow:GetNamedChild("Inventory"), container)
    return inventoryCombo
end
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
local menuRows, menuOwner
AutoCategory.ScrollMenu = {
    Hide = function() menuRows, menuOwner = nil, nil end,
    Show = function(owner, rows, options)
        equal(MOUSE_BUTTON_INDEX_RIGHT, options.openerButton)
        menuRows, menuOwner = rows, owner
    end,
}
local function menuEntry(label, rows)
    for _, entry in ipairs(rows or menuRows) do
        if entry.label == label then return entry end
    end
end
local function chooseMenu(entry)
    AutoCategory.ScrollMenu.Hide()
    assert(entry, "menu entry missing").action()
end
local function removeViaMenu(list, index)
    rowClick(list, index, true)
    chooseMenu(menuEntry(SI_AC_MENU_CM_REMOVE_DISPLAY))
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
M.Open(1, refreshInventory, inventoryList)
equal(true, layerActive)
equal(false, AC_CategoryManagementWindow:IsHidden())
equal(true, lists[1].shown)
equal(true, lists[2].shown)
equal(true, lists[1].edit ~= nil, "available list has search")
equal(true, lists[2].edit ~= nil, "present list has an independent search")
equal(25, lists[1].scroll.height)
equal(25, lists[2].scroll.height)
equal(46, lists[1].scroll[TOPLEFT][2], "space for the search box")
equal(46, lists[2].scroll[TOPLEFT][2])
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
local function rowColor(list, index) return list.scroll.rows[index]:GetNamedChild("Text").color end
local normal, grey, red = "1,1,1,1", "0.65,0.65,0.65,1", "1,0.35,0.35,1"
local present = lists[2]
local shallower = AC_CategoryManagementWindow:GetNamedChild("Shallower")
local deeper = AC_CategoryManagementWindow:GetNamedChild("Deeper")
equal(false, shallower.enabled, "no level controls without a selection")
equal(false, deeper.enabled)
equal("Bear", rowText(lists[1], 1))
equal("[1000] dog", rowText(lists[2], 1))
equal(normal, rowColor(lists[1], 1), "the left list is unchanged")
equal(grey, rowColor(present, 1), "no matching inventory header")
equal(red, rowColor(present, 2), "the explicit hidden flag wins even when a header is drawn")
equal(normal, rowColor(present, 3), "a displayed category keeps the normal color")
lists[2].scroll.rows[2]:Fire("OnMouseEnter")
equal("Apple |cFF0000(lecture seule)|r\nquality() == ITEM_QUALITY_NORMAL", tooltip)
lists[1].edit:SetText("  bEAr ")
lists[1].edit:LoseFocus()
equal(false, AC_CategoryManagementWindow:IsHidden())
equal(1, #lists[1].scroll.data)
equal("Bear", rowText(lists[1], 1))
present.edit:SetText("   A   ")
equal(2, #present.scroll.data)
equal("[59] Apple", rowText(present, 1))
equal("[59] Zebra", rowText(present, 2))
equal(red, rowColor(present, 1), "a recycled grey row takes its new item's color")
equal(normal, rowColor(present, 2), "a recycled red row resets to the default color")
equal("  bEAr ", lists[1].edit:GetText(), "the right filter does not change the left filter")
drag(present, 2, present.scroll.rows[1])
equal("dog", present.items[1].key, "a filtered drag uses actual draft indices")
equal("Zebra", present.items[2].key)
equal(1, present.scroll.revealed, "scroll to the filtered index, not the draft index")
present.arrows:GetNamedChild("Down"):Fire("OnClicked")
equal("Zebra", present.items[3].key, "priority arrows still move in the full list")
equal(2, present.scroll.revealed)
present.scroll.rows[2]:Fire("OnDragStart", MOUSE_BUTTON_INDEX_LEFT)
present.edit:SetText("1000")
equal(true, AC_OrderListDragLabel:IsHidden(), "changing filter cancels an active drag")
equal(nil, events[present.eventName])
equal(0, #present.scroll.data, "priorities aren't included in the search")
equal(false, present.empty.hidden)
equal(nil, present.selected)
equal(false, deeper.enabled, "no level edits on a hidden selection")
equal(false, present.arrows:GetNamedChild("First").enabled)
present.host:GetNamedChild("Filter"):GetNamedChild("Reset"):Fire("OnClicked")
equal(3, #present.scroll.data)
equal(true, present.empty.hidden)
equal(nil, present.selected)
lists[1].edit:SetText("[missing%]")
equal(0, #lists[1].scroll.data)
equal(false, lists[1].empty.hidden, "show no-results state")
lists[1].host:GetNamedChild("Filter"):GetNamedChild("Reset"):Fire("OnClicked")
equal(2, #lists[1].scroll.data, "reset restores all categories")
rowClick(lists[1], 1)
equal(4, #bag.rules, "click to add does not save")
M.Open(2, refreshInventory)
equal("cat", lists[1].items[1].name, "opening another bag keeps the pending draft")
equal("Inventaire", inventoryCombo.selected.name, "the context menu did not switch an open draft")
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
removeViaMenu(lists[2], 3)
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

-- A real subtree: the visible category, its child, and an invisible placeholder
-- all follow the shared level rules. The parent is chosen by display priority.
definitions.Apple.pred = 1
definitions.Bear.level, definitions.Bear.parent = 2, "Apple"
definitions.cat.level, definitions.cat.parent, definitions.cat.rule = 3, "Bear", "false"
local hidden = { name = "cat", runpriority = 20, showpriority = 20, isHidden = true }
local root = { name = "Apple", runpriority = 70, showpriority = 10 }
local child = { name = "Bear", runpriority = 50, showpriority = 90 }
local sibling = { name = "Zebra", runpriority = 40, showpriority = 25 }
local levelBag = { rules = { root, child, sibling, hidden } }
local levelSaved = { bags = { levelBag, { rules = { other } } } }
AutoCategory.saved = levelSaved
local syncs, overrides = 0, nil
AutoCategory.SyncPredefinedLayouts = function()
    syncs = syncs + 1
    overrides = AutoCategory.PredefinedLayouts.Collect(globals)
end

inventoryHeaders = { "Apple", "Apple----Bear", "Zebra" }
M.Open(1, refreshInventory, inventoryList)
equal("[70] Apple", rowText(present, 1))
equal("   [50] Bear", rowText(present, 2))
equal("      [20] cat", rowText(present, 4))
equal(normal, rowColor(present, 2), "the inventory path of a nested category is recognized")
equal(red, rowColor(present, 4), "a hidden category without a header is red rather than grey")
shallower:Fire("OnMouseEnter")
equal("Relever ←", tooltip)
shallower:Fire("OnMouseExit")
equal(nil, tooltip)
deeper:Fire("OnMouseEnter")
equal("Abaisser →", tooltip)
present.edit:SetText("  APP  ")
rowClick(present, 1)
equal(true, deeper.enabled)
button("Deeper")
equal("   [70] Apple", rowText(present, 1))
equal("Apple", present.selected, "the selected category stays selected while filtering and shifting")
equal("  APP  ", present.edit:GetText())
present.edit:SetText("")
equal("      [50] Bear", rowText(present, 2))
equal(normal, rowColor(present, 2), "level changes in the draft do not change actual inventory visibility")
equal("         [20] cat", rowText(present, 4))
button("Deeper")
equal("      [70] Apple", rowText(present, 1))
equal("            [20] cat", rowText(present, 4))
equal(false, deeper.enabled, "a level-5 child blocks another increase")
button("Deeper")
equal("      [70] Apple", rowText(present, 1), "even a direct call can't go beyond the bound")
equal(true, shallower.enabled)
button("Shallower")
button("Shallower")
equal("[70] Apple", rowText(present, 1))
equal("   [50] Bear", rowText(present, 2))
equal("      [20] cat", rowText(present, 4))
button("Deeper")
present.edit.focused = true
present.edit:SetText("app")
equal(true, present.edit:Fire("OnEscape"), "Escape in the right filter cancels the draft")
equal("", present.edit:GetText())
equal(false, present.edit.focused)
equal(false, layerActive)
equal(nil, definitions.Apple.level)
equal(nil, definitions.Apple.parent)
equal(2, definitions.Bear.level)
equal(3, definitions.cat.level)
equal(0, syncs, "cancel doesn't save predefined changes")
equal(1, refreshes, "cancel doesn't refresh the inventory")

inventoryHeaders = { "Apple", "Zebra" }
M.Open(1, function()
    equal(1, syncs, "update predefined overrides before refreshing")
    refreshInventory()
end, inventoryList)
equal("[70] Apple", rowText(present, 1))
equal(grey, rowColor(present, 2), "a child whose header is not displayed is grey")
rowClick(present, 3)
equal(false, shallower.enabled, "a top-level Normal category without children cannot be raised")
rowClick(present, 1)
button("Deeper")
button("Confirm")
equal(true, AC_CategoryManagementWindow:IsHidden(), "level-only apply closes")
equal(2, refreshes)
equal(1, syncs)
equal(2, overrides.Apple.level)
equal("Zebra", overrides.Apple.parent, "use the display priority, not the manager sort")
equal(3, definitions.Bear.level)
equal("Apple", definitions.Bear.parent)
equal(4, definitions.cat.level)
equal(true, hidden.isHidden)
equal(70, root.runpriority, "layout edits do not change execution priority")
equal(10, root.showpriority, "layout edits do not change display priority")
equal(other, levelSaved.bags[2].rules[1], "layout changes leave other bag entries intact")
equal(900, other.runpriority)

M.Open(1, refreshInventory)
rowClick(present, 1)
button("Shallower")
removeViaMenu(present, 3)
definitions.Bear.level = 4
button("Confirm")
equal(false, AC_CategoryManagementWindow:IsHidden(), "reject a stale layout before saving")
equal("obsolete", AC_CategoryManagementWindow:GetNamedChild("Status"):GetText())
equal(4, #levelBag.rules, "reject both layout and membership changes atomically")
equal(2, definitions.Apple.level)
equal(4, definitions.Bear.level, "do not overwrite an external edit")
equal(1, syncs)
equal(2, refreshes)
equal(true, M.Cancel())
definitions.Bear.level = 3

local projected = M.NewDraft(levelSaved, 1, lookup)
equal(true, M.ShiftLevel(projected, "Apple", -1))
equal(true, M.Remove(projected, "Zebra"))
equal(true, M.Add(projected, "dog"))
equal(true, M.ShiftLevel(projected, "Apple", 1))
equal("dog", projected.getLayout("Apple").parent, "parent candidates follow the draft's additions and removals")
sibling.showpriority = 26
equal(nil, M.Commit(projected, levelSaved, bagRule), "reject a stale display priority used to pick parents")
equal("Zebra", definitions.Apple.parent)
equal(4, #levelBag.rules)

inventoryHeaders = {}
M.Open(1, refreshInventory, inventoryList)
equal(grey, rowColor(present, 1), "a known empty inventory has no displayed categories")
rowClick(present, 1)
equal("Apple", present.selected, "grey rows stay selectable")
rowClick(present, 4)
equal("cat", present.selected, "red rows stay selectable")
equal(true, M.Cancel())

local function selectedKeys()
    local keys = {}
    for _, item in ipairs(present.items) do
        if present.selection[item.key] then keys[#keys + 1] = item.key end
    end
    return table.concat(keys, ",")
end
local function modifiedClick(index, control, range)
    ctrl, shift = control, range
    rowClick(present, index)
    ctrl, shift = false, false
end
local function presentedKeys()
    local keys = {}
    for _, item in ipairs(present.items) do keys[#keys + 1] = item.key end
    return table.concat(keys, ",")
end
local function priorityArrow(key)
    present.arrows:GetNamedChild(key):Fire("OnClicked")
end
local function orderTab(key)
    local control = AC_CategoryManagementWindow:GetNamedChild("PresentTitle"):GetNamedChild(key)
    control:Fire("OnClicked")
end

M.Open(1, refreshInventory, inventoryList)
rowClick(present, 1)
modifiedClick(3, true, false)
equal("Apple,Zebra", selectedKeys(), "Ctrl+click adds a disjoint row")
equal(false, present.scroll.rows[1]:GetNamedChild("Highlight"):IsHidden())
equal(true, present.scroll.rows[2]:GetNamedChild("Highlight"):IsHidden())
equal(false, present.scroll.rows[3]:GetNamedChild("Highlight"):IsHidden())
modifiedClick(1, true, false)
equal("Zebra", selectedKeys(), "Ctrl+click toggles a selected row off")
modifiedClick(2, false, true)
equal("Apple,Bear", selectedKeys(), "Shift uses the last clicked anchor and replaces the selection")
modifiedClick(4, true, true)
equal("Apple,Bear,Zebra,cat", selectedKeys(), "Ctrl+Shift adds a range")
equal(false, present.arrows:GetNamedChild("Up").enabled)
rowClick(present, 4)
modifiedClick(2, false, true)
equal("Bear,Zebra,cat", selectedKeys(), "Shift also selects a range upwards")

rowClick(present, 1)
modifiedClick(3, true, false)
priorityArrow("Up")
equal("Apple,Zebra,Bear,cat", presentedKeys(), "each selected run moves one step without reversing the group")
equal("Apple,Zebra", selectedKeys(), "reordering preserves selected keys")
priorityArrow("Last")
equal("Bear,cat,Apple,Zebra", presentedKeys(), "moving to the edge is a stable partition")
equal("Apple,Zebra", selectedKeys())
equal(70, root.runpriority, "batch execution reorder is draft only")
equal(true, M.Cancel())

M.Open(1, refreshInventory, inventoryList)
rowClick(lists[1], 1) -- dog, the only available category, enters at the top
equal("dog,Apple,Bear,Zebra,cat", presentedKeys())
rowClick(present, 1)
modifiedClick(5, false, true)
present.edit:SetText("a")
equal("Apple,Bear,Zebra,cat", selectedKeys(), "filter clears only selections that disappear")
rowClick(present, 1)
modifiedClick(3, false, true)
equal("Apple,Bear,Zebra", selectedKeys(), "ranges use filtered order")
present.edit:SetText("")
equal("Apple,Bear,Zebra", selectedKeys(), "reset does not reselect filtered-out rows")
equal(true, M.Cancel())

definitions.cat.parent = "Apple" -- two nested siblings, with a common parent under Zebra
M.Open(1, refreshInventory)
orderTab("Display")
equal("Zebra,Apple,Bear,cat", presentedKeys(), "higher-priority children stay below their parent")
equal("Zebra", rowText(present, 1), "display order has no numeric priority prefix")
equal("      Bear", rowText(present, 3), "display order still indents nested categories")
rowClick(present, 2)
equal(false, present.arrows:GetNamedChild("Down").enabled, "a parent cannot move down into its own branch")
drag(present, 2, present.scroll.rows[4])
equal("Zebra,Apple,Bear,cat", presentedKeys(), "dragging across parents does not edit the layout")
rowClick(present, 4)
modifiedClick(1, true, false)
priorityArrow("Up")
equal("Zebra,Apple,Bear,cat", presentedKeys(), "a selected ancestor carries its selected descendant without reordering it")
rowClick(present, 4)
priorityArrow("Up")
equal("Zebra,Apple,cat,Bear", presentedKeys(), "each selected category moves only among its own siblings")
equal("      cat", rowText(present, 3))
equal(26, sibling.showpriority, "display moves remain draft-only")
orderTab("Run")
equal("Apple,Bear,Zebra,cat", presentedKeys(), "display edits leave execution order untouched")
equal("   [70] Apple", rowText(present, 1), "execution priority still shows its numeric prefix")
equal("cat", selectedKeys(), "changing tabs preserves selection by key")
button("Confirm")
equal(true, AC_CategoryManagementWindow:IsHidden())
equal(3, refreshes)
equal(40, sibling.runpriority)
equal(26, sibling.showpriority, "reordering children does not edit the root's priority")
equal(10, root.showpriority, "reordering children does not edit the parent's priority")
equal(true, hidden.showpriority > child.showpriority, "Apply saves the new sibling order")
equal(1, syncs, "priority-only edits don't save predefined layouts")

local staleDisplay = M.NewDraft(levelSaved, 1, lookup)
staleDisplay.displayOrder = true
equal(true, M.MoveSelection(staleDisplay, { 4 }, -1, false))
root.showpriority = root.showpriority + 1
equal(nil, M.Commit(staleDisplay, levelSaved, bagRule), "display changes won't overwrite a stale order")

definitions.Apple.level, definitions.Apple.parent = nil, nil
definitions.Bear.level, definitions.Bear.parent = 2, "Apple"
definitions.cat.level, definitions.cat.parent = 3, "Bear"
local branches = M.NewDraft(levelSaved, 1, lookup)
equal(true, M.ShiftSelection(branches, { Apple = true, Bear = true, Zebra = true }, 1))
equal(2, branches.getLayout("Apple").level)
equal(3, branches.getLayout("Bear").level, "selected child follows its parent just once")
equal(4, branches.getLayout("cat").level, "unselected descendants follow their parent")
equal(2, branches.getLayout("Zebra").level, "an independent branch moves too")
equal(nil, branches.getLayout("Apple").parent, "do not attach to another moving branch")
equal(nil, branches.getLayout("Zebra").parent, "do not create cycles with moving peers")
equal(nil, definitions.Apple.level, "level selection remains a draft")
branches.getLayout("cat").level = 5
equal(false, M.ShiftSelection(branches, { Apple = true, Zebra = true }, 1))
equal(2, branches.getLayout("Zebra").level, "a level limit rejects the whole operation")
equal(true, M.ShiftSelection(branches, { Apple = true, Bear = true, Zebra = true }, -1))
equal(nil, branches.getLayout("Apple").level)
equal(2, branches.getLayout("Bear").level)
equal(4, branches.getLayout("cat").level)

M.Open(1, refreshInventory)
rowClick(present, 1)
modifiedClick(3, false, true)
button("Deeper")
equal("Apple,Bear,Zebra", selectedKeys(), "changing levels keeps the multi-selection")
equal("   [70] Apple", rowText(present, 1))
equal("      [50] Bear", rowText(present, 2))
equal("   [40] Zebra", rowText(present, 3))
equal(true, M.Cancel())
equal(nil, definitions.Apple.level)
equal(2, definitions.Bear.level)

-- Compare real inventory sort keys for siblings, not just the manager labels.
local siblingBag = { rules = {
    bagRule(definitions.Apple, 102, 80), bagRule(definitions.Zebra, 101, 60), bagRule(definitions.dog, 100, 40),
} }
local siblingSaved = { bags = { siblingBag } }
AutoCategory.saved = siblingSaved
local displayDraft = M.NewDraft(siblingSaved, 1, lookup)
displayDraft.displayOrder = true
local resolve = AutoCategory.MakeBagRuleDisplayResolver(1)
local function sortKey(bagrule)
    local _, key = resolve(bagrule)
    return key
end
equal(true, sortKey(siblingBag.rules[1]) < sortKey(siblingBag.rules[2]))
equal(true, M.MoveSelection(displayDraft, { 2, 3 }, -1, true))
equal(true, M.Commit(displayDraft, siblingSaved, bagRule))
resolve = AutoCategory.MakeBagRuleDisplayResolver(1)
equal(true, sortKey(siblingBag.rules[2]) < sortKey(siblingBag.rules[3]))
equal(true, sortKey(siblingBag.rules[3]) < sortKey(siblingBag.rules[1]))
equal(102, siblingBag.rules[1].runpriority)
equal(101, siblingBag.rules[2].runpriority)
equal(100, siblingBag.rules[3].runpriority)

local nestedSaved = { bags = {
    { rules = { bagRule(definitions.Bear, 800), bagRule(definitions.Zebra, 500),
        bagRule(definitions.Apple, 100), bagRule(definitions.cat, 900) } },
    { rules = {} },
} }
AutoCategory.saved = nestedSaved
local function names(rows)
    local order = {}
    for _, row in ipairs(rows) do order[#order + 1] = row.name end
    return table.concat(order, ",")
end
local nestedDraft = M.NewDraft(nestedSaved, 1, lookup)
nestedDraft.displayOrder = true
equal("Zebra,Apple,Bear,cat", names(M.OrderedRows(nestedDraft)), "the branch uses the parent's priority")
equal(true, M.Move(nestedDraft, 2, 1), "dragging root siblings moves the entire branch")
equal("Apple,Bear,cat,Zebra", names(M.OrderedRows(nestedDraft)))
equal(true, M.Commit(nestedDraft, nestedSaved, bagRule))
local nestedRules = nestedSaved.bags[1].rules
resolve = AutoCategory.MakeBagRuleDisplayResolver(1)
equal(true, sortKey(nestedRules[3]) < sortKey(nestedRules[1]))
equal(true, sortKey(nestedRules[1]) < sortKey(nestedRules[4]))
equal(true, sortKey(nestedRules[4]) < sortKey(nestedRules[2]))
equal(800, nestedRules[1].showpriority, "the child's priority does not change when its parent moves")
equal(900, nestedRules[4].showpriority, "the grandchild's priority stays unchanged too")

-- Run the real item matcher and compare its sorted paths to the draft.
local matchingSlot
AutoCategory.setChecking = function(_, _, slot) matchingSlot = slot end
AutoCategory.SetCategoryCollapsed = function() end
AutoCategory.IsCategoryCollapsed = function() return false end
AutoCategory.CategorySortNames = {}
AutoCategory.compiledRules = {}
for _, entry in ipairs(nestedRules) do
    AutoCategory.compiledRules[entry.name] = function() return matchingSlot == entry.name end
end
local matchedHeaders = {}
for _, entry in ipairs(nestedRules) do
    local matched, path, _, _, _, _, key = AutoCategory:MatchCategoryRules(1, entry.name, 1)
    equal(true, matched)
    matchedHeaders[#matchedHeaders + 1] = { path = path, key = key }
end
table.sort(matchedHeaders, function(a, b) return a.key < b.key end)
for i, path in ipairs({ "Apple", "Apple----Bear", "Apple----Bear----cat", "Zebra" }) do
    equal(path, matchedHeaders[i].path, "item sort places headers in the manager's order")
end

local layoutPreview = M.NewDraft(nestedSaved, 1, lookup)
layoutPreview.displayOrder = true
layoutPreview.getLayout("Bear").parent = "Zebra"
equal("Apple,Zebra,Bear,cat", names(M.OrderedRows(layoutPreview)), "preview uses unsaved parent changes")
equal("Apple", definitions.Bear.parent)
equal(true, M.Remove(layoutPreview, "Zebra"))
equal("Bear,cat,Apple", names(M.OrderedRows(layoutPreview)), "a branch can use an implicit parent absent from every bag")
nestedSaved.bags[2].rules[1] = nestedRules[2]
local _, previewInfo = M.OrderedRows(layoutPreview)
for row, info in pairs(previewInfo) do
    if row.name == "Bear" then equal(1, info.depth, "a parent exclusive to another bag does not add indentation") end
end

-- Exercise the bag selector through its real callbacks, including an empty bag.
local selectorSaved = { bags = {} }
selectorSaved.bags[1] = { rules = { bagRule(definitions.Apple, 50), bagRule(definitions.Zebra, 60) } }
selectorSaved.bags[2] = { rules = { bagRule(definitions.Bear, 70) } }
for i = 3, #bagIds do selectorSaved.bags[i] = { rules = {} } end
AutoCategory.saved = selectorSaved
inventoryHeaders = { "Apple" }
M.Open(1, refreshInventory, inventoryList)
equal(#bagNames, #inventoryCombo.items, "include all bag types")
for i, name in ipairs(bagNames) do
    equal(name, inventoryCombo.items[i].name, "use the localized list in its given order")
    equal(true, inventoryCombo.items[i].enabled, "empty inventories are selectable too")
end
equal("Inventaire", inventoryCombo.selected.name, "preselect the context-menu inventory")
equal("Zebra,Apple", presentedKeys())
equal(grey, rowColor(present, 1), "only Apple has a header in the originating list")
rowClick(present, 2)
orderTab("Display")
lists[1].edit:SetText("xyz")
present.edit:SetText("apple")
inventoryCombo:SelectItem(inventoryCombo.items[2])
equal("Banque", inventoryCombo.selected.name)
equal("Bear", presentedKeys())
equal("", lists[1].edit:GetText(), "the left search does not carry over to the new inventory")
equal("", present.edit:GetText())
equal("", selectedKeys())
equal(normal, rowColor(present, 1), "do not color another bag from the originating list")
equal(false, AC_CategoryManagementWindow:GetNamedChild("PresentTitle"):GetNamedChild("Display").enabled,
    "keep the selected priority mode")
inventoryCombo:SelectItem(inventoryCombo.items[3])
equal("Banque de guilde", inventoryCombo.selected.name)
equal("", presentedKeys())
inventoryCombo:SelectItem(inventoryCombo.items[1])
equal(grey, rowColor(present, 1), "returning to the original bag restores its visibility colors")

removeViaMenu(present, 1)
inventoryCombo:SelectItem(inventoryCombo.items[2])
equal("Inventaire", inventoryCombo.selected.name, "restore the dropdown when a switch is blocked")
equal("Apple", presentedKeys(), "the unsaved removal remains in the draft")
equal("save or cancel before switching", AC_CategoryManagementWindow:GetNamedChild("Status"):GetText())
equal(2, #selectorSaved.bags[1].rules, "switching does not save anything")
inventoryCombo.open = true
equal(true, M.Cancel())
equal(false, inventoryCombo.open, "close the dropdown with the window")

M.Open(3, refreshInventory)
equal("Banque de guilde", inventoryCombo.selected.name, "reopen on the newly right-clicked bag")
inventoryCombo:SelectItem(inventoryCombo.items[1])
rowClick(present, 2)
priorityArrow("Up")
inventoryCombo:SelectItem(inventoryCombo.items[2])
equal("Inventaire", inventoryCombo.selected.name, "priority-only edits also block switching")
equal(true, M.Cancel())

local previousRefreshes = refreshes
M.Open(2, refreshInventory)
inventoryCombo:SelectItem(inventoryCombo.items[3])
rowClick(lists[1], 1)
button("Confirm")
equal(previousRefreshes + 1, refreshes)
equal(1, #selectorSaved.bags[3].rules, "apply writes to the selected bag")
equal(1, #selectorSaved.bags[2].rules, "the bag that opened the window is untouched")
equal("Bear", selectorSaved.bags[2].rules[1].name)

-- Branch operations in Display Priority and the manager's right-click actions.
local contextSaved = { bags = {
    { rules = { bagRule(definitions.Zebra, 80), bagRule(definitions.Apple, 50),
        bagRule(definitions.Bear, 95), bagRule(definitions.cat, 90), bagRule(definitions.dog, 10) } },
    { rules = {} }, { rules = {} },
} }
AutoCategory.saved = contextSaved
local levelLabel = AC_CategoryManagementWindow:GetNamedChild("Level")
local function clickName(name, right, add)
    for index, key in ipairs(present.visible) do
        if key == name then
            ctrl = add == true
            rowClick(present, index, right)
            ctrl = false
            return present.scroll.rows[index]
        end
    end
    error("visible row not found: " .. name)
end

M.Open(1, refreshInventory)
orderTab("Display")
equal("", levelLabel:GetText(), "no level without a selection")
equal("Zebra,Apple,Bear,cat,dog", presentedKeys())
clickName("Apple")
equal("Niveau : 1", levelLabel:GetText())
clickName("Bear", false, true)
equal("1 / 2", levelLabel:GetText(), "mixed selections show the different levels")
priorityArrow("Up")
equal("Apple,Bear,cat,Zebra,dog", presentedKeys(), "moving up carries children and grandchildren")
priorityArrow("Down")
equal("Zebra,Apple,Bear,cat,dog", presentedKeys(), "moving down keeps the same branch together")
button("Deeper")
equal("   Apple", rowText(present, 2))
equal("      Bear", rowText(present, 3))
equal("         cat", rowText(present, 4))
equal("2 / 3", levelLabel:GetText())
button("Shallower")
equal("Apple", rowText(present, 2))
equal("   Bear", rowText(present, 3))
equal("      cat", rowText(present, 4))
equal("1 / 2", levelLabel:GetText())
equal(nil, definitions.Apple.level, "arrow operations do not save before Apply")

clickName("dog", false, true)
local owner = clickName("Apple", true)
equal(owner, menuOwner)
equal("Apple,Bear,dog", selectedKeys(), "right-clicking a selected row preserves the selection")
equal("Zebra,Apple,Bear,cat,dog", presentedKeys(), "right-click does not remove categories")
local attach = menuEntry(SI_AC_CATEGORY_MANAGER_ATTACH)
equal(true, attach.search)
equal(1, #attach.entries, "cannot attach to selected categories or their descendants")
chooseMenu(menuEntry("Zebra", attach.entries))
equal("   Apple", rowText(present, 2))
equal("      Bear", rowText(present, 3))
equal("         cat", rowText(present, 4))
equal("   dog", rowText(present, 5))
clickName("Apple", true)
local copies = menuEntry(SI_AC_MENU_CM_COPY_SUBMENU).entries
local bankChoice, guildChoice = menuEntry("Banque", copies), menuEntry("Banque de guilde", copies)
equal("check", bankChoice.kind)
equal(false, bankChoice.checked())
bankChoice.setChecked(true)
guildChoice.setChecked(true)
chooseMenu(menuEntry(SI_AC_MENU_CM_COPY_SELECTED, copies))
equal(0, #contextSaved.bags[2].rules, "the checkbox submenu queues a draft copy")
equal(0, #contextSaved.bags[3].rules)
equal("Copie en attente", AC_CategoryManagementWindow:GetNamedChild("Status"):GetText())
button("Confirm")
equal("Zebra", definitions.Apple.parent)
equal("Zebra", definitions.dog.parent)
equal("Apple", definitions.Bear.parent)
equal("Bear", definitions.cat.parent)
equal(4, definitions.cat.level)
equal(5, #contextSaved.bags[2].rules, "copy the selected branches and their ancestor only once")
equal(5, #contextSaved.bags[3].rules, "copy to all checked destinations")

M.Open(1, refreshInventory)
orderTab("Display")
clickName("Apple", true)
equal("Apple", selectedKeys(), "right-clicking an unselected row selects only that row")
chooseMenu(menuEntry(SI_AC_MENU_CM_REMOVE_DISPLAY))
equal("Zebra,Bear,cat,dog", presentedKeys())
equal("   Bear", rowText(present, 2), "remaining children are promoted under the removed category's parent")
equal("      cat", rowText(present, 3))
equal(5, #contextSaved.bags[1].rules)
equal(true, M.Cancel())
equal("Apple", definitions.Bear.parent, "Cancel discards the removal and promotion")

M.Open(1, refreshInventory)
clickName("Apple", true)
copies = menuEntry(SI_AC_MENU_CM_COPY_SUBMENU).entries
bankChoice = menuEntry("|cFF5555Banque|r", copies)
equal(SI_AC_TIP_CM_COPY_OVERWRITE, bankChoice.tooltip)
bankChoice.setChecked(true)
chooseMenu(menuEntry(SI_AC_MENU_CM_COPY_SELECTED, copies))
local destination = contextSaved.bags[2].rules[1]
destination.showpriority = 7
button("Confirm")
equal(false, AC_CategoryManagementWindow:IsHidden(), "a stale destination blocks Apply")
equal("obsolete", AC_CategoryManagementWindow:GetNamedChild("Status"):GetText())
equal(7, destination.showpriority, "no external destination changes are overwritten")
equal(true, M.Cancel())

do
    local clm = AutoCategory.CategoryLevelMenu
    local originalOpen = clm.OpenNewCategoryDialog
    local calls, finish, refuse = 0, nil, false
    clm.OpenNewCategoryDialog = function(bagId, parent, callback)
        calls = calls + 1
        equal(2, bagId, "create in the selected inventory, not the opening inventory")
        equal(nil, parent, "creating from the manager does not preselect a parent")
        equal(true, AC_CategoryManagementWindow:IsHidden(), "the higher-tier manager must be hidden")
        equal(false, layerActive, "keyboard shortcuts no longer go to the manager")
        if refuse then return end
        finish = callback
        return {}
    end

    M.Open(1, refreshInventory)
    equal("Nouvelle catégorie", AC_CategoryManagementWindow:GetNamedChild("NewCategory"):GetText(),
        "reuse the existing translation")
    removeViaMenu(present, 1)
    button("NewCategory")
    equal(0, calls, "creation must not overwrite pending manager changes")
    equal("save or cancel before creating", AC_CategoryManagementWindow:GetNamedChild("Status"):GetText())
    equal(5, #contextSaved.bags[1].rules, "the dirty draft is not saved by opening the dialog")
    equal(4, #present.items, "the draft changes are still present")
    M.Cancel()

    M.Open(1, refreshInventory)
    inventoryCombo:SelectItem(inventoryCombo.items[2])
    orderTab("Display")
    present.edit:SetText("app")
    refuse = true
    button("NewCategory")
    equal(1, calls)
    equal(false, AC_CategoryManagementWindow:IsHidden(), "restore the manager if ESO cannot show the dialog")
    equal(true, layerActive)

    refuse = false
    inventoryCombo.open = true
    button("NewCategory")
    equal(2, calls)
    equal(false, inventoryCombo.open)
    M.Open(3, refreshInventory)
    equal(true, AC_CategoryManagementWindow:IsHidden(), "do not reopen over an active dialog")
    equal(false, M.Cancel(), "a hidden manager does not consume cancel")
    finish(false)
    equal(false, AC_CategoryManagementWindow:IsHidden(), "return after cancelling creation")
    equal(true, layerActive)
    equal("Banque", inventoryCombo.selected.name)
    equal("app", present.edit:GetText(), "preserve the search filter")

    local added = definition("New category", "false")
    button("NewCategory")
    definitions[added.name], globals[#globals + 1] = added, added
    table.insert(contextSaved.bags[2].rules, bagRule(added, 1000, 1000))
    finish(true)
    equal(false, AC_CategoryManagementWindow:IsHidden(), "return after successful creation")
    equal(true, layerActive)
    equal("Banque", inventoryCombo.selected.name)
    equal("app", present.edit:GetText(), "refreshing the lists preserves the filter")
    present.edit:SetText("")
    equal("New category", rowText(present, 1), "the new row appears in the retained display-priority tab")
    button("Confirm")
    equal(true, AC_CategoryManagementWindow:IsHidden(), "the refreshed draft is not stale")
    equal(false, layerActive)
    clm.OpenNewCategoryDialog = originalOpen
end

equal(nil, LibScrollableMenu)
print("PASS: " .. checks .. " assertions (CategoryManagement)")
