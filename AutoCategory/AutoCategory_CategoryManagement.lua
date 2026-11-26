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
        rows = {}, original = {}, snapshot = {}, layouts = {}, copies = {}, count = #bag.rules,
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
            name = entry.name, runpriority = entry.runpriority, showpriority = entry.showpriority,
            isHidden = entry.isHidden, count = 0,
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

local function displayLayout(draft)
    local tree = AC.CategoryTree
    local entries, byRow, info, groups = {}, {}, {}, {}
    for _, entry in ipairs(draft.rules) do
        if not draft.original[entry.name] then entries[#entries + 1] = entry end
    end
    for _, row in ipairs(draft.rows) do
        local entry = { name = row.name, runpriority = row.priority, showpriority = row.showpriority }
        entries[#entries + 1] = entry
        byRow[row] = entry
    end
    local resolve = AC.MakeBagRuleDisplayResolver(draft.bagId, entries, draft.getLayout, draft.saved.bags)
    local rows, byPath = {}, {}
    for i, row in ipairs(draft.rows) do
        local path, key = resolve(byRow[row])
        local depth = tree.LevelCount(path)
        local parent = tree.ParentOf(path) or ""
        local prefix = depth > 1 and #tree.LevelSortKey(key, depth - 1) + 1 or 0
        -- Strip the ancestor key and the four priority digits. What
        -- remains is the inventory's tie-breaker within this sibling group.
        info[row] = { key = key, path = path, depth = depth, parent = parent, tie = key:sub(prefix + 5) }
        byPath[path] = row
        rows[i] = row
    end
    table.sort(rows, function(a, b)
        if info[a].key ~= info[b].key then return info[a].key < info[b].key end
        return a.name < b.name
    end)
    for _, row in ipairs(rows) do
        local parent = info[row].parent
        local siblings = groups[parent] or {}
        groups[parent] = siblings
        siblings[#siblings + 1] = row
        info[row].index = #siblings
        local ancestors = {}
        for _, prefix in ipairs(tree.Ancestors(info[row].path) or {}) do
            if byPath[prefix] then ancestors[#ancestors + 1] = byPath[prefix].name end
        end
        info[row].ancestors = ancestors
    end
    return rows, info, groups
end

function Management.OrderedRows(draft)
    if draft.displayOrder then return displayLayout(draft) end
    local ordered = {}
    for i, row in ipairs(draft.rows) do ordered[i] = row end
    return ordered
end

local function fitPriorities(rows, values, minimum, info)
    local function step(a, b)
        local first, second = a.name, b.name
        if info then first, second = info[a].tie, info[b].tie end
        return (first < second or (first == second and a.name < b.name)) and 0 or 1
    end
    for i = 2, #rows do
        -- Equal priorities are allowed only when the game's tie-breaker
        -- would keep these two categories in the requested order.
        values[i] = math.min(values[i], values[i - 1] - step(rows[i - 1], rows[i]))
    end
    -- Repair underflow from the bottom without clamping away a user's move.
    for i = #rows, 1, -1 do
        values[i] = math.max(values[i], minimum)
        if i < #rows then
            values[i] = math.max(values[i], values[i + 1] + step(rows[i], rows[i + 1]))
        end
    end
    return values[1] <= MAX_PRIORITY
end

local function orderPriority(draft, row)
    return draft.displayOrder and displayPriority(row) or row.priority
end

local function moveRow(draft, rows, fromIndex, toIndex)
    local values = {}
    local moved = table.remove(rows, fromIndex)
    local targetPriority = orderPriority(draft, rows[fromIndex < toIndex and toIndex - 1 or toIndex])
    table.insert(rows, toIndex, moved)
    for i, row in ipairs(rows) do
        local value = orderPriority(draft, row)
        values[i] = i < toIndex and value or (i == toIndex and targetPriority or value - 1)
    end
    return rows, values
end

local function applyDisplayValues(rows, values)
    for i, row in ipairs(rows) do
        if displayPriority(row) ~= values[i] then row.showpriority = values[i] end
    end
end

local function applyRunValues(draft, rows, values)
    if not fitPriorities(rows, values, 0) then return false end
    for i, row in ipairs(rows) do row.priority = values[i] end
    draft.rows = rows
    return true
end

function Management.Move(draft, fromIndex, toIndex)
    local rows, info, groups = Management.OrderedRows(draft)
    local from, to = rows[fromIndex], rows[toIndex]
    if fromIndex == toIndex or not from or not to then return end
    if not info then return applyRunValues(draft, moveRow(draft, rows, fromIndex, toIndex)) end
    local first, last = info[from], info[to]
    if first.parent ~= last.parent then return end
    local siblings, values = moveRow(draft, groups[first.parent], first.index, last.index)
    if not fitPriorities(siblings, values, 2, info) then return false end
    applyDisplayValues(siblings, values)
    return true
end

local function moveSelection(draft, rows, indices, delta, toEdge)
    local count = #rows
    if #indices == 0 or (delta ~= -1 and delta ~= 1) then return end
    if #indices == 1 then
        local index = indices[1]
        local target = toEdge and (delta == -1 and 1 or count) or index + delta
        if target == index or not rows[target] then return end
        return moveRow(draft, rows, index, target)
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
    if changed then return rows, values end
end

function Management.MoveSelection(draft, indices, delta, toEdge)
    local rows, info, groups = Management.OrderedRows(draft)
    if not info then
        local moved, values = moveSelection(draft, rows, indices, delta, toEdge)
        if moved then return applyRunValues(draft, moved, values) end
        return
    end
    local selectedByParent, pending, names = {}, {}, {}
    for _, index in ipairs(indices) do
        if rows[index] then names[rows[index].name] = true end
    end
    for _, index in ipairs(indices) do
        local data = info[rows[index]]
        local covered
        for _, name in ipairs(data and data.ancestors or {}) do
            if names[name] then covered = true; break end
        end
        if data and not covered then
            local selected = selectedByParent[data.parent] or {}
            selectedByParent[data.parent] = selected
            selected[#selected + 1] = data.index
        end
    end
    for parent, selected in pairs(selectedByParent) do
        local moved, values = moveSelection(draft, groups[parent], selected, delta, toEdge)
        if moved then
            if not fitPriorities(moved, values, 2, info) then return false end
            pending[#pending + 1] = { moved, values }
        end
    end
    for _, change in ipairs(pending) do applyDisplayValues(change[1], change[2]) end
    if #pending > 0 then return true end
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

local function branchMove(draft, subtree, parent, moving)
    local root = subtree[1].rule
    if parent == root.parent or moving[parent] then return end
    local parentRule = parent and draft.getLayout(parent)
    if parent and not parentRule then return end
    local newLevel = parentRule and CLM.EffectiveLevel(parentRule) + 1 or 1
    local delta = newLevel - CLM.EffectiveLevel(root)
    for _, entry in ipairs(subtree) do
        local level = CLM.EffectiveLevel(entry.rule) + delta
        if level < 1 or level > 5 then return end
    end
    return { subtree = subtree, parent = parent, delta = delta }
end

local function moveBranches(changes)
    for _, change in ipairs(changes) do
        for _, entry in ipairs(change.subtree) do
            local rule = entry.rule
            local level = CLM.EffectiveLevel(rule) + change.delta
            rule.level = level > 1 and level or nil
        end
        change.subtree[1].rule.parent = change.parent
    end
end

local function isHidden(draft, name)
    local original = draft.original[name]
    return original and original.entry.isHidden
end

local function planDisplayShift(draft, subtrees, moving, delta)
    if #subtrees == 0 or (delta ~= -1 and delta ~= 1) then return end
    local rows, info, groups = displayLayout(draft)
    local byName, byPath, changes = {}, {}, {}
    for _, row in ipairs(rows) do
        byName[row.name], byPath[info[row].path] = info[row], row
    end
    for _, subtree in ipairs(subtrees) do
        local data = byName[subtree[1].rule.name]
        local parent
        if delta == -1 then
            if data.parent == "" then return end
            local grandparent = AC.CategoryTree.ParentOf(data.parent)
            if grandparent then
                local candidate = byPath[grandparent]
                parent = candidate and candidate.name or AC.CategoryTree.DisplayName(grandparent)
            end
        else
            local siblings = groups[data.parent]
            for index = data.index - 1, 1, -1 do
                local candidate = siblings[index].name
                if not moving[candidate] and not isHidden(draft, candidate) then
                    parent = candidate
                    break
                end
            end
            if not parent then return end
        end
        local change = branchMove(draft, subtree, parent, moving)
        if not change then return end
        changes[#changes + 1] = change
    end
    return changes
end

function Management.ShiftSelection(draft, selected, delta)
    local subtrees, bagRules, moving = planLevels(draft, selected)
    if draft.displayOrder then
        local changes = planDisplayShift(draft, subtrees, moving, delta)
        if not changes then return false end
        moveBranches(changes)
        return true
    end
    if not canShiftLevels(subtrees, delta) then return false end
    for _, subtree in ipairs(subtrees) do
        CLM.ShiftRuleLevels(bagRules, subtree, delta, draft.getLayout, moving)
    end
    return true
end

function Management.ShiftLevel(draft, name, delta)
    return Management.ShiftSelection(draft, { [name] = true }, delta)
end

function Management.RemoveDisplaySelection(draft, selected)
    local parents, affected = {}, {}
    for _, row in ipairs(draft.rows) do
        local rule = draft.getLayout(row.name)
        if selected[row.name] then parents[row.name] = rule.parent or false end
    end
    for _, row in ipairs(draft.rows) do
        if parents[row.name] == nil then
            local rule = draft.getLayout(row.name)
            local parent, count, visited = rule.parent, 0, { [row.name] = true }
            while parent and parent ~= "" and not visited[parent] do
                visited[parent] = true
                if parents[parent] ~= nil then count = count + 1 end
                local ancestor = draft.getLayout(parent)
                parent = ancestor and ancestor.parent
            end
            if count > 0 then
                local direct, climbed = rule.parent, {}
                while direct and parents[direct] ~= nil do
                    if climbed[direct] then direct = nil; break end
                    climbed[direct] = true
                    direct = parents[direct] or nil
                end
                affected[#affected + 1] = { rule = rule, parent = direct, count = count }
            end
        end
    end
    for _, item in ipairs(affected) do
        local rule = item.rule
        local level = CLM.EffectiveLevel(rule) - item.count
        rule.level = level > 1 and level or nil
        rule.parent = rule.level and item.parent or nil
    end
    for name in pairs(parents) do Management.Remove(draft, name) end
    return next(parents) ~= nil
end

local function planAttach(draft, subtrees, moving, parent)
    local changes = {}
    for _, subtree in ipairs(subtrees) do
        -- A selected branch already under the target can stay in place.
        if subtree[1].rule.parent ~= parent then
            local change = branchMove(draft, subtree, parent, moving)
            if not change then return end
            changes[#changes + 1] = change
        end
    end
    if #changes > 0 then return changes end
end

local function queueCopy(draft, bagId, subtrees, overwrite)
    local bag = draft.saved.bags[bagId]
    if not bag or not bag.rules then return false end
    local copy = draft.copies[bagId]
    if not copy then
        copy = { bag = bag, rules = bag.rules, snapshot = {}, names = {} }
        for i, entry in ipairs(bag.rules) do
            copy.snapshot[i] = { entry, entry.name, entry.runpriority, entry.showpriority, entry.isHidden }
        end
        draft.copies[bagId] = copy
    end
    for _, subtree in ipairs(subtrees) do copy.names[subtree[1].rule.name] = overwrite end
    return true
end

local function layoutChanged(layout)
    return layout.copy.level ~= layout.level or layout.copy.parent ~= layout.parent
end

local function hasChanges(draft)
    if next(draft.copies) then return true end
    local present = {}
    for _, row in ipairs(draft.rows) do
        local original = draft.original[row.name]
        if not original or row.priority ~= original.priority or row.showpriority ~= original.showpriority
                or layoutChanged(draft.layouts[row.name]) then return true end
        present[row.name] = true
    end
    for name in pairs(draft.original) do
        if not present[name] then return true end
    end
    return false
end

-- Return nil if this bag, its priorities or a layout dependency is stale.
-- Keep the original entries (and all unrelated fields) for retained rules.
function Management.Commit(draft, saved, createBagRule)
    local bag = saved and saved.bags and saved.bags[draft.bagId]
    if saved ~= draft.saved or bag ~= draft.bag or bag.rules ~= draft.rules
            or #bag.rules ~= draft.count then return nil end
    for bagId, copy in pairs(draft.copies) do
        local target = saved.bags[bagId]
        if target ~= copy.bag or target.rules ~= copy.rules or #target.rules ~= #copy.snapshot then return nil end
        for i, entry in ipairs(target.rules) do
            local prior = copy.snapshot[i]
            if entry ~= prior[1] or entry.name ~= prior[2] or entry.runpriority ~= prior[3]
                    or entry.showpriority ~= prior[4] or entry.isHidden ~= prior[5] then return nil end
        end
    end
    local hasCopies = next(draft.copies) ~= nil
    local seen, displayOrderChanged = {}, false
    for _, entry in ipairs(bag.rules) do
        local prior = draft.snapshot[entry]
        seen[entry] = (seen[entry] or 0) + 1
        if not prior or prior.name ~= entry.name or prior.runpriority ~= entry.runpriority
                or seen[entry] > prior.count or (hasCopies and prior.isHidden ~= entry.isHidden) then
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
        if layoutChanged(layout) then
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

    if #layouts > 0 or displayEdited or hasCopies then
        if displayOrderChanged then return nil end
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
    for bagId, copy in pairs(draft.copies) do
        local names = {}
        for name in pairs(copy.names) do names[name] = true end
        local subtrees = planLevels(draft, names)
        for _, subtree in ipairs(subtrees) do
            local name = subtree[1].rule.name
            local copied, _, overwritten = CLM.CopySubtreeToBag(draft.bagId, name, bagId, copy.names[name])
            if copied > 0 or overwritten > 0 then changed = true end
        end
    end
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
local window, availableList, presentList, bagCombo, bagChoices, draft, onCommit
local originBagId, originList, creatingCategory
local confirmingDelete, deleteDialogRegistered
local pendingDeleteName, pendingDeleteDone
local showContextMenu, showAvailableContextMenu, requestDeleteCategory

local function showError(stringId)
    window:GetNamedChild("Status"):SetText(GetString(stringId))
end

local function close()
    draft, onCommit = nil, nil
    confirmingDelete, pendingDeleteName, pendingDeleteDone = nil, nil, nil
    originBagId, originList = nil, nil
    AC.ScrollMenu.Hide()
    bagCombo:HideDropdown()
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
    AC.ScrollMenu.Hide()
    local available, present = {}, {}
    local displayed, resolveDisplay
    -- The source list only describes the inventory that opened the manager.
    local headers = draft.bagId == originBagId and originList
        and AC.GetDisplayedHeaders(draft.bagId, originList)
    if headers then
        displayed = {}
        for _, path in ipairs(headers) do displayed[path] = true end
        resolveDisplay = AC.MakeBagRuleDisplayResolver(draft.bagId)
    end
    for _, name in ipairs(Management.GetAvailable(draft, AC.RulesW.ruleList)) do
        local rule = AC.GetRuleByName(name)
        local readOnly = rule ~= nil and type(rule.isPredefined) == "function"
            and rule:isPredefined()
        -- A predefined category is read-only: say it in the list itself and
        -- not only in the tooltip.
        local label = readOnly
            and (name .. " (" .. GetString(SI_AC_CATEGORY_MANAGER_READ_ONLY) .. ")")
            or name
        available[#available + 1] = {
            key = name, name = name, label = label,
            tooltip = Management.Tooltip(name, rule),
            callback = function()
                if draft and Management.Add(draft, name) then refresh() end
            end,
            rightClickCallback = function(owner)
                if showAvailableContextMenu then
                    showAvailableContextMenu(owner, name, readOnly)
                end
            end,
        }
    end
    local rows, displayInfo = Management.OrderedRows(draft)
    for _, row in ipairs(rows) do
        local name = row.name
        local original = draft.original[name]
        local entry = original and original.entry
        local color
        if entry and entry.isHidden then
            color = HIDDEN_COLOR
        elseif displayed and (not entry or not displayed[resolveDisplay(entry)]) then
            color = ABSENT_COLOR
        end
        local info = displayInfo and displayInfo[row]
        local depth = info and info.depth or CLM.EffectiveLevel(draft.getLayout(name))
        local indent = string.rep("   ", depth - 1)
        local label = draft.displayOrder and name or string.format("[%d] %s", row.priority, name)
        present[#present + 1] = {
            key = name, name = name, label = indent .. label,
            moveGroup = info and info.parent,
            moveAncestors = info and info.ancestors,
            color = color,
            tooltip = Management.Tooltip(name, AC.GetRuleByName(name)),
            rightClickCallback = showContextMenu,
        }
    end
    ZO_Tooltips_HideTextTooltip()
    availableList:SetItems(available)
    presentList:SetItems(present)
end

showContextMenu = function(owner, selection)
    if not draft or not next(selection) then return end
    local current, selected = draft, {}
    for name in pairs(selection) do selected[name] = true end
    local subtrees, _, moving = planLevels(current, selected)
    if #subtrees == 0 then return end
    local menu = {}
    local choices, copyAction = CLM.BuildCopyChoices(current.bagId, function(bagId)
        local bag = current.saved.bags[bagId]
        for _, entry in ipairs(bag and bag.rules or {}) do
            if moving[entry.name] then return true end
        end
        return false
    end, function(bagId, _, overwrite)
        if draft ~= current then return false end
        return queueCopy(current, bagId, subtrees, overwrite)
    end, function()
        window:GetNamedChild("Status"):SetText(GetString(SI_AC_CATEGORY_MANAGER_COPY_PENDING))
    end)
    if #choices > 0 then
        local copyRows = {}
        for _, choice in ipairs(choices) do
            copyRows[#copyRows + 1] = {
                label = choice.overwriteTooltip and ("|cFF5555" .. choice.label .. "|r") or choice.label,
                kind = "check", tooltip = choice.overwriteTooltip, setChecked = choice.onChecked,
                checked = function() return choice.selected == true end,
            }
        end
        copyRows[#copyRows + 1] = { label = GetString(SI_AC_MENU_CM_COPY_SELECTED), action = copyAction }
        menu[#menu + 1] = { label = GetString(SI_AC_MENU_CM_COPY_SUBMENU), entries = copyRows }
    end
    menu[#menu + 1] = {
        label = GetString(SI_AC_MENU_CM_REMOVE_DISPLAY),
        action = function()
            if draft == current and Management.RemoveDisplaySelection(current, selected) then refresh() end
        end,
    }
    local destinations, rows, info = {}, displayLayout(current)
    for _, row in ipairs(rows) do
        local name = row.name
        local changes = not moving[name] and not isHidden(current, name)
            and planAttach(current, subtrees, moving, name)
        if changes then
            destinations[#destinations + 1] = {
                label = string.rep("   ", info[row].depth - 1) .. name,
                action = function()
                    if draft ~= current then return end
                    moveBranches(changes)
                    refresh()
                end,
            }
        end
    end
    if #destinations > 0 then
        menu[#menu + 1] = {
            label = GetString(SI_AC_CATEGORY_MANAGER_ATTACH), entries = destinations, search = true,
        }
    end
    ZO_Tooltips_HideTextTooltip()
    AC.ScrollMenu.Show(owner, menu, { openerButton = MOUSE_BUTTON_INDEX_RIGHT })
end

-- Deleting a category rewrites the saved variables directly, like the Delete
-- button of the category settings. It is therefore only allowed on an
-- unchanged draft: the manager's own changes are applied on Confirm.
local DELETE_DIALOG = "AUTO_CATEGORY_MANAGER_DELETE_CATEGORY"

local function deletePendingCategory()
    local deleteCategory = AC.DeleteCategory
    if type(deleteCategory) ~= "function" or not pendingDeleteName then return false end
    return deleteCategory(pendingDeleteName) == true
end

local function finishDelete()
    local deleted = pendingDeleteDone
    confirmingDelete, pendingDeleteDone, pendingDeleteName = nil, nil, nil
    local current = draft
    if deleted and current then
        -- The rules and the bags changed under the draft: refresh the header
        -- menu first, then rebuild the draft from the new saved variables.
        if onCommit then onCommit() end
        local updated = Management.NewDraft(AC.saved, current.bagId, AC.GetRuleByName)
        if not updated then
            close()
            return
        end
        updated.displayOrder = current.displayOrder
        draft = updated
    end
    if not draft then return end
    window:SetHidden(false)
    window:BringWindowToTop()
    if deleted then
        window:GetNamedChild("Status"):SetText("")
        refresh()
    end
    PushActionLayerByName(CANCEL_ACTION_LAYER)
end

requestDeleteCategory = function(name)
    local current = draft
    if not current or window:IsHidden() or confirmingDelete then return end
    local rule = AC.GetRuleByName(name)
    if not rule or type(rule.isPredefined) ~= "function" or rule:isPredefined() then return end
    if hasChanges(current) then
        showError(SI_AC_CATEGORY_MANAGER_DELETE_PENDING)
        return
    end
    if not deleteDialogRegistered then
        ZO_Dialogs_RegisterCustomDialog(DELETE_DIALOG, {
            canQueue = true,
            title = { text = SI_AC_CATEGORY_MANAGER_DELETE },
            mainText = { text = "" },
            setup = function(dialog)
                ZO_Dialogs_UpdateDialogMainText(dialog, {
                    text = GetString(SI_AC_CATEGORY_MANAGER_DELETE_WARNING)
                        :format(pendingDeleteName or ""),
                })
            end,
            finishedCallback = finishDelete,
            buttons = {
                {
                    text = SI_DIALOG_CONFIRM,
                    callback = function() pendingDeleteDone = deletePendingCategory() end,
                },
                { text = SI_DIALOG_CANCEL },
            },
        })
        deleteDialogRegistered = true
    end
    pendingDeleteName, pendingDeleteDone = name, false
    -- The manager's HIGH tier would otherwise cover the native dialog.
    confirmingDelete = true
    AC.ScrollMenu.Hide()
    bagCombo:HideDropdown()
    ZO_Tooltips_HideTextTooltip()
    window:SetHidden(true)
    if not ZO_Dialogs_ShowDialog(DELETE_DIALOG) then finishDelete() end
end

showAvailableContextMenu = function(owner, name, readOnly)
    if not draft then return end
    local entries
    if readOnly then
        -- Keep the entry visible but inert: a predefined category cannot be
        -- deleted, exactly like the disabled button of the settings menu.
        entries = { {
            kind = "text",
            label = GetString(SI_AC_CATEGORY_MANAGER_DELETE) .. " ("
                .. GetString(SI_AC_CATEGORY_MANAGER_READ_ONLY) .. ")",
            tooltip = GetString(SI_AC_MENU_EC_BUTTON_DELETE_CATEGORY_TOOLTIP),
        } }
    else
        entries = { {
            label = GetString(SI_AC_CATEGORY_MANAGER_DELETE),
            tooltip = GetString(SI_AC_MENU_EC_BUTTON_DELETE_CATEGORY_TOOLTIP),
            action = function() requestDeleteCategory(name) end,
        } }
    end
    ZO_Tooltips_HideTextTooltip()
    AC.ScrollMenu.Show(owner, entries, { openerButton = MOUSE_BUTTON_INDEX_RIGHT })
end

local function setupLevels()
    local shallower = window:GetNamedChild("Shallower")
    local deeper = window:GetNamedChild("Deeper")
    local levelLabel = window:GetNamedChild("Level")
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
        local levels, text = {}, {}
        if draft then
            for name in pairs(selection) do levels[CLM.EffectiveLevel(draft.getLayout(name))] = true end
            for level = 1, 5 do if levels[level] then text[#text + 1] = level end end
        end
        levelLabel:SetText(#text == 1 and GetString(SI_AC_TIP_LEVEL):format(text[1]) or table.concat(text, " / "))
        local subtrees, _, moving
        if draft and next(selection) then subtrees, _, moving = planLevels(draft, selection) end
        if subtrees and draft.displayOrder then
            shallower:SetEnabled(planDisplayShift(draft, subtrees, moving, -1) ~= nil)
            deeper:SetEnabled(planDisplayShift(draft, subtrees, moving, 1) ~= nil)
        else
            shallower:SetEnabled(canShiftLevels(subtrees or {}, -1))
            deeper:SetEnabled(canShiftLevels(subtrees or {}, 1))
        end
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

local function selectBag(bagId)
    if not draft or bagId == draft.bagId then return end
    if hasChanges(draft) then
        bagCombo:SelectItem(bagChoices[draft.bagId], true)
        showError(SI_AC_CATEGORY_MANAGER_SWITCH_BAG)
        return
    end
    local nextDraft = Management.NewDraft(AC.saved, bagId, AC.GetRuleByName)
    if not nextDraft then
        bagCombo:SelectItem(bagChoices[draft.bagId], true)
        showError(SI_AC_CATEGORY_MANAGER_STALE)
        return
    end
    local displayOrder = draft.displayOrder
    availableList:Hide()
    presentList:Hide()
    draft = nextDraft
    selectOrder(displayOrder)
    availableList:Show()
    presentList:Show()
end

local function populateBags(bagId)
    bagCombo:ClearItems()
    bagChoices = {}
    local names = AC.cache.bags_cvt
    for index, id in ipairs(names.choicesValues) do
        local bag = AC.saved.bags[id]
        local entry = bagCombo:CreateItemEntry(names.choices[index], function() selectBag(id) end,
            bag ~= nil and bag.rules ~= nil)
        bagChoices[id] = entry
        bagCombo:AddItem(entry)
    end
    bagCombo:SelectItem(bagChoices[bagId], true)
end

local function openNewCategory()
    if not draft or creatingCategory or window:IsHidden() then return end
    if hasChanges(draft) then
        showError(SI_AC_CATEGORY_MANAGER_CREATE_PENDING)
        return
    end

    local current = draft
    local function resume(created)
        creatingCategory = false
        if created then
            -- Creation writes to the saved bag and can compact its display priorities.
            local updated = Management.NewDraft(AC.saved, current.bagId, AC.GetRuleByName)
            if not updated then
                close()
                return
            end
            updated.displayOrder = current.displayOrder
            draft = updated
            refresh()
        end
        window:SetHidden(false)
        window:BringWindowToTop()
        PushActionLayerByName(CANCEL_ACTION_LAYER)
    end

    window:GetNamedChild("Status"):SetText("")
    AC.ScrollMenu.Hide()
    bagCombo:HideDropdown()
    ZO_Tooltips_HideTextTooltip()
    -- The manager's HIGH tier would otherwise cover the native dialog.
    creatingCategory = true
    window:SetHidden(true)
    if not CLM.OpenNewCategoryDialog(current.bagId, nil, resume) then resume(false) end
end

local function setup()
    window = AC_CategoryManagementWindow
    bagCombo = ZO_ComboBox_ObjectFromContainer(window:GetNamedChild("Inventory"))
    bagCombo:SetSortsItems(false)
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
    local newCategory = window:GetNamedChild("NewCategory")
    newCategory:SetText(GetString(SI_AC_MENU_CM_NEW_CATEGORY))
    newCategory:SetHandler("OnClicked", openNewCategory)
    window:SetHandler("OnEffectivelyHidden", function()
        RemoveActionLayerByName(CANCEL_ACTION_LAYER)
        if draft and not creatingCategory and not confirmingDelete then close() end
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
            if moved == false then showError(SI_AC_CATEGORY_MANAGER_PRIORITY_LIMIT) end
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
    if creatingCategory or confirmingDelete then return end
    -- Don't discard a pending draft just because another header was clicked.
    if draft and not window:IsHidden() then
        window:BringWindowToTop()
        return
    end
    draft = Management.NewDraft(AC.saved, bagId, AC.GetRuleByName)
    if not draft then return end
    originBagId, originList = bagId, sourceList
    onCommit = refreshInventory
    populateBags(bagId)
    selectOrder(false)
    window:SetHidden(false)
    window:BringWindowToTop()
    availableList:Show()
    presentList:Show()
    PushActionLayerByName(CANCEL_ACTION_LAYER)
end
