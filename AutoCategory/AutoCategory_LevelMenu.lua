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

-- Every display name a rule contributes to the inventory lists of a
-- bag that has it: the full name of its parent chain (the Level and
-- Parent dropdowns) and every prefix of it - each level is its own
-- collapsible header. A rule without a parent contributes just its
-- own name (a legacy hierarchical "----" name contributes the
-- prefix of each of its levels). Used by Collapse All to fold every
-- level of a bag, including the ones hidden under an already folded
-- parent.
function CLM.RuleChainPrefixes(rule)
    local prefixes = {}
    if not rule or type(rule.name) ~= "string" or rule.name == "" then
        return prefixes
    end

    -- the chain of the rule, as MatchCategoryRules builds it: the
    -- name of a top-level category (a Normal category counts as
    -- level 1) carries its own levels, a level 2-5 category is
    -- preceded by its parent chain
    local chain
    if CLM.EffectiveLevel(rule) == 1 then
        chain = CategoryTree.Levels(rule.name)
        if not chain then chain = { rule.name } end
    else
        chain = { rule.name }
        local visited = { [rule.name] = true }
        local crule = rule
        while crule and CLM.EffectiveLevel(crule) > 1
                and type(crule.parent) == "string"
                and crule.parent ~= "" do
            local prule = AutoCategory.GetRuleByName(crule.parent)
            if not prule or visited[prule.name] then break end
            table.insert(chain, 1, prule.name)
            visited[prule.name] = true
            crule = prule
        end
    end

    for i = 1, #chain do
        prefixes[#prefixes + 1] =
            table.concat(chain, CategoryTree.SEPARATOR, 1, i)
    end
    return prefixes
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

-- Names are global, even though the new bag entry belongs only to the
-- clicked bag. Never silently suffix a duplicate typed by the user.
function CLM.ValidateNewCategoryName(name)
    name = type(name) == "string" and name:match("^%s*(.-)%s*$") or ""
    if name == "" then return nil, SI_AC_DIALOG_CATEGORY_NAME_EMPTY end
    local lower = LocaleAwareToLower or string.lower
    local key = lower(name)
    local rules = AutoCategory.RulesW and AutoCategory.RulesW.ruleList or {}
    if AutoCategory.GetRuleByName(name) then
        return nil, SI_AC_DIALOG_CATEGORY_NAME_EXISTS
    end
    for _, rule in ipairs(rules) do
        if type(rule.name) == "string" and lower(rule.name) == key then
            return nil, SI_AC_DIALOG_CATEGORY_NAME_EXISTS
        end
    end
    local bags = AutoCategory.saved and AutoCategory.saved.bags or {}
    for _, bag in pairs(bags) do
        for _, entry in ipairs(bag.rules or {}) do
            if type(entry.name) == "string" and lower(entry.name) == key then
                return nil, SI_AC_DIALOG_CATEGORY_NAME_EXISTS
            end
        end
    end
    return name
end

-- Create an ordinary category (Normal, no parent) in the captured bag,
-- with the chosen tag (nil keeps the empty tag, the previous default).
-- Prepare both objects before inserting anything into saved state.
function CLM.CreateCategory(bagTypeId, name, tag)
    local saved = AutoCategory.saved
    local savedBag = saved and saved.bags and saved.bags[bagTypeId]
    if not savedBag or not savedBag.rules then
        return nil, SI_AC_DIALOG_CATEGORY_CREATE_FAILED
    end
    local newName, err = CLM.ValidateNewCategoryName(name)
    if not newName then return nil, err end
    local newRule = AutoCategory.CreateRule(newName,
        tag or GetString(SI_AC_DEFAULT_NAME_EMPTY_TAG))
    newRule.rule = "false"
    newRule.level = nil
    newRule.parent = nil

    -- Stay inside the display slider's 2..1000 range. If it is already
    -- full at the top, compact existing priority groups without changing
    -- their order or ties. Do not alter rule execution priorities.
    local highest = 1
    local groups, seen = {}, {}
    for _, bagrule in ipairs(savedBag.rules) do
        local priority = bagrule.showpriority or bagrule.runpriority or 1000
        highest = math.max(highest, priority)
        if not seen[priority] then
            groups[#groups + 1] = priority
            seen[priority] = true
        end
    end
    local newPriority = #savedBag.rules == 0 and 1000 or highest + 1
    local replacements
    if newPriority > 1000 then
        if #groups > 998 then return nil, SI_AC_DIALOG_CATEGORY_CREATE_FAILED end
        table.sort(groups, function(a, b) return a > b end)
        replacements = {}
        for i, priority in ipairs(groups) do replacements[priority] = 1000 - i end
        newPriority = 1000
    end
    local entry = AutoCategory.CreateBagRule(newRule, nil, newPriority)
    if not entry then return nil, SI_AC_DIALOG_CATEGORY_CREATE_FAILED end
    newRule:compile()
    AutoCategory.ARW:AddRule(newRule)
    AutoCategory.cache.AddRule(newRule)
    if replacements then
        for _, bagrule in ipairs(savedBag.rules) do
            local priority = bagrule.showpriority or bagrule.runpriority or 1000
            bagrule.showpriority = replacements[priority]
        end
    end
    savedBag.rules[#savedBag.rules + 1] = entry

    -- An empty category is invisible while nothing matches its rule
    -- (the inventory only builds headers from matching items). Give
    -- every new category a hidden placeholder sub-category: its rule
    -- is false, so it never matches anything and never displays, but
    -- its parent link keeps the new category a structural parent, so
    -- the new category's header shows (empty) until items land in it
    -- - even with the empty-category display option off (see
    -- createNewScrollData). The placeholder is an ordinary category:
    -- it can be edited (drop items in it) or deleted like any other.
    local childName = AutoCategory.GetUsableRuleName(
        newName .. " " .. GetString(SI_AC_NEW_CATEGORY_EMPTY_CHILD))
    local childRule = AutoCategory.CreateRule(childName, newRule.tag)
    childRule.rule = "false"
    childRule.level = 2
    childRule.parent = newName
    local childEntry = AutoCategory.CreateBagRule(childRule,
        entry.runpriority, newPriority)
    if childEntry then
        childEntry.isHidden = true
        childRule:compile()
        AutoCategory.ARW:AddRule(childRule)
        AutoCategory.cache.AddRule(childRule)
        savedBag.rules[#savedBag.rules + 1] = childEntry
    end
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

-- The level shift of a move of the subtree under the category
-- newParentName, or nil when the section does not fit under it
-- (level 5 is the deepest level the addon offers).
local function moveDelta(subtree, newParentName)
    local parentRule = AutoCategory.GetRuleByName(newParentName)
    if not parentRule then return nil end

    local newRootLevel = CLM.EffectiveLevel(parentRule) + 1
    if newRootLevel > 5 then return nil end

    local delta = newRootLevel - CLM.EffectiveLevel(subtree[1].rule)
    for i = 1, #subtree do
        if CLM.EffectiveLevel(subtree[i].rule) + delta > 5 then
            return nil
        end
    end
    return delta
end

-- Move the category under another category of the bag: the new parent
-- of the category, its level one below the new parent's, and every
-- category nested under it shifted by the same difference so the
-- whole section moves together. A nil target moves the category back
-- to the top level: a Normal category without a parent. The levels
-- and the parent are properties of the global rules, so the move
-- shows in every bag that has the categories. Returns true when the
-- category moved, false when the move was refused: the target is not
-- a category of the bag, is the category itself, one of the
-- categories nested under it (a cycle) or its current parent
-- (nothing to move), or the section does not fit under the target.
function CLM.MoveSubtreeToParent(bagTypeId, ruleName, newParentName)
    local root = AutoCategory.GetRuleByName(ruleName)
    if not root then return false end

    local newRootLevel
    if newParentName == nil then
        -- move to the top level: nothing to do when the category is
        -- already a Normal category without a parent
        if root.parent == nil and CLM.EffectiveLevel(root) == 1 then
            return false
        end
        newRootLevel = 1
    else
        if type(newParentName) ~= "string" or newParentName == ""
                or newParentName == ruleName then
            return false
        end
        if root.parent == newParentName then return false end
        if not findBagrule(bagTypeId, newParentName) then return false end

        local parentRule = AutoCategory.GetRuleByName(newParentName)
        if not parentRule then return false end
        newRootLevel = CLM.EffectiveLevel(parentRule) + 1
    end

    local subtree = CLM.SubtreeInBag(bagTypeId, ruleName)
    if not subtree then return false end

    -- the category cannot move under itself or one of the categories
    -- nested under it
    for i = 2, #subtree do
        if subtree[i].rule.name == newParentName then
            return false
        end
    end

    if newRootLevel > 5 then return false end
    local delta = newRootLevel - CLM.EffectiveLevel(root)

    -- the whole section must fit under the target
    for i = 2, #subtree do
        if CLM.EffectiveLevel(subtree[i].rule) + delta > 5 then
            return false
        end
    end

    -- the nested categories keep their parent and move with the
    -- category, one level deeper or shallower with it
    for i = 2, #subtree do
        local rule = subtree[i].rule
        local newLevel = CLM.EffectiveLevel(rule) + delta
        if newLevel >= 2 then
            rule.level = newLevel
        else
            rule.level = nil
        end
    end
    if newRootLevel >= 2 then
        root.level = newRootLevel
        root.parent = newParentName
    else
        root.level = nil
        root.parent = nil
    end
    return true
end

-- ------------------------------------------------------------------
-- display priority move (the "Move Category Up/Down" menu entries)
-- ------------------------------------------------------------------

local function findBagRule(bagTypeId, ruleName)
    local saved = AutoCategory.saved
    local savedBag = saved and saved.bags and saved.bags[bagTypeId]
    local rules = savedBag and savedBag.rules
    if not rules then return nil end
    for i = 1, #rules do
        local bagrule = rules[i]
        if bagrule and bagrule.name == ruleName then
            return bagrule
        end
    end
    return nil
end

-- Can the category's display priority move one position in this
-- direction? The slider range of the display priority is 2..1000.
function CLM.CanMoveCategoryPriority(bagTypeId, ruleName, delta)
    local bagrule = findBagRule(bagTypeId, ruleName)
    if not bagrule then return false end
    local current = bagrule.showpriority or bagrule.runpriority or 0
    if delta > 0 then
        return current < 1000
    end
    return current > 2
end

-- Move a category one display position up (delta 1) or down (delta
-- -1) within the bag, by swapping display priorities with the
-- adjacent priority group: the category takes the priority of the
-- group it passes and that group takes its old priority, so both keep
-- distinct priorities and the relative order of the other categories
-- does not change. Without an adjacent group the priority steps by
-- one, inside the 2..1000 range. Execution priorities (runpriority)
-- are never touched. Returns true when the priority changed.
function CLM.MoveCategoryPriority(bagTypeId, ruleName, delta)
    local bagrule = findBagRule(bagTypeId, ruleName)
    if not bagrule then return false end
    if delta > 0 then delta = 1 else delta = -1 end
    local current = bagrule.showpriority or bagrule.runpriority or 0

    -- the adjacent priority group in the move direction
    local target = nil
    local savedBag = AutoCategory.saved.bags[bagTypeId]
    for i = 1, #savedBag.rules do
        local other = savedBag.rules[i]
        if other and other ~= bagrule and other.name then
            local p = other.showpriority or other.runpriority or 0
            if delta > 0 then
                if p > current and (target == nil or p < target) then
                    target = p
                end
            else
                if p < current and (target == nil or p > target) then
                    target = p
                end
            end
        end
    end

    if target == nil then
        -- no group to pass: step by one, inside the slider bounds
        target = current + delta
        if target < 2 or target > 1000 then return false end
    else
        -- swap with the adjacent group
        target = math.max(2, math.min(1000, target))
        if target == current then return false end
        for i = 1, #savedBag.rules do
            local other = savedBag.rules[i]
            if other and other ~= bagrule and other.name then
                local p = other.showpriority or other.runpriority or 0
                if p == target then
                    other.showpriority = current
                end
            end
        end
    end

    if target == current then return false end
    bagrule.showpriority = target
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

local NEW_CATEGORY_DIALOG = "AUTO_CATEGORY_NEW_CATEGORY"
local NEW_TAG_DIALOG = "AUTO_CATEGORY_NEW_TAG"
local newCategoryDialogRegistered = false
local newTagDialogRegistered = false

-- Create the new category in the captured bag with the chosen tag.
-- The name was already validated when the tag was chosen; creation can
-- still fail (priority compaction limit), reported in the chat window.
local function createCategoryWithTag(bagTypeId, name, tag)
    local rule = CLM.CreateCategory(bagTypeId, name, tag)
    if not rule then
        CHAT_ROUTER:AddSystemMessage(GetString(
            SI_AC_DIALOG_CATEGORY_CREATE_FAILED))
        return
    end
    refreshAfterChange()
end

-- The tag choices of the New Category dialog dropdown: the existing
-- tags (sorted), the empty tag (the previous default) and an entry
-- that opens the name dialog of a brand new tag. The value is the
-- tag the new category gets (nil keeps the empty tag); the new-tag
-- entry is marked with isNew and defers the creation to the tag
-- dialog.
function CLM.NewCategoryTagChoices()
    local RulesW = AutoCategory.RulesW
    local tags = RulesW and RulesW.tags or {}
    local choices = {}
    for i = 1, #tags do
        local tag = tags[i]
        if type(tag) == "string" and tag ~= ""
                and tag ~= GetString(SI_AC_DEFAULT_NAME_EMPTY_TAG) then
            choices[#choices + 1] = { label = tag, value = tag }
        end
    end
    table.sort(choices, function(a, b) return a.label < b.label end)
    choices[#choices + 1] =
        { label = GetString(SI_AC_DEFAULT_NAME_EMPTY_TAG) }
    choices[#choices + 1] =
        { label = GetString(SI_AC_MENU_CM_TAG_NEW), isNew = true }
    return choices
end

-- The tag dropdown of the New Category dialog, directly beside the
-- edit box: the name and the tag are chosen in the same dialog, no
-- follow-up context menu. The controls are built once per dialog
-- control and reused; every opening refreshes the tag list and
-- resets the selection to the empty tag (the previous default).
local TAG_DROPDOWN_WIDTH = 230 -- the dropdown
local TAG_LABEL_WIDTH = 90     -- room for the "Tag" label
local TAG_DROPDOWN_GAP = 12    -- between the edit box and the label

local newCategoryTagControls = nil -- { label, comboControl, comboBox }
local newCategoryTagChoice = nil   -- the selected choice entry

-- The choice currently selected in the dropdown of the open dialog
-- (the empty tag before the user picks one).
function CLM.GetNewCategoryTagChoice()
    return newCategoryTagChoice
end

local function hideNewCategoryTagDropdown()
    if newCategoryTagControls then
        newCategoryTagControls.label:SetHidden(true)
        newCategoryTagControls.comboControl:SetHidden(true)
    end
end

local function setupNewCategoryTagDropdown(dialog)
    if not WINDOW_MANAGER then return end
    local edit = dialog:GetNamedChild("Edit")
    if not edit then return end

    if not newCategoryTagControls then
        local label = WINDOW_MANAGER:CreateControl(
            "$(parent)ACTagLabel", dialog, CT_LABEL)
        label:SetFont("ZoFontGame")
        label:SetText(GetString(SI_AC_MENU_CS_DROPDOWN_TAG))
        local comboControl = CreateControlFromVirtual(
            "$(parent)ACTagCombo", dialog, "ZO_ComboBox")
        comboControl:SetWidth(TAG_DROPDOWN_WIDTH)
        -- the label sits between the edit box and the dropdown, on
        -- the row of the edit box
        label:SetAnchor(RIGHT, comboControl, LEFT, -TAG_DROPDOWN_GAP, 2)
        comboControl:SetAnchor(TOPLEFT, edit, TOPRIGHT,
            TAG_DROPDOWN_GAP + TAG_LABEL_WIDTH + TAG_DROPDOWN_GAP, 2)
        newCategoryTagControls = {
            label = label,
            comboControl = comboControl,
            comboBox = ZO_ComboBox_ObjectFromContainer(comboControl),
        }
        newCategoryTagControls.originalEditWidth = edit:GetWidth()
    end

    local controls = newCategoryTagControls
    local comboBox = controls.comboBox
    if not comboBox then return end
    controls.label:SetHidden(false)
    controls.comboControl:SetHidden(false)

    -- make room for the dropdown: the edit box keeps the left end
    -- of its row and takes a fixed width, the label and the
    -- dropdown sit at the right end (the anchors of the edit box
    -- are set again by the dialog framework on every opening)
    local isValid, point, relTo, relPoint, offX, offY = edit:GetAnchor(0)
    if isValid and relTo then
        edit:ClearAnchors()
        edit:SetAnchor(point, relTo, relPoint, offX, offY)
    end
    local editWidth = (controls.originalEditWidth or edit:GetWidth())
        - TAG_DROPDOWN_GAP - TAG_LABEL_WIDTH
        - TAG_DROPDOWN_GAP - TAG_DROPDOWN_WIDTH
    if editWidth > 100 then
        edit:SetWidth(editWidth)
    end

    comboBox:ClearItems()
    local choices = CLM.NewCategoryTagChoices()
    local defaultEntry = nil
    for i = 1, #choices do
        local choice = choices[i]
        local entry = comboBox:CreateItemEntry(choice.label, function()
            newCategoryTagChoice = choice
        end)
        comboBox:AddItem(entry)
        if choice.value == nil and not choice.isNew then
            defaultEntry = entry
        end
    end
    -- reset the selection to the empty tag without firing its
    -- callback
    newCategoryTagChoice = nil
    if defaultEntry then
        comboBox:SelectItem(defaultEntry, true)
    end
end

function CLM.OpenNewTagDialog(bagTypeId, name)
    if not newTagDialogRegistered then
        ZO_Dialogs_RegisterCustomDialog(NEW_TAG_DIALOG, {
            title = { text = SI_AC_MENU_CM_TAG_NEW },
            mainText = { text = SI_AC_DIALOG_TAG_NAME_PROMPT },
            editBox = { defaultText = "", maxInputCharacters = 128 },
            buttons = {
                {
                    text = SI_OK,
                    noReleaseOnClick = true,
                    callback = function(dialog)
                        local tag = ZO_Dialogs_GetEditBoxText(dialog)
                        tag = type(tag) == "string"
                            and tag:match("^%s*(.-)%s*$") or ""
                        if tag == "" then
                            ZO_Dialogs_UpdateDialogMainText(dialog,
                                { text = GetString(
                                    SI_AC_DIALOG_TAG_NAME_EMPTY) })
                            return
                        end
                        -- native dialogs clear their state on
                        -- release: capture the dialog data first
                        local data = dialog.data
                        ZO_Dialogs_ReleaseDialog(NEW_TAG_DIALOG)
                        if data and data.bagTypeId and data.name then
                            createCategoryWithTag(data.bagTypeId,
                                data.name, tag)
                        end
                    end,
                },
                { text = SI_DIALOG_CANCEL },
            },
        })
        newTagDialogRegistered = true
    end
    ZO_Dialogs_ShowDialog(NEW_TAG_DIALOG,
        { bagTypeId = bagTypeId, name = name })
end

function CLM.OpenNewCategoryDialog(bagTypeId)
    local bags = AutoCategory.saved and AutoCategory.saved.bags
    if not bags or not bags[bagTypeId] then return end
    if not newCategoryDialogRegistered then
        ZO_Dialogs_RegisterCustomDialog(NEW_CATEGORY_DIALOG, {
            title = { text = SI_AC_MENU_CM_NEW_CATEGORY },
            mainText = { text = SI_AC_DIALOG_CATEGORY_NAME_PROMPT },
            editBox = { defaultText = "", maxInputCharacters = 128 },
            finishedCallback = function()
                hideNewCategoryTagDropdown()
            end,
            buttons = {
                {
                    text = SI_OK,
                    noReleaseOnClick = true,
                    callback = function(dialog)
                        local bagTypeId = dialog.data.bagTypeId
                        -- validate the name first: a blank or
                        -- duplicate name keeps the dialog open
                        local newName, err = CLM.ValidateNewCategoryName(
                            ZO_Dialogs_GetEditBoxText(dialog))
                        if not newName then
                            ZO_Dialogs_UpdateDialogMainText(dialog,
                                { text = GetString(err) })
                            return
                        end
                        ZO_Dialogs_ReleaseDialog(NEW_CATEGORY_DIALOG)
                        -- then apply the tag chosen in the dropdown
                        -- beside the edit box: the empty tag (the
                        -- previous default), an existing tag, or the
                        -- new-tag dialog before creating anything
                        local choice = CLM.GetNewCategoryTagChoice()
                        if choice and choice.isNew then
                            CLM.OpenNewTagDialog(bagTypeId, newName)
                        else
                            createCategoryWithTag(bagTypeId, newName,
                                choice and choice.value or nil)
                        end
                    end,
                },
                { text = SI_DIALOG_CANCEL },
            },
        })
        newCategoryDialogRegistered = true
    end
    ZO_Dialogs_ShowDialog(NEW_CATEGORY_DIALOG, { bagTypeId = bagTypeId })
    -- a standard edit box dialog has no setup hook (only the
    -- custom-control dialogs have one), so build the tag dropdown
    -- of this opening now, against the displayed dialog
    local dialog = ZO_Dialogs_FindDialog and
        ZO_Dialogs_FindDialog(NEW_CATEGORY_DIALOG)
    if dialog then
        setupNewCategoryTagDropdown(dialog)
    end
end

-- The AutoCategory entries of the category header context menu: the
-- execution priority of the clicked category, its level and
-- display-position operations in a "Level" submenu, the move of
-- the whole section under another category of the bag in a "Move To"
-- submenu, the copy of the whole section to another bag in a "Copy
-- To" submenu, category creation, and the removal of the category
-- from the inventory list of the clicked bag (the global rule stays
-- and the categories nested under it move up one level, exactly like
-- the Remove Category button of Bag Settings; it is neither the
-- hidden state - the children would disappear with it - nor the
-- deletion of the rule). A submenu cannot hold a submenu in ESO, so
-- the level operations sit in their own submenu, next to the move
-- and copy submenus. A predefined (protected) rule accepts the level
-- and priority changes but is never offered the removal. Added by
-- AC_ItemRowHeader_OnShowContextMenu (AutoCategory.lua); a no-op for
-- headers with no operable backing rule, except for New Category.
-- The menu is keyboard-only: the gamepad inventory lists have no
-- right click.
function AutoCategory.AddCategoryLevelMenuEntries(cateName, bagTypeId)
    if not AutoCategory.CategoryLevelMenu then return end
    if not AutoCategory.saved or not AutoCategory.saved.bags then return end
    if not AutoCategory.saved.bags[bagTypeId] then return end

    local rule = CLM.HeaderRule(cateName)
    -- a predefined (protected) rule: its level and its display
    -- priorities can be changed, but it is never offered the
    -- removal from the bag
    local isPredefined = rule ~= nil and rule:isPredefined()

    -- the operations work on the bag rules of the clicked bag
    local subtree = nil
    if rule then
        subtree = CLM.SubtreeInBag(bagTypeId, rule.name)
    end
    if not subtree then
        rule = nil
    end

    if rule then

        -- the numeric execution priority of the category (read-only
        -- information): the runpriority of its bag rule in this bag,
        -- the order the rules run in (not the display order)
        local infoBagrule = subtree[1].bagrule
        if infoBagrule and infoBagrule.runpriority then
            AddCustomMenuItem(
                string.format(GetString(SI_AC_MENU_CM_RUN_PRIORITY),
                    infoBagrule.runpriority),
                function() end, MENU_ADD_OPTION_LABEL)
        end

        -- the level and display-position operations of the
        -- category, in a "Level" submenu and inside their existing
        -- limits (the 1-5 levels, the 2..1000 display priorities);
        -- an inapplicable operation is not offered
        local levelEntries = {}
        -- move the category one display position up: swap its
        -- display priority with the adjacent priority group, inside
        -- the 2..1000 range of the display slider
        if CLM.CanMoveCategoryPriority(bagTypeId, rule.name, 1) then
            levelEntries[#levelEntries + 1] = {
                label = GetString(SI_AC_MENU_CM_LEVEL_MOVE_UP),
                callback = function()
                    if CLM.MoveCategoryPriority(bagTypeId,
                            rule.name, 1) then
                        refreshAfterChange()
                    end
                end,
            }
        end
        -- one level deeper: nest the category under the category
        -- displayed just above it
        if CLM.CanIncrease(subtree) then
            levelEntries[#levelEntries + 1] = {
                label = GetString(SI_AC_MENU_CM_LEVEL_DEEPER),
                callback = function()
                    if CLM.ShiftLevels(bagTypeId, subtree, 1) then
                        refreshAfterChange()
                    end
                end,
            }
        end
        -- one level higher: un-nest the category from its parent
        if CLM.CanDecrease(subtree) then
            levelEntries[#levelEntries + 1] = {
                label = GetString(SI_AC_MENU_CM_LEVEL_SHALLOWER),
                callback = function()
                    if CLM.ShiftLevels(bagTypeId, subtree, -1) then
                        refreshAfterChange()
                    end
                end,
            }
        end
        -- move the category one display position down
        if CLM.CanMoveCategoryPriority(bagTypeId, rule.name, -1) then
            levelEntries[#levelEntries + 1] = {
                label = GetString(SI_AC_MENU_CM_LEVEL_MOVE_DOWN),
                callback = function()
                    if CLM.MoveCategoryPriority(bagTypeId,
                            rule.name, -1) then
                        refreshAfterChange()
                    end
                end,
            }
        end
        if #levelEntries > 0 then
            AddCustomSubMenuItem(GetString(SI_AC_MENU_CM_LEVEL_SUBMENU),
                levelEntries)
        end

        -- move the category under another category of the bag: the
        -- candidates in the display order of the bag, never the category
        -- itself, the categories nested under it, its current parent or
        -- a category the section does not fit under; the first entry
        -- moves the section back to the top level (a Normal category)
        local moveEntries = {}
        if CLM.EffectiveLevel(rule) > 1 or (type(rule.parent) == "string"
                and rule.parent ~= "") then
            moveEntries[#moveEntries + 1] = {
                label = GetString(SI_AC_MENU_CM_MOVE_TOP),
                callback = function()
                    if CLM.MoveSubtreeToParent(bagTypeId, rule.name, nil) then
                        refreshAfterChange()
                    end
                end,
            }
        end
        local savedBag = AutoCategory.saved.bags[bagTypeId]
        if savedBag and savedBag.rules then
            local excluded = {}
            for i = 1, #subtree do
                excluded[subtree[i].rule.name] = true
            end
            if type(rule.parent) == "string" and rule.parent ~= "" then
                excluded[rule.parent] = true
            end

            local ordered = {}
            for i = 1, #savedBag.rules do
                local brule = savedBag.rules[i]
                if brule and type(brule.name) == "string"
                        and brule.name ~= "" then
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

            for i = 1, #ordered do
                local name = ordered[i].name
                if not excluded[name] and moveDelta(subtree, name) ~= nil then
                    moveEntries[#moveEntries + 1] = {
                        label = name,
                        callback = function()
                            if CLM.MoveSubtreeToParent(bagTypeId,
                                    rule.name, name) then
                                refreshAfterChange()
                            end
                        end,
                    }
                end
            end
        end
        if #moveEntries > 0 then
            AddCustomSubMenuItem(GetString(SI_AC_MENU_CM_MOVE_SUBMENU),
                moveEntries)
        end

        -- copy the category and the categories nested under it to another
        -- bag: every other bag of the addon in a "Copy To" submenu (the
        -- rules are shared; the categories already present in the
        -- destination bag are skipped)
        local copyEntries = {}
        local bags_cvt = AutoCategory.cache and AutoCategory.cache.bags_cvt
        if bags_cvt and bags_cvt.choices and bags_cvt.choicesValues then
            for i = 1, #bags_cvt.choicesValues do
                local bagId = bags_cvt.choicesValues[i]
                local bagName = bags_cvt.choices[i]
                if bagId ~= bagTypeId and bagName then
                    copyEntries[#copyEntries + 1] = {
                        label = bagName,
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
            if #copyEntries > 0 then
                AddCustomSubMenuItem(GetString(SI_AC_MENU_CM_COPY_SUBMENU),
                    copyEntries)
            end
    end

    -- the removal of the category from the inventory list of the
    -- clicked bag only, never for a predefined (protected) rule: the
    -- global rule stays and the categories nested under it move up
    -- one level
    if rule and not isPredefined then
        AddCustomMenuItem(GetString(SI_AC_MENU_CM_REMOVE_DISPLAY),
            function()
                if CLM.DeleteLevelInBag(bagTypeId, rule.name) then
                    refreshAfterChange()
                end
            end, MENU_ADD_OPTION_LABEL)
    end
    
    -- creation does not modify the clicked rule or inherit its
    -- level; offered on ungrouped/predefined headers and at level 5
    -- as well
    AddCustomMenuItem(GetString(SI_AC_MENU_CM_NEW_CATEGORY),
        function() CLM.OpenNewCategoryDialog(bagTypeId) end,
        MENU_ADD_OPTION_LABEL)
end
