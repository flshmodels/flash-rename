local Rules = require(script.Parent.Rules)
local Adapter = {}

function Adapter.controls(panel, changed)
    panel.label("Use {name} for the old name and {n} for a number. Objects are sorted by full path; exact ties keep selection order. Duplicate sibling names are refused.")
    local template = panel.field("Name template", "Part_{n}")
    local start = panel.field("First number", "1")
    local padding = panel.field("Minimum number digits", "3")
    for _, field in ipairs({ template, start, padding }) do field:GetPropertyChangedSignal("Text"):Connect(changed) end
    return function() return { template = template.Text, start = tonumber(start.Text), padding = tonumber(padding.Text) } end
end

function Adapter.plan(selection, options)
    local rows, siblings, parents, seen = {}, {}, {}, {}
    assert(#selection <= 500, "Select no more than 500 objects.")
    for index, object in ipairs(selection) do
        assert(object.Parent and object:IsDescendantOf(game) and object.Parent ~= game, "Select objects inside a service, not the service itself.")
        if not seen[object] then
            seen[object] = true
            table.insert(rows, { target = object, parent = object.Parent, name = object.Name, path = object:GetFullName(), index = index })
            parents[object.Parent] = true
        end
    end
    local count = 0
    for parent in pairs(parents) do
        for _, sibling in ipairs(parent:GetChildren()) do
            count = count + 1
            assert(count <= 10000, "Selected parents contain more than 10000 children. Use a smaller scope.")
            table.insert(siblings, { target = sibling, parent = parent, name = sibling.Name })
        end
    end
    local plan = Rules.plan(rows, siblings, options)
    for _, entry in ipairs(plan) do entry.label = entry.before.path .. "\n" .. entry.before.name .. " -> " .. entry.after end
    return plan
end

function Adapter.validate(plan)
    local proposed = {}
    for _, entry in ipairs(plan) do
        local before = entry.before
        if not before.target:IsDescendantOf(game) or before.target.Parent ~= before.parent or before.target.Name ~= before.name then
            return false, "An object was renamed, removed or reparented. Preview again."
        end
        proposed[before.target] = entry.after
    end
    local children, count = {}, 0
    for _, entry in ipairs(plan) do
        local parent = entry.before.parent
        if not children[parent] then
            children[parent] = parent:GetChildren()
            count = count + #children[parent]
            if count > 10000 then return false, "The sibling scope grew too large. Preview again." end
        end
        for _, sibling in ipairs(children[parent]) do
            if sibling ~= entry.before.target and (proposed[sibling] or sibling.Name) == entry.after then
                return false, "A sibling now uses a proposed name. Preview again."
            end
        end
    end
    return true
end

function Adapter.write(entry)
    entry.before.target.Name = entry.after
end

return Adapter
