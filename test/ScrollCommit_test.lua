-- Lua 5.1 behavioral test for Hooks_Keyboard.lua: after replacing a scroll
-- list's data (adding category headers, typeId 998), the list must be
-- committed so every entry receives its top/bottom scroll position. An
-- uncommitted non-uniform list crashes ZO_ScrollList_UpdateScroll with
-- "operator < is not supported for nil < number" (reported on the shared
-- ZO_ComboBoxDropdown_Singleton_Keyboard list).
-- Run from the repo root: lua5.1 test/ScrollCommit_test.lua

local Passed, Failed = 0, 0
local function check(Name, Condition)
  if Condition then Passed = Passed + 1
  else Failed = Failed + 1; print("FAIL: " .. Name) end
end

--------------------------------------------------------------------
-- Minimal ZO_ScrollList model (mode, heights, commit) like ScrollTemplates.
-- Each list is a proxy over a "real" state table; writing list.data
-- (what rebuildScrollData does) is logged so the test can assert that a
-- commit follows every replacement.
--------------------------------------------------------------------
local Log = {} -- ordered events: "replace:<list>", "commit:<list>"

local function newList(Name)
  local real = {name = Name, data = {}, dataTypes = {}, mode = 1,
    uniformControlHeight = nil, visibleData = {}}
  local proxy = setmetatable({}, {
    __index = function(_, k) return real[k] end,
    __newindex = function(_, k, v)
      if k == "data" then Log[#Log + 1] = "replace:" .. Name end
      real[k] = v
    end,
  })
  return proxy, real
end

--Proxies keep their state reachable via this weak registry.
local States = setmetatable({}, {__mode = "k"})
local function state(list) return States[list] end

local function makeList(Name)
  local proxy, real = newList(Name)
  States[proxy] = real
  return proxy
end

ZO_ScrollList_AddDataType = function(list, typeId, template, height)
  local real = state(list)
  if not real or real.dataTypes[typeId] then return end
  real.dataTypes[typeId] = {height = height}
  if not real.uniformControlHeight then
    real.uniformControlHeight = height
  elseif height ~= real.uniformControlHeight and real.mode == 1 then
    real.mode = 2 -- SCROLL_LIST_NON_UNIFORM, like UpdateModeFromHeight
  end
end

ZO_ScrollList_GetDataList = function(list) return state(list).data end

ZO_ScrollList_Clear = function(list)
  local real = state(list)
  for i = #real.data, 1, -1 do real.data[i] = nil end
  for i = #real.visibleData, 1, -1 do real.visibleData[i] = nil end
end

ZO_ScrollList_CreateDataEntry = function(typeId, data)
  return {typeId = typeId, data = data}
end

ZO_ScrollList_Commit = function(list)
  local real = state(list)
  Log[#Log + 1] = "commit:" .. real.name
  --NON_UNIFORM commit: assign top/bottom to every entry (UNIFORM lists do
  --this lazily in UpdateScroll instead).
  if real.mode == 2 then
    local y = 0
    for _, Entry in ipairs(real.data) do
      Entry.top = y
      local Info = real.dataTypes[Entry.typeId]
      y = y + (Info and Info.height or 30)
      Entry.bottom = y
    end
  end
  for i = #real.visibleData, 1, -1 do real.visibleData[i] = nil end
  for i in ipairs(real.data) do real.visibleData[#real.visibleData + 1] = i end
end

-- Simulated non-uniform UpdateScroll: the game reads dataEntry.top and
-- compares it against the bottom edge; a nil top is the reported crash.
local function updateScrollSafe(list)
  local real = state(list)
  for _, Entry in ipairs(real.data) do
    if real.mode == 2 and Entry.top == nil then return false end
  end
  return true
end

--------------------------------------------------------------------
-- Stubs required by Hooks_Keyboard.lua at load and in the tested paths
--------------------------------------------------------------------
INVENTORY_BACKPACK, INVENTORY_QUEST_ITEM, INVENTORY_GUILD_BANK = 1, 2, 5
INVENTORY_VENGEANCE = 8
AC_BAG_TYPE_BACKPACK, AC_BAG_TYPE_CRAFTSTATION = 1, 5
BAG_BACKPACK = 1
ZO_SORT_ORDER_UP = true
EVENT_STACKED_ALL_ITEMS, EVENT_STACKED_ALL_ITEMS_IN_BAG = "stacked", "stacked-bag"

LibMediaProvider = {Fetch = function() return "font" end}

CapturedUpdateHook = nil
LibSFUtils = {
  safeTable = function(t) return t or {} end,
  safeClearTable = function(t)
    if not t then return {} end
    for k in pairs(t) do t[k] = nil end
    return t
  end,
  nilDefault = function(v, d) if v == nil then return d end return v end,
  dstr = function(sep, ...) return table.concat({...}, sep) end,
  CallLater = {
    NewSingle = function(_, callback)
      CapturedUpdateHook = callback
      return {Start = function(s) return s end, Destroy = function(s) return nil end}
    end,
  },
}

AutoCategory = {
  logDebug = function() end,
  Enabled = true,
  BulkMode = false,
  cache = {},
  saved = {bags = {}},
  -- Branch-specific: Hooks_Keyboard consults the category tree to decide
  -- whether an entry sits under a collapsed level, and computes the level
  -- of each category header from it.
  CategoryTree = (function()
    -- A category without sub-levels: Levels returns a single-element
    -- list, so the ancestor-feeding loop of the branch does nothing.
    local noLevels = nil
    return {
      IsAnyAncestorCollapsed = function() return false end,
      LevelCount = function() return 1 end,
      Levels = function() return noLevels end,
      ParentOf = function() return nil end,
      SEPARATOR = "::",
      DisplayName = function(_, name) return name end,
      BuildSortKey = function() return "" end,
      LevelSortKey = function() return "" end,
    }
  end)(),
  acctSaved = {appearance = {
    CATEGORY_HEADER_HEIGHT = 52,
    CATEGORY_OTHER_TEXT = "Others",
    CATEGORY_FONT_SIZE = 18,
    CATEGORY_FONT_ALIGNMENT = 1,
    CATEGORY_FONT_NAME = "Univers 67",
    CATEGORY_FONT_STYLE = "soft-shadow-thin",
    CATEGORY_FONT_COLOR = "FFFFFF",
  }},
  IsCategoryCollapsed = function() return false end,
  MatchCategoryRules = function() return false, "Others", 0, 0, 1, false end,
  RefreshList = function() end,
}

local PreHooks, RegisteredEvents = {}, {}
AutoCategory.hookmgr = {PreHook = function(_, obj, name, fn)
  PreHooks[#PreHooks + 1] = {obj = obj, name = name, fn = fn}
end}
AutoCategory.evtmgr = {registerEvt = function(_, evt, fn)
  RegisteredEvents[evt] = fn
end}

SMITHING = {deconstructionPanel = {inventory = {list = makeList("DeconList")}},
  improvementPanel = {inventory = {list = makeList("ImproveList")}}}
UNIVERSAL_DECONSTRUCTION = {deconstructionPanel = {inventory =
  {list = makeList("UniversalDeconList")}}}

local PlayerInventoryList = makeList("PlayerInventoryList")
ZO_PlayerInventoryList = PlayerInventoryList
ZO_CraftBagList = makeList("CraftBagList")
ZO_PlayerBankBackpack = makeList("PlayerBankBackpack")
local GuildBankBackpack = makeList("GuildBankBackpack")
ZO_GuildBankBackpack = GuildBankBackpack
ZO_HouseBankBackpack = makeList("HouseBankBackpack")
ZO_PlayerInventoryQuest = makeList("PlayerInventoryQuest")
ZO_FurnitureVaultList = makeList("FurnitureVaultList")
ZO_VengeanceInventoryList = makeList("VengeanceInventoryList")
ZO_UniversalDeconstructionTopLevel_KeyboardPanelInventoryBackpack = makeList("UDList")

-- inventory rows (type 1) are 52 high; a different header height flips a
-- list to NON_UNIFORM mode, where top/bottom only come from Commit.
ZO_ScrollList_AddDataType(PlayerInventoryList, 1, "ZO_PlayerInventorySlot", 52)
ZO_ScrollList_AddDataType(GuildBankBackpack, 1, "ZO_PlayerInventorySlot", 52)

SCENE_MANAGER = {GetCurrentScene = function()
  return {GetName = function() return "inventory" end}
end}

local CallLaterQueue = {}
zo_callLater = function(fn, ms) CallLaterQueue[#CallLaterQueue + 1] = fn end

PLAYER_INVENTORY = {
  selectedTabType = INVENTORY_BACKPACK,
  inventories = {},
  bagToInventoryType = {},
}

ZO_TableOrderingFunction = function(left, right)
  return tostring(left) < tostring(right)
end
ZO_InventorySlot_OnPoolReset = function() end
GetItemUniqueId = function() return nil end

--------------------------------------------------------------------
-- Load the delivered Hooks_Keyboard.lua in this environment
--------------------------------------------------------------------
local Chunk = assert(loadfile("Hooks_Keyboard.lua"))
setfenv(Chunk, getfenv(1))
Chunk()

check("Hooks_Keyboard.lua loads with the stub environment", true)

--------------------------------------------------------------------
-- HookKeyboardMode registers the 998 header type on the lists
--------------------------------------------------------------------
AutoCategory.HookKeyboardMode()

check("header data type 998 registered on the player inventory list",
  state(PlayerInventoryList).dataTypes[998] ~= nil)
check("header data type 998 registered on the guild bank list",
  state(GuildBankBackpack).dataTypes[998] ~= nil)

--------------------------------------------------------------------
-- prehookSort on a populated inventory: data is replaced and committed
--------------------------------------------------------------------
local function itemEntry(n)
  return ZO_ScrollList_CreateDataEntry(1,
    {bagId = 1, slotIndex = n, name = "item" .. n, stackCount = 1})
end

local Inventory = makeList("PlayerInventoryList")
ZO_ScrollList_AddDataType(Inventory, 1, "ZO_PlayerInventorySlot", 52)
ZO_ScrollList_AddDataType(Inventory, 998, "AC_InventoryItemRowHeader", 40)
state(Inventory).data = {itemEntry(1), itemEntry(2)}

PLAYER_INVENTORY.inventories[INVENTORY_BACKPACK] = {
  listView = Inventory,
  currentSortKey = "name",
  currentSortOrder = false,
}

local applySortHook
for _, Hook in ipairs(PreHooks) do
  if Hook.name == "ApplySort" then applySortHook = Hook.fn end
end
check("ApplySort prehook captured", applySortHook ~= nil)

applySortHook(PLAYER_INVENTORY, INVENTORY_BACKPACK)

local invState = state(Inventory)
check("inventory data replaced with headers appended",
  #invState.data == 3 and invState.data[3].typeId == 998)

--the fix: a commit happened after the replacement, before ApplySort's own
--sort + commit. Check the event order.
local ReplaceAt, CommitAfter = nil, false
for i, Event in ipairs(Log) do
  if Event == "replace:PlayerInventoryList" then ReplaceAt = i end
  if ReplaceAt and Event == "commit:PlayerInventoryList" and i > ReplaceAt then
    CommitAfter = true
  end
end
check("list committed after data replacement (the fix)", CommitAfter)

--simulated ApplySort: sort then commit, like the original function
table.sort(invState.data, function() return false end)
ZO_ScrollList_Commit(Inventory)

check("every entry has a scroll position (top) after the commits",
  updateScrollSafe(Inventory))
check("header entry received top/bottom from the commit",
  invState.data[3].top ~= nil and invState.data[3].bottom ~= nil)

--------------------------------------------------------------------
-- Guild-bank retry path: empty list queues a 100ms retry that must
-- also commit after replacing the data (this path had no commit at all)
--------------------------------------------------------------------
local GuildBank = makeList("GuildBankBackpack")
ZO_ScrollList_AddDataType(GuildBank, 1, "ZO_PlayerInventorySlot", 52)
ZO_ScrollList_AddDataType(GuildBank, 998, "AC_InventoryItemRowHeader", 40)
local gbState = state(GuildBank)

PLAYER_INVENTORY.inventories[INVENTORY_GUILD_BANK] = {
  listView = GuildBank,
  altFreeSlotType = INVENTORY_GUILD_BANK,
  currentSortKey = "name",
  currentSortOrder = false,
}

CallLaterQueue = {}
Log = {}
--SCENE_MANAGER must report the guild bank scene for this inventory
SCENE_MANAGER = {GetCurrentScene = function()
  return {GetName = function() return "guildBank" end}
end}

applySortHook(PLAYER_INVENTORY, INVENTORY_GUILD_BANK)
check("empty guild bank queues a delayed rebuild",
  #CallLaterQueue == 1 and #gbState.data == 0)

--the bank contents arrive after the scene opened; the retry rebuilds
gbState.data = {itemEntry(1), itemEntry(2)}
CallLaterQueue[1]()

local GBReplaceAt, GBCommitAfter = nil, false
for i, Event in ipairs(Log) do
  if Event == "replace:GuildBankBackpack" then GBReplaceAt = i end
  if GBReplaceAt and Event == "commit:GuildBankBackpack" and i > GBReplaceAt then
    GBCommitAfter = true
  end
end
check("delayed guild bank rebuild commits after replacing data", GBCommitAfter)
check("guild bank header has a scroll position",
  gbState.data[3] ~= nil and gbState.data[3].typeId == 998
    and gbState.data[3].top ~= nil)
check("guild bank list survives a simulated UpdateScroll",
  updateScrollSafe(GuildBank))

--------------------------------------------------------------------
-- updateHook: the one-shot CallLater starts it without arguments; a nil
-- inventory must not raise (previously a silent failure in SF_safeCall)
--------------------------------------------------------------------
check("updateHook captured by the CallLater stub", CapturedUpdateHook ~= nil)
local Ok, Err = pcall(CapturedUpdateHook)
check("updateHook tolerates a nil inventory", Ok and Err == nil)

print(string.format("scroll commit passed=%d failed=%d", Passed, Failed))
if Failed > 0 then os.exit(1) end
