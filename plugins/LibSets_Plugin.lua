-- Categorize set items by their LibSets type and their localized set name.
AutoCategory_LibSets = {
    RuleFunc = {},
}

local setTypeToLibraryInternalVariableNames = {}

function AutoCategory_LibSets.Initialize()
    if IsLibSetsAlreadyLoaded and IsLibSetsAlreadyLoaded(true) then
        -- Copy of LibSets.setTypeToLibraryInternalVariableNames. Build only
        -- after LibSets is loaded, so its global constants exist.
        setTypeToLibraryInternalVariableNames = {
            [LIBSETS_SETTYPE_ARENA] = {
                [LIBSETS_TABLEKEY_TABLENAME] = "arenaSets",
            },
            [LIBSETS_SETTYPE_BATTLEGROUND] = {
                [LIBSETS_TABLEKEY_TABLENAME] = "battlegroundSets",
            },
            [LIBSETS_SETTYPE_CRAFTED] = {
                [LIBSETS_TABLEKEY_TABLENAME] = "craftedSets",
            },
            [LIBSETS_SETTYPE_CYRODIIL] = {
                [LIBSETS_TABLEKEY_TABLENAME] = "cyrodiilSets",
            },
            [LIBSETS_SETTYPE_DAILYRANDOMDUNGEONANDICREWARD] = {
                [LIBSETS_TABLEKEY_TABLENAME] = "dailyRandomDungeonAndImperialCityRewardSets",
            },
            [LIBSETS_SETTYPE_DUNGEON] = {
                [LIBSETS_TABLEKEY_TABLENAME] = "dungeonSets",
            },
            [LIBSETS_SETTYPE_IMPERIALCITY] = {
                [LIBSETS_TABLEKEY_TABLENAME] = "imperialCitySets",
            },
            [LIBSETS_SETTYPE_MONSTER] = {
                [LIBSETS_TABLEKEY_TABLENAME] = "monsterSets",
            },
            [LIBSETS_SETTYPE_OVERLAND] = {
                [LIBSETS_TABLEKEY_TABLENAME] = "overlandSets",
            },
            [LIBSETS_SETTYPE_SPECIAL] = {
                [LIBSETS_TABLEKEY_TABLENAME] = "specialSets",
            },
            [LIBSETS_SETTYPE_TRIAL] = {
                [LIBSETS_TABLEKEY_TABLENAME] = "trialSets",
            },
            [LIBSETS_SETTYPE_MYTHIC] = {
                [LIBSETS_TABLEKEY_TABLENAME] = "mythicSets",
            },
            [LIBSETS_SETTYPE_IMPERIALCITY_MONSTER] = {
                [LIBSETS_TABLEKEY_TABLENAME] = "monsterSets",
            },
            [LIBSETS_SETTYPE_CYRODIIL_MONSTER] = {
                [LIBSETS_TABLEKEY_TABLENAME] = "monsterSets",
            },
            [LIBSETS_SETTYPE_CLASS] = {
                [LIBSETS_TABLEKEY_TABLENAME] = "classSets",
            },
        }
        AutoCategory.AddRuleFunc("autosettype", AutoCategory_LibSets.RuleFunc.AutoSetType)
        AutoCat_Logger():Info("Initializing LibSets plugin integration")
    else
        AutoCategory.AddRuleFunc("autosettype", AutoCategory.dummyRuleFunc)
    end
end

-- autosettype() matches all known set types.
-- autosettype(6), autosettype("DUNGEON") or
-- autosettype("LIBSETS_SETTYPE_DUNGEON") only matches dungeon sets.
function AutoCategory_LibSets.RuleFunc.AutoSetType(setType)
    if not IsLibSetsAlreadyLoaded or not IsLibSetsAlreadyLoaded(true) then
        return false
    end

    local requestedSetType
    if setType ~= nil then
        if type(setType) == "string" then
            local constantName = setType
            if string.sub(constantName, 1, 16) ~= "LIBSETS_SETTYPE_" then
                constantName = "LIBSETS_SETTYPE_" .. string.upper(constantName)
            end
            setType = rawget(_G, constantName)
        end
        if type(setType) ~= "number" or not setTypeToLibraryInternalVariableNames[setType] then
            error("error: autosettype(): expected a valid LibSets set type ID or constant name.")
        end
        requestedSetType = setType
    end

    local hasSet, setName, _, _, _, setId =
        GetItemLinkSetInfo(AutoCategory.checking.ItemLink)
    if not hasSet or not setId or setId <= 0 or type(setName) ~= "string" then
        return false
    end

    -- GetSetType returns nil while the database is not ready, while scanning,
    -- or when this set is unknown to LibSets.
    local actualSetType = LibSets.GetSetType(setId)
    if not actualSetType or not setTypeToLibraryInternalVariableNames[actualSetType] then
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
