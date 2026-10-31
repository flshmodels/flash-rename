local fs = require("@lune/fs")
local luau = require("@lune/luau")
local roblox = require("@lune/roblox")
local Rules = require("../src/Rules")
local Transaction = require("../src/Transaction")
local count = 0
local function test(name, callback)
    local ok, err = pcall(callback)
    assert(ok, name .. ": " .. tostring(err))
    count += 1
    print("PASS " .. name)
end
local function rejects(callback)
    assert(not pcall(callback), "expected an error")
end
for _, name in ipairs(fs.readDir("src")) do
    if name:match("%.luau$") then luau.compile(fs.readFile("src/" .. name)) end
end

test("transaction commits one batch", function()
    local writes, commits = 0, 0
    local ok = Transaction.apply({ {}, {} }, {
        validate = function() return true end,
        write = function() writes += 1 end,
    }, {
        begin = function() return "recording" end,
        finish = function(id, commit) assert(id == "recording" and commit) commits += 1 end,
    })
    assert(ok and writes == 2 and commits == 1)
end)
test("empty, stale and uncheckable plans never begin a recording", function()
    local function forbidden() error("must not be called") end
    for _, mode in ipairs({ "empty", "stale", "throw" }) do
        local began = false
        local ok = Transaction.apply(if mode == "empty" then {} else { {} }, {
            validate = function() if mode == "throw" then error("deleted") end return false, "stale" end,
            write = forbidden,
        }, { begin = function() began = true return "id" end, finish = forbidden })
        assert(not ok and not began)
    end
end)
test("refused or failing undo recordings do not edit objects", function()
    for _, mode in ipairs({ "refuse", "throw" }) do
        local writes = 0
        local ok = Transaction.apply({ {} }, { validate = function() return true end, write = function() writes += 1 end }, {
            begin = function() if mode == "throw" then error("busy") end return nil end,
            finish = function() error("must not finish") end,
        })
        assert(not ok and writes == 0)
    end
end)
test("write failures cancel and restore the fake scene", function()
    local state, snapshot, cancelled = 0, 0, false
    local ok = Transaction.apply({ {}, {} }, {
        validate = function() return true end,
        write = function() state += 1 if state == 2 then error("locked") end end,
    }, {
        begin = function() snapshot = state return "id" end,
        finish = function(_, commit) assert(not commit) state = snapshot cancelled = true end,
    })
    assert(not ok and cancelled and state == 0)
end)
test("failed commits attempt cancellation", function()
    local cancelled = false
    local ok = Transaction.apply({ {} }, { validate = function() return true end, write = function() end }, {
        begin = function() return "id" end,
        finish = function(_, commit) if commit then error("commit failed") end cancelled = true end,
    })
    assert(not ok and cancelled)
end)
test("failed cancellation is reported", function()
    local ok, message = Transaction.apply({ {} }, { validate = function() return true end, write = function() error("write failed") end }, {
        begin = function() return "id" end,
        finish = function() error("cancel failed") end,
    })
    assert(not ok and message:find("could not cancel", 1, true))
end)

local gameRoot = { Name = "Game" }
local world = { Name = "Workspace", Parent = gameRoot, children = {} }
function world:GetChildren() return self.children end
function world:IsDescendantOf(ancestor) return ancestor == gameRoot end
local function object(name, parent, class)
    local node = { Name = name, Parent = parent, children = {}, attributes = {}, Anchored = true, Locked = false, connected = {} }
    node.CFrame = roblox.CFrame.new(0.4, -0.5, 3.6) * roblox.CFrame.Angles(0, 0.4, 0)
    setmetatable(node, { __index = function(self, key) if key == "Position" then return self.CFrame.Position end return nil end })
    function node:IsA(candidate) return candidate == "BasePart" and class == "BasePart" end
    function node:IsDescendantOf(ancestor)
        local cursor = self.Parent
        while cursor do if cursor == ancestor then return true end cursor = cursor.Parent end
        return false
    end
    function node:GetFullName()
        local names, cursor = {}, self
        while cursor and cursor ~= gameRoot do table.insert(names, 1, cursor.Name) cursor = cursor.Parent end
        return table.concat(names, ".")
    end
    function node:GetChildren() return self.children end
    function node:GetConnectedParts() return self.connected end
    function node:GetAttribute(name) return self.attributes[name] end
    function node:SetAttribute(name, value) self.attributes[name] = value end
    if parent and parent.children then table.insert(parent.children, node) end
    return node
end
local Adapter = luau.load(fs.readFile("src/Adapter.luau"), { environment = {
    require = function() return Rules end,
    script = { Parent = { Rules = {} } },
    game = gameRoot, workspace = world, Vector3 = roblox.Vector3,
} })()

test("renames are sorted by full path and numbers are padded", function()
    local a, b = object("A", world), object("B", world)
    local plan = Adapter.plan({ b, a }, { template = "Tree_{n}", start = 8, padding = 3 })
    assert(plan[1].before.target == a and plan[1].after == "Tree_008" and plan[2].after == "Tree_009")
end)
test("old names are inserted literally, including percent signs and tokens", function()
    local a = object("A%{n}", world)
    local plan = Adapter.plan({ a }, { template = "{name}_LOD", start = 1, padding = 1 })
    assert(plan[1].after == "A%{n}_LOD")
end)
test("sibling conflicts are refused, but separate parents may share names", function()
    local folder = object("Folder", world)
    local a, b = object("A", folder), object("B", folder)
    rejects(function() Adapter.plan({ a }, { template = "B", start = 1, padding = 1 }) end)
    rejects(function() Adapter.plan({ a, b }, { template = "Same", start = 1, padding = 1 }) end)
    local other = object("Other", world)
    local c = object("C", other)
    assert(#Adapter.plan({ a, c }, { template = "Same", start = 1, padding = 1 }) == 2)
end)
test("unknown tokens, invalid numbering and blank names are rejected", function()
    local a = object("A", world)
    for _, template in ipairs({ "{bad}", "{N}", "", "   ", string.rep("x", 101), "bad\nname" }) do
        rejects(function() Adapter.plan({ a }, { template = template, start = 1, padding = 1 }) end)
    end
    rejects(function() Adapter.plan({ a }, { template = "{n}", start = -1, padding = 1 }) end)
    rejects(function() Adapter.plan({ a }, { template = "{n}", start = 1, padding = 7 }) end)
end)
test("stale objects and newly introduced conflicts block apply", function()
    local folder = object("Folder", world)
    local a = object("A", folder)
    local plan = Adapter.plan({ a }, { template = "Renamed", start = 1, padding = 1 })
    a.Name = "Changed"
    assert(not Adapter.validate(plan))
    a.Name = "A"
    assert(Adapter.validate(plan))
    object("Renamed", folder)
    assert(not Adapter.validate(plan))
end)
test("no-op names are omitted and services are refused", function()
    local a = object("UniqueNoopName", world)
    assert(#Adapter.plan({ a }, { template = "{name}", start = 1, padding = 1 }) == 0)
    rejects(function() Adapter.plan({ world }, { template = "Oops", start = 1, padding = 1 }) end)
end)

print(string.format("%d checks passed", count))
