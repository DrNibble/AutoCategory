-- CategoryTree: two-level collapsible categories for AutoCategory.
--
-- A category name containing the separator (default "----") is displayed as
-- a parent header (text before the separator) whose children are collapsible
-- sub-headers (text after the separator). Example: a rule named
-- "Potions----Magie" renders in the inventory as:
--
--   Potions            [-]
--     Magie            [-]
--       <items>
--     Santé            [-]
--       <items>
--
-- Both levels collapse independently, through the same saved collapse state
-- as flat categories: the parent header is keyed by the parent name, each
-- child header by its full "parent----child" name.
--
-- A name with an empty parent or child part ("----Magie", "Potions----") is
-- treated as a flat category name and displayed as-is. Only the first
-- separator splits the name; a child part may contain further separators.
-- Spaces around both parts are trimmed.

AutoCategory = AutoCategory or {}

local CategoryTree = {
    -- splits a parent from its child inside a category name
    SEPARATOR = "----",
    -- splits the parent part from the child part inside a sort key;
    -- sorts before every printable character so a parent header always
    -- precedes its children and their items
    SORT_SEPARATOR = "\001",
}
AutoCategory.CategoryTree = CategoryTree

local SEPARATOR = CategoryTree.SEPARATOR
local SORT_SEPARATOR = CategoryTree.SORT_SEPARATOR

local function trim(text)
    return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Split a full category name into its parent and child parts.
-- Returns parentName, childName. childName is nil when the name is flat
-- (no separator, or an empty part); in that case parentName is the name to
-- display, unchanged.
function CategoryTree.Split(fullName)
    if type(fullName) ~= "string" then
        return nil, nil
    end

    local sepStart, sepEnd = fullName:find(SEPARATOR, 1, true)
    if not sepStart then
        return fullName, nil
    end

    local parent = trim(fullName:sub(1, sepStart - 1))
    local child = trim(fullName:sub(sepEnd + 1))
    if parent == "" or child == "" then
        return fullName, nil
    end

    return parent, child
end

-- Parent name of a hierarchical category, or nil for a flat name. This is
-- what AC_parentName holds on inventory entries.
function CategoryTree.ParentOf(fullName)
    local parent, child = CategoryTree.Split(fullName)
    if child == nil then
        return nil
    end
    return parent
end

-- Build the sort key of an item (or child header) of the category.
-- Flat categories keep the historical single-level key format, so existing
-- rules sort exactly as before. A hierarchical key places the parent part
-- first, which makes the parent header, its children and their items sort
-- together, in that order.
function CategoryTree.BuildSortKey(showPriority, fullName)
    local parent, child = CategoryTree.Split(fullName)
    if child == nil then
        return string.format("%04d%s", 1000 - showPriority, parent)
    end
    return string.format("%04d%s", 1000 - showPriority, parent)
        .. SORT_SEPARATOR .. child
end

-- Derive the sort key of a parent header from one of its child keys: the
-- child key truncated at the sort separator. Callers should keep the
-- smallest child key seen, so the parent sorts at its best-priority child.
function CategoryTree.ParentSortKey(childKey)
    if type(childKey) ~= "string" then
        return nil
    end
    local sepStart = childKey:find(SORT_SEPARATOR, 1, true)
    if not sepStart then
        return childKey
    end
    return childKey:sub(1, sepStart - 1)
end

-- Header display text of a category: children show only their own text,
-- parents and flat categories show their full name.
function CategoryTree.DisplayName(fullName)
    local parent, child = CategoryTree.Split(fullName)
    if child == nil then
        return parent
    end
    return child
end

-- One-line display text (gamepad headers): "parent - child" instead of the
-- raw separator; flat names are returned unchanged.
function CategoryTree.JoinDisplayName(fullName)
    local parent, child = CategoryTree.Split(fullName)
    if child == nil then
        return parent
    end
    return parent .. " - " .. child
end

-- Is the level above an entry collapsed? Only hierarchical entries have a
-- parent level; parents and flat categories answer false.
function CategoryTree.IsParentCollapsed(bagTypeId, parentName)
    if parentName == nil or bagTypeId == nil then
        return false
    end
    return AutoCategory.IsCategoryCollapsed(bagTypeId, parentName)
end
