package.path = package.path .. ";lua/?.lua"
local layout = require("layout")

describe("layout.expand", function()
    describe("通常行の変換", function()
        it("タグを含まないリテラル文字列をそのまま出力する", function()
            local lines = layout.expand(" hello world", {}, 80, 1)
            assert.equals("hello world", lines[1])
        end)

        it("タグを{field:width}形式に変換する", function()
            local columns = { id = { field = "name" } }
            local lines = layout.expand(" #id##", columns, 80, 1)
            assert.equals("{name:5}", lines[1])
        end)

        it("align=rightのタグを{field:width:right}形式に変換する", function()
            local columns = { id = { field = "size", align = "right" } }
            local lines = layout.expand(" #id##", columns, 80, 1)
            assert.equals("{size:5:right}", lines[1])
        end)
    end)

    describe("flex幅の計算", function()
        it("flexタグが1つの場合、基準幅に(画面幅-80)を加算する", function()
            local columns = { id = { field = "name", flex = true } }
            local lines = layout.expand(" #id##", columns, 100, 1)
            assert.equals("{name:25}", lines[1])
        end)

        it("flexタグが複数の場合、(画面幅-80)を均等割りして加算する", function()
            local columns = {
                a = { field = "name", flex = true },
                b = { field = "ext", flex = true },
            }
            local lines = layout.expand(" #a##  #b##", columns, 100, 1)
            assert.equals("{name:14}  {ext:14}", lines[1])
        end)
    end)

    describe("繰り返し行の展開", function()
        it("繰り返し件数を画面高さ-通常行数から自動計算して展開する", function()
            local tmpl = " header\n@#id##\n footer"
            local columns = { id = { field = "files[].name" } }
            local lines = layout.expand(tmpl, columns, 80, 5)
            assert.same({
                "header",
                "{files[0].name:5}",
                "{files[1].name:5}",
                "{files[2].name:5}",
                "footer",
            }, lines)
        end)

        it("繰り返し行が複数あるとエラーになる", function()
            local tmpl = "@#a##\n@#b##"
            local columns = { a = { field = "x" }, b = { field = "y" } }
            assert.has_error(function()
                layout.expand(tmpl, columns, 80, 3)
            end)
        end)
    end)

    describe("配列グループのインデックス計算", function()
        it("dir=verticalの場合、r + c×Rでインデックスを決定する", function()
            local columns = { a = { field = "files[].name", dir = "vertical" } }
            local lines = layout.expand("@#a##  #a##", columns, 80, 2)
            assert.same({
                "{files[0].name:4}  {files[2].name:4}",
                "{files[1].name:4}  {files[3].name:4}",
            }, lines)
        end)

        it("dir=horizontalの場合、r×C + cでインデックスを決定する", function()
            local columns = { a = { field = "files[].name", dir = "horizontal" } }
            local lines = layout.expand("@#a##  #a##", columns, 80, 2)
            assert.same({
                "{files[0].name:4}  {files[1].name:4}",
                "{files[2].name:4}  {files[3].name:4}",
            }, lines)
        end)

        it("dirを省略した場合、horizontalとして扱われる", function()
            local columns = { a = { field = "files[].name" } }
            local lines = layout.expand("@#a##  #a##", columns, 80, 2)
            assert.same({
                "{files[0].name:4}  {files[1].name:4}",
                "{files[2].name:4}  {files[3].name:4}",
            }, lines)
        end)

        it("配列グループ内で同名タグの出現回数が行によって異なるとエラーになる", function()
            local tmpl = " #a##\n@#a##  #a##"
            local columns = { a = { field = "files[].name", dir = "vertical" } }
            assert.has_error(function()
                layout.expand(tmpl, columns, 80, 3)
            end)
        end)
    end)

    describe("出力配列の構造", function()
        it("要素数が画面高さと一致する", function()
            local tmpl = " header\n@#id##\n footer"
            local columns = { id = { field = "files[].name" } }
            local lines = layout.expand(tmpl, columns, 80, 5)
            assert.equals(5, #lines)
        end)
    end)
end)
