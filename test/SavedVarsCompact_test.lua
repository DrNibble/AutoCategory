-- Run from the addon root with Lua 5.1:
-- lua5.1 test/SavedVarsCompact_test.lua  (run from the AutoCategory/ addon folder)
-- Tests the SavedVariables size optimization (SavedVarsCompact.lua),
-- loading the delivered file (never a copy of it).

local assertions = 0
local function equal(expected, actual, message)
    assertions = assertions + 1
    assert(expected == actual, (message or "") .. ": expected "
        .. tostring(expected) .. ", got " .. tostring(actual))
end

-- ---------------------------------------------------------------------------
-- load the delivered SavedVarsCompact.lua (never a copy of it)
-- ---------------------------------------------------------------------------

AutoCategory = {}
assert(loadfile("SavedVarsCompact.lua"))()

local SVC = AutoCategory.SavedVarsCompact

-- ---------------------------------------------------------------------------
-- helpers
-- ---------------------------------------------------------------------------

-- build a bag rule in the current saved format
local function bagrule(name, runpriority, showpriority, isHidden)
    local r = { name = name }
    if runpriority ~= nil then r.runpriority = runpriority end
    if showpriority ~= nil then r.showpriority = showpriority end
    if isHidden ~= nil then r.isHidden = isHidden end
    return r
end

-- build a raw saved variables table in the shape the game writes:
-- rawSV.Default[account][charId or "$AccountWide"][server] = data
local function makeRawSV()
    return {
        Default = {
            ["@Alpha"] = {
                ["$AccountWide"] = {
                    ["EU Megaserver"] = {
                        bags = {
                            [1] = { rules = {
                                ["LQR"] = bagrule("LQR", 1000, 1000),
                                ["Vente"] = bagrule("Vente", 350, 350),
                                ["Nouveau"] = bagrule("Nouveau", 975, 500),
                            }},
                        },
                    },
                },
                ["1111111111111111"] = {
                    ["$LastCharacterName"] = "AlphaOne",
                    ["EU Megaserver"] = {
                        accountWide = true,
                        version = 1.1,
                        bags = {
                            [1] = { rules = {
                                [1] = { name = "Old", priority = 1000 },
                            }},
                        },
                        collapses = { [1] = { ["Old"] = true } },
                        general = { X = 1 },
                        appearance = { Y = 2 },
                        rules = { [1] = { name = "Old" } },
                    },
                },
                ["2222222222222222"] = {
                    ["$LastCharacterName"] = "AlphaTwo",
                    ["EU Megaserver"] = {
                        accountWide = false,
                        bags = {
                            [2] = { rules = {
                                ["Perso"] = bagrule("Perso", 1000, 1000),
                            }},
                        },
                        collapses = { [2] = { ["Perso"] = true } },
                        general = { X = 3 },
                    },
                },
            },
            ["@Beta"] = {
                ["$AccountWide"] = {
                    ["EU Megaserver"] = {
                        bags = {
                            [1] = { rules = {
                                ["Default"] = bagrule("Default", 1000, 1000),
                            }},
                        },
                    },
                },
            },
        },
    }
end

-- ---------------------------------------------------------------------------
-- InflateBagRules
-- ---------------------------------------------------------------------------

do
    local bags = {
        [1] = { rules = {
            ["A"] = bagrule("A"),                      -- nothing: gets defaults
            ["B"] = bagrule("B", 350),                 -- showpriority filled
            ["C"] = bagrule("C", 500, 200),            -- complete: untouched
            ["D"] = { name = "D", priority = 700 },    -- legacy format
            ["E"] = bagrule("E", 1000, nil, false),    -- isHidden stays false
        }},
    }
    local touched = SVC.InflateBagRules(bags)
    equal(5, touched, "inflate touches every entry")
    equal(1000, bags[1].rules["A"].runpriority, "A runpriority default")
    equal(1000, bags[1].rules["A"].showpriority, "A showpriority default")
    equal(350, bags[1].rules["B"].runpriority, "B runpriority kept")
    equal(350, bags[1].rules["B"].showpriority, "B showpriority filled")
    equal(500, bags[1].rules["C"].runpriority, "C runpriority kept")
    equal(200, bags[1].rules["C"].showpriority, "C showpriority kept")
    equal(700, bags[1].rules["D"].runpriority, "D priority migrated")
    equal(nil, bags[1].rules["D"].priority, "D priority removed")
    equal(700, bags[1].rules["D"].showpriority, "D showpriority filled")
    equal(false, bags[1].rules["E"].isHidden, "E isHidden kept")

    -- non-table input is safe
    equal(0, SVC.InflateBagRules(nil), "inflate nil bags")
    equal(0, SVC.InflateBagRules("nope"), "inflate non-table bags")
end

-- ---------------------------------------------------------------------------
-- TrimBagRules
-- ---------------------------------------------------------------------------

do
    local bags = {
        [1] = { rules = {
            ["A"] = bagrule("A", 1000, 1000),      -- both defaults: both trimmed
            ["B"] = bagrule("B", 350, 350),        -- showpriority == runpriority
            ["C"] = bagrule("C", 500, 200),        -- distinct values: untouched
            ["D"] = bagrule("D", 1000, 250),      -- runpriority default only
            ["E"] = bagrule("E", 100, 100, false), -- isHidden false trimmed
            [1] = { name = "Old", priority = 42 }, -- legacy format: untouched
        }},
    }
    local trimmed = SVC.TrimBagRules(bags)
    equal(nil, bags[1].rules["A"].runpriority, "A runpriority trimmed")
    equal(nil, bags[1].rules["A"].showpriority, "A showpriority trimmed")
    equal(350, bags[1].rules["B"].runpriority, "B runpriority kept")
    equal(nil, bags[1].rules["B"].showpriority, "B showpriority trimmed")
    equal(500, bags[1].rules["C"].runpriority, "C runpriority kept")
    equal(200, bags[1].rules["C"].showpriority, "C showpriority kept")
    equal(nil, bags[1].rules["D"].runpriority, "D runpriority trimmed")
    equal(250, bags[1].rules["D"].showpriority, "D showpriority kept")
    equal(nil, bags[1].rules["E"].isHidden, "E isHidden trimmed")
    equal(100, bags[1].rules["E"].runpriority, "E runpriority kept")
    equal(42, bags[1].rules[1].priority, "legacy entry untouched")
    equal(6, trimmed, "trimmed value count")

    -- trimming is idempotent
    equal(0, SVC.TrimBagRules(bags), "trim is idempotent")

    -- non-table input is safe
    equal(0, SVC.TrimBagRules(nil), "trim nil bags")
end

-- ---------------------------------------------------------------------------
-- trim / inflate round trip preserves the logical values
-- ---------------------------------------------------------------------------

do
    local original = {
        [1] = { rules = {
            ["A"] = bagrule("A", 1000, 1000),
            ["B"] = bagrule("B", 350, 350),
            ["C"] = bagrule("C", 500, 200),
            ["D"] = bagrule("D", 1000, 250),
        }},
    }
    local working = {
        [1] = { rules = {
            ["A"] = bagrule("A", 1000, 1000),
            ["B"] = bagrule("B", 350, 350),
            ["C"] = bagrule("C", 500, 200),
            ["D"] = bagrule("D", 1000, 250),
        }},
    }
    SVC.TrimBagRules(working)
    SVC.InflateBagRules(working)
    for name in pairs(original[1].rules) do
        equal(original[1].rules[name].runpriority,
            working[1].rules[name].runpriority,
            "round trip runpriority " .. name)
        equal(original[1].rules[name].showpriority,
            working[1].rules[name].showpriority,
            "round trip showpriority " .. name)
    end
end

-- ---------------------------------------------------------------------------
-- CleanupDeadCharacterData
-- ---------------------------------------------------------------------------

do
    local rawSV = makeRawSV()
    local cleaned = SVC.CleanupDeadCharacterData(rawSV)

    -- @Alpha char 1 (account-wide): bags/collapses/general/appearance/rules gone
    local char1 = rawSV.Default["@Alpha"]["1111111111111111"]["EU Megaserver"]
    equal(nil, char1.bags, "char1 bags removed")
    equal(nil, char1.collapses, "char1 collapses removed")
    equal(nil, char1.general, "char1 general removed")
    equal(nil, char1.appearance, "char1 appearance removed")
    equal(nil, char1.rules, "char1 rules removed")
    equal("AlphaOne", rawSV.Default["@Alpha"]["1111111111111111"]["$LastCharacterName"],
        "char1 name kept")

    -- @Alpha char 2 (character specific): bags/collapses kept, general dropped
    local char2 = rawSV.Default["@Alpha"]["2222222222222222"]["EU Megaserver"]
    equal(false, char2.accountWide, "char2 accountWide kept")
    equal("table", type(char2.bags), "char2 bags kept")
    equal("table", type(char2.collapses), "char2 collapses kept")
    equal(nil, char2.general, "char2 general removed")

    -- account-wide sections are untouched
    local aw = rawSV.Default["@Alpha"]["$AccountWide"]["EU Megaserver"]
    equal("table", type(aw.bags), "$AccountWide bags kept")
    equal(2, cleaned, "cleaned sections count")

    -- bad input is safe
    equal(0, SVC.CleanupDeadCharacterData(nil), "cleanup nil table")
    equal(0, SVC.CleanupDeadCharacterData({}), "cleanup no Default")
end

-- fix the placeholder assertion above: rules are name-keyed, count them
do
    local rawSV = makeRawSV()
    local aw = rawSV.Default["@Alpha"]["$AccountWide"]["EU Megaserver"]
    local n = 0
    for _ in pairs(aw.bags[1].rules) do n = n + 1 end
    equal(3, n, "$AccountWide bag rules untouched")
end

-- ---------------------------------------------------------------------------
-- TrimOtherAccounts
-- ---------------------------------------------------------------------------

do
    local rawSV = makeRawSV()
    local trimmed = SVC.TrimOtherAccounts(rawSV, "@alpha")  -- case-insensitive

    -- the current account is left alone
    local aw = rawSV.Default["@Alpha"]["$AccountWide"]["EU Megaserver"]
    equal(1000, aw.bags[1].rules["LQR"].runpriority, "current account not trimmed")
    equal(1000, aw.bags[1].rules["LQR"].showpriority, "current account showpriority kept")

    -- the other account is trimmed
    local beta = rawSV.Default["@Beta"]["$AccountWide"]["EU Megaserver"]
    equal(nil, beta.bags[1].rules["Default"].runpriority, "other account trimmed")

    -- @Alpha char 2 (not account-wide) is not "the current account's
    -- section" in the raw walk - it belongs to @Alpha so it is not
    -- trimmed either; the current account is handled at logout
    local char2 = rawSV.Default["@Alpha"]["2222222222222222"]["EU Megaserver"]
    equal(1000, char2.bags[2].rules["Perso"].runpriority, "same account sections untouched")

    equal(2, trimmed, "trimmed values count")

    -- no current account name: nothing is trimmed (safety)
    local rawSV2 = makeRawSV()
    equal(0, SVC.TrimOtherAccounts(rawSV2, nil), "no account name: no trim")
    equal(1000, rawSV2.Default["@Beta"]["$AccountWide"]["EU Megaserver"]
        .bags[1].rules["Default"].runpriority, "nothing trimmed without name")
end

-- ---------------------------------------------------------------------------
-- TrimCurrentAccount
-- ---------------------------------------------------------------------------

do
    local acctSaved = { bags = {
        [1] = { rules = { ["A"] = bagrule("A", 1000, 1000) } },
    }}
    local charSavedOn = { accountWide = true, bags = {
        [1] = { rules = { ["B"] = bagrule("B", 1000, 1000) } },
    }}
    -- account-wide on: the character bags are dead, only the account section
    -- is trimmed
    local n1 = SVC.TrimCurrentAccount(acctSaved, charSavedOn)
    equal(nil, acctSaved.bags[1].rules["A"].runpriority, "acct bags trimmed")
    equal(1000, charSavedOn.bags[1].rules["B"].runpriority, "dead char bags not trimmed")
    equal(2, n1, "logout trim count (account-wide on)")

    local charSavedOff = { accountWide = false, bags = {
        [1] = { rules = { ["B"] = bagrule("B", 1000, 1000) } },
    }}
    local n2 = SVC.TrimCurrentAccount(acctSaved, charSavedOff)
    equal(nil, charSavedOff.bags[1].rules["B"].runpriority, "live char bags trimmed")
    equal(2, n2, "logout trim count (account-wide off)")

    equal(0, SVC.TrimCurrentAccount(nil, nil), "logout trim nil tables")
end

-- ---------------------------------------------------------------------------

print("SavedVarsCompact_test: all " .. assertions .. " assertions passed")
