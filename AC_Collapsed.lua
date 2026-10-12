
local AutoCat = AutoCategory

-- [bagId][categoryName] = generation
local seen = {}

-- [bagId] = generation
local generation = {}

--[[ Get the collapse state table for a bag.

    The returned table is the persistent collapse state table for the bag
    (created if missing):

        [categoryName] = true   -- collapsed
        [categoryName] = false  -- expanded

    A missing category means that the category is not currently
    present in the bag.

    Parameters:
        bagId - Bag identifier used as the key in saved.collapses.

    Returns:
        The collapse state table for the specified bag.
--]]
--[[local function getCategoryState(bagId)
    local collapses = AutoCat.saved.collapses
    local state = collapses[bagId]

    if not state then
        state = {}
        collapses[bagId] = state
    end

    return state
end
--]]
local function getCategoryState(bagId)
    local state = AutoCat.categoryState[bagId]

    if not state then
        state = {}
        AutoCat.categoryState[bagId] = state
    end

    return state
end

--[[ Get the temporary category tracking table for a bag.

    The table records the generation in which each category was
    most recently seen:

        [categoryName] = generation

    This allows UpdateCategoryState() to identify categories that
    are no longer present in the bag without creating a new state
    table during each update.

    Parameters:
        bagId - Bag identifier used as the key in seen.

    Returns:
        The temporary seen-state table for the specified bag.
--]]
local function getSeenState(bagId)
    local state = seen[bagId]

    if not state then
        state = {}
        seen[bagId] = state
    end

    return state
end


-- -----------------------------------------------------------

--[[ Load and initialize category collapse state.

    If category collapse persistence is disabled, clear all saved
    collapse states so categories start expanded.

    Parameters:
        None.

    Returns:
        The result of ResetCollapse() when collapse persistence is
        disabled; otherwise nil.
--]]
function AutoCat.LoadCollapse()
    local saved = AutoCat.saved

    if not saved.general["SAVE_CATEGORY_COLLAPSE_STATUS"] then
        return AutoCat.ResetCollapse(saved.collapses)
    end
end

--[[ Remove expanded categories from saved collapse state.

    Expanded categories are represented by false, which is the
    default state and therefore does not need to be persisted.
    Collapsed categories remain stored as true.

    Empty bag state tables are retained.

    Parameters:
        collapses - Collapse state table indexed by bag ID.

    Returns:
        Nothing.
--]]
function AutoCat.PruneCollapse(collapses)
    if not collapses then
        return
    end

    for _, bagcol in pairs(collapses) do
        if bagcol then
            for k in pairs(bagcol) do
                if bagcol[k] == false then
                    bagcol[k] = nil
                end
            end
        end
    end
end

--[[ Reset all saved category collapse states.

    Clears every category state from each bag, causing all
    categories to use their default state (expanded) when they
    are subsequently encountered.

    Parameters:
        collapses - Collapse state table indexed by bag ID.

    Returns:
        Nothing.
--]]
function AutoCat.ResetCollapse(collapses)
    if not collapses then
        return
    end

    for _, bagcol in pairs(collapses) do
        if bagcol then
            for k in pairs(bagcol) do
                bagcol[k] = nil
            end
        end
    end
end


--[[ Determine whether a category is collapsed.

    A missing bag or category is treated as expanded.

    Parameters:
        bagTypeId   - Bag identifier containing the category.
        categoryName - Name of the category to check.

    Returns:
        true  - The category is collapsed.
        false - The category is expanded or is not present.
--]]
function AutoCat.IsCategoryCollapsed(bagTypeId, categoryName)
    if bagTypeId == nil or categoryName == nil then
        return false
    end

    local state = AutoCat.categoryState
    if not state then
        return false
    end

    local bagState = state[bagTypeId]
    if not bagState then
        return false
    end

    return bagState[categoryName] == true
end

--[[ Set the collapse state of an existing category.

    Categories are created by UpdateCategoryState(). This function
    does not create missing categories, preserving the invariant
    that collapse state only exists for categories currently present
    in the bag.

    Parameters:
        bagTypeId    - Bag identifier containing the category.
        categoryName - Name of the category to update.
        collapsed    - true to collapse the category; any other value
                       sets the category to its default expanded state.

    Returns:
        Nothing.
--]]
function AutoCat.SetCategoryCollapsed(bagTypeId, categoryName, collapsed)
    if bagTypeId == nil or categoryName == nil then
        return
    end

    local state = AutoCat.categoryState[bagTypeId]
    if not state or state[categoryName] == nil then
        return
    end

    local isCollapsed = collapsed == true
    state[categoryName] = isCollapsed

    local collapses = AutoCat.saved.collapses[bagTypeId]

    if isCollapsed then
        if not collapses then
            collapses = {}
            AutoCat.saved.collapses[bagTypeId] = collapses
        end

        collapses[categoryName] = true
    elseif collapses then
        collapses[categoryName] = nil
    end
end


--[[ Reconcile the saved collapse state with the categories currently
    present in a bag.

    Existing categories retain their current collapse state.
    New categories are initialized as expanded (false).
    Categories no longer present in the bag are removed.

    A generation counter is used to identify categories that were not
    encountered during this update without creating a new tracking
    table for every reconciliation.

    The categories table is expected to contain the currently present
    category names as keys.

    Parameters:
        bagId     - Bag identifier whose category state is being updated.
        categories - Table containing the categories currently present
                     in the bag, keyed by category name.

    Returns:
        Nothing.
--]]
function AutoCat.UpdateCategoryState(bagId, categories)
    if bagId == nil or not categories then
        return
    end

    local state = getCategoryState(bagId)
    local bagSeen = getSeenState(bagId)

    local collapses = AutoCat.saved.collapses[bagId]
    if not collapses then
        collapses = {}
        AutoCat.saved.collapses[bagId] = collapses
    end

    local gen = (generation[bagId] or 0) + 1
    generation[bagId] = gen

    -- Mark currently present categories and initialize new ones.
    for categoryName in pairs(categories) do
        bagSeen[categoryName] = gen

        if state[categoryName] == nil then
            -- New categories start expanded.
            state[categoryName] = collapses[categoryName] == true
        end
    end

    --[[
    -- Remove categories no longer present.
    for categoryName in pairs(state) do
        if bagSeen[categoryName] ~= gen then
            state[categoryName] = nil
            collapses[categoryName] = nil
            bagSeen[categoryName] = nil
        end
    end
    --]]
end


--[[ Collapse all categories currently present in a bag.

    The bag's collapse-state table contains an entry for each
    category currently present in the bag. Set every such category
    to collapsed.

    Parameters:
        bagId - Bag identifier whose categories should be collapsed.

    Returns:
        Nothing.
--]]
function AutoCat:CollapseAllCategories(bagId)
    if bagId == nil then
        return
    end

    local state = AutoCat.categoryState[bagId]
    if not state then
        return
    end

    local collapses = AutoCat.saved.collapses[bagId]

    if not collapses then
        collapses = {}
        AutoCat.saved.collapses[bagId] = collapses
    end

    for categoryName in pairs(state) do
        state[categoryName] = true
        collapses[categoryName] = true
    end
end


--[[ Expand all categories currently present in a bag.

    The bag's collapse-state table contains an entry for each
    category currently present in the bag. Set every such category
    to the default expanded state.

    Parameters:
        bagId - Bag identifier whose categories should be expanded.

    Returns:
        Nothing.
--]]
function AutoCat:ExpandAllCategories(bagId)
    if bagId == nil then
        return
    end

    local state = AutoCat.categoryState[bagId]
    if not state then
        return
    end

    local collapses = AutoCat.saved.collapses[bagId]

    for categoryName in pairs(state) do
        state[categoryName] = false

        if collapses then
            collapses[categoryName] = nil
        end
    end
end
