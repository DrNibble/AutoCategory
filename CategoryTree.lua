-- CategoryTree: multi-level collapsible categories for AutoCategory.
--
-- A category name containing the separator (default "----") is displayed as
-- nested collapsible headers, one per level. Example: a rule named
-- "Potions----Magie----Soin" renders in the inventory as:
--
--   Potions            [-]
--     Magie            [-]
--       Soin           [-]
--         <items>
--
-- Every level collapses independently, through the same saved collapse state
-- as flat categories: each header is keyed by its own prefix name
-- ("Potions", "Potions----Magie", "Potions----Magie----Soin").
--
-- A name with an empty level ("----Magie", "Potions----", "Potions------Soin")
-- is treated as a flat category name and displayed as-is. Spaces around each
-- level are trimmed.

AutoCategory = AutoCategory or {}

local CategoryTree = {
    -- splits the levels inside a category name
    SEPARATOR = "----",
    -- splits the levels inside a sort key;
    -- sorts before every printable character so a header of any level
    -- always precedes its lower levels and their items
    SORT_SEPARATOR = "\001",
}
AutoCategory.CategoryTree = CategoryTree

local SEPARATOR = CategoryTree.SEPARATOR
local SORT_SEPARATOR = CategoryTree.SORT_SEPARATOR

local function trim(text)
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Split a full category name into its levels. Returns a table of level
-- names (at least one), or nil for a non-string name. A name with a
-- missing or empty level is flat: the whole name is its single level.
function CategoryTree.Levels(fullName)
    if type(fullName) ~= "string" then
        return nil
    end

    local parts = {}
    local pos = 1
    while true do
        local sepStart, sepEnd = fullName:find(SEPARATOR, pos, true)
        if not sepStart then
            break
        end
        local part = trim(fullName:sub(pos, sepStart - 1))
        if part == "" then
            return { fullName }
        end
        parts[#parts + 1] = part
        pos = sepEnd + 1
    end
    local part = trim(fullName:sub(pos))
    if part == "" then
        return { fullName }
    end
    parts[#parts + 1] = part
    return parts
end

-- Number of display levels of a category name (1 for a flat name,
-- 0 for a non-string name).
function CategoryTree.LevelCount(fullName)
    local levels = CategoryTree.Levels(fullName)
    return levels and #levels or 0
end

-- Is the name hierarchical (more than one level)?
function CategoryTree.IsHierarchical(fullName)
    return CategoryTree.LevelCount(fullName) > 1
end

-- Two-level view of a name: parent (all levels but the last, re-joined)
-- and child (the last level). Returns fullName, nil for a flat name.
-- Kept for compatibility with two-level callers.
function CategoryTree.Split(fullName)
    if type(fullName) ~= "string" then
        return nil, nil
    end
    local levels = CategoryTree.Levels(fullName)
    if #levels < 2 then
        return fullName, nil
    end
    return table.concat(levels, SEPARATOR, 1, #levels - 1), levels[#levels]
end

-- Immediate parent prefix of a hierarchical name, or nil for a flat name.
-- This is what AC_parentName holds on inventory entries.
function CategoryTree.ParentOf(fullName)
    local levels = CategoryTree.Levels(fullName)
    if levels == nil or #levels < 2 then
        return nil
    end
    return table.concat(levels, SEPARATOR, 1, #levels - 1)
end

-- All ancestor prefixes of a name, outermost first; nil for a flat name.
-- A header or item is hidden while any of them is collapsed.
function CategoryTree.Ancestors(fullName)
    local levels = CategoryTree.Levels(fullName)
    if levels == nil or #levels < 2 then
        return nil
    end
    local prefixes = {}
    for i = 1, #levels - 1 do
        prefixes[#prefixes + 1] = table.concat(levels, SEPARATOR, 1, i)
    end
    return prefixes
end

-- Build a hierarchical name from its level names (an array of strings).
function CategoryTree.JoinName(levels)
    return table.concat(levels, SEPARATOR)
end

-- Build the sort key of an item (or header) of the category.
-- Flat categories keep the historical single-level key format, so existing
-- rules sort exactly as before. A hierarchical key places the outer levels
-- first, which makes the headers of every level, their sub-levels and
-- their items sort together, in that order.
-- sortName (optional) overrides the base of a flat key: plugins may
-- register a sort name for a category (AutoCategory.GetCategorySortName).
-- Hierarchical keys always use their own levels, which keeps the
-- documented format; sort names are registered per flat category.
function CategoryTree.BuildSortKey(showPriority, fullName, sortName)
    local levels = CategoryTree.Levels(fullName)
    if levels == nil or #levels == 1 then
        return string.format("%04d%s", 1000 - showPriority, sortName or fullName)
    end
    return string.format("%04d%s", 1000 - showPriority, levels[1])
        .. SORT_SEPARATOR .. table.concat(levels, SORT_SEPARATOR, 2, #levels)
end

-- Truncate a hierarchical sort key to its first levelCount levels: the
-- sort key of the header at that level. A key with fewer levels is
-- returned unchanged (the header of a flat category).
function CategoryTree.LevelSortKey(sortKey, levelCount)
    if type(sortKey) ~= "string" or type(levelCount) ~= "number"
        or levelCount < 1 then
        return nil
    end

    local count = 0
    local pos = 0
    while count < levelCount - 1 do
        local sepStart = sortKey:find(SORT_SEPARATOR, pos + 1, true)
        if not sepStart then
            return sortKey
        end
        pos = sepStart
        count = count + 1
    end

    local sepStart = sortKey:find(SORT_SEPARATOR, pos + 1, true)
    if sepStart then
        return sortKey:sub(1, sepStart - 1)
    end
    return sortKey
end

-- Derive the sort key of the immediate parent header from a child key: the
-- child key truncated at its last sort separator. Callers should keep the
-- smallest key seen, so the parent sorts at its best-priority child.
function CategoryTree.ParentSortKey(childKey)
    if type(childKey) ~= "string" then
        return nil
    end

    local lastStart
    local pos = 1
    while true do
        local sepStart = childKey:find(SORT_SEPARATOR, pos, true)
        if not sepStart then
            break
        end
        lastStart = sepStart
        pos = sepStart + 1
    end
    if not lastStart then
        return childKey
    end
    return childKey:sub(1, lastStart - 1)
end

-- Header display text of a category: nested headers show only their own
-- level text, top-level and flat categories show their full name.
function CategoryTree.DisplayName(fullName)
    local levels = CategoryTree.Levels(fullName)
    if levels == nil or #levels < 2 then
        return fullName
    end
    return levels[#levels]
end

-- One-line display text (gamepad headers): the levels joined with " - "
-- instead of the raw separator; flat names are returned unchanged.
function CategoryTree.JoinDisplayName(fullName)
    local levels = CategoryTree.Levels(fullName)
    if levels == nil or #levels < 2 then
        return fullName
    end
    return table.concat(levels, " - ")
end

-- Is the immediate level above an entry collapsed? Only hierarchical
-- entries have a parent level; parents and flat categories answer false.
function CategoryTree.IsParentCollapsed(bagTypeId, parentName)
    if parentName == nil or bagTypeId == nil then
        return false
    end
    return AutoCategory.IsCategoryCollapsed(bagTypeId, parentName)
end

-- Is any level above the entry collapsed? Headers and items of a
-- collapsed level are all hidden, whatever the state of the levels
-- between them and the entry.
function CategoryTree.IsAnyAncestorCollapsed(bagTypeId, fullName)
    local prefixes = CategoryTree.Ancestors(fullName)
    if prefixes == nil or bagTypeId == nil then
        return false
    end
    for _, prefix in ipairs(prefixes) do
        if AutoCategory.IsCategoryCollapsed(bagTypeId, prefix) then
            return true
        end
    end
    return false
end
