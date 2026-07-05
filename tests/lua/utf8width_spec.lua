package.path = package.path .. ";lua/?.lua"
local utf8width = require("utf8width")

describe("utf8width.width", function()
    after_each(function()
        utf8width.set_ambiguous_width(1)
    end)

    it("ASCII文字は1文字につき幅1として数える", function()
        assert.equals(5, utf8width.width("hello"))
    end)

    it("ひらがなは1文字につき幅2として数える", function()
        assert.equals(6, utf8width.width("あいう"))
    end)

    it("漢字は1文字につき幅2として数える", function()
        assert.equals(4, utf8width.width("日本"))
    end)

    it("半角と全角が混在する文字列は幅を合計して返す", function()
        assert.equals(4, utf8width.width("aあb"))
    end)

    it("Ambiguous文字はデフォルトで幅1として数える", function()
        assert.equals(2, utf8width.width("αβ"))
    end)

    it("set_ambiguous_widthで幅2に切り替えられる", function()
        utf8width.set_ambiguous_width(2)
        assert.equals(4, utf8width.width("αβ"))
    end)

    it("emダッシュはAmbiguous文字としてデフォルトで幅1として数える", function()
        assert.equals(1, utf8width.width("—"))
    end)

    it("省略記号(…)はAmbiguous文字としてデフォルトで幅1として数える", function()
        assert.equals(1, utf8width.width("…"))
    end)

    it("不正なUTF-8バイト列の場合はバイト長にフォールバックする", function()
        local invalid = string.char(0xff, 0xff)
        assert.equals(2, utf8width.width(invalid))
    end)

    it("結合文字（NFD分解された濁点）は幅0として数える", function()
        -- macOSはファイル名をNFDで保存するため「プ」は「フ」+結合半濁点に分解される
        local nfd_pu = "フ" .. utf8.char(0x309A)
        assert.equals(utf8width.width("プ"), utf8width.width(nfd_pu))
    end)
end)

describe("utf8width.truncate", function()
    it("表示幅内に収まる文字列はそのまま返す", function()
        assert.equals("abc", utf8width.truncate("abc", 5))
    end)

    it("表示幅を超える文字列は末尾を省略記号に置き換える", function()
        assert.equals("abcd…", utf8width.truncate("abcdefghij", 5))
    end)

    it("全角文字を含む文字列も表示幅を基準に切り詰める", function()
        assert.equals("あいうえ…", utf8width.truncate("あいうえおかきくけこ", 10))
    end)
end)
