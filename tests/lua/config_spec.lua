package.path = package.path .. ";lua/?.lua"

-- toml.parseはRust側が提供する関数のため、busted実行環境には実体がない。
-- 渡されたテキストをそのまま保持するだけのモックに差し替えてテストする
local function make_toml(invalid_text)
    return {
        parse = function(text)
            if invalid_text and text == invalid_text then
                return nil, "invalid toml"
            end
            return { source = text }
        end,
    }
end

describe("config.load", function()
    local original_getenv = os.getenv

    before_each(function()
        _G.fs = { read_file = function() return nil, "not found" end }
        _G.toml = make_toml()
    end)

    after_each(function()
        os.getenv = original_getenv
        _G.fs = nil
        _G.toml = nil
        package.loaded["config"] = nil
    end)

    it("FM_CONFIG環境変数が設定されている場合、そのパスのファイルを読み込む", function()
        os.getenv = function(name)
            if name == "FM_CONFIG" then return "/custom/path.toml" end
            return nil
        end
        _G.fs.read_file = function(path)
            assert.equals("/custom/path.toml", path)
            return "custom text"
        end

        local config = require("config")
        assert.equals("custom text", config.load().source)
    end)

    it("FM_CONFIG未設定の場合、HOME配下の~/.config/fm/config.tomlを読み込む", function()
        os.getenv = function(name)
            if name == "HOME" then return "/home/test" end
            return nil
        end
        _G.fs.read_file = function(path)
            assert.equals("/home/test/.config/fm/config.toml", path)
            return "home text"
        end

        local config = require("config")
        assert.equals("home text", config.load().source)
    end)

    it("設定ファイルが存在しない場合、内蔵の既定値を使う", function()
        os.getenv = function(name)
            if name == "HOME" then return "/home/test" end
            return nil
        end
        _G.fs.read_file = function() return nil, "not found" end

        local config = require("config")
        assert.is_not_nil(config.load().source:find("unzip", 1, true))
    end)

    it("設定ファイルの内容が不正なTOMLの場合、内蔵の既定値にフォールバックする", function()
        os.getenv = function(name)
            if name == "HOME" then return "/home/test" end
            return nil
        end
        _G.fs.read_file = function() return "broken toml" end
        _G.toml = make_toml("broken toml")

        local config = require("config")
        assert.is_not_nil(config.load().source:find("unzip", 1, true))
    end)
end)
