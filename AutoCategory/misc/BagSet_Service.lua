-- ============================================================================
-- BagSet_Service.lua
-- Service layer for AutoCategory Bag Settings
-- Encapsulates all bag-related business logic, data access, and events
-- ============================================================================

local AC = AutoCategory
local SF = LibSFUtils

if not AC then
    error("BagSet_Service: AutoCategory not found in global namespace")
end

-- Cache commonly used functions for performance
local logDebug = AC.logDebug
local logWouldDebug = AC.logWouldDebug

-- Local module state (private)
local _M = {
    _eventListeners = {},
    _initialized = false
}

-- Public service object
local BagSet_Service = {}
AC_UI.BagSet_Service = BagSet_Service  -- Export to global AC_UI namespace

-- ============================================================================
-- EVENT SYSTEM
-- ============================================================================

BagSet_Service.EVENTS = {
    BAG_CHANGED           = "bag_changed",              -- Payload: bagId
    RULE_ADDED            = "rule_added",               -- Payload: {bagId, ruleName, entry}
    RULE_REMOVED          = "rule_removed",             -- Payload: {bagId, ruleName}
    RULE_UPDATED          = "rule_updated",             -- Payload: {bagId, ruleName, field, oldValue, newValue}
    RULE_PRIORITY_CHANGED = "rule_priority_changed",    -- Payload: {bagId, ruleName, runPriority, showPriority}
    CACHE_INVALIDATED     = "cache_invalidated",        -- Payload: nil (global invalidation)
    DISPLAY_ORDER_REFRESH = "display_order_refresh"     -- Payload: bagId
}

-- Subscribe to an event
function BagSet_Service.Subscribe(event, callback)
    if type(event) ~= "string" then
        logDebug("Subscribe failed: event must be string, got %s", type(event))
        return false
    end
    if type(callback) ~= "function" then
        logDebug("Subscribe failed: callback must be function, got %s", type(callback))
        return false
    end
    
    if not _M._eventListeners[event] then
        _M._eventListeners[event] = {}
    end
    
    -- Check for duplicate subscription
    for _, existingCb in ipairs(_M._eventListeners[event]) do
        if existingCb == callback then
            logDebug("Warning: Duplicate subscription for event '%s'", event)
            return true  -- Already subscribed, no need to add again
        end
    end
    
    table.insert(_M._eventListeners[event], callback)
    logDebug("Subscribed to event: %s", event)
    return true
end

-- Unsubscribe from an event
function BagSet_Service.Unsubscribe(event, callback)
    local listeners = _M._eventListeners[event]
    if not listeners then
        logDebug("Unsubscribe failed: no listeners for event '%s'", event)
        return false
    end
    
    for i = #listeners, 1, -1 do
        if listeners[i] == callback then
            table.remove(listeners, i)
            logDebug("Unsubscribed from event: %s", event)
            
            -- Clean up empty event table
            if #listeners == 0 then
                _M._eventListeners[event] = nil
            end
            return true
        end
    end
    
    logDebug("Unsubscribe failed: callback not found for event '%s'", event)
    return false
end

-- Dispatch event to all subscribers
function BagSet_Service.DispatchEvent(event, payload)
    local listeners = _M._eventListeners[event]
    if not listeners or #listeners == 0 then
        return
    end
    
    logDebug("Dispatching event: %s", event)
    
    -- Create a shallow copy of listeners to handle dynamic unsubscription
    local listenersCopy = {}
    for _, cb in ipairs(listeners) do
        listenersCopy[#listenersCopy + 1] = cb
    end
    
    for _, callback in ipairs(listenersCopy) do
        local success, err = pcall(callback, payload)
        if not success then
            logDebug("Event handler error for '%s': %s", event, tostring(err))
        end
    end
end

-- ============================================================================
-- DATA ACCESS LAYER
-- ============================================================================

-- Get bag settings safely (creates default if missing)
function BagSet_Service.GetBagSettings(bagId)
    if not bagId then
        bagId = AC.getCurrentBagId()
    end
    
    if not bagId then
        logDebug("GetBagSettings: bagId is nil")
        return nil
    end
    
    local saved = AC.saved
    if not saved then
        logDebug("GetBagSettings: AC.saved is nil")
        return nil
    end
    
    if not saved.bags then
        logDebug("GetBagSettings: initializing saved.bags table")
        saved.bags = {}
    end
    
    if not saved.bags[bagId] then
        logDebug("GetBagSettings: creating default settings for bagId %s", bagId)
        saved.bags[bagId] = {
            isUngroupedHidden = false,
            rules = {}
        }
    end
    
    return saved.bags[bagId]
end

-- Get cached bag rules (read-only access to runtime cache)
function BagSet_Service.GetCachedRules(bagId)
    bagId = bagId or AC.getCurrentBagId()
    
    if not bagId then
        logDebug("GetCachedRules: bagId is nil")
        return nil
    end
    
    if not AC.cache then
        logDebug("GetCachedRules: AC.cache is nil")
        return nil
    end
    
    if not AC.cache.entriesByBag then
        logDebug("GetCachedRules: AC.cache.entriesByBag is nil")
        return nil
    end
    
    return AC.cache.entriesByBag[bagId]
end

-- Get specific bag rule entry from cache
function BagSet_Service.GetBagRule(bagId, ruleName)
    bagId = bagId or AC.getCurrentBagId()
    
    if not bagId or not ruleName then
        logDebug("GetBagRule: bagId=%s, ruleName=%s", tostring(bagId), tostring(ruleName))
        return nil
    end
    
    if not AC.cache or not AC.cache.entriesByName then
        logDebug("GetBagRule: cache.entriesByName is nil")
        return nil
    end
    
    if not AC.cache.entriesByName[bagId] then
        logDebug("GetBagRule: cache.entriesByName[%s] is nil", bagId)
        return nil
    end
    
    return AC.cache.entriesByName[bagId][ruleName]
end

-- Get rule definition from RulesW (the master rule catalog)
function BagSet_Service.GetMasterRule(ruleName)
    if not ruleName then
        logDebug("GetMasterRule: ruleName is nil")
        return nil
    end
    
    if not AC.RulesW or not AC.RulesW.ruleNames then
        logDebug("GetMasterRule: AC.RulesW.ruleNames is nil")
        return nil
    end
    
    local idx = AC.RulesW.ruleNames[ruleName]
    if not idx then
        logDebug("GetMasterRule: rule '%s' not found in RulesW", ruleName)
        return nil
    end
    
    if not AC.RulesW.ruleList[idx] then
        logDebug("GetMasterRule: ruleList[%d] is nil", idx)
        return nil
    end
    
    return AC.RulesW.ruleList[idx]
end

-- Get available rules (in master catalog but not in bag)
function BagSet_Service.GetAvailableRules(bagId, tag)
    bagId = bagId or AC.getCurrentBagId()
    
    if not bagId or not tag then
        logDebug("GetAvailableRules: invalid args bagId=%s, tag=%s", tostring(bagId), tostring(tag))
        return {}
    end
    
    -- Ensure cache structure exists
    if not AC.cache.entriesByName then
        AC.cache.entriesByName = {}
    end
    if not AC.cache.entriesByName[bagId] then
        AC.cache.entriesByName[bagId] = SF.safeTable({})
    end
    
    local usedRules = AC.cache.entriesByName[bagId]
    local tagGroup = AC.RulesW.tagGroups and AC.RulesW.tagGroups[tag]
    
    if not tagGroup then
        logDebug("GetAvailableRules: tagGroup for '%s' not found", tag)
        return {}
    end
    
    local available = {}
    local size = tagGroup:size()
    
    for i = 1, size do
        local ruleName = tagGroup.choices[i]
        if ruleName and not usedRules[ruleName] then
            available[#available + 1] = ruleName
        end
    end
    
    logDebug("GetAvailableRules: found %d available rules for tag '%s'", #available, tag)
    return available
end

-- Get all bags
function BagSet_Service.GetAllBags()
    if not AC.saved or not AC.saved.bags then
        logDebug("GetAllBags: no saved.bags exists")
        return {}
    end
    
    local bags = {}
    for bagId, settings in pairs(AC.saved.bags) do
        bags[#bags + 1] = {
            bagId = bagId,
            ruleCount = settings.rules and #settings.rules or 0,
            isUngroupedHidden = settings.isUngroupedHidden or false
        }
    end
    
    return bags
end

-- ============================================================================
-- BUSINESS LOGIC OPERATIONS
-- ============================================================================

-- Add rule to bag with validation
function BagSet_Service.AddRuleToBag(bagId, ruleName)
    bagId = bagId or AC.getCurrentBagId()
    
    if not bagId then
        return false, "No bag selected"
    end
    
    if not ruleName then
        return false, "No rule specified"
    end
    
    -- Validate rule exists in master catalog
    local rule = BagSet_Service.GetMasterRule(ruleName)
    if not rule then
        logDebug("AddRuleToBag: master rule '%s' not found", ruleName)
        return false, "Rule does not exist in catalog"
    end
    
    -- Check for duplicates in target bag
    local existing = BagSet_Service.GetBagRule(bagId, ruleName)
    if existing then
        logDebug("AddRuleToBag: rule '%s' already in bag %s", ruleName, bagId)
        return false, "Rule already added to this bag"
    end
    
    -- Get/create bag settings
    local settings = BagSet_Service.GetBagSettings(bagId)
    if not settings then
        logDebug("AddRuleToBag: failed to get bag settings for %s", bagId)
        return false, "Failed to access bag settings"
    end
    
    -- Create new bag rule entry with defaults
    local entry = AC.CreateBagRule(ruleName)
    if not entry then
        logDebug("AddRuleToBag: CreateBagRule returned nil")
        return false, "Failed to create bag rule entry"
    end
    
    -- Insert into bag rules list
    settings.rules[#settings.rules + 1] = entry
    logDebug("Added rule '%s' to bag %s (position %d)", ruleName, bagId, #settings.rules)
    
    -- Invalidate cache
    local cacheSuccess = AC.cacheBagInitialize()
    if not cacheSuccess then
        logDebug("AddRuleToBag: warning - cache invalidation returned false")
    end
    
    -- Fire events
    BagSet_Service.DispatchEvent(BagSet_Service.EVENTS.RULE_ADDED, {
        bagId = bagId,
        ruleName = ruleName,
        entry = entry
    })
    
    BagSet_Service.DispatchEvent(BagSet_Service.EVENTS.BAG_CHANGED, bagId)
    
    return true, nil
end

-- Remove rule from bag with cascade cleanup
function BagSet_Service.RemoveRuleFromBag(bagId, ruleName)
    bagId = bagId or AC.getCurrentBagId()
    
    if not bagId or not ruleName then
        return false, "Invalid arguments"
    end
    
    -- Get bag settings
    local settings = BagSet_Service.GetBagSettings(bagId)
    if not settings or not settings.rules then
        logDebug("RemoveRuleFromBag: bag settings or rules list is nil for %s", bagId)
        return false, "Bag settings not found"
    end
    
    -- Find rule in list
    local foundIndex = nil
    for i = #settings.rules, 1, -1 do  -- Reverse iteration for safety
        if settings.rules[i].name == ruleName then
            foundIndex = i
            break
        end
    end
    
    if not foundIndex then
        logDebug("RemoveRuleFromBag: rule '%s' not found in bag %s", ruleName, bagId)
        return false, "Rule not found in bag"
    end
    
    -- Store rule info for event payload
    local removedEntry = settings.rules[foundIndex]
    
    -- Remove from bag rules list
    table.remove(settings.rules, foundIndex)
    logDebug("Removed rule '%s' from bag %s (was at position %d)", ruleName, bagId, foundIndex)
    
    -- Invalidate cache
    AC.cacheBagInitialize()
    
    -- Fire events
    BagSet_Service.DispatchEvent(BagSet_Service.EVENTS.RULE_REMOVED, {
        bagId = bagId,
        ruleName = ruleName,
        wasActive = (AC.UI_ACTIVE_BAG_RULE == ruleName)  -- Check against current selection
    })
    
    BagSet_Service.DispatchEvent(BagSet_Service.EVENTS.BAG_CHANGED, bagId)
    
    return true, nil
end

-- Update bag rule field
function BagSet_Service.UpdateBagRuleField(bagId, ruleName, field, value)
    bagId = bagId or AC.getCurrentBagId()
    
    if not bagId or not ruleName or not field then
        return false, "Invalid arguments"
    end
    
    local bagRule = BagSet_Service.GetBagRule(bagId, ruleName)
    if not bagRule then
        logDebug("UpdateBagRuleField: bag rule not found for %s/%s", bagId, ruleName)
        return false, "Bag rule not found"
    end
    
    -- Track old value for event
    local oldValue = bagRule[field]
    
    -- Normalize value (convert false/0 to nil for optional fields)
    if value == false or value == 0 then
        value = nil
    end
    
    -- Apply change
    bagRule[field] = value
    
    logDebug("Updated %s.%s from %s to %s", ruleName, field, tostring(oldValue), tostring(value))
    
    -- Invalidate cache
    AC.cacheInitialize()
    
    -- Fire event
    BagSet_Service.DispatchEvent(BagSet_Service.EVENTS.RULE_UPDATED, {
        bagId = bagId,
        ruleName = ruleName,
        field = field,
        oldValue = oldValue,
        newValue = value
    })
    
    return true, nil
end

-- Update run priority
function BagSet_Service.SetRunPriority(bagId, ruleName, runPriority)
    bagId = bagId or AC.getCurrentBagId()
    
    -- Clamp value
    runPriority = math.max(2, math.min(1000, tonumber(runPriority) or 2))
    
    local success, err = BagSet_Service.UpdateBagRuleField(bagId, ruleName, "runpriority", runPriority)
    if not success then
        return false, err
    end
    
    -- Also update showpriority if it matches current runpriority (sync behavior)
    local bagRule = BagSet_Service.GetBagRule(bagId, ruleName)
    if bagRule and bagRule.showpriority == runPriority then
        bagRule.showpriority = runPriority
    end
    
    BagSet_Service.DispatchEvent(BagSet_Service.EVENTS.RULE_PRIORITY_CHANGED, {
        bagId = bagId,
        ruleName = ruleName,
        runPriority = runPriority,
        showPriority = bagRule.showpriority
    })
    
    return true, nil
end

-- Update show priority
function BagSet_Service.SetShowPriority(bagId, ruleName, showPriority)
    bagId = bagId or AC.getCurrentBagId()
    
    -- Clamp value
    showPriority = math.max(2, math.min(1000, tonumber(showPriority) or 2))
    
    local success, err = BagSet_Service.UpdateBagRuleField(bagId, ruleName, "showpriority", showPriority)
    if not success then
        return false, err
    end
    
    BagSet_Service.DispatchEvent(BagSet_Service.EVENTS.RULE_PRIORITY_CHANGED, {
        bagId = bagId,
        ruleName = ruleName,
        runPriority = BagSet_Service.GetBagRule(bagId, ruleName).runpriority,
        showPriority = showPriority
    })
    
    return true, nil
end

-- Set hide status for category
function BagSet_Service.SetCategoryHidden(bagId, ruleName, isHidden)
    return BagSet_Service.UpdateBagRuleField(bagId, ruleName, "isHidden", isHidden)
end

-- Show category (opposite of hide)
function BagSet_Service.ShowCategory(bagId, ruleName)
    return BagSet_Service.SetCategoryHidden(bagId, ruleName, false)
end

-- Hide category
function BagSet_Service.HideCategory(bagId, ruleName)
    return BagSet_Service.SetCategoryHidden(bagId, ruleName, true)
end

-- Toggle hide status
function BagSet_Service.ToggleCategoryHidden(bagId, ruleName)
    local bagRule = BagSet_Service.GetBagRule(bagId, ruleName)
    if not bagRule then
        return false, "Bag rule not found"
    end
    
    local currentHidden = bagRule.isHidden or false
    return BagSet_Service.SetCategoryHidden(bagId, ruleName, not currentHidden)
end

-- Reset single priority (showpriority = runpriority)
function BagSet_Service.ResetPriority(bagId, ruleName)
    bagId = bagId or AC.getCurrentBagId()
    
    local bagRule = BagSet_Service.GetBagRule(bagId, ruleName)
    if not bagRule then
        return false, "Bag rule not found"
    end
    
    local runPriority = bagRule.runpriority or 2
    bagRule.showpriority = runPriority
    
    AC.cacheInitialize()
    
    BagSet_Service.DispatchEvent(BagSet_Service.EVENTS.RULE_PRIORITY_CHANGED, {
        bagId = bagId,
        ruleName = ruleName,
        runPriority = runPriority,
        showPriority = runPriority
    })
    
    return true, nil
end

-- Reset all priorities in bag
function BagSet_Service.ResetAllPriorities(bagId)
    bagId = bagId or AC.getCurrentBagId()
    
    local cached = BagSet_Service.GetCachedRules(bagId)
    if not cached or not cached.choicesValues then
        logDebug("ResetAllPriorities: no cached rules for bag %s", bagId)
        return false, "No cached rules found"
    end
    
    local count = 0
    for _, ruleName in ipairs(cached.choicesValues) do
        local success = BagSet_Service.ResetPriority(bagId, ruleName)
        if success then
            count = count + 1
        end
    end
    
    logDebug("ResetAllPriorities: reset %d rules in bag %s", count, bagId)
    
    BagSet_Service.DispatchEvent(BagSet_Service.EVENTS.BAG_CHANGED, bagId)
    
    return true, nil
end

-- Set ungrouped hidden status
function BagSet_Service.SetUngroupedHidden(bagId, isHidden)
    bagId = bagId or AC.getCurrentBagId()
    
    local settings = BagSet_Service.GetBagSettings(bagId)
    if not settings then
        return false, "Bag settings not found"
    end
    
    -- Normalize value
    if isHidden == false then
        isHidden = nil
    end
    
    local oldValue = settings.isUngroupedHidden
    settings.isUngroupedHidden = isHidden
    
    logDebug("SetUngroupedHidden: bag %s changed from %s to %s", bagId, tostring(oldValue), tostring(isHidden))
    
    BagSet_Service.DispatchEvent(BagSet_Service.EVENTS.BAG_CHANGED, bagId)
    
    return true, nil
end

-- ============================================================================
-- IMPORT/EXPORT FUNCTIONALITY
-- ============================================================================

-- Deep copy bag settings from source to destination
function BagSet_Service.CopyBagToBag(srcBagId, destBagId)
    if not srcBagId or not destBagId then
        logDebug("CopyBagToBag: invalid bagIds src=%s, dest=%s", tostring(srcBagId), tostring(destBagId))
        return false, "Invalid bag IDs"
    end
    
    if srcBagId == destBagId then
        logDebug("CopyBagToBag: source and destination are the same bag")
        return false, "Source and destination cannot be the same"
    end
    
    -- Get source settings
    local srcSettings = BagSet_Service.GetBagSettings(srcBagId)
    if not srcSettings then
        logDebug("CopyBagToBag: source settings not found for %s", srcBagId)
        return false, "Source bag settings not found"
    end
    
    -- Deep copy using SF
    local copiedSettings = SF.deepCopy(srcSettings)
    if not copiedSettings then
        logDebug("CopyBagToBag: deepCopy returned nil")
        return false, "Deep copy failed"
    end
    
    -- Store in destination
    if not AC.saved then
        AC.saved = {}
    end
    if not AC.saved.bags then
        AC.saved.bags = {}
    end
    
    AC.saved.bags[destBagId] = copiedSettings
    
    logDebug("Copied bag settings from %s to %s (rules: %d)", 
              srcBagId, destBagId, #copiedSettings.rules)
    
    -- Invalidate caches
    AC.cacheInitialize()
    AC.cacheBagInitialize()
    
    -- Fire events
    BagSet_Service.DispatchEvent(BagSet_Service.EVENTS.BAG_CHANGED, destBagId)
    BagSet_Service.DispatchEvent(BagSet_Service.EVENTS.CACHE_INVALIDATED)
    
    return true, nil
end

-- Export current bag to all other bags
function BagSet_Service.ExportCurrentToAll(targetBagId)
    targetBagId = targetBagId or AC.getCurrentBagId()
    
    if not targetBagId then
        return false, "No bag selected for export"
    end
    
    local sourceSettings = BagSet_Service.GetBagSettings(targetBagId)
    if not sourceSettings then
        return false, "Target bag settings not found"
    end
    
    local exportedCount = 0
    
    AC.foreachBag(function(bagId)
        if bagId ~= targetBagId then
            local success = BagSet_Service.CopyBagToBag(targetBagId, bagId)
            if success then
                exportedCount = exportedCount + 1
            end
        end
    end)
    
    logDebug("ExportComplete: exported to %d bags", exportedCount)
    
    BagSet_Service.DispatchEvent(BagSet_Service.EVENTS.CACHE_INVALIDATED)
    
    return true, exportedCount
end

-- Import settings from another bag
function BagSet_Service.ImportFromBag(srcBagId)
    local destBagId = AC.getCurrentBagId()
    return BagSet_Service.CopyBagToBag(srcBagId, destBagId)
end

-- Clear all rules from a bag
function BagSet_Service.ClearBagRules(bagId)
    bagId = bagId or AC.getCurrentBagId()
    
    local settings = BagSet_Service.GetBagSettings(bagId)
    if not settings then
        return false, "Bag settings not found"
    end
    
    local removedCount = #settings.rules
    
    -- Clear all rules
    settings.rules = {}
    
    -- Invalidate cache
    AC.cacheBagInitialize()
    
    logDebug("ClearBagRules: removed %d rules from bag %s", removedCount, bagId)
    
    BagSet_Service.DispatchEvent(BagSet_Service.EVENTS.BAG_CHANGED, bagId)
    
    return true, removedCount
end

-- ============================================================================
-- UTILITY & QUERY FUNCTIONS
-- ============================================================================

-- Count rules in a bag
function BagSet_Service.GetRuleCount(bagId)
    local settings = BagSet_Service.GetBagSettings(bagId)
    return settings and #settings.rules or 0
end

-- Check if rule exists in bag
function BagSet_Service.RuleExistsInBag(bagId, ruleName)
    return BagSet_Service.GetBagRule(bagId, ruleName) ~= nil
end

-- Get all rule names in a bag (ordered as stored)
function BagSet_Service.GetBagRuleNames(bagId)
    local settings = BagSet_Service.GetBagSettings(bagId)
    if not settings or not settings.rules then
        return {}
    end
    
    local names = {}
    for _, entry in ipairs(settings.rules) do
        names[#names + 1] = entry.name
    end
    
    return names
end

-- Get rules sorted by priority
function BagSet_Service.GetBagRulesSorted(bagId, sortBy)
    bagId = bagId or AC.getCurrentBagId()
    sortBy = sortBy or "runpriority"  -- or "showpriority"
    
    local rules = {}
    local cache = BagSet_Service.GetCachedRules(bagId)
    
    if not cache or not cache.choicesValues then
        return rules
    end
    
    for _, ruleName in ipairs(cache.choicesValues) do
        local bagRule = BagSet_Service.GetBagRule(bagId, ruleName)
        if bagRule then
            rules[#rules + 1] = {
                name = ruleName,
                priority = bagRule[sortBy] or 2
            }
        end
    end
    
    -- Sort by priority (ascending = higher priority first)
    table.sort(rules, function(a, b)
        return a.priority < b.priority
    end)
    
    return rules
end

-- Get all bags containing a specific rule
function BagSet_Service.FindBagsContainingRule(ruleName)
    if not ruleName then
        return {}
    end
    
    local containingBags = {}
    
    AC.foreachBag(function(bagId)
        if BagSet_Service.RuleExistsInBag(bagId, ruleName) then
            containingBags[#containingBags + 1] = bagId
        end
    end)
    
    return containingBags
end

-- Validate bag configuration integrity
function BagSet_Service.ValidateBagIntegrity(bagId)
    bagId = bagId or AC.getCurrentBagId()
    
    local issues = {}
    local settings = BagSet_Service.GetBagSettings(bagId)
    
    if not settings then
        table.insert(issues, "Bag settings missing")
        return false, issues
    end
    
    -- Check each rule exists in master catalog
    for i, entry in ipairs(settings.rules) do
        if not entry.name then
            table.insert(issues, string.format("Rule %d has no name", i))
        elseif not BagSet_Service.GetMasterRule(entry.name) then
            table.insert(issues, string.format("Rule '%s' in bag %s not found in catalog", entry.name, bagId))
        end
    end
    
    -- Check cache consistency
    local cached = BagSet_Service.GetCachedRules(bagId)
    if cached and cached.choicesValues then
        for _, ruleName in ipairs(cached.choicesValues) do
            if not BagSet_Service.RuleExistsInBag(bagId, ruleName) then
                table.insert(issues, string.format("Rule '%s' in cache but not in bag settings", ruleName))
            end
        end
    end
    
    local isValid = #issues == 0
    if not isValid then
        logDebug("ValidateBagIntegrity: bag %s has %d issues", bagId, #issues)
        for _, issue in ipairs(issues) do
            logDebug("  - %s", issue)
        end
    end
    
    return isValid, issues
end

-- Rebuild cache for a bag
function BagSet_Service.RebuildBagCache(bagId)
    bagId = bagId or AC.getCurrentBagId()
    
    logDebug("RebuildBagCache: rebuilding cache for bag %s", bagId)
    
    AC.cacheBagInitialize()
    
    -- Verify cache was built
    local cached = BagSet_Service.GetCachedRules(bagId)
    if not cached then
        logDebug("RebuildBagCache: cache rebuild failed for %s", bagId)
        return false
    end
    
    logDebug("RebuildBagCache: cache rebuilt successfully (%d rules)", 
              #cached.choicesValues)
    
    BagSet_Service.DispatchEvent(BagSet_Service.EVENTS.CACHE_INVALIDATED)
    
    return true
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

function BagSet_Service.Init()
    if _M._initialized then
        logDebug("Init: already initialized")
        return true
    end
    
    logDebug("Init: starting initialization")
    
    -- Ensure saved.bags exists
    if not AC.saved then
        AC.saved = {}
    end
    if not AC.saved.bags then
        AC.saved.bags = {}
        logDebug("Init: created AC.saved.bags table")
    end
    
    -- Ensure cache structures exist
    if not AC.cache then
        AC.cache = {}
    end
    if not AC.cache.entriesByName then
        AC.cache.entriesByName = {}
    end
    if not AC.cache.entriesByBag then
        AC.cache.entriesByBag = {}
    end
    
    -- Mark as initialized
    _M._initialized = true
    
    logDebug("Init: initialization complete")
    
    return true
end

-- Shutdown/cleanup (called on addon disable)
function BagSet_Service.Shutdown()
    logDebug("Shutdown: cleaning up")
    
    -- Clear all event listeners
    _M._eventListeners = {}
    
    _M._initialized = false
    
    logDebug("Shutdown: complete")
end

-- ============================================================================
-- PUBLIC API SUMMARY (for reference)
-- ============================================================================
--[[
-- Event System
BagSet_Service.Subscribe(event, callback)
BagSet_Service.Unsubscribe(event, callback)
BagSet_Service.DispatchEvent(event, payload)
BagSet_Service.EVENTS (table of event constants)

-- Data Access
BagSet_Service.GetBagSettings(bagId)
BagSet_Service.GetCachedRules(bagId)
BagSet_Service.GetBagRule(bagId, ruleName)
BagSet_Service.GetMasterRule(ruleName)
BagSet_Service.GetAvailableRules(bagId, tag)
BagSet_Service.GetAllBags()

-- Business Logic
BagSet_Service.AddRuleToBag(bagId, ruleName)
BagSet_Service.RemoveRuleFromBag(bagId, ruleName)
BagSet_Service.UpdateBagRuleField(bagId, ruleName, field, value)
BagSet_Service.SetRunPriority(bagId, ruleName, runPriority)
BagSet_Service.SetShowPriority(bagId, ruleName, showPriority)
BagSet_Service.SetCategoryHidden(bagId, ruleName, isHidden)
BagSet_Service.ShowCategory(bagId, ruleName)
BagSet_Service.HideCategory(bagId, ruleName)
BagSet_Service.ToggleCategoryHidden(bagId, ruleName)
BagSet_Service.ResetPriority(bagId, ruleName)
BagSet_Service.ResetAllPriorities(bagId)
BagSet_Service.SetUngroupedHidden(bagId, isHidden)

-- Import/Export
BagSet_Service.CopyBagToBag(srcBagId, destBagId)
BagSet_Service.ExportCurrentToAll(targetBagId)
BagSet_Service.ImportFromBag(srcBagId)
BagSet_Service.ClearBagRules(bagId)

-- Utilities
BagSet_Service.GetRuleCount(bagId)
BagSet_Service.RuleExistsInBag(bagId, ruleName)
BagSet_Service.GetBagRuleNames(bagId)
BagSet_Service.GetBagRulesSorted(bagId, sortBy)
BagSet_Service.FindBagsContainingRule(ruleName)
BagSet_Service.ValidateBagIntegrity(bagId)
BagSet_Service.RebuildBagCache(bagId)

-- Lifecycle
BagSet_Service.Init()
BagSet_Service.Shutdown()
]]
