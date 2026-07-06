std = "lua54"

-- Rust側 (screen.rs, filesystem.rs, toml_bridge.rs) が lua.globals() に登録するインタフェース
read_globals = { "fs", "screen", "toml" }

-- Rust側 (lua_bridge.rs) が呼び出すコールバック関数
globals = { "on_init", "on_key" }

-- テストではos.getenvをモックに差し替えるため、osへの書き込みを許可する
files["tests/lua"] = {
    globals = { "os" },
}
