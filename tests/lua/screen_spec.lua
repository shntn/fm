package.path = package.path .. ";lua/?.lua"
local Screen = require("screen")

describe("Screen", function()
    it("既定のviewは何もせず、エラーにもならない", function()
        local screen = Screen.new()
        assert.has_no.errors(function()
            screen:view({})
        end)
    end)

    it("既定のcommand_mapperは常にnilを返す", function()
        local screen = Screen.new()
        assert.is_nil(screen:command_mapper("j"))
    end)
end)

describe("Screenの継承", function()
    local function make_list_view()
        local ListView = setmetatable({}, { __index = Screen })
        ListView.__index = ListView

        function ListView.new()
            local self = Screen.new()
            return setmetatable(self, ListView)
        end

        function ListView:command_mapper(key) -- luacheck: ignore
            if key == "j" then return "cursor_down" end
            return nil
        end

        return ListView
    end

    it("上書きしたcommand_mapperが呼ばれる", function()
        local ListView = make_list_view()
        local view = ListView.new()
        assert.equals("cursor_down", view:command_mapper("j"))
    end)

    it("上書きしていないviewは基底のものが呼ばれ、エラーにならない", function()
        local ListView = make_list_view()
        local view = ListView.new()
        assert.has_no.errors(function()
            view:view({})
        end)
    end)

    it("上書きしていないキーに対するcommand_mapperは基底と同じくnilを返す", function()
        local ListView = make_list_view()
        local view = ListView.new()
        assert.is_nil(view:command_mapper("x"))
    end)
end)
