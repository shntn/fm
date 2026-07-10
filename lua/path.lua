local path = {}

function path.parent_dir(p)
    local base = p:match("^(.*)/[^/]+$")
    if not base or base == "" then
        return "/"
    end
    return base
end

function path.last_segment(p)
    return p:match("([^/]+)$")
end

function path.join(base, name)
    if base == "/" then
        return "/" .. name
    end
    return base .. "/" .. name
end

-- .gitignoreのようなドットファイルは拡張子なし(nil)として扱う
function path.extension(name)
    local base, ext = name:match("^(.+)%.([^.]+)$")
    if base and base ~= "" then
        return ext
    end
    return nil
end

function path.strip_extension(name)
    local ext = path.extension(name)
    if not ext then
        return name
    end
    return name:sub(1, #name - #ext - 1)
end

return path
