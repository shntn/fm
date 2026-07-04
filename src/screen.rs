use crossterm::{cursor, execute, terminal, QueueableCommand};
use mlua::prelude::*;
use std::io::{stdout, Write};

pub fn register(lua: &Lua) -> LuaResult<()> {
    let screen = lua.create_table()?;

    // screen.clear()
    screen.set(
        "clear",
        lua.create_function(|_, ()| {
            let mut out = stdout();
            let _ = execute!(out, terminal::Clear(terminal::ClearType::All), cursor::MoveTo(0, 0));
            Ok(())
        })?,
    )?;

    // screen.write(x, y, text)
    screen.set(
        "write",
        lua.create_function(|_, (x, y, text): (u16, u16, String)| {
            let (w, h) = terminal::size().unwrap_or((80, 24));
            if x >= w || y >= h {
                return Ok(());
            }
            // 改行文字より前だけ取り出す
            let text = text.split('\n').next().unwrap_or("");
            let mut out = stdout();
            let _ = out.queue(cursor::MoveTo(x, y));
            let _ = out.write_all(text.as_bytes());
            let _ = out.flush();
            Ok(())
        })?,
    )?;

    // screen.get_size() -> width, height
    screen.set(
        "get_size",
        lua.create_function(|_, ()| {
            let (w, h) = terminal::size().unwrap_or((80, 24));
            Ok((w, h))
        })?,
    )?;

    lua.globals().set("screen", screen)?;
    Ok(())
}