local layout = require("layout")

local view = {}

view.COLUMNS = {
    n = { field = "files[].name", before = true },
    p = { field = "files[].perm" },
    s = { field = "files[].size", align = "right" },
    d = { field = "files[].modified", after = true },
}

-- 幅width、タグ名keyの #key###...# 形式のタグ文字列を組み立てる
local function tag(key, width)
    return "#" .. key .. string.rep("#", width - #key - 1)
end

view.TMPL = table.concat({
    " fm  {dir}",
    "@" .. "   " .. tag("n", 40) .. "  " .. tag("p", 9)
        .. "  " .. tag("s", 8) .. "  " .. tag("d", 19),
    " j/down:↓  k/up:↑  enter:開く  backspace:親へ  q:終了",
}, "\n")

-- columns内でfieldに一致するキーを返す
local function find_key_by_field(columns, field)
    for key, col in pairs(columns) do
        if col.field == field then
            return key
        end
    end
    return nil
end

-- ファイル名の表示幅は、テンプレート内の#タグの幅をそのまま使う(数値の二重管理を避ける)
view.NAME_WIDTH = layout.tag_width(view.TMPL, find_key_by_field(view.COLUMNS, "files[].name"))

return view
