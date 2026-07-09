use mlua::prelude::*;
use std::cell::RefCell;
use std::path::Path;
use std::rc::Rc;
use crate::screen;
use crate::filesystem;
use crate::toml_bridge;
use crate::line_input::{self, LineInputRequest, PendingLineInput};

pub struct LuaBridge {
    lua: Lua,
    pending_line_input: PendingLineInput,
}

impl LuaBridge {
    pub fn new() -> LuaResult<Self> {
        let lua = Lua::new();
        screen::register(&lua)?;
        filesystem::register(&lua)?;
        toml_bridge::register(&lua)?;
        let pending_line_input: PendingLineInput = Rc::new(RefCell::new(None));
        line_input::register(&lua, pending_line_input.clone())?;
        Ok(LuaBridge { lua, pending_line_input })
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

    /// on_key呼び出し中にterminal.request_line_inputが呼ばれていれば、そのリクエストを取り出す
    pub fn take_pending_line_input(&self) -> Option<LineInputRequest> {
        self.pending_line_input.borrow_mut().take()
    }
}
