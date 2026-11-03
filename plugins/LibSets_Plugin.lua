-- Categorize set items by their LibSets type and their localized set name.
AutoCategory_LibSets = {
    RuleFunc = {},
}

function AutoCategory_LibSets.Initialize()
    -- LibSets is optional in the addon manifest.
    if LibSets == nil then
        AutoCategory.AddRuleFunc("autosettype", AutoCategory.dummyRuleFunc)
        return
    end
    if LibSets.fullyLoaded then
        AutoCategory.AddRuleFunc("autosettype", AutoCategory_LibSets.RuleFunc.AutoSetType)
        AutoCat_Logger():Info("Initializing LibSets plugin integration")
    else
        AutoCategory.AddRuleFunc("autosettype", AutoCategory.dummyRuleFunc)
    end
end

-- autosettype() matches all known set types.
-- Optional filter: a translated type name in any language LibSets provides
-- ("Donjon" in French, "Dungeon" in English, "Verlies" in German, ...),
-- or a numeric type ID.
function AutoCategory_LibSets.RuleFunc.AutoSetType(setType)
    if LibSets == nil then
        return false
    end
    if LibSets.fullyLoaded then
        local hasSet, setName, _, _, _, setId =
            GetItemLinkSetInfo(AutoCategory.checking.ItemLink)
        if not hasSet or not setId or setId <= 0 or type(setName) ~= "string" then
            return false
        end

        local actualSetType = LibSets.GetSetType(setId)
        local typeNames = LibSets.setTypesToName[actualSetType]
        if type(typeNames) ~= "table" then
            return false
        end

        -- LibSets.clientLang is the normalized, supported UI language cached
        -- by LibSets. Do not read GetCVar or maintain another language cache.
        local setTypeName = typeNames[LibSets.clientLang]
        if type(setTypeName) ~= "string" or setTypeName == "" then
            setTypeName = typeNames[LibSets.fallbackLang or "en"]
        end
        if type(setTypeName) ~= "string" or setTypeName == "" then
            return false
        end

        if setType ~= nil then
            local requestedSetType = setType
            if type(setType) == "string" then
                requestedSetType = nil
                local requestedName = LocaleAwareToLower(setType)
                -- Every language LibSets ships in setTypesToName is accepted,
                -- not only the cached UI language or its English fallback.
                local fallbackType
                for typeId, names in pairs(LibSets.setTypesToName) do
                    for _, name in pairs(names) do
                        if type(name) == "string" and name ~= ""
                            and LocaleAwareToLower(name) == requestedName then
                            if typeId == actualSetType then
                                requestedSetType = typeId
                            elseif fallbackType == nil then
                                fallbackType = typeId
                            end
                            break -- one matching name per type is enough
                        end
                    end
                    if requestedSetType ~= nil then break end
                end
                if requestedSetType == nil then
                    requestedSetType = fallbackType
                end
            end
            if type(requestedSetType) ~= "number"
                or type(LibSets.setTypesToName[requestedSetType]) ~= "table" then
                error("error: autosettype(): expected a numeric LibSets type ID or UI type name.")
            end
            if requestedSetType ~= actualSetType then
                return false
            end
        end

        setName = string.gsub(setName, "%^.*", "")
        if setName == "" then
            return false
        end
        AutoCategory.AdditionCategoryName = "(" .. setTypeName .. ") " .. setName
        AutoCategory.AdditionCategorySortName =
            LocaleAwareToLower(setTypeName) .. "\001" .. LocaleAwareToLower(setName)
        return true
    end
    return false
end

AutoCategory.RegisterPlugin("LibSets", AutoCategory_LibSets.Initialize)
