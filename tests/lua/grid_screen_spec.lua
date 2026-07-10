package.path = package.path .. ";lua/?.lua"
local GridScreen = require("grid_screen")

local function make_screen(width, height)
    local mock = { writes = {} }
    mock.clear = function() end
    mock.write = function(_, y, text) mock.writes[y] = text end
    mock.get_size = function() return width, height end
    return mock
end

local function make_file(name, overrides)
    local f = { name = name, is_dir = false, size = 1, modified = "", perm = "rw-r--r--" }
    for k, v in pairs(overrides or {}) do
        f[k] = v
    end
    return f
end

describe("GridScreen:view", function()
    before_each(function()
        _G.screen = make_screen(80, 6) -- list_h = 4
    end)

    after_each(function()
        _G.screen = nil
    end)

    it("ヘッダーにカレントディレクトリを表示する", function()
        local data = {
            display = { width = 80, height = 6 },
            message = "",
            active_pane = 1,
            panes = { { cwd = "/root", cursor = 1, files = {} } },
        }
        GridScreen.new():view(data)
        assert.equals("fm  /root", screen.writes[0])
    end)

    it("list_hを超えた分は右側の列に表示される", function()
        -- list_h=4なので、5番目のファイルは右列の1行目(画面2行目)に入る
        local files = {}
        for i = 1, 5 do
            files[i] = make_file(i .. ".txt")
        end
        local data = {
            display = { width = 80, height = 6 },
            message = "",
            active_pane = 1,
            panes = { { cwd = "/root", cursor = 1, files = files } },
        }
        GridScreen.new():view(data)
        assert.is_not_nil(screen.writes[1]:find("1.txt", 1, true))
        assert.is_not_nil(screen.writes[1]:find("5.txt", 1, true))
    end)

    it("カーソル行は反転表示のエスケープシーケンスで囲まれる", function()
        local files = { make_file("a.txt") }
        local data = {
            display = { width = 80, height = 6 },
            message = "",
            active_pane = 1,
            panes = { { cwd = "/root", cursor = 1, files = files } },
        }
        GridScreen.new():view(data)
        assert.is_not_nil(screen.writes[1]:find("\27[7m", 1, true))
    end)

    it("フッターにキー操作のヘルプを表示する", function()
        local data = {
            display = { width = 80, height = 6 },
            message = "",
            active_pane = 1,
            panes = { { cwd = "/root", cursor = 1, files = {} } },
        }
        GridScreen.new():view(data)
        assert.is_not_nil(screen.writes[5]:find("v:表示切替", 1, true))
    end)

    it("messageがあればフッターにそれを表示する", function()
        local data = {
            display = { width = 80, height = 6 },
            message = "エラーが発生しました",
            active_pane = 1,
            panes = { { cwd = "/root", cursor = 1, files = {} } },
        }
        GridScreen.new():view(data)
        assert.is_not_nil(screen.writes[5]:find("エラーが発生しました", 1, true))
    end)
end)

describe("GridScreen:command_mapper", function()
    it("ListScreenと同じキー対応を継承する(j→cursor_down)", function()
        local view = GridScreen.new()
        assert.equals("cursor_down", view:command_mapper("j"))
    end)

    it("vはtoggle_layoutを返す(ListScreenから継承)", function()
        local view = GridScreen.new()
        assert.equals("toggle_layout", view:command_mapper("v"))
    end)
end)
