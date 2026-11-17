-- PredefinedLayouts.lua
--
-- The level and parent of a predefined (protected) category.
--
-- The predefined category definitions come from the addon code (and
-- its plugins) and are never written to the saved variables, so a
-- level or parent set on one of them is kept as a per-name override
-- in the account saved rules ("AutoCatRules"): collected from the
-- combined rule list after every change, applied back onto the
-- predefined rules at every load.
--
-- The module is pure Lua 5.1: no ESO API and no library
-- dependency, so it can be unit tested outside the game client.

AutoCategory = AutoCategory or {}
AutoCategory.PredefinedLayouts = {}

local PL = AutoCategory.PredefinedLayouts

-- Collect(ruleList) -> overrides
--
-- ruleList - the combined rule list (AutoCategory.RulesW.ruleList):
--            the predefined entries are recognized by pred == 1
--
-- Returns the override map { [rule name] = { level, parent } } with
-- an entry for every predefined category that carries a level or a
-- parent, or nil when none does (so the saved variables section
-- disappears instead of staying around as an empty table).
function PL.Collect(ruleList)
    if type(ruleList) ~= "table" then return nil end

    local overrides = nil
    for i = 1, #ruleList do
        local rule = ruleList[i]
        if type(rule) == "table" and rule.pred == 1
            and type(rule.name) == "string" and rule.name ~= "" then
            local hasLevel = type(rule.level) == "number"
            local hasParent = type(rule.parent) == "string"
                and rule.parent ~= ""
            if hasLevel or hasParent then
                overrides = overrides or {}
                overrides[rule.name] = {
                    level = hasLevel and rule.level or nil,
                    parent = hasParent and rule.parent or nil,
                }
            end
        end
    end
    return overrides
end

-- Apply(overrides, ruleList)
--
-- overrides - the saved override map (acctRules.predefLayouts);
--             anything but a table is a no-op
-- ruleList - the combined rule list to apply the overrides onto
--
-- The level and the parent of a matching predefined category are
-- replaced; a rule that is not predefined is never touched (a user
-- category of the same name keeps its own fields), and an invalid
-- value (a level outside 1-5, not an integer; an empty or non-string
-- parent) is skipped, leaving the rule as it is.
function PL.Apply(overrides, ruleList)
    if type(overrides) ~= "table" then return end
    if type(ruleList) ~= "table" then return end

    for i = 1, #ruleList do
        local rule = ruleList[i]
        if type(rule) == "table" and rule.pred == 1
            and type(rule.name) == "string" then
            local ov = overrides[rule.name]
            if type(ov) == "table" then
                local level = ov.level
                if type(level) == "number" and level >= 1
                    and level <= 5 and level == math.floor(level) then
                    rule.level = level
                end
                local parent = ov.parent
                if type(parent) == "string" and parent ~= "" then
                    rule.parent = parent
                end
            end
        end
    end
end
