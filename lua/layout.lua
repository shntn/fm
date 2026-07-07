local layout = {}

local function split_lines(tmpl)
    local lines = {}
    for line in (tmpl .. "\n"):gmatch("(.-)\n") do
        table.insert(lines, line)
    end
    return lines
end

local function parse_segments(content)
    local segments = {}
    local pos = 1
    while true do
        local s, e = content:find("#[%a%d]+#*", pos)
        if not s then
            if pos <= #content then
                table.insert(segments, { type = "literal", text = content:sub(pos) })
            end
            break
        end
        if s > pos then
            table.insert(segments, { type = "literal", text = content:sub(pos, s - 1) })
        end
        local key = content:sub(s, e):match("^#([%a%d]+)")
        table.insert(segments, { type = "tag", key = key, width = e - s + 1 })
        pos = e + 1
    end
    return segments
end

local function parse_lines(tmpl)
    local lines_data = {}
    local repeat_count_raw = 0
    for _, line in ipairs(split_lines(tmpl)) do
        local marker = line:sub(1, 1)
        local is_repeat = marker == "@"
        if is_repeat then
            repeat_count_raw = repeat_count_raw + 1
        end
        table.insert(lines_data, {
            is_repeat = is_repeat,
            segments = parse_segments(line:sub(2)),
        })
    end
    if repeat_count_raw > 1 then
        error("繰り返し行は1テンプレートに1行まで指定できます")
    end
    return lines_data
end

local function line_tag_counts(segments)
    local counts = {}
    for _, seg in ipairs(segments) do
        if seg.type == "tag" then
            counts[seg.key] = (counts[seg.key] or 0) + 1
        end
    end
    return counts
end

local function build_tag_stats(lines_data, normal_rows_total, repeat_index, height, columns)
    local lines_with_tag = {}
    for i, ld in ipairs(lines_data) do
        for key, cnt in pairs(line_tag_counts(ld.segments)) do
            lines_with_tag[key] = lines_with_tag[key] or {}
            lines_with_tag[key][i] = cnt
        end
    end

    local repeat_count = repeat_index and (height - normal_rows_total) or 0

    local stats = {}
    for key, per_line in pairs(lines_with_tag) do
        local c = nil
        for _, cnt in pairs(per_line) do
            if c == nil then
                c = cnt
            elseif c ~= cnt then
                error("配列グループ内で同名タグ '" .. key .. "' の出現回数が行によって異なります")
            end
        end

        local r_for_line = {}
        local k = 0
        for i = 1, #lines_data do
            if per_line[i] and not lines_data[i].is_repeat then
                r_for_line[i] = k
                k = k + 1
            end
        end

        local repeat_contains = repeat_index ~= nil and per_line[repeat_index] ~= nil
        local total_r = k + (repeat_contains and repeat_count or 0)

        stats[key] = {
            c = c,
            r = total_r,
            dir = (columns[key] and columns[key].dir) or "horizontal",
            r_for_line = r_for_line,
            repeat_base_r = k,
        }
    end

    return stats, repeat_count
end

local function count_flex_tags(lines_data, columns)
    local count = 0
    for _, ld in ipairs(lines_data) do
        for _, seg in ipairs(ld.segments) do
            if seg.type == "tag" then
                local col = columns[seg.key]
                if col and col.flex then
                    count = count + 1
                end
            end
        end
    end
    return count
end

local function resolved_width(seg, col, width, flex_tag_count)
    if not col.flex then
        return seg.width
    end
    return seg.width + math.floor((width - 80) / flex_tag_count)
end

local function render_line(segments, columns, tag_stats, width, flex_tag_count, line_index, expand_index)
    local occurrence = {}
    local parts = {}

    for _, seg in ipairs(segments) do
        if seg.type == "literal" then
            table.insert(parts, seg.text)
        else
            local col = columns[seg.key]
            if not col then
                error("未定義のカラムです: " .. seg.key)
            end

            local c = occurrence[seg.key] or 0
            occurrence[seg.key] = c + 1

            local w = resolved_width(seg, col, width, flex_tag_count)
            local suffix = col.align == "right" and ":right" or ""

            local prefix, field_key = col.field:match("^(.-)%[%]%.(.+)$")
            if prefix then
                local st = tag_stats[seg.key]
                local r = line_index and st.r_for_line[line_index] or (st.repeat_base_r + expand_index)
                local idx = st.dir == "vertical" and (r + c * st.r) or (r * st.c + c)
                if col.before then
                    table.insert(parts, "{" .. prefix .. "[" .. idx .. "].before}")
                end
                table.insert(parts, "{" .. prefix .. "[" .. idx .. "]." .. field_key .. ":" .. w .. suffix .. "}")
                if col.after then
                    table.insert(parts, "{" .. prefix .. "[" .. idx .. "].after}")
                end
            else
                if col.before then
                    table.insert(parts, "{before}")
                end
                table.insert(parts, "{" .. col.field .. ":" .. w .. suffix .. "}")
                if col.after then
                    table.insert(parts, "{after}")
                end
            end
        end
    end

    return table.concat(parts)
end

-- tmpl内でキーkeyのタグの幅(#の個数)を返す。見つからない場合はnil
function layout.tag_width(tmpl, key)
    for _, line in ipairs(parse_lines(tmpl)) do
        for _, seg in ipairs(line.segments) do
            if seg.type == "tag" and seg.key == key then
                return seg.width
            end
        end
    end
    return nil
end

function layout.expand(tmpl, columns, width, height)
    local lines_data = parse_lines(tmpl)

    local normal_rows_total = 0
    local repeat_index = nil
    for i, ld in ipairs(lines_data) do
        if ld.is_repeat then
            repeat_index = i
        else
            normal_rows_total = normal_rows_total + 1
        end
    end

    local tag_stats, repeat_count = build_tag_stats(lines_data, normal_rows_total, repeat_index, height, columns)
    local flex_tag_count = count_flex_tags(lines_data, columns)

    local lines = {}
    for i, ld in ipairs(lines_data) do
        if ld.is_repeat then
            for p = 0, repeat_count - 1 do
                table.insert(lines, render_line(ld.segments, columns, tag_stats, width, flex_tag_count, nil, p))
            end
        else
            table.insert(lines, render_line(ld.segments, columns, tag_stats, width, flex_tag_count, i, nil))
        end
    end

    return lines
end

return layout
