-- Categorize set items by their LibSets type and their localized set name.
AutoCategory_LibSets = {
    RuleFunc = {},
}

local function isLibSetsAvailable()
    return LibSets ~= nil
        and type(LibSets.GetSetType) == "function"
        and type(LibSets.GetSetTypeName) == "function"
        and type(LibSets.allowedSetTypes) == "table"
end

function AutoCategory_LibSets.Initialize()
    if isLibSetsAvailable() then
        AutoCategory.AddRuleFunc("autosettype", AutoCategory_LibSets.RuleFunc.AutoSetType)
        AutoCat_Logger():Info("Initializing LibSets plugin integration")
    else
        AutoCategory.AddRuleFunc("autosettype", AutoCategory.dummyRuleFunc)
    end
end

-- possibleSetTypes is local to LibSets. Resolve its exported global constants
-- instead, and validate against the public allowedSetTypes table.
local function resolveSetType(setType)
    if type(setType) == "string" then
        local constantName = setType
        if string.sub(constantName, 1, 16) ~= "LIBSETS_SETTYPE_" then
            constantName = "LIBSETS_SETTYPE_" .. string.upper(constantName)
        end
        setType = rawget(_G, constantName)
    end
    if type(setType) ~= "number" or not LibSets.allowedSetTypes[setType] then
        error("error: autosettype(): expected a valid LibSets set type ID or constant name.")
    end
    return setType
end

-- autosettype() matches all known set types.
-- autosettype(6), autosettype("DUNGEON") or
-- autosettype("LIBSETS_SETTYPE_DUNGEON") only matches dungeon sets.
function AutoCategory_LibSets.RuleFunc.AutoSetType(setType)
    if not isLibSetsAvailable() then
        return false
    end

    local requestedSetType
    if setType ~= nil then
        requestedSetType = resolveSetType(setType)
    end

    local hasSet, setName, _, _, _, setId =
        GetItemLinkSetInfo(AutoCategory.checking.ItemLink)
    if not hasSet or not setId or setId <= 0 or type(setName) ~= "string" then
        return false
    end

    -- GetSetType returns nil while the database is not ready, while scanning,
    -- or when this set is unknown to LibSets.
    local actualSetType = LibSets.GetSetType(setId)
    if not actualSetType or not LibSets.allowedSetTypes[actualSetType] then
        return false
    end
    if requestedSetType and requestedSetType ~= actualSetType then
        return false
    end

    -- Use the UI language explicitly instead of LibSets' cached default.
    local uiLanguage = type(GetCVar) == "function" and GetCVar("language.2") or "en"
    if type(uiLanguage) ~= "string" or uiLanguage == "" then
        uiLanguage = "en"
    else
        uiLanguage = string.lower(uiLanguage)
    end
    if LibSets.supportedLanguages and not LibSets.supportedLanguages[uiLanguage] then
        uiLanguage = "en"
    end
    local setTypeName = LibSets.GetSetTypeName(actualSetType, uiLanguage)
    if not setTypeName or setTypeName == "" then
        setTypeName = LibSets.GetSetTypeName(actualSetType, "en")
    end
    if not setTypeName or setTypeName == "" then
        return false
    end

    -- Strip ESO grammar suffixes, as autoset() does.
    setName = string.gsub(setName, "%^.*", "")
    if setName == "" then
        return false
    end
    AutoCategory.AdditionCategoryName = "(" .. setTypeName .. ") " .. setName
    return true
end

AutoCategory.RegisterPlugin("LibSets", AutoCategory_LibSets.Initialize)
