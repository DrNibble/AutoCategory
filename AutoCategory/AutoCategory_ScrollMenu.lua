-- Keyboard menus used by AutoCategory. No external menu API is installed.
local Menu = {}
AutoCategory.ScrollMenu = Menu

local ROW_HEIGHT, PADDING, SEARCH_HEIGHT = 28, 6, 38
local EVENT_NAMESPACE = "AutoCategory_ScrollMenu"
local root, side, anchor, opener, tooltipRow
local sideLimit

local function clearTooltip(row)
    if tooltipRow and (not row or tooltipRow == row) then
        tooltipRow = nil
        ClearTooltip(InformationTooltip)
    end
end

local function hideSide()
    opener = nil
    if side and not side.control:IsHidden() then
        side.control:SetHidden(true)
        side.edit:LoseFocus()
        side.entries = nil
        clearTooltip()
    end
end

function Menu.Hide()
    hideSide()
    anchor = nil
    if root then root.control:SetHidden(true) end
    clearTooltip()
end

local function fillList(panel, query)
    local entries = panel.entries
    local lower = LocaleAwareToLower or string.lower
    local needle = query and lower(query:match("^%s*(.-)%s*$")) or ""
    ZO_ScrollList_Clear(panel.list)
    local items = ZO_ScrollList_GetDataList(panel.list)
    for _, entry in ipairs(entries) do
        if needle == "" or lower(entry.label):find(needle, 1, true) then
            items[#items + 1] = ZO_ScrollList_CreateDataEntry(1, entry)
        end
    end
    if #items == 0 and query then
        items[1] = ZO_ScrollList_CreateDataEntry(1, {
            label = GetString(SI_SORT_FILTER_LIST_NO_RESULTS),
        })
    end
    ZO_ScrollList_Commit(panel.list)
    ZO_ScrollList_ResetToTop(panel.list)
end

local function layout(panel, entries, limit, width, searchable)
    local searchHeight = searchable and SEARCH_HEIGHT or 0
    panel.search:SetHidden(not searchable)
    panel.list:ClearAnchors()
    panel.list:SetAnchor(TOPLEFT, panel.control, TOPLEFT, PADDING, PADDING + searchHeight)
    panel.list:SetAnchor(BOTTOMRIGHT, panel.control, BOTTOMRIGHT, -PADDING, -PADDING)
    panel.control:SetDimensions(width, math.min(#entries, limit) * ROW_HEIGHT
        + 2 * PADDING + searchHeight)
    panel.entries = entries
    fillList(panel)
end

local function openSide(row, entry)
    if opener == row or #entry.entries == 0 then return end
    hideSide()
    opener = row
    side.edit:SetText("")
    local width = root.control:GetWidth()
    layout(side, entry.entries, sideLimit, width, entry.search)
    side.control:ClearAnchors()
    local right = root.control:GetRight() + width <= GuiRoot:GetRight()
        or root.control:GetLeft() - width < GuiRoot:GetLeft()
    local x = right and root.control:GetRight() or root.control:GetLeft() - width
    side.control:SetAnchor(TOPLEFT, GuiRoot, TOPLEFT,
        x - GuiRoot:GetLeft(), row:GetTop() - GuiRoot:GetTop())
    side.control:SetHidden(false)
end

local function setupRow(panel, row, entry)
    if opener == row and row.acEntry ~= entry then hideSide() end
    clearTooltip(row)
    row.acEntry = entry
    local label = row:GetNamedChild("Label")
    local arrow = row:GetNamedChild("Arrow")
    local checkbox = row:GetNamedChild("Check")
    local slider = row:GetNamedChild("Slider")
    local valueLabel = row:GetNamedChild("Value")
    local highlight = row:GetNamedChild("Highlight")
    local kind = entry.kind
    local interactive = entry.action or entry.entries or kind == "check" or kind == "slider"
    label:SetText(entry.label or "")
    label:SetColor(1, kind == "header" and 0.83 or 1, kind == "header" and 0.45 or 1,
        (interactive or kind == "header" or kind == "text") and 1 or 0.65)
    label:ClearAnchors()
    label:SetAnchor(LEFT, row, LEFT, kind == "check" and 34 or 8, 0)
    if kind == "slider" then
        label:SetAnchor(RIGHT, slider, LEFT, -6, 0)
    else
        label:SetAnchor(RIGHT, row, RIGHT, entry.entries and -28 or -8, 0)
    end
    arrow:SetHidden(not entry.entries)
    row:GetNamedChild("Divider"):SetHidden(kind ~= "divider")
    checkbox:SetHidden(kind ~= "check")
    slider:SetHidden(kind ~= "slider")
    valueLabel:SetHidden(kind ~= "slider")
    highlight:SetHidden(true)

    local function toggle(checked)
        if row.acEntry == entry and anchor then entry.setChecked(checked) end
    end
    if kind == "check" then
        ZO_CheckButton_SetCheckState(checkbox, entry.checked())
        ZO_CheckButton_SetToggleFunction(checkbox, function(_, checked) toggle(checked) end)
    end
    -- A pooled slider must not call its old callback while being initialized.
    slider:SetHandler("OnValueChanged", nil)
    if kind == "slider" then
        local data = entry.slider.data
        slider:SetMinMax(data.min, data.max)
        slider:SetValueStep(data.step)
        local value = data.value()
        slider:SetValue(value)
        valueLabel:SetText(tostring(value))
        slider:SetHandler("OnValueChanged", function(_, current)
            if row.acEntry ~= entry or not anchor then return end
            valueLabel:SetText(tostring(math.floor(current + 0.5)))
            entry.slider.callback(current)
        end)
    end

    local function onEnter()
        if not anchor or row.acEntry ~= entry then return end
        if panel == root then
            if entry.entries then openSide(row, entry) else hideSide() end
        end
        highlight:SetHidden(not interactive)
        if entry.tooltip then
            clearTooltip()
            InitializeTooltip(InformationTooltip, row, BOTTOM, 0, -4, TOP)
            SetTooltipText(InformationTooltip, entry.tooltip)
            tooltipRow = row
        end
    end
    local function onExit()
        highlight:SetHidden(true)
        clearTooltip(row)
    end
    row:SetHandler("OnMouseEnter", onEnter)
    row:SetHandler("OnMouseExit", onExit)
    checkbox:SetHandler("OnMouseEnter", onEnter)
    checkbox:SetHandler("OnMouseExit", onExit)
    slider:SetHandler("OnMouseEnter", onEnter)
    slider:SetHandler("OnMouseExit", onExit)
    row:SetHandler("OnMouseUp", function(_, button, upInside)
        if button ~= MOUSE_BUTTON_INDEX_LEFT or not upInside or not anchor
                or row.acEntry ~= entry then return end
        if entry.entries then
            openSide(row, entry)
        elseif kind == "check" then
            local checked = not entry.checked()
            ZO_CheckButton_SetCheckState(checkbox, checked)
            toggle(checked)
        elseif entry.action then
            Menu.Hide()
            entry.action()
        end
    end)
end

local function newPanel(control)
    local panel = { control = control, list = control:GetNamedChild("List"),
        search = control:GetNamedChild("Search") }
    panel.edit = panel.search:GetNamedChild("Edit")
    ZO_ScrollList_AddDataType(panel.list, 1, "AC_ScrollMenuRow", ROW_HEIGHT,
        function(row, entry) setupRow(panel, row, entry) end,
        function(row)
            if opener == row then hideSide() end
            clearTooltip(row)
            row.acEntry = nil
        end)
    return panel
end

local function initialize()
    root = newPanel(AC_ScrollMenuRoot)
    side = newPanel(AC_ScrollMenuSide)
    side.edit:SetDefaultText(GetString(SI_GAMEPAD_BANK_SEARCH_DEFAULT_TEXT))
    side.edit:SetHandler("OnTextChanged", function(edit)
        if side.entries and not side.control:IsHidden() then
            -- The edit box is outside the list, so it keeps focus and cursor.
            fillList(side, edit:GetText())
        end
    end)
    side.edit:SetHandler("OnEscape", Menu.Hide)
    EVENT_MANAGER:RegisterForEvent(EVENT_NAMESPACE, EVENT_GLOBAL_MOUSE_UP, function()
        if anchor and not MouseIsOver(root.control)
                and (side.control:IsHidden() or not MouseIsOver(side.control)) then
            Menu.Hide()
        end
    end)
    SCENE_MANAGER:RegisterCallback("SceneStateChanged", function(_, _, newState)
        if anchor and newState == SCENE_HIDING then Menu.Hide() end
    end)
    root.control:SetHandler("OnUpdate", function()
        if anchor and anchor:IsHidden() then Menu.Hide() end
    end)
end

function Menu.Show(owner, entries, options)
    Menu.Hide()
    if #entries == 0 or owner:IsHidden() then return end
    if not root then initialize() end
    options = options or {}
    anchor = owner
    sideLimit = options.submenuRows or 15
    layout(root, entries, options.visibleRows or 15, options.width or 380, false)
    local x, y = GetUIMousePosition()
    root.control:ClearAnchors()
    root.control:SetAnchor(TOPLEFT, GuiRoot, TOPLEFT, x - GuiRoot:GetLeft(), y - GuiRoot:GetTop())
    root.control:SetHidden(false)
end
