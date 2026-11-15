-- Run from AutoCategory/: lua5.1 ../test/GuildBankTrace_test.lua
-- Loads the delivered diagnostic module; external ESO APIs are simulated.
local passed = 0
local function check(name, condition)
    assert(condition, name)
    passed = passed + 1
end
local logs, queue, commits, sorts = {}, {}, 0, 0
local guild, now = 10, 1234
SLASH_COMMANDS = {}
INVENTORY_GUILD_BANK, AC_BAG_TYPE_GUILDBANK = 5, 3
EVENT_GUILD_BANK_SELECTED, EVENT_GUILD_BANK_ITEMS_READY = 100, 101
GetSelectedGuildBankId = function() return guild end
GetGameTimeMilliseconds = function() return now end
d = function() end
AutoCat_Logger = function()
    return {Info = function(_, message) logs[#logs + 1] = message end}
end
local function has(fragment)
    for _, message in ipairs(logs) do
        if message:find(fragment, 1, true) then return true end
    end
    return false
end
local function lastSummary(stage)
    for i = #logs, 1, -1 do
        if logs[i]:find(stage .. " list=", 1, true) then return logs[i] end
    end
end
local function row(header, key, slot)
    return {typeId = header and 998 or 1, top = 0, bottom = 30,
        data = {bagId = 3, slotIndex = slot, AC_categoryName = key,
            AC_sortPriorityName = key, AC_isHeader = header,
            AC_bagTypeId = 3, name = "item" .. tostring(slot)}}
end
local function list(data)
    return {data = data, visibleData = {}, activeControls = {},
        IsControlHidden = function() return false end,
        dataTypes = {[998] = {setupCallback = function() end}}}
end
local bank = list({row(true, "A", 0), row(false, "A", 1), row(true, "B", 0)})
local other = list({row(false, "X", 9)})
ZO_ScrollList_GetDataList = function(l) return l.data end
ZO_ScrollList_GetDataTypeTable = function(l, id) return l.dataTypes[id] end
ZO_ScrollList_Clear = function(l)
    for i = #l.data, 1, -1 do l.data[i] = nil end
end
ZO_ScrollList_Commit = function() commits = commits + 1 end
zo_callLater = function(callback, delay) queue[#queue + 1] = {callback, delay} end
-- ESO hook contracts: prehook false continues, posthook observes after.
ZO_PreHook = function(object, name, callback)
    if type(object) == "string" then object, name, callback = _G, object, name end
    local original = object[name]
    object[name] = function(...)
        if not callback(...) then return original(...) end
    end
    return original
end
ZO_PostHook = function(object, name, callback)
    if type(object) == "string" then object, name, callback = _G, object, name end
    local original = object[name]
    object[name] = function(...)
        local values = {original(...)}
        callback(...)
        return unpack(values)
    end
    return original
end
PLAYER_INVENTORY = {
    inventories = {[5] = {listView = bank, sortFn = function() end}},
    UpdateList = function() return "updated" end,
    ApplySort = function()
        sorts = sorts + 1
        return "sorted"
    end,
}
GetAddOnManager = function()
    return {
        GetNumAddOns = function() return 2 end,
        GetAddOnInfo = function(_, index)
            return index == 1 and "SwissKnife" or "DisabledAddon",
                "", "", "", index == 1, 1
        end,
        GetAddOnVersion = function() return 123 end,
    }
end
AutoCategory = {Enabled = true, saved = {bags = {[3] = {isUngroupedHidden = false}}}}
assert(loadfile("GuildBankTrace.lua"))()
local trace = AutoCategory.GuildBankTrace
trace:Snapshot("OFF")
check("off produces no logs", #logs == 0)
check("hooks are not installed at module load", not trace.installed)
trace.keyboard = true
SLASH_COMMANDS["/acgbtrace"]("on")
check("on installs hooks", trace.enabled and trace.installed)
check("enabled addon configuration logged", has("ADDON SwissKnife version=123"))
check("disabled addons excluded", not has("ADDON DisabledAddon"))
check("ungrouped option logged", has("ungroupedHidden=false"))
check("valid order reported", lastSummary("START"):find("inversions=0", 1, true))
check("checksum emitted", lastSummary("START"):match("hash=%d+"))
local originalHash = lastSummary("START"):match("hash=(%d+)")
local originalData = bank.data
bank.data[1], bank.data[2] = bank.data[2], bank.data[1]
trace:Snapshot("REORDER")
check("same counts but header behind item detected",
    lastSummary("REORDER"):find("inversions=1", 1, true))
check("same-count reorder changes checksum",
    lastSummary("REORDER"):match("hash=(%d+)") ~= originalHash)
bank.data[1].data.AC_categoryName = "No matching header"
trace:Snapshot("ORPHAN")
check("an unrelated header does not hide an orphaned item group",
    lastSummary("ORPHAN"):find("orphanItems=1", 1, true))
bank.data[1].data.AC_categoryName = "A"
check("snapshot leaves data table intact", bank.data == originalData)
check("snapshot leaves order intact", bank.data[1].typeId == 1)
check("diagnostics do not sort or commit", sorts == 0 and commits == 0)
local count = #logs
trace:Snapshot("OTHER", other)
check("unrelated lists ignored", #logs == count)
ZO_ScrollList_Commit(other)
check("unrelated commit still runs", commits == 1 and #logs == count)
ZO_ScrollList_Commit(bank)
check("guild commit still runs", commits == 2)
check("commit entry/exit traced", has("ZO_ScrollList_Commit_ENTER")
    and has("ZO_ScrollList_Commit_EXIT"))
check("caller stack contains file evidence", has("CALLER"))
check("UpdateList return preserved", PLAYER_INVENTORY:UpdateList(5) == "updated")
check("ApplySort return preserved", PLAYER_INVENTORY:ApplySort(5) == "sorted")
check("ApplySort still called exactly once", sorts == 1)
check("three delayed observations queued", #queue == 3)
check("delay values verified", queue[1][2] == 0 and queue[2][2] == 100
    and queue[3][2] == 300)
local delayed = queue
queue = {}
for _, task in ipairs(delayed) do task[1]() end
check("deferred checks observe current state", has("AFTER_SORT_300 list="))

-- Stale callbacks must not describe a new bank/list/session as the old one.
local function schedule() queue = {}; trace:AfterSort(bank); return queue end
local function silent(tasks)
    local before = #logs
    for _, task in ipairs(tasks) do task[1]() end
    return #logs == before
end
delayed = schedule()
trace:BankChanged(EVENT_GUILD_BANK_ITEMS_READY)
check("ready event distinguished", has("ITEMS_READY list="))
check("generation change cancels old samples", silent(delayed))
delayed = schedule()
guild = 20
check("selected guild change cancels old samples", silent(delayed))
delayed = schedule()
PLAYER_INVENTORY.inventories[5].listView = other
check("replaced list cancels old samples", silent(delayed))
PLAYER_INVENTORY.inventories[5].listView = bank
delayed = schedule()
schedule()
check("newer sort supersedes old samples", silent(delayed))
delayed = schedule()
SLASH_COMMANDS["/acgbtrace"]("off")
check("off cancels old samples", silent(delayed))
check("off does not change existing bank contents", bank.data == originalData)
SLASH_COMMANDS["/acgbtrace"]("on")
check("restart does not install duplicate hooks", trace.installed and trace.lines < 20)
delayed = schedule()
trace.keyboard = false
check("gamepad switch silences delayed samples", silent(delayed))
trace.keyboard = true
AutoCategory.Enabled = false
count = #logs
trace:Snapshot("DISABLED")
check("disabled addon ignored", #logs == count)
AutoCategory.Enabled = true

local label = {hidden = false, IsControlHidden = function(s) return s.hidden end,
    GetAlpha = function() return 1 end, GetText = function() return "Category A" end}
local control = {
    dataEntry = row(true, "A", 0),
    GetNamedChild = function() return label end,
    GetName = function() return "Header1" end,
    GetHeight = function() return 52 end,
    IsControlHidden = function() return false end,
}
bank.activeControls = {control}
bank.visibleData = {2}
trace:Rendered(control, control.dataEntry.data, bank)
check("header setup reports text and dimensions", has("HEADER_SETUP row=Header1")
    and has("height=52") and has("text=Category A"))
label.hidden = true
trace:Snapshot("HIDDEN_LABEL")
check("later label hiding detected", lastSummary("HIDDEN_LABEL"):find("hiddenH=1", 1, true))
trace:Filtered(bank, bank.data, function(entry)
    return entry.data.slotIndex == 1, "category-collapsed"
end)
check("filter counts exclude existing headers", has("FILTER inputItems=1 category-collapsed=1"))
-- Exercise the actual filtering predicate from the delivered keyboard file,
-- including its unchanged boolean contract and the new diagnostic reason.
local sourceFile = assert(io.open("Hooks_Keyboard.lua", "rb"))
local source = sourceFile:read("*a"):gsub("\r\n", "\n")
sourceFile:close()
local function extract(name)
    return assert(source:match("(local function " .. name .. "%(.-\nend)"),
        "missing delivered function " .. name)
end
AutoCategory.CategoryTree = {IsAnyAncestorCollapsed = function(_, name)
    return name == "child"
end}
AutoCategory.IsCategoryCollapsed = function(_, name) return name == "folded" end
local predicate = assert(loadstring("local CategoryTree=AutoCategory.CategoryTree\n"
    .. extract("isUngroupedHidden") .. "\n" .. extract("isHiddenEntry")
    .. "\nreturn isHiddenEntry"))()
local function reason(slot)
    return select(2, predicate({data = slot, typeId = 1}))
end
check("real rule-hidden reason", reason({AC_isHidden = true, AC_matched = true}) == "rule-hidden")
check("real ungrouped reason", reason({AC_isHidden = true, AC_matched = false}) == "ungrouped-hidden")
check("real missing bag reason", reason({}) == "missing-bag-type")
check("real ancestor reason", reason({AC_bagTypeId = 3, AC_categoryName = "child"}) == "ancestor-collapsed")
check("real category reason", reason({AC_bagTypeId = 3, AC_categoryName = "folded"}) == "category-collapsed")
check("real kept boolean preserved",
    predicate({data = {AC_bagTypeId = 3, AC_categoryName = "open"}}) == false)
AutoCategory.saved.bags[3].isUngroupedHidden = true
check("real hidden ungrouped option", predicate({data = {AC_bagTypeId = 3}}) == true)
AutoCategory.saved.bags[3].isUngroupedHidden = false
trace:Filtered(bank, {
    {typeId = 1, data = {AC_bagTypeId = 3, AC_categoryName = "open"}},
    {typeId = 1, data = {AC_bagTypeId = 3, AC_categoryName = "folded"}},
    {typeId = 1, data = {AC_bagTypeId = 3, AC_categoryName = "child"}},
    {typeId = 1, data = {AC_isHidden = true, AC_matched = true}},
    {typeId = 1, data = {AC_isHidden = true, AC_matched = false}},
    {typeId = 1, data = {}},
}, predicate)
check("filter summary uses the actual delivered predicate",
    has("FILTER inputItems=6 ancestor-collapsed=1 category-collapsed=1 kept=1 missing-bag-type=1 rule-hidden=1 ungrouped-hidden=1"))
SLASH_COMMANDS["/acgbtrace"]("mark sans en-tetes")
check("manual visual marker logged", has("MARK sans en-tetes") and has("MANUAL list="))
bank.dataTypes[998] = nil
trace:Snapshot("MISSING_TYPE")
check("missing header type diagnosed without error",
    lastSummary("MISSING_TYPE"):find("headerSetup=nil", 1, true))
ZO_ScrollList_Clear(bank)
check("clear still empties bank", #bank.data == 0)
check("clear traced", has("ZO_ScrollList_Clear_EXIT"))
local input = {row(false, nil, 2)}
bank.data = input
trace:Snapshot("MISSING_RULES")
check("missing rules diagnosed", lastSummary("MISSING_RULES"):find("missingRules=1", 1, true))
bank.data = {row(true, nil, 0)}
trace:Snapshot("HEADER_KEY_MISSING")
check("missing parent header keys diagnosed",
    lastSummary("HEADER_KEY_MISSING"):find("headerMissingKeys=1", 1, true))
trace.lines = 2500
trace:Write("limit")
check("capture stops at line limit", not trace.enabled and has("STOP line limit"))
SLASH_COMMANDS["/acgbtrace"]("mark apres limite")
check("manual marker accepted after the cap",
    has("MANUAL_AFTER_LIMIT") and has("MARK apres limite"))
check("manual marker does not restart continuous capture", not trace.enabled)
check("observation never caused an extra sort", sorts == 1)
print("GuildBankTrace passed=" .. passed .. " failed=0")
