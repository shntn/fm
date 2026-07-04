std = "lua54"

-- Rust側 (screen.rs, filesystem.rs) が lua.globals() に登録するインタフェース
read_globals = { "fs", "screen" }

-- Rust側 (lua_bridge.rs) が呼び出すコールバック関数
globals = { "on_init", "on_key" }
