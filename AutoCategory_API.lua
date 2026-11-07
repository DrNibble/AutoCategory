local SF = LibSFUtils

--====API====--

--[[ For use to tell if AutoCategory has finished its initialization process and
	is ready for business. The following variable is nil if AutoCategory is
	still initializing, and changes to true when the initialization is finished.
--]]
AutoCategory.Inited = AutoCategory.Inited

--[[ For use by bulk updaters of inventory (ESPECIALLY the Guild Bank)
	to not perform sorting for a specific period of time (until the
	bulk operation is known to be completed).
	Because the Guild Bank info is requested from the server every single
	time, it is prone to delays in operation to prevent server spamming.
	It is hoped that by entering into bulk mode that we do not perform
	server requests for the guild bank 
--]]
function AutoCategory.EnterBulkMode()
	AutoCategory.BulkMode = true
end
function AutoCategory.ExitBulkMode()
	AutoCategory.BulkMode = false
end



--[[ Convert a ZOS bagId into AutoCategory bag_type_id
	returns the bag_type_id enum value 
	     or nil if bagId is not recognized
	Note: We have separate definitions because all of the ZOS HOUSE_BANK types
		are supposed to be treated the same by us.
--]]
local BagTypeConversion = {
    [BAG_BACKPACK or 1]         = AC_BAG_TYPE_BACKPACK,
    [BAG_WORN or 2]             = AC_BAG_TYPE_BACKPACK,
    [BAG_BANK or 3]             = AC_BAG_TYPE_BANK,
    [BAG_SUBSCRIBER_BANK or 4]  = AC_BAG_TYPE_BANK,
    [BAG_VIRTUAL or 5]          = AC_BAG_TYPE_CRAFTBAG,
    [BAG_GUILDBANK or 6]        = AC_BAG_TYPE_GUILDBANK,
    [BAG_HOUSE_BANK_ONE or 7]   = AC_BAG_TYPE_HOUSEBANK,
    [BAG_HOUSE_BANK_TWO or 8]   = AC_BAG_TYPE_HOUSEBANK,
    [BAG_HOUSE_BANK_THREE or 9] = AC_BAG_TYPE_HOUSEBANK,
    [BAG_HOUSE_BANK_FOUR or 10]  = AC_BAG_TYPE_HOUSEBANK,
    [BAG_HOUSE_BANK_FIVE or 11]  = AC_BAG_TYPE_HOUSEBANK,
    [BAG_HOUSE_BANK_SIX or 12]   = AC_BAG_TYPE_HOUSEBANK,
    [BAG_HOUSE_BANK_SEVEN or 13] = AC_BAG_TYPE_HOUSEBANK,
    [BAG_HOUSE_BANK_EIGHT or 14] = AC_BAG_TYPE_HOUSEBANK,
    [BAG_HOUSE_BANK_NINE or 15]  = AC_BAG_TYPE_HOUSEBANK,
    [BAG_HOUSE_BANK_TEN or 16]   = AC_BAG_TYPE_HOUSEBANK,
    [BAG_FURNITURE_VAULT or 17]  = AC_BAG_TYPE_FURNVAULT,
    [BAG_VENGEANCE or 18]        = AC_BAG_TYPE_VENGEANCE,

}

-- convert ZOS bag type to AC bag type
local function convert2BagTypeId(bagId, acprimary)
	if acprimary ~= nil then return acprimary end
	if bagId == nil then return nil end
	return BagTypeConversion[bagId]
end

function AutoCategory.validateBagRules(bagId, acprimary)
	return AutoCategory.validateACBagRules(convert2BagTypeId(bagId, acprimary))
end

--[[ Make sure that all of the rules for this bag type are valid/undamaged
	Do this by bag rather than by rule to avoid repeating this unnecessarily
	as the bag of rules is evaluated per each item in the bag.
	Do this up front to save time.
--]]
function AutoCategory.validateACBagRules(acBagType)

	if acBagType == nil then return false end

	-- Mark rules as damaged when we find something wrong with them
	-- returns nothing
	local function checkValidRule(name, rule)
		if rule == nil or name == nil then return end
		if rule.name ~= name then 
			rule:setError(true,"name mismatch between bagrule and backing rule")
			return
		end

		--local isValid = true
		if rule.rule == nil then
			rule:setError(true,"missing rule definition")
			return
		end
		local rkey = rule:key()
		local ruleCode = AutoCategory.compiledRules[rkey]

		if not ruleCode or type(ruleCode) ~= "function" then
			rule:setError(true, "invalid compiled rule function")
			AutoCategory.compiledRules[rkey] = nil
			return
		end
		rule.damaged = nil
		return
	end

	-- Make sure all of the rules in the bag are evaluated if damaged and marked appropriately
	local bag = AutoCategory.saved.bags[acBagType]
	if not bag or not bag.rules then
		return false
	end
	for i = 1, #bag.rules do
		local entry = bag.rules[i] 
		local rule = entry:getBackingRule()
		checkValidRule(entry.name, rule)
	end
end

--[[ Adjust the name of the category based on the presence of 
	an enhancement (set name) and if SHOW_CATEGORY_SET_TITLE is enabled
--]]
local function adjustName(selfie, name, enhancement)
	if name == nil or name == "" then 
		name  = AutoCategory.acctSaved.appearance["CATEGORY_OTHER_TEXT"]
		return name
	end
	if not enhancement or enhancement == "" then
		-- just use declared category name
		return name

	elseif AutoCategory.saved.general["SHOW_CATEGORY_SET_TITLE"] == false or selfie.checking.BagId == BAG_FURNITURE_VAULT then
		-- just use the set name without the category name
		return enhancement

	end
	-- A hierarchical dynamic name (nested levels, see CategoryTree.lua)
	-- already carries its own structure: wrapping it in the rule name would
	-- break the nested display, so it is used as-is.
	if AutoCategory.CategoryTree
		and AutoCategory.CategoryTree.IsHierarchical(enhancement) then
		return enhancement
	end
	-- combine the category and set names
	return name .. " (" .. enhancement .. ")"
end

--[[ see if we find a category rule match for the item passed in.
	    i.e. execute the rule on the specific inventory item
	runs all the rules assigned to the specific bag type against
	   each item in the bag

	returns
		boolean - was a match found?
		string  - name of rule matched combined with additionCategoryName, ex. "Set(godly set)"
		number  - run priority of rule
		number -  show priority of rule
		enum    - bag type id
		boolean - is entry hidden?
--]]
function AutoCategory:MatchCategoryRules( bagId, slotIndex, specialType )
	local bag_type_id = convert2BagTypeId(bagId, specialType)
	if not bag_type_id then
		return false, "", 0, 0, nil, nil
	end

	-- set up bagId and slotIndex to "pass in" to the rule functions
	self:setChecking(bagId, slotIndex)

	local bag = AutoCategory.saved.bags[bag_type_id]
	if not bag or not bag.rules then
		return false, "", 0, 0, bag_type_id, false
	end

	-- call the rules for this bag against the entry, stop when one matches
	-- return values from SF.safeCall func

	-- localized aliases
	local setCategoryCollapsed = AutoCategory.SetCategoryCollapsed
	local getRuleByName = AutoCategory.GetRuleByName
	local isCategoryCollapsed = AutoCategory.IsCategoryCollapsed
	local compiledRules = AutoCategory.compiledRules
	local categoryTree = AutoCategory.CategoryTree

	-- rule Level path state: the category names of the parent chain
	-- (the Level and Parent dropdowns of Edit Category) recorded while
	-- the bag's rules are evaluated for this item, and the entry of the
	-- rule that opened the deepest path so far. The path of a level
	-- category is its parent chain: the parent, its own parent, and so
	-- on, up to the top, then the category itself.
	local recordedPath = nil
	local recordedEntry = nil

	-- Append a name as the deepest level of the recorded path.
	local function joinPath(path, name)
		local parts = {}
		for i = 1, #path do
			parts[i] = path[i]
		end
		parts[#parts + 1] = name
		return categoryTree.JoinName(parts)
	end


	for i = 1, #bag.rules do
		local entry = bag.rules[i]
		if entry.name then
			local rule = getRuleByName(entry.name)
			if rule and rule.damaged ~= true then
				local rkey = rule:key()
				local ruleCode = compiledRules[rkey]

				if ruleCode then
					AutoCategory.AdditionCategoryName = ""	-- this may be changed by autoset() or alphagear
					AutoCategory.AdditionCategorySortName = nil
					local exec_ok, res = SF.safeCall( ruleCode )
					if exec_ok then
						local ruleLevel = rule.level
						local isLevelRule = res == true
							and type(ruleLevel) == "number"
							and ruleLevel >= 1
							and ruleLevel == math.floor(ruleLevel)

						if isLevelRule then
							-- A rule with a Level (Edit Category dropdown) matched:
							-- build its parent chain (the Parent dropdown) and record it
							-- as the current path. A deeper chain replaces a shallower one
							-- (the first rule wins among chains of equal depth), and a later
							-- rule may refine the item one or more levels deeper.
							local chain = { entry.name }
							local visited = { [entry.name] = true }
							local crule = rule
							while type(crule.parent) == "string" and crule.parent ~= "" do
								local prule = getRuleByName(crule.parent)
								if not prule or visited[prule.name] then break end
								table.insert(chain, 1, prule.name)
								visited[prule.name] = true
								crule = prule
							end
							if recordedPath == nil or #chain > #recordedPath then
								recordedPath = chain
								recordedEntry = entry
							end

						else
							local catname = adjustName(self, rule.name,
										AutoCategory.AdditionCategoryName)
							setCategoryCollapsed(bag_type_id, catname,
								isCategoryCollapsed(bag_type_id, catname))
							if res == true then
								local finalName = catname
								if recordedPath ~= nil then
									-- a Level path is open: the rule's
									-- category becomes its deepest level
									finalName = joinPath(recordedPath, catname)
									setCategoryCollapsed(bag_type_id, finalName,
										isCategoryCollapsed(bag_type_id, finalName))
								end
								AutoCategory.CategorySortNames[finalName] =
									AutoCategory.AdditionCategorySortName
								return true,
									finalName,
									entry.runpriority,
									entry.showpriority,
									bag_type_id,
									entry.isHidden
							end
						end

					else
						rule:setError(true, res)
						compiledRules[rkey] = nil
					end
				end
			end
		end
	end

	-- Only rules with a Level matched: join the recorded parent chain into
	-- one nested category name and stop at the rule that opened the
	-- deepest path.
	if recordedPath ~= nil then
		local entry = recordedEntry
		local catname = categoryTree.JoinName(recordedPath)
		setCategoryCollapsed(bag_type_id, catname,
			isCategoryCollapsed(bag_type_id, catname))
		AutoCategory.CategorySortNames[catname] = nil
		return true,
			catname,
			entry.runpriority,
			entry.showpriority,
			bag_type_id,
			entry.isHidden
	end

	return false, "", 0, 0, bag_type_id, false
end 