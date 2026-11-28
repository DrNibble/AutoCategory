-- Lua 5.1 behavioral test for the collapse of an intermediate header.
--
-- A hierarchical category name ("Potions----Magie----Soin") is displayed as
-- one collapsible header per level. The level-1 header ("Potions") has no
-- rule of its own when no category carries that exact name: it only exists
-- as a header built from the level chain. It must still be collapsible -
-- clicking it used to be silently ignored because the category state only
-- knew the categories of the list, never the intermediate header levels.
--
-- Run from the AutoCategory/ addon folder:
--   python3 -c "import lupa.lua51 as l; l.LuaRuntime().execute(open('../test/HeaderLevel1Collapse_test.lua').read())"

local Passed, Failed = 0, 0
local function check(Name, Condition)
  if Condition then Passed = Passed + 1
  else Failed = Failed + 1; print("FAIL: " .. Name) end
end

--------------------------------------------------------------------
-- Minimal ZO_ScrollList model
--------------------------------------------------------------------
local function newList(Name)
  return {name = Name, data = {}, dataTypes = {}, mode = 2, visibleData = {}}
end

local Lists = {}
local function makeList(Name)
  local list = newList(Name)
  Lists[Name] = list
  return list
end

ZO_ScrollList_AddDataType = function(list, typeId, template, height)
  if not list.dataTypes[typeId] then
    list.dataTypes[typeId] = {height = height}
  end
end

ZO_ScrollList_GetDataList = function(list) return list.data end

ZO_ScrollList_Clear = function(list)
  for i = #list.data, 1, -1 do list.data[i] = nil end
end

ZO_ScrollList_CreateDataEntry = function(typeId, data)
  return {typeId = typeId, data = data}
end

ZO_ScrollList_Commit = function(list)
  local y = 0
  for _, Entry in ipairs(list.data) do
    Entry.top = y
    local Info = list.dataTypes[Entry.typeId]
    y = y + (Info and Info.height or 30)
    Entry.bottom = y
  end
end

--------------------------------------------------------------------
-- ESO / library stubs required by the delivered files
--------------------------------------------------------------------
INVENTORY_BACKPACK, INVENTORY_GUILD_BANK = 1, 5
AC_BAG_TYPE_BACKPACK = 1
BAG_BACKPACK = 1
ZO_SORT_ORDER_UP = true
EVENT_STACKED_ALL_ITEMS, EVENT_STACKED_ALL_ITEMS_IN_BAG = "stacked", "stacked-bag"
EVENT_GUILD_BANK_SELECTED, EVENT_GUILD_BANK_ITEMS_READY = "bank-selected", "bank-ready"

LibMediaProvider = {Fetch = function() return "font" end}

LibSFUtils = {
  safeTable = function(t) return t or {} end,
  safeClearTable = function(t)
    if not t then return {} end
    for k in pairs(t) do t[k] = nil end
    return t
  end,
  nilDefault = function(v, d) if v == nil then return d end return v end,
  dstr = function(sep, ...) return table.concat({...}, sep) end,
  isEmpty = function(t) return t == nil or next(t) == nil end,
  defaultMissing = function() end,
  CallLater = {NewSingle = function(_, callback)
    return {Start = function(s) return s end, Destroy = function() end}
  end},
}

local Now = 1000000
GetTimeStamp = function() return Now end

AutoCategory = {
  logDebug = function() end,
  Enabled = true,
  BulkMode = false,
  cache = {},
  acctRules = {},
  categoryState = {},
  saved = {
    bags = {},
    collapses = {},
    collapseExpiry = {},
    general = {
      SHOW_CATEGORY_ITEM_COUNT = false,
      SHOW_CATEGORY_COLLAPSE_ICON = true,
      SAVE_CATEGORY_COLLAPSE_STATUS = true,
      CATEGORY_COLLAPSE_EXPIRY_SECONDS = "never",
    },
    -- a saved bag entry so the bag exists for the rules
    appearance = {
      CATEGORY_HEADER_HEIGHT = 52,
      CATEGORY_OTHER_TEXT = "Others",
      CATEGORY_FONT_SIZE = 18,
      CATEGORY_FONT_ALIGNMENT = 1,
      CATEGORY_FONT_NAME = "Univers 67",
      CATEGORY_FONT_STYLE = "soft-shadow-thin",
      CATEGORY_FONT_COLOR = "FFFFFF",
      HIDDEN_CATEGORY_FONT_COLOR = {0.5, 0.5, 0.5, 1},
    },
  },
  acctSaved = {general = {}, appearance = {
    CATEGORY_HEADER_HEIGHT = 52,
    CATEGORY_OTHER_TEXT = "Others",
    CATEGORY_FONT_SIZE = 18,
    CATEGORY_FONT_ALIGNMENT = 1,
    CATEGORY_FONT_NAME = "Univers 67",
    CATEGORY_FONT_STYLE = "soft-shadow-thin",
    CATEGORY_FONT_COLOR = "FFFFFF",
    HIDDEN_CATEGORY_FONT_COLOR = {0.5, 0.5, 0.5, 1},
  }},
  RefreshList = function() end,
  RefreshCurrentList = function() end,
}

local PreHooks = {}
AutoCategory.hookmgr = {
  PreHook = function(_, obj, name, fn)
    PreHooks[#PreHooks + 1] = {obj = obj, name = name, fn = fn}
  end,
  disableAll = function() end,
}
AutoCategory.evtmgr = {registerEvt = function() end, unregEvt = function() end}

local PlayerInventoryList = makeList("PlayerInventoryList")
ZO_PlayerInventoryList = PlayerInventoryList
ZO_CraftBagList = makeList("CraftBagList")
ZO_PlayerBankBackpack = makeList("PlayerBankBackpack")
ZO_GuildBankBackpack = makeList("GuildBankBackpack")
ZO_HouseBankBackpack = makeList("HouseBankBackpack")
ZO_PlayerInventoryQuest = makeList("PlayerInventoryQuest")
ZO_FurnitureVaultList = makeList("FurnitureVaultList")
ZO_VengeanceInventoryList = makeList("VengeanceInventoryList")
ZO_UniversalDeconstructionTopLevel_KeyboardPanelInventoryBackpack = makeList("UDList")

-- Different heights: the header type makes the list NON_UNIFORM.
ZO_ScrollList_AddDataType(PlayerInventoryList, 1, "ZO_PlayerInventorySlot", 52)
ZO_ScrollList_AddDataType(PlayerInventoryList, 998, "AC_InventoryItemRowHeader", 40)

INVENTORY_QUEST_ITEM, INVENTORY_VENGEANCE = 2, 8
SMITHING = {deconstructionPanel = {inventory = {list = makeList("DeconList")}},
  improvementPanel = {inventory = {list = makeList("ImproveList")}}}
UNIVERSAL_DECONSTRUCTION = {deconstructionPanel = {inventory =
  {list = makeList("UndeconList")}}}

SCENE_MANAGER = {GetCurrentScene = function()
  return {GetName = function() return "inventory" end}
end}

zo_callLater = function() end

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
-- Load the real category tree and collapse module, then the hooks
--------------------------------------------------------------------
local function load(file)
  local Chunk = assert(loadfile(file))
  setfenv(Chunk, getfenv(1))
  Chunk()
end

load("AutoCategory_Tree.lua")
local CategoryTree = AutoCategory.CategoryTree

load("AC_Collapsed.lua")
local AutoCat = AutoCategory

-- One hierarchical category, no rule carries the level-1 name itself.
local FULL_NAME = CategoryTree.JoinName({"Potions", "Magie", "Soin"})
AutoCat.MatchCategoryRules = function()
  return true, FULL_NAME, 0, 0, BAG_BACKPACK, false, "key"
end

load("Hooks_Keyboard.lua")

AutoCat.HookKeyboardMode()

local applySortHook
for _, Hook in ipairs(PreHooks) do
  if Hook.name == "ApplySort" then applySortHook = Hook.fn end
end
check("ApplySort prehook captured", applySortHook ~= nil)

local function itemEntry(n)
  return ZO_ScrollList_CreateDataEntry(1,
    {bagId = BAG_BACKPACK, slotIndex = n, name = "item" .. n, stackCount = 1})
end

local Inventory = PLAYER_INVENTORY.inventories[INVENTORY_BACKPACK]
if Inventory == nil then
  Inventory = ZO_PlayerInventoryList
  PLAYER_INVENTORY.inventories[INVENTORY_BACKPACK] = {
    listView = Inventory,
    currentSortKey = "name",
    currentSortOrder = false,
  }
end

Inventory.data = {itemEntry(1), itemEntry(2)}
applySortHook(PLAYER_INVENTORY, INVENTORY_BACKPACK)

local LEVEL1 = "Potions"
local LEVEL2 = CategoryTree.JoinName({"Potions", "Magie"})

local function headerNames()
  local names = {}
  for _, Entry in ipairs(Inventory.data) do
    if Entry.typeId == 998 then
      names[Entry.data.AC_categoryName] = Entry.data.AC_headerLevel
    end
  end
  return names
end

local Headers = headerNames()
check("level-1 header is drawn", Headers[LEVEL1] == 1)
check("level-2 header is drawn", Headers[LEVEL2] == 2)
check("leaf header is drawn", Headers[FULL_NAME] == 3)

local State = AutoCat.categoryState[BAG_BACKPACK] or {}
check("level-1 header is known to the collapse state", State[LEVEL1] ~= nil)
check("level-2 header is known to the collapse state", State[LEVEL2] ~= nil)

-- Clicking the level-1 header must fold the whole subtree.
AutoCat.SetCategoryCollapsed(BAG_BACKPACK, LEVEL1, true)
check("level-1 header collapses", AutoCat.IsCategoryCollapsed(BAG_BACKPACK, LEVEL1))

Inventory.data = {itemEntry(1), itemEntry(2)}
applySortHook(PLAYER_INVENTORY, INVENTORY_BACKPACK)
local CollapsedHeaders = headerNames()
check("folded level-1 header remains the only header",
  CollapsedHeaders[LEVEL1] == 1 and CollapsedHeaders[LEVEL2] == nil
    and CollapsedHeaders[FULL_NAME] == nil)
check("folded level-1 state survives the refresh",
  AutoCat.IsCategoryCollapsed(BAG_BACKPACK, LEVEL1))

-- Expanding it brings the subtree back.
AutoCat.SetCategoryCollapsed(BAG_BACKPACK, LEVEL1, false)
Inventory.data = {itemEntry(1), itemEntry(2)}
applySortHook(PLAYER_INVENTORY, INVENTORY_BACKPACK)
local ExpandedHeaders = headerNames()
check("expanded level-1 header shows its sub-levels",
  ExpandedHeaders[LEVEL1] == 1 and ExpandedHeaders[LEVEL2] == 2
    and ExpandedHeaders[FULL_NAME] == 3)

print(string.format("header level 1 collapse passed=%d failed=%d",
  Passed, Failed))
if Failed > 0 then os.exit(1) end
