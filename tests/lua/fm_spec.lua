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
    local fs = { calls = {}, exit_code = 0 }
    fs.cwd = function() return "/root" end
    fs.list = function(path)
        if path == "/root" then
            return {
                { name = "sub", is_dir = true, size = 0, modified = "2025-01-01 00:00:00", perm = "rwxr-xr-x" },
                { name = "a.txt", is_dir = false, size = 10, modified = "2025-01-01 00:00:00", perm = "rw-r--r--" },
                { name = "empty.txt", is_dir = false, size = 0, modified = "2025-01-01 00:00:00", perm = "rw-r--r--" },
            }
        elseif path == "/root/sub" then
            return {}
        elseif path == "/" then
            return {
                { name = "root", is_dir = true, size = 0, modified = "2025-01-01 00:00:00", perm = "rwxr-xr-x" },
            }
        end
        return nil, "not found"
    end
    fs.run = function(cmd)
        table.insert(fs.calls, cmd)
        return fs.exit_code
    end
    -- 既定では設定ファイルが存在しないものとして扱い、config.luaの既定値にフォールバックさせる
    fs.read_file = function() return nil, "not found" end
    return fs
end

-- toml.parseはRust側が提供する関数のため、busted実行環境には実体がない。
-- テストで使う簡単な[section]\nkey = "value"形式だけを解釈するモックに差し替える
local function make_toml()
    return {
        parse = function(text)
            local result = {}
            local section = result
            for line in text:gmatch("[^\n]+") do
                local sec = line:match("^%[(%a+)%]$")
                if sec then
                    result[sec] = result[sec] or {}
                    section = result[sec]
                else
                    local key, value = line:match('^(%S+)%s*=%s*"(.-)"$')
                    if key then
                        section[key] = value
                    end
                end
            end
            return result
        end,
    }
end

describe("fm", function()
    before_each(function()
        _G.fs = make_fs()
        _G.toml = make_toml()
        _G.screen = make_screen(80, 10)
        dofile("lua/fm.lua")
    end)

    after_each(function()
        _G.fs = nil
        _G.toml = nil
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

    it("初期状態ではカーソル行(1行目)のファイル名が反転表示のエスケープシーケンスで囲まれる", function()
        on_init()
        assert.is_not_nil(screen.writes[1]:find("\27[7m", 1, true))
        assert.is_not_nil(screen.writes[1]:find("\27[0m", 1, true))
    end)

    it("カーソルがない行には反転表示のエスケープシーケンスが含まれない", function()
        on_init()
        assert.is_nil(screen.writes[2]:find("\27[7m", 1, true))
    end)

    it("jキーでカーソルが次の行に移動する", function()
        on_init()
        on_key("j")
        assert.is_not_nil(screen.writes[2]:find("\27[7m", 1, true))
    end)

    it("先頭行でkキーを押してもカーソルは1行目のまま", function()
        on_init()
        on_key("k")
        assert.is_not_nil(screen.writes[1]:find("\27[7m", 1, true))
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
        assert.is_not_nil(screen.writes[2]:find("\27[7m", 1, true))
    end)

    it("ルート直下のディレクトリへ移動してもパスが二重スラッシュにならない", function()
        _G.fs.cwd = function() return "/" end
        dofile("lua/fm.lua")
        on_init()
        on_key("j") -- カーソルを"root"に合わせる
        on_key("enter")
        assert.equals("fm  /root", screen.writes[0])
    end)

    it("トップレベルのディレクトリからbackspaceでルート'/'に移動できる", function()
        on_init()
        on_key("backspace") -- "/root" -> "/"
        assert.equals("fm  /", screen.writes[0])
    end)

    it("backspaceキーで親ディレクトリに移動する", function()
        on_init()
        on_key("j") -- カーソルをディレクトリ"sub"に合わせる
        on_key("enter") -- "sub"に入る
        on_key("backspace") -- 親("/root")に戻る
        assert.equals("fm  /root", screen.writes[0])
    end)

    it("backspaceキーで親に戻ったとき、元いた子ディレクトリの位置にカーソルが合う", function()
        on_init()
        on_key("j") -- カーソルをディレクトリ"sub"に合わせる
        on_key("enter") -- "sub"に入る
        on_key("backspace") -- 親("/root")に戻る
        assert.is_not_nil(screen.writes[2]:find("\27[7m", 1, true))
    end)

    it("grepの終了コードが0のファイルはlessで開く", function()
        _G.fs.exit_code = 0
        on_init()
        on_key("j") -- カーソルを"sub"に合わせる
        on_key("j") -- カーソルを"a.txt"に合わせる
        on_key("enter")
        assert.is_not_nil(fs.calls[#fs.calls]:find("less", 1, true))
    end)

    it("grepの終了コードが0以外のファイルはxxd経由でlessに表示する", function()
        _G.fs.exit_code = 1
        on_init()
        on_key("j") -- カーソルを"sub"に合わせる
        on_key("j") -- カーソルを"a.txt"に合わせる
        on_key("enter")
        assert.is_not_nil(fs.calls[#fs.calls]:find("xxd", 1, true))
    end)

    it("0バイトのファイルはgrepを実行せずlessで開く", function()
        on_init()
        on_key("j") -- カーソルを"sub"に合わせる
        on_key("j") -- カーソルを"a.txt"に合わせる
        on_key("j") -- カーソルを"empty.txt"に合わせる
        on_key("enter")
        assert.equals(1, #fs.calls)
    end)

    it("ファイル名に含まれるシングルクォートを安全にエスケープする", function()
        _G.fs.list = function()
            return { { name = "it's.txt", is_dir = false, size = 5, modified = "", perm = "rw-r--r--" } }
        end
        on_init()
        on_key("j") -- カーソルを"it's.txt"に合わせる
        on_key("enter")
        assert.is_not_nil(fs.calls[#fs.calls]:find("it'\\''s.txt'", 1, true))
    end)

    it("拡張子に対応するコマンドが定義されている場合はそちらを実行する", function()
        _G.fs.read_file = function() return '[associations]\ntxt = "myviewer $P/$C"' end
        dofile("lua/fm.lua")
        on_init()
        on_key("j") -- カーソルを"sub"に合わせる
        on_key("j") -- カーソルを"a.txt"に合わせる
        on_key("enter")
        assert.equals("myviewer '/root'/'a.txt'", fs.calls[#fs.calls])
    end)

    it("$Xは拡張子を除いたファイル名に展開される", function()
        _G.fs.read_file = function() return '[associations]\ntxt = "viewer $X"' end
        dofile("lua/fm.lua")
        on_init()
        on_key("j") -- カーソルを"sub"に合わせる
        on_key("j") -- カーソルを"a.txt"に合わせる
        on_key("enter")
        assert.equals("viewer 'a'", fs.calls[#fs.calls])
    end)

    it("拡張子に対応するコマンドがない場合はデフォルト動作(less/xxd)にフォールバックする", function()
        _G.fs.read_file = function() return '[associations]\nmd = "glow $C"' end
        dofile("lua/fm.lua")
        on_init()
        on_key("j") -- カーソルを"sub"に合わせる
        on_key("j") -- カーソルを"a.txt"に合わせる
        on_key("enter")
        assert.is_not_nil(fs.calls[#fs.calls]:find("less", 1, true))
    end)

    it("ドットファイル（拡張子なし）は拡張子コマンドの対象にならない", function()
        _G.fs.read_file = function() return '[associations]\ngitignore = "should-not-run $C"' end
        _G.fs.list = function()
            return { { name = ".gitignore", is_dir = false, size = 5, modified = "", perm = "rw-r--r--" } }
        end
        dofile("lua/fm.lua")
        on_init()
        on_key("j") -- カーソルを".gitignore"に合わせる
        on_key("enter")
        assert.is_nil(fs.calls[#fs.calls]:find("should-not-run", 1, true))
    end)

    it("隠しファイルは初期状態で表示される", function()
        _G.fs.list = function()
            return { { name = ".gitignore", is_dir = false, size = 5, modified = "", perm = "rw-r--r--" } }
        end
        on_init()
        assert.is_not_nil(screen.writes[2]:find(".gitignore", 1, true))
    end)

    it("'.'キーを押すと隠しファイルが表示されなくなる", function()
        _G.fs.list = function()
            return {
                { name = ".gitignore", is_dir = false, size = 5, modified = "", perm = "rw-r--r--" },
                { name = "a.txt", is_dir = false, size = 5, modified = "", perm = "rw-r--r--" },
            }
        end
        on_init()
        on_key(".")
        assert.is_nil(screen.writes[2]:find(".gitignore", 1, true))
    end)

    it("'.'キーを2回押すと隠しファイルの表示が元に戻る", function()
        _G.fs.list = function()
            return { { name = ".gitignore", is_dir = false, size = 5, modified = "", perm = "rw-r--r--" } }
        end
        on_init()
        on_key(".")
        on_key(".")
        assert.is_not_nil(screen.writes[2]:find(".gitignore", 1, true))
    end)

    it("'.'キーを押しても'..'は表示され続ける", function()
        on_init()
        on_key(".")
        assert.is_not_nil(screen.writes[1]:find("../", 1, true))
    end)

    it("隠しファイルにカーソルがある状態で非表示にすると、カーソルが範囲内に補正される", function()
        _G.fs.list = function()
            return { { name = ".gitignore", is_dir = false, size = 5, modified = "", perm = "rw-r--r--" } }
        end
        on_init()
        on_key("j") -- カーソルを".gitignore"に合わせる
        on_key(".") -- 隠しファイルを非表示にする(".."だけが残る)
        assert.is_not_nil(screen.writes[1]:find("\27[7m", 1, true))
    end)

    it("ファイル名が列幅を超える場合、拡張子を残して省略記号で切り詰める", function()
        _G.fs.list = function()
            return {
                { name = string.rep("a", 50) .. ".pdf", is_dir = false, size = 1, modified = "", perm = "rw-r--r--" },
            }
        end
        on_init()
        assert.is_not_nil(screen.writes[2]:find("….pdf", 1, true))
    end)

    it("ファイルサイズはK/M/G/T単位の人間可読な形式で表示される", function()
        _G.fs.list = function()
            return {
                { name = "big.mkv", is_dir = false, size = 592919787, modified = "", perm = "rw-r--r--" },
            }
        end
        on_init()
        assert.is_not_nil(screen.writes[2]:find("565.5M", 1, true))
    end)

    it("1024バイト未満のファイルサイズは単位を付けずバイト数のまま表示される", function()
        _G.fs.list = function()
            return {
                { name = "small.txt", is_dir = false, size = 10, modified = "", perm = "rw-r--r--" },
            }
        end
        on_init()
        assert.is_not_nil(screen.writes[2]:find("10", 1, true))
    end)

    it("ディレクトリ名が列幅を超える場合も切り詰め、末尾の'/'は保持する", function()
        _G.fs.list = function()
            return {
                { name = string.rep("d", 50), is_dir = true, size = 0, modified = "", perm = "rwxr-xr-x" },
            }
        end
        on_init()
        assert.is_not_nil(screen.writes[2]:find("…/", 1, true))
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
