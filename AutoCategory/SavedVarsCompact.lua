-- SavedVarsCompact.lua
--
-- Size optimization for the AutoCategory SavedVariables file.
--
-- The saved variables file grows large over time because:
--   * every character section keeps a full copy of the bag category
--     lists and collapse states, even when the account-wide setting
--     is enabled (in which case they are never read again);
--   * older versions left data behind in a format that is no longer
--     read (array indexed rules with a "priority" key);
--   * every bag rule entry repeats values that are the defaults
--     (runpriority 1000, showpriority equal to runpriority,
--     isHidden false);
--   * the sections of every account ever logged in on this machine
--     are kept in the file forever, even for accounts that are no
--     longer played (the game rewrites the whole file at logout).
--
-- This module provides pure functions that operate on the raw saved
-- variables tables (the same tables the game serializes at logout):
--
--   InflateBagRules(bags)  - fill back the default values that were
--                            trimmed away (call after loading, before
--                            anything reads the bag rules).
--   TrimBagRules(bags)     - remove redundant default values from a
--                            bags table (call just before saving).
--   CleanupDeadCharacterData(rawSV) - drop the per-character data that
--                            is never read (account-wide enabled), for
--                            every account in the file.
--   TrimOtherAccounts(rawSV, currentAccount) - trim the redundant
--                            values from the sections of the other
--                            accounts.
--   TrimCurrentAccount(acctSaved, charSaved) - trim the current
--                            account's tables (call at logout).
--   PurgeOtherAccounts(rawTable, currentAccount) - remove every other
--                            account's section from a raw saved
--                            variables table (user initiated).
--
-- The module is pure Lua 5.1: no ESO API and no library dependency,
-- so it can be unit tested outside the game client.

AutoCategory = AutoCategory or {}
AutoCategory.SavedVarsCompact = {}

local SVC = AutoCategory.SavedVarsCompact

-- the default run priority used when a bag rule is created without
-- one (see AutoCategory.CreateBagRule)
SVC.DEFAULT_RUN_PRIORITY = 1000

-- ---------------------------------------------------------------------------
-- bag rules (bags[bagId] = { rules = { [ruleName] = bagrule } }, where a
-- bagrule is { name, runpriority, showpriority, isHidden })
-- ---------------------------------------------------------------------------

-- fill the trimmed default values back into a bags table, and migrate
-- the old "priority" key of pre-4.x bag rules when found.
-- returns the number of bag rule entries that were touched.
function SVC.InflateBagRules(bags)
    local filled = 0
    if type(bags) ~= "table" then return filled end
    for _, bag in pairs(bags) do
        if type(bag) == "table" and type(bag.rules) == "table" then
            for _, rule in pairs(bag.rules) do
                if type(rule) == "table" and type(rule.name) == "string" then
                    -- migrate the old "priority" key if present
                    if rule.priority ~= nil and rule.runpriority == nil then
                        rule.runpriority = rule.priority
                        rule.priority = nil
                    end
                    if rule.runpriority == nil then
                        rule.runpriority = SVC.DEFAULT_RUN_PRIORITY
                    end
                    if rule.showpriority == nil then
                        rule.showpriority = rule.runpriority
                    end
                    filled = filled + 1
                end
            end
        end
    end
    return filled
end

-- remove the values that InflateBagRules re-creates from the defaults:
--   * showpriority when it is equal to runpriority (the display code
--     falls back to runpriority when showpriority is missing);
--   * runpriority when it is the default (1000);
--   * isHidden when it is false.
-- returns the number of values that were removed.
function SVC.TrimBagRules(bags)
    local trimmed = 0
    if type(bags) ~= "table" then return trimmed end
    for _, bag in pairs(bags) do
        if type(bag) == "table" and type(bag.rules) == "table" then
            for _, rule in pairs(bag.rules) do
                if type(rule) == "table" and type(rule.name) == "string" then
                    if rule.runpriority ~= nil and rule.showpriority ~= nil
                        and rule.showpriority == rule.runpriority then
                        rule.showpriority = nil
                        trimmed = trimmed + 1
                    end
                    if rule.runpriority == SVC.DEFAULT_RUN_PRIORITY then
                        rule.runpriority = nil
                        trimmed = trimmed + 1
                    end
                    if rule.isHidden == false then
                        rule.isHidden = nil
                        trimmed = trimmed + 1
                    end
                end
            end
        end
    end
    return trimmed
end

-- ---------------------------------------------------------------------------
-- whole file operations (rawSV is the raw global table such as
-- AutoCategorySavedVars: rawSV.Default[account][charId or "$AccountWide"]
-- [server] = data)
-- ---------------------------------------------------------------------------

-- walk every account in the file and remove the per-character data that
-- is never read again:
--   * general and appearance (always account-wide, older versions
--     wrongly stored them per character);
--   * rules (no longer stored per character);
--   * bags and collapses when the character uses the account-wide
--     settings (the account-wide section is used instead).
-- returns the number of character sections that were cleaned.
function SVC.CleanupDeadCharacterData(rawSV)
    local cleaned = 0
    if type(rawSV) ~= "table" or type(rawSV.Default) ~= "table" then
        return cleaned
    end
    for _, account in pairs(rawSV.Default) do
        if type(account) == "table" then
            for charId, entry in pairs(account) do
                if charId ~= "$AccountWide" and type(entry) == "table" then
                    for _, data in pairs(entry) do
                        if type(data) == "table" then
                            local dirty = false
                            if data.general ~= nil then
                                data.general = nil
                                dirty = true
                            end
                            if data.appearance ~= nil then
                                data.appearance = nil
                                dirty = true
                            end
                            if data.rules ~= nil then
                                data.rules = nil
                                dirty = true
                            end
                            if data.accountWide then
                                if data.bags ~= nil then
                                    data.bags = nil
                                    dirty = true
                                end
                                if data.collapses ~= nil then
                                    data.collapses = nil
                                    dirty = true
                                end
                            end
                            if dirty then cleaned = cleaned + 1 end
                        end
                    end
                end
            end
        end
    end
    return cleaned
end

-- trim the redundant default values from the bag rules of every account
-- except the current one (their sections are not read during this
-- session; the current account is inflated and trimmed separately).
-- returns the number of values that were removed.
function SVC.TrimOtherAccounts(rawSV, currentAccount)
    local trimmed = 0
    if type(rawSV) ~= "table" or type(rawSV.Default) ~= "table" then
        return trimmed
    end
    if type(currentAccount) ~= "string" or currentAccount == "" then
        return trimmed
    end
    local current = string.lower(currentAccount)
    for accountName, account in pairs(rawSV.Default) do
        if type(account) == "table"
            and string.lower(accountName) ~= current then
            for _, section in pairs(account) do
                if type(section) == "table" then
                    for _, data in pairs(section) do
                        if type(data) == "table" then
                            trimmed = trimmed + SVC.TrimBagRules(data.bags)
                        end
                    end
                end
            end
        end
    end
    return trimmed
end

-- trim the current account's tables (call at logout, just before the
-- game serializes the saved variables).
-- returns the number of values that were removed.
function SVC.TrimCurrentAccount(acctSaved, charSaved)
    local trimmed = 0
    if type(acctSaved) == "table" then
        trimmed = trimmed + SVC.TrimBagRules(acctSaved.bags)
    end
    if type(charSaved) == "table" and not charSaved.accountWide then
        trimmed = trimmed + SVC.TrimBagRules(charSaved.bags)
    end
    return trimmed
end

