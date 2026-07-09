use crossterm::cursor;
use crossterm::event::{self, Event, KeyCode, KeyEvent, KeyModifiers};
use crossterm::terminal::{Clear, ClearType};
use crossterm::QueueableCommand;
use mlua::prelude::*;
use std::cell::RefCell;
use std::io::{stdout, Write};
use std::rc::Rc;

/// Lua側のterminal.request_line_input()で渡された、次に行入力を行うべき領域
#[derive(Clone)]
pub struct LineInputRequest {
    pub x: u16,
    pub y: u16,
    pub max_width: u16,
    pub prompt: String,
}

/// on_key呼び出し中にrequest_line_inputが呼ばれたかどうかを、メインループへ伝える共有状態
pub type PendingLineInput = Rc<RefCell<Option<LineInputRequest>>>;

/// terminal.request_line_input(x, y, max_width, prompt)をLuaに登録する。
/// 呼ばれてもその場では何もせず、リクエスト内容を記録して即座に戻る。
/// 実際の行入力はon_keyの呼び出しが完全に終わった後、メインループが行う
pub fn register(lua: &Lua, pending: PendingLineInput) -> LuaResult<()> {
    let terminal_table = lua.create_table()?;

    terminal_table.set(
        "request_line_input",
        lua.create_function(move |_, (x, y, max_width, prompt): (u16, u16, u16, String)| {
            *pending.borrow_mut() = Some(LineInputRequest { x, y, max_width, prompt });
            Ok(())
        })?,
    )?;

    lua.globals().set("terminal", terminal_table)?;
    Ok(())
}

/// (x, y)からprompt+入力中の文字列を描画する。max_widthを超える場合は末尾を優先して表示する
fn render(x: u16, y: u16, max_width: u16, prompt: &str, buffer: &str) {
    let full = format!("{}{}", prompt, buffer);
    let text: String = if full.chars().count() > max_width as usize {
        let skip = full.chars().count() - max_width as usize;
        full.chars().skip(skip).collect()
    } else {
        full
    };

    let mut out = stdout();
    let _ = out.queue(cursor::MoveTo(x, y));
    let _ = out.queue(Clear(ClearType::UntilNewLine));
    let _ = out.write_all(text.as_bytes());
    let _ = out.flush();
}

/// Enter/Escapeまでキー入力を監視し、行編集を行う。
/// 確定時は入力文字列を、キャンセル時(Ctrl+Cも含む)は"escape"を返す
pub fn read_line(x: u16, y: u16, max_width: u16, prompt: &str) -> String {
    let mut buffer = String::new();
    loop {
        render(x, y, max_width, prompt, &buffer);

        let ev = match event::read() {
            Ok(ev) => ev,
            Err(_) => return "escape".to_string(),
        };
        if let Event::Key(KeyEvent { code, modifiers, .. }) = ev {
            match code {
                KeyCode::Enter => return buffer,
                KeyCode::Esc => return "escape".to_string(),
                KeyCode::Char('c') if modifiers.contains(KeyModifiers::CONTROL) => {
                    return "escape".to_string();
                }
                KeyCode::Backspace => {
                    buffer.pop();
                }
                KeyCode::Char(c) => {
                    buffer.push(c);
                }
                _ => {}
            }
        }
    }
}
