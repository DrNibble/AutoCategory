-- -------------------------------------------------------
-- Rule functions and helpers

local L = GetString

-- based on the requested rule name, create a name that
-- is not already in use (since rule names must be unique)
function AutoCategory.GetUsableRuleName(name)
    name = tostring(name)
	local testName = name
	local index = 1
	while AutoCategory.RulesW.ruleNames[testName] ~= nil do
		testName = name .. index
		index = index + 1
	end
	return testName
end

-- check that all required fields are set
-- returns err (t/f), errmsg (string)
function AutoCategory.isValidRule(ruledef)
    --make sure rule is well-formed
	-- validate rule name
    if (not ruledef or not ruledef.name
			or type(ruledef.name) ~= "string" or ruledef.name == "") then
        return false, "name is required"
    end
	-- validate rule text
    if (not ruledef.rule or type(ruledef.rule) ~= "string" or ruledef.rule == "") then
		ruledef.error = true
        return false, "rule text is required"
    end
	-- validate optional rule description
    if ruledef.description then -- description is optional
        if (type(ruledef.description) ~= "string") then
            return false, "non-nil description must be a string"
        end
    end
	-- validate optional rule tag
    if ruledef.tag then -- tag is optional
        if (type(ruledef.tag) ~= "string") then
            return false, "non-nil tag must be a string"
        end
    end
    -- validate optional rule level (sub-menu level of the category,
    -- set by the Level dropdown in Edit Category)
    if ruledef.level ~= nil then -- level is optional
        if (type(ruledef.level) ~= "number" or ruledef.level < 1
                or ruledef.level ~= math.floor(ruledef.level)) then
            return false, "level must be a whole number >= 1"
        end
    end
    -- validate optional rule parent (the category under which a level 2-5
    -- category is nested, set by the Parent dropdown in Edit Category)
    if ruledef.parent ~= nil then -- parent is optional
        if (type(ruledef.parent) ~= "string" or ruledef.parent == ""
                or ruledef.parent == ruledef.name) then
            return false, "parent must be a category name other than the rule's own name"
        end
    end
    return true
end


function AutoCategory.attachRuleMixin(rule)
	if rule.compile then return end
	    
	setmetatable(rule, AutoCategory.RuleMetatable)
end

-- ----------------------------------------------------------
-- factory for creating new rules
-- minimum required contents = name. description, rule, tag
function AutoCategory.CreateRule(name, tag)
	local rule = {
		name = name,
		description = "",
		rule = "true",
		tag = tag,
	}
    setmetatable(rule, AutoCategory.RuleMetatable)
	return rule
end

-- factory for making copies of rules
function AutoCategory.CopyFrom(copyFrom)
	if not copyFrom or not copyFrom.name then return end

	local ruleName = copyFrom.name
	-- get a unique name based on the old rule name
	local newName = AutoCategory.GetUsableRuleName(ruleName)
	local tag = copyFrom.tag
	if tag == "" then
		tag = AC_EMPTY_TAG_NAME
	end

	local newRule = AutoCategory.CreateRule(newName, tag)
    -- metatable already set from the CreateRule
	newRule.description = copyFrom.description
	newRule.rule = copyFrom.rule
	newRule.level = copyFrom.level
	newRule.parent = copyFrom.parent
	newRule.damaged = copyFrom.damaged
	newRule.err = copyFrom.err
	newRule.pred = nil		-- defaults to not pre-defined, because copies are user-defined rules
    return newRule
end

-- -------------------------------------------------
-- collected functions to be applied to a rule metatable
--
-- This function set to be used with rule structures loaded in or created.
-- Note: Even though the table is called a "mixin" you must NOT use
-- it with zo_mixin() because the objects that this set of functions
-- is used with is saved with SaveVariables and cannot have functions 
-- just copied into it.
AutoCategory.RuleApiMixin = {
	-- check if rule def is valid (required keys all present)
	isValid = function(self)
			return AutoCategory.isValidRule(self)
	end,

	--determine if a rule is marked as pre-defined
	isPredefined = function(self)
	    return self.pred == 1
	end,

	-- return the description if the rule has one, otherwise return the name;
	-- for a category with a Level, append the level (and its parent) so
	-- that the sub-menu position of the category shows in the tooltips
	getDesc = function(self)
			local tt = self.description
			if not tt or tt == "" then
				tt = self.name
			end
			if type(self.level) == "number" and self.level >= 1 then
				local line = string.format(L(SI_AC_TIP_LEVEL), self.level)
				if type(self.parent) == "string" and self.parent ~= "" then
					line = line .. " - " .. string.format(L(SI_AC_TIP_PARENT), self.parent)
				end
				tt = tt .. "\n" .. line
			end
			return tt
		end,

	-- handle error marking for a rule
	setError = function(self, dmg, errm)
			self.damaged = dmg
			self.err = errm
		end,

	clearError = function(self)
			self.damaged = nil
			self.err = nil
		end,

	-- get assigned key for the rule (if nil, returns name)
	key = function(self)
			if self.rkey then
				return self.rkey
			end
			return self.name
		end,

	-- compare a rule to another rule for certain basic equalities
	-- used for converting from acct/char rules to acctwide-only
	-- returns two bools - (name is ~=), (rule def ~=)
	isequiv = function(self, a)
			if not a then return false, false end
			local notname = self.name ~= a.name
			local notrule = self.rule ~= a.rule
			return notname, notrule
		end,

	-- Compile the Rule
	-- Return a string that is either empty (good compile)
	-- or an error string returned from the compile
	--
	-- Stores the compiled rule into AutoCategory.compiledRules table
	compile = function(self)
			if self.name == nil or self.name == "" then
                --logDebug("[AutoCategory] compile: rule has no name")
				return "Rule missing name"
			end

			local compiledRules = AutoCategory.compiledRules

			self:clearError()
			local rkey = self:key()
            if rkey == nil or rkey == "" then 
                self:setError(true, "Unable to generate rule key")
                return self.err
            end
            
			compiledRules[rkey] = nil

			if self.rule == nil or self.rule == "" then
				self:setError(true,"Missing rule definition")
				return self.err
			end

			local rulestr = string.format("return(%s)", self.rule)
			local compiledfunc, err = zo_loadstring(rulestr)
			if not compiledfunc then
				self:setError(true, err)
				return err
			end
			setfenv( compiledfunc, AutoCategory.Environment )
			compiledRules[rkey] = compiledfunc
			return ""
		end,
	
	-- Add the itemId to the rule's isitemid() command (the inventory
	-- context menu): when the rule has no isitemid() call, append
	-- " or isitemid(<id>)" to the rule text (or just the command when
	-- the rule text is empty); when the command already exists, add
	-- <id> to the parameters of its last call, unless the id is
	-- already a parameter of one of its calls. Returns true when the
	-- rule text changed, false when there was nothing to do.
	addItemIdToIsItemId = function(self, itemId)
		local text = self.rule or ""
		local idStr = tostring(itemId)

		-- find the isitemid() calls of the rule (the pattern does not
		-- match a longer name that only ends with isitemid)
		local lastStart, lastEnd
		local pos = 1
		while true do
			local s, e = text:find("%f[%a]isitemid%s*%b()", pos)
			if not s then break end
			lastStart, lastEnd = s, e
			pos = e + 1
		end

		if not lastStart then
			-- no isitemid() command yet: append it to the rule
			if text:find("%S") then
				self.rule = text .. " or isitemid(" .. idStr .. ")"
			else
				self.rule = "isitemid(" .. idStr .. ")"
			end
			return true
		end

		-- the command already exists: nothing to do when the id is
		-- already a parameter of one of its calls
		for call in text:gmatch("%f[%a]isitemid%s*%b()") do
			local args = call:match("%((.*)%)")
			for arg in args:gmatch("[^,]+") do
				arg = arg:gsub("^%s+", ""):gsub("%s+$", "")
				if arg == idStr then return false end
			end
		end

		-- add the id to the parameters of the last isitemid() call
		local call = text:sub(lastStart, lastEnd)
		local args = call:match("%((.*)%)")
		if args and args:find("%S") then
			args = args .. ", " .. idStr
		else
			args = idStr
		end
		self.rule = text:sub(1, lastStart - 1) .. "isitemid(" .. args .. ")"
			.. text:sub(lastEnd + 1)
		return true
	end,

	-- returns nil if the rule is not compiled, non-nil if it is compiled
	isCompiled = function(self)
		if self.name == nil or self.name == "" then
			return
		end
		return AutoCategory.compiledRules[self:key()]
	end,
}
AutoCategory.RuleMetatable = {
    __index = AutoCategory.RuleApiMixin,
}

