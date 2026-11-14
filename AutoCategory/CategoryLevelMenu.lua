-- CategoryLevelMenu: level operations on a category from the inventory
-- header context menu (right click on a category header in any keyboard
-- inventory list).
--
-- The menu operates on the rule (the global category definition) of the
-- clicked header: the whole displayed name for a flat category, else the
-- deepest level of the name chain (the rule that matched the items under
-- the header). The operations apply to the category and every category
-- nested under it in the SAME bag as the clicked header (its bag rules
-- whose parent chain contains it).
--
-- Levels and parents are properties of the global rules, shared by every
-- bag: re-levelling a category here re-levels it in every bag that shows
-- it. Copying to another bag reuses the global rules (like the "Export
-- all" button) - it only adds bag rules to the destination bag, and the
-- categories already present there are skipped. Deleting removes the
-- category from the clicked bag only (like the Remove Category button);
-- the global rule stays.

AutoCategory = AutoCategory or {}

local CategoryTree = AutoCategory.CategoryTree

local CLM = {}
AutoCategory.CategoryLevelMenu = CLM

-- The sub-menu level of a rule for the level logic: the Level dropdown
-- value when it is a whole number 1-5, and 1 for everything else (the
-- same effective level as MatchCategoryRules: a Normal category counts
-- as a top-level category).
function CLM.EffectiveLevel(rule)
    local lv = rule and rule.level
    if type(lv) == "number" and lv >= 1 and lv <= 5
            and lv == math.floor(lv) then
        return lv
    end
    return 1
end

-- Is the value an explicit Level dropdown value (1-5), as opposed to
-- Normal (no level set)?
local function isExplicitLevel(lv)
    return type(lv) == "number" and lv >= 1 and lv <= 5
        and lv == math.floor(lv)
end

-- The rule (category definition) of a clicked header: the whole
-- displayed name for a flat category (including a legacy hierarchical
-- "----" name), else the deepest level of the name chain - the rule
-- that matched the items under the header. Returns nil for the
-- "Others" category, dynamic plugin categories and names with no
-- backing rule.
function CLM.HeaderRule(cateName)
    if type(cateName) ~= "string" then return nil end

    local rule = AutoCategory.GetRuleByName(cateName)
    if rule then return rule end

    if CategoryTree then
        local levels = CategoryTree.Levels(cateName)
        if levels and #levels > 1 then
            rule = AutoCategory.GetRuleByName(levels[#levels])
        end
    end
    return rule
end

-- The bag rule of a name in a bag, or nil. A direct scan of the saved
-- bag rules (the cache lookups are refreshed separately).
local function findBagrule(bagTypeId, ruleName)
    local saved = AutoCategory.saved
    local savedBag = saved and saved.bags and saved.bags[bagTypeId]
    if not savedBag or not savedBag.rules then return nil end

    for i = 1, #savedBag.rules do
        local bagrule = savedBag.rules[i]
        if bagrule and bagrule.name == ruleName then
            return bagrule
        end
    end
    return nil
end

-- Every category of the bag whose parent chain (the Parent dropdown
-- chain) contains ruleName: the categories nested under the category,
-- in the order of the bag's rule list. The category itself is never
-- included, and a chain that loops stops at the first repeated name.
function CLM.DescendantsInBag(bagTypeId, ruleName)
    local result = {}
    local saved = AutoCategory.saved
    local savedBag = saved and saved.bags and saved.bags[bagTypeId]
    if not savedBag or not savedBag.rules or not ruleName then
        return result
    end

    for i = 1, #savedBag.rules do
        local bagrule = savedBag.rules[i]
        local rule = bagrule and AutoCategory.GetRuleByName(bagrule.name)
        if rule and rule.name ~= ruleName then
            local visited = { [rule.name] = true }
            local crule = rule
            while crule do
                local parent = crule.parent
                if type(parent) ~= "string" or parent == "" then
                    break
                end
                if parent == ruleName then
                    result[#result + 1] = { bagrule = bagrule, rule = rule }
                    break
                end
                if visited[parent] then break end
                visited[parent] = true
                crule = AutoCategory.GetRuleByName(parent)
            end
        end
    end
    return result
end

-- The category and the categories nested under it in the bag, as
-- { rule = ..., bagrule = ... } entries, the category first. Returns
-- nil when the category is not a category of the bag.
function CLM.SubtreeInBag(bagTypeId, ruleName)
    local rootBagrule = findBagrule(bagTypeId, ruleName)
    if not rootBagrule then return nil end
    local rootRule = AutoCategory.GetRuleByName(ruleName)
    if not rootRule then return nil end

    local subtree = { { rule = rootRule, bagrule = rootBagrule } }
    local descendants = CLM.DescendantsInBag(bagTypeId, ruleName)
    for i = 1, #descendants do
        subtree[#subtree + 1] = descendants[i]
    end
    return subtree
end

-- Can every category of the subtree move one level deeper? Level 5 is
-- the deepest level the addon offers.
function CLM.CanIncrease(subtree)
    for i = 1, #subtree do
        if CLM.EffectiveLevel(subtree[i].rule) >= 5 then
            return false
        end
    end
    return true
end

-- Is there anything to decrease: an explicit level on the category or
-- any of the categories nested under it (level 1 becomes Normal, the
-- plain top-level category).
function CLM.CanDecrease(subtree)
    for i = 1, #subtree do
        if isExplicitLevel(subtree[i].rule.level) then
            return true
        end
    end
    return false
end

-- The nearest category of the level just above rootName in the display
-- order of the bag (show priority high to low, then name), or the
-- first one when rootName sits above them all - the same choice as the
-- automatic parent attachment of Edit Category. The categories of the
-- subtree are never candidates (the root cannot nest under its own
-- descendants).
local function nearestAncestorName(bagTypeId, rootRule, targetLevel, subtree)
    local saved = AutoCategory.saved
    local savedBag = saved and saved.bags and saved.bags[bagTypeId]
    if not savedBag or not savedBag.rules then return nil end

    local excluded = {}
    for i = 1, #subtree do
        excluded[subtree[i].rule.name] = true
    end

    local ordered = {}
    for i = 1, #savedBag.rules do
        local brule = savedBag.rules[i]
        if brule and type(brule.name) == "string" and brule.name ~= "" then
            ordered[#ordered + 1] = brule
        end
    end
    table.sort(ordered, function(a, b)
        local ap = a.showpriority or a.runpriority or 0
        local bp = b.showpriority or b.runpriority or 0
        if ap ~= bp then
            return ap > bp
        end
        return a.name < b.name
    end)

    local nearest, first, passedSelf
    for i = 1, #ordered do
        local brule = ordered[i]
        if brule.name == rootRule.name then
            passedSelf = true
        else
            local r = AutoCategory.GetRuleByName(brule.name)
            if r and not excluded[r.name]
                    and CLM.EffectiveLevel(r) == targetLevel then
                first = first or brule.name
                if not passedSelf then
                    nearest = brule.name
                end
            end
        end
    end
    return nearest or first
end

-- Move every category of the subtree one level deeper (delta 1) or
-- shallower (delta -1). Deeper: the category keeps its parent, or is
-- attached to the nearest category of the level just above it in the
-- display order of the bag when it had none. Shallower: an explicit
-- level 1 becomes Normal (the plain top-level category) and the parent
-- is cleared; a level 2-5 category keeps a parent only while its level
-- stays 2-5. Returns true when the levels changed, false when the move
-- was refused (a category of the subtree is already at level 5) or
-- there was nothing to decrease.
function CLM.ShiftLevels(bagTypeId, subtree, delta)
    if delta ~= 1 and delta ~= -1 then return false end
    if delta == 1 and not CLM.CanIncrease(subtree) then return false end
    if delta == -1 and not CLM.CanDecrease(subtree) then return false end

    -- the new parent of the category when it moves deeper and has
    -- none: the nearest category of its old level above it
    local newRootParent
    if delta == 1 then
        local root = subtree[1].rule
        if not (type(root.parent) == "string" and root.parent ~= "") then
            newRootParent = nearestAncestorName(bagTypeId, root,
                CLM.EffectiveLevel(root), subtree)
        end
    end

    for i = 1, #subtree do
        local rule = subtree[i].rule
        local newLevel = CLM.EffectiveLevel(rule) + delta
        if newLevel <= 1 then
            rule.level = nil
            rule.parent = nil
        else
            rule.level = newLevel
        end
    end
    if newRootParent then
        subtree[1].rule.parent = newRootParent
    end
    return true
end

-- Copy the category and the categories nested under it to another bag.
-- The rules are global and shared: the copy reuses them, exactly like
-- the "Export all" button of Bag Settings - editing the category in
-- one bag changes it everywhere. Categories already present in the
-- destination bag are skipped. The ancestors of the category are copied
-- with it when they are not categories of the destination bag yet, so
-- the category keeps its place in the level hierarchy there (without
-- them a level 2-5 category displays flat in that bag).
-- Returns copied, skipped: the number of categories added to the
-- destination bag, and the number of the subtree categories that were
-- already present there.
function CLM.CopySubtreeToBag(srcBagTypeId, ruleName, destBagTypeId)
    local copied, skipped = 0, 0
    if srcBagTypeId == destBagTypeId then return copied, skipped end

    local subtree = CLM.SubtreeInBag(srcBagTypeId, ruleName)
    if not subtree then return copied, skipped end

    local saved = AutoCategory.saved
    local destBag = saved and saved.bags and saved.bags[destBagTypeId]
    if not destBag or not destBag.rules then return copied, skipped end

    local present = {}
    for i = 1, #destBag.rules do
        local bagrule = destBag.rules[i]
        if bagrule and bagrule.name then
            present[bagrule.name] = true
        end
    end

    -- the missing ancestors of the category, outermost first
    local chain = {}
    local visited = { [subtree[1].rule.name] = true }
    local crule = subtree[1].rule
    while crule do
        local parent = crule.parent
        if type(parent) ~= "string" or parent == "" then break end
        if visited[parent] then break end
        visited[parent] = true
        local prule = AutoCategory.GetRuleByName(parent)
        if not prule then break end
        table.insert(chain, 1, prule)
        crule = prule
    end

    -- what to add: the missing ancestors, then the missing categories
    -- of the subtree; the priorities of each category come from its own
    -- bag rule of the source bag, else from the copied category's
    local rootBagrule = subtree[1].bagrule
    local toAdd = {}
    local function queueCopy(rule)
        local srcBagrule = findBagrule(srcBagTypeId, rule.name)
        toAdd[#toAdd + 1] = {
            name = rule.name,
            runpriority = (srcBagrule and srcBagrule.runpriority)
                or rootBagrule.runpriority,
            showpriority = (srcBagrule and srcBagrule.showpriority)
                or rootBagrule.showpriority,
        }
    end
    for i = 1, #chain do
        if not present[chain[i].name] then
            queueCopy(chain[i])
        end
    end
    for i = 1, #subtree do
        if present[subtree[i].rule.name] then
            skipped = skipped + 1
        else
            queueCopy(subtree[i].rule)
        end
    end

    for i = 1, #toAdd do
        local item = toAdd[i]
        local entry = AutoCategory.CreateBagRule(item.name,
            item.runpriority, item.showpriority)
        if entry then
            destBag.rules[#destBag.rules + 1] = entry
            copied = copied + 1
        end
    end
    return copied, skipped
end

-- Create a new category nested under the clicked one: a new rule with
-- the rule text "false" - it never matches an item, so the new level
-- stays a pure display section until categories are nested under it -
-- one level deeper than the clicked category and parented to it, added
-- to the bag of the clicked header. Returns the new rule, or nil when
-- the clicked category is already at level 5.
function CLM.CreateSubLevel(bagTypeId, ruleName)
    local root = AutoCategory.GetRuleByName(ruleName)
    if not root then return nil end
    local level = CLM.EffectiveLevel(root)
    if level >= 5 then return nil end

    local newName = AutoCategory.GetUsableRuleName(
        GetString(SI_AC_DEFAULT_NAME_NEW_CATEGORY))
    local tag = root.tag
    if tag == nil or tag == "" then
        tag = GetString(SI_AC_DEFAULT_NAME_EMPTY_TAG)
    end

    local newRule = AutoCategory.CreateRule(newName, tag)
    newRule.rule = "false"
    newRule.level = level + 1
    newRule.parent = ruleName
    newRule:compile()

    AutoCategory.ARW:AddRule(newRule)
    AutoCategory.cache.AddRule(newRule)

    local saved = AutoCategory.saved
    local savedBag = saved and saved.bags and saved.bags[bagTypeId]
    if not savedBag or not savedBag.rules then return nil end

    local srcBagrule = findBagrule(bagTypeId, ruleName)
    local entry = AutoCategory.CreateBagRule(newName,
        srcBagrule and srcBagrule.runpriority,
        srcBagrule and srcBagrule.showpriority)
    if not entry then return nil end
    savedBag.rules[#savedBag.rules + 1] = entry
    return newRule
end

-- Delete the category from the bag of the clicked header only: the
-- global rule (shared by every bag) stays, exactly like the Remove
-- Category button of Bag Settings. Every category nested under it
-- moves up one level, and the ones directly under it nest under the
-- deleted category's own parent, so the section keeps its place
-- without the deleted level. The level and parent changes apply to
-- the global rules, so they show in every bag that has the categories.
-- Returns true when the category was removed from the bag.
function CLM.DeleteLevelInBag(bagTypeId, ruleName)
    local saved = AutoCategory.saved
    local savedBag = saved and saved.bags and saved.bags[bagTypeId]
    if not savedBag or not savedBag.rules then return false end

    local root = AutoCategory.GetRuleByName(ruleName)
    if not root then return false end

    local rootParent = root.parent
    if type(rootParent) ~= "string" or rootParent == "" then
        rootParent = nil
    end

    local descendants = CLM.DescendantsInBag(bagTypeId, ruleName)

    -- remove the category from the bag (only the bag rule: the global
    -- rule is kept)
    local removed = false
    for i = #savedBag.rules, 1, -1 do
        local bagrule = savedBag.rules[i]
        if bagrule and bagrule.name == ruleName then
            table.remove(savedBag.rules, i)
            removed = true
        end
    end
    if not removed then return false end

    -- the nested categories move up one level and nest under the
    -- deleted category's parent
    for i = 1, #descendants do
        local rule = descendants[i].rule
        local newLevel = CLM.EffectiveLevel(rule) - 1
        if newLevel <= 1 then
            rule.level = nil
            rule.parent = nil
        else
            rule.level = newLevel
            if rule.parent == ruleName then
                rule.parent = rootParent
            end
        end
    end
    return true
end

-- ------------------------------------------------------------------
-- context menu
-- ------------------------------------------------------------------

-- refresh everything that shows the levels after an operation changed
-- them: the rule caches and dropdowns of the settings panel, and the
-- inventory list of the clicked header
local function refreshAfterChange()
    AutoCategory.cacheInitialize()
    if AC_UI then
        if AC_UI.RefreshDropdownData then AC_UI.RefreshDropdownData() end
        if AC_UI.RefreshControls then AC_UI.RefreshControls() end
        if AC_UI.BagSet_RefreshOrder then AC_UI.BagSet_RefreshOrder() end
    end
    AutoCategory.RefreshCurrentList()
end

-- The AutoCategory submenu of the category header context menu: the
-- level operations on the clicked category and the categories nested
-- under it, and the copy of the whole level to another bag. Added by
-- AC_ItemRowHeader_OnShowContextMenu (AutoCategory.lua); a no-op for
-- headers with no operable backing rule. The menu is keyboard-only:
-- the gamepad inventory lists have no right click.
function AutoCategory.AddCategoryLevelMenuEntries(cateName, bagTypeId)
    if not AutoCategory.CategoryLevelMenu then return end
    if not AutoCategory.saved or not AutoCategory.saved.bags then return end

    local rule = CLM.HeaderRule(cateName)
    -- no backing rule (the "Others" category, dynamic plugin
    -- categories) or a predefined rule: nothing to operate on
    if not rule or rule:isPredefined() then return end

    -- the operations work on the bag rules of the clicked bag
    local subtree = CLM.SubtreeInBag(bagTypeId, rule.name)
    if not subtree then return end

    local entries = {}

    if CLM.CanIncrease(subtree) then
        entries[#entries + 1] = {
            label = GetString(SI_AC_MENU_CM_LEVEL_UP),
            callback = function()
                if CLM.ShiftLevels(bagTypeId, subtree, 1) then
                    refreshAfterChange()
                end
            end,
        }
    end
    if CLM.CanDecrease(subtree) then
        entries[#entries + 1] = {
            label = GetString(SI_AC_MENU_CM_LEVEL_DOWN),
            callback = function()
                if CLM.ShiftLevels(bagTypeId, subtree, -1) then
                    refreshAfterChange()
                end
            end,
        }
    end

    if CLM.EffectiveLevel(rule) < 5 then
        entries[#entries + 1] = {
            label = GetString(SI_AC_MENU_CM_NEW_LEVEL),
            callback = function()
                if CLM.CreateSubLevel(bagTypeId, rule.name) then
                    refreshAfterChange()
                end
            end,
        }
    end

    entries[#entries + 1] = {
        label = GetString(SI_AC_MENU_CM_DELETE_LEVEL),
        callback = function()
            if CLM.DeleteLevelInBag(bagTypeId, rule.name) then
                refreshAfterChange()
            end
        end,
    }

    -- copy the category and the categories nested under it to another
    -- bag: every other bag of the addon (the rules are shared; the
    -- categories already present in the destination bag are skipped)
    local bags_cvt = AutoCategory.cache and AutoCategory.cache.bags_cvt
    if bags_cvt and bags_cvt.choices and bags_cvt.choicesValues then
        for i = 1, #bags_cvt.choicesValues do
            local bagId = bags_cvt.choicesValues[i]
            local bagName = bags_cvt.choices[i]
            if bagId ~= bagTypeId and bagName then
                entries[#entries + 1] = {
                    label = string.format(
                        GetString(SI_AC_MENU_CM_COPY_TO), bagName),
                    callback = function()
                        local copied, skipped = CLM.CopySubtreeToBag(
                            bagTypeId, rule.name, bagId)
                        CHAT_ROUTER:AddSystemMessage(string.format(
                            GetString(SI_AC_MESSAGE_CM_COPY_DONE),
                            copied, bagName, skipped))
                        refreshAfterChange()
                    end,
                }
            end
        end
    end

    AddCustomSubMenuItem(GetString(SI_AC_MENU_CM_SUBMENU), entries)
end
