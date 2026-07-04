package.path = package.path .. ";lua/?.lua"
local template = require("template")

describe("template.render", function()
    it("プレースホルダを対応する値に置き換える", function()
        local result = template.render("{name}", { name = "README.md" })
        assert.equals("README.md", result)
    end)

    it("連想配列にキーが存在しない場合は空文字列に展開する", function()
        local result = template.render("{missing}", {})
        assert.equals("", result)
    end)

    it("幅指定がある場合は左詰めで埋める", function()
        local result = template.render("{name:10}", { name = "abc" })
        assert.equals("abc       ", result)
    end)

    it("rightを指定した場合は右詰めで埋める", function()
        local result = template.render("{size:8:right}", { size = "1234" })
        assert.equals("    1234", result)
    end)

    it("値が幅を超える場合はそのまま展開する", function()
        local result = template.render("{name:5}", { name = "abcdefgh" })
        assert.equals("abcdefgh", result)
    end)

    it("複数のプレースホルダをまとめて展開する", function()
        local result = template.render("{name:20}  {size:8:right}  {date}", {
            name = "README.md",
            size = "1234",
            date = "2025-06-27 10:00:00",
        })
        assert.equals("README.md                 1234  2025-06-27 10:00:00", result)
    end)
end)
