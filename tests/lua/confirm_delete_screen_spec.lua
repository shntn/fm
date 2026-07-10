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

    local function make_data()
        return {
            display = { width = 80, height = 10 },
            message = "",
            active_pane = 1,
            panes = { { cwd = "/root", cursor = 1, files = {} } },
        }
    end

    it("フッター行に確認メッセージを表示する", function()
        local data = make_data()
        local target = { name = "a.txt", is_dir = false }
        ConfirmDeleteScreen.new(target):view(data)
        assert.is_not_nil(screen.writes[9]:find('"a.txt" を削除しますか？', 1, true))
    end)

    it("確認メッセージを画面幅いっぱいにパディングし、末尾に前フレームの表示が残らないようにする", function()
        local data = make_data()
        local target = { name = "a.txt", is_dir = false }
        ConfirmDeleteScreen.new(target):view(data)
        assert.is_not_nil(screen.writes[9]:find(" $"))
    end)
end)

describe("ConfirmDeleteScreen:command_mapper", function()
    it("yはdeleteと、targetを含むargsを返す", function()
        local target = { name = "a.txt", is_dir = false }
        local view = ConfirmDeleteScreen.new(target)
        local command_name, args = view:command_mapper("y")
        assert.equals("delete", command_name)
        assert.equals(target, args.target)
    end)

    it("nはcancelを返す", function()
        local view = ConfirmDeleteScreen.new({ name = "a.txt" })
        local command_name = view:command_mapper("n")
        assert.equals("cancel", command_name)
    end)

    it("escapeはcancelを返す", function()
        local view = ConfirmDeleteScreen.new({ name = "a.txt" })
        local command_name = view:command_mapper("escape")
        assert.equals("cancel", command_name)
    end)

    it("対応しないキーはnilを返す", function()
        local view = ConfirmDeleteScreen.new({ name = "a.txt" })
        assert.is_nil(view:command_mapper("x"))
    end)
end)
