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
-- all" button) - it only adds or overwrites destination bag rules.
-- Existing categories are skipped unless explicitly selected for overwrite.
-- Deleting removes the
-- category from the clicked bag only (like the Remove Category button);
-- the global rule stays.

AutoCategory = AutoCategory or {}

local CategoryTree = AutoCategory.CategoryTree

local CLM = {}
AutoCategory.CategoryLevelMenu = CLM

-- The categories created during this session: they display a zero-count
-- header right after creation, even with the Show Empty Categories
-- option off, until their first items land (see createNewScrollData).
-- The marker is deliberately NOT persisted: an orphan "false" rule
-- left over from an earlier session (an old "new sub-level", a
-- leftover placeholder) must not keep a category visible as an empty
-- header forever - the [0] ghosts seen in the guild bank.
CLM.CreatedThisSession = {}

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

local function bagRules(bagTypeId)
    local saved = AutoCategory.saved
    local savedBag = saved and saved.bags and saved.bags[bagTypeId]
    return savedBag and savedBag.rules
end

local function findRuleInList(rules, ruleName)
    for i = 1, #(rules or {}) do
        local bagrule = rules[i]
        if bagrule and bagrule.name == ruleName then
            return bagrule
        end
    end
    return nil
end

-- Scan the saved bag rules directly; the cache is refreshed separately.
local function findBagrule(bagTypeId, ruleName)
    return findRuleInList(bagRules(bagTypeId), ruleName)
end

local function orderedBagRules(bagrules)
    local ordered = {}
    for _, brule in ipairs(bagrules) do
        if type(brule.name) == "string" and brule.name ~= "" then
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
    return ordered
end

-- A drop edits a real category of this bag, not a synthetic prefix or
-- a dynamic sub-header that happens to end in the name of a rule.
function CLM.HeaderRuleForDrag(bagTypeId, cateName)
    local rule = CLM.HeaderRule(cateName)
    if not rule or not findBagrule(bagTypeId, rule.name)
            or CategoryTree.IsHierarchical(rule.name) then return nil end
    if cateName == rule.name then return rule end
    local prefixes = CLM.RuleChainPrefixes(rule)
    if cateName == prefixes[#prefixes]
            and CategoryTree.LevelCount(cateName) <= CLM.EffectiveLevel(rule) then
        return rule
    end
end

-- Every category of the bag whose parent chain (the Parent dropdown
-- chain) contains ruleName: the categories nested under the category,
-- in the order of the bag's rule list. The category itself is never
-- included, and a chain that loops stops at the first repeated name.
local function descendantsInRules(rules, ruleName, getRule)
    local result = {}
    if not rules or not ruleName then return result end

    for i = 1, #rules do
        local bagrule = rules[i]
        local rule = bagrule and getRule(bagrule.name)
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
                crule = getRule(parent)
            end
        end
    end
    return result
end

function CLM.DescendantsInBag(bagTypeId, ruleName)
    return descendantsInRules(bagRules(bagTypeId), ruleName, AutoCategory.GetRuleByName)
end

-- The category and the categories nested under it in the bag, as
-- { rule = ..., bagrule = ... } entries, the category first. Returns
-- nil when the category is not a category of the bag.
function CLM.SubtreeInRules(rules, ruleName, getRule)
    local rootBagrule = findRuleInList(rules, ruleName)
    if not rootBagrule then return nil end
    local rootRule = getRule(ruleName)
    if not rootRule then return nil end

    local subtree = { { rule = rootRule, bagrule = rootBagrule } }
    local descendants = descendantsInRules(rules, ruleName, getRule)
    for i = 1, #descendants do
        subtree[#subtree + 1] = descendants[i]
    end
    return subtree
end

function CLM.SubtreeInBag(bagTypeId, ruleName)
    return CLM.SubtreeInRules(bagRules(bagTypeId), ruleName, AutoCategory.GetRuleByName)
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
local function nearestAncestorName(rules, rootRule, targetLevel, subtree, getRule)
    if not rules then return nil end
    local excluded = {}
    for i = 1, #subtree do
        excluded[subtree[i].rule.name] = true
    end

    local nearest, first, passedSelf
    for _, brule in ipairs(orderedBagRules(rules)) do
        if brule.name == rootRule.name then
            passedSelf = true
        else
            local r = getRule(brule.name)
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
-- Operate on the supplied rules; the manager passes draft copies.
function CLM.ShiftRuleLevels(rules, subtree, delta, getRule)
    if not subtree or not subtree[1] or (delta ~= 1 and delta ~= -1) then return false end
    if delta == 1 and not CLM.CanIncrease(subtree) then return false end
    if delta == -1 and not CLM.CanDecrease(subtree) then return false end

    -- the new parent of the category when it moves deeper and has
    -- none: the nearest category of its old level above it
    local newRootParent
    if delta == 1 then
        local root = subtree[1].rule
        if not (type(root.parent) == "string" and root.parent ~= "") then
            newRootParent = nearestAncestorName(rules, root,
                CLM.EffectiveLevel(root), subtree, getRule)
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

function CLM.ShiftLevels(bagTypeId, subtree, delta)
    if not CLM.ShiftRuleLevels(bagRules(bagTypeId), subtree, delta, AutoCategory.GetRuleByName) then
        return false
    end
    -- the level/parent layout of a predefined category is kept
    -- as an override in the account saved rules (the definition
    -- itself never is saved)
    if AutoCategory.SyncPredefinedLayouts then
        AutoCategory.SyncPredefinedLayouts()
    end
    return true
end

-- Copy the category and the categories nested under it to another bag.
-- The rules are global and shared: the copy reuses them, exactly like
-- the "Export all" button of Bag Settings - editing the category in
-- one bag changes it everywhere. Existing destination entries in the
-- subtree are skipped unless overwrite is requested. Ancestors are copied
-- with it when they are not categories of the destination bag yet, so
-- the category keeps its place in the level hierarchy there (without
-- them a level 2-5 category displays flat in that bag).
-- Returns the number of categories added, skipped, and overwritten.
function CLM.CopySubtreeToBag(srcBagTypeId, ruleName, destBagTypeId, overwrite)
    local copied, skipped, overwritten = 0, 0, 0
    if srcBagTypeId == destBagTypeId then return copied, skipped, overwritten end

    local subtree = CLM.SubtreeInBag(srcBagTypeId, ruleName)
    if not subtree then return copied, skipped, overwritten end

    local saved = AutoCategory.saved
    local destBag = saved and saved.bags and saved.bags[destBagTypeId]
    if not destBag or not destBag.rules then return copied, skipped, overwritten end

    local present = {}
    for i = 1, #destBag.rules do
        local bagrule = destBag.rules[i]
        if bagrule and bagrule.name then
            present[bagrule.name] = bagrule
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

    local rootBagrule = subtree[1].bagrule
    local function addMissing(name, srcBagrule)
        local entry = AutoCategory.CreateBagRule(name,
            (srcBagrule and srcBagrule.runpriority) or rootBagrule.runpriority,
            (srcBagrule and srcBagrule.showpriority) or rootBagrule.showpriority)
        if entry then
            destBag.rules[#destBag.rules + 1] = entry
            present[name] = entry
            copied = copied + 1
        end
    end
    for i = 1, #chain do
        local name = chain[i].name
        if not present[name] then
            addMissing(name, findBagrule(srcBagTypeId, name))
        end
    end
    for i = 1, #subtree do
        local name, srcBagrule = subtree[i].rule.name, subtree[i].bagrule
        local existing = present[name]
        if not existing then
            addMissing(name, srcBagrule)
        elseif overwrite then
            -- Keep the destination entry in place and copy only per-bag
            -- settings. Neither the shared rule nor other entries change.
            existing.runpriority = srcBagrule.runpriority
            existing.showpriority = srcBagrule.showpriority
            existing.isHidden = srcBagrule.isHidden or nil
            overwritten = overwritten + 1
        else
            skipped = skipped + 1
        end
    end
    return copied, skipped, overwritten
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

-- Only real, non-hidden categories in this bag can be selected.
-- Normal counts as level 1; a level-5 category cannot have a child.
local function newCategoryParentLevel(bagrule)
    if not bagrule or bagrule.isHidden then return nil end
    local rule = AutoCategory.GetRuleByName(bagrule.name)
    if not rule or CategoryTree.IsHierarchical(rule.name) then return nil end
    local level = CLM.EffectiveLevel(rule)
    if level < 5 then return level end
end

-- Create a category in the captured bag, with the chosen tag (nil keeps
-- the empty tag) and optional { name, level } parent selection.
-- Prepare both objects before inserting anything into saved state.
function CLM.CreateCategory(bagTypeId, name, tag, parent)
    local saved = AutoCategory.saved
    local savedBag = saved and saved.bags and saved.bags[bagTypeId]
    if not savedBag or not savedBag.rules then
        return nil, SI_AC_DIALOG_CATEGORY_CREATE_FAILED
    end
    local newName, err = CLM.ValidateNewCategoryName(name)
    if not newName then return nil, err end
    local parentLevel
    if parent then
        parentLevel = newCategoryParentLevel(findBagrule(bagTypeId, parent.name))
        if not parentLevel or parentLevel ~= parent.level then
            return nil, SI_AC_DIALOG_CATEGORY_PARENT_UNAVAILABLE
        end
    end
    local newRule = AutoCategory.CreateRule(newName,
        tag or GetString(SI_AC_DEFAULT_NAME_EMPTY_TAG))
    newRule.rule = "false"
    newRule.level = parentLevel and parentLevel + 1 or nil
    newRule.parent = parent and parent.name or nil

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
    -- (the inventory only builds headers from matching items). The
    -- zero-count header right after creation comes from the session
    -- marker (CLM.CreatedThisSession), not from a persisted marker:
    -- give the new category a hidden placeholder where the level allows it
    -- to keep it a structural parent of nested rules. Its rule is
    -- false, so it never matches anything and never displays. The
    -- placeholder is an ordinary category: it can be edited (drop
    -- items in it) or deleted like any other.
    if CLM.EffectiveLevel(newRule) < 5 then
        local childName = AutoCategory.GetUsableRuleName(
            newName .. " " .. GetString(SI_AC_NEW_CATEGORY_EMPTY_CHILD))
        local childRule = AutoCategory.CreateRule(childName, newRule.tag)
        childRule.rule = "false"
        childRule.level = CLM.EffectiveLevel(newRule) + 1
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
    end

    -- Show the new category right away, even with the Show Empty
    -- Categories option off: the session marker above drives the
    -- zero-count header of createNewScrollData.
    CLM.CreatedThisSession[newName] = true
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
    -- the level/parent layout of a predefined category is kept
    -- as an override in the account saved rules (the definition
    -- itself never is saved)
    if AutoCategory.SyncPredefinedLayouts then
        AutoCategory.SyncPredefinedLayouts()
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

-- The displayed sibling categories of a category, in the visible
-- display order of the bag: the headers present in the inventory
-- lists, the categories the player actually sees. A hidden or
-- empty category has no header, so it never is a neighbor. Only
-- the categories backed by a bag rule are kept (the ungrouped
-- "Others" section has none). Nil when the visible display order
-- is not available (the inventory lists are not built, or show
-- nothing at all); an empty list means the bag displays no
-- sibling category.
local function displayedSiblingNames(bagTypeId, fullName)
    if not AutoCategory.GetDisplayedHeaders then return nil end
    local headers = AutoCategory.GetDisplayedHeaders(bagTypeId)
    if not headers or #headers == 0 then return nil end
    if not CategoryTree or not CategoryTree.ParentOf then return nil end
    local parent = CategoryTree.ParentOf(fullName)
    local siblings = {}
    for i = 1, #headers do
        local name = headers[i]
        if CategoryTree.ParentOf(name) == parent
                and findBagRule(bagTypeId, name) then
            siblings[#siblings + 1] = name
        end
    end
    return siblings
end

-- The display priority of the neighbor among a set of rules: a
-- member of the moved category's own tie group when the display
-- order (equal priorities sorted by name) puts one next to it,
-- else the nearest priority group beyond in the move direction.
-- Nil when the category already sits at that end of the set: no
-- neighbor to pass.
local function neighborFromRules(rules, bagrule, current, delta)
    -- a tie-group member displayed just above/below the category
    for i = 1, #rules do
        local other = rules[i]
        if other and other ~= bagrule and other.name then
            local p = other.showpriority or other.runpriority or 0
            if p == current
                    and ((delta > 0 and other.name < bagrule.name)
                        or (delta < 0 and other.name > bagrule.name)) then
                return current
            end
        end
    end
    -- the nearest priority group beyond, in the move direction
    local neighbor = nil
    for i = 1, #rules do
        local other = rules[i]
        if other and other ~= bagrule and other.name then
            local p = other.showpriority or other.runpriority or 0
            if delta > 0 then
                if p > current and (neighbor == nil or p < neighbor) then
                    neighbor = p
                end
            else
                if p < current and (neighbor == nil or p > neighbor) then
                    neighbor = p
                end
            end
        end
    end
    return neighbor
end

-- The display priority of the category displayed just above (delta
-- 1) or just below (delta -1) the category, following the visible
-- display order of the bag: the neighbor is the category whose
-- header is displayed just above/below the moved one - a hidden
-- or empty category (no header displayed) is never a neighbor.
-- When the inventory lists give no visible order, the bag rules
-- stand in for it (all the categories of the bag, hidden ones
-- included). Nil when the category already sits at that end of
-- the bag: no displayed neighbor to pass.
local function displayNeighborPriority(bagTypeId, bagrule, current, delta)
    local savedBag = AutoCategory.saved.bags[bagTypeId]
    if not savedBag or not savedBag.rules then return nil end

    -- the visible display order first
    local siblings = displayedSiblingNames(bagTypeId, bagrule.name)
    if siblings then
        local index = nil
        for i = 1, #siblings do
            if siblings[i] == bagrule.name then
                index = i
                break
            end
        end
        if index then
            -- the displayed sibling just above/below
            local i = delta > 0 and index - 1 or index + 1
            if i < 1 or i > #siblings then return nil end
            local neighborRule = findBagRule(bagTypeId, siblings[i])
            if not neighborRule then return nil end
            return neighborRule.showpriority
                or neighborRule.runpriority or 0
        end
        -- the moved category itself has no displayed header (it
        -- is hidden or empty): its neighbors are the displayed
        -- siblings around its priority position
        local siblingRules = {}
        for i = 1, #siblings do
            local other = findBagRule(bagTypeId, siblings[i])
            if other then
                siblingRules[#siblingRules + 1] = other
            end
        end
        return neighborFromRules(siblingRules, bagrule, current, delta)
    end

    -- no visible display order (the inventory lists are not built):
    -- the bag rules
    return neighborFromRules(savedBag.rules, bagrule, current, delta)
end

-- Can the category's display priority move one position in this
-- direction? The move takes the display priority of the category
-- displayed just above (up) or just below (down) and steps one past
-- it, so a displayed neighbor must exist in that direction and the
-- result must stay inside the 2..1000 slider range.
function CLM.CanMoveCategoryPriority(bagTypeId, ruleName, delta)
    local bagrule = findBagRule(bagTypeId, ruleName)
    if not bagrule then return false end
    local current = bagrule.showpriority or bagrule.runpriority or 0
    local neighbor = displayNeighborPriority(bagTypeId, bagrule, current, delta)
    if not neighbor then return false end
    if delta > 0 then
        return neighbor + 1 <= 1000
    end
    return neighbor - 1 >= 2
end

-- Move a category one display position up (delta 1) or down (delta
-- -1) within the bag: the category takes the display priority of the
-- category displayed just above (up: +1, to sit just above it) or
-- just below (down: -1, to sit just below it) and steps one past
-- that neighbor, so it passes the neighbor and every category
-- sharing its priority. The other categories keep their priorities.
-- The result must stay inside the 2..1000 slider range, and without
-- a displayed neighbor in the direction the category already is at
-- that end of the bag: nothing moves. Execution priorities
-- (runpriority) are never touched. Returns true when the priority
-- changed.
function CLM.MoveCategoryPriority(bagTypeId, ruleName, delta)
    local bagrule = findBagRule(bagTypeId, ruleName)
    if not bagrule then return false end
    if delta > 0 then delta = 1 else delta = -1 end
    local current = bagrule.showpriority or bagrule.runpriority or 0

    local neighbor = displayNeighborPriority(bagTypeId, bagrule, current, delta)
    if neighbor == nil then return false end

    -- one step past the neighbor, inside the slider bounds
    local target = neighbor + delta
    if target < 2 or target > 1000 then return false end
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

-- The context menu and inventory drag share the mutation and refresh path.
function CLM.MoveSubtreeAndRefresh(bagTypeId, ruleName, newParentName)
    if not CLM.MoveSubtreeToParent(bagTypeId, ruleName, newParentName) then
        return false
    end
    refreshAfterChange()
    return true
end

-- Use the inventory's configured paths, not the visible rows: empty
-- categories and categories beneath a collapsed header remain available.
function CLM.GetMoveDestinations(bagTypeId)
    local bags = AutoCategory.saved and AutoCategory.saved.bags
    local bag = bags and bags[bagTypeId]
    local destinations = {}
    if not bag or not bag.rules then return destinations end
    local resolveDisplay = AutoCategory.MakeBagRuleDisplayResolver(bagTypeId)
    for _, bagrule in ipairs(bag.rules) do
        local rule = AutoCategory.GetRuleByName(bagrule.name)
        if rule and not bagrule.isHidden then
            local path, sortKey = resolveDisplay(bagrule)
            local level = CategoryTree.LevelCount(path)
            destinations[#destinations + 1] = {
                name = rule.name,
                rule = rule,
                label = string.rep("   ", level - 1) .. rule.name,
                sortKey = sortKey,
            }
        end
    end
    table.sort(destinations, function(a, b)
        if a.sortKey ~= b.sortKey then return a.sortKey < b.sortKey end
        return a.name < b.name
    end)
    return destinations
end

function CLM.MoveItemToCategory(bagTypeId, name, itemId)
    local bagrule = findBagrule(bagTypeId, name)
    local rule = bagrule and not bagrule.isHidden and AutoCategory.GetRuleByName(name)
    if not rule or rule:isPredefined() or not rule:addItemIdToIsItemId(itemId) then return end
    rule:compile()
    refreshAfterChange()
end

local NEW_CATEGORY_DIALOG = "AUTO_CATEGORY_NEW_CATEGORY"
local newCategoryDialogRegistered = false

local function setupNewCategoryParent(dialog)
    local combo = dialog.parentCombo
    combo:ClearItems()
    local function addParent(label, parent)
        local entry = combo:CreateItemEntry(label, function() dialog.categoryParent = parent end)
        combo:AddItem(entry)
        return entry
    end

    local selected = addParent(GetString(SI_AC_MENU_EC_DROPDOWN_PARENT_NONE), nil)
    dialog.categoryParent = nil
    local clickedParent = dialog.data.clickedParent
    local savedBag = AutoCategory.saved.bags[dialog.data.bagTypeId]
    for _, bagrule in ipairs(orderedBagRules(savedBag and savedBag.rules or {})) do
        local level = newCategoryParentLevel(bagrule)
        if level then
            local parent = { name = bagrule.name, level = level }
            local label = parent.name .. " (" .. GetString(SI_AC_TIP_LEVEL):format(level) .. ")"
            local entry = addParent(label, parent)
            if clickedParent and clickedParent.name == parent.name and clickedParent.level == level then
                selected = entry
                dialog.categoryParent = parent
            end
        end
    end
    combo:SelectItem(selected, true)
end

local function setupNewCategoryDialog(dialog)
    dialog.categoryName:SetText("")
    dialog.newTag:SetHidden(true)
    dialog.tagName:SetText("")
    dialog.tag = nil
    dialog.creatingTag = false

    local combo = dialog.tagCombo
    combo:ClearItems()
    local function addTag(label, tag, creatingTag)
        local entry = combo:CreateItemEntry(label, function()
            dialog.tag = tag
            dialog.creatingTag = creatingTag
            dialog.newTag:SetHidden(not creatingTag)
            if creatingTag then
                dialog.tagName:TakeFocus()
            else
                dialog.tagName:SetText("")
            end
        end)
        combo:AddItem(entry)
        return entry
    end

    local emptyTag = GetString(SI_AC_DEFAULT_NAME_EMPTY_TAG)
    local tags = {}
    for _, tag in ipairs(AutoCategory.RulesW.tags) do
        if type(tag) == "string" and tag ~= "" and tag ~= emptyTag then
            tags[#tags + 1] = tag
        end
    end
    table.sort(tags)
    for _, tag in ipairs(tags) do
        addTag(tag, tag, false)
    end
    local default = addTag(emptyTag, nil, false)
    addTag(GetString(SI_AC_MENU_CM_TAG_NEW), nil, true)
    combo:SelectItem(default, true)
    setupNewCategoryParent(dialog)
end

local function showNewCategoryError(dialog, errorId)
    ZO_Dialogs_UpdateDialogMainText(dialog, { text = errorId })
end

local function submitNewCategoryDialog(dialog)
    local name, err = CLM.ValidateNewCategoryName(dialog.categoryName:GetText())
    if not name then
        showNewCategoryError(dialog, err)
        return
    end
    local tag = dialog.tag
    if dialog.creatingTag then
        tag = dialog.tagName:GetText():match("^%s*(.-)%s*$")
        if tag == "" then
            showNewCategoryError(dialog, SI_AC_DIALOG_TAG_NAME_EMPTY)
            return
        end
    end
    local rule, createError = CLM.CreateCategory(dialog.data.bagTypeId, name, tag, dialog.categoryParent)
    if not rule then
        showNewCategoryError(dialog, createError)
        return
    end
    ZO_Dialogs_ReleaseDialogOnButtonPress(dialog)
    refreshAfterChange()
end

function CLM.OpenNewCategoryDialog(bagTypeId, clickedParent)
    local bags = AutoCategory.saved and AutoCategory.saved.bags
    if not bags or not bags[bagTypeId] then return end
    if not newCategoryDialogRegistered then
        local dialog = AC_NewCategoryDialog
        dialog.categoryName = dialog:GetNamedChild("CategoryName"):GetNamedChild("Edit")
        dialog.categoryName:SetMaxInputChars(128)
        dialog.newTag = dialog:GetNamedChild("NewTag")
        dialog.tagName = dialog.newTag:GetNamedChild("Backdrop"):GetNamedChild("Edit")
        local container = dialog:GetNamedChild("Tag")
        dialog.tagCombo = ZO_ComboBox_ObjectFromContainer(container)
        dialog.parentCombo = ZO_ComboBox_ObjectFromContainer(dialog:GetNamedChild("Parent"))
        -- The native keyboard combo box is already scrollable.
        dialog.tagCombo:SetSortsItems(false)
        dialog.parentCombo:SetSortsItems(false)

        ZO_Dialogs_RegisterCustomDialog(NEW_CATEGORY_DIALOG, {
            customControl = dialog,
            title = { text = SI_AC_MENU_CM_NEW_CATEGORY },
            mainText = { text = SI_AC_DIALOG_CATEGORY_NAME_PROMPT },
            setup = setupNewCategoryDialog,
            finishedCallback = function(control)
                control.tagCombo:HideDropdown()
                control.parentCombo:HideDropdown()
            end,
            buttons = {
                {
                    control = dialog:GetNamedChild("Confirm"),
                    text = SI_OK,
                    noReleaseOnClick = true,
                    callback = submitNewCategoryDialog,
                },
                { control = dialog:GetNamedChild("Cancel"), text = SI_DIALOG_CANCEL },
            },
        })
        newCategoryDialogRegistered = true
    end
    ZO_Dialogs_ShowDialog(NEW_CATEGORY_DIALOG, { bagTypeId = bagTypeId, clickedParent = clickedParent })
end

-- Wrap the rule text of the header context menu "Rule" submenu into
-- single-line chunks: the context menu entries never wrap, so a long
-- rule is cut at the last space that fits the line. The rule texts
-- are filter expressions, so the words stay whole and the lines
-- joined back with spaces give the rule again.
local RULE_MENU_LINE_MAX = 75

local function wrapRuleText(text)
    local lines, cur = {}, ""
    for word in tostring(text or ""):gmatch("%S+") do
        if cur == "" then
            cur = word
        elseif #cur + 1 + #word <= RULE_MENU_LINE_MAX then
            cur = cur .. " " .. word
        else
            lines[#lines + 1] = cur
            cur = word
        end
    end
    if cur ~= "" then lines[#lines + 1] = cur end
    return lines
end

-- The AutoCategory entries of the category header context menu: the
-- execution priority of the clicked category, its level and
-- display-position operations in a "Level" submenu, the move of
-- the whole section under another category of the bag in a "Move To"
-- submenu, the copy of the whole section to another bag in a "Copy
-- To" submenu, the removal of the category from the inventory list
-- of the clicked bag, and category creation last (the global rule stays
-- and the categories nested under it move up one level, exactly like
-- the Remove Category button of Bag Settings; it is neither the
-- hidden state - the children would disappear with it - nor the
-- deletion of the rule). A predefined (protected) rule accepts the
-- level, priority and display-removal operations too (the display
-- removal only takes it out of the inventory list of the clicked
-- bag; the protected rule itself is never deletable). Added by
-- AC_ItemRowHeader_OnShowContextMenu (AutoCategory.lua); a no-op for
-- headers with no operable backing rule, except for New Category.
-- The menu is keyboard-only: the gamepad inventory lists have no
-- right click.
function AutoCategory.AddCategoryLevelMenuEntries(cateName, bagTypeId, menu, displayName, sourceList)
    if not AutoCategory.saved or not AutoCategory.saved.bags then return end
    if not AutoCategory.saved.bags[bagTypeId] then return end
    local addItem, addSubMenu = menu.addItem, menu.addSubMenu

    local rule = CLM.HeaderRule(cateName)

    -- the operations work on the bag rules of the clicked bag
    local subtree = nil
    if rule then
        subtree = CLM.SubtreeInBag(bagTypeId, rule.name)
    end
    if not subtree then
        rule = nil
    end

    if rule then

        -- Only the clicked bag's execution priority is editable here.
        local infoBagrule = subtree[1].bagrule
        local ruleEntries = {}
        if infoBagrule and type(infoBagrule.runpriority) == "number" then
            local ruleName = rule.name
            local function clampPriority(value)
                return math.max(0, math.min(1000, math.floor(value + 0.5)))
            end
            local function currentPriority()
                return clampPriority(infoBagrule.runpriority)
            end
            ruleEntries[#ruleEntries + 1] = {
                slider = {
                    label = GetString(SI_AC_MENU_BS_SLIDER_CATEGORY_RUNPRIORITY),
                    tooltip = GetString(SI_AC_MENU_BS_SLIDER_CATEGORY_RUNPRIORITY_TOOLTIP),
                    data = { min = 0, max = 1000, step = 1, value = currentPriority },
                    callback = function(value)
                        if type(value) ~= "number" or value ~= value
                            or findBagRule(bagTypeId, ruleName) ~= infoBagrule then return end
                        local priority = clampPriority(value)
                        -- Do not save or refresh an unchanged value.
                        if priority == currentPriority() then return end
                        infoBagrule.runpriority = priority
                        refreshAfterChange()
                    end,
                },
            }
        end
        -- Keep the rule expression read-only and wrap long text as before.
        local ruleText = rule.rule or ""
        if ruleText ~= "" then
            for _, line in ipairs(wrapRuleText(ruleText)) do
                ruleEntries[#ruleEntries + 1] = {
                    label = line,
                    kind = "text",
                }
            end
        end
        if #ruleEntries > 0 then
            table.insert(ruleEntries, 1, { label = displayName or rule.name, isHeader = true })
            menu.addDivider()
            addSubMenu(GetString(SI_AC_MENU_CM_RULE), ruleEntries)
        end

        -- the level and display-position operations of the
        -- category, in a "Level" submenu and inside their existing
        -- limits (the 1-5 levels, the 2..1000 display priorities);
        -- an inapplicable operation is not offered
        local levelEntries = {}
        -- move the category one display position up: take the
        -- display priority of the category displayed just above
        -- and step one past it, inside the 2..1000 slider range
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
        -- move the category one display position down: take the
        -- display priority of the category displayed just below
        -- and step one past it
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
            addSubMenu(GetString(SI_AC_MENU_CM_LEVEL_SUBMENU),
                levelEntries)
        end

        -- Show the same destinations as the inventory-item menu. Keep
        -- invalid moves visible but disabled, including cycles and depth.
        -- Top Level remains a separate action for nested categories.
        local moveEntries = {}
        if CLM.EffectiveLevel(rule) > 1 or (type(rule.parent) == "string"
                and rule.parent ~= "") then
            moveEntries[#moveEntries + 1] = {
                label = GetString(SI_AC_MENU_CM_MOVE_TOP),
                callback = function()
                    CLM.MoveSubtreeAndRefresh(bagTypeId, rule.name, nil)
                end,
            }
        end
        local excluded = {}
        for _, member in ipairs(subtree) do
            excluded[member.rule.name] = true
        end
        for _, destination in ipairs(CLM.GetMoveDestinations(bagTypeId)) do
            local name = destination.name
            local callback
            if not excluded[name] and name ~= rule.parent and moveDelta(subtree, name) ~= nil then
                callback = function()
                    local target = findBagrule(bagTypeId, name)
                    if target and not target.isHidden then
                        CLM.MoveSubtreeAndRefresh(bagTypeId, rule.name, name)
                    end
                end
            end
            moveEntries[#moveEntries + 1] = { label = destination.label, callback = callback }
        end
        if #moveEntries > 0 then
            addSubMenu(GetString(SI_AC_MENU_CM_MOVE_SUBMENU), moveEntries, { searchable = true })
        end

        -- Stage multiple destinations; only a marked bag can overwrite.
        local copyEntries = {}
        local function copyToBag(bagId, bagName, overwrite)
            local copied, skipped, overwritten = CLM.CopySubtreeToBag(
                bagTypeId, rule.name, bagId, overwrite)
            local message
            if overwritten > 0 then
                message = string.format(GetString(SI_AC_MESSAGE_CM_COPY_OVERWRITE_DONE),
                    copied, bagName, overwritten)
            else
                message = string.format(GetString(SI_AC_MESSAGE_CM_COPY_DONE),
                    copied, bagName, skipped)
            end
            CHAT_ROUTER:AddSystemMessage(message)
            return copied > 0 or overwritten > 0
        end
        local bags_cvt = AutoCategory.cache and AutoCategory.cache.bags_cvt
        if bags_cvt and bags_cvt.choices and bags_cvt.choicesValues then
            for i = 1, #bags_cvt.choicesValues do
                local bagId = bags_cvt.choicesValues[i]
                local bagName = bags_cvt.choices[i]
                if bagId ~= bagTypeId and bagName then
                    local overwrite = findBagrule(bagId, rule.name) ~= nil
                    local entry = {
                        label = bagName,
                        overwriteTooltip = overwrite and GetString(SI_AC_TIP_CM_COPY_OVERWRITE) or nil,
                        copySelected = function()
                            return copyToBag(bagId, bagName, overwrite)
                        end,
                    }
                    entry.onChecked = function(checked)
                        entry.selected = checked == true
                    end
                    copyEntries[#copyEntries + 1] = entry
                end
            end
        end
        if #copyEntries > 0 then
            local title = GetString(SI_AC_MENU_CM_COPY_SUBMENU)
            addSubMenu(title, copyEntries, { copyAction = function()
                local changed = false
                for _, entry in ipairs(copyEntries) do
                    if entry.selected then
                        entry.selected = false
                        if entry.copySelected() then changed = true end
                    end
                end
                if changed then refreshAfterChange() end
            end })
        end
    end

    -- the removal of the category from the inventory list of the
    -- clicked bag only, for a predefined (protected) rule as well:
    -- the global rule stays (a protected rule is never deleted,
    -- it only leaves the display of the clicked bag) and the
    -- categories nested under it move up one level
    if rule then
        addItem(GetString(SI_AC_MENU_CM_REMOVE_DISPLAY),
            function()
                if CLM.DeleteLevelInBag(bagTypeId, rule.name) then
                    refreshAfterChange()
                end
            end)
    end
    
    -- Snapshot the clicked category before the menu callback opens the dialog.
    -- New Category is also offered on headers that cannot be a parent.
    local clickedRule = rule and CLM.HeaderRuleForDrag(bagTypeId, cateName)
    local clickedParent = clickedRule and { name = clickedRule.name, level = CLM.EffectiveLevel(clickedRule) }
    addItem(GetString(SI_AC_MENU_CM_NEW_CATEGORY),
        function() CLM.OpenNewCategoryDialog(bagTypeId, clickedParent) end)
    addItem(GetString(SI_AC_MENU_CM_MANAGE_CATEGORIES),
        function() AutoCategory.CategoryManagement.Open(bagTypeId, refreshAfterChange, sourceList) end)
end
