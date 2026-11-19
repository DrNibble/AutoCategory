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
    -- (the inventory only builds headers from matching items). The
    -- zero-count header right after creation comes from the session
    -- marker (CLM.CreatedThisSession), not from a persisted marker:
    -- give every new category a hidden placeholder sub-category only
    -- to keep it a structural parent of nested rules. Its rule is
    -- false, so it never matches anything and never displays. The
    -- placeholder is an ordinary category: it can be edited (drop
    -- items in it) or deleted like any other.
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

local NEW_CATEGORY_DIALOG = "AUTO_CATEGORY_NEW_CATEGORY"
local newCategoryDialogRegistered = false

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
-- for a brand new tag. The value is the
-- tag the new category gets (nil keeps the empty tag); the new-tag
-- entry is marked with isNew and shows the tag name input row
-- inside the same dialog.
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
-- follow-up dialog or context menu. The controls are built once
-- per dialog control and reused; every opening refreshes the tag
-- list and resets the selection to the empty tag (the previous
-- default).
local TAG_DROPDOWN_WIDTH = 150 -- the dropdown
local TAG_DROPDOWN_MIN_WIDTH = 120 -- the dropdown never shrinks
                                   -- below this, even on a cramped row
local TAG_LABEL_WIDTH = 90     -- room for the "Tag" label
local TAG_DROPDOWN_GAP = 12    -- between the edit box and the label
local TAG_EDIT_MIN_WIDTH = 160 -- the name field never collapses
local NEW_CATEGORY_DIALOG_WIDTH = 450 -- the window is a quarter
                                     -- wider than the framework's 360
                               -- below this (it becomes an unusable
                               -- sliver without an explicit width)

local newCategoryTagControls = nil -- { label, comboControl, comboBox,
                                   --   tagNameLabel, tagEdit, tagEditBox }
local newCategoryTagChoice = nil   -- the selected choice entry
local newTagRowShown = false       -- the tag name input row is visible
local centerDialogButtons = nil    -- forward declaration: showing and
                                   -- hiding the tag name row re-centers
                                   -- the OK and Cancel buttons under it

-- The choice currently selected in the dropdown of the open dialog
-- (the empty tag before the user picks one).
function CLM.GetNewCategoryTagChoice()
    return newCategoryTagChoice
end

-- The tag name input row, below the edit box row of the same dialog:
-- shown while "New Tag..." is selected in the dropdown, hidden
-- for every other choice (and its text is cleared, so the next
-- opening starts fresh). Selecting the entry gives the field the
-- focus: the name is typed right away, in the field that just
-- appeared.
local function showNewTagNameRow()
    local controls = newCategoryTagControls
    if not controls then return end
    controls.tagNameLabel:SetHidden(false)
    controls.tagEdit:SetHidden(false)
    newTagRowShown = true
    local box = controls.tagEditBox
    if box and box.TakeFocus then box:TakeFocus() end
    if centerDialogButtons and ZO_Dialogs_FindDialog then
        local dialog = ZO_Dialogs_FindDialog(NEW_CATEGORY_DIALOG)
        if dialog then centerDialogButtons(dialog) end
    end
end

local function hideNewTagNameRow()
    newTagRowShown = false
    local controls = newCategoryTagControls
    if not controls then return end
    controls.tagNameLabel:SetHidden(true)
    controls.tagEdit:SetHidden(true)
    -- clear the typed name: a hidden field must not keep it
    local box = controls.tagEditBox
    if box and box.SetText then box:SetText("") end
    if centerDialogButtons and ZO_Dialogs_FindDialog then
        local dialog = ZO_Dialogs_FindDialog(NEW_CATEGORY_DIALOG)
        if dialog then centerDialogButtons(dialog) end
    end
end

local function hideNewCategoryTagDropdown(dialog)
    if newCategoryTagControls then
        newCategoryTagControls.label:SetHidden(true)
        newCategoryTagControls.comboControl:SetHidden(true)
        -- restore the framework's stock window width: the
        -- other dialogs that use the same window must not
        -- see the widened one
        if newCategoryTagControls.stockTitleWidth then
            local dialogControl = dialog
            if not dialogControl and ZO_Dialogs_FindDialog then
                dialogControl = ZO_Dialogs_FindDialog(
                    NEW_CATEGORY_DIALOG)
            end
            local title = dialogControl
                and dialogControl.GetNamedChild
                and dialogControl:GetNamedChild("Title")
            if title and title.SetWidth then
                title:SetWidth(
                    newCategoryTagControls.stockTitleWidth)
            end
        end
    end
    hideNewTagNameRow()
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
        -- the tag name input row, below the edit box row: the
        -- label starts the row, the input field takes the rest
        -- of the row after it (its width is set per opening,
        -- from the row width minus the label)
        local tagNameLabel = WINDOW_MANAGER:CreateControl(
            "$(parent)ACTagNameLabel", dialog, CT_LABEL)
        tagNameLabel:SetFont("ZoFontGame")
        tagNameLabel:SetText(GetString(SI_AC_DIALOG_TAG_NAME_FIELD))
        local tagEdit = CreateControlFromVirtual(
            "$(parent)ACTagEdit", dialog,
            "ZO_SingleLineEditBackdrop_Keyboard")
        local tagEditBox = CreateControlFromVirtual(
            "$(parent)ACTagEditBox", tagEdit,
            "ZO_DefaultEditForBackdrop")
        tagNameLabel:SetAnchor(TOPLEFT, edit, BOTTOMLEFT, 0, 13)
        tagEdit:SetAnchor(TOPLEFT, tagNameLabel, TOPRIGHT,
            TAG_DROPDOWN_GAP, -3)
        tagNameLabel:SetHidden(true)
        tagEdit:SetHidden(true)
        newCategoryTagControls = {
            label = label,
            comboControl = comboControl,
            comboBox = ZO_ComboBox_ObjectFromContainer(comboControl),
            tagNameLabel = tagNameLabel,
            tagEdit = tagEdit,
            tagEditBox = tagEditBox,
        }
        -- the framework's stock width of the title, captured
        -- once before the window is ever widened, to restore
        -- it on release
        local title = dialog:GetNamedChild("Title")
        if title and title.GetWidth then
            newCategoryTagControls.stockTitleWidth
                = title:GetWidth()
        end
        newCategoryTagControls.tagNameLabelWidth =
            tagNameLabel:GetWidth()
    end

    local controls = newCategoryTagControls
    local comboBox = controls.comboBox
    if not comboBox then return end
    controls.label:SetHidden(false)
    controls.comboControl:SetHidden(false)

    -- Make room for the dropdown on the edit box row: the edit
    -- box keeps the left end of the row, the label and the
    -- dropdown the right end. The dialog framework re-applies
    -- the anchors of the edit box on every opening (a two-sided
    -- pair that stretches it across the whole row); the single
    -- anchor kept here plus an explicit width replaces that
    -- stretch. The width is ALWAYS set: a leftover below the
    -- minimum must never leave the edit box without a width -
    -- it collapses to an unusable sliver then (the name field
    -- of 4.6.27). The dropdown gives way first, down to its own
    -- minimum; only then does the row overflow the framework's
    -- width a little.
    local isValid, point, relTo, relPoint, offX, offY = edit:GetAnchor(0)
    if isValid and relTo then
        edit:ClearAnchors()
        edit:SetAnchor(point, relTo, relPoint, offX, offY)
    end
    -- widen the window itself: the row is a quarter wider
    -- than the stock 360 content, and the title is set to the
    -- SAME width so the whole window (the backdrop sizes
    -- itself to its children) grows symmetrically around the
    -- screen center - a wider row alone would overflow the
    -- right edge of a still-centered window
    local title = dialog:GetNamedChild("Title")
    if title and title.SetWidth then
        title:SetWidth(NEW_CATEGORY_DIALOG_WIDTH)
    end
    -- the row is laid out on the widened width: the extra
    -- room goes to the name field (the dropdown and the
    -- label keep their width)
    local rowWidth = NEW_CATEGORY_DIALOG_WIDTH
    local labelRoom = TAG_DROPDOWN_GAP + TAG_LABEL_WIDTH
        + TAG_DROPDOWN_GAP
    local dropdownWidth = TAG_DROPDOWN_WIDTH
    local editWidth = rowWidth - labelRoom - dropdownWidth
    if editWidth < TAG_EDIT_MIN_WIDTH then
        dropdownWidth = rowWidth - labelRoom - TAG_EDIT_MIN_WIDTH
        if dropdownWidth < TAG_DROPDOWN_MIN_WIDTH then
            dropdownWidth = TAG_DROPDOWN_MIN_WIDTH
        end
        editWidth = rowWidth - labelRoom - dropdownWidth
        if editWidth < TAG_EDIT_MIN_WIDTH then
            editWidth = TAG_EDIT_MIN_WIDTH
        end
    end
    controls.comboControl:SetWidth(dropdownWidth)
    controls.dropdownWidth = dropdownWidth
    edit:SetWidth(editWidth)
    -- the tag name input row spans the same row width: the
    -- label at its left, the input field after it
    controls.tagEdit:SetWidth(rowWidth
        - (controls.tagNameLabelWidth or 120) - TAG_DROPDOWN_GAP)

    comboBox:ClearItems()
    local choices = CLM.NewCategoryTagChoices()
    local defaultEntry = nil
    for i = 1, #choices do
        local choice = choices[i]
        local entry = comboBox:CreateItemEntry(choice.label, function()
            newCategoryTagChoice = choice
            if choice.isNew then
                showNewTagNameRow()
            else
                hideNewTagNameRow()
            end
        end)
        comboBox:AddItem(entry)
        if choice.value == nil and not choice.isNew then
            defaultEntry = entry
        end
    end
    -- reset the selection to the empty tag without firing its
    -- callback, and hide the tag name input row of the
    -- "New Tag..." entry until it is selected again
    newCategoryTagChoice = nil
    hideNewTagNameRow()
    if defaultEntry then
        comboBox:SelectItem(defaultEntry, true)
    end
end

-- Center the OK and Cancel buttons of the New Category dialog
-- horizontally under the edit box row, on their texts (SI_OK /
-- SI_DIALOG_CANCEL): the dialog framework anchors them to the
-- bottom right corner by default, and it re-applies its own
-- anchors on every opening, so this runs after every
-- ZO_Dialogs_ShowDialog, keeping the framework's spacing and
-- vertical offset. Each button also carries its key label
-- ([E], [ALT]) and its paddings on the left of its text, so the
-- pair is positioned from the name labels (right-anchored inside
-- their button) instead of the button boxes. The row the pair is
-- centered on is the width the edit box row really occupies
-- (edit box + label room + dropdown, as laid out by the setup
-- above); the main text control the edit box is anchored to is
-- only the fallback when the tag row was not built.
centerDialogButtons = function(dialog)
    local edit = dialog:GetNamedChild("Edit")
    local b1 = dialog:GetNamedChild("Button1")
    local b2 = dialog:GetNamedChild("Button2")
    if not edit or not b1 or not b2 then return end
    -- the row the buttons sit under: the tag name input row
    -- while it is shown (it spans the full row width), the
    -- edit box row otherwise
    local anchorTo = edit
    if newTagRowShown and newCategoryTagControls
        and newCategoryTagControls.tagEdit then
        anchorTo = newCategoryTagControls.tagEdit
    end
    local rowWidth = nil
    if newCategoryTagControls and newCategoryTagControls.dropdownWidth
        and newCategoryTagControls.dropdownWidth >= TAG_DROPDOWN_MIN_WIDTH
        and edit.GetWidth then
        rowWidth = edit:GetWidth() + TAG_DROPDOWN_GAP
            + TAG_LABEL_WIDTH + TAG_DROPDOWN_GAP
            + newCategoryTagControls.dropdownWidth
    end
    if not rowWidth then
        local isValid, _, relTo = edit:GetAnchor(0)
        if not isValid or not relTo or not relTo.GetWidth then
            return
        end
        rowWidth = relTo:GetWidth()
    end
    local spacing = 20 -- the framework's BUTTON_SPACING
    local w1, w2 = b1:GetWidth(), b2:GetWidth()
    -- the name text of each button and its inset from the
    -- button's right edge (the name label is right-anchored)
    local t1, t2 = w1, w2
    local r1, r2 = 0, 0
    local function readNameLabel(button)
        if not button.GetNamedChild then return end
        local label = button:GetNamedChild("NameLabel")
        if not label or not label.GetWidth or not label.GetAnchor then
            return
        end
        local aValid, _, aRelTo, _, aOffX = label:GetAnchor(0)
        if not aValid or aRelTo ~= button then return end
        return label:GetWidth(), -aOffX
    end
    local nt1, nr1 = readNameLabel(b1)
    local nt2, nr2 = readNameLabel(b2)
    if nt1 then t1, r1 = nt1, nr1 end
    if nt2 then t2, r2 = nt2, nr2 end
    b1:ClearAnchors()
    b2:ClearAnchors()
    if b2:IsHidden() then
        b1:SetAnchor(TOPLEFT, anchorTo, BOTTOMLEFT,
            (rowWidth - t1) / 2 - (w1 - t1 - r1), 23)
    else
        -- offset so that the pair of texts is centered on the
        -- row (the buttons keep the framework's spacing)
        local offX = (rowWidth - (w1 + spacing + w2)) / 2
            + (r1 + r2 + t1 - w1) / 2
        b1:SetAnchor(TOPLEFT, anchorTo, BOTTOMLEFT, offX, 23)
        b2:SetAnchor(TOPLEFT, b1, TOPRIGHT, spacing, 0)
    end
end

function CLM.OpenNewCategoryDialog(bagTypeId)
    local bags = AutoCategory.saved and AutoCategory.saved.bags
    if not bags or not bags[bagTypeId] then return end
    if not newCategoryDialogRegistered then
        ZO_Dialogs_RegisterCustomDialog(NEW_CATEGORY_DIALOG, {
            title = { text = SI_AC_MENU_CM_NEW_CATEGORY },
            mainText = { text = SI_AC_DIALOG_CATEGORY_NAME_PROMPT },
            editBox = { defaultText = "", maxInputCharacters = 128 },
            finishedCallback = function(dialog)
                hideNewCategoryTagDropdown(dialog)
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
                        -- then apply the tag chosen in the dropdown
                        -- beside the edit box: the empty tag (the
                        -- previous default), an existing tag, or a
                        -- brand new one typed in the input row
                        -- below, in the same dialog (that row is
                        -- shown while "New Tag..." is selected). A
                        -- blank tag name keeps the dialog open too
                        local choice = CLM.GetNewCategoryTagChoice()
                        local newTag = nil
                        if choice and choice.isNew then
                            local text = newCategoryTagControls
                                and newCategoryTagControls.tagEditBox
                                    :GetText()
                            newTag = type(text) == "string"
                                and text:match("^%s*(.-)%s*$") or ""
                            if newTag == "" then
                                ZO_Dialogs_UpdateDialogMainText(dialog,
                                    { text = GetString(
                                        SI_AC_DIALOG_TAG_NAME_EMPTY) })
                                return
                            end
                        end
                        ZO_Dialogs_ReleaseDialog(NEW_CATEGORY_DIALOG)
                        createCategoryWithTag(bagTypeId, newName,
                            newTag or (choice and choice.value or nil))
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
        centerDialogButtons(dialog)
    end
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
-- deletion of the rule). A submenu cannot hold a submenu in ESO, so
-- the level operations sit in their own submenu, next to the move
-- and copy submenus. A predefined (protected) rule accepts the
-- level, priority and display-removal operations too (the display
-- removal only takes it out of the inventory list of the clicked
-- bag; the protected rule itself is never deletable). Added by
-- AC_ItemRowHeader_OnShowContextMenu (AutoCategory.lua); a no-op for
-- headers with no operable backing rule, except for New Category.
-- The menu is keyboard-only: the gamepad inventory lists have no
-- right click.
function AutoCategory.AddCategoryLevelMenuEntries(cateName, bagTypeId, addMoveSubMenu)
    if not AutoCategory.CategoryLevelMenu then return end
    if not AutoCategory.saved or not AutoCategory.saved.bags then return end
    if not AutoCategory.saved.bags[bagTypeId] then return end

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

        -- the numeric execution priority of the category (read-only
        -- information): the runpriority of its bag rule in this bag,
        -- the order the rules run in (not the display order)
        local infoBagrule = subtree[1].bagrule
        -- if infoBagrule and infoBagrule.runpriority then
            -- AddCustomMenuItem(
                -- string.format(GetString(SI_AC_MENU_CM_RUN_PRIORITY),
                    -- infoBagrule.runpriority),
                -- function() end, MENU_ADD_OPTION_LABEL)
        -- end

        -- the rule of the category (read-only information): a "Rule"
        -- submenu right after the priority display, holding the
        -- execution priority again and the rule text of the clicked
        -- category - the criteria its items are sorted by, the same
        -- text the rule editbox of the settings shows. The context
        -- menu entries are single-line, so a long rule text is
        -- wrapped over as many entries as needed.
        local ruleEntries = {}
        if infoBagrule and infoBagrule.runpriority then
            ruleEntries[#ruleEntries + 1] = {
                label = string.format(GetString(SI_AC_MENU_CM_RUN_PRIORITY),
                    infoBagrule.runpriority),
                callback = function() end,
            }
        end
        local ruleText = rule.rule or ""
        if ruleText ~= "" then
            for _, line in ipairs(wrapRuleText(ruleText)) do
                ruleEntries[#ruleEntries + 1] = {
                    label = line,
                    callback = function() end,
                }
            end
        end
        if #ruleEntries > 0 then
            AddCustomSubMenuItem(GetString(SI_AC_MENU_CM_RULE), ruleEntries)
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
            local addSubMenu = addMoveSubMenu or AddCustomSubMenuItem
            addSubMenu(GetString(SI_AC_MENU_CM_MOVE_SUBMENU), moveEntries)
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
    -- clicked bag only, for a predefined (protected) rule as well:
    -- the global rule stays (a protected rule is never deleted,
    -- it only leaves the display of the clicked bag) and the
    -- categories nested under it move up one level
    if rule then
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
