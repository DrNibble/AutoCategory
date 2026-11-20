local AC = AutoCategory
local Management = {}
AC.CategoryManagement = Management

local MAX_PRIORITY = 1000
local function priority(entry)
    local value = tonumber(entry.runpriority)
    if not value then return 0 end
    return math.min(MAX_PRIORITY, math.max(0, math.floor(value)))
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
        rows = {}, original = {}, snapshot = {}, count = #bag.rules,
    }
    for _, entry in ipairs(bag.rules) do
        draft.snapshot[entry] = draft.snapshot[entry] or { entry.name, entry.runpriority, count = 0 }
        draft.snapshot[entry].count = draft.snapshot[entry].count + 1
        if not draft.original[entry.name] and getRule(entry.name) then
            local row = { name = entry.name, priority = priority(entry) }
            draft.original[entry.name] = { priority = row.priority }
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
    if not draft.getRule(name) then return false end
    for _, row in ipairs(draft.rows) do if row.name == name then return false end end
    local original = draft.original[name]
    local value = original and original.priority or MAX_PRIORITY
    draft.rows[#draft.rows + 1] = { name = name, priority = value }
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

function Management.Move(draft, fromIndex, toIndex)
    local rows = draft.rows
    if fromIndex == toIndex or not rows[fromIndex] or not rows[toIndex] then return false end

    local values = {}
    local moved = table.remove(rows, fromIndex)
    local targetPriority = fromIndex < toIndex and rows[toIndex - 1].priority or rows[toIndex].priority
    table.insert(rows, toIndex, moved)
    for i, row in ipairs(rows) do
        values[i] = i < toIndex and row.priority or (i == toIndex and targetPriority or row.priority - 1)
        if i > 1 then
            -- Equal priorities are allowed only when the game's tie-breaker
            -- would keep these two categories in the requested order.
            local step = rows[i - 1].name < row.name and 0 or 1
            values[i] = math.min(values[i], values[i - 1] - step)
        end
    end
    -- Repair underflow from the bottom without clamping away a user's move.
    for i = #rows, 1, -1 do
        values[i] = math.max(values[i], 0)
        if i < #rows then
            local step = rows[i].name < rows[i + 1].name and 0 or 1
            values[i] = math.max(values[i], values[i + 1] + step)
        end
    end
    if values[1] > MAX_PRIORITY then
        table.insert(rows, fromIndex, table.remove(rows, toIndex))
        return false
    end
    for i, row in ipairs(rows) do row.priority = values[i] end
    return true
end

-- Return nil if this bag or its priorities were changed by another UI.
-- Keep the original entries (and all unrelated fields) for retained rules.
function Management.Commit(draft, saved, createBagRule)
    local bag = saved and saved.bags and saved.bags[draft.bagId]
    if saved ~= draft.saved or bag ~= draft.bag or bag.rules ~= draft.rules
            or #bag.rules ~= draft.count then return nil end
    local seen = {}
    for _, entry in ipairs(bag.rules) do
        local prior = draft.snapshot[entry]
        seen[entry] = (seen[entry] or 0) + 1
        if not prior or prior[1] ~= entry.name or prior[2] ~= entry.runpriority or seen[entry] > prior.count then
            return nil
        end
    end

    local selected, added = {}, {}
    for _, row in ipairs(draft.rows) do
        local rule = draft.getRule(row.name)
        if not rule then return nil end
        selected[row.name] = row
        if not draft.original[row.name] then
            local entry = createBagRule(rule, row.priority)
            if not entry then return nil end
            added[#added + 1] = entry
        end
    end

    local changed = #added > 0
    for i = #bag.rules, 1, -1 do
        local entry = bag.rules[i]
        local original, row = draft.original[entry.name], selected[entry.name]
        if original and not row then
            table.remove(bag.rules, i)
            changed = true
        elseif original and row.priority ~= original.priority then
            entry.runpriority = row.priority
            changed = true
        end
    end
    for _, entry in ipairs(added) do bag.rules[#bag.rules + 1] = entry end
    return changed
end

function Management.Tooltip(name, rule)
    local title = name
    if rule and rule:isPredefined() then
        title = title .. " |cFF0000(" .. GetString(SI_AC_CATEGORY_MANAGER_READ_ONLY) .. ")|r"
    end
    return title .. "\n" .. (rule and rule.rule or "")
end

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

local function refresh()
    local available, present = {}, {}
    for _, name in ipairs(Management.GetAvailable(draft, AC.RulesW.ruleList)) do
        available[#available + 1] = {
            key = name, name = name,
            tooltip = Management.Tooltip(name, AC.GetRuleByName(name)),
            callback = function()
                if draft and Management.Add(draft, name) then refresh() end
            end,
        }
    end
    for _, row in ipairs(draft.rows) do
        local name = row.name
        present[#present + 1] = {
            key = name, name = name, label = string.format("[%d] %s", row.priority, name),
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

local function setup()
    window = AC_CategoryManagementWindow
    window:GetNamedChild("Title"):SetText(GetString(SI_AC_MENU_CM_MANAGE_CATEGORIES))
    window:GetNamedChild("AvailableTitle"):SetText(GetString(SI_AC_CATEGORY_MANAGER_AVAILABLE))
    window:GetNamedChild("PresentTitle"):SetText(GetString(SI_AC_CATEGORY_MANAGER_PRESENT))
    window:GetNamedChild("Hint"):SetText(GetString(SI_AC_CATEGORY_MANAGER_HINT))
    window:GetNamedChild("Cancel"):SetText(GetString(SI_DIALOG_CANCEL))
    window:GetNamedChild("Confirm"):SetText(GetString(SI_AC_CATEGORY_MANAGER_CONFIRM))
    window:GetNamedChild("Cancel"):SetHandler("OnClicked", close)
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

    local function makeList(key, options)
        local host = window:GetNamedChild(key)
        options.visibleRows = 15
        return LibScrollableMenu.CreateOrderListBox(host, options)
    end
    availableList = makeList("Available", { enableFilter = true })
    presentList = makeList("Present", {
        enableManualOrder = true,
        onOrderChanged = function(_, _, _, fromIndex, toIndex)
            if not draft then return end
            local moved = Management.Move(draft, fromIndex, toIndex)
            refresh()
            if not moved then showError(SI_AC_CATEGORY_MANAGER_PRIORITY_LIMIT) end
        end,
    })
end

function Management.Open(bagId, refreshInventory)
    if not LibScrollableMenu.CreateOrderListBox then
        d(GetString(SI_AC_CATEGORY_MANAGER_REQUIRES_LSM))
        return
    end
    if not window then setup() end
    -- Don't discard a pending draft just because another header was clicked.
    if draft and not window:IsHidden() then
        window:BringWindowToTop()
        return
    end
    draft = Management.NewDraft(AC.saved, bagId, AC.GetRuleByName)
    if not draft then return end
    onCommit = refreshInventory
    window:GetNamedChild("Inventory"):SetText(inventoryName(bagId))
    window:GetNamedChild("Status"):SetText("")
    refresh()
    window:SetHidden(false)
    window:BringWindowToTop()
    availableList:Show()
    presentList:Show()
end
