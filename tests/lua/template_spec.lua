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

    it("leftを指定した場合は左詰めで埋める", function()
        local result = template.render("{name:10:left}", { name = "abc" })
        assert.equals("abc       ", result)
    end)

    it("左詰めで値が幅を超える場合は末尾を切り詰める", function()
        local result = template.render("{name:5}", { name = "abcdefgh" })
        assert.equals("abcde", result)
    end)

    it("右詰めで値が幅を超える場合は先頭を切り詰める", function()
        local result = template.render("{size:5:right}", { size = "abcdefgh" })
        assert.equals("defgh", result)
    end)

    it("全角文字を含む値は表示幅を基準にパディングする", function()
        local result = template.render("{name:6}", { name = "あい" })
        assert.equals("あい  ", result)
    end)

    it("全角文字を含む値が幅を超える場合は表示幅を基準に末尾を切り詰める", function()
        local result = template.render("{name:5}", { name = "漢字漢字" })
        assert.equals("漢字", result)
    end)

    it("角括弧とドットを含むキー（layout.expandの出力形式）を展開できる", function()
        local result = template.render("{files[0].name:10}", { ["files[0].name"] = "README.md" })
        assert.equals("README.md ", result)
    end)

    it("角括弧とドットを含むキーでrightを指定した場合は右詰めで展開できる", function()
        local result = template.render("{files[0].size:6:right}", { ["files[0].size"] = "1234" })
        assert.equals("  1234", result)
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
