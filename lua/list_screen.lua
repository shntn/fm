local Screen = require("screen")
local template = require("template")
local utf8width = require("utf8width")

local NAME_WIDTH = 40

-- カーソル行の反転表示に使うエスケープシーケンス
local CURSOR_ON = "\27[7m"
local CURSOR_OFF = "\27[0m"

local ListScreen = setmetatable({}, { __index = Screen })
ListScreen.__index = ListScreen

function ListScreen.new()
    local self = Screen.new()
    return setmetatable(self, ListScreen)
end

-- nameの拡張子を返す。拡張子がない場合（.gitignoreのようなドットファイルを含む）はnilを返す
local function file_extension(name)
    local base, ext = name:match("^(.+)%.([^.]+)$")
    if base and base ~= "" then
        return ext
    end
    return nil
end

-- nameの表示幅がmax_widthを超える場合、拡張子は残したまま手前を省略記号(…)に置き換える
local function truncate_name(name, max_width)
    if utf8width.width(name) <= max_width then
        return name
    end
    local ext = file_extension(name)
    if not ext then
        return utf8width.truncate(name, max_width)
    end
    local suffix = "." .. ext
    local base = name:sub(1, #name - #ext - 1)
    local budget = math.max(max_width - utf8width.width(suffix), 0)
    return utf8width.truncate(base, budget) .. suffix
end

-- バイト数をK/M/G/T単位の人間可読な文字列に変換する（ls -lhと同様の書式）
local function format_size(bytes)
    local units = { "", "K", "M", "G", "T" }
    local value = bytes
    local unit_index = 1
    while value >= 1024 and unit_index < #units do
        value = value / 1024
        unit_index = unit_index + 1
    end
    if unit_index == 1 then
        return tostring(value)
    end
    return string.format("%.1f%s", value, units[unit_index])
end

-- ファイル一覧表示用に、切り詰め・ディレクトリの'/'付与を行った名前を返す
local function display_name(f)
    if f.is_dir then
        return truncate_name(f.name, NAME_WIDTH - 1) .. "/"
    end
    return truncate_name(f.name, NAME_WIDTH)
end

-- カーソルが含まれるページの先頭インデックス(0始まり)を返す
local function page_offset(cursor, list_h)
    return math.floor((cursor - 1) / list_h) * list_h
end

function ListScreen:view(data) -- luacheck: ignore
    local pane = data.panes[data.active_pane]
    local list_h = data.display.height - 2 -- ヘッダー1行 + フッター1行
    local offset = page_offset(pane.cursor, list_h)

    screen.write(0, 0, "fm  " .. pane.cwd)

    for r = 0, list_h - 1 do
        local index = offset + r + 1
        local f = pane.files[index]
        if f then
            local line = template.render("{name:40}  {perm:9}  {size:8:right}  {modified:19}", {
                name = display_name(f),
                perm = f.perm,
                size = format_size(f.size),
                modified = f.modified,
            })
            if index == pane.cursor then
                line = CURSOR_ON .. line .. CURSOR_OFF
            end
            screen.write(0, r + 1, line)
        end
    end

    local footer = data.message ~= "" and data.message
        or "j/down:↓  k/up:↑  enter:開く  backspace:親へ  d:削除  .:隠しファイル  q:終了"
    screen.write(0, data.display.height - 1, footer)
end

function ListScreen:command_mapper(key) -- luacheck: ignore
    if key == "j" or key == "down" then
        return "cursor_down"
    elseif key == "k" or key == "up" then
        return "cursor_up"
    elseif key == "enter" then
        return "open_selected"
    elseif key == "backspace" then
        return "go_to_parent"
    elseif key == "." then
        return "toggle_hidden"
    elseif key == "d" then
        return "confirm_delete"
    elseif key == "q" or key == "escape" then
        return "quit"
    end
    return nil
end

return ListScreen
