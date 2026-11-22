-- From AutoCategory/: lua5.1 ../test/ScrollMenu_test.lua
-- Load the production menu with simulated ESO controls and pooled scroll rows.
local count = 0
local function equal(expected, actual, message)
    count = count + 1
    assert(expected == actual, (message or "") .. ": expected " .. tostring(expected)
        .. ", got " .. tostring(actual))
end

TOPLEFT, BOTTOMRIGHT, TOP, BOTTOM, LEFT, RIGHT = 1, 2, 3, 4, 5, 6
MOUSE_BUTTON_INDEX_LEFT = 1
EVENT_GLOBAL_MOUSE_UP, SCENE_HIDING = 99, 7
SI_GAMEPAD_BANK_SEARCH_DEFAULT_TEXT = "Rechercher"
SI_SORT_FILTER_LIST_NO_RESULTS = "Aucun résultat"
GetString = function(id) return id end
local event, sceneStateChanged, hovered, x, y = nil, nil, nil, 50, 50
EVENT_MANAGER = { RegisterForEvent = function(_, namespace, id, callback)
    equal("AutoCategory_ScrollMenu", namespace)
    equal(EVENT_GLOBAL_MOUSE_UP, id)
    event = callback
end }
SCENE_MANAGER = { RegisterCallback = function(_, name, callback)
    equal("SceneStateChanged", name)
    sceneStateChanged = callback
end }
function MouseIsOver(control) return hovered == control end
function GetUIMousePosition() return x, y end
local tooltip
InformationTooltip = {}
function SetTooltipText(_, text) tooltip = text end
function ClearTooltip() tooltip = nil end
function InitializeTooltip(_, owner) assert(owner) end

local function control(children)
    local c = { children = children or {}, handlers = {}, hidden = true,
        text = "", x = 0, y = 0, width = 0 }
    function c:GetNamedChild(key) return assert(self.children[key], key) end
    function c:SetHandler(key, fn) self.handlers[key] = fn end
    function c:fire(key, ...) if self.handlers[key] then self.handlers[key](self, ...) end end
    function c:SetHidden(hidden) self.hidden = hidden end
    function c:IsHidden() return self.hidden end
    function c:IsControlHidden() return self.hidden end
    function c:SetDimensions(width, height) self.width, self.height = width, height end
    function c:GetWidth() return self.width end
    function c:GetLeft() return self.x end
    function c:GetRight() return self.x + self.width end
    function c:GetTop() return self.y end
    function c:ClearAnchors() end
    function c:SetAnchor(_, reference, _, offsetX, offsetY)
        self.x, self.y = reference.x + offsetX, reference.y + offsetY
    end
    function c:SetText(text)
        self.text = text
        self:fire("OnTextChanged")
    end
    function c:GetText() return self.text end
    function c:SetDefaultText(text) self.placeholder = text end
    function c:SetColor(...) self.color = { ... } end
    function c:LoseFocus() self.focus = false end
    function c:SetMinMax(min, max) self.min, self.max = min, max end
    function c:SetValueStep(step) self.step = step end
    function c:SetValue(value)
        self.value = value
        self:fire("OnValueChanged", value)
    end
    return c
end

local function panel()
    return control({ List = control(), Search = control({ Edit = control() }) })
end
local function makeRow()
    local children = {}
    for _, name in ipairs({ "Label", "Arrow", "Check", "Slider", "Value", "Highlight", "Divider" }) do
        children[name] = control()
    end
    return control(children)
end

GuiRoot = control()
GuiRoot.width = 1200
AC_ScrollMenuRoot, AC_ScrollMenuSide = panel(), panel()
function ZO_CheckButton_SetToggleFunction(check, fn) check.toggle = fn end
function ZO_CheckButton_SetCheckState(check, state) check.checked = state end
function ZO_ScrollList_AddDataType(list, id, template, height, setup, hide)
    equal(1, id)
    equal("AC_ScrollMenuRow", template)
    list.setup, list.hide, list.rowHeight, list.rows = setup, hide, height, {}
end
function ZO_ScrollList_Clear(list) list.data = {} end
function ZO_ScrollList_GetDataList(list) return list.data end
function ZO_ScrollList_CreateDataEntry(_, data) return data end
function ZO_ScrollList_ResetToTop(list) list.offset = 0 end
function ZO_ScrollList_Commit(list)
    -- Simulate freeing and reusing every row on a rebuild.
    for _, row in ipairs(list.rows) do list.hide(row) end
    for i, data in ipairs(list.data) do
        local row = list.rows[i] or makeRow()
        row.y = i * list.rowHeight
        list.rows[i] = row
        list.setup(row, data)
    end
end

AutoCategory = {}
assert(loadfile("AutoCategory_ScrollMenu.lua"))()
local menu = AutoCategory.ScrollMenu
local root, side = AC_ScrollMenuRoot, AC_ScrollMenuSide
local rlist, slist = root.children.List, side.children.List
local search = side.children.Search
local edit = search.children.Edit
local anchor = control()
anchor.hidden = false
local chosen, checked, priority, writes
writes = 0
local destinations = {}
for i = 18, 1, -1 do
    local label = ("  Destination %02d"):format(i)
    if i == 16 then label = label .. " [50%]" end
    destinations[#destinations + 1] = { label = label, action = function()
        equal(true, root.hidden, "actions run after the menu closes")
        chosen = i
    end }
end
local rows = {
    { label = "Move", search = true, entries = destinations },
    { label = "Copy", entries = {
        { label = "Bank", kind = "check", tooltip = "Overwrite",
            checked = function() return checked end,
            setChecked = function(value) checked = value end },
    } },
    { label = "Rule", entries = {
        { label = "Selected category", kind = "header" },
        { kind = "slider", label = "Priority", slider = {
            data = { min = 0, max = 1000, step = 1, value = function() return priority or 100 end },
            callback = function(value) priority, writes = value, writes + 1 end,
        } },
        { kind = "divider" }, { label = "true", kind = "text" },
    } },
    { label = "-", action = function() chosen = "hyphen" end },
}
local function click(row) row:fire("OnMouseUp", MOUSE_BUTTON_INDEX_LEFT, true) end
menu.Show(anchor, rows, { submenuRows = 15, visibleRows = 3 })
equal(false, root.hidden)
equal(3 * 28 + 12, root.height, "root is scrollable, not truncated")
equal(4, #rlist.data)
equal(true, root.children.Search.hidden)
rlist.rows[1]:fire("OnMouseEnter")
equal(false, side.hidden)
equal(root:GetRight(), side.x, "submenu opens immediately beside the root")
equal(15 * 28 + 12 + 38, side.height, "side menu has a fixed viewport plus search")
equal(18, #slist.data)
equal(false, search.hidden)
equal("Rechercher", edit.placeholder)
edit.focus, edit.cursor = true, 7
edit:SetText("  dEsTiNaTiOn 1  ")
equal(9, #slist.data)
equal("  Destination 18", slist.data[1].label, "case and indentation are preserved")
equal("  Destination 10", slist.data[9].label, "original order is preserved")
equal(4, #rlist.data, "search affects only the side menu")
equal(true, edit.focus)
equal(7, edit.cursor)
edit:SetText("none")
equal("Aucun résultat", slist.data[1].label)
click(slist.rows[1])
equal(nil, chosen)
equal(false, side.hidden)
edit:SetText("[50%]")
equal(1, #slist.data, "filter characters are literal")
click(slist.rows[1])
equal(16, chosen)
equal(true, side.hidden)
equal(false, edit.focus)
edit:SetText("stale")
equal(true, side.hidden, "a delayed edit cannot open the submenu")

x = 800
menu.Show(anchor, rows)
rlist.rows[1]:fire("OnMouseEnter")
equal(420, side.x, "open on the left when there is no room on the right")
equal("", edit.text, "reopening resets search")
edit:SetText("destination")
edit:fire("OnEscape")
equal(true, root.hidden)
menu.Show(anchor, rows)
rlist.rows[2]:fire("OnMouseEnter")
equal(true, search.hidden, "Copy has no search field")
local checkboxRow = slist.rows[1]
checkboxRow:fire("OnMouseEnter")
equal("Overwrite", tooltip)
click(checkboxRow)
equal(true, checked)
equal(false, side.hidden, "checkbox does not close the submenu")
checkboxRow.children.Check.toggle(checkboxRow.children.Check, false)
equal(false, checked, "checkbox control and row both work")
hovered = side
event()
equal(false, side.hidden, "clicks inside either menu do not dismiss it")
rlist.rows[3]:fire("OnMouseEnter")
equal(nil, tooltip, "switching submenus clears the old tooltip")
local sliderRow = slist.rows[2]
equal(100, sliderRow.children.Slider.value)
equal(0, writes, "slider initialization does not change the rule")
sliderRow.children.Slider:SetValue(333)
equal(333, priority)
equal("333", sliderRow.children.Value.text)
equal(1, writes)
rlist.rows[2]:fire("OnMouseEnter")
rlist.rows[3]:fire("OnMouseEnter")
equal(1, writes, "recycled slider is also silent when initialized")
equal(333, slist.rows[2].children.Slider.value)
hovered = nil
event()
equal(true, root.hidden, "outside click dismisses both menus")
equal(true, side.hidden)

menu.Show(anchor, rows)
rlist.rows[1]:fire("OnMouseEnter")
rlist.hide(rlist.rows[1])
equal(true, side.hidden, "scrolling the opener out closes the side menu")
click(rlist.rows[4])
equal("hyphen", chosen, "a literal hyphen is not a divider")
menu.Show(anchor, rows)
sceneStateChanged(nil, nil, SCENE_HIDING)
equal(true, root.hidden, "scene transition dismisses the menu")
menu.Show(anchor, rows)
anchor.hidden = true
root:fire("OnUpdate")
equal(true, root.hidden, "hidden inventory dismisses the menu")
menu.Show(anchor, rows)
equal(true, root.hidden, "a hidden inventory cannot open the menu")
equal(nil, LibScrollableMenu)
equal(nil, AddCustomScrollableMenuEntry)

-- The item submenu uses the same panel renderer under ESO's native
-- owning window, so a mouse-up inside the search or list does not close it.
local nativePanel, onEnter, onSelect, nativeTime
ZO_Menus, ZO_Menu = control(), control()
ZO_Menu.x, ZO_Menu.y, ZO_Menu.width, ZO_Menu.hidden = 50, 65, 200, false
ZO_Menu.items = {}
local launcher = control()
launcher.y, launcher.hidden = 115, false
MENU_ADD_OPTION_LABEL = 1
function ClearMenu() ZO_Menu.hidden = true end
function GetFrameTimeMilliseconds() return nativeTime end
function AddCustomMenuItem(label, select, itemType, _, _, _, _, _, _, enter, _, enabled)
    equal("Déplacer vers catégorie  >", label)
    equal(MENU_ADD_OPTION_LABEL, itemType)
    equal(false, enabled, "launcher click does not close the native menu")
    onEnter, onSelect = enter, select
    ZO_Menu.items[1] = { item = launcher }
    return 1
end
WINDOW_MANAGER = { CreateControlFromVirtual = function(_, name, parent, template)
    equal(ZO_Menus, parent, "the panel belongs to the native menus window")
    equal("AC_ScrollMenuNativeSide", name)
    equal("AC_ScrollMenuContents", template)
    nativePanel = panel()
    return nativePanel
end }
local acted
table.insert(destinations, 1, { label = "Disabled destination" })
destinations[2].action = function()
    equal(true, ZO_Menu.hidden, "selecting a destination closes the native context menu")
    equal(true, nativePanel.hidden, "also closes the side pane")
    acted = true
end
menu.AddNativeSubmenu("Déplacer vers catégorie", destinations)
equal(nil, nativePanel, "registering the row does not open a separate window")
onEnter(launcher)
equal(false, nativePanel.hidden, "hover opens the submenu beside the native context menu")
equal(250, nativePanel.x)
equal(115, nativePanel.y)
equal(15 * 28 + 12 + 38, nativePanel.height, "native submenu also scrolls")
local nativeList = nativePanel.children.List
local nativeEdit = nativePanel.children.Search.children.Edit
equal(19, #nativeList.data, "scrolling does not truncate destinations")
equal(0.65, nativeList.rows[1].children.Label.color[4], "unavailable destinations are dimmed")
click(nativeList.rows[1])
equal(false, nativePanel.hidden, "clicking a dimmed row does not close the menu")
hovered = nativePanel
event()
equal(false, nativePanel.hidden, "clicks inside the submenu do not dismiss it")
nativeEdit:SetText("destination 18")
equal(1, #nativeList.data, "search also works on the native submenu")
onSelect()
equal("destination 18", nativeEdit.text, "clicking the open launcher does not reset search")
hovered, nativeTime = nil, 10
nativePanel:fire("OnUpdate")
nativeTime = 130
nativePanel:fire("OnUpdate")
equal(false, nativePanel.hidden, "crossing the separator padding keeps the submenu open")
hovered = nativePanel
nativePanel:fire("OnUpdate")
click(nativeList.rows[1])
equal(true, acted)

ZO_Menu.hidden = false
onSelect()
equal(false, nativePanel.hidden, "click can open the submenu again")
equal("", nativeEdit.text)
hovered, nativeTime = nil, 300
nativePanel:fire("OnUpdate")
nativeTime = 510
nativePanel:fire("OnUpdate")
equal(true, nativePanel.hidden, "leaving the opener and panel dismisses only the submenu")
equal(false, ZO_Menu.hidden)
onEnter(launcher)
nativeEdit:fire("OnEscape")
equal(true, ZO_Menu.hidden, "Escape closes both parts")

ZO_Menu.hidden = false
onEnter(launcher)
ClearMenu()
nativePanel:fire("OnUpdate")
equal(true, nativePanel.hidden, "when ESO closes the original menu its submenu closes")
print("PASS: " .. count .. " assertions (ScrollMenu)")
