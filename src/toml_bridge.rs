use mlua::prelude::*;

pub fn register(lua: &Lua) -> LuaResult<()> {
    let toml_table = lua.create_table()?;

    // toml.parse(text) -> table | nil, error_message
    toml_table.set(
        "parse",
        lua.create_function(|lua, text: String| {
            match text.parse::<toml::Value>() {
                Ok(value) => Ok((to_lua_value(lua, &value)?, LuaValue::Nil)),
                Err(e) => Ok((LuaValue::Nil, LuaValue::String(lua.create_string(e.to_string())?))),
            }
        })?,
    )?;

    lua.globals().set("toml", toml_table)?;
    Ok(())
}

fn to_lua_value(lua: &Lua, value: &toml::Value) -> LuaResult<LuaValue> {
    match value {
        toml::Value::String(s) => Ok(LuaValue::String(lua.create_string(s)?)),
        toml::Value::Integer(i) => Ok(LuaValue::Integer(*i)),
        toml::Value::Float(f) => Ok(LuaValue::Number(*f)),
        toml::Value::Boolean(b) => Ok(LuaValue::Boolean(*b)),
        toml::Value::Datetime(dt) => Ok(LuaValue::String(lua.create_string(dt.to_string())?)),
        toml::Value::Array(arr) => {
            let table = lua.create_table()?;
            for (i, item) in arr.iter().enumerate() {
                table.set(i + 1, to_lua_value(lua, item)?)?;
            }
            Ok(LuaValue::Table(table))
        }
        toml::Value::Table(map) => {
            let table = lua.create_table()?;
            for (k, v) in map {
                table.set(k.as_str(), to_lua_value(lua, v)?)?;
            }
            Ok(LuaValue::Table(table))
        }
    }
}
