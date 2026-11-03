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
-- Optional filter: a name in LibSets' cached UI language ("Donjon" in French),
-- a numeric type ID, or a quoted exported constant name/suffix.
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
                for typeId, names in pairs(LibSets.setTypesToName) do
                    local name = names[LibSets.clientLang]
                    if type(name) ~= "string" or name == "" then
                        name = names[LibSets.fallbackLang or "en"]
                    end
                    if type(name) == "string" and LocaleAwareToLower(name) == requestedName then
                        requestedSetType = typeId
                        -- Shared translated names should match every such type,
                        -- not whichever entry pairs() happens to visit first.
                        if typeId == actualSetType then break end
                    end
                end
                if requestedSetType == nil then
                    local constantName = setType
                    if string.sub(constantName, 1, 16) ~= "LIBSETS_SETTYPE_" then
                        constantName = "LIBSETS_SETTYPE_" .. string.upper(constantName)
                    end
                    requestedSetType = rawget(_G, constantName)
                end
            end
            if type(requestedSetType) ~= "number"
                or type(LibSets.setTypesToName[requestedSetType]) ~= "table" then
                error("error: autosettype(): expected a LibSets type ID, UI type name or constant name.")
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
