package.path = package.path .. ";lua/?.lua"
local ConfirmDeleteScreen = require("confirm_delete_screen")

local function make_screen(width, height)
    local mock = { writes = {} }
    mock.write = function(_, y, text) mock.writes[y] = text end
    mock.get_size = function() return width, height end
    return mock
end

describe("ConfirmDeleteScreen:view", function()
    before_each(function()
        _G.screen = make_screen(80, 10)
    end)

    after_each(function()
        _G.screen = nil
    end)

    it("下敷きとしてファイル一覧を描画する", function()
        local data = {
            display = { width = 80, height = 10 },
            message = "",
            active_pane = 1,
            panes = {
                {
                    cwd = "/root", cursor = 1,
                    files = { { name = "a.txt", is_dir = false, size = 1, modified = "", perm = "rw-r--r--" } },
                },
            },
        }
        ConfirmDeleteScreen.new(data.panes[1].files[1]):view(data)
        assert.equals("fm  /root", screen.writes[0])
    end)

    it("フッター行に確認メッセージを重ねて表示する", function()
        local data = {
            display = { width = 80, height = 10 },
            message = "",
            active_pane = 1,
            panes = { { cwd = "/root", cursor = 1, files = {} } },
        }
        local target = { name = "a.txt", is_dir = false }
        ConfirmDeleteScreen.new(target):view(data)
        assert.is_not_nil(screen.writes[9]:find('"a.txt" を削除しますか？', 1, true))
    end)

    it("確認メッセージが下敷きのフッター文字列より短くても、末尾に元の文字列が残らない", function()
        local data = {
            display = { width = 80, height = 10 },
            message = "",
            active_pane = 1,
            panes = { { cwd = "/root", cursor = 1, files = {} } },
        }
        local target = { name = "a.txt", is_dir = false }
        ConfirmDeleteScreen.new(target):view(data)
        assert.is_nil(screen.writes[9]:find("q:終了", 1, true))
    end)
end)

describe("ConfirmDeleteScreen:command_mapper", function()
    it("yはdeleteとtargetを含むargsを返す", function()
        local target = { name = "a.txt", is_dir = false }
        local view = ConfirmDeleteScreen.new(target)
        local command_name, args = view:command_mapper("y")
        assert.equals("delete", command_name)
        assert.equals(target, args.target)
    end)

    it("nはcancelを返す", function()
        local view = ConfirmDeleteScreen.new({ name = "a.txt" })
        assert.equals("cancel", view:command_mapper("n"))
    end)

    it("escapeはcancelを返す", function()
        local view = ConfirmDeleteScreen.new({ name = "a.txt" })
        assert.equals("cancel", view:command_mapper("escape"))
    end)

    it("対応しないキーはnilを返す", function()
        local view = ConfirmDeleteScreen.new({ name = "a.txt" })
        assert.is_nil(view:command_mapper("x"))
    end)
end)
