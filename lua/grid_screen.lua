local Screen = require("screen")
local ListScreen = require("list_screen")
local template = require("template")
local utf8width = require("utf8width")

local COLUMN_WIDTH = 38

-- カーソル行の反転表示に使うエスケープシーケンス
local CURSOR_ON = "\27[7m"
local CURSOR_OFF = "\27[0m"

-- ファイル一覧を2段組で表示するスクリーン。command_mapperはListScreenのものをそのまま継承する
-- (カーソル移動・削除・隠しファイル切替などのキー操作は表示レイアウトに依存しないため)
local GridScreen = setmetatable({}, { __index = ListScreen })
GridScreen.__index = GridScreen

function GridScreen.new()
    local self = Screen.new()
    return setmetatable(self, GridScreen)
end

-- 名前の表示幅がmax_widthを超える場合、省略記号(…)に置き換える。ディレクトリは末尾に'/'を付ける
local function display_name(f, max_width)
    local name = f.is_dir and (f.name .. "/") or f.name
    return utf8width.truncate(name, max_width)
end

-- 1列分(indexが指すファイル、なければ空欄)の表示テキストを組み立てる
local function column_text(pane, index)
    local f = pane.files[index]
    local text = template.render("{name:" .. COLUMN_WIDTH .. "}", {
        name = f and display_name(f, COLUMN_WIDTH) or "",
    })
    if f and index == pane.cursor then
        text = CURSOR_ON .. text .. CURSOR_OFF
    end
    return text
end

function GridScreen:view(data) -- luacheck: ignore
    local pane = data.panes[data.active_pane]
    local list_h = data.display.height - 2 -- ヘッダー1行 + フッター1行

    screen.write(0, 0, "fm  " .. pane.cwd)

    for r = 0, list_h - 1 do
        local left_index = r + 1
        local right_index = r + list_h + 1
        screen.write(0, r + 1, column_text(pane, left_index) .. "  " .. column_text(pane, right_index))
    end

    local footer = data.message ~= "" and data.message
        or "j/down:↓  k/up:↑  enter:開く  backspace:親へ  d:削除  .:隠しファイル  v:表示切替  q:終了"
    screen.write(0, data.display.height - 1, footer)
end

return GridScreen
