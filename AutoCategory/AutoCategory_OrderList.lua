-- Hosted scroll lists for the category manager. The manager owns the draft;
-- the list only reports requested moves, never changes priorities itself.
local List = {}
List.__index = List
AutoCategory.OrderList = List

local ROW_HEIGHT = 25
local moveButtons = { "First", "Up", "Down", "Last" }

local function searchText(text)
    return (LocaleAwareToLower or string.lower)(text:match("^%s*(.-)%s*$"))
end

function List:StopDrag()
    if not self.drag then return end
    self.drag = nil
    self.host:SetHandler("OnUpdate", nil)
    EVENT_MANAGER:UnregisterForEvent(self.eventName, EVENT_GLOBAL_MOUSE_UP)
    AC_OrderListDragLabel:SetHidden(true)
end

function List:SelectedIndex()
    if not self.selected then return end
    for index, item in ipairs(self.items) do
        if item.key == self.selected then return index end
    end
end

function List:UpdateArrows()
    if not self.onMove then return end
    local index = self:SelectedIndex()
    for i, name in ipairs(moveButtons) do
        local canMove = index and ((i <= 2 and index > 1) or (i > 2 and index < #self.items))
        self.arrows:GetNamedChild(name):SetEnabled(canMove == true)
    end
end

function List:Move(fromIndex, toIndex)
    if not self.shown or not self.onMove or fromIndex == toIndex
            or not self.items[fromIndex] or not self.items[toIndex] then return end
    self.selected = self.items[fromIndex].key
    self.onMove(fromIndex, toIndex)
    local index = self:SelectedIndex()
    if index then ZO_ScrollList_ScrollDataIntoView(self.scroll, index, nil, true) end
end

function List:StartDrag(row, data, button)
    if button ~= MOUSE_BUTTON_INDEX_LEFT or not self.onMove or not self.shown
            or #self.items < 2 or row.acOrderData ~= data then return end
    self:StopDrag()
    self.drag = data
    ZO_Tooltips_HideTextTooltip()
    AC_OrderListDragLabel:GetNamedChild("Text"):SetText(row:GetNamedChild("Text"):GetText())
    AC_OrderListDragLabel:SetHidden(false)
    AC_OrderListDragLabel:BringWindowToTop()

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
    row.acOrderData = data
    local item = data.item
    row:GetNamedChild("Text"):SetText(item.label or item.name)
    local highlight = row:GetNamedChild("Highlight")
    highlight:SetHidden(self.selected ~= item.key)
    row:SetHandler("OnMouseEnter", function()
        if not self.shown or row.acOrderData ~= data then return end
        highlight:SetHidden(false)
        if item.tooltip and not self.drag then
            ZO_Tooltips_ShowTextTooltip(row, LEFT, item.tooltip)
        end
    end)
    row:SetHandler("OnMouseExit", function()
        highlight:SetHidden(self.selected ~= item.key)
        ZO_Tooltips_HideTextTooltip()
    end)
    row:SetHandler("OnMouseUp", function(_, button, upInside)
        if not self.shown or not upInside or self.drag or row.acOrderData ~= data then return end
        if button == MOUSE_BUTTON_INDEX_LEFT then
            if self.onMove then
                local previous = self.selectedRow
                if previous and previous ~= row then previous:GetNamedChild("Highlight"):SetHidden(true) end
                self.selected, self.selectedRow = item.key, row
                highlight:SetHidden(false)
                self:UpdateArrows()
            end
            if item.callback then item.callback() end
        elseif button == MOUSE_BUTTON_INDEX_RIGHT and item.rightClickCallback then
            item.rightClickCallback()
        end
    end)
    row:SetHandler("OnDragStart", function(_, button) self:StartDrag(row, data, button) end)
    if self.selected == item.key then self.selectedRow = row end
end

function List:Render(resetScroll)
    if not self.shown then return end
    self.selectedRow = nil
    if not self:SelectedIndex() then self.selected = nil end
    local query = self.edit and searchText(self.edit:GetText()) or ""
    ZO_ScrollList_Clear(self.scroll)
    local rows = ZO_ScrollList_GetDataList(self.scroll)
    for index, item in ipairs(self.items) do
        if query == "" or searchText(item.name):find(query, 1, true) then
            rows[#rows + 1] = ZO_ScrollList_CreateDataEntry(1, { list = self, index = index, item = item })
        end
    end
    self.empty:SetHidden(#rows > 0)
    ZO_ScrollList_Commit(self.scroll)
    if resetScroll then ZO_ScrollList_ResetToTop(self.scroll) end
    self:UpdateArrows()
end

function List:SetItems(items)
    self:StopDrag()
    self.items = items
    self:Render()
end

function List:Hide()
    self:StopDrag()
    self.shown, self.selected, self.selectedRow = false, nil, nil
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
        host = host, items = {}, onMove = options.onMove,
        scroll = host:GetNamedChild("List"), empty = host:GetNamedChild("Empty"),
        arrows = host:GetNamedChild("Arrows"), eventName = host:GetName() .. "_Drag",
    }, List)
    ZO_ScrollList_AddDataType(self.scroll, 1, "AC_OrderListRow", ROW_HEIGHT,
        function(row, data) self:SetupRow(row, data) end,
        function(row)
            if self.selectedRow == row then self.selectedRow = nil end
            row.acOrderData = nil
        end)
    local filter = host:GetNamedChild("Filter")
    filter:SetHidden(not options.searchable)
    self.arrows:SetHidden(not self.onMove)
    self.scroll:SetAnchor(TOPLEFT, host, TOPLEFT, 5, options.searchable and 46 or 5)
    self.scroll:SetAnchor(BOTTOMRIGHT, host, BOTTOMRIGHT, self.onMove and -41 or -5, -5)
    if options.searchable then
        self.edit = filter:GetNamedChild("Input"):GetNamedChild("Edit")
        self.edit:SetHandler("OnTextChanged", function() self:Render(true) end)
        filter:GetNamedChild("Reset"):SetHandler("OnClicked", function() self.edit:SetText("") end)
    end
    if self.onMove then
        for i, name in ipairs(moveButtons) do
            self.arrows:GetNamedChild(name):SetHandler("OnClicked", function()
                local index = self:SelectedIndex()
                if not index then return end
                local target
                if i == 1 or (i == 2 and IsShiftKeyDown()) then target = 1
                elseif i == 4 or (i == 3 and IsShiftKeyDown()) then target = #self.items
                else target = index + (i == 2 and -1 or 1) end
                self:Move(index, target)
            end)
        end
    end
    return self
end
