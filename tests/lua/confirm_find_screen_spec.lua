package.path = package.path .. ";lua/?.lua"
local ConfirmFindScreen = require("confirm_find_screen")

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

describe("ConfirmFindScreen:view", function()
    before_each(function()
        _G.screen = make_screen(80, 10)
    end)

    after_each(function()
        _G.screen = nil
    end)

    it("呼び出し元のスクリーンのviewをそのまま呼ぶ（検索プロンプトはRust側が描画するため何も重ねない）", function()
        local data = {
            display = { width = 80, height = 10 },
            message = "",
            active_pane = 1,
            panes = { { cwd = "/root", cursor = 1, files = {} } },
        }
        local previous = make_previous_screen("footer")
        ConfirmFindScreen.new(previous):view(data)
        assert.equals("fm  /root", screen.writes[0])
        assert.equals("footer", screen.writes[9])
    end)
end)

describe("ConfirmFindScreen:command_mapper", function()
    it("escape以外のkeyはsearchと、query・previous_screenを含むargsを返す", function()
        local previous = make_previous_screen("footer")
        local view = ConfirmFindScreen.new(previous)
        local command_name, args = view:command_mapper("a.txt")
        assert.equals("search", command_name)
        assert.equals("a.txt", args.query)
        assert.equals(previous, args.previous_screen)
    end)

    it("空文字のkeyもsearchと、空文字のqueryを含むargsを返す（絞り込み解除に使う）", function()
        local previous = make_previous_screen("footer")
        local view = ConfirmFindScreen.new(previous)
        local command_name, args = view:command_mapper("")
        assert.equals("search", command_name)
        assert.equals("", args.query)
    end)

    it("escapeはcancelと、previous_screenを含むargsを返す", function()
        local previous = make_previous_screen("footer")
        local view = ConfirmFindScreen.new(previous)
        local command_name, args = view:command_mapper("escape")
        assert.equals("cancel", command_name)
        assert.equals(previous, args.previous_screen)
    end)
end)
