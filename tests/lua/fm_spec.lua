package.path = package.path .. ";lua/?.lua"

local function make_screen(width, height)
    local mock = { writes = {}, clear_count = 0 }
    mock.clear = function()
        mock.clear_count = mock.clear_count + 1
        mock.writes = {}
    end
    mock.get_size = function() return width, height end
    mock.write = function(_, y, text) mock.writes[y] = text end
    return mock
end

local function make_fs()
    return {
        cwd = function() return "/root" end,
        list = function(path)
            if path == "/root" then
                return {
                    { name = "sub", is_dir = true, size = 0, modified = "2025-01-01 00:00:00", perm = "rwxr-xr-x" },
                    { name = "a.txt", is_dir = false, size = 10, modified = "2025-01-01 00:00:00", perm = "rw-r--r--" },
                }
            elseif path == "/root/sub" then
                return {}
            end
            return nil, "not found"
        end,
    }
end

describe("fm", function()
    before_each(function()
        _G.fs = make_fs()
        _G.screen = make_screen(80, 10)
        dofile("lua/fm.lua")
    end)

    after_each(function()
        _G.fs = nil
        _G.screen = nil
        _G.on_init = nil
        _G.on_key = nil
    end)

    it("on_initを呼ぶと画面がクリアされる", function()
        on_init()
        assert.equals(1, screen.clear_count)
    end)

    it("on_initを呼ぶとヘッダーにカレントディレクトリが表示される", function()
        on_init()
        assert.equals("fm  /root", screen.writes[0])
    end)

    it("初期状態ではカーソルが1行目にある", function()
        on_init()
        assert.equals(">", screen.writes[1]:sub(1, 1))
    end)

    it("jキーでカーソルが次の行に移動する", function()
        on_init()
        on_key("j")
        assert.equals(">", screen.writes[2]:sub(1, 1))
    end)

    it("先頭行でkキーを押してもカーソルは1行目のまま", function()
        on_init()
        on_key("k")
        assert.equals(">", screen.writes[1]:sub(1, 1))
    end)

    it("qキーを押すとfalseが返る", function()
        on_init()
        assert.is_false(on_key("q"))
    end)

    it("escapeキーを押すとfalseが返る", function()
        on_init()
        assert.is_false(on_key("escape"))
    end)

    it("jキー以外を押すとtrueが返る", function()
        on_init()
        assert.is_true(on_key("j"))
    end)

    it("enterキーでディレクトリに入るとヘッダーのパスが変わる", function()
        on_init()
        on_key("j") -- カーソルをディレクトリ"sub"に合わせる
        on_key("enter")
        assert.equals("fm  /root/sub", screen.writes[0])
    end)

    it("親ディレクトリに戻ったとき、元いた子ディレクトリの位置にカーソルが合う", function()
        on_init()
        on_key("j") -- カーソルをディレクトリ"sub"に合わせる
        on_key("enter") -- "sub"に入る
        on_key("enter") -- ".."で親("/root")に戻る
        assert.equals(">", screen.writes[2]:sub(1, 1))
    end)

    it("ファイル数が画面に収まらない場合、ページ単位で表示を切り替える", function()
        _G.screen.get_size = function() return 80, 5 end -- list_h = 3
        _G.fs.list = function()
            return {
                { name = "a.txt", is_dir = false, size = 1, modified = "", perm = "rw-r--r--" },
                { name = "b.txt", is_dir = false, size = 1, modified = "", perm = "rw-r--r--" },
                { name = "c.txt", is_dir = false, size = 1, modified = "", perm = "rw-r--r--" },
                { name = "d.txt", is_dir = false, size = 1, modified = "", perm = "rw-r--r--" },
                { name = "e.txt", is_dir = false, size = 1, modified = "", perm = "rw-r--r--" },
            }
        end

        on_init()
        on_key("j") -- cursor: ".."(1) -> "a.txt"(2)
        on_key("j") -- cursor: "a.txt"(2) -> "b.txt"(3)
        on_key("j") -- cursor: "b.txt"(3) -> "c.txt"(4) 次ページへ切り替わる

        assert.is_not_nil(screen.writes[1]:find("c.txt", 1, true))
    end)

    it("fs.listがエラーを返す場合、エラーメッセージを描画する", function()
        _G.fs.cwd = function() return "/missing" end
        dofile("lua/fm.lua")
        on_init()
        assert.equals("error: not found", screen.writes[0])
    end)
end)
