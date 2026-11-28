--local SF = LibSFUtils

--local L = GetString

-- Build a real CVT source holding the current tag list (RulesW.tags).
-- CVT:assign only accepts real CVT sources: it silently ignores plain
-- tables such as { choices = ... } (no GetUses), which is why every
-- tag-dropdown assign that passed a plain table was a silent no-op and
-- the tag dropdowns stayed empty and disabled. The source is created
-- with no uses flags (USE_NONE) to match the tag dropdowns, which are
-- created without usesFlags as well.
function AC_UI.tagListCVT()
	local src = AutoCategory.CVT:New(nil, nil)
	local tags = AutoCategory.RulesW and AutoCategory.RulesW.tags
	if tags then
		for i = 1, #tags do
			src:append(tags[i])
		end
	end
	return src
end

function AC_UI.divider()
	return {
		type = "divider",
		width = "full", --or "half" (optional)
		height = 10,
		alpha = 0.5,
	}
end

function AC_UI.header(strId)
	return {
		type = "header",
		name = strId,
		width = "full",
	}
end

function AC_UI.description(textId, titleId)
	return
		{
			type = "description",
			text = textId, -- text or string id or function returning a string
			title = titleId, -- or string id or function returning a string (optional)
			width = "full", --or "half" (optional)
		}
end

