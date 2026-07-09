package.path = package.path .. ";lua/?.lua"
local ConfirmDeleteScreen = require("confirm_delete_screen")

local function make_screen(width, height)
    local mock = { writes = {} }
    mock.write = function(_, y, text) mock.writes[y] = text end
    mock.get_size = function() return width, height end
    return mock
end

-- 呼び出し元のスクリーン役のスタブ。ヘッダーとフッターを書くだけ
local function make_previous_screen(footer_text)
    return {
        view = function(_, data)
            screen.write(0, 0, "fm  " .. data.panes[data.active_pane].cwd)
            screen.write(0, data.display.height - 1, footer_text)
        end,
    }
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

    it("下敷きとして呼び出し元のスクリーンのviewを呼ぶ", function()
        local data = make_data()
        local previous = make_previous_screen("footer")
        ConfirmDeleteScreen.new({ name = "a.txt" }, previous):view(data)
        assert.equals("fm  /root", screen.writes[0])
    end)

    it("フッター行に確認メッセージを重ねて表示する", function()
        local data = make_data()
        local previous = make_previous_screen("footer")
        local target = { name = "a.txt", is_dir = false }
        ConfirmDeleteScreen.new(target, previous):view(data)
        assert.is_not_nil(screen.writes[9]:find('"a.txt" を削除しますか？', 1, true))
    end)

    it("確認メッセージが下敷きのフッター文字列より短くても、末尾に元の文字列が残らない", function()
        local data = make_data()
        local previous = make_previous_screen("j/down:↓  k/up:↑  q:終了")
        local target = { name = "a.txt", is_dir = false }
        ConfirmDeleteScreen.new(target, previous):view(data)
        assert.is_nil(screen.writes[9]:find("q:終了", 1, true))
    end)
end)

describe("ConfirmDeleteScreen:command_mapper", function()
    it("yはdeleteと、target・previous_screenを含むargsを返す", function()
        local target = { name = "a.txt", is_dir = false }
        local previous = make_previous_screen("footer")
        local view = ConfirmDeleteScreen.new(target, previous)
        local command_name, args = view:command_mapper("y")
        assert.equals("delete", command_name)
        assert.equals(target, args.target)
        assert.equals(previous, args.previous_screen)
    end)

    it("nはcancelと、previous_screenを含むargsを返す", function()
        local previous = make_previous_screen("footer")
        local view = ConfirmDeleteScreen.new({ name = "a.txt" }, previous)
        local command_name, args = view:command_mapper("n")
        assert.equals("cancel", command_name)
        assert.equals(previous, args.previous_screen)
    end)

    it("escapeはcancelを返す", function()
        local view = ConfirmDeleteScreen.new({ name = "a.txt" }, make_previous_screen("footer"))
        local command_name = view:command_mapper("escape")
        assert.equals("cancel", command_name)
    end)

    it("対応しないキーはnilを返す", function()
        local view = ConfirmDeleteScreen.new({ name = "a.txt" }, make_previous_screen("footer"))
        assert.is_nil(view:command_mapper("x"))
    end)
end)
