use mlua::prelude::*;
use std::fs;
use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};

pub fn register(lua: &Lua) -> LuaResult<()> {
    let fst = lua.create_table()?;

    // fs.list(path) -> table | nil, error_message
    fst.set(
        "list",
        lua.create_function(|lua, path: String| {
            let rd = match fs::read_dir(&path) {
                Ok(rd) => rd,
                Err(e) => {
                    return Ok((LuaValue::Nil, LuaValue::String(lua.create_string(e.to_string())?)));
                }
            };

            let table = lua.create_table()?;
            let mut i = 1;
            for entry in rd.flatten() {
                let meta = match entry.metadata() {
                    Ok(m) => m,
                    Err(_) => continue,
                };

                let name = entry.file_name().to_string_lossy().into_owned();
                let is_dir = meta.is_dir();
                let size = meta.len();
                let modified = format_time(meta.modified().ok());
                let perm = format_perm(&meta);

                let row = lua.create_table()?;
                row.set("name", name)?;
                row.set("is_dir", is_dir)?;
                row.set("size", size)?;
                row.set("modified", modified)?;
                row.set("perm", perm)?;
                table.set(i, row)?;
                i += 1;
            }
            Ok((LuaValue::Table(table), LuaValue::Nil))
        })?,
    )?;

    // fs.run(command) -> exit_code
    fst.set(
        "run",
        lua.create_function(|_, command: String| {
            let status = Command::new("/bin/sh")
                .arg("-c")
                .arg(&command)
                .status()
                .map(|s| s.code().unwrap_or(-1))
                .unwrap_or(-1);
            Ok(status)
        })?,
    )?;

    // fs.cwd() -> path
    fst.set(
        "cwd",
        lua.create_function(|_, ()| {
            let path = std::env::current_dir()
                .map(|p| p.to_string_lossy().into_owned())
                .unwrap_or_else(|_| ".".to_string());
            Ok(path)
        })?,
    )?;

    lua.globals().set("fs", fst)?;
    Ok(())
}

fn format_time(t: Option<SystemTime>) -> String {
    let t = match t {
        Some(t) => t,
        None => return "----/--/-- --:--:--".to_string(),
    };
    let secs = t.duration_since(UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0);
    // 簡易的なUTC変換（chrono非使用）
    let s = secs % 60;
    let m = (secs / 60) % 60;
    let h = (secs / 3600) % 24;
    let days = secs / 86400;
    // 1970-01-01からの日数をグレゴリオ暦に変換
    let (year, month, day) = days_to_ymd(days);
    format!("{:04}-{:02}-{:02} {:02}:{:02}:{:02}", year, month, day, h, m, s)
}

fn days_to_ymd(days: u64) -> (u64, u64, u64) {
    // ユリウス日ベースの簡易変換
    let z = days + 719468;
    let era = z / 146097;
    let doe = z % 146097;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = if m <= 2 { y + 1 } else { y };
    (y, m, d)
}

fn format_perm(meta: &fs::Metadata) -> String {
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        let mode = meta.permissions().mode();
        let bits = [
            (0o400, 'r'), (0o200, 'w'), (0o100, 'x'),
            (0o040, 'r'), (0o020, 'w'), (0o010, 'x'),
            (0o004, 'r'), (0o002, 'w'), (0o001, 'x'),
        ];
        bits.iter()
            .map(|(bit, ch)| if mode & bit != 0 { *ch } else { '-' })
            .collect()
    }
    #[cfg(not(unix))]
    {
        if meta.permissions().readonly() {
            "r--r--r--".to_string()
        } else {
            "rw-rw-rw-".to_string()
        }
    }
}