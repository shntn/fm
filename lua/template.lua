local utf8width = require("utf8width")

local template = {}

local function pad(value, width, align)
    local len = utf8width.width(value)
    if len >= width then
        return value
    end
    local spaces = string.rep(" ", width - len)
    if align == "right" then
        return spaces .. value
    end
    return value .. spaces
end

function template.render(tmpl, vars)
    return (tmpl:gsub("{(.-)}", function(placeholder)
        local key, width, align = placeholder:match("^([^:]+):(%d+):(%a+)$")
        if not key then
            key, width = placeholder:match("^([^:]+):(%d+)$")
        end
        if not key then
            key = placeholder
        end

        local value = vars[key] or ""

        if width then
            return pad(value, tonumber(width), align)
        end
        return value
    end))
end

return template
