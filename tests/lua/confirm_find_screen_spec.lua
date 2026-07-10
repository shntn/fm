package.path = package.path .. ";lua/?.lua"
local ConfirmFindScreen = require("confirm_find_screen")

describe("ConfirmFindScreen:command_mapper", function()
    it("escape以外のkeyはsearchと、queryを含むargsを返す", function()
        local view = ConfirmFindScreen.new()
        local command_name, args = view:command_mapper("a.txt")
        assert.equals("search", command_name)
        assert.equals("a.txt", args.query)
    end)

    it("空文字のkeyもsearchと、空文字のqueryを含むargsを返す（絞り込み解除に使う）", function()
        local view = ConfirmFindScreen.new()
        local command_name, args = view:command_mapper("")
        assert.equals("search", command_name)
        assert.equals("", args.query)
    end)

    it("escapeはcancelを返す", function()
        local view = ConfirmFindScreen.new()
        local command_name = view:command_mapper("escape")
        assert.equals("cancel", command_name)
    end)
end)
