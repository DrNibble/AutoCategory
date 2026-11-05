
local LMP = LibMediaProvider
local SF = LibSFUtils

local logDebug = AutoCategory.logDebug

-- Two-level collapsible categories: a category name containing "----" is
-- displayed as a parent header with collapsible child headers.
local CategoryTree = AutoCategory.CategoryTree


-- uniqueIDs of items that have been updated (need rule re-execution),
-- based on PLAYER_INVENTORY:OnInventorySlotUpdated hook
local forceRuleReloadByUniqueIDs = {}
local pendingUpdates = {}     -- list of waiting to go to forceRuleReloadByUniqueIDs, UID -> timestamp


AutoCategory.dataCount = {}

local sortKeys = {
    slotIndex = { isNumeric = true },
    stackCount = { 
		tiebreaker = "slotIndex", 
		isNumeric = true 
	},
    name = { tiebreaker = "stackCount" },
    quality = { 
		tiebreaker = "name", 
		isNumeric = true 
	},
    stackSellPrice = { 
		tiebreaker = "name", 
		tieBreakerSortOrder = ZO_SORT_ORDER_UP, 
		isNumeric = true 
	},
    statusSortOrder = { tiebreaker = "age", isNumeric = true},
    age = { 
		tiebreaker = "name", 
		tieBreakerSortOrder = ZO_SORT_ORDER_UP, 
		isNumeric = true
	},
    statValue = { 
		tiebreaker = "name", 
		isNumeric = true, 
		tieBreakerSortOrder = ZO_SORT_ORDER_UP 
	},
    traitInformationSortOrder = { 
		tiebreaker = "name", 
		isNumeric = true, 
		tieBreakerSortOrder = ZO_SORT_ORDER_UP 
	},
    sellInformationSortOrder = { 
		tiebreaker = "name", 
		isNumeric = true, 
		tieBreakerSortOrder = ZO_SORT_ORDER_UP 
	},
	ptValue = { 
		tiebreaker = "name", 
		isNumeric = true 
	},
}

local CATEGORY_HEADER = 998

-- convenience function
-- returns true if value1 is nil or if value1 < value2
-- returns false otherwise
local function NilOrLessThan(value1, value2)
    if value1 == nil then
        return true

    elseif value2 == nil then
        return false

	elseif type(value1) == "boolean" then
		return not value1
    end
	return value1 < value2
end

-- ---------------------------------------------------
-- Category Header functions

-- currently fetched fontface
local header_face = nil

-- Invalidate the cached header font face.
--
-- The next request for the header font face will fetch it again
-- from LMP. This is needed when the user changes the desired
-- header font face in the settings.
function AutoCategory.resetface()
	header_face = nil
end

-- Return the currently fetched fontface.
-- If there is not one, fetch a new one based on
-- the current setting.
--
-- By doing this, we are no longer fetching the font
-- every single time that we create a category header.
local function getHeaderFace()
    if header_face ~= nil then
        return header_face
    end

    local appearance = AutoCategory.acctSaved.appearance
    header_face = LMP:Fetch("font", appearance.CATEGORY_FONT_NAME)
    return header_face
end

-- setup function for category header type to be added to the scroll list
local function setup_InventoryItemRowHeader(rowControl, slot, overrideOptions)
	--aliases
	local acctSaved = AutoCategory.acctSaved
	local saved = AutoCategory.saved

	-- Set header font and alignment.
	local appearance = acctSaved.appearance
	local headerLabel = rowControl:GetNamedChild("HeaderName")
	headerLabel:SetHorizontalAlignment(appearance["CATEGORY_FONT_ALIGNMENT"])
	headerLabel:SetFont(string.format('%s|%d|%s',
			getHeaderFace(), 
			appearance["CATEGORY_FONT_SIZE"],
			appearance["CATEGORY_FONT_STYLE"]))

	-- Protect against missing header data.
	slot.dataEntry.data = SF.safeTable(slot.dataEntry.data) -- protect against nil

	local nilDefault = SF.nilDefault
	local data = slot.dataEntry.data

	data.AC_categoryName = nilDefault(data.AC_categoryName, appearance["CATEGORY_OTHER_TEXT"])
	data.AC_bagTypeId = nilDefault(data.AC_bagTypeId, 1)
	data.AC_catCount = nilDefault(data.AC_catCount, 0)

	local cateName = data.AC_categoryName
	local bagTypeId = data.AC_bagTypeId
	local num = data.AC_catCount
	local headerLevel = data.AC_headerLevel or 1
	local displayName = data.AC_displayName or cateName
	local indent = (headerLevel - 1) * 30
	

	-- Determine header color.
	local cache = AutoCategory.cache
	local headerColor = "CATEGORY_FONT_COLOR"
	local entriesByName = cache.entriesByName[bagTypeId]
	local categoryEntry = entriesByName and entriesByName[cateName]
	
	if categoryEntry then
		if categoryEntry.isHidden then
			headerColor = "HIDDEN_CATEGORY_FONT_COLOR"
		end

	else
		local bagSettings = saved.bags[bagTypeId]
		if bagSettings and bagSettings.isUngroupedHidden and
				cateName == saved.appearance["CATEGORY_OTHER_TEXT"] then
			headerColor = "HIDDEN_CATEGORY_FONT_COLOR"
		end
	end

	local colorArr = appearance[headerColor]
	local r,g,b,a = colorArr[1], colorArr[2], colorArr[3], colorArr[4]
	headerLabel:SetColor(r,g,b,a)

	-- Child headers are indented under their parent.
	headerLabel:ClearAnchors()
	headerLabel:SetAnchor(BOTTOMLEFT, rowControl, BOTTOMLEFT, 60 + indent, 0)
	headerLabel:SetAnchor(TOPRIGHT, rowControl, TOPRIGHT, -10, 0)

	-- Add count to category name when enabled
    if acctSaved.general["SHOW_CATEGORY_ITEM_COUNT"] then
        headerLabel:SetText(string.format('%s |[%d]|r', displayName, num))

    else
        headerLabel:SetText(displayName)
    end

	-- set the collapse marker
	local marker = rowControl:GetNamedChild("CollapseMarker")
	marker:ClearAnchors()
	marker:SetAnchor(CENTER, rowControl, LEFT, 40 + indent, 0)
	local markerBG = rowControl:GetNamedChild("CollapseMarkerBG")
	markerBG:ClearAnchors()
	markerBG:SetAnchor(CENTER, rowControl, LEFT, 40 + indent, 0)
	local collapsed = AutoCategory.IsCategoryCollapsed(bagTypeId, cateName)
	if acctSaved.general["SHOW_CATEGORY_COLLAPSE_ICON"] then
		marker:SetHidden(false)
		if collapsed then
			-- is collapsed, so (+)
			marker:SetTexture("EsoUI/Art/Buttons/plus_up.dds")

		else
			-- is not collapsed so (-)
			marker:SetTexture("EsoUI/Art/Buttons/minus_up.dds")
		end

	else
		marker:SetHidden(true)
	end

	rowControl:SetHeight(appearance["CATEGORY_HEADER_HEIGHT"])
	rowControl.slot = slot
end

-- create the row header type and add to the inventory scroll list
local function AddTypeToList(rowHeight, datalist, inven_ndx, headerType) 
	if datalist == nil then return end
	if headerType == nil then headerType = CATEGORY_HEADER end

	local templateName = "AC_InventoryItemRowHeader"
	local setupFunc = setup_InventoryItemRowHeader
	local resetCB = ZO_InventorySlot_OnPoolReset

	local inventory = inven_ndx and PLAYER_INVENTORY.inventories[inven_ndx]
	local hiddenCB = inventory and inventory.listHiddenCallback

	return ZO_ScrollList_AddDataType(datalist, headerType, templateName, 
	    rowHeight, setupFunc, hiddenCB, nil, resetCB)
end

-- create a list entry for a category header.
-- will return nil, if catInfo is nil
local function createHeaderEntry(catInfo)
	if not catInfo then return end

	return ZO_ScrollList_CreateDataEntry(CATEGORY_HEADER, { 
			AC_categoryName = catInfo.AC_categoryName,
			AC_sortPriorityName = catInfo.AC_sortPriorityName,
			AC_bagTypeId = catInfo.AC_bagTypeId,
			AC_isHeader = true,
			AC_catCount = catInfo.AC_catCount,
			AC_parentName = catInfo.AC_parentName,
			AC_isParent = catInfo.AC_isParent,
			AC_headerLevel = catInfo.AC_headerLevel or 1,
			AC_displayName = catInfo.AC_displayName or catInfo.AC_categoryName,
			stackLaunderPrice = 0,

			statusSortOrder = 0,
			age = 0,
			name = catInfo.AC_categoryName or "",
			stackCount = 0,
			slotIndex = 0,
			quality = 0,
			displayQuality = 0,
			stackSellPrice = 0,
			statValue = 0,
			traitInformationSortOrder = 0,
			sellInformationSortOrder = 0,
			ptValue = 0
		})
end

-- ---------------------------------------------------

local function isUngroupedHidden(bagTypeId)
    if bagTypeId == nil then return true end

    local bagSettings = AutoCategory.saved.bags[bagTypeId]
    return bagSettings and bagSettings.isUngroupedHidden
end

local function isHiddenEntry(itemEntry)
    if not itemEntry or not itemEntry.data then
        return false
    end

    local data = itemEntry.data

    if data.AC_isHidden then
        return true
    end

    local bagTypeId = data.AC_bagTypeId
    if bagTypeId == nil then
        return true
    end

    if not data.AC_matched and isUngroupedHidden(bagTypeId) then
        return true
    end

    -- Items and headers under a collapsed level are hidden, whatever
    -- the state of the levels in between.
    if CategoryTree.IsAnyAncestorCollapsed(bagTypeId, data.AC_categoryName) then
        return true
    end

    return AutoCategory.IsCategoryCollapsed(bagTypeId, data.AC_categoryName)
end

local function isCollapsed(itemEntry)
    if not itemEntry or not itemEntry.data then
        return false
    end

    local data = itemEntry.data
    local bagTypeId = data.AC_bagTypeId

    if bagTypeId == nil then
        return true
    end

    return AutoCategory.IsCategoryCollapsed(bagTypeId, data.AC_categoryName)
end

-- Note that an item will always match either a defined rule or "OTHER" (when it does not match a defined rule)
-- so every itemEntry will "match" something as long as it is not a header item itself
local function runRulesOnEntry(itemEntry, specialType)
	--only match on items(not headers)
	if itemEntry.typeId == CATEGORY_HEADER then return end

	-- look for a match against rule definitions
	--localized aliases
	local data = itemEntry.data
	local bagId = data.bagId
	local slotIndex = data.slotIndex

	local matched, categoryName, categoryPriority, showPriority, bagTypeId, isHidden 
				= AutoCategory:MatchCategoryRules(bagId, slotIndex, specialType)
	data.AC_matched = matched
	data.AC_bagTypeId = bagTypeId
	data.AC_isHeader = false
	data.AC_categoryPriority = categoryPriority

	if matched then
		data.AC_categoryName = categoryName
		data.AC_parentName = CategoryTree.ParentOf(categoryName)
		-- use string.format for the zero-padding ability to maintain a fixed-width numeric prefix.
		data.AC_sortPriorityName = CategoryTree.BuildSortKey(showPriority, categoryName,
			AutoCategory.GetCategorySortName(categoryName))
		data.AC_isHidden = isHidden

	else
		data.AC_parentName = nil
		data.AC_categoryName = AutoCategory.acctSaved.appearance["CATEGORY_OTHER_TEXT"]
		data.AC_sortPriorityName = "9999" .. data.AC_categoryName
		-- if was not matched, then the isHidden value that was returned is not valid
		data.AC_isHidden = isUngroupedHidden(bagTypeId)
	end
end

local function sortInventoryFn(inven, left, right, key, order) 
	if left == nil or left.data == nil then
		return true
	end
	if right == nil or right.data == nil then
		return false
	end
	if AutoCategory.BulkMode then
		-- revert to default
		return ZO_TableOrderingFunction(left.data, right.data, 
			inven.currentSortKey, sortKeys, inven.currentSortOrder)
	end

	local ldata = left.data
	local rdata = right.data

	if AutoCategory.Enabled then
		if rdata.AC_sortPriorityName ~= ldata.AC_sortPriorityName then
			return NilOrLessThan(ldata.AC_sortPriorityName, rdata.AC_sortPriorityName)
		end
		if rdata.AC_isHeader ~= ldata.AC_isHeader then
			-- we'ved deliberately reversing the arguments so headers sort before non-headers
			return NilOrLessThan(rdata.AC_isHeader, ldata.AC_isHeader)
		end
	end

	--compatible with quality sort
	local sortKey = inven.sortKey
	if type(sortKey) == "function" then 
		if inven.sortOrder == ZO_SORT_ORDER_UP then
			return sortKey(left.data, right.data)

		else
			return sortKey(right.data, left.data)
		end
	end

	if key == nil or sortKeys[key] == nil then
		-- possible fix for Arkadius' Trading Tools sort bug
		key =  "statValue"
	end

	return ZO_TableOrderingFunction(left.data, right.data, 
			key, sortKeys, order)
end

local fcoisAvailable = FCOIS ~= nil and FCOIS.IsMarked ~= nil
local fcoisIsMarked = fcoisAvailable and FCOIS.IsMarked
local function constructEntryHash(itemEntry)
    local data = itemEntry.data

    -- Early exit if FCOIS not available - skip the table allocation
    if not fcoisAvailable then
		return SF.dstr(":", data.isPlayerLocked, data.isGemmable, data.stolen, 
            data.isBoPTradeable, data.isInArmory, data.brandNew, data.bagId, 
            data.stackCount, data.uniqueId, data.slotIndex, data.meetsUsageRequirement,
            data.locked, data.isJunk)
    end
    
    -- Include FCOIS marks in the hash when present.
    local bagId = data.bagId
    local slotIndex = data.slotIndex

    if bagId ~= nil and slotIndex ~= nil then
		-- returns itemIsMarked, markedIconsArray - both can be nil
        local _, markedIconsArray = fcoisIsMarked(bagId, slotIndex, -1)

    	if markedIconsArray and #markedIconsArray > 0 then
			-- add the FCOIS mark names to the hash
			return SF.dstr(":", data.isPlayerLocked, data.isGemmable, data.stolen, data.isBoPTradeable, data.isInArmory,
				data.brandNew, data.bagId, data.stackCount, data.uniqueId, data.slotIndex, data.meetsUsageRequirement,
				data.locked, data.isJunk, unpack(markedIconsArray))
		end
    end
	-- No FCOIS marks; use only the standard item fields.
    return SF.dstr(":", data.isPlayerLocked, data.isGemmable, data.stolen, data.isBoPTradeable, data.isInArmory,
        data.brandNew, data.bagId, data.stackCount, data.uniqueId, data.slotIndex, data.meetsUsageRequirement,
        data.locked, data.isJunk)
end

local function detectItemChanges(itemEntry, needReload)
	local data = itemEntry.data
	local currentTime = os.clock()

	if needReload then
		data.AC_lastUpdateTime = currentTime
		return true
	end

	if forceRuleReloadByUniqueIDs[data.uniqueID] then
		forceRuleReloadByUniqueIDs[data.uniqueID] = nil
		data.AC_lastUpdateTime = currentTime
		return true
	end

	local newHash = constructEntryHash(itemEntry)

	if data.AC_hash == nil or data.AC_hash ~= newHash then
		data.AC_hash = newHash
		data.AC_lastUpdateTime = currentTime
		return true
	end

	if data.AC_lastUpdateTime == nil
		or currentTime - data.AC_lastUpdateTime > 20 then
		data.AC_lastUpdateTime = currentTime
		return true
	end

	return false
end

-- Execute rules and store results in itemEntry.data, if needed. 
-- Return the number of items updated with rule re-execution.
--
-- The needsReload parameter allows the caller to force a re-evaluation
-- of rule on all of the (non-header) contents of the scrollData.
local function handleRules(scrollData, needsReload, specialType)
	local updateCount = 0

	for _, itemEntry in ipairs(scrollData) do
		if itemEntry.typeId ~= CATEGORY_HEADER
			and detectItemChanges(itemEntry, needsReload) then

			updateCount = updateCount + 1
			runRulesOnEntry(itemEntry, specialType)
		end
	end

	SF.safeClearTable(forceRuleReloadByUniqueIDs)
	return updateCount
end

-- The categoryList info is collected and then each entry is passed
-- to createHeaderEntry() to make a header row
local cnsd_categoryList = {} -- [name] {AC_catCount, AC_sortPriorityName,
                        	 --         AC_categoryName, AC_bagTypeId,
                        	 --         AC_parentName (children only) }
-- The headerList info of the intermediate levels of hierarchical names
-- ("a" and "a----b" for "a----b----c") is collected the same way and
-- produces the level headers above the categories themselves.
local cnsd_headerList = {}  -- [headerName] { AC_catCount, AC_sortPriorityName,
                        	 --              AC_categoryName, AC_bagTypeId,
                        	 --              AC_isParent, AC_headerLevel }
--- Create list with visible items and headers (performs category count).
local function createNewScrollData(scrollData)
    local newScrollData = {}

    cnsd_categoryList = SF.safeClearTable(cnsd_categoryList)
    cnsd_headerList = SF.safeClearTable(cnsd_headerList)

    local otherCategory = AutoCategory.acctSaved.appearance["CATEGORY_OTHER_TEXT"]

    -- Ensure a header info exists for an intermediate level of a
    -- hierarchical category name.
    local function ensureHeaderInfo(headerName, level, bagTypeId)
        local headerInfo = cnsd_headerList[headerName]

        if not headerInfo then
            headerInfo = {
                AC_categoryName     = headerName,
                AC_bagTypeId        = bagTypeId,
                AC_catCount         = 0,
                AC_sortPriorityName = nil,
                AC_isParent         = true,
                AC_headerLevel      = level,
                AC_displayName      = CategoryTree.DisplayName(headerName),
            }

            cnsd_headerList[headerName] = headerInfo
        end

        return headerInfo
    end

    -- Feed an entry's contribution to every header level above its
    -- category, keeping the smallest (best priority) sort key seen.
    local function feedAncestors(categoryName, bagTypeId, sortKey, contribution)
        local levels = CategoryTree.Levels(categoryName)
        if levels == nil or #levels < 2 then
            return
        end
        for level = 1, #levels - 1 do
            local headerName =
                table.concat(levels, CategoryTree.SEPARATOR, 1, level)
            local headerInfo = ensureHeaderInfo(headerName, level, bagTypeId)
            headerInfo.AC_catCount = headerInfo.AC_catCount + contribution

            local headerKey = CategoryTree.LevelSortKey(sortKey, level)
            if headerKey and (headerInfo.AC_sortPriorityName == nil
                or headerKey < headerInfo.AC_sortPriorityName) then
                headerInfo.AC_sortPriorityName = headerKey
            end
        end
    end

    -- Create newScrollData with visible items and without headers.
    -- At the same time, collect category counts.
    for _, itemEntry in ipairs(scrollData) do
        local data = itemEntry.data

        if not isHiddenEntry(itemEntry) then
            if itemEntry.typeId ~= CATEGORY_HEADER
                and not isCollapsed(itemEntry)

            then
                newScrollData[#newScrollData + 1] = itemEntry
            end
        end

        local isHeader = itemEntry.typeId == CATEGORY_HEADER
        -- A header of an intermediate level in scrollData only carries its
        -- descendants' total count; its descendants rebuild their own
        -- entries.
        if isHeader and data.AC_isParent then
            local headerInfo = ensureHeaderInfo(data.AC_categoryName,
                data.AC_headerLevel or 1, data.AC_bagTypeId)

            if AutoCategory.IsCategoryCollapsed(data.AC_bagTypeId,
                data.AC_categoryName) then
                -- Content isn't present in scrollData, so reuse
                -- the count stored on the header; it also feeds the
                -- levels above this one.
                local stored = data.AC_catCount or 0
                headerInfo.AC_catCount = stored
                feedAncestors(data.AC_categoryName, data.AC_bagTypeId,
                    data.AC_sortPriorityName, stored)
            end

        else
            local categoryName = data.AC_categoryName
            if not categoryName then
                categoryName = otherCategory
                data.AC_categoryName = categoryName
            end

            local catInfo = cnsd_categoryList[categoryName]

            if not catInfo then
                catInfo = {
                    AC_sortPriorityName = data.AC_sortPriorityName,
                    AC_categoryName     = categoryName,
                    AC_bagTypeId        = data.AC_bagTypeId,
                    AC_catCount         = 0,
                }

                local levelCount = CategoryTree.LevelCount(categoryName)
                if levelCount > 1 then
                    catInfo.AC_parentName = CategoryTree.ParentOf(categoryName)
                    catInfo.AC_headerLevel = levelCount
                    catInfo.AC_displayName =
                        CategoryTree.DisplayName(categoryName)
                end

                cnsd_categoryList[categoryName] = catInfo
            end

            local contribution = 0
            if not isHeader then
                contribution = 1

            elseif AutoCategory.IsCategoryCollapsed(
                data.AC_bagTypeId,
                categoryName
            ) then
                -- Content isn't present in scrollData, so reuse
                -- the count stored on the header.
                contribution = data.AC_catCount or 0
            end
            catInfo.AC_catCount = catInfo.AC_catCount + contribution

            -- A hierarchical entry also feeds every level's total
            -- above its category.
            feedAncestors(categoryName, data.AC_bagTypeId,
                data.AC_sortPriorityName, contribution)
        end
    end

    -- Merge the intermediate-level totals into a category that carries its
    -- own items: its header must show direct items plus all descendants.
    for _, headerInfo in pairs(cnsd_headerList) do
        local catInfo = cnsd_categoryList[headerInfo.AC_categoryName]
        if catInfo then
            catInfo.AC_catCount = catInfo.AC_catCount
                + headerInfo.AC_catCount
            if headerInfo.AC_sortPriorityName
                and (catInfo.AC_sortPriorityName == nil
                    or headerInfo.AC_sortPriorityName
                        < catInfo.AC_sortPriorityName) then
                catInfo.AC_sortPriorityName = headerInfo.AC_sortPriorityName
            end
        end
    end

    -- Append the headers of the intermediate levels. A level name that
    -- also exists as a category reuses that category's own header, and a
    -- header is only shown while every level above it is expanded.
    for _, headerInfo in pairs(cnsd_headerList) do
        if cnsd_categoryList[headerInfo.AC_categoryName] == nil
            and not CategoryTree.IsAnyAncestorCollapsed(
                headerInfo.AC_bagTypeId,
                headerInfo.AC_categoryName
            ) then
            local headerEntry = createHeaderEntry(headerInfo)

            if headerEntry then
                newScrollData[#newScrollData + 1] = headerEntry
            end
        end
    end

    -- Append category headers. A nested category header is only shown
    -- while every level above it is expanded.
    for _, catInfo in pairs(cnsd_categoryList) do
        if not CategoryTree.IsAnyAncestorCollapsed(
                catInfo.AC_bagTypeId,
                catInfo.AC_categoryName
            ) then
            local headerEntry = createHeaderEntry(catInfo)

            if headerEntry then
                newScrollData[#newScrollData + 1] = headerEntry
            end
        end
    end

    return newScrollData
end

local function rebuildScrollData(zo_inventory)
	-- add header rows
	--> rebuild scrollData with headers and visible items
	local list = zo_inventory.listView 
	local scrollData = ZO_ScrollList_GetDataList(list)

    if not scrollData or #scrollData == 0 then 
        if zo_inventory.altFreeSlotType == INVENTORY_GUILD_BANK then
            zo_callLater(function()
                local freshData = ZO_ScrollList_GetDataList(list)
                if freshData and #freshData > 0 then
                    rebuildScrollData(zo_inventory)
                end
            end, 100)
        end
        return false 
    end
	handleRules(scrollData, true)
	list.data = createNewScrollData(scrollData)
	return true
end

local sceneMap = {
    ["inventory"] = true,
    ["bank"] = true,
    ["guildBank"] = true,
    ["guildStore"] = true,
    ["smithing"] = true,
    ["tradinghouse"] = true,
    ["store"] = true,
    ["universalDeconstructionSceneKeyboard"] = true,
	["mailSend"] = true,
	["fence_keyboard"] = true,
	["fence_gamepad"] = true,
	["houseBank"] = true,
	["furnitureVault"] = true,
	["trade"] = true,
}
local function readyToUpdate()
    if not SCENE_MANAGER then
        return false
    end

    local currentScene = SCENE_MANAGER:GetCurrentScene()
    if not currentScene then
        return false
    end

    local sceneName = currentScene:GetName()

    return sceneMap[sceneName] == true, sceneName
end

-- prehook
local function prehookSort(self, inventoryType) 
	if not AutoCategory.Enabled then return false end

    local isReady, sceneName = readyToUpdate()
    if not isReady then return false end

	-- revert to default behaviour if safety conditions not met
	if inventoryType == INVENTORY_QUEST_ITEM then return false end

	if AutoCategory.BulkMode then
		if sceneName == "guildBank"
			or (XLGearBanker and sceneName == "bank") then
			return false
		end
	end

	-- inventory info from esoui/ingame/inventory/inventory.lua
	local zo_inventory = self.inventories[inventoryType]
					or self.inventories[self.selectedTabType]
	if not zo_inventory then return false end

	--change sort function
	zo_inventory.sortFn =  function(left, right) 
			return sortInventoryFn(zo_inventory, left, right,
									zo_inventory.currentSortKey, 
									zo_inventory.currentSortOrder)
		end

	if sceneName == "bank" or sceneName == "guildBank" then
		needsReload = false
	end

    rebuildScrollData(zo_inventory)

	return false
end

-- prehook
local function prehookCraftSort(self)
	-- revert to default behaviour if safety conditions not met
	if not AutoCategory.Enabled then return false end

    if not readyToUpdate() then return false end

    --change sort function
	self.sortFunction = function(left, right) 
			return sortInventoryFn(self, left, right, self.sortKey, self.sortOrder)
		end

	local scrollData = ZO_ScrollList_GetDataList(self.list)
	if scrollData and #scrollData > 0 then
		-- Craft stations always require rules to be reevaluated.
		handleRules(scrollData, true, AC_BAG_TYPE_CRAFTSTATION)

		-- add header rows
		self.list.data = createNewScrollData(scrollData) --, self.sortFunction)
	end
	-- continue on to run follow-on hooks
	return false
end

--[[ this only works if pendingUpdates uses os.clock() instead of true in updateHook()
local updateCounter = 0
local CLEANUP_THRESHOLD = 50
local callLater         -- the calllater object for controlling single-shot start/stop/destroy

-- clear out pending entries that are older than 15 seconds - they are hung
--
local function cleanupPendingUpdates()
    updateCounter = updateCounter + 1
    if updateCounter < CLEANUP_THRESHOLD then return end
    
    updateCounter = 0

    -- Clean old entries from pendingUpdates
    local currentTime = os.clock()
    local cleaned = 0
    for uid, timestamp in pairs(pendingUpdates) do
        -- If entry is older than 15 seconds, remove it
        if currentTime - timestamp > 15 then
            pendingUpdates[uid] = nil
            cleaned = cleaned + 1
        end
    end
end
--]]


local function updateHook(zo_inventory)
    for uid in pairs(pendingUpdates) do
        forceRuleReloadByUniqueIDs[uid] = true
    end
    pendingUpdates = SF.safeClearTable(pendingUpdates)

    rebuildScrollData(zo_inventory)
end


-- prehook parameters, not the event parameters
local function onInventorySlotUpdated(self, bagId, slotIndex)
	if not AutoCategory.Enabled then return end
	if bagId ~= AC_BAG_TYPE_BACKPACK and bagId ~= BAG_BACKPACK then return end
	
    local uid = GetItemUniqueId(bagId, slotIndex)
    if uid then
        pendingUpdates[uid] = true 		-- os.clock()
    end
end

-- event handler
local function onStackItems(evtid, bagId)
	local invType = PLAYER_INVENTORY.bagToInventoryType[bagId]
	AutoCategory.RefreshList(invType)
end


function AutoCategory.HookKeyboardMode()
	--Add a new header row data type
	local rowHeight = AutoCategory.acctSaved.appearance["CATEGORY_HEADER_HEIGHT"]
    local hookmgr = AutoCategory.hookmgr

    AddTypeToList(rowHeight, ZO_PlayerInventoryList,  	  INVENTORY_BACKPACK)
    AddTypeToList(rowHeight, ZO_CraftBagList,             INVENTORY_BACKPACK)
    AddTypeToList(rowHeight, ZO_PlayerBankBackpack,       INVENTORY_BACKPACK)
    AddTypeToList(rowHeight, ZO_GuildBankBackpack,        INVENTORY_BACKPACK)
    AddTypeToList(rowHeight, ZO_HouseBankBackpack,        INVENTORY_BACKPACK)
    AddTypeToList(rowHeight, ZO_PlayerInventoryQuest,     INVENTORY_QUEST_ITEM)
    AddTypeToList(rowHeight, ZO_FurnitureVaultList,       INVENTORY_BACKPACK)
    AddTypeToList(rowHeight, ZO_VengeanceInventoryList,   INVENTORY_VENGEANCE)

    AddTypeToList(rowHeight, SMITHING.deconstructionPanel.inventory.list, nil)
    AddTypeToList(rowHeight, SMITHING.improvementPanel.inventory.list,    nil)
    AddTypeToList(rowHeight, ZO_UniversalDeconstructionTopLevel_KeyboardPanelInventoryBackpack, nil )

	--- sort hooks
	hookmgr:PreHook(PLAYER_INVENTORY, "ApplySort", prehookSort)
    hookmgr:PreHook(SMITHING.deconstructionPanel.inventory, "SortData",  prehookCraftSort)
    hookmgr:PreHook(SMITHING.improvementPanel.inventory,    "SortData",  prehookCraftSort)
    hookmgr:PreHook(UNIVERSAL_DECONSTRUCTION.deconstructionPanel.inventory, "SortData",  prehookCraftSort)

	--- changes detection events/hooks (anticipate if rules results may have changed)
	hookmgr:PreHook(PLAYER_INVENTORY, "OnInventorySlotUpdated", onInventorySlotUpdated)

	-- Other events that cause a full refresh
	-- user can force a refresh with stack key
	AutoCategory.evtmgr:registerEvt(EVENT_STACKED_ALL_ITEMS_IN_BAG, onStackItems)

    pendingUpdates = SF.safeClearTable(pendingUpdates)
    callLater = SF.CallLater:NewSingle(updateHook, 50):Start()

end

function AutoCategory.UnHookKeyboardMode()
 	-- Other events that cause a full refresh
	-- user can force a refresh with stack key
	AutoCategory.evtmgr:unregEvt(EVENT_STACKED_ALL_ITEMS_IN_BAG, onStackItems)
	AutoCategory.hookmgr:disableAll()

    -- Clear pending updates
    pendingUpdates = SF.safeClearTable(pendingUpdates)
    if callLater then
        callLater = callLater:Destroy()
    end
end


