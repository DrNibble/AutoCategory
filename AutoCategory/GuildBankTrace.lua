-- Opt-in keyboard guild-bank diagnostics. No sorting, refreshing or repair.
-- Install late, on command, so callers from other addons are observable.
local Trace = {enabled = false, keyboard = false, generation = 0, session = 0}
AutoCategory.GuildBankTrace = Trace
local HEADER, LIMIT = 998, 2500

local function text(value)
    return (tostring(value):gsub("[%c|]", " ")):sub(1, 180)
end

local function guildList()
    local inventories = PLAYER_INVENTORY and PLAYER_INVENTORY.inventories
    local inventory = inventories and inventories[INVENTORY_GUILD_BANK]
    return inventory and inventory.listView, inventory
end

function Trace:Active(list)
    local current = guildList()
    return self.enabled and self.keyboard and AutoCategory.Enabled
        and current ~= nil and (list == nil or list == current)
end

function Trace:Write(message)
    if not self.enabled then return end
    self.lines = self.lines + 1
    if self.lines > LIMIT then
        self.enabled = false
        self.session = self.session + 1
        AutoCat_Logger():Info("[ACGB] STOP line limit reached")
        d("[AutoCategory] /acgbtrace stopped: line limit reached.")
        return
    end
    AutoCat_Logger():Info(string.format("[ACGB] t=%s gen=%d guild=%s %s",
        tostring(GetGameTimeMilliseconds()), self.generation,
        tostring(GetSelectedGuildBankId()), message))
end

function Trace:Stack(stage)
    if self.stacks >= 32 then return end
    self.stacks = self.stacks + 1
    if debug and type(debug.traceback) == "function" then
        -- Keep file paths/line numbers: function names alone cannot identify
        -- the addon that rebuilt the list. Bound each stack and each session.
        self:Write(stage .. " CALLER " .. debug.traceback("", 3):sub(1, 3500))
    end
end

local function entryText(entry, index)
    local data = entry.data or {}
    return string.format("%d:%s bag=%s slot=%s cat=%s key=%s name=%s y=%s/%s",
        index, entry.typeId == HEADER and "H" or "I", text(data.bagId),
        text(data.slotIndex), text(data.AC_categoryName),
        text(data.AC_sortPriorityName), text(data.name),
        text(entry.top), text(entry.bottom))
end

function Trace:Snapshot(stage, list, extra, stack)
    if not self:Active(list) then return end
    list = list or guildList()
    local _, inventory = guildList()
    local data = ZO_ScrollList_GetDataList(list) or {}
    local headers, items, missing, positions, inversions = 0, 0, 0, 0, 0
    local firstBad, previousKey, previousHeader
    local headerGroups, itemGroups = {}, {}
    local hash = 5381
    for index, entry in ipairs(data) do
        local slot = entry.data or {}
        local header = entry.typeId == HEADER
        if header then headers = headers + 1 else items = items + 1 end
        if not header and slot.AC_sortPriorityName == nil then
            missing = missing + 1
        end
        if entry.top == nil or entry.bottom == nil then positions = positions + 1 end
        local key = slot.AC_sortPriorityName
        local group = tostring(key) .. "\001" .. tostring(slot.AC_categoryName)
        if header then headerGroups[group] = true
        else itemGroups[group] = (itemGroups[group] or 0) + 1 end
        if type(key) == "string" and type(previousKey) == "string"
            and (key < previousKey
                or (key == previousKey and header and not previousHeader)) then
            inversions = inversions + 1
            firstBad = firstBad or index
        end
        previousKey, previousHeader = key, header
        -- Full sequence, not just a count or a truncated sample. Diagnostic
        -- checksum only (collisions possible); rows below expose the evidence.
        local token = table.concat({tostring(entry.typeId), tostring(slot.bagId),
            tostring(slot.slotIndex), tostring(slot.AC_categoryName),
            tostring(key), tostring(slot.stackCount), tostring(slot.name)}, "\001")
        for n = 1, #token do hash = (hash * 33 + token:byte(n)) % 2147483647 end
        hash = (hash * 33 + 2) % 2147483647
    end
    local orphanItems = 0
    for group, count in pairs(itemGroups) do
        if not headerGroups[group] then orphanItems = orphanItems + count end
    end
    local visibleHeaders, activeHeaders, hiddenHeaders = 0, 0, 0
    for _, index in ipairs(list.visibleData or {}) do
        if data[index] and data[index].typeId == HEADER then
            visibleHeaders = visibleHeaders + 1
        end
    end
    for _, control in ipairs(list.activeControls or {}) do
        if control.dataEntry and control.dataEntry.typeId == HEADER then
            activeHeaders = activeHeaders + 1
            local label = control:GetNamedChild("HeaderName")
            if control:IsControlHidden() or (label and label:IsControlHidden()) then
                hiddenHeaders = hiddenHeaders + 1
            end
            if activeHeaders <= 2 then
                self:Write(stage .. " ACTIVE_HEADER row=" .. text(control:GetName())
                    .. " height=" .. tostring(control:GetHeight())
                    .. " rowHidden=" .. tostring(control:IsControlHidden())
                    .. " labelHidden=" .. tostring(label and label:IsControlHidden())
                    .. " alpha=" .. tostring(label and label:GetAlpha())
                    .. " text=" .. text(label and label:GetText()))
            end
        end
    end
    local info = ZO_ScrollList_GetDataTypeTable(list, HEADER)
    self:Write(string.format(
        "%s list=%s data=%s n=%d items=%d H=%d missingRules=%d orphanItems=%d missingY=%d inversions=%d firstBad=%s hash=%.0f visibleH=%d activeH=%d hiddenH=%d hidden=%s sortFn=%s headerSetup=%s %s",
        stage, tostring(list), tostring(data), #data, items, headers, missing,
        orphanItems, positions, inversions, tostring(firstBad), hash, visibleHeaders,
        activeHeaders, hiddenHeaders, tostring(list:IsControlHidden()),
        tostring(inventory.sortFn), tostring(info and info.setupCallback),
        extra or ""))
    if not self.enabled then return end
    -- Samples at each boundary, plus the first bad adjacency even when it
    -- lies below the initial viewport. Do not dump hundreds of item links.
    for index = 1, math.min(#data, 4) do
        self:Write(stage .. " ROW " .. entryText(data[index], index))
    end
    if firstBad then
        for index = math.max(1, firstBad - 1), math.min(#data, firstBad + 1) do
            if index > 4 then
                self:Write(stage .. " BAD " .. entryText(data[index], index))
            end
        end
    end
    if stack then self:Stack(stage) end
end

function Trace:Filtered(list, data, predicate)
    if not self:Active(list) then return end
    local reasons, inputItems = {}, 0
    for _, entry in ipairs(data) do
        if entry.typeId ~= HEADER then
            inputItems = inputItems + 1
            local hidden, reason = predicate(entry)
            reason = hidden and (reason or "hidden") or "kept"
            reasons[reason] = (reasons[reason] or 0) + 1
        end
    end
    local summary = {}
    for reason, count in pairs(reasons) do
        summary[#summary + 1] = reason .. "=" .. count
    end
    table.sort(summary)
    self:Write("FILTER inputItems=" .. inputItems .. " " .. table.concat(summary, " "))
end

function Trace:Rendered(row, slot, list)
    if not self:Active(list) then return end
    if slot.AC_bagTypeId ~= AC_BAG_TYPE_GUILDBANK then return end
    local label = row:GetNamedChild("HeaderName")
    self:Write(string.format(
        "HEADER_SETUP row=%s cat=%s rowHidden=%s labelHidden=%s height=%s alpha=%s text=%s",
        text(row:GetName()), text(slot.AC_categoryName),
        tostring(row:IsControlHidden()), tostring(label:IsControlHidden()),
        tostring(row:GetHeight()), tostring(label:GetAlpha()), text(label:GetText())))
end

function Trace:AfterSort(list)
    if not self:Active(list) then return end
    self:Snapshot("APPLYSORT_EXIT", list)
    self.sample = (self.sample or 0) + 1
    local sample, session = self.sample, self.session
    local generation, guild = self.generation, GetSelectedGuildBankId()
    for _, delay in ipairs({0, 100, 300}) do
        local wait = delay
        zo_callLater(function()
            if self.session ~= session or self.sample ~= sample
                or self.generation ~= generation
                or GetSelectedGuildBankId() ~= guild or not self:Active(list) then return end
            self:Snapshot("AFTER_SORT_" .. wait, list)
        end, wait)
    end
end

function Trace:BankChanged(eventId)
    if not self:Active() then return end
    self.generation = self.generation + 1
    local stage = eventId == EVENT_GUILD_BANK_SELECTED and "BANK_SELECTED"
        or eventId == EVENT_GUILD_BANK_ITEMS_READY and "ITEMS_READY" or "BANK_EVENT"
    self:Snapshot(stage)
end

function Trace:Install()
    if self.installed then return end
    self.installed = true
    for _, name in ipairs({"UpdateList", "ApplySort"}) do
        local method = name
        ZO_PreHook(PLAYER_INVENTORY, method, function(_, inventoryType)
            if inventoryType == INVENTORY_GUILD_BANK then
                self:Snapshot(method .. "_ENTER", nil, nil, true)
            end
            return false -- observe only; never suppress the original
        end)
        ZO_PostHook(PLAYER_INVENTORY, method, function(_, inventoryType)
            if inventoryType == INVENTORY_GUILD_BANK then
                if method == "ApplySort" then self:AfterSort(guildList())
                else self:Snapshot(method .. "_EXIT") end
            end
        end)
    end
    for _, name in ipairs({"ZO_ScrollList_Clear", "ZO_ScrollList_Commit"}) do
        local operation = name
        ZO_PreHook(operation, function(list)
            self:Snapshot(operation .. "_ENTER", list, nil, true)
            return false
        end)
        ZO_PostHook(operation, function(list)
            self:Snapshot(operation .. "_EXIT", list)
        end)
    end
end

function Trace:Start()
    self:Install()
    self.session = self.session + 1
    self.generation, self.lines, self.stacks = 0, 0, 0
    self.enabled = true
    self:Write("START build=4.6.19 keyboard=" .. tostring(self.keyboard)
        .. " stackBudget=32 lineLimit=" .. LIMIT)
    -- Record the actual enabled addon configuration, not just the presence
    -- of a global. This is the configuration to compare in the A/B capture.
    local manager = GetAddOnManager()
    for index = 1, manager:GetNumAddOns() do
        local name, _, _, _, enabled, state = manager:GetAddOnInfo(index)
        if enabled then
            self:Write("ADDON " .. text(name) .. " version="
                .. tostring(manager:GetAddOnVersion(index)) .. " state=" .. tostring(state))
        end
    end
    local bag = AutoCategory.saved and AutoCategory.saved.bags[AC_BAG_TYPE_GUILDBANK]
    self:Write("SETTINGS enabled=" .. tostring(AutoCategory.Enabled)
        .. " bulk=" .. tostring(AutoCategory.BulkMode)
        .. " ungroupedHidden=" .. tostring(bag and bag.isUngroupedHidden))
    self:Snapshot("START")
    d("[AutoCategory] Guild bank trace ON (LibDebugLogger Info, prefix [ACGB]).")
end

SLASH_COMMANDS["/acgbtrace"] = function(command)
    command = (command or ""):match("^%s*(.-)%s*$")
    local action, note = command:match("^(%S+)%s*(.*)$")
    action = action and action:lower() or ""
    if action == "on" then
        Trace:Start()
    elseif action == "off" then
        Trace:Write("STOP requested")
        Trace.enabled = false
        Trace.session = Trace.session + 1
        d("[AutoCategory] Guild bank trace OFF.")
    elseif action == "mark" or action == "dump" then
        if Trace.enabled then
            Trace:Write("MARK " .. text(note))
            Trace:Snapshot("MANUAL", nil, nil, true)
        else
            d("[AutoCategory] Start with /acgbtrace on.")
        end
    else
        d("[AutoCategory] /acgbtrace on | off | mark <visual symptom> | dump")
    end
end
