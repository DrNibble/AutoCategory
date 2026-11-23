-- Hosted scroll lists for the category manager. The manager owns the draft;
-- the list only reports requested moves, never changes priorities itself.
local List = {}
List.__index = List
AutoCategory.OrderList = List

local ROW_HEIGHT = 25
local DEFAULT_TEXT_COLOR = { 1, 1, 1, 1 }
local moveButtons = { "First", "Up", "Down", "Last" }
local scrollboxUpTexture       = "/esoui/art/buttons/scrollbox_uparrow_%s.dds"
local scrollboxDownTexture     = "/esoui/art/buttons/scrollbox_downarrow_%s.dds"
local scrollbarEndArrowTexture = "/esoui/art/chatwindow/chat_scrollbar_endarrow_%s.dds"

local function setArrowTextures(button, name)
    local isEnd = name == "First" or name == "Last"
    local texture = isEnd and scrollbarEndArrowTexture
        or (name == "Up" and scrollboxUpTexture or scrollboxDownTexture)
    local pressed = string.format(texture, "down")
    button:SetNormalTexture(string.format(texture, "up"))
    button:SetMouseOverTexture(string.format(texture, "over"))
    button:SetPressedMouseOverTexture(pressed)
    button:SetPressedTexture(pressed)
    button:SetDisabledTexture(string.format(texture, isEnd and "disabled" or "up_disabled"))
    if name == "First" then
        -- ESO supplies the end arrow facing down. Rotate it for the first row.
        button:SetTextureCoords(1, 0, 1, 0)
    end
end

local function searchText(text)
    return (LocaleAwareToLower or string.lower)(text:match("^%s*(.-)%s*$"))
end

-- The inventory headers and the manager use the same non-interactive
-- label anchored to the mouse.
function List.ShowDragLabel(text)
    AC_OrderListDragLabel:GetNamedChild("Text"):SetText(text)
    AC_OrderListDragLabel:SetHidden(false)
    AC_OrderListDragLabel:BringWindowToTop()
end

function List.HideDragLabel()
    AC_OrderListDragLabel:SetHidden(true)
end

function List:StopDrag()
    if not self.drag then return end
    self.drag = nil
    self.host:SetHandler("OnUpdate", nil)
    EVENT_MANAGER:UnregisterForEvent(self.eventName, EVENT_GLOBAL_MOUSE_UP)
    List.HideDragLabel()
end

function List:SelectedIndices()
    local indices = {}
    for index, item in ipairs(self.items) do
        if self.selection[item.key] then indices[#indices + 1] = index end
    end
    return indices
end

function List:UpdateSelection()
    if self.onMoveSelection then
        local selected, unselected = {}, {}
        local up, down = false, false
        for _, item in ipairs(self.items) do
            local group = item.moveGroup or ""
            if self.selection[item.key] then
                selected[group] = true
                if unselected[group] then up = true end
            else
                unselected[group] = true
                if selected[group] then down = true end
            end
        end
        local enabled = { up, up, down, down }
        for i, name in ipairs(moveButtons) do
            self.arrows:GetNamedChild(name):SetEnabled(enabled[i])
        end
    end
    if self.onSelectionChanged then self.onSelectionChanged(self.selection) end
end

function List:Select(key, control, shift)
    local keep = self.selection
    local anchor = shift and self.positions[self.anchor]
    if anchor then
        local position = self.positions[key]
        if not control then keep = {} end
        for i = math.min(anchor, position), math.max(anchor, position) do
            keep[self.visible[i]] = true
        end
    else
        if not control then keep = {} end
        keep[key] = not keep[key] or nil
        self.anchor = key
    end
    self.selection, self.selected = keep, keep[key] and key or nil
    for _, visibleKey in ipairs(self.visible) do
        if not self.selected and keep[visibleKey] then self.selected = visibleKey end
        local row = self.activeRows[visibleKey]
        if row then row:GetNamedChild("Highlight"):SetHidden(not keep[visibleKey] and self.hovered ~= row) end
    end
    self:UpdateSelection()
end

function List:RevealSelection()
    local position = self.positions[self.selected]
    if position then ZO_ScrollList_ScrollDataIntoView(self.scroll, position, nil, true) end
end

function List:Move(fromIndex, toIndex)
    if not self.shown or not self.onMove or fromIndex == toIndex
            or not self.items[fromIndex] or not self.items[toIndex] then return end
    self:Select(self.items[fromIndex].key)
    self.onMove(fromIndex, toIndex)
    -- Priority moves use indices in the full draft; scrolling uses the filtered list.
    self:RevealSelection()
end

function List:StartDrag(row, data, button)
    if button ~= MOUSE_BUTTON_INDEX_LEFT or not self.onMove or not self.shown
            or #self.items < 2 or row.acOrderData ~= data
            or IsControlKeyDown() or IsShiftKeyDown() then return end
    self:StopDrag()
    self.drag = data
    ZO_Tooltips_HideTextTooltip()
    List.ShowDragLabel(row:GetNamedChild("Text"):GetText())

    local elapsed = 0
    self.host:SetHandler("OnUpdate", function()
        local time = GetFrameTimeSeconds()
        if time < elapsed then return end
        elapsed = time + 0.09
        local x, y = GetUIMousePosition()
        if x < self.scroll:GetLeft() or x > self.scroll:GetRight() then return end
        local top, bottom = self.scroll:GetTop(), self.scroll:GetBottom()
        if y >= top and y < top + ROW_HEIGHT then
            ZO_ScrollList_ScrollRelative(self.scroll, -ROW_HEIGHT, nil, true)
        elseif y <= bottom and y > bottom - ROW_HEIGHT then
            ZO_ScrollList_ScrollRelative(self.scroll, ROW_HEIGHT, nil, true)
        end
    end)
    EVENT_MANAGER:RegisterForEvent(self.eventName, EVENT_GLOBAL_MOUSE_UP, function(_, released)
        if released ~= MOUSE_BUTTON_INDEX_LEFT then return end
        local target = WINDOW_MANAGER:GetMouseOverControl()
        local targetData = target and not target:IsHidden() and target.acOrderData
        self:StopDrag()
        if targetData and targetData.list == self then self:Move(data.index, targetData.index) end
    end)
end

function List:SetupRow(row, data)
    local previous = row.acOrderData and row.acOrderData.item.key
    if previous and self.activeRows[previous] == row then self.activeRows[previous] = nil end
    row.acOrderData = data
    local item = data.item
    local text = row:GetNamedChild("Text")
    text:SetText(item.label or item.name)
    text:SetColor(unpack(item.color or DEFAULT_TEXT_COLOR))
    local highlight = row:GetNamedChild("Highlight")
    self.activeRows[item.key] = row
    highlight:SetHidden(not self.selection[item.key] and self.hovered ~= row)
    row:SetHandler("OnMouseEnter", function()
        if not self.shown or row.acOrderData ~= data then return end
        self.hovered = row
        highlight:SetHidden(false)
        if item.tooltip and not self.drag then
            ZO_Tooltips_ShowTextTooltip(row, LEFT, item.tooltip)
        end
    end)
    row:SetHandler("OnMouseExit", function()
        if self.hovered == row then self.hovered = nil end
        highlight:SetHidden(not self.selection[item.key])
        ZO_Tooltips_HideTextTooltip()
    end)
    row:SetHandler("OnMouseUp", function(_, button, upInside)
        if not self.shown or not upInside or self.drag or row.acOrderData ~= data then return end
        if button == MOUSE_BUTTON_INDEX_LEFT then
            if self.onMoveSelection then
                self:Select(item.key, IsControlKeyDown(), IsShiftKeyDown())
            end
            if item.callback then item.callback() end
        elseif button == MOUSE_BUTTON_INDEX_RIGHT and item.rightClickCallback then
            item.rightClickCallback()
        end
    end)
    row:SetHandler("OnDragStart", function(_, button) self:StartDrag(row, data, button) end)
end

function List:Render(resetScroll)
    if not self.shown then return end
    self.visible, self.positions = {}, {}
    local query = self.edit and searchText(self.edit:GetText()) or ""
    ZO_ScrollList_Clear(self.scroll)
    local rows = ZO_ScrollList_GetDataList(self.scroll)
    for index, item in ipairs(self.items) do
        if query == "" or searchText(item.name):find(query, 1, true) then
            rows[#rows + 1] = ZO_ScrollList_CreateDataEntry(1, { list = self, index = index, item = item })
            self.visible[#rows] = item.key
            self.positions[item.key] = #rows
        end
    end
    for key in pairs(self.selection) do
        if not self.positions[key] then self.selection[key] = nil end
    end
    if self.anchor and not self.positions[self.anchor] then self.anchor = nil end
    if not self.positions[self.selected] then
        self.selected = nil
        for _, key in ipairs(self.visible) do
            if self.selection[key] then self.selected = key; break end
        end
    end
    self.empty:SetHidden(#rows > 0)
    ZO_ScrollList_Commit(self.scroll)
    if resetScroll then ZO_ScrollList_ResetToTop(self.scroll) end
    self:UpdateSelection()
end

function List:SetItems(items)
    self:StopDrag()
    self.items = items
    self:Render()
end

function List:Hide()
    self:StopDrag()
    self.shown, self.selected, self.anchor, self.hovered = false, nil, nil, nil
    self.selection = {}
    if self.edit then
        self.edit:LoseFocus()
        self.edit:SetText("")
    end
    self.host:SetHidden(true)
end

function List:Show()
    self.shown = true
    self.host:SetHidden(false)
    self:Render(true)
end

function List.New(host, options)
    local self = setmetatable({
        host = host, items = {}, selection = {}, activeRows = {}, positions = {},
        onMove = options.onMove, onMoveSelection = options.onMoveSelection,
        onSelectionChanged = options.onSelectionChanged,
        scroll = host:GetNamedChild("List"), empty = host:GetNamedChild("Empty"),
        arrows = host:GetNamedChild("Arrows"), eventName = host:GetName() .. "_Drag",
    }, List)
    ZO_ScrollList_AddDataType(self.scroll, 1, "AC_OrderListRow", ROW_HEIGHT,
        function(row, data) self:SetupRow(row, data) end,
        function(row)
            local key = row.acOrderData and row.acOrderData.item.key
            if key and self.activeRows[key] == row then self.activeRows[key] = nil end
            if self.hovered == row then self.hovered = nil end
            row.acOrderData = nil
        end)
    local filter = host:GetNamedChild("Filter")
    filter:SetHidden(not options.searchable)
    self.arrows:SetHidden(not self.onMoveSelection)
    self.scroll:SetAnchor(TOPLEFT, host, TOPLEFT, 5, options.searchable and 46 or 5)
    self.scroll:SetAnchor(BOTTOMRIGHT, host, BOTTOMRIGHT, self.onMoveSelection and -41 or -5, -5)
    if options.searchable then
        self.edit = filter:GetNamedChild("Input"):GetNamedChild("Edit")
        self.edit:SetHandler("OnTextChanged", function()
            self:StopDrag()
            self:Render(true)
        end)
        filter:GetNamedChild("Reset"):SetHandler("OnClicked", function() self.edit:SetText("") end)
    end
    if self.onMoveSelection then
        for i, name in ipairs(moveButtons) do
            local button = self.arrows:GetNamedChild(name)
            setArrowTextures(button, name)
            button:SetHandler("OnClicked", function()
                if not self.shown then return end
                local indices = self:SelectedIndices()
                if #indices == 0 then return end
                local delta = i <= 2 and -1 or 1
                self.onMoveSelection(indices, delta, i == 1 or i == 4 or IsShiftKeyDown())
                self:RevealSelection()
            end)
        end
    end
    return self
end
