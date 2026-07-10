package.path = package.path .. ";lua/?.lua"
local path = require("path")

describe("path.parent_dir", function()
    it("末尾のセグメントを除いた親ディレクトリを返す", function()
        assert.equals("/root", path.parent_dir("/root/sub"))
    end)

    it("ルート直下のディレクトリの親はルート'/'になる", function()
        assert.equals("/", path.parent_dir("/root"))
    end)

    it("ルート'/'自体の親もルート'/'になる", function()
        assert.equals("/", path.parent_dir("/"))
    end)
end)

describe("path.last_segment", function()
    it("パスの末尾のセグメントを返す", function()
        assert.equals("sub", path.last_segment("/root/sub"))
    end)

    it("ルート'/'自体には末尾のセグメントがないのでnilを返す", function()
        assert.is_nil(path.last_segment("/"))
    end)
end)

describe("path.join", function()
    it("ディレクトリとファイル名を'/'で連結する", function()
        assert.equals("/root/sub", path.join("/root", "sub"))
    end)

    it("ベースがルート'/'の場合は二重スラッシュにならない", function()
        assert.equals("/root", path.join("/", "root"))
    end)
end)

describe("path.extension", function()
    it("拡張子を返す", function()
        assert.equals("txt", path.extension("a.txt"))
    end)

    it("拡張子がない場合はnilを返す", function()
        assert.is_nil(path.extension("README"))
    end)

    it("ドットファイル（.gitignoreのような名前）は拡張子なし扱いになる", function()
        assert.is_nil(path.extension(".gitignore"))
    end)

    it("複数のドットを含む名前は最後の拡張子を返す", function()
        assert.equals("gz", path.extension("archive.tar.gz"))
    end)
end)

describe("path.strip_extension", function()
    it("拡張子を除いた名前を返す", function()
        assert.equals("a", path.strip_extension("a.txt"))
    end)

    it("拡張子がない場合は元の名前をそのまま返す", function()
        assert.equals("README", path.strip_extension("README"))
    end)

    it("ドットファイルは拡張子なし扱いなので元の名前をそのまま返す", function()
        assert.equals(".gitignore", path.strip_extension(".gitignore"))
    end)
end)
