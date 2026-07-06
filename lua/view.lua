local view = {}

view.NAME_WIDTH = 40

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
    "@" .. "   " .. tag("n", view.NAME_WIDTH) .. "  " .. tag("p", 9)
        .. "  " .. tag("s", 8) .. "  " .. tag("d", 19),
    " j/down:↓  k/up:↑  enter:開く  backspace:親へ  q:終了",
}, "\n")

return view
