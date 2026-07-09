package.path = package.path .. ";lua/?.lua"
local ListScreen = require("list_screen")

local function make_screen(width, height)
    local mock = { writes = {} }
    mock.write = function(_, y, text) mock.writes[y] = text end
    mock.get_size = function() return width, height end
    return mock
end

local function make_file(overrides)
    local f = {
        name = "a.txt", is_dir = false, size = 10,
        modified = "2025-01-01 00:00:00", perm = "rw-r--r--",
    }
    for k, v in pairs(overrides or {}) do
        f[k] = v
    end
    return f
end

describe("ListScreen:view", function()
    before_each(function()
        _G.screen = make_screen(80, 10)
    end)

    after_each(function()
        _G.screen = nil
    end)

    it("ヘッダーにカレントディレクトリを表示する", function()
        local data = {
            display = { width = 80, height = 10 },
            active_pane = 1,
            panes = { { cwd = "/root", cursor = 1, files = {} } },
        }
        ListScreen.new():view(data)
        assert.equals("fm  /root", screen.writes[0])
    end)

    it("フッターにキー操作のヘルプを表示する", function()
        local data = {
            display = { width = 80, height = 10 },
            active_pane = 1,
            panes = { { cwd = "/root", cursor = 1, files = {} } },
        }
        ListScreen.new():view(data)
        assert.is_not_nil(screen.writes[9]:find("q:終了", 1, true))
    end)

    it("ファイル名・パーミッション・サイズ・更新日時を表示する", function()
        local data = {
            display = { width = 80, height = 10 },
            active_pane = 1,
            panes = { { cwd = "/root", cursor = 1, files = { make_file() } } },
        }
        ListScreen.new():view(data)
        local line = screen.writes[1]
        assert.is_not_nil(line:find("a.txt", 1, true))
        assert.is_not_nil(line:find("rw-r--r--", 1, true))
        assert.is_not_nil(line:find("10", 1, true))
        assert.is_not_nil(line:find("2025-01-01 00:00:00", 1, true))
    end)

    it("ファイルサイズはK/M/G/T単位の人間可読な形式で表示する", function()
        local data = {
            display = { width = 80, height = 10 },
            active_pane = 1,
            panes = { { cwd = "/root", cursor = 1, files = { make_file({ size = 592919787 }) } } },
        }
        ListScreen.new():view(data)
        assert.is_not_nil(screen.writes[1]:find("565.5M", 1, true))
    end)

    it("カーソル行は反転表示のエスケープシーケンスで囲まれる", function()
        local data = {
            display = { width = 80, height = 10 },
            active_pane = 1,
            panes = { { cwd = "/root", cursor = 1, files = { make_file() } } },
        }
        ListScreen.new():view(data)
        assert.is_not_nil(screen.writes[1]:find("\27[7m", 1, true))
        assert.is_not_nil(screen.writes[1]:find("\27[0m", 1, true))
    end)

    it("カーソルがない行には反転表示のエスケープシーケンスが含まれない", function()
        local data = {
            display = { width = 80, height = 10 },
            active_pane = 1,
            panes = {
                {
                    cwd = "/root",
                    cursor = 1,
                    files = { make_file({ name = "a.txt" }), make_file({ name = "b.txt" }) },
                },
            },
        }
        ListScreen.new():view(data)
        assert.is_nil(screen.writes[2]:find("\27[7m", 1, true))
    end)

    it("ディレクトリ名は末尾に'/'が付く", function()
        local data = {
            display = { width = 80, height = 10 },
            active_pane = 1,
            panes = { { cwd = "/root", cursor = 1, files = { make_file({ name = "sub", is_dir = true }) } } },
        }
        ListScreen.new():view(data)
        assert.is_not_nil(screen.writes[1]:find("sub/", 1, true))
    end)

    it("ファイル名が列幅を超える場合、拡張子を残して省略記号で切り詰める", function()
        local data = {
            display = { width = 80, height = 10 },
            active_pane = 1,
            panes = {
                {
                    cwd = "/root", cursor = 1,
                    files = { make_file({ name = string.rep("a", 50) .. ".pdf" }) },
                },
            },
        }
        ListScreen.new():view(data)
        assert.is_not_nil(screen.writes[1]:find("….pdf", 1, true))
    end)

    it("ファイル数が画面に収まらない場合、ページ単位で表示を切り替える", function()
        _G.screen = make_screen(80, 5) -- list_h = 3
        local files = {
            make_file({ name = "a.txt" }), make_file({ name = "b.txt" }),
            make_file({ name = "c.txt" }), make_file({ name = "d.txt" }),
        }
        local data = {
            display = { width = 80, height = 5 },
            active_pane = 1,
            panes = { { cwd = "/root", cursor = 4, files = files } },
        }
        ListScreen.new():view(data)
        assert.is_not_nil(screen.writes[1]:find("d.txt", 1, true))
    end)
end)

describe("ListScreen:command_mapper", function()
    it("j/downはcursor_downを返す", function()
        local view = ListScreen.new()
        assert.equals("cursor_down", view:command_mapper("j"))
        assert.equals("cursor_down", view:command_mapper("down"))
    end)

    it("k/upはcursor_upを返す", function()
        local view = ListScreen.new()
        assert.equals("cursor_up", view:command_mapper("k"))
        assert.equals("cursor_up", view:command_mapper("up"))
    end)

    it("enterはopen_selectedを返す", function()
        local view = ListScreen.new()
        assert.equals("open_selected", view:command_mapper("enter"))
    end)

    it("backspaceはgo_to_parentを返す", function()
        local view = ListScreen.new()
        assert.equals("go_to_parent", view:command_mapper("backspace"))
    end)

    it("'.'はtoggle_hiddenを返す", function()
        local view = ListScreen.new()
        assert.equals("toggle_hidden", view:command_mapper("."))
    end)

    it("q/escapeはquitを返す", function()
        local view = ListScreen.new()
        assert.equals("quit", view:command_mapper("q"))
        assert.equals("quit", view:command_mapper("escape"))
    end)

    it("対応しないキーはnilを返す", function()
        local view = ListScreen.new()
        assert.is_nil(view:command_mapper("x"))
    end)
end)
