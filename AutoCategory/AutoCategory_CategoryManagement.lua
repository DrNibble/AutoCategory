local AC = AutoCategory
local CLM = AC.CategoryLevelMenu
local Management = {}
AC.CategoryManagement = Management

local MAX_PRIORITY = 1000
local ABSENT_COLOR = { 0.65, 0.65, 0.65, 1 }
local HIDDEN_COLOR = { 1, 0.35, 0.35, 1 }
local function priority(value)
    value = tonumber(value)
    if not value then return 0 end
    return math.min(MAX_PRIORITY, math.max(0, math.floor(value)))
end

local function displayPriority(row)
    return priority(row.showpriority or row.priority)
end

local function byPriority(a, b)
    if a.priority ~= b.priority then return a.priority > b.priority end
    return a.name < b.name
end

function Management.NewDraft(saved, bagId, getRule)
    local bag = saved and saved.bags and saved.bags[bagId]
    if not bag or not bag.rules then return end
    local draft = {
        saved = saved, bagId = bagId, bag = bag, rules = bag.rules, getRule = getRule,
        rows = {}, original = {}, snapshot = {}, layouts = {}, count = #bag.rules,
    }
    -- The same rules are shared by all inventories. Only edit copies in the draft.
    draft.getLayout = function(name)
        local layout = draft.layouts[name]
        if not layout then
            local rule = getRule(name)
            if not rule then return end
            layout = {
                rule = rule, level = rule.level, parent = rule.parent,
                copy = { name = rule.name, level = rule.level, parent = rule.parent },
            }
            draft.layouts[name] = layout
        end
        return layout.copy
    end
    for _, entry in ipairs(bag.rules) do
        draft.snapshot[entry] = draft.snapshot[entry] or {
            name = entry.name, runpriority = entry.runpriority, showpriority = entry.showpriority, count = 0,
        }
        draft.snapshot[entry].count = draft.snapshot[entry].count + 1
        if not draft.original[entry.name] and draft.getLayout(entry.name) then
            local row = { name = entry.name, priority = priority(entry.runpriority), showpriority = entry.showpriority }
            draft.original[entry.name] = {
                priority = row.priority, showpriority = entry.showpriority, entry = entry,
            }
            draft.rows[#draft.rows + 1] = row
        end
    end
    table.sort(draft.rows, byPriority)
    return draft
end

function Management.GetAvailable(draft, definitions)
    local names, present = {}, {}
    for _, row in ipairs(draft.rows) do present[row.name] = true end
    for _, definition in ipairs(definitions) do
        local name = definition.name
        if name and name ~= "" and not present[name] then
            names[#names + 1] = name
            present[name] = true
        end
    end
    local lower = LocaleAwareToLower or string.lower
    table.sort(names, function(a, b)
        local first, second = lower(a), lower(b)
        if first ~= second then return first < second end
        return a < b
    end)
    return names
end

function Management.Add(draft, name)
    if not draft.getLayout(name) then return false end
    for _, row in ipairs(draft.rows) do if row.name == name then return false end end
    local original = draft.original[name]
    local value = original and original.priority or MAX_PRIORITY
    draft.rows[#draft.rows + 1] = { name = name, priority = value, showpriority = original and original.showpriority }
    table.sort(draft.rows, byPriority)
    return true
end

function Management.Remove(draft, name)
    for i, row in ipairs(draft.rows) do
        if row.name == name then
            table.remove(draft.rows, i)
            return true
        end
    end
    return false
end

function Management.OrderedRows(draft)
    local ordered = {}
    for i, row in ipairs(draft.rows) do ordered[i] = row end
    if draft.displayOrder then
        table.sort(ordered, function(a, b)
            local first, second = displayPriority(a), displayPriority(b)
            if first ~= second then return first > second end
            return a.name < b.name
        end)
    end
    return ordered
end

local function applyOrder(draft, rows, values)
    for i = 2, #rows do
        -- Equal priorities are allowed only when the game's tie-breaker
        -- would keep these two categories in the requested order.
        local step = rows[i - 1].name < rows[i].name and 0 or 1
        values[i] = math.min(values[i], values[i - 1] - step)
    end
    local minimum = draft.displayOrder and 2 or 0
    -- Repair underflow from the bottom without clamping away a user's move.
    for i = #rows, 1, -1 do
        values[i] = math.max(values[i], minimum)
        if i < #rows then
            local step = rows[i].name < rows[i + 1].name and 0 or 1
            values[i] = math.max(values[i], values[i + 1] + step)
        end
    end
    if values[1] > MAX_PRIORITY then return false end
    if draft.displayOrder then
        for i, row in ipairs(rows) do
            if displayPriority(row) ~= values[i] then row.showpriority = values[i] end
        end
    else
        for i, row in ipairs(rows) do row.priority = values[i] end
        draft.rows = rows
    end
    return true
end

local function orderPriority(draft, row)
    return draft.displayOrder and displayPriority(row) or row.priority
end

function Management.Move(draft, fromIndex, toIndex)
    local rows = Management.OrderedRows(draft)
    if fromIndex == toIndex or not rows[fromIndex] or not rows[toIndex] then return false end

    local values = {}
    local moved = table.remove(rows, fromIndex)
    local targetPriority = orderPriority(draft, rows[fromIndex < toIndex and toIndex - 1 or toIndex])
    table.insert(rows, toIndex, moved)
    for i, row in ipairs(rows) do
        local value = orderPriority(draft, row)
        values[i] = i < toIndex and value or (i == toIndex and targetPriority or value - 1)
    end
    return applyOrder(draft, rows, values)
end

function Management.MoveSelection(draft, indices, delta, toEdge)
    local rows = Management.OrderedRows(draft)
    local count = #rows
    if #indices == 0 or (delta ~= -1 and delta ~= 1) then return end
    if #indices == 1 then
        local index = indices[1]
        local target = toEdge and (delta == -1 and 1 or count) or index + delta
        if target == index or not rows[target] then return end
        return Management.Move(draft, index, target)
    end

    local selected, values, changed = {}, {}, false
    for _, index in ipairs(indices) do selected[rows[index]] = true end
    for i, row in ipairs(rows) do values[i] = orderPriority(draft, row) end
    if toEdge then
        local first, last = {}, {}
        local selectedFirst = delta == -1
        for _, row in ipairs(rows) do
            local group = (selected[row] == true) == selectedFirst and first or last
            group[#group + 1] = row
        end
        for _, row in ipairs(last) do first[#first + 1] = row end
        for i, row in ipairs(first) do
            if row ~= rows[i] then changed = true; break end
        end
        rows = first
    else
        local first, last = 2, count
        if delta == 1 then first, last = count - 1, 1 end
        for i = first, last, -delta do
            local other = i + delta
            if selected[rows[i]] and not selected[rows[other]] then
                rows[i], rows[other] = rows[other], rows[i]
                changed = true
            end
        end
    end
    if changed then return applyOrder(draft, rows, values) end
end

local function planLevels(draft, selected)
    local bagRules = {}
    for _, row in ipairs(draft.rows) do
        bagRules[#bagRules + 1] = {
            name = row.name, runpriority = row.priority,
            showpriority = row.showpriority,
        }
    end
    local roots, covered, moving, subtrees = {}, {}, {}, {}
    for _, row in ipairs(draft.rows) do
        if selected[row.name] then
            local subtree = CLM.SubtreeInRules(bagRules, row.name, draft.getLayout)
            roots[#roots + 1] = subtree
            for i = 2, #subtree do covered[subtree[i].rule.name] = true end
        end
    end
    for _, subtree in ipairs(roots) do
        if not covered[subtree[1].rule.name] then
            subtrees[#subtrees + 1] = subtree
            for _, entry in ipairs(subtree) do
                if moving[entry.rule.name] then return {}, bagRules, moving end
                moving[entry.rule.name] = true
            end
        end
    end
    return subtrees, bagRules, moving
end

local function canShiftLevels(subtrees, delta)
    if #subtrees == 0 or (delta ~= -1 and delta ~= 1) then return false end
    local canShift = delta == 1 and CLM.CanIncrease or CLM.CanDecrease
    for _, subtree in ipairs(subtrees) do
        if not canShift(subtree) then return false end
    end
    return true
end

function Management.ShiftSelection(draft, selected, delta)
    local subtrees, bagRules, moving = planLevels(draft, selected)
    if not canShiftLevels(subtrees, delta) then return false end
    for _, subtree in ipairs(subtrees) do
        CLM.ShiftRuleLevels(bagRules, subtree, delta, draft.getLayout, moving)
    end
    return true
end

function Management.ShiftLevel(draft, name, delta)
    return Management.ShiftSelection(draft, { [name] = true }, delta)
end

-- Return nil if this bag, its priorities or a layout dependency is stale.
-- Keep the original entries (and all unrelated fields) for retained rules.
function Management.Commit(draft, saved, createBagRule)
    local bag = saved and saved.bags and saved.bags[draft.bagId]
    if saved ~= draft.saved or bag ~= draft.bag or bag.rules ~= draft.rules
            or #bag.rules ~= draft.count then return nil end
    local seen, displayOrderChanged = {}, false
    for _, entry in ipairs(bag.rules) do
        local prior = draft.snapshot[entry]
        seen[entry] = (seen[entry] or 0) + 1
        if not prior or prior.name ~= entry.name or prior.runpriority ~= entry.runpriority
                or seen[entry] > prior.count then
            return nil
        end
        if prior.showpriority ~= entry.showpriority then displayOrderChanged = true end
    end

    local selected, added, layouts, displayEdited = {}, {}, {}, false
    for _, row in ipairs(draft.rows) do
        local rule = draft.getRule(row.name)
        if not rule then return nil end
        selected[row.name] = row
        local layout = draft.layouts[row.name]
        if layout.copy.level ~= layout.level or layout.copy.parent ~= layout.parent then
            layouts[#layouts + 1] = layout
        end
        local original = draft.original[row.name]
        if row.showpriority ~= (original and original.showpriority) then displayEdited = true end
        if not original then
            local entry = createBagRule(rule, row.priority, row.showpriority)
            if not entry then return nil end
            added[#added + 1] = entry
        end
    end

    if displayOrderChanged and (#layouts > 0 or displayEdited) then return nil end
    if #layouts > 0 then
        -- A parent/candidate may have changed even if it was not edited here.
        for name, layout in pairs(draft.layouts) do
            local rule = draft.getRule(name)
            if rule ~= layout.rule or rule.name ~= layout.copy.name
                    or rule.level ~= layout.level or rule.parent ~= layout.parent then return nil end
        end
    end

    local changed = #added > 0 or #layouts > 0
    for i = #bag.rules, 1, -1 do
        local entry = bag.rules[i]
        local original, row = draft.original[entry.name], selected[entry.name]
        if original and not row then
            table.remove(bag.rules, i)
            changed = true
        elseif original then
            if row.priority ~= original.priority then
                entry.runpriority = row.priority
                changed = true
            end
            if row.showpriority ~= original.showpriority then
                entry.showpriority = row.showpriority
                changed = true
            end
        end
    end
    for _, entry in ipairs(added) do bag.rules[#bag.rules + 1] = entry end
    for _, layout in ipairs(layouts) do
        layout.rule.level, layout.rule.parent = layout.copy.level, layout.copy.parent
    end
    if #layouts > 0 and AC.SyncPredefinedLayouts then AC.SyncPredefinedLayouts() end
    return changed
end

function Management.Tooltip(name, rule)
    local title = name
    if rule and rule:isPredefined() then
        title = title .. " |cFF0000(" .. GetString(SI_AC_CATEGORY_MANAGER_READ_ONLY) .. ")|r"
    end
    return title .. "\n" .. (rule and rule.rule or "")
end

local CANCEL_ACTION_LAYER = "AutoCategoryCategoryManagement"
local window, availableList, presentList, draft, onCommit

local function inventoryName(bagId)
    local names = AC.cache and AC.cache.bags_cvt
    if names and names.choicesValues and names.choices then
        for i, id in ipairs(names.choicesValues) do
            if id == bagId then return names.choices[i] or "" end
        end
    end
    return ""
end

local function showError(stringId)
    window:GetNamedChild("Status"):SetText(GetString(stringId))
end

local function close()
    draft, onCommit = nil, nil
    availableList:Hide()
    presentList:Hide()
    window:SetHidden(true)
    ZO_Tooltips_HideTextTooltip()
end

function Management.Cancel()
    if not draft or window:IsHidden() then return false end
    close()
    return true
end

local function refresh()
    local available, present = {}, {}
    local displayed, resolveDisplay
    local headers = AC.GetDisplayedHeaders(draft.bagId, draft.sourceList)
    if headers then
        displayed = {}
        for _, path in ipairs(headers) do displayed[path] = true end
        resolveDisplay = AC.MakeBagRuleDisplayResolver(draft.bagId)
    end
    for _, name in ipairs(Management.GetAvailable(draft, AC.RulesW.ruleList)) do
        available[#available + 1] = {
            key = name, name = name,
            tooltip = Management.Tooltip(name, AC.GetRuleByName(name)),
            callback = function()
                if draft and Management.Add(draft, name) then refresh() end
            end,
        }
    end
    for _, row in ipairs(Management.OrderedRows(draft)) do
        local name = row.name
        local original = draft.original[name]
        local entry = original and original.entry
        local color
        if entry and entry.isHidden then
            color = HIDDEN_COLOR
        elseif displayed and (not entry or not displayed[resolveDisplay(entry)]) then
            color = ABSENT_COLOR
        end
        local indent = string.rep("   ", CLM.EffectiveLevel(draft.getLayout(name)) - 1)
        present[#present + 1] = {
            key = name, name = name, label = indent .. string.format("[%d] %s", orderPriority(draft, row), name),
            color = color,
            tooltip = Management.Tooltip(name, AC.GetRuleByName(name)),
            rightClickCallback = function()
                if draft and Management.Remove(draft, name) then refresh() end
            end,
        }
    end
    ZO_Tooltips_HideTextTooltip()
    availableList:SetItems(available)
    presentList:SetItems(present)
end

local function setupLevels()
    local shallower = window:GetNamedChild("Shallower")
    local deeper = window:GetNamedChild("Deeper")
    local function setupButton(button, delta, tooltipId)
        button:SetHandler("OnMouseEnter", function(control)
            ZO_Tooltips_ShowTextTooltip(control, TOP, GetString(tooltipId))
        end)
        button:SetHandler("OnMouseExit", ZO_Tooltips_HideTextTooltip)
        button:SetHandler("OnClicked", function()
            if draft and Management.ShiftSelection(draft, presentList.selection, delta) then
                refresh()
            end
        end)
    end
    setupButton(shallower, -1, SI_AC_MENU_CM_LEVEL_SHALLOWER)
    setupButton(deeper, 1, SI_AC_MENU_CM_LEVEL_DEEPER)
    return function(selection)
        local subtrees = draft and next(selection) and planLevels(draft, selection) or {}
        shallower:SetEnabled(canShiftLevels(subtrees, -1))
        deeper:SetEnabled(canShiftLevels(subtrees, 1))
    end
end

local function selectOrder(displayOrder)
    if not draft then return end
    draft.displayOrder = displayOrder
    local modes = window:GetNamedChild("PresentTitle")
    modes:GetNamedChild("Run"):SetEnabled(displayOrder)
    modes:GetNamedChild("Display"):SetEnabled(not displayOrder)
    window:GetNamedChild("Status"):SetText("")
    refresh()
end

local function setup()
    window = AC_CategoryManagementWindow
    window:GetNamedChild("Title"):SetText(GetString(SI_AC_MENU_CM_MANAGE_CATEGORIES))
    window:GetNamedChild("AvailableTitle"):SetText(GetString(SI_AC_CATEGORY_MANAGER_AVAILABLE))
    local modes = window:GetNamedChild("PresentTitle")
    local run, display = modes:GetNamedChild("Run"), modes:GetNamedChild("Display")
    run:SetText(GetString(SI_AC_MENU_BS_SLIDER_CATEGORY_RUNPRIORITY))
    display:SetText(GetString(SI_AC_MENU_BS_SLIDER_CATEGORY_SHOWPRIORITY))
    run:SetHandler("OnClicked", function() selectOrder(false) end)
    display:SetHandler("OnClicked", function() selectOrder(true) end)
    window:GetNamedChild("Hint"):SetText(GetString(SI_AC_CATEGORY_MANAGER_HINT))
    window:GetNamedChild("Cancel"):SetText(GetString(SI_DIALOG_CANCEL))
    window:GetNamedChild("Confirm"):SetText(GetString(SI_AC_CATEGORY_MANAGER_CONFIRM))
    window:SetHandler("OnEffectivelyHidden", function()
        RemoveActionLayerByName(CANCEL_ACTION_LAYER)
        if draft then close() end
    end)
    window:GetNamedChild("Cancel"):SetHandler("OnClicked", Management.Cancel)
    window:GetNamedChild("Confirm"):SetHandler("OnClicked", function()
        if not draft then return end
        local changed = Management.Commit(draft, AC.saved, AC.CreateBagRule)
        if changed == nil then
            showError(SI_AC_CATEGORY_MANAGER_STALE)
            return
        end
        local callback = onCommit
        close()
        if changed and callback then callback() end
    end)

    availableList = AC.OrderList.New(window:GetNamedChild("Available"), { searchable = true })
    -- Regular keys are left to the search box. It can receive Escape before the action layer.
    availableList.edit:SetHandler("OnEscape", Management.Cancel)
    presentList = AC.OrderList.New(window:GetNamedChild("Present"), {
        searchable = true,
        onSelectionChanged = setupLevels(),
        onMove = function(fromIndex, toIndex)
            if not draft then return end
            local moved = Management.Move(draft, fromIndex, toIndex)
            refresh()
            if not moved then showError(SI_AC_CATEGORY_MANAGER_PRIORITY_LIMIT) end
        end,
        onMoveSelection = function(indices, delta, toEdge)
            if not draft then return end
            local moved = Management.MoveSelection(draft, indices, delta, toEdge)
            if moved == nil then return end
            refresh()
            if not moved then showError(SI_AC_CATEGORY_MANAGER_PRIORITY_LIMIT) end
        end,
    })
    presentList.edit:SetHandler("OnEscape", Management.Cancel)
end

function Management.Open(bagId, refreshInventory, sourceList)
    if not window then setup() end
    -- Don't discard a pending draft just because another header was clicked.
    if draft and not window:IsHidden() then
        window:BringWindowToTop()
        return
    end
    draft = Management.NewDraft(AC.saved, bagId, AC.GetRuleByName)
    if not draft then return end
    draft.sourceList = sourceList
    onCommit = refreshInventory
    window:GetNamedChild("Inventory"):SetText(inventoryName(bagId))
    selectOrder(false)
    window:SetHidden(false)
    window:BringWindowToTop()
    availableList:Show()
    presentList:Show()
    PushActionLayerByName(CANCEL_ACTION_LAYER)
end
