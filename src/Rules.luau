local Rules = {}

function Rules.plan(rows, siblings, options)
    assert(#rows > 0 and #rows <= 500, "Select between 1 and 500 objects.")
    assert(type(options.template) == "string" and #options.template <= 100, "Template must be at most 100 bytes.")
    local literal = options.template:gsub("{name}", ""):gsub("{n}", "")
    assert(not literal:find("[{}]"), "Only {name} and {n} are supported. Literal braces are not supported.")
    assert(type(options.start) == "number" and options.start % 1 == 0 and options.start >= 0 and options.start + #rows <= 1000001, "Start must be a whole number; the last number cannot exceed 1000000.")
    assert(type(options.padding) == "number" and options.padding % 1 == 0 and options.padding >= 1 and options.padding <= 6, "Number padding must be from 1 to 6.")
    local ordered = table.clone(rows)
    table.sort(ordered, function(a, b)
        if a.path == b.path then return a.index < b.index end
        return a.path < b.path
    end)
    local proposed, selected, plan = {}, {}, {}
    for index, row in ipairs(ordered) do
        local number = string.format("%0" .. tostring(options.padding) .. "d", options.start + index - 1)
        local name = options.template:gsub("{([a-z]+)}", function(token)
            return if token == "name" then row.name else number
        end)
        assert(#name > 0 and #name <= 100 and name:match("%S") and not name:find("[%c]") and utf8.len(name), "A resulting name is blank, invalid UTF-8, contains control characters or exceeds 100 bytes.")
        proposed[row.target] = name
        selected[row.target] = true
        if name ~= row.name then table.insert(plan, { before = row, after = name }) end
    end
    for _, row in ipairs(ordered) do
        for _, sibling in ipairs(siblings) do
            if sibling.parent == row.parent and sibling.target ~= row.target then
                local other = if selected[sibling.target] then proposed[sibling.target] else sibling.name
                assert(proposed[row.target] ~= other, "A resulting name conflicts with a sibling: " .. proposed[row.target])
            end
        end
    end
    return plan
end

return Rules
