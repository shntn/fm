use mlua::prelude::*;
use std::path::Path;
use crate::screen;
use crate::filesystem;

pub struct LuaBridge {
    lua: Lua,
}

impl LuaBridge {
    pub fn new() -> LuaResult<Self> {
        let lua = Lua::new();
        screen::register(&lua)?;
        filesystem::register(&lua)?;
        Ok(LuaBridge { lua })
    }

    pub fn load_script(&self, path: &str) -> LuaResult<()> {
        if !Path::new(path).exists() {
            return Err(LuaError::RuntimeError(format!(
                "{} が見つかりません",
                path
            )));
        }
        let code = std::fs::read_to_string(path).map_err(|e| {
            LuaError::RuntimeError(format!("{}の読み込み失敗: {}", path, e))
        })?;

        let dir = Path::new(path).parent().and_then(|p| p.to_str()).unwrap_or(".");
        let package: LuaTable = self.lua.globals().get("package")?;
        let existing: String = package.get("path")?;
        package.set("path", format!("{}/?.lua;{}", dir, existing))?;

        self.lua.load(&code).exec()
    }

    pub fn call_on_init(&self) -> LuaResult<()> {
        let f: LuaFunction = self.lua.globals().get("on_init")?;
        f.call(())
    }

    pub fn call_on_key(&self, key: &str) -> LuaResult<bool> {
        let f: LuaFunction = self.lua.globals().get("on_key")?;
        let result: LuaValue = f.call(key)?;
        match result {
            LuaValue::Boolean(false) => Ok(false),
            _ => Ok(true),
        }
    }
}